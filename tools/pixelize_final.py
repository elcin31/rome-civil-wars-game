"""Nine final compositions, using the existing nearest/48-colour pipeline."""
import json
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw, ImageFont
from pixelize import quantize, NEAREST

ROOT = Path(__file__).resolve().parents[1]


def main():
    manifest = json.loads((ROOT / "tools/final_art_manifest.json").read_text())
    for entry in manifest["assets"]:
        source = Image.open(ROOT / entry["source"]).convert("RGBA")
        if "cell" in entry:
            x, y = entry["cell"]
            source = source.crop((x * source.width // 2, y * source.height // 4,
                                  (x + 1) * source.width // 2, (y + 1) * source.height // 4))
            image = ImageOps.fit(source, tuple(entry["size"]), method=NEAREST)
            image.putalpha(255)
        else:
            source = source.crop(source.getbbox())
            foreground = Image.new("RGBA", (512, 512))
            icon = ImageOps.contain(source, (332, 332), method=NEAREST)
            foreground.alpha_composite(icon, ((512 - icon.width) // 2, (512 - icon.height) // 2))
            quantize(foreground).save(ROOT / "assets/final/adaptive_foreground.png")
            background = Image.new("RGBA", (512, 512), "#14151F")
            quantize(background).save(ROOT / "assets/final/adaptive_background.png")
            image = background.copy()
            icon = ImageOps.contain(source, (448, 448), method=NEAREST)
            image.alpha_composite(icon, ((512 - icon.width) // 2, (512 - icon.height) // 2))
        image = quantize(image)
        image.save(ROOT / entry["file"])
        if entry["id"] == "app_icon":
            quantize(image.resize((192, 192), NEAREST)).save(ROOT / "assets/final/app_launcher.png")
            for name in ["adaptive_foreground", "adaptive_background"]:
                adaptive = Image.open(ROOT / f"assets/final/{name}.png")
                quantize(adaptive.resize((432, 432), NEAREST)).save(ROOT / f"assets/final/{name}_432.png")
    board = Image.new("RGBA", (984, 660), "#14151F")
    draw = ImageDraw.Draw(board)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)
    for index, entry in enumerate(manifest["assets"]):
        x, y = (index % 3) * 328, (index // 3) * 220
        image = Image.open(ROOT / entry["file"])
        image = ImageOps.contain(image, (320, 192), method=NEAREST)
        board.alpha_composite(image, (x + (328 - image.width) // 2, y + 20 + (192 - image.height) // 2))
        draw.text((x + 5, y + 3), entry["id"], fill="#EDE3CC", font=font)
    quantize(board).save(ROOT / "docs/contact_final.png")
    print("FINAL ART PASS: 9 compositions, 14 game PNGs including Android icon sizes")


if __name__ == "__main__":
    main()
