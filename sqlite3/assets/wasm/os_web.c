#include <limits.h>
#include <string.h>
#include <stdlib.h>

#include "bridge.h"
#include "sqlite3.h"

typedef struct {} dart_vfs_file;

int dartvfs_open(sqlite3_vfs* vfs, const char *zName, sqlite3_file* file, int flags, int *pOutFlags) {
  return SQLITE_OK;
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
    3,             // iVersion
    sizeof(dart_vfs_file),
    INT_MAX,    // Maximum file pathname length
    NULL,       // Next VFS, registered by sqlite3
    "dart_wasm_bridge", // Name
    NULL,  /* App data, unused */
    &dartvfs_open,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    &dartvfs_random,
    &dartvfs_sleep,
    &dartvfs_currentTime,
    NULL,
    &dartvfs_currentTime64,
    NULL,
    NULL,
    NULL
  };

  sqlite3_vfs_register(&vfs, 1);

  return SQLITE_OK;
}

int sqlite3_os_end(void) {
  return SQLITE_OK;
}
