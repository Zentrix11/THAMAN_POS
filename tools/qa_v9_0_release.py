from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
checks=[]

def read(rel):
    return (ROOT/rel).read_text(encoding='utf-8')

def check(name, cond):
    checks.append((name, bool(cond)))

pub=read('pubspec.yaml')
shell=read('lib/features/management/management_shell.dart')
page=read('lib/features/management/section_page.dart')
controller=read('lib/core/app_controller.dart')
permissions=read('lib/core/permissions.dart')
section=read('lib/features/management/sections/subscription_section.dart')
repo=read('lib/core/subscription/subscription_repository.dart')
sql=read('supabase/migrations/004_pos_subscription_status.sql')

check('version:0.27.0+31', 'version: 0.27.0+31' in pub)
check('supabase_dependency', 'supabase_flutter: ^2.17.2' in pub)
check('subscription_enum', 'subscription,' in shell)
check('subscription_nav_ar', "s.text('الاشتراك والباقة', 'Subscription & plan')" in shell)
check('subscription_icon', 'Icons.workspace_premium_outlined' in shell)
check('manager_has_subscription', re.search(r'case UserRole\.manager:.*?ManagementSection\.subscription', shell, re.S) is not None)
check('accountant_has_subscription', re.search(r'case UserRole\.accountant:.*?ManagementSection\.subscription', shell, re.S) is not None)
check('section_route', 'return SubscriptionSection(s: s);' in page)
check('permission_exists', 'viewSubscription' in permissions)
check('manager_permission', re.search(r'case UserRole\.manager:.*?Permission\.viewSubscription', controller, re.S) is not None)
check('accountant_permission', re.search(r'case UserRole\.accountant:.*?Permission\.viewSubscription', controller, re.S) is not None)
check('owner_only_code_edit', 'bool get _isOwner => s.controller.role == UserRole.owner;' in section)
check('real_plan_fields', all(x in section for x in ['اسم المشترك','اسم المتجر','تاريخ البداية','تاريخ الانتهاء','المدة المتبقية','الأجهزة المرتبطة','كود التفعيل']))
check('expiry_warning_ui', 'اشتراكك يقترب من الانتهاء' in section)
check('grace_warning_ui', 'فترة السماح' in section)
check('no_fake_subscription', 'لن يتم عرض أي بيانات وهمية' in section)
check('activation_persisted', 'SharedPreferences' in repo and '_activationCodeKey' in repo)
check('dart_define_url', "String.fromEnvironment('THAMAN_SUPABASE_URL')" in repo)
check('dart_define_key', "String.fromEnvironment('THAMAN_SUPABASE_PUBLISHABLE_KEY')" in repo)
check('rpc_client', "'pos_subscription_status'" in repo)
check('sql_security_definer', 'security definer' in sql.lower())
check('sql_anon_exec_only_function', 'grant execute on function public.pos_subscription_status(text) to anon, authenticated;' in sql)
check('sql_no_table_grant', 'grant select on table' not in sql.lower())
check('sql_devices', "'devices'" in sql and "'active_device_count'" in sql)
check('sql_effective_status', "'effective_status'" in sql and "'grace'" in sql)

failed=[name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS' if ok else 'FAIL') + ' | ' + name)
print(f'\nRESULT: {len(checks)-len(failed)}/{len(checks)} PASS')
if failed:
    raise SystemExit(1)
