import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../../shared/widgets/labeled_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                color: AppColors.white,
                padding: const EdgeInsets.all(36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandLogo(height: 36)),
                    const SizedBox(height: 28),
                    const Text(
                      'Forgot password?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Enter your registered email and we\'ll send a reset link.',
                      style: TextStyle(color: AppColors.slate, fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    LabeledField(
                      label: 'Email',
                      required: true,
                      child: TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: 'you@vistarlogitek.com',
                        ),
                      ),
                    ),
                    if (_sent) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.ok.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.check_circle_outline,
                                color: AppColors.ok, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'If an account exists, a reset link will be emailed.',
                                style: TextStyle(
                                  color: AppColors.ok,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    AppButton(
                      label: _sent ? 'Resend link' : 'Send reset link',
                      icon: Icons.send_outlined,
                      expanded: true,
                      onPressed: () => setState(() => _sent = true),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => context.go('/login'),
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.plum, size: 18),
                        label: const Text('Back to sign in'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
