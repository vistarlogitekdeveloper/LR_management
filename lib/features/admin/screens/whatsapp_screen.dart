import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/section_title.dart';
import '../../shell/widgets/app_topbar.dart';
import '../data/whatsapp_repository.dart';

/// Admin → WhatsApp Alerts (super admin; server /whatsapp, 2 Nov 2026): is
/// WhatsApp on, which alerts go out, a test message, and the delivery log.
/// The token and number live in the server environment, never in the app.
class WhatsappScreen extends ConsumerStatefulWidget {
  const WhatsappScreen({super.key});

  @override
  ConsumerState<WhatsappScreen> createState() => _WhatsappScreenState();
}

class _WhatsappScreenState extends ConsumerState<WhatsappScreen> {
  final _mobile = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _mobile.dispose();
    super.dispose();
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _toggle(WhatsappAlertKind k, bool on) async {
    try {
      await ref.read(whatsappRepositoryProvider).setAlert(k.kind, on);
      ref.invalidate(whatsappStatusProvider);
    } catch (e) {
      _say(friendlyErrorMessage(e));
    }
  }

  Future<void> _test() async {
    setState(() => _sending = true);
    try {
      await ref.read(whatsappRepositoryProvider).sendTest(_mobile.text.trim());
      _say('Test message sent. Check WhatsApp on ${_mobile.text.trim()}.');
      ref.invalidate(whatsappMessagesProvider);
    } catch (e) {
      _say(friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(whatsappStatusProvider);
    final log = ref.watch(whatsappMessagesProvider);
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          const AppTopbar(
            title: 'WhatsApp Alerts',
            subtitle: 'Halt and zero-margin alerts on WhatsApp',
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(whatsappStatusProvider);
                ref.invalidate(whatsappMessagesProvider);
              },
              child: ListView(
                padding: EdgeInsets.all(mobile ? 14 : 28),
                children: [
                  status.when(
                    loading: () =>
                        const AppCard(child: LinearProgressIndicator()),
                    error: (e, _) =>
                        AppCard(child: Text(friendlyErrorMessage(e))),
                    data: (s) => _statusCard(s),
                  ),
                  const SizedBox(height: 16),
                  _testCard(status.valueOrNull?.enabled ?? false),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle(
                          icon: Icons.receipt_long_outlined,
                          title: 'Sent alerts',
                        ),
                        const SizedBox(height: 8),
                        log.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (e, _) => Text(friendlyErrorMessage(e)),
                          data: (rows) => rows.isEmpty
                              ? const Text(
                                  'Nothing sent yet.',
                                  style: TextStyle(color: AppColors.slate),
                                )
                              : Column(
                                  children: [
                                    for (final m in rows) WhatsappLogRow(m: m),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(WhatsappStatus s) {
    final (color, text) = s.enabled
        ? (AppColors.ok, 'On — alerts are being sent on WhatsApp.')
        : s.configured
        ? (
            AppColors.warn,
            'Set up but switched off on the server (WHATSAPP_ENABLED).',
          )
        : (
            AppColors.slate,
            'Not set up yet: the Meta token and phone number are not on the server.',
          );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.chat_outlined, title: 'Status'),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.circle, size: 12, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Transparent Material: the card is coloured, and a ListTile paints
          // its ripple on the nearest Material.
          for (final k in s.alerts)
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                key: ValueKey('wa-${k.kind}'),
                contentPadding: EdgeInsets.zero,
                value: k.on,
                activeThumbColor: AppColors.plum,
                onChanged: (v) => _toggle(k, v),
                title: Text(
                  k.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Template: ${k.template}',
                  style: const TextStyle(fontSize: 12, color: AppColors.slate),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _testCard(bool enabled) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          icon: Icons.send_outlined,
          title: 'Send a test message',
        ),
        const SizedBox(height: 6),
        const Text(
          'Sends Meta\'s "hello_world" message to one number, to check the setup.',
          style: TextStyle(fontSize: 12, color: AppColors.slate),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                key: const ValueKey('wa-test-mobile'),
                controller: _mobile,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  isDense: true,
                ),
              ),
            ),
            AppButton(
              label: 'Send test',
              icon: Icons.send_rounded,
              small: true,
              loading: _sending,
              onPressed: enabled && !_sending ? _test : null,
            ),
          ],
        ),
      ],
    ),
  );
}

/// One sent alert: kind, number, when, and how far it got.
class WhatsappLogRow extends StatelessWidget {
  final WhatsappMessage m;
  const WhatsappLogRow({super.key, required this.m});

  @override
  Widget build(BuildContext context) {
    final color = switch (m.status) {
      'read' => AppColors.ok,
      'delivered' => AppColors.ok,
      'sent' => AppColors.plum,
      'failed' => AppColors.danger,
      _ => AppColors.slate,
    };
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          m.status == 'failed' ? Icons.error_outline : Icons.done_all_rounded,
          color: color,
        ),
        title: Text(
          '${m.kind} → +${m.toPhone}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            if (m.createdAt != null) formatDateTime(m.createdAt!),
            if (m.status == 'failed' && (m.error ?? '').isNotEmpty) m.error!,
          ].join(' · '),
        ),
        trailing: Text(
          m.status.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }
}
