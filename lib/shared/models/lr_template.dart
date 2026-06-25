import '../../core/utils/json_parse.dart';

/// A saved LR template: a title plus a full snapshot of the LR creation form
/// (party/vehicle/route ids, lookup ids, charges and text fields).
class LrTemplate {
  final String id;
  final String title;
  final Map<String, dynamic> payload;
  final int version;

  const LrTemplate({
    required this.id,
    required this.title,
    this.payload = const {},
    this.version = 0,
  });

  factory LrTemplate.fromJson(Map<String, dynamic> json) => LrTemplate(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? '',
        payload:
            ((json['payload'] as Map?) ?? const {}).cast<String, dynamic>(),
        version: asInt(json['version']),
      );
}
