import 'dart:convert';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_state.dart';
import '../services/calendar_service.dart';
import '../services/notification_service.dart';
import 'life_map_screen.dart';
import 'meetings_screen.dart';
import 'planner_screen.dart';
import 'project_rooms_screen.dart';
import 'splash_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.profile;

    final email = profile?['email']?.toString() ?? '';
    final wakeName = profile?['wake_name']?.toString() ?? '—';
    final checkInEnabled = profile?['checkin_enabled'] as bool? ?? true;

    Future<void> signOut() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Sign out of session?'),
          content: const Text(
            'This will clear your local web session. You will need to log in again next time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFBA1A1A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out'),
            ),
          ],
        ),
      );

      if (confirmed != true || !context.mounted) return;

      await context.read<AppState>().signOut();
      if (!context.mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashScreen()),
        (route) => false,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      const Text(
                        'Settings',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1B1C1A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Manage your account, voice interactions, and connected workspaces.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF6F7482),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Identity
                      const _SectionHeader(title: 'Identity'),
                      _SettingsGroupCard(
                        children: [
                          _IdentityTile(
                            icon: Icons.mail_outline_rounded,
                            label: 'Registered Email',
                            value: email.isEmpty ? 'No email registered' : email,
                          ),
                          const _SettingsDivider(),
                          _IdentityTile(
                            icon: Icons.waving_hand_rounded,
                            label: 'Wake Name',
                            value: wakeName,
                          ),
                        ],
                      ),

                      const SizedBox(height: 36),

                      // Voice & Interaction
                      const _SectionHeader(title: 'Voice & Interaction'),
                      _SettingsGroupCard(
                        children: [
                          _SwitchTile(
                            icon: Icons.record_voice_over_rounded,
                            title: 'Listen for "Hi Pal"',
                            subtitle: kIsWeb
                                ? 'Enable this and say "Hi Pal" while Live is active.'
                                : state.wakeWordError ??
                                    (defaultTargetPlatform == TargetPlatform.android
                                        ? 'Say "Hi Pal" anytime to start Live.'
                                        : 'Say "Hi Pal" on the Companion tab to start Live hands-free.'),
                            value: state.wakeWordEnabled,
                            isError: state.wakeWordError != null,
                            onChanged: (v) => state.setWakeWordEnabled(v),
                          ),
                          const _SettingsDivider(),
                          _SwitchTile(
                            icon: Icons.notifications_active_outlined,
                            title: 'Proactive Check-ins',
                            subtitle: 'Allow AiPal to proactively check in on your schedule and focus.',
                            value: checkInEnabled,
                            onChanged: (v) => state.updateProfile({'checkin_enabled': v}),
                          ),
                          const _SettingsDivider(),
                          const _VoiceChoiceRow(),
                        ],
                      ),

                      const SizedBox(height: 36),

                      // Life OS Workspaces
                      const _SectionHeader(title: 'Life OS Workspaces'),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 560;

                          final planner = _FeatureCard(
                            icon: Icons.view_timeline_rounded,
                            title: 'Planner Engine',
                            subtitle: 'Draft daily, weekly, monthly, and 90-day execution plans.',
                            actionText: 'Open Planner',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const PlannerScreen()),
                            ),
                          );

                          final meetings = _FeatureCard(
                            icon: Icons.groups_rounded,
                            title: 'Meeting Assistant',
                            subtitle: 'Prepare agendas, capture live notes, and extract action items.',
                            actionText: 'Open Meetings',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const MeetingsScreen()),
                            ),
                          );

                          final rooms = _FeatureCard(
                            icon: Icons.dashboard_customize_rounded,
                            title: 'Project Rooms',
                            subtitle: 'Workspaces for projects, risks, tasks, and team memories.',
                            actionText: 'Open Rooms',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const ProjectRoomsScreen()),
                            ),
                          );

                          final lifeMap = _FeatureCard(
                            icon: Icons.map_rounded,
                            title: 'Life Map',
                            subtitle: 'Connected view across health, business, growth, and relationships.',
                            actionText: 'Open Life Map',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const LifeMapScreen()),
                            ),
                          );

                          if (!isWide) {
                            return Column(
                              children: [
                                planner,
                                const SizedBox(height: 14),
                                meetings,
                                const SizedBox(height: 14),
                                rooms,
                                const SizedBox(height: 14),
                                lifeMap,
                              ],
                            );
                          }

                          return Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: planner),
                                  const SizedBox(width: 14),
                                  Expanded(child: meetings),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(child: rooms),
                                  const SizedBox(width: 14),
                                  Expanded(child: lifeMap),
                                ],
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 36),

                      // Connectivity
                      const _SectionHeader(title: 'Integrations & Automation'),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 560;

                          final morningBrief = _FeatureCard(
                            icon: Icons.update_rounded,
                            title: 'Morning Brief',
                            subtitle: 'Scheduled daily for 08:00 AM.',
                            actionText: 'Reschedule',
                            onTap: () => NotificationService.instance.scheduleMorningBrief(
                              hour: 8,
                              minute: 0,
                            ),
                          );

                          final calendar = _FeatureCard(
                            icon: Icons.calendar_month_rounded,
                            title: 'Calendar Sync',
                            subtitle: 'Import today\'s events from Google or Outlook.',
                            badge: 'v2.1',
                            actionText: 'Sync Now',
                            onTap: () async {
                              final events = await CalendarService().fetchTodayEvents();
                              if (context.mounted && events.isNotEmpty) {
                                final n = await context.read<AppState>().api.importCalendar(events);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      content: Text('Imported $n calendar events'),
                                    ),
                                  );
                                }
                              }
                            },
                          );

                          final spotify = _FeatureCard(
                            icon: Icons.headphones_rounded,
                            iconColor: const Color(0xFF1DB954),
                            title: 'Spotify Integration',
                            subtitle: 'Control media playback using voice controls.',
                            badge: 'v2.1',
                            actionText: 'Authorize',
                            onTap: () async {
                              final uri = Uri.parse('https://43.160.220.9.sslip.io/privacy-policy.html');
                              await launchUrl(uri);
                            },
                          );

                          if (!isWide) {
                            return Column(
                              children: [
                                morningBrief,
                                const SizedBox(height: 14),
                                calendar,
                                const SizedBox(height: 14),
                                spotify,
                              ],
                            );
                          }

                          return Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: morningBrief),
                                  const SizedBox(width: 14),
                                  Expanded(child: calendar),
                                ],
                              ),
                              const SizedBox(height: 14),
                              spotify,
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 36),

                      // Session / Auth
                      if (kIsWeb) ...[
                        const _SectionHeader(title: 'Account'),
                        _SettingsGroupCard(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Browser Session',
                                          style: TextStyle(
                                            fontFamily: 'Manrope',
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1B1C1A),
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Sign out of your active browser session.',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF6F7482),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFBA1A1A),
                                      side: const BorderSide(color: Color(0xFFFFDAD6)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: signOut,
                                    child: const Text('Sign out'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 36),
                      ],

                      const _SettingsFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Section Header Widget
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Color(0xFF6F5081),
        ),
      ),
    );
  }
}

