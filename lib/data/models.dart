class ProductModel {
  ProductModel({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.sku,
    required this.barcode,
    required this.categoryAr,
    required this.categoryEn,
    required this.price,
    required this.cost,
    required this.stock,
    required this.minStock,
    this.baseUnit = 'piece',
    this.purchaseUnit = 'piece',
    this.unitsPerPurchaseUnit = 1,
    this.packageWeightKg = 0,
    this.active = true,
  });

  final String id;
  String nameAr;
  String nameEn;
  String sku;
  String barcode;
  String categoryAr;
  String categoryEn;
  double price;
  double cost;
  int stock;
  int minStock;
  String baseUnit;
  String purchaseUnit;
  int unitsPerPurchaseUnit;
  double packageWeightKg;
  bool active;

  double get margin => price == 0 ? 0 : ((price - cost) / price) * 100;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'sku': sku,
        'barcode': barcode,
        'categoryAr': categoryAr,
        'categoryEn': categoryEn,
        'price': price,
        'cost': cost,
        'stock': stock,
        'minStock': minStock,
        'baseUnit': baseUnit,
        'purchaseUnit': purchaseUnit,
        'unitsPerPurchaseUnit': unitsPerPurchaseUnit,
        'packageWeightKg': packageWeightKg,
        'active': active,
      };

  factory ProductModel.fromJson(Map<String, dynamic> m) => ProductModel(
        id: m['id'] as String,
        nameAr: m['nameAr'] as String,
        nameEn: (m['nameEn'] as String?) ?? m['nameAr'] as String,
        sku: m['sku'] as String,
        barcode: (m['barcode'] as String?) ?? '',
        categoryAr: (m['categoryAr'] as String?) ?? 'عام',
        categoryEn: (m['categoryEn'] as String?) ?? 'General',
        price: (m['price'] as num?)?.toDouble() ?? 0,
        cost: (m['cost'] as num?)?.toDouble() ?? 0,
        stock: (m['stock'] as num?)?.toInt() ?? 0,
        minStock: (m['minStock'] as num?)?.toInt() ?? 0,
        baseUnit: (m['baseUnit'] as String?) ?? 'piece',
        purchaseUnit: (m['purchaseUnit'] as String?) ?? 'piece',
        unitsPerPurchaseUnit: (m['unitsPerPurchaseUnit'] as num?)?.toInt() ?? 1,
        packageWeightKg: (m['packageWeightKg'] as num?)?.toDouble() ?? 0,
        active: (m['active'] as bool?) ?? true,
      );
}

class InvoiceLine {
  const InvoiceLine({
    required this.productId,
    required this.nameAr,
    required this.nameEn,
    required this.quantity,
    required this.unitPrice,
    this.unitCost = 0,
  });

  final String productId;
  final String nameAr;
  final String nameEn;
  final int quantity;
  final double unitPrice;
  final double unitCost;
  double get total => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'unitCost': unitCost,
      };

  factory InvoiceLine.fromJson(Map<String, dynamic> m) => InvoiceLine(
        productId: m['productId'] as String,
        nameAr: m['nameAr'] as String,
        nameEn: (m['nameEn'] as String?) ?? m['nameAr'] as String,
        quantity: (m['quantity'] as num).toInt(),
        unitPrice: (m['unitPrice'] as num).toDouble(),
        unitCost: (m['unitCost'] as num?)?.toDouble() ?? 0,
      );
}

class SaleInvoice {
  SaleInvoice({
    required this.id,
    required this.number,
    required this.createdAt,
    required this.cashier,
    required this.paymentMethod,
    required this.lines,
    this.cashierId = '',
    this.customer = 'Walk-in',
    this.customerId = '',
    this.paidAmount,
    this.taxPercent = 0,
    this.title = '',
    this.voided = false,
  });

  final String id;
  final String number;
  final DateTime createdAt;
  final String cashier;
  final String cashierId;
  final String paymentMethod;
  final String customer;
  final String customerId;
  final List<InvoiceLine> lines;
  final double? paidAmount;
  final double taxPercent;
  final String title;
  bool voided;

