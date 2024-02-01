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
    # NOTE: When changing this, also update `test/wasm/sqlite3_test.dart`
    URL https://sqlite.org/2024/sqlite-autoconf-3450100.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP NEW
  )
else()
  FetchContent_Declare(
    sqlite3
    # NOTE: When changing this, also update `test/wasm/sqlite3_test.dart`
    URL https://sqlite.org/2024/sqlite-autoconf-3450100.tar.gz
  )
endif()

FetchContent_MakeAvailable(sqlite3)

set(wasm_visibility "__attribute__((visibility(\"default\")))")

macro(base_sqlite3_target name)
    add_executable(${name}
        "${sqlite3_SOURCE_DIR}/sqlite3.c"
        os_web.c
        helpers.c
    )

    target_link_options(${name} PRIVATE -nostartfiles -Wl,--import-memory -Wl,--no-entry -Wl,--export-dynamic)
    target_include_directories(${name} PRIVATE "${PROJECT_SOURCE_DIR}/")
    target_include_directories(${name} PRIVATE ${sqlite3_SOURCE_DIR})
    target_compile_definitions(${name} PRIVATE
        _HAVE_SQLITE_CONFIG_H
        SQLITE_API=${wasm_visibility}
    )
    set_property(TARGET ${name} PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
endmacro()

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
    COMMAND wasm-opt sqlite3.tmp.wasm -O4 -o sqlite3.wasm
)

add_custom_target(output)
add_custom_command(TARGET output COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/sqlite3.wasm ${PROJECT_SOURCE_DIR}/../../example/web/sqlite3.wasm)
add_custom_command(TARGET output COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/sqlite3.debug.wasm ${PROJECT_SOURCE_DIR}/../../example/web/sqlite3.debug.wasm)
add_dependencies(output sqlite3_debug sqlite3_opt)
