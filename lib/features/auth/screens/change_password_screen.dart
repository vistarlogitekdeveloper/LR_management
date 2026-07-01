import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../../../shared/widgets/section_title.dart';
import '../../masters/widgets/master_actions.dart';
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

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authProvider.notifier).changePassword(
            currentPassword: _currentCtrl.text,
            newPassword: _newCtrl.text,
          );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Password updated. Please sign in with your new password.'),
          backgroundColor: AppColors.ok,
        ),
      );
      // Changing the password revokes every refresh token server-side, so this
      // session is dead. Sign out (clears stored tokens) — the router then
      // redirects to /login.
      await ref.read(authProvider.notifier).logout();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(_errorMessage(e)),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The backend returns a deliberately-generic "Password change failed." for a
  /// wrong current password (code OLD_PASSWORD_MISMATCH) — translate it into a
  /// clear, specific message. Everything else uses the server's own message.
  String _errorMessage(Object e) {
    final err = e is DioException ? e.error : e;
    if (err is ApiException && err.code == 'OLD_PASSWORD_MISMATCH') {
      return 'Current password is incorrect';
    }
    return MasterActions.messageFor(e);
  }

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
    TextInputAction textInputAction = TextInputAction.next,
    void Function(String)? onSubmitted,
  }) {
    return LabeledField(
      label: label,
      required: true,
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        enabled: !_saving,
        textInputAction: textInputAction,
        onFieldSubmitted: onSubmitted,
        validator: validator,
        decoration: InputDecoration(
          suffixIcon: IconButton(
            tooltip: obscure ? 'Show password' : 'Hide password',
            icon: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: AppColors.slate,
              size: 20,
            ),
            onPressed: onToggle,
          ),
        ),
      ),
    );
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
            subtitle: 'Min 10 chars, 1 number',
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
                          _passwordField(
                            label: 'Current password',
                            controller: _currentCtrl,
                            obscure: _obscureCurrent,
                            onToggle: () => setState(
                                () => _obscureCurrent = !_obscureCurrent),
                            validator: (v) =>
                                (v?.isEmpty ?? true) ? 'Required' : null,
                          ),
                          SizedBox(height: gap),
                          _passwordField(
                            label: 'New password',
                            controller: _newCtrl,
                            obscure: _obscureNew,
                            onToggle: () =>
                                setState(() => _obscureNew = !_obscureNew),
                            validator: (v) {
                              if (v == null || v.length < 10) {
                                return 'Min 10 characters';
                              }
                              if (v.length > 128) {
                                return 'Max 128 characters';
                              }
                              if (!RegExp(r'\d').hasMatch(v)) {
                                return 'Must contain a number';
                              }
                              if (v == _currentCtrl.text) {
                                return 'New password must be different';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: gap),
                          _passwordField(
                            label: 'Confirm new password',
                            controller: _confirmCtrl,
                            obscure: _obscureConfirm,
                            onToggle: () => setState(
                                () => _obscureConfirm = !_obscureConfirm),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            validator: (v) {
                              if (v?.isEmpty ?? true) return 'Required';
                              if (v != _newCtrl.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: isMobile ? 16 : 22),
                          AppButton(
                            label:
                                _saving ? 'Updating…' : 'Update password',
                            icon: Icons.save_outlined,
                            expanded: true,
                            loading: _saving,
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
