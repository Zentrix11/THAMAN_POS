import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'cloud_state_merge.dart';
import 'local_state_database.dart';
import '../core/credential_hash.dart';
import '../core/subscription/subscription_repository.dart';

class AppDataStore extends ChangeNotifier {
  final Random _idRandom = Random.secure();
  AppDataStore._();
  static final AppDataStore instance = AppDataStore._();
  static const _storageKey = 'thaman_pos_state_v8_7_production';
  static const _backupStorageKey = 'thaman_pos_state_v8_7_production_backup';
  static const _storageChecksumKey = 'thaman_pos_state_v8_7_production_sha256';
  static const _backupChecksumKey = 'thaman_pos_state_v8_7_production_backup_sha256';
  static const _corruptStorageKey = 'thaman_pos_state_v8_7_corrupt_recovery_copy';
  static const _cloudBaselineKey = 'thaman_pos_cloud_sync_baseline_v1';

  final List<ProductModel> products = [];
  final List<SaleInvoice> invoices = [];
  final List<HeldSale> heldSales = [];
  final List<ReturnRecord> returns = [];
  final List<StockMovement> stockMovements = [];
  final List<AttendanceRecord> attendance = [];
  final List<OvertimeRecord> overtimeRecords = [];
  final List<EmployeeAdvanceRecord> employeeAdvances = [];
  final List<TaskRecord> tasks = [];
  final List<EmployeeRecord> employees = [];
  final List<AdminAccountRecord> adminAccounts = [];
  final List<AuditLogRecord> auditLogs = [];
  final List<LeaveRecord> leaves = [];
  final List<PurchaseReceipt> purchases = [];
  final List<PurchaseReturnRecord> purchaseReturns = [];
  final List<ProductNote> productNotes = [];
  final List<CustomerRecord> customers = [];
  final List<SupplierRecord> suppliers = [];
  final List<SupplierPaymentRecord> supplierPayments = [];
  final List<CustomerPaymentRecord> customerPayments = [];
  final List<ExpenseRecord> expenses = [];
  final List<StockCountSession> stockCounts = [];
  final List<AssetRecord> assets = [];
  final List<MessageRecord> messages = [];
  final List<RestockRequest> restockRequests = [];
  final List<JournalEntry> journalEntries = [];
  final Set<String> readNotifications = <String>{};
  final Set<String> hiddenNotifications = <String>{};
  StoreSettings settings = StoreSettings();
  DateTime? financialResetAt;
  bool _forceLocalCloudAuthority = false;
  int _mutationGen = 0;
  Timer? _saveDebounce;
  Timer? _cloudPushTimer;
  bool _applyingCloudState = false;
  bool _cloudSyncBusy = false;
  bool _localCorruptionDetected = false;
  final Map<String, int> _stockBaselines = <String, int>{};
  final Map<String, double> _customerBalanceBaselines = <String, double>{};
  final Map<String, int> _sequenceEnds = <String, int>{};

  int _invoiceSerial = 1000;
  int _purchaseSerial = 2000;
  int _stockCountSerial = 0;
  int _productSerial = 0;
  int _restockSerial = 3000;
  int _journalSerial = 0;
  int _customerSerial = 0;
  int _supplierSerial = 0;

  Future<void> initialize() async {
    final database = LocalStateDatabase.instance;
    await database.initialize();

    // Preferred V9.4+ path: critical operational data lives in Hive CE.
    var raw = database.primaryRaw;
    var checksum = database.primaryChecksum;
    if (raw != null && raw.isNotEmpty) {
      if (_isValidPayload(raw, checksum)) {
        try {
          _restore((jsonDecode(raw) as Map).cast<String, dynamic>());
          _ensureDerivedBaselines();
          return;
        } catch (_) {}
      }

      _localCorruptionDetected = true;
      await database.preserveCorruptPrimary(raw);
      final backup = database.backupRaw;
      final backupChecksum = database.backupChecksum;
      if (backup != null &&
          backup.isNotEmpty &&
          _isValidPayload(backup, backupChecksum)) {
        try {
          _restore((jsonDecode(backup) as Map).cast<String, dynamic>());
          _ensureDerivedBaselines();
          await _persistMap(
            _serializeState(),
            scheduleCloud: false,
            rollBackup: false,
          );
          return;
        } catch (_) {}
      }
    }

    // One-time V9.3 -> V9.4 migration. Read the old SharedPreferences state,
    // write it to Hive, hash local credentials, then remove the sensitive old
    // copies only after the new database write succeeds.
    final prefs = await SharedPreferences.getInstance();
    final legacyRaw = prefs.getString(_storageKey);
    final legacyChecksum = prefs.getString(_storageChecksumKey);
    if (legacyRaw != null &&
        legacyRaw.isNotEmpty &&
        _isValidPayload(legacyRaw, legacyChecksum)) {
      try {
        _restore((jsonDecode(legacyRaw) as Map).cast<String, dynamic>());
        _ensureDerivedBaselines();
        await _save(scheduleCloud: false);
        await _clearLegacyOperationalPrefs(prefs);
        return;
      } catch (_) {
        _localCorruptionDetected = true;
        await database.preserveCorruptPrimary(legacyRaw);
      }
    }

    final legacyBackup = prefs.getString(_backupStorageKey);
    final legacyBackupChecksum = prefs.getString(_backupChecksumKey);
    if (legacyBackup != null &&
        legacyBackup.isNotEmpty &&
        _isValidPayload(legacyBackup, legacyBackupChecksum)) {
      try {
        _restore((jsonDecode(legacyBackup) as Map).cast<String, dynamic>());
        _ensureDerivedBaselines();
        await _save(scheduleCloud: false);
        await _clearLegacyOperationalPrefs(prefs);
        return;
      } catch (_) {}
    }

    if (raw == null || raw.isEmpty) {
      _clearAll();
      _ensureDerivedBaselines();
      await _save(scheduleCloud: false);
      await _clearLegacyOperationalPrefs(prefs);
      return;
    }

    // Both local copies are unusable. Do not persist an empty replacement;
    // once the license is validated, cloud sync gets a chance to restore data.
    _clearAll();
    _ensureDerivedBaselines();
  }

  Future<void> _clearLegacyOperationalPrefs(SharedPreferences prefs) async {
    for (final key in const [
      _storageKey,
      _backupStorageKey,
      _storageChecksumKey,
      _backupChecksumKey,
      _corruptStorageKey,
      _cloudBaselineKey,
    ]) {
      await prefs.remove(key);
    }
  }

  /// Conflict-aware multi-device synchronization.
  ///
  /// Local changes are diffed against the last successful cloud baseline and
  /// rebased on the newest server revision. This preserves unrelated changes
  /// made by several tills while still supporting offline work.
  Map<String, dynamic> _liveCloudSnapshot() =>
      CloudStateMerge.cloudProjection(_serializeState());

  Map<String, dynamic> _mergeLiveWithRemote({
    required CloudStoreState remote,
    required Map<String, dynamic> localCloud,
    required Map<String, dynamic>? baseline,
  }) {
    if (_forceLocalCloudAuthority || !remote.exists) return localCloud;
    if (baseline == null) {
      return CloudStateMerge.mergeInitial(remote.snapshot, localCloud);
    }
    return CloudStateMerge.apply(
      remote.snapshot,
      CloudStateMerge.diff(baseline, localCloud),
    );
  }

