#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v flutter >/dev/null || { echo "[ERROR] Flutter not found in PATH"; exit 1; }

THAMAN_SUPABASE_URL="${THAMAN_SUPABASE_URL:-https://bbmeefjtzszysgttryie.supabase.co}"
THAMAN_SUPABASE_PUBLISHABLE_KEY="${THAMAN_SUPABASE_PUBLISHABLE_KEY:-sb_publishable_oqYfMj4kN4D2IN_3rIKQow_9sH9FUt6}"
SUPABASE_DEFINES=("--dart-define=THAMAN_SUPABASE_URL=${THAMAN_SUPABASE_URL}" "--dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY=${THAMAN_SUPABASE_PUBLISHABLE_KEY}")
[[ "$(uname -s)" == "Darwin" ]] || { echo "[ERROR] iOS release builds require macOS + Xcode."; exit 1; }
if [[ ! -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  flutter create --platforms=ios --org com.zentrix --project-name thaman_pos .
fi
flutter pub get
dart run flutter_launcher_icons -f flutter_launcher_icons_ios.yaml
dart run tool/patch_platforms.dart
flutter analyze
flutter test
flutter build ios --release --no-codesign "${SUPABASE_DEFINES[@]}"
echo "[PASS] Unsigned iOS release build completed. Apple signing is required for installation/distribution."
