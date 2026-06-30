class PartDescription {
  PartDescription({
    this.id,
    required this.name,
    this.natureOfGoods,
    this.defaultPackageTypeId,
    this.defaultPackageTypeCode,
    this.defaultPackageTypeLabel,
    this.active = true,
    this.version = 0,
  });

  final String? id;
  final String name;
  final String? natureOfGoods;
  final String? defaultPackageTypeId;
  final String? defaultPackageTypeCode;
  final String? defaultPackageTypeLabel;
  final bool active;
  final int version;

  factory PartDescription.fromJson(Map<String, dynamic> j) {
    final pkg = j['defaultPackageType'] as Map?;
    return PartDescription(
      id: j['id'] as String?,
      name: j['name'] as String,
      natureOfGoods: j['nature_of_goods'] as String?,
      defaultPackageTypeId: j['default_package_type_id'] as String?,
      defaultPackageTypeCode: pkg?['code'] as String?,
      defaultPackageTypeLabel: pkg?['label'] as String?,
      active: (j['active'] as bool?) ?? true,
      version: (j['version'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'nature_of_goods': natureOfGoods,
        'default_package_type_id': defaultPackageTypeId,
        'active': active,
      };
}
