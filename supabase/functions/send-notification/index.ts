import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const PROJECT_ID = 'cashledger-9e954'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Generates a short-lived OAuth2 access token from a Firebase service account JSON.
async function getAccessToken(): Promise<string> {
  // let saRaw = (Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '').trim()
  // // Strip surrounding single or double quotes added accidentally when saving the secret
  // if (
  //   (saRaw.startsWith("'") && saRaw.endsWith("'")) ||
  //   (saRaw.startsWith('"') && saRaw.endsWith('"'))
  // ) {
  //   saRaw = saRaw.slice(1, -1)
  // }
  // const sa = JSON.parse(saRaw)

  const encoded = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_BASE64')!

  const decoded = atob(encoded)

  const sa = JSON.parse(decoded)

  const now = Math.floor(Date.now() / 1000)
  
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }

  const b64url = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')

  const header = b64url({ alg: 'RS256', typ: 'JWT' })
  const payload = b64url(claim)
  const signingInput = `${header}.${payload}`

  const pem = (sa.private_key as string).replace(/-----[^-]+-----/g, '').replace(/\s/g, '')
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0))
  const key = await crypto.subtle.importKey(
    'pkcs8',
    der.buffer as ArrayBuffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput),
  )
  const encodedSig = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')

  const jwt = `${signingInput}.${encodedSig}`

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })
  const json = await res.json()
  return json.access_token as string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { userId, title, body, type, data } = await req.json()

    if (!userId || !title || !body) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get FCM token from Supabase users table
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: user, error } = await supabase
      .from('users')
      .select('fcm_token')
      .eq('uid', userId)
      .single()

    if (error || !user?.fcm_token) {
      console.log(`[send-notification] No FCM token for user ${userId}`)
      return new Response(JSON.stringify({ status: 'no_token' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const accessToken = await getAccessToken()

    const fcmMessage = {
      message: {
        token: user.fcm_token,
        notification: { title, body },
        data: {
          type: type ?? '',
          ...Object.fromEntries(
            Object.entries((data as Record<string, unknown>) ?? {}).map(([k, v]) => [k, String(v)]),
          ),
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: {
          priority: 'HIGH',
          notification: {
            channel_id: 'expense_tracker_channel',
            sound: 'default',
          },
        },
        apns: {
          payload: { aps: { sound: 'default' } },
        },
      },
    }

    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(fcmMessage),
      },
    )

    const result = await fcmRes.json()
    if (!fcmRes.ok) {
      console.error('[send-notification] FCM error:', JSON.stringify(result))
    }

    return new Response(JSON.stringify(result), {
      status: fcmRes.ok ? 200 : 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('[send-notification] Error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
