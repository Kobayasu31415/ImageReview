# Called by build.cmd after the web editor has been built and checked.
$ErrorActionPreference = 'Stop'
$compiler = $env:ISCC
if (!$compiler) {
    $compiler = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
    if (!$compiler) {
        $compiler = @(
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
            "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
        ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
}
if (!$compiler -or !(Test-Path -LiteralPath $compiler)) { throw 'Install Inno Setup 6 or set ISCC to its ISCC.exe path.' }

$root = Split-Path -Parent $PSScriptRoot
$plist = [xml](Get-Content -Raw -Encoding UTF8 -LiteralPath "$root\macapp\Info.plist")
$version = $plist.SelectSingleNode("//key[text()='CFBundleShortVersionString']/following-sibling::string[1]").InnerText
if ($version -notmatch '^\d+\.\d+(\.\d+)?$') { throw "Invalid release version: $version" }
$stageRoot = (New-Item -ItemType Directory -Path "$PSScriptRoot\obj\installer" -Force).FullName
$stage = (New-Item -ItemType Directory -Path (Join-Path $stageRoot ([guid]::NewGuid().ToString('N')))).FullName
try {
    $release = Invoke-RestMethod 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json'
    $runtime = $release.'latest-runtime'
    if ($runtime -notmatch '^10\.0\.\d+$') { throw "Unexpected .NET runtime version: $runtime" }
    dotnet publish "$PSScriptRoot\ImageReview.csproj" -c Release -r win-x64 --self-contained true -o "$stage\app" "-p:RuntimeFrameworkVersion=$runtime" "-p:FileVersion=$version.0" "-p:InformationalVersion=$version" -p:DebugType=None
    if ($LASTEXITCODE) { throw 'dotnet publish failed.' }

    $bootstrapper = Join-Path $stage 'MicrosoftEdgeWebview2Setup.exe'
    Invoke-WebRequest -UseBasicParsing 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile $bootstrapper
    $signature = Get-AuthenticodeSignature -LiteralPath $bootstrapper
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?:^|, )CN=Microsoft Corporation(?:,|$)') {
        throw 'WebView2 bootstrapper signature check failed.'
    }
    & $compiler '/Qp' "/DAppVersion=$version" "/DPackageDir=$stage" "/O$root\dist" "$PSScriptRoot\ImageReview.iss"
    if ($LASTEXITCODE) { throw 'Inno Setup compilation failed.' }
} finally {
    if ((Split-Path -Parent $stage) -eq $stageRoot) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
