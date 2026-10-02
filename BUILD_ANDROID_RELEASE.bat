@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title THAMAN POS V9.5 - Android Release APK

if "%THAMAN_SUPABASE_URL%"=="" set "THAMAN_SUPABASE_URL=https://bbmeefjtzszysgttryie.supabase.co"
if "%THAMAN_SUPABASE_PUBLISHABLE_KEY%"=="" set "THAMAN_SUPABASE_PUBLISHABLE_KEY=sb_publishable_oqYfMj4kN4D2IN_3rIKQow_9sH9FUt6"

where flutter >nul 2>nul || (echo [ERROR] Flutter not found in PATH.& pause& exit /b 1)
if not exist "android\key.properties" (
  echo [ERROR] android\key.properties is required for a signed production APK.
  echo See android\key.properties.example
  pause
  exit /b 1
)
if not exist "android\gradlew.bat" call flutter create --platforms=android --org com.zentrix --project-name thaman_pos . || goto :fail

call flutter clean || goto :fail
call flutter pub get || goto :fail
call dart run flutter_launcher_icons -f flutter_launcher_icons_android.yaml || goto :fail
call dart run tool\patch_platforms.dart || goto :fail
call flutter analyze || goto :fail
call flutter test || goto :fail
call flutter build apk --release --dart-define=THAMAN_SUPABASE_URL=%THAMAN_SUPABASE_URL% --dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY=%THAMAN_SUPABASE_PUBLISHABLE_KEY% || goto :fail

echo.
echo [PASS] THAMAN POS V9.5 Android APK created.
echo APK: build\app\outputs\flutter-apk\app-release.apk
pause
exit /b 0

:fail
echo.
echo [ERROR] Android release build failed.
pause
exit /b 1
