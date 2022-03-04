#include <limits.h>
#include <string.h>
#include <stdlib.h>

#include "bridge.h"
#include "sqlite3.h"

typedef struct {
  const struct sqlite3_io_methods *pMethods;
  const char *zPath;
  int flags;
} dart_vfs_file;

int dartvfs_close(sqlite3_file *file) {
  dart_vfs_file *p = (dart_vfs_file *) file;

  if (p->flags & SQLITE_OPEN_MEMORY) {
    // This flag is set for temporary files, for which we need to free
    // the path pointer now.
    free((char *) p->zPath);
  }

  if (p->flags & SQLITE_OPEN_DELETEONCLOSE) {
    int deleteResult = dartDeleteFile(p->zPath);

    if (deleteResult != SQLITE_OK) {
      return deleteResult;
    }
  }

  return SQLITE_OK;
}

int dartvfs_read(sqlite3_file *file, void* buf, int iAmt, sqlite3_int64 iOfst) {
  int bytesRead = dartRead(((dart_vfs_file *) file)->zPath, buf, iAmt, iOfst);
  if (bytesRead < 0) {
    return SQLITE_IOERR;
  }

  if (bytesRead < iAmt) {
    // We need to fill the unread portion of the buffer with zeroes.
    memset(buf + bytesRead, 0, iAmt - bytesRead);

    return SQLITE_IOERR_SHORT_READ;
  }

  return SQLITE_OK;
}

int dartvfs_write(sqlite3_file *file, const void *buf, int iAmt, sqlite3_int64 iOfst) {
  return dartWrite(((dart_vfs_file *) file)->zPath, buf, iAmt, iOfst);
}

int dartvfs_truncate(sqlite3_file *file, sqlite3_int64 size) {
  return dartTruncate(((dart_vfs_file *) file)->zPath, size);
}

int dartvfs_sync(sqlite3_file *file, int flags) {
  return SQLITE_OK; // Not currently implemented, we sync on write
}

int dartvfs_fileSize(sqlite3_file *file, sqlite3_int64 *pSize) {
  return dartFileSize(((dart_vfs_file *) file)->zPath, pSize);
}

int dartvfs_lock(sqlite3_file *file, int i) {
  return SQLITE_OK; // Not currently implemented, we don't support shared databases
}

int dartvfs_unlock(sqlite3_file *file, int i) {
  return SQLITE_OK; // Same here.
}

int dartvfs_checkReservedLock(sqlite3_file *file, int *pResOut) {
  return SQLITE_OK; // And here.
}

int dartvfs_fileControl(sqlite3_file *file, int op, void *pArg) {
  // "VFS implementations should return SQLITE_NOTFOUND for file control opcodes that
  // they do not recognize". Well, we don't recognize any.
  return SQLITE_NOTFOUND;
}

int dartvfs_sectorSize(sqlite3_file *file) {
  return 4096; // Keep in sync with Dart implementation and deviceCharacteristics
}

int dartvfs_deviceCharacteristics(sqlite3_file *file) {
  return SQLITE_IOCAP_ATOMIC4K;
}

int dartvfs_open(sqlite3_vfs* vfs, const char *zName, sqlite3_file* file, int flags, int *pOutFlags) {
  dart_vfs_file *p = (dart_vfs_file *) file;

  p->flags = flags;

  if (zName) {
    p->zPath = zName;

    int created = dartCreateFile(zName, flags);

    if (created != SQLITE_OK) {
      return created;
    }
  } else {
    p->zPath = dartCreateTemporaryFile();
    // Flag indicating that we need to free the path later.
    p->flags |= SQLITE_OPEN_MEMORY;
  }

  static sqlite3_io_methods methods = {
    .iVersion = 1,
    .xClose = &dartvfs_close,
    .xRead = &dartvfs_read,
    .xWrite = &dartvfs_write,
    .xTruncate = &dartvfs_truncate,
    .xSync = &dartvfs_sync,
    .xFileSize = &dartvfs_fileSize,
    .xLock = &dartvfs_lock,
    .xUnlock = &dartvfs_unlock,
    .xCheckReservedLock = &dartvfs_checkReservedLock,
    .xFileControl = &dartvfs_fileControl,
    .xSectorSize = &dartvfs_sectorSize,
    .xDeviceCharacteristics = &dartvfs_deviceCharacteristics
  };
  p->pMethods = &methods;

  return SQLITE_OK;
}

int dartvfs_delete(sqlite3_vfs *vfs, const char *zName, int syncDir) {
  return dartDeleteFile(zName);
}

int dartvfs_access(sqlite3_vfs *vfs, const char *zName, int flags, int *pResOut) {
  return dartAccessFile(zName, flags, pResOut);
}

int dartvfs_fullPathname(sqlite3_vfs *vgs, const char *zName, int nOut, char *zOut) {
  return dartNormalizePath(zName, zOut, nOut);
}

int dartvfs_random(sqlite3_vfs* vfs, int nByte, char *zOut) {
  dartRandom(zOut, nByte);
  return nByte;
}

int dartvfs_sleep(sqlite3_vfs* vfs, int microseconds) {
  return SQLITE_OK;
}

int dartvfs_currentTime(sqlite3_vfs* vfs, double* dbl) {
  return SQLITE_IOERR; // Use currentTimeInt64
}

int getLastError(sqlite3_vfs* vfs, int i, char* ptr) {
  return SQLITE_OK;
}

int dartvfs_currentTime64(sqlite3_vfs* vfs, sqlite3_int64* out) {
  dartCurrentTimeMillis(out);
  return SQLITE_OK;
}

int sqlite3_os_init(void) {
  static sqlite3_vfs vfs = {
    .iVersion = 3,
    .szOsFile =sizeof(dart_vfs_file),
    .mxPathname = 512,
    .pNext = NULL,
    .zName = "dart_wasm_bridge",
    .pAppData = NULL,
    .xOpen = &dartvfs_open,
    .xDelete = &dartvfs_delete,
    .xAccess = &dartvfs_access,
    .xFullPathname = &dartvfs_fullPathname,
    .xDlOpen = NULL,
    .xDlError = NULL,
    .xDlSym = NULL,
    .xDlClose = NULL,
    .xRandomness = &dartvfs_random,
    .xSleep = &dartvfs_sleep,
    .xCurrentTime = &dartvfs_currentTime,
    .xGetLastError = NULL,
    .xCurrentTimeInt64 = &dartvfs_currentTime64,
    .xSetSystemCall = NULL,
    .xGetSystemCall = NULL,
    .xNextSystemCall = NULL
  };

  sqlite3_vfs_register(&vfs, 1);

  return SQLITE_OK;
}

int sqlite3_os_end(void) {
  return SQLITE_OK;
}
