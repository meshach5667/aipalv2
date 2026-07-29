import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/live_session.dart';
import '../services/web_title.dart';
import '../widgets/plan_draft_card.dart';

// --- Palette Setup ---
const Color _kBackground = Color(0xFFF9F9F9);
const Color _kSurface = Color(0xFFFFFFFF);
const Color _kSurfaceContainerLow = Color(0xFFF3F3F3);
const Color _kSurfaceContainerHigh = Color(0xFFE8E8E8);
const Color _kPrimaryContainer = Color(0xFFFFD600);
const Color _kOnPrimaryContainer = Color(0xFF705D00);
const Color _kOnSurface = Color(0xFF1A1C1C);
const Color _kOnSurfaceVariant = Color(0xFF4D4632);
const Color _kSecondaryText = Color(0xFF5F5E5E);
const Color _kError = Color(0xFFBA1A1A);
const Color _kOnError = Color(0xFFFFFFFF);
const Color _kBorder = Color(0xFFE2E2E2);

enum _CompanionMode { initial, text, voice }

class _ChatMessage {
  final String text;
  final bool isUser;
  final bool isPending;

  _ChatMessage({
    required this.text,
    required this.isUser,
    this.isPending = false,
  });
}

class CompanionScreen extends StatefulWidget {
  const CompanionScreen({super.key});

  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends State<CompanionScreen> {
  String? _lastWebTitle;
  String? _homeToken;
  Future<Map<String, dynamic>>? _homeFuture;
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _sendingText = false;

  _CompanionMode _mode = _CompanionMode.initial;
  LiveState _previousLiveState = LiveState.resting;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppState>().syncWakeListener();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _syncWebTitle(String title) {
    if (!kIsWeb || _lastWebTitle == title) return;
    _lastWebTitle = title;
    setWebPageTitle(title);
  }

  Future<Map<String, dynamic>> _companionHomeFuture(AppState state) {
    if (_homeFuture == null || _homeToken != state.token) {
      _homeToken = state.token;
      _homeFuture = state.api.getCompanionHome();
    }
    return _homeFuture!;
  }

  Future<void> _handleSend(AppState state, String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty || _sendingText) return;

    setState(() {
      _mode = _CompanionMode.text;
      _sendingText = true;
      _messages.add(_ChatMessage(text: cleanText, isUser: true));
      _messages.add(
        _ChatMessage(text: 'Thinking...', isUser: false, isPending: true),
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    try {
      final res = await state.sendTextTurn(cleanText);
      final reply =
          ((res['assistantMessage'] as String?) ?? (res['reply'] as String?))
              ?.trim();
      if (!mounted) return;
      setState(() {
        if (_messages.isNotEmpty && _messages.last.isPending) {
          _messages.removeLast();
        }
        if (reply != null && reply.isNotEmpty) {
          _messages.add(_ChatMessage(text: reply, isUser: false));
        }
        _sendingText = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (_messages.isNotEmpty && _messages.last.isPending) {
          _messages.removeLast();
        }
        _messages.add(
          _ChatMessage(
            text:
                state.turnError ??
                'I could not send that. Check the connection and try again.',
            isUser: false,
          ),
        );
        _sendingText = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _handleMicTap(AppState state) {
    setState(() {
      _mode = _CompanionMode.voice;
    });
    unawaited(state.toggleLive());
  }

  Future<void> _confirmDraft(AppState state) async {
    try {
      await state.confirmPlanDraft();
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(text: 'Saved to Today.', isUser: false));
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved to Today')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state.turnError ??
                'Could not save it. Check the API and try again.',
          ),
        ),
      );
    }
  }

  Future<void> _discardDraft(AppState state) async {
    try {
      await state.discardPlanDraft();
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            text: 'Okay, I left that draft out. Tell me what to change.',
            isUser: false,
          ),
        );
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not discard the draft.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final liveState = state.liveSession.state;
        final isLive = liveState != LiveState.resting;

        // Sync mode accurately with state changes
        if (liveState != _previousLiveState) {
          if (isLive) {
            _mode = _CompanionMode.voice;
          } else if (_previousLiveState != LiveState.resting &&
              _messages.isNotEmpty) {
            _mode = _CompanionMode.text;
          }
          _previousLiveState = liveState;
        }

        final webTitle = isLive ? 'Audio Call · AiPal' : 'Companion · AiPal';
        final homeFuture = _companionHomeFuture(state);
        _syncWebTitle(webTitle);

        final voiceTranscript = state.lastTranscript?.trim();
        final aiReply = state.lastReply?.trim();
        final hasConversation =
            _messages.isNotEmpty ||
            (voiceTranscript != null && voiceTranscript.isNotEmpty) ||
            (aiReply != null && aiReply.isNotEmpty) ||
            state.pendingPlanDraft != null ||
            state.turnError != null;

        // Auto-scroll when streaming responses arrive
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        final showOrb =
            _mode == _CompanionMode.initial || _mode == _CompanionMode.voice;
        final showHomePrompt =
            _mode == _CompanionMode.initial && !hasConversation;

        return Scaffold(
          backgroundColor: _kBackground,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 600;

                return Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: CustomScrollView(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            slivers: [
                              SliverPadding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isCompact ? 16 : 24,
                                  vertical: 12,
                                ),
                                sliver: SliverList(
                                  delegate: SliverChildListDelegate([
                                    const SizedBox(height: 16),

                                    // Voice & Initial Mode View
                                    if (showOrb) ...[
                                      Center(
                                        child: _LuminousOrb(
                                          isLive: isLive,
                                          liveState: liveState,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                    ],

                                    if (showHomePrompt) ...[
                                      _CompanionLiveHome(
                                        future: homeFuture,
                                        onAction: (prompt) => unawaited(
                                          _handleSend(state, prompt),
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                    ],

                                    // Render Text Chat History
                                    for (final msg in _messages) ...[
                                      _LuminousBubble(
                                        text: msg.text,
                                        isUser: msg.isUser,
                                        isPending: msg.isPending,
                                      ),
                                      const SizedBox(height: 12),
                                    ],

                                    // Live Transcript Stream
                                    if (voiceTranscript != null &&
                                        voiceTranscript.isNotEmpty) ...[
                                      _LuminousBubble(
                                        text: voiceTranscript,
                                        isUser: true,
                                      ),
                                      const SizedBox(height: 12),
                                    ],

                                    // AI Response Stream
                                    if (aiReply != null &&
                                        aiReply.isNotEmpty &&
                                        (_messages.isEmpty ||
                                            _messages.last.text != aiReply) &&
                                        !showHomePrompt) ...[
                                      _LuminousBubble(
                                        text: aiReply,
                                        isUser: false,
                                      ),
                                      const SizedBox(height: 12),
                                    ],

                                    if (state.turnError != null) ...[
                                      _ErrorBadge(errorText: state.turnError!),
                                      const SizedBox(height: 12),
                                    ],

                                    if (liveState == LiveState.resting &&
                                        state.nextOpenTask != null) ...[
                                      const SizedBox(height: 8),
                                      _NextTaskChip(
                                        title:
                                            '${state.nextOpenTask!['title']}',
                                        onTap: () => state.goToTab(1),
                                      ),
                                    ],

                                    if (state.pendingPlanDraft != null) ...[
                                      const SizedBox(height: 12),
                                      PlanDraftCard(
                                        draft: state.pendingPlanDraft!,
                                        onConfirm: () =>
                                            unawaited(_confirmDraft(state)),
                                        onDiscard: () =>
                                            unawaited(_discardDraft(state)),
                                      ),
                                    ],

                                    const SizedBox(height: 24),
                                  ]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _LuminousBottomComposer(
                      live: liveState,
                      onMicTap: () => _handleMicTap(state),
                      isSending: _sendingText,
                      onTextSubmitted: (text) =>
                          unawaited(_handleSend(state, text)),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// --- Dynamic Animated Orb Component ---
class _LuminousOrb extends StatefulWidget {
  const _LuminousOrb({required this.isLive, required this.liveState});

  final bool isLive;
  final LiveState liveState;

  @override
  State<_LuminousOrb> createState() => _LuminousOrbState();
}

class _LuminousOrbState extends State<_LuminousOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(200, 200),
          painter: _OrbWavePainter(
            animationValue: _controller.value,
            liveState: widget.liveState,
          ),
        );
      },
    );
  }
}

class _OrbWavePainter extends CustomPainter {
  _OrbWavePainter({required this.animationValue, required this.liveState});

  final double animationValue;
  final LiveState liveState;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.35;

    final coreGradient = RadialGradient(
      colors: [
        _kPrimaryContainer.withValues(alpha: 0.9),
        _kPrimaryContainer.withValues(alpha: 0.4),
        _kPrimaryContainer.withValues(alpha: 0.0),
      ],
      stops: const [0.3, 0.7, 1.0],
    );

    final corePaint = Paint()
      ..shader = coreGradient.createShader(
        Rect.fromCircle(center: center, radius: baseRadius * 1.3),
      );

    canvas.drawCircle(center, baseRadius * 1.1, corePaint);

    if (liveState == LiveState.listening) {
      _drawListeningWaves(canvas, center, baseRadius);
    } else if (liveState == LiveState.speaking) {
      _drawSpeakingWaves(canvas, center, baseRadius);
    } else if (liveState == LiveState.thinking) {
      _drawThinkingPulse(canvas, center, baseRadius);
    } else {
      _drawRestingGlow(canvas, center, baseRadius);
    }
  }

  void _drawListeningWaves(Canvas canvas, Offset center, double baseRadius) {
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = _kOnPrimaryContainer;

    for (int i = 0; i < 3; i++) {
      final progress = (animationValue + (i * 0.33)) % 1.0;
      final radius = baseRadius + (progress * 45);
      final alpha = (1.0 - progress).clamp(0.0, 1.0) * 0.7;

      wavePaint.color = _kOnPrimaryContainer.withValues(alpha: alpha);
      canvas.drawCircle(center, radius, wavePaint);
    }
  }

  void _drawSpeakingWaves(Canvas canvas, Offset center, double baseRadius) {
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5;

    const int waveCount = 28;
    const angleStep = (math.pi * 2) / waveCount;

    for (int i = 0; i < waveCount; i++) {
      final angle = i * angleStep;
      final waveOffset = math.sin((animationValue * math.pi * 4) + (i * 0.5));
      final height = 8 + (waveOffset.abs() * 22);

      final startPoint = Offset(
        center.dx + math.cos(angle) * (baseRadius * 0.85),
        center.dy + math.sin(angle) * (baseRadius * 0.85),
      );
      final endPoint = Offset(
        center.dx + math.cos(angle) * (baseRadius * 0.85 + height),
        center.dy + math.sin(angle) * (baseRadius * 0.85 + height),
      );

      final alpha = 0.4 + (waveOffset.abs() * 0.6);
      wavePaint.color = _kOnPrimaryContainer.withValues(alpha: alpha);
      canvas.drawLine(startPoint, endPoint, wavePaint);
    }
  }

  void _drawThinkingPulse(Canvas canvas, Offset center, double baseRadius) {
    final pulseOffset = math.sin(animationValue * math.pi * 2) * 8;
    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = _kOnPrimaryContainer.withValues(alpha: 0.6);

    canvas.drawCircle(center, baseRadius + pulseOffset, pulsePaint);
  }

  void _drawRestingGlow(Canvas canvas, Offset center, double baseRadius) {
    final restPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = _kOnPrimaryContainer.withValues(alpha: 0.25);

    canvas.drawCircle(center, baseRadius + 4, restPaint);
  }

  @override
  bool shouldRepaint(covariant _OrbWavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.liveState != liveState;
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kSurfaceContainerLow,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: _kOnSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kOnSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LuminousBubble extends StatelessWidget {
  const _LuminousBubble({
    required this.text,
    required this.isUser,
    this.isPending = false,
  });

  final String text;
  final bool isUser;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: screenWidth * 0.8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? _kPrimaryContainer : _kSurface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 20),
          ),
          border: isUser ? null : Border.all(color: _kBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            height: 1.4,
            fontStyle: isPending ? FontStyle.italic : FontStyle.normal,
            fontWeight: isPending ? FontWeight.w600 : FontWeight.w400,
            color: isUser
                ? _kOnPrimaryContainer
                : isPending
                ? _kSecondaryText
                : _kOnSurface,
          ),
        ),
      ),
    );
  }
}

class _LuminousBottomComposer extends StatefulWidget {
  const _LuminousBottomComposer({
    required this.live,
    required this.onMicTap,
    required this.onTextSubmitted,
    required this.isSending,
  });

  final LiveState live;
  final VoidCallback onMicTap;
  final ValueChanged<String> onTextSubmitted;
  final bool isSending;

  @override
  State<_LuminousBottomComposer> createState() =>
      _LuminousBottomComposerState();
}

class _LuminousBottomComposerState extends State<_LuminousBottomComposer> {
  final TextEditingController _controller = TextEditingController();

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && !widget.isSending) {
      widget.onTextSubmitted(text);
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isListening =
        widget.live == LiveState.listening || widget.live == LiveState.speaking;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: _kBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Row(
            children: [
              GestureDetector(
                onTap: widget.onMicTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isListening ? _kError : _kPrimaryContainer,
                    boxShadow: [
                      BoxShadow(
                        color: (isListening ? _kError : _kPrimaryContainer)
                            .withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 1,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.mic,
                    size: 26,
                    color: isListening ? _kOnError : _kOnPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.only(left: 16, right: 6),
                  decoration: BoxDecoration(
                    color: _kSurface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: _kBorder, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          enabled: !widget.isSending,
                          onSubmitted: (_) => _submit(),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            color: _kOnSurface,
                          ),
                          decoration: InputDecoration(
                            hintText: widget.isSending
                                ? 'AiPal is thinking...'
                                : "What's on your mind?",
                            hintStyle: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              color: _kSecondaryText,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: widget.isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _kOnPrimaryContainer,
                                ),
                              )
                            : const Icon(
                                Icons.arrow_upward_rounded,
                                color: _kOnPrimaryContainer,
                                size: 22,
                              ),
                        onPressed: widget.isSending ? null : _submit,
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanionLiveHome extends StatelessWidget {
  const _CompanionLiveHome({required this.future, required this.onAction});

  final Future<Map<String, dynamic>> future;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final homeMessage = data?['message']?.toString().trim();
        final cards = ((data?['cards'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();

        final displayText = snapshot.hasError
            ? 'I could not load companion home. Check the backend connection and sign in again.'
            : (homeMessage == null || homeMessage.isEmpty)
            ? 'Loading your companion home...'
            : homeMessage;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  displayText,
                  key: ValueKey(displayText),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: _kOnSurface,
                  ),
                ),
              ),
            ),
            if (cards.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final card in cards.take(4))
                    _ActionPill(
                      icon: _iconForCard(card['icon']?.toString()),
                      label: card['title']?.toString() ?? '',
                      onTap: () {
                        final prompt = card['prompt']?.toString().trim();
                        if (prompt != null && prompt.isNotEmpty) {
                          onAction(prompt);
                        }
                      },
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  IconData _iconForCard(String? icon) {
    switch (icon) {
      case 'event_note':
        return Icons.event_note_outlined;
      case 'auto_stories':
        return Icons.auto_stories_outlined;
      case 'center_focus_strong':
        return Icons.center_focus_strong_outlined;
      case 'emoji_events':
        return Icons.emoji_events_outlined;
      case 'forum':
        return Icons.forum_outlined;
      case 'calendar_today':
        return Icons.calendar_today_outlined;
      default:
        return Icons.bolt_outlined;
    }
  }
}

class _NextTaskChip extends StatelessWidget {
  const _NextTaskChip({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _kSurfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.task_alt, color: _kOnPrimaryContainer, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Next: $title',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _kOnSurface,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: _kSecondaryText, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ErrorBadge extends StatelessWidget {
  const _ErrorBadge({required this.errorText});

  final String errorText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kError.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        errorText,
        style: const TextStyle(
          fontFamily: 'Inter',
          color: _kError,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
