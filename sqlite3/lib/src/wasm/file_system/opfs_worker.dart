/// An idiomatic Dart port of on OPFS-based file system for sqlite3 relayed
/// through a worker.
///
/// This file is derived from sqlite3 sources, namely the
///  - worker potion: https://github.com/sqlite/sqlite/blob/master/ext/wasm/api/sqlite3-opfs-async-proxy.js
///  - client side: https://github.com/sqlite/sqlite/blob/master/ext/wasm/api/sqlite3-vfs-opfs.c-pp.js
///
/// However, the logic has been simplified to implement nothing more than the
/// persistence solution implemented by us.
library sqlite3.fs.opfs_worker;

import 'dart:convert';
import 'dart:html' show SharedArrayBuffer;
import 'dart:typed_data';

import 'package:js/js.dart';
import 'package:js/js_util.dart';

import '../js_interop.dart';

const _asyncIdleWaitTimeMs = 150;

@JS('Int32Array')
external Object get _int32Array;

@JS()
@anonymous
class _OpfsInit {
  external int get fileBufferSize;
  external int get metaSize;
  external SharedArrayBuffer operationBuffer;

  external factory _OpfsInit({
    required int fileBufferSize,
    required int metaSize,
    required SharedArrayBuffer operationBuffer,
  });
}

class _RequestResponseSynchronizer {
  static const _requestIndex = 0;
  static const _responseIndex = 1;

  final SharedArrayBuffer buffer;
  final Int32List int32View;

  _RequestResponseSynchronizer._(this.buffer)
      : int32View = callConstructor(_int32Array, [buffer]);

  factory _RequestResponseSynchronizer() {
    // 2 32-bit slots for the int32 array
    return _RequestResponseSynchronizer._(SharedArrayBuffer(2 * 4));
  }

  String waitForRequest() {
    return Atomics.wait(int32View, _requestIndex, 0, _asyncIdleWaitTimeMs);
  }

  int get requestedOpcode {
    final opcode = Atomics.load(int32View, _requestIndex);
    Atomics.store(int32View, _requestIndex, 0);
    return opcode;
  }

  void respond(int rc) {
    Atomics.store(int32View, _responseIndex, rc);
    Atomics.notify(int32View, _responseIndex);
  }
}

class _OpfsWorker {
  final _RequestResponseSynchronizer _requests;
  final _MessageSerializer _messages;
  var _shutdownRequested = false;

  Future<void> _releaseImplicitLocks() async {}

  Future<void> _waitLoop() async {
    while (!_shutdownRequested) {
      final waitResult = _requests.waitForRequest();

      if (waitResult == Atomics.timedOut) {
        await _releaseImplicitLocks();
        continue;
      }

      final opcode = _requests.requestedOpcode;
    }
  }

  Future<void> start() async {}
}

class _MessageSerializer {
  static const dataSize = 64 * 1024;
  static const metaOffset = dataSize;
  static const metaSize = 2048;
  static const totalSize = metaOffset + metaSize;

  final ByteBuffer buffer;
  final ByteData dataView;
  final Uint8List byteView;

  _MessageSerializer(this.buffer)
      : dataView = buffer.asByteData(metaOffset),
        byteView = buffer.asUint8List(metaOffset);

  _EmptyMessage readEmptyMessage() => const _EmptyMessage();

  _NameAndInt32Flags readNameAndFlags() {
    return _NameAndInt32Flags(
      _readString(12),
      dataView.getInt32(0),
      dataView.getInt32(4),
      dataView.getInt32(8),
    );
  }

  void write(_Message message) {
    if (message is _EmptyMessage) {
      // Nothing to do
    } else if (message is _NameAndInt32Flags) {
      dataView.setInt32(0, message.flag0);
      dataView.setInt32(4, message.flag1);
      dataView.setInt32(8, message.flag2);
      _writeString(12, message.name);
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
}

enum _WorkerOperation<Req extends _Message, Res extends _Message> {
  xAccess<_NameAndInt32Flags, _EmptyMessage>();

  const _WorkerOperation();
}

abstract class _Message {
  const _Message();
}

class _EmptyMessage extends _Message {
  const _EmptyMessage();
}

class _NameAndInt32Flags extends _Message {
  final String name;
  final int flag0;
  final int flag1;
  final int flag2;

  _NameAndInt32Flags(this.name, this.flag0, this.flag1, this.flag2);
}
