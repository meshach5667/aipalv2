import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import 'notifications_screen.dart';
import 'companion_screen.dart';
import 'settings_screen.dart';
import 'task_detail_screen.dart';
import 'text_chat_screen.dart';
import 'today_screen.dart';

// Design Tokens & Color Palette
const Color _kAppBg = Color(0xFFF8FAFC);
const Color _kSurface = Colors.white;
const Color _kPrimary = Color(0xFF2563EB);
const Color _kTextPrimary = Color(0xFF0F172A);
const Color _kTextSecondary = Color(0xFF64748B);
const Color _kBorderColor = Color(0xFFE2E8F0);
const Color _kDanger = Color(0xFFEF4444);

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _tabs = [
    CompanionScreen(),
    TodayScreen(),
    NotificationsScreen(),
    SettingsScreen(),
  ];

  static const _titles = ['Companion', 'Today', 'Notifications', 'Settings'];

  static const _subtitles = [
    "What's on your mind today?",
    'Your plan, tasks, and reminders',
    'Updates, reminders and calendar activity',
    'Manage your AiPal experience',
  ];

  @override
  Widget build(BuildContext context) {
    final index = context.watch<AppState>().selectedTab;
    return AiPalShellScaffold(
      title: _titles[index],
      subtitle: _subtitles[index],
      onNotificationsTap: () => context.read<AppState>().goToTab(2),
      onProfileTap: () => context.read<AppState>().goToTab(3),
      body: IndexedStack(index: index, children: _tabs),
    );
  }
}

