set(triple wasm32-unknown-wasi)
set(wasi_sysroot /usr/share/wasi-sysroot)

set(CMAKE_C_COMPILER clang)
set(CMAKE_C_COMPILER_TARGET ${triple})
set(CMAKE_SYSROOT ${wasi_sysroot})
