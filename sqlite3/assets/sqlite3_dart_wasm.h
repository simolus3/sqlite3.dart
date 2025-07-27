#include "sqlite3.h"

// Additional bindings we need for WASM interop.
// These are implemented in helpers.c, this header is only used for ffigen.

void *dart_sqlite3_malloc(int size);
void dart_sqlite3_free(void *ptr);


sqlite3_vfs *dart_sqlite3_register_vfs(const char *name, int dartId,
                                                  int makeDefault);

int dart_sqlite3_create_scalar_function(sqlite3 *db,
                                                   const char *zFunctionName,
                                                   int nArg, int eTextRep,
                                                   int id);

int dart_sqlite3_create_aggregate_function(sqlite3 *db,
                                                      const char *zFunctionName,
                                                      int nArg, int eTextRep,
                                                      int id);

int dart_sqlite3_create_window_function(sqlite3 *db,
                                                   const char *zFunctionName,
                                                   int nArg, int eTextRep,
                                                   int id);

void dart_sqlite3_updates(sqlite3 *db, int id);

void dart_sqlite3_commits(sqlite3 *db, int id);

void dart_sqlite3_rollbacks(sqlite3 *db, int id);

int dart_sqlite3_create_collation(sqlite3 *db, const char *zName,
                                             int eTextRep, int id);

int dart_sqlite3_db_config_int(sqlite3 *db, int op, int arg);

int dart_sqlite3changeset_apply(sqlite3 *db, int nChangeset,
                                           void *pChangeset, void *pCtx,
                                           int filter);
