#ifndef AppId
  #define AppId "tingyu.windows.desktop"
#endif
#ifndef AppName
  #define AppName "tingyu"
#endif
[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion=0.1.28
AppPublisher=boyl
AppPublisherURL=https://github.com/boyl/tingyu
DefaultDirName={localappdata}\Programs\tingyu
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputPath}
OutputBaseFilename=tingyu-0.1.28-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\tingyu.exe
LicenseFile={#SourcePath}\LICENSE.txt
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
Uninstallable=yes
SetupLogging=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; Flags: unchecked

[Files]
#include PayloadList

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\tingyu.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\tingyu.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\tingyu.exe"; Description: "启动 tingyu"; Flags: nowait postinstall skipifsilent unchecked

[Code]
function CreateFile(FileName: String; Access, Share: LongWord; Security: LongWord;
  Creation, Flags, Template: LongWord): LongWord;
  external 'CreateFileW@kernel32.dll stdcall';
function CloseHandle(Handle: LongWord): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Handle: LongWord; Target: String;
begin
  Result := '';
  Target := ExpandConstant('{app}\tingyu.exe');
  if FileExists(Target) then begin
    Handle := CreateFile(Target, $40000000, 7, 0, 3, 0, 0);
    if Handle = $FFFFFFFF then
      Result := '无法更新程序文件。请先从系统托盘退出 tingyu，并确认安装目录可写，再重试。'
    else CloseHandle(Handle);
  end;
end;

procedure VerifyInstalledFile(FileName, ExpectedHash: String);
begin
  if CompareText(GetSHA256OfFile(ExpandConstant(FileName)), ExpectedHash) <> 0 then
    RaiseException('安装文件校验失败：' + FileName);
end;

