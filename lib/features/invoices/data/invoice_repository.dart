import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/paginate.dart';
import 'invoice_models.dart';

/// Raised when `POST /invoices` is refused because one or more of the selected
/// LRs is already sitting on a live invoice (409 ALREADY_INVOICED).
///
/// This is the one server error the create screen has to act on rather than
/// merely show: it carries the offending LR NUMBERS so the screen can point at
/// the exact rows to deselect. The double-billing guard is a partial unique
/// index, so it also fires when two operators bill the same LR at the same
/// moment — the loser sees this, not a constraint name.
class AlreadyInvoicedException implements Exception {
  AlreadyInvoicedException({required this.message, this.lrNumbers = const []});

  /// The server's own sentence, already naming the LRs. Safe to show as-is.
  final String message;

  /// The LR numbers that clashed. Possibly empty if the server could not name
  /// them, in which case [message] still explains what happened.
  final List<String> lrNumbers;

  @override
  String toString() => message;
}

/// Sales invoices: list, read, issue, cancel, print, and the letterhead
/// settings row.
///
/// Every method surfaces the mapped [ApiException] rather than Dio's wrapper
/// (`throw e.error ?? e`), because the backend writes these messages for the
/// operator — "Only delivered LRs can be invoiced. Not delivered: …" is the
/// whole answer, and it must reach friendlyErrorMessage intact.
class InvoiceRepository {
  InvoiceRepository(this._api);
  final ApiClient _api;

  /// Invoice headers, newest first. Lines are NOT included — the server sends
  /// header rows only so one page stays a cheap query; use [get] for the
  /// document. [from]/[to] bound `invoice_date`, [status] is ISSUED or
  /// CANCELLED.
  Future<List<Invoice>> list({
    String? customerId,
    DateTime? from,
    DateTime? to,
    String? status,
  }) async {
    try {
      final rows = await fetchAllPages(
        _api,
        '/invoices',
        query: {
          if (customerId != null && customerId.isNotEmpty)
            'customer_id': customerId,
          if (from != null) 'from': invoiceDateOnly(from),
          if (to != null) 'to': invoiceDateOnly(to),
          if (status != null && status.isNotEmpty) 'status': status,
        },
      );
      return rows.map(Invoice.fromJson).toList();
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  /// One invoice with its lines and the LRs behind each line.
  Future<Invoice> get(String id) async {
    try {
      final res = await _api.dio.get('/invoices/$id');
      return Invoice.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  /// The LRs this customer may be billed for: delivered, unstamped, and not on
  /// a live invoice. Not paginated — the server returns the whole set, already
  /// ordered by LR date.
  Future<List<BillableLr>> billableLrs({
    required String customerId,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final res = await _api.dio.get(
        '/invoices/billable-lrs',
        queryParameters: {
          'customer_id': customerId,
          if (from != null) 'from': invoiceDateOnly(from),
          if (to != null) 'to': invoiceDateOnly(to),
        },
      );
      return ((res.data['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => BillableLr.fromJson(e.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  /// Issues an invoice. [payload] is the create body from the spec —
  /// `customer_id`, `lr_ids` and the optional header/letterhead overrides, with
  /// dates as `YYYY-MM-DD` (see [invoiceDateOnly]).
  ///
  /// Issuing ALLOCATES AN INVOICE NUMBER, so this must never be fired twice for
  /// one form: keep the submit button disabled while it is in flight. A
  /// double-submit does not double-bill (the unique index stops it), but it
  /// answers [AlreadyInvoicedException] rather than the invoice.
  Future<Invoice> create(Map<String, dynamic> payload) async {
    try {
      // Never auto-retried. Issuing an invoice allocates a number, stamps every
      // LR on it and is not idempotent; a socket dropped mid-request may well
      // have been applied, and the retry would come back ALREADY_INVOICED —
      // telling the user their invoice failed when it exists.
      final res = await _api.dio.post(
        '/invoices',
        data: payload,
        options: Options(extra: const {kNoRetryExtra: true}),
      );
      return Invoice.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      final api = asApiException(e);
      if (api != null && api.code == 'ALREADY_INVOICED') {
        throw AlreadyInvoicedException(
          message: api.message,
          lrNumbers: _lrNumbersOf(api.details),
        );
      }
      throw e.error ?? e;
    }
  }

  /// Cancels an invoice. The document stays readable; its LRs are released
  /// back into the billable pool and their bill stamp is cleared.
  Future<Invoice> cancel(String id) async {
    try {
      final res = await _api.dio.post('/invoices/$id/cancel');
      return Invoice.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  /// The rendered invoice as PDF bytes, for preview, share or save.
  ///
  /// The response type is bytes, so a server-side failure arrives as bytes too
  /// and cannot be parsed into the usual message — the caller gets the generic
  /// network sentence. Same trade-off the MIS/P&L downloads already make.
  Future<List<int>> pdfBytes(String id) async {
    try {
      final res = await _api.dio.get(
        '/invoices/$id.pdf',
        options: Options(responseType: ResponseType.bytes),
      );
      return (res.data as List).cast<int>();
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  /// The INVOICE_SETTINGS row, or null when it has never been written — which
  /// is a real state, not an error: no invoice can be issued until an admin
  /// fills it in, so the caller shows a "set this up first" prompt.
  Future<InvoiceSettings?> settings() async {
    try {
      final res = await _api.dio.get('/invoices/settings');
      final data = res.data['data'];
      if (data is! Map) return null;
      return InvoiceSettings.fromJson(data.cast<String, dynamic>());
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  /// Writes the letterhead settings. Admin-only on the server (the row holds
  /// the company's bank account number), and it rejects unknown keys — which is
  /// exactly why the payload comes from [InvoiceSettings.toJson] and is never
  /// hand-assembled at the call site.
  Future<InvoiceSettings> saveSettings(InvoiceSettings s) async {
    try {
      final res = await _api.dio.put('/invoices/settings', data: s.toJson());
      return InvoiceSettings.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  /// `lr_numbers` sits at the TOP LEVEL of the 409 body (the envelope helper
  /// spreads the extras next to `error`/`code`), and ApiException.details holds
  /// that whole body.
  static List<String> _lrNumbersOf(dynamic details) {
    if (details is! Map) return const [];
    final raw = details['lr_numbers'];
    if (raw is! List) return const [];
    return raw
        .where((e) => e != null)
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
