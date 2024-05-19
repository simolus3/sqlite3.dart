import 'dart:math';

import 'package:path/path.dart' as p;

import '../../constants.dart';
import '../js_interop/typed_data.dart';
import '../vfs.dart';
import 'utils.dart';

final class InMemoryFileSystem extends BaseVirtualFileSystem {
  final Map<String, SafeU8Array?> fileData = {};

  InMemoryFileSystem({super.name = 'dart-memory', super.random});

  @override
  int xAccess(String path, int flags) {
    return fileData.containsKey(path) ? 1 : 0;
  }

  @override
  void xDelete(String path, int syncDir) {
    fileData.remove(path);
  }

  @override
  String xFullPathName(String path) {
    return p.url.normalize('/$path');
  }

  @override
  XOpenResult xOpen(Sqlite3Filename path, int flags) {
    final pathStr = path.path ?? random.randomFileName(prefix: '/');
    if (!fileData.containsKey(pathStr)) {
      final create = flags & SqlFlag.SQLITE_OPEN_CREATE;

      if (create != 0) {
        fileData[pathStr] = SafeU8Array.allocate(0);
      } else {
        throw VfsException(SqlError.SQLITE_CANTOPEN);
      }
    }

    return (
      outFlags: 0,
      file: _InMemoryFile(
        this,
        pathStr,
        flags & SqlFlag.SQLITE_OPEN_DELETEONCLOSE != 0,
      ),
    );
  }

  @override
  void xSleep(Duration duration) {}
}

class _InMemoryFile extends BaseVfsFile {
  final InMemoryFileSystem vfs;
  final String path;
  final bool deleteOnClose;

  var _lockMode = SqlFileLockingLevels.SQLITE_LOCK_NONE;

  _InMemoryFile(this.vfs, this.path, this.deleteOnClose);

  @override
  int readInto(SafeU8Array buffer, int offset) {
    final file = vfs.fileData[path];
    if (file == null || file.length <= offset) return 0;

    final available = min(buffer.length, file.length - offset);
    buffer.setRange(0, available, file, offset);
    return available;
  }

  @override
  int xCheckReservedLock() {
    return _lockMode >= SqlFileLockingLevels.SQLITE_LOCK_RESERVED ? 1 : 0;
  }

  @override
  void xClose() {
    if (deleteOnClose) {
      vfs.xDelete(path, 0);
    }
  }

  @override
  int xFileSize() {
    return vfs.fileData[path]!.length;
  }

  @override
  void xLock(int mode) {
    _lockMode = mode;
  }

  @override
  void xSync(int flags) {}

  @override
  void xTruncate(int size) {
    final file = vfs.fileData[path];

    final result = SafeU8Array.allocate(size);
    if (file != null) {
      result.setRange(0, min(size, file.length), file);
    }

    vfs.fileData[path] = result;
  }

  @override
  void xUnlock(int mode) {
    _lockMode = mode;
  }

  @override
  void xWrite(SafeU8Array buffer, int fileOffset) {
    final file = vfs.fileData[path] ?? SafeU8Array.allocate(0);
    final increasedSize = fileOffset + buffer.length - file.length;

    if (increasedSize <= 0) {
      // Can write directy
      file.setRange(fileOffset, fileOffset + buffer.length, buffer);
    } else {
      // We need to grow the file first
      final newFile = SafeU8Array.allocate(file.length + increasedSize)
        ..setAll(0, file)
        ..setAll(fileOffset, buffer);
      vfs.fileData[path] = newFile;
    }
  }
}
