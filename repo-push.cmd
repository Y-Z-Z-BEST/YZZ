@echo off
rem ===================================================================
rem  repo-push.cmd - commit every tracked change and push to GitHub.
rem
rem  Use this after you change anything in hub\ or the launchers.
rem  Runtimes (runtime\ npm-global\ dsh\ home\ temp\ logs\ workspace\)
rem  are git-ignored, so they are never uploaded.
rem
rem  Keep this file pure ASCII + CRLF, like every other .cmd here.
rem ===================================================================
setlocal
cd /d "%~dp0"

git add -A
git diff --cached --quiet
if not errorlevel 1 (
  echo   nothing to commit - repo already up to date.
  git status --short --branch
  endlocal & exit /b 0
)

git commit -m "update %DATE% %TIME%"
if errorlevel 1 (
  echo   [warn] commit failed.
  endlocal & exit /b 1
)

git push
if errorlevel 1 (
  echo   [warn] push failed - check network / ssh key.
  endlocal & exit /b 1
)

echo.
git log --oneline -1
echo   pushed.
endlocal
