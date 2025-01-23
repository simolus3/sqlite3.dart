#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "bridge.h"
#include "sqlite3.h"

int sqlite3_os_init(void) { return SQLITE_OK; }

int sqlite3_os_end(void) { return SQLITE_OK; }

struct tm *localtime_r(const time_t *restrict timep,
                       struct tm *restrict result) {
  // This is not implemented by the WASI libc, but we can easily implement it
  // with a Dart hook.
  static_assert(sizeof(time_t) == sizeof(int64_t));
  if (dartLocalTime(*timep, result)) {
    return 0;
  } else {
    return result;
  }
}