#include <string.h>

#include "bridge.h"
#include "external_objects.h"
#include "sqlite3.h"

#define DART_FILE(file) (host_object_get(((dart_vfs_file*)(file))->dart_object))

#ifdef SQLITE_ENABLE_VFSTRACE
// When this is enabled, assume that `vfstrace_register` exists
// See https://www.sqlite.org/src/doc/trunk/src/test_vfstrace.c

extern int vfstrace_register(
    const char* zTraceName,           // Name of the newly constructed VFS
    const char* zOldVfsName,          // Name of the underlying VFS
    int (*xOut)(const char*, void*),  // Output routine.  ex: fputs
    void* pOutArg,                    // 2nd argument to xOut.  ex: stderr
    int makeDefault                   // Make the new VFS the default
);
#endif

typedef struct {
  struct sqlite3_io_methods* pMethods;
  void* dart_object;
} dart_vfs_file;

// Interfaces we want to access in Dart
SQLITE_API void* dart_sqlite3_malloc(size_t size) { return malloc(size); }

SQLITE_API void dart_sqlite3_free(void* ptr) { return free(ptr); }

SQLITE_API int dart_sqlite3_bind_blob(sqlite3_stmt* stmt, int index,
                                      const void* buf, int len) {
  return sqlite3_bind_blob64(stmt, index, buf, len, free);
}

SQLITE_API int dart_sqlite3_bind_text(sqlite3_stmt* stmt, int index,
                                      const char* buf, int len) {
  return sqlite3_bind_text(stmt, index, buf, len, free);
}

static int dartvfs_trace_log1(const char* msg, void* unused) {
  dartLogError(msg);
  return SQLITE_OK;
}

int dartvfs_close(sqlite3_file* file) {
  auto rc = xClose(DART_FILE(file));
  if (rc == 0) {
    host_object_free(((dart_vfs_file*) file)->dart_object);
  }
  return rc;
}

int dartvfs_read(sqlite3_file* file, void* buf, int iAmt, sqlite3_int64 iOfst) {
  return xRead(DART_FILE(file), buf, iAmt, iOfst);
}

int dartvfs_write(sqlite3_file* file, const void* buf, int iAmt,
                  sqlite3_int64 iOfst) {
  return xWrite(DART_FILE(file), buf, iAmt, iOfst);
}

int dartvfs_truncate(sqlite3_file* file, sqlite3_int64 size) {
  return xTruncate(DART_FILE(file), size);
}

int dartvfs_sync(sqlite3_file* file, int flags) {
  return xSync(DART_FILE(file), flags);
}

int dartvfs_fileSize(sqlite3_file* file, sqlite3_int64* pSize) {
  int size32;
  int rc = xFileSize(DART_FILE(file), &size32);
  *pSize = (sqlite3_int64)size32;
  return rc;
}

int dartvfs_lock(sqlite3_file* file, int i) { return xLock(DART_FILE(file), i); }

int dartvfs_unlock(sqlite3_file* file, int i) {
  return xUnlock(DART_FILE(file), i);
}

int dartvfs_checkReservedLock(sqlite3_file* file, int* pResOut) {
  return xCheckReservedLock(DART_FILE(file), pResOut);
}

int dartvfs_fileControl(sqlite3_file* file, int op, void* pArg) {
  // "VFS implementations should return SQLITE_NOTFOUND for file control opcodes
  // that they do not recognize". Well, we don't recognize any.
  return SQLITE_NOTFOUND;
}

int dartvfs_deviceCharacteristics(sqlite3_file* file) {
  return xDeviceCharacteristics(DART_FILE(file));
}

int dartvfs_sectorSize(sqlite3_file* file) {
  // This is also the value of SQLITE_DEFAULT_SECTOR_SIZE, which would be picked
  // if this function didn't exist. We need this method because vfstrace does
  // not support null callbacks.
  return 4096;
}

static int dartvfs_open(sqlite3_vfs* vfs, sqlite3_filename zName,
                        sqlite3_file* file, int flags, int* pOutFlags) {
  dart_vfs_file* dartFile = (dart_vfs_file*)file;
  memset(dartFile, 0, sizeof(dart_vfs_file));

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
      .xDeviceCharacteristics = &dartvfs_deviceCharacteristics,
#ifdef SQLITE_ENABLE_VFSTRACE
      .xSectorSize = &dartvfs_sectorSize
#else
      .xSectorSize = NULL
#endif
  };

  // The xOpen call will also set the dart_fd field.
  int rc;
  auto dart_file_object = xOpen(host_object_get(vfs->pAppData), zName, &rc, flags, pOutFlags);

  if (__builtin_wasm_ref_is_null_extern(dart_file_object)) {
    dartFile->pMethods = nullptr;
  } else {
    // sqlite3 will call xClose() even if this open call returns an error if
    // methods are set. So, we only provide the methods if a file has actually
    // been opened.
    dartFile->pMethods = &methods;
    dartFile->dart_object = host_object_insert(dart_file_object);
  }

  return rc;
}

