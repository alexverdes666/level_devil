; Inno Setup script for Level Devil.
; Build from CI with:
;   ISCC /DAppVersion=0.1.0 installer.iss
; Expects the following layout relative to this .iss file:
;   ../build/game.exe
;   ../launcher/build/Release/LevelDevilLauncher.exe
;   ../build/version.txt        (one line: vX.Y.Z, written by CI)
;   ../icon.svg                 (optional, ignored)

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName        "Level Devil"
#define AppPublisher   "alexverdes666"
#define AppExeName     "LevelDevilLauncher.exe"
#define AppGameExe     "game.exe"
#define AppURL         "https://github.com/alexverdes666/level_devil"

[Setup]
AppId={{F1A9E9C2-7C26-4D0E-9F90-1B7E2D6F1F11}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={autopf}\LevelDevil
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=LevelDevilSetup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=
DisableWelcomePage=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\{#AppGameExe}";            DestDir: "{app}"; Flags: ignoreversion
Source: "..\launcher\build\Release\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\version.txt";              DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}";       Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
