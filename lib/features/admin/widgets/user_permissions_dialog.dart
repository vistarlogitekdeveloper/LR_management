import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/app_button.dart';
import '../data/admin_repository.dart';
import '../providers/users_provider.dart';

/// Lets an admin / super admin grant or restrict individual features for one
/// user (e.g. allow add drivers, restrict add routes). Backed by the
/// `/admin/users/:id/permissions` endpoints.
class UserPermissionsDialog extends ConsumerStatefulWidget {
  final AppUser user;
  const UserPermissionsDialog({super.key, required this.user});

  static Future<void> show(BuildContext context, AppUser user) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: UserPermissionsDialog(user: user),
        ),
      ),
    );
  }

  @override
  ConsumerState<UserPermissionsDialog> createState() =>
      _UserPermissionsDialogState();
}

class _UserPermissionsDialogState extends ConsumerState<UserPermissionsDialog> {
  List<PermissionToggle> _toggles = const [];
  final Map<String, bool> _values = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _errorMessage(Object e) {
    if (e is DioException && e.error is ApiException) {
      return (e.error as ApiException).message;
    }
    if (e is ApiException) return e.message;
    return e.toString();
  }

  /// Maps the permission-guard error codes to clear messages; everything else
  /// (FORBIDDEN, validation, …) falls back to the server's own message.
  static String _saveError(Object e) {
    final api = e is DioException ? e.error : e;
    if (api is ApiException) {
      switch (api.code) {
        case 'SELF_LOCKOUT':
          return 'You cannot edit your own permissions.';
        case 'SUPERADMIN_LOCKED':
          return 'Super-admin permissions are role-managed; they cannot be '
              'toggled per user.';
      }
    }
    return _errorMessage(e);
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(adminRepositoryProvider);
      final toggles = await repo.getUserPermissions(widget.user.id);
      if (!mounted) return;
      setState(() {
        _toggles = toggles;
        for (final t in toggles) {
          _values[t.code] = t.effective;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final repo = ref.read(adminRepositoryProvider);
      await repo.setUserPermissions(widget.user.id, Map.of(_values));
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Access updated for ${widget.user.username}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(_saveError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(),
        Flexible(child: _body()),
        _footer(),
      ],
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Access — ${widget.user.name}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${widget.user.username} · ${widget.user.role.label}',
                    style:
                        const TextStyle(color: AppColors.slate, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: AppColors.slate),
            ),
          ],
        ),
      );

  static const _umbrellaCodes = {'ADMIN_ACCESS', 'MASTERS_MANAGE'};
  static const _visibilityCodes = {
    'VIEW_VISTAR_MARGIN',
    'VIEW_TRANSPORTER_RATE',
    'VIEW_CUSTOMER_RATE',
  };
  bool _isUmbrella(String code) => _umbrellaCodes.contains(code);
  bool _isVisibility(String code) => _visibilityCodes.contains(code);

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
      );
    }
    final umbrella = _toggles.where((t) => _isUmbrella(t.code)).toList();
    final visibility = _toggles.where((t) => _isVisibility(t.code)).toList();
    final granular = _toggles
        .where((t) => !_isUmbrella(t.code) && !_isVisibility(t.code))
        .toList();
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (umbrella.isNotEmpty) ...[
          _sectionHeader('Umbrella permissions'),
          _umbrellaInfo(),
          for (final t in umbrella) _toggleTile(t),
        ],
        if (granular.isNotEmpty) ...[
          _sectionHeader('Granular permissions'),
          for (final t in granular) _toggleTile(t),
        ],
        if (visibility.isNotEmpty) ...[
          _sectionHeader('Visibility'),
          _visibilityInfo(),
          for (final t in visibility) _toggleTile(t),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppColors.slate,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _umbrellaInfo() => Container(
        margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.plum.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.plum.withValues(alpha: 0.15)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: AppColors.plum),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'These override every granular toggle below. If you leave '
                'ADMIN_ACCESS enabled, the granular restrictions below have no '
                'effect. Turn ADMIN_ACCESS off first, then use the granular '
                'toggles to grant back specific access.',
                style: TextStyle(
                    color: AppColors.slate, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      );

  Widget _visibilityInfo() => Container(
        margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.18)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.visibility_off_outlined,
                size: 16, color: AppColors.orange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Turning any of these off hides the corresponding money field '
                'everywhere — LR list, LR detail, printed LR, MIS Excel export, '
                'Route master. The backend also blocks the user from silently '
                'writing a value they can\'t see.',
                style: TextStyle(
                    color: AppColors.slate, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      );

  Widget _toggleTile(PermissionToggle t) {
    final value = _values[t.code] ?? t.effective;
    return SwitchListTile(
      value: value,
      onChanged: _saving ? null : (v) => _onToggle(t, v),
      title: Text(
        t.label,
        style:
            const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
      ),
      subtitle: value != t.roleDefault
          ? Text(
              'Overrides role default (${t.roleDefault ? 'allowed' : 'denied'})',
              style: const TextStyle(color: AppColors.orange, fontSize: 11.5),
            )
          : null,
      dense: true,
    );
  }

  Future<void> _onToggle(PermissionToggle t, bool v) async {
    // Denying an umbrella on an admin demotes them to only the granular grants —
    // confirm first (don't block).
    final turningUmbrellaOff =
        !v && _isUmbrella(t.code) && (_values[t.code] ?? t.effective);
    if (turningUmbrellaOff && widget.user.role == UserRole.admin) {
      final ok = await _confirmUmbrellaOff(t.code);
      if (!ok || !mounted) return;
    }
    setState(() => _values[t.code] = v);
  }

  Future<bool> _confirmUmbrellaOff(String code) async {
    final message = code == 'ADMIN_ACCESS'
        ? 'Denying ADMIN_ACCESS will demote this admin to only the specific '
            'granular permissions you leave enabled below. Continue?'
        : 'Denying MASTERS_MANAGE removes blanket master access — only the '
            'granular master permissions you leave enabled below will apply. '
            'Continue?';
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Turn off $code?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Widget _footer() => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Cancel',
              kind: BtnKind.ghost,
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 10),
            AppButton(
              label: _saving ? 'Saving…' : 'Save access',
              icon: Icons.save_outlined,
              onPressed: (_saving || _loading || _error != null) ? null : _save,
            ),
          ],
        ),
      );
}
