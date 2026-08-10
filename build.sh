#!/usr/bin/env bash

set -eo pipefail

base=$(dirname "$(readlink -f "$0")")
install=$base/install

# Function to show an informational message
function msg() {
    echo -e "\e[1;32m$*\e[0m"
}

# Build LLVM
msg "Building LLVM..."
"$base"/build-llvm.py \
    --vendor-string "StormBreaker" \
    --targets AArch64 ARM X86 \
    --pgo kernel-defconfig \
    --lto full \
    --shallow-clone \
    --install-folder "$install" \
    --distribution-profile kernel \
    --build-targets distribution \
    --install-targets distribution-stripped \
    --quiet-cmake

# Build binutils
msg "Building binutils..."
"$base"/build-binutils.py \
    --targets arm aarch64 x86_64 \
    --install-folder "$install"

# Remove unused products (binutils installs headers and static libs)
msg "Removing unused products..."
rm -fr "$install"/include
rm -f "$install"/lib/*.a "$install"/lib/*.la

# 'file' can exit non-zero on odd entries, which would trip pipefail below
set +o pipefail

# Strip remaining products (LLVM is already stripped by install-distribution-stripped)
msg "Stripping remaining products..."
find "$install" -type f -exec file {} \; |
    grep 'not stripped' | awk -F: '{print $1}' |
    while read -r f; do strip "$f"; done

# Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
msg "Setting library load paths for portability..."
find "$install" -mindepth 2 -maxdepth 3 -type f -exec file {} \; |
    grep 'ELF .* interpreter' | awk -F: '{print $1}' |
    while read -r bin; do
        echo "$bin"
        # shellcheck disable=SC2016 # $ORIGIN must reach patchelf literally
        patchelf --set-rpath '$ORIGIN/../lib' "$bin"
    done

msg "Toolchain is available at: $install"
"$install"/bin/clang --version
