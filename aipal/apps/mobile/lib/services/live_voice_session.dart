import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import 'audio_playback_queue.dart';
import 'pcm_stream_recorder.dart';

typedef LiveVoiceMessageHandler = void Function(Map<String, dynamic> msg);

enum VoiceRuntimeState {
  idle,
  listening,
  userSpeaking,
  thinking,
  speaking,
  interrupted,
  cancelled,
  reconnecting,
}

/// Full-duplex Live Voice v2 session over WebSocket.
class LiveVoiceSession {
  LiveVoiceSession({
    required this.onMessage,
    this.onSpeechStart,
    this.isSpeakingForVad,
    this.silenceMs = 1800,
    this.maxSegmentMs = 14000,
    this.thresholdDb = -46.0,
    this.thresholdDbSpeaking = -44.0,
    this.bargeInThresholdDb = -34.0,
    this.immediateBargeInThresholdDb = -24.0,
  });

  final LiveVoiceMessageHandler onMessage;
  final void Function()? onSpeechStart;
  final bool Function()? isSpeakingForVad;
  final int silenceMs;
  final int maxSegmentMs;
  final double thresholdDb;
  final double thresholdDbSpeaking;
  final double bargeInThresholdDb;
  final double immediateBargeInThresholdDb;

  static const _tickMs = 80;
  static const _uuid = Uuid();

  WebSocketChannel? _channel;
  final PcmStreamRecorder _recorder = PcmStreamRecorder();
  AudioPlaybackQueue? _playback;
  Timer? _vadTicker;
  String? sessionId;
  String? _currentTurnId;
  String? _serverTurnId;
  bool _active = false;
  bool _inSegment = false;
  int _silenceAccumMs = 0;
  int _segmentStartedAt = 0;
  int _dynamicSilenceMs = 800;
  bool _speaking = false;
  int _bargeInAccumMs = 0;
  final Set<String> _playedChunks = <String>{};
  String? _activePlaybackTurnId;
  VoiceRuntimeState _runtimeState = VoiceRuntimeState.idle;

  bool get isActive => _active;
  bool get isSpeaking => _speaking;
  bool get isPlaybackActive => _playback?.isPlaying ?? false;

  void _setState(VoiceRuntimeState next, {String? turnId}) {
    if (_runtimeState == next) return;
    developer.log(
      'voice_state ${_runtimeState.name}->${next.name} turn=${turnId ?? _currentTurnId ?? _serverTurnId ?? "-"}',
      name: 'aipal.voice',
    );
    _runtimeState = next;
  }

  Future<bool> ensureMicPermission() async {
    return _recorder.ensureMicPermission();
  }

  Future<void> start(String token) async {
    await stop();
    _playback = AudioPlaybackQueue(
      onIdle: () {
        _speaking = false;
        _activePlaybackTurnId = null;
      },
    );
    _channel = WebSocketChannel.connect(Uri.parse(AppConfig.wsUrl(token)));
    _active = true;
    _dynamicSilenceMs = silenceMs;
    _setState(VoiceRuntimeState.reconnecting);

    _channel!.stream.listen(
      _onWsMessage,
      onDone: () {
        _active = false;
      },
    );

    _recorder.onPcm = _onPcmFrame;
    await _recorder.start();
    _setState(VoiceRuntimeState.listening);

    _vadTicker = Timer.periodic(const Duration(milliseconds: _tickMs), (_) {
      unawaited(_vadTick());
    });
  }

  Future<void> stop() async {
    _active = false;
    _vadTicker?.cancel();
    _vadTicker = null;
    try {
      _channel?.sink.add(jsonEncode({'type': 'end'}));
    } catch (_) {}
    await _channel?.sink.close();
    _channel = null;
    await _recorder.stop();
    await _playback?.dispose();
    _playback = null;
    sessionId = null;
    _currentTurnId = null;
    _inSegment = false;
    _speaking = false;
    _bargeInAccumMs = 0;
    _playedChunks.clear();
    _activePlaybackTurnId = null;
    _setState(VoiceRuntimeState.idle);
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    _recorder.onPcm = null;
  }

  void sendInterrupt() {
    final turnId = _serverTurnId;
    if (turnId != null) {
      _channel?.sink.add(jsonEncode({'type': 'interrupt', 'turn_id': turnId}));
    } else {
      _channel?.sink.add(jsonEncode({'type': 'interrupt', 'turn_id': 'all'}));
    }
    unawaited(_playback?.flush());
    _speaking = false;
    _currentTurnId = _uuid.v4();
    _serverTurnId = null;
    _bargeInAccumMs = 0;
    _playedChunks.clear();
    _activePlaybackTurnId = null;
    _setState(VoiceRuntimeState.interrupted, turnId: _currentTurnId);
  }

  void sendTextTurn(String text) {
    final turnId = _uuid.v4();
    _currentTurnId = turnId;
    _channel?.sink.add(
      jsonEncode({'type': 'text_turn', 'text': text, 'turn_id': turnId}),
    );
  }

  /// Play proactive greeting TTS without sending through the LLM turn pipeline.
  Future<void> playGreeting(Uint8List bytes, String mime) async {
    if (!_active || _playback == null || bytes.isEmpty) return;
    if (_playback!.isPlaying || _speaking) return;
    _activePlaybackTurnId = 'greeting';
    _speaking = true;
    _setState(VoiceRuntimeState.speaking, turnId: 'greeting');
    await _playback!.enqueue(bytes: bytes, mime: mime);
  }

  void _onPcmFrame(Uint8List bytes) {
    if (!_active || _channel == null) return;
    if (!_inSegment) return;
    final turnId = _currentTurnId ??= _uuid.v4();
    _channel!.sink.add(
      jsonEncode({
        'type': 'audio_frame',
        'turn_id': turnId,
        'data': base64Encode(bytes),
      }),
    );
  }

