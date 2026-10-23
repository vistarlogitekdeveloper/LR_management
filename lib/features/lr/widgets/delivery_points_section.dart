import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/party.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../../../shared/widgets/searchable_field.dart';

/// Create LR's delivery points (migration 222): single point — the consignee —
/// is the default; "Two-point" adds a second consignee from the master, whose
/// city is the second drop. Shown only to users the super admin allowed
/// (AppUser.canTwoPointDelivery); the server checks the same.
class DeliveryPointsSection extends StatelessWidget {
  final int points;
  final Party? first;
  final Party? second;
  final List<Party> options;
  final String? errorText;
  final ValueChanged<int> onPointsChanged;
  final ValueChanged<Party?> onSecondChanged;

  const DeliveryPointsSection({
    super.key,
    required this.points,
    required this.first,
    required this.second,
    required this.options,
    required this.onPointsChanged,
    required this.onSecondChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    // The first consignee cannot also be the second.
    final choices = options.where((p) => p.id != first?.id).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledField(
          label: 'Delivery Points',
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<int>(
              key: const ValueKey('delivery-points'),
              segments: const [
                ButtonSegment(
                  value: 1,
                  label: Text('Single point'),
                  icon: Icon(Icons.place_outlined),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text('Two-point'),
                  icon: Icon(Icons.alt_route_rounded),
                ),
              ],
              selected: {points},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onPointsChanged(s.first),
            ),
          ),
        ),
        if (points == 2) ...[
          const SizedBox(height: 10),
          LabeledField(
            label: 'Second Consignee (2nd delivery point)',
            required: true,
            errorText: errorText,
            child: SearchableField<Party>(
              key: const ValueKey('second-consignee'),
              value: second,
              options: choices,
              labelOf: (p) => p.name,
              subtitleOf: (p) => p.city,
              hintText: 'Select the second consignee',
              dialogTitle: 'Select Second Consignee',
              onChanged: onSecondChanged,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            second == null
                ? 'Accounts and Management are emailed when a two-point LR is '
                      'saved. Add the extra drop charge under Extra Point Delivery.'
                : 'Second drop: ${second!.city.isEmpty ? second!.name : second!.city}. '
                      'Accounts and Management are emailed when this LR is saved.',
            style: const TextStyle(fontSize: 12, color: AppColors.slate),
          ),
        ],
      ],
    );
  }
}
