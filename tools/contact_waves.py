"""Review sheets from actual rendered UI frames, separate from the art-source contact."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
FOLDER=ROOT/'build/ui/1280x720'
GROUPS={2:['cicero_frame_00','forest_frame_03','alesia_frame_06','brundisium_frame_03','pharsalus_frame_04','alexandria_frame_00'],3:['ides_frame_00','proscriptions_frame_04','philippi_frame_00','perusia_frame_03','actium_frame_06','ch08_s05'],4:['chronicle','fate','locked_gallery','campaign','comfort','recap']}
font=ImageFont.truetype(str(ROOT/'assets/fonts/GolosText-Reading.ttf'),18)
for wave,names in GROUPS.items():
    sheet=Image.new('RGB',(960,900),'#14151f');draw=ImageDraw.Draw(sheet)
    for i,name in enumerate(names):
        path=FOLDER/(name+'.png');assert path.exists(),path
        picture=Image.open(path).convert('RGB').resize((480,270),Image.Resampling.NEAREST)
        x,y=(i%2)*480,(i//2)*300;sheet.paste(picture,(x,y));draw.text((x+8,y+275),name,font=font,fill='#ede3cc')
    sheet.save(ROOT/f'docs/contact_wave{wave}.png')
    print('Captured review sheet:',wave)
