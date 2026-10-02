from pathlib import Path
import re, sys
BASE=Path('/mnt/data/thaman_work')
POS=BASE/'THAMAN_POS_V9_8_PRODUCTION_HARDENED'
ADM=BASE/'THAMAN_ADMIN_V2_1_PRODUCTION_HARDENED'
SQL=BASE/'THAMAN_SUPABASE_SQL_001_TO_012_PRODUCTION_HARDENED'
checks=[]
def add(group,name,ok,detail=''):
    checks.append((group,name,bool(ok),detail))
def txt(path):
    return path.read_text(encoding='utf-8') if path.exists() else ''
def has(path,*needles):
    s=txt(path)
    return all(n in s for n in needles)
def no(path,*needles):
    s=txt(path)
    return all(n not in s for n in needles)
def balanced(path):
    s=txt(path)
    # Lightweight lexical balance: ignore quoted strings/comments sufficiently for regression catching.
    out=[]; i=0; quote=None; line=False; block=False
    while i<len(s):
        c=s[i]; n=s[i+1] if i+1<len(s) else ''
        if line:
            if c=='\n': line=False; out.append(c)
            i+=1; continue
        if block:
            if c=='*' and n=='/': block=False; i+=2; continue
            i+=1; continue
        if quote:
            if c=='\\': i+=2; continue
            if c==quote: quote=None
            i+=1; continue
        if c=='/' and n=='/': line=True; i+=2; continue
        if c=='/' and n=='*': block=True; i+=2; continue
        if c in "'\"": quote=c; i+=1; continue
        out.append(c); i+=1
    st=[]; pairs={')':'(',']':'[','}':'{'}
    for c in out:
        if c in '([{': st.append(c)
        elif c in ')]}':
            if not st or st.pop()!=pairs[c]: return False
    return not st and quote is None and not block

# ---------- POS (60+) ----------
pos_files={
 'login':POS/'lib/features/auth/admin_login_screen.dart',
 'repo':POS/'lib/core/subscription/subscription_repository.dart',
 'auth':POS/'lib/core/auth_service.dart',
 'store':POS/'lib/data/app_data_store.dart',
 'pos':POS/'lib/features/pos/pos_screen.dart',
 'purchase':POS/'lib/features/management/sections/purchases_section.dart',
 'emp':POS/'lib/features/management/sections/employees_section.dart',
 'att':POS/'lib/features/management/sections/attendance_section.dart',
 'shell':POS/'lib/features/management/management_shell.dart',
 'ctrl':POS/'lib/core/app_controller.dart',
 'dev':POS/'lib/features/management/sections/developer_section.dart',
 'offers':POS/'lib/features/management/sections/offers_plans_section.dart',
 'fin':POS/'lib/features/management/sections/financial_report_dialog.dart',
 'activate':POS/'lib/features/auth/first_run_activation_screen.dart',
}
for k,p in pos_files.items(): add('POS',f'file_{k}',p.exists())
for k in ['login','repo','store','pos','purchase','emp','att','shell','dev','offers','fin']:
    add('POS',f'balanced_{k}',balanced(pos_files[k]))
