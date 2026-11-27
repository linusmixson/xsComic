<p align="center">
  <img src="Assets/Brand/xsComic-lockup.png" alt="xsComic" width="420">
</p>

**xsComic** is a native macOS reader for CBR/CBZ/etc. I cooked it up
because I wanted to read *Beastars* (sue me), didn't want unvetted
third-party software on my work partition, and realized because Codex
could make something passable in five minutes.

I then decided to run an experiment: can an LLM — tools (entities?)
that have gained infamy for their wild preference for adding lines
over deleting them — successfully write aggressively footprint-optimized
software? And can it write code that's "good," not simply "working"?
Recent models (post-January '26, basically) have seemed, perhaps,
capable of doing so.

*Reader, be advised: LLM writing is to follow.*

I believe the experiment to have been a success. Its result is a 510 KB app bundle,
about 220 KB of which is icon resources. It launches very quickly and includes no
third-party code. The source, from what I've seen, is legibile, well-structured,
and even educational. (The RAM footprint could still use some work.)

*Reader, be advised: human language stops here.*

## What it does

- Reads CB7/7z, CBR/RAR, CBT/tar, CBZ/ZIP, and image folders (`.avif`, `.bmp`, `.gif`, `.heic`/`.heif`, `.jpg`/`.jpeg`, `.png`, `.tif`/`.tiff`, `.webp`).
- Single-page and two-page spreads, left-to-right or right-to-left.
- Keyboard navigation, focal-point zoom, drag panning, fit, and actual size.
- Collapsible page sidebar, direct page jump (`Cmd+Shift+G` on macOS, `Ctrl+Shift+G` / `G` on Linux), and adjacent-volume continuation.
- Zero-extraction `pread` archive reading, GPU Lanczos-3 + mipmapped downscaling with EXIF 1–8 orientation, lossless 8-bit grayscale repacking, and bounded page caching.

## macOS

Native **Objective-C, AppKit, and Metal** (`Sources/xsComic/`, `Tests/xsComicTests/`). Requires macOS 14+ on Apple Silicon (`arm64`); Intel users can stay on [v1.0.0](https://github.com/linusmixson/xsComic/releases/tag/v1.0.0).

```sh
./scripts/build-and-run.sh
./scripts/run-tests.sh
./scripts/build-app.sh --archive
```

Compiles directly with `clang` against macOS system frameworks and libraries (`AppKit`, `Metal`, `ImageIO`, `IOSurface`, `Accelerate`, `libcompression`, `libarchive`) into `build/product/xsComic.app`. No Xcode project, no third-party dependencies.

## Linux (Slopjective-C / Objective-C 3.0)

Native **Objective-C 3.0, SDL2, and OpenGL 3.3 Core** port (`Sources/xsComicLinux/`, `Tests/xsComicLinuxTests/`) targeting Linux (`aarch64` / `x86_64`, verified on Debian 13), compiled with [**Slopjective-C**](https://github.com/doublemover/Slopjective-C) (`objc3c` `v0.1.0-preview.2`, patched Clang 23.1.5, GNUstep 2.2 ABI + `libobjc2`, zero GNUstep-Base).

```sh
# Build the stripped release binary (build/linux/xscomic)
./scripts/build-linux.sh --release

# Run the Linux core test and benchmark suite
./scripts/run-linux-tests.sh

# Build and launch (interactive X11/Wayland or headless --screenshot)
./scripts/build-and-run-linux.sh [args...]
```

Compiles `.objc3` sources directly with `objc3c` (`-Oz -flto=thin -Wl,--gc-sections -Wl,--as-needed` + `strip`) against system Linux libraries (`zlib`, `libarchive`, `libjpeg-turbo`, `libpng`, `libwebp`, `giflib`, `libtiff`, `libavif`, `libheif`, `SDL2`, `SDL2_ttf`, OpenGL, `pthreads`). On Linux with `objc3c` (or `/opt/objc3c/activate.sh`) installed, all scripts run natively; on macOS or hosts without the SDK, they automatically build and delegate through [`scripts/docker-env.sh`](scripts/docker-env.sh) and [`docker/Dockerfile`](docker/Dockerfile).

[Linux CI](.github/workflows/linux.yml) runs the core suite and the rendered-pixel and X11 smoke tests on x86-64 and AArch64. [macOS CI](.github/workflows/macos.yml) verifies the Apple Silicon AppKit bundles and runs the reader tests on `macos-15` by default. Select `macos-26` when manually dispatching the workflow to test that host.

To qualify the Objective-C 3 reader core on Apple Silicon, match Xcode to the installed experimental Darwin SDK and install the codec dependencies.

```sh
brew install pkg-config libarchive jpeg-turbo libpng webp libtiff libavif libheif giflib
XSCOMIC_OBJC3_SDK="/path/to/installed/Darwin SDK" ./scripts/run-objc3-macos-tests.sh
```

The script retains the SDK identity, loader paths, build logs, and results in `build/objc3-macos-tests/`.

### Objective-C 3 app on Apple Silicon

With macOS 15 or later and the Xcode version required by your installed
experimental Darwin SDK, build the SDL2/OpenGL reader as a native app bundle.
Install the codec dependencies above and add `sdl2-compat` and `sdl2_ttf`.

```sh
brew install sdl2-compat sdl2_ttf
XSCOMIC_OBJC3_SDK="/path/to/installed/Darwin SDK" ./scripts/build-objc3-macos-app.sh
ditto -x -k build/objc3-macos/release/xsComic-objc3-macos-arm64.zip build/objc3-macos/app
open "build/objc3-macos/app/xsComic ObjC3.app"
```

Use Cmd+O to open a comic archive or image folder. The app archive contains
its codec and window libraries. The reader links the owned Objective-C 3
runtime statically, and a separate AppKit process presents the file picker.
Slopjective-C's Apple Silicon qualification builds this archive from the
installed SDK and runs the shared pixel checks on the unpacked app.

### Linux benchmark snapshot

The following benchmark snapshot used Preview 1 on Debian 13 AArch64. [`Metrics/linux-objc3.json`](Metrics/linux-objc3.json) records the exact source digest and environment.

| Metric | Measured |
| --- | --- |
| Stripped `build/linux/xscomic` | **289.3 KiB** (296,272 bytes; 16 direct shared libs, 0 unused) |
| Core & E2E suites (`run-linux-tests.sh` + `smoke.py --x11`) | **191 passed, 0 failed** (ASan+UBSan+LSan & TSan 3/3 clean; all pixel/X11 checks pass) |
| 4,096-file directory scan | **1.16 ms** median (1.15 ms best) |
| 128-page / 500-page CBZ open | **0.024 ms** / **0.062 ms** median |
| Cold 1024×1536 JPEG decode | **3.28 ms** median (2.97 ms best) |
| Synchronous cache-hit lookup | **43.3 ns/call** median (42.3 ns/call best) |
| Cold CBZ launch-to-render (Xvfb + Mesa llvmpipe) | **97.2 ms** median direct / **95.2 ms** via `xvfb-run` |

See [`docs/linux.md`](docs/linux.md) for architecture, controls, CLI options, and cache invariants.

## Docs

- [`docs/README.md`](docs/README.md) — dual-platform repository layout and commands
- [`docs/guide.md`](docs/guide.md) — macOS architecture, I/O, Metal rendering, and cache invariants
- [`docs/linux.md`](docs/linux.md) — Linux Objective-C 3.0 architecture, OpenGL 3.3 rendering, controls, and CLI flags
- [`docs/optimization.md`](docs/optimization.md) — historical macOS 1.0 optimization record and measurements
- [`docs/releasing.md`](docs/releasing.md) — macOS packaging, signing, notarization, and DMG builds
- [`Metrics/`](Metrics/) — raw measurement records (macOS + [`Metrics/linux-objc3.json`](Metrics/linux-objc3.json))

## License

Code is **AGPL-3.0-or-later**. Docs and measurements are **CC BY-SA 4.0**. The xsComic name and everything under `Assets/` are excluded; see [`LICENSING.md`](LICENSING.md).
