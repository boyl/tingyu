#Requires -Version 7.0
# 为未开启开发者模式的 Windows 提供项目内插件目录联接。
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$metadata = Get-Content -LiteralPath (Join-Path $root '.flutter-plugins-dependencies') -Raw | ConvertFrom-Json
$links = Join-Path $root 'windows/flutter/ephemeral/.plugin_symlinks'
New-Item -ItemType Directory -Force -Path $links | Out-Null
foreach ($plugin in $metadata.plugins.windows) {
    if ($plugin.name -notmatch '^[a-z0-9_]+$') { throw '插件名称不合法。' }
    $target = [IO.Path]::GetFullPath($plugin.path)
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "插件目录不存在：$target" }
    $link = Join-Path $links $plugin.name
    if (Test-Path -LiteralPath $link) {
        $item = Get-Item -LiteralPath $link
        if (-not $item.LinkType -or [IO.Path]::GetFullPath($item.Target).TrimEnd('\') -ne $target.TrimEnd('\')) {
            throw "已有插件链接与依赖不符，请检查：$link"
        }
    } else {
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    }
}
Write-Output 'Windows 插件目录联接已核对。'
