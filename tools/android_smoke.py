"""Exercise the exported game on an emulator through adb touch input and real saves."""
import io
import json
import math
from pathlib import Path
import subprocess
import sys
import time
from PIL import Image

PACKAGE = "org.cinislauri.game"
OUTPUT = Path("build/android-smoke")
OUTPUT.mkdir(parents=True, exist_ok=True)


def adb(*args, binary=False, check=True):
    result = subprocess.run(["adb", *args], check=check, capture_output=True)
    return result.stdout if binary else result.stdout.decode(errors="replace").strip()


def screenshot(name):
    data = adb("exec-out", "screencap", "-p", binary=True)
    (OUTPUT / f"{name}.png").write_bytes(data)
    return Image.open(io.BytesIO(data)).size


def state():
    try:
        return json.loads(adb("exec-out", "run-as", PACKAGE, "cat", "files/cinis_story_v2.json"))
    except (ValueError, subprocess.CalledProcessError):
        return {}


def point(x, y):
    return str(round(offset_x + x * factor)), str(round(offset_y + y * factor))


def tap(x, y):
    adb("shell", "input", "tap", *point(x, y))


adb("install", "-r", sys.argv[1])
adb("shell", "wm", "size", "720x1280")
adb("shell", "settings", "put", "system", "accelerometer_rotation", "0")
adb("shell", "settings", "put", "system", "user_rotation", "1")
adb("logcat", "-c")
launch = adb("shell", "am", "start", "-W", "-n", PACKAGE + "/com.godot.game.GodotApp")
time.sleep(2)
width, height = screenshot("menu")
assert width > height, f"Landscape was not applied: {width}x{height}"
factor = max(1, math.floor(min(width / 320, height / 180)))
offset_x, offset_y = (width - 320 * factor) / 2, (height - 180 * factor) / 2
tap(160, 72)
for attempt in range(160):
    saved = state()
    episode = saved.get("gameplay", {}).get("encounter", {})
    if episode.get("beat") == "beat_ch01_s01":
        break
    tap(265, 167)
else:
    screenshot("failure_before_hub")
    raise AssertionError("Story input did not reach the first real RPG hub")
screenshot("hub_before")
# Hold the joystick northeast, then interact with the actual scribe.
position = point(56, 140)
adb("shell", "input", "swipe", *position, *position, "800")
tap(201, 162)
time.sleep(0.3)
saved = state()
assert saved["gameplay"]["encounter"]["state"]["quest"] == 1, "Touch interaction did not accept the hub quest"
node = saved["node"]
adb("shell", "input", "keyevent", "KEYCODE_HOME")
time.sleep(0.2)
adb("shell", "am", "force-stop", PACKAGE)
adb("shell", "am", "start", "-W", "-n", PACKAGE + "/com.godot.game.GodotApp")
time.sleep(1)
tap(160, 100)
time.sleep(0.5)
restored = state()
assert restored["node"] == node and restored["gameplay"]["encounter"]["state"]["quest"] == 1
assert restored["flags"] == saved["flags"]
screenshot("hub_after_cold_restart")
logs = adb("logcat", "-d", "-v", "brief")
(OUTPUT / "logcat.txt").write_text(logs)
for failure in ["SCRIPT ERROR:", "Parse Error:", "FATAL EXCEPTION: main", "Fatal signal"]:
    assert failure not in logs, failure
report = {"platform": "Android API 35 emulator, x86_64 smoke export", "commit_content": "same game as ARM64 release",
          "screen": [width, height], "story_to_hub": True, "joystick_and_interaction": True,
          "cold_restart_restore": True, "launch_output": launch, "physical_arm64_test": False}
(OUTPUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print("ANDROID SMOKE PASS:", report)
