#ifndef AppVersion
  #error AppVersion must be supplied by build_installer.ps1
#endif
#ifndef AppBuild
  #error AppBuild must be supplied by build_installer.ps1
#endif
#ifndef SourceDir
  #error SourceDir must be supplied by build_installer.ps1
#endif
#ifndef OutputDir
  #error OutputDir must be supplied by build_installer.ps1
#endif
#ifndef IconPath
  #error IconPath must be supplied by build_installer.ps1
#endif

[Setup]
AppId={{D9C5471B-6A0C-4527-9CF7-8B11E2B198D6}
AppName=Pulse
AppVersion={#AppVersion}
AppVerName=Pulse {#AppVersion} (build {#AppBuild})
AppPublisher=Pulse
DefaultDirName={localappdata}\Programs\Pulse
DefaultGroupName=Pulse
UninstallDisplayIcon={app}\pulse_flutter.exe
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#IconPath}
OutputDir={#OutputDir}
OutputBaseFilename=Pulse-Desktop-Instalador-v{#AppVersion}-build{#AppBuild}
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Pulse"; Filename: "{app}\pulse_flutter.exe"
Name: "{autodesktop}\Pulse"; Filename: "{app}\pulse_flutter.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\pulse_flutter.exe"; Description: "Abrir Pulse"; Flags: nowait postinstall skipifsilent
