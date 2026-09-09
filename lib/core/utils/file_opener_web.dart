import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Opens [bytes] in a new browser tab using a Blob URL. PDFs and images render
/// inline; other types download. The URL is revoked after a short delay so the
/// new tab has time to load it.
///
/// Built on `package:web` + `dart:js_interop` rather than `dart:html`, so the
/// web build compiles under both dart2js and dart2wasm. [filename] is accepted
/// for call-site symmetry with the non-web stub; a Blob URL carries no name of
/// its own, so the browser names any download itself.
void openFileInBrowser(List<int> bytes, String mimeType, String filename) {
  final type = mimeType.isEmpty ? 'application/octet-stream' : mimeType;
  final parts = <JSAny>[Uint8List.fromList(bytes).toJS].toJS;
  final blob = web.Blob(parts, web.BlobPropertyBag(type: type));
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
  Timer(const Duration(minutes: 2), () => web.URL.revokeObjectURL(url));
}
