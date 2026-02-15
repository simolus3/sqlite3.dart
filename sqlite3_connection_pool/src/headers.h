#include <stdint.h>

typedef struct ConnectionPool ConnectionPool;
typedef struct PoolRequest PoolRequest;

typedef const void *Connection;

typedef struct ExternalFunctions {
  int (*sqlite3_close_v2)(Connection);
  int (*dart_post_c_object)(int64_t, const void* message);
} SqliteFunctions;

typedef struct InitializedPool {
  struct ExternalFunctions functions;
  Connection write;
  const Connection *reads;
  uintptr_t read_count;
} InitializedPool;

typedef struct InitializedPool *(*PoolInitializer)(void);

typedef int64_t DartPort;

ConnectionPool *pkg_sqlite3_connection_pool_open(const uint8_t *name,
                                                   uintptr_t name_len,
                                                   PoolInitializer initialize);

void pkg_sqlite3_connection_pool_close(const ConnectionPool *pool);

PoolRequest* pkg_sqlite3_connection_pool_obtain_read(const ConnectionPool *pool, int64_t tag, DartPort port);

PoolRequest* pkg_sqlite3_connection_pool_obtain_write(const ConnectionPool *pool, int64_t tag, DartPort port);

PoolRequest* pkg_sqlite3_connection_pool_obtain_exclusive(const ConnectionPool *pool,
                                                  int64_t tag,
                                                  DartPort port);

uintptr_t pkg_sqlite3_connection_pool_query_read_connection_count(const ConnectionPool *pool);
void pkg_sqlite3_connection_pool_query_connections(const ConnectionPool *pool, Connection *writer, Connection *readers, uintptr_t reader_count);

void pkg_sqlite3_connection_pool_request_close(PoolRequest *request);
