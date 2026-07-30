import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../widgets/aipal_logo.dart';
import '../services/notification_service.dart';
import 'home_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.continueProfile = false});

  final bool continueProfile;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _emailController = TextEditingController();
  final _wakeNameController = TextEditingController();
  final _aboutController = TextEditingController();

  int _currentStep = 0;
  String? _error;
  String? _validatedEmail;
  bool _isLoading = false;
  TimeOfDay _morningBriefAt = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _eveningRecapAt = const TimeOfDay(hour: 20, minute: 0);
  bool _knowledgeGapDataConsent = false;

  @override
  void initState() {
    super.initState();
    if (widget.continueProfile) {
      _currentStep = 1;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _wakeNameController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return false;
    final at = trimmed.indexOf('@');
    return at > 0 && trimmed.contains('.') && at < trimmed.length - 1;
  }

  void _onContinueFromEmail() {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }

    setState(() {
      _error = null;
      _validatedEmail = email;
      _currentStep = 1;
    });

    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  void _goBack() {
    if (_currentStep > 0 && !widget.continueProfile) {
      FocusScope.of(context).unfocus();
      setState(() {
        _currentStep = 0;
        _error = null;
      });
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  String _formatTimeForApi(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTimeForDisplay(TimeOfDay value) {
    final hour = value.hourOfPeriod == 0 ? 12 : value.hourOfPeriod;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _pickBriefTime({required bool morning}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: morning ? _morningBriefAt : _eveningRecapAt,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (morning) {
        _morningBriefAt = picked;
      } else {
        _eveningRecapAt = picked;
      }
      _error = null;
    });
  }

  Future<void> _finish() async {
    FocusScope.of(context).unfocus();
    if (!_knowledgeGapDataConsent) {
      setState(() {
        _error =
            'Please allow AiPal to use your data for better knowledge-gap support.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final state = context.read<AppState>();

    try {
      if (!widget.continueProfile) {
        final email = _validatedEmail ?? _emailController.text.trim();

        if (!_isValidEmail(email)) {
          setState(() {
            _error = 'Please enter a valid email address';
            _isLoading = false;
          });
          return;
        }

        await state.login(email);
      }

      await state.updateProfile({
        'wake_name': _wakeNameController.text.trim().isEmpty
            ? 'friend'
            : _wakeNameController.text.trim(),
        'display_name': _wakeNameController.text.trim(),
        'about_me': _aboutController.text.trim(),
        'morning_brief_at': _formatTimeForApi(_morningBriefAt),
        'evening_recap_at': _formatTimeForApi(_eveningRecapAt),
        'knowledge_gap_data_consent': _knowledgeGapDataConsent,
      });

      try {
        await NotificationService.instance.scheduleMorningBrief(
          hour: _morningBriefAt.hour,
          minute: _morningBriefAt.minute,
        );
        await NotificationService.instance.scheduleEveningRecap(
          hour: _eveningRecapAt.hour,
          minute: _eveningRecapAt.minute,
        );
      } catch (_) {
        // Notifications optional — must not block onboarding
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (_, animation, __) =>
              FadeTransition(opacity: animation, child: const HomeShell()),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Soft Ambient Warm Background for White Theme
          const _AmbientBackground(),

          SafeArea(
            child: Center(
              // Max width constraint for desktop & web screen responsiveness
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    // Top App Bar / Step Indicator
                    _TopAppBar(
                      currentStep: _currentStep,
                      showBack: _currentStep > 0 && !widget.continueProfile,
                      onBack: _goBack,
                    ),

                    // Main Form Content Body
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [_buildEmailStep(), _buildProfileStep()],
                      ),
                    ),

                    // Error Banner Component
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Color(0xFFDC2626),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Color(0xFF991B1B),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Pinned Bottom Action Container with Yellow Button
                    _BottomActionBar(
                      isEmailStep: _currentStep == 0 && !widget.continueProfile,
                      isLoading: _isLoading,
                      onPressed: () {
                        if (_currentStep == 0 && !widget.continueProfile) {
                          _onContinueFromEmail();
                        } else {
                          _finish();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // STEP 0: Email Entry Screen View
  Widget _buildEmailStep() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),

              // Brand Visual Icon Badge
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFACC15), Color(0xFFEAB308)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEAB308).withValues(alpha: 0.35),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Center(child: AiPalLogo(size: 40)),
                ),
              ),

              const SizedBox(height: 36),

              const Text(
                "Welcome to AiPal",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.8,
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                "Your intelligent personal companion. Sign in or create an account with your email to get started.",
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Color(0xFF64748B),
                ),
              ),

              const SizedBox(height: 36),

              _AppTextField(
                controller: _emailController,
                label: "Email Address",
                hintText: "name@example.com",
                prefixIcon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),

              const SizedBox(height: 28),

              const _FeatureBadgeRow(),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  // STEP 1: Profile Customization View
  Widget _buildProfileStep() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              const Text(
                "Personalize Your Assistant",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Help AiPal tailor morning briefs and daily recaps to your preferences.",
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Color(0xFF64748B),
                ),
              ),

              const SizedBox(height: 32),

              _AppTextField(
                controller: _wakeNameController,
                label: "What should AiPal call you?",
                hintText: "Your name or preferred nickname",
                prefixIcon: Icons.person_outline_rounded,
              ),

              const SizedBox(height: 24),

              _AppTextField(
                controller: _aboutController,
                label: "A bit about yourself",
                hintText:
                    "e.g. Developer, early riser, loves focus work & deep conversations",
                prefixIcon: Icons.notes_rounded,
                maxLines: 4,
                optionalLabel: "Optional",
              ),

              const SizedBox(height: 24),

              _ScheduleTile(
                title: "Automated Daily Briefs",
                subtitle:
                    "Morning recap at ${_formatTimeForDisplay(_morningBriefAt)} • Evening digest at ${_formatTimeForDisplay(_eveningRecapAt)}",
                icon: Icons.notifications_active_outlined,
                onTap: () => _pickBriefTime(morning: true),
              ),

              const SizedBox(height: 12),

              _ScheduleTile(
                title: "Evening Daily Recap",
                subtitle:
                    "Daily recap at ${_formatTimeForDisplay(_eveningRecapAt)}",
                icon: Icons.nightlight_outlined,
                onTap: () => _pickBriefTime(morning: false),
              ),

              const SizedBox(height: 12),

              _ConsentTile(
                value: _knowledgeGapDataConsent,
                onChanged: (value) {
                  setState(() {
                    _knowledgeGapDataConsent = value ?? false;
                    _error = null;
                  });
                },
              ),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

// TOP NAVIGATION BAR
class _TopAppBar extends StatelessWidget {
  const _TopAppBar({
    required this.currentStep,
    required this.showBack,
    required this.onBack,
  });

  final int currentStep;
  final bool showBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: showBack
                ? IconButton(
                    onPressed: onBack,
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Color(0xFF0F172A),
                      size: 20,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF1F5F9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  )
                : null,
          ),
          const Spacer(),
          _StepIndicator(currentStep: currentStep),
          const Spacer(),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(2, (index) {
        final isActive = index == currentStep;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFEAB308) : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

// MODERN TEXT FIELD COMPONENT (Light Mode Styled)
class _AppTextField extends StatelessWidget {
  const _AppTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.prefixIcon,
    this.keyboardType,
    this.maxLines = 1,
    this.optionalLabel,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? optionalLabel;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
            if (optionalLabel != null) ...[
              const Spacer(),
              Text(
                optionalLabel!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          onChanged: onChanged,
          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16),
          cursorColor: const Color(0xFFCA8A04),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
            prefixIcon: Padding(
              padding: EdgeInsets.only(bottom: maxLines > 1 ? 70 : 0),
              child: Icon(prefixIcon, color: const Color(0xFFCA8A04), size: 22),
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.all(18),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: Color(0xFFEAB308), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

// SCHEDULE TILE
class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF9C3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFFCA8A04), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFFEAB308),
            checkColor: const Color(0xFF0F172A),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Allow AiPal knowledge-gap support",
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  "AiPal can use your profile and app activity to understand knowledge gaps and personalize help.",
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// FEATURE BADGES
class _FeatureBadgeRow extends StatelessWidget {
  const _FeatureBadgeRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Privacy First Platform",
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  "Your conversations are encrypted and secure.",
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// PINNED BOTTOM ACTION BAR WITH YELLOW BUTTON
class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.isEmailStep,
    required this.isLoading,
    required this.onPressed,
  });

  final bool isEmailStep;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isLoading ? null : onPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFACC15), // Vibrant Yellow
                    foregroundColor: const Color(
                      0xFF0F172A,
                    ), // Dark High Contrast Text
                    disabledBackgroundColor: const Color(0xFFFEF08A),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Color(0xFF0F172A),
                            strokeWidth: 2.5,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              isEmailStep
                                  ? "Continue"
                                  : "Get Started with AiPal",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 20,
                              color: Color(0xFF0F172A),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "By continuing, you agree to AiPal's Terms & Privacy Policy.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// SOFT AMBIENT BACKGROUND (Light Mode)
class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -80,
          right: -80,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFEF08A).withValues(alpha: 0.35),
            ),
          ),
        ),
        Positioned(
          bottom: 120,
          left: -100,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE0F2FE).withValues(alpha: 0.4),
            ),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent),
        ),
      ],
    );
  }
}
