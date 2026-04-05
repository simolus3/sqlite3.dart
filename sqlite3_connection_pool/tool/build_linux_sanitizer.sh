#!/bin/bash
set -e

function compile() {
    local sanitizer=$1

    RUSTDOCFLAGS="-Zsanitizer=$sanitizer" RUSTFLAGS="-Zsanitizer=$sanitizer -Zlocation-detail=none -Zfmt-debug=none -Zunstable-options -Cpanic=immediate-abort" cargo +nightly build \
        --release \
        -Z build-std=std,panic_abort \
        -Z build-std-features=

    cp target/release/libsqlite3_connection_pool.so target/release/libsqlite3_connection_pool.$sanitizer.san.so
}

compile address
compile memory
compile thread
