import '../time_format.dart';
import '../../data/app_data_store.dart';
import '../../data/models.dart';
import 'print_document.dart';

String _dt(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year} ${formatHour12(value)}';
}

String _t(bool ar, String arText, String enText) => ar ? arText : enText;

String _payment(bool ar, String value) {
  return switch (value.trim().toLowerCase()) {
    'cash' => _t(ar, 'نقدي', 'Cash'),
    'card' => _t(ar, 'بطاقة', 'Card'),
    'bank' => _t(ar, 'بنك', 'Bank'),
    'transfer' || 'bank transfer' => _t(ar, 'تحويل بنكي', 'Bank transfer'),
    'debt' || 'credit' => _t(ar, 'آجل', 'Credit'),
    _ => value,
  };
}

String _movement(bool ar, String value) {
  return switch (value.trim().toLowerCase()) {
    'sale' => _t(ar, 'بيع', 'Sale'),
    'return' => _t(ar, 'مرتجع', 'Return'),
    'receive' || 'receiving' => _t(ar, 'استلام', 'Receiving'),
    'purchase' => _t(ar, 'شراء', 'Purchase'),
    'damage' => _t(ar, 'تالف', 'Damage'),
    'transfer' => _t(ar, 'نقل', 'Transfer'),
    'void' => _t(ar, 'إلغاء فاتورة', 'Invoice void'),
    'count' || 'stock_count' || 'count_adjustment' =>
      _t(ar, 'تسوية جرد', 'Stock-count adjustment'),
    'adjustment' => _t(ar, 'تسوية مخزون', 'Stock adjustment'),
    _ => value,
  };
}

String _status(bool ar, String value) {
  return switch (value.trim().toLowerCase()) {
    'pending' => _t(ar, 'قيد الانتظار', 'Pending'),
    'in_progress' || 'in progress' => _t(ar, 'قيد التنفيذ', 'In progress'),
    'completed' => _t(ar, 'مكتمل', 'Completed'),
    'open' => _t(ar, 'مفتوح', 'Open'),
    'closed' => _t(ar, 'مغلق', 'Closed'),
    'requested' => _t(ar, 'مطلوب', 'Requested'),
    'ordered' => _t(ar, 'تم الطلب', 'Ordered'),
    'received' => _t(ar, 'تم الاستلام', 'Received'),
    'cancelled' || 'canceled' => _t(ar, 'ملغي', 'Cancelled'),
    _ => value,
  };
}

String _unit(bool ar, String value) {
  return switch (value.trim().toLowerCase()) {
    'piece' || 'pcs' || 'pc' => _t(ar, 'قطعة', 'Piece'),
    'carton' => _t(ar, 'كرتونة', 'Carton'),
    'box' => _t(ar, 'صندوق', 'Box'),
    'pack' => _t(ar, 'عبوة', 'Pack'),
    'kg' || 'kilogram' => _t(ar, 'كغم', 'kg'),
    'g' || 'gram' => _t(ar, 'غرام', 'g'),
    'liter' || 'litre' || 'l' => _t(ar, 'لتر', 'L'),
    'bottle' => _t(ar, 'زجاجة', 'Bottle'),
    _ => value,
  };
}

String _productName(
  AppDataStore store,
  String productId,
  String fallback,
  bool ar,
) {
  final product = productId.isEmpty ? null : store.productOrNull(productId);
  if (product == null) return fallback;
  return ar ? product.nameAr : product.nameEn;
}

String _accountName(bool ar, String code, String fallback) {
  final names = <String, (String, String)>{
    '1000': ('النقد', 'Cash'),
    '1010': ('البنك والبطاقات', 'Bank / Card'),
    '1100': ('ذمم العملاء', 'Accounts Receivable'),
    '1110': ('باقي لنا من مرتجعات الموردين', 'Supplier Return Receivable'),
    '1150': ('سلف الموظفين', 'Employee Advances'),
    '1200': ('المخزون', 'Inventory'),
    '1500': ('الأصول الثابتة', 'Fixed Assets'),
    '1590': ('مجمع الإهلاك', 'Accumulated Depreciation'),
    '2000': ('ذمم الموردين', 'Accounts Payable'),
    '2100': ('ضريبة المبيعات المستحقة', 'Sales Tax Payable'),
    '3000': ('حقوق الملكية', 'Owner Equity'),
    '4000': ('إيرادات المبيعات', 'Sales Revenue'),
    '4010': ('مرتجعات المبيعات', 'Sales Returns'),
    '5000': ('تكلفة البضاعة المباعة', 'Cost of Goods Sold'),
    '6000': ('المصروفات التشغيلية', 'Operating Expenses'),
    '6020': ('مصروف الرواتب', 'Payroll Expense'),
    '6050': ('عجز المخزون', 'Inventory Shrinkage'),
    '4050': ('أرباح تسوية المخزون', 'Inventory Adjustment Gain'),
    '6100': ('مصروف الإهلاك', 'Depreciation Expense'),
  };
  final pair = names[code];
  return pair == null ? fallback : (ar ? pair.$1 : pair.$2);
}

class ThamanPrintTemplates {
  const ThamanPrintTemplates._();

