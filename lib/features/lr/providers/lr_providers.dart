import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_providers.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/models/user.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lookups/providers/lookups_provider.dart';
import '../data/lr_repository.dart';

class LrFilter {
  final String query;
  final LrStatus? status;
  final String? route;
  final String? region; // region_id; null = all regions
  final DateTime? fromDate; // inclusive lower bound (date-only); null = no min
  final DateTime? toDate; // inclusive upper bound (date-only); null = no max

  const LrFilter({
    this.query = '',
    this.status,
    this.route,
    this.region,
    this.fromDate,
    this.toDate,
  });

  LrFilter copyWith(
      {String? query,
      LrStatus? status,
      String? route,
      String? region,
      DateTime? fromDate,
      DateTime? toDate,
      bool clearStatus = false,
      bool clearRoute = false,
      bool clearRegion = false,
      bool clearDates = false}) {
    return LrFilter(
      query: query ?? this.query,
      status: clearStatus ? null : (status ?? this.status),
      route: clearRoute ? null : (route ?? this.route),
      region: clearRegion ? null : (region ?? this.region),
      fromDate: clearDates ? null : (fromDate ?? this.fromDate),
      toDate: clearDates ? null : (toDate ?? this.toDate),
    );
  }
}

final lrRepositoryProvider = Provider<LrRepository>((ref) {
  final lookups = ref.watch(lookupsProvider).valueOrNull ?? const {};
  return LrRepository(ref.watch(apiClientProvider), lookups);
});

class LrNotifier extends StateNotifier<List<LorryReceipt>> {
  LrNotifier(this._repo, this._user) : super(const []) {
    refresh();
  }
  final LrRepository _repo;
  final AppUser? _user;

  /// Bumped on each refresh so a superseded load (e.g. the constructor's initial
  /// fetch and RefreshGate's on-entry fetch racing on first mount, or a fast
  /// re-navigation) stops writing state — only the latest refresh paints. Without
  /// this, two concurrent progressive loads could interleave their per-page
  /// writes and make the list visibly jump.
  int _refreshGen = 0;

  /// Timestamp of the last successful load. Used to skip a re-fetch when the
  /// user re-navigates to a screen whose data is still fresh — see [_freshFor].
  DateTime? _lastOk;

  /// A refresh already in flight — subsequent callers await the same future
  /// instead of triggering a duplicate walk of /lrs. Cleared when the fetch
  /// settles (whenComplete), so a later call starts a fresh one.
  Future<void>? _pending;

  /// Data younger than this is served from cache; a re-entry within the window
  /// is a no-op. Kept short so anything the user just changed elsewhere
  /// (create / edit / status change) still surfaces on a fresh nav within
  /// seconds. Explicit refresh (pull-to-refresh, force=true) bypasses this.
  static const _freshFor = Duration(seconds: 30);

  /// Operators may only see the LRs they created — region scope alone still
  /// exposes peers' consignments. Admins / super admins / accounts see the full
  /// (backend-scoped) set.
  ///
  /// NOTE: this is a UI-side filter. For true enforcement the backend must also
  /// scope GET /lrs and GET /lrs/:id by created_by for operators.
  List<LorryReceipt> _scoped(List<LorryReceipt> all) {
    final u = _user;
    if (u != null && u.isOperator) {
      return all.where((lr) => lr.enteredBy == u.id).toList();
    }
    return all;
  }

  /// Fetches the LR list, applying two short-circuits:
  ///   * TTL (`_freshFor`): a re-nav within the window returns immediately;
  ///     the screen renders from the cached state without another API hit.
  ///   * In-flight dedupe (`_pending`): if a fetch is already running (e.g.
  ///     the notifier constructor kicked one off and RefreshGate then tried
  ///     to as well), the second caller awaits the same future.
  /// Callers that need bypass (pull-to-refresh, after a mutation elsewhere)
  /// pass `force: true`.
  Future<void> refresh({bool force = false}) {
    if (!force &&
        state.isNotEmpty &&
        _lastOk != null &&
        DateTime.now().difference(_lastOk!) < _freshFor) {
      return Future.value();
    }
    return _pending ??= _doRefresh().whenComplete(() => _pending = null);
  }

