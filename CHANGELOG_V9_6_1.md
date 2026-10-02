# THAMAN POS V9.6.1 — Final QA test harness fix

- Fixed Flutter unit tests that used Hive CE through `Hive.initFlutter()` without a mocked `path_provider` channel.
- Added a test-only database reset helper so each AppDataStore test starts from a truly clean Hive state.
- Added `LocalCredentialHasher.needsUpgrade()` and centralized the legacy-credential migration check.
- No business logic, subscription behavior, licensing limits, or production storage paths were changed.
