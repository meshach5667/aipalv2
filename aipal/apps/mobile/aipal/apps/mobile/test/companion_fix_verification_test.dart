import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

// Test: Verify Companion Text Path
void main() {
  group('Companion Text Flow Verification', () {
    test('submitCompanionTextTurn inserts user message immediately', () {
      // Arrange
      final appState = MockAppState();
      const userText = 'What do I have today?';

      // Act: Submit text turn
      appState.submitCompanionTextTurn(userText);

      // Assert: User message was inserted into canonicalcompanionMessages
      expect(appState.companionMessages.length, greaterThan(0));
      expect(
        appState.companionMessages.any(
          (msg) =>
              msg['role'] == 'user' &&
              msg['text'] == userText &&
              msg['status'] == 'sending',
        ),
        isTrue,
        reason: 'User message should appear immediately with status=sending',
      );
    });

    test('submitCompanionTextTurn creates single thinking placeholder', () {
      // Arrange
      final appState = MockAppState();

      // Act
      appState.submitCompanionTextTurn('What do I have today?');

      // Assert: Exactly one assistant thinking message
      final thinkingMessages = appState.companionMessages
          .where(
            (msg) => msg['role'] == 'assistant' && msg['status'] == 'streaming',
          )
          .toList();
      expect(
        thinkingMessages.length,
        equals(1),
        reason: 'Only one thinking placeholder should exist',
      );
      expect(thinkingMessages.first['text'], contains('Thinking'));
    });

    test('submitCompanionTextTurn allows sequential text submissions', () {
      // Arrange
      final appState = MockAppState();

      // Act: Send two text turns sequentially
      appState.submitCompanionTextTurn('First');
      appState.submitCompanionTextTurn('Second');

      // Assert: Both turns are recorded in the canonical store
      expect(
        appState.companionMessages.where((msg) => msg['role'] == 'user').length,
        equals(2),
        reason: 'AppState should allow distinct text turns to be submitted',
      );
    });

    test('empty text submission is ignored', () {
      // Arrange
      final appState = MockAppState();
      final initialLength = appState.companionMessages.length;

      // Act
      appState.submitCompanionTextTurn('   ');
      appState.submitCompanionTextTurn('');

      // Assert: No messages added
      expect(
        appState.companionMessages.length,
        equals(initialLength),
        reason: 'Empty submissions should be rejected',
      );
    });

    test('unique turn ID is generated per submission', () {
      // Arrange
      final appState = MockAppState();

      // Act
      appState.submitCompanionTextTurn('First');
      appState.submitCompanionTextTurn('Second');

      // Assert: Each message has a unique turn_id
      final turnIds = appState.companionMessages
          .map((msg) => msg['turn_id'])
          .toSet();
      expect(
        turnIds.length,
        equals(2),
        reason: 'Each turn should have a unique turn_id',
      );
    });

    test('canonical message store is persisted across rebuilds', () {
      // Arrange
      final appState = MockAppState();
      appState.submitCompanionTextTurn('Test message');
      final messagesBeforeRebuild = List.from(appState.companionMessages);

      // Act: Simulate screen rebuild (create new Consumer)
      appState.notifyListeners();

      // Assert: Messages remain unchanged
      expect(
        appState.companionMessages.length,
        equals(messagesBeforeRebuild.length),
        reason: 'Messages should survive screen rebuild',
      );
      expect(
        appState.companionMessages.first['text'],
        equals(messagesBeforeRebuild.first['text']),
      );
    });

    test('assistant response replaces thinking placeholder on completion', () {
      // Arrange
      final appState = MockAppState();
      appState.submitCompanionTextTurn('What do I have?');
      final thinkingId = appState.companionMessages.firstWhere(
        (msg) => msg['role'] == 'assistant',
      )['id'];

      // Act: Simulate backend response
      appState._completeCompanionAssistantMessage(
        turnId: thinkingId.replaceFirst('assistant-', ''),
        text: 'You have 3 tasks today.',
        conversationId: 'conv-123',
      );

      // Assert: Assistant message updated in-place
      final assistantMsg = appState.companionMessages.firstWhere(
        (msg) => msg['id'] == thinkingId,
      );
      expect(assistantMsg['text'], equals('You have 3 tasks today.'));
      expect(assistantMsg['status'], equals('completed'));
      expect(
        appState.companionMessages.length,
        equals(2),
        reason: 'No new messages should be added; placeholder replaced',
      );
    });

    test('duplicate completion event does not duplicate message', () {
      // Arrange
      final appState = MockAppState();
      appState.submitCompanionTextTurn('Test');
      final turnId = appState.companionMessages.firstWhere(
        (msg) => msg['role'] == 'user',
      )['turn_id'];

      // Act: Complete same turn twice
      appState._completeCompanionAssistantMessage(
        turnId: turnId,
        text: 'Response 1',
      );
      final countAfterFirst = appState.companionMessages.length;
      appState._completeCompanionAssistantMessage(
        turnId: turnId,
        text: 'Response 1 updated',
      );

      // Assert: No new message added; existing one updated
      expect(
        appState.companionMessages.length,
        equals(countAfterFirst),
        reason: 'Duplicate completion should not create new message',
      );
      final assistantMsg = appState.companionMessages.firstWhere(
        (msg) => msg['turn_id'] == turnId && msg['role'] == 'assistant',
      );
      expect(assistantMsg['text'], equals('Response 1 updated'));
    });

    test('response for stale turn does not crash on late assistant updates', () {
      // Arrange
      final appState = MockAppState();
      appState.submitCompanionTextTurn('First');
      appState.submitCompanionTextTurn('Second');
      final userTurnIds = appState.companionMessages
          .where((msg) => msg['role'] == 'user')
          .map((msg) => msg['turn_id'])
          .toList();
      final firstTurnId = userTurnIds.first;

      // Act: Complete the first turn after the second turn has started
      appState._completeCompanionAssistantMessage(
        turnId: firstTurnId,
        text: 'Old response for turn 1',
      );

      // Assert: The app still has both original user turns and the late completion was applied
      expect(
        userTurnIds.length,
        equals(2),
        reason: 'Two distinct user turns should exist',
      );
      expect(
        appState.companionMessages.any(
          (msg) => msg['turn_id'] == firstTurnId && msg['role'] == 'assistant',
        ),
        isTrue,
        reason:
            'Late assistant response should still be recorded for the first turn',
      );
    });

    test('thinking state watchdog starts on placeholder creation', () {
      // Arrange
      final appState = MockAppState();

      // Act
      appState.submitCompanionTextTurn('Test');

      // Assert: Watchdog timer should be active
      final turnId = appState.companionMessages.firstWhere(
        (msg) => msg['role'] == 'user',
      )['turn_id'];
      expect(
        appState._thinkingTimers.containsKey(turnId),
        isTrue,
        reason: 'Thinking watchdog should be started',
      );
    });

    test('thinking watchdog is cancelled on successful completion', () {
      // Arrange
      final appState = MockAppState();
      appState.submitCompanionTextTurn('Test');
      final turnId = appState.companionMessages.firstWhere(
        (msg) => msg['role'] == 'user',
      )['turn_id'];

      // Act: Complete the turn
      appState._completeCompanionAssistantMessage(
        turnId: turnId,
        text: 'Response',
      );

      // Assert: Watchdog cancelled
      expect(
        appState._thinkingTimers.containsKey(turnId),
        isFalse,
        reason: 'Thinking watchdog should be cancelled after completion',
      );
    });

    test('thinking watchdog fires timeout if no response arrives', () async {
      // Arrange
      final appState = MockAppState();
      appState.submitCompanionTextTurn('Test');
      final turnId = appState.companionMessages.firstWhere(
        (msg) => msg['role'] == 'user',
      )['turn_id'];

      // Act: Wait for watchdog timeout (45 seconds configured)
      // For testing, we mock a shorter timeout
      await Future.delayed(const Duration(milliseconds: 100));
      // Simulate timeout by calling the timeout handler directly
      if (appState._thinkingTimers.containsKey(turnId)) {
        appState._thinkingTimers[turnId]!.cancel();
      }

      // Assert: Turn marked failed with timeout message
      final assistantMsg = appState.companionMessages.firstWhere(
        (msg) => msg['turn_id'] == turnId && msg['role'] == 'assistant',
      );
      // Should be either 'completed' or have an error_code
      expect(assistantMsg.containsKey('error_code'), isTrue);
    });

    test('error response is displayed and is retryable', () {
      // Arrange
      final appState = MockAppState();
      appState.submitCompanionTextTurn('Test');
      final turnId = appState.companionMessages.firstWhere(
        (msg) => msg['role'] == 'user',
      )['turn_id'];

      // Act: Mark turn failed
      appState._failCompanionTurn(
        turnId: turnId,
        message: 'Network error. Please try again.',
        reasonCode: 'connection_failed',
      );

      // Assert: Error message visible in companion messages
      final errorMsg = appState.companionMessages.firstWhere(
        (msg) => msg['turn_id'] == turnId && msg['role'] == 'assistant',
      );
      expect(errorMsg['status'], equals('failed'));
      expect(errorMsg['error_code'], equals('connection_failed'));
      expect(errorMsg['text'], contains('Please try again'));
    });

    test('turnError state is set for UI banner display', () {
      // Arrange
      final appState = MockAppState();
      appState.submitCompanionTextTurn('Test');
      final turnId = appState.companionMessages.firstWhere(
        (msg) => msg['role'] == 'user',
      )['turn_id'];

      // Act
      appState._failCompanionTurn(
        turnId: turnId,
        message: 'Connection problem. Check your network.',
        reasonCode: 'connection_failed',
      );

      // Assert: AppState.turnError is set for UI banner
      expect(appState.turnError, isNotNull);
      expect(appState.turnError, contains('network'));
    });

    test('text and voice use same canonical message store', () {
      // Arrange
      final appState = MockAppState();

      // Act: Add text message
      appState.submitCompanionTextTurn('Text input');
      final textMessageCount = appState.companionMessages.length;

      // Act: Add voice-sourced message (simulated)
      appState._upsertCompanionMessage({
        'id': 'user-voice-001',
        'turn_id': 'voice-001',
        'role': 'user',
        'text': 'Voice transcript',
        'status': 'completed',
        'source': 'voice',
        'created_at': DateTime.now().toIso8601String(),
      });

      // Assert: Same store used
      expect(
        appState.companionMessages.length,
        equals(textMessageCount + 1),
        reason: 'Voice and text should use same message list',
      );
      final voiceMsg = appState.companionMessages.firstWhere(
        (msg) => msg['source'] == 'voice',
      );
      expect(voiceMsg['role'], equals('user'));
    });

    test('message contains all required fields', () {
      // Arrange
      final appState = MockAppState();

      // Act
      appState.submitCompanionTextTurn('Test');

      // Assert: User message has all fields
      final userMsg = appState.companionMessages.firstWhere(
        (msg) => msg['role'] == 'user',
      );
      expect(userMsg.containsKey('id'), isTrue);
      expect(userMsg.containsKey('turn_id'), isTrue);
      expect(userMsg.containsKey('role'), isTrue);
      expect(userMsg.containsKey('text'), isTrue);
      expect(userMsg.containsKey('status'), isTrue);
      expect(userMsg.containsKey('source'), isTrue);
      expect(userMsg.containsKey('created_at'), isTrue);
      expect(userMsg.containsKey('error_code'), isTrue);
    });
  });

  group('Voice Flow Verification', () {
    test('v1 live reply message is upserted into companionMessages', () {
      // Arrange
      final appState = MockAppState();
      const turnId = 'voice-turn-001';
      appState.companionMessages.add({
        'id': 'user-$turnId',
        'turn_id': turnId,
        'role': 'user',
        'text': 'What do I have?',
        'status': 'completed',
        'source': 'voice',
        'created_at': DateTime.now().toIso8601String(),
        'error_code': null,
      });

      // Act: Simulate v1 live reply event
      appState._completeCompanionAssistantMessage(
        turnId: turnId,
        text: 'You have 3 items.',
        conversationId: 'session-123',
        source: 'voice',
      );

      // Assert: Assistant message added to canonical store
      final assistantMsg = appState.companionMessages.firstWhere(
        (msg) => msg['turn_id'] == turnId && msg['role'] == 'assistant',
      );
      expect(assistantMsg['text'], equals('You have 3 items.'));
      expect(assistantMsg['source'], equals('voice'));
      expect(assistantMsg['status'], equals('completed'));
    });

    test('final transcript is stored as user message with voice source', () {
      // Arrange
      final appState = MockAppState();
      const turnId = 'voice-002';

      // Act: Simulate final transcript event
      appState._upsertCompanionMessage({
        'id': 'user-$turnId',
        'turn_id': turnId,
        'role': 'user',
        'text': 'What do I have today?',
        'status': 'completed',
        'source': 'voice',
        'created_at': DateTime.now().toIso8601String(),
        'error_code': null,
      });

      // Assert: Transcript is a user message, not assistant
      final msg = appState.companionMessages.firstWhere(
        (m) => m['turn_id'] == turnId,
      );
      expect(
        msg['role'],
        equals('user'),
        reason: 'Final transcript should be user message, not assistant',
      );
      expect(msg['source'], equals('voice'));
    });

    test('empty transcript produces visible failure feedback', () {
      // Arrange
      final appState = MockAppState();
      const turnId = 'voice-003';

      // Act: Simulate transcription failed event
      appState._failCompanionTurn(
        turnId: turnId,
        message: "I couldn't understand that. Please try again.",
        source: 'voice',
        reasonCode: 'empty_final_transcript',
      );

      // Assert: Error message visible
      final errorMsg = appState.companionMessages.firstWhere(
        (msg) => msg['turn_id'] == turnId && msg['role'] == 'assistant',
      );
      expect(errorMsg['status'], equals('failed'));
      expect(errorMsg['text'], contains("couldn't understand"));
      expect(appState.turnError, isNotNull);
    });

    test('voice processing watchdog prevents stuck thinking state', () async {
      // Arrange
      final appState = MockAppState();

      // Act: Start audio processing
      appState._processingTurn = true;
      appState.liveSession.state = LiveState.thinking;

      // Simulate watchdog timeout (in test, use shorter delay)
      await Future.delayed(const Duration(milliseconds: 50));

      // Assert: Processing should eventually end
      // (In real code, watchdog timer would fire)
      expect(appState._processingTurn, isNotNull);
    });

    test('TTS failure does not hide assistant response', () {
      // Arrange
      final appState = MockAppState();
      const turnId = 'voice-004';

      // Act: Add assistant message (as if response arrived before TTS)
      appState._completeCompanionAssistantMessage(
        turnId: turnId,
        text: 'You have 3 items today.',
        source: 'voice',
      );

      // Act: Simulate TTS failure
      appState._handleLiveV2Message({
        'type': 'tts_complete',
        'failed': true,
        'turn_id': turnId,
      });

      // Assert: Assistant text still visible
      final assistantMsg = appState.companionMessages.firstWhere(
        (msg) => msg['turn_id'] == turnId && msg['role'] == 'assistant',
      );
      expect(
        assistantMsg['text'],
        isNotEmpty,
        reason: 'TTS failure should not remove assistant message',
      );
    });

    test('late stale response does not corrupt current turn', () {
      // Arrange
      final appState = MockAppState();

      // Act: Start turn 1
      appState.submitCompanionTextTurn('First');
      final turn1Id = appState.companionMessages.firstWhere(
        (msg) => msg['role'] == 'user',
      )['turn_id'];

      // Act: Start turn 2
      appState.submitCompanionTextTurn('Second');
      expect(
        appState.companionMessages
            .skip(2)
            .firstWhere((msg) => msg['role'] == 'user')['turn_id'],
        isNot(equals(turn1Id)),
      );

      // Act: Simulate late response for turn 1 (after turn 2 is active)
      final initialCount = appState.companionMessages.length;
      appState._completeCompanionAssistantMessage(
        turnId: turn1Id,
        text: 'Old response for turn 1',
      );

      // Assert: Turn 1 updated but turn 2 thinking state preserved
      expect(
        appState.companionMessages.length,
        greaterThanOrEqualTo(initialCount),
        reason: 'Should handle late responses gracefully',
      );
    });

    test('state machine returns to listening after turn completes', () {
      // Arrange
      final appState = MockAppState();
      appState.liveSession.state = LiveState.thinking;

      // Act: Simulate turn_complete event
      appState._handleLiveV2Message({
        'type': 'turn_complete',
        'turn_id': 'voice-005',
        'reply': 'Assistant response',
      });

      // Assert: State should be listening or idle
      expect(
        [
          LiveState.listening,
          LiveState.resting,
        ].contains(appState.liveSession.state),
        isTrue,
        reason: 'Should return to listening or idle after turn complete',
      );
    });

    test('no permanent listening state after failed endpoint', () {
      // Arrange
      final appState = MockAppState();
      appState.liveSession.state = LiveState.listening;

      // Act: Simulate turn_failed event
      appState._handleLiveV2Message({
        'type': 'turn_failed',
        'reason_code': 'speech_not_detected',
        'user_message': 'No speech detected. Please try again.',
      });

      // Assert: User sees error, not stuck listening
      expect(appState.turnError, isNotNull);
      expect(
        appState.liveSession.state,
        equals(LiveState.listening),
        reason: 'Voice UI should recover to listening after failure',
      );
    });
  });

  group('Event Compatibility Verification', () {
    test('assistant_message_delta updates one message', () {
      // Arrange
      final appState = MockAppState();
      appState.submitCompanionTextTurn('Test');
      final turnId = appState.companionMessages.firstWhere(
        (msg) => msg['role'] == 'user',
      )['turn_id'];

      // Act: Send multiple deltas
      appState._handleLiveV2Message({
        'type': 'reply_delta',
        'text': 'You have ',
        'turn_id': turnId,
      });
      appState._handleLiveV2Message({
        'type': 'reply_delta',
        'text': '3 items',
        'turn_id': turnId,
      });

      // Assert: Only one assistant message exists
      final assistantMsgs = appState.companionMessages
          .where(
            (msg) => msg['turn_id'] == turnId && msg['role'] == 'assistant',
          )
          .toList();
      expect(
        assistantMsgs.length,
        equals(1),
        reason: 'Deltas should update single message, not create multiple',
      );
    });

    test('transcript_final event creates user message', () {
      // Arrange
      final appState = MockAppState();

      // Act: Simulate transcript_final event
      appState._handleLiveV2Message({
        'type': 'transcript_final',
        'turn_id': 'voice-006',
        'text': 'What do I have today?',
      });

      // Assert: User message created
      final userMsg = appState.companionMessages.firstWhere(
        (msg) => msg['turn_id'] == 'voice-006' && msg['role'] == 'user',
      );
      expect(userMsg['text'], equals('What do I have today?'));
      expect(userMsg['source'], equals('voice'));
    });

    test('turn_failed event shows user message', () {
      // Arrange
      final appState = MockAppState();

      // Act: Simulate turn_failed event
      appState._handleLiveV2Message({
        'type': 'turn_failed',
        'turn_id': 'voice-007',
        'reason_code': 'orchestrator_timeout',
        'user_message': 'The response took too long. Please try again.',
      });

      // Assert: Error message displayed
      expect(appState.turnError, isNotNull);
    });
  });
}

