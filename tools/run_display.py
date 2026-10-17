#!/usr/bin/env python3
"""Own the software X server for the entire check, including process cleanup."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


def main():
    if shutil.which('xvfb-run'):
        return subprocess.call(['xvfb-run', '-a', *sys.argv[1:]], env=dict(os.environ, LIBGL_ALWAYS_SOFTWARE='1'))
    server = Path('/usr/lib/xorg/Xorg')
    config = Path('/etc/X11/xorg.conf')
    if not server.exists() or not config.exists():
        raise SystemExit('Install xvfb and run with tools/run_display.py')
    number = 100 + os.getpid() % 500
    display = f':{number}'
    env = dict(os.environ, DISPLAY=display, LIBGL_ALWAYS_SOFTWARE='1')
    Path('build').mkdir(exist_ok=True)
    with Path('build/xorg.log').open('w') as log:
        process = subprocess.Popen([str(server), display, '-config', str(config), '-logfile',
                                    str(Path('build/xorg-server.log').resolve()), '-nolisten', 'tcp', '-noreset'],
                                   stdout=log, stderr=log)
        try:
            for _ in range(100):
                if Path(f'/tmp/.X11-unix/X{number}').exists():
                    break
                if process.poll() is not None:
                    raise RuntimeError('Xorg failed; see build/xorg.log')
                time.sleep(0.05)
            return subprocess.call(sys.argv[1:], env=env)
        finally:
            process.terminate()
            process.wait(timeout=10)


if __name__ == '__main__':
    raise SystemExit(main())
