import 'dart:convert';
import 'dart:typed_data';

import 'package:typed_data/typed_buffers.dart';

/// A [Codec] capable of converting Dart objects from and to the [JSONB] format
/// used by sqlite3.
///
/// The codec is useful when columns stored as blobs in SQLite are to be
/// interpreted as JSONB values, as one conversion step between Dart and SQLite
/// (usually implemented by mapping to a JSON string in Dart and then calling
/// the `jsonb` SQL function, or calling `json` the other way around) becomes
/// superfluous.
///
/// This codec's [Codec.encoder] supports the same objects as Dart's [json]
/// encoder with the addition of non-finite [double] values that can't be
/// represented in regular JSON. When passing a custom object into
/// [Codec.encode], it will attempt to call a `toJson()` method. The encoder
/// also throws the same [JsonCyclicError] and [JsonUnsupportedObjectError]
/// classes thrown by the native JSON encoder.
///
/// Example:
///
/// ```dart
/// import 'package:sqlite3/sqlite3.dart';
///
/// void main() {
///   final database = sqlite3.openInMemory()
///     ..execute('CREATE TABLE entries (entry BLOB NOT NULL) STRICT;')
///     // You can insert JSONB-formatted values directly
///     ..execute('INSERT INTO entries (entry) VALUES (?)', [
///       jsonb.encode({'hello': 'dart'})
///     ]);
///   // And use them with JSON operators in SQLite without a further conversion:
///   print(database.select('SELECT entry ->> ? AS r FROM entries;', [r'$.hello']));
/// }
/// ```
///
/// [JSONB]: https://sqlite.org/jsonb.html
/// {@category common}
const Codec<Object?, Uint8List> jsonb = _JsonbCodec();

final class _JsonbCodec extends Codec<Object?, Uint8List> {
  const _JsonbCodec();

  @override
  Converter<Uint8List, Object?> get decoder => const _JsonbDecoder();

  @override
  Converter<Object?, Uint8List> get encoder => const _JsonbEncoder();
}

enum _ElementType {
  _null,
  _true,
  _false,
  _int,
  _int5,
  _float,
  _float5,
  _text,
  _textJ,
  _text5,
  _textraw,
  _array,
  _object,
  _reserved13,
  _reserved14,
  _reserved15,
}

final class _JsonbDecoder extends Converter<Uint8List, Object?> {
  const _JsonbDecoder();

  @override
  Object? convert(Uint8List input) {
    final state = _JsonbDecodingState(input);
    final value = state.read();
    if (state.remainingLength > 0) {
      state._malformedJson();
    }

    return value;
  }
}

final class _JsonbDecodingState {
  final Uint8List input;
  int offset = 0;
  final List<int> endOffsetStack;

  _JsonbDecodingState(this.input) : endOffsetStack = [input.length];

  int get remainingLength => endOffsetStack.last - offset;

  Never _malformedJson() {
    throw ArgumentError('Malformed JSONB');
  }

  int nextByte() => input[offset++];

  void pushLengthRestriction(int length) {
    endOffsetStack.add(offset + length);
  }

  void popLengthRestriction() => endOffsetStack.removeLast();

  void checkRemainingLength(int requiredBytes) {
    if (remainingLength < requiredBytes) {
      _malformedJson();
    }
  }

  (_ElementType, int) readHeader() {
    assert(remainingLength >= 1);
    final firstByte = nextByte();
    final type = _ElementType.values[firstByte & 0xF];
    final lengthIndicator = firstByte >> 4;

    var length = 0;
    if (lengthIndicator <= 11) {
      length = lengthIndicator;
    } else {
      final additionalBytes = 1 << (lengthIndicator - 12);
      checkRemainingLength(additionalBytes);

      for (var i = 0; i < additionalBytes; i++) {
        length <<= 8;
        length |= nextByte();
      }
    }

    return (type, length);
  }

