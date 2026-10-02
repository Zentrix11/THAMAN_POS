@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if "%THAMAN_SUPABASE_URL%"=="" set "THAMAN_SUPABASE_URL=https://bbmeefjtzszysgttryie.supabase.co"
if "%THAMAN_SUPABASE_PUBLISHABLE_KEY%"=="" set "THAMAN_SUPABASE_PUBLISHABLE_KEY=sb_publishable_oqYfMj4kN4D2IN_3rIKQow_9sH9FUt6"
title THAMAN POS V9.5 - Prepare Windows
where flutter >nul 2>nul || (echo [ERROR] Flutter not found in PATH.& pause& exit /b 1)
call flutter config --enable-windows-desktop >nul || goto :fail
if not exist "windows\CMakeLists.txt" (
  echo [REPAIR] Creating Windows runner in-place...
  call flutter create --platforms=windows --org com.zentrix --project-name thaman_pos . || goto :fail
)
call flutter clean || goto :fail
call flutter pub get || goto :fail
call dart run tool\patch_platforms.dart || goto :fail
call flutter build windows --debug --dart-define=THAMAN_SUPABASE_URL=%THAMAN_SUPABASE_URL% --dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY=%THAMAN_SUPABASE_PUBLISHABLE_KEY% || goto :fail
echo.
echo Windows debug build: PASS
echo Output: build\windows\x64\runner\Debug\
exit /b 0
:fail
echo.
echo Windows preparation: FAILED
pause
exit /b 1
