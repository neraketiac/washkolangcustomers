@echo off

for /f "tokens=1-5 delims=/ " %%a in ("%date%") do set d=%%c%%b%%a
for /f "tokens=1-2 delims=:." %%a in ("%time: =0%") do set t=%%a%%b
set BUILD_TIME=%d%-%t%

echo ====================================
echo BUILD START %BUILD_TIME%
echo ====================================

echo Cleaning...
call flutter clean

echo Building...
call flutter build web --release --dart-define=BUILD_TIME=%BUILD_TIME%

echo Deploying...
call firebase deploy --only hosting

echo ====================================
echo DONE
echo ====================================
pause