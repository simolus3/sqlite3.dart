// This file defines the definitions for which we generate FFI bindings on
// native platforms. To re-generate bindings, run:
// `dart run ffigen --config ffigen.yaml`.
#include <stdint.h>

typedef struct sqlite3_char sqlite3_char;
typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;
typedef struct sqlite3_backup sqlite3_backup;
typedef struct sqlite3_api_routines sqlite3_api_routines;

sqlite3_char *sqlite3_temp_directory;

int sqlite3_initialize();

int sqlite3_open_v2(sqlite3_char *filename, sqlite3 **ppDb, int flags,
                    sqlite3_char *zVfs);
int sqlite3_close_v2(sqlite3 *db);
sqlite3_char *sqlite3_db_filename(sqlite3 *db, sqlite3_char *zDbName);
const sqlite3_char *sqlite3_compileoption_get(int N);

// Error handling
int sqlite3_extended_result_codes(sqlite3 *db, int onoff);
int sqlite3_extended_errcode(sqlite3 *db);
sqlite3_char *sqlite3_errmsg(sqlite3 *db);
sqlite3_char *sqlite3_errstr(int code);
void sqlite3_free(void *ptr);

// Versions
sqlite3_char *sqlite3_libversion();
sqlite3_char *sqlite3_sourceid();
int sqlite3_libversion_number();

// Database
int64_t sqlite3_last_insert_rowid(sqlite3 *db);
int sqlite3_changes(sqlite3 *db);
int sqlite3_exec(sqlite3 *db, sqlite3_char *sql, void *callback, void *argToCb,
                 sqlite3_char **errorOut);
void *sqlite3_update_hook(sqlite3 *,
                          void (*)(void *, int, sqlite3_char const *,
                                   sqlite3_char const *, int64_t),
                          void *);
void *sqlite3_commit_hook(sqlite3 *, int (*)(void *), void *);
void *sqlite3_rollback_hook(sqlite3 *, void (*)(void *), void *);
int sqlite3_get_autocommit(sqlite3 *db);

// Statements
int sqlite3_prepare_v2(sqlite3 *db, const sqlite3_char *zSql, int nByte,
                       sqlite3_stmt **ppStmt, const sqlite3_char **pzTail);
int sqlite3_prepare_v3(sqlite3 *db, const sqlite3_char *zSql, int nByte,
                       unsigned int prepFlags, sqlite3_stmt **ppStmt,
                       const sqlite3_char **pzTail);
int sqlite3_finalize(sqlite3_stmt *pStmt);
int sqlite3_step(sqlite3_stmt *pStmt);
int sqlite3_reset(sqlite3_stmt *pStmt);
int sqlite3_stmt_isexplain(sqlite3_stmt *pStmt);
int sqlite3_stmt_readonly(sqlite3_stmt *pStmt);

int sqlite3_column_count(sqlite3_stmt *pStmt);
int sqlite3_bind_parameter_count(sqlite3_stmt *pStmt);
int sqlite3_bind_parameter_index(sqlite3_stmt *, sqlite3_char *zName);
sqlite3_char *sqlite3_column_name(sqlite3_stmt *pStmt, int N);
sqlite3_char *sqlite3_column_table_name(sqlite3_stmt *pStmt, int N);

int sqlite3_bind_blob64(sqlite3_stmt *pStmt, int index, void *data,
                        uint64_t length, void *destructor);
int sqlite3_bind_double(sqlite3_stmt *pStmt, int index, double data);
int sqlite3_bind_int64(sqlite3_stmt *pStmt, int index, int64_t data);
int sqlite3_bind_null(sqlite3_stmt *pStmt, int index);
int sqlite3_bind_text(sqlite3_stmt *pStmt, int index, sqlite3_char *data,
                      int length, void *destructor);

void *sqlite3_column_blob(sqlite3_stmt *pStmt, int iCol);
double sqlite3_column_double(sqlite3_stmt *pStmt, int iCol);
int64_t sqlite3_column_int64(sqlite3_stmt *pStmt, int iCol);
sqlite3_char *sqlite3_column_text(sqlite3_stmt *pStmt, int iCol);
int sqlite3_column_bytes(sqlite3_stmt *pStmt, int iCol);
int sqlite3_column_type(sqlite3_stmt *pStmt, int iCol);

// Values

typedef struct sqlite3_value sqlite3_value;

void *sqlite3_value_blob(sqlite3_value *value);
double sqlite3_value_double(sqlite3_value *value);
int sqlite3_value_type(sqlite3_value *value);
int64_t sqlite3_value_int64(sqlite3_value *value);
sqlite3_char *sqlite3_value_text(sqlite3_value *value);
int sqlite3_value_bytes(sqlite3_value *value);

// Functions

typedef struct sqlite3_context sqlite3_context;

int sqlite3_create_function_v2(
    sqlite3 *db, sqlite3_char *zFunctionName, int nArg, int eTextRep,
    void *pApp, void (*xFunc)(sqlite3_context *, int, sqlite3_value **),
    void (*xStep)(sqlite3_context *, int, sqlite3_value **),
    void (*xFinal)(sqlite3_context *), void (*xDestroy)(void *));
int sqlite3_create_window_function(
    sqlite3 *db, sqlite3_char *zFunctionName, int nArg, int eTextRep,
    void *pApp, void (*xStep)(sqlite3_context *, int, sqlite3_value **),
    void (*xFinal)(sqlite3_context *), void (*xValue)(sqlite3_context *),

    void (*xInverse)(sqlite3_context *, int, sqlite3_value **),
    void (*xDestroy)(void *));

void *sqlite3_aggregate_context(sqlite3_context *ctx, int nBytes);

void *sqlite3_user_data(sqlite3_context *ctx);
void sqlite3_result_blob64(sqlite3_context *ctx, void *data, uint64_t length,
                           void *destructor);
