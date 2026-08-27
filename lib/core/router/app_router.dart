import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/screens/accounts_screen.dart';
import '../../features/admin/screens/admin_screen.dart';
import '../../features/admin/screens/audit_screen.dart';
import '../../features/admin/screens/capacity_options_screen.dart';
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
import '../../features/masters/screens/drivers_screen.dart';
import '../../features/masters/screens/parties_screen.dart';
import '../../features/masters/screens/part_descriptions_screen.dart';
import '../../features/masters/screens/routes_screen.dart';
import '../../features/masters/screens/transporters_screen.dart';
import '../../features/masters/screens/vehicles_screen.dart';
import '../../features/admin/providers/capacity_options_provider.dart';
import '../../features/admin/providers/system_config_provider.dart';
import '../../features/admin/providers/users_provider.dart';
import '../../features/lr/providers/lr_providers.dart';
import '../../features/masters/providers/master_providers.dart';
import '../../features/masters/providers/part_descriptions_provider.dart';
import '../../features/reports/screens/reports_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/tracking/screens/live_tracking_screen.dart';
import '../../features/tracking/screens/lr_tracking_screen.dart';
import '../../features/warehouse/screens/warehouse_screen.dart';
import '../../shared/models/user.dart';
import '../../shared/widgets/refresh_gate.dart';

// Each top-level nav destination gets its own branch so its widget tree is
// mounted once, on first visit, and preserved forever after. Switching
// branches is an IndexedStack visibility swap — no rebuild, no re-fetch, no
// route transition — which is what makes sidebar taps feel instant.
//
// Sub-routes (LR detail, Create LR, admin sub-pages) stack on top of their
// branch's Navigator, so back-nav stays within the branch and the branch
// remembers where the user was when they left it.

/// Pageless [NoTransitionPage] helper — shell branches never animate.
Page<void> _noAnim(GoRouterState state, Widget child) =>
    NoTransitionPage(key: state.pageKey, child: child);

