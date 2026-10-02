from pathlib import Path
import re, sys
ROOT = Path(__file__).resolve().parents[1]
checks=[]
def check(name, ok, detail=''):
    checks.append((name,bool(ok),detail))

def read(rel):
    p=ROOT/rel
    return p.read_text(encoding='utf-8') if p.exists() else ''

pub=read('pubspec.yaml')
store=read('lib/data/app_data_store.dart')
models=read('lib/data/models.dart')
admin=read('lib/features/auth/admin_login_screen.dart')
staff=read('lib/features/auth/staff_login_screen.dart')
web=read('lib/core/printing/print_service_web.dart')
native=read('lib/core/printing/print_service_native.dart')
templates=read('lib/core/printing/print_templates.dart')
tests=read('test/app_data_store_test.dart')
settings=read('lib/features/management/sections/settings_section.dart')
staff_home=read('lib/features/staff/staff_home.dart')
attendance=read('lib/features/management/sections/attendance_section.dart')
management_widgets=read('lib/features/management/widgets/management_widgets.dart')
batch=read('lib/features/inventory/inventory_batch_dialog.dart')

for d in ['windows','android','ios','macos','web']:
    check(f'platform:{d}', (ROOT/d).is_dir())
check('version:0.25.1+29', 'version: 0.25.1+29' in pub)
check('production storage key', "thaman_pos_state_v8_7_production" in store)
check('no demo seeder', '_seedDemoData(' not in store)
check('clean first-run bootstrap', '_seedProductionAccessAccounts();' in store and 'products.isEmpty || employees.isEmpty' not in store)
check('business reset exists', 'Future<void> resetBusinessData()' in store)
check('business reset preserves management accounts', 'final managementAccounts = adminAccounts' in store and 'adminAccounts.addAll(managementAccounts)' in store)
check('neutral store name default', "this.storeName = ''" in models)
check('neutral branch default', "this.branchName = ''" in models)
check('neutral receipt footer default', "this.receiptFooter = ''" in models)
check('admin login not prefilled', 'TextEditingController(text:' not in admin)
check('staff login not prefilled', 'TextEditingController(text:' not in staff)
check('no demo credentials admin UI', 'Commercial demo credentials' not in admin and 'بيانات العرض التجاري' not in admin)
check('no demo credentials staff UI', 'Demo staff accounts' not in staff and 'حسابات العرض' not in staff)
check('production reset UI', 'Clear business data' in settings and 'resetBusinessData()' in settings)
check('business reset owner only', "if(s.controller.role==UserRole.owner) ...[" in settings and 'هذا الخيار للمالك فقط.' in settings)
check('owner credentials editable', "PopupMenuItem(value:'owner'" in settings and "targetRole:role" in settings)
check('admin credential updates owner-authorized', "if (actorRole != 'owner') return false;" in store and "targetRole == 'owner'" not in store)
check('no runtime demo identifiers', all(token not in (store+admin+staff+staff_home) for token in ['I-203','E-310','C-104','M-301','THAMAN Market','_seedDemoData','resetDemo']))
check('staff session has no fake-id fallback', "controller.employeeId ?? '" not in staff_home)
check('attendance readable lateness formatter', 'formatReadableMinutes' in management_widgets and "return parts.join(' و');" in management_widgets)
check('attendance UI uses readable lateness', 'formatReadableMinutes(s, lateMinutes)' in attendance and "'$lateMinutes m" not in attendance)
check('attendance print uses readable lateness', 'formatReadableMinutes(s, store.lateMinutes(r))' in attendance)
check('unified stock entry action visible', "s.text('إدخال بضاعة للمخزون', 'Stock entry')" in staff_home and "_showInventoryAction(context, s, 'purchase')" in staff_home)
check('inventory staff no duplicate receive/purchase cards', "_showInventoryAction(context, s, 'receive')" not in staff_home and "s.text('شراء بضاعة', 'Purchase stock')" not in staff_home)
barcode_station=read('lib/features/inventory/barcode_station_screen.dart')
check('barcode station uses unified stock entry', "_operation('receive')" not in barcode_station and "s.text('إدخال هذا الصنف', 'Enter stock')" in barcode_station)
check('inventory purchase supports full new-product details', all(token in batch for token in ['line.nameEn','line.newSku','line.categoryAr','line.categoryEn','line.minStock']))
check('inventory purchase duplicate SKU protection', 'A duplicate SKU was found' in batch)
check('inventory product creation role restricted', 'addInventoryPurchaseProduct' in store and "actorRole != 'inventory'" in store)
check('inventory purchase regression tests', 'attendance lateness is formatted as hours and minutes' in tests and 'inventory staff can create a detailed product through purchasing' in tests)

