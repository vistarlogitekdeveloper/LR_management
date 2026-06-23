class Attachment {
  final String id;
  final String name;
  final int sizeBytes;
  final String? mimeType;
  final DateTime uploadedAt;
  final String uploadedBy;
  final String? fileKey;
  final String? attachmentType;

  const Attachment({
    required this.id,
    required this.name,
    required this.sizeBytes,
    this.mimeType,
    required this.uploadedAt,
    required this.uploadedBy,
    this.fileKey,
    this.attachmentType,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: (json['id'] as String?) ?? '',
        name: (json['file_name'] as String?) ?? (json['name'] as String?) ?? '',
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        mimeType: json['mime_type'] as String?,
        uploadedAt:
            DateTime.tryParse(json['uploaded_at']?.toString() ?? '') ??
                DateTime.now(),
        uploadedBy: (json['uploaded_by'] as String?) ?? '',
        fileKey: json['file_key'] as String?,
        attachmentType: json['attachment_type'] as String?,
      );

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
