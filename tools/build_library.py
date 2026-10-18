"""Build the searchable art catalog from the connected story, never a second story graph."""
import json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads((ROOT/p).read_text())
def write(p,d):(ROOT/p).write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
scenes={};chapters=[]
extra={'ch02_s02':'lucilla_kiln','ch03_s04':'aglaia_boat','ch03_s08':'serranus_desk','ch03_s16':'citizen_court','ch05_s06':'neria_clinic','ch06_s08':'vettius_road'}
epigraphs=['Тот, кто держит щит, тоже нуждается в руке.','Не всякая граница отмечена на земле.','Письмо переживает того, кто уверен в его итоге.','Известие приходит раньше понимания.','Назвать имя бывает опаснее, чем открыть дверь.','Общая мера начинается с чужой доли.','Берег видят не все, кого ждут.','Память не освобождает от следующего вопроса.']
assets={}
def register(file,title,chapter,**unlock):
 if file and file not in assets:assets[file]={'file':file,'title':title,'chapter':chapter,**unlock}
for number in range(1,9):
 p=f'story/chapters/ch{number:02}.json';c=read(p);c['epigraph']=epigraphs[number-1]
 baseline=json.loads(subprocess.check_output(['git','show',f'1d2ad5c:{p}'],cwd=ROOT));old={s['id']:s['illustration'] for s in baseline['scenes']}
 for scene in c['scenes']:
  if scene['id'] in extra:scene['illustration']='assets/new_story/'+extra[scene['id']]+'.png'
  if old.get(scene['id']) and old[scene['id']]!=scene['illustration']:
   scene['illustration_archive']=list(dict.fromkeys(scene.get('illustration_archive',[])+[old[scene['id']]]))
  scenes[scene['id']]=scene
  for file in [scene['illustration']]+[v['file'] for v in scene.get('illustration_variants',[])]+scene.get('illustration_archive',[]):
   register(file,scene['title']['ru'],number,scene=scene['id'])
 write(p,c);chapters.append({k:v for k,v in c.items() if k not in ['nodes','scenes']})
write('story/chapter_index.json',{'chapters':chapters})
beats=read('story/beats.json')['beats']
for file in sorted((ROOT/'story/cutscenes').glob('*.json')):
 data=json.loads(file.read_text());beat=next(b for b in beats if b.get('cutscene')==data['id'])
 for i,frame in enumerate(data['frames'],1):register(frame['image'],data['title']+f' · кадр {i}',data['chapter'],beat=beat['id'])
for entry in read('story/chronicle.json')['entries']:
 if entry['image']:register(entry['image'],entry['title'],entry['chapter'])
for entry in read('tools/wave_art_manifest.json')['assets']:
 if entry['file'] not in assets:register(entry['file'],{'menu':'Пепел лавра','mediterranean':'Средиземноморье'}.get(entry['id'],entry['id']),1,always=entry['id'] in ['menu','mediterranean'])
# Preserve all old standalone paintings in their existing archive category.
for entry in read('tools/final_art_manifest.json')['assets']:
 if entry['size'] in [[480,270],[640,360]]:
  register(entry['file'],'Архив · Картина '+str(len(assets)+1),8)
write('story/library_art.json',{'assets':list(assets.values())});print('Gallery paintings:',len(assets))
