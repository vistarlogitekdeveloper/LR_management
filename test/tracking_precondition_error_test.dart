// "Start tracking" can fail for three reasons that are all the same KIND of
// problem — the LR has no usable driver phone number — and all fixed in the
// same place. They are grouped so the UI can answer them with one actionable
// dialog instead of a snackbar carrying a raw exception dump.
//
// Server authority (controllers/trackingController.js startTracking):
//   no_driver  -> 400 NO_DRIVER
//   no_mobile  -> 400 NO_MOBILE
//   bad_mobile -> 400 BAD_MOBILE
//   sim_busy   -> 409 SIM_BUSY   (a different kind: a dispatch decision)
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/core/network/api_exception.dart';

ApiException _api(int status, String code, [String message = 'x']) =>
    ApiException(status: status, code: code, message: message);

void main() {
  group('isTrackingPrecondition', () {
    test('covers all three missing-driver-phone cases', () {
      expect(_api(400, 'NO_DRIVER').isTrackingPrecondition, isTrue);
      expect(_api(400, 'NO_MOBILE').isTrackingPrecondition, isTrue);
      expect(_api(400, 'BAD_MOBILE').isTrackingPrecondition, isTrue);
    });

    test('does not swallow SIM_BUSY, which needs its own dialog', () {
      // A busy SIM is a dispatch decision — stop the other LR, or use a
      // different driver — and already has a dedicated takeover prompt.
      final busy = _api(409, 'SIM_BUSY');
      expect(busy.isTrackingPrecondition, isFalse);
      expect(busy.isSimBusy, isTrue);
    });

    test('does not swallow unrelated failures', () {
      expect(_api(503, 'SCT_DISABLED').isTrackingPrecondition, isFalse);
      expect(_api(403, 'FORBIDDEN').isTrackingPrecondition, isFalse);
      expect(_api(404, 'NOT_FOUND').isTrackingPrecondition, isFalse);
      expect(_api(412, 'VERSION_CONFLICT').isTrackingPrecondition, isFalse);
      expect(_api(400, 'VALIDATION_ERROR').isTrackingPrecondition, isFalse);
    });

    test('the status must be 400 — the code alone is not enough', () {
      // Guards against a future endpoint reusing the code at another status.
      expect(_api(500, 'NO_DRIVER').isTrackingPrecondition, isFalse);
    });
  });

  group('isNoDriver picks the right instruction', () {
    test('true only for a completely unassigned driver', () {
      expect(_api(400, 'NO_DRIVER').isNoDriver, isTrue);
      // A driver IS assigned here — telling the user to "assign a driver"
      // would send them looking for something that is already there.
      expect(_api(400, 'NO_MOBILE').isNoDriver, isFalse);
      expect(_api(400, 'BAD_MOBILE').isNoDriver, isFalse);
    });
  });

  group('friendlyErrorMessage passes the server wording through', () {
    test('a 400 keeps the precise server message', () {
      // The server already distinguishes the three cases in words; re-writing
      // them client-side would lose which one it was.
      const msg =
          'This LR has no driver assigned — assign a driver with a mobile '
          'number to track it.';
      expect(friendlyErrorMessage(_api(400, 'NO_DRIVER', msg)), msg);
    });

    test('a 403 is generalised instead', () {
      // "Missing permission: TRACKING_START or ADMIN_ACCESS or
      // SUPERADMIN_ACCESS" is for a log, not for an operator.
      expect(
        friendlyErrorMessage(_api(403, 'FORBIDDEN', 'Missing permission: X')),
        "You don't have permission to do this.",
      );
    });
  });
}
