#include "bridge.h"
#include "sqlite3.h"

// Interfaces we want to access in Dart
SQLITE_API void *dart_sqlite3_malloc(size_t size) { return malloc(size); }

SQLITE_API void dart_sqlite3_free(void *ptr) { return free(ptr); }

SQLITE_API int dart_sqlite3_create_scalar_function(sqlite3 *db,
                                                   const char *zFunctionName,
                                                   int nArg, int eTextRep,
                                                   int id) {
  return sqlite3_create_function_v2(db, zFunctionName, nArg, eTextRep,
                                    (void *)id, &dartXFunc, NULL, NULL,
                                    &dartForgetAboutFunction);
}

SQLITE_API int dart_sqlite3_create_aggregate_function(sqlite3 *db,
                                                      const char *zFunctionName,
                                                      int nArg, int eTextRep,
                                                      int id) {
  return sqlite3_create_function_v2(db, zFunctionName, nArg, eTextRep,
                                    (void *)id, NULL, &dartXStep, &dartXFinal,
                                    &dartForgetAboutFunction);
}

SQLITE_API int dart_sqlite3_create_window_function(sqlite3 *db,
                                                   const char *zFunctionName,
                                                   int nArg, int eTextRep,
                                                   int id) {
  return sqlite3_create_window_function(
      db, zFunctionName, nArg, eTextRep, (void *)id, &dartXStep, &dartXFinal,
      &dartXValue, &dartXInverse, &dartForgetAboutFunction);
}

SQLITE_API void dart_sqlite3_updates(sqlite3 *db, int id) {
  sqlite3_update_hook(db, id >= 0 ? &dartUpdateHook : NULL, (void *)id);
}

SQLITE_API int dart_sqlite3_create_collation(sqlite3 *db, const char *zName,
                                             int eTextRep, int id) {
  return sqlite3_create_collation_v2(db, zName, eTextRep, (void *)id,
                                     &dartXCompare, &dartForgetAboutFunction);
}
