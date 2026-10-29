# Build the loader on a full base, then run it in a slim runtime base that
# represents an intended target (matching OpenSSL present, no dev tooling).
ARG BUILD_BASE=debian:bookworm
ARG RUNTIME_BASE=debian:bookworm-slim
FROM ${BUILD_BASE} AS build
# deb.debian.org has purged bullseye's security pool, so bullseye installs need the archive.
RUN . /etc/os-release && if [ "$VERSION_CODENAME" = bullseye ]; then sed -i 's|deb.debian.org|archive.debian.org|g' /etc/apt/sources.list; fi
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
COPY loader.c /loader.c
RUN gcc -O2 -o /loader /loader.c -ldl

FROM ${RUNTIME_BASE}
ARG RUNTIME_PKGS=""
RUN . /etc/os-release && if [ "$VERSION_CODENAME" = bullseye ]; then sed -i 's|deb.debian.org|archive.debian.org|g' /etc/apt/sources.list; fi
RUN if [ -n "$RUNTIME_PKGS" ]; then apt-get update && apt-get install -y --no-install-recommends $RUNTIME_PKGS && rm -rf /var/lib/apt/lists/*; fi
COPY --from=build /loader /usr/local/bin/loader
COPY native/ /native/
ENTRYPOINT ["/usr/local/bin/loader"]
