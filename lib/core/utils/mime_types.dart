/// Best-effort MIME type from a filename extension, used when opening picked
/// files for preview (so PDFs/images render inline rather than downloading).
String mimeForName(String fileName) {
  final ext =
      fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return 'application/pdf';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'csv':
      return 'text/csv';
    default:
      return 'application/octet-stream';
  }
}
