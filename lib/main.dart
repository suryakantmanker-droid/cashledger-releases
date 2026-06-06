import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/services/hive_service.dart';
import 'firebase_options.dart';

/// Background FCM handler — must be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('FCM background message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── System UI ──────────────────────────────────────────────────────────────
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor:           Colors.transparent,
      statusBarIconBrightness:  Brightness.dark,
      statusBarBrightness:      Brightness.light,
    ),
  );

  // ── Firebase (Messaging only — Auth is now Supabase) ──────────────────────
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ── Supabase (Auth + Database) ─────────────────────────────────────────────
  await Supabase.initialize(
    url:     'https://lfvmkuqesvjodqrzzpaj.supabase.co',
    anonKey: 'sb_publishable_29VQyGKH2I7McmX_US3XoQ_QdClPK0E',
  );

  // ── Deep link handling (Supabase password-reset redirect) ──────────────────
  // When the user taps the reset link in their email, Android fires
  // com.cashledger.app://login-callback#access_token=...&type=recovery
  // AppLinks captures it; we hand the URI to Supabase so it creates a
  // passwordRecovery session, which the router then redirects to /update-password.
  final appLinks = AppLinks();

  // App opened cold via the deep link
  try {
    final initialUri = await appLinks.getInitialLink();
    if (initialUri != null) {
      await Supabase.instance.client.auth
          .getSessionFromUrl(initialUri, storeSession: true);
    }
  } catch (_) {}

  // App already running and a deep link arrives
  appLinks.uriLinkStream.listen((uri) async {
    try {
      await Supabase.instance.client.auth
          .getSessionFromUrl(uri, storeSession: true);
    } catch (_) {}
  });

  // ── Local Storage (Hive) ───────────────────────────────────────────────────
  await Hive.initFlutter();
  await HiveService.initialize();

  // ── Run App ────────────────────────────────────────────────────────────────
  runApp(const ProviderScope(child: App()));
}
