"""Produce the exact user delivery ZIP from the exported APK."""
from datetime import datetime, timezone
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import hashlib
import json
import subprocess

build = Path(__file__).resolve().parents[1] / "build"
commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=build.parent, text=True).strip()
apk = build / "cinis-lauri.apk"
info = {"commit": commit, "package": "org.cinislauri.game", "version": "0.4.0", "version_code": 4,
        "abi": "arm64-v8a", "min_sdk": 24, "target_sdk": 36, "bytes": apk.stat().st_size,
        "sha256": hashlib.sha256(apk.read_bytes()).hexdigest()}
(build / "build-info.json").write_text(json.dumps(info, indent=2) + "\n")
readme = build / "README_INSTALL.txt"
readme.write_text("""CINIS LAURI / Пепел лавра — Android 0.4.0
Пакет: org.cinislauri.game. Android 7.0+ (API 24), ARM64, ландшафт.

1. Скопируйте cinis-lauri.apk на Android и откройте файл.
2. Разрешите установку неизвестных приложений для браузера/файлового менеджера.
3. Нажмите «Установить», затем откройте CINIS LAURI.
4. После установки можно снова отключить разрешение неизвестных источников.

Это debug-сборка для прямой установки, без сетевых разрешений и мультиплеера.
Сохранения хранятся на устройстве. Удаление приложения удаляет сохранения.
Подпись CI debug; разные сборки могут потребовать удаления старой версии.
Управление: джойстик слева, действия справа; пауза — в верхней панели/«Назад».
Документация и ограничения: https://github.com/elcin31/rome-civil-wars-game
""", encoding="utf-8")
name = "rome-civil-wars-" + datetime.now(timezone.utc).strftime("%Y-%m-%d") + ".zip"
with ZipFile(build / name, "w", ZIP_DEFLATED) as archive:
    for path in (apk, readme, build / "apk-metadata.txt", build / "build-info.json"):
        archive.write(path, path.name)
print(build / name)