  static PrintDocument saleInvoice(
    AppDataStore store,
    SaleInvoice invoice, {
    bool isArabic = true,
  }) {
    final customer = invoice.customerId.isEmpty
        ? null
        : store.customerOrNull(invoice.customerId);
    final currentDue = store.invoiceOutstanding(invoice.id);
    final storeSubtitle = <String>[
      store.settings.storeName.trim(),
      store.settings.branchName.trim(),
    ].where((value) => value.isNotEmpty).join(' • ');
    final status = invoice.voided
        ? _t(isArabic, 'ملغاة', 'Voided')
        : currentDue <= 0.005
            ? _t(isArabic, 'مسددة', 'Paid')
            : currentDue < invoice.total
                ? _t(isArabic, 'مدفوعة جزئيًا', 'Partially paid')
                : _t(isArabic, 'مستحقة', 'Due');

    return PrintDocument(
      isArabic: isArabic,
      title: _t(isArabic, 'فاتورة مبيعات', 'Sales Invoice'),
      subtitle: storeSubtitle,
      metadata: <String, String>{
        _t(isArabic, 'رقم الفاتورة', 'Invoice number'): invoice.number,
        if (invoice.title.trim().isNotEmpty)
          _t(isArabic, 'اسم الفاتورة', 'Invoice name'): invoice.title.trim(),
        _t(isArabic, 'التاريخ والوقت', 'Date & time'): _dt(invoice.createdAt),
        _t(isArabic, 'العميل', 'Customer'):
            invoice.customer.trim().isEmpty ? '-' : invoice.customer,
        if (customer != null)
          _t(isArabic, 'رقم حساب العميل', 'Customer account'):
              customer.accountNumber,
        if (customer != null && customer.phone.trim().isNotEmpty)
          _t(isArabic, 'هاتف العميل', 'Customer phone'): customer.phone,
        _t(isArabic, 'الكاشير', 'Cashier'):
            '${invoice.cashier}${invoice.cashierId.isEmpty ? '' : ' • ${invoice.cashierId}'}',
        _t(isArabic, 'طريقة الدفع', 'Payment method'):
            _payment(isArabic, invoice.paymentMethod),
        _t(isArabic, 'حالة الفاتورة', 'Invoice status'): status,
      },
      headers: <String>[
        _t(isArabic, 'الصنف', 'Item'),
        _t(isArabic, 'الكمية', 'Qty'),
        '${_t(isArabic, 'سعر الوحدة', 'Unit price')} (${store.settings.currency})',
        '${_t(isArabic, 'الإجمالي', 'Total')} (${store.settings.currency})',
      ],
      rows: invoice.lines
          .map(
            (line) => <String>[
              isArabic ? line.nameAr : line.nameEn,
              '${line.quantity}',
              line.unitPrice.toStringAsFixed(2),
              line.total.toStringAsFixed(2),
            ],
          )
          .toList(),
      summary: <String, String>{
        _t(isArabic, 'قبل الضريبة', 'Subtotal'):
            '${invoice.subtotal.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'الضريبة', 'Tax'):
            '${invoice.taxAmount.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'الإجمالي', 'Total'):
            '${invoice.total.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'المدفوع عند البيع', 'Paid at sale'):
            '${invoice.receivedAtSale.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'المتبقي عند البيع', 'Due at sale'):
            '${invoice.dueAmount.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'الرصيد الحالي للفاتورة', 'Current invoice balance'):
            '${currentDue.toStringAsFixed(2)} ${store.settings.currency}',
      },
      notes: <String>[
        if (invoice.voided)
          _t(isArabic, 'هذه الفاتورة ملغاة.', 'This invoice is voided.'),
        if (!invoice.voided && (currentDue - invoice.dueAmount).abs() > 0.005)
          _t(
            isArabic,
            'الرصيد الحالي يأخذ بالاعتبار الدفعات أو المرتجعات المسجلة بعد إصدار الفاتورة.',
            'Current balance includes payments or returns recorded after the invoice was issued.',
          ),
      ],
      footer: store.settings.receiptFooter,
    );
  }

