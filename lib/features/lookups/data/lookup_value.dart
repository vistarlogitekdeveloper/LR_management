class LookupValue {
  final String id;
  final String category;
  final String code;
  final String label;
  final int sortOrder;
  final Map<String, dynamic> meta;

  const LookupValue({
    required this.id,
    required this.category,
    required this.code,
    required this.label,
    this.sortOrder = 0,
    this.meta = const {},
  });

  factory LookupValue.fromJson(Map<String, dynamic> json) => LookupValue(
        id: json['id'] as String,
        category: (json['category'] as String?) ?? '',
        code: (json['code'] as String?) ?? '',
        label: (json['label'] as String?) ?? '',
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        meta: ((json['meta'] as Map?) ?? const {}).cast<String, dynamic>(),
      );
}
