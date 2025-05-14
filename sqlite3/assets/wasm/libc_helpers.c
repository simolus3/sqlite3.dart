#include <stdlib.h>

#include <stdlib.h>
#include "bridge.h"
#include <time.h>

// sqlite3mc calls getentropy on initialization. That call pulls a bunch of WASI
// imports in when using the default WASI libc, which we're trying to avoid
// here. Instead, we use a local implementation backed by `Random.secure()` in
// Dart.
int getentropy(void* buf, size_t n) {
  return xRandomness(-1, (int)n, (char*)buf);
}

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