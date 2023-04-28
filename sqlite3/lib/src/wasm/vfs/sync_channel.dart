import 'dart:convert';
import 'dart:html';
import 'dart:typed_data';

import '../js_interop.dart';

const protocolVersion = 1;
const asyncIdleWaitTimeMs = 150;
const asyncIdleWaitTime = Duration(milliseconds: asyncIdleWaitTimeMs);

class RequestResponseSynchronizer {
  static const _requestIndex = 0;
  static const _responseIndex = 1;

  // 2 32-bit slots for the int32 array
  static const byteLength = 2 * 4;

  final SharedArrayBuffer buffer;
  final Int32List int32View;

  RequestResponseSynchronizer._(this.buffer) : int32View = buffer.asInt32List();

  factory RequestResponseSynchronizer([SharedArrayBuffer? buffer]) {
    if (buffer != null && buffer.byteLength != byteLength) {
      throw ArgumentError('Must be $byteLength in length');
    }

    return RequestResponseSynchronizer._(
        buffer ?? SharedArrayBuffer(byteLength));
  }

  int requestAndWaitForResponse(int opcode) {
    Atomics.store(int32View, _responseIndex, -1);
    Atomics.store(int32View, _requestIndex, opcode);
    Atomics.notify(int32View, _requestIndex);

    // Async worker will take over here...

    Atomics.wait(int32View, _responseIndex, -1);
    return Atomics.load(int32View, _responseIndex);
  }

  String waitForRequest() {
    return Atomics.waitWithTimeout(
        int32View, _requestIndex, 0, asyncIdleWaitTimeMs);
  }

  int takeOpcode() {
    final opcode = Atomics.load(int32View, _requestIndex);
    Atomics.store(int32View, _requestIndex, 0);
    return opcode;
  }

  void respond(int rc) {
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
  final ByteData dataView;
  final Uint8List byteView;

  MessageSerializer(this.buffer)
      : dataView = buffer.asByteData(),
        byteView = buffer.asUint8List();

  void write(Message message) {
    if (message is EmptyMessage) {
      // Nothing to do
    } else if (message is Flags) {
      dataView.setInt32(0, message.flag0);
      dataView.setInt32(4, message.flag1);
      dataView.setInt32(8, message.flag2);

      if (message is NameAndInt32Flags) {
        _writeString(12, message.name);
      }
    } else {
      throw UnsupportedError('Message $message');
    }
  }

  String _readString(int offset) {
    final length = dataView.getInt32(offset);
    return utf8.decode(buffer.asUint8List(offset + 4, length));
  }

  void _writeString(int offset, String data) {
    final encoded = utf8.encode(data);
    dataView.setInt32(offset, encoded.length);
    byteView.setAll(offset + 4, encoded);
  }

  static EmptyMessage readEmpty(MessageSerializer unused) {
    return const EmptyMessage();
  }

  static Flags readFlags(MessageSerializer msg) {
    return Flags(
      msg.dataView.getInt32(0),
      msg.dataView.getInt32(4),
      msg.dataView.getInt32(8),
    );
  }

  static NameAndInt32Flags readNameAndFlags(MessageSerializer msg) {
    return NameAndInt32Flags(
      msg._readString(12),
      msg.dataView.getInt32(0),
      msg.dataView.getInt32(4),
      msg.dataView.getInt32(8),
    );
  }
}

enum WorkerOperation<Req extends Message, Res extends Message> {
  xAccess<NameAndInt32Flags, Flags>(
    MessageSerializer.readNameAndFlags,
    MessageSerializer.readFlags,
  ),
  xOpen<NameAndInt32Flags, Flags>(
    MessageSerializer.readNameAndFlags,
    MessageSerializer.readFlags,
  ),
  xClose<Flags, EmptyMessage>(
    MessageSerializer.readNameAndFlags,
    MessageSerializer.readEmpty,
  ),
  xFileSize<Flags, Flags>(
    MessageSerializer.readNameAndFlags,
    MessageSerializer.readNameAndFlags,
  ),
  xTruncate<Flags, EmptyMessage>(
    MessageSerializer.readNameAndFlags,
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

class NameAndInt32Flags extends Flags {
  final String name;

  NameAndInt32Flags(this.name, super.flag0, super.flag1, super.flag2);
}
