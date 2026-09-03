// Proves the LR list loads PROGRESSIVELY: a small first page paints almost
// immediately, then the rest streams in. Drives the REAL chain
// LrNotifier -> LrRepository -> fetchAllPages, faking only the HTTP transport,
// so the actual production code paths are exercised.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/core/network/api_client.dart';
import 'package:lr_management/core/network/paginate.dart';
import 'package:lr_management/core/network/token_storage.dart';
import 'package:lr_management/features/lr/data/lr_repository.dart';
import 'package:lr_management/features/lr/providers/lr_providers.dart';

class _MemTokens implements TokenStorage {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> readAccess() async => 'test';
  @override
  Future<String?> readRefresh() async => 'test';
  @override
  Future<void> write({required String access, required String refresh}) async {}
}

/// Serves /lrs as two cursor pages and records the `limit` of every request so
/// the first-page-small / rest-large sizing can be asserted. A configurable
/// delay on page 2 lets a test observe the intermediate (page-1-only) state.
class _PagedAdapter implements HttpClientAdapter {
  _PagedAdapter({
    required this.page1,
    required this.page2,
    this.failPage2 = false,
  });

  final List<Map<String, dynamic>> page1;
  final List<Map<String, dynamic>> page2;

  /// When true, the second (cursor) request returns HTTP 400 so the bulk page
  /// fails — used to exercise a mid-stream error. Mutable so a test can succeed
  /// the first full load, then fail a later refresh.
  bool failPage2;
  final List<String> limits = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? _,
    Future<void>? _,
  ) async {
    limits.add('${options.queryParameters['limit']}');
    final hasCursor = (options.queryParameters['cursor'] ?? '') != '';
    Map<String, dynamic> body;
    if (!hasCursor) {
      body = {
        'success': true,
        'data': page1,
        'meta': {'next_cursor': 'CURSOR2'},
      };
    } else {
      if (failPage2) {
        // HTTP 400 → Dio throws badResponse (not retried like a 5xx), so the
        // bulk page fails mid-stream.
        return ResponseBody.fromString(
          jsonEncode({'success': false, 'error': 'boom'}),
          400,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      body = {
        'success': true,
        'data': page2,
        'meta': {'next_cursor': null},
      };
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

List<Map<String, dynamic>> _rows(String prefix, int n) => [
  for (var i = 0; i < n; i++)
    {
      'id': '$prefix$i',
      'number': 'LR/$prefix/$i',
      'lr_date': '2026-07-01',
      'entered_by': 'u1',
    },
];

ApiClient _client(HttpClientAdapter adapter) {
  final c = ApiClient(_MemTokens());
  c.dio.httpClientAdapter = adapter;
  return c;
}

void main() {
  test(
    'fetchAllPages: small first page, large rest, onPage per page',
    () async {
      final adapter = _PagedAdapter(page1: _rows('a', 3), page2: _rows('b', 2));
      final api = _client(adapter);
      final pages = <int>[];
      final all = await fetchAllPages(
        api,
        '/lrs',
        firstPageSize: 100,
        pageSize: 1000,
        onPage: (p) => pages.add(p.length),
      );
      expect(pages, [3, 2]); // fired once per page, in order
      expect(all.length, 5); // full accumulated set returned
      expect(adapter.limits, ['100', '1000']); // first small, rest large
    },
  );

  test(
    'fetchAllPages: empty result fires onPage once with an empty page',
    () async {
      final api = _client(_OnePageAdapter(const []));
      final pages = <int>[];
      final all = await fetchAllPages(
        api,
        '/lrs',
        onPage: (p) => pages.add(p.length),
      );
      expect(all, isEmpty);
      expect(pages, [
        0,
      ]); // empty page still emitted so consumers clear stale rows
    },
  );

  test(
    'LrNotifier paints page 1 separately, before the full set (progressive)',
    () async {
      final adapter = _PagedAdapter(
        page1: _rows('a', 100),
        page2: _rows('b', 50),
      );
      final repo = LrRepository(_client(adapter), const {});
      final notifier = LrNotifier(repo, null);

      // Record every list length the notifier emits, and complete once the full
      // set (150) lands. Deterministic — no arbitrary delays to race: the notifier
      // sets state once per page, so the first page's 100 is always emitted before
      // the final 150 regardless of how fast the pages resolve.
      final lengths = <int>[];
      final done = Completer<void>();
      notifier.addListener((state) {
        lengths.add(state.length);
        if (state.length == 150 && !done.isCompleted) done.complete();
      }, fireImmediately: true);

      await done.future.timeout(const Duration(seconds: 5));

      expect(
        lengths.contains(100),
        isTrue,
        reason: 'the first page painted on its own, before the rest arrived',
      );
      expect(lengths.last, 150, reason: 'the full set is shown once loaded');
      expect(
        lengths.indexOf(100) < lengths.lastIndexOf(150),
        isTrue,
        reason: '100 must be emitted before the final 150',
      );

      notifier.dispose();
    },
  );

  test(
    'concurrent refreshes settle to the full list (generation guard)',
    () async {
      final adapter = _PagedAdapter(
        page1: _rows('a', 100),
        page2: _rows('b', 50),
      );
      final repo = LrRepository(_client(adapter), const {});
      final notifier = LrNotifier(repo, null); // constructor fires refresh #1
      // A second refresh right away simulates RefreshGate's on-entry fetch racing
      // the constructor's initial load on first mount.
      final second = notifier.refresh();
      final done = Completer<void>();
      notifier.addListener((s) {
        if (s.length == 150 && !done.isCompleted) done.complete();
      }, fireImmediately: true);
      await second;
      await done.future.timeout(const Duration(seconds: 5));
      expect(notifier.state.length, 150, reason: 'settles to the complete set');
      notifier.dispose();
    },
  );

  test('warm refresh with a mid-stream error keeps the FULL prior list '
      '(no truncation to the partial first page)', () async {
    final adapter = _PagedAdapter(
      page1: _rows('a', 100),
      page2: _rows('b', 50),
    );
    final repo = LrRepository(_client(adapter), const {});
    final notifier = LrNotifier(repo, null); // load #1 succeeds fully (150)
    final loaded = Completer<void>();
    notifier.addListener((s) {
      if (s.length == 150 && !loaded.isCompleted) loaded.complete();
    }, fireImmediately: true);
    await loaded.future.timeout(const Duration(seconds: 5));
    expect(notifier.state.length, 150);

    // A refresh where the bulk page fails must NOT shrink the list to 100.
    adapter.failPage2 = true;
    await notifier.refresh();
    expect(
      notifier.state.length,
      150,
      reason: 'the already-loaded full list is preserved on a mid-stream error',
    );
    notifier.dispose();
  });

  test('cold load with a mid-stream error keeps the partial first page '
      '(better than an empty list)', () async {
    final adapter = _PagedAdapter(
      page1: _rows('a', 100),
      page2: _rows('b', 50),
      failPage2: true,
    );
    final repo = LrRepository(_client(adapter), const {});
    final notifier = LrNotifier(repo, null); // cold: empty -> streams page 1
    final painted = Completer<void>();
    notifier.addListener((s) {
      if (s.length == 100 && !painted.isCompleted) painted.complete();
    }, fireImmediately: true);
    await painted.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(
      const Duration(milliseconds: 50),
    ); // let page 2 fail
    expect(
      notifier.state.length,
      100,
      reason: 'partial first page is kept rather than reset to empty',
    );
    notifier.dispose();
  });

  test(
    'LrNotifier: an empty result clears to an empty list (no stale rows)',
    () async {
      final repo = LrRepository(_client(_OnePageAdapter(const [])), const {});
      final notifier = LrNotifier(repo, null);
      await Future.delayed(const Duration(milliseconds: 30));
      expect(notifier.state, isEmpty);
      notifier.dispose();
    },
  );
}

/// A single-page adapter (no next_cursor) for the empty-result cases.
class _OnePageAdapter implements HttpClientAdapter {
  _OnePageAdapter(this.data);
  final List<Map<String, dynamic>> data;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? _,
    Future<void>? _,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'data': data,
        'meta': {'next_cursor': null},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
