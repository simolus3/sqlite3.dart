cmake_minimum_required(VERSION 3.24)

set(PROJECT_NAME "sqlite3_web")
project(${PROJECT_NAME} LANGUAGES C)

set(triple wasm32-unknown-wasi)
set(wasi_sysroot "/usr/share/wasi-sysroot" CACHE PATH "Path to wasi sysroot")
set(clang "clang" CACHE FILEPATH "Path to wasm-capable clang executable")

include(FetchContent)

FetchContent_Declare(
    sqlite3
    URL https://sqlite.org/2024/sqlite-autoconf-3460000.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP NEW
)

FetchContent_MakeAvailable(sqlite3)

file(DOWNLOAD https://raw.githubusercontent.com/sqlite/sqlite/master/src/test_vfstrace.c "${CMAKE_BINARY_DIR}/vfstrace.c")

get_filename_component(RS_LIB_DIR "${CMAKE_BINARY_DIR}/../../powersync-sqlite-core/" ABSOLUTE)
set(RS_LIB "powersync")
set(RS_WASM_TGT "wasm32-wasi")
set(RS_WASM_TGT_DIR "${RS_LIB_DIR}/target/${RS_WASM_TGT}")

set(RS_RELEASE_OUT "${RS_WASM_TGT_DIR}/wasm/")
set(RS_RELEASE_OUT_DEPS "${RS_WASM_TGT_DIR}/wasm/deps")
set(RS_RELEASE_EXTENSION_OUT "${RS_RELEASE_OUT}/powersync-extension.o")

# Generate symbols we need to export from the sqlite3.wasm build
add_custom_command(
    OUTPUT required_symbols.txt
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../../
    COMMAND dart run tool/wasm_symbols.dart ${CMAKE_CURRENT_BINARY_DIR}/required_symbols.txt
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/../../tool/wasm_symbols.dart
    VERBATIM
)
add_custom_target(required_symbols DEPENDS required_symbols.txt)

macro(base_sqlite3_target name debug)
  set(clang_output ${name}.clang.wasm)
  set(init_output ${name}.init.wasm)
  set(output ${init_output})

  set(sources
    ${CMAKE_CURRENT_SOURCE_DIR}/os_web.c
    ${CMAKE_CURRENT_SOURCE_DIR}/helpers.c
    ${sqlite3_SOURCE_DIR}/sqlite3.c
    ${RS_RELEASE_EXTENSION_OUT}
  )
  set(flags -Wall -Wextra -Wno-unused-parameter -Wno-unused-function)

  if(${debug})
    list(APPEND sources "${CMAKE_BINARY_DIR}/vfstrace.c")
    list(APPEND flags "-g" "-DDEBUG")
  else()
    list(APPEND flags "-Oz" "-DNDEBUG" "-flto")
  endif()

  add_custom_command(
    OUTPUT ${clang_output}
    COMMAND ${clang} --target=${triple} -std=c23
      ${flags}
      -o ${clang_output}
      -I ${PROJECT_SOURCE_DIR} -I ${sqlite3_SOURCE_DIR}
      -D_HAVE_SQLITE_CONFIG_H
      -mcpu=generic
      -mexec-model=reactor
      -fno-stack-protector -fno-stack-clash-protection
      -Wl,--import-memory
      --sysroot ${wasi_sysroot}
      ${sources}
      @${CMAKE_CURRENT_BINARY_DIR}/required_symbols.txt
    DEPENDS ${sources} required_symbols
    VERBATIM
  )

  add_custom_command(
    OUTPUT ${init_output}
    COMMAND wasm-ctor-eval -c _initialize ${clang_output} -o ${init_output}
    VERBATIM
    DEPENDS ${clang_output}
  )

  if(NOT ${debug})
    set(output ${name}.wasm)

    add_custom_command(
        OUTPUT ${output}
        COMMAND wasm-opt --strip --strip-producers -c -O4 ${init_output} -o ${output}
        VERBATIM
        DEPENDS ${init_output}
    )
  endif()

  add_custom_target(${name} DEPENDS ${output})
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

base_sqlite3_target(sqlite3_debug true)
base_sqlite3_target(sqlite3_opt false)

add_dependencies(sqlite3_opt powersync_core_bytecode)
add_dependencies(sqlite3_debug powersync_core_bytecode)

add_custom_target(output)
add_custom_command(TARGET output COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/sqlite3_opt.wasm ${PROJECT_SOURCE_DIR}/../../example/web/sqlite3.wasm)
add_custom_command(TARGET output COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/sqlite3_debug.init.wasm ${PROJECT_SOURCE_DIR}/../../example/web/sqlite3.debug.wasm)
add_dependencies(output sqlite3_debug sqlite3_opt powersync_core_bytecode)
