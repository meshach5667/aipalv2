import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import 'companion_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'task_detail_screen.dart';
import 'text_chat_screen.dart';
import 'today_screen.dart';

/// Design System Color Palette inspired by Luminous Intelligence
class AiPalTheme {
  static const Color primary = Color(0xFF705D00);
  static const Color primaryContainer = Color(0xFFFFD600);
  static const Color onPrimaryContainer = Color(0xFF705D00);
  static const Color surfaceContainerLow = Color(0xFFF3F3F3);
  static const Color surfaceContainerHigh = Color(0xFFE8E8E8);
  static const Color surfaceContainerHighest = Color(0xFFE2E2E2);
  static const Color background = Color(0xFFF9F9F9);
  static const Color onSurface = Color(0xFF1A1C1C);
  static const Color onSurfaceVariant = Color(0xFF4D4632);
  static const Color outlineVariant = Color(0xFFD0C6AB);
  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
}

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
      backgroundColor: AiPalTheme.background,
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

/// Premium Clean Top App Bar
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: AiPalTheme.background,
        border: Border(
          bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AiPalTheme.primary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AiPalTheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onNotificationsTap,
              icon: const Icon(Icons.notifications_outlined),
              color: AiPalTheme.onSurface,
              tooltip: 'Notifications',
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onProfileTap,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AiPalTheme.surfaceContainerHigh,
                    width: 2,
                  ),
                  color: AiPalTheme.surfaceContainerLow,
                ),
                child: const ClipOval(
                  child: Icon(
                    Icons.person_rounded,
                    color: AiPalTheme.onSurfaceVariant,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Desktop Navigation Sidebar
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete conversation?'),
        content: const Text(
          'This will remove the conversation thread from your sidebar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AiPalTheme.error,
              foregroundColor: AiPalTheme.onError,
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: taskId)));
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

    return Container(
      width: 270,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: AiPalTheme.background,
        border: Border(
          right: BorderSide(color: Color(0xFFEEEEEE), width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.security_rounded,
                          color: AiPalTheme.onSurface,
                          size: 22,
                        ),
                        Spacer(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'AiPal',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.0,
                        color: AiPalTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Quiet Intelligence',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AiPalTheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),

                    _SidebarItem(
                      index: 0,
                      currentIndex: index,
                      icon: Icons.smart_toy_rounded,
                      label: 'Companion',
                      onTap: widget.onTabTap,
                    ),
                    const SizedBox(height: 6),
                    _SidebarItem(
                      index: 1,
                      currentIndex: index,
                      icon: Icons.calendar_today_rounded,
                      label: 'Today',
                      onTap: widget.onTabTap,
                    ),
                    const SizedBox(height: 6),
                    _SidebarItem(
                      index: 2,
                      currentIndex: index,
                      icon: Icons.notifications_none_rounded,
                      label: 'Alerts',
                      onTap: widget.onTabTap,
                    ),
                    const SizedBox(height: 6),
                    _SidebarItem(
                      index: 3,
                      currentIndex: index,
                      icon: Icons.settings_rounded,
                      label: 'Settings',
                      onTap: widget.onTabTap,
                    ),

                    const SizedBox(height: 24),
                    if (index == 0)
                      _SidebarAccordion(
                        title: 'Companion Threads',
                        subtitle: 'Resume or remove threads',
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
                                    title:
                                        session['preview']
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
                        subtitle: 'Edit or manage open work',
                        expanded: _todayOpen,
                        onChanged: (v) => setState(() => _todayOpen = v),
                        child: openTasks.isEmpty
                            ? const _SidebarEmptyHint(
                                text: 'No open tasks to edit.',
                              )
                            : Column(
                                children: openTasks.take(8).map((task) {
                                  return _TaskTile(
                                    title:
                                        task['title']?.toString() ??
                                        'Untitled task',
                                    meta:
                                        task['due_label']?.toString() ??
                                        task['status']?.toString() ??
                                        'planned',
                                    onOpen: () =>
                                        _openTaskDetail(context, task),
                                    onEdit: () =>
                                        _editTask(context, state, task),
                                    onDelete: () async {
                                      final id = task['id'] as int?;
                                      if (id != null) {
                                        final messenger = ScaffoldMessenger.of(
                                          context,
                                        );
                                        await state.deleteTask(id);
                                        if (mounted) {
                                          messenger.showSnackBar(
                                            const SnackBar(
                                              content: Text('Task deleted'),
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
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AiPalTheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: AiPalTheme.surfaceContainerHigh,
                    child: Icon(
                      Icons.person,
                      color: AiPalTheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'User Session',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AiPalTheme.onSurface,
                          ),
                        ),
                        Text(
                          'Active',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: AiPalTheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
    required this.label,
    required this.onTap,
  });

  final int index;
  final int currentIndex;
  final IconData icon;
  final String label;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final active = index == currentIndex;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () => onTap(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? AiPalTheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: active
                    ? AiPalTheme.onPrimaryContainer
                    : AiPalTheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active
                      ? AiPalTheme.onPrimaryContainer
                      : AiPalTheme.onSurfaceVariant,
                ),
              ),
            ],
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
    return Container(
      decoration: BoxDecoration(
        color: AiPalTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onChanged(!expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AiPalTheme.onSurface,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: AiPalTheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AiPalTheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: 10, right: 10, bottom: 10),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _SidebarEmptyHint extends StatelessWidget {
  const _SidebarEmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: AiPalTheme.onSurfaceVariant,
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
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        dense: true,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          meta,
          style: const TextStyle(fontFamily: 'Inter', fontSize: 10),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 16),
          onPressed: onDelete,
          splashRadius: 16,
        ),
        onTap: onOpen,
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
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        dense: true,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          meta,
          style: const TextStyle(fontFamily: 'Inter', fontSize: 10),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              onPressed: onEdit,
              splashRadius: 16,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              onPressed: onDelete,
              splashRadius: 16,
            ),
          ],
        ),
        onTap: onOpen,
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
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Edit Task',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AiPalTheme.primaryContainer,
                    foregroundColor: AiPalTheme.onPrimaryContainer,
                  ),
                  onPressed: () {
                    Navigator.pop(context, {
                      'title': titleController.text,
                      'notes': notesController.text,
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating Mobile Bottom Navigation Bar styled per reference HTML
class _MobileBottomNav extends StatelessWidget {
  const _MobileBottomNav({
    required this.currentIndex,
    required this.onTabTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTabTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AiPalTheme.background,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _MobileNavItem(
              index: 0,
              currentIndex: currentIndex,
              icon: Icons.smart_toy_rounded,
              label: 'Companion',
              onTap: onTabTap,
            ),
            _MobileNavItem(
              index: 1,
              currentIndex: currentIndex,
              icon: Icons.calendar_today_rounded,
              label: 'Today',
              onTap: onTabTap,
            ),
            _MobileNavItem(
              index: 2,
              currentIndex: currentIndex,
              icon: Icons.notifications_none_rounded,
              label: 'Alerts',
              onTap: onTabTap,
            ),
            _MobileNavItem(
              index: 3,
              currentIndex: currentIndex,
              icon: Icons.settings_rounded,
              label: 'Settings',
              onTap: onTabTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileNavItem extends StatelessWidget {
  const _MobileNavItem({
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final int index;
  final int currentIndex;
  final IconData icon;
  final String label;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final active = index == currentIndex;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AiPalTheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: active
                  ? AiPalTheme.onPrimaryContainer
                  : AiPalTheme.onSurfaceVariant,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active
                    ? AiPalTheme.onPrimaryContainer
                    : AiPalTheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}