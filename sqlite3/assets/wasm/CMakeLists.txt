cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "sqlite3_web")
project(${PROJECT_NAME} LANGUAGES C)

include(FetchContent)
if (CMAKE_VERSION VERSION_GREATER_EQUAL "3.24.0")
  # cmake 3.24.0 added the `DOWNLOAD_EXTRACT_TIMESTAMP` and prints an ugly warning when
  # the default is used, so override it to the recommended behavior.
  # We can't really ask users to use a cmake that recent, so there's this if here.
  FetchContent_Declare(
    sqlite3
    URL https://sqlite.org/2023/sqlite-autoconf-3440000.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP NEW
  )
else()
  FetchContent_Declare(
    sqlite3
    URL https://sqlite.org/2023/sqlite-autoconf-3440000.tar.gz
  )
endif()

FetchContent_MakeAvailable(sqlite3)

set(wasm_visibility "__attribute__((visibility(\"default\")))")

get_filename_component(RS_LIB_DIR "${CMAKE_BINARY_DIR}/../../powersync-sqlite-core/" ABSOLUTE)
set(RS_LIB "powersync")
set(RS_WASM_TGT "wasm32-wasi")
set(RS_WASM_TGT_DIR "${RS_LIB_DIR}/target/${RS_WASM_TGT}")

set(RS_RELEASE_OUT "${RS_WASM_TGT_DIR}/wasm/")
set(RS_RELEASE_OUT_DEPS "${RS_WASM_TGT_DIR}/wasm/deps")
set(RS_RELEASE_EXTENSION_OUT "${RS_RELEASE_OUT}/powersync-extension.o")
set(RS_DEBUG_BC "${RS_WASM_TGT_DIR}/debug/deps/${RS_LIB}.bc")
set(RS_BUILD_COMMAND "cargo build -p powersync_loadable --profile wasm --no-default-features --features \"powersync_core/static powersync_core/omit_load_extension sqlite_nostd/static sqlite_nostd/omit_load_extension\" -Z build-std=panic_abort,core,alloc --target ${RS_WASM_TGT}")

file(GLOB BYTECODE_FILES "${RS_WASM_TGT_DIR}/wasm/deps/*.bc")
file(GLOB OBJ_FILES "${RS_WASM_TGT_DIR}/wasm/deps/*.o" CONFIGURE_DEPENDS "*.o")

macro(base_sqlite3_target name)
    add_executable(${name}
        "${sqlite3_SOURCE_DIR}/sqlite3.c"
        os_web.c
        helpers.c
    )

    target_link_libraries(${name} ${RS_RELEASE_EXTENSION_OUT})
    target_link_options(${name} PRIVATE -nostartfiles -Wl,--import-memory -Wl,--no-entry -Wl,--export-dynamic)
    target_include_directories(${name} PRIVATE "${PROJECT_SOURCE_DIR}/")
    target_include_directories(${name} PRIVATE ${sqlite3_SOURCE_DIR})
    target_compile_definitions(${name} PRIVATE
        _HAVE_SQLITE_CONFIG_H
        SQLITE_API=${wasm_visibility}
    )
    set_property(TARGET ${name} PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
endmacro()

# Script to use llc to get object code from bytecode
set(objectcode_script "${CMAKE_CURRENT_BINARY_DIR}/loop_objectcode_script.sh")
file(WRITE ${objectcode_script}
  "cd ${RS_RELEASE_OUT_DEPS}\n"
  "for filename in *.bc; do llc -march=wasm32 -filetype=obj $filename  -o $filename.o; done\n"
  "wasm-ld -relocatable *.o -o ../powersync-extension.o"
)

add_custom_target(
    powersync_core_bytecode
    COMMAND ${CMAKE_COMMAND} -E env
    "RUSTFLAGS=--emit=llvm-bc -C linker=true"
    cargo build -p powersync_loadable --profile wasm --no-default-features --features \"powersync_core/static powersync_core/omit_load_extension sqlite_nostd/static sqlite_nostd/omit_load_extension\" -Z build-std=panic_abort,core,alloc --target ${RS_WASM_TGT}
    WORKING_DIRECTORY ${RS_LIB_DIR}
    # Converts bytecode to wasm object files
    COMMAND sh ${objectcode_script}
)

base_sqlite3_target(sqlite3_debug)
file(DOWNLOAD https://raw.githubusercontent.com/sqlite/sqlite/master/src/test_vfstrace.c "${CMAKE_BINARY_DIR}/vfstrace.c")
target_sources(sqlite3_debug PRIVATE "${CMAKE_BINARY_DIR}/vfstrace.c")
target_compile_options(sqlite3_debug PRIVATE -g)
target_compile_definitions(sqlite3_debug PRIVATE SQLITE_ENABLE_VFSTRACE SQLITE_ENABLE_API_ARMOR)
set_target_properties(sqlite3_debug PROPERTIES OUTPUT_NAME "sqlite3" SUFFIX ".debug.wasm")

base_sqlite3_target(sqlite3_opt)
target_compile_options(sqlite3_opt PRIVATE -Oz)
set_target_properties(sqlite3_opt PROPERTIES OUTPUT_NAME "sqlite3" SUFFIX ".tmp.wasm")
add_custom_command(TARGET sqlite3_opt POST_BUILD
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../../
    COMMAND dart run tool/wasm_dce.dart ${CMAKE_CURRENT_BINARY_DIR}/sqlite3.tmp.wasm ${CMAKE_CURRENT_BINARY_DIR}/sqlite3.dce.wasm
    COMMAND wasm-opt ${CMAKE_CURRENT_BINARY_DIR}/sqlite3.dce.wasm -O4 -o ${CMAKE_CURRENT_BINARY_DIR}/sqlite3.wasm
)

add_dependencies(sqlite3_opt powersync_core_bytecode)
add_dependencies(sqlite3_debug powersync_core_bytecode)

add_custom_target(output)
add_custom_command(TARGET output COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/sqlite3.wasm ${PROJECT_SOURCE_DIR}/../../example/web/sqlite3.wasm DEPENDS)
add_custom_command(TARGET output COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/sqlite3.debug.wasm ${PROJECT_SOURCE_DIR}/../../example/web/sqlite3.debug.wasm)
add_dependencies(output sqlite3_debug sqlite3_opt powersync_core_bytecode)