add('POS','owner_pin_field',has(pos_files['login'],'controller: pin','selectedRole == \'owner\''))
add('POS','owner_login_passes_pin',has(pos_files['login'],'repository.ownerLogin(email: email.text, password: password.text, pin: pin.text)'))
add('POS','owner_cloud_authoritative',has(pos_files['login'],'Owner credentials are authoritative in Supabase'))
add('POS','owner_login_rpc_v3',has(pos_files['repo'],"'pos_owner_login_v3'","'p_pin': pin"))
add('POS','management_owner_pin_required',has(pos_files['auth'],'requiresPin = true'))
add('POS','password_nonempty_activation',has(pos_files['activate'],"if (pwd.isEmpty)"))
add('POS','password_advisory_activation',has(pos_files['activate'],'ننصح بكلمة طويلة ومميزة'))
add('POS','employee_duplicate_only_active',has(pos_files['store'],'duplicate.active','employeeByLoginId(normalized)'))
add('POS','employee_lookup_prefers_active',has(pos_files['store'],'employeeByLoginId','reversed'))
add('POS','employee_reuse_internal_id',has(pos_files['emp'],'millisecondsSinceEpoch','loginId:employeeId'))
add('POS','employee_print_public_login_id',has(pos_files['emp'],'rows:employees.map((e)=>[e.loginId'))
add('POS','employee_profile_public_login_id',has(pos_files['emp'],"'الرقم الوظيفي'","value:e.loginId"))
add('POS','owner_purchase_option',has(pos_files['purchase'],"receivingEmployeeId = '__owner__'"))
add('POS','owner_purchase_no_employee_required',has(pos_files['purchase'],"ownerPurchase = receivingEmployeeId == '__owner__'","employee = ownerPurchase ? null"))
add('POS','owner_purchase_actor_name',has(pos_files['purchase'],'employeeName: employee == null ? s.controller.currentUserName'))
add('POS','return_increments_stock',has(pos_files['store'],'p.stock += qty'))
add('POS','return_stock_movement',has(pos_files['store'],"type: 'return'"))
add('POS','returned_invoice_visible',has(pos_files['pos'],'store.invoices','store.returns'))
add('POS','return_invoice_badge',has(pos_files['pos'],'مرتجع'))
add('POS','checkout_customer_error_flag',has(pos_files['pos'],'customerFieldError'))
add('POS','checkout_paid_error_flag',has(pos_files['pos'],'paidFieldError'))
add('POS','checkout_red_border',has(pos_files['pos'],'AppColors.danger','enabledBorder'))
add('POS','manager_attendance_permission',has(pos_files['ctrl'],'UserRole.manager','Permission.manageAttendance'))
add('POS','accountant_attendance_permission',has(pos_files['ctrl'],'UserRole.accountant','Permission.manageAttendance'))
add('POS','admin_attendance_ids',has(pos_files['shell'],"'ADMIN-${controller.role!.name}'"))
add('POS','attendance_owner_admin_print',has(pos_files['att'],"'ADMIN-manager'","'ADMIN-accountant'"))
add('POS','attendance_staff_print_filter',has(pos_files['att'],"!r.employeeId.startsWith('ADMIN-')"))
add('POS','developer_url_launcher',has(pos_files['dev'],'package:url_launcher/url_launcher.dart','launchUrl'))
add('POS','developer_whatsapp',has(pos_files['dev'],'wa.me/970569477784'))
add('POS','developer_website',has(pos_files['dev'],'https://'))
add('POS','developer_email',has(pos_files['dev'],"scheme: 'mailto'"))
add('POS','url_launcher_dependency',has(POS/'pubspec.yaml','url_launcher: ^6.3.1'))
add('POS','plans_responsive_wrap',has(pos_files['offers'],'Wrap('))
add('POS','financial_three_dot_details',has(pos_files['fin'],'PopupMenuButton','عرض التفاصيل'))
add('POS','financial_purchase_source',has(pos_files['fin'],'purchase'))
add('POS','financial_asset_source',has(pos_files['fin'],'asset'))
add('POS','financial_salary_or_expense_source',('salary' in txt(pos_files['fin']).lower()) or ('expense' in txt(pos_files['fin']).lower()))
add('POS','sql013_bundled',(POS/'013_access_reuse_bulk_lock_and_owner_pin.sql').exists())
# Existing actual unit test token for inventory return regression
unit=POS/'test/app_data_store_test.dart'
add('POS','unit_test_return_stock_exists',has(unit,'sale and return update stock without demo dependencies'))
add('POS','unit_test_return_expected_stock',('19' in txt(unit) and 'return' in txt(unit).lower()))

