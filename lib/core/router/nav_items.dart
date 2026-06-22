import 'package:flutter/material.dart';

import '../../shared/models/user.dart';

class NavItem {
  final String id;
  final String label;
  final IconData icon;
  final String path;
  final bool Function(UserRole role) canAccess;

  const NavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.path,
    required this.canAccess,
  });
}

class NavSection {
  final String title;
  final List<NavItem> items;
  const NavSection({required this.title, required this.items});
}

class AppNav {
  AppNav._();

  static final sections = <NavSection>[
    NavSection(
      title: 'Operations',
      items: [
        NavItem(
          id: 'dashboard',
          label: 'Dashboard',
          icon: Icons.dashboard_rounded,
          path: '/dashboard',
          canAccess: (_) => true,
        ),
        NavItem(
          id: 'lrs',
          label: 'Lorry Receipts',
          icon: Icons.description_outlined,
          path: '/lrs',
          canAccess: (r) => r != UserRole.accounts,
        ),
        NavItem(
          id: 'create',
          label: 'Create LR',
          icon: Icons.add_circle_outline,
          path: '/lrs/new',
          canAccess: (r) => r.canCreate,
        ),
        NavItem(
          id: 'ewb',
          label: 'E-Way Bills',
          icon: Icons.qr_code_2_rounded,
          path: '/ewb',
          canAccess: (r) => r != UserRole.accounts,
        ),
        NavItem(
          id: 'warehouse',
          label: 'Warehouse',
          icon: Icons.warehouse_outlined,
          path: '/warehouse',
          canAccess: (r) => r != UserRole.accounts,
        ),
      ],
    ),
    NavSection(
      title: 'Masters',
      items: [
        NavItem(
          id: 'consignors',
          label: 'Consignors',
          icon: Icons.business_outlined,
          path: '/masters/consignors',
          canAccess: (r) => r != UserRole.accounts,
        ),
        NavItem(
          id: 'consignees',
          label: 'Consignees',
          icon: Icons.people_outline,
          path: '/masters/consignees',
          canAccess: (r) => r != UserRole.accounts,
        ),
        NavItem(
          id: 'vehicles',
          label: 'Vehicles',
          icon: Icons.local_shipping_outlined,
          path: '/masters/vehicles',
          canAccess: (r) => r != UserRole.accounts,
        ),
        NavItem(
          id: 'drivers',
          label: 'Drivers',
          icon: Icons.badge_outlined,
          path: '/masters/drivers',
          canAccess: (r) => r != UserRole.accounts,
        ),
        NavItem(
          id: 'transporters',
          label: 'Transporters',
          icon: Icons.alt_route_rounded,
          path: '/masters/transporters',
          canAccess: (r) => r != UserRole.accounts,
        ),
        NavItem(
          id: 'routes',
          label: 'Routes',
          icon: Icons.route_outlined,
          path: '/masters/routes',
          canAccess: (r) => r != UserRole.accounts,
        ),
      ],
    ),
    NavSection(
      title: 'Insights',
      items: [
        NavItem(
          id: 'reports',
          label: 'Reports',
          icon: Icons.bar_chart_rounded,
          path: '/reports',
          canAccess: (r) => r.canReports,
        ),
        NavItem(
          id: 'accounts',
          label: 'Accounts & Billing',
          icon: Icons.account_balance_wallet_outlined,
          path: '/accounts',
          canAccess: (r) => r.canReports,
        ),
      ],
    ),
    NavSection(
      title: 'System',
      items: [
        NavItem(
          id: 'admin',
          label: 'Admin Panel',
          icon: Icons.shield_outlined,
          path: '/admin',
          canAccess: (r) => r.canAdmin,
        ),
      ],
    ),
  ];
}
