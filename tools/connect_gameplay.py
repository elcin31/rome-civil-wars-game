"""Attach one chapter's data-driven encounters without rewriting its prose."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads((ROOT / path).read_text())


def write(path, data):
    (ROOT / path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def redirect(value, before, target):
    if isinstance(value, dict):
        for key, child in value.items():
            if key in ("next", "goto", "entry") and child == before:
                value[key] = target
            else:
                redirect(child, before, target)
    elif isinstance(value, list):
        for child in value:
            redirect(child, before, target)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("chapter", type=int, choices=range(1, 9))
    args = parser.parse_args()
    prefix = f"ch{args.chapter:02d}_"
    chapter_path = f"story/chapters/ch{args.chapter:02d}.json"
    chapter = read(chapter_path)
    beats = read("story/beats.json")
    index = {beat["id"]: beat for beat in beats["beats"]}
    for spec in read("story/gameplay_catalog.json")["encounters"]:
        if not spec["scene"].startswith(prefix):
            continue
        node_id = spec["node"]
        if not any(node["id"] == node_id for node in chapter["nodes"]):
            before = spec["insert_before"]
            assert any(node["id"] == before for node in chapter["nodes"]), before
            redirect(chapter, before, node_id)
            chapter["nodes"].append({"id": node_id, "scene": spec["scene"],
                "kind": "beat", "beat": spec["id"], "speaker": "narrator", "portrait": "",
                "text": {"ru": "", "en": ""}, "next": before})
        else:
            actual = next(node for node in chapter["nodes"] if node["id"] == node_id)
            assert actual.get("beat") == spec["id"], f"Node collision: {node_id}"
        record = {key: value for key, value in spec.items() if key != "insert_before"}
        if spec["id"] in index:
            index[spec["id"]].update(record)
        else:
            beats["beats"].append(record)
            index[spec["id"]] = record
    write(chapter_path, chapter)
    write("story/beats.json", beats)
    print(f"Connected chapter {args.chapter}; prose preserved.")


if __name__ == "__main__":
    main()
