import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

enum LiveState { resting, listening, thinking, speaking }

class LiveSession {
  WebSocketChannel? _channel;
  String? sessionId;

  LiveState state = LiveState.resting;

  Future<void> start(String token, void Function(Map<String, dynamic>) onMessage) async {
    await stop();
    _channel = WebSocketChannel.connect(Uri.parse(AppConfig.wsUrl(token)));
    state = LiveState.listening;
    _channel!.stream.listen((data) {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      final t = msg['type'] as String?;
      if (t == 'session_started') {
        sessionId = msg['session_id'] as String?;
      }
      if (t == 'state') {
        final s = msg['state'] as String?;
        if (s == 'thinking') state = LiveState.thinking;
        if (s == 'listening') state = LiveState.listening;
        if (s == 'speaking') state = LiveState.speaking;
      }
      onMessage(msg);
    });
  }

  void sendText(String text) {
    _channel?.sink.add(jsonEncode({'type': 'text_turn', 'text': text}));
    state = LiveState.thinking;
  }

  bool get isActive => _channel != null;

  Future<void> stop() async {
    try {
      _channel?.sink.add(jsonEncode({'type': 'end'}));
    } catch (_) {}
    await _channel?.sink.close();
    _channel = null;
    sessionId = null;
    state = LiveState.resting;
  }
}
