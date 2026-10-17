#!/usr/bin/env python3
"""Build the v0.4 art addition from saved original generation sources (offline)."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
from PIL import Image, ImageDraw, ImageFont, ImageOps
from pixelize import dominant_resize, clean_clusters, quantize, remove_background, NEAREST

ROOT = Path(__file__).resolve().parents[1]
EMOTIONS = ['neutral', 'angry', 'worried', 'smile']
STORIES = {
 'story_a': [('ditch_survey','Двое у незаконченного рва','ch01_s01'), ('forest_ambush','Засада среди дубов','ch01_s04'), ('camp_lanterns','Лагерные огни','ch01_s03'), ('rubicon_watch','Дозор на Рубиконе','ch02_s04'), ('council_map','Карта без приказа','ch02_s03'), ('rome_shutters','Закрытые ставни Рима','ch02_s05')],
 'story_b': [('brundisium_sails','Паруса Брундизия','ch03_s01'), ('pharos_dawn','Маяк на рассвете','ch03_s04'), ('palace_audience','Александрийская аудиенция',None), ('pompey_shore','Последняя пристань Помпея','ch03_s03'), ('senate_walk','Дорога в сенат','ch04_s02'), ('forum_eulogy','Речь над Форумом','ch04_s04')],
 'story_c': [('names_at_dawn','Имена на рассвете','ch05_s02'), ('attic_refuge','Убежище под крышей','ch05_s05'), ('cicero_letter','Письмо Цицерона','ch05_s03'), ('philippi_mist','Туман Филипп','ch06_s01'), ('perusia_gates','Ворота Перузии','ch06_s05'), ('grain_queue','Мера зимнего хлеба','ch06_s04')],
 'story_d': [('actium_oars','Вёсла Акция','ch07_s02'), ('silent_quay','Безмолвная набережная','ch07_s05'), ('archive_rescue','Сухие листы','ch07_s07'), ('forum_oath','Новый Форум','ch08_s02'), ('old_workshop','Старые друзья в мастерской','ch08_s03'), ('laurel_ash','Лавр и пепел','ch08_s04')]
}
LOCATIONS = {
 'locations_a': ['command_tent','atrium_house','senate_curia','tavern','ship_deck','prison'],
 'locations_b': ['villa_garden','temple','market','olive_road','stone_bridge','field_hospital'],
 'locations_c': ['camp_day','camp_rain','forest_night','road_rain']
}
NPCS = {'npc_a': ['scribe','merchant','healer','centurion','sailor'], 'npc_b': ['priest','druid','servant','child','messenger']}
CAST = {'cast_a': ['titus_pullo','lucius_vorenus','julius_caesar','octavian_young','augustus_old'], 'cast_b': ['mark_antony','cleopatra','pompey','brutus','caesar_legionary'], 'cast_c': ['gallic_warrior','pompeian_soldier','roman_citizen','senator','craftsman']}
NAMES = dict(zip(sum(LOCATIONS.values(), []), ['Палатка командира','Римский атрий','Курия','Таверна','Палуба','Тюрьма','Сад виллы','Храм','Рынок','Оливковая дорога','Каменный мост','Лазарет','Дневной лагерь','Лагерь в дождь','Ночной лес','Дорога в дождь']))
NPC_NAMES = dict(zip(sum(NPCS.values(), []), ['Писец','Торговец','Лекарь','Центурион','Моряк','Жрец','Друид','Слуга','Ребёнок','Посыльная']))


def save_json(path, data):
    (ROOT / path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def crop_cell(source, column, row, columns, rows):
    return source.crop((round(column * source.width / columns), round(row * source.height / rows), round((column + 1) * source.width / columns), round((row + 1) * source.height / rows)))


def landscape(source, size=(640, 360)):
    ratio = size[0] / size[1]
    width, height = source.size
    if width / height > ratio:
        target = round(height * ratio)
        source = source.crop(((width-target)//2, 0, (width+target)//2, height))
    else:
        target = round(width / ratio)
        source = source.crop((0, (height-target)//2, width, (height+target)//2))
    return dominant_resize(source, size)


def portrait_sheets():
    actors = json.loads((ROOT / 'story/characters.json').read_text())
    portraits = json.loads((ROOT / 'story/portraits.json').read_text())
    for name, people in [('portraits_a', ['narrator','history','lucilla','serranus']), ('portraits_b', ['aulus','vettius','neria','aglaia'])]:
        source_path = ROOT / f'art_src/refresh/{name}.png'
        if not source_path.exists():
            continue
        source = Image.open(source_path).convert('RGBA')
        for row, ident in enumerate(people):
            atlas = Image.new('RGBA', (256, 256))
            for col, emotion in enumerate(EMOTIONS):
                frame = dominant_resize(crop_cell(source, col, row, 4, 4), (128, 128))
                file = f'assets/portraits/{ident}_{emotion}.png'
                frame.save(ROOT / file, optimize=True)
                atlas.alpha_composite(frame, (col % 2 * 128, col // 2 * 128))
                portraits['portraits'][ident + '_' + emotion] = {'file': file, 'emotion': emotion, 'character': ident}
            atlas.save(ROOT / f'assets/portraits/{ident}_emotions.png', optimize=True)
            actors['characters'][ident]['default_portrait'] = ident + '_neutral'
    # Reprocess existing speakers from their full source rather than enlarging 96px pixels.
    manifest = json.loads((ROOT / 'tools/story_art_manifest.json').read_text())
    for asset in manifest['assets']:
        if asset['category'] != 'emotions':
            continue
        source = remove_background(Image.open(ROOT / asset['source']))
        atlas = Image.new('RGBA', (256, 256))
        for col, emotion in enumerate(EMOTIONS):
            crop = crop_cell(source, col % 2, col // 2, 2, 2)
            if crop.getbbox():
                crop = crop.crop(crop.getbbox())
            crop.thumbnail((124, 124), NEAREST)
            frame = Image.new('RGBA', (128, 128))
            frame.alpha_composite(crop, ((128 - crop.width) // 2, 126 - crop.height))
            frame = clean_clusters(quantize(frame))
            frame.save(ROOT / f'assets/portraits/{asset["id"]}_{emotion}.png', optimize=True)
            atlas.alpha_composite(frame, (col % 2 * 128, col // 2 * 128))
        atlas.save(ROOT / asset['file'], optimize=True)
        atlas.save(ROOT / f'assets/portraits/{asset["id"]}_emotions.png', optimize=True)
        asset['size'] = [256, 256]
    save_json('tools/story_art_manifest.json', manifest)
    save_json('story/characters.json', actors)
    save_json('story/portraits.json', portraits)


def sprite_row(source, row):
    crops = []
    for col in range(5):
        crop = crop_cell(source, col, row, 5, 5).convert('RGBA')
        crop.putalpha(crop.getchannel('A').point(lambda a: 255 if a >= 128 else 0))
        if not crop.getbbox():
            raise ValueError(f'Empty sprite row {row}, col {col}')
        crops.append(crop.crop(crop.getbbox()))
    factor = min(58 / max(c.width for c in crops), 88 / max(c.height for c in crops))
    result = []
    for crop in crops:
        crop = dominant_resize(crop, (max(1, round(crop.width * factor)), max(1, round(crop.height * factor))))
        frame = Image.new('RGBA', (64, 96))
        frame.alpha_composite(crop, ((64 - crop.width) // 2, 94 - crop.height))
        result.append(clean_clusters(frame, outline=True))
    return result


def character_atlas(source, row, output, previous=None):
    poses = sprite_row(source, row)
    frames = [poses[0], poses[1], poses[0], poses[0], poses[1], poses[1], poses[2], poses[3], poses[4]]
    if previous:
        old = Image.open(previous).convert('RGBA')
        cell_w, cell_h = old.width // 3, old.height // 3
        for index in [2]:
            crop = old.crop((index * cell_w, 0, (index + 1) * cell_w, cell_h))
            crop = crop.crop(crop.getbbox())
            factor = min(58 / crop.width, 88 / crop.height)
            crop = dominant_resize(crop, (round(crop.width * factor), round(crop.height * factor)))
            frame = Image.new('RGBA', (64, 96))
            frame.alpha_composite(crop, ((64 - crop.width) // 2, 94 - crop.height))
            frames[index] = clean_clusters(quantize(frame))
    atlas = Image.new('RGBA', (192, 288))
    for index, frame in enumerate(frames):
        atlas.alpha_composite(frame, (index % 3 * 64, index // 3 * 96))
    atlas.save(output, optimize=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--portraits-only', action='store_true')
    parser.add_argument('--partial', action='store_true')
    args = parser.parse_args()
    portrait_sheets()
    if args.portraits_only:
        return
    assets = []
    for folder in ['illustrations','interiors','npcs','chapter_cards']:
        (ROOT / 'assets' / folder).mkdir(exist_ok=True)
    for source_name, entries in STORIES.items():
        path = ROOT / f'art_src/refresh/{source_name}.png'
        if not path.exists() and args.partial:
            continue
        source = Image.open(path).convert('RGBA')
        columns, rows = (2, 3) if source_name == 'story_a' else (3, 2)
        for index, (ident, title, scene) in enumerate(entries):
            file = f'assets/illustrations/{ident}.png'
            landscape(crop_cell(source, index % columns, index // columns, columns, rows)).save(ROOT / file, optimize=True)
            assets.append({'id': ident, 'title': title, 'file': file, 'size': [640,360], 'category': 'illustrations', 'kind': 'story', 'scene': scene, 'source': str(path.relative_to(ROOT)), 'cell': [index % columns, index // columns], 'grid': [columns,rows]})
    for source_name, entries in LOCATIONS.items():
        path = ROOT / f'art_src/refresh/{source_name}.png'
        if not path.exists() and args.partial:
            continue
        source = Image.open(path).convert('RGBA')
        columns, rows = (2, 2) if source_name == 'locations_c' else (3, 2)
        for index, ident in enumerate(entries):
            file = f'assets/interiors/{ident}.png'
            landscape(crop_cell(source, index % columns, index // columns, columns, rows)).save(ROOT / file, optimize=True)
            assets.append({'id': ident, 'title': NAMES[ident], 'file': file, 'size': [640,360], 'category': 'illustrations', 'kind': 'location', 'source': str(path.relative_to(ROOT)), 'cell': [index % columns,index // columns], 'grid': [columns,rows]})
    base_manifest = json.loads((ROOT / 'tools/manifest.json').read_text())
    for source_name, entries in (NPCS | CAST).items():
        path = ROOT / f'art_src/refresh/{source_name}.png'
        if not path.exists() and args.partial:
            continue
        source = Image.open(path).convert('RGBA')
        for row, ident in enumerate(entries):
            is_new = source_name in NPCS
            file = f'assets/{"npcs" if is_new else "characters"}/{ident}.png'
            previous = None
            if not is_new:
                previous = ROOT / f'art_src/refresh/legacy_keys/{ident}.png'
                previous.parent.mkdir(exist_ok=True)
                if not previous.exists():
                    shutil.copy2(ROOT / file, previous)
            character_atlas(source, row, ROOT / file, previous)
            if is_new:
                assets.append({'id': ident, 'title': NPC_NAMES[ident], 'file': file, 'size': [192,288], 'frame_size': [64,96], 'category': 'illustrations', 'kind': 'npc_sheet', 'source': str(path.relative_to(ROOT)), 'row': row})
            else:
                asset = next(a for a in base_manifest['assets'] if a['id'] == ident)
                asset['size'] = [192,288]
                asset['frame_size'] = [64,96]
                asset['refresh_source'] = str(path.relative_to(ROOT))
                asset['refresh_row'] = row
    cards = ROOT / 'art_src/refresh/chapter_cards.png'
    if cards.exists():
        source = Image.open(cards).convert('RGBA')
        for index in range(8):
            file = f'assets/chapter_cards/ch{index+1:02d}.png'
            dominant_resize(crop_cell(source,index%4,index//4,4,2),(128,160)).save(ROOT / file,optimize=True)
            assets.append({'id': f'chapter_{index+1:02d}', 'title': f'Карточка главы {index+1}', 'file': file, 'size': [128,160], 'category': 'illustrations', 'kind': 'chapter_card', 'source': str(cards.relative_to(ROOT)), 'cell': [index%4,index//4], 'grid': [4,2]})
    menu = ROOT / 'art_src/refresh/menu_new.png'
    if menu.exists():
        landscape(Image.open(menu).convert('RGBA')).save(ROOT / 'assets/final/menu.png', optimize=True)
    save_json('tools/refresh_art_manifest.json', {'version':1,'new_compositions':len(assets),'assets':assets})
    save_json('tools/manifest.json', base_manifest)
    for chapter in range(1, 9):
        path = f'story/chapters/ch{chapter:02}.json'
        data = json.loads((ROOT / path).read_text())
        for scene in data['scenes']:
            new_art = next((a for a in assets if a.get('scene') == scene['id']), None)
            # Preserve authored loss variants; do not show a living friend after his death.
            if new_art and not scene.get('illustration_variants'):
                if scene.get('illustration') != new_art['file']:
                    scene['illustration_archive'] = list(dict.fromkeys(scene.get('illustration_archive', []) + [scene['illustration']]))
                scene['illustration'] = new_art['file']
        save_json(path, data)
    font = ImageFont.truetype(str(ROOT / 'assets/fonts/Tiny5.ttf'), 24)
    columns, cw, ch = 4, 340, 230
    board = Image.new('RGB', (columns*cw, ((len(assets)+columns-1)//columns)*ch+60), '#14151f')
    draw = ImageDraw.Draw(board)
    draw.text((16,12), f'CINIS LAURI / {len(assets)} новых композиций / 48 цветов', font=font, fill='#ede3cc')
    for index, asset in enumerate(assets):
        image = Image.open(ROOT / asset['file']).convert('RGBA')
        image.thumbnail((320,180), NEAREST)
        x, y = index%columns*cw+10,index//columns*ch+60
        board.paste(image,(x+(320-image.width)//2,y),image)
        draw.text((x,y+184), asset['title'],font=font,fill='#ede3cc')
    board.save(ROOT / 'docs/contact_refresh.png',optimize=True)
    print(f'Built {len(assets)} additional compositions')


if __name__ == '__main__':
    main()
