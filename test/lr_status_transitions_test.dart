import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/shared/models/lr_models.dart';

// The Change status dialog offers only the moves the server allows
// (lr.service.js STATUS_GRAPH). It used to list every status, so a Delivered
// LR offered "Mark as Booked" and the server refused it.
void main() {
  test('everyone: forward moves only, nothing after Delivered / Cancelled', () {
    expect(LrStatus.booked.nextStatuses(admin: false), [
      LrStatus.inTransit,
      LrStatus.cancelled,
    ]);
    expect(LrStatus.inTransit.nextStatuses(admin: false), [
      LrStatus.delivered,
      LrStatus.cancelled,
    ]);
    expect(LrStatus.delivered.nextStatuses(admin: false), isEmpty);
    expect(LrStatus.cancelled.nextStatuses(admin: false), isEmpty);
  });

  test('admin may correct to any other status', () {
    expect(LrStatus.delivered.nextStatuses(admin: true), [
      LrStatus.booked,
      LrStatus.inTransit,
      LrStatus.cancelled,
    ]);
  });
}
