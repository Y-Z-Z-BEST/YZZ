@echo off
rem ===================================================================
rem  cleanup-drive.cmd - remove the virtual drive letter (subst) left
rem  behind by start.cmd.
rem
rem  start.cmd maps this folder to a letter like Q: so that paths stay
rem  stable across machines. It removes the mapping on exit, but if the
rem  process is killed or the window is closed, the mapping survives
rem  until you log off. Run this file to remove it right away.
rem
rem  Nothing on disk is deleted - Q: is only a pointer to this folder.
rem ===================================================================
setlocal EnableExtensions EnableDelayedExpansion
set "THIS_DIR=%~dp0"
if "%THIS_DIR:~-1%"=="\" set "THIS_DIR=%THIS_DIR:~0,-1%"
set "FOUND=0"
echo.
for %%L in (Q W V U X Y R) do (
  if exist "%%L:\start.cmd" if exist "%%L:\runtime\git\bin\bash.exe" (
    echo   removing %%L:
    subst %%L: /d >nul 2>&1
    set "FOUND=1"
  )
)
if "%FOUND%"=="0" (
  echo   no leftover virtual drive found.
) else (
  echo.
  echo   done. The letter is gone from Explorer.
)
echo.
pause
endlocal
