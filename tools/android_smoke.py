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
import traceback as traceback_module
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
    # before resolving the position of the next button.
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
        (OUTPUT / "failure.txt").write_text("".join(traceback_module.format_exception(kind, value, traceback)))
        (OUTPUT / "logcat.txt").write_text(adb("logcat", "-d", "-v", "brief", check=False))
        (OUTPUT / "failure-ui.json").write_text(json.dumps(ui(), ensure_ascii=False, indent=2))
        (OUTPUT / "failure-state.json").write_text(json.dumps(state(), ensure_ascii=False, indent=2))
        screenshot("failure")
    finally:
        sys.__excepthook__(kind, value, traceback)


sys.excepthook = record_failure


assert adb("shell", "getprop", "ro.kernel.qemu") == "1", "This smoke runner requires an emulator"
# The stock Messages app can ANR during the Google APIs image's first boot.
# Its system dialog intercepts otherwise valid game taps. Scope this setup to
# the already-verified disposable emulator; the game does not use SMS.
adb("shell", "am", "force-stop", "com.google.android.apps.messaging", check=False)
adb("shell", "pm", "disable-user", "--user", "0", "com.google.android.apps.messaging", check=False)
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
launch_begin = time.monotonic()
launch = adb("shell", "am", "start", "-W", "-n", activity)
menu_deadline = time.monotonic() + 12
while ui().get("mode") != "menu" and time.monotonic() < menu_deadline:
    time.sleep(0.1)
launch_to_menu = round(time.monotonic() - launch_begin, 3)
assert ui().get("mode") == "menu", "Cold launch did not reach menu"
time.sleep(0.3)
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
# Remove only debug layout telemetry so a previous process cannot satisfy the
# menu timing check. The actual story save remains untouched.
adb("shell", "run-as", PACKAGE, "rm", "-f", "files/cinis_ui_layout.json")
restart_begin = time.monotonic()
restart_launch = adb("shell", "am", "start", "-W", "-n", activity)
restart_deadline = time.monotonic() + 12
while ui().get("mode") != "menu" and time.monotonic() < restart_deadline:
    time.sleep(0.1)
restart_to_menu = round(time.monotonic() - restart_begin, 3)
assert ui().get("mode") == "menu", "Subsequent cold launch did not reach menu"
dismiss_fullscreen_hint()
before_x = saved["gameplay"]["encounter"]["state"]["x"]
tap_caption("Продолжить")
if ui().get("mode") == "recap":
    tap_caption("К истории")
wait_for_hub()
hold_joystick(-1, 0, 350)
tap_caption("Что дальше?")
time.sleep(0.3)
restored = state()
assert restored["gameplay"]["encounter"]["state"]["x"] < before_x - 3, "Restored hub did not respond to joystick"
assert restored["node"] == node and restored["gameplay"]["encounter"]["state"]["quest"] == 1
assert restored["flags"] == saved["flags"]
screenshot("hub_after_cold_restart", verify_render=True)
adb("shell", "input", "keyevent", "KEYCODE_BACK")
wait_for_fresh_layout()
assert ui().get("mode") == "pause", "Android Back must open pause without exiting"
screenshot("android_back_pause", verify_render=True)
tap_caption("Продолжить")
wait_for_hub()
# Final build: approach each station by actual joystick gestures, never editing the save.
def approach(station_id):
    for attempt in range(16):
        layout = ui()
        hub = layout.get("hub", {})
        if not hub:
            raise AssertionError("Final native hub telemetry missing")
        target = next(s for s in hub["stations"] if s["id"] == station_id)
        dx, dy = target["x"] - hub["hero"][0], target["y"] - hub["hero"][1]
        distance = math.hypot(dx, dy)
        if distance < 27:
            return
        hold_joystick(dx / distance * 0.95, dy / distance * 0.95,
                      max(90, min(450, round((distance - 22) / 70 * 1000))))
    raise AssertionError("Joystick approach failed: " + station_id)

if ui().get("hub"):
    approach("supplies")
    tap_caption("Взять")
    assert state()["gameplay"]["encounter"]["state"]["quest"] == 2
    screenshot("supplies_collected", verify_render=True)
    approach("witness")
    tap_caption("Передать")
    assert state()["gameplay"]["encounter"]["state"]["quest"] == 3
    screenshot("supplies_delivered", verify_render=True)
    approach("exit")
    tap_caption("В путь")
    tap_caption("Продолжить")
    for attempt in range(180):
        layout = ui()
        if layout.get("encounter_type") == "cutscene":
            break
        if layout.get("mode") == "loading":
            time.sleep(0.4)
        elif layout.get("story_choices"):
            tap_caption(layout["story_choices"][0])
        else:
            tap_caption("Дальше")
    else:
        raise AssertionError("First cinematic not reached through story")
    screenshot("cinematic", verify_render=True)
    tap_caption("Пропустить")
    cinematic = ui()["cinematic"]
    assert cinematic["waiting_choice"]
    tap_caption(cinematic["choice"][0]["text"]["ru"])
    tap_caption("Пропустить")
    screenshot("cinematic_result", verify_render=True)
    tap_caption("Принять последствия")
    assert "beat_ch01_s03" in state()["cutscenes"]

