"""Insert one authored interlude and optional, reachable delivery quests in its chapter."""
import json,sys,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
number=int(sys.argv[1]);title=sys.argv[2];year=sys.argv[3];source=Path(sys.argv[4]);jobs=json.loads(sys.argv[5])
def read(p):return json.loads((ROOT/p).read_text())
def write(p,d):(ROOT/p).write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
chapter=read(f'story/chapters/ch{number:02}.json');scene=f'ch{number:02}_interlude'
if any(s['id']==scene for s in chapter['scenes']):raise SystemExit('Interlude already inserted')
paragraphs=[p.strip() for p in source.read_text().split('\n\n') if p.strip()]
words=len(re.findall(r"[А-Яа-яЁёA-Za-z0-9]+(?:[-’'][А-Яа-яЁёA-Za-z0-9]+)*",' '.join(paragraphs)))
assert 700<=words<=1000,(number,words)
# Keep all cross-chapter branches intact: they share the same established target.
if number<8:
 targets=[]
 for n in chapter['nodes']:
  for field in ['next']:
   if n.get(field,'').startswith('ch') and not n[field].startswith(f'ch{number:02}'):
    targets.append(n[field]);n[field]=scene+'_n01'
  for branch in n.get('branches',[])+n.get('choices',[]):
   if branch.get('goto','').startswith('ch') and not branch['goto'].startswith(f'ch{number:02}'):
    targets.append(branch['goto']);branch['goto']=scene+'_n01'
 assert len(set(targets))==1,targets
 tail=targets[0]
else:
 tail='ch08_s04_n01'
 for n in chapter['nodes']:
  if n.get('next')==tail:n['next']=scene+'_n01'
chapter['scenes'].append({'id':scene,'title':{'ru':title,'en':''},'year':year,'entry':scene+'_n01','illustration':f'assets/new_story/interlude{number:02}.png','optional':False,'route':'shared','prose_status':'complete','historical_anchors':[],'interlude':True,'word_count':words})
for i,text in enumerate(paragraphs,1):
 chapter['nodes'].append({'id':scene+f'_n{i:02}','scene':scene,'kind':'dialogue','speaker':'narrator','portrait':'narrator_neutral','text':{'ru':text,'en':''},'next':scene+f'_n{i+1:02}' if i<len(paragraphs) else (f'ch{number:02}_job01_optional_n90' if jobs else tail)})
beats=read('story/beats.json')['beats']
for i,job in enumerate(jobs,1):
 ident=f'ch{number:02}_job{i:02}';next_job=f'ch{number:02}_job{i+1:02}_optional_n90' if i<len(jobs) else tail
 chapter['scenes'].append({'id':ident,'title':{'ru':job['title'],'en':''},'year':year,'entry':ident+'_optional_n90','illustration':f'assets/new_story/interlude{number:02}.png','optional':True,'route':'shared','prose_status':'complete','historical_anchors':[],'side_quest':True})
 chapter['nodes'] += [
 {'id':ident+'_optional_n90','scene':ident,'kind':'choice','speaker':'narrator','portrait':'','text':{'ru':'','en':''},'choices':[{'id':ident+'_visit','text':{'ru':'Помочь: '+job['title'],'en':''},'goto':ident+'_n01'},{'id':ident+'_skip','text':{'ru':'Продолжить дорогу','en':''},'goto':next_job}]},
 {'id':ident+'_n01','scene':ident,'kind':'dialogue','speaker':job.get('speaker','serranus'),'portrait':'','text':{'ru':job['intro'],'en':''},'next':ident+'_n75'},
 {'id':ident+'_n75','scene':ident,'kind':'beat','speaker':'narrator','portrait':'','text':{'ru':job['objective'],'en':''},'beat':'beat_'+ident,'next':ident+'_n91'},
 {'id':ident+'_n91','scene':ident,'kind':'dialogue','speaker':job.get('speaker','serranus'),'portrait':'','text':{'ru':job['outro'],'en':''},'rep':{'citizens':1},'next':next_job}]
 location={1:'roman_camp',2:'roman_forum',3:'alexandria',4:'roman_forum',5:'rome_night',6:'pharsalus',7:'actium',8:'roman_forum'}[number]
 beats.append({'id':'beat_'+ident,'scene':ident,'type':'rpg','title':{'ru':job['title'],'en':''},'objective':{'ru':job['objective'],'en':''},'place':{'ru':title,'en':''},'victory':[{'ru':job['objective'],'en':''}],'node':ident+'_n75','location':location,'tiles':'camp_fields' if number in [1,6,7] else 'city','difficulty':min(number+1,10),'variant':i+number,'goal':'exit','condition':'','implementation':'playable','hub_dialogue':{'intro':{'ru':job['intro'],'en':''},'request':{'ru':job['objective'],'en':''},'collected':{'ru':'Груз у вас. Передайте его получателю у дороги.','en':''},'delivered':{'ru':job['outro'],'en':''},'unassigned':{'ru':'Сначала уточните поручение у писца.','en':''},'waiting':{'ru':'Получатель ждёт груз; его место отмечено стрелкой.','en':''}}})
write(f'story/chapters/ch{number:02}.json',chapter);write('story/beats.json',{'beats':beats})
print(f'{scene}: {words} words, {len(jobs)} optional quests')