final routerProvider = Provider<GoRouter>((ref) {
  // Do NOT ref.watch(authProvider) here — it would rebuild the whole GoRouter
  // on every auth state change (including loading true/false and error
  // set/clear), which remounts the current route and wipes any in-progress
  // form state (e.g. the login username + password disappear the moment you
  // press Sign In). The redirect callback reads fresh auth state via
  // ref.read on every invocation, and _AuthListenable pokes GoRouter to
  // re-run the redirect whenever it actually matters (auth transition or
  // splash-init finishing).
  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final auth = ref.read(authProvider);
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
        // Accounts/payouts are for the accounts desk + super admins only
        // (matches nav gating) — operators and regional admins are redirected.
        if (loc == '/accounts' && !user.canViewAccounts) {
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
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          // 1 — Dashboard
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                pageBuilder: (context, state) => _noAnim(
                  state,
                  RefreshGate(
                    onEnter: (ref) =>
                        ref.read(lrListProvider.notifier).refresh(),
                    loadingFlag: lrListLoadingProvider,
                    child: const DashboardScreen(),
                  ),
                ),
              ),
            ],
          ),
          // Live Tracking (SIM/GPS) — fleet map + per-LR trail. Additive branch.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tracking',
                pageBuilder: (context, state) =>
                    _noAnim(state, const LiveTrackingScreen()),
                routes: [
                  GoRoute(
                    path: 'lr/:id',
                    pageBuilder: (context, state) => _noAnim(
                      state,
                      LrTrackingScreen(id: state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 2 — Lorry Receipts (+ create / detail / edit / print)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/lrs',
                pageBuilder: (context, state) => _noAnim(
                  state,
                  RefreshGate(
                    onEnter: (ref) =>
                        ref.read(lrListProvider.notifier).refresh(),
                    loadingFlag: lrListLoadingProvider,
                    child: const LrListScreen(),
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'new',
                    pageBuilder: (context, state) =>
                        _noAnim(state, const CreateLrScreen()),
                  ),
                  GoRoute(
                    path: ':id',
                    pageBuilder: (context, state) => _noAnim(
                      state,
                      LrDetailScreen(id: state.pathParameters['id']!),
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        pageBuilder: (context, state) => _noAnim(
                          state,
                          CreateLrScreen(editId: state.pathParameters['id']!),
                        ),
                      ),
                      GoRoute(
                        path: 'print',
                        pageBuilder: (context, state) => _noAnim(
                          state,
                          PrintLrScreen(id: state.pathParameters['id']!),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // 3 — E-Way Bills
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ewb',
                pageBuilder: (context, state) =>
                    _noAnim(state, const EwbScreen()),
              ),
            ],
          ),
          // 4 — Warehouse
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/warehouse',
                pageBuilder: (context, state) => _noAnim(
                  state,
                  RefreshGate(
                    onEnter: (ref) =>
                        ref.read(lrListProvider.notifier).refresh(),
                    loadingFlag: lrListLoadingProvider,
                    child: const WarehouseScreen(),
                  ),
                ),
              ),
            ],
          ),
          // 5 — Parties (includes the merged legacy consignors / consignees
          // paths — kept as siblings so bookmarks work).
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/masters/parties',
                pageBuilder: (context, state) => _noAnim(
                  state,
                  RefreshGate(
                    onEnter: (ref) =>
                        ref.read(partiesProvider.notifier).refresh(),
                    loadingFlag: partiesLoadingProvider,
                    child: const PartiesScreen(),
                  ),
                ),
              ),
              GoRoute(
                path: '/masters/customers',
                redirect: (context, state) => '/masters/parties',
              ),
              GoRoute(
                path: '/masters/consignors',
                pageBuilder: (context, state) => _noAnim(
                  state,
                  RefreshGate(
                    onEnter: (ref) =>
                        ref.read(consignorsProvider.notifier).refresh(),
                    loadingFlag: consignorsLoadingProvider,
                    child: const ConsignorsScreen(),
                  ),
                ),
              ),
              GoRoute(
                path: '/masters/consignees',
                pageBuilder: (context, state) => _noAnim(
                  state,
                  RefreshGate(
                    onEnter: (ref) =>
                        ref.read(consigneesProvider.notifier).refresh(),
                    loadingFlag: consigneesLoadingProvider,
                    child: const ConsigneesScreen(),
                  ),
                ),
              ),
            ],
          ),
          // 6 — Vehicles
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/masters/vehicles',
                pageBuilder: (context, state) => _noAnim(
                  state,
                  RefreshGate(
                    // Drivers + transporters feed the vehicle form's pickers;
                    // the vehicles list drives this screen's loading flag, so
                    // its refresh is the one awaited.
                    onEnter: (ref) {
                      ref.read(driversProvider.notifier).refresh();
                      ref.read(transportersProvider.notifier).refresh();
                      return ref.read(vehiclesProvider.notifier).refresh();
                    },
                    loadingFlag: vehiclesLoadingProvider,
                    child: const VehiclesScreen(),
                  ),
                ),
              ),
            ],
          ),
          // 7 — Drivers
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/masters/drivers',
                pageBuilder: (context, state) => _noAnim(
                  state,
                  RefreshGate(
                    onEnter: (ref) =>
                        ref.read(driversProvider.notifier).refresh(),
                    loadingFlag: driversLoadingProvider,
                    child: const DriversScreen(),
                  ),
                ),
              ),
            ],
          ),
          // 8 — Transporters
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/masters/transporters',
                pageBuilder: (context, state) => _noAnim(
                  state,
                  RefreshGate(
                    onEnter: (ref) =>
                        ref.read(transportersProvider.notifier).refresh(),
                    loadingFlag: transportersLoadingProvider,
                    child: const TransportersScreen(),
                  ),
                ),
              ),
            ],
          ),
          // 9 — Routes
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/masters/routes',
                pageBuilder: (context, state) => _noAnim(
                  state,
                  RefreshGate(
                    onEnter: (ref) =>
                        ref.read(routesProvider.notifier).refresh(),
                    loadingFlag: routesLoadingProvider,
                    child: const RoutesScreen(),
                  ),
                ),
              ),
            ],
          ),
          // 10 — Part Descriptions
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/masters/part-descriptions',
                pageBuilder: (context, state) => _noAnim(
                  state,
                  RefreshGate(
                    onEnter: (ref) =>
                        ref.read(partDescriptionsProvider.notifier).refresh(),
                    loadingFlag: partDescriptionsLoadingProvider,
                    child: const PartDescriptionsScreen(),
                  ),
                ),
              ),
            ],
          ),
          // 11 — Reports
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reports',
                pageBuilder: (context, state) => _noAnim(
                  state,
                  RefreshGate(
                    onEnter: (ref) =>
                        ref.read(lrListProvider.notifier).refresh(),
                    loadingFlag: lrListLoadingProvider,
                    child: const ReportsScreen(),
                  ),
                ),
              ),
            ],
          ),
          // 12 — Accounts & Billing
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/accounts',
                pageBuilder: (context, state) => _noAnim(
                  state,
                  RefreshGate(
                    onEnter: (ref) =>
                        ref.read(lrListProvider.notifier).refresh(),
                    loadingFlag: lrListLoadingProvider,
                    child: const AccountsScreen(),
                  ),
                ),
              ),
            ],
          ),
          // 13 — Admin (+ users, regions, numbering, lr-format, capacity,
          // audit, settings sub-routes)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin',
                pageBuilder: (context, state) =>
                    _noAnim(state, const AdminScreen()),
                routes: [
                  GoRoute(
                    path: 'users',
                    pageBuilder: (context, state) => _noAnim(
                      state,
                      RefreshGate(
                        onEnter: (ref) =>
                            ref.read(usersProvider.notifier).refresh(),
                        loadingFlag: usersLoadingProvider,
                        child: const UsersAdminScreen(),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'regions',
                    pageBuilder: (context, state) => _noAnim(
                      state,
                      RefreshGate(
                        onEnter: (ref) =>
                            ref.read(regionsProvider.notifier).refresh(),
                        loadingFlag: regionsLoadingProvider,
                        child: const RegionsScreen(),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'numbering',
                    pageBuilder: (context, state) => _noAnim(
                      state,
                      RefreshGate(
                        onEnter: (ref) =>
                            ref.read(systemConfigProvider.notifier).refresh(),
                        child: const NumberingScreen(),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'lr-format',
                    pageBuilder: (context, state) => _noAnim(
                      state,
                      RefreshGate(
                        onEnter: (ref) =>
                            ref.read(systemConfigProvider.notifier).refresh(),
                        child: const LrFormatScreen(),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'vehicle-capacity',
                    pageBuilder: (context, state) => _noAnim(
                      state,
                      RefreshGate(
                        onEnter: (ref) => ref
                            .read(capacityOptionsProvider.notifier)
                            .refresh(),
                        loadingFlag: capacityOptionsLoadingProvider,
                        child: const CapacityOptionsScreen(),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'audit',
                    pageBuilder: (context, state) =>
                        _noAnim(state, const AuditScreen()),
                  ),
                  GoRoute(
                    path: 'settings',
                    pageBuilder: (context, state) =>
                        _noAnim(state, const SettingsScreen()),
                  ),
                ],
              ),
            ],
          ),
          // 14 — Profile (+ change-password sub-route)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) =>
                    _noAnim(state, const ProfileScreen()),
                routes: [
                  GoRoute(
                    path: 'change-password',
                    pageBuilder: (context, state) =>
                        _noAnim(state, const ChangePasswordScreen()),
                  ),
                ],
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
      // Trigger a redirect re-run on the two transitions that actually change
      // routing: sign-in / sign-out (isAuthenticated flip) and bootstrap
      // finishing (initializing flip → move off /splash). Loading and error
      // changes are intentionally ignored so the login form is never remounted
      // mid-submit.
      if (prev?.isAuthenticated != next.isAuthenticated ||
          prev?.initializing != next.initializing) {
        notifyListeners();
      }
    });
  }
  final Ref _ref;
}
