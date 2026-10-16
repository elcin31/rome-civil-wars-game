#!/usr/bin/env python3
"""Rebuild indexed, nearest-neighbour game art from generated source PNGs.

No generative service is called here. Original sources are never overwritten.
The magenta matte is an explicit production choice, not a guessed white matte.
"""
from __future__ import annotations

import argparse
from array import array
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
NEAREST = Image.Resampling.NEAREST
POSES = ["front", "side", "back", "idle", "walk", "run", "attack", "block", "hurt"]


def palette_colors():
    spec = json.loads((ROOT / "tools/palette.json").read_text())
    return [tuple(bytes.fromhex(c["hex"].lstrip("#"))) for c in spec["colors"]]


def quantize(image):
    image = image.convert("RGBA")
    pal = Image.new("P", (1, 1))
    colors = palette_colors()
    pal.putpalette([v for color in colors for v in color] + list(colors[0]) * (256 - len(colors)))
    result = image.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE).convert("RGBA")
    result.putalpha(image.getchannel("A").point(lambda a: 255 if a >= 128 else 0))
    return result


def remove_background(image):
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if r > 110 and b > 100 and g < r * .65 and g < b * .7:
                pixels[x, y] = (0, 0, 0, 0)
            elif a < 128:
                pixels[x, y] = (0, 0, 0, 0)
            else:
                pixels[x, y] = (r, g, b, 255)
    return image


def components(image):
    """8-connected components; retain labels to prevent neighbouring weapons leaking in."""
    w, h = image.size
    mask = bytearray(image.getchannel("A").tobytes())
    labels = array("I", [0]) * (w * h)
    items = []
    for start in range(w * h):
        if not mask[start]:
            continue
        ident = len(items) + 1
        stack = [start]
        mask[start] = 0
        area, x0, y0, x1, y1 = 0, w, h, 0, 0
        while stack:
            i = stack.pop()
            labels[i] = ident
            y, x = divmod(i, w)
            area += 1
            x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
            for ny in range(max(0, y - 1), min(h, y + 2)):
                for nx in range(max(0, x - 1), min(w, x + 2)):
                    k = ny * w + nx
                    if mask[k]:
                        mask[k] = 0
                        stack.append(k)
        items.append({"id": ident, "area": area, "box": (x0, y0, x1 + 1, y1 + 1)})
    return items, labels


def isolate(image, labels, items):
    ids = {item["id"] for item in items}
    boxes = [item["box"] for item in items]
    box = (min(b[0] for b in boxes), min(b[1] for b in boxes),
           max(b[2] for b in boxes), max(b[3] for b in boxes))
    crop = image.crop(box)
    w = image.width
    alpha = bytes(255 if labels[y * w + x] in ids else 0
                  for y in range(box[1], box[3]) for x in range(box[0], box[2]))
    crop.putalpha(Image.frombytes("L", crop.size, alpha))
    return crop


