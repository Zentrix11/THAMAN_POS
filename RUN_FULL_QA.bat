@echo off
setlocal
cd /d "%~dp0"
python tools\qa_static_check.py || exit /b 1
python tools\qa_v9_4_release.py || exit /b 1
if "%THAMAN_SUPABASE_URL%"=="" set "THAMAN_SUPABASE_URL=https://bbmeefjtzszysgttryie.supabase.co"
if "%THAMAN_SUPABASE_PUBLISHABLE_KEY%"=="" set "THAMAN_SUPABASE_PUBLISHABLE_KEY=sb_publishable_oqYfMj4kN4D2IN_3rIKQow_9sH9FUt6"
if "%THAMAN_SUPABASE_URL%"=="" echo Missing THAMAN_SUPABASE_URL & exit /b 1
if "%THAMAN_SUPABASE_PUBLISHABLE_KEY%"=="" echo Missing THAMAN_SUPABASE_PUBLISHABLE_KEY & exit /b 1
call flutter pub get || exit /b 1
call flutter analyze || exit /b 1
call flutter test || exit /b 1
call flutter build web --release --dart-define=THAMAN_SUPABASE_URL=%THAMAN_SUPABASE_URL% --dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY=%THAMAN_SUPABASE_PUBLISHABLE_KEY% || exit /b 1
echo THAMAN V9.4 QA completed successfully.
endlocal
