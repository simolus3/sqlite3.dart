#!/bin/bash
set -e

function compile() {
    local triple=$1
    RUSTFLAGS="-Zlocation-detail=none -Zfmt-debug=none -Zunstable-options -Cpanic=immediate-abort" cargo +nightly build \
        --release \
        -Z build-std=std,panic_abort \
        -Z build-std-features= \
        --target $triple
}

compile x86_64-unknown-linux-gnu
compile aarch64-unknown-linux-gnu
compile armv7-unknown-linux-gnueabihf
compile riscv64gc-unknown-linux-gnu
