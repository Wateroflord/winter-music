; Установщик Winter Music для Windows (Inno Setup 6), ставится в профиль пользователя.
#define BuildNo GetEnv("BUILD_NO")
#if BuildNo == ""
  #define BuildNo "0"
#endif

[Setup]
AppId={{F2EC6217-D5FB-47DF-B8F7-44D668024860}
AppName=Winter Music
AppVersion=1.0.{#BuildNo}
AppPublisher=Winter Hub
DefaultDirName={localappdata}\Programs\Winter Music
DefaultGroupName=Winter Music
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Winter-Music-Setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\winter_music.exe
CloseApplications=force
RestartApplications=no
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Winter Music"; Filename: "{app}\winter_music.exe"
Name: "{group}\{cm:UninstallProgram,Winter Music}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Winter Music"; Filename: "{app}\winter_music.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\winter_music.exe"; Description: "{cm:LaunchProgram,Winter Music}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\winter_music.exe"; Flags: nowait; Check: WizardSilent
