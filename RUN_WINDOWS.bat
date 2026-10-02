@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if "%THAMAN_SUPABASE_URL%"=="" set "THAMAN_SUPABASE_URL=https://bbmeefjtzszysgttryie.supabase.co"
if "%THAMAN_SUPABASE_PUBLISHABLE_KEY%"=="" set "THAMAN_SUPABASE_PUBLISHABLE_KEY=sb_publishable_oqYfMj4kN4D2IN_3rIKQow_9sH9FUt6"
title THAMAN POS V9.5 - Windows Native

echo ==========================================
echo THAMAN POS V9.5 - Windows Native
echo ==========================================
where flutter >nul 2>nul || (echo [ERROR] Flutter not found in PATH.& pause& exit /b 1)

call flutter config --enable-windows-desktop >nul || goto :fail
if not exist "windows\CMakeLists.txt" (
  echo [REPAIR] Windows runner is missing. Generating it in-place...
  call flutter create --platforms=windows --org com.zentrix --project-name thaman_pos . || goto :fail
)

call flutter pub get || goto :fail
call dart run tool\patch_platforms.dart || goto :fail
call flutter analyze || goto :fail
call flutter test || goto :fail

echo.
echo [CHECK] Looking for the native Windows Flutter device...
flutter devices | findstr /I /C:"Windows (desktop)" >nul
if errorlevel 1 (
  echo.
  echo [ERROR] Flutter does not detect Windows desktop support on this PC.
  echo This launcher will NOT open Chrome as a fallback.
  echo.
  echo Run: flutter doctor -v
  echo Make sure Visual Studio 2022 is installed with:
  echo   Desktop development with C++
  echo Then reopen the terminal and run this file again.
  pause
  exit /b 1
)

echo.
echo [INFO] Starting THAMAN POS as a native Windows application...
call flutter run -d windows --dart-define=THAMAN_SUPABASE_URL=%THAMAN_SUPABASE_URL% --dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY=%THAMAN_SUPABASE_PUBLISHABLE_KEY%
exit /b %errorlevel%

:fail
echo.
echo [ERROR] Windows preparation failed. Run flutter doctor -v and review the first error above.
pause
exit /b 1
