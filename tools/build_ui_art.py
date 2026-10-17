"""Original small Roman bevels; 12 px corners are stretched as nine-slice panels."""
from pathlib import Path
from PIL import Image, ImageDraw
from pixelize import quantize

ROOT = Path(__file__).resolve().parents[1]
for state in ['normal', 'hover', 'pressed', 'focus', 'disabled', 'hover_pressed', 'stone', 'parchment']:
    bg = '#202431' if state not in ('pressed', 'hover_pressed') else '#4a3026'
    edge = '#d9a441' if state in ('hover', 'focus') else '#a87b3d'
    if state == 'disabled':
        bg, edge = '#22232b', '#605c55'
    if state == 'parchment':
        bg = '#302a29'
    im = Image.new('RGBA', (48, 48), bg)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 47, 47), outline='#14151f', width=2)
    d.rectangle((2, 2, 45, 45), outline=edge, width=2)
    d.line((5, 5, 42, 5, 42, 42), fill='#76503b', width=2)
    d.line((5, 42, 5, 5, 42, 5), fill='#bfa87a')
    for x, y in [(5, 5), (36, 5), (5, 36), (36, 36)]:
        d.rectangle((x, y, x + 6, y + 6), fill='#14151f', outline=edge)
        d.rectangle((x + 2, y + 2, x + 4, y + 4), fill=edge)
    quantize(im).save(ROOT / f'assets/ui/roman_{state}.png', optimize=True)
