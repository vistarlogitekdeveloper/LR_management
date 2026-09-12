import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../reports/services/export_service.dart';
import '../../shell/widgets/app_topbar.dart';
import '../data/vehicle_bank_models.dart';
import '../data/vehicle_bank_repository.dart';
import '../providers/vehicle_bank_providers.dart';
import '../widgets/vehicle_bank_filters.dart';

/// Below this the nine-column table is unreadable, so each vehicle becomes a
/// stacked card instead — the same break the rest of the app uses.
const double _tableBreakpoint = 720;

/// The table never squeezes below this: nine columns sharing 720 px produce
/// eight ellipsised words. Between the two the table scrolls sideways inside
/// its own box, which is the only horizontal scrolling on the page.
const double _minTableWidth = 1120;

/// A document lapsing inside this many days is called out in the warning
/// colour; anything already past is an error, not a warning. Reading a fleet's
/// paperwork off a list of dates is what this screen exists to spare people.
const int _expirySoonDays = 30;

/// Read-only fleet directory: one row per vehicle carrying its transporter,
/// current driver and assigned route, filterable and exportable.
///
/// Nothing here writes. Editing stays in the master screens so this data keeps
/// exactly one write path, and the screen shows no rate of any kind — route
/// rates are permission-gated elsewhere and this directory is shared widely.
/// The transporter Aadhaar arrives already masked from the service; it is
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
    ref.invalidate(vehicleBankRowsProvider(filter));
  }

  /// Downloads the server-built workbook for the filters currently applied.
  ///
  /// The workbook comes from the same service as the table, so it can never
  /// carry a column the screen hides. The button is inert while this runs: a
  /// second tap would build the whole sheet twice.
  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final filter = ref.read(vehicleBankFilterProvider);
      final bytes = await ref
          .read(vehicleBankRepositoryProvider)
          .exportXlsx(filter);
      final day = DateTime.now().toIso8601String().substring(0, 10);
      await ExportService.shareBytes(bytes, 'Vehicle_Bank_$day.xlsx');
      // A large fleet can outlive the screen; the messenger was captured
      // before the awaits, but posting to a disposed one still throws.
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Vehicle Bank exported')),
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
    final rowsAsync = ref.watch(currentVehicleBankRowsProvider);
    final pad = MediaQuery.sizeOf(context).width < 600 ? 14.0 : 28.0;

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Vehicle Bank',
            subtitle:
                'Every vehicle with its transporter, driver and route on one '
                'line',
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
              AsyncData(:final value) => value.isEmpty
                  ? _EmptyState(
                      filtered: filter.hasFilters,
                      onClearFilters: () =>
                          ref.read(vehicleBankFilterProvider.notifier).state =
                              VehicleBankFilter.empty,
                    )
                  : _Directory(rows: value, padding: pad),
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
        child: constraints.maxWidth < _tableBreakpoint
            ? const ShimmerCards(cards: 6, height: 108)
            : const AppCard(
                padding: EdgeInsets.all(16),
                child: ShimmerRows(rows: 9, showLeadingIcon: false),
              ),
      ),
    );
  }
}

/// The vehicles themselves: a table on a wide screen, stacked cards on a
/// phone. Wrapped in a [SelectionArea] so a registration number or a driver's
/// mobile can be copied straight out of the directory.
class _Directory extends StatelessWidget {
  const _Directory({required this.rows, required this.padding});

  final List<VehicleBankRow> rows;
  final double padding;

