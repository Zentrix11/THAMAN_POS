from pathlib import Path
import re, sys, zipfile

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'lib'
errors = []
checks = []

def ok(name, cond, detail=''):
    checks.append((name, bool(cond), detail))
    if not cond:
        errors.append(name + (f': {detail}' if detail else ''))

# Project essentials
for rel in ['pubspec.yaml','lib/main.dart','lib/data/app_data_store.dart','lib/data/models.dart','lib/features/auth/access_screen.dart','lib/features/auth/admin_login_screen.dart']:
    ok(f'file:{rel}', (ROOT/rel).exists())

dart_files = list(LIB.rglob('*.dart')) + list((ROOT / 'test').rglob('*.dart'))
ok('dart_files>=30', len(dart_files) >= 30, str(len(dart_files)))

# Imports, directives, simple delimiter scanner, accidental markdown.
for f in dart_files:
    txt = f.read_text(encoding='utf-8')
    rel = f.relative_to(ROOT)
    ok(f'no_markdown:{rel}', '```' not in txt)
    seen_decl = False
    for n, line in enumerate(txt.splitlines(), 1):
        s = line.strip()
        if not s or s.startswith('//') or s.startswith('/*') or s.startswith('*'):
            continue
        if s.startswith(('import ', 'export ', 'part ', 'library ')):
            ok(f'directive_order:{rel}:{n}', not seen_decl)
        else:
            seen_decl = True
    for m in re.finditer(r"import\s+'([^']+)'", txt):
        p = m.group(1)
        if p.startswith(('package:', 'dart:')):
            continue
        ok(f'import:{rel}:{p}', (f.parent / p).resolve().exists())
    for m in re.finditer(r"Image\.asset\(\s*'([^']+)'", txt):
        asset = m.group(1)
        ok(f'asset_ref:{asset}', (ROOT / asset).exists())

    stack = []
    pairs = {')':'(', ']':'[', '}':'{'}
    opens = set(pairs.values())
    i = 0; line = 1; state = 'code'; quote = ''; triple = False
    bad = None
    while i < len(txt):
        c = txt[i]; nxt = txt[i+1] if i+1 < len(txt) else ''
        if c == '\n': line += 1
        if state == 'line_comment':
            if c == '\n': state = 'code'
            i += 1; continue
        if state == 'block_comment':
            if c == '*' and nxt == '/': state = 'code'; i += 2; continue
            i += 1; continue
        if state == 'string':
            if c == '\\': i += 2; continue
            if triple:
                if txt[i:i+3] == quote*3: state = 'code'; i += 3; continue
            elif c == quote:
                state = 'code'; i += 1; continue
            i += 1; continue
        if c == '/' and nxt == '/': state = 'line_comment'; i += 2; continue
        if c == '/' and nxt == '*': state = 'block_comment'; i += 2; continue
        if c in "'\"":
            quote = c; triple = txt[i:i+3] == c*3; state = 'string'; i += 3 if triple else 1; continue
        if c in opens: stack.append((c, line))
        elif c in pairs:
            if not stack or stack[-1][0] != pairs[c]: bad = f'unmatched {c} line {line}'; break
            stack.pop()
        i += 1
    if bad is None and stack: bad = f'unclosed {stack[-1]}'
    ok(f'delimiters:{rel}', bad is None, bad or '')

# Declared assets exist.
pub = (ROOT/'pubspec.yaml').read_text(encoding='utf-8')
for asset in re.findall(r'^\s*-\s+(assets/[^\s]+)\s*$', pub, re.M):
    ok(f'pubspec_asset:{asset}', (ROOT/asset).exists())