  List<Object?> readArray(int payloadLength) {
    pushLengthRestriction(payloadLength);
    final result = [];
    while (remainingLength > 0) {
      result.add(read());
    }

    popLengthRestriction();
    return result;
  }

  Map<String, Object?> readObject(int payloadLength) {
    pushLengthRestriction(payloadLength);
    final result = <String, Object?>{};
    while (remainingLength > 0) {
      final name = read();
      if (name is! String) {
        _malformedJson();
      }

      final value = read();
      result[name] = value;
    }

    popLengthRestriction();
    return result;
  }

  Object? read() {
    checkRemainingLength(1);
    final (type, payloadLength) = readHeader();
    checkRemainingLength(payloadLength);
    final payloadStartOffset = offset;
    final endIndex = offset + payloadLength;

    Uint8List payloadBytes() {
      return input.buffer
          .asUint8List(input.offsetInBytes + payloadStartOffset, payloadLength);
    }

    String payloadString() {
      return utf8.decode(payloadBytes());
    }

    final value = switch (type) {
      _ElementType._null => null,
      _ElementType._true => true,
      _ElementType._false => false,
      _ElementType._int || _ElementType._int5 => int.parse(payloadString()),
      _ElementType._float ||
      _ElementType._float5 =>
        double.parse(payloadString()),
      _ElementType._text || _ElementType._textraw => payloadString(),
      _ElementType._textJ ||
      _ElementType._text5 =>
        json.decode('"${payloadString()}"'),
      _ElementType._array => readArray(payloadLength),
      _ElementType._object => readObject(payloadLength),
      _ => _malformedJson(),
    };

    assert(offset <= endIndex);
    offset = endIndex;
    return value;
  }
}

final class _JsonbEncoder extends Converter<Object?, Uint8List> {
  const _JsonbEncoder();

  @override
  Uint8List convert(Object? input) {
    final operation = _JsonbEncodingOperation()..write(input);
    return operation._buffer.buffer
        .asUint8List(operation._buffer.offsetInBytes, operation._buffer.length);
  }
}

final class _JsonbEncodingOperation {
  final Uint8Buffer _buffer = Uint8Buffer();

  /// List of objects currently being traversed. Used to detect cycles.
  final List<Object?> _seen = [];

  void writeHeader(int payloadSize, _ElementType type) {
    var firstByte = type.index;
    if (payloadSize <= 11) {
      _buffer.add((payloadSize << 4) | firstByte);
    } else {
      // We can encode the length as a 1, 2, 4 or 8 byte integer. Prefer the
      // shortest.
      switch (payloadSize.bitLength) {
        case <= 8:
          const prefix = 12 << 4;
          _buffer
            ..add(prefix | firstByte)
            ..add(payloadSize);
        case <= 16:
          const prefix = 13 << 4;
          _buffer
            ..add(prefix | firstByte)
            ..add(payloadSize >> 8)
            ..add(payloadSize);
        case <= 32:
          const prefix = 14 << 4;
          _buffer
            ..add(prefix | firstByte)
            ..add(payloadSize >> 24)
            ..add(payloadSize >> 16)
            ..add(payloadSize >> 8)
            ..add(payloadSize);
        default:
          const prefix = 15 << 4;
          _buffer
            ..add(prefix | firstByte)
            ..add(payloadSize >> 56)
            ..add(payloadSize >> 48)
            ..add(payloadSize >> 40)
            ..add(payloadSize >> 32)
            ..add(payloadSize >> 24)
            ..add(payloadSize >> 16)
            ..add(payloadSize >> 8)
            ..add(payloadSize);
      }
    }
  }

  int prepareUnknownLength(_ElementType type) {
    const prefix = 15 << 4;
    _buffer.add(prefix | type.index);
    final index = _buffer.length;
    _buffer.addAll(_eightZeroes);
    return index;
  }

