#!/usr/bin/env python3
"""Run actual Godot screenshots and input/layout checks at all requested sizes."""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SIZES = [(1280, 720), (1920, 1080), (2160, 1080), (2340, 1080),
         (2400, 1080), (2560, 1080), (800, 480)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--quick', action='store_true')
    parser.add_argument('--size', help='Run one size, e.g. 1280x720')
    parser.add_argument('--no-capture', action='store_true')
    args = parser.parse_args()
    sizes = [tuple(map(int, args.size.split('x')))] if args.size else SIZES
    results = []
    env = dict(os.environ, LIBGL_ALWAYS_SOFTWARE='1')
    for width, height in sizes:
        folder = ROOT / 'build/ui' / f'{width}x{height}'
        folder.mkdir(parents=True, exist_ok=True)
        command = ['godot', '--path', str(ROOT), '--audio-driver', 'Dummy',
                   '--resolution', f'{width}x{height}', '--position', '0,0',
                   '--script', 'tools/verify_ui.gd', '--', '--out=' + str(folder)]
        if args.quick:
            command.append('--quick')
        if args.no_capture:
            command.append('--no-capture')
        with (folder / 'godot.log').open('w') as log:
            result = subprocess.run(command, cwd=ROOT, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=600)
        report = folder / 'report.json'
        data = json.loads(report.read_text()) if report.exists() else {'errors': ['No report']}
        data['exit_code'] = result.returncode
        results.append(data)
        print(f'{width}x{height}: {len(data.get("frames", []))} frames, '
              f'{len(data["errors"])} errors, exit {result.returncode}', flush=True)
    (ROOT / 'docs/ui_validation.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
    return int(any(item['errors'] or item['exit_code'] for item in results))


if __name__ == '__main__':
    raise SystemExit(main())