  static PrintDocument purchaseReceipt(
    AppDataStore store,
    PurchaseReceipt receipt, {
    bool isArabic = true,
  }) {
    final supplier = receipt.supplierId.isEmpty
        ? null
        : store.supplierOrNull(receipt.supplierId);
    final currentDue = store.purchaseOutstanding(receipt);
    final storeSubtitle = <String>[
      store.settings.storeName.trim(),
      receipt.branch.trim().isEmpty ? store.settings.branchName.trim() : receipt.branch.trim(),
    ].where((value) => value.isNotEmpty).join(' • ');

    return PrintDocument(
      isArabic: isArabic,
      title: _t(isArabic, 'فاتورة شراء واستلام', 'Purchase & Receiving Invoice'),
      subtitle: storeSubtitle,
      metadata: <String, String>{
        _t(isArabic, 'رقم العملية', 'Operation number'): receipt.number,
        if (receipt.title.trim().isNotEmpty)
          _t(isArabic, 'اسم الفاتورة', 'Invoice name'): receipt.title.trim(),
        _t(isArabic, 'فاتورة المورد', 'Vendor invoice'):
            receipt.vendorInvoiceNumber.isEmpty ? '-' : receipt.vendorInvoiceNumber,
        _t(isArabic, 'التاريخ والوقت', 'Date & time'): _dt(receipt.createdAt),
        _t(isArabic, 'المورد', 'Supplier'): receipt.supplier,
        if (supplier != null)
          _t(isArabic, 'رقم حساب المورد', 'Supplier account'):
              supplier.accountNumber,
        if (supplier != null && supplier.phone.trim().isNotEmpty)
          _t(isArabic, 'هاتف المورد', 'Supplier phone'): supplier.phone,
        _t(isArabic, 'المستلم', 'Received by'):
            '${receipt.employeeName}${receipt.employeeId.isEmpty ? '' : ' • ${receipt.employeeId}'}',
        _t(isArabic, 'طريقة الدفع', 'Payment method'):
            _payment(isArabic, receipt.paymentMethod),
      },
      headers: <String>[
        _t(isArabic, 'الصنف', 'Item'),
        _t(isArabic, 'الكمية', 'Qty'),
        _t(isArabic, 'الوحدة', 'Unit'),
        _t(isArabic, 'محتوى الوحدة', 'Units per pack'),
        '${_t(isArabic, 'سعر الشراء', 'Purchase price')} (${store.settings.currency})',
        '${_t(isArabic, 'الإجمالي', 'Total')} (${store.settings.currency})',
      ],
      rows: receipt.lines
          .map(
            (line) => <String>[
              _productName(store, line.productId, line.itemName, isArabic),
              '${line.quantity}',
              _unit(isArabic, line.purchaseUnit),
              '${line.unitsPerPurchaseUnit}',
              line.unitCost.toStringAsFixed(2),
              line.total.toStringAsFixed(2),
            ],
          )
          .toList(),
      summary: <String, String>{
        _t(isArabic, 'قيمة البضاعة', 'Merchandise'):
            '${receipt.merchandiseTotal.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'الشحن والمصاريف', 'Shipping & costs'):
            '${receipt.shippingCost.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'الضريبة', 'Tax'):
            '${receipt.taxAmount.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'الإجمالي', 'Total'):
            '${receipt.total.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'المدفوع عند الشراء', 'Paid at purchase'):
            '${receipt.amountPaid.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'المتبقي الحالي', 'Current due'):
            '${currentDue.toStringAsFixed(2)} ${store.settings.currency}',
      },
      notes: <String>[
        if (receipt.note.trim().isNotEmpty) receipt.note.trim(),
      ],
      footer: store.settings.receiptFooter,
    );
  }

  static PrintDocument stockCount(
    AppDataStore store,
    StockCountSession session, {
    bool isArabic = true,
  }) {
    final rows = <List<String>>[];
    var shortage = 0;
    var surplus = 0;
    for (final line in session.lines) {
      final breakdown = store.stockCountBreakdown(session.id, line.productId);
      final product = store.productOrNull(line.productId);
      final difference = line.counted ? breakdown.difference : 0;
      final lineShortage = line.counted && difference < 0 ? -difference : 0;
      final lineSurplus = line.counted && difference > 0 ? difference : 0;
      shortage += lineShortage;
      surplus += lineSurplus;
      rows.add(<String>[
        product == null
            ? line.itemName
            : (isArabic ? product.nameAr : product.nameEn),
        product?.sku ?? '-',
        product?.barcode.isNotEmpty == true ? product!.barcode : '-',
        '${breakdown.openingStock}',
        '${breakdown.received}',
        '${breakdown.sold}',
        '${breakdown.damaged}',
        '${breakdown.returned}',
        '${breakdown.transferredOut}',
        '${breakdown.expected}',
        line.counted
            ? '${breakdown.actual}'
            : _t(isArabic, 'لم يُعد', 'Not counted'),
        line.counted ? '$lineShortage' : '—',
        line.counted ? '$lineSurplus' : '—',
      ]);
    }

    return PrintDocument(
      isArabic: isArabic,
      title: _t(isArabic, 'إشعار جرد مخزون', 'Stock Count Notice'),
      subtitle: _t(
        isArabic,
        'تفاصيل الجرد والحركات المؤثرة على كل صنف',
        'Count details and stock movements affecting each item',
      ),
      metadata: <String, String>{
        _t(isArabic, 'رقم الجرد', 'Count'): session.number,
        _t(isArabic, 'بدأ في', 'Started'): _dt(session.createdAt),
        _t(isArabic, 'نفذه', 'Performed by'):
            '${session.employeeName} • ${session.employeeId}',
        _t(isArabic, 'الحالة', 'Status'): _status(isArabic, session.status),
        _t(isArabic, 'اعتمد في', 'Completed'):
            session.completedAt == null ? '-' : _dt(session.completedAt!),
        _t(isArabic, 'الفرع', 'Branch'): store.settings.branchName,
      },
      headers: <String>[
        _t(isArabic, 'الصنف', 'Item'),
        'SKU',
        _t(isArabic, 'الباركود', 'Barcode'),
        _t(isArabic, 'بداية', 'Opening'),
        _t(isArabic, 'استلام', 'Received'),
        _t(isArabic, 'مباع', 'Sold'),
        _t(isArabic, 'تالف', 'Damaged'),
        _t(isArabic, 'مرتجع', 'Returned'),
        _t(isArabic, 'نقل', 'Transfer'),
        _t(isArabic, 'المتوقع', 'Expected'),
        _t(isArabic, 'الموجود', 'Actual'),
        _t(isArabic, 'النقص', 'Shortage'),
        _t(isArabic, 'الزيادة', 'Surplus'),
      ],
      rows: rows,
      summary: <String, String>{
        _t(isArabic, 'عدد الأصناف', 'Items'): '${session.lines.length}',
        _t(isArabic, 'أصناف بفروقات', 'Variances'):
            '${session.lines.where((line) => line.counted && store.stockCountExpectedQuantity(session, line) != line.actual).length}',
        _t(isArabic, 'إجمالي النقص', 'Shortage units'): '$shortage',
        _t(isArabic, 'إجمالي الزيادة', 'Surplus units'): '$surplus',
      },
      notes: <String>[
        _t(
          isArabic,
          'المتوقع = رصيد البداية + الاستلام + المرتجعات - المبيعات - التالف - النقل ± التعديلات.',
          'Expected = opening + receiving + returns - sales - damage - transfers ± adjustments.',
        ),
        _t(
          isArabic,
          'النقص = المتوقّع - الموجود عندما تكون الكمية الفعلية أقل من النظام. الزيادة = الموجود - المتوقّع عندما تكون الكمية الفعلية أعلى.',
          'Shortage = expected - actual when physical stock is lower. Surplus = actual - expected when physical stock is higher.',
        ),
      ],
      footer: store.settings.receiptFooter,
    );
  }

