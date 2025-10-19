### Compiling

Note: Compiling sqlite3 to WebAssembly is not necessary for users of this package,
just grab the `.wasm` from the latest release on GitHub.

This section describes how to compile the WebAssembly modules from source. This
uses a LLVM-based toolchain with components of the WASI SDK for C runtime components.

#### Setup

##### Linux

On Linux, you need a LLVM based toolchain capable of compiling to WebAssembly.
On Arch Linux, the `wasi-compiler-rt` and `wasi-libc` packages are enough for this.
On other distros, you may have to download the sysroot and compiler builtins from their
respective package managers or directly from the WASI SDK releases.

With wasi in `/usr/share/wasi-sysroot` and the default clang compiler having the
required builtins, you can setup the build with:

```
cmake -S src -B .dart_tool/sqlite3_build
```

##### macOS

On macOS, install a WebAssembly-capable C compiler. If you're using Homebrew,
you can use

```
brew install cmake llvm binaryen wasi-libc wasi-runtimes
```

Then, set up the build with

```
cmake -Dwasi_sysroot=/opt/homebrew/share/wasi-sysroot -Dclang=/opt/homebrew/opt/llvm/bin/clang -S src -B .dart_tool/sqlite3_build
```

#### Building

In this directory, run:

```
cmake --build .dart_tool/sqlite3_build/ -t output -j
```

The `output` target copies `sqlite3.wasm` and `sqlite3.debug.wasm` to `out/`.

(Of course, you can also run the build in any other directory than `.dart_tool/sqite3_build` if you want to).

### Customizing the WASM module

The build scripts in this repository, which are also used for the default distribution of `sqlite3.wasm`
attached to releases, are designed to mirror the options used by `sqlite3_flutter_libs`.
If you want to use different options, or include custom extensions in the WASM module, you can customize
the build setup.

To use regular sqlite3 sources with different compile-time options, alter `assets/wasm/sqlite_cfg.h` and
re-run the build as described in [compiling](#compiling).
Including additional extensions written in C is possible by adapting the `CMakeLists.txt` in
`assets/wasm`.

A simple example demonstrating how to include Rust-based extensions is included in `example/custom_wasm_build`.
The readme in that directory explains the build process in detail, but you still need the WASI/Clang toolchains
described in the [setup section](#linux).
