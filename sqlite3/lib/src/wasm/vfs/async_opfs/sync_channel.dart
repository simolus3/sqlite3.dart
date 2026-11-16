import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import '../../js_interop.dart';

const protocolVersion = 2;
const asyncIdleWaitTimeMs = 150;
const asyncIdleWaitTime = Duration(milliseconds: asyncIdleWaitTimeMs);

/// Implements a synchronous mechanism to wait for requests and responses.
class RequestResponseSynchronizer {
  static const _requestIndex = 0;
  static const _responseIndex = 1;

  // 2 32-bit slots for the int32 array
  static const _byteLength = 2 * 4;

  /// The shared array buffer used with atomics for synchronization.
  ///
  /// It must have a length of [byteLength].
  final SharedArrayBuffer buffer;

  /// A int32 view over [buffer], required for atomics to work.
  final Int32List int32View;

  RequestResponseSynchronizer._(this.buffer) : int32View = buffer.asInt32List();

  factory RequestResponseSynchronizer([SharedArrayBuffer? buffer]) {
    if (buffer != null && buffer.byteLength != _byteLength) {
      throw ArgumentError('Must be $_byteLength in length');
    }

    return RequestResponseSynchronizer._(
      buffer ?? SharedArrayBuffer(_byteLength),
    );
  }

  /// Creates a shared buffer and fills it with the initial state suitable for
  /// a request synchronization channel.
  static SharedArrayBuffer createBuffer() {
    final buffer = SharedArrayBuffer(_byteLength);
    final view = buffer.asInt32List();

    // The server will wait for the request index to not be -1 to wait for a
    // request. The initial value when allocating shared buffers is 0, which is
    // also a valid opcode.
    Atomics.store(view, _requestIndex, -1);

    return buffer;
  }

  /// Send a request with the given [opcode], wait for the remote worker to
  /// process it and returns the response code.
  int requestAndWaitForResponse(int opcode) {
    assert(opcode >= 0);
    Atomics.store(int32View, _responseIndex, -1);
    Atomics.store(int32View, _requestIndex, opcode);
    Atomics.notify(int32View, _requestIndex);

    // Async worker will take over here...

    var rc = Atomics.load(int32View, _responseIndex);
    while (rc == -1) {
      // Wait for a -1 value. The loop prevents race conditions where a previous
      // request didn't have to wait and we're now getting that notify.
      Atomics.wait(int32View, _responseIndex, -1);
      rc = Atomics.load(int32View, _responseIndex);
    }

    return rc;
  }

  /// Waits for a request, returning false if that timed out.
  bool waitForRequest() {
    var rc = Atomics.load(int32View, _requestIndex);
    while (rc == -1) {
      final code = Atomics.waitWithTimeout(
        int32View,
        _requestIndex,
        -1,
        asyncIdleWaitTimeMs,
      );
      if (code == Atomics.timedOut) {
        return false;
      }

      rc = Atomics.load(int32View, _requestIndex);
    }

    return true;
  }

  int takeOpcode() {
    final opcode = Atomics.load(int32View, _requestIndex);
    assert(opcode != -1);

    Atomics.store(int32View, _requestIndex, -1);
    return opcode;
  }

  void respond(int rc) {
    assert(rc != -1);
    Atomics.store(int32View, _responseIndex, rc);
    Atomics.notify(int32View, _responseIndex);
  }
}

class MessageSerializer {
  static const dataSize = 64 * 1024;
  static const metaOffset = dataSize;
  static const metaSize = 2048;
  static const totalSize = metaOffset + metaSize;

  final SharedArrayBuffer buffer;
  final _DataView _dataView;
  final Uint8List byteView;

  MessageSerializer(this.buffer)
    : _dataView = _DataView(buffer, metaOffset, metaSize),
      byteView = buffer.asUint8List();

  void write(Message message) {
    if (message is EmptyMessage) {
      // Nothing to do
    } else if (message is Flags) {
      _setInt(_flag0Offset, message.flag0);
      _setInt(_flag1Offset, message.flag1);
      _setInt(_flag2Offset, message.flag2);

      if (message is NameAndIntFlags) {
        _writeString(_stringOffset, message.name);
      }
    } else {
      throw UnsupportedError('Message $message');
    }
  }

  Uint8List viewByteRange(int offset, int length) {
    return buffer.asUint8ListSlice(offset, length);
  }

