import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../providers/app_state.dart';
import '../services/live_session.dart';
import '../services/web_title.dart';
import '../widgets/plan_draft_card.dart';
import 'text_chat_screen.dart';

const _background = Color(0xFFF7F7F8);
const _surface = Color(0xFFFFFFFF);
const _assistantBubble = Color(0xFFF4F4F5);
const _primaryText = Color(0xFF111827);
const _secondaryText = Color(0xFF6B7280);
const _border = Color(0xFFE5E7EB);
const _accent = Color(0xFF10A37F);

class CompanionScreen extends StatefulWidget {
  const CompanionScreen({super.key});

  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends State<CompanionScreen> {
  String? _lastWebTitle;
  String? _homeToken;
  Future<Map<String, dynamic>>? _homeFuture;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppState>().syncWakeListener();
      }
    });
  }

  String _statusLabel(LiveState live) {
    switch (live) {
      case LiveState.resting:
        return 'Ready';
      case LiveState.listening:
        return 'Listening';
      case LiveState.thinking:
        return 'Thinking';
      case LiveState.speaking:
        return 'Speaking';
    }
  }

  String _helperText(AppState state, LiveState live) {
    if (state.turnError != null) {
      return 'Connection issue';
    }

    if (kIsWeb && state.wakeWordEnabled) {
      return live == LiveState.resting ? 'Wake word ready' : 'Wake word active';
    }

    if (state.checkinBanner != null && live == LiveState.resting) {
      return state.checkinBanner!;
    }

    if (live == LiveState.speaking) {
      return 'Interrupt anytime.';
    }

    if (live == LiveState.thinking) {
      return 'Thinking';
    }

    if (live == LiveState.listening) {
      return 'Listening';
    }

    return 'Voice ready';
  }

  String _sessionModeLabel(LiveState live, AppState state) {
    if (state.turnError != null) return 'Need attention';

    if (live == LiveState.resting) return 'Ready';

    if (state.lastReply != null && state.lastReply!.trim().isNotEmpty) {
      return 'AiPal is talking back';
    }

    return _statusLabel(live);
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

  Future<Map<String, dynamic>> _companionHomeFuture(AppState state) {
    if (_homeFuture == null || _homeToken != state.token) {
      _homeToken = state.token;
      _homeFuture = state.api.getCompanionHome();
    }
    return _homeFuture!;
  }

  void _openTextMode(BuildContext context, AppState state) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => TextChatScreen(sessionId: state.companionConversationId)));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final live = state.liveSession.state;
        final isLive = live != LiveState.resting;
        final webTitle = isLive ? 'Audio Call · AiPal' : 'Companion · AiPal';
        final homeFuture = _companionHomeFuture(state);
        _syncWebTitle(webTitle);

        return Scaffold(
          backgroundColor: _background,
          body: SafeArea(
            child: Column(
              children: [
                _CompanionAppBar(
                  status: _statusLabel(live),
                  live: live,
                  onClose: () => unawaited(_handleClose(state)),
                  onTextMode: () => _openTextMode(context, state),
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: _ChatBody(
                        state: state,
                        live: live,
                        homeFuture: homeFuture,
                        helperText: _helperText(state, live),
                        modeLabel: _sessionModeLabel(live, state),
                        onHomeAction: (prompt) {
                          unawaited(state.sendTextTurn(prompt));
                        },
                        onPlanDay: () {
                          unawaited(state.sendTextTurn('Help me plan my day.'));
                        },
                        onReminder: () {
                          unawaited(
                            state.sendTextTurn('Help me create a reminder.'),
                          );
                        },
                        onTalkIdea: () {
                          unawaited(
                            state.sendTextTurn(
                              'I want to talk through an idea.',
                            ),
                          );
                        },
                        onReviewTasks: () {
                          unawaited(state.sendTextTurn('Review my tasks.'));
                        },
                        onOpenToday: () => state.goToTab(1),
                      ),
                    ),
                  ),
                ),
                _BottomComposer(
                  live: live,
                  helperText: _helperText(state, live),
                  onMicTap: () => unawaited(state.toggleLive()),
                  onKeyboardTap: () => _openTextMode(context, state),
                  onComposerTap: () => _openTextMode(context, state),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CompanionAppBar extends StatelessWidget {
  const _CompanionAppBar({
    required this.status,
    required this.live,
    required this.onClose,
    required this.onTextMode,
  });

  final String status;
  final LiveState live;
  final VoidCallback onClose;
  final VoidCallback onTextMode;

  Color get _statusColor {
    switch (live) {
      case LiveState.listening:
      case LiveState.speaking:
        return _accent;
      case LiveState.thinking:
        return const Color(0xFF6366F1);
      case LiveState.resting:
        return _secondaryText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          _IconCircleButton(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            onTap: onClose,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'AiPal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _primaryText,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _IconCircleButton(
            icon: Icons.edit_outlined,
            tooltip: 'Text mode',
            onTap: onTextMode,
          ),
        ],
      ),
    );
  }
}

class _IconCircleButton extends StatelessWidget {
  const _IconCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: _primaryText, size: 22),
          ),
        ),
      ),
    );
  }
}

