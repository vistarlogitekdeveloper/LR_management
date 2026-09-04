// CONTRACT tests for the two scan-to-autofill endpoints.
//
// The fixtures in test/fixtures were captured by running the REAL backend
// services (vistar_CRM, offline Tesseract over rendered documents) and
// serialising exactly what their controllers send. So these fail when the
// server's shape and this client's expectations drift apart — the actual
// integration risk for a feature split across two repositories — rather than
// checking hand-written JSON that agrees with itself.
//
// The freight tests are the ones that matter most. A consignor's invoice
// states the value of the GOODS, not the freight: freight is negotiated with
// the transporter, and on a large consignment the two differ by more than an
// order of magnitude. Since `total` and `balance` are generated columns, a
// goods value written into `freight` would flow straight through to what
// Accounts pays out. Both directions are pinned below.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/shared/models/scan_result.dart';

void main() {
  Map<String, dynamic> data(String name) {
    final json =
        jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map;
    return (json['data'] as Map).cast<String, dynamic>();
  }

  group('invoice scan — goods value must never become freight', () {
    late ScannedLrDraft scan;
    setUp(() => scan = ScannedLrDraft.fromJson(data('lr_scan_invoice.json')));

    test('parses and produces a draft', () {
      expect(scan.readable, isTrue);
      expect(scan.hasDraft, isTrue);
      expect(scan.profile, 'gst-invoice');
    });

    test('freight is ABSENT from an invoice scan', () {
      // The single most consequential assertion in this file.
      expect(scan.draft.containsKey('freight'), isFalse);
    });

    test('the goods value lands on the invoice item instead', () {
      expect(scan.invoiceItems, isNotEmpty);
      expect(scan.invoiceItems.first['gross_value'], isNotNull);
    });

    test('and the user is told, in a warning flagged as important', () {
      expect(scan.goodsValueNotFreight, isTrue);
      final w = scan.warningWithCode('GOODS_VALUE_NOT_FREIGHT')!;
      // isImportant drives the prominent treatment in the confirm dialog.
      expect(w.isImportant, isTrue);
      expect(w.fields, contains('freight'));
    });

    test('the consignor resolves EXACTLY, on the GSTIN', () {
      // Consignors carry a gstin, and a GSTIN has a mod-36 check digit that
      // the server validates before querying — so this is an exact match on a
      // self-verifying key, not name similarity.
      final consignor = scan.resolved['consignor']!;
      expect(consignor.isResolved, isTrue);
      expect(consignor.confidence, greaterThanOrEqualTo(0.95));
      expect(consignor.matchedOn, contains('GSTIN'));
    });

    test('a plate written with spaces in the master still matches', () {
      // The master holds "MH 12 AB 1234"; the document reads "MH12AB1234".
      expect(scan.resolved['vehicle']!.isResolved, isTrue);
      expect(scan.draft['vehicle_id'], isNotNull);
    });

    test('the draft is honest about what it cannot fill', () {
      // An LR needs lookups that appear on no supplier document, so the
      // response says so rather than implying it can be saved as-is.
      expect(scan.missingRequired, contains('delivery_type_id'));
      expect(scan.warningWithCode('DRAFT_INCOMPLETE'), isNotNull);
    });
  });

  group('consignment note — freight IS stated here', () {
    late ScannedLrDraft scan;
    setUp(
        () => scan = ScannedLrDraft.fromJson(data('lr_scan_consignment.json')));

    test('freight is filled from a transporter note', () {
      // Same field, opposite treatment, because on this document a freight
      // amount really is the freight.
      expect(scan.draft['freight'], 75000);
    });

    test('and no goods-value warning is raised', () {
      expect(scan.goodsValueNotFreight, isFalse);
    });

    test('the payment type resolves from the tenant lookup', () {
      // Matched against the tenant's OWN configured PAY_TYPE labels — a paper
      // "TO PAY" with no matching row stays unresolved rather than being
      // mapped to whichever option looks closest, because that decides who
      // gets billed.
      expect(scan.draft['pay_type_id'], 'pt-1');
      expect(scan.resolved['payType']!.isResolved, isTrue);
    });

    test('no invoice items are invented', () {
      expect(scan.invoiceItems, isEmpty);
    });
  });

  group('cheque scan', () {
    late ScannedCheque scan;
    setUp(() => scan = ScannedCheque.fromJson(data('cheque_scan.json')));

    test('all five bank fields are read', () {
      expect(scan.readable, isTrue);
      expect(scan.ifsc, 'HDFC0000123');
      expect(scan.accountNo, '50200012345678');
      // "Bank" is both a label and part of every bank's name, so the server
      // falls back to the letterhead rather than returning the suffix.
      expect(scan.bankName, 'HDFC BANK LTD');
      expect(scan.accountHolder, 'KRISHNA ROADLINES PVT LTD');
      expect(scan.branch, 'CHAKAN PUNE');
      expect(scan.hasAnything, isTrue);
    });

    test('the account number is ALWAYS flagged for checking', () {
      // Not conditional on confidence: an account number has no checksum, no
      // format rule and no directory to verify against, so OCR cannot be
      // trusted with it — and a wrong one pays a stranger.
      final w = scan.warningWithCode('VERIFY_ACCOUNT_NUMBER');
      expect(w, isNotNull);
      expect(w!.isImportant, isTrue);
    });

    test('review metadata maps from bank_account keys to canonical names', () {
      // The values come back under bank_account keys (ifsc, account_no) while
      // review is keyed by the API's field names (ifscCode, accountNo), so
      // the mapping has to hold or the UI shows no confidence at all.
      expect(scan.reviewFor('ifsc'), isNotNull);
      expect(scan.reviewFor('account_no'), isNotNull);
      expect(scan.reviewFor('bank_name'), isNotNull);
    });

    test('the IFSC is structurally checkable, the account number is not', () {
      final ifsc = scan.reviewFor('ifsc')!;
      final acct = scan.reviewFor('account_no')!;
      // An IFSC has fixed letter/digit positions; an account number has
      // nothing, so it must never outrank the IFSC in confidence.
      expect(ifsc.confidence, greaterThan(acct.confidence));
    });
  });

  group('defensive parsing', () {
    test('an empty object does not throw', () {
      final lr = ScannedLrDraft.fromJson(const {});
      expect(lr.readable, isFalse);
      expect(lr.hasDraft, isFalse);
      expect(lr.invoiceItems, isEmpty);

      final cheque = ScannedCheque.fromJson(const {});
      expect(cheque.readable, isFalse);
      expect(cheque.hasAnything, isFalse);
    });

    test('unexpected types are tolerated', () {
      // A number the server later returns as a string must not crash the form.
      final lr = ScannedLrDraft.fromJson(const {
        'readable': true,
        'confidence': '84',
        'draft': {'freight': 75000},
        'review': {
          'freightAmount': {'confidence': '0.82', 'needsReview': false}
        },
        'resolved': {'consignor': {'id': '', 'confidence': '0'}},
        'missingRequired': 'not-a-list',
        'warnings': 'not-a-list',
      });
      expect(lr.pageConfidence, 84);
      expect(lr.review['freightAmount']!.confidence, closeTo(0.82, 0.001));
      // An empty id must read as unresolved, not as the empty string.
      expect(lr.resolved['consignor']!.isResolved, isFalse);
      expect(lr.missingRequired, isEmpty);
      expect(lr.warnings, isEmpty);
    });

    test('blank bank_account strings are treated as absent', () {
      final cheque = ScannedCheque.fromJson(const {
        'readable': true,
        'bankAccount': {'ifsc': '  ', 'account_no': ''},
      });
      expect(cheque.ifsc, isNull);
      expect(cheque.accountNo, isNull);
      expect(cheque.hasAnything, isFalse);
    });
  });
}
