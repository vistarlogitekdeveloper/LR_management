import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/screens/accounts_screen.dart';
import '../../features/admin/screens/admin_screen.dart';
import '../../features/admin/screens/audit_screen.dart';
import '../../features/admin/screens/lr_format_screen.dart';
import '../../features/admin/screens/numbering_screen.dart';
import '../../features/admin/screens/regions_screen.dart';
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
import '../../features/masters/screens/customers_screen.dart';
import '../../features/masters/screens/drivers_screen.dart';
import '../../features/masters/screens/parties_screen.dart';
import '../../features/masters/screens/routes_screen.dart';
import '../../features/masters/screens/transporters_screen.dart';
import '../../features/masters/screens/vehicles_screen.dart';
import '../../features/admin/providers/system_config_provider.dart';
import '../../features/admin/providers/users_provider.dart';
import '../../features/lr/providers/lr_providers.dart';
import '../../features/masters/providers/master_providers.dart';
import '../../features/reports/screens/reports_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/warehouse/screens/warehouse_screen.dart';
import '../../shared/models/user.dart';
import '../../shared/widgets/refresh_gate.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final loc = state.matchedLocation;

      // While restoring a saved session (e.g. after a browser refresh) wait on
      // a splash instead of bouncing to /login — and remember where to return.
      if (auth.initializing) {
        return loc == '/splash'
            ? null
            : '/splash?from=${Uri.encodeComponent(state.uri.toString())}';
      }

      final isAuthed = auth.isAuthenticated;

      // Once auth is known, send the splash to the original page (or /login).
      if (loc == '/splash') {
        if (!isAuthed) return '/login';
        final from = state.uri.queryParameters['from'];
        if (from != null &&
            from.isNotEmpty &&
            !from.startsWith('/splash') &&
            !from.startsWith('/login')) {
          return from;
        }
        return '/dashboard';
      }

      final isPublic = loc == '/login' || loc == '/forgot-password';
      if (!isAuthed && !isPublic) return '/login';
      if (isAuthed && loc == '/login') return '/dashboard';

      // Role / permission guards for protected branches
      final user = auth.user;
      final role = user?.role;
      if (user != null && role != null) {
        if (loc.startsWith('/admin') && !role.canAdmin) return '/dashboard';
        // Region maintenance is super-admin only.
        if (loc.startsWith('/admin/regions') && !role.canManageRegions) {
          return '/dashboard';
        }
        if (loc.startsWith('/masters/') &&
            !(role.canMasters || role.canReports)) {
          return '/dashboard';
        }
        // LR create/edit honour per-user permission overrides.
        if (loc == '/lrs/new' && !user.canCreateLr) return '/dashboard';
        if (loc.endsWith('/edit') && !user.canEditLr) return '/dashboard';
        // Accounts/payouts are hidden from operators (matches nav gating).
        if (loc == '/accounts' && role == UserRole.operator) {
          return '/dashboard';
        }
      }
      return null;
    },
    refreshListenable: _AuthListenable(ref),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: RefreshGate(
                onEnter: (ref) => ref.read(lrListProvider.notifier).refresh(),
                child: const DashboardScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ProfileScreen()),
            routes: [
              GoRoute(
                path: 'change-password',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: ChangePasswordScreen()),
              ),
            ],
          ),
          GoRoute(
            path: '/lrs',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: RefreshGate(
                onEnter: (ref) => ref.read(lrListProvider.notifier).refresh(),
                child: const LrListScreen(),
              ),
            ),
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
                      child: PrintLrScreen(id: state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/ewb',
            pageBuilder: (context, state) =>
                NoTransitionPage(key: state.pageKey, child: const EwbScreen()),
          ),
          GoRoute(
            path: '/masters/consignors',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: RefreshGate(
                onEnter: (ref) =>
                    ref.read(consignorsProvider.notifier).refresh(),
                child: const ConsignorsScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/masters/parties',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: RefreshGate(
                onEnter: (ref) => ref.read(partiesProvider.notifier).refresh(),
                child: const PartiesScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/masters/customers',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: RefreshGate(
                onEnter: (ref) =>
                    ref.read(customersProvider.notifier).refresh(),
                child: const CustomersScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/masters/consignees',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: RefreshGate(
                onEnter: (ref) =>
                    ref.read(consigneesProvider.notifier).refresh(),
                child: const ConsigneesScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/masters/vehicles',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: RefreshGate(
                onEnter: (ref) {
                  ref.read(vehiclesProvider.notifier).refresh();
                  ref.read(driversProvider.notifier).refresh();
                  ref.read(transportersProvider.notifier).refresh();
                },
                child: const VehiclesScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/masters/drivers',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: RefreshGate(
                onEnter: (ref) => ref.read(driversProvider.notifier).refresh(),
                child: const DriversScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/masters/transporters',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: RefreshGate(
                onEnter: (ref) =>
                    ref.read(transportersProvider.notifier).refresh(),
                child: const TransportersScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/masters/routes',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: RefreshGate(
                onEnter: (ref) => ref.read(routesProvider.notifier).refresh(),
                child: const RoutesScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/warehouse',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: RefreshGate(
                onEnter: (ref) => ref.read(lrListProvider.notifier).refresh(),
                child: const WarehouseScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: RefreshGate(
                onEnter: (ref) => ref.read(lrListProvider.notifier).refresh(),
                child: const ReportsScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/accounts',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: RefreshGate(
                onEnter: (ref) => ref.read(lrListProvider.notifier).refresh(),
                child: const AccountsScreen(),
              ),
            ),
          ),
          GoRoute(
            path: '/admin',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AdminScreen()),
            routes: [
              GoRoute(
                path: 'users',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: RefreshGate(
                    onEnter: (ref) =>
                        ref.read(usersProvider.notifier).refresh(),
                    child: const UsersAdminScreen(),
                  ),
                ),
              ),
              GoRoute(
                path: 'regions',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: RefreshGate(
                    onEnter: (ref) =>
                        ref.read(regionsProvider.notifier).refresh(),
                    child: const RegionsScreen(),
                  ),
                ),
              ),
              GoRoute(
                path: 'numbering',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: RefreshGate(
                    onEnter: (ref) =>
                        ref.read(systemConfigProvider.notifier).refresh(),
                    child: const NumberingScreen(),
                  ),
                ),
              ),
              GoRoute(
                path: 'lr-format',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: RefreshGate(
                    onEnter: (ref) =>
                        ref.read(systemConfigProvider.notifier).refresh(),
                    child: const LrFormatScreen(),
                  ),
                ),
              ),
              GoRoute(
                path: 'audit',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const AuditScreen(),
                ),
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
