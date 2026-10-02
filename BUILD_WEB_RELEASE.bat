@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title THAMAN POS V9.5 - Web Release
where flutter >nul 2>nul || (echo [ERROR] Flutter not found in PATH.& pause& exit /b 1)
if "%THAMAN_SUPABASE_URL%"=="" set "THAMAN_SUPABASE_URL=https://bbmeefjtzszysgttryie.supabase.co"
if "%THAMAN_SUPABASE_PUBLISHABLE_KEY%"=="" set "THAMAN_SUPABASE_PUBLISHABLE_KEY=sb_publishable_oqYfMj4kN4D2IN_3rIKQow_9sH9FUt6"
if "%THAMAN_SUPABASE_URL%"=="" (echo [ERROR] THAMAN_SUPABASE_URL is not set.& pause& exit /b 1)
if "%THAMAN_SUPABASE_PUBLISHABLE_KEY%"=="" (echo [ERROR] THAMAN_SUPABASE_PUBLISHABLE_KEY is not set.& pause& exit /b 1)
call flutter config --enable-web >nul || goto :fail
if not exist "web\index.html" call flutter create --platforms=web --org com.zentrix --project-name thaman_pos . || goto :fail
call flutter pub get || goto :fail
call dart run tool\patch_platforms.dart || goto :fail
call flutter analyze || goto :fail
call flutter test || goto :fail
call flutter build web --release --dart-define=THAMAN_SUPABASE_URL=%THAMAN_SUPABASE_URL% --dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY=%THAMAN_SUPABASE_PUBLISHABLE_KEY% || goto :fail
echo.
echo [PASS] Web release: build\web\
pause
exit /b 0
:fail
echo [ERROR] Web release build failed.
pause
exit /b 1
