#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "bridge.h"
#include "sqlite3.h"

extern int __rust_no_alloc_shim_is_unstable = 0;
extern int sqlite3_powersync_init(sqlite3 *db, char **pzErrMsg,
                                  const sqlite3_api_routines *pApi);

int sqlite3_os_init(void)
{
    sqlite3_auto_extension((void (*)(void)) & sqlite3_powersync_init);
    return SQLITE_OK;
}

int sqlite3_os_end(void) { return SQLITE_OK; }