  @override
  Widget build(BuildContext context) {
    // Read the clock once per build and pass it down, so every expiry badge in
    // one frame is measured against the same day and no leaf widget has to
    // reach for DateTime.now() itself.
    final today = DateUtils.dateOnly(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padding, 14, padding, 8),
          child: _ResultCount(count: rows.length),
        ),
        Expanded(
          child: SelectionArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < _tableBreakpoint) {
                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) =>
                        _VehicleCard(row: rows[i], today: today),
                  );
                }
                return Padding(
                  padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
                  child: _VehicleTable(
                    rows: rows,
                    today: today,
                    width: constraints.maxWidth - padding * 2,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // The repository walks pages up to this ceiling; at the ceiling the list is
    // a prefix of the fleet, and saying so beats letting someone conclude the
    // missing trucks were sold.
    final capped = count >= VehicleBankRepository.maxRows;
    final noun = count == 1 ? 'vehicle' : 'vehicles';
    return Text(
      capped
          ? 'First $count $noun — narrow the filters to see the rest'
          : '$count $noun',
      style: const TextStyle(
        color: AppColors.slate,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _VehicleTable extends StatelessWidget {
  const _VehicleTable({
    required this.rows,
    required this.today,
    required this.width,
  });

  final List<VehicleBankRow> rows;
  final DateTime today;
  final double width;

  @override
  Widget build(BuildContext context) {
    final tableWidth = width < _minTableWidth ? _minTableWidth : width;
    return AppCard(
      padding: const EdgeInsets.all(4),
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            // Header and body share one horizontal scroll box, so a column
            // heading never drifts away from its column.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _TableHeader(),
                const Divider(height: 1, color: AppColors.line),
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: AppColors.line),
                    itemBuilder: (context, i) =>
                        _TableRow(row: rows[i], today: today),
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

/// Column widths as flex units. The order is the reading order of the
/// directory: what the truck is, then who is attached to it, then what is
/// about to lapse.
const List<(String, int)> _columns = [
  ('Registration', 16),
  ('Type', 11),
  ('Capacity', 10),
  ('Region', 11),
  ('Transporter', 18),
  ('Driver', 16),
  ('Licence', 14),
  ('Route', 18),
  ('Expiry', 16),
];

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.plum.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          for (final (label, flex) in _columns)
            Expanded(
              flex: flex,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    fontSize: 12.5,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.row, required this.today});

  final VehicleBankRow row;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final expiry = _ExpiryStatus.of(row, today);
    final licenceExpiry = row.driverLicenseExpiry;
    final licence = _urgencyOf(licenceExpiry, today);
    final distanceKm = row.routeDistanceKm;
    // One entry per column, in the same order as _columns — they are indexed
    // together below.
    final cells = <Widget>[
      _Cell(
        title: _or(row.registrationNo),
        strong: true,
        subtitle: row.active ? (row.hasGps ? 'GPS fitted' : '') : 'Inactive',
        subtitleColor: row.active ? AppColors.ok : AppColors.danger,
      ),
      _Cell(title: _or(row.vehicleType)),
      _Cell(
        title: _or(_capacityText(row.capacityMt)),
        subtitle: _lengthText(row.lengthFt),
      ),
      _Cell(title: _or(row.regionName)),
      _TransporterCell(row: row),
      _Cell(title: _or(row.driverName), subtitle: row.driverMobile),
      _Cell(
        title: _or(row.driverLicenseNo),
        subtitle: licenceExpiry == null ? '' : formatDate(licenceExpiry),
        subtitleColor: licence == _Urgency.none ? null : _colorOf(licence),
        subtitleStrong: licence != _Urgency.none,
      ),
      _Cell(
        title: row.routeLabel.isEmpty ? '—' : row.routeLabel,
        subtitle: distanceKm == null ? '' : '${distanceKm.round()} km',
      ),
      _ExpiryCell(status: expiry),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _columns.length; i++)
            Expanded(
              flex: _columns[i].$2,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: cells[i],
              ),
            ),
        ],
      ),
    );
  }
}

/// A two-line table cell. No fixed height anywhere: at textScaler 2.0 the row
/// simply grows.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.title,
    this.subtitle = '',
    this.strong = false,
    this.subtitleColor,
    this.subtitleStrong = false,
  });

  final String title;
  final String subtitle;
  final bool strong;
  final Color? subtitleColor;
  final bool subtitleStrong;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: strong ? 13.5 : 13,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: subtitleStrong ? FontWeight.w800 : FontWeight.w600,
              color: subtitleColor ?? AppColors.slate,
            ),
          ),
        ],
      ],
    );
  }
}

