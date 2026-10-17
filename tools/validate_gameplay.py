"""Check every connected encounter, choice witness, final asset and original sound."""
from collections import Counter
import json
from pathlib import Path
from PIL import Image
from pixelize import palette_colors

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads((ROOT / path).read_text())


def main():
    chapters = [read(f"story/chapters/ch{number:02d}.json") for number in range(1, 9)]
    index = read("story/chapter_index.json")["chapters"]
    assert index == [{key: value for key, value in chapter.items() if key not in ("nodes", "scenes")}
                     for chapter in chapters], "Lazy chapter index is stale"
    nodes = {node["id"]: node for chapter in chapters for node in chapter["nodes"]}
    beats = read("story/beats.json")["beats"]
    assert len({beat["id"] for beat in beats}) == len(beats)
    counts = Counter(beat["type"] for beat in beats)
    assert counts["tactical"] >= 10 and counts["platformer"] >= 10 and counts["rpg"] >= 8
    for beat in beats:
        assert beat["implementation"] == "playable", beat["id"]
        assert nodes[beat["node"]]["beat"] == beat["id"]
        assert nodes[beat["node"]]["kind"] == "beat"
        assert 1 <= beat["difficulty"] <= 10
        for category, ident in [("locations", beat["location"]), ("tiles", beat["tiles"])]:
            assert (ROOT / f"assets/{category}/{ident}.png").is_file()
    choices = {choice["id"] for node in nodes.values() for choice in node.get("choices", [])}
    witnesses = read("story/test_routes.json")
    routes = witnesses["routes"] + witnesses["scenarios"]
    covered = {decision["choice"] for route in routes for decision in route["decisions"]}
    assert choices <= covered, f"Uncovered choices: {choices - covered}"
    manifest = read("tools/final_art_manifest.json")
    palette = set(palette_colors())
    for path in sorted((ROOT / "assets/final").glob("*.png")):
        image = Image.open(path).convert("RGBA")
        colors = image.getcolors(1024)
        assert colors, f"Not quantized: {path}"
        pixels = {color for _, color in colors}
        assert {pixel[3] for pixel in pixels} <= {0, 255}, path
        used = {pixel[:3] for pixel in pixels if pixel[3]}
        assert used <= palette and len(used) <= len(palette), path
        if path.with_suffix(".png.import").is_file():
            assert "mipmaps/generate=false" in path.with_suffix(".png.import").read_text()
    for entry in manifest["assets"]:
        assert Image.open(ROOT / entry["file"]).size == tuple(entry["size"])
    for name in ["city", "march", "battle", "sword", "hit", "choice", "turn", "victory"]:
        data = (ROOT / f"assets/audio/{name}.ogg").read_bytes()
        assert data.startswith(b"OggS") and b"vorbis" in data[:128], name
    report = {"encounters": len(beats), "types": dict(counts), "routes": len(routes),
              "choices_covered": len(choices), "endings": sorted({route["ending"] for route in routes}),
              "logical_art_compositions": 36 + 30 + manifest["composition_count"],
              "game_pngs": len(list((ROOT / "assets").rglob("*.png"))),
              "music_layers": 3, "effects": 5, "errors": []}
    (ROOT / "docs/gameplay_validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("GAMEPLAY VALIDATION PASS:", report)


if __name__ == "__main__":
    main()