  void fillPreviouslyUnknownLength(int index) {
    final length = _buffer.length - index - 8;
    for (var i = 0; i < 8; i++) {
      _buffer[index + i] = length >> (8 * (7 - i));
    }
  }

  /// Check that [object] is not already being traversed, or add it to the end
  /// of the seen list otherwise.
  void checkCycle(Object? object) {
    for (final entry in _seen) {
      if (identical(object, entry)) {
        throw JsonCyclicError(object);
      }
    }

    _seen.add(object);
  }

  /// Removes [object] from the end of the [_seen] list.
  void removeSeen(Object? object) {
    assert(_seen.isNotEmpty);
    assert(identical(_seen.last, object));
    _seen.removeLast();
  }

  void writeNull() {
    writeHeader(0, _ElementType._null);
  }

  void writeBool(bool value) {
    writeHeader(0, value ? _ElementType._true : _ElementType._false);
  }

  void writeInt(int value) {
    final encoded = utf8.encode(value.toString());
    writeHeader(encoded.length, _ElementType._int);
    _buffer.addAll(encoded);
  }

  void writeDouble(double value) {
    if (value.isNaN) {
      // Recent SQLite versions don't accept NaN anymore, and this is consistent
      // with the json codec from the SDK.
      throw JsonUnsupportedObjectError(value);
    }

    final encoded = utf8.encode(value.toString());
    // RFC 8259 does not support infinity or NaN.
    writeHeader(encoded.length,
        value.isFinite ? _ElementType._float : _ElementType._float5);
    _buffer.addAll(encoded);
  }

  void writeString(String value) {
    final encoded = utf8.encode(value);
    writeHeader(encoded.length, _ElementType._textraw);
    _buffer.addAll(encoded);
  }

  void writeArray(Iterable<Object?> values) {
    if (values.isEmpty) {
      return writeHeader(0, _ElementType._array);
    }

    final index = prepareUnknownLength(_ElementType._array);
    values.forEach(write);
    fillPreviouslyUnknownLength(index);
  }

  bool writeMap(Map<Object?, Object?> values) {
    if (values.isEmpty) {
      writeHeader(0, _ElementType._object);
      return true;
    }

    final keyValueList = List<Object?>.filled(values.length * 2, null);
    var i = 0;
    var invalidKey = false;
    for (final MapEntry(:key, :value) in values.entries) {
      if (key is! String) {
        invalidKey = true;
        break;
      }
      keyValueList[i++] = key;
      keyValueList[i++] = value;
    }
    if (invalidKey) return false;

    final index = prepareUnknownLength(_ElementType._object);
    for (final value in keyValueList) {
      write(value);
    }
    fillPreviouslyUnknownLength(index);
    return true;
  }

  void write(Object? value) {
    // Try writing values that don't need to be converted into a JSON-compatible
    // format.
    if (writeJsonValue(value)) {
      return;
    }

    checkCycle(value);
    try {
      final lowered = _encodeObject(value);
      if (!writeJsonValue(lowered)) {
        throw JsonUnsupportedObjectError(lowered);
      }
      removeSeen(value);
    } catch (e) {
      throw JsonUnsupportedObjectError(value, cause: e);
    }
  }

  bool writeJsonValue(Object? value) {
    switch (value) {
      case null:
        writeNull();
        return true;
      case bool b:
        writeBool(b);
        return true;
      case int i:
        writeInt(i);
        return true;
      case double d:
        writeDouble(d);
        return true;
      case String s:
        writeString(s);
        return true;
      case List<Object?> i:
        checkCycle(i);
        writeArray(i);
        removeSeen(i);
        return true;
      case Map<Object?, Object?> o:
        checkCycle(o);
        final success = writeMap(o);
        removeSeen(o);
        return success;
      default:
        return false;
    }
  }

  static final _eightZeroes = Uint8List(8);

  static Object? _encodeObject(dynamic object) => object.toJson();
}
