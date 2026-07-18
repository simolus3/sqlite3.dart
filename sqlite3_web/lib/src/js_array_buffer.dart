import 'dart:js_interop';
import 'dart:js_interop_unsafe';

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
