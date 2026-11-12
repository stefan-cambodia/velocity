# Building

Requirements (as on the development machine): Godot 4.7.2 with export templates, Android SDK
(build-tools 36+), JDK 17 configured in Godot's editor settings (`export/android/java_sdk_path`),
debug keystore configured, Python 3 with numpy and Pillow, and ffmpeg.

```sh
python3 tools/gen_textures.py            # textures + launcher icons -> assets/textures, assets/icons
python3 tools/gen_audio.py               # engine loops, SFX, music -> assets/audio (about 2 min)
python3 tools/gen_audio.py --check       # verifies formats, levels and loop seams
godot --headless --path . --import       # (re)import assets, refresh the class cache
godot --headless --path . -s tests/run_tests.gd
godot --headless --path . --export-debug "Android" build/android/velocity.apk           # arm64 APK (~34 MB)
godot --headless --path . --install-android-build-template --export-debug "Android AAB" build/android/velocity.aab
adb install -r build/android/velocity.apk
```

Presets (`export_presets.cfg`): **Android** (arm64 APK, no Gradle), **Android Emulator** (adds
x86_64), **Android AAB** (Gradle build, App Bundle). The release builds (`--export-release`) need a
release keystore set in the editor settings. None is configured, and the debug keystore must not
be used for Play uploads.

The generated textures and audio are committed as assets but can always be rebuilt from the
scripts. Track worlds are built at load time from `TrackLibrary` data. There is no baking step.
