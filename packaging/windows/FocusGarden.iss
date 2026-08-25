; Focus Garden — Windows installer.
;
; Built by tools/build_installer.ps1, which passes the version and paths in.
; Compile by hand with:
;
;   ISCC.exe /DAppVersion=0.2.0 packaging\windows\FocusGarden.iss
;
; The install is deliberately per-user: no UAC prompt, which is what lets the
; in-app updater run this silently with /SILENT when a player accepts an update.
; An installer that needs elevation cannot be part of a one-click update.

#define AppName "Focus Garden"
#define AppPublisher "Focus Garden"
#define AppExeName "FocusGarden.exe"
#define AppUrl "https://github.com/jjee33/FocusGarden"

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#ifndef SourceExe
  #define SourceExe "..\..\builds\windows\FocusGarden.exe"
#endif

#ifndef OutputDir
  #define OutputDir "..\..\builds\installer"
#endif

[Setup]
; NEVER change AppId. It is what makes installing a new version an upgrade
; rather than a second entry in Add/Remove Programs, and what lets the
; uninstaller find an install made by an earlier release.
AppId={{F1AD21B0-9419-49FF-8608-257CD17680AF}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases

; PrivilegesRequired=lowest resolves {autopf} to %LOCALAPPDATA%\Programs.
;
; Deliberately NOT PrivilegesRequiredOverridesAllowed: an all-users install would
; put the app somewhere the unelevated updater cannot write, and a silent update
; would then install a second per-user copy alongside it rather than replacing
; the first. Per-user only is what makes one-click updating work at all.
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes

OutputDir={#OutputDir}
OutputBaseFilename=FocusGarden-Setup-{#AppVersion}
SetupIconFile=app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}

Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; The game is a 64-bit build and there is no 32-bit export preset.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

; Let Setup close a running copy through the Restart Manager rather than failing
; on a locked file. The updater quits the app before launching this, but a player
; who runs the installer by hand should not have to.
CloseApplications=yes
CloseApplicationsFilter=*.exe
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; One self-contained executable. embed_pck is on in export_presets.cfg, so there
; is no .pck and nothing else to ship.
Source: "{#SourceExe}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; Interactive install: the usual "run it now" tickbox on the last page.
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

; Silent install started by the in-app updater. postinstall entries are skipped
; under /SILENT, so without this the app would close to update and never come
; back — which is the difference between a one-click update and a disappearing
; act. The updater passes /relaunch=1; a player running Setup by hand does not.
Filename: "{app}\{#AppExeName}"; Flags: nowait skipifnotsilent; Check: ShouldRelaunch

; No [UninstallDelete] on purpose. Saves live in
; %APPDATA%\Godot\app_userdata\Focus Garden\, outside {app}, so uninstalling —
; or being replaced by an update — never touches a player's garden.

[Code]
function ShouldRelaunch(): Boolean;
begin
  Result := ExpandConstant('{param:relaunch|0}') = '1';
end;
