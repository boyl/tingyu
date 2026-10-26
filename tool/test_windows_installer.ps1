#Requires -Version 7.0
param([Parameter(Mandatory)][string]$BuildDirectory, [Parameter(Mandatory)][string]$TestDirectory)
$ErrorActionPreference = 'Stop'
$build = [IO.Path]::GetFullPath($BuildDirectory)
$target = [IO.Path]::GetFullPath($TestDirectory)
$manifest = Get-Content -LiteralPath (Join-Path $build 'installer-manifest.json') -Raw | ConvertFrom-Json
if (-not $manifest.testIdentity) { throw '只允许自动测试独立 AppId 安装包。' }
if (Test-Path -LiteralPath $target) { throw '测试目录必须不存在。' }
$exe = Join-Path $build $manifest.installer
$registry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\tingyu.installer.regression_is1'
if (Test-Path $registry) { throw '已有安装测试登记，需先检查上次结果。' }
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'tingyu 安装测试\tingyu 安装测试.lnk'
$desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'tingyu 安装测试.lnk'
function Invoke-Install([string]$Phase) {
    $log = Join-Path $build "$Phase.log"
    $process = Start-Process -FilePath $exe -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/TASKS=desktopicon', ('/DIR="' + $target + '"'), ('/LOG="' + $log + '"')) -WindowStyle Hidden -Wait -PassThru
    return $process.ExitCode
}
function Assert-Payload {
    foreach ($file in $manifest.files) {
        $installed = Join-Path $target $file.path
        if (-not (Test-Path -LiteralPath $installed) -or (Get-FileHash -LiteralPath $installed).Hash.ToLowerInvariant() -ne $file.sha256) {
            throw "安装文件校验失败：$($file.path)"
        }
    }
}
if ((Invoke-Install 'fresh') -ne 0) { throw '首次安装失败。' }
Assert-Payload
if (-not (Test-Path $registry) -or -not (Test-Path -LiteralPath $shortcut) -or -not (Test-Path -LiteralPath $desktop)) { throw '缺少登记或快捷方式。' }
$shell = New-Object -ComObject WScript.Shell
if ($shell.CreateShortcut($shortcut).TargetPath -ne (Join-Path $target 'tingyu.exe')) { throw '快捷方式目标错误。' }
$sentinel = Join-Path $target '用户资料-保留.txt'
Set-Content -LiteralPath $sentinel -Value 'preserve-user-file'
if ((Invoke-Install 'upgrade') -ne 0) { throw '覆盖安装失败。' }
Assert-Payload
if ((Get-Content -LiteralPath $sentinel -Raw).Trim() -ne 'preserve-user-file') { throw '覆盖安装损坏用户文件。' }
$lock = [IO.File]::Open((Join-Path $target 'tingyu.exe'), 'Open', 'Read', 'Read')
try { $lockedExit = Invoke-Install 'locked' } finally { $lock.Dispose() }
if ($lockedExit -eq 0) { throw '文件占用时未阻止安装。' }
Assert-Payload
$uninstaller = Join-Path $target 'unins000.exe'
$process = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="'+(Join-Path $build 'uninstall.log')+'"')) -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0) { throw '卸载失败。' }
foreach ($file in $manifest.files) {
    if (Test-Path -LiteralPath (Join-Path $target $file.path)) { throw "卸载残留：$($file.path)" }
}
if ((Test-Path $registry) -or (Test-Path -LiteralPath $shortcut) -or (Test-Path -LiteralPath $desktop)) { throw '卸载后仍有登记或快捷方式。' }
if ((Get-Content -LiteralPath $sentinel -Raw).Trim() -ne 'preserve-user-file') { throw '卸载删除了用户文件。' }
$result = @{fresh='PASS'; upgrade='PASS'; lockedFile='PASS'; lockedExitCode=$lockedExit; uninstall='PASS'; retainedUserFile='PASS'; payloadFiles=$manifest.files.Count; testInstallerSha256=$manifest.sha256}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $build 'verification.json')
$result | ConvertTo-Json
