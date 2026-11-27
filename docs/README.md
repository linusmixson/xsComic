# Documentation

- [macOS project guide](guide.md) — Objective-C / AppKit / Metal architecture, I/O, GPU rendering, and invariants.
- [Linux project guide](linux.md) — Objective-C 3.0 / SDL2 / OpenGL 3.3 architecture, controls, CLI flags, and benchmarks.
- [Release procedure](releasing.md) — macOS packaging, Developer ID signing, notarization, and DMG creation.
- [Optimization record](optimization.md) — historical macOS 1.0 optimization log and measurements.

Raw JSON measurements live in [`../Metrics/`](../Metrics/), including the Linux Slopjective-C audit at [`../Metrics/linux-objc3.json`](../Metrics/linux-objc3.json).

## Repository layout

```text
.
├── VERSION                   release version
├── Sources/
│   ├── xsComic/              macOS Objective-C / AppKit / Metal application (.h, .m)
│   └── xsComicLinux/         Linux Objective-C 3.0 / SDL2 / OpenGL 3.3 application (.h, .objc3)
├── Tests/
│   ├── xsComicTests/         macOS standalone test and benchmark suite (main.m)
│   └── xsComicLinuxTests/    Linux core test/benchmark suite (main.objc3, 191 assertions) & E2E smoke (smoke.py)
├── .github/workflows/        Linux (x86-64/AArch64) and macOS (arm64) CI workflows
├── docker/
│   └── Dockerfile            Debian 13 + pinned Slopjective-C SDK (v0.1.0-preview.1) toolchain image
├── Assets/                   compiled Assets.car, alternate SVG, and brand masters
├── Metrics/                  raw JSON measurement records (macOS + linux-objc3.json)
├── docs/
│   ├── README.md             this document
│   ├── guide.md              macOS architecture guide
│   ├── linux.md              Linux Objective-C 3.0 architecture guide
│   ├── optimization.md       historical macOS 1.0 optimization record
│   └── releasing.md          macOS signing, notarization, and DMG procedure
└── scripts/                  macOS and Linux build, test, launch, Docker, icon, and DMG scripts
```

Only `Assets/Assets.car` and `Assets/Brand/xsComic-azusa-app-mark.svg` ship in
the macOS app bundle. No Xcode project, CMake project, GNUstep-Base dependency,
vendored libraries, telemetry, or updater.

Code is AGPL-3.0-or-later, docs/metrics are CC BY-SA 4.0, and branding is
excluded. See [`../LICENSING.md`](../LICENSING.md).

## Commands

### macOS (`Sources/xsComic/`, output in `build/product/`)

```sh
# Build and launch a release app (build/product/xsComic.app).
./scripts/build-and-run.sh

# Build a debug binary for LLDB.
./scripts/build-and-run.sh --debug

# Run macOS tests and benchmarks.
./scripts/run-tests.sh

# Build the app bundle and reproducible ZIP / tar.xz archives.
./scripts/build-app.sh --archive

# Build the themed arm64 DMG.
./scripts/build-dmg.sh arm64
```

Local macOS builds are ad-hoc signed by default; see [releasing.md](releasing.md)
for Developer ID signing and notarization.

### Linux (`Sources/xsComicLinux/`, output in `build/linux/`)

```sh
# Build the stripped release binary (build/linux/xscomic, -Oz -flto=thin).
./scripts/build-linux.sh --release

# Build an unoptimized debug binary with symbols (-O0 -g).
./scripts/build-linux.sh --debug

# Run the standalone Linux test and benchmark suite (191 assertions).
./scripts/run-linux-tests.sh

# Run the E2E rendered-pixel and X11 interaction smoke suite.
./scripts/docker-env.sh xvfb-run -a python3 Tests/xsComicLinuxTests/smoke.py build/linux/xscomic --x11

# Build and launch xsComic (interactive X11/Wayland or headless --screenshot).
./scripts/build-and-run-linux.sh [args...]

# Capture a headless PNG screenshot under Xvfb + Mesa software GL.
./scripts/build-and-run-linux.sh -- --screenshot build/shot.png path/to/comic.cbz

# Open a login shell inside the Debian 13 Slopjective-C SDK Docker image.
./scripts/docker-env.sh
```

Build outputs land in `build/` (gitignored) in disjoint platform directories:
macOS writes to `build/clang/` and `build/product/`, while Linux writes to
`build/objc3/`, `build/linux/` (retaining unstripped symbols at
`build/linux/xscomic.symbols`), and `build/linux-tests/`.

On Linux hosts with `objc3c` (or `/opt/objc3c/activate.sh`) installed,
`build-linux.sh`, `run-linux-tests.sh`, and `build-and-run-linux.sh` compile
and run natively. On macOS or hosts without the Slopjective-C SDK, they
automatically build `xscomic-objc3:dev` from [`../docker/Dockerfile`](../docker/Dockerfile)
via [`../scripts/docker-env.sh`](../scripts/docker-env.sh) and execute inside
the container.
