#!/bin/sh
set -e

function compile() {
    local triple=$1
    RUSTFLAGS="-Zlocation-detail=none -Zfmt-debug=none -Zunstable-options -Cpanic=immediate-abort" cargo +nightly build \
        --release \
        --target aarch64-apple-darwin \
        -Z build-std=std,panic_abort \
        -Z build-std-features= \
        --target $triple
}

compile aarch64-apple-darwin
compile x86_64-apple-darwin

compile aarch64-apple-ios
compile aarch64-apple-ios-sim
compile x86_64-apple-ios
