// Changing the driver mid-trip (LR/PUN/26-27/01317: the driver changed at
// Khalghat and tracking kept following the previous driver's phone).
//
// The parsing of what the server answered, the rules of the driver picker,
// and the dialog itself: it can only submit a trackable new driver, says what
// will happen, keeps a refusal on screen, and hands back the result.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/core/network/api_exception.dart';
import 'package:lr_management/features/masters/providers/master_providers.dart';
import 'package:lr_management/features/tracking/data/driver_change.dart';
import 'package:lr_management/features/tracking/data/driver_change_rules.dart';
import 'package:lr_management/features/tracking/data/tracking_repository.dart';
import 'package:lr_management/features/tracking/providers/tracking_providers.dart';
import 'package:lr_management/features/tracking/widgets/change_driver_dialog.dart';
import 'package:lr_management/shared/models/driver.dart';

const _mansar = Driver(
  id: 'd-old',
  name: 'MANSAR',
  mobile: '9630716391',
  licenseNo: 'MP13 2019',
);
const _raju = Driver(
  id: 'd-new',
  name: 'RAJU',
  mobile: '98220 11223',
  licenseNo: 'MH12 2020',
);
const _anil = Driver(
  id: 'd-3',
  name: 'Anil',
  mobile: '12345',
  licenseNo: 'KA01',
);
const _bina = Driver(id: 'd-4', name: 'bina', mobile: '', licenseNo: 'GJ05');

Map<String, dynamic> _answer(
  Map<String, dynamic> tracking, {
  List<String> also = const [],
}) => {
  'driver': {'id': 'd-new', 'name': 'RAJU', 'mobile': '9822011223'},
  'also_changed': also,
  'closed_halt': true,
  'public_link_reset': true,
  'tracking': tracking,
};

