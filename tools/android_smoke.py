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
TAPS = []


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



def ui():
    try:
        data = json.loads(adb("exec-out", "run-as", PACKAGE, "cat", "files/cinis_ui_layout.json"))
    except (ValueError, RuntimeError):
        return {}
    density = max(1.0, data.get("dpi", 160) / 160.0)
    for button in data.get("buttons", []):
        assert min(button["rect"][2:]) / density >= 47.9, "Android target below 48 dp: " + button["text"]
    return data


def wait_for_fresh_layout():
    # The probe is written every 250 ms. A tap can change the screen before the
    # next probe; immediately reusing old Next coordinates can hit the hub Journal.
    previous = ui().get("frame", -1)
    updates = 0
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        current = ui().get("frame", -1)
        if current > previous:
            previous = current
            updates += 1
            if updates == 2:
                return
        time.sleep(0.05)
    raise AssertionError("Native layout probe did not acknowledge the touch")


def tap_caption(caption, allow_hub=False):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        layout = ui()
        if allow_hub and layout.get("encounter_type") == "rpg":
            return
        for button in layout.get("buttons", []):
            if button["text"] == caption and not button["disabled"]:
                x, y, width, height = button["rect"]
                TAPS.append({"caption": caption, "frame": layout.get("frame"),
                             "rect": button["rect"], "mode": layout.get("mode")})
                (OUTPUT / "taps.json").write_text(json.dumps(TAPS, ensure_ascii=False, indent=2))
                adb("shell", "input", "tap", str(round(x + width / 2)), str(round(y + height / 2)))
                wait_for_fresh_layout()
                return
        time.sleep(0.1)
    raise AssertionError("Visible enabled button not found: " + caption)


def wait_for_hub():
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if ui().get("encounter_type") == "rpg":
            return
        time.sleep(0.1)
    raise AssertionError("RPG interface did not appear")


def hold_joystick(axis_x, axis_y, duration):
    data = ui()
    x, y, radius = data["joystick"]
    point = (str(round(x + axis_x * radius)), str(round(y + axis_y * radius)))
    adb("shell", "input", "swipe", *point, *point, str(duration))
    # Context actions move with the hero. Also settle the probe after movement,
    # before resolving the position of the next button. Pending native validation.
    wait_for_fresh_layout()


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
        (OUTPUT / "failure-ui.json").write_text(json.dumps(ui(), ensure_ascii=False, indent=2))
        (OUTPUT / "failure-state.json").write_text(json.dumps(state(), ensure_ascii=False, indent=2))
        screenshot("failure")
    finally:
        sys.__excepthook__(kind, value, traceback)


sys.excepthook = record_failure


assert adb("shell", "getprop", "ro.kernel.qemu") == "1", "This smoke runner requires an emulator"
adb("install", "-r", sys.argv[1])
adb("shell", "pm", "clear", PACKAGE)
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
tap_caption("Новая игра")
for attempt in range(160):
    saved = state()
    episode = saved.get("gameplay", {}).get("encounter", {})
    if episode.get("beat") == "beat_ch01_s01":
        break
    tap_caption("Дальше", allow_hub=True)
else:
    screenshot("failure_before_hub")
    raise AssertionError("Story input did not reach the first real RPG hub")
wait_for_hub()
screenshot("hub_before", verify_render=True)
# Hold the joystick northeast, then interact with the actual scribe.
hold_joystick(0.96, -0.27, 800)
tap_caption("Говорить")
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
tap_caption("Продолжить")
wait_for_hub()
hold_joystick(-1, 0, 350)
tap_caption("Что дальше?")
time.sleep(0.3)
restored = state()
assert restored["gameplay"]["encounter"]["state"]["x"] < before_x - 3, "Restored hub did not respond to joystick"
assert restored["node"] == node and restored["gameplay"]["encounter"]["state"]["quest"] == 1
assert restored["flags"] == saved["flags"]
screenshot("hub_after_cold_restart", verify_render=True)
logs = adb("logcat", "-d", "-v", "brief")
(OUTPUT / "logcat.txt").write_text(logs)
for failure in ["SCRIPT ERROR:", "Parse Error:", "Program linking failed", "FATAL EXCEPTION: main", "Fatal signal"]:
    assert failure not in logs, failure
report = {"platform": "Android API 35 emulator, x86_64 smoke export", "commit_content": "same game as ARM64 release",
          "screen": [width, height], "story_to_hub": True, "joystick_and_interaction": True,
          "cold_restart_restore": True, "post_restart_movement": True, "rendered_frames_verified": True, "native_layout_probe": True, "android_48dp_checked": True,
          "launch_output": launch, "physical_arm64_test": False}
(OUTPUT / "ui-layout.json").write_text(json.dumps(ui(), ensure_ascii=False, indent=2) + "\n")
(OUTPUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print("ANDROID SMOKE PASS:", report)