void sqlite3_result_double(sqlite3_context *ctx, double result);
void sqlite3_result_error(sqlite3_context *ctx, sqlite3_char *msg, int length);
void sqlite3_result_int64(sqlite3_context *ctx, int64_t result);
void sqlite3_result_null(sqlite3_context *ctx);
void sqlite3_result_text(sqlite3_context *ctx, sqlite3_char *data, int length,
                         void *destructor);

// Collations
int sqlite3_create_collation_v2(sqlite3 *, sqlite3_char *zName, int eTextRep,
                                void *pArg,
                                int (*xCompare)(void *, int, const void *, int,
                                                const void *),
                                void (*xDestroy)(void *));

// Backup
sqlite3_backup *sqlite3_backup_init(sqlite3 *pDestDb, sqlite3_char *zDestDb,
                                    sqlite3 *pSrcDb, sqlite3_char *zSrcDb);
int sqlite3_backup_step(sqlite3_backup *p, int nPage);
int sqlite3_backup_finish(sqlite3_backup *p);
int sqlite3_backup_remaining(sqlite3_backup *p);
int sqlite3_backup_pagecount(sqlite3_backup *p);

// Extensions
int sqlite3_auto_extension(void *xEntryPoint);

// Database configuration
int sqlite3_db_config(sqlite3 *db, int op, ...);

// VFS
typedef struct sqlite3_file sqlite3_file;

struct sqlite3_io_methods {
  int iVersion;
  int (*xClose)(sqlite3_file *);
  int (*xRead)(sqlite3_file *, void *, int iAmt, int64_t iOfst);
  int (*xWrite)(sqlite3_file *, const void *, int iAmt, int64_t iOfst);
  int (*xTruncate)(sqlite3_file *, int64_t size);
  int (*xSync)(sqlite3_file *, int flags);
  int (*xFileSize)(sqlite3_file *, int64_t *pSize);
  int (*xLock)(sqlite3_file *, int);
  int (*xUnlock)(sqlite3_file *, int);
  int (*xCheckReservedLock)(sqlite3_file *, int *pResOut);
  int (*xFileControl)(sqlite3_file *, int op, void *pArg);
  int (*xSectorSize)(sqlite3_file *);
  int (*xDeviceCharacteristics)(sqlite3_file *);
  /* Methods above are valid for version 1 */
  int (*xShmMap)(sqlite3_file *, int iPg, int pgsz, int, void **);
  int (*xShmLock)(sqlite3_file *, int offset, int n, int flags);
  void (*xShmBarrier)(sqlite3_file *);
  int (*xShmUnmap)(sqlite3_file *, int deleteFlag);
  /* Methods above are valid for version 2 */
  int (*xFetch)(sqlite3_file *, int64_t iOfst, int iAmt, void **pp);
  int (*xUnfetch)(sqlite3_file *, int64_t iOfst, void *p);
  /* Methods above are valid for version 3 */
  /* Additional methods may be added in future releases */
};

struct sqlite3_file {
  const struct sqlite3_io_methods *pMethods; /* Methods for an open file */
};

typedef struct sqlite3_vfs sqlite3_vfs;
typedef void (*sqlite3_syscall_ptr)(void);
typedef const char *sqlite3_filename;

struct sqlite3_vfs {
  int iVersion;       /* Structure version number (currently 3) */
  int szOsFile;       /* Size of subclassed sqlite3_file */
  int mxPathname;     /* Maximum file pathname length */
  sqlite3_vfs *pNext; /* Next registered VFS */
  const char *zName;  /* Name of this virtual file system */
  void *pAppData;     /* Pointer to application-specific data */
  int (*xOpen)(sqlite3_vfs *, sqlite3_filename zName, sqlite3_file *, int flags,
               int *pOutFlags);
  int (*xDelete)(sqlite3_vfs *, const char *zName, int syncDir);
  int (*xAccess)(sqlite3_vfs *, const char *zName, int flags, int *pResOut);
  int (*xFullPathname)(sqlite3_vfs *, const char *zName, int nOut, char *zOut);
  void *(*xDlOpen)(sqlite3_vfs *, const char *zFilename);
  void (*xDlError)(sqlite3_vfs *, int nByte, char *zErrMsg);
  void (*(*xDlSym)(sqlite3_vfs *, void *, const char *zSymbol))(void);
  void (*xDlClose)(sqlite3_vfs *, void *);
  int (*xRandomness)(sqlite3_vfs *, int nByte, char *zOut);
  int (*xSleep)(sqlite3_vfs *, int microseconds);
  int (*xCurrentTime)(sqlite3_vfs *, double *);
  int (*xGetLastError)(sqlite3_vfs *, int, char *);
  /*
  ** The methods above are in version 1 of the sqlite_vfs object
  ** definition.  Those that follow are added in version 2 or later
  */
  int (*xCurrentTimeInt64)(sqlite3_vfs *, int64_t *);
  /*
  ** The methods above are in versions 1 and 2 of the sqlite_vfs object.
  ** Those below are for version 3 and greater.
  */
  int (*xSetSystemCall)(sqlite3_vfs *, const char *zName, sqlite3_syscall_ptr);
  sqlite3_syscall_ptr (*xGetSystemCall)(sqlite3_vfs *, const char *zName);
  const char *(*xNextSystemCall)(sqlite3_vfs *, const char *zName);
  /*
  ** The methods above are in versions 1 through 3 of the sqlite_vfs object.
  ** New fields may be appended in future versions.  The iVersion
  ** value will increment whenever this happens.
  */
};
int sqlite3_vfs_register(sqlite3_vfs *, int makeDflt);
int sqlite3_vfs_unregister(sqlite3_vfs *);
