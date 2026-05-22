import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import 'widgets/app_sidebar.dart';

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1100;

    return Scaffold(
      backgroundColor: AppColors.mist,
      drawer: isWide
          ? null
          : Drawer(
              backgroundColor: AppColors.white,
              child: AppSidebar(currentLocation: location),
            ),
      appBar: isWide
          ? null
          : AppBar(
              backgroundColor: AppColors.white,
              foregroundColor: AppColors.ink,
              elevation: 0,
              shape: const Border(
                  bottom: BorderSide(color: AppColors.line)),
              title: const Text(
                'Vistar Logitek',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
      body: Row(
        children: [
          if (isWide) AppSidebar(currentLocation: location),
          Expanded(
            child: ClipRect(child: child),
          ),
        ],
      ),
    );
  }
}
