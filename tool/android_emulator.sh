#!/bin/sh
# Project-local Android 16 emulator. No global SDK or AVD configuration changes.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tools="$root/../.toolchains"
export ANDROID_HOME="$tools/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_AVD_HOME="$tools/avd"
tingyu_avd=tingyu-api36
tingyu_port=5556
if [ "${TINGYU_EMULATOR_TEST:-0}" = 1 ]; then
  export ANDROID_AVD_HOME="$tools/regression-avd"
  tingyu_avd=tingyu-regression
  tingyu_port=5558
fi
for tingyu_jdk in "$tools"/jdk-*/Contents/Home; do
  if [ -x "$tingyu_jdk/bin/java" ]; then
    export JAVA_HOME="$tingyu_jdk"
    break
  fi
done
if [ ! -f "$ANDROID_HOME/system-images/android-36/google_apis/arm64-v8a/package.xml" ]; then
  echo 'Install emulator and system-images;android-36;google_apis;arm64-v8a with sdkmanager first.' >&2
  exit 1
fi
mkdir -p "$ANDROID_AVD_HOME"
if [ ! -f "$ANDROID_AVD_HOME/$tingyu_avd.ini" ]; then
  echo no | "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd --name "$tingyu_avd" --package 'system-images;android-36;google_apis;arm64-v8a' --path "$ANDROID_AVD_HOME/$tingyu_avd.avd"
  # Use a phone-resolution framebuffer rather than avdmanager's 320x640 default.
  tingyu_config="$ANDROID_AVD_HOME/$tingyu_avd.avd/config.ini"
  awk '!/^hw\.lcd\.(width|height|density)[[:space:]]*=|^skin\.(name|dynamic)[[:space:]]*=/' "$tingyu_config" > "$tingyu_config.hd"
  cat >> "$tingyu_config.hd" <<'CONFIG'
hw.lcd.width = 1080
hw.lcd.height = 2400
hw.lcd.density = 480
skin.name = 1080x2400
skin.dynamic = yes
CONFIG
  mv "$tingyu_config.hd" "$tingyu_config"
fi
# A music player needs output, not microphone capture. Keeping input disabled
# avoids the emulator's documented macOS/Bluetooth recording-route interference.
# https://developer.android.com/studio/run/emulator-troubleshooting
# Project-owned AVD only; retain user data and keep audio output enabled.
tingyu_config="$ANDROID_AVD_HOME/$tingyu_avd.avd/config.ini"
awk '!/^hw\.audio(Input|Output)[[:space:]]*=/' "$tingyu_config" > "$tingyu_config.audio"
printf '\nhw.audioInput = no\nhw.audioOutput = yes\n' >> "$tingyu_config.audio"
mv "$tingyu_config.audio" "$tingyu_config"
if [ "${TINGYU_EMULATOR_HEADLESS:-0}" = 1 ]; then
  exec "$ANDROID_HOME/emulator/emulator" -avd "$tingyu_avd" -port "$tingyu_port" -no-snapshot -no-audio -gpu swiftshader -no-window
fi
exec "$ANDROID_HOME/emulator/emulator" -avd "$tingyu_avd" -port "$tingyu_port" -no-snapshot -gpu auto
