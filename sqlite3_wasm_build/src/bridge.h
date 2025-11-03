#include <stdint.h>
#include <stdlib.h>
#include <time.h>

#include "sqlite3.h"

#define import_dart(name) \
  __attribute__((import_module("dart"), import_name(name)))

// Defines functions implemented in Dart. These functions are imported into
// the wasm module.

// Static
import_dart("error_log") extern void dartLogError(const char* msg);
import_dart("localtime") extern int dartLocalTime(int64_t time,
                                                  struct tm* result);

// Methods on VirtualFileSystem
import_dart("xOpen") extern __externref_t xOpen(__externref_t vfs, sqlite3_filename zName,
                                      int* rcPtr, int flags,
                                      int* pOutFlags);
import_dart("xDelete") extern int xDelete(__externref_t vfs, const char* zName,
                                          int syncDir);
import_dart("xAccess") extern int xAccess(__externref_t vfs, const char* zName, int flags,
                                          int* pResOut);
import_dart("xFullPathname") extern int xFullPathname(__externref_t vfs,
                                                      const char* zName,
                                                      int nOut, char* zOut);
import_dart("xRandomness") extern int xRandomness(__externref_t vfs, int nByte,
                                                  char* zOut);
import_dart("xSleep") extern int xSleep(__externref_t vfs, int microseconds);
import_dart("xCurrentTimeInt64") extern int xCurrentTimeInt64(__externref_t vfs,
                                                              int64_t* target);

// Methods on VirtualFileSystemFile
import_dart("xClose") extern int xClose(__externref_t file);
import_dart("xRead") extern int xRead(__externref_t, void*, int iAmt,
                                      sqlite3_int64 iOfst);
import_dart("xWrite") extern int xWrite(__externref_t, const void*, int iAmt,
                                        sqlite3_int64 iOfst);
import_dart("xTruncate") extern int xTruncate(__externref_t, sqlite3_int64 size);
import_dart("xSync") extern int xSync(__externref_t, int flags);
import_dart("xFileSize") extern int xFileSize(__externref_t, int* pSize);
import_dart("xLock") extern int xLock(__externref_t, int);
import_dart("xUnlock") extern int xUnlock(__externref_t, int);
import_dart("xCheckReservedLock") extern int xCheckReservedLock(__externref_t,
                                                                int* pResOut);
import_dart("xDeviceCharacteristics") extern int xDeviceCharacteristics(__externref_t);

// Handles injected as externrefs, are DartExternalReference<Function> in Dart.
import_dart("dispatch_()v") extern void dartDispatchReturnVoid(__externref_t handle);
import_dart("dispatch_()i") extern int dartDispatchReturnInt(__externref_t handle);
import_dart("dispatch_update") extern void dartDispatchUpdateHook(__externref_t handle, int kind, const char* schema, const char* table, sqlite3_int64 rowid);

// Handles injected as externrefs, are DartExternalReference<RegisteredFunctionSet> in Dart.
import_dart("dispatch_xFunc") extern void dispatchXFunc(__externref_t handle, sqlite3_context* ctx,
                                                    int nArgs,
                                                    sqlite3_value** value);
import_dart("dispatch_xStep") extern void dispatchXStep(__externref_t handle, sqlite3_context* ctx,
                                                    int nArgs,
                                                    sqlite3_value** value);
import_dart("dispatch_xInverse") extern void dispatchXInverse(
    __externref_t handle, sqlite3_context* ctx, int nArgs, sqlite3_value** value);
import_dart("dispatch_xFinal") extern void dispatchXFinal(__externref_t handle, sqlite3_context* ctx);
import_dart("dispatch_xValue") extern void dispatchXValue(__externref_t handle, sqlite3_context* ctx);
import_dart("dispatch_compare") extern int dispatchXCompare(__externref_t handle, int lengthA,
                                                        const void* a,
                                                        int lengthB,
                                                        const void* b);

// Methods on SessionApplyCallbacks
import_dart("changeset_apply_filter") extern int dispatchApplyFilter(
    __externref_t callbacks, const char* zTab);
import_dart("changeset_apply_conflict") extern int dispatchApplyConflict(
    __externref_t callbacks, int eConflict, sqlite3_changeset_iter* p);
