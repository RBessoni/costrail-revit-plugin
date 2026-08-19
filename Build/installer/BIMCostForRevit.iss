; BIM Cost for Revit - installer
;
; Builds a single self-contained .exe that drops the connector and the bundled panel UI
; into the per-user Revit Addins folder. Per-user on purpose: Revit modellers should not
; need admin rights, and Revit reads %AppData%\Autodesk\Revit\Addins by default.
;
; Build with:  ISCC.exe Build\installer\BIMCostForRevit.iss
; Expects Release builds to exist and the UI to be generated (see PreBuild checks below).

#define AppName "BIM Cost for Revit"
#define AppPublisher "Blackbird Industries"
#define AppVersion "1.0.2"

; Connector Release output
#define Out2026 "..\..\Connectors\Revit\Speckle.Connectors.Revit2026\bin\Release\net8.0-windows"
#define Out2027 "..\..\Connectors\Revit\Speckle.Connectors.Revit2027\bin\Release\net10.0-windows"
; Static panel UI generated from the sibling speckle-connectors-dui repo
#define UiDir "..\..\..\speckle-connectors-dui\.output\public"

[Setup]
AppId={{b01889a6-e55c-437a-8d34-87a5f6bb633e}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}
DefaultDirName={userappdata}\Autodesk\Revit\Addins
DisableDirPage=yes
DisableProgramGroupPage=yes
UninstallDisplayName={#AppName}
OutputDir=..\..\output
OutputBaseFilename=BIMCostForRevit-{#AppVersion}-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Per-user install: no elevation prompt.
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "pt"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Types]
Name: "custom"; Description: "Custom"; Flags: iscustom

[Components]
Name: "r2026"; Description: "Revit 2026"; Types: custom; Check: RevitInstalled('2026')
Name: "r2027"; Description: "Revit 2027"; Types: custom; Check: RevitInstalled('2027')

[Files]
; --- Revit 2026 ---
Source: "{#Out2026}\*"; DestDir: "{userappdata}\Autodesk\Revit\Addins\2026\Speckle.Connectors.Revit2026"; \
  Flags: ignoreversion recursesubdirs createallsubdirs; Components: r2026
Source: "{#UiDir}\*"; DestDir: "{userappdata}\Autodesk\Revit\Addins\2026\Speckle.Connectors.Revit2026\ui"; \
  Flags: ignoreversion recursesubdirs createallsubdirs; Components: r2026
Source: "{#Out2026}\Plugin\Speckle.Connectors.Revit2026.addin"; DestDir: "{userappdata}\Autodesk\Revit\Addins\2026"; \
  Flags: ignoreversion; Components: r2026

; --- Revit 2027 ---
Source: "{#Out2027}\*"; DestDir: "{userappdata}\Autodesk\Revit\Addins\2027\Speckle.Connectors.Revit2027"; \
  Flags: ignoreversion recursesubdirs createallsubdirs; Components: r2027
Source: "{#UiDir}\*"; DestDir: "{userappdata}\Autodesk\Revit\Addins\2027\Speckle.Connectors.Revit2027\ui"; \
  Flags: ignoreversion recursesubdirs createallsubdirs; Components: r2027
Source: "{#Out2027}\Plugin\Speckle.Connectors.Revit2027.addin"; DestDir: "{userappdata}\Autodesk\Revit\Addins\2027"; \
  Flags: ignoreversion; Components: r2027

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\Autodesk\Revit\Addins\2026\Speckle.Connectors.Revit2026"
Type: filesandordirs; Name: "{userappdata}\Autodesk\Revit\Addins\2027\Speckle.Connectors.Revit2027"

[Code]
{ Revit is detected by its install directory rather than the registry: the registry layout
  varies between Autodesk releases, the folder does not. }
function RevitInstalled(Version: String): Boolean;
begin
  Result := DirExists(ExpandConstant('{commonpf}\Autodesk\Revit ') + Version);
end;

{ Copying over DLLs that Revit has loaded fails mid-install and leaves a half-written addin,
  so refuse to start while Revit is open. }
function IsRevitRunning: Boolean;
var
  ResultCode: Integer;
begin
  Result := False;
  if Exec('powershell.exe',
          '-NoProfile -NonInteractive -Command "if (Get-Process Revit -ErrorAction SilentlyContinue) { exit 1 } exit 0"',
          '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Result := ResultCode = 1;
end;

{ The panel is a WebView2 control. Windows 11 ships the Evergreen runtime, but older or
  stripped images may not have it, and without it the panel stays blank. }
function IsWebView2Present: Boolean;
var
  Value: String;
begin
  Result :=
    RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', Value) or
    RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', Value) or
    RegQueryStringValue(HKCU, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', Value);
end;

function InitializeSetup: Boolean;
begin
  Result := True;

  if IsRevitRunning then
  begin
    MsgBox('Revit is currently running.' + #13#10#13#10 +
           'Close every open Revit window and run this installer again.',
           mbError, MB_OK);
    Result := False;
    Exit;
  end;

  if not (RevitInstalled('2026') or RevitInstalled('2027')) then
  begin
    MsgBox('No supported Revit version was found.' + #13#10#13#10 +
           'This build supports Revit 2026 and 2027.',
           mbError, MB_OK);
    Result := False;
    Exit;
  end;

  if not IsWebView2Present then
    MsgBox('The Microsoft Edge WebView2 Runtime was not detected.' + #13#10#13#10 +
           'BIM Cost uses it to draw its panel. Installation will continue, but if the panel ' +
           'appears blank inside Revit, install the WebView2 Runtime from Microsoft and restart Revit.',
           mbInformation, MB_OK);
end;
