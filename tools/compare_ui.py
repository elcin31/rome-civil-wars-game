"""Contact sheet of actual pre-change and current Godot frames, never mockups."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
PAIRS=[('Главное меню','gameplay_menu','menu'),('Диалог','story_dialogue','dialogue'),('Лагерный расчёт','gameplay_hub','hub'),('Тактика','gameplay_tactical','tactical'),('Платформер','gameplay_platformer','platformer'),('Кампания','gameplay_campaign','campaign'),('Настройки','gameplay_settings','settings'),('Сохранения','gameplay_saves','saves'),('Журнал','story_log','log'),('Об игре','gameplay_credits','credits'),('Лицензии','gameplay_licenses','licenses')]
font=ImageFont.truetype(str(ROOT/'assets/fonts/Tiny5.ttf'),26)
board=Image.new('RGB',(1304,66+len(PAIRS)*400),'#14151f');draw=ImageDraw.Draw(board)
draw.text((16,12),'CINIS LAURI / ДО',font=font,fill='#d9a441');draw.text((670,12),'ПОСЛЕ / реальный Godot 1280×720',font=font,fill='#ede3cc')
for i,(name,before,after) in enumerate(PAIRS):
 y=66+i*400;draw.text((16,y),name,font=font,fill='#ede3cc')
 for col,file in enumerate([ROOT/f'docs/ui_before/{before}.png',ROOT/f'build/ui/1280x720/{after}.png']):
  im=Image.open(file).convert('RGB').resize((640,360),Image.Resampling.NEAREST);board.paste(im,(8+col*648,y+32))
board.save(ROOT/'docs/ui_before_after.png',optimize=True)
# A compact review preview; full sheet is retained for zooming.
board.crop((0,0,1304,66+3*400)).save(ROOT/'docs/ui_before_after_preview.png',optimize=True)
print('docs/ui_before_after.png')
