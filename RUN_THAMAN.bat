@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if "%THAMAN_SUPABASE_URL%"=="" set "THAMAN_SUPABASE_URL=https://bbmeefjtzszysgttryie.supabase.co"
if "%THAMAN_SUPABASE_PUBLISHABLE_KEY%"=="" set "THAMAN_SUPABASE_PUBLISHABLE_KEY=sb_publishable_oqYfMj4kN4D2IN_3rIKQow_9sH9FUt6"
title THAMAN POS V9.5 - Launcher
:menu
cls
echo ==========================================
echo         THAMAN POS V9.5 Launcher
echo ==========================================
echo 1. Windows
echo 2. Android - build APK / show devices
echo 3. Web - Chrome
echo 4. Flutter doctor
echo 5. Exit
echo.
choice /c 12345 /n /m "Choose: "
if errorlevel 5 exit /b 0
if errorlevel 4 (flutter doctor -v & pause & goto menu)
if errorlevel 3 (call RUN_WEB.bat & goto menu)
if errorlevel 2 (call RUN_ANDROID.bat & goto menu)
if errorlevel 1 (call RUN_WINDOWS.bat & goto menu)
