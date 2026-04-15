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

if [[ $RID == linux-musl* ]]; then
    dockerfile="Dockerfile.linux-musl"
else
    dockerfile="Dockerfile.linux"
fi

docker buildx build --platform "$platform" --load -t $RID -f $dockerfile .

docker run --platform "$platform" -t -e RID=$RID --name=$RID $RID

docker cp $RID:/nativebinaries/nuget.package/runtimes nuget.package

docker rm $RID
