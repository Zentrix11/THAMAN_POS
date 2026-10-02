#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v flutter >/dev/null || { echo "[ERROR] Flutter not found in PATH"; exit 1; }

THAMAN_SUPABASE_URL="${THAMAN_SUPABASE_URL:-https://bbmeefjtzszysgttryie.supabase.co}"
THAMAN_SUPABASE_PUBLISHABLE_KEY="${THAMAN_SUPABASE_PUBLISHABLE_KEY:-sb_publishable_oqYfMj4kN4D2IN_3rIKQow_9sH9FUt6}"
SUPABASE_DEFINES=("--dart-define=THAMAN_SUPABASE_URL=${THAMAN_SUPABASE_URL}" "--dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY=${THAMAN_SUPABASE_PUBLISHABLE_KEY}")
[[ "$(uname -s)" == "Darwin" ]] || { echo "[ERROR] macOS builds require macOS + Xcode."; exit 1; }
flutter config --enable-macos-desktop >/dev/null
if [[ ! -f macos/Runner.xcodeproj/project.pbxproj ]]; then
  echo "[REPAIR] macOS runner is missing. Generating it in-place..."
  flutter create --platforms=macos --org com.zentrix --project-name thaman_pos .
fi
flutter pub get
dart run flutter_launcher_icons -f flutter_launcher_icons_macos.yaml
dart run tool/patch_platforms.dart
flutter analyze
flutter test
flutter run -d macos "${SUPABASE_DEFINES[@]}"
