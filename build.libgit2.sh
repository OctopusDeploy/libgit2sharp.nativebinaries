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
    echo "macOS: libssh2 sourced from global installation"
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
