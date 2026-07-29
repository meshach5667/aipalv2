import 'package:flutter/material.dart';

class TodayEmpty extends StatelessWidget {
  const TodayEmpty({
    super.key,
    this.title = 'No tasks have been created',
    this.description = 'Tap below to talk with your companion or add a new task to get started.',
    this.actionLabel,
    this.onGoCompanion,
  });

  final String? title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onGoCompanion;

  // Custom Yellow Palette Constants
  static const Color yellowPrimary = Color(0xFFFFD600);
  static const Color yellowOnPrimary = Color(0xFF221B00);
  static const Color yellowContainer = Color(0xFFFFE170);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Fallbacks ensuring text exists even if null or empty strings are passed in
    final effectiveTitle = (title != null && title!.trim().isNotEmpty)
        ? title!.trim()
        : 'No tasks have been created';

    final effectiveDescription = (description != null && description!.trim().isNotEmpty)
        ? description!.trim()
        : 'Tap below to talk with your companion or add a new task to get started.';

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 36,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 32,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Ambient Yellow Icon Badge
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: yellowContainer,
                          boxShadow: [
                            BoxShadow(
                              color: yellowPrimary.withValues(alpha: 0.35),
                              blurRadius: 28,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: yellowOnPrimary,
                            size: 36,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Guaranteed Title Text
                      Text(
                        effectiveTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 22,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: colorScheme.onSurface != Colors.transparent
                              ? colorScheme.onSurface
                              : const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Guaranteed Description Text
                      Text(
                        effectiveDescription,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant != Colors.transparent
                              ? colorScheme.onSurfaceVariant
                              : const Color(0xFF6B7280),
                        ),
                      ),

                      // Companion Yellow Action Button
                      if (onGoCompanion != null &&
                          actionLabel?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 32),
                        FilledButton.icon(
                          onPressed: onGoCompanion,
                          icon: const Icon(Icons.graphic_eq_rounded, size: 20),
                          label: Text(actionLabel!.trim()),
                          style: FilledButton.styleFrom(
                            backgroundColor: yellowPrimary,
                            foregroundColor: yellowOnPrimary,
                            minimumSize: const Size.fromHeight(54),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}