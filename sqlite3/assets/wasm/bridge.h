#include <stdint.h>
#include <stdlib.h>

#include "sqlite3.h"

#define import_dart(name) \
  __attribute__((import_module("dart"), import_name(name)))

// Defines functions implemented in Dart. These functions are imported into
// the wasm module.

import_dart("random") extern void dartRandom(char *buf, size_t length);
import_dart("error_log") extern void dartLogError(const char *msg);
import_dart("now") extern int64_t dartUnixMillis();
import_dart("path_normalize") extern int dartNormalizePath(const char *zPath,
                                                           char *zOut,
                                                           int nOut);

import_dart("function_xFunc") extern void dartXFunc(sqlite3_context *ctx,
                                                    int nArgs,
                                                    sqlite3_value **value);
import_dart("function_xStep") extern void dartXStep(sqlite3_context *ctx,
                                                    int nArgs,
                                                    sqlite3_value **value);
import_dart("function_xInverse") extern void dartXInverse(
    sqlite3_context *ctx, int nArgs, sqlite3_value **value);
import_dart("function_xFinal") extern void dartXFinal(sqlite3_context *ctx);
import_dart("function_xValue") extern void dartXValue(sqlite3_context *ctx);
import_dart("function_forget") extern void dartForgetAboutFunction(void *ptr);
import_dart("function_hook") extern void dartUpdateHook(void *id, int kind,
                                                        const char *db,
                                                        const char *table,
                                                        sqlite3_int64 rowid);
import_dart("function_compare") extern int dartXCompare(void *id, int lengthA,
                                                        const void *a,
                                                        int lengthB,
                                                        const void *b);

import_dart("fs_create") extern int dartCreateFile(const char *zPath,
                                                   int flags);
import_dart("fs_temp_create") extern const char *dartCreateTemporaryFile();
import_dart("fs_size") extern int dartFileSize(const char *zPath,
                                               sqlite3_int64 *pSize);
import_dart("fs_truncate") extern int dartTruncate(const char *zPath,
                                                   sqlite3_int64 pSize);
import_dart("fs_read") extern int dartRead(const char *zPath, void *into,
                                           int amt, sqlite3_int64 offset);
import_dart("fs_write") extern int dartWrite(const char *zPath,
                                             const void *from, int amt,
                                             sqlite3_int64 offset);
import_dart("fs_delete") extern int dartDeleteFile(const char *zPath);
import_dart("fs_access") extern int dartAccessFile(const char *zName, int flags,
                                                   int *pResOut);
