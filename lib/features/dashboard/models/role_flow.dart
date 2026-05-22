import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/user.dart';

class FlowStep {
  final String id;
  final IconData icon;
  final String title;
  final String desc;
  final Color tint;
  final String path;

  const FlowStep({
    required this.id,
    required this.icon,
    required this.title,
    required this.desc,
    required this.tint,
    required this.path,
  });
}

class RoleFlow {
  final String tagline;
  final List<FlowStep> steps;
  const RoleFlow({required this.tagline, required this.steps});
}

class RoleFlows {
  RoleFlows._();

  static final Map<UserRole, RoleFlow> flows = {
    UserRole.admin: const RoleFlow(
      tagline:
          'Full control — create LRs, manage masters, run reports & administer the system.',
      steps: [
        FlowStep(
          id: 'create',
          icon: Icons.add_rounded,
          title: 'Create LR',
          desc: 'Generate a new Lorry Receipt',
          tint: AppColors.red,
          path: '/lrs/new',
        ),
        FlowStep(
          id: 'lrs',
          icon: Icons.description_outlined,
          title: 'Manage LRs',
          desc: 'View, edit, delete & print',
          tint: AppColors.orange,
          path: '/lrs',
        ),
        FlowStep(
          id: 'masters',
          icon: Icons.business_outlined,
          title: 'Masters',
          desc: 'Customers, vehicles, transporters',
          tint: AppColors.amber,
          path: '/masters/consignors',
        ),
        FlowStep(
          id: 'reports',
          icon: Icons.bar_chart_rounded,
          title: 'Reports',
          desc: 'Daily, monthly & accounts',
          tint: AppColors.plumLight,
          path: '/reports',
        ),
        FlowStep(
          id: 'admin',
          icon: Icons.shield_outlined,
          title: 'Admin Panel',
          desc: 'Users, numbering & audit',
          tint: AppColors.plum,
          path: '/admin',
        ),
      ],
    ),
    UserRole.operator: const RoleFlow(
      tagline:
          'Dispatch desk — create & print Lorry Receipts, enter invoices and E-Way Bill details.',
      steps: [
        FlowStep(
          id: 'create',
          icon: Icons.add_rounded,
          title: 'Create LR',
          desc: 'Start a new Lorry Receipt',
          tint: AppColors.red,
          path: '/lrs/new',
        ),
        FlowStep(
          id: 'lrs',
          icon: Icons.description_outlined,
          title: 'Edit / Print LR',
          desc: 'Update & print 4 copies',
          tint: AppColors.orange,
          path: '/lrs',
        ),
        FlowStep(
          id: 'reports',
          icon: Icons.bar_chart_rounded,
          title: 'Reports',
          desc: 'Daily dispatch overview',
          tint: AppColors.plumLight,
          path: '/reports',
        ),
      ],
    ),
    UserRole.accounts: const RoleFlow(
      tagline:
          'Billing desk — track pending freight, advances, customer ledgers & exports.',
      steps: [
        FlowStep(
          id: 'accounts',
          icon: Icons.account_balance_wallet_outlined,
          title: 'Accounts & Billing',
          desc: 'Pending freight & advances',
          tint: AppColors.red,
          path: '/accounts',
        ),
        FlowStep(
          id: 'reports',
          icon: Icons.bar_chart_rounded,
          title: 'Reports',
          desc: 'Freight & customer summary',
          tint: AppColors.orange,
          path: '/reports',
        ),
        FlowStep(
          id: 'transporters',
          icon: Icons.alt_route_rounded,
          title: 'Transporter Ledger',
          desc: 'Trip-wise billing & margin',
          tint: AppColors.plumLight,
          path: '/masters/transporters',
        ),
      ],
    ),
  };
}
