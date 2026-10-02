# THAMAN POS V8.7 — Release Candidate Clean

- Production first-run state is empty of all business/demo data.
- New production storage namespace prevents legacy demo data from older releases loading into V8.7.
- Removed demo credentials and fake employee-ID fallbacks from runtime UI.
- Owner-only full business-data reset while preserving management access accounts.
- Owner can update Owner, Manager and Accountant credentials before launch.
- Hardened native and web printing: optional logo, sanitized text, normalized table rows and safe missing references.
- Arabic native printing is offline-safe using Flutter raster rendering; English native reports use vector PDF.
- macOS print entitlements retained.
- Release/run scripts enforce `flutter analyze` and `flutter test` before build/run on supported host platforms.
- V8.7 source QA includes clean-bootstrap, printing regression, financial-reset and platform checks.
