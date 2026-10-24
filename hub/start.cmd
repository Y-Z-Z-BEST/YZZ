@echo off
rem ===================================================================
rem  YZZ hub -- Windows entry point (no subst, no install required)
rem
rem  Design goal: copy the whole folder onto a USB drive, plug it into
rem  any Windows machine, double-click, done. No absolute path may be
rem  hardcoded here, so Git Bash is located at run time.
rem
rem  Lookup order (first hit wins):
rem    1. PortableGit\bin\bash.exe next to this file  <- no install
rem    2. %ProgramFiles%\Git\bin\bash.exe
rem    3. %ProgramFiles(x86)%\Git\bin\bash.exe
rem    4. %LOCALAPPDATA%\Programs\Git\bin\bash.exe
rem    5. bash.exe on PATH
rem    6. registry HKLM\SOFTWARE\GitForWindows  InstallPath
rem
rem  Difference from the upstream PocketAgentHub build:
rem    upstream does pushd "%~dp0", which moves the working directory to
rem    hub\, so the launched agent starts inside hub\ instead of the
rem    user's project. This script does not pushd: the agent inherits the
rem    caller's working directory. Set HUB_START_DIR to pin one.
rem ===================================================================
setlocal EnableExtensions

rem -- Optional: fixed starting directory (empty = current directory) --
set "HUB_START_DIR="

set "GIT_BASH="

rem -- 1) PortableGit next to this file (USB, no install) -------------
if exist "%~dp0PortableGit\bin\bash.exe" set "GIT_BASH=%~dp0PortableGit\bin\bash.exe"
if defined GIT_BASH goto :found

rem -- 2) .. 4) common install locations ------------------------------
if exist "%ProgramFiles%\Git\bin\bash.exe"          set "GIT_BASH=%ProgramFiles%\Git\bin\bash.exe"
if defined GIT_BASH goto :found
if exist "%ProgramFiles(x86)%\Git\bin\bash.exe"     set "GIT_BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if defined GIT_BASH goto :found
if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "GIT_BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if defined GIT_BASH goto :found

rem -- 5) PATH --------------------------------------------------------
for /f "delims=" %%I in ('where bash.exe 2^>nul') do (
  if not defined GIT_BASH set "GIT_BASH=%%I"
)
if defined GIT_BASH goto :found

rem -- 6) registry ----------------------------------------------------
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\GitForWindows" /v InstallPath 2^>nul ^| findstr /i "InstallPath"') do (
  if exist "%%B\bin\bash.exe" set "GIT_BASH=%%B\bin\bash.exe"
)
if defined GIT_BASH goto :found

:notfound
echo.
echo   Git Bash not found on this machine.
echo.
echo   Two ways to fix:
echo     1) Install Git for Windows:  https://git-scm.com/download/win
echo     2) For a no-install portable setup, download PortableGit and put it
echo        next to this file as:  %~dp0PortableGit\
echo        (it should contain bin\bash.exe)
echo.
echo   After that, double-click start.cmd again.
echo.
pause
exit /b 1

:found
if defined HUB_START_DIR if exist "%HUB_START_DIR%" pushd "%HUB_START_DIR%"

rem launch.sh derives the project root itself, so no drive letter is
rem baked in: another drive or another machine still works.
"%GIT_BASH%" "%~dp0launch.sh" %*
set "RC=%ERRORLEVEL%"

if defined HUB_START_DIR popd

rem Double-clicking closes the window instantly; only pause on error.
if not "%RC%"=="0" pause
endlocal & exit /b %RC%
