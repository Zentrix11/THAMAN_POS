from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

def read(rel):
    p = ROOT / rel
    return p.read_text(encoding='utf-8') if p.exists() else ''

checks=[]
def check(name, cond):
    checks.append((name,bool(cond)))
    print(('PASS' if cond else 'FAIL') + ' | ' + name)

pub=read('pubspec.yaml')
repo=read('lib/core/subscription/subscription_repository.dart')
store=read('lib/data/app_data_store.dart')
merge=read('lib/data/cloud_state_merge.dart')
secure=read('lib/core/security/secure_kv_store.dart')
hasher=read('lib/core/security/local_credential_hasher.dart')
auth=read('lib/core/auth_service.dart')
sql=read('supabase/migrations/008_pos_cloud_state_sync_and_security_hardening.sql')
gradle=read('android/app/build.gradle.kts')

check('version_0_31_0_38', 'version: 0.31.0+38' in pub)
check('secure_storage_dependency', 'flutter_secure_storage:' in pub)
check('crypto_dependency', 'crypto:' in pub)
check('license_secure_kv', 'SecureKvStore' in repo and 'SharedPreferences' not in repo)
check('strong_device_uid', 'List<int>.generate(24' in repo)
check('server_time_offline_lease', "'server_time'" in repo and 'isOfflineWindowValid' in repo)
check('device_bound_status', "'pos_subscription_status_v2'" in repo)
check('cloud_pull', "'pos_pull_store_state'" in repo)
check('cloud_push_concurrency', "'pos_push_store_state_v2'" in repo and 'expectedRevision' in repo)
check('sequence_reservation_client', "'pos_reserve_sequence_block'" in repo)
check('local_checksum_backup', '_storageChecksumKey' in store and '_backupChecksumKey' in store)
check('corrupt_copy_preserved', '_corruptStorageKey' in store and 'cloud recovery' in store)
check('cloud_baseline_merge', '_cloudBaselineKey' in store and 'CloudStateMerge.diff' in store and 'CloudStateMerge.apply' in store)
check('sequence_invoice', "_nextSequenceValue('invoice')" in store)
check('sequence_customer_supplier', "_nextSequenceValue('customer')" in store and "_nextSequenceValue('supplier')" in store)
check('credential_hashing', 'CredentialHash.encode' in store and 'CredentialHash.verify' in auth)
check('pbkdf2_iterations', '_iterations = 120000' in hasher)
check('merge_by_stable_id', '_byId' in merge and 'upserts' in merge and 'deletes' in merge)
check('sql_store_state_rls', 'alter table public.pos_store_state enable row level security' in sql)
check('sql_direct_table_denied', 'revoke all on table public.pos_store_state from anon, authenticated' in sql)
check('sql_device_validation', 'pos_resolve_active_device' in sql)
check('sql_optimistic_revision', 'pos_push_store_state_v2' in sql and 'sync_conflict' in sql)
check('sql_owner_rate_limit', 'pos_owner_login_attempts' in sql and 'too_many_attempts' in sql)
check('sql_device_bound_subscription', 'pos_subscription_status_v2' in sql)
check('sql_server_time_wrappers', 'pos_activate_device_v2' in sql and 'pos_device_heartbeat_v2' in sql)
check('sql_sequence_blocks', 'pos_reserve_sequence_block' in sql and 'pos_sequence_counters' in sql)
check('release_not_debug_signed', 'signingConfigs.getByName("debug")' not in gradle)
check('release_signing_template', 'keystorePropertiesFile' in gradle and (ROOT/'android/key.properties.example').exists())
check('no_service_role', 'service_role' not in '\n'.join([repo,store,secure,auth]).lower())

passed=sum(1 for _,v in checks if v)
print(f'\nRESULT: {passed}/{len(checks)} PASS')
sys.exit(0 if passed==len(checks) else 1)
