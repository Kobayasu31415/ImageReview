@echo off
setlocal
pushd "%~dp0..\web" || exit /b 1
call npm.cmd ci --no-audit --no-fund || goto :failed
call npm.cmd run build || goto :failed
call npx.cmd --no-install astryx doctor --built dist || goto :failed
popd
if /i "%~1"=="--installer" goto :installer
dotnet publish "%~dp0ImageReview.csproj" -c Release -o "%~dp0..\dist\ImageReview-Windows"
exit /b %errorlevel%
:installer
powershell.exe -NoProfile -File "%~dp0package-installer.ps1"
exit /b %errorlevel%
:failed
popd
exit /b 1