  /// Safe copy for the inventory counter. Intentionally excludes all system
  /// quantities, movement totals and variance information so a blind count
  /// remains blind even when the employee prints it.
  static PrintDocument stockCountCounterCopy(
    AppDataStore store,
    StockCountSession session, {
    bool isArabic = true,
  }) {
    final rows = <List<String>>[];
    for (final line in session.lines) {
      final product = store.productOrNull(line.productId);
      rows.add(<String>[
        product == null
            ? line.itemName
            : (isArabic ? product.nameAr : product.nameEn),
        product?.sku ?? '-',
        product?.barcode.isNotEmpty == true ? product!.barcode : '-',
        line.counted ? '${line.enteredQuantity}' : _t(isArabic, 'لم يُعد', 'Not counted'),
        line.counted ? _unit(isArabic, line.countUnit) : '—',
        line.counted ? '${line.actual}' : '—',
      ]);
    }

    final counted = session.lines.where((line) => line.counted).length;
    return PrintDocument(
      isArabic: isArabic,
      title: _t(isArabic, 'نسخة موظف المخزن - جرد', 'Inventory Employee Count Copy'),
      subtitle: _t(
        isArabic,
        'نسخة بالكميات التي تم عدّها فقط — لا تعرض رصيد النظام أو الفروقات.',
        'Counter-entered quantities only — system stock and variances are not shown.',
      ),
      metadata: <String, String>{
        _t(isArabic, 'رقم الجرد', 'Count'): session.number,
        _t(isArabic, 'بدأ في', 'Started'): _dt(session.createdAt),
        _t(isArabic, 'نفذه', 'Performed by'):
            '${session.employeeName} • ${session.employeeId}',
        _t(isArabic, 'الحالة', 'Status'): _status(isArabic, session.status),
        _t(isArabic, 'الفرع', 'Branch'): store.settings.branchName,
      },
      headers: <String>[
        _t(isArabic, 'الصنف', 'Item'),
        'SKU',
        _t(isArabic, 'الباركود', 'Barcode'),
        _t(isArabic, 'الكمية المدخلة', 'Entered qty'),
        _t(isArabic, 'الوحدة', 'Unit'),
        _t(isArabic, 'الإجمالي بالوحدة الأساسية', 'Base-unit total'),
      ],
      rows: rows,
      summary: <String, String>{
        _t(isArabic, 'عدد الأصناف', 'Items'): '${session.lines.length}',
        _t(isArabic, 'تم عدّها', 'Counted'): '$counted',
        _t(isArabic, 'متبقي', 'Remaining'): '${session.lines.length - counted}',
      },
      notes: <String>[
        _t(
          isArabic,
          'هذه النسخة مخصصة لموظف المخزن ولا تحتوي على الكمية المتوقعة أو النقص أو الزيادة أو حركات المخزون.',
          'This employee copy does not contain expected stock, shortages, surpluses, or stock movements.',
        ),
      ],
      footer: store.settings.receiptFooter,
    );
  }

