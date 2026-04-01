#!/bin/bash

set -e

LIBGIT2SHA=`cat ./nuget.package/libgit2/libgit2_hash.txt`
SHORTSHA=${LIBGIT2SHA:0:7}
OS=`uname`
ARCH=`uname -m`
PACKAGEPATH="nuget.package/runtimes"
OSXARCHITECTURE=$ARCH
LIBSSH2_VERSION="1.11.1"
LIBSSH2_SHA256="d9ec76cbe34db98eec3539fe2c899d26b0c837cb3eb466a56b0f109cabf658f7"

EXTRA_CMAKE_FLAGS=""

if [[ $OS == "Darwin" ]]; then
    USEHTTPS="ON"
    if [[ $RID == "osx-arm64" ]]; then
        OSXARCHITECTURE="arm64"
    elif [[ $RID == "osx-x64" ]]; then
        OSXARCHITECTURE="x86_64"
    fi

    # Build libssh2 from source with SecureTransport backend
    echo "Building libssh2 ${LIBSSH2_VERSION} from source with SecureTransport..."
    LIBSSH2_SRC="libssh2-${LIBSSH2_VERSION}"
    if [[ ! -d "$LIBSSH2_SRC" ]]; then
        curl -L -o libssh2.tar.gz \
            "https://github.com/libssh2/libssh2/releases/download/libssh2-${LIBSSH2_VERSION}/libssh2-${LIBSSH2_VERSION}.tar.gz"
        echo "${LIBSSH2_SHA256} libssh2.tar.gz" | shasum -a 256 --check
        tar xzf libssh2.tar.gz
    fi
    LIBSSH2_INSTALL="$PWD/libssh2-install"
    rm -rf "$LIBSSH2_SRC/build-dir" "$LIBSSH2_INSTALL"
    mkdir -p "$LIBSSH2_SRC/build-dir"
    pushd "$LIBSSH2_SRC/build-dir"
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DCRYPTO_BACKEND=SecureTransport \
          -DBUILD_SHARED_LIBS=ON \
          -DBUILD_EXAMPLES=OFF \
          -DBUILD_TESTING=OFF \
          -DCMAKE_OSX_ARCHITECTURES=$OSXARCHITECTURE \
          -DCMAKE_INSTALL_PREFIX="$LIBSSH2_INSTALL" \
          ..
    cmake --build . --target install
    popd

    EXTRA_CMAKE_FLAGS="-DCMAKE_PREFIX_PATH=$LIBSSH2_INSTALL"
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
    # Find the libssh2 dylib linked by libgit2
    LIBSSH2_REF=$(otool -L "$LIBGIT2_PATH" | grep libssh2 | awk '{print $1}')
    if [[ -z "$LIBSSH2_REF" ]]; then
        echo "ERROR: libgit2 does not appear to link against libssh2"
        exit 1
    fi

    # The reference may be to the install prefix; resolve the actual file
    LIBSSH2_REALPATH=$(python3 -c "import os; print(os.path.realpath('$LIBSSH2_REF'))")
    LIBSSH2_BASENAME=$(basename "$LIBSSH2_REALPATH")

    echo "Bundling $LIBSSH2_BASENAME from $LIBSSH2_REALPATH"
    cp "$LIBSSH2_REALPATH" "$PACKAGEPATH/$RID/native/$LIBSSH2_BASENAME"

    # Rewrite libgit2's reference to use @loader_path
    install_name_tool -change "$LIBSSH2_REF" "@loader_path/$LIBSSH2_BASENAME" "$LIBGIT2_PATH"

    # Set libssh2's own install name
    install_name_tool -id "@loader_path/$LIBSSH2_BASENAME" "$PACKAGEPATH/$RID/native/$LIBSSH2_BASENAME"
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
