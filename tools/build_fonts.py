#!/usr/bin/env python3
"""Rebuild the two bundled Golos Text instances from the preserved OFL source."""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_src/fonts/GolosText-Variable.ttf'


def main():
    for weight, name in [(450, 'GolosText-Reading.ttf'), (600, 'GolosText-Semibold.ttf')]:
        face = instantiateVariableFont(TTFont(SOURCE, recalcTimestamp=False), {'wght': weight}, inplace=True)
        target = ROOT / 'assets/fonts' / name
        face.save(target)
        print(f'{name}: weight {weight}, {target.stat().st_size} bytes')


if __name__ == '__main__':
    main()