  static PrintDocument customerStatement(
    AppDataStore store,
    CustomerRecord customer, {
    bool isArabic = true,
  }) {
    final entries = <({DateTime date, List<String> row})>[];
    final invoices = store.invoices
        .where((invoice) => !invoice.voided && invoice.customerId == customer.id);
    final payments = store.customerPayments
        .where((payment) => payment.customerId == customer.id);

    for (final invoice in invoices) {
      entries.add((
        date: invoice.createdAt,
        row: <String>[
          _dt(invoice.createdAt),
          invoice.number,
          _t(isArabic, 'فاتورة', 'Invoice'),
          invoice.total.toStringAsFixed(2),
          invoice.receivedAtSale.toStringAsFixed(2),
          store.invoiceOutstanding(invoice.id).toStringAsFixed(2),
        ],
      ));
    }
    for (final payment in payments) {
      entries.add((
        date: payment.createdAt,
        row: <String>[
          _dt(payment.createdAt),
          payment.id,
          _t(isArabic, 'دفعة', 'Payment'),
          '-',
          payment.amount.toStringAsFixed(2),
          '-',
        ],
      ));
    }
    entries.sort((a, b) => a.date.compareTo(b.date));

    return PrintDocument(
      isArabic: isArabic,
      title: _t(isArabic, 'كشف حساب عميل', 'Customer Statement'),
      subtitle: customer.name,
      metadata: <String, String>{
        _t(isArabic, 'رقم الحساب', 'Account'): customer.accountNumber,
        _t(isArabic, 'الهاتف', 'Phone'): customer.phone,
        _t(isArabic, 'العنوان', 'Address'): customer.address,
        _t(isArabic, 'حد الائتمان', 'Credit limit'): customer.creditLimit <= 0
            ? _t(isArabic, 'بدون حد', 'Unlimited')
            : '${customer.creditLimit.toStringAsFixed(2)} ${store.settings.currency}',
      },
      headers: <String>[
        _t(isArabic, 'التاريخ', 'Date'),
        _t(isArabic, 'المرجع', 'Reference'),
        _t(isArabic, 'النوع', 'Type'),
        _t(isArabic, 'قيمة الفاتورة', 'Invoice value'),
        _t(isArabic, 'المدفوع', 'Paid'),
        _t(isArabic, 'المتبقي', 'Due'),
      ],
      rows: entries.map((entry) => entry.row).toList(),
      summary: <String, String>{
        _t(isArabic, 'الرصيد المستحق', 'Outstanding'):
            '${customer.balance.toStringAsFixed(2)} ${store.settings.currency}',
      },
      notes: <String>[
        if (customer.note.trim().isNotEmpty) customer.note.trim(),
      ],
      footer: store.settings.receiptFooter,
    );
  }

  static PrintDocument supplierStatement(
    AppDataStore store,
    SupplierRecord supplier, {
    bool isArabic = true,
  }) {
    final entries = <({DateTime date, List<String> row})>[];
    final purchases = store.purchases.where((p) => p.supplierId == supplier.id);
    final payments =
        store.supplierPayments.where((p) => p.supplierId == supplier.id);
    final returns = store.purchaseReturns.where((r) => r.supplierId == supplier.id);

    for (final purchase in purchases) {
      entries.add((
        date: purchase.createdAt,
        row: <String>[
          _dt(purchase.createdAt),
          purchase.number,
          _t(isArabic, 'شراء', 'Purchase'),
          purchase.total.toStringAsFixed(2),
          purchase.amountPaid.toStringAsFixed(2),
          store.purchaseOutstanding(purchase).toStringAsFixed(2),
        ],
      ));
    }
    for (final payment in payments) {
      entries.add((
        date: payment.createdAt,
        row: <String>[
          _dt(payment.createdAt),
          payment.purchaseNumber.isEmpty ? payment.id : payment.purchaseNumber,
          _t(isArabic, 'دفعة', 'Payment'),
          '-',
          payment.amount.toStringAsFixed(2),
          '-',
        ],
      ));
    }
    for (final record in returns) {
      entries.add((
        date: record.createdAt,
        row: <String>[
          _dt(record.createdAt),
          record.purchaseNumber,
          _t(isArabic, 'مرتجع شراء', 'Purchase return'),
          record.agreedAmount.toStringAsFixed(2),
          record.cashRefund.toStringAsFixed(2),
          record.remainingRefund.toStringAsFixed(2),
        ],
      ));
    }
    entries.sort((a, b) => a.date.compareTo(b.date));

    return PrintDocument(
      isArabic: isArabic,
      title: _t(isArabic, 'كشف حساب مورد', 'Supplier Statement'),
      subtitle: supplier.name,
      metadata: <String, String>{
        _t(isArabic, 'رقم الحساب', 'Account'): supplier.accountNumber,
        _t(isArabic, 'الهاتف', 'Phone'): supplier.phone,
        _t(isArabic, 'العنوان', 'Address'): supplier.address,
      },
      headers: <String>[
        _t(isArabic, 'التاريخ', 'Date'),
        _t(isArabic, 'المرجع', 'Reference'),
        _t(isArabic, 'النوع', 'Type'),
        _t(isArabic, 'القيمة', 'Value'),
        _t(isArabic, 'المدفوع', 'Paid'),
        _t(isArabic, 'المتبقي', 'Due'),
      ],
      rows: entries.map((entry) => entry.row).toList(),
      summary: <String, String>{
        _t(isArabic, 'الرصيد المستحق علينا', 'Payable'):
            '${store.supplierBalance(supplier.id).toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'باقي لنا من مرتجعات هذا المورد', 'Return receivable'):
            '${store.purchaseReturns.where((r) => r.supplierId == supplier.id).fold<double>(0, (sum, r) => sum + r.remainingRefund).toStringAsFixed(2)} ${store.settings.currency}',
      },
      footer: store.settings.receiptFooter,
    );
  }

