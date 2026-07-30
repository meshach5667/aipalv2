---
name: aipal-mobile
description: >-
  AiPal Flutter app structure: AppState, api_client, dart-define API_BASE_URL,
  web base-href /app/, platform voice parity, key screens. Use when editing
  apps/mobile, Flutter widgets, or mobile API integration.
---

# AiPal Mobile

## Layout

```
apps/mobile/
├── lib/
│   ├── main.dart              # Theme: bg #0D1117, gold #E8A838, lavender #9B7EDE
│   ├── config.dart            # API_BASE_URL from dart-define
│   ├── providers/app_state.dart
│   ├── services/api_client.dart
│   ├── screens/
│   │   ├── splash_screen.dart
│   │   ├── onboarding_screen.dart
│   │   ├── home_shell.dart    # tabs: Companion / Today / Settings
│   │   ├── companion_screen.dart
│   │   ├── today_screen.dart
│   │   ├── text_chat_screen.dart
│   │   └── settings_screen.dart
│   └── widgets/
│       ├── aipal_logo.dart    # AiPalBrandRow, AiPalOrbMark, AiPalLogo
│       ├── orb_widget.dart
│       └── today/             # header, focus timer, priority lanes, routines
└── web/index.html             # favicon cache-bust, base href
```

## API config

```bash
flutter run --dart-define=API_BASE_URL=https://43.160.220.9.sslip.io/api/v2
flutter build web --release --base-href /app/ --dart-define=API_BASE_URL=...
```

Default in `lib/config.dart` points to production v2 API. WebSocket: `AppConfig.wsUrl(token)`.

## AppState patterns

- `token` in `FlutterSecureStorage`; `api` getter builds `ApiClient`
- `refreshTodayView()` → `GET /tasks/today-view`
- `toggleLive()` → mic permission, `LiveVoiceLoop`, WS session
- `sendTextTurn(text, sessionId:)` → returns `plan_draft` without creating tasks
- `suggestDayPlan(template:)` → `POST /tasks/suggest-day`

## Platform voice parity

| Platform | Live voice | Wake word ("Hi Pal") |
|----------|------------|----------------------|
| Android (native) | Full VAD loop | C2: `WakeBackgroundService` + `WakeForegroundHandler` (FGS microphone) when Settings opt-in — works across tabs and background |
| iOS | Full VAD loop | C1: `WakeWordService` on Companion tab only |
| Web | Text-first | Educational copy only — no always-on mic |

Wake word: shared `WakeWordEngine` + ONNX models in `assets/models/`. Android background path: `flutter_foreground_task` → `startWakeCallback` → `WakeForegroundHandler`. iOS foreground: `WakeWordService`. Settings via `WakeWordPrefs` (default off). On wake → `AppState.toggleLive()` (background: `handleBackgroundWake()` + `launchApp()`).

Do not break `LiveVoiceLoop` / `AppState.toggleLive` when editing Companion UI.

## Key screens

- **Companion** — orb hero, Live state chip, text mode entry, `AiPalBrandRow` header
- **Today** — priority lanes, routine chips, focus dial timer, suggest-day + plan draft card
- **Onboarding** — orb + wordmark, profile fields, notification schedule

## Verify

```bash
cd apps/mobile && flutter analyze lib/
```
