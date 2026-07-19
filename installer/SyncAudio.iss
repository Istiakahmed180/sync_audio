; Build after: flutter build windows --release
; Compile this file with Inno Setup on a Windows development machine.

#define AppName "Sync Audio"
#define AppVersion "1.0.0"
#define AppPublisher "Sync Audio"
#define AppExeName "sync_audio.exe"
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{B7F7F8E1-2D7A-4FCE-9A78-7C1AA0E9B1B4}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\Sync Audio
DefaultGroupName={#AppName}
OutputDir=..\dist
OutputBaseFilename=SyncAudioSetup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=..\windows\runner\resources\app_icon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
