// Opens raw file bytes for viewing. On web this creates a Blob URL and opens it
// in a new browser tab (PDFs/images render inline); on other platforms it is a
// no-op stub. Conditional import keeps non-web builds compiling.
export 'file_opener_stub.dart'
    if (dart.library.html) 'file_opener_web.dart';