// Container Card for grouping rows
class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEFECE6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: Color(0xFFF3F0EA));
  }
}

// Identity Display Row
class _IdentityTile extends StatelessWidget {
  const _IdentityTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3EF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF6F5081), size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6F7482),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B1C1A),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: const Color(0xFF9EA3B0),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

// Interactive Toggle Tile
class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4D9FF).withOpacity(0.4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF6F5081), size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B1C1A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: isError ? const Color(0xFFBA1A1A) : const Color(0xFF6F7482),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            value: value,
            activeColor: const Color(0xFF6F5081),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// Dynamic Voice Selector
class _VoiceChoiceRow extends StatefulWidget {
  const _VoiceChoiceRow();

  @override
  State<_VoiceChoiceRow> createState() => _VoiceChoiceRowState();
}

class _VoiceChoiceRowState extends State<_VoiceChoiceRow> {
  static const _fallbackVoices = <Map<String, String>>[
    {
      'id': 'calm_female',
      'name': 'Calm Female',
      'style': 'Warm, calm, and steady',
    },
    {
      'id': 'calm_male',
      'name': 'Calm Male',
      'style': 'Relaxed, grounded, and patient',
    },
    {
      'id': 'coach',
      'name': 'Coach',
      'style': 'Direct, focused, and strategic',
    },
    {
      'id': 'friendly',
      'name': 'Friendly',
      'style': 'Warm and friendly',
    },
  ];

  String _selected = 'calm_female';
  List<Map<String, dynamic>> _voices = _fallbackVoices;
  bool _loading = true;
  bool _previewing = false;
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = context.read<AppState>().api;
      final results = await Future.wait([
        api.getCompanionPreferences(),
        api.getTtsVoices(),
      ]);

      final prefs = results[0] as Map<String, dynamic>;
      final voices = (results[1] as List<Map<String, dynamic>>)
          .where((v) => (v['id']?.toString() ?? '').isNotEmpty)
          .toList();

      if (!mounted) return;

      setState(() {
        if (voices.isNotEmpty) _voices = voices;
        _selected = prefs['voice_profile']?.toString() ?? 'calm_female';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(String value) async {
    setState(() => _selected = value);
    try {
      await context.read<AppState>().api.updateCompanionPreferences({
        'voice_profile': value,
        'tts_voice': value,
      });
    } catch (e) {
      // Error handling
    }
  }

  Future<void> _preview() async {
    setState(() => _previewing = true);
    try {
      final response = await context.read<AppState>().api.tts(
        'Hello! I am your companion.',
        voice: _selected,
      );
      final audio = response['audio_base64'] as String?;
      if (audio != null && audio.isNotEmpty) {
        await _player.stop();
        await _player.play(BytesSource(base64Decode(audio)));
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F3F1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.spatial_audio_off_rounded, color: Color(0xFF2C6B60), size: 22),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Companion Voice',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1B1C1A),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Voice profile used for spoken responses.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF6F7482)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F7F4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E2DC)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selected,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      items: _voices.map((v) {
                        return DropdownMenuItem<String>(
                          value: v['id'].toString(),
                          child: Text(
                            v['name']?.toString() ?? '',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        );
                      }).toList(),
                      onChanged: _loading ? null : (v) => v != null ? _save(v) : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF4D9FF).withOpacity(0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _loading || _previewing ? null : _preview,
                icon: _previewing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded, color: Color(0xFF6F5081)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Interactive Workspace / Connectivity Feature Card
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionText,
    required this.onTap,
    this.badge,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionText;
  final VoidCallback onTap;
  final String? badge;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEFECE6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 28, color: iconColor ?? const Color(0xFF6F5081)),
                    const Spacer(),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4D9FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6F5081),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B1C1A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF6F7482),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      actionText,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6F5081),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: Color(0xFF6F5081),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Clean App Footer
class _SettingsFooter extends StatefulWidget {
  const _SettingsFooter();

  @override
  State<_SettingsFooter> createState() => _SettingsFooterState();
}

class _SettingsFooterState extends State<_SettingsFooter> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() {
          _version = 'v${info.version} (${info.buildNumber})';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const Text(
            'AiPal Life OS',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF9EA3B0),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _version.isEmpty ? 'v2.1' : _version,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFB5B9C4),
            ),
          ),
        ],
      ),
    );
  }
}