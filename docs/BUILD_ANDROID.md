# Building Enough for Android

This is the step-by-step recipe to produce installable Android builds of **Enough**:

- a **debug APK** for sideloading onto a device (testing), and
- a signed **release AAB** for the Google Play Store (the shipping artifact).

The project is already configured for this — see `game/export_presets.cfg`. You only
have to install the toolchain, supply a keystore, and run one command.

> CI automates all of this in `.github/workflows/android.yml` (runs on `v*` tags /
> manual dispatch). Read that file for the canonical, reproducible recipe.

---

## 1. Prerequisites (one-time)

| Tool | Version | Notes |
|------|---------|-------|
| Godot | **4.3-stable** | Standard (not .NET) build. `godot --version` must report `4.3.stable`. |
| Export templates | **4.3-stable** | Must match the engine exactly. |
| JDK | **17** (Temurin/OpenJDK) | Godot 4.3's Gradle Android template requires JDK 17. |
| Android SDK | platform-tools, `build-tools;34.0.0`, `platforms;android-34` | Target SDK 34. |
| Android NDK | matched to the SDK (installed via `sdkmanager` or the editor) | Needed for the native libraries. |

### Install export templates (matching 4.3)
Either from the editor — **Editor → Manage Export Templates → Download and Install** —
or by hand:

```bash
BASE="https://github.com/godotengine/godot/releases/download/4.3-stable"
curl -fsSL -o /tmp/templates.tpz "$BASE/Godot_v4.3-stable_export_templates.tpz"
mkdir -p ~/.local/share/godot/export_templates/4.3.stable
unzip -o /tmp/templates.tpz -d /tmp/templates
mv /tmp/templates/templates/* ~/.local/share/godot/export_templates/4.3.stable/
```

### Install the JDK + Android SDK
- Install JDK 17 and note its path (`$JAVA_HOME`).
- Install the Android command-line tools, then:

```bash
sdkmanager --install "platform-tools" "build-tools;34.0.0" "platforms;android-34" "ndk;25.2.9519653"
yes | sdkmanager --licenses
```

### Point Godot at the JDK + SDK
In the editor: **Editor → Editor Settings → Export → Android** and set
**Java SDK Path** and **Android SDK Path**. (For headless/CI, write these into
`~/.config/godot/editor_settings-4.tres` — see `android.yml`.)

### Install the Gradle build template into the project
The preset uses `gradle_build/use_gradle_build=true`, so the project needs the Gradle
build files under `game/android/build/` (git-ignored). From the editor:
**Project → Install Android Build Template**, or headless:

```bash
godot --headless --path game --install-android-build-template
```

---

## 2. Create a signing keystore

**Never commit the keystore or its passwords.** `.gitignore` blocks `*.keystore`,
`*.jks`, and `keystore.properties`.

```bash
keytool -genkeypair -v \
  -keystore enough-release.keystore \
  -alias enough \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storetype pkcs12
```

Store the file and its passwords in a password manager. If you enroll in
**Google Play App Signing** (recommended), this is your *upload* key — Google holds
the app signing key.

### Where the keystore values go
`export_presets.cfg` deliberately contains **no** secrets. Supply them at build time
by either:

- **Editor:** select the preset → fill *Keystore* / *User* / *Password* fields. These
  land in `game/export_presets.cfg.local` (git-ignored), **not** the committed file.
- **Headless / CI:** environment variables Godot reads:

  ```bash
  export GODOT_ANDROID_KEYSTORE_DEBUG_PATH=/path/to/debug.keystore
  export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
  export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android

  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/enough-release.keystore
  export GODOT_ANDROID_KEYSTORE_RELEASE_USER=enough
  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=********
  ```

A throwaway **debug** keystore (for the debug APK only):

```bash
keytool -keyalg RSA -genkeypair -alias androiddebugkey \
  -keypass android -keystore debug.keystore \
  -storepass android -dname "CN=Android Debug,O=Android,C=US" \
  -validity 9999 -deststoretype pkcs12
```

