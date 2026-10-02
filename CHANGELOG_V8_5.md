# THAMAN POS V8.5 — All Platforms Ready

## Platform runners included
- Windows (`windows/`)
- Android (`android/`)
- iOS / iPhone & iPad (`ios/`)
- macOS (`macos/`)
- Web (`web/`)

The platform folders are now shipped inside the project instead of relying only on temporary bootstrap projects.

## Reliability improvements
- Reworked Windows bootstrap so it no longer moves a temporary Windows project into the app.
- Reworked Android/iOS/macOS run scripts to use the included runners and only create a missing runner in-place.
- Added platform scaffold checker: `CHECK_PLATFORM_SUPPORT.bat`.
- Added direct release build scripts for Windows, Android, iOS, macOS and Web.
- Updated Android Gradle/Kotlin template compatibility settings for current Flutter tooling.
- Fixed Windows runner C++ visibility/linking details used by the native window bootstrap.
- Fixed macOS Flutter Assemble configuration inheritance.

## Branding
- App name: **THAMAN POS**
- Application / bundle ID: `com.zentrix.thamanpos`
- THAMAN icon is included for Windows, Android, iOS, macOS and Web.

## V8.4 fixes retained
- Owner-only financial reset workflow and asset printing changes remain included.
- POS `_paymentLabel` scope error is fixed by using a shared file-level helper.

## Version
- Flutter app version: `0.22.0+23`
