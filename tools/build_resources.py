#!/usr/bin/env python3
"""Create reusable Godot SpriteFrames and TileSet resources from the asset manifest."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POSES = ["front", "side", "back", "idle", "walk", "run", "attack", "block", "hurt"]

for asset in json.loads((ROOT / "tools/manifest.json").read_text())["assets"]:
    path = ROOT / asset["file"]
    if not path.exists():
        continue
    if asset["category"] == "characters":
        text = '[gd_resource type="SpriteFrames" load_steps=11 format=3]\n\n'
        text += f'[ext_resource type="Texture2D" path="res://{asset["file"]}" id="1"]\n\n'
        for i, pose in enumerate(POSES):
            text += f'[sub_resource type="AtlasTexture" id="Pose_{pose}"]\natlas = ExtResource("1")\n'
            text += f'region = Rect2({i % 3 * 48}, {i // 3 * 64}, 48, 64)\n\n'
        text += '[resource]\nanimations = ['
        text += ',\n'.join('{"frames": [{"duration": 1.0, "texture": SubResource("Pose_' + pose + '")}], "loop": true, "name": &"' + pose + '", "speed": 4.0}' for pose in POSES)
        text += ']\n'
        path.with_suffix('.tres').write_text(text)
    elif asset["category"] == "tiles":
        text = '[gd_resource type="TileSet" load_steps=3 format=3]\n\n'
        text += f'[ext_resource type="Texture2D" path="res://{asset["file"]}" id="1"]\n\n'
        text += '[sub_resource type="TileSetAtlasSource" id="Atlas"]\ntexture = ExtResource("1")\ntexture_region_size = Vector2i(16, 16)\n'
        text += ''.join(f'{x}:{y}/0 = 0\n' for y in range(8) for x in range(8))
        text += '\n[resource]\ntile_size = Vector2i(16, 16)\nsources/0 = SubResource("Atlas")\n'
        path.with_suffix('.tres').write_text(text)
print('Godot resources rebuilt')
