import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'core.dart';

// These types provide wrappers around JS typeddata objects that don't have
// the toDart extension on them.
// Using toDart is unsafe as it creates a reference in dart2js while copying in
// dart2wasm. This causes issues that are very hard to find, so we should be
// very explicit about where we copy and explain why that's safe.

extension type SafeBuffer(JSArrayBuffer inner) implements JSObject {
  SafeU8Array asUint8Array([int offsetInBytes = 0, int? length]) {
    return switch (length) {
      null => SafeU8Array._bufferView(this, offsetInBytes),
      var length =>
        SafeU8Array._bufferViewWithLength(this, offsetInBytes, length),
    };
  }
}

@JS('DataView')
extension type SafeDataView(JSDataView inner) implements JSObject {
  @JS('')
  external factory SafeDataView.entireBufferView(SafeBuffer buffer);

  external void setInt32(int byteOffset, int value);
  external int getInt32(int byteOffset);

  external void setBigInt64(int offset, JsBigInt value, bool littleEndian);
}

@JS('Uint8Array')
extension type SafeU8Array(JSUint8Array inner) implements JSObject {
  @JS('')
  external factory SafeU8Array.allocate(int length);

  @JS('')
  external factory SafeU8Array._bufferView(SafeBuffer buffer, int byteOffset);

  @JS('')
  external factory SafeU8Array._bufferViewWithLength(
      SafeBuffer buffer, int byteOffset, int length);

  external void set(JSTypedArray array, int targetOffset);
  external void fill(int value, int start, int end);

  external SafeU8Array subarray(int begin, int end);

  external int get length;

  int operator [](int index) {
    return getProperty<JSNumber>(index.toJS).toDartInt;
  }

  void operator []=(int index, int value) {
    setProperty(index.toJS, value.toJS);
  }

  /// Implementation of [List.setRange] for wrapped u8 arrays.
  void setRange(int start, int end, SafeU8Array other, [int skipCount = 0]) {
    if (skipCount == 0 && end - start == other.length) {
      set(other.inner, start);
    } else {
      set(other.subarray(skipCount, skipCount + (end - start)).inner, start);
    }
  }

  /// Implementation of [List.setAll] for wrapped u8 arrays.
  void setAll(int index, SafeU8Array other) {
    set(other.inner, index);
  }
}

@JS('Int32Array')
extension type SafeI32Array(JSInt32Array inner) implements JSObject {
  @JS('')
  external factory SafeI32Array.entireBufferView(SafeBuffer buffer);

  int operator [](int index) {
    return getProperty<JSNumber>(index.toJS).toDartInt;
  }

  void operator []=(int index, int value) {
    setProperty(index.toJS, value.toJS);
  }
}
