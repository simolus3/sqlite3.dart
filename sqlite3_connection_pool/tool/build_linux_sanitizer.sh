#!/bin/bash
set -e

function compile() {
    local sanitizer=$1

    RUSTDOCFLAGS="-Zsanitizer=$sanitizer" RUSTFLAGS="-Zsanitizer=$sanitizer -Zlocation-detail=none -Zfmt-debug=none -Zunstable-options -Cpanic=immediate-abort" cargo +nightly build \
        --release \
        -Z build-std=std,panic_abort \
        -Z build-std-features= \
        --target x86_64-unknown-linux-gnu

    cp target/x86_64-unknown-linux-gnu/release/libsqlite3_connection_pool.so target/release/libsqlite3_connection_pool.$sanitizer.san.so
}

compile address
compile memory
compile thread
