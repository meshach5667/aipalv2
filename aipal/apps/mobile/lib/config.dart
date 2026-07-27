class AppConfig {
  static const _rawApiBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://aipal.onrender.com/api/v2',
  );
  static final String apiBase = _normalizeApiBase(_rawApiBase);

  /// Live Voice v2: full-duplex WebSocket + PCM streaming (native).
  static const liveVoiceV2 = bool.fromEnvironment(
    'LIVE_VOICE_V2',
    defaultValue: true,
  );

  /// Production hides raw STT by default. Enable only for QA/debug builds.
  static const showLiveTranscript = bool.fromEnvironment(
    'SHOW_LIVE_TRANSCRIPT',
    defaultValue: false,
  );

  static String wsUrl(String token) {
    final base = apiBase
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return '$base/ws/session?token=$token';
  }

  static String _normalizeApiBase(String value) {
    var normalized = value.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    normalized = normalized.replaceFirst('/pi/v2', '/api/v2');
    if (!normalized.endsWith('/api/v2')) {
      normalized = '$normalized/api/v2';
    }
    return normalized;
  }
}
