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

LIBGIT2="libgit2/build/libgit2-$SHORTSHA.$LIBEXT"
cp $LIBGIT2 $PACKAGEPATH/$RID/native

# Find and bundle the shared libssh2 alongside libgit2
if [[ $OS == "Darwin" ]]; then
    LIBSSH2_PATH=$(otool -L $LIBGIT2 | grep libssh2 | awk '{print $1}')
    if [[ -n "$LIBSSH2_PATH" ]]; then
        cp $LIBSSH2_PATH $PACKAGEPATH/$RID/native/
        LIBSSH2_NAME=$(basename $LIBSSH2_PATH)
        # Rewrite libgit2 to find libssh2 in the same directory
        install_name_tool -change $LIBSSH2_PATH @loader_path/$LIBSSH2_NAME $PACKAGEPATH/$RID/native/libgit2-$SHORTSHA.$LIBEXT
        # Set libssh2's own id to be relative too
        install_name_tool -id @loader_path/$LIBSSH2_NAME $PACKAGEPATH/$RID/native/$LIBSSH2_NAME
        echo "Bundled $LIBSSH2_NAME alongside libgit2"
    fi
else
    LIBSSH2_PATH=$(ldd $LIBGIT2 | grep libssh2 | awk '{print $3}')
    if [[ -n "$LIBSSH2_PATH" ]]; then
        cp $LIBSSH2_PATH $PACKAGEPATH/$RID/native/
        LIBSSH2_NAME=$(basename $LIBSSH2_PATH)
        # Set RPATH so libgit2 looks in its own directory
        patchelf --set-rpath '$ORIGIN' $PACKAGEPATH/$RID/native/libgit2-$SHORTSHA.$LIBEXT
        echo "Bundled $LIBSSH2_NAME alongside libgit2"
    fi
fi