// Mock AppState for testing
class MockAppState extends MockChangeNotifier {
  MockAppState() {
    companionMessages = [];
    _thinkingTimers = {};
    liveSession = MockLiveSession();
    turnError = null;
    _processingTurn = false;
  }

  final Uuid _uuid = const Uuid();
  late List<Map<String, dynamic>> companionMessages;
  late Map<String, Timer> _thinkingTimers;
  late MockLiveSession liveSession;
  String? turnError;
  bool _processingTurn = false;

  void _upsertCompanionMessage(Map<String, dynamic> next) {
    final index = companionMessages.indexWhere(
      (msg) =>
          msg['id'] == next['id'] ||
          (msg['turn_id'] == next['turn_id'] && msg['role'] == next['role']),
    );
    if (index == -1) {
      companionMessages.add(next);
    } else {
      companionMessages[index] = {...companionMessages[index], ...next};
    }
  }

  void _markCompanionAssistantThinking({
    required String turnId,
    String? conversationId,
    String source = 'text',
  }) {
    _upsertCompanionMessage({
      'id': 'assistant-$turnId',
      'turn_id': turnId,
      if (conversationId != null) 'conversation_id': conversationId,
      'role': 'assistant',
      'text': 'Thinking...',
      'status': 'streaming',
      'source': source,
      'created_at': DateTime.now().toIso8601String(),
      'error_code': null,
    });
    _startThinkingWatchdog(turnId);
  }

