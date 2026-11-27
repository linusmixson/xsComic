#!/usr/bin/env bash
set -euo pipefail

# Build and launch xsComic for Linux (Objective-C 3.0 + SDL2 + OpenGL 3.3 Core).
# Supports both interactive desktop launches (X11/Wayland) and headless
# --screenshot runs (automatically wrapped with xvfb-run when no display exists).
# On hosts without native objc3c (e.g. macOS), delegates via scripts/docker-env.sh.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)

usage() {
    cat <<EOF
Usage: $(basename "$0") [--release|--debug] [--] [xscomic args...]

Build options:
  --release          Build optimized, stripped release binary (default).
  --debug            Build debug binary with symbols.
  -h, --help         Show this help message.

xsComic runtime args (forwarded to xscomic):
  --single|--double  Start in single-page or two-page spread mode
  --ltr|--rtl        Start in LTR or RTL reading direction
  --sidebar          Open page sidebar on launch
  --page N           Jump to 1-based page N
  --zoom SCALE       Start at custom zoom scale
  --jump-modal       Open the Jump-to-Page modal
  --settings         Open the Settings popover
  --screenshot PATH  Render a frame, save PNG to PATH, and exit
  [book_path]        Optional archive (.cbz/.cbr/.cb7/.cbt) or image directory

Environment:
  CBR_SCRATCH_PATH          Object/build scratch dir (default: build/objc3)
  CBR_OUTPUT_DIR            Output directory for xscomic binary (default: build/linux)
  XSCOMIC_USE_XVFB=1        Force launching under xvfb-run with software GL
  XSCOMIC_DOCKER_IMAGE      Override Docker image tag (default: xscomic-objc3:dev)
  XSCOMIC_LIBRARY_DIR       Expose this host comic library read-only in Docker
EOF
}

BUILD_CONFIG="release"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --release|--debug)
            BUILD_CONFIG="${1#--}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *) break ;;
    esac
done
APP_ARGS=("$@")
HAS_SCREENSHOT=false
for arg in "$@"; do
    case "$arg" in
        --) break ;;
        --screenshot|--screenshot=*) HAS_SCREENSHOT=true ;;
    esac
done

is_native_objc3_linux() {
    [[ "$(uname -s)" == "Linux" ]] && {
        command -v objc3c >/dev/null 2>&1 || [[ -f /opt/objc3c/activate.sh ]]
    }
}

host_path() {
    local path="$1" parent
    if [[ -d "$path" ]]; then
        (cd -- "$path" && pwd -P)
    else
        parent=$(cd -- "$(dirname -- "$path")" && pwd -P) || return 1
        printf '%s/%s\n' "${parent%/}" "${path##*/}"
    fi
}

add_docker_bind() {
    local source="${1//\"/\"\"}" target="${2//\"/\"\"}"
    DOCKER_FLAGS+=(--run-arg --mount --run-arg "type=bind,\"source=$source\",\"target=$target\"${3:+,$3}")
}

map_docker_path() {
    local path="$1" kind="$2" resolved
    DOCKER_PATH="$path"
    if ! resolved=$(host_path "$path" 2>/dev/null); then
        return 1
    fi
    if [[ "$resolved" == "$ROOT" ]]; then
        DOCKER_PATH=/work
    elif [[ "$resolved" == "$ROOT/"* ]]; then
        DOCKER_PATH="/work/${resolved#"$ROOT/"}"
    elif [[ -n "$library" && "$kind" == book && "$resolved" == "$library" ]]; then
        DOCKER_PATH=/comics
    elif [[ -n "$library" && "$kind" == book && "$resolved" == "${library%/}/"* ]]; then
        DOCKER_PATH="/comics/${resolved#"${library%/}/"}"
    elif [[ "$kind" == screenshot ]]; then
        add_docker_bind "$(dirname -- "$resolved")" /screenshot-output
        DOCKER_PATH="/screenshot-output/${resolved##*/}"
    elif [[ -e "$resolved" ]]; then
        DOCKER_PATH="/book-argument/${resolved##*/}"
        add_docker_bind "$resolved" "$DOCKER_PATH" readonly
    else
        return 1
    fi
}

