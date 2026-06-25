import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Opens [bytes] in a new browser tab using a Blob URL. PDFs and images render
/// inline; other types download. The URL is revoked after a short delay so the
/// new tab has time to load it.
void openFileInBrowser(List<int> bytes, String mimeType, String filename) {
  final type = mimeType.isEmpty ? 'application/octet-stream' : mimeType;
  final blob = html.Blob([Uint8List.fromList(bytes)], type);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  Timer(const Duration(minutes: 2), () => html.Url.revokeObjectUrl(url));
}
