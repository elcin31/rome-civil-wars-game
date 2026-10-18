"""Contact sheet from actual touches through the camp quest (capture_wave1.gd)."""
from pathlib import Path
import argparse
import re
import subprocess
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ITEMS = [
    ('take', 'Приоритет ящика · «Взять»'),
    ('delivery', 'Припасы взяты · доставка'),
    ('completed', 'Поручение выполнено'),
    ('debug', 'Области взаимодействия'),
    ('hint', 'Что делать дальше?'),
    ('journal', 'Журнал · текущая цель'),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--capture', action='store_true')
    args = parser.parse_args()
    if args.capture:
        (ROOT / 'build/wave1').mkdir(parents=True, exist_ok=True)
        result = subprocess.run(
            [sys.executable, str(ROOT / 'tools/run_display.py'), 'godot', '--path', str(ROOT),
             '--audio-driver', 'Dummy', '--resolution', '1280x720',
             '--script', 'tools/capture_wave1.gd'], cwd=ROOT, text=True,
             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        (ROOT / 'build/wave1/godot.log').write_text(result.stdout)
        if result.returncode or re.search(r'(^|\n)(SCRIPT ERROR:|ERROR:)', result.stdout):
            print(result.stdout)
            raise SystemExit('Quest capture failed; inspect build/wave1/godot.log')
    width, height = 480, 270
    sheet = Image.new('RGB', (3 * width, 2 * (height + 46) + 38), '#14151f')
    draw = ImageDraw.Draw(sheet)
    face = ImageFont.truetype(str(ROOT / 'assets/fonts/GolosText-Semibold.ttf'), 20)
    small = ImageFont.truetype(str(ROOT / 'assets/fonts/GolosText-Reading.ttf'), 16)
    draw.text((12, 8), 'CINIS LAURI 0.4.2 · волна 1 · реальный Godot-рендерер',
              font=face, fill='#d9a441')
    for index, (filename, caption) in enumerate(ITEMS):
        picture = Image.open(ROOT / 'build/wave1' / (filename + '.png')).convert('RGB')
        picture = picture.resize((width, height), Image.Resampling.NEAREST)
        x = (index % 3) * width
        y = 38 + (index // 3) * (height + 46)
        sheet.paste(picture, (x, y))
        draw.text((x + 10, y + height + 10), caption, font=small, fill='#ede3cc')
    sheet.save(ROOT / 'docs/contact_wave1.png')
    print('docs/contact_wave1.png')


if __name__ == '__main__':
    main()
