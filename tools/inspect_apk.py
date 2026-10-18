"""Fail the build on the wrong package, ABI, SDK, signing layout or size."""
from pathlib import Path
import json
import re
import sys
from zipfile import ZipFile

apk = Path(sys.argv[1])
metadata = Path(sys.argv[2]).read_text()
assert apk.stat().st_size <= 150 * 1024 * 1024, "APK exceeds 150 MiB"
assert "package: name='org.cinislauri.game'" in metadata
assert "versionName='0.5.1'" in metadata and "versionCode='8'" in metadata
assert "uses-permission: name='android.permission.INTERNET'" not in metadata
assert "uses-permission: name='android.permission.VIBRATE'" in metadata
assert re.search(r"sdkVersion:'24'", metadata), "Wrong minimum SDK"
assert re.search(r"targetSdkVersion:'36'", metadata), "Wrong target SDK"
with ZipFile(apk) as archive:
    libraries = [name for name in archive.namelist() if name.startswith("lib/")]
    assert libraries and all(name.startswith("lib/arm64-v8a/") for name in libraries)
    assert "assets/game.pck" in archive.namelist() or any(
        name.startswith("assets/") for name in archive.namelist())
    # These JSON files are read through FileAccess, so Godot's resource export
    # must include them explicitly. Check the delivered payload, not just source.
    root = Path(__file__).resolve().parents[1]
    for path in (root / 'story').rglob('*.json'):
        if path.name == 'test_routes.json':
            continue
        payload = 'assets/' + path.relative_to(root).as_posix()
        assert json.loads(archive.read(payload)) == json.loads(path.read_text()), payload
print(f"APK PASS: org.cinislauri.game 0.5.1, ARM64, SDK 24/36, {apk.stat().st_size / 1048576:.1f} MiB")
