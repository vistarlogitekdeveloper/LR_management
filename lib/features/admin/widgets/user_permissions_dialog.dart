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
      messenger.showSnackBar(SnackBar(content: Text(_errorMessage(e))));
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
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final t in _toggles)
          SwitchListTile(
            value: _values[t.code] ?? t.effective,
            onChanged: _saving
                ? null
                : (v) => setState(() => _values[t.code] = v),
            title: Text(
              t.label,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            subtitle: (_values[t.code] ?? t.effective) != t.roleDefault
                ? Text(
                    'Overrides role default (${t.roleDefault ? 'allowed' : 'denied'})',
                    style: const TextStyle(
                        color: AppColors.orange, fontSize: 11.5),
                  )
                : null,
            dense: true,
          ),
      ],
    );
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
