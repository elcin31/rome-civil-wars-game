"""Slice unique generated compositions and apply the shared no-dither pixel pipeline."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image,ImageOps,ImageDraw
from pixelize import dominant_resize,palette_colors
ROOT=Path(__file__).resolve().parents[1]

def build():
    entries=[]
    for meta in sorted((ROOT/'art_src/waves').glob('*.json')):
        spec=json.loads(meta.read_text());source=ROOT/spec['source']
        if not source.exists():continue
        original=Image.open(source).convert('RGB');columns,rows=spec['layout']
        for i in range(spec['unique_compositions']):
            x,y=i%columns,i//columns
            box=(round(x*original.width/columns),round(y*original.height/rows),round((x+1)*original.width/columns),round((y+1)*original.height/rows))
            crop=original.crop(box)
            crop=ImageOps.fit(crop,(480,270),method=Image.Resampling.NEAREST)
            category=spec.get('category','cs');name=spec.get('names',[])
            ident=name[i] if name else f'{spec["id"]}_{i+1:02}'
            dest=ROOT/f'assets/{category}/{ident}.png';dest.parent.mkdir(parents=True,exist_ok=True)
            pixels=dominant_resize(crop,(480,270)).convert('RGB')
            palette=Image.new('P',(1,1));colors=palette_colors();palette.putpalette([v for c in colors for v in c]+list(colors[0])*(256-len(colors)))
            indexed=pixels.quantize(palette=palette,dither=Image.Dither.NONE);indexed.save(dest,optimize=True)
            entries.append({'id':ident,'file':str(dest.relative_to(ROOT)),'source':spec['source'],'source_box':box,'size':[480,270],'category':category,'composition_sha256':hashlib.sha256(original.crop(box).tobytes()).hexdigest()})
    report={'generator':'image_gen','pipeline':'480x270 shared48-color palette, no dithering, nearest, singleton cleanup, indexed PNG','compositions':len(entries),'assets':entries}
    (ROOT/'tools/wave_art_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    if entries:
        thumb=Image.new('RGB',(960,160*((len(entries)+3)//4)), '#14151f');draw=ImageDraw.Draw(thumb)
        for i,e in enumerate(entries):
            x,y=i%4*240,i//4*160;im=Image.open(ROOT/e['file']).convert('RGB').resize((240,135),Image.Resampling.NEAREST);thumb.paste(im,(x,y));draw.text((x+4,y+138),e['id'],fill='#ede3cc')
        thumb.save(ROOT/'docs/contact_new_art.png')
    print('Unique new compositions:',len(entries))

if __name__=='__main__':build()
