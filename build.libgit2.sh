#!/bin/bash

set -e

LIBGIT2SHA=`cat ./nuget.package/libgit2/libgit2_hash.txt`
SHORTSHA=${LIBGIT2SHA:0:7}
OS=`uname`
ARCH=`uname -m`
PACKAGEPATH="nuget.package/runtimes"
OSXARCHITECTURE=$ARCH

EXTRA_CMAKE_FLAGS=""

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

if [[ $OS == "Darwin" ]]; then
    # We don't run Octopus Server on Mac, so we can avoid the restriction of relying on the system crypto libraries
    # (Required for FIPS compliance). Instead we just bundle the packages so devs don't need to install them.
    NATIVE_DIR="$PACKAGEPATH/$RID/native"

    is_homebrew_path() {
        case "$1" in
            /opt/homebrew/*|/usr/local/Cellar/*) return 0 ;;
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
