; Version and build paths are supplied by the shared Flutter release publisher.
#ifndef AppId
  #define AppId "xy_car_app"
#endif
#ifndef AppName
  #define AppName "XY-CAR"
#endif
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppBuildNumber
  #define AppBuildNumber "0"
#endif
#ifndef AppPublisher
  #define AppPublisher "XY-CAR"
#endif
#ifndef AppExeName
  #define AppExeName "xy_car_app.exe"
#endif
#ifndef SourceDir
  #define SourceDir "..\\..\\build\\windows\\x64\\runner\\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\\..\\release"
#endif
#ifndef OutputBaseFilename
  #define OutputBaseFilename "xy_car_app-windows-x64-setup"
#endif
#ifndef AppIconFile
  #define AppIconFile "..\\..\\windows\\runner\\resources\\app_icon.ico"
#endif

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\{#AppId}
DefaultGroupName={#AppName}
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
SetupIconFile={#AppIconFile}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
VersionInfoVersion={#AppVersion}.{#AppBuildNumber}
VersionInfoProductVersion={#AppVersion}.{#AppBuildNumber}
VersionInfoDescription={#AppName} installer
VersionInfoProductName={#AppName}
VersionInfoCompany={#AppPublisher}
CloseApplications=yes
RestartApplications=no

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; WorkingDir: "{app}"; Flags: postinstall nowait skipifsilent