  Future<void> syncFromCloudAfterValidation() async {
    if (_cloudSyncBusy) return;
    final repository = SubscriptionRepository();
    if (!repository.isConfigured) return;
    _cloudSyncBusy = true;
    try {
      _saveDebounce?.cancel();
      await _save(scheduleCloud: false);
      // Cloud owner provisioning happens before this method. It is now safe to
      // migrate legacy local credentials before any snapshot can leave device.
      _migrateLocalCredentials();
      var mergeGen = _mutationGen;
      var localFull = _serializeState();
      var localCloud = CloudStateMerge.cloudProjection(localFull);
      final baseline = await _readCloudBaseline();

      CloudStoreState remote = await repository.pullStoreState();
      if (_mutationGen != mergeGen) {
        mergeGen = _mutationGen;
        localFull = _serializeState();
        localCloud = CloudStateMerge.cloudProjection(localFull);
      }
      Map<String, dynamic> merged = _mergeLiveWithRemote(
        remote: remote,
        localCloud: localCloud,
        baseline: baseline,
      );

      if (!remote.exists &&
          _localCorruptionDetected &&
          _operationalCount(localCloud) == 0 &&
          !_forceLocalCloudAuthority) {
        return;
      }

      // Optimistic concurrency. If another device wrote between our pull/push,
      // pull its revision and rebase the latest local delta before retrying.
      var synchronized = false;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (_mutationGen != mergeGen) {
          mergeGen = _mutationGen;
          localCloud = _liveCloudSnapshot();
          merged = _mergeLiveWithRemote(
            remote: remote,
            localCloud: localCloud,
            baseline: baseline,
          );
        }
        final needsPush = !CloudStateMerge.deepEqual(
          CloudStateMerge.cloudProjection(remote.snapshot),
          CloudStateMerge.cloudProjection(merged),
        );
        if (!remote.exists || needsPush) {
          final pushed = await repository.pushStoreState(
            CloudStateMerge.cloudProjection(merged),
            expectedRevision: remote.revision,
          );
          if (!pushed.saved) {
            remote = await repository.pullStoreState();
            localCloud = _liveCloudSnapshot();
            mergeGen = _mutationGen;
            merged = _mergeLiveWithRemote(
              remote: remote,
              localCloud: localCloud,
              baseline: baseline,
            );
            continue;
          }
          remote = CloudStoreState(
            exists: true,
            revision: pushed.revision,
            snapshot: CloudStateMerge.cloudProjection(merged),
          );
        } else {
          merged = CloudStateMerge.cloudProjection(remote.snapshot);
        }
        synchronized = true;
        break;
      }
      if (synchronized) _forceLocalCloudAuthority = false;
      // Never advance the local baseline if every optimistic write collided;
      // doing so could make an unsaved local mutation disappear on next sync.
      if (!synchronized) return;

      // A local add during the network wait must not be wiped by an older merge.
      if (_mutationGen != mergeGen) {
        await _persistMap(_serializeState(), scheduleCloud: false);
        return;
      }

      final localMeta = _captureLocalMeta();
      _applyingCloudState = true;
      _restore(CloudStateMerge.cloudProjection(merged));
      _restoreLocalMeta(localMeta);
      _ensureDerivedBaselines();
      _recomputeDerivedState();
      _localCorruptionDetected = false;
      localFull = _serializeState();
      localCloud = CloudStateMerge.cloudProjection(localFull);
      await _persistMap(localFull, scheduleCloud: false);
      await _writeCloudBaseline(localCloud);
      await _ensureSequenceCapacity(repository);
      notifyListeners();
    } catch (_) {
      // A successful local save remains usable offline. The next background
      // sync/heartbeat retries without discarding the local mutation.
    } finally {
      _applyingCloudState = false;
      _cloudSyncBusy = false;
    }
  }

  Future<Map<String, dynamic>?> _readCloudBaseline() async {
    final raw = LocalStateDatabase.instance.cloudBaselineRaw;
    if (raw == null || raw.isEmpty) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCloudBaseline(Map<String, dynamic> state) =>
      LocalStateDatabase.instance.writeCloudBaseline(jsonEncode(state));

  void _scheduleCloudPush() {
    if (_applyingCloudState) return;
    _cloudPushTimer?.cancel();
    _cloudPushTimer = Timer(
      const Duration(milliseconds: 900),
      syncFromCloudAfterValidation,
    );
  }

  ProductModel product(String id) =>
      products.firstWhere((item) => item.id == id);
  ProductModel? productOrNull(String id) {
    for (final item in products) {
      if (item.id == id) return item;
    }
    return null;
  }

  ProductModel? productByBarcodeOrSku(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return null;
    final skuKey = code.toLowerCase();
    for (final item in products) {
      if (!item.active) continue;
      if (item.barcode.trim() == code ||
          item.sku.trim().toLowerCase() == skuKey) {
        return item;
      }
    }
    return null;
  }

  /// SKU is free-form and is stored exactly as the user typed it.
  /// Uniqueness remains case-insensitive so lookup stays unambiguous.
  bool skuExists(String raw, {String? exceptProductId}) {
    final key = raw.trim().toLowerCase();
    if (key.isEmpty) return false;
    return products.any((item) =>
        item.id != exceptProductId && item.sku.trim().toLowerCase() == key);
  }

  EmployeeRecord? employeeOrNull(String id) {
    for (final item in employees) {
      if (item.id == id) return item;
    }
    return null;
  }

  EmployeeRecord? employeeByLoginId(String loginId) {
    final normalized = loginId.trim().toUpperCase();
    EmployeeRecord? inactiveMatch;
    for (final item in employees.reversed) {
      if (item.loginId.trim().toUpperCase() != normalized) continue;
      if (item.active) return item;
      inactiveMatch ??= item;
    }
    return inactiveMatch;
  }

  EmployeeRecord? activeEmployeeUsingLoginId(String loginId, {String? exceptEmployeeId}) {
    final normalized = loginId.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    for (final item in employees.reversed) {
      if (!item.active || item.id == exceptEmployeeId) continue;
      if (item.loginId.trim().toUpperCase() == normalized) return item;
    }
    return null;
  }

  AdminAccountRecord? adminAccountByEmail(String email) {
    final normalized = email.trim().toLowerCase();
    for (final item in adminAccounts) {
      if (item.email.trim().toLowerCase() == normalized) return item;
    }
    return null;
  }

  AdminAccountRecord? adminAccountByRole(String roleKey) {
    for (final item in adminAccounts) {
      if (item.roleKey == roleKey) return item;
    }
    return null;
  }

  bool verifyManagerPassword(String password) {
    final manager = adminAccountByRole('manager');
    return manager != null &&
        manager.active &&
        password.trim().isNotEmpty &&
        CredentialHash.verify(password.trim(), manager.password);
  }

  bool verifyOwnerPassword(String password) {
    final owner = adminAccountByRole('owner');
    return owner != null &&
        owner.active &&
        password.trim().isNotEmpty &&
        CredentialHash.verify(password.trim(), owner.password);
  }

  bool _isCurrentFinancialDate(DateTime date) {
    final resetAt = financialResetAt;
    return resetAt == null || !date.isBefore(resetAt);
  }

  bool isInCurrentFinancialPeriod(DateTime date) =>
      _isCurrentFinancialDate(date);

  DateTime? _effectiveFinancialStart(DateTime? requestedStart) {
    final resetAt = financialResetAt;
    if (resetAt == null) return requestedStart;
    if (requestedStart == null || resetAt.isAfter(requestedStart)) return resetAt;
    return requestedStart;
  }

  Iterable<JournalEntry> get currentFinancialJournalEntries =>
      journalEntries.where((entry) => _isCurrentFinancialDate(entry.createdAt));

  CustomerRecord? customerOrNull(String id) {
    for (final item in customers) {
      if (item.id == id) return item;
    }
    return null;
  }

  CustomerRecord? addCustomer({
    required String name,
    required String phone,
    String address = '',
    bool creditAllowed = false,
    double creditLimit = 0,
    double openingBalance = 0,
    String note = '',
    required String actorName,
    required String actorRole,
  }) {
    if (actorRole != 'owner' && actorRole != 'manager') return null;
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    final safeLimit = creditLimit < 0 ? 0.0 : creditLimit;
    final safeOpening = openingBalance < 0 ? 0.0 : openingBalance;
    if (cleanName.isEmpty || cleanPhone.isEmpty) return null;
    if (customers.any((c) => c.phone.trim() == cleanPhone)) return null;
    if (creditAllowed && safeLimit > 0 && safeOpening > safeLimit) return null;

    final account =
        'C-${_nextSequenceValue('customer').toString().padLeft(4, '0')}';
    final customer = CustomerRecord(
      id: _id('cus'),
      accountNumber: account,
      name: cleanName,
      phone: cleanPhone,
      address: address.trim(),
      balance: safeOpening,
      creditAllowed: creditAllowed,
      creditLimit: creditAllowed ? safeLimit : 0,
      note: note.trim(),
    );
    customers.add(customer);
    if (safeOpening > 0) {
      _postJournal(
        date: customer.createdAt,
        reference: 'OPEN-${customer.accountNumber}',
        description: 'Customer opening receivable ${customer.name}',
        sourceType: 'customer_opening_balance',
        sourceId: customer.id,
        lines: [
          JournalLine(
            accountCode: '1100',
            accountName: accountName('1100'),
            debit: safeOpening,
          ),
          JournalLine(
            accountCode: '3000',
            accountName: accountName('3000'),
            credit: safeOpening,
          ),
        ],
      );
    }
    _recordAudit(
      actorName: actorName,
      actorRole: actorRole,
      action: 'customer_created',
      targetType: 'customer',
      targetId: customer.id,
      description:
          'Customer ${customer.accountNumber} created. Credit: ${customer.creditAllowed}, limit: ${customer.creditLimit.toStringAsFixed(2)}, opening balance: ${customer.balance.toStringAsFixed(2)}',
    );
    _changed();
    return customer;
  }

  bool updateCustomer({
    required String customerId,
    required String name,
    required String phone,
    String address = '',
    bool creditAllowed = false,
    double creditLimit = 0,
    String note = '',
    bool active = true,
    required String actorName,
    required String actorRole,
  }) {
    if (actorRole != 'owner' && actorRole != 'manager') return false;
    final customer = customerOrNull(customerId);
    if (customer == null) return false;
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    final safeLimit = creditLimit < 0 ? 0.0 : creditLimit;
    if (cleanName.isEmpty || cleanPhone.isEmpty) return false;
    if (customers
        .any((c) => c.id != customerId && c.phone.trim() == cleanPhone))
      return false;
    if (creditAllowed && safeLimit > 0 && customer.balance > safeLimit)
      return false;

    customer.name = cleanName;
    customer.phone = cleanPhone;
    customer.address = address.trim();
    customer.creditAllowed = creditAllowed;
    customer.creditLimit = creditAllowed ? safeLimit : 0;
    customer.note = note.trim();
    customer.active = active;
    _recordAudit(
      actorName: actorName,
      actorRole: actorRole,
      action: 'customer_updated',
      targetType: 'customer',
      targetId: customer.id,
      description:
          'Customer ${customer.accountNumber} updated. Active: ${customer.active}, credit: ${customer.creditAllowed}, limit: ${customer.creditLimit.toStringAsFixed(2)}',
    );
    _changed();
    return true;
  }

  String? validateCreditSale(String customerId, double newDueAmount) {
    final customer = customerOrNull(customerId);
    if (customer == null || !customer.active) return 'customer_not_found';
    if (!customer.creditAllowed) return 'credit_not_allowed';
    if (newDueAmount < 0) return 'invalid_due';
    if (customer.creditLimit > 0 &&
        customer.balance + newDueAmount > customer.creditLimit)
      return 'credit_limit_exceeded';
    return null;
  }

  SupplierRecord? supplierOrNull(String id) {
    for (final item in suppliers) {
      if (item.id == id) return item;
    }
    return null;
  }

  SupplierRecord? supplierByName(String name) {
    final q = name.trim().toLowerCase();
    for (final item in suppliers) {
      if (item.name.trim().toLowerCase() == q) return item;
    }
    return null;
  }

  SupplierRecord? addSupplier({
    required String name,
    String phone = '',
    String address = '',
    double openingBalance = 0,
    required String actorName,
    required String actorRole,
  }) {
    if (actorRole != 'owner' && actorRole != 'manager') return null;
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    final safeOpening = openingBalance < 0 ? 0.0 : openingBalance;
    if (cleanName.isEmpty) return null;
    if (suppliers.any(
      (s) => s.name.trim().toLowerCase() == cleanName.toLowerCase(),
    )) {
      return null;
    }
    if (cleanPhone.isNotEmpty &&
        suppliers.any((s) => s.phone.trim().isNotEmpty && s.phone.trim() == cleanPhone)) {
      return null;
    }

    final serial = _nextSequenceValue('supplier');
    final supplier = SupplierRecord(
      id: _id('sup'),
      accountNumber: 'S-${serial.toString().padLeft(4, '0')}',
      name: cleanName,
      phone: cleanPhone,
      address: address.trim(),
      openingBalance: safeOpening,
    );
    suppliers.add(supplier);

    if (safeOpening > 0) {
      _postJournal(
        date: DateTime.now(),
        reference: 'OPEN-${supplier.accountNumber}',
        description: 'Supplier opening payable ${supplier.name}',
        sourceType: 'supplier_opening_balance',
        sourceId: supplier.id,
        lines: [
          JournalLine(
            accountCode: '3000',
            accountName: accountName('3000'),
            debit: safeOpening,
          ),
          JournalLine(
            accountCode: '2000',
            accountName: accountName('2000'),
            credit: safeOpening,
          ),
        ],
      );
    }

    _recordAudit(
      actorName: actorName,
      actorRole: actorRole,
      action: 'supplier_created',
      targetType: 'supplier',
      targetId: supplier.id,
      description:
          'Supplier ${supplier.accountNumber} created. Opening balance: ${safeOpening.toStringAsFixed(2)}',
    );
    _changed();
    return supplier;
  }

  SupplierRecord ensureSupplier(String name) {
    final clean = name.trim().isEmpty ? 'Direct supplier' : name.trim();
    final existing = supplierByName(clean);
    if (existing != null) return existing;
    final serial = _nextSequenceValue('supplier');
    final supplier = SupplierRecord(
      id: _id('sup'),
      accountNumber: 'S-${serial.toString().padLeft(4, '0')}',
      name: clean,
    );
    suppliers.add(supplier);
    return supplier;
  }

  List<GlobalSearchHit> searchAll(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final hits = <GlobalSearchHit>[];
    bool has(String value) => value.toLowerCase().contains(q);

    for (final invoice in invoices) {
      if (has(invoice.number) ||
          has(invoice.customer) ||
          has(invoice.cashier) ||
          has(invoice.paymentMethod)) {
        hits.add(GlobalSearchHit(
            kind: 'invoice',
            id: invoice.id,
            title: '${invoice.number} • ${invoice.customer}',
            subtitle:
                '${invoice.total.toStringAsFixed(2)} ${settings.currency} • ${invoice.cashier}'));
      }
    }
    for (final customer in customers) {
      if (has(customer.name) ||
          has(customer.phone) ||
          has(customer.accountNumber) ||
          has(customer.note)) {
        hits.add(GlobalSearchHit(
            kind: 'customer',
            id: customer.id,
            title: '${customer.name} • ${customer.accountNumber}',
            subtitle:
                '${customer.phone} • ${customer.balance.toStringAsFixed(2)} ${settings.currency}'));
      }
    }
    for (final employee in employees) {
      if (has(employee.id) ||
          has(employee.loginId) ||
          has(employee.nameAr) ||
          has(employee.nameEn) ||
          has(employee.phone)) {
        hits.add(GlobalSearchHit(
            kind: 'employee',
            id: employee.id,
            title: '${employee.nameAr} • ${employee.id}',
            subtitle: '${employee.roleKey} • ${employee.phone}'));
      }
    }
    for (final task in tasks) {
      if (has(task.titleAr) ||
          has(task.titleEn) ||
          has(task.description) ||
          has(task.assignedEmployeeId) ||
          has(task.status)) {
        hits.add(GlobalSearchHit(
            kind: 'task',
            id: task.id,
            title: task.titleAr,
            subtitle: '${task.assignedEmployeeId} • ${task.status}'));
      }
    }
    for (final record in attendance) {
      if (has(record.employeeName) || has(record.employeeId)) {
        hits.add(GlobalSearchHit(
            kind: 'attendance',
            id: record.id,
            title: '${record.employeeName} • ${record.employeeId}',
            subtitle:
                '${record.clockIn.toIso8601String()} • ${record.clockOut?.toIso8601String() ?? 'open'}'));
      }
    }
    for (final product in products) {
      if (has(product.nameAr) ||
          has(product.nameEn) ||
          has(product.sku) ||
          has(product.barcode) ||
          has(product.categoryAr) ||
          has(product.categoryEn)) {
        hits.add(GlobalSearchHit(
            kind: 'product',
            id: product.id,
            title: '${product.nameAr} • ${product.sku}',
            subtitle:
                'Stock ${product.stock} • ${product.price.toStringAsFixed(2)} ${settings.currency}'));
      }
    }
    for (final supplier in suppliers) {
      if (has(supplier.name) ||
          has(supplier.accountNumber) ||
          has(supplier.phone) ||
          has(supplier.address)) {
        hits.add(GlobalSearchHit(
            kind: 'supplier',
            id: supplier.id,
            title: '${supplier.name} • ${supplier.accountNumber}',
            subtitle: supplier.phone));
      }
    }
    for (final purchase in purchases) {
      if (has(purchase.number) ||
          has(purchase.vendorInvoiceNumber) ||
          has(purchase.supplier) ||
          has(purchase.employeeName) ||
          purchase.lines.any((line) => has(line.itemName))) {
        hits.add(GlobalSearchHit(
            kind: 'purchase',
            id: purchase.id,
            title: '${purchase.number} • ${purchase.supplier}',
            subtitle:
                '${purchase.total.toStringAsFixed(2)} ${settings.currency} • ${purchase.employeeName}'));
      }
    }
    for (final record in returns) {
      if (has(record.invoiceNumber) ||
          has(record.reason) ||
          has(record.processedBy) ||
          record.lines.any((line) => has(line.nameAr) || has(line.nameEn))) {
        hits.add(GlobalSearchHit(
            kind: 'return',
            id: record.id,
            title:
                '${record.invoiceNumber} • ${record.total.toStringAsFixed(2)} ${settings.currency}',
            subtitle: '${record.processedBy} • ${record.reason}'));
      }
    }
    for (final movement in stockMovements) {
      if (has(movement.itemName) ||
          has(movement.reference) ||
          has(movement.employeeName) ||
          has(movement.note) ||
          has(movement.type)) {
        hits.add(GlobalSearchHit(
            kind: 'stock_movement',
            id: movement.id,
            title: '${movement.itemName} • ${movement.type}',
            subtitle:
                '${movement.quantity} • ${movement.reference} • ${movement.employeeName}'));
      }
    }
    for (final message in messages) {
      if (has(message.body) ||
          has(message.senderName) ||
          has(message.recipientType)) {
        hits.add(GlobalSearchHit(
            kind: 'message',
            id: message.id,
            title: message.senderName,
            subtitle: message.body));
      }
    }
    for (final request in restockRequests) {
      if (has(request.number) ||
          has(request.createdByName) ||
          has(request.note) ||
          request.lines.any((line) => has(line.itemName))) {
        hits.add(GlobalSearchHit(
            kind: 'restock',
            id: request.id,
            title: request.number,
            subtitle: request.lines.map((e) => e.itemName).take(3).join('، ')));
      }
    }
    for (final held in heldSales) {
      if (has(held.label) ||
          has(held.cashierName) ||
          has(held.cashierId) ||
          has(held.customer)) {
        hits.add(GlobalSearchHit(
            kind: 'held_sale',
            id: held.id,
            title: '${held.label} • ${held.customer}',
            subtitle: '${held.cashierName} • ${held.itemCount} items'));
      }
    }
    for (final payment in customerPayments) {
      if (has(payment.customerName) ||
          has(payment.employeeName) ||
          has(payment.note) ||
          has(payment.method)) {
        hits.add(GlobalSearchHit(
            kind: 'customer_payment',
            id: payment.id,
            title: payment.customerName,
            subtitle:
                '${payment.amount.toStringAsFixed(2)} ${settings.currency} • ${payment.method}'));
      }
    }
    for (final payment in supplierPayments) {
      if (has(payment.supplierName) ||
          has(payment.employeeName) ||
          has(payment.note) ||
          has(payment.purchaseNumber) ||
          has(payment.method)) {
        hits.add(GlobalSearchHit(
            kind: 'supplier_payment',
            id: payment.id,
            title: payment.supplierName,
            subtitle:
                '${payment.amount.toStringAsFixed(2)} ${settings.currency} • ${payment.purchaseNumber}'));
      }
    }
    for (final expense in expenses) {
      if (has(expense.category) ||
          has(expense.description) ||
          has(expense.employeeName) ||
          has(expense.paymentMethod)) {
        hits.add(GlobalSearchHit(
            kind: 'expense',
            id: expense.id,
            title: expense.description,
            subtitle:
                '${expense.amount.toStringAsFixed(2)} ${settings.currency} • ${expense.category}'));
      }
    }
    for (final note in productNotes.where((n) => n.active)) {
      final productItem = productOrNull(note.productId);
      if (has(note.text) ||
          has(note.createdBy) ||
          (productItem != null &&
              (has(productItem.nameAr) || has(productItem.sku)))) {
        hits.add(GlobalSearchHit(
            kind: 'product_note',
            id: note.id,
            title: productItem?.nameAr ?? note.productId,
            subtitle: note.text));
      }
    }
    return hits;
  }

  List<ProductModel> get lowStock => products
      .where((item) => item.active && item.stock <= item.minStock)
      .toList();
  List<TaskRecord> get openTasks =>
      tasks.where((item) => item.status != 'completed').toList();
  List<TaskRecord> get overdueTasks =>
      tasks.where((item) => item.isOverdue).toList();
  List<EmployeeRecord> get activeEmployees =>
      employees.where((item) => item.active).toList();
  List<AttendanceRecord> get openAttendance {
    _autoCloseExpiredAttendance();
    return attendance.where((item) => item.clockOut == null).toList();
  }

  double get inventoryValue => products
      .where((p) => p.active)
      .fold<double>(0, (sum, p) => sum + p.cost * p.stock);
  double get grossSales => invoices
      .where((i) => !i.voided && _isCurrentFinancialDate(i.createdAt))
      .fold<double>(0, (sum, i) => sum + i.total);
  double get returnsValue => returns
      .where((r) => _isCurrentFinancialDate(r.createdAt))
      .fold<double>(0, (sum, r) => sum + r.total);
  double get totalSales => grossSales - returnsValue;
  double get purchaseReturnsValue => purchaseReturns
      .where((r) => _isCurrentFinancialDate(r.createdAt))
      .fold<double>(0, (sum, r) => sum + r.agreedAmount);
  double get supplierReturnReceivables => purchaseReturns
      .where((r) => _isCurrentFinancialDate(r.createdAt))
      .fold<double>(0, (sum, r) => sum + r.remainingRefund);
  double get purchasesValue => purchases
      .where((p) => _isCurrentFinancialDate(p.createdAt))
      .fold<double>(0, (sum, p) => sum + p.total);
  double get grossCostOfSales => invoices
      .where((i) => !i.voided && _isCurrentFinancialDate(i.createdAt))
      .fold<double>(
      0,
      (sum, invoice) =>
          sum +
          invoice.lines.fold<double>(
              0, (inner, line) => inner + line.unitCost * line.quantity));
  double get returnedCost => returns
      .where((r) => _isCurrentFinancialDate(r.createdAt))
      .fold<double>(
      0,
      (sum, record) =>
          sum +
          record.lines.fold<double>(
              0, (inner, line) => inner + line.unitCost * line.quantity));
  double get estimatedCostOfSales =>
      (grossCostOfSales - returnedCost).clamp(0, double.infinity).toDouble();
  double get assetPurchaseValue => assets
      .where((a) => a.active)
      .fold<double>(0, (sum, a) => sum + a.purchasePrice);
  double get assetBookValue => assets
      .where((a) => a.active)
      .fold<double>(0, (sum, a) => sum + a.bookValueAt(DateTime.now()));

  double get totalReceivables => customers.fold<double>(
      0, (sum, c) => sum + (c.balance > 0 ? c.balance : 0));
  double get totalCustomerPayments => customerPayments
      .where((p) => _isCurrentFinancialDate(p.createdAt))
      .fold<double>(0, (sum, p) => sum + p.amount);
  double get collectedAtSale => invoices
      .where((i) => !i.voided && _isCurrentFinancialDate(i.createdAt))
      .fold<double>(0, (sum, i) => sum + i.receivedAtSale);
  double get totalCollectedSales => collectedAtSale + totalCustomerPayments;
  double get totalExpenses => expenses
      .where((e) => _isCurrentFinancialDate(e.createdAt))
      .fold<double>(0, (sum, e) => sum + e.amount);
  double get currentDepreciationExpense {
    final now = DateTime.now();
    final yearStart = DateTime(now.year, 1, 1);
    final start = _effectiveFinancialStart(yearStart) ?? yearStart;
    final end = now;
    return assets.fold<double>(
        0, (sum, a) => sum + a.depreciationForPeriod(start, end));
  }

  double get grossProfit => financialSummary().grossProfit;
  double get netProfit => financialSummary().netProfit;
  double get totalSupplierPaid => (purchases
          .where((p) => _isCurrentFinancialDate(p.createdAt))
          .fold<double>(0, (sum, p) => sum + p.amountPaid) +
      supplierPayments
          .where((p) => _isCurrentFinancialDate(p.createdAt))
          .fold<double>(0, (sum, p) => sum + p.amount) -
      purchaseReturns
          .where((r) => _isCurrentFinancialDate(r.createdAt))
          .fold<double>(0, (sum, r) => sum + r.cashRefund))
      .clamp(0, double.infinity)
      .toDouble();
  double get totalPayables {
    var total = 0.0;
    for (final supplier in suppliers) {
      final balance = supplierBalance(supplier.id);
      if (balance > 0) total += balance;
    }
    total += purchases
        .where((p) => p.supplierId.isEmpty && _isCurrentFinancialDate(p.createdAt))
        .fold<double>(0, (sum, p) => sum + purchaseOutstanding(p));
    return total;
  }

  double get cashBalance => accountBalance('1000');
  double get bankBalance => accountBalance('1010');
  double get salesTaxPayable => accountBalance('2100') * -1;
  double get netOperationalCashFlow => cashBalance;

  bool _usesCashAccount(String method) =>
      method == 'Cash' || method == 'Debt';

  double _cashReceivedFromInvoice(SaleInvoice invoice) =>
      _usesCashAccount(invoice.paymentMethod) ? invoice.receivedAtSale : 0;
  double _cashRefund(ReturnRecord record) =>
      record.refundMethod == 'Cash' ? record.refundAmount : 0;

  double salaryCashPaidForExpense(ExpenseRecord expense) {
    if (expense.sourceType != 'salary') return 0;
    var cash = 0.0;
    for (final entry in journalEntries) {
      if (entry.sourceType != 'salary' || entry.sourceId != expense.id) continue;
      for (final line in entry.lines) {
        if ((line.accountCode == '1000' || line.accountCode == '1010') &&
            line.credit > 0) {
          cash += line.credit;
        }
      }
    }
    return cash;
  }

  double cashResultForPeriod({DateTime? start, DateTime? end}) {
    final effectiveStart = _effectiveFinancialStart(start);
    bool inside(DateTime date) {
      if (effectiveStart != null && date.isBefore(effectiveStart)) return false;
      if (end != null && !date.isBefore(end!)) return false;
      return true;
    }

    final inflows = invoices
            .where((i) => !i.voided && inside(i.createdAt))
            .fold<double>(0, (sum, i) => sum + i.receivedAtSale) +
        customerPayments
            .where((p) => inside(p.createdAt))
            .fold<double>(0, (sum, p) => sum + p.amount) +
        purchaseReturns
            .where((r) => inside(r.createdAt))
            .fold<double>(0, (sum, r) => sum + r.cashRefund);

    final operatingExpenses = expenses
        .where((e) => e.sourceType != 'salary' && inside(e.createdAt))
        .fold<double>(0, (sum, e) => sum + e.amount);
    final salaryCash = expenses
        .where((e) => e.sourceType == 'salary' && inside(e.createdAt))
        .fold<double>(0, (sum, e) => sum + salaryCashPaidForExpense(e));
    final purchasesPaid = purchases
        .where((p) => inside(p.createdAt))
        .fold<double>(0, (sum, p) => sum + p.amountPaid);
    final supplierPaid = supplierPayments
        .where((p) => inside(p.createdAt))
        .fold<double>(0, (sum, p) => sum + p.amount);
    final refunds = returns
        .where((r) => inside(r.createdAt))
        .fold<double>(0, (sum, r) => sum + r.refundAmount);
    final assetOut = assets
        .where((a) => inside(a.purchaseDate))
        .fold<double>(0, (sum, a) => sum + a.purchasePrice);
    final advancesOut = employeeAdvances
        .where((a) => inside(a.createdAt))
        .fold<double>(0, (sum, a) => sum + a.amount);
    return inflows -
        (operatingExpenses +
            salaryCash +
            purchasesPaid +
            supplierPaid +
            refunds +
            assetOut +
            advancesOut);
  }

  double depreciationForPeriod(DateTime start, DateTime endExclusive) =>
      assets.fold<double>(
          0, (sum, a) => sum + a.depreciationForPeriod(start, endExclusive));

  FinancialPeriodSummary financialSummary({DateTime? start, DateTime? end}) {
    final effectiveStart = _effectiveFinancialStart(start);
    bool inRange(DateTime date) {
      if (effectiveStart != null && date.isBefore(effectiveStart)) return false;
      if (end != null && !date.isBefore(end!)) return false;
      return true;
    }

    final periodInvoices =
        invoices.where((i) => !i.voided && inRange(i.createdAt)).toList();
    final periodReturns = returns.where((r) => inRange(r.createdAt)).toList();
    final periodPurchases =
        purchases.where((p) => inRange(p.createdAt)).toList();
    final periodPurchaseReturns =
        purchaseReturns.where((r) => inRange(r.createdAt)).toList();
    final periodExpenses = expenses.where((e) => inRange(e.createdAt)).toList();
    final periodCustomerPayments =
        customerPayments.where((p) => inRange(p.createdAt)).toList();
    final periodSupplierPayments =
        supplierPayments.where((p) => inRange(p.createdAt)).toList();

    final salesSubtotal =
        periodInvoices.fold<double>(0, (sum, i) => sum + i.subtotal);
    final returnSubtotal =
        periodReturns.fold<double>(0, (sum, r) => sum + r.subtotal);
    final netSalesValue = salesSubtotal - returnSubtotal;
    final salesTaxValue =
        periodInvoices.fold<double>(0, (sum, i) => sum + i.taxAmount) -
            periodReturns.fold<double>(0, (sum, r) => sum + r.taxAmount);
    final cost = (periodInvoices.fold<double>(
                0,
                (sum, invoice) =>
                    sum +
                    invoice.lines.fold<double>(
                        0,
                        (inner, line) =>
                            inner + line.unitCost * line.quantity)) -
            periodReturns.fold<double>(
                0,
                (sum, record) =>
                    sum +
                    record.lines.fold<double>(
                        0,
                        (inner, line) =>
                            inner + line.unitCost * line.quantity)))
        .clamp(0, double.infinity)
        .toDouble();
    final expenseValue =
        periodExpenses.fold<double>(0, (sum, e) => sum + e.amount);
    final periodStart = effectiveStart ?? DateTime(2000);
    final periodNow = DateTime.now();
    final requestedEnd = end ?? periodNow;
    final periodEnd = requestedEnd.isAfter(periodNow) ? periodNow : requestedEnd;
    final depreciationValue = depreciationForPeriod(periodStart, periodEnd);
    final collectedValue =
        periodInvoices.fold<double>(0, (sum, i) => sum + i.receivedAtSale) +
            periodCustomerPayments.fold<double>(0, (sum, p) => sum + p.amount);
    final purchaseValue =
        periodPurchases.fold<double>(0, (sum, p) => sum + p.total);
    final supplierPaidValue = (periodPurchases.fold<double>(
                0, (sum, p) => sum + p.amountPaid) +
            periodSupplierPayments.fold<double>(0, (sum, p) => sum + p.amount) -
            periodPurchaseReturns.fold<double>(
                0, (sum, r) => sum + r.cashRefund))
        .clamp(0, double.infinity)
        .toDouble();
    final grossProfitValue = netSalesValue - cost;
    final netProfitValue = grossProfitValue - expenseValue - depreciationValue;
    final cashReceipts = periodInvoices.fold<double>(
            0, (sum, i) => sum + _cashReceivedFromInvoice(i)) +
        periodCustomerPayments
            .where((p) => p.method == 'Cash')
            .fold<double>(0, (sum, p) => sum + p.amount);
    final cashRefunds =
        periodReturns.fold<double>(0, (sum, r) => sum + _cashRefund(r));
    final cashSupplier = (periodPurchases
            .where((p) => _usesCashAccount(p.paymentMethod))
            .fold<double>(0, (sum, p) => sum + p.amountPaid) +
        periodSupplierPayments
            .where((p) => p.method == 'Cash')
            .fold<double>(0, (sum, p) => sum + p.amount) -
        periodPurchaseReturns.fold<double>(
            0, (sum, r) => sum + r.cashRefund))
        .clamp(0, double.infinity)
        .toDouble();
    final cashExpenses = periodExpenses
        .where((e) => e.paymentMethod == 'Cash')
        .fold<double>(0, (sum, e) => sum + e.amount);
    final cashFlowValue =
        cashReceipts - cashRefunds - cashSupplier - cashExpenses;

    return FinancialPeriodSummary(
        netSales: netSalesValue,
        collected: collectedValue,
        purchases: purchaseValue,
        purchaseReturns: periodPurchaseReturns.fold<double>(
            0, (sum, r) => sum + r.agreedAmount),
        supplierReturnReceivables: periodPurchaseReturns.fold<double>(
            0, (sum, r) => sum + r.remainingRefund),
        supplierPaid: supplierPaidValue,
        costOfSales: cost,
        expenses: expenseValue,
        depreciation: depreciationValue,
        salesTax: salesTaxValue,
        grossProfit: grossProfitValue,
        netProfit: netProfitValue,
        cashFlow: cashFlowValue);
  }

  double purchaseOutstanding(PurchaseReceipt purchase) {
    final laterPayments = supplierPayments.fold<double>(
        0, (sum, p) => sum + p.allocatedTo(purchase.id));
    final returnCredits = purchaseReturns
        .where((r) => r.purchaseId == purchase.id)
        .fold<double>(0, (sum, r) => sum + r.payableReduction);
    return (purchase.total - purchase.amountPaid - laterPayments - returnCredits)
        .clamp(0, purchase.total)
        .toDouble();
  }

  double supplierBalance(String supplierId) {
    final supplier = supplierOrNull(supplierId);
    if (supplier == null) return 0;
    final purchaseDebt = purchases
        .where((p) =>
            p.supplierId == supplierId && _isCurrentFinancialDate(p.createdAt))
        .fold<double>(0, (sum, p) => sum + (p.total - p.amountPaid));
    final payments = supplierPayments
        .where((p) =>
            p.supplierId == supplierId && _isCurrentFinancialDate(p.createdAt))
        .fold<double>(0, (sum, p) => sum + p.amount);
    final purchaseReturnCredits = purchaseReturns
        .where((r) =>
            r.supplierId == supplierId && _isCurrentFinancialDate(r.createdAt))
        .fold<double>(0, (sum, r) => sum + r.payableReduction);
    return (supplier.openingBalance + purchaseDebt - payments - purchaseReturnCredits)
        .clamp(0, double.infinity)
        .toDouble();
  }

  double invoiceOutstanding(String invoiceId) {
    final invoice = invoices.firstWhere((i) => i.id == invoiceId);
    final payments = customerPayments.fold<double>(
        0, (sum, p) => sum + p.allocatedTo(invoiceId));
    final returnCredits = returns
        .where((r) => r.invoiceId == invoiceId)
        .fold<double>(0, (sum, r) => sum + r.receivableReduction);
    return (invoice.dueAmount - payments - returnCredits)
        .clamp(0, invoice.total)
        .toDouble();
  }

  static const Map<String, String> _accountNames = {
    '1000': 'Cash',
    '1010': 'Bank / Card',
    '1100': 'Accounts Receivable',
    '1110': 'Supplier Return Receivable',
    '1150': 'Employee Advances',
    '1200': 'Inventory',
    '1500': 'Fixed Assets',
    '1590': 'Accumulated Depreciation',
    '2000': 'Accounts Payable',
    '2100': 'Sales Tax Payable',
    '3000': 'Owner Equity',
    '4000': 'Sales Revenue',
    '4010': 'Sales Returns',
    '5000': 'Cost of Goods Sold',
    '6000': 'Operating Expenses',
    '6020': 'Payroll Expense',
    '6050': 'Inventory Shrinkage',
    '4050': 'Inventory Adjustment Gain',
    '6100': 'Depreciation Expense',
  };

  String accountName(String code) => _accountNames[code] ?? code;
  double accountBalance(String code) {
    double debit = 0, credit = 0;
    for (final entry in currentFinancialJournalEntries) {
      for (final line in entry.lines.where((l) => l.accountCode == code)) {
        debit += line.debit;
        credit += line.credit;
      }
    }
    return debit - credit;
  }

  JournalEntry _postJournal(
      {required DateTime date,
      required String reference,
      required String description,
      required String sourceType,
      required String sourceId,
      required List<JournalLine> lines}) {
    final debit = lines.fold<double>(0, (s, l) => s + l.debit);
    final credit = lines.fold<double>(0, (s, l) => s + l.credit);
    if ((debit - credit).abs() >= 0.005)
      throw StateError('Unbalanced journal entry: $reference');
    final entry = JournalEntry(
        id: _id('je'),
        number: 'JE-${_nextSequenceValue('journal').toString().padLeft(6, '0')}',
        createdAt: date,
        reference: reference,
        description: description,
        sourceType: sourceType,
        sourceId: sourceId,
        lines: lines.where((l) => l.debit > 0 || l.credit > 0).toList());
    journalEntries.insert(0, entry);
    return entry;
  }

  AccountingSnapshot accountingSnapshot() {
    final cash = accountBalance('1000');
    final bank = accountBalance('1010');
    final ar = totalReceivables +
        accountBalance('1110').clamp(0, double.infinity).toDouble();
    final inv = inventoryValue;
    final fixed = assetBookValue;
    final ap = totalPayables;
    final tax = salesTaxPayable.clamp(0, double.infinity).toDouble();
    final assetsTotal = cash + bank + ar + inv + fixed;
    final equity = assetsTotal - ap - tax;
    return AccountingSnapshot(
        cash: cash,
        bank: bank,
        receivables: ar,
        inventory: inv,
        fixedAssetsNet: fixed,
        payables: ap,
        salesTaxPayable: tax,
        equity: equity);
  }

  Map<String, double> get trialBalanceDebits {
    final result = <String, double>{};
    for (final entry in currentFinancialJournalEntries) {
      for (final line in entry.lines) {
        result.update(line.accountCode, (v) => v + line.debit,
            ifAbsent: () => line.debit);
      }
    }
    return result;
  }

  Map<String, double> get trialBalanceCredits {
    final result = <String, double>{};
    for (final entry in currentFinancialJournalEntries) {
      for (final line in entry.lines) {
        result.update(line.accountCode, (v) => v + line.credit,
            ifAbsent: () => line.credit);
      }
    }
    return result;
  }

  bool get journalIsBalanced {
    if (!currentFinancialJournalEntries.every((e) => e.balanced)) return false;
    final d = trialBalanceDebits.values.fold<double>(0, (a, b) => a + b);
    final c = trialBalanceCredits.values.fold<double>(0, (a, b) => a + b);
    return (d - c).abs() < 0.005;
  }

  int lateMinutes(AttendanceRecord record) {
    final employee = employeeOrNull(record.employeeId);
    final startMinutes = record.scheduledStartMinutes >= 0
        ? record.scheduledStartMinutes
        : employee?.shiftStartMinutes;
    if (startMinutes == null) return 0;
    final scheduled = DateTime(record.clockIn.year, record.clockIn.month, record.clockIn.day)
        .add(Duration(minutes: startMinutes));
    return record.clockIn.isAfter(scheduled)
        ? record.clockIn.difference(scheduled).inMinutes
        : 0;
  }

  DateTime? scheduledStartForAttendance(AttendanceRecord record) {
    final employee = employeeOrNull(record.employeeId);
    final minutes = record.scheduledStartMinutes >= 0 ? record.scheduledStartMinutes : employee?.shiftStartMinutes;
    if (minutes == null) return null;
    return DateTime(record.clockIn.year, record.clockIn.month, record.clockIn.day).add(Duration(minutes: minutes));
  }

  DateTime? scheduledEndForAttendance(AttendanceRecord record) {
    final employee = employeeOrNull(record.employeeId);
    final startMinutes = record.scheduledStartMinutes >= 0 ? record.scheduledStartMinutes : employee?.shiftStartMinutes;
    final endMinutes = record.scheduledEndMinutes >= 0 ? record.scheduledEndMinutes : employee?.shiftEndMinutes;
    if (startMinutes == null || endMinutes == null) return null;
    var end = DateTime(record.clockIn.year, record.clockIn.month, record.clockIn.day).add(Duration(minutes: endMinutes));
    if (endMinutes <= startMinutes) end = end.add(const Duration(days: 1));
    return end;
  }

  Duration totalAttendanceFor(String employeeId) {
    return attendance
        .where((a) => a.employeeId == employeeId)
        .fold<Duration>(Duration.zero, (sum, item) => sum + item.duration);
  }

  SaleInvoice completeSale({
    required Map<String, int> cart,
    required String cashier,
    required String paymentMethod,
    String cashierId = '',
    String customer = 'Walk-in',
    String customerId = '',
    double? paidAmount,
    String invoiceTitle = '',
  }) {
    if (cart.isEmpty) throw StateError('Cart is empty');
    final previewLines = <InvoiceLine>[];
    for (final entry in cart.entries) {
      final p = productOrNull(entry.key);
      if (p == null || !p.active)
        throw StateError('Product not found: ${entry.key}');
      if (entry.value <= 0) continue;
      if (entry.value > p.stock)
        throw StateError('Insufficient stock: ${p.nameAr}');
      previewLines.add(InvoiceLine(
          productId: p.id,
          nameAr: p.nameAr,
          nameEn: p.nameEn,
          quantity: entry.value,
          unitPrice: p.price,
          unitCost: p.cost));
    }
    if (previewLines.isEmpty) throw StateError('Cart has no valid quantity');
    final subtotal = previewLines.fold<double>(0, (sum, l) => sum + l.total);
    final taxPercent = settings.taxPercent.clamp(0, 100).toDouble();
    final tax = subtotal * taxPercent / 100;
    final total = subtotal + tax;
    final normalizedPaid = paymentMethod == 'Debt'
        ? (paidAmount ?? 0).clamp(0, total).toDouble()
        : total;
    final due = total - normalizedPaid;
    if (paymentMethod == 'Debt') {
      if (customerId.isEmpty)
        throw StateError('Credit sale requires a registered customer');
      final creditError = validateCreditSale(customerId, due);
      if (creditError != null) throw StateError(creditError);
    } else if (paidAmount != null && paidAmount! + 0.005 < total) {
      throw StateError('Non-credit sale cannot leave an unpaid balance');
    }

    final now = DateTime.now();
    final number = 'INV-${_nextSequenceValue('invoice')}';
    for (final line in previewLines) {
      final p = product(line.productId);
      p.stock -= line.quantity;
      stockMovements.insert(
          0,
          StockMovement(
              id: _id('mv'),
              productId: p.id,
              itemName: p.nameAr,
              type: 'sale',
              quantity: -line.quantity,
              note: 'POS sale',
              createdAt: now,
              employeeId: cashierId,
              employeeName: cashier,
              reference: number));
    }
    final invoice = SaleInvoice(
        id: _id('inv'),
        number: number,
        createdAt: now,
        cashier: cashier.isEmpty ? 'Cashier' : cashier,
        cashierId: cashierId,
        paymentMethod: paymentMethod,
        customer: customer,
        customerId: customerId,
        paidAmount: normalizedPaid,
        taxPercent: taxPercent,
        title: invoiceTitle.trim(),
        lines: previewLines);
    invoices.insert(0, invoice);
    if (due > 0 && customerId.isNotEmpty) {
      final customerRecord = customerOrNull(customerId);
      if (customerRecord != null) customerRecord.balance += due;
    }
    // A credit (Debt) sale may include an immediate down payment. The UI does
    // not ask for a second channel for that down payment, so it is treated as
    // cash. Card/Wallet/Bank/Transfer payments use the bank/card account.
    final paidAccount = _usesCashAccount(paymentMethod) ? '1000' : '1010';
    final cogs =
        previewLines.fold<double>(0, (sum, l) => sum + l.unitCost * l.quantity);
    _postJournal(
        date: now,
        reference: number,
        description: 'POS sale',
        sourceType: 'sale',
        sourceId: invoice.id,
        lines: [
          if (normalizedPaid > 0)
            JournalLine(
                accountCode: paidAccount,
                accountName: accountName(paidAccount),
                debit: normalizedPaid),
          if (due > 0)
            JournalLine(
                accountCode: '1100',
                accountName: accountName('1100'),
                debit: due),
          JournalLine(
              accountCode: '4000',
              accountName: accountName('4000'),
              credit: subtotal),
          if (tax > 0)
            JournalLine(
                accountCode: '2100',
                accountName: accountName('2100'),
                credit: tax),
          if (cogs > 0)
            JournalLine(
                accountCode: '5000',
                accountName: accountName('5000'),
                debit: cogs),
          if (cogs > 0)
            JournalLine(
                accountCode: '1200',
                accountName: accountName('1200'),
                credit: cogs),
        ]);
    _changed();
    return invoice;
  }

  bool voidInvoice(
      {required String invoiceId,
      required String actorName,
      required String actorRole,
      String reason = ''}) {
    if (actorRole != 'owner' && actorRole != 'manager') return false;
    SaleInvoice? invoice;
    for (final item in invoices) {
      if (item.id == invoiceId) {
        invoice = item;
        break;
      }
    }
    if (invoice == null || invoice.voided) return false;
    if (returns.any((r) => r.invoiceId == invoice!.id)) return false;
    if (customerPayments.any((p) => p.allocatedTo(invoice!.id) > 0.005))
      return false;
    for (final line in invoice.lines) {
      final productItem = productOrNull(line.productId);
      if (productItem != null) {
        productItem.stock += line.quantity;
        stockMovements.insert(
            0,
            StockMovement(
                id: _id('mv'),
                productId: productItem.id,
                itemName: productItem.nameAr,
                type: 'void',
                quantity: line.quantity,
                note: reason.trim().isEmpty
                    ? 'Invoice void ${invoice.number}'
                    : reason.trim(),
                createdAt: DateTime.now(),
                employeeName: actorName,
                reference: invoice.number));
      }
    }
    if (invoice.customerId.isNotEmpty && invoice.dueAmount > 0) {
      final customer = customerOrNull(invoice.customerId);
      if (customer != null)
        customer.balance = (customer.balance - invoice.dueAmount)
            .clamp(0, double.infinity)
            .toDouble();
    }
    invoice.voided = true;
    final originals = journalEntries
        .where((e) => e.sourceType == 'sale' && e.sourceId == invoice!.id)
        .toList();
    for (final entry in originals) {
      _postJournal(
          date: DateTime.now(),
          reference: 'VOID-${invoice.number}',
          description: 'Void ${invoice.number}: $reason',
          sourceType: 'sale_void',
          sourceId: invoice.id,
          lines: [
            for (final line in entry.lines)
              JournalLine(
                  accountCode: line.accountCode,
                  accountName: line.accountName,
                  debit: line.credit,
                  credit: line.debit)
          ]);
    }
    _recordAudit(
        actorName: actorName,
        actorRole: actorRole,
        action: 'invoice_voided',
        targetType: 'invoice',
        targetId: invoice.id,
        description: '${invoice.number} voided: $reason');
    _changed();
    return true;
  }

  HeldSale holdSale(
    Map<String, int> cart, {
    String cashierId = '',
    String cashierName = '',
    String customer = 'Walk-in',
  }) {
    final sale = HeldSale(
      id: _id('hold'),
      label: 'H-${heldSales.length + 1}',
      createdAt: DateTime.now(),
      lines: Map<String, int>.from(cart),
      cashierId: cashierId,
      cashierName: cashierName,
      customer: customer,
    );
    heldSales.insert(0, sale);
    _changed();
    return sale;
  }

  Map<String, int> takeHeldSale(String id) {
    final index = heldSales.indexWhere((item) => item.id == id);
    if (index == -1) return {};
    final sale = heldSales.removeAt(index);
    _changed();
    return Map<String, int>.from(sale.lines);
  }

  void deleteHeldSale(String id) {
    heldSales.removeWhere((item) => item.id == id);
    _changed();
  }

  int returnedQuantity(String invoiceId, String productId) {
    return returns.where((r) => r.invoiceId == invoiceId).fold<int>(0,
        (sum, r) {
      return sum +
          r.lines
              .where((line) => line.productId == productId)
              .fold<int>(0, (inner, line) => inner + line.quantity);
    });
  }

  int availableReturnQuantity(SaleInvoice invoice, InvoiceLine line) {
    return (line.quantity - returnedQuantity(invoice.id, line.productId))
        .clamp(0, line.quantity)
        .toInt();
  }

  ReturnRecord? returnSale({
    required SaleInvoice invoice,
    required Map<String, int> quantities,
    required String reason,
    required String refundMethod,
    String processedBy = '',
    String processedById = '',
  }) {
    final lines = <InvoiceLine>[];
    final now = DateTime.now();
    for (final original in invoice.lines) {
      final requested = quantities[original.productId] ?? 0;
      final max = availableReturnQuantity(invoice, original);
      final qty = requested.clamp(0, max).toInt();
      if (qty <= 0) continue;
      final p = product(original.productId);
      p.stock += qty;
      lines.add(InvoiceLine(
          productId: p.id,
          nameAr: original.nameAr,
          nameEn: original.nameEn,
          quantity: qty,
          unitPrice: original.unitPrice,
          unitCost: original.unitCost));
      stockMovements.insert(
          0,
          StockMovement(
              id: _id('mv'),
              productId: p.id,
              itemName: p.nameAr,
              type: 'return',
              quantity: qty,
              note: reason,
              createdAt: now,
              employeeId: processedById,
              employeeName: processedBy,
              reference: invoice.number));
    }
    if (lines.isEmpty) return null;
    final subtotal = lines.fold<double>(0, (sum, l) => sum + l.total);
    final taxAmount = subtotal * invoice.taxPercent / 100;
    final returnTotal = subtotal + taxAmount;
    final outstandingBefore =
        invoice.customerId.isEmpty ? 0.0 : invoiceOutstanding(invoice.id);
    final receivableReduction =
        returnTotal.clamp(0, outstandingBefore).toDouble();
    final refundAmount =
        (returnTotal - receivableReduction).clamp(0, returnTotal).toDouble();
    final record = ReturnRecord(
        id: _id('ret'),
        invoiceId: invoice.id,
        invoiceNumber: invoice.number,
        createdAt: now,
        reason: reason,
        refundMethod: refundMethod,
        lines: lines,
        processedBy: processedBy,
        processedById: processedById,
        taxAmount: taxAmount,
        receivableReduction: receivableReduction,
        refundAmount: refundAmount);
    returns.insert(0, record);
    if (invoice.customerId.isNotEmpty && receivableReduction > 0) {
      final customerRecord = customerOrNull(invoice.customerId);
      if (customerRecord != null)
        customerRecord.balance = (customerRecord.balance - receivableReduction)
            .clamp(0, double.infinity)
            .toDouble();
    }
    final refundAccount = refundMethod == 'Cash' ? '1000' : '1010';
    final returnedCogs =
        lines.fold<double>(0, (sum, l) => sum + l.unitCost * l.quantity);
    _postJournal(
        date: now,
        reference: 'RET-${record.id}',
        description: 'Return ${invoice.number}',
        sourceType: 'return',
        sourceId: record.id,
        lines: [
          JournalLine(
              accountCode: '4010',
              accountName: accountName('4010'),
              debit: subtotal),
          if (taxAmount > 0)
            JournalLine(
                accountCode: '2100',
                accountName: accountName('2100'),
                debit: taxAmount),
          if (receivableReduction > 0)
            JournalLine(
                accountCode: '1100',
                accountName: accountName('1100'),
                credit: receivableReduction),
          if (refundAmount > 0)
            JournalLine(
                accountCode: refundAccount,
                accountName: accountName(refundAccount),
                credit: refundAmount),
          if (returnedCogs > 0)
            JournalLine(
                accountCode: '1200',
                accountName: accountName('1200'),
                debit: returnedCogs),
          if (returnedCogs > 0)
            JournalLine(
                accountCode: '5000',
                accountName: accountName('5000'),
                credit: returnedCogs),
        ]);
    _changed();
    return record;
  }

  ProductModel createManualProduct({
    required String name,
    String sku = '',
    int openingStock = 0,
    double cost = 0,
    String barcode = '',
  }) {
    final requestedSku = sku.trim();
    if (requestedSku.isNotEmpty && skuExists(requestedSku)) {
      throw StateError('SKU already exists');
    }

    var serial = _nextSequenceValue('product');
    var finalSku = requestedSku;
    if (finalSku.isEmpty) {
      finalSku = 'NEW-$serial';
      while (skuExists(finalSku)) {
        serial = _nextSequenceValue('product');
        finalSku = 'NEW-$serial';
      }
    }

    final p = ProductModel(
      id: 'p-manual-$serial',
      nameAr: name,
      nameEn: name,
      sku: finalSku,
      barcode: barcode.trim(),
      categoryAr: 'غير مصنف',
      categoryEn: 'Uncategorized',
      price: 0,
      cost: cost,
      stock: openingStock,
      minStock: 0,
    );
    products.add(p);
    return p;
  }

  ProductModel? addManagedProduct({
    required String nameAr,
    required String nameEn,
    required String sku,
    String barcode = '',
    required String categoryAr,
    required String categoryEn,
    required double salePrice,
    required double cost,
    int openingStock = 0,
    int minStock = 0,
    String baseUnit = 'piece',
    String purchaseUnit = 'piece',
    int unitsPerPurchaseUnit = 1,
    double packageWeightKg = 0,
    required String actorName,
    required String actorRole,
  }) {
    if (actorRole != 'owner' && actorRole != 'manager') return null;
    final cleanNameAr = nameAr.trim();
    final cleanNameEn = nameEn.trim().isEmpty ? cleanNameAr : nameEn.trim();
    var cleanSku = sku.trim();
    final cleanBarcode = barcode.trim();
    if (cleanNameAr.isEmpty ||
        salePrice < 0 ||
        cost < 0 ||
        openingStock < 0 ||
        minStock < 0) return null;
    if (cleanSku.isEmpty) {
      final serial = _nextSequenceValue('product');
      cleanSku = 'NEW-$serial';
      while (skuExists(cleanSku)) {
        cleanSku = 'NEW-${_nextSequenceValue('product')}';
      }
    }
    if (skuExists(cleanSku)) return null;
    if (cleanBarcode.isNotEmpty &&
        products.any((p) => p.barcode == cleanBarcode)) return null;
    final serial = _nextSequenceValue('product');
    final p = ProductModel(
      id: 'p-managed-$serial',
      nameAr: cleanNameAr,
      nameEn: cleanNameEn,
      sku: cleanSku,
      barcode: cleanBarcode,
      categoryAr: categoryAr.trim().isEmpty ? 'غير مصنف' : categoryAr.trim(),
      categoryEn:
          categoryEn.trim().isEmpty ? 'Uncategorized' : categoryEn.trim(),
      price: salePrice,
      cost: cost,
      stock: openingStock,
      minStock: minStock,
      baseUnit: baseUnit,
      purchaseUnit: purchaseUnit,
      unitsPerPurchaseUnit:
          unitsPerPurchaseUnit <= 0 ? 1 : unitsPerPurchaseUnit,
      packageWeightKg: packageWeightKg < 0 ? 0 : packageWeightKg,
    );
    products.add(p);
    _recordAudit(
      actorName: actorName,
      actorRole: actorRole,
      action: 'product_created',
      targetType: 'product',
      targetId: p.id,
      description:
          'Product ${p.sku} created with sale price ${p.price.toStringAsFixed(2)} and cost ${p.cost.toStringAsFixed(2)}',
    );
    _changed();
    return p;
  }

  ProductModel? addInventoryPurchaseProduct({
    required String nameAr,
    required String nameEn,
    required String sku,
    String barcode = '',
    required String categoryAr,
    required String categoryEn,
    required double salePrice,
    required double cost,
    int minStock = 0,
    String baseUnit = 'piece',
    String purchaseUnit = 'piece',
    int unitsPerPurchaseUnit = 1,
    double packageWeightKg = 0,
    required String actorName,
    required String actorRole,
  }) {
    if (actorRole != 'inventory' &&
        actorRole != 'owner' &&
        actorRole != 'manager') return null;
    final cleanNameAr = nameAr.trim();
    final cleanNameEn = nameEn.trim().isEmpty ? cleanNameAr : nameEn.trim();
    final cleanSku = sku.trim();
    final cleanBarcode = barcode.trim();
    if (cleanNameAr.isEmpty ||
        cleanSku.isEmpty ||
        salePrice <= 0 ||
        cost < 0 ||
        minStock < 0 ||
        unitsPerPurchaseUnit <= 0 ||
        packageWeightKg < 0) return null;
    if (skuExists(cleanSku)) return null;
    if (cleanBarcode.isNotEmpty &&
        products.any((p) => p.barcode == cleanBarcode)) return null;

    final serial = _nextSequenceValue('product');
    final p = ProductModel(
      id: 'p-inventory-$serial',
      nameAr: cleanNameAr,
      nameEn: cleanNameEn,
      sku: cleanSku,
      barcode: cleanBarcode,
      categoryAr: categoryAr.trim().isEmpty ? 'غير مصنف' : categoryAr.trim(),
      categoryEn:
          categoryEn.trim().isEmpty ? 'Uncategorized' : categoryEn.trim(),
      price: salePrice,
      cost: cost,
      stock: 0,
      minStock: minStock,
      baseUnit: baseUnit,
      purchaseUnit: purchaseUnit,
      unitsPerPurchaseUnit: unitsPerPurchaseUnit,
      packageWeightKg: packageWeightKg,
    );
    products.add(p);
    _recordAudit(
      actorName: actorName,
      actorRole: actorRole,
      action: 'inventory_product_created',
      targetType: 'product',
      targetId: p.id,
      description:
          'Inventory purchase created product ${p.sku} with sale price ${p.price.toStringAsFixed(2)} and base cost ${p.cost.toStringAsFixed(2)}',
    );
    _changed();
    return p;
  }

  bool updateManagedProduct({
    required String productId,
    required String nameAr,
    required String nameEn,
    required String sku,
    String barcode = '',
    required String categoryAr,
    required String categoryEn,
    required double salePrice,
    required double cost,
    required int minStock,
    required String baseUnit,
    required String purchaseUnit,
    required int unitsPerPurchaseUnit,
    required double packageWeightKg,
    required bool active,
    required String actorName,
    required String actorRole,
  }) {
    if (actorRole != 'owner' && actorRole != 'manager') return false;
    final p = productOrNull(productId);
    if (p == null) return false;
    final cleanNameAr = nameAr.trim();
    final cleanNameEn = nameEn.trim().isEmpty ? cleanNameAr : nameEn.trim();
    var cleanSku = sku.trim();
    final cleanBarcode = barcode.trim();
    if (cleanNameAr.isEmpty ||
        salePrice < 0 ||
        cost < 0 ||
        minStock < 0 ||
        unitsPerPurchaseUnit <= 0 ||
        packageWeightKg < 0) return false;
    if (cleanSku.isEmpty) cleanSku = p.sku;
    if (skuExists(cleanSku, exceptProductId: p.id)) return false;
    if (cleanBarcode.isNotEmpty &&
        products.any((x) => x.id != p.id && x.barcode == cleanBarcode))
      return false;
    final oldPrice = p.price;
    final oldCost = p.cost;
    p.nameAr = cleanNameAr;
    p.nameEn = cleanNameEn;
    p.sku = cleanSku;
    p.barcode = cleanBarcode;
    p.categoryAr = categoryAr.trim().isEmpty ? 'غير مصنف' : categoryAr.trim();
    p.categoryEn =
        categoryEn.trim().isEmpty ? 'Uncategorized' : categoryEn.trim();
    p.price = salePrice;
    p.cost = cost;
    p.minStock = minStock;
    p.baseUnit = baseUnit;
    p.purchaseUnit = purchaseUnit;
    p.unitsPerPurchaseUnit = unitsPerPurchaseUnit;
    p.packageWeightKg = packageWeightKg;
    p.active = active;
    _recordAudit(
      actorName: actorName,
      actorRole: actorRole,
      action: (oldPrice != salePrice || oldCost != cost)
          ? 'product_price_updated'
          : 'product_updated',
      targetType: 'product',
      targetId: p.id,
      description:
          'Product ${p.sku} updated. Sale price ${oldPrice.toStringAsFixed(2)} -> ${salePrice.toStringAsFixed(2)}, cost ${oldCost.toStringAsFixed(2)} -> ${cost.toStringAsFixed(2)}',
    );
    _changed();
    return true;
  }

  void receiveStock(
    String productId,
    int quantity, {
    String employeeId = '',
    String employeeName = '',
    String supplier = 'Direct supplier',
    double unitCost = 0,
    String note = '',
    String purchaseUnit = 'piece',
    int unitsPerPurchaseUnit = 1,
    double packageWeightKg = 0,
    String saleUnit = 'piece',
    double salePrice = 0,
    double unitExpense = 0,
    double? amountPaid,
  }) {
    if (quantity <= 0) return;
    final p = product(productId);
    final oldCost = p.cost;
    final oldStock = p.stock;
    final oldSalePrice = p.price;
    final units = unitsPerPurchaseUnit <= 0 ? 1 : unitsPerPurchaseUnit;
    final baseQuantity = quantity * units;
    final packageCost = unitCost > 0 ? unitCost : p.cost * units;
    final safeUnitExpense = unitExpense < 0 ? 0.0 : unitExpense;
    final baseCost = (packageCost + safeUnitExpense) / units;
    final totalCostBefore = oldStock * oldCost;
    final receivedCost = baseQuantity * baseCost;
    p.stock += baseQuantity;
    if (p.stock > 0 && receivedCost > 0)
      p.cost = (totalCostBefore + receivedCost) / p.stock;
    if (salePrice > 0) p.price = salePrice;
    p.baseUnit = saleUnit;
    p.purchaseUnit = purchaseUnit;
    p.unitsPerPurchaseUnit = units;
    p.packageWeightKg = packageWeightKg;
    final number = 'RCV-${_nextSequenceValue('purchase')}';
    final supplierRecord = ensureSupplier(supplier);
    final line = PurchaseLine(
        productId: p.id,
        itemName: p.nameAr,
        quantity: quantity,
        unitCost: packageCost,
        purchaseUnit: purchaseUnit,
        unitsPerPurchaseUnit: units,
        packageWeightKg: packageWeightKg,
        saleUnit: saleUnit,
        salePrice: salePrice > 0 ? salePrice : p.price,
        unitExpense: safeUnitExpense);
    final total = line.total;
    final paid = (amountPaid ?? total).clamp(0, total).toDouble();
    final receipt = PurchaseReceipt(
        id: _id('pur'),
        number: number,
        createdAt: DateTime.now(),
        employeeId: employeeId,
        employeeName: employeeName,
        supplier: supplierRecord.name,
        supplierId: supplierRecord.id,
        paymentMethod: paid >= total ? 'Cash' : 'Debt',
        amountPaid: paid,
        lines: [line],
        note: note);
    purchases.insert(0, receipt);
    stockMovements.insert(
        0,
        StockMovement(
            id: _id('mv'),
            productId: p.id,
            itemName: p.nameAr,
            type: 'receive',
            quantity: baseQuantity,
            note: note.trim().isEmpty ? 'Purchase receiving' : note.trim(),
            createdAt: receipt.createdAt,
            employeeId: employeeId,
            employeeName: employeeName,
            reference: number,
            amount: total,
            operationUnit: purchaseUnit,
            operationQuantity: quantity.toDouble(),
            unitsPerOperationUnit: units));
    final due = total - paid;
    _postJournal(
        date: receipt.createdAt,
        reference: number,
        description: 'Inventory receiving',
        sourceType: 'purchase',
        sourceId: receipt.id,
        lines: [
          JournalLine(
              accountCode: '1200',
              accountName: accountName('1200'),
              debit: total),
          if (paid > 0)
            JournalLine(
                accountCode: '1000',
                accountName: accountName('1000'),
                credit: paid),
          if (due > 0)
            JournalLine(
                accountCode: '2000',
                accountName: accountName('2000'),
                credit: due),
        ]);
    if (oldCost != p.cost || oldSalePrice != p.price)
      _recordAudit(
          actorName: employeeName.isEmpty ? employeeId : employeeName,
          actorRole: 'inventory',
          action: 'receiving_price_updated',
          targetType: 'product',
          targetId: p.id,
          description:
              'Receiving updated ${p.sku}: sale ${oldSalePrice.toStringAsFixed(2)} -> ${p.price.toStringAsFixed(2)}, weighted cost ${oldCost.toStringAsFixed(2)} -> ${p.cost.toStringAsFixed(2)}');
    _changed();
  }

  ProductModel receiveManualItem({
    required String itemName,
    String sku = '',
    required int quantity,
    required String employeeId,
    required String employeeName,
    String supplier = 'Direct supplier',
    double unitCost = 0,
    String note = '',
    String purchaseUnit = 'piece',
    int unitsPerPurchaseUnit = 1,
    double packageWeightKg = 0,
    String saleUnit = 'piece',
    double salePrice = 0,
    double unitExpense = 0,
  }) {
    final p =
        createManualProduct(name: itemName, sku: sku, openingStock: 0, cost: unitCost);
    receiveStock(
      p.id,
      quantity,
      employeeId: employeeId,
      employeeName: employeeName,
      supplier: supplier,
      unitCost: unitCost,
      note: note,
      purchaseUnit: purchaseUnit,
      unitsPerPurchaseUnit: unitsPerPurchaseUnit,
      packageWeightKg: packageWeightKg,
      saleUnit: saleUnit,
      salePrice: salePrice,
      unitExpense: unitExpense,
    );
    return p;
  }

  PurchaseReceipt createPurchase({
    required List<PurchaseLine> lines,
    required String supplierName,
    required String employeeId,
    required String employeeName,
    String vendorInvoiceNumber = '',
    String paymentMethod = 'Cash',
    double amountPaid = 0,
    double shippingCost = 0,
    double taxAmount = 0,
    DateTime? dueDate,
    String note = '',
    String invoiceTitle = '',
    String restockRequestId = '',
  }) {
    if (lines.isEmpty)
      throw StateError('Purchase must contain at least one line');
    if (lines.any((l) =>
        l.quantity <= 0 || l.unitCost < 0 || l.unitExpense < 0 || l.unitsPerPurchaseUnit <= 0))
      throw StateError('Invalid purchase line');
    final supplier = ensureSupplier(supplierName);
    final safeShipping = shippingCost < 0 ? 0.0 : shippingCost;
    final safeTax = taxAmount < 0 ? 0.0 : taxAmount;
    final merchandise = lines.fold<double>(0, (sum, l) => sum + l.total);
    final extraCosts = safeShipping + safeTax;
    final total = merchandise + extraCosts;
    if (amountPaid < 0 || amountPaid > total + 0.005)
      throw StateError('Invalid purchase payment');

    for (final line in lines) {
      final productItem = productOrNull(line.productId);
      if (productItem == null) continue;
      final oldCost = productItem.cost;
      final oldStock = productItem.stock;
      final oldSalePrice = productItem.price;
      final share = merchandise <= 0 ? 0.0 : line.total / merchandise;
      final allocatedExtra = extraCosts * share;
      final landedBaseCost = line.baseQuantity <= 0
          ? 0.0
          : (line.total + allocatedExtra) / line.baseQuantity;
      final currentValue = oldStock * oldCost;
      final receivedValue = line.baseQuantity * landedBaseCost;
      productItem.stock += line.baseQuantity;
      if (productItem.stock > 0 && receivedValue > 0)
        productItem.cost = (currentValue + receivedValue) / productItem.stock;
      if (line.salePrice > 0) productItem.price = line.salePrice;
      productItem.baseUnit = line.saleUnit;
      productItem.purchaseUnit = line.purchaseUnit;
      productItem.unitsPerPurchaseUnit = line.unitsPerPurchaseUnit;
      productItem.packageWeightKg = line.packageWeightKg;
      if (oldCost != productItem.cost || oldSalePrice != productItem.price)
        _recordAudit(
            actorName: employeeName.isEmpty ? employeeId : employeeName,
            actorRole: 'receiving',
            action: 'purchase_price_updated',
            targetType: 'product',
            targetId: productItem.id,
            description:
                'Purchase ${productItem.sku}: sale ${oldSalePrice.toStringAsFixed(2)} -> ${productItem.price.toStringAsFixed(2)}, weighted landed cost ${oldCost.toStringAsFixed(2)} -> ${productItem.cost.toStringAsFixed(2)}');
    }
    final number = 'PUR-${_nextSequenceValue('purchase')}';
    final now = DateTime.now();
    final paid = amountPaid.clamp(0, total).toDouble();
    final receipt = PurchaseReceipt(
        id: _id('pur'),
        number: number,
        createdAt: now,
        employeeId: employeeId,
        employeeName: employeeName,
        supplier: supplier.name,
        supplierId: supplier.id,
        branch: settings.branchName,
        vendorInvoiceNumber: vendorInvoiceNumber,
        paymentMethod: paymentMethod,
        amountPaid: paid,
        shippingCost: safeShipping,
        taxAmount: safeTax,
        dueDate: dueDate,
        note: note,
        title: invoiceTitle.trim(),
        restockRequestId: restockRequestId,
        restockRequestNumber: restockRequestId.isEmpty
            ? ''
            : restockRequests
                .where((r) => r.id == restockRequestId)
                .map((r) => r.number)
                .firstWhere((_) => true, orElse: () => ''),
        lines: lines);
    purchases.insert(0, receipt);
    for (final line in lines)
      stockMovements.insert(
          0,
          StockMovement(
              id: _id('mv'),
              productId: line.productId,
              itemName: line.itemName,
              type: 'receive',
              quantity: line.baseQuantity,
              note: [
                if (note.trim().isNotEmpty) note.trim(),
                if (line.note.trim().isNotEmpty) line.note.trim(),
                if (note.trim().isEmpty && line.note.trim().isEmpty)
                  'Purchase ${receipt.number}'
              ].join(' • '),
              createdAt: now,
              employeeId: employeeId,
              employeeName: employeeName,
              reference: receipt.number,
              amount: line.total,
              operationUnit: line.purchaseUnit,
              operationQuantity: line.quantity.toDouble(),
              unitsPerOperationUnit: line.unitsPerPurchaseUnit));
    // For a partially-paid credit purchase, the immediate payment is treated
    // as cash unless a digital/card/transfer method is explicitly selected.
    final paidAccount = _usesCashAccount(paymentMethod) ? '1000' : '1010';
    final due = total - paid;
    _postJournal(
        date: now,
        reference: number,
        description: 'Purchase / receiving',
        sourceType: 'purchase',
        sourceId: receipt.id,
        lines: [
          JournalLine(
              accountCode: '1200',
              accountName: accountName('1200'),
              debit: total),
          if (paid > 0)
            JournalLine(
                accountCode: paidAccount,
                accountName: accountName(paidAccount),
                credit: paid),
          if (due > 0)
            JournalLine(
                accountCode: '2000',
                accountName: accountName('2000'),
                credit: due),
        ]);
    _fulfillRestockRequestsForPurchase(receipt, preferredRequestId: restockRequestId);
    _changed();
    return receipt;
  }

  void _fulfillRestockRequestsForPurchase(
    PurchaseReceipt receipt, {
    String preferredRequestId = '',
  }) {
    final purchasedIds = receipt.lines.map((l) => l.productId).where((id) => id.isNotEmpty).toSet();
    if (purchasedIds.isEmpty && preferredRequestId.isEmpty) return;
    final targets = <RestockRequest>[];
    if (preferredRequestId.isNotEmpty) {
      for (final request in restockRequests) {
        if (request.id == preferredRequestId) {
          targets.add(request);
          break;
        }
      }
    }
    if (targets.isEmpty) {
      for (final request in restockRequests) {
        if (request.status == 'received' || request.status == 'cancelled') continue;
        final overlap = request.lines.any((line) => purchasedIds.contains(line.productId));
        if (overlap) targets.add(request);
      }
    }
    if (targets.isEmpty) return;
    final now = DateTime.now();
    for (final request in targets) {
      request.status = 'received';
      request.updatedAt = now;
      request.fulfilledAt = now;
      request.fulfilledPurchaseId = receipt.id;
      request.fulfilledPurchaseNumber = receipt.number;
      request.fulfilledById = receipt.employeeId;
      request.fulfilledByName = receipt.employeeName;
    }
  }


  int returnedPurchaseQuantity(String purchaseId, String productId) {
    return purchaseReturns
        .where((r) => r.purchaseId == purchaseId)
        .fold<int>(0, (sum, r) {
      return sum +
          r.lines
              .where((line) => line.productId == productId)
              .fold<int>(0, (inner, line) => inner + line.quantity);
    });
  }

  int availablePurchaseReturnQuantity(
      PurchaseReceipt purchase, PurchaseLine line) {
    return (line.baseQuantity -
            returnedPurchaseQuantity(purchase.id, line.productId))
        .clamp(0, line.baseQuantity)
        .toInt();
  }

  PurchaseReturnRecord? returnPurchase({
    required PurchaseReceipt purchase,
    required Map<String, int> quantities,
    required String reason,
    required String processedBy,
    required String processedById,
    Map<String, String> returnUnits = const {},
    Map<String, int> returnUnitQuantities = const {},
    double? agreedRefundAmount,
    double paidNow = 0,
  }) {
    final now = DateTime.now();
    final planned = <({PurchaseLine original, int quantity, double unitCost})>[];

    for (final original in purchase.lines) {
      final requested = quantities[original.productId] ?? 0;
      final available = availablePurchaseReturnQuantity(purchase, original);
      final quantity = requested.clamp(0, available).toInt();
      if (quantity <= 0) continue;
      final productItem = productOrNull(original.productId);
      if (productItem == null || productItem.stock < quantity) return null;
      planned.add((
        original: original,
        quantity: quantity,
        unitCost: purchase.landedBaseUnitCost(original),
      ));
    }

    if (planned.isEmpty || paidNow < 0) return null;
    final inventoryReturnValue =
        planned.fold<double>(0, (sum, line) => sum + line.quantity * line.unitCost);
    final agreed = (agreedRefundAmount == null || agreedRefundAmount <= 0)
        ? inventoryReturnValue
        : agreedRefundAmount;
    if (agreed <= 0) return null;

    final outstandingBefore = purchaseOutstanding(purchase);
    final payableReduction = agreed.clamp(0, outstandingBefore).toDouble();
    final supplierRefundDue = (agreed - payableReduction)
        .clamp(0, double.infinity)
        .toDouble();
    if (paidNow > supplierRefundDue + 0.005) return null;
    final cashRefund = paidNow.clamp(0, supplierRefundDue).toDouble();
    final remainingRefund = (supplierRefundDue - cashRefund)
        .clamp(0, double.infinity)
        .toDouble();

    final lines = <PurchaseReturnLine>[];
    for (final item in planned) {
      final productItem = productOrNull(item.original.productId);
      if (productItem == null || productItem.stock < item.quantity) return null;
      final oldInventoryValue = productItem.stock * productItem.cost;
      final returnedInventoryValue = item.quantity * item.unitCost;
      productItem.stock -= item.quantity;
      if (productItem.stock > 0) {
        productItem.cost = ((oldInventoryValue - returnedInventoryValue) / productItem.stock)
            .clamp(0, double.infinity)
            .toDouble();
      }
      lines.add(PurchaseReturnLine(
        productId: item.original.productId,
        itemName: item.original.itemName,
        quantity: item.quantity,
        unitCost: item.unitCost,
        returnUnit: returnUnits[item.original.productId] ?? item.original.saleUnit,
        returnUnitQuantity: returnUnitQuantities[item.original.productId] ?? item.quantity,
      ));
      stockMovements.insert(
        0,
        StockMovement(
          id: _id('mv'),
          productId: item.original.productId,
          itemName: item.original.itemName,
          type: 'purchase_return',
          quantity: -item.quantity,
          note: reason.trim().isEmpty
              ? 'Purchase return ${purchase.number}'
              : reason.trim(),
          createdAt: now,
          employeeId: processedById,
          employeeName: processedBy,
          reference: purchase.number,
          amount: item.quantity * item.unitCost,
        ),
      );
    }

    final record = PurchaseReturnRecord(
      id: _id('pret'),
      purchaseId: purchase.id,
      purchaseNumber: purchase.number,
      createdAt: now,
      supplierId: purchase.supplierId,
      supplierName: purchase.supplier,
      lines: lines,
      processedBy: processedBy,
      processedById: processedById,
      reason: reason.trim(),
      payableReduction: payableReduction,
      cashRefund: cashRefund,
      agreedRefundAmount: agreed,
      remainingRefund: remainingRefund,
    );
    purchaseReturns.insert(0, record);

    final difference = agreed - inventoryReturnValue;
    _postJournal(
      date: now,
      reference: 'PRET-${purchase.number}',
      description: 'Purchase return ${purchase.number}',
      sourceType: 'purchase_return',
      sourceId: record.id,
      lines: [
        if (payableReduction > 0)
          JournalLine(
            accountCode: '2000',
            accountName: accountName('2000'),
            debit: payableReduction,
          ),
        if (cashRefund > 0)
          JournalLine(
            accountCode: '1000',
            accountName: accountName('1000'),
            debit: cashRefund,
          ),
        if (remainingRefund > 0)
          JournalLine(
            accountCode: '1110',
            accountName: accountName('1110'),
            debit: remainingRefund,
          ),
        if (difference < -0.005)
          JournalLine(
            accountCode: '6050',
            accountName: accountName('6050'),
            debit: -difference,
          ),
        JournalLine(
          accountCode: '1200',
          accountName: accountName('1200'),
          credit: inventoryReturnValue,
        ),
        if (difference > 0.005)
          JournalLine(
            accountCode: '4050',
            accountName: accountName('4050'),
            credit: difference,
          ),
      ],
    );
    _recordAudit(
      actorName: processedBy,
      actorRole: 'inventory',
      action: 'purchase_return',
      targetType: 'purchase',
      targetId: purchase.id,
      description:
          'Returned inventory ${inventoryReturnValue.toStringAsFixed(2)} from ${purchase.number}; agreed ${agreed.toStringAsFixed(2)}, payable reduced ${payableReduction.toStringAsFixed(2)}, paid now ${cashRefund.toStringAsFixed(2)}, remaining refund ${remainingRefund.toStringAsFixed(2)}.',
    );
    _changed();
    return record;
  }

  SupplierPaymentRecord? recordSupplierPayment({
    required String supplierId,
    required double amount,
    required String method,
    required String employeeName,
    String purchaseId = '',
    String note = '',
  }) {
    final supplier = supplierOrNull(supplierId);
    if (supplier == null ||
        amount <= 0 ||
        amount > supplierBalance(supplierId) + 0.005) return null;
    final allocations = <String, double>{};
    PurchaseReceipt? explicit;
    if (purchaseId.isNotEmpty) {
      for (final p in purchases) {
        if (p.id == purchaseId &&
            p.supplierId == supplierId &&
            _isCurrentFinancialDate(p.createdAt)) {
          explicit = p;
          break;
        }
      }
      if (explicit == null || amount > purchaseOutstanding(explicit) + 0.005)
        return null;
      allocations[explicit.id] = amount;
    } else {
      var remaining = amount;
      final open = purchases
          .where((p) =>
              p.supplierId == supplierId &&
              _isCurrentFinancialDate(p.createdAt) &&
              purchaseOutstanding(p) > 0.005)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final purchase in open) {
        if (remaining <= 0.005) break;
        final applied =
            remaining.clamp(0, purchaseOutstanding(purchase)).toDouble();
        if (applied > 0) {
          allocations[purchase.id] = applied;
          remaining -= applied;
        }
      }
    }
    final payment = SupplierPaymentRecord(
        id: _id('spay'),
        supplierId: supplier.id,
        supplierName: supplier.name,
        createdAt: DateTime.now(),
        amount: amount,
        method: method,
        employeeName: employeeName,
        purchaseId: explicit?.id ?? '',
        purchaseNumber: explicit?.number ?? '',
        note: note,
        allocations: allocations);
    supplierPayments.insert(0, payment);
    final account = method == 'Cash' ? '1000' : '1010';
    _postJournal(
        date: payment.createdAt,
        reference:
            payment.purchaseNumber.isEmpty ? 'SUP-PAY' : payment.purchaseNumber,
        description: 'Supplier payment ${supplier.name}',
        sourceType: 'supplier_payment',
        sourceId: payment.id,
        lines: [
          JournalLine(
              accountCode: '2000',
              accountName: accountName('2000'),
              debit: amount),
          JournalLine(
              accountCode: account,
              accountName: accountName(account),
              credit: amount)
        ]);
    _changed();
    return payment;
  }

  CustomerPaymentRecord? recordCustomerPayment({
    required String customerId,
    required double amount,
    required String method,
    required String employeeName,
    String note = '',
  }) {
    final customer = customerOrNull(customerId);
    if (customer == null || amount <= 0 || amount > customer.balance + 0.005)
      return null;
    var remaining = amount;
    final allocations = <String, double>{};
    final openInvoices = invoices
        .where((i) =>
            !i.voided &&
            i.customerId == customerId &&
            _isCurrentFinancialDate(i.createdAt) &&
            invoiceOutstanding(i.id) > 0.005)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final invoice in openInvoices) {
      if (remaining <= 0.005) break;
      final outstanding = invoiceOutstanding(invoice.id);
      final applied = remaining.clamp(0, outstanding).toDouble();
      if (applied > 0) {
        allocations[invoice.id] = applied;
        remaining -= applied;
      }
    }
    // Any remainder belongs to the customer's opening/unallocated balance.
    // It is still a valid receivable collection even when no historical
    // invoice exists to allocate it to.
    final payment = CustomerPaymentRecord(
        id: _id('cpay'),
        customerId: customer.id,
        customerName: customer.name,
        createdAt: DateTime.now(),
        amount: amount,
        method: method,
        employeeName: employeeName,
        note: note,
        allocations: allocations);
    customerPayments.insert(0, payment);
    customer.balance =
        (customer.balance - amount).clamp(0, double.infinity).toDouble();
    final account = method == 'Cash' ? '1000' : '1010';
    _postJournal(
        date: payment.createdAt,
        reference: 'CUS-PAY-${payment.id}',
        description: 'Customer payment ${customer.name}',
        sourceType: 'customer_payment',
        sourceId: payment.id,
        lines: [
          JournalLine(
              accountCode: account,
              accountName: accountName(account),
              debit: amount),
          JournalLine(
              accountCode: '1100',
              accountName: accountName('1100'),
              credit: amount)
        ]);
    _changed();
    return payment;
  }

  String payrollPeriodKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  DateTime salaryDueDate(EmployeeRecord employee, DateTime month) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final day = employee.salaryPayDay.clamp(1, lastDay).toInt();
    return DateTime(month.year, month.month, day);
  }

  List<ExpenseRecord> salaryPaymentsFor(String employeeId, DateTime month) {
    final key = payrollPeriodKey(month);
    return expenses.where((expense) {
      if (expense.sourceType != 'salary' || expense.sourceId != employeeId) return false;
      return expense.payrollPeriod == key || expense.description.contains(key);
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  ExpenseRecord? salaryPaymentFor(String employeeId, DateTime month) {
    final rows = salaryPaymentsFor(employeeId, month);
    return rows.isEmpty ? null : rows.first;
  }

  double salaryPaidAmountFor(String employeeId, DateTime month) =>
      salaryPaymentsFor(employeeId, month).fold<double>(0, (sum, expense) => sum + expense.amount);

  List<OvertimeRecord> overtimeForEmployee(String employeeId, DateTime month) =>
      overtimeRecords.where((record) =>
        record.employeeId == employeeId &&
        record.startAt.year == month.year &&
        record.startAt.month == month.month
      ).toList()..sort((a, b) => b.startAt.compareTo(a.startAt));

  double employeeDailyShiftHours(String employeeId) {
    final employee = employeeOrNull(employeeId);
    if (employee == null) return 8.0;
    var minutes = employee.shiftEndMinutes - employee.shiftStartMinutes;
    if (minutes <= 0) minutes += 24 * 60;
    if (minutes <= 0) return 8.0;
    return minutes / 60.0;
  }

  double overtimePayFor(String employeeId, DateTime month) {
    final employee = employeeOrNull(employeeId);
    if (employee == null || employee.salary <= 0) return 0;
    final dailyHours = employeeDailyShiftHours(employeeId);
    if (dailyHours <= 0) return 0;
    final hourlyRate = employee.salary / 30.0 / dailyHours;
    return overtimeForEmployee(employeeId, month).fold<double>(
      0,
      (sum, record) => sum + (record.hours * hourlyRate * record.rateMultiplier),
    );
  }

  double payrollGrossFor(String employeeId, DateTime month) {
    final employee = employeeOrNull(employeeId);
    if (employee == null || employee.salary <= 0) return 0;
    return employee.salary + overtimePayFor(employeeId, month);
  }

  double salaryOutstandingFor(String employeeId, DateTime month) {
    final gross = payrollGrossFor(employeeId, month);
    if (gross <= 0) return 0;
    return (gross - salaryPaidAmountFor(employeeId, month))
        .clamp(0, gross)
        .toDouble();
  }

  bool salaryPaidFor(String employeeId, DateTime month) {
    final employee = employeeOrNull(employeeId);
    if (employee == null || employee.salary <= 0) return false;
    return salaryOutstandingFor(employeeId, month) <= 0.005;
  }

  double get monthlyPayrollTotal { final now = DateTime.now(); return employees.where((e) => e.active && e.salary > 0).fold<double>(0, (sum, e) => sum + payrollGrossFor(e.id, now)); }

  bool updateEmployeePayroll({
    required String employeeId,
    required double salary,
    required int payDay,
    required String actorName,
    required String actorRole,
  }) {
    if (!const {'owner', 'manager'}.contains(actorRole)) return false;
    final e = employeeOrNull(employeeId);
    if (e == null || salary < 0 || payDay < 1 || payDay > 31) return false;
    e.salary = salary;
    e.salaryPayDay = payDay;
    _recordAudit(actorName: actorName, actorRole: actorRole, action: 'payroll_updated', targetType: 'employee', targetId: e.id, description: 'Payroll settings updated for ${e.id}.');
    _changed();
    return true;
  }

  List<EmployeeAdvanceRecord> advancesForEmployee(String employeeId) =>
      employeeAdvances.where((a) => a.employeeId == employeeId).toList();

  double employeeOutstandingAdvance(String employeeId) => advancesForEmployee(employeeId)
      .fold<double>(0, (sum, a) => sum + a.outstanding);

  double employeeAdvanceTotal(String employeeId) => advancesForEmployee(employeeId)
      .fold<double>(0, (sum, a) => sum + a.amount);

  double employeeAdvanceSettled(String employeeId) => advancesForEmployee(employeeId)
      .fold<double>(0, (sum, a) => sum + a.settledAmount);

  double employeeNetSalaryAfterAdvances(String employeeId, DateTime month) {
    final salaryRemaining = salaryOutstandingFor(employeeId, month);
    final advances = employeeOutstandingAdvance(employeeId);
    return (salaryRemaining - advances).clamp(0, salaryRemaining).toDouble();
  }

  bool hasPayrollActivityForMonth(DateTime month) {
    final key = payrollPeriodKey(month);
    if (expenses.any((e) => e.sourceType == 'salary' && e.payrollPeriod == key)) return true;
    if (employeeAdvances.any((a) => a.createdAt.year == month.year && a.createdAt.month == month.month)) return true;
    return false;
  }

  EmployeeAdvanceRecord? recordEmployeeAdvance({
    required String employeeId,
    required double amount,
    required String givenBy,
    required String actorRole,
    String paymentMethod = 'Cash',
    String note = '',
  }) {
    if (!const {'owner', 'accountant'}.contains(actorRole)) return null;
    final e = employeeOrNull(employeeId);
    if (e == null || amount <= 0) return null;
    final record = EmployeeAdvanceRecord(
      id: _id('adv'), employeeId: e.id, employeeName: e.nameAr,
      createdAt: DateTime.now(), amount: amount, givenBy: givenBy,
      paymentMethod: paymentMethod, note: note.trim(),
    );
    employeeAdvances.insert(0, record);
    final cashAccount = _usesCashAccount(paymentMethod) ? '1000' : '1010';
    _postJournal(date: record.createdAt, reference: 'ADV-${record.id}', description: 'Employee advance • ${e.nameAr}', sourceType: 'employee_advance', sourceId: record.id, lines: [
      JournalLine(accountCode: '1150', accountName: accountName('1150'), debit: amount),
      JournalLine(accountCode: cashAccount, accountName: accountName(cashAccount), credit: amount),
    ]);
    _recordAudit(actorName: givenBy, actorRole: actorRole, action: 'employee_advance', targetType: 'employee', targetId: e.id, description: 'Employee advance ${amount.toStringAsFixed(2)} recorded.');
    _changed();
    return record;
  }

  void _settleEmployeeAdvances(String employeeId, double amount) {
    var remaining = amount;
    if (remaining <= 0) return;
    final rows = employeeAdvances.where((a) => a.employeeId == employeeId && a.outstanding > 0).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final advance in rows) {
      if (remaining <= 0) break;
      final applied = remaining.clamp(0, advance.outstanding).toDouble();
      advance.settledAmount += applied;
      remaining -= applied;
    }
  }

  ExpenseRecord? recordSalaryPayment({
    required String employeeId,
    required DateTime month,
    required String paidBy,
    required String actorRole,
    String paymentMethod = 'Cash',
    double? grossAmount,
    double advanceDeduction = 0,
  }) {
    if (!const {'owner', 'manager', 'accountant'}.contains(actorRole)) return null;
    final e = employeeOrNull(employeeId);
    if (e == null || e.salary <= 0) return null;
    final remainingSalary = salaryOutstandingFor(employeeId, month);
    if (remainingSalary <= 0.005) return null;
    final requested = grossAmount ?? remainingSalary;
    if (requested <= 0 || requested > remainingSalary + 0.005) return null;
    final gross = requested.clamp(0, remainingSalary).toDouble();
    final outstandingAdvance = employeeOutstandingAdvance(employeeId);
    final deduction = advanceDeduction.clamp(0, min(gross, outstandingAdvance)).toDouble();
    final net = gross - deduction;
    final key = payrollPeriodKey(month);
    final record = ExpenseRecord(
      id: _id('exp'), createdAt: DateTime.now(), category: 'Salaries',
      description: 'Salary • ${e.nameAr} • $key${deduction > 0 ? ' • Advance deduction ${deduction.toStringAsFixed(2)}' : ''}',
      amount: gross, employeeName: paidBy, paymentMethod: paymentMethod,
      sourceType: 'salary', sourceId: e.id, payrollPeriod: key,
    );
    expenses.insert(0, record);
    final cashAccount = _usesCashAccount(paymentMethod) ? '1000' : '1010';
    _postJournal(date: record.createdAt, reference: 'PAY-${record.id}', description: record.description, sourceType: 'salary', sourceId: record.id, lines: [
      JournalLine(accountCode: '6020', accountName: accountName('6020'), debit: gross),
      if (deduction > 0) JournalLine(accountCode: '1150', accountName: accountName('1150'), credit: deduction),
      if (net > 0) JournalLine(accountCode: cashAccount, accountName: accountName(cashAccount), credit: net),
    ]);
    _settleEmployeeAdvances(employeeId, deduction);
    _recordAudit(actorName: paidBy, actorRole: actorRole, action: 'salary_paid', targetType: 'employee', targetId: e.id, description: 'Salary installment recorded for ${e.id} • $key • gross ${gross.toStringAsFixed(2)} • advance deduction ${deduction.toStringAsFixed(2)} • remaining ${salaryOutstandingFor(employeeId, month).toStringAsFixed(2)}.');
    _changed();
    return record;
  }

  ExpenseRecord? addExpense({
    required String category,
    required String description,
    required double amount,
    required String employeeName,
    String paymentMethod = 'Cash',
    String accountCode = '6000',
    String sourceType = '',
    String sourceId = '',
    String payrollPeriod = '',
    DateTime? createdAt,
  }) {
    if (amount <= 0 || description.trim().isEmpty) return null;
    final record = ExpenseRecord(
        id: _id('exp'),
        createdAt: createdAt ?? DateTime.now(),
        category: category.trim().isEmpty ? 'General' : category.trim(),
        description: description.trim(),
        amount: amount,
        employeeName: employeeName,
        paymentMethod: paymentMethod,
        sourceType: sourceType,
        sourceId: sourceId,
        payrollPeriod: payrollPeriod);
    expenses.insert(0, record);
    final account = paymentMethod == 'Cash' ? '1000' : '1010';
    _postJournal(
        date: record.createdAt,
        reference: 'EXP-${record.id}',
        description: record.description,
        sourceType: 'expense',
        sourceId: record.id,
        lines: [
          JournalLine(
              accountCode: accountCode,
              accountName: accountName(accountCode),
              debit: amount),
          JournalLine(
              accountCode: account,
              accountName: accountName(account),
              credit: amount)
        ]);
    _changed();
    return record;
  }

  bool recordDamage({
    required String productId,
    required int quantity,
    required String reason,
    String employeeId = '',
    String employeeName = '',
    String operationUnit = '',
    double operationQuantity = 0,
    int unitsPerOperationUnit = 1,
  }) {
    final p = product(productId);
    if (quantity <= 0 || quantity > p.stock) return false;
    p.stock -= quantity;
    stockMovements.insert(
      0,
      StockMovement(
        id: _id('mv'),
        productId: productId,
        itemName: p.nameAr,
        type: 'damage',
        quantity: -quantity,
        note: reason,
        createdAt: DateTime.now(),
        employeeId: employeeId,
        employeeName: employeeName,
        operationUnit: operationUnit,
        operationQuantity: operationQuantity,
        unitsPerOperationUnit:
            unitsPerOperationUnit <= 0 ? 1 : unitsPerOperationUnit,
      ),
    );
    final lossValue = quantity * p.cost;
    if (lossValue > 0)
      _postJournal(
          date: DateTime.now(),
          reference: 'DMG-${p.id}',
          description: 'Inventory shrinkage: ${p.nameAr}',
          sourceType: 'damage',
          sourceId: p.id,
          lines: [
            JournalLine(
                accountCode: '6050',
                accountName: accountName('6050'),
                debit: lossValue),
            JournalLine(
                accountCode: '1200',
                accountName: accountName('1200'),
                credit: lossValue)
          ]);
    _changed();
    return true;
  }

  void recordManualInventoryLog({
    required String itemName,
    required String type,
    required int quantity,
    required String note,
    required String employeeId,
    required String employeeName,
    String reference = '',
  }) {
    stockMovements.insert(
      0,
      StockMovement(
        id: _id('mv'),
        itemName: itemName,
        type: type,
        quantity: quantity,
        note: note,
        createdAt: DateTime.now(),
        employeeId: employeeId,
        employeeName: employeeName,
        reference: reference,
      ),
    );
    _changed();
  }

  bool transferStock({
    required String productId,
    required int quantity,
    required String destination,
    String employeeId = '',
    String employeeName = '',
    String operationUnit = '',
    double operationQuantity = 0,
    int unitsPerOperationUnit = 1,
    String note = '',
  }) {
    final p = product(productId);
    if (quantity <= 0 || quantity > p.stock) return false;
    p.stock -= quantity;
    stockMovements.insert(
      0,
      StockMovement(
        id: _id('mv'),
        productId: productId,
        itemName: p.nameAr,
        type: 'transfer',
        quantity: -quantity,
        note: [
          if (note.trim().isNotEmpty) note.trim(),
          'Transfer to $destination'
        ].join(' • '),
        createdAt: DateTime.now(),
        employeeId: employeeId,
        employeeName: employeeName,
        reference: destination,
        operationUnit: operationUnit,
        operationQuantity: operationQuantity,
        unitsPerOperationUnit:
            unitsPerOperationUnit <= 0 ? 1 : unitsPerOperationUnit,
      ),
    );
    _changed();
    return true;
  }

  void setStockCount(
    String productId,
    int actual, {
    String employeeId = '',
    String employeeName = '',
  }) {
    final p = product(productId);
    if (actual < 0) return;
    final difference = actual - p.stock;
    p.stock = actual;
    stockMovements.insert(
      0,
      StockMovement(
        id: _id('mv'),
        productId: productId,
        itemName: p.nameAr,
        type: 'count',
        quantity: difference,
        note: 'Stock count adjustment',
        createdAt: DateTime.now(),
        employeeId: employeeId,
        employeeName: employeeName,
      ),
    );
    _changed();
  }

  StockCountSession startStockCount({
    required String employeeId,
    required String employeeName,
    List<String>? productIds,
    String requestedByName = '',
    String requestedByRole = '',
  }) {
    final includedIds = productIds == null ? null : productIds.toSet();
    final session = StockCountSession(
      id: _id('count'),
      number: 'CNT-${_nextSequenceValue('stock_count')}',
      createdAt: DateTime.now(),
      employeeId: employeeId,
      employeeName: employeeName,
      requestedByName: requestedByName,
      requestedByRole: requestedByRole,
      lines: products
          .where((p) =>
              p.active && (includedIds == null || includedIds.contains(p.id)))
          .map((p) => StockCountLine(
              productId: p.id,
              itemName: p.nameAr,
              expected: p.stock,
              actual: 0,
              countUnit: p.baseUnit,
              unitsPerCountUnit: 1,
              enteredQuantity: 0,
              counted: false))
          .toList(),
    );
    stockCounts.insert(0, session);
    _changed();
    return session;
  }

  void updateStockCountLine(String sessionId, String productId, int actual) {
    final session = stockCounts.firstWhere((s) => s.id == sessionId);
    if (session.status != 'open' || actual < 0) return;
    final line = session.lines.firstWhere((l) => l.productId == productId);
    line.actual = actual;
    line.enteredQuantity = actual;
    line.unitsPerCountUnit = 1;
    line.countUnit = productOrNull(productId)?.baseUnit ?? line.countUnit;
    line.counted = true;
    _changed();
  }

  void updateStockCountEntry(
    String sessionId,
    String productId, {
    required int enteredQuantity,
    required String unit,
    required int unitsPerUnit,
  }) {
    final session = stockCounts.firstWhere((s) => s.id == sessionId);
    if (session.status != 'open' || enteredQuantity < 0 || unitsPerUnit <= 0)
      return;
    final line = session.lines.firstWhere((l) => l.productId == productId);
    line.enteredQuantity = enteredQuantity;
    line.countUnit = unit;
    line.unitsPerCountUnit = unitsPerUnit;
    line.actual = enteredQuantity * unitsPerUnit;
    line.counted = true;
    _changed();
  }

  int stockCountExpectedQuantity(
      StockCountSession session, StockCountLine line) {
    // Freeze the system quantity at the moment the stock-count session starts.
    // This makes variances deterministic and prevents unrelated stock movements
    // from changing the expected quantity while the employee is counting.
    return line.expected;
  }

  StockCountBreakdown stockCountBreakdown(String sessionId, String productId) {
    final session = stockCounts.firstWhere((s) => s.id == sessionId);
    final line = session.lines.firstWhere((l) => l.productId == productId);
    final end = session.status == 'completed'
        ? (session.completedAt ?? session.createdAt)
        : session.status == 'submitted'
            ? (session.submittedAt ?? DateTime.now())
            : DateTime.now();

    DateTime? previousCountAt;
    for (final other in stockCounts) {
      if (other.id == session.id ||
          other.status != 'completed' ||
          other.completedAt == null) continue;
      if (!other.completedAt!.isBefore(session.createdAt)) continue;
      if (!other.lines.any((l) => l.productId == productId)) continue;
      if (previousCountAt == null ||
          other.completedAt!.isAfter(previousCountAt))
        previousCountAt = other.completedAt;
    }

    final productMovements = stockMovements
        .where((m) => m.productId == productId && !m.createdAt.isAfter(end))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final start = previousCountAt ??
        (productMovements.isNotEmpty
            ? productMovements.first.createdAt
            : session.createdAt);
    final movements = productMovements
        .where((m) =>
            !m.createdAt.isBefore(start) &&
            !m.createdAt.isAfter(end) &&
            !(m.type == 'count' && m.reference == session.number))
        .toList();

    var received = 0;
    var returned = 0;
    var sold = 0;
    var damaged = 0;
    var transferredOut = 0;
    var adjustments = 0;
    for (final movement in movements) {
      switch (movement.type) {
        case 'receive':
          received += movement.quantity > 0 ? movement.quantity : 0;
          break;
        case 'return':
          returned += movement.quantity > 0 ? movement.quantity : 0;
          break;
        case 'sale':
          sold +=
              movement.quantity < 0 ? -movement.quantity : movement.quantity;
          break;
        case 'damage':
          damaged +=
              movement.quantity < 0 ? -movement.quantity : movement.quantity;
          break;
        case 'transfer':
          if (movement.quantity < 0) {
            transferredOut += -movement.quantity;
          } else {
            adjustments += movement.quantity;
          }
          break;
        default:
          adjustments += movement.quantity;
      }
    }
    final expected = stockCountExpectedQuantity(session, line);
    final netMovement =
        movements.fold<int>(0, (sum, movement) => sum + movement.quantity);
    final openingStock = expected - netMovement;
    return StockCountBreakdown(
      periodStart: start,
      periodEnd: end,
      openingStock: openingStock,
      received: received,
      returned: returned,
      sold: sold,
      damaged: damaged,
      transferredOut: transferredOut,
      adjustments: adjustments,
      expected: expected,
      actual: line.actual,
      movements: movements.reversed.toList(),
    );
  }

  bool submitStockCount(String sessionId) {
    final session = stockCounts.firstWhere((s) => s.id == sessionId);
    if (session.status != 'open' || session.lines.isEmpty) return false;
    if (session.lines.any((line) => !line.counted)) return false;
    // Freeze the system quantity at the exact submission moment. The inventory
    // employee never sees this value, but management gets a fair variance even
    // if sales/receipts happened while the physical count was in progress.
    for (final line in session.lines) {
      final p = productOrNull(line.productId);
      if (p != null) line.expected = p.stock;
    }
    session.status = 'submitted';
    session.submittedAt = DateTime.now();
    _recordAudit(
      actorName: session.employeeName,
      actorRole: 'inventory',
      action: 'stock_count_submitted',
      targetType: 'stock_count',
      targetId: session.id,
      description: 'Blind stock count ${session.number} submitted for management review.',
    );
    _changed();
    return true;
  }

  bool approveStockCount(
    String sessionId, {
    required String actorName,
    required String actorRole,
  }) {
    if (actorRole != 'owner' && actorRole != 'manager') return false;
    final session = stockCounts.firstWhere((s) => s.id == sessionId);
    if ((session.status != 'open' && session.status != 'submitted') ||
        session.lines.isEmpty) return false;
    if (session.lines.any((line) => !line.counted)) return false;

    for (final line in session.lines) {
      final p = product(line.productId);
      final systemExpected = line.expected;
      if (line.actual == systemExpected) continue;
      final diff = line.actual - systemExpected;
      // Apply only the approved variance to the current stock so movements that
      // occurred after submission are preserved.
      p.stock += diff;
      final adjustmentValue = diff.abs() * p.cost;
      if (adjustmentValue > 0) {
        if (diff < 0) {
          _postJournal(
              date: DateTime.now(),
              reference: session.number,
              description: 'Inventory count shrinkage ${p.nameAr}',
              sourceType: 'stock_count',
              sourceId: session.id,
              lines: [
                JournalLine(
                    accountCode: '6050',
                    accountName: accountName('6050'),
                    debit: adjustmentValue),
                JournalLine(
                    accountCode: '1200',
                    accountName: accountName('1200'),
                    credit: adjustmentValue)
              ]);
        } else {
          _postJournal(
              date: DateTime.now(),
              reference: session.number,
              description: 'Inventory count gain ${p.nameAr}',
              sourceType: 'stock_count',
              sourceId: session.id,
              lines: [
                JournalLine(
                    accountCode: '1200',
                    accountName: accountName('1200'),
                    debit: adjustmentValue),
                JournalLine(
                    accountCode: '4050',
                    accountName: accountName('4050'),
                    credit: adjustmentValue)
              ]);
        }
      }
      stockMovements.insert(
        0,
        StockMovement(
          id: _id('mv'),
          productId: p.id,
          itemName: p.nameAr,
          type: 'count',
          quantity: diff,
          note: 'Stock count ${session.number} • approved by $actorName',
          createdAt: DateTime.now(),
          employeeId: session.employeeId,
          employeeName: session.employeeName,
          reference: session.number,
          operationUnit: line.countUnit,
          operationQuantity: line.enteredQuantity.toDouble(),
          unitsPerOperationUnit: line.unitsPerCountUnit,
        ),
      );
    }
    session.status = 'completed';
    session.completedAt = DateTime.now();
    session.approvedByName = actorName;
    session.approvedByRole = actorRole;
    _recordAudit(
      actorName: actorName,
      actorRole: actorRole,
      action: 'stock_count_approved',
      targetType: 'stock_count',
      targetId: session.id,
      description: 'Stock count ${session.number} variances reviewed and approved.',
    );
    _changed();
    return true;
  }

  // Backward-compatible management completion path.
  bool completeStockCount(String sessionId) => approveStockCount(
        sessionId,
        actorName: 'Management',
        actorRole: 'manager',
      );

  TaskRecord createTask({
    required String title,
    required String employeeId,
    required DateTime dueAt,
    required String priority,
    required String assignedBy,
    String description = '',
  }) {
    final task = TaskRecord(
      id: _id('task'),
      titleAr: title,
      titleEn: title,
      description: description,
      assignedEmployeeId: employeeId,
      priority: priority,
      createdAt: DateTime.now(),
      dueAt: dueAt,
      assignedBy: assignedBy,
    );
    tasks.insert(0, task);
    _changed();
    return task;
  }

  void updateTaskStatus(String id, String status) {
    final task = tasks.firstWhere((item) => item.id == id);
    if (status == 'in_progress' && task.startedAt == null)
      task.startedAt = DateTime.now();
    if (status == 'completed') task.completedAt = DateTime.now();
    if (status != 'completed') task.completedAt = null;
    task.status = status;
    _changed();
  }

  void toggleTask(String id) {
    final task = tasks.firstWhere((item) => item.id == id);
    updateTaskStatus(id, task.done ? 'pending' : 'completed');
  }

  void deleteTask(String id) {
    tasks.removeWhere((item) => item.id == id);
    _changed();
  }

  bool _autoCloseExpiredAttendance({String? employeeId}) {
    final now = DateTime.now();
    var changed = false;
    for (final record in attendance) {
      if (record.clockOut != null) continue;
      if (employeeId != null && record.employeeId != employeeId) continue;
      final scheduledEnd = scheduledEndForAttendance(record);
      if (scheduledEnd == null || now.isBefore(scheduledEnd)) continue;
      record.clockOut = scheduledEnd.isBefore(record.clockIn) ? record.clockIn : scheduledEnd;
      record.automaticClockOut = true;
      changed = true;
    }
    if (changed) unawaited(_save());
    return changed;
  }

  AttendanceRecord clockIn(String employeeId, String name) {
    _autoCloseExpiredAttendance(employeeId: employeeId);
    final open = attendance.where((r) => r.employeeId == employeeId && r.clockOut == null);
    if (open.isNotEmpty) return open.first;
    final employee = employeeOrNull(employeeId);
    final record = AttendanceRecord(
      id: _id('att'),
      employeeId: employeeId,
      employeeName: name,
      clockIn: DateTime.now(),
      scheduledStartMinutes: employee?.shiftStartMinutes ?? -1,
      scheduledEndMinutes: employee?.shiftEndMinutes ?? -1,
    );
    attendance.insert(0, record);
    _changed();
    return record;
  }

  bool _attendanceBelongsTo(AttendanceRecord record, String employeeId) {
    if (record.employeeId == employeeId) return true;
    EmployeeRecord? employee = employeeOrNull(employeeId);
    if (employee == null) {
      for (final item in employees) {
        if (item.id == employeeId || item.loginId == employeeId) {
          employee = item;
          break;
        }
      }
    }
    if (employee == null) return false;
    return record.employeeId == employee.id || record.employeeId == employee.loginId;
  }

  bool clockOut(String employeeId) {
    _autoCloseExpiredAttendance(employeeId: employeeId);
    final open = attendance
        .where((r) => r.clockOut == null && _attendanceBelongsTo(r, employeeId))
        .toList();
    if (open.isEmpty) return false;
    final now = DateTime.now();
    for (final record in open) {
      record.clockOut = now;
      record.automaticClockOut = false;
    }
    _changed();
    return true;
  }

  AttendanceRecord? currentAttendance(String employeeId) {
    _autoCloseExpiredAttendance(employeeId: employeeId);
    for (final item in attendance) {
      if (item.clockOut == null && _attendanceBelongsTo(item, employeeId)) {
        return item;
      }
    }
    return null;
  }

  OvertimeRecord? recordOvertime({
    required String employeeId,
    required DateTime startAt,
    required DateTime endAt,
    required String createdBy,
    required String actorRole,
    String note = '',
    double rateMultiplier = 1.0,
  }) {
    if (!const {'owner', 'manager'}.contains(actorRole)) return null;
    final employee = employeeOrNull(employeeId);
    if (employee == null || !endAt.isAfter(startAt) || rateMultiplier <= 0) return null;
    final record = OvertimeRecord(
      id: _id('ot'),
      employeeId: employee.id,
      employeeName: employee.nameAr,
      startAt: startAt,
      endAt: endAt,
      createdBy: createdBy,
      note: note.trim(),
      rateMultiplier: rateMultiplier,
    );
    overtimeRecords.insert(0, record);
    _recordAudit(actorName: createdBy, actorRole: actorRole, action: 'overtime_recorded', targetType: 'employee', targetId: employee.id, description: 'Overtime ${record.hours.toStringAsFixed(2)} hours recorded.');
    _changed();
    return record;
  }


  void renameEmployee(String id,
      {required String nameAr, required String nameEn}) {
    final e = employeeOrNull(id);
    if (e == null) return;
    e.nameAr = nameAr;
    e.nameEn = nameEn;
    _changed();
  }

  void updateEmployeeShift(
      String id, int startMinutes, int endMinutes, int weeklyOffDay) {
    final e = employeeOrNull(id);
    if (e == null) return;
    e.shiftStartMinutes = startMinutes;
    e.shiftEndMinutes = endMinutes;
    e.weeklyOffDay = weeklyOffDay;
    _changed();
  }

  bool updateEmployeeCredentials({
    required String employeeId,
    required String loginId,
    required String pin,
    required String actorName,
    required String actorRole,
  }) {
    if (actorRole != 'owner' && actorRole != 'manager') return false;
    final e = employeeOrNull(employeeId);
    if (e == null || loginId.trim().isEmpty) return false;
    if (pin.trim().isNotEmpty && pin.trim().length < 4) return false;
    final normalized = loginId.trim().toUpperCase();
    final duplicate = activeEmployeeUsingLoginId(normalized, exceptEmployeeId: e.id);
    if (duplicate != null) return false;
    e.loginId = normalized;
    if (pin.trim().isNotEmpty) e.pin = pin.trim();
    _recordAudit(
      actorName: actorName,
      actorRole: actorRole,
      action: 'credentials_updated',
      targetType: 'employee',
      targetId: e.id,
      description: 'Employee login credentials changed for ${e.id}',
    );
    _changed();
    return true;
  }

  bool updateAdminCredentials({
    required String targetRole,
    required String displayName,
    required String email,
    required String password,
    required String pin,
    required String actorName,
    required String actorRole,
  }) {
    if (actorRole != 'owner' || email.trim().isEmpty || displayName.trim().isEmpty) return false;
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedName = displayName.trim();
    var account = adminAccountByRole(targetRole);
    final creating = account == null;
    if (creating && password.trim().isEmpty) return false;
    if (creating && !RegExp(r'^\d{4}$').hasMatch(pin.trim())) return false;

    if (!creating && pin.trim().isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(pin.trim())) return false;
    final duplicate = adminAccountByEmail(normalizedEmail);
    if (duplicate != null && duplicate.id != account?.id) return false;

    if (account == null) {
      account = AdminAccountRecord(
        id: 'admin-$targetRole',
        roleKey: targetRole,
        email: normalizedEmail,
        password: password.trim(),
        pin: pin.trim(),
        // One display name is used in both UI languages so the greeting always
        // addresses the real person rather than the permission role.
        nameAr: normalizedName,
        nameEn: normalizedName,
      );
      adminAccounts.add(account);
    } else {
      account.nameAr = normalizedName;
      account.nameEn = normalizedName;
      account.email = normalizedEmail;
      if (password.trim().isNotEmpty) account.password = password.trim();
      if (pin.trim().isNotEmpty) account.pin = pin.trim();
      account.active = true;
    }
    _syncManagementEmployee(account);

    _recordAudit(
      actorName: actorName,
      actorRole: actorRole,
      action: creating ? 'management_account_created' : 'credentials_updated',
      targetType: 'management_account',
      targetId: account.id,
      description: creating
          ? 'Management account created for $targetRole'
          : 'Management login credentials changed for $targetRole',
    );
    _changed();
    return true;
  }

  bool get hasOwnerAccount => adminAccountByRole('owner') != null;

  Future<void> provisionOwnerAccount({
    required String name,
    required String email,
    required String password,
    required String pin,
    String phone = '',
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty || !RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw ArgumentError('Invalid owner credentials');
    }
    // First activation replaces any legacy/bootstrap management credentials so
    // the store starts with credentials chosen by its real owner.
    adminAccounts.clear();
    adminAccounts.add(
      AdminAccountRecord(
        id: 'admin-owner',
        roleKey: 'owner',
        email: normalizedEmail,
        password: password,
        pin: pin,
        phone: phone.trim(),
        nameAr: name.trim().isEmpty ? 'المالك' : name.trim(),
        nameEn: name.trim().isEmpty ? 'Owner' : name.trim(),
      ),
    );
    _recordAudit(
      actorName: name.trim().isEmpty ? 'Owner' : name.trim(),
      actorRole: 'owner',
      action: 'first_run_owner_created',
      targetType: 'management_account',
      targetId: 'admin-owner',
      description: 'Owner account created after successful THAMAN subscription activation',
    );
    await _save();
    notifyListeners();
  }

  Future<void> upsertOwnerCache({
    required String name,
    required String email,
    required String password,
    String phone = '',
    String? pin,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    var owner = adminAccountByRole('owner');
    if (owner == null) {
      owner = AdminAccountRecord(
        id: 'admin-owner',
        roleKey: 'owner',
        email: normalizedEmail,
        password: password,
        pin: (pin != null && RegExp(r'^\d{4}$').hasMatch(pin)) ? pin : '0000',
        phone: phone.trim(),
        nameAr: name.trim().isEmpty ? 'المالك' : name.trim(),
        nameEn: name.trim().isEmpty ? 'Owner' : name.trim(),
      );
      adminAccounts.add(owner);
    } else {
      owner.email = normalizedEmail;
      if (password.isNotEmpty) owner.password = password;
      if (pin != null && RegExp(r'^\d{4}$').hasMatch(pin)) owner.pin = pin;
      owner.phone = phone.trim().isEmpty ? owner.phone : phone.trim();
      owner.nameAr = name.trim().isEmpty ? owner.nameAr : name.trim();
      owner.nameEn = name.trim().isEmpty ? owner.nameEn : name.trim();
      owner.active = true;
    }
    await _save();
    notifyListeners();
  }

  Future<void> updateCachedOwnerPassword(String email, String password) async {
    final owner = adminAccountByRole('owner');
    if (owner == null || owner.email.trim().toLowerCase() != email.trim().toLowerCase()) return;
    if (password.isEmpty) return;
    owner.password = CredentialHash.encode(password);
    await _save();
    notifyListeners();
  }

  bool resetFinancialAccounts({
    required String actorName,
    required String actorRole,
    required String ownerPassword,
    bool alreadyVerified = false,
  }) {
    if (actorRole != 'owner') return false;
    if (!alreadyVerified && !verifyOwnerPassword(ownerPassword)) {
      return false;
    }

    final resetAt = DateTime.now();
    financialResetAt = resetAt;
    for (final customer in customers) {
      customer.balance = 0;
      _customerBalanceBaselines[customer.id] = 0;
    }
    for (final supplier in suppliers) {
      supplier.openingBalance = 0;
    }

    _recordAudit(
      actorName: actorName,
      actorRole: actorRole,
      action: 'financial_accounts_reset',
      targetType: 'financial_system',
      targetId: resetAt.toIso8601String(),
      description:
          'Financial accounts reset to zero. Historical operational records were retained.',
    );
    _forceLocalCloudAuthority = true;
    _changed();
    return true;
  }

  void _recordAudit({
    required String actorName,
    required String actorRole,
    required String action,
    required String targetType,
    required String targetId,
    required String description,
  }) {
    auditLogs.insert(
        0,
        AuditLogRecord(
          id: _id('audit'),
          createdAt: DateTime.now(),
          actorName: actorName,
          actorRole: actorRole,
          action: action,
          targetType: targetType,
          targetId: targetId,
          description: description,
        ));
  }

  void terminateEmployee(String id) {
    final e = employeeOrNull(id);
    if (e == null) return;
    e.active = false;
    e.terminatedAt = DateTime.now();
    if (e.managementOnly && const {'manager', 'accountant'}.contains(e.roleKey)) {
      final account = adminAccountByRole(e.roleKey);
      if (account != null) account.active = false;
    }
    _changed();
  }

  bool deleteEmployee(String id, {required String actorRole}) {
    final e = employeeOrNull(id);
    if (e == null) return false;
    if (e.managementOnly && actorRole != 'owner') return false;
    employees.removeWhere((item) => item.id == id);
    if (e.managementOnly && const {'manager', 'accountant'}.contains(e.roleKey)) {
      adminAccounts.removeWhere((account) => account.roleKey == e.roleKey);
    }
    _recordAudit(
      actorName: actorRole,
      actorRole: actorRole,
      action: 'employee_deleted',
      targetType: 'employee',
      targetId: id,
      description: 'Employee ${e.loginId} deleted; historical attendance and transaction records were retained.',
    );
    _changed();
    return true;
  }

  bool reactivateEmployee(String id) {
    final e = employeeOrNull(id);
    if (e == null) return false;
    final duplicate = activeEmployeeUsingLoginId(e.loginId, exceptEmployeeId: e.id);
    if (duplicate != null) return false;
    e.active = true;
    e.terminatedAt = null;
    if (e.managementOnly && const {'manager', 'accountant'}.contains(e.roleKey)) {
      final account = adminAccountByRole(e.roleKey);
      if (account != null) account.active = true;
    }
    _changed();
    return true;
  }

  void setEmployeeLeave({
    required String employeeId,
    required DateTime start,
    required DateTime end,
    required String type,
    required String createdBy,
    String note = '',
  }) {
    leaves.insert(
        0,
        LeaveRecord(
            id: _id('leave'),
            employeeId: employeeId,
            start: start,
            end: end,
            type: type,
            createdBy: createdBy,
            note: note));
    final e = employeeOrNull(employeeId);
    if (e != null) {
      e.onLeave = true;
      e.leaveUntil = end;
    }
    _changed();
  }

  void clearExpiredLeaves() {
    final now = DateTime.now();
    var changed = false;
    for (final e in employees) {
      if (e.onLeave &&
          e.leaveUntil != null &&
          now.isAfter(e.leaveUntil!.add(const Duration(days: 1)))) {
        e.onLeave = false;
        e.leaveUntil = null;
        changed = true;
      }
    }
    if (changed) _changed();
  }

  MessageRecord sendMessage({
    required String senderId,
    required String senderName,
    required String senderRole,
    required String recipientType,
    required String body,
    String recipientId = '',
    String replyToId = '',
  }) {
    final clean = body.trim();
    if (clean.isEmpty) throw ArgumentError('Message body cannot be empty');
    final message = MessageRecord(
      id: _id('msg'),
      createdAt: DateTime.now(),
      senderId: senderId,
      senderName: senderName,
      senderRole: senderRole,
      recipientType: recipientType,
      recipientId: recipientId,
      body: clean,
      replyToId: replyToId,
    );
    messages.insert(0, message);
    _recordAudit(
      actorName: senderName,
      actorRole: senderRole,
      action: 'send_message',
      targetType: 'message',
      targetId: message.id,
      description:
          'Message sent to $recipientType${recipientId.isEmpty ? '' : ':$recipientId'}',
    );
    _changed();
    return message;
  }

  bool messageVisibleToManagement(MessageRecord message, String roleKey,
      {String readerId = ''}) {
    if (readerId.isNotEmpty && message.hiddenBy.contains(readerId))
      return false;
    // Owner and manager oversee the internal operational channel, including
    // inventory replies and staff broadcasts. Accountant sees only messages
    // addressed to management/accounting or sent by management.
    if (roleKey == 'owner' || roleKey == 'manager') return true;
    if (message.senderRole == 'owner' ||
        message.senderRole == 'manager' ||
        message.senderRole == 'accountant') return true;
    if (message.recipientType == 'management' ||
        message.recipientType == roleKey) return true;
    return false;
  }

  bool messageVisibleToStaff(MessageRecord message, EmployeeRecord employee) {
    if (message.hiddenBy.contains(employee.id)) return false;
    if (message.senderId == employee.id) return true;
    if (message.recipientType == 'all_staff') return true;
    if (message.recipientType == 'employee' &&
        message.recipientId == employee.id) return true;
    if (message.recipientType == 'inventory' && employee.roleKey == 'inventory')
      return true;
    return false;
  }

  List<MessageRecord> messagesForManagement(String roleKey,
          {String readerId = ''}) =>
      messages
          .where(
              (m) => messageVisibleToManagement(m, roleKey, readerId: readerId))
          .toList();

  List<MessageRecord> messagesForEmployee(EmployeeRecord employee) =>
      messages.where((m) => messageVisibleToStaff(m, employee)).toList();

  void markMessageRead(String messageId, String readerId) {
    final message = messages.firstWhere((m) => m.id == messageId);
    if (!message.readBy.contains(readerId)) {
      message.readBy.add(readerId);
      _changed();
    }
  }

  void markMessageUnread(String messageId, String readerId) {
    final message = messages.firstWhere((m) => m.id == messageId);
    if (message.readBy.remove(readerId)) _changed();
  }

  void hideMessageForReader(String messageId, String readerId) {
    final message = messages.firstWhere((m) => m.id == messageId);
    if (!message.hiddenBy.contains(readerId)) {
      message.hiddenBy.add(readerId);
      message.readBy.remove(readerId);
      _changed();
    }
  }

  int unreadManagementMessages(String roleKey, String readerId) => messages
      .where((m) =>
          messageVisibleToManagement(m, roleKey, readerId: readerId) &&
          !m.readBy.contains(readerId) &&
          m.senderId != readerId)
      .length;

  int unreadEmployeeMessages(EmployeeRecord employee) => messages
      .where((m) =>
          messageVisibleToStaff(m, employee) &&
          !m.readBy.contains(employee.id) &&
          m.senderId != employee.id)
      .length;

  String _notificationStateKey(String readerId, String notificationKey) =>
      '$readerId::$notificationKey';

  bool isNotificationUnread(String readerId, String notificationKey) {
    final key = _notificationStateKey(readerId, notificationKey);
    return !readNotifications.contains(key) &&
        !hiddenNotifications.contains(key);
  }

  bool isNotificationHidden(String readerId, String notificationKey) =>
      hiddenNotifications
          .contains(_notificationStateKey(readerId, notificationKey));

  void markNotificationRead(String readerId, String notificationKey) {
    final key = _notificationStateKey(readerId, notificationKey);
    if (readNotifications.add(key)) _changed();
  }

  void markNotificationUnread(String readerId, String notificationKey) {
    final key = _notificationStateKey(readerId, notificationKey);
    final changed =
        readNotifications.remove(key) | hiddenNotifications.remove(key);
    if (changed) _changed();
  }

  void hideNotification(String readerId, String notificationKey) {
    final key = _notificationStateKey(readerId, notificationKey);
    readNotifications.remove(key);
    if (hiddenNotifications.add(key)) _changed();
  }

  RestockRequest createRestockRequest({
    required List<RestockRequestLine> lines,
    required String createdById,
    required String createdByName,
    required String createdByRole,
    String note = '',
    String assignedRole = 'inventory',
  }) {
    if (lines.isEmpty)
      throw ArgumentError('Restock request requires at least one line');
    final request = RestockRequest(
      id: _id('restock'),
      number: 'REQ-${_nextSequenceValue('restock')}',
      createdAt: DateTime.now(),
      createdById: createdById,
      createdByName: createdByName,
      createdByRole: createdByRole,
      lines: List<RestockRequestLine>.from(lines),
      note: note.trim(),
      assignedRole: assignedRole,
    );
    restockRequests.insert(0, request);
    _recordAudit(
      actorName: createdByName,
      actorRole: createdByRole,
      action: 'create_restock_request',
      targetType: 'restock_request',
      targetId: request.id,
      description: '${request.number} with ${request.lines.length} item(s)',
    );
    sendMessage(
      senderId: createdById,
      senderName: createdByName,
      senderRole: createdByRole,
      recipientType: assignedRole == 'inventory' ? 'inventory' : 'all_staff',
      body:
          'طلب توريد ${request.number}: ${request.lines.map((e) => '${e.itemName} × ${e.quantity.toStringAsFixed(e.quantity % 1 == 0 ? 0 : 2)} ${e.unit}').join('، ')}',
    );
    return request;
  }

  RestockRequest createRestockRequestForProduct({
    required ProductModel product,
    required double quantity,
    required String unit,
    required String createdById,
    required String createdByName,
    required String createdByRole,
    String note = '',
  }) {
    return createRestockRequest(
      createdById: createdById,
      createdByName: createdByName,
      createdByRole: createdByRole,
      note: note,
      lines: [
        RestockRequestLine(
          productId: product.id,
          itemName: product.nameAr,
          quantity: quantity,
          unit: unit,
          currentStock: product.stock,
          reorderLevel: product.minStock,
          note: note,
        ),
      ],
    );
  }

  void updateRestockStatus({
    required String requestId,
    required String status,
    required String actorName,
    required String actorRole,
  }) {
    final request = restockRequests.firstWhere((r) => r.id == requestId);
    request.status = status;
    request.updatedAt = DateTime.now();
    _recordAudit(
      actorName: actorName,
      actorRole: actorRole,
      action: 'update_restock_status',
      targetType: 'restock_request',
      targetId: request.id,
      description: '${request.number} -> $status',
    );
    if (actorRole == 'inventory') {
      sendMessage(
        senderId: 'INVENTORY',
        senderName: actorName,
        senderRole: 'inventory',
        recipientType: 'management',
        body: 'تحديث طلب التوريد ${request.number}: $status',
      );
    } else {
      _changed();
    }
  }

  List<RestockRequest> get openRestockRequests => restockRequests
      .where((r) => r.status != 'received' && r.status != 'cancelled')
      .toList();

  ProductNote addProductNote({
    required String productId,
    required String text,
    required String audience,
    required String createdBy,
  }) {
    final note = ProductNote(
        id: _id('note'),
        productId: productId,
        text: text,
        audience: audience,
        createdBy: createdBy,
        createdAt: DateTime.now());
    productNotes.insert(0, note);
    _changed();
    return note;
  }

  List<ProductNote> notesForProduct(String productId, {String? audience}) {
    return productNotes.where((n) {
      if (!n.active || n.productId != productId) return false;
      if (audience == null) return true;
      return n.audience == 'both' || n.audience == audience;
    }).toList();
  }

  void dismissProductNote(String id) {
    final note = productNotes.firstWhere((n) => n.id == id);
    note.active = false;
    _changed();
  }

  void addExistingStockCountLines(
      String sessionId, Iterable<String> productIds) {
    final session = stockCounts.firstWhere((item) => item.id == sessionId);
    if (session.status == 'completed') return;
    final existing = session.lines.map((line) => line.productId).toSet();
    for (final productId in productIds) {
      if (existing.contains(productId)) continue;
      final p = productOrNull(productId);
      if (p == null || !p.active) continue;
      session.lines.add(StockCountLine(
          productId: p.id,
          itemName: p.nameAr,
          expected: p.stock,
          actual: 0,
          countUnit: p.baseUnit,
          unitsPerCountUnit: 1,
          enteredQuantity: 0,
          counted: false));
      existing.add(productId);
    }
    _changed();
  }

  ProductModel? addManualStockCountLine(
      String sessionId, String itemName, String sku) {
    final session = stockCounts.firstWhere((s) => s.id == sessionId);
    final cleanSku = sku.trim();
    if (session.status != 'open' ||
        itemName.trim().isEmpty ||
        cleanSku.isEmpty ||
        skuExists(cleanSku)) {
      return null;
    }
    final p = createManualProduct(
        name: itemName.trim(), sku: cleanSku, openingStock: 0);
    session.lines.add(StockCountLine(
        productId: p.id,
        itemName: p.nameAr,
        expected: 0,
        actual: 0,
        countUnit: p.baseUnit,
        unitsPerCountUnit: 1,
        enteredQuantity: 0,
        counted: false));
    _changed();
    return p;
  }

  void _syncManagementEmployee(AdminAccountRecord account) {
    if (!const {'manager', 'accountant'}.contains(account.roleKey)) return;
    final id = 'ADMIN-${account.roleKey}';
    var employee = employeeOrNull(id);
    if (employee == null) {
      final prefix = account.roleKey == 'manager' ? 'MGR' : 'ACC';
      var n = 1;
      var loginId = '$prefix-${n.toString().padLeft(3, '0')}';
      while (activeEmployeeUsingLoginId(loginId) != null) {
        n++;
        loginId = '$prefix-${n.toString().padLeft(3, '0')}';
      }
      employee = EmployeeRecord(
        id: id,
        nameAr: account.nameAr,
        nameEn: account.nameEn,
        roleKey: account.roleKey,
        pin: '0000',
        loginId: loginId,
        phone: account.phone,
        branch: settings.branchName,
        shiftStartMinutes: 8 * 60,
        shiftEndMinutes: 16 * 60,
        weeklyOffDay: DateTime.friday,
        managementOnly: true,
      );
      employees.add(employee);
    } else {
      employee.nameAr = account.nameAr;
      employee.nameEn = account.nameEn;
      employee.phone = account.phone;
      employee.roleKey = account.roleKey;
      employee.managementOnly = true;
      employee.active = account.active;
    }
  }

  void _ensureManagementEmployees() {
    for (final role in const ['manager', 'accountant']) {
      final account = adminAccountByRole(role);
      if (account != null) _syncManagementEmployee(account);
    }
  }

  EmployeeRecord addEmployee({
    required String id,
    required String nameAr,
    required String nameEn,
    required String roleKey,
    required String pin,
    String? loginId,
    String phone = '',
    String branch = 'Main branch',
    int shiftStartMinutes = 480,
    int shiftEndMinutes = 960,
    int weeklyOffDay = DateTime.friday,
    double salary = 0,
    int salaryPayDay = 1,
    bool managementOnly = false,
  }) {
    if (employeeOrNull(id) != null) throw StateError('Employee ID already exists');
    final requestedLogin = (loginId ?? id).trim().toUpperCase();
    if (activeEmployeeUsingLoginId(requestedLogin) != null) throw StateError('Employee login ID already exists');
    final employee = EmployeeRecord(
      id: id,
      nameAr: nameAr,
      nameEn: nameEn,
      roleKey: roleKey,
      pin: pin,
      loginId: loginId ?? id,
      phone: phone,
      branch: branch,
      shiftStartMinutes: shiftStartMinutes,
      shiftEndMinutes: shiftEndMinutes,
      weeklyOffDay: weeklyOffDay,
      salary: salary,
      salaryPayDay: salaryPayDay,
      managementOnly: managementOnly,
    );
    employees.add(employee);
    _changed();
    return employee;
  }

  AssetRecord addAsset(
      {required String name,
      required String category,
      required DateTime purchaseDate,
      required double purchasePrice,
      required double annualDepreciationRate,
      String note = ''}) {
    final asset = AssetRecord(
        id: _id('asset'),
        name: name,
        category: category,
        purchaseDate: purchaseDate,
        purchasePrice: purchasePrice,
        annualDepreciationRate: annualDepreciationRate,
        note: note);
    assets.insert(0, asset);
    _postJournal(
        date: DateTime.now(),
        reference: 'ASSET-${asset.id}',
        description: 'Asset purchase $name',
        sourceType: 'asset',
        sourceId: asset.id,
        lines: [
          JournalLine(
              accountCode: '1500',
              accountName: accountName('1500'),
              debit: purchasePrice),
          JournalLine(
              accountCode: '1000',
              accountName: accountName('1000'),
              credit: purchasePrice)
        ]);
    _changed();
    return asset;
  }

  void setAssetActive(String id, bool active) {
    final asset = assets.firstWhere((a) => a.id == id);
    asset.active = active;
    _changed();
  }

  void updateSettings({
    String? storeName,
    String? currency,
    String? branchName,
    double? taxPercent,
    String? receiptFooter,
    bool? allowCashierReturns,
    bool? requireClockOutConfirmation,
    bool? lowStockNotifications,
    bool? taskNotifications,
  }) {
    if (storeName != null) settings.storeName = storeName;
    if (currency != null) settings.currency = currency;
    if (branchName != null) settings.branchName = branchName;
    if (taxPercent != null) settings.taxPercent = taxPercent;
    if (receiptFooter != null) settings.receiptFooter = receiptFooter;
    if (allowCashierReturns != null)
      settings.allowCashierReturns = allowCashierReturns;
    if (requireClockOutConfirmation != null)
      settings.requireClockOutConfirmation = requireClockOutConfirmation;
    if (lowStockNotifications != null)
      settings.lowStockNotifications = lowStockNotifications;
    if (taskNotifications != null)
      settings.taskNotifications = taskNotifications;
    _changed();
  }

  Future<bool> resetBusinessData({
    required String actorRole,
    required String ownerPassword,
    bool alreadyVerified = false,
  }) async {
    if (actorRole != 'owner') return false;
    if (!alreadyVerified && !verifyOwnerPassword(ownerPassword)) {
      return false;
    }
    final managementAccounts = adminAccounts
        .map((account) => AdminAccountRecord.fromJson(account.toJson()))
        .toList();
    _clearAll();
    adminAccounts.addAll(managementAccounts);
    _forceLocalCloudAuthority = true;
    await _save();
    // This is an intentional reset, so the pre-reset local backup must not be
    // treated as a disaster-recovery candidate later. Cloud sync still sees
    // the normal baseline and propagates the intentional deletions.
    await LocalStateDatabase.instance.clearBackup();
    notifyListeners();
    unawaited(syncFromCloudAfterValidation());
    return true;
  }


  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idRandom.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}';

  void _clearAll() {
    products.clear();
    invoices.clear();
    heldSales.clear();
    returns.clear();
    stockMovements.clear();
    attendance.clear();
    overtimeRecords.clear();
    employeeAdvances.clear();
    tasks.clear();
    employees.clear();
    adminAccounts.clear();
    auditLogs.clear();
    leaves.clear();
    purchases.clear();
    purchaseReturns.clear();
    productNotes.clear();
    customers.clear();
    suppliers.clear();
    supplierPayments.clear();
    customerPayments.clear();
    expenses.clear();
    stockCounts.clear();
    assets.clear();
    messages.clear();
    restockRequests.clear();
    journalEntries.clear();
    readNotifications.clear();
    hiddenNotifications.clear();
    _stockBaselines.clear();
    _customerBalanceBaselines.clear();
    _sequenceEnds.clear();
    settings = StoreSettings();
    financialResetAt = null;
    _invoiceSerial = 1000;
    _purchaseSerial = 2000;
    _stockCountSerial = 0;
    _productSerial = 0;
    _restockSerial = 3000;
    _journalSerial = 0;
    _customerSerial = 0;
    _supplierSerial = 0;
  }

  void _changed() {
    if (_applyingCloudState) {
      notifyListeners();
      return;
    }
    _mutationGen++;
    notifyListeners();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 180), () {
      _save();
    });
  }

  void _migrateLocalCredentials() {
    for (final employee in employees) {
      if (CredentialHash.needsUpgrade(employee.pin)) {
        employee.pin = CredentialHash.encode(employee.pin);
      }
    }
    for (final account in adminAccounts) {
      if (CredentialHash.needsUpgrade(account.password)) {
        account.password = CredentialHash.encode(account.password);
      }
      if (CredentialHash.needsUpgrade(account.pin)) {
        account.pin = CredentialHash.encode(account.pin);
      }
    }
  }

  Future<void> _save({bool scheduleCloud = true}) async {
    _ensureManagementEmployees();
    _migrateLocalCredentials();
    _ensureDerivedBaselines();
    await _persistMap(_serializeState(), scheduleCloud: scheduleCloud);
  }

  Map<String, dynamic> _serializeState() => <String, dynamic>{
        'invoiceSerial': _invoiceSerial,
        'purchaseSerial': _purchaseSerial,
        'stockCountSerial': _stockCountSerial,
        'productSerial': _productSerial,
        'restockSerial': _restockSerial,
        'journalSerial': _journalSerial,
        'customerSerial': _customerSerial,
        'supplierSerial': _supplierSerial,
        'sequenceEnds': _sequenceEnds,
        'financialResetAt': financialResetAt?.toIso8601String(),
        'stockBaselines': _stockBaselines,
        'customerBalanceBaselines': _customerBalanceBaselines,
        'products': products.map((e) => e.toJson()).toList(),
        'invoices': invoices.map((e) => e.toJson()).toList(),
        'heldSales': heldSales.map((e) => e.toJson()).toList(),
        'returns': returns.map((e) => e.toJson()).toList(),
        'stockMovements': stockMovements.map((e) => e.toJson()).toList(),
        'attendance': attendance.map((e) => e.toJson()).toList(),
        'overtimeRecords': overtimeRecords.map((e) => e.toJson()).toList(),
        'employeeAdvances': employeeAdvances.map((e) => e.toJson()).toList(),
        'tasks': tasks.map((e) => e.toJson()).toList(),
        'employees': employees.map((e) => e.toJson()).toList(),
        'adminAccounts': adminAccounts.map((e) => e.toJson()).toList(),
        'auditLogs': auditLogs.map((e) => e.toJson()).toList(),
        'leaves': leaves.map((e) => e.toJson()).toList(),
        'purchases': purchases.map((e) => e.toJson()).toList(),
        'purchaseReturns': purchaseReturns.map((e) => e.toJson()).toList(),
        'productNotes': productNotes.map((e) => e.toJson()).toList(),
        'customers': customers.map((e) => e.toJson()).toList(),
        'suppliers': suppliers.map((e) => e.toJson()).toList(),
        'supplierPayments': supplierPayments.map((e) => e.toJson()).toList(),
        'customerPayments': customerPayments.map((e) => e.toJson()).toList(),
        'expenses': expenses.map((e) => e.toJson()).toList(),
        'stockCounts': stockCounts.map((e) => e.toJson()).toList(),
        'assets': assets.map((e) => e.toJson()).toList(),
        'messages': messages.map((e) => e.toJson()).toList(),
        'restockRequests': restockRequests.map((e) => e.toJson()).toList(),
        'journalEntries': journalEntries.map((e) => e.toJson()).toList(),
        'readNotifications': readNotifications.toList(),
        'hiddenNotifications': hiddenNotifications.toList(),
        'settings': settings.toJson(),
      };

  Future<void> _persistMap(
    Map<String, dynamic> data, {
    bool scheduleCloud = true,
    bool rollBackup = true,
  }) async {
    final encoded = jsonEncode(data);
    final digest = sha256.convert(utf8.encode(encoded)).toString();
    await LocalStateDatabase.instance.writeState(
      encoded,
      digest,
      rollBackup: rollBackup,
    );
    if (scheduleCloud) _scheduleCloudPush();
  }

  bool _isValidPayload(String raw, String? checksum) {
    if (checksum == null || checksum.isEmpty) return true; // legacy V9.3 state
    return sha256.convert(utf8.encode(raw)).toString() == checksum;
  }

  void _restore(Map<String, dynamic> data) {
    _clearAll();
    _invoiceSerial = (data['invoiceSerial'] as num?)?.toInt() ?? 1000;
    _purchaseSerial = (data['purchaseSerial'] as num?)?.toInt() ?? 2000;
    _stockCountSerial = (data['stockCountSerial'] as num?)?.toInt() ?? 0;
    _productSerial = (data['productSerial'] as num?)?.toInt() ?? 0;
    _restockSerial = (data['restockSerial'] as num?)?.toInt() ?? 3000;
    _journalSerial = (data['journalSerial'] as num?)?.toInt() ?? 0;
    _customerSerial = (data['customerSerial'] as num?)?.toInt() ?? 0;
    _supplierSerial = (data['supplierSerial'] as num?)?.toInt() ?? 0;
    if (data['sequenceEnds'] is Map) {
      _sequenceEnds.addAll((data['sequenceEnds'] as Map).map(
        (key, value) => MapEntry('$key', (value as num).toInt()),
      ));
    }
    if (data['stockBaselines'] is Map) {
      _stockBaselines.addAll((data['stockBaselines'] as Map).map(
        (key, value) => MapEntry('$key', (value as num).toInt()),
      ));
    }
    if (data['customerBalanceBaselines'] is Map) {
      _customerBalanceBaselines.addAll(
        (data['customerBalanceBaselines'] as Map).map(
          (key, value) => MapEntry('$key', (value as num).toDouble()),
        ),
      );
    }
    final resetRaw = data['financialResetAt'] as String?;
    financialResetAt = resetRaw == null || resetRaw.isEmpty
        ? null
        : DateTime.tryParse(resetRaw);

    products.addAll(_list(data['products'], ProductModel.fromJson));
    invoices.addAll(_list(data['invoices'], SaleInvoice.fromJson));
    heldSales.addAll(_list(data['heldSales'], HeldSale.fromJson));
    returns.addAll(_list(data['returns'], ReturnRecord.fromJson));
    stockMovements
        .addAll(_list(data['stockMovements'], StockMovement.fromJson));
    attendance.addAll(_list(data['attendance'], AttendanceRecord.fromJson));
    overtimeRecords.addAll(_list(data['overtimeRecords'], OvertimeRecord.fromJson));
    employeeAdvances.addAll(_list(data['employeeAdvances'], EmployeeAdvanceRecord.fromJson));
    tasks.addAll(_list(data['tasks'], TaskRecord.fromJson));
    employees.addAll(_list(data['employees'], EmployeeRecord.fromJson));
    adminAccounts
        .addAll(_list(data['adminAccounts'], AdminAccountRecord.fromJson));
    auditLogs.addAll(_list(data['auditLogs'], AuditLogRecord.fromJson));
    leaves.addAll(_list(data['leaves'], LeaveRecord.fromJson));
    purchases.addAll(_list(data['purchases'], PurchaseReceipt.fromJson));
    purchaseReturns.addAll(
        _list(data['purchaseReturns'], PurchaseReturnRecord.fromJson));
    productNotes.addAll(_list(data['productNotes'], ProductNote.fromJson));
    customers.addAll(_list(data['customers'], CustomerRecord.fromJson));
    suppliers.addAll(_list(data['suppliers'], SupplierRecord.fromJson));
    supplierPayments.addAll(
        _list(data['supplierPayments'], SupplierPaymentRecord.fromJson));
    customerPayments.addAll(
        _list(data['customerPayments'], CustomerPaymentRecord.fromJson));
    expenses.addAll(_list(data['expenses'], ExpenseRecord.fromJson));
    if (suppliers.isEmpty) {
      final names = purchases
          .map((p) => p.supplier)
          .where((n) => n.trim().isNotEmpty)
          .toSet();
      for (final name in names) {
        ensureSupplier(name);
      }
    }
    stockCounts.addAll(_list(data['stockCounts'], StockCountSession.fromJson));
    assets.addAll(_list(data['assets'], AssetRecord.fromJson));
    messages.addAll(_list(data['messages'], MessageRecord.fromJson));
    restockRequests
        .addAll(_list(data['restockRequests'], RestockRequest.fromJson));
    journalEntries.addAll(_list(data['journalEntries'], JournalEntry.fromJson));
    readNotifications.addAll(((data['readNotifications'] as List?) ?? const [])
        .map((e) => e.toString()));
    hiddenNotifications.addAll(
        ((data['hiddenNotifications'] as List?) ?? const [])
            .map((e) => e.toString()));
    settings = data['settings'] is Map
        ? StoreSettings.fromJson(
            (data['settings'] as Map).cast<String, dynamic>())
        : StoreSettings();
    _ensureManagementEmployees();
    _autoCloseExpiredAttendance();
    _syncLocalSerialMinimums();
    if (journalEntries.isEmpty && financialResetAt == null) {
      _rebuildJournalFromCurrentState();
    }
  }

  Map<String, dynamic> _captureLocalMeta() => <String, dynamic>{
        'invoiceSerial': _invoiceSerial,
        'purchaseSerial': _purchaseSerial,
        'stockCountSerial': _stockCountSerial,
        'productSerial': _productSerial,
        'restockSerial': _restockSerial,
        'journalSerial': _journalSerial,
        'customerSerial': _customerSerial,
        'supplierSerial': _supplierSerial,
        'sequenceEnds': Map<String, int>.from(_sequenceEnds),
      };

  void _restoreLocalMeta(Map<String, dynamic> meta) {
    _invoiceSerial = (meta['invoiceSerial'] as num?)?.toInt() ?? _invoiceSerial;
    _purchaseSerial =
        (meta['purchaseSerial'] as num?)?.toInt() ?? _purchaseSerial;
    _stockCountSerial =
        (meta['stockCountSerial'] as num?)?.toInt() ?? _stockCountSerial;
    _productSerial = (meta['productSerial'] as num?)?.toInt() ?? _productSerial;
    _restockSerial = (meta['restockSerial'] as num?)?.toInt() ?? _restockSerial;
    _journalSerial = (meta['journalSerial'] as num?)?.toInt() ?? _journalSerial;
    _customerSerial = (meta['customerSerial'] as num?)?.toInt() ?? _customerSerial;
    _supplierSerial = (meta['supplierSerial'] as num?)?.toInt() ?? _supplierSerial;
    _sequenceEnds.clear();
    if (meta['sequenceEnds'] is Map) {
      _sequenceEnds.addAll((meta['sequenceEnds'] as Map).map(
        (key, value) => MapEntry('$key', (value as num).toInt()),
      ));
    }
    _syncLocalSerialMinimums();
  }

  int _operationalCount(Map<String, dynamic> state) {
    var count = 0;
    for (final key in const [
      'products',
      'invoices',
      'returns',
      'stockMovements',
      'purchases',
      'purchaseReturns',
      'customers',
      'suppliers',
      'customerPayments',
      'supplierPayments',
      'expenses',
      'journalEntries',
      'employees',
      'adminAccounts',
      'assets',
    ]) {
      final value = state[key];
      if (value is List) count += value.length;
    }
    return count;
  }

  void _ensureDerivedBaselines() {
    for (final product in products) {
      if (_stockBaselines.containsKey(product.id)) continue;
      final movementTotal = stockMovements
          .where((m) => m.productId == product.id)
          .fold<int>(0, (sum, m) => sum + m.quantity);
      _stockBaselines[product.id] = product.stock - movementTotal;
    }

    for (final customer in customers) {
      if (_customerBalanceBaselines.containsKey(customer.id)) continue;
      _customerBalanceBaselines[customer.id] =
          customer.balance - _customerOperationalNet(customer.id);
    }
  }

  void _recomputeDerivedState() {
    for (final product in products) {
      final baseline = _stockBaselines[product.id];
      if (baseline == null) continue;
      final movementTotal = stockMovements
          .where((m) => m.productId == product.id)
          .fold<int>(0, (sum, m) => sum + m.quantity);
      product.stock = baseline + movementTotal;
    }

    for (final customer in customers) {
      final baseline = _customerBalanceBaselines[customer.id];
      if (baseline == null) continue;
      customer.balance = (baseline + _customerOperationalNet(customer.id))
          .clamp(0, double.infinity)
          .toDouble();
    }
  }

  double _customerOperationalNet(String customerId) {
    final resetAt = financialResetAt;
    bool current(DateTime date) => resetAt == null || !date.isBefore(resetAt);
    final customerInvoices = invoices
        .where((i) =>
            !i.voided && i.customerId == customerId && current(i.createdAt))
        .toList();
    final invoiceIds = customerInvoices.map((i) => i.id).toSet();
    final debt = customerInvoices.fold<double>(0, (sum, i) => sum + i.dueAmount);
    final credits = returns
        .where((r) => invoiceIds.contains(r.invoiceId) && current(r.createdAt))
        .fold<double>(0, (sum, r) => sum + r.receivableReduction);
    final payments = customerPayments
        .where((p) => p.customerId == customerId && current(p.createdAt))
        .fold<double>(0, (sum, p) => sum + p.amount);
    return debt - credits - payments;
  }

  void _syncLocalSerialMinimums() {
    int serialFrom(String value) =>
        int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    for (final invoice in invoices) {
      final value = serialFrom(invoice.number);
      if (value > _invoiceSerial) _invoiceSerial = value;
    }
    for (final purchase in purchases) {
      final value = serialFrom(purchase.number);
      if (value > _purchaseSerial) _purchaseSerial = value;
    }
    for (final count in stockCounts) {
      final value = serialFrom(count.number);
      if (value > _stockCountSerial) _stockCountSerial = value;
    }
    for (final request in restockRequests) {
      final value = serialFrom(request.number);
      if (value > _restockSerial) _restockSerial = value;
    }
    for (final entry in journalEntries) {
      final value = serialFrom(entry.number);
      if (value > _journalSerial) _journalSerial = value;
    }
    for (final customer in customers) {
      final value = serialFrom(customer.accountNumber);
      if (value > _customerSerial) _customerSerial = value;
    }
    for (final supplier in suppliers) {
      final value = serialFrom(supplier.accountNumber);
      if (value > _supplierSerial) _supplierSerial = value;
    }
  }

  Future<void> _ensureSequenceCapacity(SubscriptionRepository repository) async {
    for (final config in const [
      ('invoice', 100),
      ('purchase', 100),
      ('stock_count', 50),
      ('product', 100),
      ('restock', 100),
      ('journal', 500),
      ('customer', 100),
      ('supplier', 100),
    ]) {
      await _ensureSequence(repository, config.$1, config.$2);
    }
    await _persistMap(_serializeState(), scheduleCloud: false);
  }

  Future<void> _ensureSequence(
    SubscriptionRepository repository,
    String kind,
    int blockSize,
  ) async {
    final current = _serialFor(kind);
    final end = _sequenceEnds[kind] ?? 0;
    final threshold = blockSize >= 100 ? 20 : 10;
    if (end > current && end - current > threshold) return;
    final block = await repository.reserveSequenceBlock(
      kind,
      blockSize: blockSize,
      observedMinimum: current,
    );
    if (block.start <= 0 || block.end < block.start) return;
    if (current < block.start) _setSerial(kind, block.start - 1);
    _sequenceEnds[kind] = block.end;
  }

  int _serialFor(String kind) => switch (kind) {
        'invoice' => _invoiceSerial,
        'purchase' => _purchaseSerial,
        'stock_count' => _stockCountSerial,
        'product' => _productSerial,
        'restock' => _restockSerial,
        'journal' => _journalSerial,
        'customer' => _customerSerial,
        'supplier' => _supplierSerial,
        _ => 0,
      };

  void _setSerial(String kind, int value) {
    switch (kind) {
      case 'invoice':
        _invoiceSerial = value;
        break;
      case 'purchase':
        _purchaseSerial = value;
        break;
      case 'stock_count':
        _stockCountSerial = value;
        break;
      case 'product':
        _productSerial = value;
        break;
      case 'restock':
        _restockSerial = value;
        break;
      case 'journal':
        _journalSerial = value;
        break;
      case 'customer':
        _customerSerial = value;
        break;
      case 'supplier':
        _supplierSerial = value;
        break;
    }
  }

  int _nextSequenceValue(String kind) {
    final current = _serialFor(kind);
    final next = current + 1;
    final end = _sequenceEnds[kind] ?? 0;
    if (end > 0 && next > end) {
      throw StateError('sequence_block_exhausted:$kind');
    }
    _setSerial(kind, next);
    return next;
  }

  void persistCredentialUpgrade() {
    _save();
  }

  void _rebuildJournalFromCurrentState() {
    journalEntries.clear();
    _journalSerial = 0;
    // Opening balances make restored data reconcile without rewriting source records.
    final currentInventory = inventoryValue;
    if (currentInventory > 0)
      _postJournal(
          date: DateTime.now(),
          reference: 'OPEN-INV',
          description: 'Opening inventory reconciliation',
          sourceType: 'opening',
          sourceId: 'inventory',
          lines: [
            JournalLine(
                accountCode: '1200',
                accountName: accountName('1200'),
                debit: currentInventory),
            JournalLine(
                accountCode: '3000',
                accountName: accountName('3000'),
                credit: currentInventory)
          ]);
    final ar = totalReceivables;
    if (ar > 0)
      _postJournal(
          date: DateTime.now(),
          reference: 'OPEN-AR',
          description: 'Opening receivables reconciliation',
          sourceType: 'opening',
          sourceId: 'receivables',
          lines: [
            JournalLine(
                accountCode: '1100',
                accountName: accountName('1100'),
                debit: ar),
            JournalLine(
                accountCode: '3000',
                accountName: accountName('3000'),
                credit: ar)
          ]);
    final ap = totalPayables;
    if (ap > 0)
      _postJournal(
          date: DateTime.now(),
          reference: 'OPEN-AP',
          description: 'Opening payables reconciliation',
          sourceType: 'opening',
          sourceId: 'payables',
          lines: [
            JournalLine(
                accountCode: '3000',
                accountName: accountName('3000'),
                debit: ap),
            JournalLine(
                accountCode: '2000',
                accountName: accountName('2000'),
                credit: ap)
          ]);
    final fixed = assetBookValue;
    if (fixed > 0)
      _postJournal(
          date: DateTime.now(),
          reference: 'OPEN-ASSET',
          description: 'Opening fixed assets',
          sourceType: 'opening',
          sourceId: 'assets',
          lines: [
            JournalLine(
                accountCode: '1500',
                accountName: accountName('1500'),
                debit: fixed),
            JournalLine(
                accountCode: '3000',
                accountName: accountName('3000'),
                credit: fixed)
          ]);
  }

  List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) fromJson) {
    return ((raw as List?) ?? [])
        .map((e) => fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  receivePurchase(
      {required List<PurchaseLine> lines,
      required String supplierName,
      required String employeeId,
      required String employeeName,
      required int amountPaid}) {}
}
