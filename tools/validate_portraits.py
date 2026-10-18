#!/usr/bin/env python3
"""Fail for an unillustrated speaker, absent emotion, empty frame or invalid font."""
import hashlib
import json
from pathlib import Path
from PIL import Image
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]


def main():
    characters = json.loads((ROOT / 'story/characters.json').read_text())['characters']
    portraits = json.loads((ROOT / 'story/portraits.json').read_text())['portraits']
    errors, speakers, nodes = [], set(), []

    def walk(value):
        if isinstance(value, dict):
            if 'speaker' in value:
                speakers.add(value['speaker'])
                nodes.append(value)
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    for path in (ROOT / 'story').rglob('*.json'):
        walk(json.loads(path.read_text()))
    for node in nodes:
        speaker = node['speaker']
        ident = node.get('portrait') or characters.get(speaker, {}).get('default_portrait')
        if not ident or ident not in portraits:
            errors.append(f'{node.get("id", "scene")}: no portrait for {speaker}')
        elif speaker not in ('history', 'narrator') and portraits[ident].get('character') != speaker:
            errors.append(f'{node.get("id")}: portrait belongs to another speaker')
    for speaker in sorted(speakers):
        hashes = set()
        for emotion in ['neutral', 'angry', 'worried', 'smile']:
            ident = speaker + '_' + emotion
            data = portraits.get(ident)
            if not data or not (ROOT / data['file']).is_file():
                errors.append(f'{speaker}: missing {emotion}')
                continue
            image = Image.open(ROOT / data['file']).convert('RGBA')
            if image.size != (128, 128) or not image.getbbox() or len(image.getcolors(128 * 128)) < 8:
                errors.append(f'{ident}: empty or invalid 128x128 image')
            hashes.add(hashlib.sha256(image.tobytes()).hexdigest())
        if len(hashes) != 4:
            errors.append(f'{speaker}: four distinct emotions required')
        sheet = ROOT / f'assets/portraits/{speaker}_emotions.png'
        if not sheet.exists() or Image.open(sheet).size != (256, 256):
            errors.append(f'{speaker}: missing four-emotion sheet')
    checked_fonts = ['GolosText-Reading.ttf', 'GolosText-Semibold.ttf', 'PTSerif-Bold.ttf']
    missing = []
    alphabet = 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя0123456789−+…—«»'
    for name in checked_fonts:
        with TTFont(ROOT / 'assets/fonts' / name) as font:
            missing_here = [c for c in alphabet if ord(c) not in font.getBestCmap()]
        missing.extend(missing_here)
        if missing_here:
            errors.append(name + ' missing glyphs: ' + ''.join(missing_here))
    report = {'speakers': sorted(speakers), 'checked_nodes': len(nodes), 'errors': errors,
              'portrait_size': [128, 128], 'font_cyrillic_complete': not missing,
              'checked_fonts': checked_fonts}
    (ROOT / 'docs/portrait_validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f'PORTRAITS: {len(speakers)} speakers, {len(nodes)} nodes, {len(errors)} errors')
    for error in errors:
        print('ERROR:', error)
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