  Future<void> _doRefresh() async {
    try {
      // Render progressively: each page repaints the list as it arrives, so the
      // first ~100 LRs show almost immediately instead of waiting for the whole
      // set. The shimmer (gated on an empty list) clears as soon as page 1
      // lands. `mounted` guards against a state write after disposal.
      final gen = ++_refreshGen;
      // Only paint progressively on a COLD list (first load / empty). When the
      // list is already populated (a re-open / pull-to-refresh), we already show
      // data, so streaming per-page gives nothing — and, crucially, replacing
      // the full list with a partial first page would truncate it if a later
      // page then failed. So on a warm list we accumulate silently and commit
      // the full set once, keeping the prior list intact on any mid-stream error.
      final paintProgressively = state.isEmpty;
      final acc = <LorryReceipt>[];
      final all = await _repo.list(
        onPage: (page) {
          // Stop if disposed or superseded by a newer refresh.
          if (!mounted || gen != _refreshGen) return;
          acc.addAll(page);
          if (paintProgressively) state = _scoped(List.of(acc));
        },
      );
      // Authoritative final state — also clears stale rows on an empty result,
      // where no non-empty page callback replaced them.
      if (mounted && gen == _refreshGen) {
        state = _scoped(all);
        _lastOk = DateTime.now();
      }
    } catch (_) {
      // A transient backend/DB error shouldn't crash the UI; keep prior state.
    }
  }

  Future<LorryReceipt> create(Map<String, dynamic> payload,
      {EwbInput? ewb, String? idempotencyKey}) async {
    final created =
        await _repo.create(payload, ewb: ewb, idempotencyKey: idempotencyKey);
    state = [created, ...state];
    return created;
  }

  /// Runs a write that carries an `If-Match: <version>` header. On a 412
  /// VERSION_CONFLICT (the DB moved past the version we sent — e.g. another
  /// tab/user/backend trigger bumped it between our last list fetch and this
  /// click), silently refetch the specific LR so the UI reflects the current
  /// server state, then rethrow. The caller shows a friendly "please try
  /// again" message; the user's next click carries the fresh version and
  /// succeeds.
  ///
  /// We deliberately don't auto-retry the write: payment endpoints trigger
  /// notification emails and record timestamps, so re-firing without an
  /// explicit user confirmation risks double-notifications on an already-
  /// completed action.
  Future<LorryReceipt> _versionSafeWrite(
    String id,
    Future<LorryReceipt> Function() write,
  ) async {
    try {
      return await write();
    } on ApiException catch (e) {
      if (e.isVersionConflict) {
        await _refetchOne(id);
      }
      rethrow;
    }
  }

  /// Reload a single LR from the server and replace it in local state — used
  /// after a version conflict so the next click carries the current version.
  /// Best-effort: if the refetch itself fails (network drop, 5xx), we keep
  /// the stale row and let the caller surface the original conflict.
  Future<void> _refetchOne(String id) async {
    try {
      final fresh = await _repo.getById(id);
      if (!mounted) return;
      state = [for (final lr in state) lr.id == id ? fresh : lr];
    } catch (_) {}
  }

  Future<LorryReceipt> updateLr(
    String id,
    int version,
    Map<String, dynamic> payload, {
    EwbInput? ewb,
    String? existingEwbId,
    int existingEwbVersion = 0,
  }) =>
      _versionSafeWrite(id, () async {
        final updated = await _repo.update(id, version, payload,
            ewb: ewb,
            existingEwbId: existingEwbId,
            existingEwbVersion: existingEwbVersion);
        state = [for (final lr in state) lr.id == updated.id ? updated : lr];
        return updated;
      });

