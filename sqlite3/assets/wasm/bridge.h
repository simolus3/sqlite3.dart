#include <stdlib.h>
#include <stdint.h>

#define import_dart(name) __attribute__((import_module("dart"), import_name(name)))

import_dart("random") extern void dartRandom(char* buf, size_t length);
import_dart("error_log") extern void dartLogError(const char* msg);
import_dart("now") extern void dartCurrentTimeMillis(int64_t* out);
