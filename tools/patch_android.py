"""Настраивает Android-проект: разрешения и название."""
import pathlib, re
ROOT = pathlib.Path("android/app")
m = ROOT / "src/main/AndroidManifest.xml"
t = m.read_text(encoding="utf-8")
for p in ["android.permission.INTERNET", "android.permission.READ_MEDIA_AUDIO", "android.permission.READ_EXTERNAL_STORAGE", "android.permission.WAKE_LOCK", "android.permission.FOREGROUND_SERVICE", "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK", "android.permission.POST_NOTIFICATIONS"]:
    if p not in t:
        t = re.sub(r"(<manifest[^>]*>)", rf'\1\n    <uses-permission android:name="{p}"/>', t, count=1)
t = re.sub(r'android:label="[^"]*"', 'android:label="Winter Music"', t, count=1)
# Фоновое воспроизведение и управление с экрана блокировки (audio_service).
if "com.ryanheise.audioservice.AudioService" not in t:
    t = t.replace("</application>", """    <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
    </application>""", 1)

m.write_text(t, encoding="utf-8")
# MainActivity должна быть AudioServiceActivity, иначе audio_service не подключится.
for act in ROOT.glob("src/main/kotlin/**/MainActivity.kt"):
    a = act.read_text(encoding="utf-8")
    a = a.replace("import io.flutter.embedding.android.FlutterActivity", "import com.ryanheise.audioservice.AudioServiceActivity")
    a = re.sub(r"class MainActivity\s*:\s*FlutterActivity\(\)", "class MainActivity : AudioServiceActivity()", a)
    if "AudioServiceActivity()" not in a:
        raise SystemExit("PATCH ERROR: MainActivity не переделан под AudioServiceActivity")
    act.write_text(a, encoding="utf-8")
# Новые версии file_picker требуют свежий compileSdk.
g = ROOT / "build.gradle.kts"
gs = g.read_text(encoding="utf-8")
gs = re.sub(r"compileSdk = [^\n]+", "compileSdk = 36", gs, count=1)
g.write_text(gs, encoding="utf-8")
# Плагины, собранные под старый compileSdk (file_picker), поднимаем до 36.
root = pathlib.Path("android/build.gradle.kts")
rs = root.read_text(encoding="utf-8")
if "compileSdkVersion" not in rs:
    rs = """subprojects {
    afterEvaluate {
        val ext = extensions.findByName("android")
        if (ext != null) {
            try {
                ext.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType).invoke(ext, 36)
            } catch (e: Exception) {
            }
        }
    }
}

""" + rs
    root.write_text(rs, encoding="utf-8")
print("patched")
