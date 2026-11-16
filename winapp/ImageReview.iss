[Setup]
AppId=ImageReview.Windows
AppName=ImageReview
AppVersion={#AppVersion}
AppPublisher=Kobayasu31415
AppPublisherURL=https://github.com/Kobayasu31415/ImageReview
DefaultDirName={localappdata}\Programs\ImageReview
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19045
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\ImageReview.exe
SetupIconFile=ImageReview.ico
OutputBaseFilename=ImageReview-{#AppVersion}-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
ChangesAssociations=yes
RestartApplications=no

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#PackageDir}\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs
Source: "{#PackageDir}\MicrosoftEdgeWebview2Setup.exe"; Flags: dontcopy

[Icons]
Name: "{userprograms}\ImageReview"; Filename: "{app}\ImageReview.exe"

[Registry]
Root: HKCU; Subkey: "Software\Classes\ImageReview.Installed.Document"; ValueType: string; ValueData: "ImageReview"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\ImageReview.Installed.Document\DefaultIcon"; ValueType: string; ValueData: """{app}\ImageReview.exe"",0"
Root: HKCU; Subkey: "Software\Classes\ImageReview.Installed.Document\shell\open\command"; ValueType: string; ValueData: """{app}\ImageReview.exe"" ""%1"""
#define OpenWith(Ext) 'Root: HKCU; Subkey: "Software\Classes\' + Ext + '\OpenWithProgids"; ValueType: string; ValueName: "ImageReview.Installed.Document"; ValueData: ""; Flags: uninsdeletevalue'
{#OpenWith(".png")}
{#OpenWith(".jpg")}
{#OpenWith(".jpeg")}
{#OpenWith(".gif")}
{#OpenWith(".webp")}
{#OpenWith(".bmp")}
{#OpenWith(".pdf")}
{#OpenWith(".json")}

[Run]
Filename: "{app}\ImageReview.exe"; Description: "{cm:LaunchProgram,ImageReview}"; Flags: nowait postinstall skipifsilent

[CustomMessages]
japanese.WebViewError=Microsoft Edge WebView2 Runtime をインストールできませんでした。インターネット接続を確認してから、もう一度実行してください。
english.WebViewError=Microsoft Edge WebView2 Runtime could not be installed. Check your internet connection and run setup again.

[Code]
function HasRuntime(Root: Integer): Boolean;
var
  Version: String;
begin
  Result := RegQueryStringValue(Root, 'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', Version)
    and (Version <> '') and (Version <> '0.0.0.0');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ExitCode: Integer;
begin
  Result := '';
  if HasRuntime(HKLM32) or HasRuntime(HKCU) then Exit;
  ExtractTemporaryFile('MicrosoftEdgeWebview2Setup.exe');
  if not Exec(ExpandConstant('{tmp}\MicrosoftEdgeWebview2Setup.exe'), '/silent /install', '', SW_HIDE, ewWaitUntilTerminated, ExitCode)
    or not (HasRuntime(HKLM32) or HasRuntime(HKCU)) then
    Result := CustomMessage('WebViewError');
end;