# ---------- ADMIN (45+) ----------
adm_files={
 'app':ADM/'lib/app.dart','iface':ADM/'lib/data/admin_repository.dart','sup':ADM/'lib/data/supabase_repository.dart','demo':ADM/'lib/data/demo_repository.dart'
}
for k,p in adm_files.items(): add('ADMIN',f'file_{k}',p.exists())
for k,p in adm_files.items(): add('ADMIN',f'balanced_{k}',balanced(p))
add('ADMIN','forgot_password_interface',has(adm_files['iface'],'requestPasswordReset'))
add('ADMIN','forgot_password_supabase',has(adm_files['sup'],'resetPasswordForEmail'))
add('ADMIN','forgot_password_ui',has(adm_files['app'],'_forgotPassword','نسيت كلمة المرور'))
add('ADMIN','bulk_business_interface',has(adm_files['iface'],'deleteBusinessesBulk'))
add('ADMIN','bulk_subscription_interface',has(adm_files['iface'],'deleteSubscriptionsBulk'))
add('ADMIN','bulk_device_interface',has(adm_files['iface'],'deleteDevicesBulk'))
add('ADMIN','bulk_business_rpc',has(adm_files['sup'],"'admin_bulk_delete_businesses'"))
add('ADMIN','bulk_subscription_rpc',has(adm_files['sup'],"'admin_bulk_delete_subscriptions'"))
add('ADMIN','bulk_device_rpc',has(adm_files['sup'],"'admin_bulk_delete_devices'"))
add('ADMIN','demo_bulk_business',has(adm_files['demo'],'deleteBusinessesBulk'))
add('ADMIN','demo_bulk_subscription',has(adm_files['demo'],'deleteSubscriptionsBulk'))
add('ADMIN','demo_bulk_device',has(adm_files['demo'],'deleteDevicesBulk'))
add('ADMIN','business_multiselect',has(adm_files['app'],'final Set<String> selected','widget.data.businesses.where'))
add('ADMIN','subscription_multiselect',has(adm_files['app'],'widget.data.subscriptions.where((e) => selected.contains(e.id))'))
add('ADMIN','device_multiselect',has(adm_files['app'],'widget.data.devices.where((e) => selected.contains(e.id))'))
add('ADMIN','bulk_delete_label',txt(adm_files['app']).count('حذف المحدد')>=3)
add('ADMIN','device_hard_lock_rpc',has(adm_files['sup'],"'admin_set_device_active_v2'"))
add('ADMIN','custom_plan_plus',has(adm_files['app'],'tooltip: \'إضافة باقة مخصصة\'','Icons.add_rounded'))
add('ADMIN','custom_plan_draft',has(adm_files['app'],'_customPlanDraftDialog','durationDays','deviceLimit'))
add('ADMIN','custom_plan_apply',has(adm_files['app'],'repository.applyCustomPlan'))
add('ADMIN','custom_plan_dropdown',has(adm_files['app'],"'__custom__'"))
add('ADMIN','plan_layout_wrap',txt(adm_files['app']).count('Wrap(')>=3)
add('ADMIN','message_unread_loaded',has(adm_files['sup'],'admin_subscription_request_unread_counts_v1','unread_admin_count'))
add('ADMIN','notification_combined_count',has(adm_files['app'],'_adminAlertCount(data)'))
add('ADMIN','notification_tooltip_messages',has(adm_files['app'],'طلبات الاشتراك والرسائل'))
add('ADMIN','password_reset_nonempty',has(adm_files['sup'],"'admin_reset_pos_owner_password'"))
add('ADMIN','sql013_bundled',(ADM/'013_access_reuse_bulk_lock_and_owner_pin.sql').exists())
# repo implementation parity basic method names
iface=txt(adm_files['iface'])
methods=re.findall(r'Future<[^>]+>|Future<void>',iface)
for name in ['requestPasswordReset','deleteBusinessesBulk','deleteSubscriptionsBulk','deleteDevicesBulk']:
    add('ADMIN',f'sup_impl_{name}',f'{name}(' in txt(adm_files['sup']))
    add('ADMIN',f'demo_impl_{name}',f'{name}(' in txt(adm_files['demo']))
# Critical shell/UI regressions
add('ADMIN','owner_role_session_validation',has(adm_files['sup'],'_currentUserIsOwner','admin_profiles'))
add('ADMIN','business_delete_hardened_rpc',has(adm_files['sup'],"'admin_delete_business'"))
add('ADMIN','subscription_delete_hardened_rpc',has(adm_files['sup'],"'admin_delete_subscription'"))
add('ADMIN','email_normalized_reset',has(adm_files['sup'],'trim().toLowerCase()'))
add('ADMIN','reset_message_generic',has(adm_files['app'],'إن كان الحساب مسجلًا'))
add('ADMIN','topbar_combined_alerts',has(adm_files['app'],'requestCount: _adminAlertCount(data)'))