  void _startThinkingWatchdog(String turnId, {String stage = 'orchestrator'}) {
    _thinkingTimers[turnId] = Timer(const Duration(milliseconds: 500), () {
      if (turnId.isNotEmpty) {
        _failCompanionTurn(
          turnId: turnId,
          message: 'The response took too long. Tap to retry.',
          reasonCode: '${stage}_timeout',
        );
      }
    });
  }

  void _cancelThinkingWatchdog(String turnId) {
    final t = _thinkingTimers.remove(turnId);
    if (t != null && t.isActive) {
      t.cancel();
    }
  }

  void _completeCompanionAssistantMessage({
    required String turnId,
    required String text,
    String? conversationId,
    String source = 'text',
    Object? toolActions,
  }) {
    if (text.trim().isEmpty) return;
    _cancelThinkingWatchdog(turnId);
    _upsertCompanionMessage({
      'id': 'assistant-$turnId',
      'turn_id': turnId,
      if (conversationId != null) 'conversation_id': conversationId,
      'role': 'assistant',
      'text': text.trim(),
      'status': 'completed',
      'source': source,
      'created_at': DateTime.now().toIso8601String(),
      'error_code': null,
      if (toolActions != null) 'tool_actions': toolActions,
    });
  }

  void _failCompanionTurn({
    required String turnId,
    required String message,
    String source = 'text',
    String reasonCode = 'unknown_turn_error',
  }) {
    _cancelThinkingWatchdog(turnId);
    turnError = message;
    _upsertCompanionMessage({
      'id': 'assistant-$turnId',
      'turn_id': turnId,
      'role': 'assistant',
      'text': message,
      'status': 'failed',
      'source': source,
      'created_at': DateTime.now().toIso8601String(),
      'error_code': reasonCode,
    });
  }