  static PrintDocument financialSummary(
    AppDataStore store,
    FinancialPeriodSummary summary,
    String periodLabel, {
    bool isArabic = true,
  }) {
    return PrintDocument(
      isArabic: isArabic,
      title: _t(isArabic, 'الملخص المالي', 'Financial Summary'),
      subtitle: periodLabel,
      metadata: <String, String>{
        _t(isArabic, 'المتجر', 'Store'): store.settings.storeName,
        _t(isArabic, 'الفرع', 'Branch'): store.settings.branchName,
      },
      headers: <String>[
        _t(isArabic, 'البند', 'Metric'),
        _t(isArabic, 'القيمة', 'Value'),
      ],
      rows: <(String, double)>[
        (_t(isArabic, 'صافي المبيعات', 'Net sales'), summary.netSales),
        (_t(isArabic, 'المقبوض', 'Collected'), summary.collected),
        (_t(isArabic, 'تكلفة المبيعات', 'COGS'), summary.costOfSales),
        (_t(isArabic, 'إجمالي الربح', 'Gross profit'), summary.grossProfit),
        (_t(isArabic, 'المصروفات', 'Expenses'), summary.expenses),
        (_t(isArabic, 'الإهلاك', 'Depreciation'), summary.depreciation),
        (_t(isArabic, 'صافي الربح', 'Net profit'), summary.netProfit),
        (_t(isArabic, 'المشتريات', 'Purchases'), summary.purchases),
        (_t(isArabic, 'مرتجعات المشتريات', 'Purchase returns'), summary.purchaseReturns),
        (_t(isArabic, 'باقي لنا من مرتجعات الموردين', 'Supplier return receivables'), summary.supplierReturnReceivables),
        (_t(isArabic, 'المدفوع للموردين', 'Supplier paid'), summary.supplierPaid),
        (_t(isArabic, 'ضريبة المبيعات', 'Sales tax'), summary.salesTax),
        (_t(isArabic, 'التدفق النقدي', 'Cash flow'), summary.cashFlow),
      ]
          .map(
            (row) => <String>[
              row.$1,
              '${row.$2.toStringAsFixed(2)} ${store.settings.currency}',
            ],
          )
          .toList(),
      summary: <String, String>{
        _t(isArabic, 'لنا عند العملاء', 'Receivables'):
            '${store.totalReceivables.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'علينا للموردين', 'Payables'):
            '${store.totalPayables.toStringAsFixed(2)} ${store.settings.currency}',
      },
      footer: store.settings.receiptFooter,
    );
  }

  static PrintDocument financialLedgerReport(
    AppDataStore store, {
    required String title,
    required String range,
    required List<List<String>> rows,
    required double total,
    Map<String, String> filters = const <String, String>{},
    bool isArabic = true,
  }) {
    return PrintDocument(
      isArabic: isArabic,
      title: title,
      subtitle: store.settings.storeName,
      metadata: <String, String>{
        _t(isArabic, 'المتجر', 'Store'): store.settings.storeName,
        _t(isArabic, 'الفرع', 'Branch'): store.settings.branchName,
        _t(isArabic, 'الفترة', 'Period'): range,
        ...filters,
      },
      headers: <String>[
        _t(isArabic, 'التاريخ', 'Date'),
        _t(isArabic, 'الطرف', 'Party'),
        _t(isArabic, 'النوع', 'Type'),
        _t(isArabic, 'المرجع', 'Reference'),
        _t(isArabic, 'المبلغ', 'Amount'),
        _t(isArabic, 'الموظف', 'Actor'),
        _t(isArabic, 'ملاحظات', 'Notes'),
      ],
      rows: rows,
      summary: <String, String>{
        _t(isArabic, 'عدد السجلات', 'Records'): '${rows.length}',
        _t(isArabic, 'إجمالي الحركات', 'Transactions total'):
            '${total.toStringAsFixed(2)} ${store.settings.currency}',
      },
      notes: <String>[
        _t(
          isArabic,
          'تم إنشاء هذا الكشف من سجلات THAMAN التشغيلية والمالية وفق عوامل التصفية الظاهرة أعلاه.',
          'This statement was generated from THAMAN financial and operational records using the filters shown above.',
        ),
      ],
      footer: store.settings.receiptFooter,
    );
  }

