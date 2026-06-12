#!/bin/bash

set -e

LIBGIT2SHA=`cat ./nuget.package/libgit2/libgit2_hash.txt`
SHORTSHA=${LIBGIT2SHA:0:7}
OS=`uname`
ARCH=`uname -m`
PACKAGEPATH="nuget.package/runtimes"
OSXARCHITECTURE=$ARCH

EXTRA_CMAKE_FLAGS=""
CMAKE_PREFIX_PATH_FLAG=""

# When OPENSSL_VARIANT is set, append it to the libgit2 filename so multiple
# variants can ship side by side and be selected at runtime
# This is only needed to support multiple versions of OpenSSL on Linux
LIBGIT2_FILENAME="git2-$SHORTSHA"
if [[ -n "$OPENSSL_VARIANT" ]]; then
    LIBGIT2_FILENAME="$LIBGIT2_FILENAME-$OPENSSL_VARIANT"
fi

if [[ $OS == "Darwin" ]]; then
    USEHTTPS="ON"
    if [[ $RID == "osx-arm64" ]]; then
        OSXARCHITECTURE="arm64"
    elif [[ $RID == "osx-x64" ]]; then
        OSXARCHITECTURE="x86_64"
    fi

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
        -DCMAKE_OSX_ARCHITECTURES=$OSXARCHITECTURE \
        -DCMAKE_INSTALL_PREFIX="$LIBSSH2_PREFIX"
    cmake --build libssh2-src/build --target install
    rm -rf libssh2-src libssh2.tar.gz

    # CMAKE_PREFIX_PATH is passed directly to cmake below to avoid word-splitting on spaces in the path.
    CMAKE_PREFIX_PATH_FLAG="-DCMAKE_PREFIX_PATH=$LIBSSH2_PREFIX"
else
    USEHTTPS="OpenSSL-Dynamic"
    EXTRA_CMAKE_FLAGS="-DCMAKE_BUILD_RPATH='\$ORIGIN'"
fi

rm -rf libgit2/build
mkdir libgit2/build
pushd libgit2/build

export _BINPATH=`pwd`

cmake -DCMAKE_BUILD_TYPE:STRING=Release \
      -DBUILD_TESTS:BOOL=OFF \
      -DUSE_SSH=ON \
      -DLIBGIT2_FILENAME=$LIBGIT2_FILENAME \
      -DCMAKE_OSX_ARCHITECTURES=$OSXARCHITECTURE \
      -DUSE_HTTPS=$USEHTTPS \
      -DUSE_BUNDLED_ZLIB=ON \
      ${CMAKE_PREFIX_PATH_FLAG:+"$CMAKE_PREFIX_PATH_FLAG"} \
      $EXTRA_CMAKE_FLAGS \
      ..
cmake --build .

popd

if [[ $RID == "" ]]; then
    echo "$(tput setaf 3)RID not defined. Skipping copy to package path.$(tput sgr0)"
    exit 0
fi

if [[ $OS == "Darwin" ]]; then
    LIBEXT="dylib"
else
    LIBEXT="so"
fi

rm -rf $PACKAGEPATH/$RID
mkdir -p $PACKAGEPATH/$RID/native

cp libgit2/build/lib$LIBGIT2_FILENAME.$LIBEXT $PACKAGEPATH/$RID/native

LIBGIT2_PATH="$PACKAGEPATH/$RID/native/lib$LIBGIT2_FILENAME.$LIBEXT"

if [[ $OS == "Darwin" ]]; then
    # We don't run Octopus Server on Mac, so we can avoid the restriction of relying on the system crypto libraries
    # (Required for FIPS compliance). Instead we just bundle the packages so devs don't need to install them.
    NATIVE_DIR="$PACKAGEPATH/$RID/native"

    is_homebrew_path() {
        case "$1" in
            /opt/homebrew/*|/usr/local/Cellar/*|/usr/local/opt/*) return 0 ;;
            *) return 1 ;;
        esac
    }

    # Walk the load commands of $1 and, for each Homebrew-rooted dep, copy it next to libgit2,
    # rewrite the load command to @rpath, and recurse so transitive deps (libssl -> libcrypto, etc.) are covered.
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

    # libgit2 links our source-built libssh2, which lives outside Homebrew so the
    # walker above won't pick it up.
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

    # Ad-hoc re-sign — install_name_tool invalidates the existing signature, which is fatal on Apple Silicon.
    for DYLIB in "$NATIVE_DIR"/*.dylib; do
        codesign --force --sign - "$DYLIB"
    done
elif [[ -n "$OPENSSL_VARIANT" ]]; then
    echo "$OPENSSL_VARIANT: libssh2 statically linked into libgit2"
else
    # Linux: bundle the dynamic libssh2 alongside libgit2.
    LIBGIT2_PATH="$PACKAGEPATH/$RID/native/lib$LIBGIT2_FILENAME.$LIBEXT"
    LIBSSH2_PATH=$(ldd "$LIBGIT2_PATH" | grep libssh2 | awk '{print $3}')
    if [[ -z "$LIBSSH2_PATH" ]]; then
        echo "ERROR: libgit2 does not appear to link against libssh2"
        exit 1
    fi

    LIBSSH2_BASENAME=$(basename "$LIBSSH2_PATH")

    echo "Bundling $LIBSSH2_BASENAME from $LIBSSH2_PATH"
    cp "$LIBSSH2_PATH" "$PACKAGEPATH/$RID/native/$LIBSSH2_BASENAME"
fi
