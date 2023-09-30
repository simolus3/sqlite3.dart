set(CMAKE_SYSTEM_NAME wasm)

set(triple wasm32-unknown-wasi)
set(wasi_sysroot "/usr/share/wasi-sysroot" CACHE PATH "Path to wasi sysroot")
set(clang "clang" CACHE FILEPATH "Path to wasm-capable clang executable")

set(CMAKE_C_COMPILER ${clang})
set(CMAKE_C_COMPILER_TARGET ${triple})
set(CMAKE_SYSROOT ${wasi_sysroot})
set(CMAKE_C_COMPILER_WORKS 1)
