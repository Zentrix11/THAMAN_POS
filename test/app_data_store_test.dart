import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaman_pos/core/printing/print_document.dart';
import 'package:thaman_pos/core/printing/print_templates.dart';
import 'package:thaman_pos/core/app_controller.dart';
import 'package:thaman_pos/core/app_strings.dart';
import 'package:thaman_pos/core/credential_hash.dart';
import 'package:thaman_pos/features/management/widgets/management_widgets.dart';
import 'package:thaman_pos/data/app_data_store.dart';
import 'package:thaman_pos/data/local_state_database.dart';
import 'package:thaman_pos/data/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory testDocumentsDirectory;

  setUpAll(() async {
    LocalStateDatabase.instance.setEncryptionKeyForTesting(List<int>.generate(32, (i) => i));
    testDocumentsDirectory = await Directory.systemTemp.createTemp('thaman_pos_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getApplicationSupportDirectory':
        case 'getTemporaryDirectory':
          return testDocumentsDirectory.path;
        case 'getDownloadsDirectory':
          return testDocumentsDirectory.path;
        default:
          return testDocumentsDirectory.path;
      }
    });
  });

  tearDownAll(() async {
    await LocalStateDatabase.instance.resetForTesting();
    LocalStateDatabase.instance.setEncryptionKeyForTesting(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await testDocumentsDirectory.exists()) {
      await testDocumentsDirectory.delete(recursive: true);
    }
  });

  Future<AppDataStore> freshStore() async {
    await LocalStateDatabase.instance.resetForTesting();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = AppDataStore.instance;
    await store.initialize();
    return store;
  }

  ProductModel addProduct(AppDataStore store, {String id = 'p1', int stock = 20}) {
    final p = ProductModel(
      id: id,
      nameAr: 'صنف اختبار',
      nameEn: 'Test item',
      sku: 'SKU-$id',
      barcode: '123456789$id',
      categoryAr: 'اختبار',
      categoryEn: 'Test',
      price: 10,
      cost: 6,
      stock: stock,
      minStock: 2,
    );
    store.products.add(p);
    return p;
  }

  EmployeeRecord addEmployee(AppDataStore store) {
    final e = EmployeeRecord(
      id: 'E-1',
      nameAr: 'موظف اختبار',
      nameEn: 'Test Employee',
      roleKey: 'inventory',
      pin: '1111',
      shiftStartMinutes: 480,
      shiftEndMinutes: 960,
      salary: 1200,
      salaryPayDay: 25,
    );
    store.employees.add(e);
    return e;
  }

  void expectPrintDocumentValid(PrintDocument d) {
    expect(d.title.trim(), isNotEmpty);
    expect(d.headers, isNotEmpty);
    for (final row in d.rows) {
      expect(row.length, d.headers.length,
          reason: 'Print row/header mismatch in ${d.title}');
    }
  }

  test('production first run contains no business/demo data', () async {
    final store = await freshStore();
    expect(store.products, isEmpty);
    expect(store.invoices, isEmpty);
    expect(store.heldSales, isEmpty);
    expect(store.returns, isEmpty);
    expect(store.stockMovements, isEmpty);
    expect(store.attendance, isEmpty);
    expect(store.tasks, isEmpty);
    expect(store.employees, isEmpty);
    expect(store.customers, isEmpty);
    expect(store.suppliers, isEmpty);
    expect(store.purchases, isEmpty);
    expect(store.expenses, isEmpty);
    expect(store.assets, isEmpty);
    expect(store.stockCounts, isEmpty);
    expect(store.journalEntries, isEmpty);
    expect(store.adminAccounts, isEmpty);
  });


  test('owner account is provisioned only after first-run activation flow', () async {
    final store = await freshStore();
    expect(store.adminAccounts, isEmpty);
    await store.provisionOwnerAccount(
      name: 'مالك المتجر',
      email: 'owner@example.com',
      password: 'StrongPass123',
      pin: '2468',
    );
    expect(store.adminAccounts.length, 1);
    final owner = store.adminAccountByRole('owner');
    expect(owner, isNotNull);
    expect(owner!.email, 'owner@example.com');
    expect(CredentialHash.verify('2468', owner.pin), isTrue);
    expect(CredentialHash.isHash(owner.pin), isTrue);
    expect(owner.nameAr, 'مالك المتجر');
    expect(owner.nameEn, 'مالك المتجر');
  });

  test('management accounts keep the entered user name for personalized greeting', () async {
    final store = await freshStore();
    await store.provisionOwnerAccount(
      name: 'عمر',
      email: 'owner@example.com',
      password: 'StrongPass123',
      pin: '2468',
    );
    final created = store.updateAdminCredentials(
      targetRole: 'manager',
      displayName: 'أحمد',
      email: 'manager@example.com',
      password: 'ManagerPass123',
      pin: '1357',
      actorName: 'عمر',
      actorRole: 'owner',
    );
    expect(created, isTrue);
    final manager = store.adminAccountByRole('manager');
    expect(manager, isNotNull);
    expect(manager!.nameAr, 'أحمد');
    expect(manager.nameEn, 'أحمد');
  });


  test('owner and manager can add a supplier while other roles cannot', () async {
    final store = await freshStore();
    final supplier = store.addSupplier(
      name: 'مورد الاختبار',
      phone: '0599000000',
      address: 'غزة',
      openingBalance: 250,
      actorName: 'Owner',
      actorRole: 'owner',
    );
    expect(supplier, isNotNull);
    expect(supplier!.accountNumber, startsWith('S-'));
    expect(store.supplierBalance(supplier.id), 250);
    expect(store.journalEntries.any((entry) =>
        entry.sourceType == 'supplier_opening_balance' && entry.balanced), isTrue);

    final duplicate = store.addSupplier(
      name: 'مورد الاختبار',
      actorName: 'Owner',
      actorRole: 'owner',
    );
    expect(duplicate, isNull);

    final denied = store.addSupplier(
      name: 'مورد غير مصرح',
      actorName: 'Cashier',
      actorRole: 'cashier',
    );
    expect(denied, isNull);
  });

  test('sale and return update stock without demo dependencies', () async {
    final store = await freshStore();
    final p = addProduct(store);
    final invoice = store.completeSale(
      cart: <String, int>{p.id: 2},
      cashier: 'QA',
      cashierId: 'C-1',
      paymentMethod: 'Cash',
    );
    expect(p.stock, 18);
    final returned = store.returnSale(
      invoice: invoice,
      quantities: <String, int>{p.id: 1},
      reason: 'QA return',
      refundMethod: 'Cash',
      processedBy: 'QA',
      processedById: 'C-1',
    );
    expect(returned, isNotNull);
    expect(p.stock, 19);
    expect(store.journalEntries.every((e) => e.balanced), isTrue);
  });

  test('blind stock count changes stock only after management approval', () async {
    final store = await freshStore();
    final p = addProduct(store, stock: 20);
    final session = store.startStockCount(
      employeeId: 'I-1',
      employeeName: 'Inventory',
      productIds: <String>[p.id],
      requestedByName: 'Owner',
      requestedByRole: 'owner',
    );
    store.updateStockCountLine(session.id, p.id, 18);
    expect(store.submitStockCount(session.id), isTrue);
    expect(p.stock, 20);
    expect(session.status, 'submitted');
    expect(store.approveStockCount(session.id, actorName: 'Owner', actorRole: 'owner'), isTrue);
    expect(p.stock, 18);
    expect(session.status, 'completed');
  });

  test('salary payment is an expense and cannot duplicate same month', () async {
    final store = await freshStore();
    final e = addEmployee(store);
    final month = DateTime(2026, 9, 1);
    final first = store.recordSalaryPayment(
      employeeId: e.id,
      month: month,
      paidBy: 'Accountant',
      actorRole: 'accountant',
    );
    expect(first, isNotNull);
    expect(first!.sourceType, 'salary');
    expect(first.amount, e.salary);
    expect(store.recordSalaryPayment(
      employeeId: e.id,
      month: month,
      paidBy: 'Accountant',
      actorRole: 'accountant',
    ), isNull);
  });

  test('financial reset remains owner-only and accepts trimmed manager password', () async {
    final store = await freshStore();
    await store.provisionOwnerAccount(
      name: 'Owner',
      email: 'owner@example.com',
      password: 'OwnerPass123',
      pin: '2468',
    );
    final managerCreated = store.updateAdminCredentials(
      targetRole: 'manager',
      displayName: 'Manager',
      email: 'manager@example.com',
      password: 'Manager@2026',
      pin: '1357',
      actorName: 'Owner',
      actorRole: 'owner',
    );
    expect(managerCreated, isTrue);
    expect(store.verifyManagerPassword(' Manager@2026 '), isTrue);
    expect(store.resetFinancialAccounts(
      actorName: 'Manager',
      actorRole: 'manager',
      ownerPassword: 'OwnerPass123',
    ), isFalse);
    expect(store.resetFinancialAccounts(
      actorName: 'Owner',
      actorRole: 'owner',
      ownerPassword: ' OwnerPass123 ',
    ), isTrue);
  });


  test('attendance lateness is formatted as hours and minutes', () {
    final controller = AppController();
    final strings = AppStrings(controller);
    expect(formatReadableMinutes(strings, 600), '10 ساعات');
    expect(formatReadableMinutes(strings, 125), 'ساعتين و5 دقائق');
    expect(formatReadableMinutes(strings, 5), '5 دقائق');

    controller.setLanguage(AppLanguage.en);
    expect(formatReadableMinutes(strings, 600), '10 hours');
    expect(formatReadableMinutes(strings, 125), '2 hours and 5 minutes');
  });

  test('inventory staff can create a detailed product through purchasing', () async {
    final store = await freshStore();
    final denied = store.addInventoryPurchaseProduct(
      nameAr: 'ممنوع',
      nameEn: 'Denied',
      sku: 'DENIED-1',
      categoryAr: 'عام',
      categoryEn: 'General',
      salePrice: 10,
      cost: 5,
      actorName: 'Accountant',
      actorRole: 'accountant',
    );
    expect(denied, isNull);

    final product = store.addInventoryPurchaseProduct(
      nameAr: 'منتج مخزون',
      nameEn: 'Inventory Product',
      sku: 'INV-NEW-1',
      barcode: '9988776655',
      categoryAr: 'اختبار',
      categoryEn: 'Test',
      salePrice: 15,
      cost: 6,
      minStock: 3,
      baseUnit: 'piece',
      purchaseUnit: 'carton',
      unitsPerPurchaseUnit: 12,
      actorName: 'Inventory Staff',
      actorRole: 'inventory',
    );
    expect(product, isNotNull);
    expect(product!.stock, 0);
    expect(product.sku, 'INV-NEW-1');
    expect(product.minStock, 3);

    final receipt = store.createPurchase(
      lines: <PurchaseLine>[
        PurchaseLine(
          productId: product.id,
          itemName: product.nameAr,
          quantity: 2,
          unitCost: 72,
          purchaseUnit: 'carton',
          unitsPerPurchaseUnit: 12,
          saleUnit: 'piece',
          salePrice: 15,
        ),
      ],
      supplierName: 'Supplier QA',
      employeeId: 'I-1',
      employeeName: 'Inventory Staff',
      paymentMethod: 'Debt',
      amountPaid: 0,
    );
    expect(receipt.lines.single.baseQuantity, 24);
    expect(product.stock, 24);
    expect(store.journalEntries.every((entry) => entry.balanced), isTrue);
  });

  test('SKU is free-form, preserved exactly, and unique case-insensitively', () async {
    final store = await freshStore();
    final product = store.addManagedProduct(
      nameAr: 'منتج حر الرمز',
      nameEn: 'Free SKU item',
      sku: 'رمز-abC_7/خاص',
      categoryAr: 'اختبار',
      categoryEn: 'Test',
      salePrice: 12,
      cost: 5,
      actorName: 'Owner',
      actorRole: 'owner',
    );
    expect(product, isNotNull);
    expect(product!.sku, 'رمز-abC_7/خاص');
    expect(store.productByBarcodeOrSku('رمز-ABC_7/خاص')?.id, product.id);

    final duplicate = store.addManagedProduct(
      nameAr: 'مكرر',
      nameEn: 'Duplicate',
      sku: 'رمز-ABC_7/خاص',
      categoryAr: 'اختبار',
      categoryEn: 'Test',
      salePrice: 9,
      cost: 4,
      actorName: 'Owner',
      actorRole: 'owner',
    );
    expect(duplicate, isNull);
  });

  test('manual product creation keeps a user-chosen SKU unchanged', () async {
    final store = await freshStore();
    final product = store.createManualProduct(
      name: 'يدوي',
      sku: 'my sku-#42',
    );
    expect(product.sku, 'my sku-#42');
    expect(store.productByBarcodeOrSku('MY SKU-#42')?.id, product.id);
  });

  test('core print templates have consistent columns', () async {
    final store = await freshStore();
    final p = addProduct(store);
    final invoice = store.completeSale(
      cart: <String, int>{p.id: 1},
      cashier: 'QA',
      paymentMethod: 'Cash',
    );
    final session = store.startStockCount(
      employeeId: 'I-1',
      employeeName: 'Inventory',
      productIds: <String>[p.id],
    );
    store.updateStockCountLine(session.id, p.id, p.stock);

    expectPrintDocumentValid(
      ThamanPrintTemplates.saleInvoice(store, invoice, isArabic: true),
    );
    expectPrintDocumentValid(
      ThamanPrintTemplates.saleInvoice(store, invoice, isArabic: false),
    );
    expectPrintDocumentValid(
      ThamanPrintTemplates.stockCountCounterCopy(store, session, isArabic: true),
    );
    expectPrintDocumentValid(
      ThamanPrintTemplates.stockCount(store, session, isArabic: true),
    );
    expectPrintDocumentValid(
      ThamanPrintTemplates.assetsReport(store, isArabic: true),
    );
    expectPrintDocumentValid(
      ThamanPrintTemplates.accountingStatement(store, isArabic: true),
    );
  });

  test('supplier return remaining refund is 9 when agreed is 19 and paid now is 10 on a paid purchase', () async {
    final store = await freshStore();
    final p = addProduct(store, stock: 20);
    final receipt = store.createPurchase(
      lines: <PurchaseLine>[
        PurchaseLine(
          productId: p.id,
          itemName: p.nameAr,
          quantity: 2,
          unitCost: 9.5,
          purchaseUnit: 'piece',
          unitsPerPurchaseUnit: 1,
          saleUnit: 'piece',
          salePrice: 15,
        ),
      ],
      supplierName: 'مورد المرتجع',
      employeeId: 'I-1',
      employeeName: 'Inventory',
      paymentMethod: 'Cash',
      amountPaid: 19,
    );
    expect(store.purchaseOutstanding(receipt), 0);
    expect(p.stock, 22);

    final record = store.returnPurchase(
      purchase: receipt,
      quantities: <String, int>{p.id: 2},
      reason: 'QA supplier return remaining',
      processedBy: 'QA',
      processedById: 'I-1',
      agreedRefundAmount: 19,
      paidNow: 10,
    );
    expect(record, isNotNull);
    expect(record!.agreedAmount, 19);
    expect(record.payableReduction, 0);
    expect(record.cashRefund, 10);
    expect(record.remainingRefund, 9);
    expect(p.stock, 20);
    expect(store.supplierReturnReceivables, 9);
    expect(store.journalEntries.every((e) => e.balanced), isTrue);
    final summary = store.financialSummary();
    expect(summary.purchases, 19);
    expect(summary.purchaseReturns, 19);
    expect(summary.supplierReturnReceivables, 9);
    expect(store.purchasesValue, 19);
    expect(store.purchaseReturnsValue, 19);
    expect(store.accountingSnapshot().receivables, closeTo(9, 0.001));

    expect(
      store.returnPurchase(
        purchase: receipt,
        quantities: <String, int>{p.id: 2},
        reason: 'duplicate',
        processedBy: 'QA',
        processedById: 'I-1',
        agreedRefundAmount: 19,
        paidNow: 10,
      ),
      isNull,
    );
  });

  test('partially paid purchase return settles 10 debt and accepts at most 5 cash', () async {
    final store = await freshStore();
    final p = addProduct(store, stock: 0);
    final receipt = store.createPurchase(
      lines: <PurchaseLine>[
        PurchaseLine(
          productId: p.id,
          itemName: p.nameAr,
          quantity: 1,
          unitCost: 15,
          purchaseUnit: 'carton',
          unitsPerPurchaseUnit: 20,
          saleUnit: 'piece',
          salePrice: 1,
        ),
      ],
      supplierName: 'lion',
      employeeId: 'I-1',
      employeeName: 'Omar',
      paymentMethod: 'Cash',
      amountPaid: 5,
    );
    expect(receipt.total, 15);
    expect(store.purchaseOutstanding(receipt), 10);
    expect(p.stock, 20);

    expect(
      store.returnPurchase(
        purchase: receipt,
        quantities: <String, int>{p.id: 20},
        reason: 'too much cash',
        processedBy: 'QA',
        processedById: 'I-1',
        agreedRefundAmount: 15,
        paidNow: 15,
      ),
      isNull,
    );
    expect(
      store.returnPurchase(
        purchase: receipt,
        quantities: <String, int>{p.id: 20},
        reason: 'agreed covers only the debt',
        processedBy: 'QA',
        processedById: 'I-1',
        agreedRefundAmount: 10,
        paidNow: 5,
      ),
      isNull,
    );

    final record = store.returnPurchase(
      purchase: receipt,
      quantities: <String, int>{p.id: 20},
      reason: 'full carton',
      processedBy: 'QA',
      processedById: 'I-1',
      agreedRefundAmount: 15,
      paidNow: 5,
    );
    expect(record, isNotNull);
    expect(record!.payableReduction, 10);
    expect(record.cashRefund, 5);
    expect(record.remainingRefund, 0);
    expect(store.purchaseOutstanding(receipt), 0);
    expect(p.stock, 0);
    expect(store.journalEntries.every((e) => e.balanced), isTrue);
  });

  test('supplier return remaining is 19 when paid now is 0 and 0 when fully paid', () async {
    final store = await freshStore();
    final p = addProduct(store, stock: 40);
    final unpaid = store.createPurchase(
      lines: <PurchaseLine>[
        PurchaseLine(
          productId: p.id,
          itemName: p.nameAr,
          quantity: 2,
          unitCost: 9.5,
          purchaseUnit: 'piece',
          unitsPerPurchaseUnit: 1,
          saleUnit: 'piece',
          salePrice: 15,
        ),
      ],
      supplierName: 'مورد أ',
      employeeId: 'I-1',
      employeeName: 'Inventory',
      paymentMethod: 'Cash',
      amountPaid: 19,
    );
    final unpaidReturn = store.returnPurchase(
      purchase: unpaid,
      quantities: <String, int>{p.id: 1},
      reason: 'none paid',
      processedBy: 'QA',
      processedById: 'I-1',
      agreedRefundAmount: 19,
      paidNow: 0,
    );
    expect(unpaidReturn, isNotNull);
    expect(unpaidReturn!.remainingRefund, 19);
    expect(unpaidReturn.cashRefund, 0);

    final full = store.createPurchase(
      lines: <PurchaseLine>[
        PurchaseLine(
          productId: p.id,
          itemName: p.nameAr,
          quantity: 2,
          unitCost: 9.5,
          purchaseUnit: 'piece',
          unitsPerPurchaseUnit: 1,
          saleUnit: 'piece',
          salePrice: 15,
        ),
      ],
      supplierName: 'مورد ب',
      employeeId: 'I-1',
      employeeName: 'Inventory',
      paymentMethod: 'Cash',
      amountPaid: 19,
    );
    final fullReturn = store.returnPurchase(
      purchase: full,
      quantities: <String, int>{p.id: 1},
      reason: 'full cash',
      processedBy: 'QA',
      processedById: 'I-1',
      agreedRefundAmount: 19,
      paidNow: 19,
    );
    expect(fullReturn, isNotNull);
    expect(fullReturn!.remainingRefund, 0);
    expect(fullReturn.cashRefund, 19);

    final over = store.returnPurchase(
      purchase: full,
      quantities: <String, int>{p.id: 1},
      reason: 'overpay',
      processedBy: 'QA',
      processedById: 'I-1',
      agreedRefundAmount: 19,
      paidNow: 25,
    );
    expect(over, isNull);
  });

  test('return notice remains printable even if original invoice is unavailable', () async {
    final store = await freshStore();
    final record = ReturnRecord(
      id: 'ret-1',
      invoiceId: 'missing-invoice',
      invoiceNumber: 'INV-404',
      createdAt: DateTime(2026, 9, 5),
      reason: 'QA',
      refundMethod: 'Cash',
      lines: const <InvoiceLine>[
        InvoiceLine(
          productId: 'missing-product',
          nameAr: 'صنف',
          nameEn: 'Item',
          quantity: 1,
          unitPrice: 10,
        ),
      ],
    );
    final doc = ThamanPrintTemplates.returnNotice(store, record, isArabic: true);
    expectPrintDocumentValid(doc);
    expect(doc.metadata.values, contains('-'));
  });

  test('payroll equation is base + overtime - advance', () async {
    final store = await freshStore();
    final e = addEmployee(store);
    e.salary = 1000;
    e.shiftStartMinutes = 8 * 60;
    e.shiftEndMinutes = 16 * 60;
    final month = DateTime(2026, 9, 1);
    final overtime = store.recordOvertime(
      employeeId: e.id,
      startAt: DateTime(2026, 9, 2, 16),
      endAt: DateTime(2026, 9, 4, 16),
      createdBy: 'Owner',
      actorRole: 'owner',
    );
    expect(overtime, isNotNull);
    expect(store.overtimePayFor(e.id, month), closeTo(200, 0.05));
    expect(store.payrollGrossFor(e.id, month), closeTo(1200, 0.05));

    final advance = store.recordEmployeeAdvance(
      employeeId: e.id,
      amount: 500,
      givenBy: 'Accountant',
      actorRole: 'accountant',
    );
    expect(advance, isNotNull);
    expect(store.employeeNetSalaryAfterAdvances(e.id, month), closeTo(700, 0.05));

    final paid = store.recordSalaryPayment(
      employeeId: e.id,
      month: month,
      paidBy: 'Accountant',
      actorRole: 'accountant',
      advanceDeduction: 500,
    );
    expect(paid, isNotNull);
    expect(paid!.amount, closeTo(1200, 0.05));
    expect(store.salaryCashPaidForExpense(paid), closeTo(700, 0.05));
    expect(store.employeeOutstandingAdvance(e.id), closeTo(0, 0.05));
    expect(store.journalEntries.every((entry) => entry.balanced), isTrue);
    expect(store.cashResultForPeriod(), closeTo(-1200, 0.05));
  });

  test('credit sale return reduces receivable and keeps journals balanced', () async {
    final store = await freshStore();
    final p = addProduct(store, stock: 10);
    final customer = store.addCustomer(
      name: 'عميل آجل',
      phone: '0790000001',
      creditAllowed: true,
      creditLimit: 1000,
      actorName: 'Owner',
      actorRole: 'owner',
    );
    expect(customer, isNotNull);
    final invoice = store.completeSale(
      cart: <String, int>{p.id: 2},
      cashier: 'QA',
      cashierId: 'C-1',
      paymentMethod: 'Debt',
      customer: customer!.name,
      customerId: customer.id,
      paidAmount: 0,
    );
    expect(store.invoiceOutstanding(invoice.id), invoice.total);
    expect(customer.balance, invoice.total);
    final returned = store.returnSale(
      invoice: invoice,
      quantities: <String, int>{p.id: 1},
      reason: 'partial credit return',
      refundMethod: 'Cash',
      processedBy: 'QA',
      processedById: 'C-1',
    );
    expect(returned, isNotNull);
    expect(returned!.refundAmount, 0);
    expect(returned.receivableReduction, closeTo(invoice.total / 2, 0.02));
    expect(store.invoiceOutstanding(invoice.id), closeTo(invoice.total / 2, 0.02));
    expect(store.journalEntries.every((entry) => entry.balanced), isTrue);
  });
}
