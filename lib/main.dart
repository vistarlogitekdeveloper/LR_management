import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/constants/app_strings.dart';
import 'core/observability/error_reporter.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// Built once rather than on every [VistarApp.build]: AppTheme.light() assembles
/// a full ThemeData (and a GoogleFonts lookup) each time it is called.
final _theme = AppTheme.light();

void main() {
  // bootstrap() installs the four global error handlers §11 requires and then
  // calls runApp inside a guarded zone — so a throw during the very first frame
  // is reported instead of vanishing.
  bootstrap(() {
    usePathUrlStrategy();
    return const ProviderScope(child: VistarApp());
  });
}

class VistarApp extends ConsumerWidget {
  const VistarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: '${AppStrings.appName} (${AppStrings.appShortName})',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      routerConfig: router,
    );
  }
}