  static PrintDocument accountingStatement(
    AppDataStore store, {
    bool isArabic = true,
  }) {
    final snapshot = store.accountingSnapshot();
    final codes = <String>{
      ...store.trialBalanceDebits.keys,
      ...store.trialBalanceCredits.keys,
    }.toList()
      ..sort();
    final rows = codes
        .map(
          (code) => <String>[
            code,
            _accountName(isArabic, code, store.accountName(code)),
            (store.trialBalanceDebits[code] ?? 0).toStringAsFixed(2),
            (store.trialBalanceCredits[code] ?? 0).toStringAsFixed(2),
            store.accountBalance(code).toStringAsFixed(2),
          ],
        )
        .toList();

    return PrintDocument(
      isArabic: isArabic,
      title: _t(
        isArabic,
        'الميزانية وميزان المراجعة',
        'Balance Sheet & Trial Balance',
      ),
      subtitle: store.settings.storeName,
      metadata: <String, String>{
        _t(isArabic, 'الفرع', 'Branch'): store.settings.branchName,
        _t(isArabic, 'حالة القيود', 'Journal'): store.journalIsBalanced
            ? _t(isArabic, 'متزن', 'Balanced')
            : _t(isArabic, 'غير متزن', 'NOT BALANCED'),
      },
      headers: <String>[
        _t(isArabic, 'الحساب', 'Account'),
        _t(isArabic, 'اسم الحساب', 'Account name'),
        _t(isArabic, 'مدين', 'Debit'),
        _t(isArabic, 'دائن', 'Credit'),
        _t(isArabic, 'الرصيد', 'Balance'),
      ],
      rows: rows,
      summary: <String, String>{
        _t(isArabic, 'النقد', 'Cash'):
            '${snapshot.cash.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'البنك والبطاقات', 'Bank / Card'):
            '${snapshot.bank.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'الذمم لنا (عملاء + مرتجع موردين)', 'Receivables'):
            '${snapshot.receivables.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'باقي لنا من مرتجعات الموردين', 'Supplier return receivables'):
            '${store.supplierReturnReceivables.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'المخزون', 'Inventory'):
            '${snapshot.inventory.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'الأصول الثابتة الصافية', 'Fixed assets net'):
            '${snapshot.fixedAssetsNet.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'إجمالي الأصول', 'Assets'):
            '${snapshot.totalAssets.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'ذمم الموردين', 'Payables'):
            '${snapshot.payables.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'ضريبة مبيعات مستحقة', 'Sales tax payable'):
            '${snapshot.salesTaxPayable.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'حقوق الملكية', 'Equity'):
            '${snapshot.equity.toStringAsFixed(2)} ${store.settings.currency}',
      },
      footer: store.settings.receiptFooter,
    );
  }

  static PrintDocument assetsReport(
    AppDataStore store, {
    Iterable<AssetRecord>? assets,
    bool isArabic = true,
  }) {
    final now = DateTime.now();
    final data = (assets ?? store.assets).toList();
    final purchaseTotal = data.fold<double>(0, (sum, a) => sum + a.purchasePrice);
    final depreciationTotal = data.fold<double>(
        0, (sum, a) => sum + a.accumulatedDepreciationAt(now));
    final bookTotal = data.fold<double>(0, (sum, a) => sum + a.bookValueAt(now));

    return PrintDocument(
      isArabic: isArabic,
      title: _t(isArabic, 'سجل الأصول وتفاصيلها', 'Asset Register & Details'),
      subtitle: store.settings.storeName,
      metadata: <String, String>{
        _t(isArabic, 'الفرع', 'Branch'): store.settings.branchName,
        _t(isArabic, 'تاريخ التقرير', 'Report date'): _dt(now),
      },
      headers: <String>[
        _t(isArabic, 'الأصل', 'Asset'),
        _t(isArabic, 'التصنيف', 'Category'),
        _t(isArabic, 'تاريخ الشراء', 'Purchase date'),
        _t(isArabic, 'سعر الشراء', 'Purchase price'),
        _t(isArabic, 'الإهلاك السنوي', 'Annual depreciation'),
        _t(isArabic, 'الإهلاك المتراكم', 'Accumulated depreciation'),
        _t(isArabic, 'القيمة الدفترية', 'Book value'),
        _t(isArabic, 'الحالة', 'Status'),
        _t(isArabic, 'ملاحظات', 'Notes'),
      ],
      rows: data
          .map((asset) => <String>[
                asset.name,
                asset.category,
                _dt(asset.purchaseDate).split(' ').first,
                '${asset.purchasePrice.toStringAsFixed(2)} ${store.settings.currency}',
                '${asset.annualDepreciationRate.toStringAsFixed(1)}%',
                '${asset.accumulatedDepreciationAt(now).toStringAsFixed(2)} ${store.settings.currency}',
                '${asset.bookValueAt(now).toStringAsFixed(2)} ${store.settings.currency}',
                asset.active
                    ? _t(isArabic, 'نشط', 'Active')
                    : _t(isArabic, 'مؤرشف', 'Archived'),
                asset.note.isEmpty ? '-' : asset.note,
              ])
          .toList(),
      summary: <String, String>{
        _t(isArabic, 'عدد الأصول', 'Assets'): '${data.length}',
        _t(isArabic, 'إجمالي تكلفة الشراء', 'Total purchase cost'):
            '${purchaseTotal.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'إجمالي الإهلاك المتراكم', 'Accumulated depreciation'):
            '${depreciationTotal.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'إجمالي القيمة الدفترية', 'Total book value'):
            '${bookTotal.toStringAsFixed(2)} ${store.settings.currency}',
      },
      footer: store.settings.receiptFooter,
    );
  }

  static PrintDocument customReport({
    required String title,
    required String subtitle,
    required List<String> headers,
    required List<List<String>> rows,
    Map<String, String> metadata = const <String, String>{},
    Map<String, String> summary = const <String, String>{},
    List<String> notes = const <String>[],
    String footer = '',
    bool isArabic = true,
  }) {
    return PrintDocument(
      isArabic: isArabic,
      title: title,
      subtitle: subtitle,
      metadata: metadata,
      headers: headers,
      rows: rows,
      summary: summary,
      notes: notes,
      footer: footer,
    );
  }