  /// Marks the 90% transporter advance as paid (backend computes the amount and
  /// triggers the notification email), then refreshes the LR in local state.
  Future<LorryReceipt> markAdvancePaid(String id, int version) =>
      _versionSafeWrite(id, () async {
        final updated = await _repo.markAdvancePaid(id, version);
        state = [for (final lr in state) lr.id == updated.id ? updated : lr];
        return updated;
      });

  /// Completes the payment (releases the POD balance; backend settles the amount
  /// and triggers the notification email), then refreshes the LR in local state.
  Future<LorryReceipt> completePayment(String id, int version) =>
      _versionSafeWrite(id, () async {
        final updated = await _repo.completePayment(id, version);
        state = [for (final lr in state) lr.id == updated.id ? updated : lr];
        return updated;
      });

  /// Sends the LR to Accounts for payment (backend flips the flag + emails
  /// Accounts), then refreshes the LR in local state.
  Future<LorryReceipt> sendForPayment(String id, int version) =>
      _versionSafeWrite(id, () async {
        final updated = await _repo.sendForPayment(id, version);
        state = [for (final lr in state) lr.id == updated.id ? updated : lr];
        return updated;
      });

  Future<void> changeStatus(String id, LrStatus to, {String? reason}) async {
    await _repo.changeStatus(id, to.code, reason: reason);
    final fresh = await _repo.getById(id);
    state = [for (final lr in state) lr.id == id ? fresh : lr];
  }

  Future<void> remove(String id) async {
    await _repo.remove(id);
    state = state.where((lr) => lr.id != id).toList();
  }

  LorryReceipt? findById(String id) {
    for (final lr in state) {
      if (lr.id == id) return lr;
    }
    return null;
  }
}

final lrListProvider =
    StateNotifierProvider<LrNotifier, List<LorryReceipt>>((ref) {
  return LrNotifier(
    ref.watch(lrRepositoryProvider),
    ref.watch(currentUserProvider),
  );
});

/// First-load flag for the LR list: `true` until the initial GET /lrs settles
/// (cleared by the route's RefreshGate). The list screen shows a shimmer while
/// this is true AND the list is still empty, so a pending fetch no longer looks
/// like an empty result.
final lrListLoadingProvider = StateProvider<bool>((ref) => true);

final lrFilterProvider = StateProvider<LrFilter>((ref) => const LrFilter());

final filteredLrsProvider = Provider<List<LorryReceipt>>((ref) {
  final list = ref.watch(lrListProvider);
  final filter = ref.watch(lrFilterProvider);
  return list.where((lr) {
    if (filter.status != null && lr.status != filter.status) return false;
    if (filter.route != null && lr.route != filter.route) return false;
    if (filter.region != null && lr.regionId != filter.region) return false;
    if (filter.fromDate != null || filter.toDate != null) {
      // Compare by calendar day so both endpoints are inclusive regardless of
      // any time component on lr.date / the picked bounds.
      final d = DateTime(lr.date.year, lr.date.month, lr.date.day);
      final from = filter.fromDate;
      final to = filter.toDate;
      if (from != null &&
          d.isBefore(DateTime(from.year, from.month, from.day))) {
        return false;
      }
      if (to != null && d.isAfter(DateTime(to.year, to.month, to.day))) {
        return false;
      }
    }
    if (filter.query.isNotEmpty) {
      final q = filter.query.toLowerCase();
      final hay = [
        lr.number,
        lr.consignor.name,
        lr.consignee.name,
        lr.vehicle.number,
        lr.route,
        lr.ewb?.number ?? '',
      ].join(' ').toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }).toList();
});

/// Quick summary lookup from the already-loaded list.
final lrByIdProvider = Provider.family<LorryReceipt?, String>((ref, id) {
  final list = ref.watch(lrListProvider);
  for (final lr in list) {
    if (lr.id == id) return lr;
  }
  return null;
});

/// Full LR detail (invoice items, attachments, freight, EWB) fetched on demand.
final lrDetailProvider =
    FutureProvider.autoDispose.family<LorryReceipt, String>((ref, id) async {
  return ref.watch(lrRepositoryProvider).getById(id);
});
