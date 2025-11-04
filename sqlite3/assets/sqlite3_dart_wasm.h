#include "sqlite3.h"

// Additional bindings we need for WASM interop.
// These are implemented in sqlite3_wasm_build, this header is only used for
// ffigen.
typedef struct {
} externref;

void* dart_sqlite3_malloc(int size);
void dart_sqlite3_free(void* ptr);

int dart_sqlite3_bind_blob(sqlite3_stmt* stmt, int index, const void* buf,
                           int len);

int dart_sqlite3_bind_text(sqlite3_stmt* stmt, int index, const char* buf,
                           int len);

sqlite3_vfs* dart_sqlite3_register_vfs(const char* name, externref* vfs,
                                       int makeDefault);
int dart_sqlite3_unregister_vfs(sqlite3_vfs* vfs);

int dart_sqlite3_create_function_v2(sqlite3* db, const char* zFunctionName,
                                    int nArg, int eTextRep, int isAggregate,
                                    externref* handlers);

int dart_sqlite3_create_window_function(sqlite3* db, const char* zFunctionName,
                                        int nArg, int eTextRep,
                                        externref* handlers);

void dart_sqlite3_updates(sqlite3* db, externref* callback);

void dart_sqlite3_commits(sqlite3* db, externref* callback);

void dart_sqlite3_rollbacks(sqlite3* db, externref* callback);

int dart_sqlite3_create_collation(sqlite3* db, const char* zName, int eTextRep,
                                  externref* function);

int dart_sqlite3_db_config_int(sqlite3* db, int op, int arg);

int dart_sqlite3changeset_apply(sqlite3* db, int nChangeset, void* pChangeset,
                                externref* callbacks, int filter);
