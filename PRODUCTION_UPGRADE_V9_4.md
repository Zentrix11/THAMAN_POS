# THAMAN POS V9.4 Production Hardening / Multi-device Sync

## Required before production
1. Apply Supabase SQL migrations in order: `001` through `008`.
2. Set `THAMAN_SUPABASE_URL` and `THAMAN_SUPABASE_PUBLISHABLE_KEY` for every build/run target.
3. Android: create your private release keystore, copy `android/key.properties.example` to `android/key.properties`, and fill it locally. Never commit or share the keystore/passwords.
4. Run `RUN_FULL_QA.bat` (Windows) or `RUN_FULL_QA.sh` (macOS/Linux) on a machine with Flutter installed.
5. For Web, deploy only over HTTPS because secure browser storage depends on a secure origin.

## What changed
- Operational store state now syncs to Supabase after device/subscription validation.
- Optimistic revision control prevents silent last-write-wins overwrites.
- Stable-ID merge preserves concurrent record additions from multiple devices.
- Stock/customer balance derived baselines allow merged movements to be recomputed.
- Server-reserved sequence blocks reduce duplicate invoice/customer/supplier/etc. numbers across devices.
- Local data remains available as offline cache.
- Primary + backup state checksums, corrupt-copy preservation, and cloud recovery path were added.
- License/device UID/validation metadata moved to secure storage where supported.
- Offline validation rejects future timestamps and prefers server time.
- Local employee/admin credentials are migrated from legacy plaintext to salted PBKDF2-HMAC-SHA256 hashes.
- Android release builds no longer silently use the debug signing key.
- Build/run scripts fail closed when Supabase settings are missing.

## Migration behavior
Existing local data is retained. Legacy plaintext local PIN/password values are automatically upgraded to hashes before persistence/cloud upload. Existing operational data is uploaded after successful subscription/device validation.

## Sync model
This release uses a conflict-aware cloud snapshot model with revision checks and record-level merging. It is appropriate for the current THAMAN data model and multi-device rollout. For very large/high-throughput multi-branch installations, a future normalized transactional backend is still preferable.