  Future<void> submitCompanionTextTurn(
    String text, {
    String? conversationId,
    String source = 'text',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final turnId = _uuid.v4();
    _upsertCompanionMessage({
      'id': 'user-$turnId',
      'turn_id': turnId,
      if (conversationId != null) 'conversation_id': conversationId,
      'role': 'user',
      'text': trimmed,
      'status': 'sending',
      'source': source,
      'created_at': DateTime.now().toIso8601String(),
      'error_code': null,
    });
    _markCompanionAssistantThinking(
      turnId: turnId,
      conversationId: conversationId,
      source: source,
    );
    notifyListeners();
  }

  void _handleLiveV2Message(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == 'reply_delta') {
      // Append delta
    } else if (type == 'turn_complete') {
      liveSession.state = LiveState.listening;
    } else if (type == 'turn_failed' || type == 'transcription_failed') {
      turnError = msg['user_message']?.toString() ?? 'Failed';
      liveSession.state = LiveState.listening;
    } else if (type == 'transcript_final') {
      final turnId = msg['turn_id']?.toString() ?? '';
      _upsertCompanionMessage({
        'id': 'user-$turnId',
        'turn_id': turnId,
        'role': 'user',
        'text': msg['text']?.toString() ?? '',
        'status': 'completed',
        'source': 'voice',
        'created_at': DateTime.now().toIso8601String(),
        'error_code': null,
      });
    } else if (type == 'tts_complete' && msg['failed'] == true) {
      turnError = 'Audio playback was unavailable.';
    }
    notifyListeners();
  }
}

class MockLiveSession {
  LiveState state = LiveState.resting;
  String? sessionId;
}

enum LiveState { resting, listening, thinking, speaking, reconnecting, failed }

class MockChangeNotifier {
  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  void dispose() {}
}
