import 'dart:html';
import 'dart:typed_data';

import 'package:js/js_util.dart';
import 'package:path/path.dart' as p;

import '../../constants.dart';
import '../../vfs.dart';
import '../js_interop.dart';
import 'sync_channel.dart';
import 'worker.dart';

class WasmVfs extends BaseVirtualFileSystem {
  final RequestResponseSynchronizer synchronizer;
  final MessageSerializer serializer;

  final String chroot;
  final p.Context pathContext;

  WasmVfs({
    super.random,
    required WorkerOptions workerOptions,
    this.chroot = '/',
  })  : synchronizer =
            RequestResponseSynchronizer(workerOptions.synchronizationBuffer),
        serializer = MessageSerializer(workerOptions.communicationBuffer),
        pathContext = p.Context(style: p.Style.url, current: chroot),
        super(name: 'dart-sqlite3-vfs');

  Res _runInWorker<Req extends Message, Res extends Message>(
      WorkerOperation<Req, Res> operation, Req requestData) {
    serializer.write(requestData);

    final rc = synchronizer.requestAndWaitForResponse(operation.index);
    if (rc != 0) {
      throw VfsException(rc);
    }

    return operation.readResponse(serializer);
  }

  @override
  int xAccess(String path, int flags) {
    final res = _runInWorker(
        WorkerOperation.xAccess, NameAndInt32Flags(name, flags, 0, 0));
    return res.flag0;
  }

  @override
  void xDelete(String path, int syncDir) {}

  @override
  String xFullPathName(String path) {
    final resolved = pathContext.absolute(path);
    if (!p.isWithin(chroot, resolved)) {
      throw const VfsException(SqlError.SQLITE_CANTOPEN);
    }

    return resolved;
  }

  @override
  XOpenResult xOpen(Sqlite3Filename path, int flags) {
    final filePath = path.path ?? _randomFileName();
    final result = _runInWorker(
        WorkerOperation.xOpen, NameAndInt32Flags(filePath, flags, 0, 0));

    final outFlags = result.flag0;
    final fd = result.flag1;
    return (outFlags: outFlags, file: WasmFile(this, fd));
  }

  @override
  void xSleep(Duration duration) {}

  String _randomFileName({int length = 16}) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ012346789';

    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.writeCharCode(chars.codeUnitAt(random.nextInt(chars.length)));
    }

    return buffer.toString();
  }

  static bool get supportsAtomicsAndSharedMemory {
    return Atomics.supported && hasProperty(globalThis, 'SharedArrayBuffer');
  }

  static WorkerOptions createOptions() {
    return WorkerOptions(
      synchronizationBuffer:
          SharedArrayBuffer(RequestResponseSynchronizer.byteLength),
      communicationBuffer: SharedArrayBuffer(MessageSerializer.totalSize),
    );
  }
}

class WasmFile extends BaseVfsFile {
  final WasmVfs vfs;
  final int fd;

  WasmFile(this.vfs, this.fd);

  @override
  int readInto(Uint8List buffer, int offset) {
    // TODO: implement readInto
    throw UnimplementedError();
  }

  @override
  int xCheckReservedLock() {
    // TODO: implement xCheckReservedLock
    throw UnimplementedError();
  }

  @override
  void xClose() {
    vfs._runInWorker(WorkerOperation.xClose, Flags(fd, 0, 0));
  }

  @override
  int xFileSize() {
    final response =
        vfs._runInWorker(WorkerOperation.xFileSize, Flags(fd, 0, 0));
    return response.flag0;
  }

  @override
  void xLock(int mode) {
    // TODO: implement xLock
  }

  @override
  void xSync(int flags) {
    // TODO: implement xSync
  }

  @override
  void xTruncate(int size) {
    vfs._runInWorker(WorkerOperation.xTruncate, Flags(fd, size, 0));
  }

  @override
  void xUnlock(int mode) {
    // TODO: implement xUnlock
  }

  @override
  void xWrite(Uint8List buffer, int fileOffset) {
    // TODO: implement xWrite
  }
}
