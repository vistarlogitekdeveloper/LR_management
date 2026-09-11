import 'package:flutter/material.dart';

import '../../shared/models/user.dart';

class NavItem {
  final String id;
  final String label;
  final IconData icon;
  final String path;
  final bool Function(AppUser user) canAccess;

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
          canAccess: (u) => u.role != UserRole.accounts,
        ),
        NavItem(
          id: 'create',
          label: 'Create LR',
          icon: Icons.add_circle_outline,
          path: '/lrs/new',
          canAccess: (u) => u.canCreateLr,
        ),
        NavItem(
          id: 'ewb',
          label: 'E-Way Bills',
          icon: Icons.qr_code_2_rounded,
          path: '/ewb',
          canAccess: (u) => u.role != UserRole.accounts,
        ),
        NavItem(
          id: 'warehouse',
          label: 'Warehouse',
          icon: Icons.warehouse_outlined,
          path: '/warehouse',
          canAccess: (u) => u.role != UserRole.accounts,
        ),
        NavItem(
          id: 'tracking',
          label: 'Live Tracking',
          icon: Icons.my_location_rounded,
          path: '/tracking',
          canAccess: (_) => true,
        ),
      ],
    ),
    NavSection(
      title: 'Masters',
      items: [
        NavItem(
          id: 'parties',
          label: 'Parties',
          icon: Icons.business_outlined,
          path: '/masters/parties',
          canAccess: (u) => u.role != UserRole.accounts,
        ),
        NavItem(
          id: 'vehicles',
          label: 'Vehicles',
          icon: Icons.local_shipping_outlined,
          path: '/masters/vehicles',
          canAccess: (u) => u.role != UserRole.accounts,
        ),
        NavItem(
          id: 'drivers',
          label: 'Drivers',
          icon: Icons.badge_outlined,
          path: '/masters/drivers',
          canAccess: (u) => u.role != UserRole.accounts,
        ),
        NavItem(
          id: 'transporters',
          label: 'Transporters',
          icon: Icons.alt_route_rounded,
          path: '/masters/transporters',
          canAccess: (u) => u.role != UserRole.accounts,
        ),
        NavItem(
          id: 'routes',
          label: 'Routes',
          icon: Icons.route_outlined,
          path: '/masters/routes',
          canAccess: (u) => u.role != UserRole.accounts,
        ),
        NavItem(
          id: 'part-descriptions',
          label: 'Part Descriptions',
          icon: Icons.inventory_2_outlined,
          path: '/masters/part-descriptions',
          canAccess: (u) => u.role != UserRole.accounts,
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
          canAccess: (u) => u.canViewReports,
        ),
        NavItem(
          id: 'accounts',
          label: 'Accounts & Billing',
          icon: Icons.account_balance_wallet_outlined,
          path: '/accounts',
          // Billing/payouts belong to the accounts desk (and super admins).
          // Operators handle dispatch; regional admins don't get billing access.
          canAccess: (u) => u.canViewAccounts,
        ),
        NavItem(
          id: 'invoices',
          label: 'Invoices',
          icon: Icons.receipt_long_outlined,
          path: '/invoices',
          // Permission-based, not role-based: the invoice router's READ tier is
          // INVOICE_VIEW | ADMIN_ACCESS | SUPERADMIN_ACCESS, so an accounts
          // user granted INVOICE_VIEW sees this and nobody else does.
          canAccess: (u) => u.canViewInvoices,
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
          canAccess: (u) => u.canAdmin,
        ),
        NavItem(
          id: 'regions',
          label: 'Regions',
          icon: Icons.public_outlined,
          path: '/admin/regions',
          canAccess: (u) => u.canManageRegions,
        ),
        NavItem(
          id: 'invoice-settings',
          label: 'Invoice Settings',
          icon: Icons.receipt_outlined,
          path: '/admin/invoice-settings',
          // Needs its own entry point, not just a route: the server refuses to
          // issue any invoice until this letterhead row exists, and both the
          // invoice list and the create screen tell the admin to come here.
          // Gated on the settings tier (ADMIN_ACCESS | SUPERADMIN_ACCESS) —
          // narrower than issuing invoices, because this row holds the bank
          // account customers pay into.
          canAccess: (u) => u.canManageInvoiceSettings,
        ),
      ],
    ),
  ];
}
