import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../../../shared/widgets/section_title.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/auth_provider.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    if (_currentCtrl.text != user.password) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current password is incorrect')),
      );
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Password change accepted — wire to backend in production',
        ),
      ),
    );
    context.go('/profile');
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final gap = isMobile ? 10.0 : 14.0;
    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Change Password',
            subtitle: 'Min 8 chars, 1 number',
            actions: [
              AppButton(
                label: 'Back',
                kind: BtnKind.ghost,
                icon: Icons.arrow_back_rounded,
                onPressed: () => context.go('/profile'),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 14 : 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: AppCard(
                    padding: EdgeInsets.all(isMobile ? 12 : 20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SectionTitle(
                            icon: Icons.lock_outline_rounded,
                            title: 'Set new password',
                          ),
                          LabeledField(
                            label: 'Current password',
                            required: true,
                            child: TextFormField(
                              controller: _currentCtrl,
                              obscureText: true,
                              validator: (v) =>
                                  (v?.isEmpty ?? true) ? 'Required' : null,
                            ),
                          ),
                          SizedBox(height: gap),
                          LabeledField(
                            label: 'New password',
                            required: true,
                            child: TextFormField(
                              controller: _newCtrl,
                              obscureText: true,
                              validator: (v) {
                                if (v == null || v.length < 8) {
                                  return 'Min 8 characters';
                                }
                                if (!RegExp(r'\d').hasMatch(v)) {
                                  return 'Must contain a number';
                                }
                                return null;
                              },
                            ),
                          ),
                          SizedBox(height: gap),
                          LabeledField(
                            label: 'Confirm new password',
                            required: true,
                            child: TextFormField(
                              controller: _confirmCtrl,
                              obscureText: true,
                              validator: (v) =>
                                  (v?.isEmpty ?? true) ? 'Required' : null,
                            ),
                          ),
                          SizedBox(height: isMobile ? 16 : 22),
                          AppButton(
                            label: 'Update password',
                            icon: Icons.save_outlined,
                            expanded: true,
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    ),
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