# ---------- SQL 013 (35+) ----------
sql=txt(SQL/'013_access_reuse_bulk_lock_and_owner_pin.sql')
def sh(*needles): return all(n in sql for n in needles)
add('SQL','sql013_exists',bool(sql))
add('SQL','admin_locked_column',sh('admin_locked boolean'))
add('SQL','admin_locked_at',sh('admin_locked_at timestamptz'))
add('SQL','admin_locked_by',sh('admin_locked_by uuid'))
add('SQL','device_active_v2_fn',sh('function public.admin_set_device_active_v2'))
add('SQL','device_lock_sets_admin_locked',sh('admin_locked = not p_active'))
add('SQL','activation_v4_override',sh('function public.pos_activate_device_v4'))
add('SQL','activation_checks_admin_lock',sh('device_admin_locked'))
add('SQL','activation_rate_limit_device',sh('pos_activation_attempts','v_device_failed'))
add('SQL','activation_rate_limit_code',sh('pos_activation_attempts','v_code_failed'))
add('SQL','owner_login_v3',sh('function public.pos_owner_login_v3'))
add('SQL','owner_login_pin',sh('p_pin text','pin_hash'))
add('SQL','owner_login_device_proof',sh('p_device_proof'))
add('SQL','owner_login_rate_device',sh('pos_owner_login_attempts','v_failures'))
add('SQL','owner_login_rate_account',sh('pos_owner_login_attempts','v_account_failures'))
add('SQL','owner_login_temp_expiry',sh('temporary_password_expires_at'))
add('SQL','provision_owner_override',sh('function public.pos_provision_owner'))
add('SQL','provision_nonempty_password',sh("Password cannot be empty"))
add('SQL','admin_reset_owner_password',sh('function public.admin_reset_pos_owner_password'))
add('SQL','owner_change_password',sh('function public.pos_change_owner_password'))
add('SQL','subscription_delete_override',sh('function public.admin_delete_subscription'))
add('SQL','subscription_delete_frees_owner',sh('delete from public.pos_owner_accounts'))
add('SQL','subscription_delete_frees_email',sh("email=null"))
add('SQL','subscription_delete_archives_business',sh("status='archived'"))
add('SQL','bulk_devices',sh('function public.admin_bulk_delete_devices'))
add('SQL','bulk_subscriptions',sh('function public.admin_bulk_delete_subscriptions'))
add('SQL','bulk_businesses',sh('function public.admin_bulk_delete_businesses'))
add('SQL','bulk_businesses_uses_hardened_single',sh('perform public.admin_delete_business(v_id)'))
add('SQL','bulk_subscriptions_uses_hardened_single',sh('perform public.admin_delete_subscription(v_id)'))
add('SQL','revoke_bulk_devices',sh('revoke all on function public.admin_bulk_delete_devices'))
add('SQL','revoke_bulk_subscriptions',sh('revoke all on function public.admin_bulk_delete_subscriptions'))
add('SQL','revoke_bulk_businesses',sh('revoke all on function public.admin_bulk_delete_businesses'))
add('SQL','grant_owner_login_anon',sh('grant execute on function public.pos_owner_login_v3'))
add('SQL','verify013_exists',(SQL/'VERIFY_AFTER_013.sql').exists())
add('SQL','verify013_bulk_businesses',has(SQL/'VERIFY_AFTER_013.sql','bulk_businesses'))
add('SQL','verify013_activation',has(SQL/'VERIFY_AFTER_013.sql','activation_v4_override'))
# Sequence completeness 001..013
for n in range(1,14):
    hits=list(SQL.glob(f'{n:03d}_*.sql'))
    add('SQL',f'migration_{n:03d}_present',bool(hits),','.join(x.name for x in hits))

passed=sum(x[2] for x in checks); failed=len(checks)-passed
print(f'THAMAN BACKLOG RC1 STATIC QA: {passed}/{len(checks)} passed; {failed} failed')
for group,name,ok,detail in checks:
    print(f'[{"PASS" if ok else "FAIL"}] {group:5} {name}' + (f' :: {detail}' if detail else ''))
report=BASE/'QA_THAMAN_BACKLOG_RC1_RESULTS.txt'
report.write_text('\n'.join([f'THAMAN BACKLOG RC1 STATIC QA: {passed}/{len(checks)} passed; {failed} failed']+[f'[{"PASS" if ok else "FAIL"}] {g:5} {n}' + (f' :: {d}' if d else '') for g,n,ok,d in checks])+'\n',encoding='utf-8')
sys.exit(1 if failed else 0)
