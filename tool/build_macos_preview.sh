#!/bin/sh
# 本机调试预览：保留沙箱权限，ad-hoc 签名；不发布或执行应用。
set -eu
tingyu_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$tingyu_root"
if [ -z "${DEVELOPER_DIR:-}" ]; then
  tingyu_selected=$(xcode-select -p)
  if [ -x "$tingyu_selected/usr/bin/xcodebuild" ] && [ -d "$tingyu_selected/Platforms" ]; then
    DEVELOPER_DIR="$tingyu_selected"
  elif [ -d /Applications/Xcode.app/Contents/Developer ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    echo '请通过 DEVELOPER_DIR 指定已初始化的 Xcode。' >&2
    exit 1
  fi
  export DEVELOPER_DIR
fi
xcodebuild -checkFirstLaunchStatus
if ! command -v pod >/dev/null 2>&1; then
  echo '缺少 CocoaPods，请安装后重试。' >&2
  exit 1
fi
mkdir -p artifacts/mac-native-preview
sh tool/flutterw.sh build macos --debug --no-pub --dart-define=TINGYU_MACOS_PREVIEW=true --config-only > artifacts/mac-native-preview/config.log 2>&1
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug \
  -derivedDataPath build/macos CODE_SIGNING_ALLOWED=NO build > artifacts/mac-native-preview/build.log 2>&1
python3 - <<'PY'
from pathlib import Path
import subprocess
import plistlib
app = Path('build/macos/Build/Products/Debug/tingyu.app')
frameworks = app / 'Contents/Frameworks'
for item in sorted(frameworks.iterdir()):
    if item.suffix in {'.framework', '.dylib'}:
        subprocess.run(['codesign', '--force', '--sign', '-', str(item)], check=True)
# 空的共享钥匙串声明没有可授权组，且会使 ad-hoc 预览被 AMFI 拒绝。
# 仅本地预览省略此空声明；保留沙箱与其余权限，正式工程声明不变。
entitlements = plistlib.loads(Path('macos/Runner/DebugProfile.entitlements').read_bytes())
if entitlements.get('keychain-access-groups') == []:
    del entitlements['keychain-access-groups']
preview_entitlements = Path('artifacts/mac-native-preview/Preview.entitlements')
preview_entitlements.write_bytes(plistlib.dumps(entitlements))
subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements', str(preview_entitlements), str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(app.resolve())
PY
