#!/usr/bin/env python3
"""Compare actual Godot screenshots of the old and new Cyrillic typography."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
PAIRS = [('Главное меню', 'menu'), ('Диалог', 'dialogue'), ('Лагерное поручение', 'hub')]


def main():
    font = ImageFont.truetype(str(ROOT / 'assets/fonts/GolosText-Semibold.ttf'), 26)
    board = Image.new('RGB', (1304, 66 + len(PAIRS) * 406), '#14151f')
    draw = ImageDraw.Draw(board)
    draw.text((16, 12), 'ДО / Tiny5', font=font, fill='#d9a441')
    draw.text((670, 12), 'ПОСЛЕ / Golos Text + PT Serif', font=font, fill='#ede3cc')
    for index, (caption, name) in enumerate(PAIRS):
        y = 66 + index * 406
        draw.text((16, y), caption, font=font, fill='#ede3cc')
        before = ROOT / f'docs/typography_before/{name}.png'
        after = ROOT / ('docs/android_hub.png' if name == 'hub' else f'build/ui/1280x720/{name}.png')
        for column, path in enumerate([before, after]):
            picture = Image.open(path).convert('RGB').resize((640, 360), Image.Resampling.LANCZOS)
            board.paste(picture, (8 + column * 648, y + 36))
    board.save(ROOT / 'docs/typography_before_after.png', optimize=True)
    print('docs/typography_before_after.png')


if __name__ == '__main__':
    main()
