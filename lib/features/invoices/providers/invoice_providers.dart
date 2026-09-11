import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../../../shared/models/user.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/invoice_models.dart';
import '../data/invoice_repository.dart';

final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) => InvoiceRepository(ref.watch(apiClientProvider)),
);

// ---- Permissions -----------------------------------------------------------
// Mirrors the two tiers the routes enforce. The server is the authority; these
// only decide what the UI OFFERS, so a hidden button is never the protection.

bool _hasAny(AppUser? user, List<String> codes) {
  if (user == null) return false;
  for (final code in codes) {
    if (user.can(code)) return true;
  }
  return false;
}

/// May open the invoices module at all (INVOICE_VIEW tier).
final canViewInvoicesProvider = Provider<bool>(
  (ref) => _hasAny(ref.watch(currentUserProvider), const [
    'INVOICE_VIEW',
    'ADMIN_ACCESS',
    'SUPERADMIN_ACCESS',
  ]),
);

/// May issue and cancel invoices (INVOICE_MANAGE tier).
final canManageInvoicesProvider = Provider<bool>(
  (ref) => _hasAny(ref.watch(currentUserProvider), const [
    'INVOICE_MANAGE',
    'ADMIN_ACCESS',
    'SUPERADMIN_ACCESS',
  ]),
);

/// May WRITE the letterhead settings. Deliberately narrower than
/// [canManageInvoicesProvider]: that row carries the company's bank account
/// number, so billing a customer is not the same right as re-pointing where
/// that customer pays. Reading the settings only needs view access.
final canEditInvoiceSettingsProvider = Provider<bool>(
  (ref) => _hasAny(ref.watch(currentUserProvider), const [
    'ADMIN_ACCESS',
    'SUPERADMIN_ACCESS',
  ]),
);

// ---- Invoice list ----------------------------------------------------------

/// Filters for the invoice list. Held in a provider rather than in screen
/// fields so the list survives a rebuild, a tab switch and a back-navigation.
class InvoiceListFilter {
  /// Customer party id; null = every customer.
  final String? customerId;

  /// Inclusive `invoice_date` bounds; null = unbounded.
  final DateTime? from;
  final DateTime? to;

  /// ISSUED | CANCELLED; null = both.
  final String? status;

  const InvoiceListFilter({this.customerId, this.from, this.to, this.status});

  bool get isEmpty =>
      customerId == null && from == null && to == null && status == null;

  InvoiceListFilter copyWith({
    String? customerId,
    DateTime? from,
    DateTime? to,
    String? status,
    bool clearCustomer = false,
    bool clearDates = false,
    bool clearStatus = false,
  }) {
    return InvoiceListFilter(
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      from: clearDates ? null : (from ?? this.from),
      to: clearDates ? null : (to ?? this.to),
      status: clearStatus ? null : (status ?? this.status),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is InvoiceListFilter &&
      other.customerId == customerId &&
      other.from == from &&
      other.to == to &&
      other.status == status;

  @override
  int get hashCode => Object.hash(customerId, from, to, status);
}

final invoiceListFilterProvider = StateProvider<InvoiceListFilter>(
  (ref) => const InvoiceListFilter(),
);

/// Invoice headers for the current filter, newest first. Refresh with
/// `ref.invalidate(invoiceListProvider)` after issuing or cancelling one.
final invoiceListProvider = FutureProvider.autoDispose<List<Invoice>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  final filter = ref.watch(invoiceListFilterProvider);
  return ref
      .watch(invoiceRepositoryProvider)
      .list(
        customerId: filter.customerId,
        from: filter.from,
        to: filter.to,
        status: filter.status,
      );
});

/// One invoice with its lines and LR links — the detail and PDF screens.
final invoiceDetailProvider = FutureProvider.autoDispose
    .family<Invoice, String>(
      (ref, id) => ref.watch(invoiceRepositoryProvider).get(id),
    );

// ---- Billable LRs ----------------------------------------------------------

/// The query behind the create screen's LR picker. Value-equal so the family
/// hands back the SAME provider across rebuilds instead of refetching.
class BillableLrsQuery {
  /// Customer party id. Empty means "none picked yet" — the provider then
  /// resolves to an empty list without calling the server, which requires it.
  final String customerId;
  final DateTime? from;
  final DateTime? to;

  const BillableLrsQuery({this.customerId = '', this.from, this.to});

  bool get hasCustomer => customerId.isNotEmpty;

  BillableLrsQuery copyWith({
    String? customerId,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
  }) {
    return BillableLrsQuery(
      customerId: customerId ?? this.customerId,
      from: clearDates ? null : (from ?? this.from),
      to: clearDates ? null : (to ?? this.to),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BillableLrsQuery &&
      other.customerId == customerId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(customerId, from, to);
}

/// The create screen's customer + date-range selection, kept in a provider so
/// it survives a rebuild while the picker is open.
final billableLrsQueryProvider = StateProvider<BillableLrsQuery>(
  (ref) => const BillableLrsQuery(),
);

/// Billable LRs for a query. Returns an empty list — not an error — before a
/// customer is chosen, so the screen shows its "pick a customer" empty state.
final billableLrsProvider = FutureProvider.autoDispose
    .family<List<BillableLr>, BillableLrsQuery>((ref, query) async {
      if (!query.hasCustomer) return const [];
      return ref
          .watch(invoiceRepositoryProvider)
          .billableLrs(
            customerId: query.customerId,
            from: query.from,
            to: query.to,
          );
    });

/// The ticked LR ids on the create screen.
///
/// A provider rather than a `Set` field on the State so the selection survives
/// a rebuild — and, more importantly, so [retain] can drop ids that have left
/// the billable list (the range changed, or someone else billed them). Sending
/// a stale id is not harmless: it either 404s the whole create or trips the
/// double-billing guard.
class BillableSelection extends StateNotifier<Set<String>> {
  BillableSelection() : super(const <String>{});

  bool isSelected(String id) => state.contains(id);

  void toggle(String id) {
    final next = Set<String>.from(state);
    if (!next.remove(id)) next.add(id);
    state = next;
  }

  void selectAll(Iterable<String> ids) => state = Set<String>.from(ids);

  void clear() => state = const <String>{};

  /// Keeps only ids still present in [ids].
  void retain(Iterable<String> ids) {
    final allowed = ids.toSet();
    final next = state.where(allowed.contains).toSet();
    if (next.length != state.length) state = next;
  }
}

final billableSelectionProvider =
    StateNotifierProvider.autoDispose<BillableSelection, Set<String>>(
      (ref) => BillableSelection(),
    );

// ---- Letterhead settings ---------------------------------------------------

/// The INVOICE_SETTINGS row, or null when an admin has not written it yet.
/// Null is a real state: no invoice can be issued until it exists, and the
/// create screen also seeds its HSN/SAC, service mode and line title from it.
/// Invalidate after a save.
final invoiceSettingsProvider = FutureProvider.autoDispose<InvoiceSettings?>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.watch(invoiceRepositoryProvider).settings();
});
