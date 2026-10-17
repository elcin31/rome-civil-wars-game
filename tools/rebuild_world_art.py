#!/usr/bin/env python3
"""Upgrade legacy world composites from retained full-size sources; no new generation."""
import json
from pathlib import Path
from PIL import Image
from pixelize import parallax
from build_refresh_art import landscape

ROOT = Path(__file__).resolve().parents[1]
base = json.loads((ROOT / 'tools/manifest.json').read_text())
for entry in base['assets']:
    if entry['category'] != 'locations':
        continue
    entry['size'] = [640, 360]
    entry['layer_size'] = [640, 360]
    source = Image.open(ROOT / entry['source']).convert('RGBA')
    parallax(source, ROOT / entry['file'], entry.get('layer_boxes'), entry.get('layer_offsets_y', [0, 0, 0]), (640, 360))
(ROOT / 'tools/manifest.json').write_text(json.dumps(base, ensure_ascii=False, indent=2) + '\n')
manifest = json.loads((ROOT / 'tools/story_art_manifest.json').read_text())
for entry in manifest['assets']:
    if entry['category'] == 'emotions':
        continue
    landscape(Image.open(ROOT / entry['source']).convert('RGBA')).save(ROOT / entry['file'], optimize=True)
    entry['size'] = [640, 360]
(ROOT / 'tools/story_art_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
manifest = json.loads((ROOT / 'tools/final_art_manifest.json').read_text())
for entry in manifest['assets']:
    if 'cell' not in entry or entry['id'] == 'banner':
        continue
    source = Image.open(ROOT / entry['source']).convert('RGBA')
    x, y = entry['cell']
    source = source.crop((x * source.width // 2, y * source.height // 4, (x + 1) * source.width // 2, (y + 1) * source.height // 4))
    landscape(source).save(ROOT / entry['file'], optimize=True)
    entry['size'] = [640, 360]
    if entry['id'] == 'menu':
        entry['refresh_source'] = 'art_src/refresh/menu_new.png'
        landscape(Image.open(ROOT / entry['refresh_source']).convert('RGBA')).save(ROOT / entry['file'], optimize=True)
(ROOT / 'tools/final_art_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print('WORLD REBUILD: 12 backgrounds + 36 layers, 20 story/endings, 7 presentation screens')
