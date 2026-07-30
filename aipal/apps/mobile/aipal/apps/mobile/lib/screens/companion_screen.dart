import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../providers/app_state.dart';
import '../services/live_session.dart';
import '../services/web_title.dart';
import '../widgets/plan_draft_card.dart';

// Mobile-first Color Palette & Design Tokens
const Color _kBgColor = Color(0xFFFAFAFA);
const Color _kSurface = Color(0xFFF1F5F9);
const Color _kPrimaryText = Color(0xFF0F172A);
const Color _kSecondaryText = Color(0xFF64748B);
const Color _kBorderColor = Color(0xFFE2E8F0);
const Color _kUserBubbleColor = Color(0xFF2563EB);
const Color _kAssistantBubbleColor = Color(0xFFFFFFFF);

const LinearGradient _kBrandGradient = LinearGradient(
  colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class CompanionScreen extends StatefulWidget {
  const CompanionScreen({super.key});

  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends State<CompanionScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <Map<String, dynamic>>[];
  final _inlineSessionId = const Uuid().v4();
  String? _lastSyncedTranscript;
  String? _lastSyncedReply;
  int? _assistantMessageIndex;
  bool _textSendInFlight = false;
  String? _lastWebTitle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final state = context.read<AppState>();
        state.clearTurnError();
        state.syncWakeListener();
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _statusLabel(LiveState live) {
    switch (live) {
      case LiveState.resting:
        return 'Ready';
      case LiveState.listening:
        return 'Listening...';
      case LiveState.thinking:
        return 'Thinking...';
      case LiveState.speaking:
        return 'Speaking...';
      case LiveState.reconnecting:
        return 'Reconnecting';
      case LiveState.failed:
        return 'Offline';
    }
  }

  Future<void> _handleClose(AppState state) async {
    if (state.liveSession.state != LiveState.resting) {
      await state.toggleLive();
    }
    state.goToTab(1);
  }

  void _syncWebTitle(String title) {
    if (!kIsWeb || _lastWebTitle == title) return;
    _lastWebTitle = title;
    setWebPageTitle(title);
  }

  Future<void> _sendText(AppState state) async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    await _sendPrompt(state, text, clearComposer: true);
  }

  Future<void> _sendPrompt(
    AppState state,
    String text, {
    bool clearComposer = false,
  }) async {
    if (_textSendInFlight) return;
    _textSendInFlight = true;
    if (clearComposer) {
      _textController.clear();
    }
    _scrollToBottom();

    try {
      await state.submitCompanionTextTurn(
        text,
        conversationId: _inlineSessionId,
      );
      if (!mounted) return;
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.turnError ?? 'Something went wrong.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _textSendInFlight = false;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool _syncConversationMessages(AppState state, LiveState live) {
    final transcript = state.lastTranscript?.trim();
    final reply = state.lastReply?.trim();
    var changed = false;

    if (AppConfig.showLiveTranscript &&
        transcript != null &&
        transcript.isNotEmpty &&
        transcript != _lastSyncedTranscript &&
        live != LiveState.listening) {
      _messages.add({'role': 'user', 'text': transcript});
      _lastSyncedTranscript = transcript;
      _assistantMessageIndex = null;
      _lastSyncedReply = null;
      changed = true;
    }

    if (reply != null && reply.isNotEmpty && reply != _lastSyncedReply) {
      final index = _assistantMessageIndex;
      if (index != null &&
          index >= 0 &&
          index < _messages.length &&
          _messages[index]['role'] == 'assistant') {
        _messages[index] = {..._messages[index], 'text': reply};
      } else {
        _messages.add({'role': 'assistant', 'text': reply});
        _assistantMessageIndex = _messages.length - 1;
      }
      _lastSyncedReply = reply;
      changed = true;
    }

    if (changed) {
      _scrollToBottom();
    }
    return changed;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final live = state.liveSession.state;
        final isLive = live != LiveState.resting;
        final webTitle = isLive ? 'Audio Call · AiPal' : 'Companion · AiPal';
        _syncWebTitle(webTitle);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_syncConversationMessages(state, live)) {
            setState(() {});
          }
        });

        return Scaffold(
          backgroundColor: _kBgColor,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: _SimpleAppBar(
              status: _statusLabel(live),
              live: live,
              onClose: () => unawaited(_handleClose(state)),
            ),
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: _SimpleChatBody(
                  state: state,
                  live: live,
                  scrollController: _scrollController,
                  textController: _textController,
                  messages: state.companionMessages,
                  onSelectPrompt: (prompt) =>
                      unawaited(_sendPrompt(state, prompt)),
                  onMicTap: () => unawaited(state.toggleLive()),
                  onSendText: () => unawaited(_sendText(state)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SimpleAppBar extends StatelessWidget {
  const _SimpleAppBar({
    required this.status,
    required this.live,
    required this.onClose,
  });

  final String status;
  final LiveState live;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isLiveActive = live != LiveState.resting;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: _kBorderColor, width: 0.8),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.arrow_back_rounded, color: _kPrimaryText, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: _kSurface,
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(8),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: _kBrandGradient,
              ),
              child: const Center(
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'AiPal',
                  style: TextStyle(
                    color: _kPrimaryText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isLiveActive
                            ? const Color(0xFF10B981)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      status,
                      style: TextStyle(
                        color: isLiveActive
                            ? const Color(0xFF059669)
                            : _kSecondaryText,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleChatBody extends StatelessWidget {
  const _SimpleChatBody({
    required this.state,
    required this.live,
    required this.scrollController,
    required this.textController,
    required this.messages,
    required this.onSelectPrompt,
    required this.onMicTap,
    required this.onSendText,
  });

  final AppState state;
  final LiveState live;
  final ScrollController scrollController;
  final TextEditingController textController;
  final List<Map<String, dynamic>> messages;
  final ValueChanged<String> onSelectPrompt;
  final VoidCallback onMicTap;
  final VoidCallback onSendText;

  @override
  Widget build(BuildContext context) {
    final transcript = state.lastTranscript?.trim();
    final hasLiveTranscript =
        AppConfig.showLiveTranscript &&
        transcript != null &&
        transcript.isNotEmpty &&
        live == LiveState.listening;
    final showGreeting =
        messages.isEmpty && !hasLiveTranscript && live == LiveState.resting;

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            physics: const BouncingScrollPhysics(),
            children: [
              if (showGreeting) ...[
                const SizedBox(height: 40),
                const _MinimalGreeting(),
                const SizedBox(height: 28),
                _QuickSuggestions(onSelect: onSelectPrompt),
              ] else ...[
                for (final message in messages)
                  _MessageBubble(
                    text: message['text'] as String? ?? '',
                    isUser: message['role'] == 'user',
                  ),
                if (hasLiveTranscript)
                  _MessageBubble(text: transcript, isUser: true),
                if (live != LiveState.resting) ...[
                  const SizedBox(height: 12),
                  _VoiceStateBanner(live: live),
                ],
                if (state.turnError != null) ...[
                  const SizedBox(height: 12),
                  _ErrorPanel(errorText: state.turnError!),
                ],
                if (state.pendingPlanDraft != null) ...[
                  const SizedBox(height: 12),
                  PlanDraftCard(
                    draft: state.pendingPlanDraft!,
                    onConfirm: () => state.confirmPlanDraft(),
                    onDiscard: () => state.discardPlanDraft(),
                  ),
                ],
              ],
            ],
          ),
        ),
        _SimpleComposer(
          controller: textController,
          live: live,
          onMicTap: onMicTap,
          onSend: onSendText,
        ),
      ],
    );
  }
}

class _MinimalGreeting extends StatelessWidget {
  const _MinimalGreeting();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF2563EB).withValues(alpha: 0.08),
          ),
          child: const Center(
            child: Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF2563EB),
              size: 26,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'How can I help you today?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _kPrimaryText,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ask a question, start a task, or speak naturally.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _kSecondaryText,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _QuickSuggestions extends StatelessWidget {
  const _QuickSuggestions({required this.onSelect});

  final ValueChanged<String> onSelect;

  final List<Map<String, dynamic>> _prompts = const [
    {'icon': Icons.calendar_today_rounded, 'label': 'Plan my day'},
    {'icon': Icons.wb_sunny_rounded, 'label': 'Morning brief'},
    {'icon': Icons.chat_bubble_outline_rounded, 'label': 'Prepare for meeting'},
    {'icon': Icons.lightbulb_outline_rounded, 'label': 'Brainstorm ideas'},
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: _prompts.map((item) {
        final label = item['label'] as String;
        final icon = item['icon'] as IconData;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelect(label),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kBorderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: const Color(0xFF2563EB)),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: _kPrimaryText,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.text, required this.isUser});

  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = screenWidth < 520 ? screenWidth * 0.78 : 420.0;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: isUser ? _kUserBubbleColor : _kAssistantBubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 18),
            ),
            border: isUser ? null : Border.all(color: _kBorderColor),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: isUser ? Colors.white : _kPrimaryText,
              fontSize: 14.5,
              height: 1.4,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _SimpleComposer extends StatelessWidget {
  const _SimpleComposer({
    required this.controller,
    required this.live,
    required this.onMicTap,
    required this.onSend,
  });

  final TextEditingController controller;
  final LiveState live;
  final VoidCallback onMicTap;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final isLiveActive = live != LiveState.resting;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: _kBorderColor, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 46),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _kBorderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      style: const TextStyle(
                        color: _kPrimaryText,
                        fontSize: 14.5,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                        isCollapsed: true,
                        hintStyle: TextStyle(
                          color: _kSecondaryText,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty;
                      if (!hasText) return const SizedBox.shrink();

                      return Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: onSend,
                          customBorder: const CircleBorder(),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: _kBrandGradient,
                            ),
                            child: const Icon(
                              Icons.arrow_upward_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onMicTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isLiveActive ? _kBrandGradient : null,
                  color: isLiveActive ? null : _kSurface,
                  border: isLiveActive ? null : Border.all(color: _kBorderColor),
                ),
                child: Icon(
                  isLiveActive ? Icons.stop_rounded : Icons.mic_rounded,
                  color: isLiveActive ? Colors.white : _kPrimaryText,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceStateBanner extends StatelessWidget {
  const _VoiceStateBanner({required this.live});

  final LiveState live;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            live == LiveState.thinking ? 'AiPal is thinking...' : 'Listening...',
            style: const TextStyle(
              color: Color(0xFF1E3A8A),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.errorText});

  final String errorText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorText,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}