---

## 3. Build

From the repo root. Output goes to `build/` (git-ignored).

### Release AAB (Play Store) — the shipping artifact
```bash
mkdir -p build
godot --headless --path game --export-release "Android" ../build/enough.aab
```

### Debug APK (sideload / device testing)
```bash
mkdir -p build
godot --headless --path game --export-debug "Android APK" ../build/enough-debug.apk
```

> Paths are relative to `game/` because `--path game` sets the working dir; the preset's
> own `export_path` (`../build/enough.aab`) already resolves to `build/` at repo root.

---

## 4. Test the debug APK on a device

1. Enable **Developer options → USB debugging** on the phone (Android 7 / API 24+).
2. Connect over USB and confirm it's visible:
   ```bash
   adb devices
   ```
3. Install and launch:
   ```bash
   adb install -r build/enough-debug.apk
   adb shell monkey -p com.divyangchauhan.enough -c android.intent.category.LAUNCHER 1
   ```
4. Verify: portrait lock, touch input, and that **haptics** buzz on choices
   (`Input.vibrate_handheld` needs the `VIBRATE` permission, which the preset grants).
5. Read logs while playing:
   ```bash
   adb logcat -s godot
   ```

You can also one-step deploy from the editor with a device attached
(**Remote Deploy / Run on Android**).

---

## 5. Google Play upload

1. **Play Console → Create app.** App name **Enough**, package
   **`com.divyangchauhan.enough`**. Type: Game. Free or paid → **Paid**.
2. **Pricing:** premium one-time purchase (~$4.99, see PRD §9). **No ads, no IAP.**
3. **App signing:** opt into Play App Signing; upload with the *upload* keystore above.
4. **Data safety:** declare **no data collected, no data shared**. The app is fully
   offline — no `INTERNET` permission, no analytics, no accounts. The only permission
   requested is `VIBRATE` (haptic feedback).
5. **Content rating:** complete the IARC questionnaire. Emotional themes, no violence /
   sexual content / gambling; expect a low rating (e.g. Everyone / PEGI 3–7). Answer
   honestly about mature/thematic content.
6. **Store listing:** screenshots (portrait), short + full description, the
   512×512 icon (`game/assets/icons/icon_store_512.png` is the source), feature graphic.
7. **Release:** upload `build/enough.aab` to a testing track first (internal/closed),
   validate on real devices, then promote to production.

---

## Preset reference (what's already configured)

| Setting | Value |
|---------|-------|
| Package / unique name | `com.divyangchauhan.enough` |
| App name | Enough |
| Orientation | Portrait (set in `project.godot`) |
| Min SDK | 24 (Android 7) |
| Target SDK | 34 |
| Architectures | `arm64-v8a` + `armeabi-v7a` |
| Build system | Gradle (`use_gradle_build=true`) |
| Permissions | `VIBRATE` only (no internet/ads — premium offline) |
| AAB preset | `Android` → `build/enough.aab` (release/Play Store) |
| APK preset | `Android APK` → `build/enough-debug.apk` (sideload) |
| Icons | `game/assets/icons/` (512 store + 432 adaptive fg/bg) |

### Regenerating icons
Icons are rasterized from the SVG sources in `game/assets/icons/` (no external
rasterizer needed — Godot does it):

```bash
godot --headless --path game --script tools/RenderIcons.gd
```

---

## What a human must do before a real Play Store build

These cannot be done in this repo / a stock CI box and are on you:

1. **Install export templates** matching 4.3 (large download).
2. **Install JDK 17 + Android SDK/NDK** and point Godot at them.
3. **Create a release keystore** and keep it + passwords secret. Add them as GitHub
   secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
   `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) for the `android.yml` release path.
4. **Create the Play Console app**, set pricing, fill data-safety + content rating.
