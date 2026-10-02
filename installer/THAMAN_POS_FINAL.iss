#define MyAppName "THAMAN POS"
#define MyAppVersion "0.32.0"
#define MyAppPublisher "Zentrix"
#define MyAppExeName "thaman_pos.exe"

[Setup]
AppId={{E73B6467-456E-49AB-84E9-905A0F5B0950}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\THAMAN POS
DefaultGroupName=THAMAN POS
OutputDir=output
OutputBaseFilename=THAMAN_POS_Setup_0.32.0
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\THAMAN POS"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\THAMAN POS"; Filename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch THAMAN POS"; Flags: nowait postinstall skipifsilent
