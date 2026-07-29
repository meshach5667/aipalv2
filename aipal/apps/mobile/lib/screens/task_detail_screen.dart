import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import 'goal_reflection_detail_screens.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  // Brand Yellow Palette Constants
  static const Color yellowPrimary = Color(0xFFFFD600);
  static const Color yellowOnPrimary = Color(0xFF221B00);
  static const Color yellowContainer = Color(0xFFFFE170);
  static const Color yellowSurface = Color(0xFFFFFDE7);

  Future<Map<String, dynamic>>? _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = _load();
  }

  Future<Map<String, dynamic>> _load() =>
      context.read<AppState>().api.getTaskDetail(widget.taskId);

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _detailFuture = _load();
    });
  }

  Future<void> _editTask(Map<String, dynamic> task) async {
    final appState = context.read<AppState>();

    DateTime? initialDueDate;
    if (task['due_at'] != null) {
      initialDueDate = DateTime.tryParse(task['due_at'].toString())?.toLocal();
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TaskEditorSheet(
        initialTitle: task['title']?.toString() ?? '',
        initialNotes:
            task['notes']?.toString() ?? task['description']?.toString() ?? '',
        initialDueDate: initialDueDate,
        initialPriority: task['priority']?.toString() ?? 'medium',
      ),
    );

    if (result == null || !mounted) return;

    final numericId = _taskNumericId(task);
    if (numericId != null) {
      await appState.updateTask(
        numericId,
        title: result['title']?.toString(),
        notes: result['notes']?.toString(),
        dueAt: result['due_at'] as DateTime?,
        priority: result['priority'] as int?,
      );
    } else {
      await appState.api.updateTodayItem(task['id'].toString(), {
        'title': result['title']?.toString(),
        'description': result['notes']?.toString(),
        'priority': result['priority']?.toString(),
        if (result['due_at'] != null)
          'due_at': (result['due_at'] as DateTime).toUtc().toIso8601String(),
        if (result['priority'] != null)
          'priority': _priorityLabel(result['priority'] as int),
      });
      await appState.refreshTodayView();
    }

    if (!mounted) return;
    await _refresh();
  }

  Future<void> _toggleComplete(Map<String, dynamic> task) async {
    final appState = context.read<AppState>();
    final isDone = _isTaskDone(task);
    if (!isDone) {
      final confirmed = await _confirmTaskDone();
      if (confirmed != true) return;
    }
    final numericId = _taskNumericId(task);
    if (numericId != null) {
      await appState.updateTask(numericId, status: isDone ? 'planned' : 'done');
    } else {
      await appState.toggleItemComplete(task['id'].toString(), !isDone);
    }
    if (!mounted) return;
    await _refresh();
  }

  Future<bool?> _confirmTaskDone() {
    var checked = false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: Colors.white,
          title: const Text(
            'Confirm task completion',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontFamily: 'Manrope',
            ),
          ),
          content: CheckboxListTile(
            value: checked,
            activeColor: yellowOnPrimary,
            fillColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.selected) ? yellowPrimary : null,
            ),
            onChanged: (value) => setDialogState(() {
              checked = value ?? false;
            }),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I have finished this task.',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: yellowPrimary,
                foregroundColor: yellowOnPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: checked ? () => Navigator.pop(ctx, true) : null,
              child: const Text(
                'Mark Done',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addSubtask(Map<String, dynamic> task) async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SubtaskEditorSheet(),
    );

    final title = result?['title']?.trim() ?? '';
    if (title.isEmpty || !mounted) return;

    final parentTaskId = _taskNumericId(task);
    if (parentTaskId == null) return;

    await context.read<AppState>().createTask(
      title,
      notes: result?['notes']?.trim(),
      goalId: task['goal_id']?.toString(),
      parentTaskId: parentTaskId,
    );

    if (!mounted) return;
    await _refresh();
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    final appState = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        title: const Text(
          'Delete task?',
          style: TextStyle(fontWeight: FontWeight.w800, fontFamily: 'Manrope'),
        ),
        content: const Text(
          'This action removes the task permanently.',
          style: TextStyle(color: Color(0xFF575C6B), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF575C6B)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final numericId = _taskNumericId(task);
    if (numericId != null) {
      await appState.deleteTask(numericId);
    } else {
      await appState.cancelTodayItem(task['id'].toString());
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _linkGoal(Map<String, dynamic>? task) async {
    final numericId = task == null ? null : _taskNumericId(task);
    if (numericId == null) return;
    final appState = context.read<AppState>();
    final goals = await appState.api.listGoals();
    if (!mounted) return;

    final selected = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GoalPickerSheet(
        goals: goals.cast<Map<String, dynamic>>(),
        currentGoalId: task?['goal_id']?.toString(),
      ),
    );

    if (selected == null) return;
    await appState.updateTask(
      numericId,
      goalId: selected.isEmpty ? null : selected,
    );
    if (!mounted) return;
    await _refresh();
  }

  void _openGoal(Map<String, dynamic> goal) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GoalDetailScreen(goalId: goal['id'].toString()),
      ),
    );
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return 'Flexible';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} · $hour:$minute $period';
    } catch (_) {
      return raw;
    }
  }

  int? _taskNumericId(Map<String, dynamic> task) {
    final taskId = task['task_id'] ?? task['id'];
    if (taskId is int) return taskId;
    return int.tryParse(taskId?.toString() ?? '');
  }

  bool _isTaskDone(Map<String, dynamic> task) {
    final status = task['status']?.toString();
    return status == 'done' || status == 'completed';
  }

  String _priorityLabel(int value) {
    return switch (value) {
      0 => 'low',
      2 => 'high',
      3 => 'urgent',
      _ => 'medium',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF111827),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const Text(
          'Task Details',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF374151)),
          ),
          FutureBuilder<Map<String, dynamic>>(
            future: _detailFuture,
            builder: (context, snapshot) {
              final raw = snapshot.data;
              final task = ((raw?['task'] as Map?) ?? raw)
                  ?.cast<String, dynamic>();
              if (task == null) return const SizedBox.shrink();
              return IconButton(
                onPressed: () => _deleteTask(task),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFDC2626),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _detailFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final task = ((data?['task'] as Map?) ?? data)
                ?.cast<String, dynamic>();
            final goal = (data?['linked_goal'] as Map?)
                ?.cast<String, dynamic>();
            final subtasks =
                (data?['subtasks'] as List?)?.cast<Map<String, dynamic>>() ??
                [];
            final isDone = task == null ? false : _isTaskDone(task);

            if (snapshot.connectionState == ConnectionState.waiting &&
                task == null) {
              return const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: yellowPrimary,
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              color: yellowOnPrimary,
              backgroundColor: yellowPrimary,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  // Primary Task Card
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFFF0F0F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(8),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badges Row
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _YellowBadge(
                              label: (task?['status']?.toString() ?? 'planned')
                                  .toUpperCase(),
                              isHighContrast: true,
                            ),
                            _YellowBadge(
                              label:
                                  'Priority: ${(task?['priority']?.toString() ?? 'medium').toUpperCase()}',
                            ),
                            if ((task?['due_at']?.toString() ?? '').isNotEmpty)
                              _YellowBadge(
                                label: _formatDate(task?['due_at']?.toString()),
                                icon: Icons.schedule_rounded,
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Title Text
                        Text(
                          task?['title']?.toString() ?? 'Untitled Task',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                            color: isDone
                                ? const Color(0xFF9CA3AF)
                                : const Color(0xFF111827),
                            decoration: isDone
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Notes Header
                        const Text(
                          'NOTES & DESCRIPTION',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Notes Content
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: yellowSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: yellowContainer.withAlpha(120),
                            ),
                          ),
                          child: Text(
                            (task?['notes']?.toString().isNotEmpty == true)
                                ? task!['notes'].toString()
                                : (task?['description']
                                          ?.toString()
                                          .isNotEmpty ==
                                      true)
                                ? task!['description'].toString()
                                : 'No details or notes added yet.',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color:
                                  (task?['notes']?.toString().isNotEmpty ==
                                          true ||
                                      task?['description']
                                              ?.toString()
                                              .isNotEmpty ==
                                          true)
                                  ? const Color(0xFF221B00)
                                  : const Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Actions Row
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  side: const BorderSide(
                                    color: yellowPrimary,
                                    width: 1.5,
                                  ),
                                  backgroundColor: yellowContainer.withAlpha(
                                    40,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: task == null
                                    ? null
                                    : () => _editTask(task),
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                  color: yellowOnPrimary,
                                ),
                                label: const Text(
                                  'Edit Details',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: yellowOnPrimary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  side: const BorderSide(
                                    color: Color(0xFFE5E7EB),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed:
                                    task == null || _taskNumericId(task) == null
                                    ? null
                                    : () => _linkGoal(task),
                                icon: Icon(
                                  goal == null
                                      ? Icons.add_link_rounded
                                      : Icons.link_rounded,
                                  size: 18,
                                  color: const Color(0xFF374151),
                                ),
                                label: Text(
                                  goal == null ? 'Link Goal' : 'Change Goal',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF374151),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Linked Goal Section
                  _SectionHeader(
                    title: 'Linked Goal',
                    badgeCount: goal == null ? 0 : 1,
                  ),
                  const SizedBox(height: 12),
                  if (goal == null)
                    const _EmptyCard(text: 'No goal linked to this task yet.')
                  else
                    _GoalPreviewCard(
                      goal: goal,
                      onTap: () => _openGoal(goal),
                      onClear: task == null ? null : () => _linkGoal(task),
                    ),
                  const SizedBox(height: 28),

                  // Subtasks Section Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionHeader(
                        title: 'Subtasks',
                        badgeCount: subtasks.length,
                      ),
                      if (task != null && _taskNumericId(task) != null)
                        TextButton.icon(
                          onPressed: () => _addSubtask(task),
                          icon: const Icon(
                            Icons.add_circle_outline_rounded,
                            size: 18,
                            color: yellowOnPrimary,
                          ),
                          label: const Text(
                            'Add Subtask',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: yellowOnPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (subtasks.isEmpty)
                    const _EmptyCard(text: 'No subtasks created for this task.')
                  else
                    ...subtasks.map((subtask) => _SubtaskCard(task: subtask)),
                ],
              ),
            );
          },
        ),
      ),

      // Bottom Completion Toggle Action Bar
      bottomSheet: FutureBuilder<Map<String, dynamic>>(
        future: _detailFuture,
        builder: (context, snapshot) {
          final raw = snapshot.data;
          final task = ((raw?['task'] as Map?) ?? raw)?.cast<String, dynamic>();
          if (task == null) return const SizedBox.shrink();

          final isDone = _isTaskDone(task);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: const Border(top: BorderSide(color: Color(0xFFF0F0F0))),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 16,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDone
                        ? const Color(0xFF10B981)
                        : yellowPrimary,
                    foregroundColor: isDone ? Colors.white : yellowOnPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () => _toggleComplete(task),
                  icon: Icon(
                    isDone
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 22,
                  ),
                  label: Text(
                    isDone ? 'Mark as Open' : 'Mark as Complete',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: isDone ? Colors.white : yellowOnPrimary,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Editable Task Modal Bottom Sheet
class _TaskEditorSheet extends StatefulWidget {
  const _TaskEditorSheet({
    required this.initialTitle,
    required this.initialNotes,
    this.initialDueDate,
    required this.initialPriority,
  });

  final String initialTitle;
  final String initialNotes;
  final DateTime? initialDueDate;
  final String initialPriority;

  @override
  State<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<_TaskEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  DateTime? _selectedDueDate;
  late String _selectedPriority;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _notesController = TextEditingController(text: widget.initialNotes);
    _selectedDueDate = widget.initialDueDate;
    _selectedPriority = _normalizePriority(widget.initialPriority);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _TaskDetailScreenState.yellowPrimary,
              onPrimary: _TaskDetailScreenState.yellowOnPrimary,
              surface: Colors.white,
              onSurface: Color(0xFF111827),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDueDate ?? DateTime.now()),
    );

    if (!mounted) return;

    setState(() {
      _selectedDueDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime?.hour ?? 12,
        pickedTime?.minute ?? 0,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottomInset + 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Edit Task',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 20),

            // Title Field
            TextField(
              controller: _titleController,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              decoration: _inputDecoration(
                'Task Title',
                Icons.task_alt_rounded,
              ),
            ),
            const SizedBox(height: 16),

            // Notes Field
            TextField(
              controller: _notesController,
              maxLines: 3,
              style: const TextStyle(fontSize: 14),
              decoration: _inputDecoration(
                'Notes & Details',
                Icons.notes_rounded,
              ),
            ),
            const SizedBox(height: 16),

            // Options Row (Due Date & Priority)
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDueDate,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 18,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedDueDate == null
                                  ? 'Set Due Date'
                                  : '${_selectedDueDate!.month}/${_selectedDueDate!.day}/${_selectedDueDate!.year}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _selectedDueDate == null
                                    ? const Color(0xFF9CA3AF)
                                    : const Color(0xFF111827),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Priority Dropdown
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedPriority.toLowerCase(),
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        items: ['low', 'medium', 'high'].map((p) {
                          return DropdownMenuItem(
                            value: p,
                            child: Text(
                              p.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedPriority = val);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Save Action Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _TaskDetailScreenState.yellowPrimary,
                  foregroundColor: _TaskDetailScreenState.yellowOnPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  final text = _titleController.text.trim();
                  if (text.isEmpty) return;
                  Navigator.pop(context, {
                    'title': text,
                    'notes': _notesController.text.trim(),
                    'due_at': _selectedDueDate,
                    'priority': _priorityValue(_selectedPriority),
                  });
                },
                child: const Text(
                  'Save Changes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF6B7280), size: 20),
      labelStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: _TaskDetailScreenState.yellowPrimary,
          width: 2,
        ),
      ),
    );
  }

  String _normalizePriority(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      '0' || 'low' => 'low',
      '2' || 'high' => 'high',
      '3' || 'urgent' => 'high',
      _ => 'medium',
    };
  }

  int _priorityValue(String value) {
    return switch (value) {
      'low' => 0,
      'high' => 2,
      _ => 1,
    };
  }
}

// Subtask Creation Sheet
class _SubtaskEditorSheet extends StatefulWidget {
  const _SubtaskEditorSheet();

  @override
  State<_SubtaskEditorSheet> createState() => _SubtaskEditorSheetState();
}

class _SubtaskEditorSheetState extends State<_SubtaskEditorSheet> {
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottomInset + 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'New Subtask',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText: 'Subtask title...',
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            decoration: InputDecoration(
              hintText: 'Notes (optional)',
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _TaskDetailScreenState.yellowPrimary,
                foregroundColor: _TaskDetailScreenState.yellowOnPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () {
                Navigator.pop(context, {
                  'title': _titleController.text,
                  'notes': _notesController.text,
                });
              },
              child: const Text(
                'Add Subtask',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Goal Selector Sheet
class _GoalPickerSheet extends StatelessWidget {
  const _GoalPickerSheet({required this.goals, this.currentGoalId});

  final List<Map<String, dynamic>> goals;
  final String? currentGoalId;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Link to Goal',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (currentGoalId != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: const Text(
                    'Remove Link',
                    style: TextStyle(color: Color(0xFFDC2626)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: goals.length,
              itemBuilder: (context, index) {
                final g = goals[index];
                final id = g['id']?.toString();
                final isSelected = id == currentGoalId;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _TaskDetailScreenState.yellowContainer
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? _TaskDetailScreenState.yellowPrimary
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: ListTile(
                    onTap: () => Navigator.pop(context, id),
                    leading: Icon(
                      Icons.flag_rounded,
                      color: isSelected
                          ? _TaskDetailScreenState.yellowOnPrimary
                          : const Color(0xFF6B7280),
                    ),
                    title: Text(
                      g['title']?.toString() ?? 'Goal',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(g['life_area']?.toString() ?? ''),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: _TaskDetailScreenState.yellowOnPrimary,
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// UI Components
class _YellowBadge extends StatelessWidget {
  const _YellowBadge({
    required this.label,
    this.icon,
    this.isHighContrast = false,
  });

  final String label;
  final IconData? icon;
  final bool isHighContrast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isHighContrast
            ? _TaskDetailScreenState.yellowPrimary
            : _TaskDetailScreenState.yellowContainer.withAlpha(150),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: _TaskDetailScreenState.yellowOnPrimary),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _TaskDetailScreenState.yellowOnPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.badgeCount});

  final String title;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _TaskDetailScreenState.yellowContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            badgeCount.toString(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _TaskDetailScreenState.yellowOnPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _GoalPreviewCard extends StatelessWidget {
  const _GoalPreviewCard({
    required this.goal,
    required this.onTap,
    required this.onClear,
  });

  final Map<String, dynamic> goal;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _TaskDetailScreenState.yellowContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.flag_rounded,
                    color: _TaskDetailScreenState.yellowOnPrimary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal['title']?.toString() ?? 'Linked Goal',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        goal['life_area']?.toString() ?? 'Goal',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onClear != null)
                  TextButton(
                    onPressed: onClear,
                    child: const Text(
                      'Unlink',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubtaskCard extends StatelessWidget {
  const _SubtaskCard({required this.task});

  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final isDone = task['status']?.toString() == 'done';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              isDone ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 20,
              color: isDone
                  ? const Color(0xFF10B981)
                  : _TaskDetailScreenState.yellowOnPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task['title']?.toString() ?? 'Untitled subtask',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDone
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF111827),
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (task['notes']?.toString().isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    task['notes'].toString(),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }
}
