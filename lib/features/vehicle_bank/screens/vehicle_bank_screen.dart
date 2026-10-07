import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../reports/services/export_service.dart';
import '../../shell/widgets/app_topbar.dart';
import '../data/ledger_workbook.dart';
import '../data/vehicle_bank_models.dart';
import '../providers/vehicle_bank_providers.dart';
import '../widgets/ledger_directory.dart';
import '../widgets/ledger_table.dart' show ledgerTableBreakpoint;
import '../widgets/vehicle_bank_filters.dart';

/// Vendor ledger, sourced from the LR table: one row per driver/owner +
/// transporter + lane we have actually run a load on, deduplicated server-side.
///
/// It answers a different question from the vehicle master, which only knows who
/// is attached to a truck today. A driver who ran forty loads last year and has
/// since been unassigned is absent there and present here.
///
/// Nothing writes. Editing stays in the master screens so this data keeps
/// exactly one write path, and no rate of any kind is shown — route rates are
/// permission-gated elsewhere and this directory is shared widely. The Aadhaar
/// and the bank block arrive already resolved by the service (full only for a
/// holder of VEHICLE_BANK_PII_VIEW, masked or empty otherwise); they are
/// rendered as given and never reassembled.
class VehicleBankScreen extends ConsumerStatefulWidget {
  const VehicleBankScreen({super.key});

  @override
  ConsumerState<VehicleBankScreen> createState() => _VehicleBankScreenState();
}

class _VehicleBankScreenState extends ConsumerState<VehicleBankScreen> {
  bool _exporting = false;

  void _refresh() {
    final filter = ref.read(vehicleBankFilterProvider);
    ref.invalidate(vehicleBankLedgerProvider(filter));
  }

  /// Saves the ledger as an .xlsx built from the rows currently on screen.
  ///
  /// Built client-side, from those exact rows, so the sheet IS the screen and
  /// the two cannot drift — and so the export inherits the server's PII
  /// decision for free: rows in hand are already masked or blank for a caller
  /// without VEHICLE_BANK_PII_VIEW, so the download can never carry more than
  /// was displayed. The button is inert while this runs: a second tap would
  /// build the whole sheet twice.
  Future<void> _export() async {
    if (_exporting) return;
    final rows = ref.read(currentVehicleBankLedgerProvider).valueOrNull;
    final messenger = ScaffoldMessenger.of(context);
    if (rows == null || rows.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nothing to export yet')),
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final bytes = buildLedgerWorkbook(rows);
      if (bytes == null) throw StateError('empty workbook');
      final day = DateTime.now().toIso8601String().substring(0, 10);
      await ExportService.shareBytes(bytes, 'Vehicle_Directory_$day.xlsx');
      // A large sheet can outlive the screen; the messenger was captured before
      // the await, but posting to a disposed one still throws.
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Exported ${rows.length} entries')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export: ${friendlyErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(vehicleBankFilterProvider);
    final rowsAsync = ref.watch(currentVehicleBankLedgerProvider);
    final pad = MediaQuery.sizeOf(context).width < 600 ? 14.0 : 28.0;

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Vehicle Bank',
            subtitle:
                'Every driver, owner and transporter we have run a load with — '
                'one line per lane',
            actions: [
              AppButton(
                label: 'Refresh',
                icon: Icons.refresh_rounded,
                kind: BtnKind.ghost,
                small: true,
                onPressed: _refresh,
              ),
              AppButton(
                label: 'Download Excel',
                icon: Icons.file_download_outlined,
                kind: BtnKind.soft,
                small: true,
                loading: _exporting,
                onPressed: _export,
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            child: const VehicleBankFilters(),
          ),
          Expanded(
            child: switch (rowsAsync) {
              AsyncError(:final error) => _ErrorState(
                message: friendlyErrorMessage(error),
                onRetry: _refresh,
              ),
              AsyncData(:final value) =>
                value.isEmpty
                    ? _EmptyState(
                        filtered: filter.hasFilters,
                        onClearFilters: () =>
                            ref.read(vehicleBankFilterProvider.notifier).state =
                                VehicleBankFilter.empty,
                      )
                    : LedgerDirectory(rows: value, padding: pad),
              // Loading, including a refetch after a filter change: a skeleton
              // says "rows are coming", a bare spinner reads like an empty
              // fleet.
              _ => _LoadingState(padding: pad),
            },
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.padding});

  final double padding;

  @override
  Widget build(BuildContext context) {
    // Measured the same way the real content is — the window is wider than
    // this pane by the width of the app's sidebar, so MediaQuery would promise
    // a table and then hand over cards.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.all(padding),
        child: constraints.maxWidth < ledgerTableBreakpoint
            ? const ShimmerCards(cards: 6, height: 108)
            : const AppCard(
                padding: EdgeInsets.all(16),
                child: ShimmerRows(rows: 9, showLeadingIcon: false),
              ),
      ),
    );
  }
}

/// Nothing to show. A fleet that has never been entered and a filter set that
/// matches nothing are different problems, so they get different words and
/// only the second one gets a way out.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered, required this.onClearFilters});

  final bool filtered;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return _Placeholder(
      icon: Icons.local_shipping_outlined,
      tint: AppColors.plum,
      title: filtered ? 'No entries match these filters' : 'No entries yet',
      body: filtered
          ? 'Try a different region, another pair of cities, or clear the '
                'filters to see everyone.'
          : 'A driver, owner or transporter appears here as soon as an LR is '
                'raised naming them — one line per lane they run.',
      action: filtered
          ? AppButton(
              label: 'Clear filters',
              icon: Icons.filter_alt_off_outlined,
              kind: BtnKind.ghost,
              onPressed: onClearFilters,
            )
          : null,
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Placeholder(
      icon: Icons.cloud_off_rounded,
      tint: AppColors.danger,
      title: 'Could not load the Vehicle Bank',
      // The backend writes these for the operator (a missing permission, a
      // rejected filter), so the message is shown as written rather than
      // replaced with a generic apology.
      body: message,
      action: AppButton(
        label: 'Retry',
        icon: Icons.refresh_rounded,
        onPressed: onRetry,
      ),
    );
  }
}

/// The shared shape of the empty and error states: a tinted glyph, a headline,
/// a sentence saying what to do next, and at most one button.
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.tint,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final button = action;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 30, color: tint),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.slate),
              ),
              if (button != null) ...[const SizedBox(height: 16), button],
            ],
          ),
        ),
      ),
    );
  }
}
