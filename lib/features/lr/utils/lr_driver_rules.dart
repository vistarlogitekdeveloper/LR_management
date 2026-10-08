import '../../../shared/models/driver.dart';
import '../../masters/utils/transporter_kyc.dart';

/// The driver rules of the LR form, kept out of the 3000-line screen so they
/// can be tested directly. They mirror the server's
/// services/trackingReadiness.js.
///
/// Vehicle tracking starts on its own when an LR is saved and follows the
/// phone of the LR's driver, so an LR with no driver, or with a driver whose
/// mobile is not a 10-digit number, was saved happily and then never tracked.

/// Null when [driver] may be saved on the LR, else the message to show under
/// the Driver field.
///
/// - Creating, or editing an open LR: a driver is required.
/// - Editing a delivered / cancelled LR: may be left without one (tracking is
///   over; demanding a driver would block e.g. a billing correction).
/// - The mobile is checked only for a driver being newly put on the LR —
///   [savedDriverId] is the one already saved — the same rule as the server,
///   so a legacy driver with a bad number does not block unrelated edits.
String? lrDriverError({
  required Driver? driver,
  required bool closed,
  String? savedDriverId,
}) {
  if (driver == null) {
    return closed
        ? null
        : "Select a driver — tracking follows the driver's mobile.";
  }
  if (savedDriverId != null && driver.id == savedDriverId) return null;
  final mobile = driver.mobile.trim();
  if (mobile.isEmpty) {
    return '${driver.name} has no mobile number, so the trip cannot be '
        'tracked. Add it in Masters → Drivers.';
  }
  if (normalizeIndianMobile(mobile) == null) {
    return "${driver.name}'s mobile ($mobile) is not a valid 10-digit "
        'number, so the trip cannot be tracked. Correct it in Masters → Drivers.';
  }
  return null;
}

/// The driver to show after the vehicle changes from [previousVehicleDriverId]'s
/// vehicle to one whose assigned driver is [newVehicleDriver].
///
/// The new vehicle's driver is filled in when the field is empty or still holds
/// the PREVIOUS vehicle's driver (i.e. it was auto-filled, not chosen). A
/// driver the user picked by hand is kept — it used to be overwritten silently.
/// A vehicle with no assigned driver changes nothing.
Driver? driverAfterVehicleChange({
  required Driver? current,
  required String? previousVehicleDriverId,
  required Driver? newVehicleDriver,
}) {
  if (newVehicleDriver == null) return current;
  if (current == null) return newVehicleDriver;
  if (previousVehicleDriverId != null &&
      current.id == previousVehicleDriverId) {
    return newVehicleDriver;
  }
  return current;
}
