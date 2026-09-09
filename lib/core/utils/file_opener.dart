// Opens raw file bytes for viewing. On web this creates a Blob URL and opens it
// in a new browser tab (PDFs/images render inline); on other platforms it is a
// no-op stub. Conditional import keeps non-web builds compiling.
//
// The guard is `dart.library.js_interop`, not `dart.library.html`: js_interop is
// available on BOTH web compilers, whereas dart.library.html is false under
// dart2wasm — which would silently select the throwing stub for a `--wasm` web
// build. It stays false on the Dart VM, so native builds still get the stub.
export 'file_opener_stub.dart'
    if (dart.library.js_interop) 'file_opener_web.dart';
