#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "bridge.h"
#include "sqlite3.h"

extern int sqlite3_powersync_init(sqlite3 *db, char **pzErrMsg,
                                  const sqlite3_api_routines *pApi);

int getentropy(void* buf, size_t n) {
    return xRandomness(-1, (int) n, (char*) buf);
}

int sqlite3_os_init(void) {
    return SQLITE_OK;
}

int sqlite3_os_end(void) { return SQLITE_OK; }
