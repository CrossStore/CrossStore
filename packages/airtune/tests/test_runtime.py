#!/usr/bin/env python3
"""Exercise AirTune through CrossMux's real sandbox and canvas geometry."""
from pathlib import Path
import os
import subprocess
import tempfile

PACKAGE = Path(__file__).resolve().parents[1]
FIRMWARE = Path(os.environ.get('CROSSMUX_ROOT', PACKAGE.parents[2] / 'crossmux'))
EXCLUDED = {'lua.c', 'luac.c', 'linit.c', 'liolib.c', 'loslib.c', 'loadlib.c', 'ldblib.c', 'lcorolib.c'}

def main():
    lua = FIRMWARE / 'lib/CrossStoreLua/src'
    runtime = FIRMWARE / 'lib/CrossStoreRuntime'
    with tempfile.TemporaryDirectory(prefix='airtune-test-') as temp:
        build = Path(temp)
        objects = []
        for source in sorted(lua.glob('*.c')):
            if source.name in EXCLUDED:
                continue
            obj = build / (source.stem + '.o')
            subprocess.run(['cc', '-O1', '-DLUAI_MAXCCALLS=50', '-c', str(source), '-o', str(obj)], check=True)
            objects.append(str(obj))
        binary = build / 'airtune-test'
        subprocess.run(['c++', '-std=c++17', '-O1', '-fno-exceptions', '-Wall', '-Wextra', '-Werror',
                        '-I'+str(lua), '-I'+str(runtime), str(runtime/'CrossStoreRuntime.cpp'),
                        str(PACKAGE/'tests/AirTuneTest.cpp'), *objects, '-o', str(binary)], check=True)
        subprocess.run([str(binary), str(PACKAGE/'main.lua')], check=True, timeout=20)

if __name__ == '__main__':
    main()
