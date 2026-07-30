import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/web_title.dart';
import '../widgets/plan_draft_card.dart';
import '../widgets/today/focus_timer_bar.dart';
import '../widgets/today/today_empty.dart';
import 'task_detail_screen.dart';

// Premium Color System & Visual Tokens
const Color _kBgColor = Color(0xFFF8FAFC);
const Color _kCardBg = Colors.white;
const Color _kPrimary = Color(0xFF2563EB);
const Color _kTextPrimary = Color(0xFF0F172A);
const Color _kTextSecondary = Color(0xFF64748B);
const Color _kBorderColor = Color(0xFFE2E8F0);
const Color _kSuccess = Color(0xFF10B981);
const Color _kDanger = Color(0xFFEF4444);

const LinearGradient _kBrandGradient = LinearGradient(
  colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  bool _completedExpanded = false;
  String? _lastWebTitle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshTodayView();
    });
  }

  void _syncWebTitle(String title) {
    if (!kIsWeb || _lastWebTitle == title) return;
    _lastWebTitle = title;
    setWebPageTitle(title);
  }

  Future<void> _suggestDay(AppState state, {String? template}) async {
    await state.suggestDayPlan(template: template);
    if (!mounted) return;

    final notice = state.suggestDayNotice;
    if (notice != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(notice),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      state.clearSuggestDayNotice();
    }
  }

  Future<void> _addTask() async {
    final titleController = TextEditingController();
    final noteController = TextEditingController();

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PremiumTaskSheet(
        titleController: titleController,
        noteController: noteController,
      ),
    );

    titleController.dispose();
    noteController.dispose();

    final title = result?['title']?.trim() ?? '';
    final notes = result?['notes']?.trim();

    if (title.isNotEmpty && mounted) {
      await context.read<AppState>().createTask(
        title,
        notes: notes?.isNotEmpty == true ? notes : null,
      );
    }
  }

  void _openReview(AppState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PremiumReviewSheet(
        openTasks: state.openTasksForReview,
        onDefer: () async {
          Navigator.pop(context);
          await state.deferOpenTasks();
        },
        onGoLive: () {
          Navigator.pop(context);
          state.goToTab(0);
          state.toggleLive();
        },
      ),
    );
  }

  Future<void> _showSuggestSheet(AppState state) async {
    final template = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SuggestPlanSheet(),
    );

    if (template != null && mounted) {
      await _suggestDay(state, template: template);
    }
  }

  void _openTaskDetail(Map<String, dynamic> task) {
    final taskId = task['id']?.toString();
    if (taskId == null || taskId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(taskId: taskId),
      ),
    );
  }

  Future<void> _loadAndReview(AppState state) async {
    await state.loadEveningPayload();
    if (mounted) _openReview(state);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        _syncWebTitle('Today · AiPal');
        final view = state.todayView;
        final summary = view?['summary'] as Map<String, dynamic>?;
        final sections = view?['sections'] as Map<String, dynamic>?;
        final upNext = view?['up_next'] as Map<String, dynamic>?;
        final todayItems =
            (view?['today_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        final agendaOpen = todayItems
            .where(
              (item) => !{
                'completed',
                'cancelled',
                'dismissed',
              }.contains(item['status']?.toString()),
            )
            .toList();
        final agendaCompleted = todayItems
            .where((item) => item['status']?.toString() == 'completed')
            .toList();

        final now =
            (sections?['now'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final upcoming =
            (sections?['upcoming'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final completed =
            (sections?['completed'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        final focus = state.focusTask;
        final planDraft = state.pendingPlanDraft;

        final done = summary?['done'] as int? ?? 0;
        final total = summary?['total'] as int? ?? 0;
        final streak = summary?['streak_days'] as int? ?? 0;

        return Scaffold(
          backgroundColor: _kBgColor,
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onPressed: _addTask,
            icon: const Icon(Icons.add_rounded, size: 22),
            label: const Text(
              'Add Task',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          body: Stack(
            children: [
              const _TodayBackground(),
              SafeArea(
                child: Column(
                  children: [
                    if (focus != null)
                      FocusTimerBar(
                        taskTitle: focus['title'] as String? ?? 'Focus Session',
                        totalSeconds: state.focusSeconds,
                        onComplete: () => state.completeFocusTask(),
                        onCancel: () => state.cancelFocus(),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: state.refreshTodayView,
                        color: _kPrimary,
                        child: view == null
                            ? const Center(
                                child: CircularProgressIndicator(color: _kPrimary),
                              )
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
                                physics: const BouncingScrollPhysics(),
                                children: [
                                  // Dynamic Date & Stat Header
                                  _TodayHeader(
                                    done: done,
                                    total: total,
                                    streak: streak,
                                    onReview: () => _loadAndReview(state),
                                  ),

                                  const SizedBox(height: 20),

                                  // Quick Routine Presets Selector
                                  _RoutineChips(
                                    busy: state.loading,
                                    onSelect: (template) =>
                                        _suggestDay(state, template: template),
                                    onSuggest: () => _showSuggestSheet(state),
                                  ),

                                  const SizedBox(height: 20),

                                  // AI Plan Draft Preview Card if present
                                  if (planDraft != null) ...[
                                    _GlassPanel(
                                      child: PlanDraftCard(
                                        draft: planDraft,
                                        onConfirm: state.confirmPlanDraft,
                                        onDiscard: state.discardPlanDraft,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                  ],

                                  // Empty State vs Populated Tasks View
                                  if (total == 0 &&
                                      upNext == null &&
                                      todayItems.isEmpty &&
                                      now.isEmpty &&
                                      upcoming.isEmpty) ...[
                                    SizedBox(
                                      height: MediaQuery.of(context).size.height * 0.45,
                                      child: TodayEmpty(
                                        onGoCompanion: () => state.goToTab(0),
                                      ),
                                    ),
                                  ] else ...[
                                    // Highlighted Priority Up Next Card
                                    if (upNext != null) ...[
                                      _UpNextPremiumCard(
                                        task: upNext,
                                        onStartFocus: () =>
                                            state.startFocus(upNext),
                                        onOpen: () => _openTaskDetail(upNext),
                                        onDone: () async {
                                          final id = upNext['id'] as int?;
                                          if (id != null) {
                                            await state.completeTask(id);
                                          }
                                        },
                                      ),
                                      const SizedBox(height: 24),
                                    ],

                                    // Main Today Agenda Items
                                    if (todayItems.isNotEmpty)
                                      _AgendaColumn(
                                        open: agendaOpen,
                                        completed: agendaCompleted,
                                        completedExpanded: _completedExpanded,
                                        onToggleCompleted: () => setState(
                                          () => _completedExpanded =
                                              !_completedExpanded,
                                        ),
                                        onComplete: state.completeTodayItem,
                                        onSnooze: (id) =>
                                            state.snoozeTodayItem(id),
                                        onStartFocus: (item) =>
                                            state.startFocusTodayItem(item),
                                        onCancel: state.cancelTodayItem,
                                        onOpenDetail: _openTaskDetail,
                                      )
                                    else ...[
                                      if (now.isNotEmpty) ...[
                                        _TaskSection(
                                          title: 'Do Now',
                                          icon: Icons.bolt_rounded,
                                          iconColor: const Color(0xFFF59E0B),
                                          tasks: now,
                                          onOpenDetail: _openTaskDetail,
                                          onComplete: (id) =>
                                              state.completeTask(id),
                                        ),
                                        const SizedBox(height: 20),
                                      ],
                                      if (upcoming.isNotEmpty) ...[
                                        _TaskSection(
                                          title: 'Upcoming Today',
                                          icon: Icons.schedule_rounded,
                                          iconColor: _kPrimary,
                                          tasks: upcoming,
                                          onOpenDetail: _openTaskDetail,
                                          onComplete: (id) =>
                                              state.completeTask(id),
                                        ),
                                        const SizedBox(height: 20),
                                      ],
                                      if (completed.isNotEmpty) ...[
                                        _TaskSection(
                                          title: 'Completed Today',
                                          icon: Icons.check_circle_rounded,
                                          iconColor: _kSuccess,
                                          tasks: completed,
                                          isCompleted: true,
                                          onOpenDetail: _openTaskDetail,
                                          onComplete: (id) {},
                                        ),
                                      ],
                                    ],
                                  ],
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({
    required this.done,
    required this.total,
    required this.streak,
    required this.onReview,
  });

  final int done;
  final int total;
  final int streak;
  final VoidCallback onReview;

  String _formattedDate() {
    final now = DateTime.now();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return '${days[now.weekday % 7]}, ${months[now.month - 1]} ${now.day}';
  }

  @override
  Widget build(BuildContext context) {
    final double progress = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final int percentage = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kBorderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formattedDate().toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: _kTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Today\'s Plan',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: _kTextPrimary,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (streak > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          const Text('🔥', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 4),
                          Text(
                            '$streak',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onReview,
                    icon: const Icon(Icons.wb_twilight_rounded, size: 16, color: _kPrimary),
                    label: const Text(
                      'Review',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kPrimary),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      side: const BorderSide(color: Color(0xFFBFDBFE)),
                      backgroundColor: const Color(0xFFEFF6FF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Progress bar & text
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$done of $total tasks completed',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _kTextSecondary,
                ),
              ),
              Text(
                '$percentage%',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _kPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: const AlwaysStoppedAnimation<Color>(_kPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutineChips extends StatelessWidget {
  const _RoutineChips({
    required this.busy,
    required this.onSelect,
    required this.onSuggest,
  });

  final bool busy;
  final ValueChanged<String> onSelect;
  final VoidCallback onSuggest;

  final List<Map<String, dynamic>> _presets = const [
    {'id': 'focus', 'label': '⚡ Deep Focus', 'icon': Icons.bolt_rounded},
    {'id': 'meetings', 'label': '📅 Meeting Heavy', 'icon': Icons.calendar_month_rounded},
    {'id': 'balanced', 'label': '🧘 Balanced', 'icon': Icons.self_improvement_rounded},
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          // AI Custom Suggestion Pill Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: busy ? null : onSuggest,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: _kBrandGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _kPrimary.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'AI Auto-Plan',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Preset Chips
          ..._presets.map((p) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: busy ? null : () => onSelect(p['id'] as String),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    decoration: BoxDecoration(
                      color: _kCardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _kBorderColor),
                    ),
                    child: Text(
                      p['label'] as String,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _kTextPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _UpNextPremiumCard extends StatelessWidget {
  const _UpNextPremiumCard({
    required this.task,
    required this.onStartFocus,
    required this.onOpen,
    required this.onDone,
  });

  final Map<String, dynamic> task;
  final VoidCallback onStartFocus;
  final VoidCallback onOpen;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final title = task['title']?.toString() ?? 'Untitled Task';
    final duration = task['estimated_minutes']?.toString() ?? '25';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        gradient: const LinearGradient(
          colors: [Color(0xFFEFF6FF), Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: _kPrimary.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kPrimary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.star_rounded, color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'UP NEXT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                color: _kTextSecondary,
                tooltip: 'Task Details',
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _kTextPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 14, color: _kTextSecondary),
              const SizedBox(width: 4),
              Text(
                '$duration min estimated',
                style: const TextStyle(fontSize: 12, color: _kTextSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onStartFocus,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Start Focus Session'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: onDone,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 24),
                color: _kSuccess,
                tooltip: 'Mark Done',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFD1FAE5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgendaColumn extends StatelessWidget {
  const _AgendaColumn({
    required this.open,
    required this.completed,
    required this.completedExpanded,
    required this.onToggleCompleted,
    required this.onComplete,
    required this.onSnooze,
    required this.onStartFocus,
    required this.onCancel,
    required this.onOpenDetail,
  });

  final List<Map<String, dynamic>> open;
  final List<Map<String, dynamic>> completed;
  final bool completedExpanded;
  final VoidCallback onToggleCompleted;
  final ValueChanged<String> onComplete;
  final ValueChanged<String> onSnooze;
  final ValueChanged<Map<String, dynamic>> onStartFocus;
  final ValueChanged<String> onCancel;
  final ValueChanged<Map<String, dynamic>> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (open.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Agenda',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _kTextPrimary,
              ),
            ),
          ),
          ...open.map((item) {
            final id = item['id']?.toString() ?? '';
            return _AgendaItemCard(
              item: item,
              onComplete: () => onComplete(id),
              onSnooze: () => onSnooze(id),
              onStartFocus: () => onStartFocus(item),
              onCancel: () => onCancel(id),
              onTap: () => onOpenDetail(item),
            );
          }),
        ],

        if (completed.isNotEmpty) ...[
          const SizedBox(height: 16),
          InkWell(
            onTap: onToggleCompleted,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    completedExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    color: _kTextSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Completed (${completed.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _kTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (completedExpanded)
            ...completed.map((item) {
              return _AgendaItemCard(
                item: item,
                isCompleted: true,
                onComplete: () {},
                onSnooze: () {},
                onStartFocus: () {},
                onCancel: () {},
                onTap: () => onOpenDetail(item),
              );
            }),
        ],
      ],
    );
  }
}

class _AgendaItemCard extends StatelessWidget {
  const _AgendaItemCard({
    required this.item,
    this.isCompleted = false,
    required this.onComplete,
    required this.onSnooze,
    required this.onStartFocus,
    required this.onCancel,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final bool isCompleted;
  final VoidCallback onComplete;
  final VoidCallback onSnooze;
  final VoidCallback onStartFocus;
  final VoidCallback onCancel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = item['title']?.toString() ?? item['summary']?.toString() ?? 'Task';
    final timeStr = item['time']?.toString() ?? item['due_label']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorderColor),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Completion Checkbox
                IconButton(
                  onPressed: onComplete,
                  icon: Icon(
                    isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isCompleted ? _kSuccess : _kTextSecondary,
                    size: 22,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                const SizedBox(width: 10),

                // Task Information Title & Meta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isCompleted ? _kTextSecondary : _kTextPrimary,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (timeStr.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: _kTextSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                if (!isCompleted) ...[
                  IconButton(
                    onPressed: onStartFocus,
                    icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
                    color: _kPrimary,
                    tooltip: 'Focus',
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 18, color: _kTextSecondary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onSelected: (val) {
                      if (val == 'snooze') onSnooze();
                      if (val == 'cancel') onCancel();
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'snooze',
                        child: Row(
                          children: [
                            Icon(Icons.snooze_rounded, size: 16, color: _kTextSecondary),
                            SizedBox(width: 8),
                            Text('Snooze'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'cancel',
                        child: Row(
                          children: [
                            Icon(Icons.close_rounded, size: 16, color: _kDanger),
                            SizedBox(width: 8),
                            Text('Cancel', style: TextStyle(color: _kDanger)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskSection extends StatelessWidget {
  const _TaskSection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.tasks,
    this.isCompleted = false,
    required this.onOpenDetail,
    required this.onComplete,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Map<String, dynamic>> tasks;
  final bool isCompleted;
  final ValueChanged<Map<String, dynamic>> onOpenDetail;
  final ValueChanged<int> onComplete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _kTextPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${tasks.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...tasks.map((task) {
          final id = task['id'] as int?;
          return _AgendaItemCard(
            item: task,
            isCompleted: isCompleted,
            onComplete: () {
              if (id != null) onComplete(id);
            },
            onSnooze: () {},
            onStartFocus: () {},
            onCancel: () {},
            onTap: () => onOpenDetail(task),
          );
        }),
      ],
    );
  }
}

class _PremiumTaskSheet extends StatelessWidget {
  const _PremiumTaskSheet({
    required this.titleController,
    required this.noteController,
  });

  final TextEditingController titleController;
  final TextEditingController noteController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 30,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _kBorderColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'New Task',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _kTextPrimary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                autofocus: true,
                style: const TextStyle(fontSize: 15, color: _kTextPrimary),
                decoration: InputDecoration(
                  hintText: 'What needs to be done?',
                  prefixIcon: const Icon(Icons.task_alt_rounded, color: _kPrimary),
                  filled: true,
                  fillColor: _kBgColor,
                  contentPadding: const EdgeInsets.all(16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 3,
                style: const TextStyle(fontSize: 14, color: _kTextPrimary),
                decoration: InputDecoration(
                  hintText: 'Add details or notes (optional)',
                  prefixIcon: const Icon(Icons.notes_rounded, color: _kTextSecondary),
                  filled: true,
                  fillColor: _kBgColor,
                  contentPadding: const EdgeInsets.all(16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, {
                      'title': titleController.text,
                      'notes': noteController.text,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Save Task',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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

class _PremiumReviewSheet extends StatelessWidget {
  const _PremiumReviewSheet({
    required this.openTasks,
    required this.onDefer,
    required this.onGoLive,
  });

  final List<Map<String, dynamic>> openTasks;
  final VoidCallback onDefer;
  final VoidCallback onGoLive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _kBorderColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Row(
              children: [
                Icon(Icons.wb_twilight_rounded, color: Color(0xFF7C3AED), size: 24),
                SizedBox(width: 10),
                Text(
                  'Evening Recap & Review',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _kTextPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              openTasks.isEmpty
                  ? 'Great job! You completed all tasks scheduled for today.'
                  : 'You have ${openTasks.length} open items remaining today.',
              style: const TextStyle(fontSize: 14, color: _kTextSecondary),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                if (openTasks.isNotEmpty) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDefer,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Defer Remaining'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onGoLive,
                    icon: const Icon(Icons.mic_rounded, size: 18),
                    label: const Text('Voice Reflection'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestPlanSheet extends StatelessWidget {
  const _SuggestPlanSheet();

  @override
  Widget build(BuildContext context) {
    final templates = [
      {'id': 'focus', 'title': 'Deep Work Sprint', 'desc': 'High priority deep focus blocks'},
      {'id': 'meetings', 'title': 'Collaborative Day', 'desc': 'Structure around calls & admin'},
      {'id': 'balanced', 'title': 'Balanced Pace', 'desc': 'Mix of focus, breaks, and routine'},
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _kBorderColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Select AI Day Template',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _kTextPrimary,
              ),
            ),
            const SizedBox(height: 16),
            ...templates.map((t) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: _kBorderColor),
                  ),
                  title: Text(
                    t['title']!,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: Text(
                    t['desc']!,
                    style: const TextStyle(fontSize: 12, color: _kTextSecondary),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: _kTextSecondary),
                  onTap: () => Navigator.pop(context, t['id']),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kBorderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TodayBackground extends StatelessWidget {
  const _TodayBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -100,
          right: -80,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFDBEAFE).withValues(alpha: 0.5),
            ),
          ),
        ),
        Positioned(
          bottom: 100,
          left: -80,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFEDE9FE).withValues(alpha: 0.4),
            ),
          ),
        ),
      ],
    );
  }
}