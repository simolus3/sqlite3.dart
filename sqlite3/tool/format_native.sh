#!/bin/sh
clang-format --style=google -i assets/sqlite3.h assets/wasm/*.{c,h} test/**/*.c
