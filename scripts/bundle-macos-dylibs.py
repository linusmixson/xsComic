#!/usr/bin/env python3
"""Copy the arm64 Homebrew libraries linked by xsComic into its app bundle."""

import argparse
from collections import deque
from pathlib import Path
import shutil
import subprocess


def run(*args):
    return subprocess.check_output(args, text=True)


def dylibs(binary):
    return [line.strip().split(" (compatibility version", 1)[0]
            for line in run("otool", "-L", binary).splitlines()[1:] if line.startswith("\t")]


def rpaths(binary):
    for line in run("otool", "-l", binary).splitlines():
        line = line.strip()
        if line.startswith("path ") and " (offset " in line:
            yield line.removeprefix("path ").rsplit(" (offset ", 1)[0]


def system_library(name):
    return name.startswith(("/usr/lib/", "/System/Library/"))


def expand(name, origin, executable):
    for prefix, directory in (("@loader_path/", origin.parent),
                              ("@executable_path/", executable.parent)):
        if name.startswith(prefix):
            return directory / name.removeprefix(prefix)
    return Path(name)


def resolve(name, source, executable, brew, executable_rpaths):
    if name.startswith("@rpath/"):
        suffix = name.removeprefix("@rpath/")
        candidates = [expand(path, source, executable) / suffix for path in rpaths(source)]
        candidates.extend(expand(path, executable, executable) / suffix for path in executable_rpaths)
        candidates.append(brew / "lib" / suffix)
    else:
        candidates = [expand(name, source, executable)]
    for candidate in candidates:
        if candidate.is_file():
            path = candidate.resolve()
            if path.is_relative_to(brew):
                return path
    raise ValueError(f"{source}: cannot resolve Homebrew dependency {name}")


def bundle(executable, brew):
    if any(Path(name).name.startswith(("libobjc.", "libobjc3darwin."))
           for name in dylibs(executable)):
        raise ValueError("The reader must link the owned Objective-C 3 runtime statically")
    frameworks = executable.parent.parent / "Frameworks"
    frameworks.mkdir()
    executable_rpaths = tuple(rpaths(executable))
    pending = deque([(executable, executable)])
    bundled = {}

    def include(library, name):
        destination = frameworks / name
        prior = bundled.get(name)
        if prior is None:
            if run("lipo", "-archs", library).strip() != "arm64":
                raise ValueError(f"{library} is not an arm64 Homebrew dylib")
            shutil.copy2(library, destination)
            destination.chmod(0o755)
            bundled[name] = library
            pending.append((library, destination))
        elif prior != library:
            raise ValueError(f"Conflicting library install names for {name}")
        return destination

    # Homebrew's SDL2 compatibility library opens SDL3 by name at runtime.
    sdl3 = (brew / "opt/sdl3/lib/libSDL3.dylib").resolve(strict=True)
    if not sdl3.is_relative_to(brew):
        raise ValueError("SDL3 is outside the Homebrew prefix")
    include(sdl3, "libSDL3.dylib")

    while pending:
        source, target = pending.popleft()
        # otool lists a dylib's own install name before its dependencies.
        dependencies = dylibs(source)[0 if source == executable else 1:]
        arguments = []
        if source != executable:
            arguments += ["-id", f"@rpath/{target.name}"]
        for name in dependencies:
            if system_library(name):
                continue
            library = resolve(name, source, executable, brew, executable_rpaths)
            destination = include(library, Path(name).name)
            relative = "../Frameworks/" if target == executable else ""
            arguments += ["-change", name, f"@loader_path/{relative}{destination.name}"]
        for path in dict.fromkeys(rpaths(source)):
            arguments += ["-delete_rpath", path]
        if arguments:
            run("install_name_tool", *arguments, target)


def verify(executable):
    contents = executable.parent.parent
    libraries = sorted((contents / "Frameworks").glob("*.dylib"))
    if not any(library.name == "libSDL3.dylib" for library in libraries):
        raise ValueError("The application is missing SDL3")
    for binary in [executable, *libraries]:
        if run("lipo", "-archs", binary).strip() != "arm64":
            raise ValueError(f"{binary} is not arm64")
        if tuple(rpaths(binary)):
            raise ValueError(f"{binary} has a runtime search path outside its own imports")
        for name in dylibs(binary)[0 if binary == executable else 1:]:
            if system_library(name):
                if binary == executable and Path(name).name.startswith("libobjc."):
                    raise ValueError("The reader linked the system Objective-C runtime")
                continue
            if (not name.startswith("@loader_path/") or
                    not expand(name, binary, executable).resolve().is_relative_to(contents / "Frameworks") or
                    not expand(name, binary, executable).is_file()):
                raise ValueError(f"{binary} has an unbundled dependency {name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("brew_prefix", type=Path, nargs="?")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    try:
        executable = args.executable.resolve(strict=True)
        if args.verify:
            verify(executable)
        elif args.brew_prefix is not None:
            bundle(executable, args.brew_prefix.resolve(strict=True))
        else:
            parser.error("provide the Homebrew prefix to assemble the bundle")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"xscomic: {error}\n")
