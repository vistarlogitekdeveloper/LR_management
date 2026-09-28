import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/features/tracking/data/trip_history.dart';
import 'package:lr_management/shared/models/consignee.dart';
import 'package:lr_management/shared/models/consignor.dart';
import 'package:lr_management/shared/models/lr_models.dart';
import 'package:lr_management/shared/models/transporter.dart';
import 'package:lr_management/shared/models/vehicle.dart';

/// Fixed "now" so the rolling-period cases don't drift with the wall clock.
final _now = DateTime(2026, 9, 16);

LorryReceipt _lr({
  required String id,
  required String number,
  required DateTime date,
  LrStatus status = LrStatus.delivered,
  String truck = 'MH12AB1234',
  String driver = '',
  String fromCity = 'PUNE',
  String toCity = 'DEWAS',
  String consignor = 'RAPL',
  String consignee = 'SMVL',
}) => LorryReceipt(
  id: id,
  number: number,
  date: date,
  enteredBy: 'u1',
  consignor: Consignor(
    id: 'c1',
    name: consignor,
    gst: '',
    city: '',
    address: '',
    contact: '',
    mobile: '',
    email: '',
  ),
  consignee: Consignee(
    id: 'c2',
    name: consignee,
    gst: '',
    location: '',
    address: '',
    contact: '',
    mobile: '',
  ),
  vehicle: Vehicle(id: 'v1', number: truck, driver: driver),
  transporter: const Transporter(id: 't1', name: '', pan: '', tds: 'No'),
  route: '$fromCity → $toCity',
  fromCity: fromCity,
  toCity: toCity,
  items: const [],
  freight: const FreightDetails(),
  payType: PayType.tbb,
  deliveryType: DeliveryType.doorDelivery,
  status: status,
);

void main() {
  group('filterTripHistory', () {
    test('keeps only finished trips, newest first', () {
      final rows = filterTripHistory([
        _lr(id: '1', number: 'LR/1', date: DateTime(2026, 9, 1)),
        _lr(
          id: '2',
          number: 'LR/2',
          date: DateTime(2026, 9, 10),
          status: LrStatus.inTransit,
        ),
        _lr(
          id: '3',
          number: 'LR/3',
          date: DateTime(2026, 9, 5),
          status: LrStatus.cancelled,
        ),
        _lr(
          id: '4',
          number: 'LR/4',
          date: DateTime(2026, 9, 8),
          status: LrStatus.booked,
        ),
      ], now: _now);

      expect(rows.map((e) => e.number), ['LR/3', 'LR/1']);
    });

    test('excludes LRs still showing on the Active tab', () {
      final rows = filterTripHistory(
        [
          _lr(id: 'a', number: 'LR/A', date: DateTime(2026, 9, 1)),
          _lr(id: 'b', number: 'LR/B', date: DateTime(2026, 9, 2)),
        ],
        excludeLrIds: {'b'},
        now: _now,
      );

      expect(rows.single.number, 'LR/A');
    });

    test('status filter narrows to one outcome', () {
      final all = [
        _lr(id: '1', number: 'LR/1', date: DateTime(2026, 9, 1)),
        _lr(
          id: '2',
          number: 'LR/2',
          date: DateTime(2026, 9, 2),
          status: LrStatus.cancelled,
        ),
      ];

      expect(
        filterTripHistory(
          all,
          filter: const TripHistoryFilter(status: LrStatus.cancelled),
          now: _now,
        ).single.number,
        'LR/2',
      );
    });

    test('period cuts off older trips and is inclusive at the boundary', () {
      final all = [
        _lr(id: '1', number: 'inside', date: DateTime(2026, 9, 10)),
        // Exactly 30 days before "now" — the boundary day must be kept.
        _lr(id: '2', number: 'boundary', date: DateTime(2026, 8, 17)),
        _lr(id: '3', number: 'outside', date: DateTime(2026, 8, 16)),
      ];

      final rows = filterTripHistory(
        all,
        filter: const TripHistoryFilter(period: TripPeriod.days30),
        now: _now,
      );

      expect(rows.map((e) => e.number), ['inside', 'boundary']);
    });

    test('a trip dated later the same day is not cut off by the period', () {
      final rows = filterTripHistory(
        [_lr(id: '1', number: 'today', date: DateTime(2026, 9, 16, 18, 30))],
        filter: const TripHistoryFilter(period: TripPeriod.days30),
        now: _now,
      );

      expect(rows.single.number, 'today');
    });

    test('search matches LR, truck, driver, city and party, ignoring case', () {
      final all = [
        _lr(
          id: '1',
          number: 'LR/PUN/26-27/00902',
          date: DateTime(2026, 9, 1),
          truck: 'MH18BG5730',
          driver: 'SALMAN',
          fromCity: 'CHAKAN',
          toCity: 'DEWAS',
          consignor: 'RAPL3',
          consignee: 'SMVL',
        ),
        _lr(
          id: '2',
          number: 'LR/SBN/26-27/01590',
          date: DateTime(2026, 9, 2),
          truck: 'MH20GC7189',
          driver: 'GAJANAN',
          fromCity: 'WALUJ',
          toCity: 'NARSAPURA',
          consignor: 'VARROC',
          consignee: 'HOSUR',
        ),
      ];

      List<String> found(String q) => filterTripHistory(
        all,
        filter: TripHistoryFilter(query: q),
        now: _now,
      ).map((e) => e.id).toList();

      expect(found('00902'), ['1']);
      expect(found('mh20gc'), ['2']);
      expect(found('gajanan'), ['2']);
      expect(found('dewas'), ['1']);
      expect(found('varroc'), ['2']);
      expect(found('  salman  '), ['1']);
      expect(found('nothing here'), isEmpty);
    });

    test('isUnfiltered tells an empty result apart from a filtered one', () {
      expect(const TripHistoryFilter().isUnfiltered, isTrue);
      expect(const TripHistoryFilter(query: '  ').isUnfiltered, isTrue);
      expect(const TripHistoryFilter(query: 'x').isUnfiltered, isFalse);
      expect(
        const TripHistoryFilter(period: TripPeriod.days30).isUnfiltered,
        isFalse,
      );
      expect(
        const TripHistoryFilter(status: LrStatus.delivered).isUnfiltered,
        isFalse,
      );
    });

    test('copyWith clears the status without disturbing the rest', () {
      const filter = TripHistoryFilter(
        query: 'pune',
        period: TripPeriod.days90,
        status: LrStatus.cancelled,
      );
      final cleared = filter.copyWith(clearStatus: true);

      expect(cleared.status, isNull);
      expect(cleared.query, 'pune');
      expect(cleared.period, TripPeriod.days90);
    });

    test('all-time period applies no cutoff', () {
      expect(TripPeriod.all.cutoff(_now), isNull);
      final rows = filterTripHistory([
        _lr(id: '1', number: 'ancient', date: DateTime(2019, 1, 1)),
      ], now: _now);
      expect(rows.single.number, 'ancient');
    });
  });
}
