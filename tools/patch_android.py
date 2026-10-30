"""Настраивает Android-проект: разрешения и название."""
import pathlib, re
ROOT = pathlib.Path("android/app")
m = ROOT / "src/main/AndroidManifest.xml"
t = m.read_text(encoding="utf-8")
for p in ["android.permission.INTERNET", "android.permission.READ_MEDIA_AUDIO", "android.permission.READ_EXTERNAL_STORAGE", "android.permission.WAKE_LOCK", "android.permission.FOREGROUND_SERVICE"]:
    if p not in t:
        t = re.sub(r"(<manifest[^>]*>)", rf'\1\n    <uses-permission android:name="{p}"/>', t, count=1)
t = re.sub(r'android:label="[^"]*"', 'android:label="Winter Music"', t, count=1)

m.write_text(t, encoding="utf-8")
# Новые версии file_picker требуют свежий compileSdk.
g = ROOT / "build.gradle.kts"
gs = g.read_text(encoding="utf-8")
gs = re.sub(r"compileSdk = [^\n]+", "compileSdk = 36", gs, count=1)
g.write_text(gs, encoding="utf-8")
print("patched")