# Exercise the new library with the real Android keyboard and touch callbacks.
adb("shell", "settings", "put", "secure", "show_ime_with_hard_keyboard", "1")
tap_caption("Пауза")
tap_caption("Главное меню")
tap_caption("Хроника")
captions = lambda: [b["text"] for b in ui().get("buttons", []) if not b["disabled"]]
assert "Гай Юлий Цезарь" in captions()
search_button = next(b for b in ui()["buttons"] if b["text"] == "Найти")
x, y, box_width, box_height = search_button["rect"]
adb("shell", "input", "tap", str(round(x * 0.5)), str(round(y + box_height / 2)))
wait_for_fresh_layout()
adb("shell", "input", "text", "54")
wait_for_fresh_layout()
screenshot("chronicle_keyboard", verify_render=True)
(OUTPUT / "keyboard-state.txt").write_text(adb("shell", "dumpsys", "input_method"))
adb("shell", "input", "keyevent", "KEYCODE_BACK")
wait_for_fresh_layout()
tap_caption("Найти")
assert "Гай Юлий Цезарь" not in captions(), "Android search query was lost or not applied"
assert "Квинт Туллий Цицерон" in captions()
screenshot("chronicle_filtered", verify_render=True)
tap_caption("Квинт Туллий Цицерон")
adb("shell", "input", "swipe", str(round(width * .75)), str(round(height * .62)),
    str(round(width * .75)), str(round(height * .35)), "400")
wait_for_fresh_layout()
screenshot("chronicle_article", verify_render=True)
tap_caption("К списку")
tap_caption("Галерея")
tap_caption("Ров, который ещё не выкопан")
tap_caption("+")
adb("shell", "input", "swipe", str(round(width * .5)), str(round(height * .45)),
    str(round(width * .65)), str(round(height * .5)), "350")
wait_for_fresh_layout()
screenshot("gallery_zoom", verify_render=True)
tap_caption("К списку")
tap_caption("Свиток судеб")
screenshot("fate", verify_render=True)
tap_caption("Карта")
screenshot("campaign", verify_render=True)
tap_caption("Назад")
tap_caption("Настройки")
tap_caption("Комфорт")
tap_caption("Левая рука: выкл")
assert "Левая рука: вкл" in captions()
config = adb("exec-out", "run-as", PACKAGE, "cat", "files/settings.cfg")
assert re.search(r"left_handed\s*=\s*true", config)
adb("shell", "am", "force-stop", PACKAGE)
adb("shell", "run-as", PACKAGE, "rm", "-f", "files/cinis_ui_layout.json")
adb("shell", "am", "start", "-W", "-n", activity)
deadline = time.monotonic() + 12
while ui().get("mode") != "menu" and time.monotonic() < deadline:
    time.sleep(.1)
assert ui().get("mode") == "menu"
tap_caption("Настройки")
tap_caption("Комфорт")
assert "Левая рука: вкл" in captions(), "Comfort setting did not survive process restart"
screenshot("comfort_restored", verify_render=True)
tap_caption("Левая рука: вкл")

logs = adb("logcat", "-d", "-v", "brief")
(OUTPUT / "logcat.txt").write_text(logs)
for failure in ["SCRIPT ERROR:", "Parse Error:", "Program linking failed", "FATAL EXCEPTION: main", "Fatal signal"]:
    assert failure not in logs, failure
memory = adb("shell", "dumpsys", "meminfo", PACKAGE)
(OUTPUT / "meminfo.txt").write_text(memory)
pss = re.search(r"TOTAL PSS:\s*(\d+)", memory)
report = {"platform": "Android API 35 emulator, x86_64 smoke export", "commit_content": "same game as ARM64 release",
          "screen": [width, height], "story_to_hub": True, "joystick_and_interaction": True,
          "cold_restart_restore": True, "post_restart_movement": True, "android_back_pause_resume": True, "rendered_frames_verified": True, "native_layout_probe": True, "pickup_delivery_and_cinematic": bool(ui().get("hub") or state().get("cutscenes")), "android_48dp_checked": True,
          "launch_output": launch, "launch_to_menu_seconds": launch_to_menu,
          "first_install_launch_to_menu_seconds": launch_to_menu,
          "subsequent_cold_launch_output": restart_launch,
          "subsequent_cold_launch_to_menu_seconds": restart_to_menu,
          "android_keyboard_search": True, "gallery_zoom_and_pan": True,
          "comfort_restart_restore": True, "memory_snapshot_mode": ui().get("mode"),
          "emulator_pss_mib": round(int(pss[1])/1024, 2) if pss else None, "physical_arm64_test": False}
(OUTPUT / "ui-layout.json").write_text(json.dumps(ui(), ensure_ascii=False, indent=2) + "\n")
(OUTPUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print("ANDROID SMOKE PASS:", report)
