"""Strict acceptance checks for the current PDF: additions counted over the old game."""
from collections import Counter
import hashlib,json
from pathlib import Path
from PIL import Image
from story_model import Model,WORD,read
from pixelize import palette_colors
ROOT=Path(__file__).resolve().parents[1]

def main():
    model=Model();beats=read('story/beats.json')['beats'];types=Counter(b['type'] for b in beats)
    assert set(types)<={'cutscene','soft','rpg'},types
    assert types['rpg']>=20 and types['cutscene']>=12
    interludes=[s for s in model.scenes.values() if s.get('interlude')]
    assert len(interludes)==8
    interlude_words={s['id']:sum(len(WORD.findall(n['text']['ru'])) for n in model.nodes.values() if n['scene']==s['id']) for s in interludes}
    assert all(700<=v<=1000 for v in interlude_words.values()),interlude_words
    endings={}
    for policy in ['together','apart','sacrifice','bad']:
        route=model.walk(policy)
        scene=model.nodes[route['nodes'][-1]]['scene']
        words=sum(len(WORD.findall(model.nodes[n]['text']['ru'])) for n in route['nodes'] if model.nodes[n]['scene']==scene)
        assert words>=1500,(policy,words)
        endings[policy]=words
    chronicle=read('story/chronicle.json')['entries'];assert len(chronicle)>=60
    assert len({e['id'] for e in chronicle})==len(chronicle)
    for entry in chronicle:
        assert 80<=len(WORD.findall(entry['text']))<=150,(entry['id'],len(WORD.findall(entry['text'])))
        assert entry['source'] and entry['category'] in ['people','events','places','equipment']
        assert 1<=entry['chapter']<=8
        if entry['image']:assert (ROOT/entry['image']).is_file()
    art=read('tools/wave_art_manifest.json')['assets'];counts=Counter(a['category'] for a in art)
    assert len(art)>=100 and counts['cs']>=72 and counts['chronicle']>=20 and counts['new_story']>=20,counts
    assert len({a['composition_sha256'] for a in art})==len(art),'Duplicate compositions'
    palette=set(palette_colors())
    for asset in art:
        im=Image.open(ROOT/asset['file']);assert im.mode=='P' and im.size==(480,270),asset['file']
        colors=im.convert('RGB').getcolors(49);assert colors
        assert {color for _,color in colors}<=palette,asset['file']
        assert len(im.getcolors())<=48
        assert (ROOT/asset['source']).exists()
    cinematic_words=0;frames=0
    for beat in beats:
        if beat['type']!='cutscene':continue
        data=read('story/cutscenes/'+beat['cutscene']+'.json');assert 6<=len(data['frames'])<=8
        assert len(data['choice']['options'])>=2 and set(data['outcome']['cards'])=={'win','costly','loss'}
        for frame in data['frames']:
            assert (ROOT/frame['image']).is_file() and 1<=frame['duration']<=20
            cinematic_words+=len(WORD.findall(frame['caption']['ru']));frames+=1
        for option in data['choice']['options']:
            assert set(option.get('set_flags',[]))<=model.definitions['flags'].keys()
    characters=read('story/characters.json')['characters']
    personal_scenes={k:len({n['scene'] for n in model.nodes.values() if n['speaker']==k}) for k,v in characters.items() if v.get('arc')}
    assert 4<=len(personal_scenes)<=6 and min(personal_scenes.values())>=3,personal_scenes
    narrative_words=sum(len(WORD.findall(n['text']['ru'])) for n in model.nodes.values())
    assert 45000<=narrative_words+cinematic_words<=60000
    catalog=read('story/library_art.json')['assets'];assert len({a['file'] for a in catalog})==len(catalog)
    assert {a['file'] for a in art}<={a['file'] for a in catalog}
    audio_bytes=sum(p.stat().st_size for p in (ROOT/'assets/audio').glob('*.ogg'));assert audio_bytes<=40*1024**2
    for name in ['city','march','tension','battle','sadness','triumph','ambient_forest','ambient_camp','ambient_forum','ambient_sea','choice','step','sword','shield','fire','crowd']:
        assert (ROOT/f'assets/audio/{name}.ogg').read_bytes().startswith(b'OggS')
    routes=[]
    for route_name in ['legion','citizen']:
        r=model.walk('together',route_name);routes.append({'route':route_name,'words':r['words'],'minutes_at_120_wpm':round(r['words']/120,1),'minutes_at_200_wpm':round(r['words']/200,1)})
    report={'story_words':narrative_words,'cinematic_words':cinematic_words,'total_narrative_words':narrative_words+cinematic_words,'interludes':interlude_words,'epilogues':endings,'new_original_compositions':len(art),'new_art_categories':dict(counts),'cinematics':types['cutscene'],'cinematic_frames':frames,'personal_scenes':personal_scenes,'peaceful_quests':types['rpg'],'soft_episodes':types['soft'],'chronicle_entries':len(chronicle),'gallery_paintings':len(catalog),'audio_bytes':audio_bytes,'reading_routes':routes,'physical_device_performance':'requires physical ARM64 device','errors':[]}
    (ROOT/'docs/completion_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))

if __name__=='__main__':main()
