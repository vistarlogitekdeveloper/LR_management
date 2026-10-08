import 'tracking_repository.dart';

/// What the LR tracking panel offers, decided in one place so every reason the
/// Start button is withheld is named on screen instead of discovered by
/// pressing it.
enum TrackingAction {
  /// A trip is running — nothing to start.
  none,

  /// No trip yet: "Start tracking".
  start,

  /// The trip was stopped (taken over, driver changed) or ended by the
  /// provider, on an open LR: "Restart tracking". There used to be no way back
  /// from either state.
  restart,

  /// The user lacks TRACKING_START.
  noPermission,

  /// No driver on the LR.
  noDriver,

  /// The driver is marked inactive.
  inactiveDriver,

  /// The driver's mobile is missing or not a 10-digit number.
  badMobile,

  /// The LR is delivered or cancelled and was never tracked: it can no longer
  /// be. (Start used to be offered on these from the trip history list.)
  closed,
}

/// Mirrors the server's own refusals (startTrackingForLr), so the button is
/// only shown when the press can succeed. The server still decides — this is a
/// hint, not the gate.
TrackingAction trackingActionFor(LrTracking t, {required bool canStart}) {
  final state = (t.trackingState ?? '').toUpperCase();
  final noTrip = state.isEmpty;
  if (!noTrip && !t.canRestart) return TrackingAction.none;
  if (t.lrClosed) {
    return noTrip ? TrackingAction.closed : TrackingAction.none;
  }
  if (!canStart) return TrackingAction.noPermission;
  if ((t.driverName ?? '').trim().isEmpty) return TrackingAction.noDriver;
  // null = a server too old to say; then leave it to the press.
  if (t.driverActive == false) return TrackingAction.inactiveDriver;
  if (t.driverMobileValid == false) return TrackingAction.badMobile;
  return noTrip ? TrackingAction.start : TrackingAction.restart;
}
