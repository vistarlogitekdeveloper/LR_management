import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _userCtrl = TextEditingController(text: 'admin');
  final _passCtrl = TextEditingController(text: '123456');

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await ref
        .read(authProvider.notifier)
        .login(_userCtrl.text, _passCtrl.text);
    if (!mounted) return;
    if (ok) context.go('/dashboard');
  }

  Future<void> _quickSignIn(String username, String password) async {
    _userCtrl.text = username;
    _passCtrl.text = password;
    await _submit();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      border: Border.all(color: AppColors.line),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14241726),
                          blurRadius: 30,
                          offset: Offset(0, 12),
                        ),
                      ],
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: isWide
                        ? IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: _Hero()),
                                Expanded(
                                  child: _Form(
                                    userCtrl: _userCtrl,
                                    passCtrl: _passCtrl,
                                    loading: auth.loading,
                                    error: auth.error,
                                    onSubmit: _submit,
                                    onQuickSignIn: _quickSignIn,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Hero(compact: true),
                              _Form(
                                userCtrl: _userCtrl,
                                passCtrl: _passCtrl,
                                loading: auth.loading,
                                error: auth.error,
                                compact: true,
                                onSubmit: _submit,
                                onQuickSignIn: _quickSignIn,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final bool compact;
  const _Hero({this.compact = false});

  @override
  Widget build(BuildContext context) {
    // Mobile: a slim branded header (logo + one-line title) so the login form
    // sits near the top and needs little scrolling.
    if (compact) {
      return Container(
        decoration: const BoxDecoration(gradient: AppColors.loginHeroGradient),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: const Row(
          children: [
            BrandLogo(height: 28, light: true),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Lorry Receipt Management',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.loginHeroGradient,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 54,
        vertical: 56,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandLogo(height: 36, light: true),
          const SizedBox(height: 32),
          const Text(
            'Lorry Receipt\nManagement',
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Generate LRs, track consignments, manage masters and freight billing — all in one place.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          SizedBox(height: compact ? 28 : 80),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Demo logins',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'admin · operator · accounts  (password: 123456)',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                SizedBox(height: 4),
                Text(
                  'Tenant: VISTAR',
                  style: TextStyle(color: Colors.white60, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Form extends StatefulWidget {
  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final bool loading;
  final String? error;
  final bool compact;
  final VoidCallback onSubmit;
  final Future<void> Function(String username, String password) onQuickSignIn;

  const _Form({
    required this.userCtrl,
    required this.passCtrl,
    required this.loading,
    required this.error,
    required this.onSubmit,
    required this.onQuickSignIn,
    this.compact = false,
  });

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  bool _obscurePassword = true; // hidden by default; the eye icon toggles it

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 22 : 44,
        vertical: compact ? 26 : 56,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Welcome back',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sign in to continue dispatching',
            style: TextStyle(color: AppColors.slate, fontSize: 14),
          ),
          SizedBox(height: compact ? 20 : 28),
          LabeledField(
            label: 'Username',
            required: true,
            child: TextField(
              controller: widget.userCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'admin'),
            ),
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'Password',
            required: true,
            child: TextField(
              controller: widget.passCtrl,
              obscureText: _obscurePassword,
              onSubmitted: (_) => widget.onSubmit(),
              decoration: InputDecoration(
                hintText: '••••',
                // Eye icon to show / hide the password.
                suffixIcon: IconButton(
                  tooltip:
                      _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.slate,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go('/forgot-password'),
              child: const Text('Forgot password?'),
            ),
          ),
          const SizedBox(height: 12),
          AppButton(
            label: widget.loading ? 'Signing in…' : 'Sign in',
            icon: Icons.login_rounded,
            expanded: true,
            onPressed: widget.loading ? null : widget.onSubmit,
          ),
          SizedBox(height: compact ? 16 : 22),
          Row(
            children: [
              const Expanded(child: Divider(color: AppColors.line)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or sign in as',
                  style: TextStyle(
                    color: AppColors.slate.withValues(alpha: 0.8),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: AppColors.line)),
            ],
          ),
          const SizedBox(height: 14),
          _RoleQuickPicker(
              loading: widget.loading, onPick: widget.onQuickSignIn),
          SizedBox(height: compact ? 14 : 18),
          const Center(
            child: Text(
              '© Vistar Logitek Pvt Ltd',
              style: TextStyle(color: AppColors.slate, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleOption {
  final String label;
  final String username;
  final String password;
  final String displayName;
  final IconData icon;
  final Color tint;
  const _RoleOption({
    required this.label,
    required this.username,
    required this.password,
    required this.displayName,
    required this.icon,
    required this.tint,
  });
}

class _RoleQuickPicker extends StatelessWidget {
  final bool loading;
  final Future<void> Function(String username, String password) onPick;

  const _RoleQuickPicker({required this.loading, required this.onPick});

  static const _options = <_RoleOption>[
    _RoleOption(
      label: 'Admin',
      username: 'admin',
      password: '123456',
      displayName: 'admin',
      icon: Icons.shield_outlined,
      tint: AppColors.plum,
    ),
    _RoleOption(
      label: 'Operator',
      username: 'operator',
      password: '123456',
      displayName: 'operator',
      icon: Icons.local_shipping_outlined,
      tint: AppColors.orange,
    ),
    _RoleOption(
      label: 'Accounts',
      username: 'accounts',
      password: '123456',
      displayName: 'accounts',
      icon: Icons.account_balance_wallet_outlined,
      tint: AppColors.ok,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _options.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: _RoleTile(
                option: _options[i],
                disabled: loading,
                onTap: () => onPick(
                  _options[i].username,
                  _options[i].password,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final _RoleOption option;
  final bool disabled;
  final VoidCallback onTap;

  const _RoleTile({
    required this.option,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: disabled ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: option.tint.withValues(alpha: 0.06),
              border: Border.all(color: option.tint.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: option.tint.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(option.icon, color: option.tint, size: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  option.label,
                  style: TextStyle(
                    color: option.tint,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  option.displayName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
