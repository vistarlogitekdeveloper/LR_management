import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/screens/accounts_screen.dart';
import '../../features/admin/screens/admin_screen.dart';
import '../../features/admin/screens/audit_screen.dart';
import '../../features/admin/screens/lr_format_screen.dart';
import '../../features/admin/screens/numbering_screen.dart';
import '../../features/admin/screens/settings_screen.dart';
import '../../features/admin/screens/users_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/change_password_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/profile_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/ewb/screens/ewb_screen.dart';
import '../../features/lr/screens/create_lr_screen.dart';
import '../../features/lr/screens/lr_detail_screen.dart';
import '../../features/lr/screens/lr_list_screen.dart';
import '../../features/lr/screens/print_lr_screen.dart';
import '../../features/masters/screens/consignees_screen.dart';
import '../../features/masters/screens/consignors_screen.dart';
import '../../features/masters/screens/drivers_screen.dart';
import '../../features/masters/screens/routes_screen.dart';
import '../../features/masters/screens/transporters_screen.dart';
import '../../features/masters/screens/vehicles_screen.dart';
import '../../features/reports/screens/reports_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/warehouse/screens/warehouse_screen.dart';
import '../../shared/models/user.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final isAuthed = auth.isAuthenticated;
      final loc = state.matchedLocation;
      final isPublic =
          loc == '/login' || loc == '/forgot-password';
      if (!isAuthed && !isPublic) return '/login';
      if (isAuthed && loc == '/login') return '/dashboard';

      // Role guards for protected branches
      final role = auth.user?.role;
      if (role != null) {
        if (loc.startsWith('/admin') && !role.canAdmin) return '/dashboard';
        if (loc.startsWith('/masters/') && !(role.canMasters || role.canReports)) {
          return '/dashboard';
        }
        if (loc == '/lrs/new' && !role.canCreate) return '/dashboard';
        if (loc.endsWith('/edit') && !role.canEdit) return '/dashboard';
      }
      return null;
    },
    refreshListenable: _AuthListenable(ref),
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DashboardScreen()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ProfileScreen()),
            routes: [
              GoRoute(
                path: 'change-password',
                pageBuilder: (context, state) => const NoTransitionPage(
                    child: ChangePasswordScreen()),
              ),
            ],
          ),
          GoRoute(
            path: '/lrs',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: LrListScreen()),
            routes: [
              GoRoute(
                path: 'new',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: CreateLrScreen()),
              ),
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: LrDetailScreen(id: state.pathParameters['id']!),
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    pageBuilder: (context, state) => NoTransitionPage(
                      child: CreateLrScreen(
                        editId: state.pathParameters['id']!,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'print',
                    pageBuilder: (context, state) => NoTransitionPage(
                      child: PrintLrScreen(
                        id: state.pathParameters['id']!,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/ewb',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: EwbScreen()),
          ),
          GoRoute(
            path: '/masters/consignors',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ConsignorsScreen()),
          ),
          GoRoute(
            path: '/masters/consignees',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ConsigneesScreen()),
          ),
          GoRoute(
            path: '/masters/vehicles',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: VehiclesScreen()),
          ),
          GoRoute(
            path: '/masters/drivers',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DriversScreen()),
          ),
          GoRoute(
            path: '/masters/transporters',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: TransportersScreen()),
          ),
          GoRoute(
            path: '/masters/routes',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: RoutesScreen()),
          ),
          GoRoute(
            path: '/warehouse',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: WarehouseScreen()),
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ReportsScreen()),
          ),
          GoRoute(
            path: '/accounts',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AccountsScreen()),
          ),
          GoRoute(
            path: '/admin',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AdminScreen()),
            routes: [
              GoRoute(
                path: 'users',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: UsersAdminScreen()),
              ),
              GoRoute(
                path: 'numbering',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: NumberingScreen()),
              ),
              GoRoute(
                path: 'lr-format',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: LrFormatScreen()),
              ),
              GoRoute(
                path: 'audit',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: AuditScreen()),
              ),
              GoRoute(
                path: 'settings',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: SettingsScreen()),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _ref.listen(authProvider, (prev, next) {
      if (prev?.isAuthenticated != next.isAuthenticated) notifyListeners();
    });
  }
  final Ref _ref;
}
