#define WASI_EMULATED_MMAN 1

// Don't include the default VFS implementations, we write our own
#define SQLITE_OS_OTHER 1

// Don't include locking code
#define SQLITE_THREADSAFE 0

// Our implementation of temporary files is also entirely in-memory,
// so there really is no point in using temp files.
#define SQLITE_TEMP_STORE 3

// Recommended options
#define SQLITE_DQS 0
#define SQLITE_DEFAULT_MEMSTATUS 0
#define SQLITE_DEFAULT_WAL_SYNCHRONOUS 1
#define SQLITE_LIKE_DOESNT_MATCH_BLOBS 1
#define SQLITE_MAX_EXPR_DEPTH 0
#define SQLITE_OMIT_DECLTYPE 1
#define SQLITE_USE_ALLOCA 1
#define SQLITE_BYTEORDER 1234

// We have them, so we may as well let sqlite3 use them?
#define HAVE_ISNAN 1
#define HAVE_LOCALTIME_R 1
#define HAVE_LOCALTIME_S 1
#define HAVE_MALLOC_USABLE_SIZE 1
#define HAVE_STRCHRNUL 1

#define SQLITE_ENABLE_FTS5 1
#define SQLITE_ENABLE_MATH_FUNCTIONS 1
#define SQLITE_ENABLE_RTREE 1

// Disable things we don't need
#define SQLITE_OMIT_DEPRECATED
#define SQLITE_OMIT_PROGRESS_CALLBACK
#define SQLITE_OMIT_AUTHORIZATION
#define SQLITE_UNTESTABLE
#define SQLITE_OMIT_COMPILEOPTION_DIAGS
#define SQLITE_OMIT_LOAD_EXTENSION
#define SQLITE_OMIT_TCL_VARIABLE
#define SQLITE_OMIT_UTF16
#define SQLITE_OMIT_DESERIALIZE
#define SQLITE_DISABLE_DIRSYNC
