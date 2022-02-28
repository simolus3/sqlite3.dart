#include <stdlib.h>
#include "sqlite3.h"

// Interfaces we want to access in Dart
SQLITE_API void* dart_sqlite3_malloc(size_t size) {
  return malloc(size);
}

SQLITE_API void dart_sqlite3_free(void* ptr) {
  return free(ptr);
}

int sqlite3_os_init(void) {
  return SQLITE_OK;
}

int sqlite3_os_end(void) {
  return SQLITE_OK;
}
