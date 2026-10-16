param([ValidateSet('check', 'build', 'run')][string]$Mode = 'run')
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Install Flutter stable and add flutter/bin to PATH first.'
}
function Invoke-TingyuFlutter {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments)
    & flutter @FlutterArguments
    if ($LASTEXITCODE -ne 0) { throw "flutter $FlutterArguments failed ($LASTEXITCODE)" }
}
Invoke-TingyuFlutter pub get
Invoke-TingyuFlutter analyze
Invoke-TingyuFlutter test
if ($Mode -eq 'build') { Invoke-TingyuFlutter build windows --release }
elseif ($Mode -eq 'run') { Invoke-TingyuFlutter run -d windows }
