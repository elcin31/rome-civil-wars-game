"""Create a temporary x86_64 export for the emulator; production remains ARM64."""
from pathlib import Path
import sys

path = Path("export_presets.cfg")
source = path.read_text()
smoke = source.replace("preset.0", "preset.1").replace('name="Android"', 'name="AndroidSmoke"')
smoke = smoke.replace("runnable=true", "runnable=false")
smoke = smoke.replace('custom_features=""', 'custom_features="android_smoke"')
smoke = smoke.replace("architectures/arm64-v8a=true", "architectures/arm64-v8a=false\narchitectures/x86_64=true")
smoke = smoke.replace('export_path="build/cinis-lauri.apk"', f'export_path="{sys.argv[1]}"')
path.write_text(source + "\n" + smoke)
