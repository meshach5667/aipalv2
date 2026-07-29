import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

class FocusTimerBar extends StatefulWidget {
  const FocusTimerBar({
    super.key,
    required this.taskTitle,
    required this.totalSeconds,
    required this.onComplete,
    required this.onCancel,
  });

  final String taskTitle;
  final int totalSeconds;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  @override
  State<FocusTimerBar> createState() => FocusTimerBarState();
}

class FocusTimerBarState extends State<FocusTimerBar> {
  late int _remaining;
  Timer? _timer;
  bool _paused = false;

  // Yellow & Dark Bento Palette Tokens
  static const Color primaryYellow = Color(0xFFFFD600);
  static const Color onPrimaryDark = Color(0xFF221B00);
  static const Color darkContainer = Color(0xFF1A1C1C);
  static const Color surfaceContainer = Color(0xFFEEEEEE);

  @override
  void initState() {
    super.initState();
    _remaining = widget.totalSeconds;
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused) return;

      if (_remaining <= 1) {
        _timer?.cancel();
        widget.onComplete();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _label {
    final m = _remaining ~/ 60;
    final s = _remaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _progress {
    if (widget.totalSeconds <= 0) return 0;
    return (_remaining / widget.totalSeconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final completed = 1 - _progress;

    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Row: Timer Gauge & Details
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Circular Indicator
                      SizedBox(
                        width: 68,
                        height: 68,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 68,
                              height: 68,
                              child: CircularProgressIndicator(
                                value: completed,
                                strokeWidth: 5.5,
                                strokeCap: StrokeCap.round,
                                backgroundColor: surfaceContainer,
                                color: primaryYellow,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.timer_outlined,
                                  size: 14,
                                  color: onPrimaryDark,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _label,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                    color: darkContainer,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 14),

                      // Status & Task Title
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _paused
                                    ? surfaceContainer
                                    : primaryYellow.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _paused
                                          ? Colors.grey
                                          : darkContainer,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _paused ? 'PAUSED' : 'FOCUS MODE',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                      color: darkContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.taskTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 15,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: darkContainer,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${(completed * 100).round()}% complete',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF5F5E5E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Linear Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: completed,
                      minHeight: 5,
                      backgroundColor: surfaceContainer,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        primaryYellow,
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Mobile Responsive Action Bar
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 340;

                      return Row(
                        children: [
                          // Main Pause/Resume Action Button
                          Expanded(
                            child: _FocusActionButton(
                              icon: _paused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              label: _paused ? 'Resume' : 'Pause',
                              filled: true,
                              onTap: () => setState(() => _paused = !_paused),
                            ),
                          ),
                          SizedBox(width: isCompact ? 6 : 8),
                          _FocusIconButton(
                            icon: Icons.add_rounded,
                            tooltip: '+5 min',
                            onTap: () => setState(() => _remaining += 300),
                          ),
                          SizedBox(width: isCompact ? 6 : 8),
                          _FocusIconButton(
                            icon: Icons.check_rounded,
                            tooltip: 'Complete',
                            isAccent: true,
                            onTap: widget.onComplete,
                          ),
                          SizedBox(width: isCompact ? 6 : 8),
                          _FocusIconButton(
                            icon: Icons.close_rounded,
                            tooltip: 'Cancel',
                            onTap: widget.onCancel,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusActionButton extends StatelessWidget {
  const _FocusActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: filled ? const Color(0xFFFFD600) : const Color(0xFFEEEEEE),
        foregroundColor: const Color(0xFF221B00),
        elevation: 0,
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FocusIconButton extends StatelessWidget {
  const _FocusIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isAccent = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isAccent
            ? const Color(0xFFFFD600).withValues(alpha: 0.3)
            : const Color(0xFFEEEEEE),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              size: 20,
              color: const Color(0xFF1A1C1C),
            ),
          ),
        ),
      ),
    );
  }
}