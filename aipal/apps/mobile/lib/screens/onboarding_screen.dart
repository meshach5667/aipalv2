import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/notification_service.dart';
import 'home_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.continueProfile = false});

  final bool continueProfile;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _emailController = TextEditingController();
  final _wakeNameController = TextEditingController();
  final _aboutController = TextEditingController();

  int _step = 0;
  bool _isLoading = false;
  String? _error;
  String? _validatedEmail;

  @override
  void initState() {
    super.initState();
    if (widget.continueProfile) _step = 1;
  }

  @override
  void dispose() {
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
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }

    setState(() {
      _error = null;
      _validatedEmail = email;
      _step = 1;
    });
  }

  Future<void> _finish() async {
    final state = context.read<AppState>();
    setState(() {
      _isLoading = true;
      _error = null;
    });

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
        'morning_brief_at': '08:00',
        'evening_recap_at': '20:00',
      });

      try {
        await NotificationService.instance
            .scheduleMorningBrief(hour: 8, minute: 0);
        await NotificationService.instance
            .scheduleEveningRecap(hour: 20, minute: 0);
      } catch (_) {
        // Optional notifications fallback
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
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
    final isEmailStep = _step == 0 && !widget.continueProfile;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      // App Bar / Navigation Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFD600).withAlpha(40),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.bubble_chart_rounded,
                                  color: Color(0xFF705D00),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'AiPal',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF705D00),
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F0F0),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _step == 0 ? '01 / 02' : '02 / 02',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF705D00),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Step Content Container
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: isEmailStep
                            ? _buildEmailStep()
                            : _buildProfileStep(),
                      ),

                      const Spacer(),

                      const SizedBox(height: 24),

                      // Primary Action Button
                      _YellowButton(
                        label: isEmailStep ? 'Continue' : 'Get Started',
                        isLoading: _isLoading,
                        onPressed: isEmailStep
                            ? _onContinueFromEmail
                            : _finish,
                      ),

                      if (isEmailStep) ...[
                        const SizedBox(height: 20),
                        // Quick Sign-In Option
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Quick Sign-in: ',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF5F5E5E),
                              ),
                            ),
                            InkWell(
                              onTap: () {},
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEEEEE),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(
                                      Icons.g_mobiledata_rounded,
                                      size: 22,
                                      color: Color(0xFF1A1C1C),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Google',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1A1C1C),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 28),

                      // Security & Legal Footer
                      const _TemplateFooter(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      key: const ValueKey('email_step'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Hero Visual Container
        Container(
          width: double.infinity,
          height: 160,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F3F3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFFFD600),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFF544600),
                size: 32,
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Title & Lead Text
        const Text(
          'Welcome to AiPal',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 32,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            color: Color(0xFF1A1C1C),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Sign in with your email to start setting up your personal AI companion.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: Color(0xFF5F5E5E),
          ),
        ),
        const SizedBox(height: 28),

        // Email Form Control
        _TemplateTextField(
          controller: _emailController,
          labelText: 'EMAIL ADDRESS',
          hintText: 'name@example.com',
          prefixIcon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _onContinueFromEmail(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 16,
                color: Color(0xFFBA1A1A),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFBA1A1A),
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildProfileStep() {
    return Column(
      key: const ValueKey('profile_step'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 8),
        const Text(
          'Tell us about yourself',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 32,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            color: Color(0xFF1A1C1C),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'This helps AiPal adapt to your daily workflow and personal rhythm.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: Color(0xFF5F5E5E),
          ),
        ),
        const SizedBox(height: 28),
        _TemplateTextField(
          controller: _wakeNameController,
          labelText: 'WHAT SHOULD WE CALL YOU?',
          hintText: 'First name or nickname',
          prefixIcon: Icons.badge_outlined,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 20),
        _TemplateTextField(
          controller: _aboutController,
          labelText: 'A BIT ABOUT YOU (OPTIONAL)',
          hintText: 'Your focus goals, habits, or routine...',
          prefixIcon: Icons.notes_outlined,
          maxLines: 3,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 16,
                color: Color(0xFFBA1A1A),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFBA1A1A),
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TemplateTextField extends StatelessWidget {
  const _TemplateTextField({
    required this.controller,
    required this.labelText,
    required this.hintText,
    this.prefixIcon,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Color(0xFF4D4632),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          maxLines: maxLines,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: const TextStyle(
            fontSize: 16,
            color: Color(0xFF1A1C1C),
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(
              color: Color(0xFFA09B8C),
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: prefixIcon != null
                ? Padding(
                    padding: const EdgeInsets.only(left: 16, right: 12),
                    child: Icon(
                      prefixIcon,
                      color: const Color(0xFF705D00),
                      size: 22,
                    ),
                  )
                : null,
            prefixIconConstraints: const BoxConstraints(
              minWidth: 48,
              minHeight: 48,
            ),
            filled: true,
            fillColor: const Color(0xFFF6F6F6),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFEAEAEA), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF1A1C1C), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _YellowButton extends StatelessWidget {
  const _YellowButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFFD600),
          foregroundColor: const Color(0xFF544600),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF544600)),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: Color(0xFF544600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 22,
                    color: Color(0xFF544600),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TemplateFooter extends StatelessWidget {
  const _TemplateFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: Color(0xFF5F5E5E),
            ),
            SizedBox(width: 6),
            Text(
              'Your data is private and encrypted.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF5F5E5E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {},
              child: const Text(
                'Privacy Policy',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5E5F5F),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(width: 20),
            GestureDetector(
              onTap: () {},
              child: const Text(
                'Terms of Service',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5E5F5F),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}