@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title THAMAN POS V9.5 - Android Test APK
if "%THAMAN_SUPABASE_URL%"=="" set "THAMAN_SUPABASE_URL=https://bbmeefjtzszysgttryie.supabase.co"
if "%THAMAN_SUPABASE_PUBLISHABLE_KEY%"=="" set "THAMAN_SUPABASE_PUBLISHABLE_KEY=sb_publishable_oqYfMj4kN4D2IN_3rIKQow_9sH9FUt6"
where flutter >nul 2>nul || (echo [ERROR] Flutter not found in PATH.& pause& exit /b 1)
call flutter clean || goto :fail
call flutter pub get || goto :fail
call flutter build apk --debug --dart-define=THAMAN_SUPABASE_URL=%THAMAN_SUPABASE_URL% --dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY=%THAMAN_SUPABASE_PUBLISHABLE_KEY% || goto :fail
echo.
echo [PASS] Test APK: build\app\outputs\flutter-apk\app-debug.apk
pause
exit /b 0
:fail
echo [ERROR] Android test APK build failed.
pause
exit /b 1
