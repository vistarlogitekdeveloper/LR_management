import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../data/login_prefs.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _rememberMe = false;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  /// Prefill the username from the last "Remember me" sign-in, if any.
  Future<void> _loadRemembered() async {
    final saved = await LoginPrefs.load();
    if (!mounted) return;
    setState(() {
      _rememberMe = saved.remember;
      if (saved.username.isNotEmpty) _userCtrl.text = saved.username;
      _prefsLoaded = true;
    });
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Client-side validation first — don't hit the network for an empty form.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final username = _userCtrl.text.trim();
    final ok = await ref
        .read(authProvider.notifier)
        .login(username, _passCtrl.text);
    if (!mounted) return;
    if (ok) {
      // Persist (or clear) the remembered username only after a successful
      // sign-in, so a failed attempt never changes what's stored.
      await LoginPrefs.save(remember: _rememberMe, username: username);
      if (!mounted) return;
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isWide = MediaQuery.of(context).size.width >= 900;

    final form = _Form(
      formKey: _formKey,
      userCtrl: _userCtrl,
      passCtrl: _passCtrl,
      loading: auth.loading,
      error: auth.error,
      rememberMe: _rememberMe,
      autofocusUsername: _prefsLoaded && _userCtrl.text.isEmpty,
      onRememberChanged: (v) => setState(() => _rememberMe = v),
      onSubmit: _submit,
      compact: !isWide,
    );

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
                                const Expanded(child: _Hero()),
                                Expanded(child: form),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const _Hero(compact: true),
                              form,
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
          const SizedBox(height: 40),
          _TrustPoints(),
        ],
      ),
    );
  }
}

/// A short list of reassurance bullets on the hero panel — replaces the old
/// demo-credentials card, which must not ship to a client.
class _TrustPoints extends StatelessWidget {
  static const _points = [
    (Icons.verified_user_outlined, 'Role-based access & audit trail'),
    (Icons.lock_outline_rounded, 'Encrypted sessions'),
    (Icons.support_agent_outlined, 'Vistar Logitek support'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (icon, text) in _points)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 18),
                const SizedBox(width: 10),
                Text(
                  text,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Form extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final bool loading;
  final String? error;
  final bool compact;
  final bool rememberMe;
  final bool autofocusUsername;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onSubmit;

  const _Form({
    required this.formKey,
    required this.userCtrl,
    required this.passCtrl,
    required this.loading,
    required this.error,
    required this.rememberMe,
    required this.autofocusUsername,
    required this.onRememberChanged,
    required this.onSubmit,
    this.compact = false,
  });

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  bool _obscurePassword = true; // hidden by default; the eye icon toggles it

  String? _validateUsername(String? v) {
    if ((v ?? '').trim().isEmpty) return 'Username is required';
    return null;
  }

  String? _validatePassword(String? v) {
    if ((v ?? '').isEmpty) return 'Password is required';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 22 : 44,
        vertical: compact ? 26 : 56,
      ),
      child: Form(
        key: widget.formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
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
              child: TextFormField(
                controller: widget.userCtrl,
                autofocus: widget.autofocusUsername,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                enabled: !widget.loading,
                validator: _validateUsername,
                decoration: const InputDecoration(hintText: 'Enter your username'),
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: 'Password',
              required: true,
              child: TextFormField(
                controller: widget.passCtrl,
                obscureText: _obscurePassword,
                enabled: !widget.loading,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                validator: _validatePassword,
                onFieldSubmitted: (_) => widget.onSubmit(),
                decoration: InputDecoration(
                  hintText: 'Enter your password',
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
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
                ),
              ),
            ],
            const SizedBox(height: 10),
            _RememberRow(
              rememberMe: widget.rememberMe,
              onChanged: widget.loading ? null : widget.onRememberChanged,
            ),
            const SizedBox(height: 14),
            AppButton(
              label: widget.loading ? 'Signing in…' : 'Sign in',
              icon: Icons.login_rounded,
              expanded: true,
              loading: widget.loading,
              onPressed: widget.onSubmit,
            ),
            SizedBox(height: compact ? 18 : 24),
            const Center(
              child: Text(
                '© Vistar Logitek Pvt Ltd',
                style: TextStyle(color: AppColors.slate, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Remember me" checkbox on the left, "Forgot password?" on the right.
class _RememberRow extends StatelessWidget {
  final bool rememberMe;
  final ValueChanged<bool>? onChanged;

  const _RememberRow({required this.rememberMe, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? () => onChanged!(!rememberMe) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: rememberMe,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeColor: AppColors.plum,
                    onChanged:
                        enabled ? (v) => onChanged!(v ?? false) : null,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Remember me',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: enabled ? () => context.go('/forgot-password') : null,
          child: const Text('Forgot password?'),
        ),
      ],
    );
  }
}