static int dartvfs_delete(sqlite3_vfs* vfs, const char* zName, int syncDir) {
  return xDelete(host_object_get(vfs->pAppData), zName, syncDir);
}

static int dartvfs_access(sqlite3_vfs* vfs, const char* zName, int flags,
                          int* pResOut) {
  return xAccess(host_object_get(vfs->pAppData), zName, flags, pResOut);
}

static int dartvfs_fullPathname(sqlite3_vfs* vfs, const char* zName, int nOut,
                                char* zOut) {
  return xFullPathname(host_object_get(vfs->pAppData), zName, nOut, zOut);
}

static int dartvfs_randomness(sqlite3_vfs* vfs, int nByte, char* zOut) {
  return xRandomness(host_object_get(vfs->pAppData), nByte, zOut);
}

static int dartvfs_sleep(sqlite3_vfs* vfs, int microseconds) {
  return xSleep(host_object_get(vfs->pAppData), microseconds);
}

static int dartvfs_currentTimeInt64(sqlite3_vfs* vfs, sqlite3_int64* timeOut) {
  int64_t milliseconds;
  int rc = xCurrentTimeInt64(host_object_get(vfs->pAppData), &milliseconds);
  if (rc) {
    return rc;
  }

  // https://github.com/sqlite/sqlite/blob/8ee75f7c3ac1456b8d941781857be27bfddb57d6/src/os_unix.c#L6757
  static const int64_t unixEpoch = 24405875 * (int64_t)8640000;
  *timeOut = unixEpoch + milliseconds;
  return SQLITE_OK;
}

SQLITE_API sqlite3_vfs* dart_sqlite3_register_vfs(const char* name, __externref_t dart_vfs,
                                                  int makeDefault) {
  sqlite3_vfs* vfs = calloc(1, sizeof(sqlite3_vfs));
  vfs->iVersion = 2;
  vfs->szOsFile = sizeof(dart_vfs_file);
  vfs->mxPathname = 1024;
  vfs->zName = name;
  vfs->pAppData = host_object_insert(dart_vfs);
  vfs->xOpen = &dartvfs_open;
  vfs->xDelete = &dartvfs_delete;
  vfs->xAccess = &dartvfs_access;
  vfs->xFullPathname = &dartvfs_fullPathname;
  vfs->xRandomness = &dartvfs_randomness;
  vfs->xSleep = &dartvfs_sleep;
  vfs->xCurrentTimeInt64 = &dartvfs_currentTimeInt64;

#ifdef SQLITE_ENABLE_VFSTRACE
  sqlite3_vfs_register(vfs, 0);

  static const char* prefix = "trace_";
  static const int prefixLength = 6;
  char* traceName = malloc(strlen(name) + prefixLength);
  strcpy(traceName, prefix);
  strcpy(&traceName[prefixLength], name);

  vfstrace_register(traceName, name, &dartvfs_trace_log1, NULL, makeDefault);
#else
  // Just register the VFS as is.
  int rc = sqlite3_vfs_register(vfs, makeDefault);
  if (rc) {
    host_object_free(vfs->pAppData);
    free(vfs);
    return NULL;
  }
#endif
  return vfs;
}

int dart_sqlite3_unregister_vfs(sqlite3_vfs* vfs) {
  auto rc = sqlite3_vfs_unregister(vfs);
  if (!rc) {
    host_object_free(vfs->pAppData);
    free(vfs->zName);
    free(vfs);
  }
  return rc;
}

static void dartXFunc(sqlite3_context* context, int nArg, sqlite3_value** args) {
  auto handle = host_object_get(sqlite3_user_data(context));
  return dispatchXFunc(handle, context, nArg, args);
}

static void dartXStep(sqlite3_context* context, int nArg, sqlite3_value** args) {
  auto handle = host_object_get(sqlite3_user_data(context));
  return dispatchXStep(handle, context, nArg, args);
}

static void dartXInverse(sqlite3_context* context, int nArg, sqlite3_value** args) {
  auto handle = host_object_get(sqlite3_user_data(context));
  return dispatchXInverse(handle, context, nArg, args);
}

static void dartXFinal(sqlite3_context* context) {
  auto handle = host_object_get(sqlite3_user_data(context));
  return dispatchXFinal(handle, context);
}

