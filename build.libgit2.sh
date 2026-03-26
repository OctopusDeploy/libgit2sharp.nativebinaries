#!/bin/bash

set -e

LIBGIT2SHA=`cat ./nuget.package/libgit2/libgit2_hash.txt`
SHORTSHA=${LIBGIT2SHA:0:7}
OS=`uname`
ARCH=`uname -m`
PACKAGEPATH="nuget.package/runtimes"
OSXARCHITECTURE=$ARCH

if [[ $OS == "Darwin" ]]; then
    USEHTTPS="ON"
    if [[ $RID == "osx-arm64" ]]; then
        OSXARCHITECTURE="arm64"
    elif [[ $RID == "osx-x64" ]]; then
        OSXARCHITECTURE="x86_64"
    fi
else
    USEHTTPS="OpenSSL-Dynamic"
fi

# Find static libssh2 for linking into the shared libgit2 library
LIBSSH2_STATIC=$(find /usr /opt/homebrew 2>/dev/null -name "libssh2.a" 2>/dev/null | head -1)
if [[ -z "$LIBSSH2_STATIC" ]]; then
    echo "$(tput setaf 1)Error: static libssh2 (libssh2.a) not found. Install libssh2-dev (Debian), libssh2-static (Alpine), or libssh2 (Homebrew).$(tput sgr0)"
    exit 1
fi

rm -rf libgit2/build
mkdir libgit2/build
pushd libgit2/build

export _BINPATH=`pwd`

LIBSSH2_INCLUDE_DIR=$(dirname "$LIBSSH2_STATIC")/../include

cmake -DCMAKE_BUILD_TYPE:STRING=Release \
      -DBUILD_TESTS:BOOL=OFF \
      -DUSE_SSH=ON \
      -DLIBSSH2_FOUND:BOOL=TRUE \
      -DLIBSSH2_LIBRARIES=$LIBSSH2_STATIC \
      -DLIBSSH2_INCLUDE_DIRS=$LIBSSH2_INCLUDE_DIR \
      -DLIBSSH2_LDFLAGS="-lssh2" \
      -DLIBGIT2_FILENAME=git2-$SHORTSHA \
      -DCMAKE_OSX_ARCHITECTURES=$OSXARCHITECTURE \
      -DUSE_HTTPS=$USEHTTPS \
      -DUSE_BUNDLED_ZLIB=ON \
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

cp libgit2/build/libgit2-$SHORTSHA.$LIBEXT $PACKAGEPATH/$RID/native
