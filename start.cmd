@echo off
rem ===================================================================
rem  YZZ portable launcher
rem
rem  Put this whole folder on a USB drive / external disk. Plug it into
rem  any Windows machine and double-click this file. Nothing needs to be
rem  installed on the host: Git, Node and the agents all live on the drive.
rem
rem  What it does:
rem    1. maps the drive to a FIXED virtual letter with subst (default Q:)
rem       - survives different drive letters across machines
rem       - shortens the path, dodging the 260-char node_modules limit
rem    2. points USERPROFILE / APPDATA / TEMP into the drive's home\
rem       - so agent configs and login state land on the drive, not the host
rem    3. prepends the drive's node / git / npm-global to PATH
rem       - the host's installed versions are irrelevant
rem    4. starts the hub TUI, then on exit wipes login credentials (config
rem       is kept) and releases the virtual drive
rem
rem  Switches (environment variables):
rem    KEEP_CREDS=1   do not wipe credentials this run (own machine)
rem    PA_NO_TUI=1    debug: set everything up but do not start the TUI
rem
rem  NOTE: keep this file pure ASCII. cmd.exe on a Chinese Windows reads
rem  .cmd files as GBK; UTF-8 Chinese text corrupts the parser and the
rem  script dies with weird errors like "tlocal is not recognized".
rem ===================================================================
setlocal EnableExtensions EnableDelayedExpansion

set "THIS_DIR=%~dp0"
if "%THIS_DIR:~-1%"=="\" set "THIS_DIR=%THIS_DIR:~0,-1%"

rem ---- 0) prefer Windows Terminal ----------------------------------
rem A bare cmd.exe console renders this TUI badly (double-drawn frames,
rem leftover fragments on the right edge) while the exact same script is
rem fine inside Windows Terminal. Rather than fight conhost, hand off:
rem re-launch this same file inside a Windows Terminal tab and exit.
rem PA_IN_WT guards against an endless relaunch loop.
if not defined PA_IN_WT (
  where wt.exe >nul 2>&1
  if not errorlevel 1 (
    set "PA_IN_WT=1"
    wt.exe -w -1 new-tab cmd /c ""%~f0" %*"
    exit /b 0
  )
)

rem ---- 1) pick the virtual drive letter ------------------------------
rem First reuse a mapping that ALREADY points at this bundle. A previous
rem run may have been killed before its cleanup, leaving (say) Q: mapped
rem here. Without this check the script would think Q: is taken, pick W:,
rem and leave Q: behind again - the mappings then pile up run after run.
set "ROOT="
set "VLETTER="
set "SUBBED=0"
for %%L in (Q W V U X Y R) do (
  if not defined ROOT (
    if exist "%%L:\start.cmd" (
      if exist "%%L:\runtime\git\bin\bash.exe" (
        set "VLETTER=%%L"
        set "ROOT=%%L:"
        set "SUBBED=1"
      )
    )
  )
)

rem Otherwise take the first letter that is genuinely free.
if not defined ROOT (
  for %%L in (Q W V U X Y R) do (
    if not defined VLETTER if not exist "%%L:\" set "VLETTER=%%L"
  )
  if defined VLETTER (
    rem Inside a parenthesised block %VAR% is expanded when the block is
    rem PARSED, i.e. as empty - delayed expansion !VAR! is the only way to
    rem see the value the loop above just set.
    subst !VLETTER!: "%THIS_DIR%" >nul 2>&1
    if not errorlevel 1 (
      set "ROOT=!VLETTER!:"
      set "SUBBED=1"
    )
  )
)

if "%SUBBED%"=="0" (
  rem No free letter: fall back to the real path. Still works, just
  rem without the stable-letter and short-path benefits.
  set "ROOT=%THIS_DIR%"
  echo   [warn] no free drive letter for subst - running from the real path
)

if not exist "%ROOT%\runtime\git\bin\bash.exe" (
  echo.
  echo   ERROR: runtime\git\bin\bash.exe not found under
  echo          %ROOT%
  echo.
  echo   The portable bundle is incomplete. Expected layout:
  echo     runtime\git\bin\bash.exe
  echo     runtime\node\node.exe
  echo     hub\launch.sh
  echo.
  if "%SUBBED%"=="1" subst %VLETTER%: /d >nul 2>&1
  pause
  exit /b 1
)

