# THAMAN POS V9.6.2 Final QA Fix

- Serializes Hive writes so test cleanup cannot close a box during a pending write/flush.
- Updates the financial-reset test to create the manager account explicitly, matching production first-run behavior (no bootstrap/demo manager).
- Keeps the V9.6 custom-plans feature set unchanged.
- No new Supabase SQL migration is required for this QA fix.
