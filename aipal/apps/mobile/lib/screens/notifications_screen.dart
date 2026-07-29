import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/web_title.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // Brand Color Palette Constants
  static const Color yellowPrimary = Color(0xFFFFD600);
  static const Color yellowOnPrimary = Color(0xFF221B00);
  static const Color yellowContainer = Color(0xFFFFE170);
  static const Color surfaceBackground = Color(0xFFFAFAFA);
  static const Color cardBorder = Color(0xFFF0F0F0);

  Future<List<Map<String, dynamic>>>? _notificationsFuture;
  Future<Map<String, dynamic>>? _preferencesFuture;
  String? _lastWebTitle;

  @override
  void initState() {
    super.initState();
    _notificationsFuture = _loadNotifications();
    _preferencesFuture = _loadPreferences();
  }

  Future<List<Map<String, dynamic>>> _loadNotifications() async {
    final rows = await context.read<AppState>().api.getNotifications();
    return rows.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> _loadPreferences() async {
    return context.read<AppState>().api.getNotificationPreferences();
  }

  Future<void> _refresh() async {
    await context.read<AppState>().refreshTodayView();
    if (!mounted) return;
    setState(() {
      _notificationsFuture = _loadNotifications();
      _preferencesFuture = _loadPreferences();
    });
  }

  Future<void> _markRead(String id) async {
    await context.read<AppState>().api.markNotificationRead(id);
    await _refresh();
  }

  Future<void> _dismiss(String id) async {
    await context.read<AppState>().api.dismissNotification(id);
    await _refresh();
  }

  Future<void> _updatePreference(String key, bool value) async {
    await context.read<AppState>().api.updateNotificationPreferences({
      key: value,
    });
    await _refresh();
  }

  String _timeLabel(String? raw) {
    if (raw == null || raw.isEmpty) return 'All day';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    } catch (_) {
      return raw;
    }
  }

  void _syncWebTitle(String title) {
    if (!kIsWeb || _lastWebTitle == title) return;
    _lastWebTitle = title;
    setWebPageTitle(title);
  }

  @override
  Widget build(BuildContext context) {
    _syncWebTitle('Notifications · AiPal');

    return Scaffold(
      backgroundColor: surfaceBackground,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF111827)),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const Text(
          'Notifications',
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
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: yellowOnPrimary,
          backgroundColor: yellowPrimary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            children: [
              // Agenda Section Header
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _notificationsFuture,
                builder: (context, snapshot) {
                  final rows = snapshot.data ?? const [];
                  final unreadCount = rows
                      .where((r) => r['status'] != 'read' && r['status'] != 'sent')
                      .length;

                  return _SectionCard(
                    title: 'Agenda Activity',
                    subtitle: 'Reminders, task dues, and commitment updates',
                    badgeCount: unreadCount,
                    child: Builder(
                      builder: (context) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 36),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: yellowPrimary,
                              ),
                            ),
                          );
                        }
                        if (rows.isEmpty) {
                          return const _EmptyNotificationState(
                            text: 'You are all caught up! No active notifications.',
                          );
                        }
                        return Column(
                          children: rows.map((row) {
                            final id = row['id'].toString();
                            final status = row['status']?.toString() ?? 'pending';
                            final isRead = status == 'read' || status == 'sent';

                            return Dismissible(
                              key: Key('notif_$id'),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) => _dismiss(id),
                              background: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                              child: _NotificationCard(
                                icon: _iconFor(row['type']?.toString()),
                                title: row['title']?.toString() ?? 'Notification',
                                channel: row['channel']?.toString() ?? 'in_app',
                                status: status,
                                formattedTime: _timeLabel(row['scheduled_for']?.toString()),
                                isRead: isRead,
                                accentColor: _accentFor(row['type']?.toString()),
                                onRead: () => _markRead(id),
                                onDismiss: () => _dismiss(id),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // Preferences Section
              _SectionCard(
                title: 'Notification Settings',
                subtitle: 'Customize how and when AiPal nudges you',
                child: FutureBuilder<Map<String, dynamic>>(
                  future: _preferencesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: yellowPrimary,
                          ),
                        ),
                      );
                    }
                    final prefs = snapshot.data ?? const <String, dynamic>{};
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Column(
                        children: [
                          _PreferenceTile(
                            icon: Icons.notifications_none_rounded,
                            title: 'In-app notifications',
                            subtitle: 'Receive banners and nudges inside the app',
                            value: prefs['in_app_enabled'] as bool? ?? true,
                            onChanged: (value) =>
                                _updatePreference('in_app_enabled', value),
                          ),
                          const Divider(height: 1, color: cardBorder),
                          _PreferenceTile(
                            icon: Icons.mail_outline_rounded,
                            title: 'Email reminders',
                            subtitle: 'Daily agenda summaries and important alerts',
                            value: prefs['email_enabled'] as bool? ?? true,
                            onChanged: (value) =>
                                _updatePreference('email_enabled', value),
                          ),
                          const Divider(height: 1, color: cardBorder),
                          _PreferenceTile(
                            icon: Icons.phone_iphone_rounded,
                            title: 'Push notifications',
                            subtitle: 'Real-time notifications on your device',
                            value: prefs['push_enabled'] as bool? ?? true,
                            onChanged: (value) =>
                                _updatePreference('push_enabled', value),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'meeting':
        return Icons.groups_rounded;
      case 'task_due':
        return Icons.task_alt_rounded;
      case 'commitment_followup':
      case 'smart_commitment_progress':
        return Icons.handshake_rounded;
      case 'smart_meeting_prep':
        return Icons.lightbulb_rounded;
      case 'smart_missed_followup':
        return Icons.volunteer_activism_rounded;
      case 'reminder':
        return Icons.notifications_active_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Color _accentFor(String? type) {
    switch (type) {
      case 'meeting':
        return const Color(0xFF2563EB); // Blue
      case 'task_due':
        return const Color(0xFFD97706); // Amber
      case 'commitment_followup':
      case 'smart_commitment_progress':
        return const Color(0xFF7C3AED); // Purple
      case 'smart_meeting_prep':
        return const Color(0xFF059669); // Emerald
      default:
        return yellowOnPrimary;
    }
  }
}

// Section Container UI Card
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.badgeCount,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              if (badgeCount != null && badgeCount! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _NotificationsScreenState.yellowPrimary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$badgeCount UNREAD',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _NotificationsScreenState.yellowOnPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

// Notification Entry Row
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.icon,
    required this.title,
    required this.channel,
    required this.status,
    required this.formattedTime,
    required this.isRead,
    required this.accentColor,
    required this.onRead,
    required this.onDismiss,
  });

  final IconData icon;
  final String title;
  final String channel;
  final String status;
  final String formattedTime;
  final bool isRead;
  final Color accentColor;
  final VoidCallback onRead;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRead ? const Color(0xFFFAFAFA) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRead ? const Color(0xFFE5E7EB) : _NotificationsScreenState.yellowPrimary.withAlpha(140),
          width: isRead ? 1 : 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon Box
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isRead
                  ? const Color(0xFFF3F4F6)
                  : accentColor.withAlpha(25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: isRead ? const Color(0xFF9CA3AF) : accentColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),

          // Content Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                    color: isRead ? const Color(0xFF4B5563) : const Color(0xFF111827),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),

                // Meta Info Pills
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _MetaPill(label: channel.replaceAll('_', ' ').toUpperCase()),
                    _MetaPill(
                      label: formattedTime,
                      icon: Icons.schedule_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isRead)
                IconButton(
                  tooltip: 'Mark read',
                  onPressed: onRead,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  color: const Color(0xFF059669),
                  iconSize: 20,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
                color: const Color(0xFF9CA3AF),
                iconSize: 20,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: const Color(0xFF6B7280)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}

// Preference Switch Tile
class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF4B5563), size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: _NotificationsScreenState.yellowPrimary,
            activeColor: _NotificationsScreenState.yellowOnPrimary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// Empty State View
class _EmptyNotificationState extends StatelessWidget {
  const _EmptyNotificationState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.notifications_off_outlined,
            size: 36,
            color: Color(0xFF9CA3AF),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}