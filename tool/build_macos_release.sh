#!/bin/sh
# 未公证开发发行：Release 构建、保留沙箱、ad-hoc 签名；不上传或执行。
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
mkdir -p artifacts/mac-native-release
sh tool/flutterw.sh build macos --release --no-pub --config-only > artifacts/mac-native-release/config.log 2>&1
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
  -derivedDataPath build/macos CODE_SIGNING_ALLOWED=NO build > artifacts/mac-native-release/build.log 2>&1
python3 - <<'PY'
from pathlib import Path
import subprocess
import plistlib
app = Path('build/macos/Build/Products/Release/tingyu.app')
frameworks = app / 'Contents/Frameworks'
for item in sorted(frameworks.iterdir()):
    if item.suffix in {'.framework', '.dylib'}:
        subprocess.run(['codesign', '--force', '--sign', '-', str(item)], check=True)
# 空的共享钥匙串声明没有可授权组，且会使 ad-hoc 预览被 AMFI 拒绝。
# ad-hoc 开发发行省略空组声明，保留沙箱与其他权限，不冒充 Developer ID。
entitlements = plistlib.loads(Path('macos/Runner/Release.entitlements').read_bytes())
if entitlements.get('keychain-access-groups') == []:
    del entitlements['keychain-access-groups']
preview_entitlements = Path('artifacts/mac-native-release/Preview.entitlements')
preview_entitlements.write_bytes(plistlib.dumps(entitlements))
subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements', str(preview_entitlements), str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(app.resolve())
PY
