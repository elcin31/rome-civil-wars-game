#!/usr/bin/env python3
"""Count distinct additions, validate palette/atlases and reject silent duplicates."""
from collections import Counter
import hashlib
import json
from pathlib import Path
from PIL import Image
from pixelize import palette_colors

ROOT = Path(__file__).resolve().parents[1]


def main():
    manifest = json.loads((ROOT / 'tools/refresh_art_manifest.json').read_text())
    assets = manifest['assets']
    counts = Counter(a['kind'] for a in assets)
    errors, hashes = [], {}
    palette = set(palette_colors())
    for kind, minimum in [('story', 20), ('location', 12), ('npc_sheet', 10), ('chapter_card', 8)]:
        if counts[kind] < minimum:
            errors.append(f'{kind}: {counts[kind]} < {minimum}')
    for asset in assets:
        path = ROOT / asset['file']
        if not path.exists() or not (ROOT / asset['source']).exists():
            errors.append(asset['id'] + ': missing output/source')
            continue
        image = Image.open(path).convert('RGBA')
        if image.size != tuple(asset['size']) or not image.getbbox():
            errors.append(asset['id'] + ': bad dimensions/empty image')
        visible = {(r, g, b) for r, g, b, a in image.getdata() if a}
        if visible - palette or set(image.getchannel('A').getdata()) - {0, 255}:
            errors.append(asset['id'] + ': palette/alpha violation')
        digest = hashlib.sha256(image.tobytes()).hexdigest()
        if digest in hashes:
            errors.append(asset['id'] + ': duplicates ' + hashes[digest])
        hashes[digest] = asset['id']
        imported = path.with_suffix('.png.import')
        if not imported.exists() or 'mipmaps/generate=false' not in imported.read_text():
            errors.append(asset['id'] + ': missing nearest/lossless import')
        if asset['kind'] == 'npc_sheet':
            for pose in range(9):
                frame = image.crop((pose % 3 * 64, pose // 3 * 96, pose % 3 * 64 + 64, pose // 3 * 96 + 96))
                if not frame.getbbox():
                    errors.append(asset['id'] + ': empty pose')
    report = {'distinct_new_compositions': len(hashes), 'categories': dict(counts), 'palette_colors': len(palette), 'errors': errors}
    (ROOT / 'docs/refresh_art_validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('REFRESH ART:', report)
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
