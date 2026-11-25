; Hanna Installment — Windows Setup (Inno Setup 6). build.yml (Build Windows) isse banata hai:
;   iscc /DAppVersion=1.0.<run> /DSourceDir=<Release folder> windows_installer\hanna_installment.iss
; Natija: Hanna-Installment-Setup.exe (artifact "windows-installer").
;
; * Har user ke apne folder mein (%LOCALAPPDATA%\Programs\Hanna Installment) — admin password nahi chahiye,
;   aur app khud update (silent) kar sakti hai.
; * Start menu + Desktop shortcut. Visual C++ DLLs Release folder mein pehle se (build.yml) — alag install nahi.
; * Uninstall par data (AppData / Documents) NAHI mitta — customers, qisten, license mehfooz.
; * Update: app Setup ko /VERYSILENT ke saath chalati hai; purani app band, nayi files, phir app khud khulti hai.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{368AC202-8EB7-417A-A64B-6D4B482FA639}
AppName=Hanna Installment
AppVersion={#AppVersion}
AppVerName=Hanna Installment {#AppVersion}
AppPublisher=Hanna Solutions
AppPublisherURL=https://hanna-installment.web.app
AppSupportURL=https://hanna-installment.web.app
DefaultDirName={autopf}\Hanna Installment
DefaultGroupName=Hanna Installment
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\installer-out
OutputBaseFilename=Hanna-Installment-Setup
SetupIconFile=..\branding\windows\app_icon.ico
UninstallDisplayIcon={app}\hanna_installment.exe
UninstallDisplayName=Hanna Installment
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force
RestartApplications=no
VersionInfoVersion={#AppVersion}
VersionInfoCompany=Hanna Solutions
VersionInfoProductName=Hanna Installment

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Desktop par shortcut banayein"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Hanna Installment"; Filename: "{app}\hanna_installment.exe"
Name: "{autodesktop}\Hanna Installment"; Filename: "{app}\hanna_installment.exe"; Tasks: desktopicon

[Run]
; Install ke baad app kholo — silent update mein bhi (skipifsilent nahi), taake update ke baad app khud wapas aaye.
Filename: "{app}\hanna_installment.exe"; Description: "Hanna Installment kholein"; Flags: nowait postinstall
