#!/bin/bash

set -e
echo "building for $RID"

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

build_in_container() {
    local tag="$1" dockerfile="$2" variant="$3" base_image="$4"

    local build_args=()
    if [[ -n "$base_image" ]]; then
        build_args+=(--build-arg "BASE_IMAGE=$base_image")
    fi

    docker buildx build --platform "$platform" --load -t "$tag" -f "$dockerfile" "${build_args[@]}" .
    docker run --platform "$platform" -t -e RID=$RID -e OPENSSL_VARIANT="$variant" --name="$tag" "$tag"
}

extract_runtimes() {
    local tag="$1"
    docker cp "$tag":/nativebinaries/nuget.package/runtimes/$RID/native/. nuget.package/runtimes/$RID/native/
    docker rm "$tag"
}

# Reset the host-side runtime dir so we only ship artifacts produced by this
# invocation. Each extract_runtimes call merges its container's outputs in.
rm -rf nuget.package/runtimes/$RID
mkdir -p nuget.package/runtimes/$RID/native

if [[ $RID == linux-musl* ]]; then
    build_in_container "$RID" "Dockerfile.linux-musl" "" ""
    extract_runtimes "$RID"
elif [[ $RID == linux-ppc64le ]]; then
    # debian:bullseye-slim has no ppc64le manifest, so we skip the openssl1.1
    # variant on this arch and ship only the default OpenSSL 3 build.
    build_in_container "$RID" "Dockerfile.linux" "" ""
    extract_runtimes "$RID"
else
    # All glibc-based Linux RIDs get two variants:
    #   1. Default: built on bookworm against OpenSSL 3, libssh2 bundled as a separate .so
    #   2. openssl1.1: built on bullseye against OpenSSL 1.1, libssh2 statically linked
    build_in_container "$RID" "Dockerfile.linux" "" ""
    extract_runtimes "$RID"

    build_in_container "$RID-openssl1.1" "Dockerfile.linux-static-libssh2" "openssl1.1" "debian:bullseye-slim"
    extract_runtimes "$RID-openssl1.1"
fi
