#include <stdlib.h>

#include "bridge.h"

// sqlite3mc calls getentropy on initialization. That call pulls a bunch of WASI
// imports in when using the default WASI libc, which we're trying to avoid
// here. Instead, we use a local implementation backed by `Random.secure()` in
// Dart.
int getentropy(void* buf, size_t n) {
  return xRandomness(__builtin_wasm_ref_null_extern(), (int)n, (char*)buf);
}
