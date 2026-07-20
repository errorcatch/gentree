@echo off
setlocal

echo ==^> Checking for Node.js...
where node >nul 2>nul
if errorlevel 1 (
    echo Node.js is not installed. Install Node 20+ first: https://nodejs.org
    exit /b 1
)

echo ==^> Cloning gentree...
if exist gentree (
    echo Folder "gentree" already exists, pulling latest instead.
    cd gentree
    git pull
) else (
    git clone https://github.com/errorcatch/gentree.git
    cd gentree
)

echo ==^> Installing dependencies...
call npm install
if errorlevel 1 goto :error

echo ==^> Building...
call npm run build
if errorlevel 1 goto :error

echo ==^> Linking gentree globally...
call npm link
if errorlevel 1 goto :error

echo.
echo Done. Try running "gentree" from any Rojo project folder.
goto :eof

:error
echo.
echo Something failed above. Scroll up to see what broke.
exit /b 1