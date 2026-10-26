#Requires -Version 7.0
param([ValidateSet('check', 'build', 'run')][string]$Mode = 'run')
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    function Invoke-TingyuFlutter {
        param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments)
        & (Get-Command pwsh -ErrorAction Stop).Source -NoProfile -File (Join-Path $PSScriptRoot 'flutterw.ps1') @FlutterArguments
        if ($LASTEXITCODE -ne 0) { throw "Flutter 命令失败 ($LASTEXITCODE)：$FlutterArguments" }
    }
    Invoke-TingyuFlutter pub get
    Invoke-TingyuFlutter analyze
    Invoke-TingyuFlutter test
    if ($Mode -eq 'build') { Invoke-TingyuFlutter build windows --release }
    elseif ($Mode -eq 'run') { Invoke-TingyuFlutter run -d windows }
} finally {
    Pop-Location
}
