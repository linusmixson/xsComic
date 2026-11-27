#!/usr/bin/env bash
set -euo pipefail

# Compile and run the standalone Linux Objective-C 3.0 test & benchmark suite.
# On Linux with objc3c (or /opt/objc3c/activate.sh) installed, runs natively.
# Otherwise (e.g. macOS host), delegates automatically through scripts/docker-env.sh.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)

is_native_objc3_linux() {
    [[ "$(uname -s)" == "Linux" ]] && {
        command -v objc3c >/dev/null 2>&1 || [[ -f /opt/objc3c/activate.sh ]]
    }
}

if ! is_native_objc3_linux; then
    if [[ -n "${XSCOMIC_DOCKER_DELEGATED:-}" ]]; then
        echo "Error: objc3c toolchain not found inside container." >&2
        exit 1
    fi
    exec "$ROOT/scripts/docker-env.sh" \
        env XSCOMIC_DOCKER_DELEGATED=1 \
        bash /work/scripts/run-linux-tests.sh "$@"
fi

if ! command -v objc3c >/dev/null 2>&1 && [[ -f /opt/objc3c/activate.sh ]]; then
    # shellcheck disable=SC1091
    source /opt/objc3c/activate.sh
fi
if ! command -v objc3c >/dev/null 2>&1; then
    echo "Error: objc3c not found in PATH." >&2
    exit 1
fi

cd "$ROOT"

SRC_DIR="$ROOT/Sources/xsComicLinux"
TEST_SRC="$ROOT/Tests/xsComicLinuxTests/main.objc3"
OUT_DIR="$ROOT/build/linux-tests"
OBJ_DIR="$OUT_DIR/obj"
OUT_BIN="$OUT_DIR/xsComicLinuxTests"

SOURCES=(
    "$TEST_SRC"
    "$SRC_DIR/XSCBase.objc3"
    "$SRC_DIR/XSCArchive.objc3"
    "$SRC_DIR/XSCImageStore.objc3"
    "$SRC_DIR/XSCReaderModel.objc3"
)

for src in "${SOURCES[@]}"; do
    if [[ ! -f "$src" ]]; then
        echo "Error: missing required source file: $src" >&2
        exit 1
    fi
done

mkdir -p "$OBJ_DIR"

COMPILE_FLAGS=(
    -std=c17
    -D_GNU_SOURCE
    -O2
    -Wall
    -Wextra
    -Werror
    -Wno-unused-command-line-argument
    -I"$SRC_DIR"
)

LINK_FLAGS=(
    -Wl,--as-needed
    -lz
    -larchive
    -ljpeg
    -lpng
    -lwebp
    -lgif
    -ltiff
    -lavif
    -lheif
    -lpthread
    -lm
)

OBJECTS=()
for src in "${SOURCES[@]}"; do
    base=$(basename "$src" .objc3)
    if [[ "$src" == "$TEST_SRC" ]]; then
        base="test_main"
    fi
    obj="$OBJ_DIR/$base.o"
    objc3c "${COMPILE_FLAGS[@]}" -c "$src" -o "$obj"
    OBJECTS+=("$obj")
done

objc3c "${OBJECTS[@]}" "${LINK_FLAGS[@]}" -o "$OUT_BIN"
chmod 755 "$OUT_BIN"

exec "$OUT_BIN" "$@"
