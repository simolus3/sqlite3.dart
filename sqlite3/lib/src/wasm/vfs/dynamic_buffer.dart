import 'dart:typed_data';

/// A utility class that manages a growing byte buffer.
/// It dynamically increases its capacity in factors of 2 when needed.
class DynamicBuffer {
  Uint8List _buffer;
  int _capacity;
  int _length = 0;

  /// Creates a [DynamicBuffer] with an optional initial capacity.
  /// The default initial capacity is 1024 bytes.
  DynamicBuffer([int initialCapacity = 1024])
      : _capacity = initialCapacity,
        _buffer = Uint8List(initialCapacity) {
    if (initialCapacity < 1) {
      throw ArgumentError("initialCapacity must be positive");
    }
  }

  /// Adds [data] to the buffer, expanding its capacity if necessary.
  void add(Uint8List data) {
    _ensureCapacity(_length + data.length);
    _buffer.setRange(_length, _length + data.length, data);
    _length += data.length;
  }

  /// Writes [data] into the buffer starting at [offset], expanding capacity if necessary.
  /// If the write operation extends beyond the current length, the length is updated accordingly.
  void write(Uint8List data, int offset) {
    if (offset < 0) {
      throw ArgumentError("Offset must be non-negative");
    }
    final endPosition = offset + data.length;
    _ensureCapacity(endPosition);
    _buffer.setRange(offset, endPosition, data);
    if (endPosition > _length) {
      _length = endPosition;
    }
  }

  /// Truncates the buffer to a specific [newSize].
  ///
  /// No memory is freed when using [truncate].
  ///
  /// If [newSize] is less than the current length, the buffer is truncated.
  /// If [newSize] is greater than the current length, the buffer length is extended with zeros.
  void truncate(int newSize) {
    if (newSize < 0) {
      throw ArgumentError("newSize must be non-negative");
    }
    _ensureCapacity(newSize);
    if (newSize > _length) {
      // Zero out the new extended area
      _buffer.fillRange(_length, newSize, 0);
    }
    _length = newSize;
  }

  /// Returns a [Uint8List] view containing the data up to the current length.
  Uint8List toUint8List() {
    return Uint8List.view(_buffer.buffer, 0, _length);
  }

  /// Ensures that the buffer has enough capacity to hold [requiredCapacity] bytes.
  void _ensureCapacity(int requiredCapacity) {
    if (requiredCapacity > _capacity) {
      // Double the capacity until it is sufficient.
      int newCapacity = _capacity;
      while (newCapacity < requiredCapacity) {
        newCapacity *= 2;
      }
      // Allocate a new buffer and copy existing data.
      Uint8List newBuffer = Uint8List(newCapacity);
      newBuffer.setRange(0, _length, _buffer);
      _buffer = newBuffer;
      _capacity = newCapacity;
    }
  }

  /// Returns the current length of the data in the buffer.
  int get length => _length;

  /// Resets the buffer length to zero without altering its capacity.
  void reset() {
    _length = 0;
  }
}
