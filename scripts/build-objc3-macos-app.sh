#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

usage() {
    printf '%s\n' "Usage: $0 [--release|--debug]" \
        "Set XSCOMIC_OBJC3_SDK to the installed Apple Silicon SDK."
}

case "${1:---release}" in
    -h|--help) usage; exit 0 ;;
    --release) configuration=release; optimization=(-Oz) ;;
    --debug) configuration=debug; optimization=(-O0 -g) ;;
    *) usage >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then usage >&2; exit 2; fi
if [[ "$(uname -s):$(uname -m)" != Darwin:arm64 ]]; then
    echo "Building the Objective-C 3 app requires native Apple Silicon." >&2
    exit 2
fi

SDK=$(cd "${XSCOMIC_OBJC3_SDK:?Set XSCOMIC_OBJC3_SDK to the installed Apple Silicon SDK.}" && pwd -P)
COMPILER="$SDK/bin/objc3c"
BREW_PREFIX=$(brew --prefix)
FORMULAE=(libarchive jpeg-turbo libpng webp libtiff libavif libheif giflib sdl2-compat sdl2_ttf)
for formula in "${FORMULAE[@]}"; do
    pc="$(brew --prefix "$formula")/lib/pkgconfig"
    PKG_CONFIG_PATH="$pc${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
done
export PKG_CONFIG_PATH
PACKAGES=(libarchive libjpeg libpng libwebp libtiff-4 libavif libheif sdl2 SDL2_ttf)
CFLAGS=$(pkg-config --cflags "${PACKAGES[@]}")
LIBS=$(pkg-config --libs "${PACKAGES[@]}")
GIF=$(brew --prefix giflib)
SDL=$(brew --prefix sdl2-compat)
TTF=$(brew --prefix sdl2_ttf)
"$COMPILER" --version

OUTPUT="$ROOT/build/objc3-macos/$configuration"
mkdir -p "$OUTPUT"
work=$(mktemp -d "$OUTPUT/.build.XXXXXX")
trap 'rm -rf "$work"' EXIT
APP="$work/xsComic ObjC3.app"
BIN="$APP/Contents/MacOS/xscomic"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SOURCE="$ROOT/Sources/xsComicLinux"
objects=()
pids=()
for unit in "$SOURCE"/*.objc3; do
    stem=$(basename "$unit" .objc3)
    object="$work/$stem.o"
    # pkg-config publishes a list of compiler arguments.
    # shellcheck disable=SC2086
    "$COMPILER" -x objective-c -std=c17 -D_DARWIN_C_SOURCE -DGL_SILENCE_DEPRECATION \
        -fobjc-arc -fblocks -Wall -Wextra -Werror "${optimization[@]}" \
        -I"$SOURCE" -I"$GIF/include" -I"$SDL/include" -I"$TTF/include" \
        $CFLAGS -c "$unit" -o "$object" >"$work/$stem.log" 2>&1 &
    pids+=("$!")
    objects+=("$object")
done
failed=0
for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
cat "$work"/*.log
if (( failed )); then exit 1; fi

# The AppKit picker is a separate process with the system Objective-C ABI.
# shellcheck disable=SC2086
"$COMPILER" --runtime-link=static "${objects[@]}" $LIBS -L"$GIF/lib" -lgif -lz \
    -framework OpenGL -Wl,-headerpad_max_install_names -o "$BIN"
xcrun --sdk macosx clang -arch arm64 -mmacosx-version-min=15.0 -fobjc-arc -Oz \
    -Wall -Wextra -Werror -framework AppKit "$ROOT/Sources/xsComicObjC3Mac/ChooseBook.m" \
    -o "$APP/Contents/MacOS/xscomic-open"

python3 "$ROOT/scripts/bundle-macos-dylibs.py" "$BIN" "$BREW_PREFIX"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/"
python3 - "$APP" "$ROOT/VERSION" <<'PY'
from pathlib import Path
import plistlib
import sys

app, version = map(Path, sys.argv[1:])
number = version.read_text().strip()
(app / "Contents/Info.plist").write_bytes(plistlib.dumps({
    "CFBundleExecutable": "xscomic",
    "CFBundleIdentifier": "com.xscomic.objc3",
    "CFBundleIconFile": "AppIcon",
    "CFBundleName": "xsComic ObjC3",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": number,
    "CFBundleVersion": number,
    "LSMinimumSystemVersion": "15.0",
    "NSHighResolutionCapable": True,
}))
PY
for library in "$APP/Contents/Frameworks/"*.dylib; do
    codesign --force --sign - "$library"
done
codesign --force --sign - "$APP/Contents/MacOS/xscomic-open"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

# Archive only after the completed bundle passes signature verification.
ditto -c -k --keepParent "$APP" "$work/xsComic-objc3-macos-arm64.zip"
mv -f "$work/xsComic-objc3-macos-arm64.zip" "$OUTPUT/xsComic-objc3-macos-arm64.zip"
printf 'Built %s\n' "$OUTPUT/xsComic-objc3-macos-arm64.zip"
