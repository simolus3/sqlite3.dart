CC=clang
WASI_SYSROOT=/usr/share/wasi-sysroot
BUILD_DIR=.dart_tool/native_build

example/web/sqlite3.wasm:
	$(CC) --target=wasm32-unknown-wasi \
	--sysroot $(WASI_SYSROOT) \
	-Iassets/wasm -I/tmp/sqlite/ \
	-nostartfiles \
	-Ofast \
	-Wl,--import-memory -Wl,--no-entry -Wl,--export-dynamic \
	-D_HAVE_SQLITE_CONFIG_H -DSQLITE_API='__attribute__((visibility("default")))' \
	-o example/web/sqlite.wasm \
	/tmp/sqlite/sqlite3.c assets/wasm/os_web.c assets/wasm/helpers.c

all: example/web/sqlite3.wasm

.PHONY: clean
clean:
	rm -r $(BUILD_DIR)
