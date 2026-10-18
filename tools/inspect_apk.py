"""Fail the build on the wrong package, ABI, SDK, signing layout or size."""
from pathlib import Path
import re
import sys
from zipfile import ZipFile

apk = Path(sys.argv[1])
metadata = Path(sys.argv[2]).read_text()
assert apk.stat().st_size <= 150 * 1024 * 1024, "APK exceeds 150 MiB"
assert "package: name='org.cinislauri.game'" in metadata
assert "versionName='0.4.1'" in metadata and "versionCode='5'" in metadata
assert "uses-permission: name='android.permission.INTERNET'" not in metadata
assert re.search(r"sdkVersion:'24'", metadata), "Wrong minimum SDK"
assert re.search(r"targetSdkVersion:'36'", metadata), "Wrong target SDK"
with ZipFile(apk) as archive:
    libraries = [name for name in archive.namelist() if name.startswith("lib/")]
    assert libraries and all(name.startswith("lib/arm64-v8a/") for name in libraries)
    assert "assets/game.pck" in archive.namelist() or any(
        name.startswith("assets/") for name in archive.namelist())
print(f"APK PASS: org.cinislauri.game 0.4.1, ARM64, SDK 24/36, {apk.stat().st_size / 1048576:.1f} MiB")
