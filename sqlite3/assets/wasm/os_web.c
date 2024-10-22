#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "bridge.h"
#include "sqlite3.h"

extern int sqlite3_powersync_init(sqlite3 *db, char **pzErrMsg,
                                  const sqlite3_api_routines *pApi);

int sqlite3_os_init(void) {
  int rc = sqlite3_auto_extension((void (*)(void)) & sqlite3_powersync_init);
  if (rc != SQLITE_OK) {
    return rc;
  }
  return SQLITE_OK;
}

int sqlite3_os_end(void) { return SQLITE_OK; }
