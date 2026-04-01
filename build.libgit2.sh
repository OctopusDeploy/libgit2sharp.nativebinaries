#!/bin/bash

set -e

LIBGIT2SHA=`cat ./nuget.package/libgit2/libgit2_hash.txt`
SHORTSHA=${LIBGIT2SHA:0:7}
OS=`uname`
ARCH=`uname -m`
PACKAGEPATH="nuget.package/runtimes"
OSXARCHITECTURE=$ARCH

EXTRA_CMAKE_FLAGS=""

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

rm -rf libgit2/build
mkdir libgit2/build
pushd libgit2/build

export _BINPATH=`pwd`

cmake -DCMAKE_BUILD_TYPE:STRING=Release \
      -DBUILD_TESTS:BOOL=OFF \
      -DUSE_SSH=ON \
      -DLIBGIT2_FILENAME=git2-$SHORTSHA \
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

cp libgit2/build/libgit2-$SHORTSHA.$LIBEXT $PACKAGEPATH/$RID/native

# Bundle libssh2 shared library alongside libgit2
LIBGIT2_PATH="$PACKAGEPATH/$RID/native/libgit2-$SHORTSHA.$LIBEXT"

if [[ $OS == "Darwin" ]]; then
    echo "macOS: libssh2 sourced from global installation"
else
    # Linux: find libssh2 via ldd
    LIBSSH2_PATH=$(ldd "$LIBGIT2_PATH" | grep libssh2 | awk '{print $3}')
    if [[ -z "$LIBSSH2_PATH" ]]; then
        echo "ERROR: libgit2 does not appear to link against libssh2"
        exit 1
    fi

    LIBSSH2_BASENAME=$(basename "$LIBSSH2_PATH")

    echo "Bundling $LIBSSH2_BASENAME from $LIBSSH2_PATH"
    cp "$LIBSSH2_PATH" "$PACKAGEPATH/$RID/native/$LIBSSH2_BASENAME"

    # Set RPATH so libgit2 finds libssh2 in the same directory at runtime
    patchelf --set-rpath '$ORIGIN' "$LIBGIT2_PATH"
fi

echo "Contents of $PACKAGEPATH/$RID/native/:"
ls -la "$PACKAGEPATH/$RID/native/"
