#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
python3 tools/qa_static_check.py
python3 tools/qa_v9_4_release.py
THAMAN_SUPABASE_URL="${THAMAN_SUPABASE_URL:-https://bbmeefjtzszysgttryie.supabase.co}"
THAMAN_SUPABASE_PUBLISHABLE_KEY="${THAMAN_SUPABASE_PUBLISHABLE_KEY:-sb_publishable_oqYfMj4kN4D2IN_3rIKQow_9sH9FUt6}"
flutter pub get
flutter analyze
flutter test
flutter build web --release \
  --dart-define=THAMAN_SUPABASE_URL="$THAMAN_SUPABASE_URL" \
  --dart-define=THAMAN_SUPABASE_PUBLISHABLE_KEY="$THAMAN_SUPABASE_PUBLISHABLE_KEY"
echo "THAMAN V9.4 QA completed successfully."