class _ChatBody extends StatelessWidget {
  const _ChatBody({
    required this.state,
    required this.live,
    required this.homeFuture,
    required this.helperText,
    required this.modeLabel,
    required this.onHomeAction,
    required this.onPlanDay,
    required this.onReminder,
    required this.onTalkIdea,
    required this.onReviewTasks,
    required this.onOpenToday,
  });

  final AppState state;
  final LiveState live;
  final Future<Map<String, dynamic>> homeFuture;
  final String helperText;
  final String modeLabel;
  final ValueChanged<String> onHomeAction;
  final VoidCallback onPlanDay;
  final VoidCallback onReminder;
  final VoidCallback onTalkIdea;
  final VoidCallback onReviewTasks;
  final VoidCallback onOpenToday;

  @override
  Widget build(BuildContext context) {
    final transcript = state.lastTranscript?.trim();
    final reply = state.lastReply?.trim();
    final hasTranscript =
        AppConfig.showLiveTranscript &&
        transcript != null &&
        transcript.isNotEmpty;
    final hasReply = reply != null && reply.isNotEmpty;
    final showEmpty = !hasTranscript && !hasReply && live == LiveState.resting;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      physics: const BouncingScrollPhysics(),
      children: [
        _CompanionHomePanel(future: homeFuture, onAction: onHomeAction),
        const SizedBox(height: 18),
        if (showEmpty)
          _EmptyConversationState(
            onPlanDay: onPlanDay,
            onReminder: onReminder,
            onTalkIdea: onTalkIdea,
            onReviewTasks: onReviewTasks,
          )
        else ...[
          if (hasTranscript)
            _MessageBubble(text: transcript, isUser: true, label: 'You'),
          if (hasTranscript) const SizedBox(height: 14),
          if (hasReply) ...[
            _MessageBubble(text: reply, isUser: false, label: 'AiPal'),
            const SizedBox(height: 12),
          ],
          _VoiceStateBanner(live: live, mode: modeLabel, helper: helperText),
          if (state.turnError != null) ...[
            const SizedBox(height: 12),
            _ErrorPanel(errorText: state.turnError!),
          ],
          const SizedBox(height: 16),
          _SuggestedActionsCard(
            onPlanDay: onPlanDay,
            onReminder: onReminder,
            onTalkIdea: onTalkIdea,
            onReviewTasks: onReviewTasks,
          ),
        ],
        if (live == LiveState.resting && state.nextOpenTask != null) ...[
          const SizedBox(height: 16),
          _NextTaskChip(
            title: '${state.nextOpenTask!['title']}',
            onTap: onOpenToday,
          ),
        ],
        if (state.pendingPlanDraft != null) ...[
          const SizedBox(height: 16),
          PlanDraftCard(
            draft: state.pendingPlanDraft!,
            onConfirm: () => state.confirmPlanDraft(),
            onDiscard: () => state.discardPlanDraft(),
          ),
        ],
      ],
    );
  }
}

class _CompanionHomePanel extends StatelessWidget {
  const _CompanionHomePanel({required this.future, required this.onAction});

