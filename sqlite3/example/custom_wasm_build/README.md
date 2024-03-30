```
clang --target=wasm32-unknown-wasi --sysroot=/usr/share/wasi-sysroot ../../.dart_tool/sqlite3_build/libsqlite3_opt_lib.a target/wasm32-wasi/debug/libcustom_wasm_build.a -o sqlite3.wasm -nostartfiles -Wl,--no-entry -Wl
,--export-dynamic -Wl,--import-memory
```