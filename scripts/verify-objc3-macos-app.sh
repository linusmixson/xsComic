#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
ARCHIVE=${1:?Supply the archive from build-objc3-macos-app.sh.}
EVIDENCE=${2:?Supply a directory for qualification logs.}
mkdir -p "$EVIDENCE"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/xscomic-macos.XXXXXX")
scratch=$(cd "$scratch" && pwd -P)
trap 'rm -rf "$scratch"' EXIT
destination="$scratch/Relocated App"
ditto -x -k "$ARCHIVE" "$destination"
APP="$destination/xsComic ObjC3.app"
BIN="$APP/Contents/MacOS/xscomic"
HELPER="$APP/Contents/MacOS/xscomic-open"

codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
test -s "$APP/Contents/Resources/AppIcon.icns"
test "$(lipo -archs "$HELPER")" = arm64
nm -j "$BIN" >"$EVIDENCE/symbols.txt"
grep -Fxq _objc3_darwin_allocate_v1 "$EVIDENCE/symbols.txt"
otool -L "$BIN" >"$EVIDENCE/load-paths.txt"
python3 "$ROOT/scripts/bundle-macos-dylibs.py" "$BIN" --verify
"$HELPER" --check
env -u DYLD_LIBRARY_PATH -u DYLD_FALLBACK_LIBRARY_PATH DYLD_PRINT_LIBRARIES=1 \
    "$BIN" --screenshot "$scratch/window.png" --size 800x600 2>"$EVIDENCE/dyld.log"
grep -Fq "$APP/Contents/Frameworks/libSDL3.dylib" "$EVIDENCE/dyld.log"
env -u DYLD_LIBRARY_PATH -u DYLD_FALLBACK_LIBRARY_PATH \
    python3 "$ROOT/Tests/xsComicLinuxTests/smoke.py" "$BIN" | tee "$EVIDENCE/results.txt"
shasum -a 256 "$ARCHIVE" >"$EVIDENCE/archive.sha256"
