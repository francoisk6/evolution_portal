# Command reference

All from `/home/evo/evolution/flutter/Workspace/evolution/evolution_portal`.

## 1. Run locally (fastest iteration — hot reload)

```bash
flutter devices                      # see what's connected

# Web, in Chrome
flutter run -d chrome

# Web, reachable from other machines on the LAN
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8899

# Connected Android phone / emulator
flutter run -d <device-id>
```

As the **DMP** app — add the defines to any of the above:

```bash
flutter run -d chrome \
  --dart-define=WORKSPACE_SLUG=dmp \
  --dart-define=WORKSPACE_NAME=DMP \
  --dart-define=API_BASE_URL=https://dmpapi.evolution-portal.com
```

For logo tweaks this is much faster than a release build — press `r` to hot
reload, `R` to restart. Asset changes need `R` (capital).

> Note: `flutter run` on Android also needs `--flavor dmp` (or `--flavor
> portal`) now that flavors exist. Web ignores flavors.

## 2. Build the APK (sideload / testing)

```bash
flutter build apk --release --flavor dmp \
  --dart-define=WORKSPACE_SLUG=dmp \
  --dart-define=WORKSPACE_NAME=DMP \
  --dart-define=API_BASE_URL=https://dmpapi.evolution-portal.com
# -> build/app/outputs/flutter-apk/app-dmp-release.apk
```

### Getting it onto a phone

```bash
# Over USB (needs USB debugging enabled)
~/Android/Sdk/platform-tools/adb devices
~/Android/Sdk/platform-tools/adb install -r \
  build/app/outputs/flutter-apk/app-dmp-release.apk

# Or over the LAN: copy into a served folder and download it on the phone
cp build/app/outputs/flutter-apk/app-dmp-release.apk build/web/dmp.apk
cd build/web && python3 -m http.server 8899 --bind 0.0.0.0
# then open http://<this-machine-ip>:8899/dmp.apk on the phone
```

Android blocks the first install with "isn't allowed to install unknown apps" —
enable it for the browser, then retry. Play Protect may also warn; that is
normal for a sideloaded build.

## 3. Build the app bundle (Play Store)

```bash
flutter build appbundle --release --flavor portal          # Evolution
flutter build appbundle --release --flavor dmp \           # DMP
  --dart-define=WORKSPACE_SLUG=dmp \
  --dart-define=WORKSPACE_NAME=DMP \
  --dart-define=API_BASE_URL=https://dmpapi.evolution-portal.com
```

Remember `--flavor` is now **mandatory** — a bare `flutter build appbundle` runs
for 80s and then fails with "Gradle build failed to produce an .aab file."

## 4. Web build (for `/var/www/v3_portal`)

```bash
flutter build web --release       # -> build/web/
```

## 5. Regenerate launcher icons (only if you change `launcher_icon_dmp.png`)

```bash
dart run flutter_launcher_icons
```

The header logo needs none of this — `assets/logos/<slug>.png` is picked up on
the next build.

---

## Reference values

| | Evolution | DMP |
|---|---|---|
| Flavor | `portal` | `dmp` |
| applicationId | `com.evolution_portal` | `com.dmp_portal` |
| App name | Evolution Portal | DMP |
| API base | `https://api.evolution-portal.com` | `https://dmpapi.evolution-portal.com` |
| Header logo | `assets/logo.png` | `assets/logos/dmp.png` |
| Launcher icon | `assets/launcher_icon.png` | `assets/launcher_icon_dmp.png` |
| Workspace switcher | shown when >1 workspace | hidden (build-locked) |

The flavor is **not** named `main` — that collides with Gradle's built-in `main`
source set and fails configuration.

Adding a workspace logo: drop `assets/logos/<slug>.png` (wide wordmark,
transparent background). No code change. A workspace with no file falls back to
its name as styled text, never to Evolution's logo.
