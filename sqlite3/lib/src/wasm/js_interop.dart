import 'dart:js_interop';

import 'package:web/web.dart' show Blob;
import 'js_interop/typed_data.dart';

// This internal library exports wrappers around newer Web APIs for which no
// up-to-date bindings exist in the Dart SDK.

export 'js_interop/atomics.dart';
export 'js_interop/core.dart';
export 'js_interop/fetch.dart';
export 'js_interop/new_file_system_access.dart';
export 'js_interop/indexed_db.dart';
export 'js_interop/typed_data.dart';
export 'js_interop/wasm.dart';

extension ReadBlob on Blob {
  Future<SafeBuffer> byteBuffer() async {
    final buffer = await arrayBuffer().toDart;
    return SafeBuffer(buffer);
  }
}
