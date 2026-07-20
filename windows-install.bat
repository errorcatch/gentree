@echo off
setlocal enableextensions

set "REPO=errorcatch/gentree"
set "ASSET=gentree-windows-x86_64.exe"
set "INSTALL_DIR=%LOCALAPPDATA%\Programs\gentree"
set "URL=https://github.com/%REPO%/releases/latest/download/%ASSET%"

where curl >nul 2>nul
if errorlevel 1 (
    echo curl is required. It ships with Windows 10 and newer, so please update Windows.
    exit /b 1
)

echo ==^> Downloading %ASSET%...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

curl -fL "%URL%" -o "%INSTALL_DIR%\gentree.exe"
if errorlevel 1 (
    echo Download failed. Check your connection or that a release exists.
    exit /b 1
)

echo ==^> Updating PATH...
powershell -NoProfile -Command "$d = '%INSTALL_DIR%'; $p = [Environment]::GetEnvironmentVariable('Path','User'); if ([string]::IsNullOrEmpty($p)) { $p = '' }; if (($p -split ';') -notcontains $d) { [Environment]::SetEnvironmentVariable('Path', ($p.TrimEnd(';') + ';' + $d).TrimStart(';'), 'User'); Write-Host 'Added to your PATH.' } else { Write-Host 'Already on your PATH.' }"

echo.
echo Done. Open a NEW terminal and run "gentree -V".
endlocal