# Explicit release requirements.
all_src = '\n'.join(f.read_text(encoding='utf-8') for f in dart_files)
requirements = {
    'manager_login_account': 'updateAdminCredentials' in all_src and "'manager' => UserRole.manager" in all_src,
    'management_three_factor_fields': 'Management PIN' in all_src and 'password' in (ROOT/'lib/features/auth/admin_login_screen.dart').read_text(encoding='utf-8'),
    'financial_summary_screen': 'class FinancialSummarySection' in all_src and 'netProfit' in all_src and 'totalReceivables' in all_src and 'totalPayables' in all_src,
    'supplier_payments': 'recordSupplierPayment' in all_src and 'purchaseOutstanding' in all_src,
    'customer_collections': 'recordCustomerPayment' in all_src,
    'purchase_units': 'purchaseUnit' in all_src and 'unitsPerPurchaseUnit' in all_src and 'packageWeightKg' in all_src,
    'landed_cost': 'landedBaseUnitCost' in all_src and 'allocatedExtra' in all_src,
    'inventory_sets_pos_price': ('POS selling price' in all_src or 'سعر البيع للكاشير' in all_src) and 'receiving_price_updated' in all_src,
    'owner_manager_product_management': 'addManagedProduct' in all_src and 'updateManagedProduct' in all_src,
    'brand_access_pattern_merged': '_AccessHeroDecorationPainter' in all_src and 'path.cubicTo' in all_src and "Image.asset('assets/thaman-access-pattern.png')" not in all_src,
    'bulk_inventory_checkbox': 'showInventoryBatchOperation' in all_src and all_src.count('CheckboxListTile') >= 3,
    'bulk_purchase_checkbox': '_MultiPurchasePickerDialog' in all_src and 'Select multiple purchase items' in all_src,
    'independent_operation_units': 'operationQuantity' in all_src and 'unitsPerOperationUnit' in all_src,
    'item_specific_operation_notes': 'Item-specific note' in all_src and 'line.itemNote' in all_src and 'line.note' in all_src,
    'selected_stock_count': 'addExistingStockCountLines' in all_src and 'productIds' in (ROOT/'lib/data/app_data_store.dart').read_text(encoding='utf-8'),
    'stock_count_independent_units': all(x in all_src for x in ['updateStockCountEntry', 'countUnit', 'unitsPerCountUnit', 'enteredQuantity']),
    'live_management_updates': 'attendanceUpdates' in all_src and 'completedTasks' in all_src,
    'internal_messaging': all(x in all_src for x in ['MessageRecord', 'sendMessage', 'messagesForManagement', 'messagesForEmployee', 'CommunicationsSection']),
    'restock_workflow': all(x in all_src for x in ['RestockRequest', 'createRestockRequest', 'updateRestockStatus', 'RestockRequestsSection']),
    'low_stock_actions': all(x in all_src for x in ['إضافة ملاحظة', 'إشعار المخزون', 'طلب بضاعة']),
    'financial_period_centralized': 'FinancialPeriodSummary financialSummary' in all_src and 'Monthly profit reconciliation' in all_src,
    'management_product_notes': 'addProductNote' in all_src and 'Add note' in all_src,
    'tasks_attendance_inventory_workflows': all(x in all_src for x in ['createTask','clockIn','clockOut','startStockCount','recordDamage','transferStock']),
    'held_sales_returns': all(x in all_src for x in ['holdSale','takeHeldSale','returnSale']),
    'serial_invoices': "_nextSequenceValue('invoice')" in all_src,
    'audit_log': 'AuditLogRecord' in all_src and '_recordAudit' in all_src,
}
for name, cond in requirements.items(): ok('requirement:'+name, cond)

# AI attribution should not be embedded in distributable project text/code.
scan_files = [p for p in ROOT.rglob('*') if p.is_file() and p.suffix.lower() in {'.dart','.md','.txt','.yaml','.html','.bat'}]
for p in scan_files:
    txt = p.read_text(encoding='utf-8', errors='ignore').lower()
    ok(f'no_ai_attribution:{p.relative_to(ROOT)}', 'chatgpt' not in txt and 'openai' not in txt)

passed = sum(1 for _,v,_ in checks if v)
print(f'THAMAN static QA: {passed}/{len(checks)} checks passed')
if errors:
    print(f'FAILED: {len(errors)}')
    for e in errors[:100]: print(' -', e)
    sys.exit(1)
print('RESULT: PASS (static/source integrity checks)')
