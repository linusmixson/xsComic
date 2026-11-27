# syntax=docker/dockerfile:1
FROM debian:13

ARG TARGETARCH
ARG OBJC3_SDK_VERSION=v0.1.0-preview.1
ARG OBJC3_SDK_ROOT_BASE=/opt/objc3c

# Pinned SHA-256 digests from doublemover/Slopjective-C v0.1.0-preview.1 SHA256SUMS
ARG INSTALL_LINUX_SH_SHA256=872e127695ee6ce91801faba0e17a343860bf2751bee2bd49d98b1e8ec3cc4ba
ARG INSTALL_SDK_PY_SHA256=5ca49105c707cc6be5dd6b1269dda836dc9f1f2067eb44d4924a4a7c1cab962e
ARG SDK_AARCH64_SHA256=390a78c403cf9e391a973abd91bbf296e0242136a43ec87eab48d017574e5ee9
ARG SDK_X86_64_SHA256=279269c7e87b56289e11e800097f2490dd18d2124fc456306665471fab207222

# Layer 1: Download, verify, and install the official Slopjective-C Linux SDK.
# Kept separate and before the xsComic dev-library layer so Docker caches the
# ~494 MB SDK archive download and extraction across library tweaks.
RUN set -eu; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
        arm64|aarch64) \
            sdk_arch="aarch64"; \
            sdk_sha256="${SDK_AARCH64_SHA256}"; \
            ;; \
        amd64|x86_64) \
            sdk_arch="x86_64"; \
            sdk_sha256="${SDK_X86_64_SHA256}"; \
            ;; \
        *) \
            echo "Unsupported TARGETARCH: $arch" >&2; \
            exit 1; \
            ;; \
    esac; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl; \
    base_url="https://github.com/doublemover/Slopjective-C/releases/download/${OBJC3_SDK_VERSION}"; \
    sdk_file="objc3-sdk-${OBJC3_SDK_VERSION}-linux-${sdk_arch}.tar.zst"; \
    workdir="/tmp/objc3-install"; \
    mkdir -p "$workdir"; \
    curl -fsSL --retry 3 --retry-delay 2 -o "$workdir/install-linux.sh" "${base_url}/install-linux.sh"; \
    curl -fsSL --retry 3 --retry-delay 2 -o "$workdir/install-sdk.py" "${base_url}/install-sdk.py"; \
    curl -fsSL --retry 3 --retry-delay 2 -o "$workdir/${sdk_file}" "${base_url}/${sdk_file}"; \
    printf '%s  %s\n%s  %s\n%s  %s\n' \
        "${INSTALL_LINUX_SH_SHA256}" "$workdir/install-linux.sh" \
        "${INSTALL_SDK_PY_SHA256}" "$workdir/install-sdk.py" \
        "${sdk_sha256}" "$workdir/${sdk_file}" \
        | sha256sum -c -; \
    chmod +x "$workdir/install-linux.sh"; \
    "$workdir/install-linux.sh" --provision \
        --archive "$workdir/${sdk_file}" \
        --sha256 "${sdk_sha256}" \
        --root "${OBJC3_SDK_ROOT_BASE}"; \
    rm -rf "$workdir" /var/lib/apt/lists/*

# Layer 2: Install Linux dev/runtime libraries for xsComic (archives, codecs,
# SDL2 + OpenGL/Mesa, fonts, and headless Xvfb verification tooling).
RUN set -eu; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        pkg-config \
        make \
        zlib1g-dev \
        libarchive-dev \
        libzstd1 \
        libjpeg62-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libgif-dev \
        libtiff-dev \
        libavif-dev \
        libheif-dev \
        libsdl2-dev \
        libsdl2-ttf-dev \
        libgl-dev \
        libegl-dev \
        libgl1-mesa-dri \
        libglx-mesa0 \
        libegl-mesa0 \
        mesa-utils \
        xvfb \
        xauth \
        xdotool \
        fonts-dejavu-core \
        python3 \
        python3-pil; \
    install -d -m 1777 /tmp/.X11-unix; \
    rm -rf /var/lib/apt/lists/*

# Configure SDK environment for both non-login invocations and login shells,
# plus dynamic linker registration for /opt/objc3c/current/lib.
RUN set -eu; \
    printf '%s\n' "${OBJC3_SDK_ROOT_BASE}/current/lib" > /etc/ld.so.conf.d/objc3c.conf; \
    ldconfig; \
    printf '%s\n' \
        '# Activate Slopjective-C SDK for login shells.' \
        "if [ -f ${OBJC3_SDK_ROOT_BASE}/activate.sh ]; then" \
        "    . ${OBJC3_SDK_ROOT_BASE}/activate.sh" \
        'fi' \
        > /etc/profile.d/objc3c.sh; \
    chmod 0644 /etc/profile.d/objc3c.sh

ENV OBJC3C_SDK_ROOT="${OBJC3_SDK_ROOT_BASE}/current" \
    OBJC3C_CLANG_FOUNDATION_ROOT="${OBJC3_SDK_ROOT_BASE}/current" \
    LLVM_ROOT="${OBJC3_SDK_ROOT_BASE}/current" \
    OBJC3C_LLVM_ROOT="${OBJC3_SDK_ROOT_BASE}/current" \
    LLVM_DIR="${OBJC3_SDK_ROOT_BASE}/current/lib/cmake/llvm" \
    Clang_DIR="${OBJC3_SDK_ROOT_BASE}/current/lib/cmake/clang" \
    LD_LIBRARY_PATH="${OBJC3_SDK_ROOT_BASE}/current/lib" \
    PATH="${OBJC3_SDK_ROOT_BASE}/current/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

WORKDIR /work
