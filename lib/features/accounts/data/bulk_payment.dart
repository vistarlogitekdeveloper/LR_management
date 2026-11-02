import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/lr_models.dart';

/// Accounts → select several LRs and pay them in one go (2 Nov 2026). Each LR
/// goes through the SAME server call as its own button (POST
/// /lrs/:id/advance-paid or /payment-complete), one after another, so every
/// rule, amount and notification email is exactly as for a single LR.
enum BulkPayAction { advance, complete }

extension BulkPayActionX on BulkPayAction {
  String get label => switch (this) {
    BulkPayAction.advance => 'Mark Advance Paid',
    BulkPayAction.complete => 'Complete Payment',
  };

  String get done => switch (this) {
    BulkPayAction.advance => 'Advance marked paid',
    BulkPayAction.complete => 'Settled in full',
  };
}

/// LR ids ticked on the Accounts list. Cleared after a run (failures stay
/// ticked so they can be retried).
final accountsSelectionProvider = StateProvider<Set<String>>((ref) => {});

/// Whether [lr] can take [action] — the same test that shows its own button.
bool bulkEligible(LorryReceipt lr, BulkPayAction action) {
  final freight = lr.freight.freight;
  final advance = lr.freight.advance;
  return switch (action) {
    BulkPayAction.advance => advance <= 0 && freight > 0,
    BulkPayAction.complete => freight - advance > 0.01,
  };
}

/// The advance the server will release for [lr]: its advance % of the
/// transporter freight, rounded to the nearest 1,000 and clamped to the freight
/// (lrController.markAdvancePaid; same as the card's preview).
double bulkAdvanceAmount(LorryReceipt lr) {
  final freight = lr.freight.freight;
  final pct = lr.freight.advancePercent.clamp(0, 100).toDouble();
  return (((freight * (pct / 100)) / 1000).roundToDouble() * 1000)
      .clamp(0, freight)
      .toDouble();
}

/// What paying [lr] with [action] releases.
double bulkAmount(LorryReceipt lr, BulkPayAction action) => switch (action) {
  BulkPayAction.advance => bulkAdvanceAmount(lr),
  BulkPayAction.complete =>
    (lr.freight.freight - lr.freight.advance)
        .clamp(0, double.infinity)
        .toDouble(),
};

class BulkPayFailure {
  final LorryReceipt lr;
  final String message;
  const BulkPayFailure(this.lr, this.message);
}

class BulkPayResult {
  final List<LorryReceipt> paid;
  final List<BulkPayFailure> failed;

  /// Ticked LRs this action does not apply to (already paid, no advance yet…).
  final List<LorryReceipt> skipped;
  const BulkPayResult({
    this.paid = const [],
    this.failed = const [],
    this.skipped = const [],
  });
}

/// Pays [selected] one after another with [pay]. Ineligible LRs are skipped,
/// one failure never stops the rest, and [onProgress] reports (done, total).
/// [fresh] re-reads an LR right before its call, so each one carries its
/// latest version (the list may have refreshed while the batch ran).
Future<BulkPayResult> runBulkPay({
  required List<LorryReceipt> selected,
  required BulkPayAction action,
  required Future<void> Function(LorryReceipt lr) pay,
  required String Function(Object error) describe,
  LorryReceipt Function(LorryReceipt lr)? fresh,
  void Function(int done, int total)? onProgress,
}) async {
  final todo = <LorryReceipt>[];
  final skipped = <LorryReceipt>[];
  for (final lr in selected) {
    (bulkEligible(lr, action) ? todo : skipped).add(lr);
  }
  final paid = <LorryReceipt>[];
  final failed = <BulkPayFailure>[];
  for (var i = 0; i < todo.length; i++) {
    onProgress?.call(i, todo.length);
    final lr = fresh == null ? todo[i] : fresh(todo[i]);
    if (!bulkEligible(lr, action)) {
      // Paid by someone else while the batch ran.
      skipped.add(lr);
      continue;
    }
    try {
      await pay(lr);
      paid.add(lr);
    } catch (e) {
      failed.add(BulkPayFailure(lr, describe(e)));
    }
  }
  onProgress?.call(todo.length, todo.length);
  return BulkPayResult(paid: paid, failed: failed, skipped: skipped);
}
