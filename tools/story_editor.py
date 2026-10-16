#!/usr/bin/env python3
"""Replace a scene's prose from JSON on stdin, preserving its graph/control nodes.

Input: {"scene":"ch01_s01", "status":"complete", "passages":[
  {"speaker":"...","portrait":"...","text":{"ru":"...","en":""}}]}
No narrative text is kept in this script; chapters remain the source of truth.
"""
import json
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
data=json.load(sys.stdin)
scene=data['scene']
path=ROOT/f'story/chapters/{scene[:4]}.json'
chapter=json.loads(path.read_text())
old=[n for n in chapter['nodes'] if n.get('scene')==scene and n['id'].startswith(scene+'_n') and int(n['id'].rsplit('_n',1)[1])<70]
if not old:raise ValueError('Scene has no prose entry')
first=next(n for n in old if n['id']==scene+'_n01')
tail=next((n['next'] for n in old if n.get('next') not in {o['id'] for o in old}), scene+'_n90')
passages=data['passages']
if not 1<=len(passages)<70:raise ValueError('Expected 1..69 passages')
replacement=[]
for i,p in enumerate(passages,1):
    node={'id':scene+f'_n{i:02}','scene':scene,'kind':first.get('kind','dialogue') if i==1 else 'dialogue','speaker':p.get('speaker','narrator'),'portrait':p.get('portrait',''),'text':p['text'],'next':scene+f'_n{i+1:02}' if i<len(passages) else tail}
    if i==1 and first.get('set_flags'):node['set_flags']=first['set_flags']
    if p.get('condition'):node['condition']=p['condition']
    replacement.append(node)
old_ids={n['id'] for n in old}
position=min(i for i,n in enumerate(chapter['nodes']) if n['id'] in old_ids)
chapter['nodes']=[n for n in chapter['nodes'] if n['id'] not in old_ids]
chapter['nodes'][position:position]=replacement
for s in chapter['scenes']:
    if s['id']==scene:s['prose_status']=data.get('status','draft')
chapter['prose_status']='complete' if all(s.get('prose_status')=='complete' for s in chapter['scenes']) else 'draft'
path.write_text(json.dumps(chapter,ensure_ascii=False,indent=2)+'\n')
