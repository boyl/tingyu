#!/bin/sh
set -eu
# Debug/driver traffic must stay local even when the shell has an HTTP proxy.
export NO_PROXY="${NO_PROXY:+$NO_PROXY,}localhost,127.0.0.1,::1"
export no_proxy="${no_proxy:+$no_proxy,}localhost,127.0.0.1,::1"
tingyu_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tingyu_tools="$tingyu_root/../.toolchains"
if [ -d "$tingyu_tools/android-sdk" ]; then
  export ANDROID_HOME="$tingyu_tools/android-sdk"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
fi
for tingyu_jdk in "$tingyu_tools"/jdk-*/Contents/Home; do
  if [ -x "$tingyu_jdk/bin/java" ]; then
    export JAVA_HOME="$tingyu_jdk"
    export PATH="$JAVA_HOME/bin:$PATH"
    break
  fi
done
export GRADLE_USER_HOME="$tingyu_tools/gradle"
cd "$tingyu_root"
if [ -x "$tingyu_tools/flutter/bin/flutter" ]; then
  exec "$tingyu_tools/flutter/bin/flutter" "$@"
fi
exec flutter "$@"
