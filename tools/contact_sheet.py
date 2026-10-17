#!/usr/bin/env python3
"""Produce native-scale review boards from every logical asset, not source thumbnails."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from pixelize import quantize

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "tools/manifest.json").read_text())
font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
try:
    FONT = ImageFont.truetype(font_path, 12)
    TITLE = ImageFont.truetype(font_path, 22)
except OSError:
    FONT = ImageFont.load_default(size=12)
    TITLE = ImageFont.load_default(size=22)
COLS, CW, CH = 4, 336, 228
INK, IVORY, BRONZE = '#14151F', '#EDE3CC', '#A87B3D'


def board(assets, filename, title):
    rows = (len(assets) + COLS - 1) // COLS
    result = Image.new('RGBA', (COLS * CW + 16, rows * CH + 72), INK)
    draw = ImageDraw.Draw(result)
    draw.text((12, 8), title, font=TITLE, fill=IVORY)
    draw.text((12, 40), '48 цветов / nearest / игровые PNG / ' + str(len(assets)) + ' наборов', font=FONT, fill=BRONZE)
    for index, item in enumerate(assets):
        x, y = 8 + index % COLS * CW, 64 + index // COLS * CH
        draw.rectangle((x, y, x + CW - 8, y + CH - 8), outline=BRONZE)
        draw.text((x + 5, y + 3), f'{index+1:02d}  {item["title"]}', font=FONT, fill=IVORY)
        p = ROOT / item['file']
        if not p.exists():
            draw.text((x + 12, y + 65), 'В работе', font=FONT, fill=BRONZE)
            continue
        image = Image.open(p).convert('RGBA')
        if item['category'] == 'characters':
            result.alpha_composite(image, (x + 4, y + 24))
            portrait = Image.open(ROOT / item['portrait']).convert('RGBA')
            result.alpha_composite(portrait, (x + 190, y + 52))
            draw.text((x + 177, y + 158), '9 поз + портрет', font=FONT, fill=BRONZE)
            draw.text((x + 188, y + 176), '48x64 / 96x96', font=FONT, fill=BRONZE)
        else:
            px = x + (CW - 8 - image.width) // 2
            py = y + 24 + (192 - image.height) // 2
            result.alpha_composite(image, (px, py))
    quantize(result).save(ROOT / filename)
    print(filename)


board(manifest['assets'], 'docs/contact_overview.png', 'CINIS LAURI / Пепел лавра — 36 наборов')
for category in ['characters', 'locations', 'tiles', 'ui']:
    group = [a for a in manifest['assets'] if a['category'] == category]
    board(group, f'docs/contact_{category}.png', f'CINIS LAURI / {category}')

# Complete delivery board: every PNG including portraits and individual depth layers.
files = []
for item in manifest['assets']:
    files.append((item['file'], item['id']))
    if item.get('portrait'):
        files.append((item['portrait'], item['id'] + ' / portrait'))
    for depth, path in zip(['far', 'mid', 'near'], item.get('layers', [])):
        files.append((path, item['id'] + ' / ' + depth))
files.extend([('assets/ui/buttons.png', 'button states'), ('assets/ui/arrows.png', 'arrows')])
cols, width, height = 8, 168, 216
rows = (len(files) + cols - 1) // cols
result = Image.new('RGBA', (cols * width + 16, rows * height + 72), INK)
draw = ImageDraw.Draw(result)
draw.text((12, 8), 'CINIS LAURI / Все игровые PNG', font=TITLE, fill=IVORY)
draw.text((12, 40), f'{len(files)} файлов / 36 наборов / 48 цветов / nearest', font=FONT, fill=BRONZE)
for n, (path, title) in enumerate(files):
    x, y = 8 + n % cols * width, 64 + n // cols * height
    draw.rectangle((x, y, x + width - 8, y + height - 8), outline=BRONZE)
    draw.text((x + 4, y + 3), title[:21], font=FONT, fill=IVORY)
    p = ROOT / path
    if not p.exists():
        continue
    im = Image.open(p).convert('RGBA')
    if im.width > 152 or im.height > 188:
        im.thumbnail((152, 188), Image.Resampling.NEAREST)
    result.alpha_composite(im, (x + (width - 8 - im.width) // 2, y + 20 + (188 - im.height) // 2))
quantize(result).save(ROOT / 'docs/contact_sheet.png')
print('docs/contact_sheet.png — all', len(files), 'PNG files')
