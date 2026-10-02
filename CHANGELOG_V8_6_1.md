# THAMAN POS V8.6.1

- Fixed VS Code Run/Debug configuration that previously forced Chrome.
- Added a dedicated `THAMAN POS - Windows` launch profile using `deviceId: windows`.
- Added a generic `THAMAN POS - Select Device` profile.
- Hardened `RUN_WINDOWS.bat` so it launches only native Windows and never falls back to Chrome.
- Added `RUN_WINDOWS_NATIVE.bat` shortcut.