def character(source, output):
    source = remove_background(source)
    items, labels = components(source)
    large = sorted((i for i in items if i["area"] >= 250), key=lambda i: i["area"], reverse=True)
    # The large bust in the lower part is deliberately separate from nine full bodies.
    portraits = [i for i in large if (i["box"][1] + i["box"][3]) / 2 > source.height * .72]
    if not portraits:
        raise ValueError(f"{output}: no lower portrait; inspect source layout")
    portrait = max(portraits, key=lambda i: i["area"])
    bodies = [i for i in large if i != portrait][:9]
    if len(bodies) != 9:
        raise ValueError(f"{output}: expected nine separate full bodies, found {len(bodies)}")
    bodies.sort(key=lambda i: (i["box"][1] + i["box"][3]) / 2)
    bodies = [i for row in range(3) for i in sorted(bodies[row * 3:row * 3 + 3], key=lambda j: j["box"][0])]
    anchors = bodies + [portrait]
    groups = [[item] for item in anchors]
    major = {i["id"] for i in anchors}
    # Reattach detached pixels / small accessories to the nearest full body.
    for item in items:
        if item["id"] in major or item["area"] < 3:
            continue
        x0, y0, x1, y1 = item["box"]
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        def distance(anchor):
            a, b, c, d = anchor["box"]
            return max(a - cx, 0, cx - c) ** 2 + max(b - cy, 0, cy - d) ** 2
        nearest = min(range(10), key=lambda n: distance(anchors[n]))
        if distance(anchors[nearest]) < (source.width * .06) ** 2:
            groups[nearest].append(item)
    crops = [isolate(source, labels, group) for group in groups]
    # Shared standing height across the cast. Wide sword keys keep their scale,
    # rather than shrinking only an attack or making civilians larger than centurions.
    scale = min(44 / max(c.width for c in crops[:9]), 40 / crops[0].height,
                60 / max(c.height for c in crops[:9]))
    atlas = Image.new("RGBA", (144, 192))
    for n, crop in enumerate(crops[:9]):
        sprite = crop.resize((max(1, round(crop.width * scale)), max(1, round(crop.height * scale))), NEAREST)
        atlas.alpha_composite(sprite, ((n % 3) * 48 + (48 - sprite.width) // 2, (n // 3) * 64 + 62 - sprite.height))
    quantize(atlas).save(output)
    bust = crops[-1]
    bust.thumbnail((96, 96), NEAREST)
    portrait_image = Image.new("RGBA", (96, 96))
    portrait_image.alpha_composite(bust, ((96 - bust.width) // 2, 96 - bust.height))
    quantize(portrait_image).save(output.with_name(output.stem + "_portrait.png"))
    return {"components": len(items), "body_scale": scale, "source_boxes": [a["box"] for a in anchors]}


def resize_full(image, size):
    return quantize(image.resize(tuple(size), NEAREST))


def icon_atlas(source, output):
    source = remove_background(source)
    atlas = Image.new("RGBA", (112, 16))
    for n in range(7):
        x, y = n % 4, n // 4
        icon = source.crop((round(x * source.width / 4), round(y * source.height / 2),
                            round((x + 1) * source.width / 4), round((y + 1) * source.height / 2)))
        box = icon.getbbox()
        if box:
            icon = icon.crop(box)
            icon.thumbnail((14, 14), NEAREST)
            atlas.alpha_composite(icon, (n * 16 + (16 - icon.width) // 2, (16 - icon.height) // 2))
    quantize(atlas).save(output)
    return {"icons": 7, "frame_size": [16, 16]}


def wordmark(source, output):
    # Only the title is type, the original emblem itself is generated art.
    emblem = remove_background(source)
    emblem = emblem.crop(emblem.getbbox())
    emblem.thumbnail((62, 60), NEAREST)
    result = Image.new("RGBA", (256, 64))
    result.alpha_composite(emblem, (8 + (62 - emblem.width) // 2, (64 - emblem.height) // 2))
    glyphs = {
        'C': ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
        'I': ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
        'N': ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
        'S': ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        'L': ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        'A': ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        'U': ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
        'R': ["11110", "10001", "10001", "11110", "10100", "10010", "10001"]}
    draw = ImageDraw.Draw(result)
    cursor = 86
    for letter in 'CINIS LAURI':
        if letter == ' ':
            cursor += 6
            continue
        for y, row in enumerate(glyphs[letter]):
            for x, value in enumerate(row):
                if value == '1':
                    draw.rectangle((cursor + x * 2, 22 + y * 2, cursor + x * 2 + 1, 23 + y * 2), fill='#EDE3CC')
        cursor += 14
    draw.line((86, 43, 242, 43), fill='#A87B3D', width=1)
    draw.rectangle((86, 42, 88, 44), fill='#D9A441')
    draw.rectangle((240, 42, 242, 44), fill='#D9A441')
    quantize(result).save(output)
    return {"wordmark": "CINIS LAURI", "lettering": "original 5x7 bitmap glyphs"}


def parallax(source, output, layout, offsets_y):
    """Three authored horizontal panels, top=far, middle=mid, bottom=near."""
    w, h = source.size
    for n, name in enumerate(["far", "mid", "near"]):
        box = layout[n] if layout else (0, round(h * n / 3), w, round(h * (n + 1) / 3))
        layer = source.crop(tuple(box))
        if n:
            layer = remove_background(layer)
        layer = resize_full(layer, (320, 180))
        if offsets_y[n]:
            shifted = Image.new("RGBA", (320, 180))
            shifted.alpha_composite(layer, (0, offsets_y[n]))
            layer = shifted
        layer.save(output.with_name(output.stem + "_" + name + ".png"))
    comp = Image.new("RGBA", (320, 180))
    for name in ["far", "mid", "near"]:
        comp.alpha_composite(Image.open(output.with_name(output.stem + "_" + name + ".png")))
    comp.save(output)
    return {"layers": 3}


def process(entry):
    source_path = ROOT / entry["source"]
    output = ROOT / entry["file"]
    output.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source_path) as source:
        source = source.convert("RGBA")
        if entry.get("buttons_source_boxes"):
            buttons = Image.new("RGBA", (64, 80))
            for n, box in enumerate(entry["buttons_source_boxes"]):
                button = remove_background(source.crop(tuple(box))).resize((64, 20), NEAREST)
                buttons.alpha_composite(button, (0, n * 20))
            quantize(buttons).save(ROOT / "assets/ui/buttons.png")
            arrows = Image.new("RGBA", (32, 16))
            for n, box in enumerate(entry["arrows_source_boxes"]):
                arrow = remove_background(source.crop(tuple(box))).resize((16, 16), NEAREST)
                arrows.alpha_composite(arrow, (n * 16, 0))
            quantize(arrows).save(ROOT / "assets/ui/arrows.png")
        kind = entry["kind"]
        if kind == "icons":
            return icon_atlas(source, output)
        if kind == "logo":
            return wordmark(source, output)
        if kind == "character":
            return character(source, output)
        if kind == "parallax":
            return parallax(source, output, entry.get("layer_boxes"), entry.get("layer_offsets_y", [0, 0, 0]))
        if entry.get("crop"):
            source = source.crop(tuple(entry["crop"]))
        if entry.get("key_background", False):
            source = remove_background(source)
        image = resize_full(source, entry["size"])
        image.save(output)
        return {"size": list(image.size)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ids", nargs="*", help="Only rebuild these asset IDs; default all")
    parser.add_argument("--input", type=Path, help="Single-image mode")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--size", nargs=2, type=int, default=[48, 64])
    parser.add_argument("--crop", nargs=4, type=int)
    parser.add_argument("--remove-background", action="store_true")
    args = parser.parse_args()
    if args.input:
        if not args.output:
            parser.error("--output is required with --input")
        im = Image.open(args.input).convert("RGBA")
        if args.crop:
            im = im.crop(tuple(args.crop))
        if args.remove_background:
            im = remove_background(im)
        resize_full(im, args.size).save(args.output)
        return
    manifest = json.loads((ROOT / "tools/manifest.json").read_text())
    report = {}
    for entry in manifest["assets"]:
        if args.ids and entry["id"] not in args.ids:
            continue
        if not (ROOT / entry["source"]).exists():
            print(f"SKIP {entry['id']} — source not yet generated")
            continue
        report[entry["id"]] = process(entry)
        print(f"OK {entry['id']}")
    (ROOT / "docs/pixelize_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
