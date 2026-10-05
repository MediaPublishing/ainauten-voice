#!/usr/bin/env python3
"""Check arm64 main-executable dependencies without launching the app.

Code signatures alone do not prove that dyld can find bundled libraries.
System libraries may live only in the dyld cache; non-system dependencies must
resolve inside the app using its actual load commands, including inherited rpaths.
"""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess


def load_commands(binary):
    libraries = subprocess.check_output(['otool', '-arch', 'arm64', '-L', str(binary)], text=True)
    dependencies = [line.strip().split(' (compatibility version', 1)[0]
                    for line in libraries.splitlines() if line.startswith('\t')]
    commands = subprocess.check_output(['otool', '-arch', 'arm64', '-l', str(binary)], text=True).splitlines()
    rpaths = [commands[i + 2].strip().removeprefix('path ').rsplit(' (offset ', 1)[0]
              for i, line in enumerate(commands) if line.strip() == 'cmd LC_RPATH']
    return dependencies, rpaths


def verify_runtime(app):
    app = Path(app).resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    macos = app / 'Contents/MacOS'
    executable = macos / info['CFBundleExecutable']
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError('App executable is missing or not executable')
    # Internal UI previews use a shell launcher around the actual debug binary.
    with executable.open('rb') as stream:
        launcher = stream.read(2) == b'#!'
    if launcher:
        executable = macos / 'VoiceWispr'
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise ValueError('Preview runtime executable is missing')
    seen = set()

    def expand(path, loader):
        for prefix, directory in [('@executable_path', executable.parent), ('@loader_path', loader.parent)]:
            if path == prefix or path.startswith(prefix + '/'):
                return directory / path[len(prefix):].lstrip('/')
        return Path(path) if path.startswith('/') else None

    def visit(binary, inherited):
        binary = binary.resolve()
        if not binary.is_relative_to(app):
            raise ValueError('Runtime executable is outside the app bundle')
        if binary in seen:
            return
        seen.add(binary)
        dependencies, rpaths = load_commands(binary)
        search = [candidate for path in rpaths if (candidate := expand(path, binary)) is not None] + inherited
        for dependency in dependencies:
            if dependency.startswith(('/usr/lib/', '/System/Library/')):
                continue
            if dependency.startswith('@rpath/'):
                candidates = [directory / dependency[len('@rpath/'):] for directory in search]
            else:
                candidate = expand(dependency, binary)
                candidates = [candidate] if candidate is not None else []
            resolved = next((candidate.resolve() for candidate in candidates
                             if candidate.is_file() and candidate.resolve().is_relative_to(app)), None)
            if resolved is None:
                raise ValueError(f'{binary.relative_to(app)} cannot resolve bundled dependency {dependency}')
            visit(resolved, search)

    visit(executable, [])
    return len(seen)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    try:
        count = verify_runtime(args.app)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'BUNDLE FAIL: {error}\n')
    print(f'BUNDLE PASS: {count} linked arm64 binaries resolve within {args.app.name}')
