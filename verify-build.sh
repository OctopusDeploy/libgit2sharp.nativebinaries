#!/bin/bash
# Verifies the output of build.libgit2.sh (or dockerbuild.sh / build.libgit2.ps1)
# for a given RID, asserting the expected native binaries are present and
# correctly relocatable.
#
# Usage: ./verify-build.sh <rid> [variant]
#   <rid>     target runtime identifier (e.g. osx-x64, linux-arm64, win-x86)
#   [variant] optional variant suffix (e.g. openssl1.1)

RID="${1:-}"
VARIANT="${2:-}"

if [[ -z "$RID" ]]; then
    echo "Usage: $0 <rid> [variant]" >&2
    exit 2
fi

PACKAGEPATH="nuget.package/runtimes"
LIBGIT2SHA=$(cat ./nuget.package/libgit2/libgit2_hash.txt)
SHORTSHA=${LIBGIT2SHA:0:7}

LIBGIT2_BASENAME="libgit2-$SHORTSHA"
if [[ -n "$VARIANT" ]]; then
    LIBGIT2_BASENAME="$LIBGIT2_BASENAME-$VARIANT"
fi

NATIVE_DIR="$PACKAGEPATH/$RID/native"

failures=0
fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}
pass() {
    echo "PASS: $*"
}

require_file() {
    if [[ -f "$1" ]]; then
        pass "$1 exists"
    else
        fail "$1 missing"
    fi
}

echo "Verifying $NATIVE_DIR (rid=$RID, variant=${VARIANT:-none})"

case "$RID" in
    osx-*)
        LIBGIT2_FILE="$NATIVE_DIR/$LIBGIT2_BASENAME.dylib"
        require_file "$LIBGIT2_FILE"
        require_file "$NATIVE_DIR/libssh2.1.dylib"

        # No dylib in the bundle should retain an absolute Homebrew path; every
        # such reference should have been rewritten to @rpath/<basename> by the
        # build script's bundle_homebrew_deps loop. Covers both install-id (the
        # first line of otool -L output) and load commands.
        for dylib in "$NATIVE_DIR"/*.dylib; do
            [[ -f "$dylib" ]] || continue
            FORBIDDEN=$(otool -L "$dylib" | tail -n +2 | awk '{print $1}' \
                | grep -E '^(/opt/homebrew/|/usr/local/opt/|/usr/local/Cellar/)' || true)
            if [[ -n "$FORBIDDEN" ]]; then
                fail "$(basename "$dylib") retains absolute Homebrew paths:"$'\n'"$FORBIDDEN"
            else
                pass "$(basename "$dylib"): no absolute Homebrew dependencies"
            fi
        done
        ;;

    linux-*)
        LIBGIT2_FILE="$NATIVE_DIR/$LIBGIT2_BASENAME.so"
        require_file "$LIBGIT2_FILE"

        if [[ ! -f "$LIBGIT2_FILE" ]]; then
            continue
        fi

        # readelf works on any ELF regardless of host arch, so it inspects
        # cross-built arm/arm64/ppc64le/musl artifacts without needing to
        # execute them.
        if ! READELF_OUT=$(readelf -d "$LIBGIT2_FILE" 2>&1); then
            fail "readelf failed on $LIBGIT2_FILE: $READELF_OUT"
        else
            NEEDED=$(echo "$READELF_OUT" | awk '/\(NEEDED\)/ {print $NF}' | tr -d '[]')
            if [[ -z "$NEEDED" ]]; then
                fail "$LIBGIT2_FILE has no NEEDED entries — readelf may have parsed nothing"
            elif [[ -n "$VARIANT" ]]; then
                # Variant builds (e.g. openssl1.1) statically link libssh2 into libgit2.
                if echo "$NEEDED" | grep -q '^libssh2'; then
                    fail "$LIBGIT2_FILE dynamically links libssh2 in $VARIANT build (expected static):"$'\n'"$(echo "$NEEDED" | grep '^libssh2')"
                else
                    pass "$LIBGIT2_FILE: libssh2 not in NEEDED (statically linked)"
                fi
            else
                # Default builds dynamically bundle libssh2 alongside libgit2 via ldd.
                if echo "$NEEDED" | grep -q '^libssh2'; then
                    pass "$LIBGIT2_FILE: libssh2 in NEEDED (dynamic)"
                else
                    fail "$LIBGIT2_FILE: libssh2 missing from NEEDED — default build should link dynamically"
                fi
                LIBSSH2_BUNDLED=$(find "$NATIVE_DIR" -maxdepth 1 -name 'libssh2.so*' -print -quit)
                if [[ -n "$LIBSSH2_BUNDLED" ]]; then
                    pass "$(basename "$LIBSSH2_BUNDLED") bundled alongside libgit2"
                else
                    fail "no libssh2.so* found in $NATIVE_DIR — default build should bundle it"
                fi
            fi
        fi
        ;;

    win-*)
        require_file "$NATIVE_DIR/git2-$SHORTSHA.dll"
        require_file "$NATIVE_DIR/libssh2.dll"
        ;;

    *)
        fail "Unknown RID: $RID"
        ;;
esac

echo
if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "All checks passed"
