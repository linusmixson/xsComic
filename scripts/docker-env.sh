#!/usr/bin/env bash
set -eu

# Build (if missing) the xscomic-objc3:dev Docker image and run commands inside
# it with the repository root bind-mounted at /work.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
IMAGE="${XSCOMIC_DOCKER_IMAGE:-xscomic-objc3:dev}"
DOCKERFILE="$REPO_ROOT/docker/Dockerfile"

usage() {
    cat <<EOF
Usage: $(basename -- "$0") [--build] [--] [command [args...]]

Options:
  --run-arg ARG  Append a Docker run argument before the image. Repeat as needed.
  --build     (Re)build ${IMAGE} from docker/Dockerfile before running.
              If no command is given, exits after building.
  -h, --help  Show this help message.

Environment:
  XSCOMIC_DOCKER_IMAGE  Override Docker image tag (default: xscomic-objc3:dev)

Examples:
  ./scripts/docker-env.sh --build
  ./scripts/docker-env.sh objc3c --version
  ./scripts/docker-env.sh sh -c 'xvfb-run -a glxinfo -B'
  ./scripts/docker-env.sh   # interactive shell in /work
EOF
}

FORCE_BUILD=0
RUN_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --build)
            FORCE_BUILD=1
            shift
            ;;
        --run-arg)
            if [[ $# -lt 2 ]]; then
                echo "Missing docker run argument" >&2
                exit 2
            fi
            RUN_ARGS+=("$2")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

build_image() {
    docker build \
        -f "$DOCKERFILE" \
        -t "$IMAGE" \
        "$REPO_ROOT/docker"
}

if [ "$FORCE_BUILD" -eq 1 ]; then
    build_image
    if [ $# -eq 0 ]; then
        exit 0
    fi
elif ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    build_image
fi

if [[ -t 0 && -t 1 ]]; then
    RUN_ARGS+=(-it)
fi
CONFIG_DIR="$REPO_ROOT/build/docker-config"
mkdir -p "$CONFIG_DIR"
if [[ $# -eq 0 ]]; then
    set -- bash -l
fi
exec docker run --rm --init --user "$(id -u):$(id -g)" \
    -v "$REPO_ROOT:/work" \
    -e HOME=/tmp \
    -e XDG_CONFIG_HOME=/work/build/docker-config \
    -e XSCOMIC_BUILD_LOCK_DIR=/work/build/.locks \
    -e XDG_CACHE_HOME=/tmp/xscomic-cache \
    -e XDG_DATA_HOME=/tmp/xscomic-data \
    -w /work ${RUN_ARGS[@]+"${RUN_ARGS[@]}"} "$IMAGE" "$@"
