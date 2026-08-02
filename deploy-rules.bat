@echo off
REM ---------------------------------------------------------------------
REM  Deploy firestore.rules, then record which version went live.
REM
REM  The recorded hash is what makes "did I deploy this?" answerable.
REM  Run check-rules.bat any time to find out.
REM ---------------------------------------------------------------------
cd /d "%~dp0"

echo Deploying firestore.rules ...
call firebase deploy --only firestore:rules
if errorlevel 1 (
  echo.
  echo DEPLOY FAILED - the live rules are unchanged.
  exit /b 1
)

git hash-object firestore.rules > .rules-deployed
echo.
echo Deployed. Live rules now match your local firestore.rules.