/// Transporter name and mobile, with the KYC references on the tooltip rather
/// than in a column of their own — the Aadhaar is shown exactly as the service
/// masked it.
class _TransporterCell extends StatelessWidget {
  const _TransporterCell({required this.row});

  final VehicleBankRow row;

  @override
  Widget build(BuildContext context) {
    final kyc = [
      if (row.transporterPan.isNotEmpty) 'PAN ${row.transporterPan}',
      if (row.transporterAadhaarMasked.isNotEmpty)
        'Aadhaar ${row.transporterAadhaarMasked}',
      if (row.transporterTdsApplicable) 'TDS applicable',
    ].join('\n');
    final cell = _Cell(
      title: _or(row.transporterName),
      subtitle: row.transporterMobile,
    );
    if (kyc.isEmpty) return cell;
    return Tooltip(message: kyc, child: cell);
  }
}

class _ExpiryCell extends StatelessWidget {
  const _ExpiryCell({required this.status});

  final _ExpiryStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) {
      return const _Cell(title: '—', subtitle: 'No papers on file');
    }
    final color = _colorOf(s.urgency);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (s.urgency != _Urgency.none) ...[
              Icon(
                s.urgency == _Urgency.expired
                    ? Icons.error_outline_rounded
                    : Icons.warning_amber_rounded,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                formatDate(s.date),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${s.document} · ${s.note}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: s.urgency == _Urgency.none ? AppColors.slate : color,
          ),
        ),
      ],
    );
  }
}

/// One vehicle as a stacked card, for phone widths.
class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.row, required this.today});

  final VehicleBankRow row;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final expiry = _ExpiryStatus.of(row, today);
    final licenceExpiry = row.driverLicenseExpiry;
    final licence = _urgencyOf(licenceExpiry, today);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _or(row.registrationNo),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!row.active)
                const _Tag(text: 'Inactive', color: AppColors.danger)
              else if (row.hasGps)
                const _Tag(text: 'GPS', color: AppColors.ok),
            ],
          ),
          const SizedBox(height: 10),
          _CardLine(
            label: 'Vehicle',
            value: [
              _or(row.vehicleType),
              _capacityText(row.capacityMt),
              _lengthText(row.lengthFt),
            ].where((v) => v.isNotEmpty && v != '—').join(' · '),
          ),
          _CardLine(label: 'Region', value: _or(row.regionName)),
          _CardLine(
            label: 'Transporter',
            value: [
              _or(row.transporterName),
              row.transporterMobile,
            ].where((v) => v.isNotEmpty && v != '—').join(' · '),
          ),
          // Masked by the service; rendered verbatim.
          if (row.transporterAadhaarMasked.isNotEmpty ||
              row.transporterPan.isNotEmpty)
            _CardLine(
              label: 'KYC',
              value: [
                if (row.transporterPan.isNotEmpty) row.transporterPan,
                if (row.transporterAadhaarMasked.isNotEmpty)
                  row.transporterAadhaarMasked,
              ].join(' · '),
            ),
          _CardLine(
            label: 'Driver',
            value: [
              _or(row.driverName),
              row.driverMobile,
            ].where((v) => v.isNotEmpty && v != '—').join(' · '),
          ),
          _CardLine(
            label: 'Licence',
            value: [
              _or(row.driverLicenseNo),
              if (licenceExpiry != null) 'till ${formatDate(licenceExpiry)}',
            ].where((v) => v.isNotEmpty && v != '—').join(' · '),
            valueColor: licence == _Urgency.none ? null : _colorOf(licence),
          ),
          _CardLine(
            label: 'Route',
            value: row.routeLabel.isEmpty ? '—' : row.routeLabel,
          ),
          if (expiry != null) ...[
            const SizedBox(height: 10),
            _ExpiryBanner(status: expiry),
          ],
        ],
      ),
    );
  }
}

