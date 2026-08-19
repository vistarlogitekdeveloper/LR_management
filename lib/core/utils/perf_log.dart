import 'package:flutter/foundation.dart';

/// Gated performance logging for the Accounts & Billing investigation.
///
/// Enable with:
///   flutter run --dart-define=ACC_PERF_LOG=true
///
/// Every call site guards on [kAccPerfLog] — a compile-time `const bool` — so
/// with the flag off (the default) dart2js/AOT tree-shakes the guarded blocks
/// out entirely. There is zero runtime cost, and no string is even built,
/// because the interpolation lives inside the `if (kAccPerfLog) { … }` block.
const bool kAccPerfLog = bool.fromEnvironment('ACC_PERF_LOG');

/// Convenience for the guarded call sites. Prefer `if (kAccPerfLog) accLog(...)`
/// so the message is not constructed when the flag is off.
void accLog(String message) => debugPrint(message);
