#!/usr/bin/env bash
# Install an already-completed tc-build tree into ./install without rebuilding.

set -eo pipefail

base=$(dirname "$(readlink -f "$0")")
install=$base/install
dest=$base/build/.destdir

function msg() {
    echo -e "\e[1;32m$*\e[0m"
}

# LLVM: the final stage was configured with CMAKE_INSTALL_PREFIX=/usr/local, so
# stage into DESTDIR and move the tree over. This avoids a cmake reconfigure,
# which could trigger relinking of an LTO build. clang/lld locate their resource
# and library dirs relative to argv[0], so the result is fully relocatable.
msg "Installing LLVM..."
rm -rf "$dest"
DESTDIR=$dest ninja -C "$base"/build/llvm/final install-distribution-stripped
mkdir -p "$install"
cp -a "$dest"/usr/local/. "$install"/
rm -rf "$dest"

# binutils: prefix is in the top-level Makefile's BASE_FLAGS_TO_PASS, so it can
# be overridden at install time.
msg "Installing binutils..."
for arch in "$base"/build/binutils/*/; do
    make -C "$arch" -s "-j$(nproc)" prefix="$install" install-strip
done

msg "Removing unused products..."
rm -fr "$install"/include
rm -f "$install"/lib/*.a "$install"/lib/*.la

# 'file' can exit non-zero on odd entries, which trips pipefail below
set +o pipefail

msg "Stripping remaining products..."
find "$install" -type f -exec file {} \; |
    grep 'not stripped' | awk -F: '{print $1}' |
    while read -r f; do strip "$f"; done

if command -v patchelf &>/dev/null; then
    msg "Setting library load paths for portability..."
    find "$install" -mindepth 2 -maxdepth 3 -type f -exec file {} \; |
        grep 'ELF .* interpreter' | awk -F: '{print $1}' |
        while read -r bin; do
            patchelf --set-rpath '$ORIGIN/../lib' "$bin"
        done
fi

msg "Done: $install"
"$install"/bin/clang --version
