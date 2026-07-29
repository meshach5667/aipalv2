import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/web_title.dart';
import '../widgets/plan_draft_card.dart';
import '../widgets/today/focus_timer_bar.dart';
import '../widgets/today/today_empty.dart';
import 'task_detail_screen.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  bool _completedExpanded = false;
  String? _lastWebTitle;

  // Modern High-Contrast Design Palette
  static const Color primaryColor = Color(0xFF705D00);
  static const Color primaryContainer = Color(0xFFFFD600);
  static const Color onPrimaryFixed = Color(0xFF221B00);
  static const Color surfaceColor = Color(0xFFF4F5F7);
  static const Color darkContainer = Color(0xFF1A1C1C);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppState>().refreshTodayView();
      }
    });
  }

  Future<void> _suggestDay(AppState state, {String? template}) async {
    await state.suggestDayPlan(template: template);
    if (!mounted) return;

    final notice = state.suggestDayNotice;
    if (notice != null && notice.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notice,
            style: const TextStyle(fontFamily: 'Inter', color: Colors.white),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: darkContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
      state.clearSuggestDayNotice();
    }
  }

  Future<void> _addTask(Map<String, dynamic> ui) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PremiumTaskSheet(ui: ui),
    );

    final title = result?['title']?.trim() ?? '';

    if (title.isNotEmpty && mounted) {
      await context.read<AppState>().createTask(
        title,
        notes: result?['notes']?.toString(),
        dueAt: result?['due_at'] as DateTime?,
        priority: result?['priority'] as int?,
        estimatedMinutes: result?['estimated_minutes'] as int?,
        category: result?['category']?.toString(),
      );
    }
  }

  void _openReview(AppState state, Map<String, dynamic> ui) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PremiumReviewSheet(
        ui: ui,
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

  Future<void> _showSuggestSheet(
    AppState state,
    Map<String, dynamic> ui,
  ) async {
    final template = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SuggestPlanSheet(ui: ui),
    );

    if (template != null && mounted) {
      await _suggestDay(state, template: template);
    }
  }

  void _openTaskDetail(Map<String, dynamic> task) {
    final detailId = task['task_id'] ?? task['id'];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(taskId: detailId.toString()),
      ),
    );
  }

  Future<void> _toggleTaskComplete(
    AppState state,
    String id,
    bool completed,
  ) async {
    if (completed) {
      final confirmed = await _confirmTaskDone();
      if (confirmed != true) return;
    }
    final numericId = int.tryParse(id);
    if (numericId != null) {
      if (completed) {
        await state.completeTask(numericId);
      } else {
        await state.updateTask(numericId, status: 'planned');
      }
    } else {
      await state.toggleItemComplete(id, completed);
    }
  }

  Future<bool?> _confirmTaskDone() {
    var checked = false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Confirm task completion'),
          content: CheckboxListTile(
            value: checked,
            onChanged: (value) => setDialogState(() {
              checked = value ?? false;
            }),
            contentPadding: EdgeInsets.zero,
            title: const Text('I have finished this task.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: checked ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Mark done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadAndReview(AppState state, Map<String, dynamic> ui) async {
    await state.loadEveningPayload();
    if (mounted) _openReview(state, ui);
  }

  void _syncWebTitle(String title) {
    if (!kIsWeb || _lastWebTitle == title) return;
    _lastWebTitle = title;
    setWebPageTitle(title);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        _syncWebTitle('Today · AiPal');
        final view = state.todayView;
        final summary = view?['summary'] as Map<String, dynamic>?;
        final ui = (view?['ui'] as Map?)?.cast<String, dynamic>() ?? {};
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

        final focus = state.focusTask;
        final planDraft = state.pendingPlanDraft;

        final done = summary?['done'] as int? ?? 0;
        final total = summary?['total'] as int? ?? 0;
        final streak = summary?['streak_days'] as int? ?? 0;

        final isEmptyState = total == 0 && upNext == null && todayItems.isEmpty;

        return Scaffold(
          backgroundColor: surfaceColor,
          floatingActionButton: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: primaryContainer.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: FloatingActionButton.extended(
              elevation: 0,
              highlightElevation: 0,
              backgroundColor: primaryContainer,
              foregroundColor: onPrimaryFixed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              onPressed: () => _addTask(ui),
              icon: const Icon(Icons.add_rounded, size: 24),
              label: const Text(
                'New Task',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (focus != null)
                  FocusTimerBar(
                    taskTitle: focus['title'] as String,
                    totalSeconds: state.focusSeconds,
                    onComplete: () => state.completeFocusTask(),
                    onCancel: () => state.cancelFocus(),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    color: primaryColor,
                    onRefresh: state.refreshTodayView,
                    child: view == null
                        ? const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                primaryColor,
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                            children: [
                              // Hero Bento Summary Header
                              _TodayHeader(
                                ui: ui,
                                done: done,
                                total: total,
                                streak: streak,
                                onReview: () => _loadAndReview(state, ui),
                              ),
                              const SizedBox(height: 20),

                              // Quick Action Chips
                              _RoutineChips(
                                ui: ui,
                                busy: state.loading,
                                onSelect: (template) =>
                                    _suggestDay(state, template: template),
                                onSuggest: () => _showSuggestSheet(state, ui),
                              ),
                              const SizedBox(height: 24),

                              if (planDraft != null) ...[
                                PlanDraftCard(
                                  draft: planDraft,
                                  onConfirm: state.confirmPlanDraft,
                                  onDiscard: state.discardPlanDraft,
                                ),
                                const SizedBox(height: 24),
                              ],

                              if (isEmptyState)
                                Padding(
                                  padding: const EdgeInsets.only(top: 24.0),
                                  child: SizedBox(
                                    height:
                                        MediaQuery.of(context).size.height *
                                        0.4,
                                    child: TodayEmpty(
                                      title: ui['empty_title']?.toString(),
                                      description: ui['empty_description']
                                          ?.toString(),
                                      actionLabel: ui['companion_label']
                                          ?.toString(),
                                      onGoCompanion: () => state.goToTab(0),
                                    ),
                                  ),
                                )
                              else ...[
                                // Up Next Hero Card
                                if (upNext != null) ...[
                                  _UpNextCard(
                                    ui: ui,
                                    upNext: upNext,
                                    onStartFocus: () =>
                                        state.startFocusTask(upNext),
                                    onBreakDown: () => _openTaskDetail(upNext),
                                    onComplete: () => _toggleTaskComplete(
                                      state,
                                      upNext['id'].toString(),
                                      true,
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                ],

                                // Layout Split: Timeline & Focus Analytics
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final isWide = constraints.maxWidth > 768;

                                    final timelineWidget = _PersonalAgenda(
                                      ui: ui,
                                      openItems: agendaOpen,
                                      completedItems: agendaCompleted,
                                      completedExpanded: _completedExpanded,
                                      onToggleExpanded: () {
                                        setState(() {
                                          _completedExpanded =
                                              !_completedExpanded;
                                        });
                                      },
                                      onTaskTap: _openTaskDetail,
                                      onTaskToggle: (id, completed) {
                                        _toggleTaskComplete(
                                          state,
                                          id,
                                          completed,
                                        );
                                      },
                                    );

                                    final analyticsWidget = _FocusLanes(
                                      ui: ui,
                                      openCount: agendaOpen.length,
                                      completedCount: agendaCompleted.length,
                                    );

                                    if (isWide) {
                                      return Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: timelineWidget,
                                          ),
                                          const SizedBox(width: 24),
                                          Expanded(
                                            flex: 2,
                                            child: analyticsWidget,
                                          ),
                                        ],
                                      );
                                    }

                                    return Column(
                                      children: [
                                        timelineWidget,
                                        const SizedBox(height: 28),
                                        analyticsWidget,
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Bento Summary Header
class _TodayHeader extends StatelessWidget {
  final Map<String, dynamic> ui;
  final int done;
  final int total;
  final int streak;
  final VoidCallback onReview;

  const _TodayHeader({
    required this.ui,
    required this.done,
    required this.total,
    required this.streak,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final double progress = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final title = ui['title']?.toString().trim() ?? 'Today';
    final completionLabel = ui['completion_label']?.toString().trim();
    final streakLabel = ui['streak_label']?.toString().trim();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFEFEFEF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.0,
                  color: Color(0xFF1A1C1C),
                ),
              ),
              IconButton(
                onPressed: onReview,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF4F5F7),
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(
                  Icons.auto_graph_rounded,
                  color: Color(0xFF1A1C1C),
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              // Tasks Completed Badge
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF705D00).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: Color(0xFF705D00),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$done / $total',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1C1C),
                            ),
                          ),
                          Text(
                            completionLabel ?? 'Tasks Done',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.black.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Streak Badge
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD600).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFFFD600).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD600).withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.local_fire_department_rounded,
                          size: 16,
                          color: Color(0xFF705D00),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$streak Days',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF705D00),
                            ),
                          ),
                          Text(
                            streakLabel ?? 'Streak',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF705D00).withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Progress Indicator Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Day Completion',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8C8E90),
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: const Color(0xFFF0F1F3),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFFD600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Quick Routine Action Chips
class _RoutineChips extends StatelessWidget {
  final Map<String, dynamic> ui;
  final bool busy;
  final Function(String?) onSelect;
  final VoidCallback onSuggest;

  const _RoutineChips({
    required this.ui,
    required this.busy,
    required this.onSelect,
    required this.onSuggest,
  });

  @override
  Widget build(BuildContext context) {
    final suggestLabel = ui['suggest_label']?.toString().trim();
    final templates = ((ui['templates'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where(
          (item) =>
              item['id']?.toString().trim().isNotEmpty == true &&
              item['label']?.toString().trim().isNotEmpty == true,
        )
        .toList();

    if (suggestLabel?.isNotEmpty != true && templates.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          if (suggestLabel?.isNotEmpty == true)
            ElevatedButton.icon(
              onPressed: busy ? null : onSuggest,
              icon: const Icon(Icons.auto_awesome_rounded, size: 16),
              label: Text(suggestLabel!),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1C1C),
                foregroundColor: const Color(0xFFFFD600),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (suggestLabel?.isNotEmpty == true && templates.isNotEmpty)
            const SizedBox(width: 8),
          for (final template in templates) ...[
            _ChipButton(
              label: template['label'].toString(),
              onTap: () => onSelect(template['id'].toString()),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ChipButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1C1C),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Hero "Up Next" Bento Card Component
class _UpNextCard extends StatelessWidget {
  final Map<String, dynamic> ui;
  final Map<String, dynamic> upNext;
  final VoidCallback onStartFocus;
  final VoidCallback onBreakDown;
  final VoidCallback onComplete;

  const _UpNextCard({
    required this.ui,
    required this.upNext,
    required this.onStartFocus,
    required this.onBreakDown,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final title = upNext['title']?.toString().trim() ?? '';
    final notes = upNext['notes']?.toString().trim();
    final description = _taskDescription(notes);
    final sensitivity = _taskMeta(notes, 'Sensitivity');
    final scheduled = _scheduledFromTask(upNext, notes);
    final upNextLabel = ui['up_next_label']?.toString().trim() ?? 'UP NEXT';
    final startFocusLabel =
        ui['start_focus_label']?.toString().trim() ?? 'Start Focus';
    final openDetailLabel =
        ui['open_detail_label']?.toString().trim() ?? 'Details';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C1C),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD600),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  upNextLabel.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF221B00),
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              IconButton(
                onPressed: onComplete,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.08),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.check_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.3,
            ),
          ),
          if (description?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: Colors.white.withOpacity(0.6),
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (sensitivity?.isNotEmpty == true)
                _UpNextMetaChip(
                  icon: Icons.privacy_tip_outlined,
                  label: sensitivity!,
                ),
              if (scheduled.date.isNotEmpty)
                _UpNextMetaChip(
                  icon: Icons.event_outlined,
                  label: scheduled.date,
                ),
              if (scheduled.time.isNotEmpty)
                _UpNextMetaChip(
                  icon: Icons.schedule_outlined,
                  label: scheduled.time,
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onStartFocus,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text(startFocusLabel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD600),
                    foregroundColor: const Color(0xFF221B00),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: onBreakDown,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withOpacity(0.08),
                  side: BorderSide(color: Colors.white.withOpacity(0.12)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(openDetailLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _taskDescription(String? notes) {
    if (notes == null || notes.isEmpty) return null;
    final lines = notes
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where(
          (line) =>
              !line.startsWith('Scheduled:') &&
              !line.startsWith('Reminder:') &&
              !line.startsWith('Location:') &&
              !line.startsWith('Sensitivity:') &&
              !line.startsWith('Attachments:'),
        )
        .toList();
    return lines.isEmpty ? null : lines.join(' ');
  }

  String? _taskMeta(String? notes, String key) {
    if (notes == null || notes.isEmpty) return null;
    final prefix = '$key:';
    for (final line in notes.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith(prefix)) {
        return trimmed.substring(prefix.length).trim();
      }
    }
    return null;
  }

  _ScheduledInfo _scheduledFromTask(Map<String, dynamic> task, String? notes) {
    final rawDue = task['due_at']?.toString();
    final parsedDue = rawDue == null ? null : DateTime.tryParse(rawDue);
    if (parsedDue != null) {
      final local = parsedDue.toLocal();
      return _ScheduledInfo(_formatDate(local), _formatTime(local));
    }

    final scheduled = _taskMeta(notes, 'Scheduled');
    if (scheduled == null || scheduled.isEmpty) {
      return const _ScheduledInfo('', '');
    }
    final parts = scheduled.split(RegExp(r'\s+'));
    return _ScheduledInfo(
      parts.isNotEmpty ? parts.first : '',
      parts.length > 1 ? parts.sublist(1).join(' ') : '',
    );
  }

  String _formatDate(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _ScheduledInfo {
  const _ScheduledInfo(this.date, this.time);

  final String date;
  final String time;
}

class _UpNextMetaChip extends StatelessWidget {
  const _UpNextMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFFFD600)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// Personal Agenda Timeline View
class _PersonalAgenda extends StatelessWidget {
  final Map<String, dynamic> ui;
  final List<Map<String, dynamic>> openItems;
  final List<Map<String, dynamic>> completedItems;
  final bool completedExpanded;
  final VoidCallback onToggleExpanded;
  final Function(Map<String, dynamic>) onTaskTap;
  final Function(String, bool) onTaskToggle;

  const _PersonalAgenda({
    required this.ui,
    required this.openItems,
    required this.completedItems,
    required this.completedExpanded,
    required this.onToggleExpanded,
    required this.onTaskTap,
    required this.onTaskToggle,
  });

  @override
  Widget build(BuildContext context) {
    final agendaTitle = ui['agenda_title']?.toString().trim() ?? 'Timeline';
    final completedLabel =
        ui['completed_label']?.toString().trim() ?? 'Completed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              size: 18,
              color: Color(0xFF705D00),
            ),
            const SizedBox(width: 8),
            Text(
              agendaTitle,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1C1C),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (openItems.isNotEmpty || completedItems.isNotEmpty) ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: openItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final task = openItems[index];
              return _TaskTile(
                task: task,
                onTap: () => onTaskTap(task),
                onToggle: (val) =>
                    onTaskToggle(task['id'].toString(), val ?? true),
              );
            },
          ),
          if (completedItems.isNotEmpty) ...[
            const SizedBox(height: 16),
            InkWell(
              onTap: onToggleExpanded,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8.0,
                  horizontal: 4,
                ),
                child: Row(
                  children: [
                    Icon(
                      completedExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      color: const Color(0xFF705D00),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$completedLabel (${completedItems.length})',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF705D00),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (completedExpanded) ...[
              const SizedBox(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: completedItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final task = completedItems[index];
                  return Opacity(
                    opacity: 0.5,
                    child: _TaskTile(
                      task: task,
                      isCompleted: true,
                      onTap: () => onTaskTap(task),
                      onToggle: (val) =>
                          onTaskToggle(task['id'].toString(), val ?? false),
                    ),
                  );
                },
              ),
            ],
          ],
        ],
      ],
    );
  }
}

// Polished Task Tile Component
class _TaskTile extends StatelessWidget {
  final Map<String, dynamic> task;
  final bool isCompleted;
  final VoidCallback onTap;
  final ValueChanged<bool?> onToggle;

  const _TaskTile({
    required this.task,
    this.isCompleted = false,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final title = task['title']?.toString() ?? '';
    final time = task['due_time']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEFEFEF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => onToggle(!isCompleted),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? const Color(0xFF705D00)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCompleted
                            ? const Color(0xFF705D00)
                            : const Color(0xFFCCCCCC),
                        width: 2,
                      ),
                    ),
                    child: isCompleted
                        ? const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      decoration: isCompleted
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      color: isCompleted
                          ? const Color(0xFF8C8E90)
                          : const Color(0xFF1A1C1C),
                    ),
                  ),
                ),
                if (time.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F5F7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      time,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF705D00),
                      ),
                    ),
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

// Analytics and Focus Side Panel
class _FocusLanes extends StatelessWidget {
  final Map<String, dynamic> ui;
  final int openCount;
  final int completedCount;

  const _FocusLanes({
    required this.ui,
    required this.openCount,
    required this.completedCount,
  });

  @override
  Widget build(BuildContext context) {
    final total = openCount + completedCount;
    final ratio = total > 0 ? (completedCount / total) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEFEFEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.donut_large_rounded,
                size: 18,
                color: Color(0xFF705D00),
              ),
              SizedBox(width: 8),
              Text(
                'Focus Summary',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$openCount Pending',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8C8E90),
                ),
              ),
              Text(
                '$completedCount Done',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF705D00),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: const Color(0xFFF0F1F3),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFFD600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Bottom Sheet: New Task Creator
class _PremiumTaskSheet extends StatefulWidget {
  const _PremiumTaskSheet({required this.ui});

  final Map<String, dynamic> ui;

  @override
  State<_PremiumTaskSheet> createState() => _PremiumTaskSheetState();
}

class _PremiumTaskSheetState extends State<_PremiumTaskSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _tagController = TextEditingController();
  final _attachmentController = TextEditingController();
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  bool _reminder = false;
  String _sensitivity = 'normal';

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _tagController.dispose();
    _attachmentController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final dueAt = _reminder
        ? DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute)
        : null;
    final notes = _buildNotes();

    Navigator.pop(context, {
      'title': title,
      'notes': notes,
      'due_at': dueAt,
      'priority': _priorityForSensitivity(_sensitivity),
      'estimated_minutes': null,
      'category': _tagController.text.trim(),
    });
  }

  String? _buildNotes() {
    final parts = <String>[];
    final description = _descriptionController.text.trim();
    final location = _locationController.text.trim();
    final attachments = _attachmentController.text.trim();
    if (description.isNotEmpty) parts.add(description);
    parts.add(
      'Scheduled: ${_dateLabel(_date)} ${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
    );
    parts.add('Reminder: ${_reminder ? 'yes' : 'no'}');
    if (location.isNotEmpty) parts.add('Location: $location');
    parts.add('Sensitivity: $_sensitivity');
    if (attachments.isNotEmpty) parts.add('Attachments: $attachments');
    return parts.isEmpty ? null : parts.join('\n');
  }

  int _priorityForSensitivity(String value) {
    return switch (value) {
      'low' => 0,
      'high' => 2,
      'sensitive' => 3,
      _ => 1,
    };
  }

  String _dateLabel(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.all(28),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1C1C),
              borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
            ),
            child: ListView(
              controller: scrollController,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Add Task',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),
                _TaskInput(
                  controller: _titleController,
                  label: 'Name',
                  icon: Icons.drive_file_rename_outline,
                ),
                const SizedBox(height: 12),
                _TaskInput(
                  controller: _descriptionController,
                  label: 'Description',
                  icon: Icons.notes_rounded,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _TaskPickerButton(
                        icon: Icons.event_rounded,
                        label: 'Date',
                        value: _dateLabel(_date),
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TaskPickerButton(
                        icon: Icons.schedule_rounded,
                        label: 'Time',
                        value: _time.format(context),
                        onTap: _pickTime,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile.adaptive(
                    value: _reminder,
                    onChanged: (value) => setState(() => _reminder = value),
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: const Color(0xFFFFD600),
                    title: const Text(
                      'Reminder',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                _TaskInput(
                  controller: _locationController,
                  label: 'Location',
                  icon: Icons.place_outlined,
                ),
                const SizedBox(height: 12),
                _TaskInput(
                  controller: _tagController,
                  label: 'Tag',
                  icon: Icons.sell_outlined,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _sensitivity,
                  dropdownColor: const Color(0xFF1A1C1C),
                  decoration: _darkInputDecoration(
                    label: 'Sensitivity',
                    icon: Icons.privacy_tip_outlined,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(
                      value: 'sensitive',
                      child: Text('Sensitive'),
                    ),
                  ],
                  style: const TextStyle(color: Colors.white),
                  onChanged: (value) {
                    if (value != null) setState(() => _sensitivity = value);
                  },
                ),
                const SizedBox(height: 12),
                _TaskInput(
                  controller: _attachmentController,
                  label: 'Image, document, or file references',
                  icon: Icons.attach_file_rounded,
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD600),
                      foregroundColor: const Color(0xFF221B00),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'Save Task',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TaskInput extends StatelessWidget {
  const _TaskInput({
    required this.controller,
    required this.label,
    required this.icon,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(
        fontFamily: 'Inter',
        color: Colors.white,
        fontSize: 15,
      ),
      decoration: _darkInputDecoration(label: label, icon: icon),
    );
  }
}

class _TaskPickerButton extends StatelessWidget {
  const _TaskPickerButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: InputDecorator(
        decoration: _darkInputDecoration(label: label, icon: icon),
        child: Text(
          value,
          style: const TextStyle(
            fontFamily: 'Inter',
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

InputDecoration _darkInputDecoration({
  required String label,
  required IconData icon,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: Colors.white70),
    labelStyle: TextStyle(
      fontFamily: 'Inter',
      color: Colors.white.withValues(alpha: 0.55),
    ),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.08),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFFFD600)),
    ),
  );
}

// Bottom Sheet: Suggest Plan Template Selector
class _SuggestPlanSheet extends StatelessWidget {
  final Map<String, dynamic> ui;

  const _SuggestPlanSheet({required this.ui});

  @override
  Widget build(BuildContext context) {
    final templates = ((ui['templates'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1C1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Suggest Day Plan',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          ...templates.map(
            (t) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                child: ListTile(
                  title: Text(
                    t['label']?.toString() ?? '',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Color(0xFFFFD600),
                  ),
                  onTap: () => Navigator.pop(context, t['id'].toString()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Bottom Sheet: Evening Review Component
class _PremiumReviewSheet extends StatelessWidget {
  final Map<String, dynamic> ui;
  final List openTasks;
  final VoidCallback onDefer;
  final VoidCallback onGoLive;

  const _PremiumReviewSheet({
    required this.ui,
    required this.openTasks,
    required this.onDefer,
    required this.onGoLive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1C1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Daily Summary',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'You have ${openTasks.length} unfinished task${openTasks.length == 1 ? '' : 's'} remaining.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onDefer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD600),
                    foregroundColor: const Color(0xFF221B00),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Defer Unfinished',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: onGoLive,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text('Live Mode'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
