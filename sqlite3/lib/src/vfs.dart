import 'dart:math';
import 'dart:typed_data';

import 'constants.dart';

class VfsException implements Exception {
  final int returnCode;

  const VfsException(this.returnCode) : assert(returnCode != 0);

  @override
  String toString() {
    return 'VfsException($returnCode)';
  }
}

class Sqlite3Filename {
  final String? path;

  Sqlite3Filename(this.path);
}

abstract class VirtualFileSystem {
  final String name;

  VirtualFileSystem(this.name);

  XOpenResult xOpen(
    Sqlite3Filename path,
    int flags,
  );
  void xDelete(String path, int syncDir);
  int xAccess(String path, int flags);
  String xFullPathName(String path);

  /// Fill the [target] with random bytes.
  ///
  /// __Safety warning__: Target may be a direct view over native memory that
  /// must not be used after this function returns.
  void xRandomness(Uint8List target);
  void xSleep(Duration duration);
  DateTime xCurrentTime();
}

typedef XOpenResult = ({int outFlags, VirtualFileSystemFile file});

abstract class VirtualFileSystemFile {
  void xClose();

  /// Fill the [target] with bytes read from [fileOffset].
  ///
  /// If the file is not large enough to fullfill the read, a [VfsException]
  /// with an error code of [SqlExtendedError.SQLITE_IOERR_SHORT_READ] must be
  /// thrown. Additional, the rest of [target] must be filled with zeroes.
  ///
  /// __Safety warning__: Target may be a direct view over native memory that
  /// must not be used after this function returns.
  void xRead(Uint8List target, int fileOffset);
  void xWrite(Uint8List buffer, int fileOffset);
  void xTruncate(int size);
  void xSync(int flags);
  int xFileSize();
  void xLock(int mode);
  void xUnlock(int mode);
  int xCheckReservedLock();
}

abstract class BaseVirtualFileSystem extends VirtualFileSystem {
  final Random random;

  BaseVirtualFileSystem({Random? random, required String name})
      : random = random ?? Random.secure(),
        super(name);

  @override
  void xRandomness(Uint8List target) {
    for (var i = 0; i < target.length; i++) {
      target[i] = random.nextInt(1 << 8);
    }
  }

  @override
  DateTime xCurrentTime() => DateTime.now();
}

abstract class BaseVfsFile implements VirtualFileSystemFile {
  int readInto(Uint8List buffer, int offset);

  @override
  void xRead(Uint8List target, int fileOffset) {
    final bytesRead = readInto(target, fileOffset);

    if (bytesRead < target.length) {
      // Remaining buffer must be filled with zeroes.
      target.fillRange(bytesRead, target.length, 0);

      // And we need to return a short read error
      throw const VfsException(SqlExtendedError.SQLITE_IOERR_SHORT_READ);
    }
  }
}