  double get subtotal => lines.fold<double>(0, (sum, line) => sum + line.total);
  double get taxAmount => subtotal * (taxPercent.clamp(0, 100) / 100);
  double get total => subtotal + taxAmount;
  double get receivedAtSale => (paidAmount ?? (paymentMethod == 'Debt' ? 0 : total)).clamp(0, total).toDouble();
  double get dueAmount => (total - receivedAtSale).clamp(0, total).toDouble();
  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'createdAt': createdAt.toIso8601String(),
        'cashier': cashier,
        'cashierId': cashierId,
        'paymentMethod': paymentMethod,
        'customer': customer,
        'customerId': customerId,
        'paidAmount': paidAmount,
        'taxPercent': taxPercent,
        'title': title,
        'voided': voided,
        'lines': lines.map((e) => e.toJson()).toList(),
      };

  factory SaleInvoice.fromJson(Map<String, dynamic> m) => SaleInvoice(
        id: m['id'] as String,
        number: m['number'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        cashier: m['cashier'] as String,
        cashierId: (m['cashierId'] as String?) ?? '',
        paymentMethod: m['paymentMethod'] as String,
        customer: (m['customer'] as String?) ?? 'Walk-in',
        customerId: (m['customerId'] as String?) ?? '',
        paidAmount: (m['paidAmount'] as num?)?.toDouble(),
        taxPercent: (m['taxPercent'] as num?)?.toDouble() ?? 0,
        title: (m['title'] as String?) ?? '',
        voided: (m['voided'] as bool?) ?? false,
        lines: ((m['lines'] as List?) ?? [])
            .map((e) => InvoiceLine.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class HeldSale {
  HeldSale({
    required this.id,
    required this.label,
    required this.createdAt,
    required this.lines,
    this.cashierId = '',
    this.cashierName = '',
    this.customer = 'Walk-in',
  });

  final String id;
  final String label;
  final DateTime createdAt;
  final Map<String, int> lines;
  final String cashierId;
  final String cashierName;
  final String customer;

  int get itemCount => lines.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'createdAt': createdAt.toIso8601String(),
        'lines': lines,
        'cashierId': cashierId,
        'cashierName': cashierName,
        'customer': customer,
      };

  factory HeldSale.fromJson(Map<String, dynamic> m) => HeldSale(
        id: m['id'] as String,
        label: m['label'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        lines: (m['lines'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        cashierId: (m['cashierId'] as String?) ?? '',
        cashierName: (m['cashierName'] as String?) ?? '',
        customer: (m['customer'] as String?) ?? 'Walk-in',
      );
}

class ReturnRecord {
  ReturnRecord({
    required this.id,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.createdAt,
    required this.reason,
    required this.refundMethod,
    required this.lines,
    this.processedBy = '',
    this.processedById = '',
    this.taxAmount = 0,
    this.receivableReduction = 0,
    this.refundAmount = 0,
  });

  final String id;
  final String invoiceId;
  final String invoiceNumber;
  final DateTime createdAt;
  final String reason;
  final String refundMethod;
  final List<InvoiceLine> lines;
  final String processedBy;
  final String processedById;
  final double taxAmount;
  final double receivableReduction;
  final double refundAmount;

  double get subtotal => lines.fold<double>(0, (sum, line) => sum + line.total);
  double get total => subtotal + taxAmount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'invoiceId': invoiceId,
        'invoiceNumber': invoiceNumber,
        'createdAt': createdAt.toIso8601String(),
        'reason': reason,
        'refundMethod': refundMethod,
        'processedBy': processedBy,
        'processedById': processedById,
        'taxAmount': taxAmount,
        'receivableReduction': receivableReduction,
        'refundAmount': refundAmount,
        'lines': lines.map((e) => e.toJson()).toList(),
      };

  factory ReturnRecord.fromJson(Map<String, dynamic> m) {
    final lines = ((m['lines'] as List?) ?? [])
        .map((e) => InvoiceLine.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final legacySubtotal = lines.fold<double>(0, (sum, line) => sum + line.total);
    return ReturnRecord(
      id: m['id'] as String,
      invoiceId: m['invoiceId'] as String,
      invoiceNumber: m['invoiceNumber'] as String,
      createdAt: DateTime.parse(m['createdAt'] as String),
      reason: m['reason'] as String,
      refundMethod: m['refundMethod'] as String,
      processedBy: (m['processedBy'] as String?) ?? '',
      processedById: (m['processedById'] as String?) ?? '',
      taxAmount: (m['taxAmount'] as num?)?.toDouble() ?? 0,
      receivableReduction: (m['receivableReduction'] as num?)?.toDouble() ?? 0,
      refundAmount: (m['refundAmount'] as num?)?.toDouble() ?? legacySubtotal,
      lines: lines,
    );
  }
}

class EmployeeRecord {
  EmployeeRecord({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.roleKey,
    required this.pin,
    String? loginId,
    required this.shiftStartMinutes,
    required this.shiftEndMinutes,
    this.phone = '',
    this.branch = 'Main',
    this.weeklyOffDay = DateTime.friday,
    this.active = true,
    this.onLeave = false,
    this.leaveUntil,
    this.terminatedAt,
    this.salary = 0,
    this.salaryPayDay = 1,
    this.managementOnly = false,
  }) : loginId = loginId ?? id;

  final String id;
  String nameAr;
  String nameEn;
  String roleKey;
  String pin;
  String loginId;
  String phone;
  String branch;
  int shiftStartMinutes;
  int shiftEndMinutes;
  int weeklyOffDay;
  bool active;
  bool onLeave;
  DateTime? leaveUntil;
  DateTime? terminatedAt;
  double salary;
  int salaryPayDay;
  bool managementOnly;

  String get shiftLabel => '${_hm(shiftStartMinutes)} — ${_hm(shiftEndMinutes)}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'roleKey': roleKey,
        'pin': pin,
        'loginId': loginId,
        'phone': phone,
        'branch': branch,
        'shiftStartMinutes': shiftStartMinutes,
        'shiftEndMinutes': shiftEndMinutes,
        'weeklyOffDay': weeklyOffDay,
        'active': active,
        'onLeave': onLeave,
        'leaveUntil': leaveUntil?.toIso8601String(),
        'terminatedAt': terminatedAt?.toIso8601String(),
        'salary': salary,
        'salaryPayDay': salaryPayDay,
        'managementOnly': managementOnly,
      };

  factory EmployeeRecord.fromJson(Map<String, dynamic> m) => EmployeeRecord(
        id: m['id'] as String,
        nameAr: m['nameAr'] as String,
        nameEn: (m['nameEn'] as String?) ?? m['nameAr'] as String,
        roleKey: (m['roleKey'] as String?) ?? 'general',
        pin: (m['pin'] as String?) ?? '0000',
        loginId: (m['loginId'] as String?) ?? m['id'] as String,
        phone: (m['phone'] as String?) ?? '',
        branch: (m['branch'] as String?) ?? 'Main',
        shiftStartMinutes: (m['shiftStartMinutes'] as num?)?.toInt() ?? 480,
        shiftEndMinutes: (m['shiftEndMinutes'] as num?)?.toInt() ?? 960,
        weeklyOffDay: (m['weeklyOffDay'] as num?)?.toInt() ?? DateTime.friday,
        active: (m['active'] as bool?) ?? true,
        onLeave: (m['onLeave'] as bool?) ?? false,
        leaveUntil: m['leaveUntil'] == null ? null : DateTime.parse(m['leaveUntil'] as String),
        terminatedAt: m['terminatedAt'] == null ? null : DateTime.parse(m['terminatedAt'] as String),
        salary: (m['salary'] as num?)?.toDouble() ?? 0,
        salaryPayDay: ((m['salaryPayDay'] as num?)?.toInt() ?? 1).clamp(1, 31).toInt(),
        managementOnly: (m['managementOnly'] as bool?) ?? false,
      );
}

class AdminAccountRecord {
  AdminAccountRecord({
    required this.id,
    required this.roleKey,
    required this.email,
    required this.password,
    required this.pin,
    required this.nameAr,
    required this.nameEn,
    this.phone = '',
    this.active = true,
  });

  final String id;
  final String roleKey;
  String email;
  String password;
  String pin;
  String nameAr;
  String nameEn;
  String phone;
  bool active;

  Map<String, dynamic> toJson() => {
        'id': id,
        'roleKey': roleKey,
        'email': email,
        'password': password,
        'pin': pin,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'phone': phone,
        'active': active,
      };

  factory AdminAccountRecord.fromJson(Map<String, dynamic> m) => AdminAccountRecord(
        id: m['id'] as String,
        roleKey: m['roleKey'] as String,
        email: (m['email'] as String?) ?? '',
        password: (m['password'] as String?) ?? '',
        pin: (m['pin'] as String?) ?? '',
        nameAr: (m['nameAr'] as String?) ?? '',
        nameEn: (m['nameEn'] as String?) ?? '',
        phone: (m['phone'] as String?) ?? '',
        active: (m['active'] as bool?) ?? true,
      );
}

class AuditLogRecord {
  AuditLogRecord({
    required this.id,
    required this.createdAt,
    required this.actorName,
    required this.actorRole,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.description,
  });

  final String id;
  final DateTime createdAt;
  final String actorName;
  final String actorRole;
  final String action;
  final String targetType;
  final String targetId;
  final String description;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'actorName': actorName,
        'actorRole': actorRole,
        'action': action,
        'targetType': targetType,
        'targetId': targetId,
        'description': description,
      };

  factory AuditLogRecord.fromJson(Map<String, dynamic> m) => AuditLogRecord(
        id: m['id'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        actorName: (m['actorName'] as String?) ?? '',
        actorRole: (m['actorRole'] as String?) ?? '',
        action: (m['action'] as String?) ?? '',
        targetType: (m['targetType'] as String?) ?? '',
        targetId: (m['targetId'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
      );
}

class TaskRecord {
  TaskRecord({
    required this.id,
    required this.titleAr,
    required this.titleEn,
    required this.assignedEmployeeId,
    required this.priority,
    required this.createdAt,
    required this.dueAt,
    required this.assignedBy,
    this.description = '',
    this.status = 'pending',
    this.startedAt,
    this.completedAt,
  });

  final String id;
  String titleAr;
  String titleEn;
  String description;
  String assignedEmployeeId;
  String priority;
  final DateTime createdAt;
  DateTime dueAt;
  String assignedBy;
  String status;
  DateTime? startedAt;
  DateTime? completedAt;

  bool get done => status == 'completed';
  bool get isOverdue => !done && dueAt.isBefore(DateTime.now());

  Map<String, dynamic> toJson() => {
        'id': id,
        'titleAr': titleAr,
        'titleEn': titleEn,
        'description': description,
        'assignedEmployeeId': assignedEmployeeId,
        'priority': priority,
        'createdAt': createdAt.toIso8601String(),
        'dueAt': dueAt.toIso8601String(),
        'assignedBy': assignedBy,
        'status': status,
        'startedAt': startedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      };

  factory TaskRecord.fromJson(Map<String, dynamic> m) => TaskRecord(
        id: m['id'] as String,
        titleAr: m['titleAr'] as String,
        titleEn: (m['titleEn'] as String?) ?? m['titleAr'] as String,
        description: (m['description'] as String?) ?? '',
        assignedEmployeeId: m['assignedEmployeeId'] as String,
        priority: (m['priority'] as String?) ?? 'medium',
        createdAt: DateTime.parse(m['createdAt'] as String),
        dueAt: DateTime.parse(m['dueAt'] as String),
        assignedBy: (m['assignedBy'] as String?) ?? 'Management',
        status: (m['status'] as String?) ?? ((m['done'] as bool?) == true ? 'completed' : 'pending'),
        startedAt: m['startedAt'] == null ? null : DateTime.parse(m['startedAt'] as String),
        completedAt: m['completedAt'] == null ? null : DateTime.parse(m['completedAt'] as String),
      );
}

class StockMovement {
  StockMovement({
    required this.id,
    required this.type,
    required this.quantity,
    required this.note,
    required this.createdAt,
    this.productId = '',
    this.itemName = '',
    this.employeeId = '',
    this.employeeName = '',
    this.branch = 'Main',
    this.reference = '',
    this.amount = 0,
    this.operationUnit = '',
    this.operationQuantity = 0,
    this.unitsPerOperationUnit = 1,
  });

  final String id;
  final String productId;
  final String itemName;
  final String type;
  final int quantity;
  final String note;
  final DateTime createdAt;
  final String employeeId;
  final String employeeName;
  final String branch;
  final String reference;
  final double amount;
  final String operationUnit;
  final double operationQuantity;
  final int unitsPerOperationUnit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'itemName': itemName,
        'type': type,
        'quantity': quantity,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'employeeId': employeeId,
        'employeeName': employeeName,
        'branch': branch,
        'reference': reference,
        'amount': amount,
        'operationUnit': operationUnit,
        'operationQuantity': operationQuantity,
        'unitsPerOperationUnit': unitsPerOperationUnit,
      };

  factory StockMovement.fromJson(Map<String, dynamic> m) => StockMovement(
        id: m['id'] as String,
        productId: (m['productId'] as String?) ?? '',
        itemName: (m['itemName'] as String?) ?? '',
        type: m['type'] as String,
        quantity: (m['quantity'] as num).toInt(),
        note: (m['note'] as String?) ?? '',
        createdAt: DateTime.parse(m['createdAt'] as String),
        employeeId: (m['employeeId'] as String?) ?? '',
        employeeName: (m['employeeName'] as String?) ?? '',
        branch: (m['branch'] as String?) ?? 'Main',
        reference: (m['reference'] as String?) ?? '',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        operationUnit: (m['operationUnit'] as String?) ?? '',
        operationQuantity: (m['operationQuantity'] as num?)?.toDouble() ?? 0,
        unitsPerOperationUnit: (m['unitsPerOperationUnit'] as num?)?.toInt() ?? 1,
      );
}

class AttendanceRecord {
  AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.clockIn,
    this.clockOut,
    this.scheduledStartMinutes = -1,
    this.scheduledEndMinutes = -1,
    this.automaticClockOut = false,
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final DateTime clockIn;
  DateTime? clockOut;
  final int scheduledStartMinutes;
  final int scheduledEndMinutes;
  bool automaticClockOut;

  Duration get duration => (clockOut ?? DateTime.now()).difference(clockIn);
  bool get hasSchedule => scheduledStartMinutes >= 0 && scheduledEndMinutes >= 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'clockIn': clockIn.toIso8601String(),
        'clockOut': clockOut?.toIso8601String(),
        'scheduledStartMinutes': scheduledStartMinutes,
        'scheduledEndMinutes': scheduledEndMinutes,
        'automaticClockOut': automaticClockOut,
      };

  factory AttendanceRecord.fromJson(Map<String, dynamic> m) => AttendanceRecord(
        id: (m['id'] as String?) ?? 'att-${m['employeeId']}-${m['clockIn']}',
        employeeId: m['employeeId'] as String,
        employeeName: m['employeeName'] as String,
        clockIn: DateTime.parse(m['clockIn'] as String),
        clockOut: m['clockOut'] == null ? null : DateTime.parse(m['clockOut'] as String),
        scheduledStartMinutes: (m['scheduledStartMinutes'] as num?)?.toInt() ?? -1,
        scheduledEndMinutes: (m['scheduledEndMinutes'] as num?)?.toInt() ?? -1,
        automaticClockOut: (m['automaticClockOut'] as bool?) ?? false,
      );
}

class OvertimeRecord {
  OvertimeRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.startAt,
    required this.endAt,
    required this.createdBy,
    this.note = '',
    this.rateMultiplier = 1.0,
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final DateTime startAt;
  final DateTime endAt;
  final String createdBy;
  final String note;
  final double rateMultiplier;

  Duration get duration => endAt.difference(startAt);
  double get hours => duration.inMinutes / 60.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'startAt': startAt.toIso8601String(),
        'endAt': endAt.toIso8601String(),
        'createdBy': createdBy,
        'note': note,
        'rateMultiplier': rateMultiplier,
      };

  factory OvertimeRecord.fromJson(Map<String, dynamic> m) => OvertimeRecord(
        id: m['id'] as String,
        employeeId: m['employeeId'] as String,
        employeeName: (m['employeeName'] as String?) ?? '',
        startAt: DateTime.parse(m['startAt'] as String),
        endAt: DateTime.parse(m['endAt'] as String),
        createdBy: (m['createdBy'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        rateMultiplier: (m['rateMultiplier'] as num?)?.toDouble() ?? 1.0,
      );
}

class EmployeeAdvanceRecord {
  EmployeeAdvanceRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.createdAt,
    required this.amount,
    required this.givenBy,
    this.paymentMethod = 'Cash',
    this.note = '',
    this.settledAmount = 0,
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final DateTime createdAt;
  final double amount;
  final String givenBy;
  final String paymentMethod;
  final String note;
  double settledAmount;

  double get outstanding => (amount - settledAmount).clamp(0, amount).toDouble();

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'createdAt': createdAt.toIso8601String(),
        'amount': amount,
        'givenBy': givenBy,
        'paymentMethod': paymentMethod,
        'note': note,
        'settledAmount': settledAmount,
      };

  factory EmployeeAdvanceRecord.fromJson(Map<String, dynamic> m) => EmployeeAdvanceRecord(
        id: m['id'] as String,
        employeeId: m['employeeId'] as String,
        employeeName: (m['employeeName'] as String?) ?? '',
        createdAt: DateTime.parse(m['createdAt'] as String),
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        givenBy: (m['givenBy'] as String?) ?? '',
        paymentMethod: (m['paymentMethod'] as String?) ?? 'Cash',
        note: (m['note'] as String?) ?? '',
        settledAmount: (m['settledAmount'] as num?)?.toDouble() ?? 0,
      );
}

class LeaveRecord {
  LeaveRecord({
    required this.id,
    required this.employeeId,
    required this.start,
    required this.end,
    required this.type,
    required this.createdBy,
    this.note = '',
  });

  final String id;
  final String employeeId;
  final DateTime start;
  final DateTime end;
  final String type;
  final String createdBy;
  final String note;

  bool get activeNow {
    final now = DateTime.now();
    return !now.isBefore(start) && !now.isAfter(end.add(const Duration(days: 1)));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'type': type,
        'createdBy': createdBy,
        'note': note,
      };

  factory LeaveRecord.fromJson(Map<String, dynamic> m) => LeaveRecord(
        id: m['id'] as String,
        employeeId: m['employeeId'] as String,
        start: DateTime.parse(m['start'] as String),
        end: DateTime.parse(m['end'] as String),
        type: m['type'] as String,
        createdBy: (m['createdBy'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
      );
}

class PurchaseLine {
  PurchaseLine({
    required this.itemName,
    required this.quantity,
    required this.unitCost,
    this.productId = '',
    this.purchaseUnit = 'piece',
    this.unitsPerPurchaseUnit = 1,
    this.packageWeightKg = 0,
    this.saleUnit = 'piece',
    this.salePrice = 0,
    this.unitExpense = 0,
    this.note = '',
  });

  final String productId;
  final String itemName;
  final int quantity;
  final double unitCost;
  final String purchaseUnit;
  final int unitsPerPurchaseUnit;
  final double packageWeightKg;
  final String saleUnit;
  final double salePrice;
  final double unitExpense;
  final String note;

  int get baseQuantity => quantity * (unitsPerPurchaseUnit <= 0 ? 1 : unitsPerPurchaseUnit);
  double get purchaseSubtotal => quantity * unitCost;
  double get lineExpenses => quantity * unitExpense;
  double get total => purchaseSubtotal + lineExpenses;
  double get baseUnitCost => baseQuantity <= 0 ? 0 : total / baseQuantity;
  double get totalWeightKg => packageWeightKg <= 0 ? 0 : packageWeightKg * quantity;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'itemName': itemName,
        'quantity': quantity,
        'unitCost': unitCost,
        'purchaseUnit': purchaseUnit,
        'unitsPerPurchaseUnit': unitsPerPurchaseUnit,
        'packageWeightKg': packageWeightKg,
        'saleUnit': saleUnit,
        'salePrice': salePrice,
        'unitExpense': unitExpense,
        'note': note,
      };

  factory PurchaseLine.fromJson(Map<String, dynamic> m) => PurchaseLine(
        productId: (m['productId'] as String?) ?? '',
        itemName: m['itemName'] as String,
        quantity: (m['quantity'] as num).toInt(),
        unitCost: (m['unitCost'] as num?)?.toDouble() ?? 0,
        purchaseUnit: (m['purchaseUnit'] as String?) ?? 'piece',
        unitsPerPurchaseUnit: (m['unitsPerPurchaseUnit'] as num?)?.toInt() ?? 1,
        packageWeightKg: (m['packageWeightKg'] as num?)?.toDouble() ?? 0,
        saleUnit: (m['saleUnit'] as String?) ?? 'piece',
        salePrice: (m['salePrice'] as num?)?.toDouble() ?? 0,
        unitExpense: (m['unitExpense'] as num?)?.toDouble() ?? 0,
        note: (m['note'] as String?) ?? '',
      );
}

class PurchaseReceipt {
  PurchaseReceipt({
    required this.id,
    required this.number,
    required this.createdAt,
    required this.employeeId,
    required this.employeeName,
    required this.supplier,
    required this.lines,
    this.supplierId = '',
    this.branch = 'Main',
    this.vendorInvoiceNumber = '',
    this.paymentMethod = 'Cash',
    this.amountPaid = 0,
    this.shippingCost = 0,
    this.taxAmount = 0,
    this.dueDate,
    this.note = '',
    this.title = '',
    this.restockRequestId = '',
    this.restockRequestNumber = '',
  });

  final String id;
  final String number;
  final DateTime createdAt;
  final String employeeId;
  final String employeeName;
  final String supplier;
  final String supplierId;
  final String branch;
  final List<PurchaseLine> lines;
  final String vendorInvoiceNumber;
  final String paymentMethod;
  final double amountPaid;
  final double shippingCost;
  final double taxAmount;
  final DateTime? dueDate;
  final String note;
  final String title;
  final String restockRequestId;
  final String restockRequestNumber;

  double get merchandiseTotal => lines.fold<double>(0, (sum, line) => sum + line.total);
  double get extraCosts => shippingCost + taxAmount;
  double get total => merchandiseTotal + extraCosts;
  double get initialDue => (total - amountPaid).clamp(0, total).toDouble();

  double allocatedExtraFor(PurchaseLine line) {
    if (merchandiseTotal <= 0 || line.total <= 0) return 0;
    return extraCosts * (line.total / merchandiseTotal);
  }

  double landedBaseUnitCost(PurchaseLine line) {
    if (line.baseQuantity <= 0) return 0;
    return (line.total + allocatedExtraFor(line)) / line.baseQuantity;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'createdAt': createdAt.toIso8601String(),
        'employeeId': employeeId,
        'employeeName': employeeName,
        'supplier': supplier,
        'supplierId': supplierId,
        'branch': branch,
        'vendorInvoiceNumber': vendorInvoiceNumber,
        'paymentMethod': paymentMethod,
        'amountPaid': amountPaid,
        'shippingCost': shippingCost,
        'taxAmount': taxAmount,
        'dueDate': dueDate?.toIso8601String(),
        'note': note,
        'title': title,
        'restockRequestId': restockRequestId,
        'restockRequestNumber': restockRequestNumber,
        'lines': lines.map((e) => e.toJson()).toList(),
      };

  factory PurchaseReceipt.fromJson(Map<String, dynamic> m) => PurchaseReceipt(
        id: m['id'] as String,
        number: m['number'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        employeeId: (m['employeeId'] as String?) ?? '',
        employeeName: (m['employeeName'] as String?) ?? '',
        supplier: (m['supplier'] as String?) ?? 'Direct supplier',
        supplierId: (m['supplierId'] as String?) ?? '',
        branch: (m['branch'] as String?) ?? 'Main',
        vendorInvoiceNumber: (m['vendorInvoiceNumber'] as String?) ?? '',
        paymentMethod: (m['paymentMethod'] as String?) ?? 'Cash',
        amountPaid: (m['amountPaid'] as num?)?.toDouble() ?? 0,
        shippingCost: (m['shippingCost'] as num?)?.toDouble() ?? 0,
        taxAmount: (m['taxAmount'] as num?)?.toDouble() ?? 0,
        dueDate: m['dueDate'] == null ? null : DateTime.parse(m['dueDate'] as String),
        note: (m['note'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        restockRequestId: (m['restockRequestId'] as String?) ?? '',
        restockRequestNumber: (m['restockRequestNumber'] as String?) ?? '',
        lines: ((m['lines'] as List?) ?? [])
            .map((e) => PurchaseLine.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}


class PurchaseReturnLine {
  PurchaseReturnLine({
    required this.productId,
    required this.itemName,
    required this.quantity,
    required this.unitCost,
    this.returnUnit = 'piece',
    this.returnUnitQuantity = 0,
  });

  final String productId;
  final String itemName;
  /// Quantity removed from stock in the product base unit.
  final int quantity;
  final double unitCost;
  /// Unit selected by the user when returning to the supplier.
  final String returnUnit;
  /// Quantity entered in [returnUnit]. Kept for clear audit/history display.
  final int returnUnitQuantity;

  double get total => quantity * unitCost;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'itemName': itemName,
        'quantity': quantity,
        'unitCost': unitCost,
        'returnUnit': returnUnit,
        'returnUnitQuantity': returnUnitQuantity,
      };

  factory PurchaseReturnLine.fromJson(Map<String, dynamic> m) =>
      PurchaseReturnLine(
        productId: (m['productId'] as String?) ?? '',
        itemName: (m['itemName'] as String?) ?? '',
        quantity: (m['quantity'] as num?)?.toInt() ?? 0,
        unitCost: (m['unitCost'] as num?)?.toDouble() ?? 0,
        returnUnit: (m['returnUnit'] as String?) ?? 'piece',
        returnUnitQuantity: (m['returnUnitQuantity'] as num?)?.toInt() ??
            (m['quantity'] as num?)?.toInt() ?? 0,
      );
}

class PurchaseReturnRecord {
  PurchaseReturnRecord({
    required this.id,
    required this.purchaseId,
    required this.purchaseNumber,
    required this.createdAt,
    required this.supplierId,
    required this.supplierName,
    required this.lines,
    required this.processedBy,
    required this.processedById,
    this.reason = '',
    this.payableReduction = 0,
    this.cashRefund = 0,
    this.agreedRefundAmount = 0,
    this.remainingRefund = 0,
  });

  final String id;
  final String purchaseId;
  final String purchaseNumber;
  final DateTime createdAt;
  final String supplierId;
  final String supplierName;
  final List<PurchaseReturnLine> lines;
  final String processedBy;
  final String processedById;
  final String reason;
  /// Amount of the supplier debt cancelled by this return.
  final double payableReduction;
  /// Amount actually received from the supplier now.
  final double cashRefund;
  /// Amount agreed with the supplier for the returned goods.
  /// Older records fall back to [total].
  final double agreedRefundAmount;
  /// Amount still owed to us by the supplier after debt reduction and payment now.
  final double remainingRefund;

  double get total =>
      lines.fold<double>(0, (sum, line) => sum + line.total);
  double get agreedAmount => agreedRefundAmount > 0 ? agreedRefundAmount : total;
  double get paidNow => cashRefund;

  Map<String, dynamic> toJson() => {
        'id': id,
        'purchaseId': purchaseId,
        'purchaseNumber': purchaseNumber,
        'createdAt': createdAt.toIso8601String(),
        'supplierId': supplierId,
        'supplierName': supplierName,
        'processedBy': processedBy,
        'processedById': processedById,
        'reason': reason,
        'payableReduction': payableReduction,
        'cashRefund': cashRefund,
        'agreedRefundAmount': agreedRefundAmount,
        'remainingRefund': remainingRefund,
        'lines': lines.map((e) => e.toJson()).toList(),
      };

  factory PurchaseReturnRecord.fromJson(Map<String, dynamic> m) =>
      PurchaseReturnRecord(
        id: (m['id'] as String?) ?? '',
        purchaseId: (m['purchaseId'] as String?) ?? '',
        purchaseNumber: (m['purchaseNumber'] as String?) ?? '',
        createdAt: DateTime.parse(m['createdAt'] as String),
        supplierId: (m['supplierId'] as String?) ?? '',
        supplierName: (m['supplierName'] as String?) ?? '',
        processedBy: (m['processedBy'] as String?) ?? '',
        processedById: (m['processedById'] as String?) ?? '',
        reason: (m['reason'] as String?) ?? '',
        payableReduction:
            (m['payableReduction'] as num?)?.toDouble() ?? 0,
        cashRefund: (m['cashRefund'] as num?)?.toDouble() ?? 0,
        agreedRefundAmount:
            (m['agreedRefundAmount'] as num?)?.toDouble() ?? 0,
        remainingRefund: (m['remainingRefund'] as num?)?.toDouble() ?? 0,
        lines: ((m['lines'] as List?) ?? [])
            .map((e) =>
                PurchaseReturnLine.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class ProductNote {
  ProductNote({
    required this.id,
    required this.productId,
    required this.text,
    required this.audience,
    required this.createdBy,
    required this.createdAt,
    this.active = true,
  });

  final String id;
  final String productId;
  String text;
  String audience;
  String createdBy;
  final DateTime createdAt;
  bool active;

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'text': text,
        'audience': audience,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'active': active,
      };

  factory ProductNote.fromJson(Map<String, dynamic> m) => ProductNote(
        id: m['id'] as String,
        productId: m['productId'] as String,
        text: m['text'] as String,
        audience: (m['audience'] as String?) ?? 'both',
        createdBy: (m['createdBy'] as String?) ?? '',
        createdAt: DateTime.parse(m['createdAt'] as String),
        active: (m['active'] as bool?) ?? true,
      );
}

class CustomerRecord {
  CustomerRecord({
    required this.id,
    required this.accountNumber,
    required this.name,
    required this.phone,
    this.address = '',
    this.balance = 0,
    this.loyaltyPoints = 0,
    this.creditAllowed = false,
    this.creditLimit = 0,
    this.note = '',
    this.active = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String accountNumber;
  final DateTime createdAt;
  String name;
  String phone;
  String address;
  double balance;
  int loyaltyPoints;
  bool creditAllowed;
  double creditLimit;
  String note;
  bool active;

  double get availableCredit => creditAllowed
      ? (creditLimit <= 0 ? double.infinity : (creditLimit - balance).clamp(0, double.infinity).toDouble())
      : 0.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountNumber': accountNumber,
        'createdAt': createdAt.toIso8601String(),
        'name': name,
        'phone': phone,
        'address': address,
        'balance': balance,
        'loyaltyPoints': loyaltyPoints,
        'creditAllowed': creditAllowed,
        'creditLimit': creditLimit,
        'note': note,
        'active': active,
      };

  factory CustomerRecord.fromJson(Map<String, dynamic> m) => CustomerRecord(
        id: m['id'] as String,
        accountNumber: m['accountNumber'] as String,
        createdAt: m['createdAt'] == null ? null : DateTime.parse(m['createdAt'] as String),
        name: m['name'] as String,
        phone: m['phone'] as String,
        address: (m['address'] as String?) ?? '',
        balance: (m['balance'] as num?)?.toDouble() ?? 0,
        loyaltyPoints: (m['loyaltyPoints'] as num?)?.toInt() ?? 0,
        creditAllowed: (m['creditAllowed'] as bool?) ?? false,
        creditLimit: (m['creditLimit'] as num?)?.toDouble() ?? 0,
        note: (m['note'] as String?) ?? '',
        active: (m['active'] as bool?) ?? true,
      );
}

class SupplierRecord {
  SupplierRecord({
    required this.id,
    required this.accountNumber,
    required this.name,
    this.phone = '',
    this.address = '',
    this.openingBalance = 0,
    this.active = true,
  });

  final String id;
  final String accountNumber;
  String name;
  String phone;
  String address;
  double openingBalance;
  bool active;

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountNumber': accountNumber,
        'name': name,
        'phone': phone,
        'address': address,
        'openingBalance': openingBalance,
        'active': active,
      };

  factory SupplierRecord.fromJson(Map<String, dynamic> m) => SupplierRecord(
        id: m['id'] as String,
        accountNumber: (m['accountNumber'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        phone: (m['phone'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
        openingBalance: (m['openingBalance'] as num?)?.toDouble() ?? 0,
        active: (m['active'] as bool?) ?? true,
      );
}

class SupplierPaymentRecord {
  SupplierPaymentRecord({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.createdAt,
    required this.amount,
    required this.method,
    required this.employeeName,
    this.purchaseId = '',
    this.purchaseNumber = '',
    this.note = '',
    Map<String, double>? allocations,
  }) : allocations = allocations ?? <String, double>{};

  final String id;
  final String supplierId;
  final String supplierName;
  final DateTime createdAt;
  final double amount;
  final String method;
  final String employeeName;
  final String purchaseId;
  final String purchaseNumber;
  final String note;
  final Map<String, double> allocations;

  double allocatedTo(String purchaseId) => allocations[purchaseId] ?? 0;
  double get allocatedAmount => allocations.values.fold<double>(0, (sum, v) => sum + v);
  double get unallocatedAmount => (amount - allocatedAmount).clamp(0, amount).toDouble();

  Map<String, dynamic> toJson() => {
        'id': id,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'createdAt': createdAt.toIso8601String(),
        'amount': amount,
        'method': method,
        'employeeName': employeeName,
        'purchaseId': purchaseId,
        'purchaseNumber': purchaseNumber,
        'note': note,
        'allocations': allocations,
      };

  factory SupplierPaymentRecord.fromJson(Map<String, dynamic> m) => SupplierPaymentRecord(
        id: m['id'] as String,
        supplierId: (m['supplierId'] as String?) ?? '',
        supplierName: (m['supplierName'] as String?) ?? '',
        createdAt: DateTime.parse(m['createdAt'] as String),
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        method: (m['method'] as String?) ?? 'Cash',
        employeeName: (m['employeeName'] as String?) ?? '',
        purchaseId: (m['purchaseId'] as String?) ?? '',
        purchaseNumber: (m['purchaseNumber'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        allocations: ((m['allocations'] as Map?) ?? const {}).map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
      );
}

class CustomerPaymentRecord {
  CustomerPaymentRecord({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.createdAt,
    required this.amount,
    required this.method,
    required this.employeeName,
    this.note = '',
    Map<String, double>? allocations,
  }) : allocations = allocations ?? <String, double>{};

  final String id;
  final String customerId;
  final String customerName;
  final DateTime createdAt;
  final double amount;
  final String method;
  final String employeeName;
  final String note;
  final Map<String, double> allocations;

  double allocatedTo(String invoiceId) => allocations[invoiceId] ?? 0;
  double get allocatedAmount => allocations.values.fold<double>(0, (sum, v) => sum + v);

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerId': customerId,
        'customerName': customerName,
        'createdAt': createdAt.toIso8601String(),
        'amount': amount,
        'method': method,
        'employeeName': employeeName,
        'note': note,
        'allocations': allocations,
      };

  factory CustomerPaymentRecord.fromJson(Map<String, dynamic> m) => CustomerPaymentRecord(
        id: m['id'] as String,
        customerId: (m['customerId'] as String?) ?? '',
        customerName: (m['customerName'] as String?) ?? '',
        createdAt: DateTime.parse(m['createdAt'] as String),
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        method: (m['method'] as String?) ?? 'Cash',
        employeeName: (m['employeeName'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        allocations: ((m['allocations'] as Map?) ?? const {}).map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
      );
}

class ExpenseRecord {
  ExpenseRecord({
    required this.id,
    required this.createdAt,
    required this.category,
    required this.description,
    required this.amount,
    required this.employeeName,
    this.paymentMethod = 'Cash',
    this.sourceType = '',
    this.sourceId = '',
    this.payrollPeriod = '',
  });

  final String id;
  final DateTime createdAt;
  final String category;
  final String description;
  final double amount;
  final String employeeName;
  final String paymentMethod;
  final String sourceType;
  final String sourceId;
  final String payrollPeriod;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'category': category,
        'description': description,
        'amount': amount,
        'employeeName': employeeName,
        'paymentMethod': paymentMethod,
        'sourceType': sourceType,
        'sourceId': sourceId,
        'payrollPeriod': payrollPeriod,
      };

  factory ExpenseRecord.fromJson(Map<String, dynamic> m) => ExpenseRecord(
        id: m['id'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        category: (m['category'] as String?) ?? 'General',
        description: (m['description'] as String?) ?? '',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        employeeName: (m['employeeName'] as String?) ?? '',
        paymentMethod: (m['paymentMethod'] as String?) ?? 'Cash',
        sourceType: (m['sourceType'] as String?) ?? '',
        sourceId: (m['sourceId'] as String?) ?? '',
        payrollPeriod: (m['payrollPeriod'] as String?) ?? '',
      );
}

class StockCountLine {
  StockCountLine({
    required this.productId,
    required this.itemName,
    required this.expected,
    required this.actual,
    this.countUnit = 'piece',
    this.unitsPerCountUnit = 1,
    int? enteredQuantity,
    this.counted = false,
  }) : enteredQuantity = enteredQuantity ?? actual;

  final String productId;
  final String itemName;
  int expected;
  int actual;
  String countUnit;
  int unitsPerCountUnit;
  int enteredQuantity;
  bool counted;
  int get difference => actual - expected;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'itemName': itemName,
        'expected': expected,
        'actual': actual,
        'countUnit': countUnit,
        'unitsPerCountUnit': unitsPerCountUnit,
        'enteredQuantity': enteredQuantity,
        'counted': counted,
      };

  factory StockCountLine.fromJson(Map<String, dynamic> m) => StockCountLine(
        productId: m['productId'] as String,
        itemName: m['itemName'] as String,
        expected: (m['expected'] as num).toInt(),
        actual: (m['actual'] as num).toInt(),
        countUnit: (m['countUnit'] as String?) ?? 'piece',
        unitsPerCountUnit: (m['unitsPerCountUnit'] as num?)?.toInt() ?? 1,
        enteredQuantity: (m['enteredQuantity'] as num?)?.toInt(),
        counted: (m['counted'] as bool?) ?? true,
      );
}

class StockCountSession {
  StockCountSession({
    required this.id,
    required this.number,
    required this.createdAt,
    required this.employeeId,
    required this.employeeName,
    required this.lines,
    this.status = 'open',
    this.completedAt,
    this.submittedAt,
    this.requestedByName = '',
    this.requestedByRole = '',
    this.approvedByName = '',
    this.approvedByRole = '',
  });

  final String id;
  final String number;
  final DateTime createdAt;
  final String employeeId;
  final String employeeName;
  final List<StockCountLine> lines;
  String status;
  DateTime? completedAt;
  DateTime? submittedAt;
  String requestedByName;
  String requestedByRole;
  String approvedByName;
  String approvedByRole;

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'createdAt': createdAt.toIso8601String(),
        'employeeId': employeeId,
        'employeeName': employeeName,
        'status': status,
        'completedAt': completedAt?.toIso8601String(),
        'submittedAt': submittedAt?.toIso8601String(),
        'requestedByName': requestedByName,
        'requestedByRole': requestedByRole,
        'approvedByName': approvedByName,
        'approvedByRole': approvedByRole,
        'lines': lines.map((e) => e.toJson()).toList(),
      };

  factory StockCountSession.fromJson(Map<String, dynamic> m) => StockCountSession(
        id: m['id'] as String,
        number: m['number'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        employeeId: m['employeeId'] as String,
        employeeName: m['employeeName'] as String,
        status: (m['status'] as String?) ?? 'open',
        completedAt: m['completedAt'] == null ? null : DateTime.parse(m['completedAt'] as String),
        submittedAt: m['submittedAt'] == null ? null : DateTime.parse(m['submittedAt'] as String),
        requestedByName: (m['requestedByName'] as String?) ?? '',
        requestedByRole: (m['requestedByRole'] as String?) ?? '',
        approvedByName: (m['approvedByName'] as String?) ?? '',
        approvedByRole: (m['approvedByRole'] as String?) ?? '',
        lines: ((m['lines'] as List?) ?? [])
            .map((e) => StockCountLine.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}


class StockCountBreakdown {
  const StockCountBreakdown({
    required this.periodStart,
    required this.periodEnd,
    required this.openingStock,
    required this.received,
    required this.returned,
    required this.sold,
    required this.damaged,
    required this.transferredOut,
    required this.adjustments,
    required this.expected,
    required this.actual,
    required this.movements,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final int openingStock;
  final int received;
  final int returned;
  final int sold;
  final int damaged;
  final int transferredOut;
  final int adjustments;
  final int expected;
  final int actual;
  final List<StockMovement> movements;

  int get difference => actual - expected;
  int get reconciledExpected => openingStock + received + returned - sold - damaged - transferredOut + adjustments;
}

class GlobalSearchHit {
  const GlobalSearchHit({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
  });

  final String kind;
  final String id;
  final String title;
  final String subtitle;
}

class MessageRecord {
  MessageRecord({
    required this.id,
    required this.createdAt,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.recipientType,
    required this.body,
    this.recipientId = '',
    this.replyToId = '',
    List<String>? readBy,
    List<String>? hiddenBy,
  })  : readBy = readBy ?? <String>[],
        hiddenBy = hiddenBy ?? <String>[];

  final String id;
  final DateTime createdAt;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String recipientType;
  final String recipientId;
  final String body;
  final String replyToId;
  final List<String> readBy;
  final List<String> hiddenBy;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'senderId': senderId,
        'senderName': senderName,
        'senderRole': senderRole,
        'recipientType': recipientType,
        'recipientId': recipientId,
        'body': body,
        'replyToId': replyToId,
        'readBy': readBy,
        'hiddenBy': hiddenBy,
      };

  factory MessageRecord.fromJson(Map<String, dynamic> m) => MessageRecord(
        id: m['id'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        senderId: (m['senderId'] as String?) ?? '',
        senderName: (m['senderName'] as String?) ?? '',
        senderRole: (m['senderRole'] as String?) ?? '',
        recipientType: (m['recipientType'] as String?) ?? 'all_staff',
        recipientId: (m['recipientId'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        replyToId: (m['replyToId'] as String?) ?? '',
        readBy: ((m['readBy'] as List?) ?? []).map((e) => e.toString()).toList(),
        hiddenBy: ((m['hiddenBy'] as List?) ?? []).map((e) => e.toString()).toList(),
      );
}

class RestockRequestLine {
  RestockRequestLine({
    required this.productId,
    required this.itemName,
    required this.quantity,
    required this.unit,
    this.currentStock = 0,
    this.reorderLevel = 0,
    this.note = '',
  });

  final String productId;
  final String itemName;
  final double quantity;
  final String unit;
  final int currentStock;
  final int reorderLevel;
  final String note;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'itemName': itemName,
        'quantity': quantity,
        'unit': unit,
        'currentStock': currentStock,
        'reorderLevel': reorderLevel,
        'note': note,
      };

  factory RestockRequestLine.fromJson(Map<String, dynamic> m) => RestockRequestLine(
        productId: (m['productId'] as String?) ?? '',
        itemName: (m['itemName'] as String?) ?? '',
        quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
        unit: (m['unit'] as String?) ?? 'piece',
        currentStock: (m['currentStock'] as num?)?.toInt() ?? 0,
        reorderLevel: (m['reorderLevel'] as num?)?.toInt() ?? 0,
        note: (m['note'] as String?) ?? '',
      );
}

class RestockRequest {
  RestockRequest({
    required this.id,
    required this.number,
    required this.createdAt,
    required this.createdById,
    required this.createdByName,
    required this.createdByRole,
    required this.lines,
    this.status = 'requested',
    this.note = '',
    this.assignedRole = 'inventory',
    this.updatedAt,
    this.fulfilledPurchaseId = '',
    this.fulfilledPurchaseNumber = '',
    this.fulfilledById = '',
    this.fulfilledByName = '',
    this.fulfilledAt,
  });

  final String id;
  final String number;
  final DateTime createdAt;
  final String createdById;
  final String createdByName;
  final String createdByRole;
  final List<RestockRequestLine> lines;
  String status;
  String note;
  String assignedRole;
  DateTime? updatedAt;
  String fulfilledPurchaseId;
  String fulfilledPurchaseNumber;
  String fulfilledById;
  String fulfilledByName;
  DateTime? fulfilledAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'createdAt': createdAt.toIso8601String(),
        'createdById': createdById,
        'createdByName': createdByName,
        'createdByRole': createdByRole,
        'lines': lines.map((e) => e.toJson()).toList(),
        'status': status,
        'note': note,
        'assignedRole': assignedRole,
        'updatedAt': updatedAt?.toIso8601String(),
        'fulfilledPurchaseId': fulfilledPurchaseId,
        'fulfilledPurchaseNumber': fulfilledPurchaseNumber,
        'fulfilledById': fulfilledById,
        'fulfilledByName': fulfilledByName,
        'fulfilledAt': fulfilledAt?.toIso8601String(),
      };

  factory RestockRequest.fromJson(Map<String, dynamic> m) => RestockRequest(
        id: m['id'] as String,
        number: m['number'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        createdById: (m['createdById'] as String?) ?? '',
        createdByName: (m['createdByName'] as String?) ?? '',
        createdByRole: (m['createdByRole'] as String?) ?? '',
        lines: ((m['lines'] as List?) ?? [])
            .map((e) => RestockRequestLine.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        status: (m['status'] as String?) ?? 'requested',
        note: (m['note'] as String?) ?? '',
        assignedRole: (m['assignedRole'] as String?) ?? 'inventory',
        updatedAt: m['updatedAt'] == null ? null : DateTime.parse(m['updatedAt'] as String),
        fulfilledPurchaseId: (m['fulfilledPurchaseId'] as String?) ?? '',
        fulfilledPurchaseNumber: (m['fulfilledPurchaseNumber'] as String?) ?? '',
        fulfilledById: (m['fulfilledById'] as String?) ?? '',
        fulfilledByName: (m['fulfilledByName'] as String?) ?? '',
        fulfilledAt: m['fulfilledAt'] == null ? null : DateTime.parse(m['fulfilledAt'] as String),
      );
}

class JournalLine {
  const JournalLine({required this.accountCode, required this.accountName, this.debit = 0, this.credit = 0});
  final String accountCode;
  final String accountName;
  final double debit;
  final double credit;
  Map<String, dynamic> toJson() => {'accountCode': accountCode, 'accountName': accountName, 'debit': debit, 'credit': credit};
  factory JournalLine.fromJson(Map<String, dynamic> m) => JournalLine(accountCode: m['accountCode'] as String, accountName: (m['accountName'] as String?) ?? '', debit: (m['debit'] as num?)?.toDouble() ?? 0, credit: (m['credit'] as num?)?.toDouble() ?? 0);
}

class JournalEntry {
  JournalEntry({required this.id, required this.number, required this.createdAt, required this.reference, required this.description, required this.lines, this.sourceType = '', this.sourceId = ''});
  final String id;
  final String number;
  final DateTime createdAt;
  final String reference;
  final String description;
  final List<JournalLine> lines;
  final String sourceType;
  final String sourceId;
  double get totalDebit => lines.fold<double>(0, (s, l) => s + l.debit);
  double get totalCredit => lines.fold<double>(0, (s, l) => s + l.credit);
  bool get balanced => (totalDebit - totalCredit).abs() < 0.005;
  Map<String, dynamic> toJson() => {'id': id, 'number': number, 'createdAt': createdAt.toIso8601String(), 'reference': reference, 'description': description, 'sourceType': sourceType, 'sourceId': sourceId, 'lines': lines.map((e) => e.toJson()).toList()};
  factory JournalEntry.fromJson(Map<String, dynamic> m) => JournalEntry(id: m['id'] as String, number: m['number'] as String, createdAt: DateTime.parse(m['createdAt'] as String), reference: (m['reference'] as String?) ?? '', description: (m['description'] as String?) ?? '', sourceType: (m['sourceType'] as String?) ?? '', sourceId: (m['sourceId'] as String?) ?? '', lines: ((m['lines'] as List?) ?? []).map((e) => JournalLine.fromJson((e as Map).cast<String, dynamic>())).toList());
}

class AccountingSnapshot {
  const AccountingSnapshot({required this.cash, required this.bank, required this.receivables, required this.inventory, required this.fixedAssetsNet, required this.payables, required this.salesTaxPayable, required this.equity});
  final double cash;
  final double bank;
  final double receivables;
  final double inventory;
  final double fixedAssetsNet;
  final double payables;
  final double salesTaxPayable;
  final double equity;
  double get totalAssets => cash + bank + receivables + inventory + fixedAssetsNet;
  double get totalLiabilities => payables + salesTaxPayable;
}

class FinancialPeriodSummary {
  const FinancialPeriodSummary({
    required this.netSales,
    required this.collected,
    required this.purchases,
    required this.purchaseReturns,
    required this.supplierReturnReceivables,
    required this.supplierPaid,
    required this.costOfSales,
    required this.expenses,
    required this.depreciation,
    required this.salesTax,
    required this.grossProfit,
    required this.netProfit,
    required this.cashFlow,
  });

  final double netSales;
  final double collected;
  final double purchases;
  final double purchaseReturns;
  final double supplierReturnReceivables;
  final double supplierPaid;
  final double costOfSales;
  final double expenses;
  final double depreciation;
  final double salesTax;
  final double grossProfit;
  final double netProfit;
  final double cashFlow;
}

class AssetRecord {
  AssetRecord({
    required this.id,
    required this.name,
    required this.purchaseDate,
    required this.purchasePrice,
    required this.annualDepreciationRate,
    this.category = 'General',
    this.note = '',
    this.active = true,
  });

  final String id;
  String name;
  String category;
  DateTime purchaseDate;
  double purchasePrice;
  double annualDepreciationRate;
  String note;
  bool active;

  double bookValueAt(DateTime date) {
    final days = date.difference(purchaseDate).inDays.clamp(0, 36500);
    final years = days / 365.0;
    final value = purchasePrice * (1 - annualDepreciationRate / 100 * years);
    return value.clamp(0, purchasePrice).toDouble();
  }

  double accumulatedDepreciationAt(DateTime date) => purchasePrice - bookValueAt(date);

  double depreciationForPeriod(DateTime start, DateTime endExclusive) {
    if (!active || annualDepreciationRate <= 0 || purchasePrice <= 0) return 0;
    final effectiveStart = purchaseDate.isAfter(start) ? purchaseDate : start;
    if (!effectiveStart.isBefore(endExclusive)) return 0;
    final days = endExclusive.difference(effectiveStart).inHours / 24.0;
    final annual = purchasePrice * (annualDepreciationRate / 100);
    final amount = annual * (days / 365.0);
    final remaining = bookValueAt(effectiveStart);
    return amount.clamp(0, remaining).toDouble();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'purchaseDate': purchaseDate.toIso8601String(),
        'purchasePrice': purchasePrice,
        'annualDepreciationRate': annualDepreciationRate,
        'note': note,
        'active': active,
      };

  factory AssetRecord.fromJson(Map<String, dynamic> m) => AssetRecord(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        category: (m['category'] as String?) ?? 'General',
        purchaseDate: DateTime.parse(m['purchaseDate'] as String),
        purchasePrice: (m['purchasePrice'] as num?)?.toDouble() ?? 0,
        annualDepreciationRate: (m['annualDepreciationRate'] as num?)?.toDouble() ?? 0,
        note: (m['note'] as String?) ?? '',
        active: (m['active'] as bool?) ?? true,
      );
}

class StoreSettings {
  StoreSettings({
    this.storeName = '',
    this.currency = '₪',
    this.branchName = '',
    this.taxPercent = 0,
    this.receiptFooter = '',
    this.allowCashierReturns = true,
    this.requireClockOutConfirmation = true,
    this.lowStockNotifications = true,
    this.taskNotifications = true,
  });

  String storeName;
  String currency;
  String branchName;
  double taxPercent;
  String receiptFooter;
  bool allowCashierReturns;
  bool requireClockOutConfirmation;
  bool lowStockNotifications;
  bool taskNotifications;

  Map<String, dynamic> toJson() => {
        'storeName': storeName,
        'currency': currency,
        'branchName': branchName,
        'taxPercent': taxPercent,
        'receiptFooter': receiptFooter,
        'allowCashierReturns': allowCashierReturns,
        'requireClockOutConfirmation': requireClockOutConfirmation,
        'lowStockNotifications': lowStockNotifications,
        'taskNotifications': taskNotifications,
      };

  factory StoreSettings.fromJson(Map<String, dynamic> m) => StoreSettings(
        storeName: (m['storeName'] as String?) ?? '',
        currency: (m['currency'] as String?) ?? '₪',
        branchName: (m['branchName'] as String?) ?? '',
        taxPercent: (m['taxPercent'] as num?)?.toDouble() ?? 0,
        receiptFooter: (m['receiptFooter'] as String?) ?? '',
        allowCashierReturns: (m['allowCashierReturns'] as bool?) ?? true,
        requireClockOutConfirmation: (m['requireClockOutConfirmation'] as bool?) ?? true,
        lowStockNotifications: (m['lowStockNotifications'] as bool?) ?? true,
        taskNotifications: (m['taskNotifications'] as bool?) ?? true,
      );
}

String _hm(int minutes) {
  final normalized = ((minutes % 1440) + 1440) % 1440;
  final h24 = normalized ~/ 60;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final m = (normalized % 60).toString().padLeft(2, '0');
  final period = h24 < 12 ? 'صباحًا' : 'مساءً';
  return '$h12:$m $period';
}
