#!/bin/bash

set -e
echo "building for $RID variant=${VARIANT:-default}"

# Map RID to Docker platform for native builds (no cross-compilation).
if [[ $RID =~ arm64 ]]; then
    platform="linux/arm64"
elif [[ $RID =~ arm ]]; then
    platform="linux/arm/v7"
elif [[ $RID =~ ppc64le ]]; then
    platform="linux/ppc64le"
else
    platform="linux/amd64"
fi

# Choose the Dockerfile (and OpenSSL 1.1 base image) based on RID and variant.
build_args=()
if [[ $RID == linux-musl* ]]; then
    dockerfile="Dockerfile.linux-musl"
elif [[ "$VARIANT" == "openssl1.1" ]]; then
    # Built on bullseye against OpenSSL 1.1, libssh2 statically linked.
    dockerfile="Dockerfile.linux-static-libssh2"
    build_args+=(--build-arg "BASE_IMAGE=debian:bullseye-slim")
else
    # Default: built on bookworm against OpenSSL 3, libssh2 bundled as a separate .so.
    dockerfile="Dockerfile.linux"
fi

docker buildx build --platform "$platform" --load -t "$RID" -f "$dockerfile" "${build_args[@]}" .
docker run --platform "$platform" -t -e RID=$RID -e OPENSSL_VARIANT="$VARIANT" --name="$RID" "$RID"
docker cp "$RID":/nativebinaries/nuget.package/runtimes nuget.package
docker rm "$RID"
