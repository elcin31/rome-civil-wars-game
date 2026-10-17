"""Write local editor paths only; the generated signing key stays outside Git."""
import json
from pathlib import Path
import sys

sdk, java, keystore = sys.argv[1:]
destination = Path.home() / ".config/godot/editor_settings-4.6.tres"
destination.parent.mkdir(parents=True, exist_ok=True)
settings = {
    "export/android/android_sdk_path": sdk,
    "export/android/java_sdk_path": java,
    "export/android/debug_keystore": keystore,
    "export/android/debug_keystore_user": "androiddebugkey",
    "export/android/debug_keystore_pass": "android",
}
destination.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' +
                       "".join(f"{key} = {json.dumps(value)}\n" for key, value in settings.items()))
