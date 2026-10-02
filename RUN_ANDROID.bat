@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if "%THAMAN_SUPABASE_URL%"=="" set "THAMAN_SUPABASE_URL=https://bbmeefjtzszysgttryie.supabase.co"
if "%THAMAN_SUPABASE_PUBLISHABLE_KEY%"=="" set "THAMAN_SUPABASE_PUBLISHABLE_KEY=sb_publishable_oqYfMj4kN4D2IN_3rIKQow_9sH9FUt6"
title THAMAN POS V9.5 - Android
where flutter >nul 2>nul || (echo [ERROR] Flutter not found in PATH.& pause& exit /b 1)
if not exist "android\app\src\main\AndroidManifest.xml" (
  echo [REPAIR] Android runner is missing. Generating it in-place...
  call flutter create --platforms=android --org com.zentrix --project-name thaman_pos . || goto :fail
)
call flutter pub get || goto :fail
call dart run flutter_launcher_icons -f flutter_launcher_icons_android.yaml || goto :fail
call dart run tool\patch_platforms.dart || goto :fail
call flutter analyze || goto :fail
call flutter test || goto :fail
call flutter build apk --debug --dart-define=THAMAN_SUPABASE_URL=%THAMAN_SUPABASE_URL% --dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY=%THAMAN_SUPABASE_PUBLISHABLE_KEY% || goto :fail
echo.
echo [PASS] Android debug APK: build\app\outputs\flutter-apk\app-debug.apk
echo Connected devices:
call flutter devices
echo.
echo To launch on a connected Android device/emulator use:
echo   flutter run -d ^<DEVICE_ID^>
pause
exit /b 0
:fail
echo [ERROR] Android preparation/build failed.
pause
exit /b 1
