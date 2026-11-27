# Guide to xsComic (Linux / Objective-C 3.0)

How the Linux **Objective-C 3.0** port of xsComic is put together, where the
ownership boundaries sit, and why the hot paths are written the way they are.
Detailed invariants live in the source comments; this is the map. For the
native macOS AppKit/Metal implementation, see [guide.md](guide.md).

## Toolchain and Objective-C 3.0 model

xsComic on Linux targets `aarch64-unknown-linux-gnu` and
`x86_64-unknown-linux-gnu` (verified on Debian 13) and compiles directly with
the official **Slopjective-C** (`doublemover/Slopjective-C`,
`v0.1.0-preview.1`) **`objc3c`** compiler — patched LLVM/Clang 23.1.5 targeting
the GNUstep 2.2 ABI and `libobjc2` (`libobjc.so.4.6`) with ARC and Blocks
enabled.

To avoid GNUstep-Base footprint and startup overhead,
[`XSCBase.objc3`](../Sources/xsComicLinux/XSCBase.objc3) defines a minimal
`__attribute__((objc_root_class))` ARC root class (`XSCObject`) and only the
primitives the reader actually needs. The `.objc3` sources use idiomatic
Objective-C 3.0 throughout:

- `defer` for deterministic cleanup of file descriptors, heap buffers, mutex
  guards, libarchive handles, and OpenGL objects;
- `Optional(T)` (`Some` / `None`) and `Result(T, E)` (`Ok` / `Err`) unpacked
  via exhaustive `match`;
- typed `throws(XSCError *)` (conforming to Objective-C 3.0 `<Error>`),
  `tryValue` / `tryOptional`, and `handle` / `catch`.

## Build, test, and run

```sh
# Stripped release binary -> build/linux/xscomic (+ build/linux/xscomic.symbols)
./scripts/build-linux.sh --release

# Unoptimized debug binary (-O0 -g) -> build/linux/xscomic
./scripts/build-linux.sh --debug

# Standalone core test and benchmark suite
./scripts/run-linux-tests.sh

# Check the built release with Mesa, Xvfb, and ordinary synthetic comic pages
xvfb-run -a python3 Tests/xsComicLinuxTests/smoke.py build/linux/xscomic --x11

# Build and launch interactively (X11/Wayland) or headlessly (--screenshot)
./scripts/build-and-run-linux.sh [args...]
```

All Linux scripts run natively when `objc3c` (or `/opt/objc3c/activate.sh`) is
present on Linux, and automatically delegate through
[`../scripts/docker-env.sh`](../scripts/docker-env.sh) and
[`../docker/Dockerfile`](../docker/Dockerfile) (`xscomic-objc3:dev`) on macOS
or hosts without the SDK. The image runs as the invoking UID and GID and saves
preferences to `build/docker-config/`. Build inputs and outputs specified by
`CBR_SCRATCH_PATH` and `CBR_OUTPUT_DIR` live under the checkout when Docker
performs the build. Native builds also accept paths outside the checkout.

Docker mounts an explicitly supplied book outside the checkout read-only and
mounts the requested screenshot output directory. Set
`XSCOMIC_LIBRARY_DIR=/path/to/comics` to browse a whole host library, navigate
adjacent volumes, or drop files from that library into the window. The library
mount is read-only. Native interactive builds use `zenity` or `kdialog` for the
Open dialog.

### Experimental Darwin Objective-C 3 SDK qualification

