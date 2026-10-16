#!/usr/bin/env python3
"""Part II: same 24-color pipeline, four-emotion busts and 480x270 illustrations."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
from pixelize import quantize, remove_background, NEAREST

ROOT = Path(__file__).resolve().parents[1]
EMOTIONS = ['neutral', 'angry', 'worried', 'smile']


def process(asset):
    source = Image.open(ROOT / asset['source']).convert('RGBA')
    out = ROOT / asset['file']
    out.parent.mkdir(parents=True, exist_ok=True)
    if asset['category'] == 'emotions':
        source = remove_background(source)
        crops = []
        for i in range(4):
            x, y = i % 2, i // 2
            crop = source.crop((round(x * source.width / 2), round(y * source.height / 2), round((x+1)*source.width/2), round((y+1)*source.height/2)))
            if not crop.getbbox(): raise ValueError(f'Empty emotion: {asset["id"]} {i}')
            crops.append(crop.crop(crop.getbbox()))
        scale = min(92/max(c.width for c in crops), 94/max(c.height for c in crops))
        atlas = Image.new('RGBA', (192, 192))
        for i,crop in enumerate(crops):
            crop = crop.resize((max(1,round(crop.width*scale)),max(1,round(crop.height*scale))),NEAREST)
            cell = Image.new('RGBA',(96,96))
            cell.alpha_composite(crop, ((96-crop.width)//2,95-crop.height))
            cell=quantize(cell)
            cell.save(ROOT/f'assets/portraits/{asset["id"]}_{EMOTIONS[i]}.png')
            atlas.alpha_composite(cell, ((i%2)*96,(i//2)*96))
        atlas.save(out)
    else:
        image=ImageOps.fit(source,(480,270),method=NEAREST,centering=(.5,.5))
        image.putalpha(255)
        quantize(image).save(out)


def main():
    manifest=json.loads((ROOT/'tools/story_art_manifest.json').read_text())
    for asset in manifest['assets']:
        process(asset)
        print('OK', asset['id'])
    width,height=500,296
    board=Image.new('RGBA',(width*3+16,height*10+66),'#14151F')
    draw=ImageDraw.Draw(board)
    try:
        font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',13)
    except OSError:
        font=ImageFont.load_default(size=13)
    draw.text((10,10),'CINIS LAURI / Часть II / 30 исходных композиций / 24 цвета',font=font,fill='#EDE3CC')
    for i,asset in enumerate(manifest['assets']):
        x,y=8+i%3*width,48+i//3*height
        draw.rectangle((x,y,x+492,y+288),outline='#A87B3D')
        draw.text((x+5,y+3),asset['title'],font=font,fill='#EDE3CC')
        im=Image.open(ROOT/asset['file']).convert('RGBA')
        board.alpha_composite(im,(x+(492-im.width)//2,y+20+(270-im.height)//2))
    quantize(board).save(ROOT/'docs/contact_story.png')


if __name__=='__main__':main()
