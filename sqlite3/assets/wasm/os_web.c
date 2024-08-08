#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "bridge.h"
#include "sqlite3.h"
#include "sqlite-vec.h"

int sqlite3_os_init(void) {
    sqlite3_auto_extension((void (*)(void)) sqlite3_vec_init);
    return SQLITE_OK;
}

int sqlite3_os_end(void) { return SQLITE_OK; }
