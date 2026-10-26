#Requires -Version 7.0
# 直接运行 SDK 内的 Dart 工具，避免依赖 cmd / Windows PowerShell 入口。
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments)
$ErrorActionPreference = 'Stop'
$flutterSdk = $env:FLUTTER_ROOT
if (-not $flutterSdk) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCommand) { $flutterSdk = Split-Path (Split-Path $flutterCommand.Source -Parent) -Parent }
}
if (-not $flutterSdk) { throw '请设置 FLUTTER_ROOT 为 Flutter SDK 目录。' }
$dart = Join-Path $flutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
$snapshot = Join-Path $flutterSdk 'bin/cache/flutter_tools.snapshot'
if (-not (Test-Path -LiteralPath $dart) -or -not (Test-Path -LiteralPath $snapshot)) {
    throw 'Flutter SDK 缺少 Dart 或 flutter_tools.snapshot，请使用完整官方 Windows SDK。'
}
$env:FLUTTER_ROOT = $flutterSdk
$env:NO_PROXY = (($env:NO_PROXY, 'localhost', '127.0.0.1', '::1' | Where-Object { $_ }) -join ',')
& $dart $snapshot --suppress-analytics --no-version-check @FlutterArguments
exit $LASTEXITCODE
