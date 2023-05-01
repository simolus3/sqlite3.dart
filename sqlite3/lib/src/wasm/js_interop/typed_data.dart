import 'dart:html';
import 'dart:typed_data';

import 'package:js/js.dart';
import 'package:js/js_util.dart';

import 'core.dart';

@JS('Uint8Array')
external Object get _uint8Array;

@JS('Int32Array')
external Object get _int32Array;

@JS('DataView')
external Object get _dataView;

/// Implements
extension SharedArrayBufferAsByteBuffer on SharedArrayBuffer {
  /// [ByteBuffer.asUint8List] for shared buffers.
  Uint8List asUint8List([int offsetInBytes = 0, int? length]) {
    // Not using an if collection element here allows dart2js to emit the direct
    // constructor invocation.
    if (length != null) {
      return callConstructor(_uint8Array, [this, offsetInBytes, length]);
    } else {
      return callConstructor(_uint8Array, [this, offsetInBytes]);
    }
  }

  /// [ByteBuffer.asInt32List] for shared buffers.
  Int32List asInt32List([int offsetInBytes = 0, int? length]) {
    if (length != null) {
      return callConstructor(_int32Array, [this, offsetInBytes, length]);
    } else {
      return callConstructor(_int32Array, [this, offsetInBytes]);
    }
  }

  /// [ByteBuffer.asByteData] for shared buffers.
  ByteData asByteData([int offsetInBytes = 0, int? length]) {
    if (length != null) {
      return callConstructor(_dataView, [this, offsetInBytes, length]);
    } else {
      return callConstructor(_dataView, [this, offsetInBytes]);
    }
  }
}

extension NativeUint8List on Uint8List {
  /// A native version of [setRange] that takes another typed array directly.
  /// This avoids the type checks part of [setRange] in compiled JavaScript
  /// code.
  void set(Uint8List from, int offset) {
    callMethod<void>(this, 'set', [from, offset]);
  }
}

extension NativeDataView on ByteData {
  void setBigInt64(int offset, JsBigInt value, bool littleEndian) {
    callMethod<void>(
        this, 'setBigInt64', [offset, value.jsObject, littleEndian]);
  }
}
