@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo THAMAN POS platform scaffold check
echo.
if exist windows\CMakeLists.txt (echo [OK] Windows) else (echo [MISSING] Windows)
if exist android\app\src\main\AndroidManifest.xml (echo [OK] Android) else (echo [MISSING] Android)
if exist ios\Runner.xcodeproj\project.pbxproj (echo [OK] iOS) else (echo [MISSING] iOS)
if exist macos\Runner.xcodeproj\project.pbxproj (echo [OK] macOS) else (echo [MISSING] macOS)
if exist web\index.html (echo [OK] Web) else (echo [MISSING] Web)
echo.
where flutter >nul 2>nul && flutter doctor -v || echo [INFO] Flutter is not available in PATH on this computer.
pause
