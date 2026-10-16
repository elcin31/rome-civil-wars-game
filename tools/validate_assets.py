#!/usr/bin/env python3
"""Validate the actual deliverable: palette, geometry, alpha, sources, imports and counts."""
import json
from pathlib import Path
from PIL import Image
from pixelize import palette_colors

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'tools/manifest.json').read_text())
palette = set(palette_colors())
errors = []
report = {'logical_assets': len(manifest['assets']), 'palette_colors': len(palette), 'pngs': [], 'errors': errors}
if len(manifest['assets']) < 36:
    errors.append('Fewer than 36 logical assets')
if len(palette) > 24:
    errors.append('More than 24 colors')


def check(path, size, transparency=False, opaque=False):
    path = ROOT / path
    if not path.exists():
        errors.append(f'Missing {path.relative_to(ROOT)}')
        return
    image = Image.open(path).convert('RGBA')
    unique = set(image.getdata())
    visible = {(r, g, b) for r, g, b, a in unique if a}
    alphas = {a for r, g, b, a in unique}
    if image.size != tuple(size):
        errors.append(f'{path.name}: size {image.size} != {size}')
    if visible - palette:
        errors.append(f'{path.name}: colors outside palette')
    if not alphas <= {0, 255}:
        errors.append(f'{path.name}: non-binary alpha')
    if transparency and not {0, 255} <= alphas:
        errors.append(f'{path.name}: transparent sprite/layer missing alpha or contents')
    if opaque and alphas != {255}:
        errors.append(f'{path.name}: far layer/composite is not opaque')
    if not image.getbbox():
        errors.append(f'{path.name}: blank image')
    report['pngs'].append({'file': str(path.relative_to(ROOT)), 'size': list(image.size), 'visible_colors': len(visible), 'alpha': sorted(alphas)})
    imp = path.with_suffix(path.suffix + '.import')
    if not imp.exists() or 'mipmaps/generate=false' not in imp.read_text():
        errors.append(f'{path.name}: missing explicit no-mipmap Godot import')


for asset in manifest['assets']:
    if not (ROOT / asset['source']).is_file():
        errors.append(f'Missing generated source: {asset["source"]}')
    check(asset['file'], asset['size'], transparency=asset['category'] == 'characters', opaque=asset['category'] == 'locations')
    if asset['category'] == 'characters':
        check(asset['portrait'], (96, 96), transparency=True)
        path = ROOT / asset['file']
        if path.exists():
            image = Image.open(path).convert('RGBA')
            for n in range(9):
                cell = image.crop((n % 3 * 48, n // 3 * 64, n % 3 * 48 + 48, n // 3 * 64 + 64))
                box = cell.getbbox()
                if not box or box[0] < 1 or box[1] < 1 or box[2] > 47 or box[3] > 63:
                    errors.append(f'{asset["id"]} pose {n}: blank or touches frame boundary')
        if not path.with_suffix('.tres').exists():
            errors.append(f'{asset["id"]}: missing SpriteFrames')
    for n, layer in enumerate(asset.get('layers', [])):
        check(layer, (320, 180), transparency=n > 0, opaque=n == 0)
    if asset['category'] == 'tiles' and not (ROOT / asset['file']).with_suffix('.tres').exists():
        errors.append(f'{asset["id"]}: missing TileSet')
for extra, size in [('assets/ui/buttons.png', (64, 80)), ('assets/ui/arrows.png', (32, 16))]:
    check(extra, size, transparency=True)
report['png_count'] = len(report['pngs'])
(ROOT / 'docs/validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(f"{report['logical_assets']} logical assets; {report['png_count']} PNGs; {len(palette)} palette colors; {len(errors)} errors")
for error in errors:
    print('ERROR:', error)
raise SystemExit(bool(errors))
