#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v flutter >/dev/null || { echo "[ERROR] Flutter not found in PATH"; exit 1; }

THAMAN_SUPABASE_URL="${THAMAN_SUPABASE_URL:-https://bbmeefjtzszysgttryie.supabase.co}"
THAMAN_SUPABASE_PUBLISHABLE_KEY="${THAMAN_SUPABASE_PUBLISHABLE_KEY:-sb_publishable_oqYfMj4kN4D2IN_3rIKQow_9sH9FUt6}"
SUPABASE_DEFINES=("--dart-define=THAMAN_SUPABASE_URL=${THAMAN_SUPABASE_URL}" "--dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY=${THAMAN_SUPABASE_PUBLISHABLE_KEY}")
[[ "$(uname -s)" == "Darwin" ]] || { echo "[ERROR] iOS builds require macOS + Xcode."; exit 1; }
if [[ ! -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  echo "[REPAIR] iOS runner is missing. Generating it in-place..."
  flutter create --platforms=ios --org com.zentrix --project-name thaman_pos .
fi
flutter pub get
dart run flutter_launcher_icons -f flutter_launcher_icons_ios.yaml
dart run tool/patch_platforms.dart
flutter analyze
flutter test
flutter build ios --debug --no-codesign "${SUPABASE_DEFINES[@]}"
echo
echo "[PASS] iOS debug build completed without code signing."
echo "Connect an iPhone or start a Simulator, then run: flutter devices"
echo "Launch with: flutter run -d <DEVICE_ID>"
