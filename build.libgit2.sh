#!/bin/bash

set -e

LIBGIT2SHA=`cat ./nuget.package/libgit2/libgit2_hash.txt`
SHORTSHA=${LIBGIT2SHA:0:7}
OS=`uname`
PACKAGEPATH="nuget.package/runtimes"

# OPENSSL_VARIANT (Linux only) suffixes the filename so builds against different system
# OpenSSL ABIs can ship side by side and be selected at runtime.
LIBGIT2_FILENAME="git2-$SHORTSHA"
if [[ -n "$OPENSSL_VARIANT" ]]; then
    LIBGIT2_FILENAME="$LIBGIT2_FILENAME-$OPENSSL_VARIANT"
fi

USEHTTPS="OpenSSL-Dynamic"
LIBEXT="so"
CMAKE_FLAGS=()

if [[ $OS == "Darwin" ]]; then
    USEHTTPS="ON"
    LIBEXT="dylib"

    case "$RID" in
        osx-arm64) OSXARCH="arm64" ;;
        osx-x64)   OSXARCH="x86_64" ;;
        *)         OSXARCH="$(uname -m)" ;;
    esac

    LIBSSH2_VERSION="${LIBSSH2_VERSION:-1.11.1}"
    LIBSSH2_SHA256="${LIBSSH2_SHA256:-d9ec76cbe34db98eec3539fe2c899d26b0c837cb3eb466a56b0f109cabf658f7}"
    LIBSSH2_PREFIX="$(pwd)/libssh2-install"
    rm -rf "$LIBSSH2_PREFIX" libssh2-src libssh2.tar.gz
    curl -fsSL "https://github.com/libssh2/libssh2/releases/download/libssh2-${LIBSSH2_VERSION}/libssh2-${LIBSSH2_VERSION}.tar.gz" -o libssh2.tar.gz
    echo "${LIBSSH2_SHA256}  libssh2.tar.gz" | shasum -a 256 -c -
    mkdir libssh2-src
    tar xf libssh2.tar.gz -C libssh2-src --strip-components=1
    cmake -S libssh2-src -B libssh2-src/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DCRYPTO_BACKEND=OpenSSL \
        -DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)" \
        -DBUILD_TESTING=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DCMAKE_OSX_ARCHITECTURES="$OSXARCH" \
        -DCMAKE_INSTALL_PREFIX="$LIBSSH2_PREFIX"
    cmake --build libssh2-src/build --target install
    rm -rf libssh2-src libssh2.tar.gz

    CMAKE_FLAGS=(
        "-DCMAKE_OSX_ARCHITECTURES=$OSXARCH"
        "-DCMAKE_PREFIX_PATH=$LIBSSH2_PREFIX"
    )
fi

rm -rf libgit2/build
mkdir libgit2/build
pushd libgit2/build

export _BINPATH=`pwd`

cmake -DCMAKE_BUILD_TYPE:STRING=Release \
      -DBUILD_TESTS:BOOL=OFF \
      -DUSE_SSH=ON \
      -DLIBGIT2_FILENAME=$LIBGIT2_FILENAME \
      -DUSE_HTTPS=$USEHTTPS \
      -DUSE_BUNDLED_ZLIB=ON \
      "${CMAKE_FLAGS[@]}" \
      ..
cmake --build .

popd

if [[ $RID == "" ]]; then
    echo "$(tput setaf 3)RID not defined. Skipping copy to package path.$(tput sgr0)"
    exit 0
fi

rm -rf $PACKAGEPATH/$RID
mkdir -p $PACKAGEPATH/$RID/native

cp libgit2/build/lib$LIBGIT2_FILENAME.$LIBEXT $PACKAGEPATH/$RID/native

LIBGIT2_PATH="$PACKAGEPATH/$RID/native/lib$LIBGIT2_FILENAME.$LIBEXT"

if [[ $OS != "Darwin" ]]; then
    echo "libssh2 statically linked into libgit2; nothing to bundle"
    exit 0
fi

NATIVE_DIR="$PACKAGEPATH/$RID/native"

is_homebrew_path() {
    case "$1" in
        /opt/homebrew/*|/usr/local/Cellar/*|/usr/local/opt/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Copy each Homebrew dep next to libgit2, repoint it at @rpath, and recurse to cover
# transitive deps (libssl -> libcrypto, ...).
bundle_homebrew_deps() {
    local DYLIB="$1"
    local DEPS
    DEPS=$(otool -L "$DYLIB" | tail -n +2 | awk '{print $1}')
    local DEP
    for DEP in $DEPS; do
        if is_homebrew_path "$DEP"; then
            local DEP_BASENAME
            DEP_BASENAME=$(basename "$DEP")
            local DEP_DEST="$NATIVE_DIR/$DEP_BASENAME"
            if [[ ! -f "$DEP_DEST" ]]; then
                echo "Bundling $DEP_BASENAME from $DEP"
                cp "$DEP" "$DEP_DEST"
                chmod u+w "$DEP_DEST"
                install_name_tool -id "@rpath/$DEP_BASENAME" "$DEP_DEST"
                bundle_homebrew_deps "$DEP_DEST"
            fi
            install_name_tool -change "$DEP" "@rpath/$DEP_BASENAME" "$DYLIB"
        fi
    done
}

# libssh2 is source-built (outside Homebrew), so the walker above misses it - handle it explicitly.
SSH2_REF=$(otool -L "$LIBGIT2_PATH" | awk '/libssh2/ {print $1; exit}')
if [[ -z "$SSH2_REF" ]]; then
    echo "ERROR: libgit2 does not appear to link against libssh2"
    exit 1
fi
SSH2_BASENAME=$(basename "$SSH2_REF")
cp "$LIBSSH2_PREFIX/lib/$SSH2_BASENAME" "$NATIVE_DIR/$SSH2_BASENAME"
chmod u+w "$NATIVE_DIR/$SSH2_BASENAME"
install_name_tool -id "@rpath/$SSH2_BASENAME" "$NATIVE_DIR/$SSH2_BASENAME"
install_name_tool -change "$SSH2_REF" "@rpath/$SSH2_BASENAME" "$LIBGIT2_PATH"
bundle_homebrew_deps "$NATIVE_DIR/$SSH2_BASENAME"

bundle_homebrew_deps "$LIBGIT2_PATH"

for DYLIB in "$NATIVE_DIR"/*.dylib; do
    install_name_tool -add_rpath @loader_path "$DYLIB"
done

# Re-sign - install_name_tool invalidated the signatures, which is fatal on Apple Silicon.
for DYLIB in "$NATIVE_DIR"/*.dylib; do
    codesign --force --sign - "$DYLIB"
done
