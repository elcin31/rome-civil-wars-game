"""Reachable regression cases for major decisions, without injecting final states."""


def verify_scenarios(model):
    cases=[];locked=0
    def case(name,route,expected,policy='together',side=True,faction=None,overrides=None):
        result=model.walk(policy,route,faction,side,overrides)
        assert result['ending']==expected, f'{name}: expected {expected}, reached {result["ending"]}'
        result['case']=route+'/'+name
        flags=result['state']['flags'];visited=set(result['nodes'])
        for flag,yes,no in [('warned_lucilla','ch08_s04_n04','ch08_s04_n05'),
                            ('warned_serranus','ch08_s04_n06','ch08_s04_n07')]:
            assert (yes in visited)==flags[flag] and (no in visited)!=flags[flag], name+': wrong persistent epilogue'
        if flags['friend_lost']:
            assert not any(n>='ch07_s04' and model.nodes[n]['speaker']=='vorenus' for n in visited), name+': lost friend speaks later'
        cases.append(result)
        return result
    def unavailable(route,overrides,policy='together'):
        nonlocal locked
        try:model.walk(policy,route,overrides=overrides)
        except ValueError as error:
            assert str(error).startswith('Requested choice unavailable:'), str(error)
            locked+=1
        else:raise AssertionError('Locked decision unexpectedly available')
    for route in ['legion','citizen']:
        harbor='ch03_s05' if route=='legion' else 'ch03_s13'
        for faction in ['octavian','antony','republicans']:
            case('faction_'+faction,route,'together',faction=faction)
        both=case('warn_both_without_side_quests',route,'together',side=False,
                  overrides={'ch05_s04_n90':'ch05_s04_both'})
        assert both['state']['flags']['warned_serranus'] and both['state']['flags']['warned_lucilla']
        family=case('warn_family',route,'together',overrides={'ch05_s04_n90':'ch05_s04_lucilla'})
        assert family['state']['flags']['warned_lucilla'] and not family['state']['flags']['warned_serranus']
        orders=case('leave_actium',route,'apart',overrides={'ch07_s03_n90':'ch07_s03_orders'})
        assert not orders['state']['flags']['aulus_safe'] and not orders['state']['flags']['friend_lost']
        case('records_then_sacrifice',route,'sacrifice',overrides={harbor+'_n90':harbor+'_records',
             'ch07_s03_n90':'ch07_s03_sacrifice'})
        low={'ch05_s08_n90':'ch05_s08_evidence','ch04_s07_n90':'ch04_s07_keep_ledger',
             'ch06_s05_n90':'ch06_s05_evacuate',harbor+'_n90':harbor+'_boat'}
        unavailable(route,{**low,'ch07_s03_n90':'ch07_s03_together'},policy='bad')
        result=case('low_trust_sacrifice',route,'sacrifice',policy='bad',overrides={**low,
                    'ch07_s03_n90':'ch07_s03_sacrifice'})
        assert result['state']['bond']<65 and result['state']['flags']['aglaia_safe']
        unavailable(route,{'ch01_s02_n90':'ch01_s02_inspect',
                          'ch01_s03_n90':'ch01_s03_hold_rampart','ch05_s04_n90':'ch05_s04_both'})
        unavailable(route,{harbor+'_n90':harbor+'_records','ch07_s03_n90':'ch07_s03_together'})
    return cases,locked