static void dartXValue(sqlite3_context* context) {
  auto handle = host_object_get(sqlite3_user_data(context));
  return dispatchXValue(handle, context);
}

SQLITE_API int dart_sqlite3_create_function_v2(
    sqlite3* db,
    const char* zFunctionName,
    int nArg,
    int eTextRep,
    int isAggregate,
    __externref_t handlers
) {
  auto id = host_object_insert(handlers);
  return sqlite3_create_function_v2(
    db,
    zFunctionName,
    nArg,
    eTextRep,
    id,
    &dartXFunc,
    isAggregate ? &dartXStep : nullptr,
    isAggregate ? &dartXFinal : nullptr,
    &host_object_free
  );
}

SQLITE_API int dart_sqlite3_create_window_function(sqlite3* db, const char* zFunctionName,
                                        int nArg, int eTextRep, __externref_t handlers) {
  auto id = host_object_insert(handlers);
  return sqlite3_create_window_function(
    db,
    zFunctionName,
    nArg,
    eTextRep,
    id,
    &dartXStep,
    &dartXFinal,
    &dartXValue,
    &dartXInverse,
    &host_object_free
  );
}

static void dartXUpdate(void* context, int kind, const char* schema, const char* table, sqlite3_int64 rowid) {
  // TODO (not supported in clang): Cast to extern => anyref => function => call_ref
  dartDispatchUpdateHook(host_object_get(context), kind, schema, table, rowid);
}


SQLITE_API void dart_sqlite3_updates(sqlite3* db, __externref_t function) {
  void* previous;
  if (__builtin_wasm_ref_is_null_extern(function)) {
    previous = sqlite3_update_hook(db, nullptr, nullptr);
  } else {
    previous = sqlite3_update_hook(db, &dartXUpdate, host_object_insert(function));
  }

  if (previous) {
    host_object_free(previous);
  }
}

static int dartXCommit(void* context) {
  // TODO (not supported in clang): Cast to extern => anyref => function => call_ref
  return dartDispatchReturnInt(host_object_get(context));
}

SQLITE_API void dart_sqlite3_commits(sqlite3* db, __externref_t function) {
  void* previous;
  if (__builtin_wasm_ref_is_null_extern(function)) {
    previous = sqlite3_commit_hook(db, nullptr, nullptr);
  } else {
    previous = sqlite3_commit_hook(db, &dartXCommit, host_object_insert(function));
  }

  if (previous) {
    host_object_free(previous);
  }
}

static void dartXRollback(void* context) {
  // TODO (not supported in clang): Cast to extern => anyref => function => call_ref
  return dartDispatchReturnVoid(host_object_get(context));
}

SQLITE_API void dart_sqlite3_rollbacks(sqlite3* db, __externref_t function) {
  void* previous;
  if (__builtin_wasm_ref_is_null_extern(function)) {
    previous = sqlite3_rollback_hook(db, nullptr, nullptr);
  } else {
    previous = sqlite3_rollback_hook(db, &dartXRollback, host_object_insert(function));
  }

  if (previous) {
    host_object_free(previous);
  }
}

static int dartXCompare(void* context, int lengthA,
                                        const void* a,
                                        int lengthB,
                                        const void* b) {
  return dispatchXCompare(host_object_get(context), lengthA, a, lengthB, b);
}

SQLITE_API int dart_sqlite3_create_collation(sqlite3* db, const char* zName,
                                             int eTextRep, __externref_t function) {
  auto context = host_object_insert(function);
  return sqlite3_create_collation_v2(db, zName, eTextRep, context,
                                      &dartXCompare, &host_object_free);
}

SQLITE_API int dart_sqlite3_db_config_int(sqlite3* db, int op, int arg) {
  return sqlite3_db_config(db, op, arg);
}

static int dartChangesetXFilter(void *pCtx, const char *zTab) {
  return dispatchApplyFilter(host_object_get(pCtx), zTab);
}

static int dartChangesetXConflict(void *pCtx, int eConflict, sqlite3_changeset_iter* p) {
  return dispatchApplyConflict(host_object_get(pCtx), eConflict, p);
}

SQLITE_API int dart_sqlite3changeset_apply(sqlite3* db, int nChangeset,
                                           void* pChangeset, __externref_t callbacks,
                                           bool filter) {
  auto context = host_object_insert(callbacks);
  auto rc =  sqlite3changeset_apply(db, nChangeset, pChangeset,
                                filter ? &dartChangesetXFilter : 0,
                                &dartChangesetXConflict, context);
  host_object_free(context);
  return rc;
}
