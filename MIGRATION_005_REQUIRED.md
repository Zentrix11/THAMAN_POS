# THAMAN — Migration 005 required

Your Supabase project already has migrations 001–004. For these new builds run only:

`supabase/migrations/005_device_activation_blocking_and_deletes.sql`

This adds real POS device activation/heartbeat, device blocking, and owner-only delete RPCs.

Do not place a Supabase service-role/secret key in either Flutter app. Use only the project URL and publishable key at build time.
