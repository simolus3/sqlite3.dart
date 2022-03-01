#include <stdlib.h>
#include <stdint.h>

#include "sqlite3.h"

#define import_dart(name) __attribute__((import_module("dart"), import_name(name)))

import_dart("random") extern void dartRandom(char* buf, size_t length);
import_dart("error_log") extern void dartLogError(const char* msg);
import_dart("now") extern void dartCurrentTimeMillis(int64_t* out);

import_dart("function_xFunc") extern void dartXFunc(sqlite3_context *ctx, int nArgs, sqlite3_value **value);
import_dart("function_xStep") extern void dartXStep(sqlite3_context *ctx, int nArgs, sqlite3_value **value);
import_dart("function_xFinal") extern void dartXFinal(sqlite3_context *ctx);
import_dart("function_forget") extern void dartForgetAboutFunction(void* ptr);
