/// Where a manual LR number stands while it is typed.
enum ManualLrStatus {
  /// The format is wrong ([ManualLrEntry.message] says how).
  invalid,

  /// Asking the server whether it is free.
  checking,

  /// Free: no LR has it.
  available,

  /// Already used by an LR.
  taken,

  /// The check could not be made; the save will check it.
  unknown,
}

/// The manual LR number the operator entered, and its status.
class ManualLrEntry {
  final String number;
  final ManualLrStatus status;
  final String? message;
  const ManualLrEntry(this.number, this.status, [this.message]);

  /// What blocks the save, or null (unknown / checking: the save checks).
  String? get blocker => switch (status) {
    ManualLrStatus.invalid || ManualLrStatus.taken => message,
    _ => null,
  };
}
