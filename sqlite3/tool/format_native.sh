#!/bin/sh
clang-format --style=google -i assets/sqlite3.h assets/sqlite3_dart_wasm.h assets/wasm/*.{c,h} test/**/*.c
