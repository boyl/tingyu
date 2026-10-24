#!/bin/sh
# 对已构建签名的 Release .app 制作只读 DMG；不发布、不挂载或执行应用。
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
version=$(sed -n 's/^version: \([^+]*\)+.*/\1/p' pubspec.yaml)
app=build/macos/Build/Products/Release/tingyu.app
codesign --verify --deep --strict "$app"
staging=$(mktemp -d "${TMPDIR:-/tmp}/tingyu-dmg.XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM
ditto "$app" "$staging/tingyu.app"
ln -s /Applications "$staging/Applications"
mkdir -p artifacts
hdiutil create -volname "tingyu $version" -srcfolder "$staging" -format UDZO -ov "artifacts/tingyu-$version-macos-release.dmg"
hdiutil verify "artifacts/tingyu-$version-macos-release.dmg"
shasum -a 256 "artifacts/tingyu-$version-macos-release.dmg"
