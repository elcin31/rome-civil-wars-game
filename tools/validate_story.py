#!/usr/bin/env python3
"""Validate narrative integrity, assets, authored volume and actual route lengths.

--draft checks structure while explicitly reporting unmet literary requirements.
The default is strict and fails until the PDF's full acceptance criteria are met.
"""
import argparse
import json
from collections import Counter
from pathlib import Path
from PIL import Image
from story_model import Model, WORD, NUMERIC, read
from story_scenarios import verify_scenarios
from pixelize import palette_colors

ROOT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--draft',action='store_true')
    args=parser.parse_args()
    model=Model();errors=[];requirements=[]
    nodes=model.nodes;scenes=model.scenes;flags=model.definitions['flags'];rep=model.definitions['reputation']
    speakers=read('story/characters.json')['characters'];portraits=read('story/portraits.json')['portraits']
    beats={b['id']:b for b in read('story/beats.json')['beats']}
    all_ids=[n['id'] for c in model.chapters for n in c['nodes']]
    if len(all_ids)!=len(set(all_ids)):errors.append('Duplicate node IDs')
    choice_ids=[o['id'] for n in nodes.values() for o in n.get('choices',[])]
    if len(choice_ids)!=len(set(choice_ids)):errors.append('Duplicate choice IDs')
    for flag,definition in flags.items():
        for choice in definition.get('restore_from_choices',[]):
            if choice not in choice_ids:errors.append(f'{flag}: invalid saved-choice migration {choice}')
    edges={}
    words=0;used_portraits=set();choices=0;majors=[];texts=[]
    def expression(value,where):
        if not value:return
        for alternative in value.replace(' ','').split('|'):
            for atom in alternative.split('&'):
                match=NUMERIC.fullmatch(atom)
                if match:
                    if match[1]!='bond' and match[1][4:] not in rep:errors.append(f'{where}: unknown reputation {match[1]}')
                elif atom.lstrip('!') not in flags:errors.append(f'{where}: undefined condition flag {atom}')
    def effect(data,where):
        for flag in data.get('set_flags',[])+data.get('clear_flags',[]):
            if flag not in flags:errors.append(f'{where}: undefined flag {flag}')
        if set(data.get('set_flags',[])) & set(data.get('clear_flags',[])):errors.append(f'{where}: contradictory flag effects')
        for faction,value in data.get('rep',{}).items():
            if faction not in rep or not isinstance(value,int):errors.append(f'{where}: invalid reputation effect')
        if not isinstance(data.get('bond',0),int):errors.append(f'{where}: bond delta not integer')
        expression(data.get('condition',''),where)
    for ident,node in nodes.items():
        if node.get('scene') not in scenes:errors.append(f'{ident}: unknown scene')
        if node.get('speaker') not in speakers:errors.append(f'{ident}: unknown speaker')
        if not isinstance(node.get('text',{}).get('ru'),str) or not isinstance(node.get('text',{}).get('en'),str):errors.append(f'{ident}: missing language fields')
        text=node.get('text',{}).get('ru','');words+=len(WORD.findall(text))
        if len(WORD.findall(text))>50:texts.append(text)
        portrait=node.get('portrait','')
        if portrait:
            used_portraits.add(portrait)
            if portrait not in portraits:errors.append(f'{ident}: unknown portrait {portrait}')
        effect(node,ident)
        destinations=[]
        if node.get('next'):destinations.append(node['next'])
        if node.get('choices'):
            choices+=1
            if not any(not c.get('condition') for c in node['choices']):errors.append(f'{ident}: all choices conditional, possible trap')
            if node.get('major_branch'):majors.append(node['major_branch'])
            for option in node['choices']:
                effect(option,ident+'/'+option['id'])
                destinations.append(option.get('goto',''))
        for branch in node.get('branches',[]):
            expression(branch.get('condition',''),ident);destinations.append(branch.get('goto',''))
        if node.get('kind')=='beat' and node.get('beat') not in beats:errors.append(f'{ident}: undefined beat')
        if node.get('kind')=='ending':
            if destinations:errors.append(f'{ident}: terminal has outgoing edge')
        elif not destinations:errors.append(f'{ident}: non-ending dead end')
        for target in destinations:
            if target not in nodes:errors.append(f'{ident}: broken transition {target}')
        edges[ident]=destinations
    duplicates=[text for text,n in Counter(texts).items() if n>1]
    if duplicates:errors.append('Duplicated long narrative paragraphs')
    visited=set();active=set();stack=[('ch01_s01_n01',False)]
    while stack:
        ident,leaving=stack.pop()
        if leaving:
            active.discard(ident);visited.add(ident);continue
        if ident in active:errors.append('Graph cycle at '+ident);continue
        if ident in visited or ident not in nodes:continue
        active.add(ident);stack.append((ident,True))
        stack.extend((dest,False) for dest in reversed(edges[ident]))
    if set(nodes)-visited:errors.append(f'{len(set(nodes)-visited)} unreachable nodes')
    for scene in scenes.values():
        if scene.get('entry') not in nodes:errors.append(scene['id']+': missing entry')
        for variant in scene.get('illustration_variants',[]):expression(variant.get('condition',''),scene['id'])
        for path in [scene.get('illustration','')]+[v['file'] for v in scene.get('illustration_variants',[])]+scene.get('illustration_archive',[]):
            if not (ROOT/path).is_file():errors.append(scene['id']+': missing illustration '+path)
    palette=set(palette_colors());art=read('tools/story_art_manifest.json')['assets'];pngs=set()
    for asset in art:
        if not (ROOT/asset['source']).is_file():errors.append('Missing source '+asset['source'])
        if asset['category']=='emotions':
            if not any(p.startswith(asset['id']+'_') for p in used_portraits):errors.append('Unused emotion character '+asset['id'])
        elif not any(asset['file'] in [s.get('illustration')]+[v['file'] for v in s.get('illustration_variants',[])]+s.get('illustration_archive',[]) for s in scenes.values()):
            errors.append('Unlinked story illustration '+asset['id'])
        pngs.add((asset['file'],tuple(asset['size'])))
    for portrait in portraits.values():pngs.add((portrait['file'],(128,128)))
    for file,size in sorted(pngs):
        path=ROOT/file
        if not path.is_file():errors.append('Missing PNG '+file);continue
        image=Image.open(path).convert('RGBA')
        colors={color for count,color in image.getcolors(image.width*image.height)}
        if image.size!=size:errors.append(file+': wrong size')
        if any((r,g,b) not in palette for r,g,b,a in colors if a):errors.append(file+': outside palette')
        if any(a not in [0,255] for r,g,b,a in colors):errors.append(file+': non-binary alpha')
        if not image.getbbox():errors.append(file+': blank PNG')
        imp=Path(str(path)+'.import')
        if not imp.is_file() or 'mipmaps/generate=false' not in imp.read_text():errors.append(file+': no explicit no-mipmap import')
    witnesses=[];scenario_routes=[];locked_choices=0
    if not any('broken transition' in e for e in errors):
        for route in ['legion','citizen']:
            for policy in ['together','apart','sacrifice','bad']:
                try:
                    result=model.walk(policy,route)
                    witnesses.append(result)
                    if result['ending']!=policy:errors.append(f'{route}/{policy}: reached {result["ending"]}')
                except Exception as error:errors.append(f'{route}/{policy}: {error}')
        try:scenario_routes,locked_choices=verify_scenarios(model)
        except Exception as error:errors.append('Major decision regression: '+str(error))
    if len(scenes)<60:requirements.append('At least 60 scenes required')
    if choices<40:requirements.append('At least 40 decision nodes required')
    if len(set(majors))<8:requirements.append('At least 8 major branches required')
    side_count=sum(bool(s.get('optional')) for s in scenes.values())
    if side_count<20:requirements.append('At least 20 side scenes required')
    if len(art)<30:requirements.append('At least 30 illustrations required')
    if not 45000<=words<=60000:requirements.append(f'Authored narrative words {words}: required 45000..60000')
    unfinished=[s['id'] for s in scenes.values() if s.get('prose_status')!='complete']
    if unfinished:requirements.append(f'{len(unfinished)} scenes still marked draft')
    # Reading time is reported from actual traversals; branch-only prose is not counted twice.
    normal_routes=[]
    for route in ['legion','citizen']:
        for faction in ['neutral','octavian','antony','republicans']:
            for side in [False,True]:
                result=model.walk('together',route,faction,visit_side=side)
                result['faction']=faction;normal_routes.append(result)
    required_events=set(read('story/history_events.json')['required_events'])
    for route in normal_routes:
        covered_scenes={nodes[n]['scene'] for n in route['nodes']}
        covered={event for scene in covered_scenes for event in scenes[scene].get('historical_anchors',[])}
        if required_events-covered:errors.append(f"{route['route']}: missing historical anchors {sorted(required_events-covered)}")
    if any(r['minutes']<150 for r in normal_routes):requirements.append('Expanded route unexpectedly shorter than 150 minutes at 200 words/min')
    report={'mode':'draft' if args.draft else 'strict','nodes':len(nodes),'scenes':len(scenes),'choices':choices,'major_branches':len(set(majors)),'side_scenes':side_count,'narrative_words':words,'all_text_minutes':round(words/200,1),'finished_scenes':len(scenes)-len(unfinished),'illustrations':len(art),'new_pngs':len(pngs),'verified_scenarios':len(witnesses)+len(scenario_routes),'locked_choices_checked':locked_choices,'normal_routes':[{k:r[k] for k in ['route','faction','side_quests','words','minutes']} for r in normal_routes],'errors':errors,'unmet_requirements':requirements}
    (ROOT/'docs/story_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    (ROOT/'story/test_routes.json').write_text(json.dumps({'routes':witnesses,'scenarios':scenario_routes},ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ['normal_routes','errors','unmet_requirements']},ensure_ascii=False))
    for route in report['normal_routes']:print('ROUTE',route)
    for error in errors:print('ERROR',error)
    for req in requirements:print('UNMET',req)
    print('STRUCTURE PASS' if not errors else 'STRUCTURE FAIL')
    raise SystemExit(bool(errors or requirements and not args.draft))


if __name__=='__main__':main()
