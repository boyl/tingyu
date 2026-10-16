#!/bin/sh
# Project-local Android 16 emulator. No global SDK or AVD configuration changes.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tools="$root/../.toolchains"
export ANDROID_HOME="$tools/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_AVD_HOME="$tools/avd"
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
if [ ! -f "$ANDROID_AVD_HOME/tingyu-api36.ini" ]; then
  echo no | "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd --name tingyu-api36 --package 'system-images;android-36;google_apis;arm64-v8a' --path "$ANDROID_AVD_HOME/tingyu-api36.avd"
fi
if [ "${TINGYU_EMULATOR_HEADLESS:-0}" = 1 ]; then
  exec "$ANDROID_HOME/emulator/emulator" -avd tingyu-api36 -port 5556 -no-snapshot -no-audio -gpu swiftshader -no-window
fi
exec "$ANDROID_HOME/emulator/emulator" -avd tingyu-api36 -port 5556 -no-snapshot -gpu swiftshader
