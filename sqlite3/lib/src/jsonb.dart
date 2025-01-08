import 'dart:convert';
import 'dart:typed_data';

import 'package:typed_data/typed_buffers.dart';

const jsonb = _JsonbCodec();

final class _JsonbCodec extends Codec<Object?, Uint8List> {
  const _JsonbCodec();

  @override
  // TODO: implement decoder
  Converter<Uint8List, Object?> get decoder => throw UnimplementedError();

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
    final encoded = utf8.encode(value.toString());
    // RFC 8259 does not support infinity or NaN.
    writeHeader(encoded.length,
        value.isFinite ? _ElementType._float : _ElementType._float5);
    _buffer.addAll(encoded);
  }

  void writeString(String value) {
    final encoded = _jsonUtf8.convert(value);
    // Encoding a string adds quotes at the beginning and end which we don't
    // need.
    const doubleQuote = 0x22;
    assert(encoded[0] == doubleQuote);
    assert(encoded[encoded.length - 1] == doubleQuote);

    writeHeader(encoded.length - 2, _ElementType._textJ);
    _buffer.addAll(encoded, 1, encoded.length - 1);
  }

  void writeArray(Iterable<Object?> values) {
    if (values.isEmpty) {
      return writeHeader(0, _ElementType._array);
    }

    final index = prepareUnknownLength(_ElementType._array);
    values.forEach(write);
    fillPreviouslyUnknownLength(index);
  }

  void writeObject(Map<String, Object?> values) {
    if (values.isEmpty) {
      return writeHeader(0, _ElementType._object);
    }

    final index = prepareUnknownLength(_ElementType._object);
    for (final MapEntry(:key, :value) in values.entries) {
      writeString(key);
      write(value);
    }
    fillPreviouslyUnknownLength(index);
  }

  void write(Object? value) {
    return switch (value) {
      null => writeNull(),
      bool b => writeBool(b),
      int i => writeInt(i),
      double d => writeDouble(d),
      String s => writeString(s),
      Iterable<Object?> i => writeArray(i),
      Map<String, Object> o => writeObject(o),
      Map<dynamic, dynamic> o => writeObject(o.cast()),
      _ => throw ArgumentError.value(value, 'value', 'Invalid JSON value.'),
    };
  }

  static final _eightZeroes = Uint8List(8);
  static final _jsonUtf8 = const JsonEncoder().fuse(const Utf8Encoder());
}