if ! is_native_objc3_linux; then
    if [[ -n "${XSCOMIC_DOCKER_DELEGATED:-}" ]]; then
        echo "Error: objc3c toolchain not found inside container." >&2
        exit 1
    fi

    DOCKER_FLAGS=()
    DOCKER_ARGS=()
    library=
    if [[ -n "${XSCOMIC_LIBRARY_DIR:-}" ]]; then
        if [[ ! -d "$XSCOMIC_LIBRARY_DIR" ]]; then
            echo "Error: XSCOMIC_LIBRARY_DIR must be an existing directory." >&2
            exit 2
        fi
        library=$(host_path "$XSCOMIC_LIBRARY_DIR")
        add_docker_bind "$library" /comics readonly
        DOCKER_FLAGS+=(--run-arg -e --run-arg "XSCOMIC_HOST_LIBRARY_DIR=$library")
    fi
    DOCKER_FLAGS+=(--run-arg -e --run-arg "XSCOMIC_HOST_CHECKOUT=$ROOT")

    positional_only=false
    saw_book=false
    saw_screenshot=false
    while [[ $# -gt 0 ]]; do
        arg="$1"
        shift
        if [[ "$positional_only" == false ]]; then
            case "$arg" in
                --)
                    positional_only=true
                    DOCKER_ARGS+=("$arg")
                    continue
                    ;;
                --screenshot|--screenshot=*)
                    if [[ "$saw_screenshot" == true ]]; then
                        echo "Error: specify --screenshot once." >&2
                        exit 2
                    fi
                    saw_screenshot=true
                    if [[ "$arg" == --screenshot ]]; then
                        if [[ $# -eq 0 || "$1" == -* ]]; then
                            DOCKER_ARGS+=("$arg")
                            continue
                        fi
                        path="$1"
                        shift
                    else
                        path="${arg#*=}"
                    fi
                    if [[ -z "$path" ]]; then
                        DOCKER_ARGS+=(--screenshot=)
                        continue
                    fi
                    if ! map_docker_path "$path" screenshot; then
                        echo "Error: screenshot output directory does not exist: $path" >&2
                        exit 2
                    fi
                    DOCKER_ARGS+=("--screenshot=$DOCKER_PATH")
                    continue
                    ;;
                --page|--zoom|--size|--window-size)
                    DOCKER_ARGS+=("$arg")
                    if [[ $# -gt 0 && "$1" != -* ]]; then
                        DOCKER_ARGS+=("$1")
                        shift
                    fi
                    continue
                    ;;
                -*)
                    DOCKER_ARGS+=("$arg")
                    continue
                    ;;
            esac
        fi
        if [[ "$saw_book" == true ]]; then
            echo "Error: specify a single book path." >&2
            exit 2
        fi
        saw_book=true
        if [[ -z "$arg" ]] || ! map_docker_path "$arg" book; then
            echo "Error: book path does not exist: $arg" >&2
            exit 2
        fi
        DOCKER_ARGS+=("$DOCKER_PATH")
    done

    if [[ "$(uname -s)" == Linux && "$HAS_SCREENSHOT" == false && "${XSCOMIC_USE_XVFB:-0}" != 1 ]]; then
        if [[ -n "${DISPLAY:-}" ]]; then
            DOCKER_FLAGS+=(--run-arg -e --run-arg "DISPLAY=$DISPLAY")
            if [[ -d /tmp/.X11-unix ]]; then
                add_docker_bind /tmp/.X11-unix /tmp/.X11-unix readonly
            fi
            xauth="${XAUTHORITY:-$HOME/.Xauthority}"
            if [[ -f "$xauth" ]]; then
                add_docker_bind "$(host_path "$xauth")" /tmp/xscomic-Xauthority readonly
                DOCKER_FLAGS+=(--run-arg -e --run-arg XAUTHORITY=/tmp/xscomic-Xauthority)
            fi
        fi
        if [[ -n "${WAYLAND_DISPLAY:-}" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
            wayland_socket="$WAYLAND_DISPLAY"
            if [[ "$wayland_socket" != /* ]]; then
                wayland_socket="$XDG_RUNTIME_DIR/$wayland_socket"
            fi
            if [[ -S "$wayland_socket" ]]; then
                add_docker_bind "$wayland_socket" /tmp/xscomic-wayland readonly
                DOCKER_FLAGS+=(--run-arg -e --run-arg WAYLAND_DISPLAY=/tmp/xscomic-wayland)
            fi
        fi
        if [[ -d /dev/dri ]]; then
            DOCKER_FLAGS+=(--run-arg --device --run-arg /dev/dri:/dev/dri)
            seen_gids=":"
            for render_node in /dev/dri/renderD*; do
                [[ -c "$render_node" ]] || continue
                gid=$(stat -c '%g' "$render_node")
                if [[ "$seen_gids" != *":$gid:"* ]]; then
                    seen_gids+="$gid:"
                    DOCKER_FLAGS+=(--run-arg --group-add --run-arg "$gid")
                fi
            done
        fi
    fi

    DOCKER_ENV_ARGS=(XSCOMIC_DOCKER_DELEGATED=1)
    for name in XSCOMIC_USE_XVFB LIBGL_ALWAYS_SOFTWARE XSCOMIC_NO_LTO; do
        value="${!name:-}"
        if [[ -n "$value" ]]; then
            DOCKER_ENV_ARGS+=("$name=$value")
        fi
    done
    for name in CBR_SCRATCH_PATH CBR_OUTPUT_DIR; do
        value="${!name:-}"
        if [[ -z "$value" ]]; then
            continue
        fi
        if [[ "$value" == "$ROOT/"* ]]; then
            value="${value#"$ROOT/"}"
        elif [[ "$value" == /* ]]; then
            echo "Error: $name must be inside the checkout for Docker builds." >&2
            exit 2
        fi
        DOCKER_ENV_ARGS+=("$name=$value")
    done
    exec "$ROOT/scripts/docker-env.sh" ${DOCKER_FLAGS[@]+"${DOCKER_FLAGS[@]}"} -- \
        env "${DOCKER_ENV_ARGS[@]}" \
        bash /work/scripts/build-and-run-linux.sh "--$BUILD_CONFIG" -- ${DOCKER_ARGS[@]+"${DOCKER_ARGS[@]}"}
fi

"$ROOT/scripts/build-linux.sh" "--$BUILD_CONFIG"

OUTPUT_DIR="${CBR_OUTPUT_DIR:-$ROOT/build/linux}"
if [[ "$OUTPUT_DIR" != /* ]]; then
    OUTPUT_DIR="$ROOT/$OUTPUT_DIR"
fi
BIN="$OUTPUT_DIR/xscomic"

if [[ ! -x "$BIN" ]]; then
    echo "Error: built executable not found at $BIN" >&2
    exit 1
fi

USE_XVFB=false
if [[ "${XSCOMIC_USE_XVFB:-0}" == "1" ]]; then
    USE_XVFB=true
elif [[ "$HAS_SCREENSHOT" == true && -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" && "${SDL_VIDEODRIVER:-}" != offscreen ]]; then
    USE_XVFB=true
fi

if [[ "$USE_XVFB" == true ]]; then
    if ! command -v xvfb-run >/dev/null 2>&1; then
        echo "Error: headless launch requested, but xvfb-run is not installed." >&2
        exit 1
    fi
    export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
    xvfb-run -a -s "-screen 0 1280x800x24" \
        "$BIN" ${APP_ARGS[@]+"${APP_ARGS[@]}"}
    exit $?
fi

if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" && "${SDL_VIDEODRIVER:-}" != offscreen ]]; then
    echo "Error: neither DISPLAY nor WAYLAND_DISPLAY is set." >&2
    echo "Run interactively on a Linux X11/Wayland session, set XSCOMIC_USE_XVFB=1, or pass --screenshot <out.png>." >&2
    exit 1
fi

if [[ "${XSCOMIC_DOCKER_DELEGATED:-0}" == "1" && -n "${WAYLAND_DISPLAY:-}" && -z "${XDG_RUNTIME_DIR:-}" ]]; then
    RUNTIME_DIR=$(mktemp -d /tmp/xscomic-runtime-XXXXXX)
    chmod 0700 "$RUNTIME_DIR"
    export XDG_RUNTIME_DIR="$RUNTIME_DIR"
    trap 'rm -rf "$RUNTIME_DIR"' EXIT
    "$BIN" ${APP_ARGS[@]+"${APP_ARGS[@]}"}
    exit $?
fi

exec "$BIN" ${APP_ARGS[@]+"${APP_ARGS[@]}"}