  void _onWsMessage(dynamic data) {
    final msg = jsonDecode(data as String) as Map<String, dynamic>;
    final type = msg['type'] as String?;
    if (type == 'session_started') {
      sessionId = msg['session_id'] as String?;
    }
    if (type == 'state') {
      final s = msg['state'] as String?;
      _speaking = s == 'speaking';
      if (s == 'thinking') _setState(VoiceRuntimeState.thinking);
      if (s == 'speaking') _setState(VoiceRuntimeState.speaking);
      if (s == 'listening') _setState(VoiceRuntimeState.listening);
    }
    if (type == 'tts_chunk') {
      _serverTurnId = msg['turn_id'] as String? ?? _serverTurnId;
      final turnId = msg['turn_id']?.toString() ?? '';
      final chunkIndex = msg['chunk_index'] is int
          ? msg['chunk_index'] as int
          : int.tryParse(msg['chunk_index']?.toString() ?? '');
      final chunkKey = chunkIndex == null ? null : '$turnId:$chunkIndex';
      if (chunkKey != null && !_playedChunks.add(chunkKey)) {
        onMessage(msg);
        return;
      }
      final b64 = msg['data'] as String?;
      final mime = msg['mime'] as String? ?? 'audio/mpeg';
      if (b64 != null && b64.isNotEmpty) {
        unawaited(
          _enqueueTurnAudio(
            turnId: turnId,
            bytes: base64Decode(b64),
            mime: mime,
            chunkIndex: chunkIndex,
          ),
        );
        _speaking = true;
        _setState(VoiceRuntimeState.speaking, turnId: turnId);
      }
    }
    if (type == 'tts_complete') {
      if (!(_playback?.isPlaying ?? false)) {
        _speaking = false;
      }
    }
    if (type == 'turn_cancelled') {
      unawaited(_playback?.flush());
      _speaking = false;
      _currentTurnId = null;
      _serverTurnId = null;
      _bargeInAccumMs = 0;
      _playedChunks.clear();
      _activePlaybackTurnId = null;
      _setState(VoiceRuntimeState.cancelled);
    }
    if (type == 'turn_complete') {
      if (!(_playback?.isPlaying ?? false)) {
        _speaking = false;
      }
      _currentTurnId = null;
      _serverTurnId = null;
      if (!(_playback?.isPlaying ?? false)) {
        _setState(VoiceRuntimeState.listening);
      }
    }
    onMessage(msg);
  }

  Future<void> _enqueueTurnAudio({
    required String turnId,
    required Uint8List bytes,
    required String mime,
    int? chunkIndex,
  }) async {
    final playback = _playback;
    if (playback == null) return;
    if (_activePlaybackTurnId != null && _activePlaybackTurnId != turnId) {
      await playback.flush();
      _playedChunks.clear();
    }
    _activePlaybackTurnId = turnId;
    await playback.enqueue(bytes: bytes, mime: mime, chunkIndex: chunkIndex);
  }

  Future<void> _vadTick() async {
    if (!_active) return;
    final amp = await _recorder.getAmplitude();
    final aiSpeaking =
        _speaking ||
        (_playback?.isPlaying ?? false) ||
        (isSpeakingForVad?.call() ?? false);
    final threshold = aiSpeaking ? thresholdDbSpeaking : thresholdDb;
    var speaking = amp.current > threshold;
    if (aiSpeaking) {
      if (amp.current > immediateBargeInThresholdDb) {
        developer.log(
          'barge_in_immediate db=${amp.current.toStringAsFixed(1)}',
          name: 'aipal.voice',
        );
        if (!_inSegment) {
          sendInterrupt();
          _startSpeechSegment();
        }
        return;
      }
      if (amp.current > bargeInThresholdDb) {
        _bargeInAccumMs += _tickMs;
      } else {
        _bargeInAccumMs = 0;
      }
      speaking = _bargeInAccumMs >= _tickMs;
    } else {
      _bargeInAccumMs = 0;
    }

    if (speaking) {
      _silenceAccumMs = 0;
      if (!_inSegment) {
        final wasSpeaking = _speaking || (_playback?.isPlaying ?? false);
        if (wasSpeaking) {
          sendInterrupt();
        }
        _startSpeechSegment();
      }
    } else if (_inSegment) {
      _silenceAccumMs += _tickMs;
    }

    if (_inSegment) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - _segmentStartedAt;
      if (_silenceAccumMs >= _dynamicSilenceMs || elapsed >= maxSegmentMs) {
        await _endSegment();
      }
    }
  }

  void _startSpeechSegment() {
    _inSegment = true;
    _silenceAccumMs = 0;
    _segmentStartedAt = DateTime.now().millisecondsSinceEpoch;
    _currentTurnId ??= _uuid.v4();
    _setState(VoiceRuntimeState.userSpeaking, turnId: _currentTurnId);
    _channel?.sink.add(
      jsonEncode({'type': 'speech_start', 'turn_id': _currentTurnId}),
    );
    onSpeechStart?.call();
  }

  Future<void> _endSegment() async {
    if (!_inSegment) return;
    _inSegment = false;
    _silenceAccumMs = 0;
    final turnId = _currentTurnId;
    if (turnId != null) {
      _channel?.sink.add(jsonEncode({'type': 'speech_end', 'turn_id': turnId}));
    }
    _setState(VoiceRuntimeState.thinking, turnId: turnId);
    _currentTurnId = null;
    final elapsed = DateTime.now().millisecondsSinceEpoch - _segmentStartedAt;
    _dynamicSilenceMs = max(1400, min(2800, (elapsed * 0.28).round()));
  }
}
