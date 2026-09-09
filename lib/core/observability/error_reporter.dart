import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Severity for [report]. Release builds drop anything below [LogLevel.warn]
/// so a chatty debug path costs nothing in production (CLAUDE.md §10).
enum LogLevel { debug, info, warn, error }

/// The single sink every uncaught error funnels through.
///
/// Today it writes a redacted line to the console; it exists so there is ONE
/// call site to point at a crash reporter (Sentry/Crashlytics) later without
/// touching the four global handlers. Per §10 nothing here may emit PII,
/// tokens, request bodies or full URLs — [_redact] enforces that on the way
/// out, because the values arriving here come from exception messages we do
/// not control.
void report(
  Object error,
  StackTrace? stack, {
  String? feature,
  LogLevel level = LogLevel.error,
  bool fatal = false,
}) {
  if (kReleaseMode && level.index < LogLevel.warn.index) return;

  final tag = feature == null ? '' : '[$feature] ';
  final head = '${level.name.toUpperCase()} $tag${_redact(error.toString())}';

  // Wrapped so a failure inside reporting can never itself crash the app or
  // re-enter the handlers that called us.
  try {
    debugPrint(fatal ? 'FATAL $head' : head);
    // Stack traces are noise in release console output and go to the crash
    // reporter instead once one is wired.
    if (!kReleaseMode && stack != null) debugPrintStack(stackTrace: stack);
  } catch (_) {
    // Deliberately swallowed: the reporter is the last line of defence.
  }
}

/// Strips the things §10 forbids from leaving the process. Deliberately blunt —
/// over-redaction is cheap, a leaked bearer token is not.
String _redact(String input) {
  var out = input;
  // Bearer / JWT-shaped values.
  out = out.replaceAll(
    RegExp(r'(Bearer\s+)?eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*'),
    '<token>',
  );
  // Authorization headers however they are spelled in a dio dump.
  out = out.replaceAll(
    RegExp(
      '(authorization|cookie|set-cookie)[\'"\\s:=]+[^,}\\s]+',
      caseSensitive: false,
    ),
    r'$1: <redacted>',
  );
  // Query strings — dio's toString() includes the full URL, and ours carry
  // filter values plus the `_ts` cache-buster.
  out = out.replaceAll(RegExp(r'\?[^\s)]{1,400}'), '?<query>');
  // Long digit runs: mobiles, GSTINs, account numbers.
  out = out.replaceAll(RegExp(r'\b\d{9,}\b'), '<digits>');
  return out;
}

/// Runs [appBuilder] with all four handlers CLAUDE.md §11 requires installed:
/// `FlutterError.onError`, `PlatformDispatcher.instance.onError`,
/// `runZonedGuarded`, and an `ErrorWidget.builder` that never shows a release
/// user a red screen.
///
/// Everything is wired BEFORE `runApp` so an error thrown during the first
/// frame is still captured.
void bootstrap(Widget Function() appBuilder) {
  runZonedGuarded(() {
    // Framework errors: build/layout/paint failures and anything the widget
    // tree throws synchronously.
    FlutterError.onError = (details) {
      report(
        details.exception,
        details.stack,
        feature: details.library,
        fatal: false,
      );
      // Keep the console dump in debug so the usual red-box detail survives.
      if (!kReleaseMode) FlutterError.presentError(details);
    };

    // Errors from the engine side / unhandled async errors outside the zone.
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, feature: 'platform', fatal: true);
      return true; // handled — do not let the process die.
    };

    // A widget that throws must not paint a red screen for an operator.
    // Debug keeps the default so developers still get the detail.
    ErrorWidget.builder = (details) {
      if (!kReleaseMode) return ErrorWidget(details.exception);
      return const _ReleaseErrorPanel();
    };

    runApp(appBuilder());
  }, (error, stack) => report(error, stack, feature: 'zone', fatal: true));
}

/// What a release user sees in place of a red screen: honest, branded, and
/// free of any exception text (§10 — no internals reach the user).
class _ReleaseErrorPanel extends StatelessWidget {
  const _ReleaseErrorPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.mist,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 32,
            color: AppColors.warn,
          ),
          const SizedBox(height: 12),
          const Text(
            "This section couldn't be displayed",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Please reload the page. If it keeps happening, report it to your '
            'administrator.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.slate),
          ),
        ],
      ),
    );
  }
}
