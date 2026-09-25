; HomeTunes – Windows installer (Inno Setup 6)
;
; Normally run through tool\build_release.ps1, which builds the app, adds the
; Visual C++ runtime DLLs and passes in the version and folders below.
; To run by hand:
;   iscc /DAppVersion=0.1.0 /DSourceDir=..\build\windows\x64\runner\Release installer\hometunes.iss

; The #ifndef blocks below are Inno Setup preprocessor defaults. build_release.ps1 overrides
; them with /DAppVersion=..., /DSourceDir=... and /DOutputDir=... on the command line.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\build\dist"
#endif

; Names used throughout the script below ({#AppName}, {#AppExe}).
#define AppName "HomeTunes"
#define AppExe "hometunes.exe"

[Setup]
; Never change AppId: Windows uses it to recognise upgrades of the same app.
AppId={{2D99FA48-1B2A-46E0-B225-6C98D94C2714}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\windows\runner\resources\app_icon.ico
; (The icon path is relative to this .iss file, i.e. the generated windows\ runner folder.)

; Installs just for the current user by default, so no admin rights are needed
; (handy on work PCs). The user can still choose "all users" if they are admin.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; {autopf} means "Program Files" for an all-users install, or the per-user programs folder
; (%LOCALAPPDATA%\Programs) for a current-user install.
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes

; 64-bit only (Flutter builds x64)
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

; Close HomeTunes if it's running while installing an update
CloseApplications=yes
RestartApplications=no

OutputDir={#OutputDir}
OutputBaseFilename=HomeTunes-Setup-{#AppVersion}
; Strongest compression; makes the installer smaller at the cost of a slower build.
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; English only, using Inno Setup's built-in wording.
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

; Optional tick-box on the wizard: "Create a desktop shortcut" (unticked by default).
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Flutter Release folder: exe, engine + plugin DLLs, data\ and the VC++ runtime DLLs.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; Start menu shortcut, plus the desktop shortcut if the task above was ticked.
[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

; "Launch HomeTunes" tick-box on the final page (skipped for silent installs).
[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; Uninstalling removes the program files only. The user's library, playlists and
; settings (in %APPDATA%) are kept, so reinstalling picks up where they left off.
