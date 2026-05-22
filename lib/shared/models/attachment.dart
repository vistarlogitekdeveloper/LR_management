class Attachment {
  final String id;
  final String name;
  final int sizeBytes;
  final String? mimeType;
  final DateTime uploadedAt;
  final String uploadedBy;

  const Attachment({
    required this.id,
    required this.name,
    required this.sizeBytes,
    this.mimeType,
    required this.uploadedAt,
    required this.uploadedBy,
  });

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
