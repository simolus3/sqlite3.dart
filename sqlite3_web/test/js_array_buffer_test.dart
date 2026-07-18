@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:sqlite3_web/src/js_array_buffer.dart';
import 'package:test/test.dart';

void main() {
  test('can use initial buffer', () {
    final buffer = GrowableArrayBuffer();
    buffer.newChunk(16).setUint8(10, 10);
    final result = buffer.take().toDart;

    expect(result.lengthInBytes, 16);
    expect(result.asByteData().getInt8(10), 10);
  });

  test('can grow', () {
    final buffer = GrowableArrayBuffer(16);
    for (var i = 0; i < 1024; i++) {
      buffer.newChunk(16).setUint8(10, 10);
    }

    final result = buffer.take().toDart;
    expect(result.lengthInBytes, 1024 * 16);
    final asUint8List = result.asUint8List();

    for (var i = 0; i < 1024; i++) {
      expect(asUint8List[i * 16 + 10], 10);
    }
  });
}