check('native print catches failures', 'try {' in native and 'return false;' in native)
check('arabic native offline raster', 'document.isArabic\n        ? await _buildArabicRasterPdf(document)' in native)
check('no runtime Google font dependency', 'PdfGoogleFonts.' not in native)
check('native logo optional', 'Printing remains usable even if the optional brand image cannot load.' in native)
check('web popup opened synchronously', "web.window.open('', '_blank')" in web)
check('web logo optional', 'The report must still print if the optional logo asset is unavailable.' in web)
check('web rows normalized', '_normalizedRow(row, columnCount)' in web)
check('web HTML escaped', 'HtmlEscape' in web and '_e(cell)' in web)
check('print text sanitized', '_cleanPrintText' in native and "replaceAll('\\u0000', '')" in native)
check('return notice missing invoice safe', 'SaleInvoice? invoice;' in templates and 'firstWhere((i) => i.id == record.invoiceId)' not in templates)
check('inventory employee safe print copy exists', 'stockCountCounterCopy' in templates)
check('management stock-count report exists', 'static PrintDocument stockCount(' in templates)
check('assets print exists', 'static PrintDocument assetsReport(' in templates)
check('accounting print exists', 'static PrintDocument accountingStatement(' in templates)
check('customer print exists', 'static PrintDocument customerStatement(' in templates)
check('supplier print exists', 'static PrintDocument supplierStatement(' in templates)
check('sale print exists', 'static PrintDocument saleInvoice(' in templates)
check('purchase print exists', 'static PrintDocument purchaseReceipt(' in templates)
check('return print exists', 'static PrintDocument returnNotice(' in templates)
check('movement print exists', 'static PrintDocument stockMovementNotice(' in templates)

for f in ['macos/Runner/Release.entitlements','macos/Runner/DebugProfile.entitlements']:
    txt=read(f)
    check(f'print entitlement:{f}', 'com.apple.security.print' in txt)

for f in ['RUN_WINDOWS.bat','RUN_ANDROID.bat','RUN_WEB.bat']:
    txt=read(f)
    check(f'quality analyze:{f}', 'flutter analyze' in txt)
    check(f'quality test:{f}', 'flutter test' in txt)
for f in ['BUILD_WINDOWS_RELEASE.bat','BUILD_ANDROID_RELEASE.bat','BUILD_WEB_RELEASE.bat','BUILD_IOS_RELEASE.sh','BUILD_MACOS_RELEASE.sh']:
    txt=read(f)
    check(f'release analyze:{f}', 'flutter analyze' in txt)
    check(f'release test:{f}', 'flutter test' in txt)
check('windows native device fixed', 'flutter run -d windows' in read('RUN_WINDOWS.bat'))
check('web explicit chrome', 'flutter run -d chrome' in read('RUN_WEB.bat'))
check('ios build script present', (ROOT/'RUN_IOS.sh').exists())
check('macos build script present', (ROOT/'RUN_MACOS.sh').exists())

check('production empty-data test', 'production first run contains no business/demo data' in tests)
check('print structure test', 'core print templates have consistent columns' in tests)
check('missing invoice print regression test', 'return notice remains printable even if original invoice is unavailable' in tests)
check('financial reset trim test', "verifyManagerPassword(' Manager@2026 ')" in tests)

# Basic delimiter sanity scan ignoring strings/comments imperfectly but useful for packaging QA.
pairs={')':'(',']':'[','}':'{'}
for p in list((ROOT/'lib').rglob('*.dart')) + list((ROOT/'test').rglob('*.dart')):
    text=p.read_text(encoding='utf-8')
    stack=[]; quote=None; esc=False; line_comment=False; block_comment=False; i=0
    ok=True
    while i < len(text):
        ch=text[i]; nxt=text[i+1] if i+1<len(text) else ''
        if line_comment:
            if ch=='\n': line_comment=False
            i+=1; continue
        if block_comment:
            if ch=='*' and nxt=='/': block_comment=False; i+=2; continue
            i+=1; continue
        if quote:
            if esc: esc=False
            elif ch=='\\': esc=True
            elif text.startswith(quote, i): i += len(quote); quote=None; continue
            i+=1; continue
        if ch=='/' and nxt=='/': line_comment=True; i+=2; continue
        if ch=='/' and nxt=='*': block_comment=True; i+=2; continue
        if text.startswith("'''", i) or text.startswith('"""', i): quote=text[i:i+3]; i+=3; continue
        if ch in "'\"": quote=ch; i+=1; continue
        if ch in '([{': stack.append(ch)
        elif ch in ')]}':
            if not stack or stack[-1]!=pairs[ch]: ok=False; break
            stack.pop()
        i+=1
    if stack: ok=False
    check(f'delimiters:{p.relative_to(ROOT)}', ok)

failed=[x for x in checks if not x[1]]
for name,ok,detail in checks:
    print(('[PASS] ' if ok else '[FAIL] ')+name+(f' ({detail})' if detail else ''))
print(f'\nTHAMAN V8.8.1 RELEASE QA: {len(checks)-len(failed)}/{len(checks)} PASS')
if failed:
    sys.exit(1)