void main() {
  group('the server answer', () {
    test('started, consent pending: says the new driver must approve', () {
      final r = DriverChangeResult.fromJson(
        _answer({
          'state': 'STARTED',
          'consent_status': 'PENDING',
          'consent_suggestion': 'Reply Y',
        }),
      );
      expect(r.move, TrackingMove.started);
      expect(r.closedHalt, isTrue);
      expect(r.publicLinkReset, isTrue);
      expect(r.simBusy, isFalse);
      expect(r.summary, contains("Tracking moved to RAJU's phone"));
      expect(r.summary, contains('must approve the SIM consent'));
    });

    test('started with consent already given', () {
      final r = DriverChangeResult.fromJson(
        _answer({'state': 'STARTED', 'consent_status': 'ALLOWED'}),
      );
      expect(
        r.summary,
        "Driver changed to RAJU. Tracking now follows RAJU's phone.",
      );
    });

    test(
      'the new phone busy on another truck is a SIM clash, carrying the message',
      () {
        final r = DriverChangeResult.fromJson(
          _answer({
            'state': 'START_REFUSED',
            'code': 'SIM_BUSY',
            'message': 'already being tracked for MH12ZZ0001',
          }),
        );
        expect(r.move, TrackingMove.refused);
        expect(r.simBusy, isTrue);
        expect(r.summary, contains('already being tracked for MH12ZZ0001'));
      },
    );

    test('another refusal is not a SIM clash', () {
      final r = DriverChangeResult.fromJson(
        _answer({
          'state': 'START_REFUSED',
          'code': 'BAD_MOBILE',
          'message': 'bad',
        }),
      );
      expect(r.simBusy, isFalse);
    });

    test('provider down, same phone, tracking off, truck-mates', () {
      expect(
        DriverChangeResult.fromJson(_answer({'state': 'START_FAILED'})).summary,
        contains('press Start tracking again'),
      );
      expect(
        DriverChangeResult.fromJson(_answer({'state': 'SAME_PHONE'})).summary,
        contains('same phone'),
      );
      expect(
        DriverChangeResult.fromJson(_answer({'state': 'DISABLED'})).move,
        TrackingMove.disabled,
      );
      final mates = DriverChangeResult.fromJson(
        _answer(
          {'state': 'STARTED', 'consent_status': 'ALLOWED'},
          also: ['LR/PUN/26-27/01318'],
        ),
      );
      expect(
        mates.summary,
        contains('LR/PUN/26-27/01318 on the same truck changed too'),
      );
    });

    test(
      'a missing or unknown tracking block reads as a failure, never a crash',
      () {
        expect(DriverChangeResult.fromJson(const {}).move, TrackingMove.failed);
        expect(
          DriverChangeResult.fromJson(const {
            'tracking': {'state': 'WHAT'},
          }).move,
          TrackingMove.failed,
        );
      },
    );
  });

  group('the tracking screen data', () {
    test('handovers, the current driver and a fix from the previous phone', () {
      final t = LrTracking.fromJson({
        'lr_id': 'lr1',
        'driver_id': 'd-new',
        'fix_before_driver_change': true,
        'driver_changes': [
          {
            'id': 'c1',
            'changed_at': '2026-10-10T08:30:00Z',
            'from_driver_name': 'MANSAR',
            'to_driver_name': 'RAJU',
            'lat': '22.0000000',
            'lng': 75.5,
            'city': 'Khalghat',
            'note': 'shift change',
            'source': 'TRACKING',
          },
          {'id': 'c2', 'source': 'LR_EDIT'},
        ],
      });
      expect(t.driverId, 'd-new');
      expect(t.fixBeforeDriverChange, isTrue);
      expect(t.driverChanges, hasLength(2));
      expect(t.driverChanges.first.city, 'Khalghat');
      expect(t.driverChanges.first.lat, 22.0);
      expect(t.driverChanges.first.fromLrEdit, isFalse);
      expect(t.driverChanges.last.fromLrEdit, isTrue);
      expect(t.driverChanges.last.lat, isNull);
    });

    test('an older server without the fields reads as no handovers', () {
      final t = LrTracking.fromJson({'lr_id': 'lr1'});
      expect(t.driverChanges, isEmpty);
      expect(t.fixBeforeDriverChange, isFalse);
      expect(t.driverId, isNull);
    });

    test(
      'a halt closed by the handover reads as "Driver changed" but is never pickable',
      () {
        final h = TripHalt.fromJson({
          'id': 'h1',
          'ack_reason': 'DRIVER_CHANGED',
        });
        expect(h.ackReason, HaltReason.driverChanged);
        expect(h.ackReason!.label, 'Driver changed');
        expect(HaltReasonX.pickable, isNot(contains(HaltReason.driverChanged)));
        expect(HaltReasonX.pickable, hasLength(6));
      },
    );
  });

  group('the driver picker', () {
    final all = [_mansar, _raju, _anil, _bina];

    test('never offers the current driver; sorted by name', () {
      final c = changeDriverCandidates(all, currentDriverId: 'd-old');
      expect(c.map((d) => d.name), [
        'RAJU',
        'Anil',
        'bina',
      ], reason: 'trackable first');
    });

    test(
      'finds by name, licence or (3+) digits of the mobile, ignoring spaces',
      () {
        expect(
          changeDriverCandidates(
            all,
            currentDriverId: 'd-old',
            query: 'raj',
          ).single.id,
          'd-new',
        );
        expect(
          changeDriverCandidates(
            all,
            currentDriverId: 'd-old',
            query: 'mh12',
          ).single.id,
          'd-new',
        );
        expect(
          changeDriverCandidates(
            all,
            currentDriverId: 'd-old',
            query: '2011 223',
          ).single.id,
          'd-new',
        );
        expect(
          changeDriverCandidates(all, currentDriverId: 'd-old', query: '96307'),
          isEmpty,
          reason: 'that is the current driver',
        );
        expect(
          changeDriverCandidates(all, currentDriverId: 'd-old', query: 'zzz'),
          isEmpty,
        );
      },
    );

    test(
      'a driver without a valid mobile is shown with the reason, not offered',
      () {
        expect(changeDriverBlocker(_raju), isNull);
        expect(
          changeDriverBlocker(_anil),
          contains('not a valid 10-digit number'),
        );
        expect(changeDriverBlocker(_bina), contains('No mobile number'));
      },
    );
  });

  group('the dialog', () {
    testWidgets('submits only a trackable driver, then hands back the result', (
      tester,
    ) async {
      final repo = _Repo(
        result: DriverChangeResult.fromJson(
          _answer({'state': 'STARTED', 'consent_status': 'PENDING'}),
        ),
      );
      DriverChangeResult? got;
      await _pumpOpener(tester, repo, (r) => got = r);

      expect(find.text('Change driver'), findsWidgets);
      expect(
        find.text('MANSAR'),
        findsNothing,
        reason: 'the current driver is not offered',
      );
      final submit = find.widgetWithText(FilledButton, 'Change driver');
      expect(
        tester.widget<FilledButton>(submit).onPressed,
        isNull,
        reason: 'nothing picked yet',
      );

      await tester.tap(find.text('Anil'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(submit).onPressed,
        isNull,
        reason: 'an untrackable driver cannot be picked',
      );

      await tester.tap(find.text('RAJU'));
      await tester.pump();
      expect(find.text('What happens'), findsOneWidget);
      expect(
        find.textContaining("MANSAR's phone stops being tracked"),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Note (optional)'),
        'shift change at Khalghat',
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(repo.calls, [('lr1', 'd-new', 'shift change at Khalghat')]);
      expect(got?.move, TrackingMove.started);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets(
      'a refusal stays in the dialog to be read; nothing is returned',
      (tester) async {
        final repo = _Repo(
          error: ApiException(
            status: 400,
            code: 'DRIVER_INACTIVE',
            message: 'RAJU is marked inactive. Pick an active driver.',
          ),
        );
        DriverChangeResult? got;
        var closed = false;
        await _pumpOpener(tester, repo, (r) {
          got = r;
          closed = true;
        });
        await tester.tap(find.text('RAJU'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Change driver'));
        await tester.pumpAndSettle();
        expect(
          find.text('RAJU is marked inactive. Pick an active driver.'),
          findsOneWidget,
        );
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(closed, isFalse);
        expect(got, isNull);
      },
    );

    testWidgets('on a short laptop window the buttons stay reachable', (
      tester,
    ) async {
      final repo = _Repo(
        result: DriverChangeResult.fromJson(
          _answer({'state': 'STARTED', 'consent_status': 'ALLOWED'}),
        ),
      );
      DriverChangeResult? got;
      await _pumpOpener(
        tester,
        repo,
        (r) => got = r,
        size: const Size(1000, 640),
      );
      await tester.tap(find.text('RAJU'));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'no layout error');
      final submit = find.widgetWithText(FilledButton, 'Change driver');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(got?.move, TrackingMove.started);
    });

    testWidgets('cancel returns nothing and calls nothing', (tester) async {
      final repo = _Repo();
      DriverChangeResult? got;
      var closed = false;
      await _pumpOpener(tester, repo, (r) {
        got = r;
        closed = true;
      });
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(got, isNull);
      expect(repo.calls, isEmpty);
    });

    testWidgets(
      'the search narrows the list; no match explains where to add a driver',
      (tester) async {
        await _pumpOpener(tester, _Repo(), (_) {});
        await tester.enterText(
          find.widgetWithText(TextField, 'Search name, mobile or licence'),
          'bin',
        );
        await tester.pump();
        expect(find.text('bina'), findsOneWidget);
        expect(find.text('RAJU'), findsNothing);
        await tester.enterText(
          find.widgetWithText(TextField, 'Search name, mobile or licence'),
          'nobody',
        );
        await tester.pump();
        expect(
          find.textContaining('Add the new driver in Masters → Drivers'),
          findsOneWidget,
        );
      },
    );
  });
}

Future<void> _pumpOpener(
  WidgetTester tester,
  _Repo repo,
  void Function(DriverChangeResult?) onClosed, {
  Size size = const Size(1200, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trackingRepositoryProvider.overrideWithValue(repo),
        driversProvider.overrideWith(
          (ref) => _Drivers([_mansar, _raju, _anil, _bina]),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final r = await showChangeDriverDialog(
                    context,
                    lrId: 'lr1',
                    currentDriverId: 'd-old',
                    currentDriverName: 'MANSAR',
                  );
                  onClosed(r);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

class _Repo implements TrackingRepository {
  _Repo({this.result, this.error});
  final DriverChangeResult? result;
  final Object? error;
  final calls = <(String, String, String?)>[];

  @override
  Future<DriverChangeResult> changeDriver(
    String lrId, {
    required String driverId,
    String? note,
  }) async {
    calls.add((lrId, driverId, note));
    if (error != null) throw error!;
    return result ?? const DriverChangeResult();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Drivers extends StateNotifier<List<Driver>> implements DriversNotifier {
  _Drivers(super.state);

  @override
  Future<void> refresh() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
