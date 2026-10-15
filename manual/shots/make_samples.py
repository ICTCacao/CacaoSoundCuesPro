# 撮影用のキューシートを作る。元は repo の sample/夕暮れの谷.ccsc（作業中の版）。
# 4 曲のリスト（作った音）・メモ・書き込み・MIDI の割り当てを足し、日本語／英語、縦書き／横書きの 4 つを出す
import json, shutil, os, sys, uuid, math, array, wave, copy
SRC = '/Users/ccostudio/CacaoApps/CacaoSoundCuesPro/sample/夕暮れの谷.ccsc'
OUT = sys.argv[1]
SR = 48000

def tone(path, seconds, base, seed):
    n = int(seconds * SR)
    a = array.array('h')
    import random
    r = random.Random(seed)
    parts = [(base * k, r.uniform(0.2, 0.6), r.uniform(0.05, 0.3), r.uniform(0, 6.28)) for k in (1, 1.5, 2, 3)]
    for i in range(n):
        t = i / SR
        env = min(1, t / 1.5, (seconds - t) / 2.5)
        slow = 0.6 + 0.4 * math.sin(t * 0.7 + seed)
        v = sum(a1 * math.sin(2 * math.pi * f * t + p) * (0.5 + 0.5 * math.sin(t * m + p)) for f, a1, m, p in parts)
        a.append(int(max(-1, min(1, v * env * slow * 0.5)) * 32767))
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(a.tobytes())

JA = dict(list='本編', steps=[('客入れBGM', 40), ('幕間BGM', 35), ('エンディング', 45), ('客出しBGM', 30)],
          note='照明と合わせる', memo='遠く・小さめ', title='夕暮れの谷')
EN = dict(list='Main List', steps=[('Preshow Music', 40), ('Intermission', 35), ('Ending', 45), ('Postshow Music', 30)],
          note='Sync with lights', memo='Distant, soft', title='Evening Valley')
EN_NAMES = {'風が吹く': 'Wind', '風と風鈴': 'Wind & Chime', '春は来るよ': 'Spring Comes', 'birds': 'Birds',
            'bell': 'Bell', 'bell2': 'Bell 2', 'door': 'Door', '風よふけ': 'Wind Song'}
STEP_IDS = [uuid.UUID('11111111-0000-4000-8000-00000000000%d' % i) for i in range(1, 5)]
SOUND_IDS = [uuid.UUID('22222222-0000-4000-8000-00000000000%d' % i) for i in range(1, 5)]
SEQ_ID = '33333333-0000-4000-8000-000000000001'
KEY_SPRING = '1835CC78-5805-4EC7-A5DC-E211F7BE6104'
KEY_BIRDS = '9F279913-83B1-464C-B34B-93377B546AA6'

def build(name, lang, vertical):
    dst = os.path.join(OUT, name + '.ccsc')
    if os.path.exists(dst): shutil.rmtree(dst)
    shutil.copytree(SRC, dst)
    show = json.load(open(os.path.join(dst, 'show.json')))
    pro = json.load(open(os.path.join(dst, 'pro.json')))
    T = EN if lang == 'en' else JA
    show['name'] = T['title']
    if lang == 'en':
        for c in show['keyCues']: c['name'] = EN_NAMES.get(c['name'], c['name'])
        for s in show['sounds']:
            old = s['fileName']; new = s['id'] + '-' + EN_NAMES.get(s['displayName'], s['displayName']) + os.path.splitext(old)[1]
            os.rename(os.path.join(dst, 'Audio', old), os.path.join(dst, 'Audio', new))
            s['fileName'] = new; s['displayName'] = EN_NAMES.get(s['displayName'], s['displayName'])
    play_tpl = copy.deepcopy(show['keyCues'][0]['play'])
    for k in ('volumePoints', 'panPoints'): play_tpl[k] = []
    play_tpl.update(dict(fadeIn=0, fadeOut=0, inPoint=0, outPoint=None, loop=False, loopCount=0, volumeDB=0, pan=0,
                         curve='equalPower', fadeInBezier=None, fadeOutBezier=None, fadeOutAtEnd=False))
    play_tpl = {k: v for k, v in play_tpl.items() if v is not None}
    steps = []
    for i, (nm, sec) in enumerate(T['steps']):
        fn = '%s-%s.wav' % (str(SOUND_IDS[i]).upper(), nm)
        tone(os.path.join(dst, 'Audio', fn), sec, [110, 130.8, 98, 123.5][i], i + 1)
        show['sounds'].append(dict(id=str(SOUND_IDS[i]).upper(), fileName=fn, displayName=nm, duration=float(sec)))
        p = dict(play_tpl); p['soundID'] = str(SOUND_IDS[i]).upper()
        steps.append(dict(id=str(STEP_IDS[i]).upper(), name=nm, play=p, start='returnKey', startSeconds=0))
    show['sequences'] = [dict(id=SEQ_ID, name=T['list'], steps=steps, loop=False, stopFade=3)]
    # リストの曲のきっかけ: 客入れ＝幕開き前から（F.O. は明かりが入るとき）、幕間＝二場の頭、エンディング＝三場の終わり
    links = pro['links']; ends = pro['ends']
    # 幕間 BGM は一場の終わり（明かりが落ちる）から二場の頭まで、エンディングは三場の終わりから幕まで
    links[str(STEP_IDS[1]).upper()] = dict(line='pos-0-19', offset=0, nudge=0.3)
    ends[str(STEP_IDS[1]).upper()] = dict(line='pos-1-2', offset=0, nudge=0.5)
    links[str(STEP_IDS[2]).upper()] = dict(line='pos-2-12', offset=0, nudge=0.3)
    ends[str(STEP_IDS[2]).upper()] = dict(line='pos-2-14', offset=0, nudge=0.8)
    pro['memos'] = {KEY_SPRING: T['memo']}
    pro['notes'] = [dict(id=str(uuid.UUID('44444444-0000-4000-8000-000000000001')).upper(), anchor=dict(line='pos-0-15', offset=0, nudge=0.4), text=T['note'])]
    pro['vertical'] = vertical
    pro['fontSize'] = 16; pro['lineSpacing'] = 0.2
    pro.pop('bodyChars', None); pro.pop('nameChars', None)
    pro['midi'] = dict(mscReceiveID=127, mscSendID=127,
                       bindings=[dict(id=str(uuid.UUID('55555555-0000-4000-8000-000000000001')).upper(), trigger={'note': {'channel': 0, 'note': 36}}, action={'cue': {'_0': KEY_BIRDS}}),
                                 dict(id=str(uuid.UUID('55555555-0000-4000-8000-000000000002')).upper(), trigger={'msc': {'command': 1}}, action={'advance': {}}),
                                 dict(id=str(uuid.UUID('55555555-0000-4000-8000-000000000003')).upper(), trigger={'note': {'channel': 9, 'note': 38}}, action={'panic': {}}),
                                 dict(id=str(uuid.UUID('55555555-0000-4000-8000-000000000004')).upper(), trigger={'cc': {'channel': 0, 'number': 7}}, action={'masterVolume': {}})],
                       sends={KEY_BIRDS: {'note': {'channel': 0, 'note': 60, 'velocity': 127}}})
    json.dump(show, open(os.path.join(dst, 'show.json'), 'w'), ensure_ascii=False, indent=2)
    json.dump(pro, open(os.path.join(dst, 'pro.json'), 'w'), ensure_ascii=False, indent=2)
    print('made', dst)

build('ja', 'ja', True)
build('ja-h', 'ja', False)
build('en', 'en', False)
build('en-v', 'en', True)
