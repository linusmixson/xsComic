#!/usr/bin/env bash
set -euo pipefail

# Compile and link xsComic for Linux with Slopjective-C (objc3c).
# On Linux with objc3c (or /opt/objc3c/activate.sh) installed, builds natively.
# Otherwise (e.g. macOS host), delegates automatically through scripts/docker-env.sh.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)

usage() {
    cat <<EOF
Usage: $(basename "$0") [--release|--debug]

Options:
  --release   Build size-optimized (-Oz), stripped binary (default).
  --debug     Build unoptimized (-O0 -g) binary with symbols.
  -h, --help  Show this help message.

Environment:
  CBR_SCRATCH_PATH   Object/build scratch dir (default: build/objc3)
  CBR_OUTPUT_DIR     Output directory for xscomic binary (default: build/linux)
  XSCOMIC_NO_LTO=1   Disable ThinLTO in release mode (fallback to plain -Oz)
EOF
}

CONFIGURATION="release"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            CONFIGURATION="release"
            shift
            ;;
        --debug)
            CONFIGURATION="debug"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "usage: $0 [--debug|--release]" >&2
            exit 2
            ;;
    esac
done

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
    DOCKER_ENV_ARGS=(XSCOMIC_DOCKER_DELEGATED=1)
    if [[ -n "${XSCOMIC_NO_LTO:-}" ]]; then
        DOCKER_ENV_ARGS+=("XSCOMIC_NO_LTO=$XSCOMIC_NO_LTO")
    fi
    for name in CBR_SCRATCH_PATH CBR_OUTPUT_DIR; do
        value="${!name:-}"
        if [[ -z "$value" ]]; then continue; fi
        if [[ "$value" == "$ROOT/"* ]]; then
            value="${value#"$ROOT/"}"
        elif [[ "$value" == /* ]]; then
            echo "Error: $name must be inside the checkout for Docker builds." >&2
            exit 2
        fi
        DOCKER_ENV_ARGS+=("$name=$value")
    done
    exec "$ROOT/scripts/docker-env.sh" \
        env "${DOCKER_ENV_ARGS[@]}" \
        bash /work/scripts/build-linux.sh "--$CONFIGURATION"
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
export TZ=UTC

canonicalize_path() {
    local p="$1"
    if [[ "$p" != /* ]]; then
        p="$ROOT/$p"
    fi
    if command -v realpath >/dev/null 2>&1 && realpath -m "$p" >/dev/null 2>&1; then
        realpath -m "$p"
        return
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$p"
        return
    fi
    local suffix=""
    local cur="$p"
    while [[ ! -d "$cur" && "$cur" != "/" ]]; do
        suffix="/$(basename "$cur")$suffix"
        cur=$(dirname "$cur")
    done
    local resolved
    resolved=$(cd "$cur" && pwd -P)
    if [[ "$resolved" == "/" ]]; then
        printf '%s\n' "${suffix:-/}"
    else
        printf '%s%s\n' "$resolved" "$suffix"
    fi
}

validate_mutable_path() {
    local candidate="$1"
    local label="$2"
    local allowed_build_root="$ROOT/build"

    if [[ "$candidate" == "/" \
        || "$ROOT" == "$candidate" \
        || "$ROOT" == "$candidate/"* ]]; then
        echo "$label may not contain the source repository: $candidate" >&2
        exit 2
    fi
    if [[ "$candidate" == "$ROOT/"* \
        && "$candidate" != "$allowed_build_root" \
        && "$candidate" != "$allowed_build_root/"* ]]; then
        echo "$label may only write under build/ inside the source repository: $candidate" >&2
        exit 2
    fi
}

require_disjoint_paths() {
    local first="$1"
    local second="$2"
    if [[ "$first" == "$second" \
        || "$first" == "$second/"* \
        || "$second" == "$first/"* ]]; then
        echo "$3 and $4 must not overlap." >&2
        exit 2
    fi
}

lock_path_for() {
    local resource="$1"
    local key=""
    if command -v sha256sum >/dev/null 2>&1; then
        key=$(printf '%s' "$resource" | sha256sum | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        key=$(printf '%s' "$resource" | shasum -a 256 | awk '{print $1}')
    else
        key=$(printf '%s' "$resource" | cksum | awk '{print $1}')
    fi
    printf '%s/xscomic-build-lock.%s\n' "$BUILD_LOCK_DIR" "$key"
}

SCRATCH_PATH=$(canonicalize_path "${CBR_SCRATCH_PATH:-$ROOT/build/objc3}")
OUTPUT_DIR=$(canonicalize_path "${CBR_OUTPUT_DIR:-$ROOT/build/linux}")

validate_mutable_path "$SCRATCH_PATH" "Build scratch path"
validate_mutable_path "$OUTPUT_DIR" "Output directory"
require_disjoint_paths "$OUTPUT_DIR" "$SCRATCH_PATH" "Output directory" "Build scratch path"

BUILD_LOCK_DIR="${XSCOMIC_BUILD_LOCK_DIR:-/tmp}"
mkdir -p "$BUILD_LOCK_DIR"
OUTPUT_LOCK_DIR=$(lock_path_for "$OUTPUT_DIR")
SCRATCH_LOCK_DIR=$(lock_path_for "$SCRATCH_PATH")
OWNS_OUTPUT_LOCK=false
OWNS_SCRATCH_LOCK=false
STAGE_BIN=""

cleanup_build() {
    if [[ -n "$STAGE_BIN" && -e "$STAGE_BIN" ]]; then
        rm -f "$STAGE_BIN"
    fi
    if $OWNS_SCRATCH_LOCK; then
        rmdir "$SCRATCH_LOCK_DIR" 2>/dev/null || true
    fi
    if $OWNS_OUTPUT_LOCK; then
        rmdir "$OUTPUT_LOCK_DIR" 2>/dev/null || true
    fi
}
trap cleanup_build EXIT

if ! mkdir "$OUTPUT_LOCK_DIR" 2>/dev/null; then
    echo "Another build is using output directory: $OUTPUT_DIR" >&2
    exit 1
fi
OWNS_OUTPUT_LOCK=true

if ! mkdir "$SCRATCH_LOCK_DIR" 2>/dev/null; then
    echo "Another build is using build scratch path: $SCRATCH_PATH" >&2
    exit 1
fi
OWNS_SCRATCH_LOCK=true

SRC_DIR="$ROOT/Sources/xsComicLinux"
shopt -s nullglob
SOURCES=("$SRC_DIR"/*.objc3)
shopt -u nullglob
if [[ ${#SOURCES[@]} -eq 0 ]]; then
    echo "No Objective-C 3.0 (.objc3) sources found in $SRC_DIR" >&2
    exit 1
fi

OBJ_DIR="$SCRATCH_PATH/$CONFIGURATION"
mkdir -p "$OBJ_DIR" "$OUTPUT_DIR"

COMPILE_FLAGS=(
    -std=c17
    -D_GNU_SOURCE
    -Wall
    -Wextra
    -Werror
    -Wno-unused-command-line-argument
    -I"$SRC_DIR"
    -I/usr/include/SDL2
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
    -lSDL2
    -lSDL2_ttf
    -lGL
    -lpthread
    -lm
)

if [[ "$CONFIGURATION" == "release" ]]; then
    COMPILE_FLAGS+=(-Oz -ffunction-sections -fdata-sections)
    LINK_FLAGS+=(-Wl,--gc-sections)
    if [[ "${XSCOMIC_NO_LTO:-0}" != "1" ]]; then
        COMPILE_FLAGS+=(-flto=thin)
        LINK_FLAGS+=(-flto=thin)
    fi
else
    COMPILE_FLAGS+=(-O0 -g)
fi

OBJECTS=()
for src in "${SOURCES[@]}"; do
    base=$(basename "$src" .objc3)
    obj="$OBJ_DIR/$base.o"
    objc3c "${COMPILE_FLAGS[@]}" -c "$src" -o "$obj"
    OBJECTS+=("$obj")
done

STAGE_BIN="$OUTPUT_DIR/.xscomic.stage.$$"
OUT_BIN="$OUTPUT_DIR/xscomic"

objc3c "${OBJECTS[@]}" "${LINK_FLAGS[@]}" -o "$STAGE_BIN"
chmod 755 "$STAGE_BIN"

if [[ "$CONFIGURATION" == "release" ]]; then
    SYMBOLS_BIN="$OUTPUT_DIR/xscomic.symbols"
    cp -f "$STAGE_BIN" "$SYMBOLS_BIN"
    if command -v strip >/dev/null 2>&1; then
        strip --strip-all "$STAGE_BIN"
    elif command -v llvm-strip >/dev/null 2>&1; then
        llvm-strip --strip-all "$STAGE_BIN"
    fi
fi

mv -f "$STAGE_BIN" "$OUT_BIN"
STAGE_BIN=""

BIN_BYTES=$(wc -c < "$OUT_BIN" | tr -d '[:space:]')
BIN_KIB=$(awk -v b="$BIN_BYTES" 'BEGIN { printf "%.1f", b / 1024.0 }')
if [[ "$CONFIGURATION" == "release" ]]; then
    echo "Built: $OUT_BIN (release, stripped: ${BIN_BYTES} bytes / ${BIN_KIB} KiB)"
else
    echo "Built: $OUT_BIN (debug, ${BIN_BYTES} bytes / ${BIN_KIB} KiB)"
fi
