"""Small independent narrative interpreter used for validation and witness generation."""
import json
import re
from copy import deepcopy
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
WORD=re.compile(r"[A-Za-zА-Яа-яЁё0-9]+(?:[’'‑-][A-Za-zА-Яа-яЁё0-9]+)*")
NUMERIC=re.compile(r'^(bond|rep\.[a-z_]+)(>=|<=|==|!=|>|<)(-?\d+)$')


def read(path):return json.loads((ROOT/path).read_text())


def atom(value,state):
    if value.startswith('!'):return not state['flags'].get(value[1:],False)
    match=NUMERIC.fullmatch(value)
    if match:
        name,op,rhs=match.groups();rhs=int(rhs)
        lhs=state['bond'] if name=='bond' else state['rep'][name[4:]]
        return {'>=':lhs>=rhs,'<=':lhs<=rhs,'==':lhs==rhs,'!=':lhs!=rhs,'>':lhs>rhs,'<':lhs<rhs}[op]
    return bool(state['flags'].get(value,False))


def condition(expression,state):
    if not expression.strip():return True
    return any(all(atom(v,state) for v in group.split('&')) for group in expression.replace(' ','').split('|'))


def effects(data,state):
    for flag in data.get('set_flags',[]):state['flags'][flag]=True
    for flag in data.get('clear_flags',[]):state['flags'][flag]=False
    state['bond']=max(0,min(100,state['bond']+data.get('bond',0)))
    for faction,delta in data.get('rep',{}).items():state['rep'][faction]=max(-100,min(100,state['rep'][faction]+delta))


class Model:
    def __init__(self):
        self.chapters=[read(f'story/chapters/ch{i:02}.json') for i in range(1,9)]
        self.nodes={n['id']:n for c in self.chapters for n in c['nodes']}
        self.scenes={s['id']:s for c in self.chapters for s in c['scenes']}
        self.definitions=read('story/flags.json')

    def initial(self):
        return {'flags':{k:v['default'] for k,v in self.definitions['flags'].items()},'rep':deepcopy(self.definitions['reputation']),'bond':self.definitions['initial_bond']}

    def walk(self,policy='together',route='legion',faction=None,visit_side=True):
        state=self.initial();target='ch01_s01_n01';visited=[];decisions=[];words=0
        for step in range(10000):
            node=self.nodes[target]
            if not condition(node.get('condition',''),state):target=node['next'];continue
            visited.append(target);effects(node,state)
            words+=len(WORD.findall(node.get('text',{}).get('ru','')))
            if node.get('kind')=='ending':return {'ending':node['ending'],'state':state,'nodes':visited,'decisions':decisions,'words':words,'minutes':round(words/200,1),'route':route,'policy':policy,'side_quests':visit_side}
            if node.get('kind')=='branch':
                target=next((b['goto'] for b in node.get('branches',[]) if condition(b.get('condition',''),state)),node.get('next'))
                continue
            options=node.get('choices',[])
            if options:
                available=[o for o in options if condition(o.get('condition',''),state)]
                if not available:raise ValueError('No available choice at '+target)
                option=available[0]
                ending=lambda suffix:next((o for o in available if o['id'].endswith(suffix)),option)
                if policy=='bad':option=available[-1]
                if target=='ch02_s08_n90':option=ending('_'+route)
                if target=='ch05_s01_n90':option=ending('_'+(faction or ('neutral' if policy=='together' else 'antony' if policy=='apart' else 'octavian')))
                if target=='ch07_s03_n90' and policy=='sacrifice':option=ending('_sacrifice')
                if target=='ch08_s01_n90' and policy=='apart':option=ending('_private')
                if target=='ch08_s02_n90' and policy=='apart':option=ending('_rank')
                if '_optional_' in target:option=ending('_visit' if visit_side else '_skip')
                effects(option,state);words+=len(WORD.findall(option['text']['ru']))
                decisions.append({'node':target,'choice':option['id']});target=option['goto']
            else:target=node['next']
        raise ValueError('Traversal limit exceeded')
