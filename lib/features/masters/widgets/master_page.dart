import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../shell/widgets/app_topbar.dart';

class MasterRow {
  final String id;
  final List<String> cells;
  const MasterRow({required this.id, required this.cells});
}

class MasterPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> columns;
  final List<MasterRow> rows;
  final bool canEdit;
  final VoidCallback? onAdd;
  final void Function(String id)? onEdit;
  final void Function(String id)? onDelete;

  const MasterPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.columns,
    required this.rows,
    this.canEdit = false,
    this.onAdd,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<MasterPage> createState() => _MasterPageState();
}

class _MasterPageState extends State<MasterPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.rows
        : widget.rows.where((r) {
            final hay = r.cells.join(' ').toLowerCase();
            return hay.contains(_query.toLowerCase());
          }).toList();

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: widget.title,
            subtitle: widget.subtitle,
            actions: [
              if (widget.canEdit && widget.onAdd != null)
                AppButton(
                  label: 'Add new',
                  icon: Icons.add_rounded,
                  onPressed: widget.onAdd,
                ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 280,
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: 'Search…',
                              prefixIcon:
                                  Icon(Icons.search, color: AppColors.slate),
                            ),
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${filtered.length} of ${widget.rows.length}',
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          AppColors.plum.withValues(alpha: 0.05),
                        ),
                        columnSpacing: 28,
                        dataRowMinHeight: 48,
                        dataRowMaxHeight: 56,
                        columns: [
                          for (final col in widget.columns)
                            DataColumn(
                              label: Text(
                                col,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                  fontSize: 12.5,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          if (widget.canEdit)
                            const DataColumn(label: Text('')),
                        ],
                        rows: [
                          for (final row in filtered)
                            DataRow(
                              cells: [
                                for (final cell in row.cells)
                                  DataCell(Text(cell)),
                                if (widget.canEdit)
                                  DataCell(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.onEdit != null)
                                        IconButton(
                                          tooltip: 'Edit',
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            color: AppColors.plum,
                                            size: 18,
                                          ),
                                          onPressed: () =>
                                              widget.onEdit!(row.id),
                                        ),
                                      if (widget.onDelete != null)
                                        IconButton(
                                          tooltip: 'Delete',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: AppColors.danger,
                                            size: 18,
                                          ),
                                          onPressed: () =>
                                              widget.onDelete!(row.id),
                                        ),
                                    ],
                                  )),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
