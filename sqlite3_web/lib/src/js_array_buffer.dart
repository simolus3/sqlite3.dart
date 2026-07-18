import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Utility to growing an array buffer directly in JavaScript.
///
/// We don't use resizable array buffers since support for `transfer` is easier
/// to probe for and similarly efficient.
///
/// We don't use typed buffers from the `typed_data` package because we want to
/// convert to JavaScript in the end, so allocating buffers in Dart would be
/// more expensive for `dart2wasm`.
final class GrowableArrayBuffer {
  JSArrayBuffer _buffer;
  int _capacity;
  final bool _supportsTransfer;
  var _length = 0;

  GrowableArrayBuffer._(this._buffer, this._capacity, this._supportsTransfer);

  factory GrowableArrayBuffer([int initialCapacity = 512]) {
    final buffer = JSArrayBuffer(initialCapacity);
    return GrowableArrayBuffer._(
      buffer,
      initialCapacity,
      buffer.has('transfer'),
    );
  }

  /// Grows the buffer by the given size, and returns a data view of the added
  /// chunk.
  ///
  /// The view is valid until [newChunk] or [take] are called.
  JSDataView newChunk(int size) {
    assert(size >= 0);
    final oldLength = _length;
    _length = oldLength + size;

    if (_length > _capacity) {
      _grow(_length);
    }

    return JSDataView(_buffer, oldLength, size);
  }

  JSArrayBuffer take() {
    if (_supportsTransfer) {
      return _buffer.transfer(_length);
    } else {
      return _buffer.slice(0, _length);
    }
  }

  void _grow(int minSize) {
    final oldCapacity = _capacity;
    while (_capacity < minSize) {
      _capacity *= 2;
    }

    if (_supportsTransfer) {
      _buffer = _buffer.transfer(_capacity);
    } else {
      final newBuffer = JSArrayBuffer(_capacity);
      JSUint8Array(
        newBuffer,
        0,
        _capacity,
      ).set(JSUint8Array(_buffer, 0, oldCapacity));
      _buffer = newBuffer;
    }
  }
}

@JS()
extension on JSArrayBuffer {
  external JSArrayBuffer transfer(int newByteLength);

  external JSArrayBuffer slice(int start, int end);
}

@JS()
extension on JSTypedArray {
  external void set(JSAny? sourceArray);
}

@JS()
extension DataViewMethods on JSDataView {
  external void setUint8(int byteOffset, int value);
}
