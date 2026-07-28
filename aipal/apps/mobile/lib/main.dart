import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'providers/app_state.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'services/wake_background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    FlutterForegroundTask.initCommunicationPort();
    await WakeBackgroundService.init();
  }
  final appState = AppState();
  try {
    await NotificationService.instance.init(
      onForegroundNudge: (taskId, minutes) =>
          appState.handleForegroundNudge(taskId, minutes),
    );
  } catch (_) {
    // Notifications optional — must not block app launch (APK sideload / web).
  }
  await appState.loadStoredAuth();
  runApp(AipalApp(appState: appState));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(appState.finishBootstrap());
  });
}

class AipalApp extends StatelessWidget {
  const AipalApp({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'AiPal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFFAF9F5),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF6F5081),
          secondary: Color(0xFF326667),
          surface: Colors.white,
          onSurface: Color(0xFF1B1C1A),
        ),
        textTheme: GoogleFonts.manropeTextTheme(ThemeData.light().textTheme),
      ),
      home: const SplashScreen(),
    );
    return ChangeNotifierProvider.value(
      value: appState,
      child: (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          ? WithForegroundTask(child: app)
          : app,
    );
  }
}