class _CardLine extends StatelessWidget {
  const _CardLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? AppColors.ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card's version of the expiry column — a tinted strip, because on a
/// phone this is the line people open the directory for.
class _ExpiryBanner extends StatelessWidget {
  const _ExpiryBanner({required this.status});

  final _ExpiryStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _colorOf(status.urgency);
    final calm = status.urgency == _Urgency.none;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: calm ? AppColors.mist : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            calm
                ? Icons.verified_outlined
                : (status.urgency == _Urgency.expired
                      ? Icons.error_outline_rounded
                      : Icons.warning_amber_rounded),
            size: 16,
            color: calm ? AppColors.slate : color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${status.document} ${status.note} '
              '(${formatDate(status.date)})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: calm ? AppColors.slate : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
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
      title: filtered
          ? 'No vehicles match these filters'
          : 'No vehicles in the bank yet',
      body: filtered
          ? 'Try a different region, another pair of cities, or clear the '
                'filters to see the whole fleet.'
          : 'Vehicles appear here as soon as they are added in the Vehicles '
                'master, together with their transporter, driver and route.',
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

enum _Urgency { none, soon, expired }

/// The soonest of a vehicle's four documents to lapse, and how urgent that is.
class _ExpiryStatus {
  const _ExpiryStatus({
    required this.document,
    required this.date,
    required this.days,
  });

  /// Which paper it is — "Insurance" is a different errand from "PUC".
  final String document;
  final DateTime date;

  /// Days from today; negative once the date has passed.
  final int days;

  _Urgency get urgency => _urgencyFromDays(days);

  String get note => switch (urgency) {
    _Urgency.expired => days == -1 ? 'expired yesterday' : 'expired',
    _Urgency.soon => days == 0
        ? 'expires today'
        : 'expires in $days ${days == 1 ? 'day' : 'days'}',
    _Urgency.none => 'valid',
  };

  static _ExpiryStatus? of(VehicleBankRow row, DateTime today) {
    (String, DateTime)? soonest;
    for (final doc in <(String, DateTime?)>[
      ('Fitness', row.fitnessExpiry),
      ('Insurance', row.insuranceExpiry),
      ('Permit', row.permitExpiry),
      ('PUC', row.pucExpiry),
    ]) {
      final date = doc.$2;
      if (date == null) continue;
      if (soonest == null || date.isBefore(soonest.$2)) {
        soonest = (doc.$1, date);
      }
    }
    if (soonest == null) return null;
    return _ExpiryStatus(
      document: soonest.$1,
      date: soonest.$2,
      days: DateUtils.dateOnly(soonest.$2).difference(today).inDays,
    );
  }
}

/// The same scale the vehicle documents use, applied to any single date — the
/// driver's licence gets the identical treatment, because an expired licence
/// stops the truck just as surely as an expired permit.
_Urgency _urgencyOf(DateTime? date, DateTime today) {
  if (date == null) return _Urgency.none;
  return _urgencyFromDays(DateUtils.dateOnly(date).difference(today).inDays);
}

_Urgency _urgencyFromDays(int days) {
  if (days < 0) return _Urgency.expired;
  return days <= _expirySoonDays ? _Urgency.soon : _Urgency.none;
}

Color _colorOf(_Urgency urgency) => switch (urgency) {
  _Urgency.expired => AppColors.danger,
  _Urgency.soon => AppColors.warn,
  _Urgency.none => AppColors.ink,
};

String _or(String value) => value.trim().isEmpty ? '—' : value;

/// Tonnes without noise digits: 12 rather than "12.0", 12.5 kept.
String _capacityText(double? mt) {
  if (mt == null || mt <= 0) return '';
  return '${mt.toStringAsFixed(mt.truncateToDouble() == mt ? 0 : 1)} MT';
}

String _lengthText(double? ft) {
  if (ft == null || ft <= 0) return '';
  return '${ft.toStringAsFixed(ft.truncateToDouble() == ft ? 0 : 1)} ft';
}
