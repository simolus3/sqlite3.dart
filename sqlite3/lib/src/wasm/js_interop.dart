import 'dart:html';
import 'dart:typed_data';

import 'package:js/js_util.dart';

// This internal library exports wrappers around newer Web APIs for which no
// up-to-date bindings exist in the Dart SDK.

export 'js_interop/core.dart';
export 'js_interop/fetch.dart';
export 'js_interop/file_system_access.dart';
export 'js_interop/indexed_db.dart';
export 'js_interop/wasm.dart';

extension ReadBlob on Blob {
  Future<Uint8List> arrayBuffer() async {
    final buffer = await promiseToFuture<ByteBuffer>(
        callMethod(this, 'arrayBuffer', const []));
    return buffer.asUint8List();
  }
}