class AiPalShellScaffold extends StatelessWidget {
  const AiPalShellScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.onNotificationsTap,
    required this.onProfileTap,
    this.onSidebarTabTap,
    this.activeSidebarIndex,
    this.showDesktopSidebar = true,
    this.showMobileBottomNav = true,
  });

  final String title;
  final String subtitle;
  final Widget body;
  final VoidCallback onNotificationsTap;
  final VoidCallback onProfileTap;
  final ValueChanged<int>? onSidebarTabTap;
  final int? activeSidebarIndex;
  final bool showDesktopSidebar;
  final bool showMobileBottomNav;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final activeIndex =
        activeSidebarIndex ?? context.watch<AppState>().selectedTab;
    final tabTap =
        onSidebarTabTap ??
        (int index) => context.read<AppState>().goToTab(index);

    return Scaffold(
      backgroundColor: _kAppBg,
      body: Row(
        children: [
          if (isDesktop && showDesktopSidebar)
            _DesktopSidebar(activeIndex: activeIndex, onTabTap: tabTap),
          Expanded(
            child: Column(
              children: [
                _TopHeader(
                  title: title,
                  subtitle: subtitle,
                  onNotificationsTap: onNotificationsTap,
                  onProfileTap: onProfileTap,
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop || !showMobileBottomNav
          ? null
          : _MobileBottomNav(currentIndex: activeIndex, onTabTap: tabTap),
    );
  }
}

class _DesktopSidebar extends StatefulWidget {
  const _DesktopSidebar({required this.activeIndex, required this.onTabTap});

  final int activeIndex;
  final ValueChanged<int> onTabTap;

  @override
  State<_DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends State<_DesktopSidebar> {
  bool _companionOpen = true;
  bool _todayOpen = true;

  Future<void> _confirmDeleteConversation(
    BuildContext context,
    AppState state,
    String sessionId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        title: const Text(
          'Delete conversation?',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: _kTextPrimary,
          ),
        ),
        content: const Text(
          'This will remove the conversation thread from your sidebar.',
          style: TextStyle(color: _kTextSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _kTextSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kDanger,
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
    if (ok == true && mounted) {
      await state.deleteConversationSession(sessionId);
    }
  }

  Future<void> _editTask(
    BuildContext context,
    AppState state,
    Map<String, dynamic> task,
  ) async {
    final titleController = TextEditingController(
      text: task['title']?.toString() ?? '',
    );
    final notesController = TextEditingController(
      text: task['notes']?.toString() ?? '',
    );
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TaskEditorSheet(
        titleController: titleController,
        notesController: notesController,
      ),
    );
    titleController.dispose();
    notesController.dispose();
    if (result != null && mounted) {
      await state.updateTask(
        task['id'] as int,
        title: result['title']?.trim(),
        notes: result['notes']?.trim(),
      );
    }
  }

  void _openTaskDetail(BuildContext context, Map<String, dynamic> task) {
    final taskId = task['id']?.toString();
    if (taskId == null || taskId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: taskId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.activeIndex;
    final state = context.watch<AppState>();
    final sections = state.todayView?['sections'] as Map<String, dynamic>?;
    final companionSessions = state.conversationSessions;
    final openTasks = state.openTasksForReview.isNotEmpty
        ? state.openTasksForReview
        : [
            ...((sections?['now'] as List?)?.cast<Map<String, dynamic>>() ??
                []),
            ...((sections?['upcoming'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                []),
          ];

    final userName = state.wakeName;

    return Container(
      width: 270,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(
          right: BorderSide(color: _kBorderColor, width: 0.8),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brand Header Logo
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [_kPrimary, Color(0xFF7C3AED)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _kPrimary.withValues(alpha: 0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AiPal',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: _kTextPrimary,
                              ),
                            ),
                            Text(
                              'Quiet Intelligence',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: _kTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Primary Navigation Items
                    _SidebarItem(
                      index: 0,
                      currentIndex: index,
                      icon: Icons.forum_outlined,
                      activeIcon: Icons.forum_rounded,
                      label: 'Companion',
                      onTap: widget.onTabTap,
                    ),
                    const SizedBox(height: 6),
                    _SidebarItem(
                      index: 1,
                      currentIndex: index,
                      icon: Icons.calendar_today_outlined,
                      activeIcon: Icons.calendar_today_rounded,
                      label: 'Today',
                      onTap: widget.onTabTap,
                    ),
                    const SizedBox(height: 6),
                    _SidebarItem(
                      index: 2,
                      currentIndex: index,
                      icon: Icons.notifications_none_rounded,
                      activeIcon: Icons.notifications_rounded,
                      label: 'Notifications',
                      onTap: widget.onTabTap,
                    ),
                    const SizedBox(height: 6),
                    _SidebarItem(
                      index: 3,
                      currentIndex: index,
                      icon: Icons.settings_outlined,
                      activeIcon: Icons.settings_rounded,
                      label: 'Settings',
                      onTap: widget.onTabTap,
                    ),

                    const SizedBox(height: 24),
                    const Divider(color: _kBorderColor, height: 1),
                    const SizedBox(height: 18),

                    // Contextual Threads & Tasks Accordions
                    if (index == 0)
                      _SidebarAccordion(
                        title: 'Companion Threads',
                        subtitle: 'Resume or manage conversations',
                        expanded: _companionOpen,
                        onChanged: (v) => setState(() => _companionOpen = v),
                        child: companionSessions.isEmpty
                            ? const _SidebarEmptyHint(
                                text: 'No saved conversations yet.',
                              )
                            : Column(
                                children: companionSessions.map((session) {
                                  final sessionId =
                                      session['session_id']?.toString() ?? '';
                                  return _ThreadTile(
                                    title: session['preview']
                                                ?.toString()
                                                .isNotEmpty ==
                                            true
                                        ? session['preview'].toString()
                                        : 'Conversation',
                                    meta:
                                        '${session['turn_count']?.toString() ?? '0'} turns',
                                    onOpen: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => TextChatScreen(
                                            sessionId: sessionId,
                                          ),
                                        ),
                                      );
                                    },
                                    onDelete: () => _confirmDeleteConversation(
                                      context,
                                      state,
                                      sessionId,
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                    if (index == 1)
                      _SidebarAccordion(
                        title: 'Today Tasks',
                        subtitle: 'Edit or review scheduled work',
                        expanded: _todayOpen,
                        onChanged: (v) => setState(() => _todayOpen = v),
                        child: openTasks.isEmpty
                            ? const _SidebarEmptyHint(
                                text: 'No open tasks for today.',
                              )
                            : Column(
                                children: openTasks.take(8).map((task) {
                                  return _TaskTile(
                                    title: task['title']?.toString() ??
                                        'Untitled task',
                                    meta: task['due_label']?.toString() ??
                                        task['status']?.toString() ??
                                        'planned',
                                    onOpen: () => _openTaskDetail(context, task),
                                    onEdit: () => _editTask(context, state, task),
                                    onDelete: () async {
                                      final id = task['id'] as int?;
                                      if (id != null) {
                                        final messenger =
                                            ScaffoldMessenger.of(context);
                                        await state.deleteTask(id);
                                        if (mounted) {
                                          messenger.showSnackBar(
                                            const SnackBar(
                                              content: Text('Task deleted'),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  );
                                }).toList(),
                              ),
                      ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kAppBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _kBorderColor),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kPrimary.withValues(alpha: 0.1),
                        border: Border.all(
                          color: _kPrimary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.person_rounded,
                          color: _kPrimary,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _kTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Pro Plan',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: _kTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });

  final int index;
  final int currentIndex;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final active = index == currentIndex;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: active ? _kPrimary.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onTap(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(
                  active ? activeIcon : icon,
                  size: 20,
                  color: active ? _kPrimary : _kTextSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? _kPrimary : _kTextPrimary,
                  ),
                ),
                if (active) ...[
                  const Spacer(),
                  Container(
                    width: 5,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _kPrimary,
                      borderRadius: BorderRadius.circular(4),
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

class _SidebarAccordion extends StatelessWidget {
  const _SidebarAccordion({
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onChanged,
    required this.child,
  });

  final String title;
  final String subtitle;
  final bool expanded;
  final ValueChanged<bool> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          initiallyExpanded: expanded,
          onExpansionChanged: onChanged,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          collapsedIconColor: _kTextSecondary,
          iconColor: _kPrimary,
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _kTextPrimary,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: _kTextSecondary,
            ),
          ),
          children: [child],
        ),
      ),
    );
  }
}

class _SidebarEmptyHint extends StatelessWidget {
  const _SidebarEmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kAppBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderColor),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: _kTextSecondary,
        ),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.title,
    required this.meta,
    required this.onOpen,
    required this.onDelete,
  });

  final String title;
  final String meta;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kAppBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _kTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: _kTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.close_rounded, size: 16),
            color: _kTextSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Delete thread',
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.title,
    required this.meta,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final String meta;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _kAppBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _kTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: _kTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 16),
            color: _kTextSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            color: _kDanger,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: _kBorderColor,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _TaskEditorSheet extends StatelessWidget {
  const _TaskEditorSheet({
    required this.titleController,
    required this.notesController,
  });

  final TextEditingController titleController;
  final TextEditingController notesController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
              const _SheetHandle(),
              const SizedBox(height: 16),
              const Text(
                'Edit Task',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _kTextPrimary,
                ),
              ),
              const SizedBox(height: 18),
              _EditorInput(
                controller: titleController,
                hint: 'Task title',
                icon: Icons.task_alt_rounded,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              _EditorInput(
                controller: notesController,
                hint: 'Notes or details',
                icon: Icons.notes_rounded,
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context, <String, String>{
                      'title': titleController.text.trim(),
                      'notes': notesController.text.trim(),
                    });
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save Changes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
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

class _EditorInput extends StatelessWidget {
  const _EditorInput({
    required this.controller,
    required this.hint,
    required this.icon,
    this.autofocus = false,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool autofocus;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 14, color: _kTextPrimary),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: _kPrimary, size: 20),
        hintText: hint,
        hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 14),
        filled: true,
        fillColor: _kAppBg,
        contentPadding: const EdgeInsets.all(14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _kBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _kPrimary, width: 1.8),
        ),
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.title,
    required this.subtitle,
    required this.onNotificationsTap,
    required this.onProfileTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onNotificationsTap;
  final VoidCallback onProfileTap;

  String _dynamicGreeting(String userName) {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning, $userName';
    if (hour < 17) return 'Good Afternoon, $userName';
    return 'Good Evening, $userName';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final userName = state.wakeName;
    final hasUnreadNotifs = state.hasUnreadNotifications;

    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: _kBorderColor, width: 0.8),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title == 'Companion' ? _dynamicGreeting(userName) : title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: _kTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _kTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Notification Button with Dot Indicator
            Stack(
              clipBehavior: Clip.none,
              children: [
                _HeaderIconButton(
                  icon: Icons.notifications_none_rounded,
                  onTap: onNotificationsTap,
                ),
                if (hasUnreadNotifs)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: _kPrimary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),

            // Profile Button
            _HeaderIconButton(
              icon: Icons.person_outline_rounded,
              onTap: onProfileTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kAppBg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _kBorderColor),
          ),
          child: Icon(icon, color: _kTextPrimary, size: 20),
        ),
      ),
    );
  }
}

class _MobileBottomNav extends StatelessWidget {
  const _MobileBottomNav({
    required this.currentIndex,
    required this.onTabTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTabTap;

  @override
  Widget build(BuildContext context) {
    final navItems = [
      {'icon': Icons.forum_outlined, 'activeIcon': Icons.forum_rounded, 'label': 'Companion'},
      {'icon': Icons.calendar_today_outlined, 'activeIcon': Icons.calendar_today_rounded, 'label': 'Today'},
      {'icon': Icons.notifications_none_rounded, 'activeIcon': Icons.notifications_rounded, 'label': 'Alerts'},
      {'icon': Icons.settings_outlined, 'activeIcon': Icons.settings_rounded, 'label': 'Settings'},
    ];

    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: _kBorderColor, width: 0.8),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(navItems.length, (i) {
            final active = currentIndex == i;
            final item = navItems[i];

            return InkWell(
              onTap: () => onTabTap(i),
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? _kPrimary.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      active ? (item['activeIcon'] as IconData) : (item['icon'] as IconData),
                      color: active ? _kPrimary : _kTextSecondary,
                      size: 22,
                    ),
                    if (active) ...[
                      const SizedBox(width: 8),
                      Text(
                        item['label'] as String,
                        style: const TextStyle(
                          color: _kPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}