The core Objective-C 3 sources (`XSCBase`, `XSCArchive`, `XSCImageStore`,
`XSCReaderModel`) also carry minimal `#if defined(__APPLE__)` runtime guards
and a standalone qualification script for testing the experimental Slopjective-C
Darwin SDK on Apple Silicon
([`Slopjective-C #8340`](https://github.com/doublemover/Slopjective-C/issues/8340)):

```sh
brew install pkg-config libarchive jpeg-turbo libpng webp libtiff libavif libheif giflib
XSCOMIC_OBJC3_SDK="/path/to/installed/Darwin SDK" ./scripts/run-objc3-macos-tests.sh
```

Build logs, SDK identity, library paths, and test output are saved under
`build/objc3-macos-tests/`. For the native macOS desktop app, see
[guide.md](guide.md).

## Supported formats

| Family | Extensions | Backend |
| --- | --- | --- |
| ZIP | `.cbz`, `.zip` | `pread(2)` Central Directory + Zip64 + `zlib` raw-DEFLATE (fallback to `libarchive` for exotic methods) |
| tar | `.cbt`, `.tar` | `pread(2)` ustar / PAX / GNU LongName offset scan (fallback to `libarchive` if needed) |
| RAR | `.cbr`, `.rar` | in-process `libarchive` (`-larchive`) |
| 7-Zip | `.cb7`, `.7z` | in-process `libarchive` (`-larchive`) |
| Folder | any directory | POSIX `fdopendir` / `openat` |

Image extensions: `.avif`, `.bmp`, `.gif`, `.heic`, `.heif`, `.jpeg`, `.jpg`,
`.png`, `.tif`, `.tiff`, `.webp`. Decoding runs directly against native Linux
libraries (`libjpeg-turbo`, `libpng`, `libwebp`, `giflib`, `libtiff`,
`libavif`, `libheif`) plus a built-in zero-dependency 24/32-bit BMP decoder.

Dotfiles, `__MACOSX` resource forks, symlinks, non-regular files (FIFOs,
sockets, device nodes), embedded NUL bytes, Windows drive prefixes, leading
slashes, and `..` path traversal components are rejected or skipped. Pages and
adjacent sibling volumes are ordered with a zero-allocation ASCII-fast natural
comparator (`page2.jpg` before `page10.jpg`) that seamlessly handles UTF-8
multibyte prefixes and fullwidth digits with a deterministic raw-byte
tie-breaker (`qsort_r`).

## Architecture

Six `.objc3` implementation files and five headers in
[`../Sources/xsComicLinux/`](../Sources/xsComicLinux/):

```text
main.objc3 (XSCAppController / XSCUIRenderer)
  │ SDL2 window, reactive event loop, dark-chrome GL UI, XDG prefs, CLI/--screenshot
  ▼
XSCReaderModel ──────────► XSCArchive (XSCBook)
  │ archive-order nav,      zero-extraction CBZ/CBT (pread + zlib),
  │ spreads, pre-warming    libarchive CBR/CB7, POSIX directory scan
  │
  ├──────────────────────► XSCImageStore (XSCDecodedPage)
  │                         pthread_mutex hash cache, page-owned mmap,
  │                         L8 grayscale repack, 4-lane priority pthread pool
  ▼
XSCGLCanvas
  OpenGL 3.3 Core, GL_R8 / GL_RGBA8 textures, hybrid Lanczos-3 + mipmap & EXIF 1–8

XSCBase — XSCObject ARC root, XSCString, XSCData, XSCError <Error>, XSCIndexList,
          main-thread queue/timers, and background pthread pool
```

### `XSCBase` ([`XSCBase.h`](../Sources/xsComicLinux/XSCBase.h), [`XSCBase.objc3`](../Sources/xsComicLinux/XSCBase.objc3))

- **Minimal ARC foundation**: `XSCObject` (`__attribute__((objc_root_class))`)
  allocates and disposes directly through `libobjc2` (`class_createInstance` /
  `object_dispose`). `XSCString`, `XSCData` (including zero-copy
  `dataTakingBytesNoCopy:length:`), `XSCError <Error>`, and `XSCIndexList`
  replace Foundation collections and strings without extra runtime baggage.
- **Queues, timers, and clock**: Provides monotonic timing (`xsc_now_ns` /
  `xsc_now_ms`), a main-thread dispatch and delayed-timer queue
  (`xsc_dispatch_main`, `xsc_dispatch_main_after_ms`, `xsc_main_drain`) with a
  wakeup hook (`xsc_set_main_wakeup`) shared by both SDL2 and headless tests, a
  background pthread worker pool (`xsc_dispatch_bg`), and recursive POSIX tree
  removal (`xsc_remove_tree`).

### `XSCArchive` ([`XSCArchive.h`](../Sources/xsComicLinux/XSCArchive.h), [`XSCArchive.objc3`](../Sources/xsComicLinux/XSCArchive.objc3))

- **CBZ/ZIP & CBT/tar** use an open file descriptor and `pread(2)`.
  ZIP reads verify CRC-32 for both STORE and DEFLATE, including empty entries.
  Raw DEFLATE output and ZIP index sizes are bounded before allocating.
  The native ZIP and tar paths support Zip64 and ustar/PAX/GNU LongName
  respectively, without extracting page files to disk.
- **libarchive fallback** reads RAR, 7-Zip, and alternate ZIP and tar formats.
  It checks an opened regular file and switches only the calling thread to
  a UTF-8 locale. Each book may hold up to 256 MiB of archive payload buffers
  in memory. Larger pages spill to private temporary storage, capped at
  2 GiB per book. The process-wide cap is 4 GiB or half the available
  temporary filesystem space at the first spill, whichever is lower. The
  spill directory uses an absolute `TMPDIR` when set, otherwise `/tmp`.
  Closing the book, cancellation, and errors release its spill storage.
- **Directories & adjacent volumes** use a retained directory descriptor for
  indexing and reads. Page names are stored relative to that descriptor.
  Traversal uses `openat` with `O_NOFOLLOW` for child directory and file
  components. Adjacent-volume discovery checks readable siblings in natural order.

### `XSCImageStore` ([`XSCImageStore.h`](../Sources/xsComicLinux/XSCImageStore.h), [`XSCImageStore.objc3`](../Sources/xsComicLinux/XSCImageStore.objc3))

- **Bounded cache and synchronous hits** use a lock-protected hash table,
  retention-aware LRU eviction, in-flight request coalescing, and a bounded
  negative cache. The cache holds up to 12 entries and 64 MiB of decoded
  bytes by default. A decoded page owns its pixel mapping for as long as a
  caller or the cache retains it, including its use by the canvas.
- **Native codecs and EXIF** cover JPEG, PNG, WebP, GIF, TIFF, AVIF, HEIF,
  and 24/32-bit BMP. Animated GIFs retain composited frames and honor the
  encoded frame timing and repeat count. TIFF keeps the source orientation for
  the canvas and converts libtiff's associated alpha to straight alpha.
- **Grayscale** JPEG and opaque grayscale PNG decode directly to 8-bit L8.
  Other static pages use L8 only if every decoded pixel is opaque and has
  identical red, green, and blue channels. Pixel rows are 64-byte aligned.
- **Concurrency**: 4-lane priority pthread decode pool capping background
  prefetch/pre-warm work at 3 active lanes so 1 lane is always reserved for
  visible demand.

### `XSCGLCanvas` ([`XSCGLCanvas.h`](../Sources/xsComicLinux/XSCGLCanvas.h), [`XSCGLCanvas.objc3`](../Sources/xsComicLinux/XSCGLCanvas.objc3))

- Renders directly through OpenGL 3.3 Core, uploading `L8` pages as `GL_R8`
  (1 Bpp) and color pages as `GL_RGBA8` (4 Bpp) using `GL_UNPACK_ROW_LENGTH` to
  honor 64-byte-aligned row strides.
- Compiles an inline GLSL 330 Core shader once at startup using an empty VAO
  and `gl_VertexID` quads. The fragment shader performs EXIF 1–8 orientation
  transforms, `.rrr1` grayscale swizzling, hybrid downscaling (6×6 separable
  Lanczos-3 on level 0 for `1.05×–3×` reductions to keep manga screentones
  crisp, switching to lazily generated trilinear mipmaps above `3×` to avoid
  extreme-zoom aliasing, and linear sampling at native/upscale), and a
  one-pixel border. Color uploads use premultiplied alpha to keep transparent
  pixels from tinting edges during filtering.
- Decode-once, GPU-scale-always: focal-point zooming (`0.1×`–`16×`), drag
  panning, resizing, and toggling the sidebar never re-decode images.
  A page keeps its texture and playback position when it moves to the other
  side of a spread. GIF playback schedules actual frame deadlines and skips
  missed frames without slowing the animation.

### `XSCReaderModel` & desktop shell ([`XSCReaderModel.h`](../Sources/xsComicLinux/XSCReaderModel.h), [`XSCReaderModel.objc3`](../Sources/xsComicLinux/XSCReaderModel.objc3), [`main.objc3`](../Sources/xsComicLinux/main.objc3))

- **Archive-order navigation & zero-hop turns**: `currentIndex` always walks
  `0 ..< pageCount` aligned to the spread step; RTL reverses only
  `visualPageIndices`. Synchronous cache hits update `XSCGLCanvas` in the same
  event turn. Cold decodes hold the previous spread for a 120 ms loading grace
  period before revealing the loading overlay.
- **Prefetch & adjacent-volume pre-warming**: Prefetches 8 pages ahead and 2
  behind, flipping bias backward after 2 consecutive backward turns. Within 3
  pages of either volume boundary (when volume continuation is enabled), the
  adjacent volume is opened and its boundary page(s) pre-decoded off-main so
  crossing volumes swaps seamlessly.
- **Desktop shell (`main.objc3`)**: Single-process SDL2 + OpenGL 3.3 Core +
  `SDL2_ttf` (DejaVu Sans / Liberation Sans) reactive event loop using
  `SDL_WaitEventTimeout`, a user event for queued main-thread work, and deadlines
  for timers, GIFs, and the text caret. Draws dark-chrome UI elements
  via an inline SDF rounded-rectangle shader and an LRU glyph texture cache:
  top toolbar, collapsible 180 px page sidebar, empty-state CTA card, direct
  Jump-to-Page modal, settings popover persisted to
  `$XDG_CONFIG_HOME/xscomic/prefs.ini` (default `~/.config/xscomic/prefs.ini`),
  drag-and-drop (`SDL_DROPFILE`), off-main file chooser (`zenity` / `kdialog`),
  and deterministic `--screenshot` PNG capture via `libpng`.

## Controls and CLI options

### Keyboard and pointer

| Input | Action |
| --- | --- |
| `Left` / `Right` | Turn page (respects RTL key-swap preference) |
| `Space` / `Shift+Space`, `PageDown` / `PageUp` | Next / previous page or spread |
| `Home` / `End` | First / last page |
| `Ctrl+O` | Open comic (`zenity` / `kdialog`) — or drag & drop onto window |
| `Ctrl+Shift+G` or `G` | Open Jump-to-Page modal |
| `B` or `Ctrl+Alt+S` | Toggle page sidebar |
| `D` / `Ctrl+D` | Toggle LTR / RTL reading direction |
| `P` / `Ctrl+P` | Toggle Single / Two-page spread mode |
| `+` / `-`, `Ctrl`+scroll, trackpad pinch | Zoom in / out (focal-point on pointer/pinch) |
| `0` / `F` / `Ctrl+0`, `1` / `Ctrl+1` | Fit to window / 100% actual size |
| Left-drag (while zoomed) | Pan canvas |
| `Ctrl+,` | Toggle Settings popover |
| `Esc` / `Ctrl+Q` | Dismiss modal/popover/banner / Quit |

### CLI flags

```text
build/linux/xscomic [options] [book_path]
  --single            Start in single-page mode
  --double            Start in two-page spread mode
  --ltr               Start in left-to-right reading direction
  --rtl               Start in right-to-left reading direction
  --sidebar           Start with the page sidebar open
  --page N            Jump to 1-based page N after opening
  --zoom SCALE        Set custom zoom scale (e.g. 1.5)
  --size WxH          Start with initial window dimensions (e.g. 640x480)
  --jump-modal        Open the Jump-to-Page modal
  --settings          Open the Settings popover
  --screenshot PATH   Render frame, save PNG to PATH, and exit
```

With a book path, `--screenshot` waits for the requested spread to render.
Opening, decoding, and output errors return a nonzero status. With no book,
it captures the empty reader. Invalid command-line arguments exit with status 2.

## Measured footprint and benchmarks

Measured on Debian 13 (`aarch64`, `objc3c` `v0.1.0-preview.1` / Clang 23.1.5,
GNUstep 2.2 ABI, `-Oz -flto=thin -Wl,--gc-sections -Wl,--as-needed` + `strip`).
Full section breakdown, sanitizers, and raw run samples are recorded in
[`../Metrics/linux-objc3.json`](../Metrics/linux-objc3.json):

| Metric | Measured |
| --- | --- |
| Stripped `build/linux/xscomic` | **289.3 KiB** (296,272 bytes; `text` 264,715 B, `data` 27,588 B, `bss` 8,000 B) |
| Unstripped `build/linux/xscomic.symbols` | **447.1 KiB** (457,832 bytes) |
| Debug `-O0 -g` binary | **888.7 KiB** (909,984 bytes) |
| Direct dynamic dependencies (`readelf -d`) | **16** (`ldd -u -r`: 0 unused; zero GNUstep-Base) |
| Standalone tests ([`Tests/xsComicLinuxTests/main.objc3`](../Tests/xsComicLinuxTests/main.objc3)) | **191 passed, 0 failed** (3/3 runs; ASan+UBSan+LSan & TSan 3/3 clean) |
| E2E pixel & X11 smoke suite ([`Tests/xsComicLinuxTests/smoke.py`](../Tests/xsComicLinuxTests/smoke.py)) | All CLI, orientation, alpha-edge, Lanczos-3 / mipmap, GIF, picker, and jump checks passed |
| 4,096-file directory scan (3 runs) | **1.16 ms** median (1.15 ms fastest) |
| 128-page CBZ open (3 runs) | **0.024 ms** median (0.023 ms fastest) |
| 500-page CBZ open (3 runs) | **0.062 ms** median (0.056 ms fastest) |
| Cold 1024×1536 JPEG decode (3 runs) | **3.28 ms** median (2.97 ms fastest) |
| Synchronous cache-hit lookup (10,000 hits, 3 runs) | **43.3 ns/call** median (42.3 ns/call fastest) |
| Test process RSS (`/proc/self/statm`, 3 runs) | **42.64 MiB** median (42.64 MiB lowest) |
| Cold launch-to-render, 10p 1024×1536 CBZ (1280×800, Mesa llvmpipe) | **97.23 ms** median direct on Xvfb (76.09 ms fastest) / **95.15 ms** via `xvfb-run` |
