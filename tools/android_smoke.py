"""Exercise the exported game on an emulator through adb touch input and real saves."""
import io
import json
import math
from pathlib import Path
import subprocess
import sys
import time
import re
import xml.etree.ElementTree as ET
from PIL import Image

PACKAGE = "org.cinislauri.game"
OUTPUT = Path("build/android-smoke")
OUTPUT.mkdir(parents=True, exist_ok=True)


def adb(*args, binary=False, check=True):
    result = subprocess.run(["adb", *args], capture_output=True)
    if check and result.returncode:
        raise RuntimeError(f"adb {' '.join(args)} failed: " +
                           result.stdout.decode(errors="replace") + result.stderr.decode(errors="replace"))
    return result.stdout if binary else result.stdout.decode(errors="replace").strip()


def screenshot(name, verify_render=False):
    data = adb("exec-out", "screencap", "-p", binary=True)
    (OUTPUT / f"{name}.png").write_bytes(data)
    image = Image.open(io.BytesIO(data)).convert("RGB")
    if verify_render:
        colors = image.getcolors(image.width * image.height)
        assert max(count for count, _ in colors) < image.width * image.height * 0.75, "Blank Android game frame"
    return image.size


def state():
    try:
        return json.loads(adb("exec-out", "run-as", PACKAGE, "cat", "files/cinis_story_v2.json"))
    except (ValueError, RuntimeError):
        return {}


def point(x, y):
    return str(round(offset_x + x * factor)), str(round(offset_y + y * factor))


def tap(x, y):
    adb("shell", "input", "tap", *point(x, y))


def dismiss_fullscreen_hint():
    adb("shell", "uiautomator", "dump", "/data/local/tmp/cinis-window.xml", check=False)
    xml = adb("exec-out", "cat", "/data/local/tmp/cinis-window.xml", check=False)
    if "Viewing full screen" not in xml and "immersive_mode" not in xml:
        return
    for node in ET.fromstring(xml).iter("node"):
        if node.get("text", "").lower() == "got it":
            left, top, right, bottom = map(int, re.findall(r"\d+", node.get("bounds", "")))
            adb("shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))
            time.sleep(0.3)


def record_failure(kind, value, traceback):
    try:
        (OUTPUT / "logcat.txt").write_text(adb("logcat", "-d", "-v", "brief", check=False))
        screenshot("failure")
    finally:
        sys.__excepthook__(kind, value, traceback)


sys.excepthook = record_failure


adb("install", "-r", sys.argv[1])
adb("shell", "wm", "size", "720x1280")
adb("shell", "wm", "density", "320")
adb("shell", "settings", "put", "system", "accelerometer_rotation", "0")
adb("shell", "settings", "put", "system", "user_rotation", "1")
adb("shell", "settings", "put", "secure", "immersive_mode_confirmations", "confirmed")
adb("logcat", "-c")
resolved = adb("shell", "cmd", "package", "resolve-activity", "--brief", "-a", "android.intent.action.MAIN",
               "-c", "android.intent.category.LAUNCHER", "-p", PACKAGE)
activity = resolved.splitlines()[-1].strip()
assert activity.startswith(PACKAGE + "/"), resolved
launch = adb("shell", "am", "start", "-W", "-n", activity)
time.sleep(2)
dismiss_fullscreen_hint()
width, height = screenshot("menu")
assert width > height, f"Landscape was not applied: {width}x{height}"
factor = min(width / 960, height / 540)
offset_x, offset_y = (width - 960 * factor) / 2, (height - 540 * factor) / 2
for attempt in range(20):
    tap(240, 170)
    if state().get("node"):
        break
    time.sleep(0.2)
for attempt in range(160):
    saved = state()
    episode = saved.get("gameplay", {}).get("encounter", {})
    if episode.get("beat") == "beat_ch01_s01":
        break
    tap(848, 488)
else:
    screenshot("failure_before_hub")
    raise AssertionError("Story input did not reach the first real RPG hub")
screenshot("hub_before", verify_render=True)
# Hold the joystick northeast, then interact with the actual scribe.
position = point(108, 470)
adb("shell", "input", "swipe", *position, *position, "800")
tap(590, 488)
time.sleep(0.3)
saved = state()
assert saved["gameplay"]["encounter"]["state"]["quest"] == 1, "Touch interaction did not accept the hub quest"
node = saved["node"]
adb("shell", "input", "keyevent", "KEYCODE_HOME")
time.sleep(0.2)
adb("shell", "am", "force-stop", PACKAGE)
adb("shell", "am", "start", "-W", "-n", activity)
time.sleep(2)
dismiss_fullscreen_hint()
before_x = saved["gameplay"]["encounter"]["state"]["x"]
for attempt in range(4):
    tap(240, 248)
    time.sleep(0.4)
    position = point(24, 482)
    adb("shell", "input", "swipe", *position, *position, "350")
    tap(590, 488)
    time.sleep(0.3)
    restored = state()
    if restored["gameplay"]["encounter"]["state"]["x"] < before_x - 3:
        break
else:
    raise AssertionError("The restored hub did not respond to joystick movement")
assert restored["node"] == node and restored["gameplay"]["encounter"]["state"]["quest"] == 1
assert restored["flags"] == saved["flags"]
screenshot("hub_after_cold_restart", verify_render=True)
logs = adb("logcat", "-d", "-v", "brief")
(OUTPUT / "logcat.txt").write_text(logs)
for failure in ["SCRIPT ERROR:", "Parse Error:", "Program linking failed", "FATAL EXCEPTION: main", "Fatal signal"]:
    assert failure not in logs, failure
report = {"platform": "Android API 35 emulator, x86_64 smoke export", "commit_content": "same game as ARM64 release",
          "screen": [width, height], "story_to_hub": True, "joystick_and_interaction": True,
          "cold_restart_restore": True, "post_restart_movement": True, "rendered_frames_verified": True,
          "launch_output": launch, "physical_arm64_test": False}
(OUTPUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print("ANDROID SMOKE PASS:", report)
