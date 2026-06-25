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

    final isMobile = MediaQuery.of(context).size.width < 600;
    final pad = isMobile ? 14.0 : 28.0;

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
              padding: EdgeInsets.all(pad),
              child: AppCard(
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        // Search shrinks on mobile (capped on desktop) so it
                        // never collides with the count.
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: TextField(
                                decoration: const InputDecoration(
                                  hintText: 'Search…',
                                  prefixIcon: Icon(
                                    Icons.search,
                                    color: AppColors.slate,
                                  ),
                                ),
                                onChanged: (v) => setState(() => _query = v),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
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
                    SizedBox(height: isMobile ? 10 : 14),
                    LayoutBuilder(
                      builder: (context, c) {
                        if (filtered.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: Text(
                                'No records',
                                style: TextStyle(color: AppColors.slate),
                              ),
                            ),
                          );
                        }
                        // Phones: stacked cards. Wider: the data table.
                        return c.maxWidth < 640
                            ? Column(
                                children: [
                                  for (final row in filtered) _mobileCard(row),
                                ],
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: _dataTable(filtered),
                              );
                      },
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

  Widget _mobileCard(MasterRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    row.cells.isNotEmpty ? row.cells.first : '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
              if (widget.canEdit) ...[
                if (widget.onEdit != null)
                  IconButton(
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: AppColors.plum,
                      size: 18,
                    ),
                    onPressed: () => widget.onEdit!(row.id),
                  ),
                if (widget.onDelete != null)
                  IconButton(
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.danger,
                      size: 18,
                    ),
                    onPressed: () => widget.onDelete!(row.id),
                  ),
              ],
            ],
          ),
          for (
            var i = 1;
            i < row.cells.length && i < widget.columns.length;
            i++
          )
            if (row.cells[i].trim().isNotEmpty && row.cells[i] != '—')
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 84,
                      child: Text(
                        widget.columns[i],
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.cells[i],
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _dataTable(List<MasterRow> filtered) {
    return DataTable(
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
        if (widget.canEdit) const DataColumn(label: Text('')),
      ],
      rows: [
        for (final row in filtered)
          DataRow(
            cells: [
              for (final cell in row.cells) DataCell(Text(cell)),
              if (widget.canEdit)
                DataCell(
                  Row(
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
                          onPressed: () => widget.onEdit!(row.id),
                        ),
                      if (widget.onDelete != null)
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppColors.danger,
                            size: 18,
                          ),
                          onPressed: () => widget.onDelete!(row.id),
                        ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
