@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if "%THAMAN_SUPABASE_URL%"=="" set "THAMAN_SUPABASE_URL=https://bbmeefjtzszysgttryie.supabase.co"
if "%THAMAN_SUPABASE_PUBLISHABLE_KEY%"=="" set "THAMAN_SUPABASE_PUBLISHABLE_KEY=sb_publishable_oqYfMj4kN4D2IN_3rIKQow_9sH9FUt6"
where flutter >nul 2>nul || (echo [ERROR] Flutter not found in PATH.& pause& exit /b 1)
where python >nul 2>nul && python tools\qa_static_check.py || exit /b 1
where python >nul 2>nul && python tools\qa_v9_5_final.py || exit /b 1
call flutter clean || exit /b 1
call flutter pub get || exit /b 1
call flutter analyze || exit /b 1
call flutter test --dart-define=THAMAN_SUPABASE_URL=%THAMAN_SUPABASE_URL% --dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY=%THAMAN_SUPABASE_PUBLISHABLE_KEY% || exit /b 1
echo.
echo [PASS] THAMAN POS V9.5.1 remote-enforcement QA completed.
pause
