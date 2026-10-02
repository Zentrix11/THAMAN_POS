@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title THAMAN POS V9.5 - Windows Release

if "%THAMAN_SUPABASE_URL%"=="" set "THAMAN_SUPABASE_URL=https://bbmeefjtzszysgttryie.supabase.co"
if "%THAMAN_SUPABASE_PUBLISHABLE_KEY%"=="" set "THAMAN_SUPABASE_PUBLISHABLE_KEY=sb_publishable_oqYfMj4kN4D2IN_3rIKQow_9sH9FUt6"

where flutter >nul 2>nul || (echo [ERROR] Flutter not found in PATH.& pause& exit /b 1)
call flutter config --enable-windows-desktop >nul || goto :fail
if not exist "windows\CMakeLists.txt" call flutter create --platforms=windows --org com.zentrix --project-name thaman_pos . || goto :fail

call flutter clean || goto :fail
call flutter pub get || goto :fail
call dart run tool\patch_platforms.dart || goto :fail
call flutter analyze || goto :fail
call flutter test || goto :fail
call flutter build windows --release --dart-define=THAMAN_SUPABASE_URL=%THAMAN_SUPABASE_URL% --dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY=%THAMAN_SUPABASE_PUBLISHABLE_KEY% || goto :fail

echo.
echo [PASS] THAMAN POS V9.5 Windows release created.
echo EXE: build\windows\x64\runner\Release\thaman_pos.exe
echo IMPORTANT: distribute the entire Release folder, not the EXE alone.
pause
exit /b 0

:fail
echo.
echo [ERROR] Windows release build failed.
pause
exit /b 1