  static PrintDocument stockMovementNotice(
    AppDataStore store,
    StockMovement movement, {
    bool isArabic = true,
  }) {
    final product = movement.productId.isEmpty
        ? null
        : store.productOrNull(movement.productId);
    final item = product == null
        ? (movement.itemName.isEmpty ? '-' : movement.itemName)
        : (isArabic ? product.nameAr : product.nameEn);
    final unit = movement.operationUnit.isEmpty
        ? (product?.baseUnit ?? '')
        : movement.operationUnit;
    final operation = movement.operationQuantity > 0
        ? '${movement.operationQuantity.toStringAsFixed(movement.operationQuantity % 1 == 0 ? 0 : 2)} ${_unit(isArabic, unit)}${movement.unitsPerOperationUnit > 1 ? ' × ${movement.unitsPerOperationUnit}' : ''}'
        : '-';

    return PrintDocument(
      isArabic: isArabic,
      title: _t(isArabic, 'إشعار حركة مخزون', 'Stock Movement Notice'),
      subtitle: store.settings.storeName,
      metadata: <String, String>{
        _t(isArabic, 'الصنف', 'Item'): item,
        'SKU': product?.sku ?? '-',
        _t(isArabic, 'الباركود', 'Barcode'):
            (product?.barcode.isNotEmpty ?? false) ? product!.barcode : '-',
        _t(isArabic, 'نوع الحركة', 'Movement'):
            _movement(isArabic, movement.type),
        _t(isArabic, 'التاريخ والوقت', 'Date & time'):
            _dt(movement.createdAt),
        _t(isArabic, 'نفذها', 'Performed by'): movement.employeeName.isEmpty
            ? _t(isArabic, 'النظام', 'System')
            : '${movement.employeeName}${movement.employeeId.isEmpty ? '' : ' • ${movement.employeeId}'}',
        _t(isArabic, 'الفرع', 'Branch'): movement.branch,
        if (movement.reference.isNotEmpty)
          _t(isArabic, 'المرجع', 'Reference'): movement.reference,
      },
      headers: <String>[
        _t(isArabic, 'الكمية الأساسية', 'Base qty'),
        _t(isArabic, 'الكمية المدخلة والوحدة', 'Entered qty & unit'),
        _t(isArabic, 'القيمة', 'Value'),
        _t(isArabic, 'الملاحظة', 'Note'),
      ],
      rows: <List<String>>[
        <String>[
          '${movement.quantity > 0 ? '+' : ''}${movement.quantity}',
          operation,
          movement.amount > 0
              ? '${movement.amount.toStringAsFixed(2)} ${store.settings.currency}'
              : '-',
          movement.note.isEmpty ? '-' : movement.note,
        ],
      ],
      notes: <String>[
        _t(
          isArabic,
          'تم إنشاء هذا الإشعار مباشرة من سجل حركة المخزون في THAMAN.',
          'Generated directly from the THAMAN stock movement ledger.',
        ),
      ],
      footer: store.settings.receiptFooter,
    );
  }

  static PrintDocument returnNotice(
    AppDataStore store,
    ReturnRecord record, {
    bool isArabic = true,
  }) {
    SaleInvoice? invoice;
    for (final candidate in store.invoices) {
      if (candidate.id == record.invoiceId) {
        invoice = candidate;
        break;
      }
    }
    return PrintDocument(
      isArabic: isArabic,
      title: _t(isArabic, 'إشعار مرتجع', 'Return Notice'),
      subtitle: store.settings.storeName,
      metadata: <String, String>{
        _t(isArabic, 'الفاتورة الأصلية', 'Original invoice'):
            record.invoiceNumber,
        _t(isArabic, 'التاريخ', 'Date'): _dt(record.createdAt),
        _t(isArabic, 'العميل', 'Customer'): invoice?.customer ?? '-',
        _t(isArabic, 'المعالج', 'Processed by'): record.processedBy,
        _t(isArabic, 'السبب', 'Reason'): record.reason,
        _t(isArabic, 'طريقة الرد', 'Refund method'):
            _payment(isArabic, record.refundMethod),
      },
      headers: <String>[
        _t(isArabic, 'الصنف', 'Item'),
        _t(isArabic, 'الكمية', 'Qty'),
        _t(isArabic, 'السعر', 'Price'),
        _t(isArabic, 'الإجمالي', 'Total'),
      ],
      rows: record.lines
          .map(
            (line) => <String>[
              isArabic ? line.nameAr : line.nameEn,
              '${line.quantity}',
              line.unitPrice.toStringAsFixed(2),
              line.total.toStringAsFixed(2),
            ],
          )
          .toList(),
      summary: <String, String>{
        _t(isArabic, 'قبل الضريبة', 'Subtotal'):
            '${record.subtotal.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'الضريبة', 'Tax'):
            '${record.taxAmount.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'إجمالي المرتجع', 'Return total'):
            '${record.total.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'تخفيض الذمة', 'Receivable reduction'):
            '${record.receivableReduction.toStringAsFixed(2)} ${store.settings.currency}',
        _t(isArabic, 'المبلغ المردود', 'Refunded'):
            '${record.refundAmount.toStringAsFixed(2)} ${store.settings.currency}',
      },
      footer: store.settings.receiptFooter,
    );
  }
}
