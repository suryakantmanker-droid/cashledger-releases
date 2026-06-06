import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { email, password, name, role, businessId } = await req.json()

    if (!email || !password) {
      return new Response(
        JSON.stringify({ error: 'email and password are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // service_role key bypasses RLS — safe to use server-side only
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // 1. Create the Supabase Auth account
    const { data, error } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    })

    if (error) {
      console.error('[create-auth-user] Auth error:', error.message)
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const uid = data.user.id
    console.log(`[create-auth-user] Auth user created: ${uid}`)

    // 2. Insert the users table row using service_role (bypasses RLS).
    //    The Flutter client cannot do this directly because the admin's JWT
    //    fails the "uid = fn_current_user_uid()" RLS INSERT policy when
    //    inserting a row for a different uid (the new employee).
    if (name || role || businessId) {
      const now = new Date().toISOString()
      const { error: userRowError } = await supabaseAdmin
        .from('users')
        .upsert({
          uid,
          name:        name        ?? email.split('@')[0],
          email,
          role:        role        ?? 'employee',
          business_id: businessId  ?? null,
          is_active:   true,
          created_at:  now,
        })

      if (userRowError) {
        // Auth user was created — log the error but don't block the response.
        // The client will handle any missing users row gracefully.
        console.error('[create-auth-user] users row error:', userRowError.message)
      } else {
        console.log(`[create-auth-user] users row created for uid: ${uid}`)
      }
    }

    return new Response(
      JSON.stringify({ uid }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (err) {
    console.error('[create-auth-user] Unexpected error:', err)
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
