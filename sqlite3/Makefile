CC=clang
WASI_SYSROOT=/usr/share/wasi-sysroot
BUILD_DIR=.dart_tool/native_build

SQLITE_AMALGAMATION = sqlite-amalgamation-3380200
SQLITE_URL=https://www.sqlite.org/2022/sqlite-amalgamation-3380200.zip

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/$(SQLITE_AMALGAMATION).zip: $(BUILD_DIR)
	curl $(SQLITE_URL) --output $(BUILD_DIR)/$(SQLITE_AMALGAMATION).zip

$(BUILD_DIR)/$(SQLITE_AMALGAMATION): $(BUILD_DIR)/$(SQLITE_AMALGAMATION).zip
	mkdir -p $(BUILD_DIR)/$(SQLITE_AMALGAMATION)
	unzip -u '$(BUILD_DIR)/$(SQLITE_AMALGAMATION).zip' -d $(BUILD_DIR)

$(BUILD_DIR)/$(SQLITE_AMALGAMATION)/test_vfstrace.c: $(BUILD_DIR)/$(SQLITE_AMALGAMATION)
	curl https://raw.githubusercontent.com/sqlite/sqlite/master/src/test_vfstrace.c -o $(BUILD_DIR)/$(SQLITE_AMALGAMATION)/test_vfstrace.c

example/web/sqlite3.wasm: $(BUILD_DIR)/$(SQLITE_AMALGAMATION) assets/wasm/os_web.c
	$(CC) --target=wasm32-unknown-wasi \
	--sysroot $(WASI_SYSROOT) \
	-Iassets/wasm -I$(BUILD_DIR)/$(SQLITE_AMALGAMATION) \
	-nostartfiles \
	-Ofast \
	-Wl,--import-memory -Wl,--no-entry -Wl,--export-dynamic \
	-D_HAVE_SQLITE_CONFIG_H -DSQLITE_API='__attribute__((visibility("default")))' \
	-o example/web/sqlite3.wasm \
	$(BUILD_DIR)/$(SQLITE_AMALGAMATION)/sqlite3.c assets/wasm/os_web.c assets/wasm/helpers.c

example/web/sqlite3.debug.wasm: $(BUILD_DIR)/$(SQLITE_AMALGAMATION) $(BUILD_DIR)/$(SQLITE_AMALGAMATION)/test_vfstrace.c assets/wasm/os_web.c
	$(CC) --target=wasm32-unknown-wasi \
	--sysroot $(WASI_SYSROOT) \
	-Iassets/wasm -I$(BUILD_DIR)/$(SQLITE_AMALGAMATION) \
	-nostartfiles \
	-g \
	-Wl,--import-memory -Wl,--no-entry -Wl,--export-dynamic \
	-D_HAVE_SQLITE_CONFIG_H -DSQLITE_ENABLE_VFSTRACE -DSQLITE_API='__attribute__((visibility("default")))' \
	-o example/web/sqlite3.debug.wasm \
	$(BUILD_DIR)/$(SQLITE_AMALGAMATION)/sqlite3.c $(BUILD_DIR)/$(SQLITE_AMALGAMATION)/test_vfstrace.c assets/wasm/os_web.c assets/wasm/helpers.c

wasm: example/web/sqlite3.wasm
debug: example/web/sqlite3.debug.wasm
all: wasm debug

.PHONY: clean
clean:
	rm -r $(BUILD_DIR)