  final Future<Map<String, dynamic>> future;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final contextData =
            (data?['context'] as Map?)?.cast<String, dynamic>() ?? {};
        final nextItem = (contextData['next_item'] as Map?)
            ?.cast<String, dynamic>();
        final cards = (data?['cards'] as List? ?? [])
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final message = data?['message']?.toString().trim();
        final hasMessage = message != null && message.isNotEmpty;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome_outlined, color: _accent, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Companion Home',
                      style: TextStyle(
                        color: _primaryText,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: loading
                    ? const _HomeSkeleton()
                    : hasMessage
                    ? Text(
                        message,
                        key: ValueKey(message),
                        style: const TextStyle(
                          color: _primaryText,
                          fontSize: 15.5,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : const Text(
                        'No companion brief available yet.',
                        key: ValueKey('home-empty'),
                        style: TextStyle(
                          color: _secondaryText,
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              if (nextItem != null) ...[
                const SizedBox(height: 12),
                _NextHomeItem(item: nextItem),
              ],
              if (cards.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: cards.take(4).map((card) {
                    return _HomeActionChip(
                      card: card,
                      onTap: () {
                        final prompt = card['prompt']?.toString();
                        if (prompt != null && prompt.trim().isNotEmpty) {
                          onAction(prompt.trim());
                        }
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('home-loading'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SkeletonLine(width: MediaQuery.sizeOf(context).width * 0.58),
        const SizedBox(height: 8),
        const _SkeletonLine(width: 180),
      ],
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 13,
      width: width.clamp(80, 300),
      decoration: BoxDecoration(
        color: const Color(0xFFEAEAEC),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _NextHomeItem extends StatelessWidget {
  const _NextHomeItem({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final title = item['title']?.toString() ?? 'Next item';
    final type = item['type']?.toString() ?? 'Today';
    final time = item['start_time']?.toString() ?? item['due_at']?.toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCEBE7)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_outlined, color: _accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              time == null ? title : '$title · ${_formatHomeDateTime(time)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _primaryText,
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SmallPill(label: type),
        ],
      ),
    );
  }
}

class _HomeActionChip extends StatelessWidget {
  const _HomeActionChip({required this.card, required this.onTap});

  final Map<String, dynamic> card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = card['title']?.toString() ?? 'Talk with AiPal';
    return ActionChip(
      backgroundColor: _surface,
      side: const BorderSide(color: _border),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      avatar: const Icon(Icons.add_comment_outlined, size: 16, color: _accent),
      label: Text(
        title,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _primaryText,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      onPressed: onTap,
    );
  }
}

class _EmptyConversationState extends StatelessWidget {
  const _EmptyConversationState({
    required this.onPlanDay,
    required this.onReminder,
    required this.onTalkIdea,
    required this.onReviewTasks,
  });

  final VoidCallback onPlanDay;
  final VoidCallback onReminder;
  final VoidCallback onTalkIdea;
  final VoidCallback onReviewTasks;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: _primaryText,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Voice companion',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _primaryText,
              fontSize: 25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start voice mode or open text chat. Assistant replies appear only after the backend returns them.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _secondaryText,
              fontSize: 14.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          _SuggestedActionsCard(
            onPlanDay: onPlanDay,
            onReminder: onReminder,
            onTalkIdea: onTalkIdea,
            onReviewTasks: onReviewTasks,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.text,
    required this.isUser,
    required this.label,
  });

  final String text;
  final bool isUser;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width < 480 ? 320 : 560,
        ),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                label,
                style: const TextStyle(
                  color: _secondaryText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: isUser ? _primaryText : _assistantBubble,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 20),
                ),
                border: isUser ? null : Border.all(color: _border),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: isUser ? Colors.white : _primaryText,
                  fontSize: 15.5,
                  height: 1.48,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceStateBanner extends StatelessWidget {
  const _VoiceStateBanner({
    required this.live,
    required this.mode,
    required this.helper,
  });

  final LiveState live;
  final String mode;
  final String helper;

  @override
  Widget build(BuildContext context) {
    final isActive = live != LiveState.resting;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isActive ? const Color(0xFFCDECE4) : _border),
      ),
      child: Row(
        children: [
          _VoiceStateIcon(live: live),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _primaryText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  helper,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _secondaryText,
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (live == LiveState.listening) const _ListeningWaveform(),
          if (live == LiveState.thinking) const _ThinkingDots(),
          if (live == LiveState.speaking) const _SmallPill(label: 'Interrupt'),
        ],
      ),
    );
  }
}

class _VoiceStateIcon extends StatelessWidget {
  const _VoiceStateIcon({required this.live});

  final LiveState live;

  @override
  Widget build(BuildContext context) {
    final icon = switch (live) {
      LiveState.listening => Icons.mic_rounded,
      LiveState.thinking => Icons.more_horiz_rounded,
      LiveState.speaking => Icons.graphic_eq_rounded,
      LiveState.resting => Icons.radio_button_unchecked_rounded,
    };

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: live == LiveState.resting
            ? const Color(0xFFF3F4F6)
            : const Color(0xFFE8F7F3),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: live == LiveState.resting ? _secondaryText : _accent,
        size: 18,
      ),
    );
  }
}

class _ListeningWaveform extends StatefulWidget {
  const _ListeningWaveform();

  @override
  State<_ListeningWaveform> createState() => _ListeningWaveformState();
}

class _ListeningWaveformState extends State<_ListeningWaveform> {
  bool _tall = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (mounted) {
        setState(() => _tall = !_tall);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heights = _tall
        ? const [10.0, 18.0, 26.0, 14.0]
        : const [20.0, 12.0, 18.0, 26.0];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final height in heights)
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 3,
            height: height,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots> {
  int _active = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 360), (_) {
      if (mounted) {
        setState(() => _active = (_active + 1) % 3);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: index == _active ? _accent : const Color(0xFFD1D5DB),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.errorText});

  final String errorText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFB42318),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              errorText,
              style: const TextStyle(
                color: Color(0xFF912018),
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestedActionsCard extends StatelessWidget {
  const _SuggestedActionsCard({
    required this.onPlanDay,
    required this.onReminder,
    required this.onTalkIdea,
    required this.onReviewTasks,
  });

  final VoidCallback onPlanDay;
  final VoidCallback onReminder;
  final VoidCallback onTalkIdea;
  final VoidCallback onReviewTasks;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _PromptChip(
          icon: Icons.calendar_today_outlined,
          label: 'Plan my day',
          onTap: onPlanDay,
        ),
        _PromptChip(
          icon: Icons.notifications_none_rounded,
          label: 'Create a reminder',
          onTap: onReminder,
        ),
        _PromptChip(
          icon: Icons.lightbulb_outline_rounded,
          label: 'Talk through an idea',
          onTap: onTalkIdea,
        ),
        _PromptChip(
          icon: Icons.checklist_rounded,
          label: 'Review my tasks',
          onTap: onReviewTasks,
        ),
      ],
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      backgroundColor: _surface,
      side: const BorderSide(color: _border),
      avatar: Icon(icon, size: 17, color: _accent),
      label: Text(
        label,
        style: const TextStyle(
          color: _primaryText,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      onPressed: onTap,
    );
  }
}

class _NextTaskChip extends StatelessWidget {
  const _NextTaskChip({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ActionChip(
        backgroundColor: _surface,
        side: const BorderSide(color: _border),
        avatar: const Icon(
          Icons.arrow_forward_rounded,
          size: 16,
          color: _accent,
        ),
        label: Text(
          'Up next: $title',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: onTap,
      ),
    );
  }
}

class _BottomComposer extends StatelessWidget {
  const _BottomComposer({
    required this.live,
    required this.helperText,
    required this.onMicTap,
    required this.onKeyboardTap,
    required this.onComposerTap,
  });

  final LiveState live;
  final String helperText;
  final VoidCallback onMicTap;
  final VoidCallback onKeyboardTap;
  final VoidCallback onComposerTap;

  bool get _isLive => live != LiveState.resting;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomPadding),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: _background,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: _border),
                ),
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                child: Row(
                  children: [
                    _ComposerButton(
                      icon: Icons.keyboard_rounded,
                      tooltip: 'Open text chat',
                      onTap: onKeyboardTap,
                    ),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: onComposerTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          child: Text(
                            _isLive ? helperText : 'Message AiPal',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _isLive ? _primaryText : _secondaryText,
                              fontSize: 15,
                              fontWeight: _isLive
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _VoiceActionButton(live: live, onTap: onMicTap),
                  ],
                ),
              ),
              if (_isLive) ...[
                const SizedBox(height: 8),
                Text(
                  live == LiveState.speaking
                      ? 'Speaking. Interrupt anytime.'
                      : 'Live voice is on.',
                  style: const TextStyle(
                    color: _secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerButton extends StatelessWidget {
  const _ComposerButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: _secondaryText, size: 22),
          ),
        ),
      ),
    );
  }
}

class _VoiceActionButton extends StatelessWidget {
  const _VoiceActionButton({required this.live, required this.onTap});

  final LiveState live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLive = live != LiveState.resting;
    final icon = isLive ? Icons.stop_rounded : Icons.mic_rounded;

    return Tooltip(
      message: isLive ? 'Stop live voice' : 'Start live voice',
      child: Material(
        color: isLive ? _primaryText : _accent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: Colors.white, size: 23),
          ),
        ),
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F7F3),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF08785E),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _formatHomeDateTime(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final hour = parsed.hour == 0
      ? 12
      : parsed.hour > 12
      ? parsed.hour - 12
      : parsed.hour;
  final minute = parsed.minute.toString().padLeft(2, '0');
  final suffix = parsed.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}