  String _readString(int offset) {
    final length = _dataView.getInt32(offset);
    // Browsers don't allow TextDecoder.decode on shared array buffers
    // (https://github.com/whatwg/encoding/issues/172). So, we copy.
    final originalSlice = buffer.asUint8ListSlice(offset + 4, length);
    final copy = Uint8List.fromList(originalSlice);

    return utf8.decode(copy);
  }

  void _writeString(int offset, String data) {
    final encoded = utf8.encode(data);
    _dataView.setInt32(offset, encoded.length);
    byteView.setAll(offset + 4, encoded);
  }

  int _getInt(int offset) {
    final bigInt = _dataView.getBigInt64(offset);
    return bigInt.asDartInt;
  }

  void _setInt(int offset, int value) {
    _dataView.setBigInt64(offset, JsBigInt.fromInt(value));
  }

  static EmptyMessage readEmpty(MessageSerializer unused) {
    return const EmptyMessage();
  }

  static Flags readFlags(MessageSerializer msg) {
    return Flags(
      msg._getInt(_flag0Offset),
      msg._getInt(_flag1Offset),
      msg._getInt(_flag2Offset),
    );
  }

  static NameAndIntFlags readNameAndFlags(MessageSerializer msg) {
    return NameAndIntFlags(
      msg._readString(_stringOffset),
      msg._getInt(_flag0Offset),
      msg._getInt(_flag1Offset),
      msg._getInt(_flag2Offset),
    );
  }

  static const _flag0Offset = 0;
  static const _flag1Offset = 8;
  static const _flag2Offset = 16;
  static const _stringOffset = 24;
}

enum WorkerOperation<Req extends Message, Res extends Message> {
  xAccess<NameAndIntFlags, Flags>(
    MessageSerializer.readNameAndFlags,
    MessageSerializer.readFlags,
  ),
  xDelete<NameAndIntFlags, EmptyMessage>(
    MessageSerializer.readNameAndFlags,
    MessageSerializer.readEmpty,
  ),
  xOpen<NameAndIntFlags, Flags>(
    MessageSerializer.readNameAndFlags,
    MessageSerializer.readFlags,
  ),
  xRead<Flags, Flags>(MessageSerializer.readFlags, MessageSerializer.readFlags),
  xWrite<Flags, EmptyMessage>(
    MessageSerializer.readFlags,
    MessageSerializer.readEmpty,
  ),
  xSleep<Flags, EmptyMessage>(
    MessageSerializer.readFlags,
    MessageSerializer.readEmpty,
  ),
  xClose<Flags, EmptyMessage>(
    MessageSerializer.readFlags,
    MessageSerializer.readEmpty,
  ),
  xFileSize<Flags, Flags>(
    MessageSerializer.readFlags,
    MessageSerializer.readFlags,
  ),
  xSync<Flags, EmptyMessage>(
    MessageSerializer.readFlags,
    MessageSerializer.readEmpty,
  ),
  xTruncate<Flags, EmptyMessage>(
    MessageSerializer.readFlags,
    MessageSerializer.readEmpty,
  ),
  xLock<Flags, EmptyMessage>(
    MessageSerializer.readFlags,
    MessageSerializer.readEmpty,
  ),
  xUnlock<Flags, EmptyMessage>(
    MessageSerializer.readFlags,
    MessageSerializer.readEmpty,
  ),
  stopServer<EmptyMessage, EmptyMessage>(
    MessageSerializer.readEmpty,
    MessageSerializer.readEmpty,
  );

  final Req Function(MessageSerializer) readRequest;
  final Res Function(MessageSerializer) readResponse;

  const WorkerOperation(this.readRequest, this.readResponse);
}

abstract class Message {
  const Message();
}

class EmptyMessage extends Message {
  const EmptyMessage();
}

class Flags extends Message {
  final int flag0;
  final int flag1;
  final int flag2;

  Flags(this.flag0, this.flag1, this.flag2);
}

class NameAndIntFlags extends Flags {
  final String name;

  NameAndIntFlags(this.name, super.flag0, super.flag1, super.flag2);
}

@JS('DataView')
extension type _DataView._(JSObject _) implements JSObject {
  external _DataView([SharedArrayBuffer buffer, int byteOffset, int length]);

  external int getInt32(int byteOffset);
  external void setInt32(int byteOffset, int value);

  external JsBigInt getBigInt64(int byteOffset);
  external void setBigInt64(int byteOffset, JsBigInt value);
}
