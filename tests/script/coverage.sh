#!/bin/bash

set -ue

sudo apt update
sudo apt-get install binutils-dev libiberty-dev libcurl4-openssl-dev libelf-dev libdw-dev cmake gcc g++

curl -sSL https://github.com/SimonKagstrom/kcov/archive/refs/tags/38.tar.gz | tar xz
mkdir kcov-38/build
pushd kcov-38/build
cmake ..
sudo make install
popd

mkdir coverage
export FIBB_TEST=true
kcov --exclude-path=test,.git,setup,coverage ./coverage/ ./lets-fiware.sh example.com