rem ---- 2) point the user profile into the drive --------------------
set "USERPROFILE=%ROOT%\home"
set "HOME=%ROOT%\home"
set "APPDATA=%ROOT%\home\AppData\Roaming"
set "LOCALAPPDATA=%ROOT%\home\AppData\Local"
set "XDG_DATA_HOME=%ROOT%\home\.local\share"
set "XDG_CONFIG_HOME=%ROOT%\home\.config"
set "XDG_CACHE_HOME=%ROOT%\home\.cache"
set "XDG_STATE_HOME=%ROOT%\home\.local\state"
set "TEMP=%ROOT%\temp"
set "TMP=%ROOT%\temp"

if not exist "%APPDATA%"        mkdir "%APPDATA%"        >nul 2>&1
if not exist "%LOCALAPPDATA%"   mkdir "%LOCALAPPDATA%"   >nul 2>&1
if not exist "%XDG_DATA_HOME%"  mkdir "%XDG_DATA_HOME%"  >nul 2>&1
if not exist "%XDG_CONFIG_HOME%" mkdir "%XDG_CONFIG_HOME%" >nul 2>&1
if not exist "%XDG_CACHE_HOME%" mkdir "%XDG_CACHE_HOME%" >nul 2>&1
if not exist "%XDG_STATE_HOME%" mkdir "%XDG_STATE_HOME%" >nul 2>&1
if not exist "%TEMP%"           mkdir "%TEMP%"           >nul 2>&1
if not exist "%ROOT%\logs"      mkdir "%ROOT%\logs"      >nul 2>&1

rem ---- 3) prepend the drive's runtime to PATH ----------------------
rem npm on Windows writes its global shims (.cmd/.ps1) directly into the
rem prefix folder, not into prefix\bin - so npm-global itself must be on
rem PATH. The bin subfolder is kept as a harmless fallback.
set "PATH=%ROOT%\runtime\node;%ROOT%\npm-global;%ROOT%\npm-global\bin;%ROOT%\runtime\git\bin;%ROOT%\runtime\git\usr\bin;%PATH%"

rem Make "npm install -g" default to the drive. Using env vars instead of
rem a hardcoded .npmrc keeps the prefix correct when subst picks another
rem letter.
set "npm_config_prefix=%ROOT%\npm-global"
set "npm_config_cache=%ROOT%\temp\npm-cache"
set "NODE_PATH=%ROOT%\npm-global\node_modules"
if not exist "%npm_config_cache%" mkdir "%npm_config_cache%" >nul 2>&1

rem ---- 4) working directory ----------------------------------------
if exist "%ROOT%\workspace" (
  cd /d "%ROOT%\workspace"
) else (
  cd /d "%ROOT%"
)

set "BASH=%ROOT%\runtime\git\bin\bash.exe"
set "RC=0"

rem ---- 5) debug switch: set up but skip the TUI --------------------
if defined PA_NO_TUI (
  echo.
  echo   [PA_NO_TUI] environment ready, TUI skipped.
  echo     ROOT        = %ROOT%
  echo     USERPROFILE = %USERPROFILE%
  echo     TEMP        = %TEMP%
  echo     npm prefix  = %npm_config_prefix%
  echo.
  call :probe
  goto :cleanup
)

rem ---- 6) run the TUI ----------------------------------------------
"%BASH%" "%ROOT%\hub\launch.sh" %*
set "RC=%ERRORLEVEL%"

:cleanup
rem ---- 7) wipe credentials, then release the virtual drive ---------
echo.
echo   Cleaning up...
"%BASH%" "%ROOT%\hub\bin\wipe-creds.sh"
if errorlevel 1 (
  echo   [warn] some credential files could not be removed - check manually.
)

if "%SUBBED%"=="1" (
  rem give the file handles a moment to close, otherwise subst /d fails
  ping -n 2 127.0.0.1 >nul 2>&1
  subst %VLETTER%: /d >nul 2>&1
  if errorlevel 1 (
    echo   [warn] could not release drive %VLETTER%: - it will vanish on logoff.
  )
)

echo   Done. You can safely eject the drive now.
if not "%RC%"=="0" pause
endlocal & exit /b %RC%

rem ---- helper: print what resolves where (used by PA_NO_TUI) --------
rem Keep each probe as its own simple bash -c call. Trying to build one
rem command with printf/loops inside a .cmd runs into cmd quote-mangling
rem and the shell ends up receiving a truncated string.
:probe
"%BASH%" -c "command -v node || echo node:MISSING"
"%BASH%" -c "command -v npm  || echo npm:MISSING"
"%BASH%" -c "command -v git  || echo git:MISSING"
"%BASH%" -c "node -v"
goto :eof
