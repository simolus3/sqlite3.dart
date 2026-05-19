#!/bin/bash
set -eu


pushd openssl

BUILD_DIR=$(realpath ../openssl-build)
./Configure no-ssl no-tls no-dtls no-engine no-deprecated no-shared no-tests no-docs no-apps --prefix=$BUILD_DIR --openssldir=$BUILD_DIR \
          '-Wl,-rpath,$(LIBRPATH)' 

make -j 8
make install
popd