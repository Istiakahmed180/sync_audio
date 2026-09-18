; Build after: flutter build windows --release
; Compile this file with Inno Setup on a Windows development machine.

#define AppName "SyncMesh Audio"
#define AppVersion "1.0.0"
#define AppPublisher "SyncMesh Audio"
#define AppExeName "sync_audio.exe"
#define ReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{B7F7F8E1-2D7A-4FCE-9A78-7C1AA0E9B1B4}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\SyncMesh Audio
DefaultGroupName={#AppName}
OutputDir=..\..\dist
OutputBaseFilename=SyncAudioSetup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#AppExeName}
; Keep the icon next to this script and resolve it from the script's own
; directory so the compiler always finds it, no matter which directory the
; build is invoked from.
SetupIconFile={#SourcePath}\app_icon.ico
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Setup
VersionInfoProductName={#AppName}
VersionInfoVersion={#AppVersion}

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
; Allow LAN control + audio traffic. Without these, Windows Firewall silently
; drops UDP audio (port 5051) and discovery (port 5054) on Ethernet/Wi-Fi,
; which looks like "TCP reachable but no audio / cannot connect".
; Discovery replies are sent back to the Host's ephemeral source port, not to
; 5054, so the program needs a blanket inbound UDP allow as well, otherwise
; release installs cannot find Receivers while debug builds (which got an
; "allow all" firewall prompt) can.
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""SyncMesh Audio LAN Discovery"" dir=in action=allow protocol=UDP program=""{app}\{#AppExeName}"""; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""SyncMesh Audio TCP Control"" dir=in action=allow protocol=TCP localport=5050 program=""{app}\{#AppExeName}"""; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""SyncMesh Audio UDP Audio"" dir=in action=allow protocol=UDP localport=5051 program=""{app}\{#AppExeName}"""; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""SyncMesh Audio UDP Discovery"" dir=in action=allow protocol=UDP localport=5054 program=""{app}\{#AppExeName}"""; Flags: runhidden
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""SyncMesh Audio LAN Discovery"""; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""SyncMesh Audio TCP Control"""; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""SyncMesh Audio UDP Audio"""; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""SyncMesh Audio UDP Discovery"""; Flags: runhidden
