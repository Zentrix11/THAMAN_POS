import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/time_format.dart';
import '../../app/app_theme.dart';
import '../../core/app_controller.dart';
import '../../core/app_strings.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/brand_pattern.dart';
import '../../core/widgets/language_switch.dart';
import '../../core/widgets/logout_confirmation.dart';
import '../../core/printing/print_service.dart';
import '../../core/printing/print_templates.dart';
import '../../data/app_data_store.dart';
import '../../data/models.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key, this.managementMode = false});
  final bool managementMode;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final store = AppDataStore.instance;
  final search = TextEditingController();
  final Map<String, int> cart = {};
  int selectedCategory = 0;
  String selectedCustomerId = '';
  String selectedCustomerName = 'Walk-in';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  double get total => cart.entries.fold<double>(0, (sum, entry) {
        final product = store.product(entry.key);
        return sum + product.price * entry.value;
      });

  int get itemCount => cart.values.fold(0, (sum, value) => sum + value);

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmLeave(s) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            return BrandPattern(
              borderRadius: BorderRadius.zero,
              child: SafeArea(
                child: Column(
                children: [
                  _header(s),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 960;
                        return Row(
                          children: [
                            Expanded(child: _catalog(s)),
                            if (wide)
                              SizedBox(
                                width: constraints.maxWidth >= 1380 ? 410 : 370,
                                child: _cartPanel(s),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
                ),
              ),
            );
          },
        ),
        floatingActionButton: MediaQuery.sizeOf(context).width >= 960
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _showCartSheet(s),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                label: Text('${s.text('السلة', 'Cart')} • $itemCount • ${total.toStringAsFixed(2)} ${AppDataStore.instance.settings.currency}'),
              ),
      ),
    );
  }

  Widget _header(AppStrings s) {
    final controller = s.controller;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 760;

    return Container(
      height: compact ? 78 : 86,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton.outlined(
            tooltip: widget.managementMode ? s.text('العودة للإدارة', 'Back to management') : s.text('تسجيل الخروج', 'Sign out'),
            onPressed: () => _handleExit(s),
            icon: Icon(controller.isArabic ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded, size: 19),
          ),
          const SizedBox(width: 10),
          if (!compact) const AppLogo(compact: true),
          if (!compact) const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(30)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 7, height: 7, child: DecoratedBox(decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle))),
                const SizedBox(width: 7),
                Text(s.text('وردية مفتوحة', 'Shift open'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.primary)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (!widget.managementMode && controller.employeeId != null && width >= 760) ...[
            _AttendanceHeaderButton(s: s),
            const SizedBox(width: 8),
          ],
          if (width >= 980)
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: TextField(
                  controller: search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (value) => _scanBarcodeToCart(value, s),
                  decoration: InputDecoration(
                    hintText: s.text('ابحث بالاسم، SKU أو امسح الباركود...', 'Search name, SKU or scan barcode...'),
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    suffixIcon: const Icon(Icons.qr_code_scanner_rounded, size: 19, color: AppColors.muted),
                    isDense: true,
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          if (width >= 680) ...[
            _HeaderAction(
              icon: Icons.pause_circle_outline_rounded,
              label: s.text('المعلقة', 'Held'),
              badge: store.heldSales.length,
              onTap: () => _showHeldSales(s),
            ),
            const SizedBox(width: 7),
            _HeaderAction(icon: Icons.receipt_long_outlined, label: s.text('الفواتير', 'Invoices'), onTap: () => _showInvoices(s)),
            const SizedBox(width: 7),
            _HeaderAction(icon: Icons.assignment_return_outlined, label: s.text('إرجاع', 'Return'), onTap: () => _showReturnSelector(s), emphasized: true),
            const SizedBox(width: 8),
          ] else ...[
            PopupMenuButton<String>(
              tooltip: s.text('المزيد', 'More'),
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (value) {
                if (value == 'held') _showHeldSales(s);
                if (value == 'invoices') _showInvoices(s);
                if (value == 'return') _showReturnSelector(s);
                if (value == 'attendance') _showAttendanceAction(s);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'held', child: Text('${s.text('الفواتير المعلقة', 'Held invoices')} (${store.heldSales.length})')),
                PopupMenuItem(value: 'invoices', child: Text(s.text('الفواتير', 'Invoices'))),
                PopupMenuItem(value: 'return', child: Text(s.text('إرجاع بضاعة', 'Return goods'))),
                if (!widget.managementMode && controller.employeeId != null) PopupMenuItem(value: 'attendance', child: Text(store.currentAttendance(controller.employeeId!) == null ? s.text('تسجيل حضور', 'Clock in') : s.text('تسجيل انصراف', 'Clock out'))),
              ],
            ),
          ],
          const LanguageSwitch(compact: true),
        ],
      ),
    );
  }

  Future<void> _showAttendanceAction(AppStrings s) async {
    final id = s.controller.employeeId;
    if (id == null) return;
    final current = store.currentAttendance(id);
    if (current == null) {
      store.clockIn(id, s.controller.currentUserName);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('تم تسجيل الحضور.', 'Clock-in recorded.'))));
      return;
    }
    if (!store.settings.requireClockOutConfirmation) { store.clockOut(id); return; }
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
          scrollable: true,
      title: Text(s.text('تأكيد تسجيل الانصراف', 'Confirm clock out')),
      content: Text(s.text('هل أنت متأكد من تسجيل الانصراف الآن؟', 'Are you sure you want to clock out now?')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.text('إلغاء', 'Cancel'))), FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.text('تسجيل الانصراف', 'Clock out')))],
    ));
    if (ok == true) store.clockOut(id);
  }

  Widget _catalog(AppStrings s) {
    final categories = <_Category>[
      _Category(s.text('الكل', 'All'), null),
      _Category(s.text('مشروبات', 'Drinks'), 'Drinks'),
      _Category(s.text('مواد غذائية', 'Groceries'), 'Groceries'),
      _Category(s.text('حلويات', 'Sweets'), 'Sweets'),
      _Category(s.text('ألبان', 'Dairy'), 'Dairy'),
      _Category(s.text('المنزل', 'Home'), 'Home'),
    ];
    final query = search.text.trim().toLowerCase();
    final category = categories[selectedCategory].key;
    final products = store.products.where((product) {
      final categoryMatches = category == null || product.categoryEn == category;
      final queryMatches = query.isEmpty ||
          product.nameAr.contains(query) ||
          product.nameEn.toLowerCase().contains(query) ||
          product.sku.toLowerCase().contains(query) ||
          product.barcode.contains(query);
      return categoryMatches && queryMatches;
    }).toList();

    return Container(
      color: AppColors.background.withValues(alpha: .9),
      child: Column(
        children: [
          if (MediaQuery.sizeOf(context).width < 980)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
              child: TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                onSubmitted: (value) => _scanBarcodeToCart(value, s),
                decoration: InputDecoration(
                  hintText: s.text('بحث أو باركود...', 'Search or barcode...'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  isDense: true,
                ),
              ),
            ),
          SizedBox(
            height: 60,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final selected = selectedCategory == index;
                return ChoiceChip(
                  selected: selected,
                  onSelected: (_) => setState(() => selectedCategory = index),
                  showCheckmark: false,
                  selectedColor: AppColors.primary,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  label: Text(categories[index].label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.text)),
                );
              },
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth >= 1180 ? 5 : c.maxWidth >= 880 ? 4 : c.maxWidth >= 600 ? 3 : 2;
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 5, 14, 100),
                  itemCount: products.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: c.maxWidth < 500 ? .84 : .96,
                  ),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return _ProductCard(
                      product: product,
                      s: s,
                      inCart: cart[product.id] ?? 0,
                      onTap: product.stock <= 0 ? null : () => _addProduct(product),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartPanel(AppStrings s) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: AppColors.border), right: BorderSide(color: AppColors.border))),
      child: _CartContent(
        s: s,
        cart: cart,
        total: total,
        itemCount: itemCount,
        onQty: _changeQty,
        onSetQty: _setQty,
        onClear: cart.isEmpty ? null : () => setState(cart.clear),
        onHold: cart.isEmpty ? null : () => _holdSale(s),
        onPay: cart.isEmpty ? null : () => _showPayment(s),
      ),
    );
  }

  void _scanBarcodeToCart(String raw, AppStrings s) {
    final code = raw.trim();
    if (code.isEmpty) return;
    final product = store.productByBarcodeOrSku(code);
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('لم يتم العثور على صنف بهذا الباركود أو SKU.', 'No product found for this barcode or SKU.'))));
      return;
    }
    if (product.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('الصنف غير متوفر في المخزون.', 'This item is out of stock.'))));
      return;
    }
    _addProduct(product);
    search.clear();
  }

  void _addProduct(ProductModel product) {
    final s = AppStrings(AppScope.of(context));
    final current = cart[product.id] ?? 0;
    if (current >= product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('الكمية المتاحة لا تسمح', 'Insufficient stock'))));
      return;
    }
    setState(() => cart[product.id] = current + 1);
  }

  void _changeQty(String productId, int delta) {
    _setQty(productId, (cart[productId] ?? 0) + delta);
  }

  void _setQty(String productId, int quantity) {
    final product = store.productOrNull(productId);
    if (product == null) return;
    setState(() {
      if (quantity <= 0) {
        cart.remove(productId);
        return;
      }
      final next = quantity > product.stock ? product.stock : quantity;
      cart[productId] = next;
    });
    if (product.stock > 0 && quantity > product.stock && mounted) {
      final s = AppStrings(AppScope.of(context));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.text(
              'الحد الأقصى المتاح ${product.stock}',
              'Maximum available is ${product.stock}',
            ),
          ),
        ),
      );
    }
  }

  void _holdSale(AppStrings s) {
    if (cart.isEmpty) return;
    final held = store.holdSale(cart, cashierId: s.controller.employeeId ?? '', cashierName: s.controller.currentUserName, customer: selectedCustomerName);
    setState(cart.clear);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('تم تعليق الفاتورة', 'Sale held')} • ${held.label}')));
  }

  Future<void> _showCartSheet(AppStrings s) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Directionality(
        textDirection: s.controller.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: Container(
          height: MediaQuery.sizeOf(context).height * .82,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          child: StatefulBuilder(
            builder: (context, sheetSetState) {
              return _CartContent(
                s: s,
                cart: cart,
                total: total,
                itemCount: itemCount,
                onQty: (id, delta) {
                  _changeQty(id, delta);
                  sheetSetState(() {});
                },
                onSetQty: (id, qty) {
                  _setQty(id, qty);
                  sheetSetState(() {});
                },
                onClear: cart.isEmpty
                    ? null
                    : () {
                        setState(cart.clear);
                        sheetSetState(() {});
                      },
                onHold: cart.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        _holdSale(s);
                      },
                onPay: cart.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        _showPayment(s);
                      },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showPayment(AppStrings s) async {
    if (cart.isEmpty) return;
    if (selectedCustomerId.isNotEmpty) {
      final selected = store.customerOrNull(selectedCustomerId);
      if (selected == null || !selected.active) {
        selectedCustomerId = '';
        selectedCustomerName = 'Walk-in';
      }
    }
    String method = 'Cash';
    final invoiceTitle = TextEditingController();
    final paidNow = TextEditingController(text: total.toStringAsFixed(2));
    String? paymentError;
    bool customerFieldError = false;
    bool paidFieldError = false;
    await showDialog<void>(
      context: context,
      builder: (context) => Directionality(
        textDirection: s.controller.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, dialogSetState) => AlertDialog(
          scrollable: true,
            title: Row(
              children: [
                Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.payments_outlined, color: AppColors.primary, size: 19)),
                const SizedBox(width: 10),
                Expanded(child: Text(s.text('إتمام الدفع', 'Complete payment'))),
              ],
            ),
            content: SizedBox(
              width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 420.0).toDouble(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: AppColors.primaryStrong, borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.text('الإجمالي المستحق', 'Amount due'), style: const TextStyle(color: Color(0xFFBDD4CF), fontSize: 9.5)),
                        const SizedBox(height: 5),
                        Text('${total.toStringAsFixed(2)} ${AppDataStore.instance.settings.currency}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: invoiceTitle,
                    decoration: InputDecoration(
                      labelText: s.text('اسم الفاتورة (اختياري)', 'Invoice name (optional)'),
                      hintText: s.text('مثال: طلبية أحمد', 'Example: Ahmad order'),
                      prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(s.text('العميل', 'Customer'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      border: customerFieldError ? Border.all(color: AppColors.danger, width: 1.6) : null,
                    ),
                    child: DropdownMenu<String>(
                      enableFilter: true,
                      enableSearch: true,
                      expandedInsets: EdgeInsets.zero,
                      initialSelection: selectedCustomerId.isEmpty ? 'walk-in' : selectedCustomerId,
                      dropdownMenuEntries: [
                        DropdownMenuEntry(value: 'walk-in', label: s.text('عميل نقدي / بدون حساب', 'Walk-in customer')),
                        ...store.customers.where((customer) => customer.active).map((customer) => DropdownMenuEntry(value: customer.id, label: '${customer.name} • ${customer.phone} • ${customer.accountNumber}')),
                      ],
                      onSelected: (value) {
                        if (value == null || value == 'walk-in') {
                          selectedCustomerId = '';
                          selectedCustomerName = 'Walk-in';
                        } else {
                          final customer = store.customerOrNull(value);
                          if (customer != null) {
                            selectedCustomerId = customer.id;
                            selectedCustomerName = customer.name;
                          }
                        }
                        dialogSetState(() {
                          customerFieldError = false;
                          paymentError = null;
                        });
                      },
                    ),
                  ),
                  if (selectedCustomerId.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Builder(builder: (_) {
                      final customer = store.customerOrNull(selectedCustomerId);
                      if (customer == null) return const SizedBox.shrink();
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(11)),
                        child: Wrap(spacing: 14, runSpacing: 6, children: [
                          Text('${s.text('الرصيد المستحق', 'Current due')}: ${customer.balance.toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 8.8, fontWeight: FontWeight.w800)),
                          Text(customer.creditAllowed ? '${s.text('حد الائتمان', 'Credit limit')}: ${customer.creditLimit <= 0 ? s.text('بدون حد', 'Unlimited') : '${customer.creditLimit.toStringAsFixed(2)} ${store.settings.currency}'}' : s.text('الشراء بالدين غير مسموح', 'Credit sales disabled'), style: TextStyle(fontSize: 8.8, fontWeight: FontWeight.w800, color: customer.creditAllowed ? AppColors.primary : AppColors.danger)),
                        ]),
                      );
                    }),
                  ],
                  const SizedBox(height: 16),
                  Text(s.text('طريقة الدفع', 'Payment method'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in const [('Cash', Icons.payments_outlined), ('Card', Icons.credit_card_rounded), ('Wallet', Icons.account_balance_wallet_outlined), ('Debt', Icons.schedule_rounded)])
                        ChoiceChip(
                          selected: method == entry.$1,
                          onSelected: (_) => dialogSetState(() {
                            method = entry.$1;
                            paidNow.text = method == 'Debt' ? '0' : total.toStringAsFixed(2);
                            paymentError = null;
                            customerFieldError = false;
                            paidFieldError = false;
                          }),
                          showCheckmark: false,
                          avatar: Icon(entry.$2, size: 16, color: method == entry.$1 ? Colors.white : AppColors.primary),
                          label: Text(_paymentLabel(s, entry.$1)),
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: method == entry.$1 ? Colors.white : AppColors.text),
                        ),
                    ],
                  ),
                  if (method == 'Debt') ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: paidNow,
                      onChanged: (_) => dialogSetState(() { paymentError = null; paidFieldError = false; }),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: s.text('المبلغ المدفوع الآن', 'Amount paid now'),
                        helperText: s.text('المتبقي يُسجل تلقائيًا على حساب العميل.', 'The remaining amount is added to the customer account.'),
                        prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                        enabledBorder: paidFieldError ? const OutlineInputBorder(borderSide: BorderSide(color: AppColors.danger, width: 1.6)) : null,
                        focusedBorder: paidFieldError ? const OutlineInputBorder(borderSide: BorderSide(color: AppColors.danger, width: 1.8)) : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Builder(builder: (_) {
                      final paid = double.tryParse(paidNow.text) ?? 0;
                      final due = (total - paid).clamp(0, total).toDouble();
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [Expanded(child: Text(s.text('المبلغ الآجل', 'Amount on account'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800))), Text('${due.toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.accent))]),
                      );
                    }),
                  ],
                  if (paymentError != null) ...[
                    const SizedBox(height: 9),
                    Text(paymentError!, style: const TextStyle(fontSize: 9, color: AppColors.danger, fontWeight: FontWeight.w800)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.text('إلغاء', 'Cancel'))),
              FilledButton.icon(
                onPressed: () {
                  double paid = total;
                  if (method == 'Debt') {
                    if (selectedCustomerId.isEmpty) {
                      dialogSetState(() {
                        customerFieldError = true;
                        paymentError = s.text('البيع الآجل يحتاج اختيار عميل مسجل.', 'Credit sale requires a registered customer.');
                      });
                      return;
                    }
                    paid = double.tryParse(paidNow.text.trim()) ?? -1;
                    if (paid < 0 || paid > total) {
                      dialogSetState(() {
                        paidFieldError = true;
                        paymentError = s.text('المبلغ المدفوع يجب أن يكون بين صفر وإجمالي الفاتورة.', 'Paid amount must be between zero and the invoice total.');
                      });
                      return;
                    }
                    final due = (total - paid).clamp(0, total).toDouble();
                    final creditError = store.validateCreditSale(selectedCustomerId, due);
                    if (creditError != null) {
                      final text = switch (creditError) {
                        'credit_not_allowed' => s.text('هذا العميل غير مسموح له بالشراء بالدين. يجب أن يفعّل المدير أو المالك هذه الصلاحية من ملف العميل.', 'Credit sales are disabled for this customer. Owner/manager must enable them in the customer profile.'),
                        'credit_limit_exceeded' => s.text('هذه الفاتورة ستتجاوز حد الائتمان المحدد للعميل.', 'This sale would exceed the customer credit limit.'),
                        _ => s.text('تعذر استخدام الحساب الآجل لهذا العميل.', 'This customer cannot use credit for this sale.'),
                      };
                      dialogSetState(() => paymentError = text);
                      return;
                    }
                  }
                  SaleInvoice invoice;
                  try {
                    invoice = store.completeSale(cart: cart, cashier: s.controller.currentUserName, cashierId: s.controller.employeeId ?? '', paymentMethod: method, customer: selectedCustomerName, customerId: selectedCustomerId, paidAmount: paid, invoiceTitle: invoiceTitle.text.trim());
                  } on StateError {
                    dialogSetState(() => paymentError = s.text('تعذر إتمام الفاتورة بسبب إعدادات حساب العميل.', 'Could not complete the sale because of customer account settings.'));
                    return;
                  }
                  setState(cart.clear);
                  Navigator.of(context).pop();
                  Future<void>.delayed(const Duration(milliseconds: 120), () {
                    if (mounted) _showSaleCompleted(s, invoice);
                  });
                },
                icon: const Icon(Icons.check_rounded, size: 17),
                label: Text(s.text('تأكيد الدفع', 'Confirm payment')),
              ),
            ],
          ),
        ),
      ),
    );
    invoiceTitle.dispose();
    paidNow.dispose();
  }

  Future<void> _showSaleCompleted(AppStrings s, SaleInvoice invoice) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
          scrollable: true,
        title: Row(children: [const Icon(Icons.check_circle_rounded, color: AppColors.success), const SizedBox(width: 9), Expanded(child: Text(s.text('تمت عملية البيع', 'Sale completed')))]),
        content: SizedBox(
          width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 430.0).toDouble(),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _ReceiptDetail(label: s.text('رقم الفاتورة', 'Invoice number'), value: invoice.number),
            if(invoice.title.trim().isNotEmpty) _ReceiptDetail(label:s.text('اسم الفاتورة','Invoice name'),value:invoice.title.trim()),
            _ReceiptDetail(label: s.text('الإجمالي', 'Total'), value: '${invoice.total.toStringAsFixed(2)} ${store.settings.currency}'),
            _ReceiptDetail(label: s.text('المدفوع', 'Paid'), value: '${invoice.receivedAtSale.toStringAsFixed(2)} ${store.settings.currency}'),
            if (invoice.dueAmount > 0) _ReceiptDetail(label: s.text('المتبقي على العميل', 'Customer due'), value: '${invoice.dueAmount.toStringAsFixed(2)} ${store.settings.currency}'),
          ]),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () => ThamanPrintService.printDocument(ThamanPrintTemplates.saleInvoice(store, invoice, isArabic: s.controller.isArabic)),
            icon: const Icon(Icons.print_outlined, size: 17),
            label: Text(s.text('طباعة الفاتورة', 'Print invoice')),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(s.text('تم', 'Done'))),
        ],
      ),
    );
  }

  Future<void> _showHeldSales(AppStrings s) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Directionality(
        textDirection: s.controller.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: _HeldSalesSheet(
          s: s,
          store: store,
          onRestore: (sale) {
            if (cart.isNotEmpty) {
              ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text(s.text('علّق أو أفرغ السلة الحالية أولًا.', 'Hold or clear the current cart first.'))));
              return;
            }
            final restored = store.takeHeldSale(sale.id);
            setState(() => cart.addAll(restored));
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _showInvoices(AppStrings s) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Directionality(
        textDirection: s.controller.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: _InvoicesSheet(
          s: s,
          store: store,
          allowReturn: true,
          onReturn: (invoice) {
            Navigator.of(context).pop();
            Future<void>.delayed(const Duration(milliseconds: 180), () => _showReturnDialog(s, invoice));
          },
        ),
      ),
    );
  }

  Future<void> _showReturnSelector(AppStrings s) async {
    if (!widget.managementMode && !store.settings.allowCashierReturns) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('المرتجعات للكاشير معطلة من إعدادات الإدارة.', 'Cashier returns are disabled by management settings.'))));
      return;
    }
    if (store.invoices.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Directionality(
        textDirection: s.controller.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: _InvoicesSheet(
          s: s,
          store: store,
          title: s.text('اختر فاتورة للإرجاع', 'Choose invoice to return'),
          allowReturn: true,
          onReturn: (invoice) {
            Navigator.of(context).pop();
            Future<void>.delayed(const Duration(milliseconds: 180), () => _showReturnDialog(s, invoice));
          },
        ),
      ),
    );
  }

  Future<void> _showReturnDialog(AppStrings s, SaleInvoice invoice) async {
    final quantities = <String, int>{};
    final reason = TextEditingController(text: s.text('إرجاع من العميل', 'Customer return'));
    const supportedRefundMethods = {'Cash', 'Card', 'Wallet'};
    String refundMethod = supportedRefundMethods.contains(invoice.paymentMethod)
        ? invoice.paymentMethod
        : 'Cash';
    await showDialog<void>(
      context: context,
      builder: (context) => Directionality(
        textDirection: s.controller.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, dialogSetState) {
            final refundTotal = invoice.lines.fold<double>(0, (sum, line) => sum + (quantities[line.productId] ?? 0) * line.unitPrice);
            return AlertDialog(
          scrollable: true,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.text('إرجاع بضاعة', 'Return goods')),
                  const SizedBox(height: 4),
                  Text(invoice.number, style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w600)),
                ],
              ),
              content: SizedBox(
                width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 560.0).toDouble(),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final line in invoice.lines) ...[
                        Builder(
                          builder: (_) {
                            final max = store.availableReturnQuantity(invoice, line);
                            final qty = quantities[line.productId] ?? 0;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(s.text(line.nameAr, line.nameEn), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 3),
                                        Text('${line.unitPrice.toStringAsFixed(2)} ${AppDataStore.instance.settings.currency} • ${s.text('متاح للإرجاع', 'Returnable')}: $max', style: const TextStyle(fontSize: 8.8, color: AppColors.muted)),
                                      ],
                                    ),
                                  ),
                                  IconButton.outlined(onPressed: qty <= 0 ? null : () => dialogSetState(() => quantities[line.productId] = qty - 1), icon: const Icon(Icons.remove_rounded, size: 16)),
                                  SizedBox(width: 34, child: Center(child: Text('$qty', style: const TextStyle(fontWeight: FontWeight.w900)))),
                                  IconButton.filled(onPressed: qty >= max ? null : () => dialogSetState(() => quantities[line.productId] = qty + 1), icon: const Icon(Icons.add_rounded, size: 16)),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextField(controller: reason, decoration: InputDecoration(labelText: s.text('سبب الإرجاع', 'Return reason'), prefixIcon: const Icon(Icons.notes_rounded, size: 18))),
                      const SizedBox(height: 11),
                      DropdownButtonFormField<String>(
                        value: refundMethod,
                        decoration: InputDecoration(labelText: s.text('طريقة رد المبلغ', 'Refund method'), prefixIcon: const Icon(Icons.currency_exchange_rounded, size: 18)),
                        items: const ['Cash', 'Card', 'Wallet']
                            .map((value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_paymentLabel(s, value)),
                                ))
                            .toList(),
                        onChanged: (value) => dialogSetState(() => refundMethod = value ?? refundMethod),
                      ),
                      const SizedBox(height: 13),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          children: [
                            Expanded(child: Text(s.text('قيمة المرتجع', 'Refund total'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
                            Text('${refundTotal.toStringAsFixed(2)} ${AppDataStore.instance.settings.currency}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.accent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.text('إلغاء', 'Cancel'))),
                FilledButton.icon(
                  onPressed: refundTotal <= 0
                      ? null
                      : () {
                          final record = store.returnSale(invoice: invoice, quantities: quantities, reason: reason.text.trim(), refundMethod: refundMethod, processedBy: s.controller.currentUserName, processedById: s.controller.employeeId ?? '');
                          Navigator.of(context).pop();
                          if (record != null) {
                            ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('${s.text('تم تسجيل المرتجع وإعادة الكمية للمخزون', 'Return recorded and stock restored')} • ${record.total.toStringAsFixed(2)} ${AppDataStore.instance.settings.currency}')));
                          }
                        },
                  icon: const Icon(Icons.assignment_return_rounded, size: 17),
                  label: Text(s.text('تأكيد الإرجاع', 'Confirm return')),
                ),
              ],
            );
          },
        ),
      ),
    );
    reason.dispose();
  }

  Future<bool> _confirmLeave(AppStrings s) async {
    if (cart.isEmpty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
          scrollable: true,
        title: Text(s.text('فاتورة غير مكتملة', 'Open sale')),
        content: Text(s.text('السلة تحتوي على أصناف. هل تريد الخروج بدون حفظها؟', 'The cart contains items. Leave without saving it?')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.text('البقاء', 'Stay'))),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.text('خروج', 'Leave'))),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handleExit(AppStrings s) async {
    if (!await _confirmLeave(s)) return;
    if (!mounted) return;
    if (widget.managementMode) {
      Navigator.of(context).pop();
      return;
    }
    final controller = AppScope.of(context);
    if (!await confirmSignOut(context, s) || !mounted) return;
    controller.signOut();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}


class _ReceiptDetail extends StatelessWidget {
  const _ReceiptDetail({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [Expanded(child: Text(label, style: const TextStyle(fontSize: 9, color: AppColors.muted))), Text(value, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900))]),
      );
}

class _AttendanceHeaderButton extends StatelessWidget {
  const _AttendanceHeaderButton({required this.s});
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final id = s.controller.employeeId ?? '';
    final current = store.currentAttendance(id);
    final clockedIn = current != null;
    return clockedIn
        ? OutlinedButton.icon(
            onPressed: () => _clockOut(context, store, id),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: Text(s.text('انصراف', 'Clock out'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
          )
        : FilledButton.tonalIcon(
            onPressed: () => store.clockIn(id, s.controller.currentUserName),
            icon: const Icon(Icons.login_rounded, size: 16),
            label: Text(s.text('حضور', 'Clock in'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
          );
  }

  Future<void> _clockOut(BuildContext context, AppDataStore store, String id) async {
    if (!store.settings.requireClockOutConfirmation) { store.clockOut(id); return; }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
          scrollable: true,
        title: Text(s.text('تأكيد تسجيل الانصراف', 'Confirm clock out')),
        content: Text(s.text('هل أنت متأكد من تسجيل الانصراف الآن؟', 'Are you sure you want to clock out now?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.text('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.text('تسجيل الانصراف', 'Clock out'))),
        ],
      ),
    );
    if (ok == true) store.clockOut(id);
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.icon, required this.label, required this.onTap, this.badge = 0, this.emphasized = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final button = emphasized
        ? FilledButton.tonalIcon(onPressed: onTap, icon: Icon(icon, size: 17), label: Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)))
        : OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 17), label: Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)));
    if (badge <= 0) return button;
    return Badge(label: Text('$badge'), offset: const Offset(-4, -4), child: button);
  }
}

class _Category {
  const _Category(this.label, this.key);
  final String label;
  final String? key;
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.s, required this.inCart, required this.onTap});
  final ProductModel product;
  final AppStrings s;
  final int inCart;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final low = product.stock <= product.minStock;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: inCart > 0 ? AppColors.primary.withValues(alpha: .5) : AppColors.border),
            boxShadow: const [BoxShadow(color: Color(0x08083A34), blurRadius: 15, offset: Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: _productTint(product.categoryEn), borderRadius: BorderRadius.circular(12)),
                    child: Icon(_productIcon(product.categoryEn), color: AppColors.primary, size: 19),
                  ),
                  const Spacer(),
                  if (inCart > 0)
                    Container(
                      width: 25,
                      height: 25,
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text('$inCart', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                    ),
                ],
              ),
              const Spacer(),
              Text(s.text(product.nameAr, product.nameEn), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, height: 1.35)),
              const SizedBox(height: 4),
              Text(product.sku, style: const TextStyle(fontSize: 8.2, color: AppColors.muted, letterSpacing: .5)),
              const SizedBox(height: 9),
              Row(
                children: [
                  Text('${product.price.toStringAsFixed(2)} ${AppDataStore.instance.settings.currency}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.primary)),
                  const Spacer(),
                  Text('${product.stock}', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: low ? AppColors.danger : AppColors.muted)),
                  const SizedBox(width: 3),
                  Icon(low ? Icons.warning_amber_rounded : Icons.inventory_2_outlined, size: 13, color: low ? AppColors.danger : AppColors.muted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _productTint(String category) => switch (category) {
        'Drinks' => const Color(0xFFEAF4F7),
        'Sweets' => const Color(0xFFFFF1EA),
        'Dairy' => const Color(0xFFF0F0FA),
        'Home' => const Color(0xFFF3F1EA),
        _ => AppColors.primarySoft,
      };

  static IconData _productIcon(String category) => switch (category) {
        'Drinks' => Icons.local_drink_outlined,
        'Sweets' => Icons.cookie_outlined,
        'Dairy' => Icons.breakfast_dining_outlined,
        'Home' => Icons.home_outlined,
        _ => Icons.shopping_basket_outlined,
      };
}

class _CartContent extends StatelessWidget {
  const _CartContent({
    required this.s,
    required this.cart,
    required this.total,
    required this.itemCount,
    required this.onQty,
    required this.onSetQty,
    required this.onClear,
    required this.onHold,
    required this.onPay,
  });

  final AppStrings s;
  final Map<String, int> cart;
  final double total;
  final int itemCount;
  final void Function(String productId, int delta) onQty;
  final void Function(String productId, int quantity) onSetQty;
  final VoidCallback? onClear;
  final VoidCallback? onHold;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.shopping_bag_outlined, color: AppColors.primary, size: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.text('الفاتورة الحالية', 'Current sale'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
                    Text('${s.text('عدد القطع', 'Items')}: $itemCount', style: const TextStyle(fontSize: 8.8, color: AppColors.muted)),
                  ],
                ),
              ),
              IconButton(onPressed: onClear, tooltip: s.text('تفريغ السلة', 'Clear cart'), icon: const Icon(Icons.delete_outline_rounded, size: 19)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: cart.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 58, height: 58, decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.shopping_cart_outlined, color: AppColors.muted, size: 24)),
                      const SizedBox(height: 12),
                      Text(s.text('السلة فارغة', 'Cart is empty'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text(s.text('اضغط على منتج لإضافته.', 'Tap a product to add it.'), style: const TextStyle(fontSize: 9, color: AppColors.muted)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: cart.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = cart.entries.elementAt(index);
                    final product = store.product(entry.key);
                    return Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.text(product.nameAr, product.nameEn), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.8, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 3),
                                Text('${product.price.toStringAsFixed(2)} ${AppDataStore.instance.settings.currency}', style: const TextStyle(fontSize: 8.5, color: AppColors.muted)),
                              ],
                            ),
                          ),
                          _TinyButton(icon: Icons.remove_rounded, onTap: () => onQty(product.id, -1)),
                          _QtyField(
                            value: entry.value,
                            max: product.stock,
                            onSubmitted: (qty) => onSetQty(product.id, qty),
                          ),
                          _TinyButton(icon: Icons.add_rounded, filled: true, onTap: () => onQty(product.id, 1)),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
          child: Column(
            children: [
              Row(children: [Expanded(child: Text(s.text('المجموع الفرعي', 'Subtotal'), style: const TextStyle(fontSize: 9.5, color: AppColors.muted))), Text('${total.toStringAsFixed(2)} ${AppDataStore.instance.settings.currency}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800))]),
              const SizedBox(height: 5),
              Row(children: [Expanded(child: Text(s.text('الضريبة', 'Tax'), style: const TextStyle(fontSize: 9.5, color: AppColors.muted))), Text('0.00 ${AppDataStore.instance.settings.currency}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800))]),
              const Divider(height: 22),
              Row(children: [Expanded(child: Text(s.text('الإجمالي', 'Total'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))), Text('${total.toStringAsFixed(2)} ${AppDataStore.instance.settings.currency}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primary))]),
              const SizedBox(height: 13),
              Row(
                children: [
                  Expanded(child: OutlinedButton.icon(onPressed: onHold, icon: const Icon(Icons.pause_rounded, size: 17), label: Text(s.text('تعليق', 'Hold')))),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: FilledButton.icon(onPressed: onPay, icon: const Icon(Icons.payments_outlined, size: 17), label: Text(s.text('الدفع', 'Pay')))),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QtyField extends StatefulWidget {
  const _QtyField({required this.value, required this.max, required this.onSubmitted});
  final int value;
  final int max;
  final ValueChanged<int> onSubmitted;

  @override
  State<_QtyField> createState() => _QtyFieldState();
}

class _QtyFieldState extends State<_QtyField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focus = FocusNode();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _QtyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != '${widget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = '${widget.value}';
      return;
    }
    widget.onSubmitted(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        ),
        onSubmitted: (_) => _commit(),
        onEditingComplete: _commit,
      ),
    );
  }
}

class _TinyButton extends StatelessWidget {
  const _TinyButton({required this.icon, required this.onTap, this.filled = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: filled
          ? IconButton.filled(padding: EdgeInsets.zero, onPressed: onTap, icon: Icon(icon, size: 14))
          : IconButton.outlined(padding: EdgeInsets.zero, onPressed: onTap, icon: Icon(icon, size: 14)),
    );
  }
}

class _HeldSalesSheet extends StatelessWidget {
  const _HeldSalesSheet({required this.s, required this.store, required this.onRestore});
  final AppStrings s;
  final AppDataStore store;
  final ValueChanged<HeldSale> onRestore;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * .72,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(
        children: [
          _SheetHeader(title: s.text('الفواتير المعلقة', 'Held sales'), subtitle: s.text('استرجع أي فاتورة وأكمل البيع من حيث توقفت.', 'Restore a held sale and continue where you left off.')),
          Expanded(
            child: AnimatedBuilder(
              animation: store,
              builder: (context, _) => store.heldSales.isEmpty
                  ? _EmptyState(icon: Icons.pause_circle_outline_rounded, title: s.text('لا توجد فواتير معلقة', 'No held sales'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: store.heldSales.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final sale = store.heldSales[index];
                        final count = sale.lines.values.fold(0, (a, b) => a + b);
                        final value = sale.lines.entries.fold<double>(0, (sum, e) => sum + store.product(e.key).price * e.value);
                        return _RowCard(
                          icon: Icons.pause_rounded,
                          title: '${sale.label} • $count ${s.text('قطعة', 'items')}',
                          subtitle: '${_time(sale.createdAt)} • ${value.toStringAsFixed(2)} ${AppDataStore.instance.settings.currency}',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(onPressed: () => store.deleteHeldSale(sale.id), tooltip: s.text('حذف', 'Delete'), icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 18)),
                              const SizedBox(width: 4),
                              FilledButton.tonal(onPressed: () => onRestore(sale), child: Text(s.text('استرجاع', 'Restore'))),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoicesSheet extends StatelessWidget {
  const _InvoicesSheet({required this.s, required this.store, required this.allowReturn, required this.onReturn, this.title});
  final AppStrings s;
  final AppDataStore store;
  final bool allowReturn;
  final ValueChanged<SaleInvoice> onReturn;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * .78,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(
        children: [
          _SheetHeader(title: title ?? s.text('الفواتير الأخيرة', 'Recent invoices'), subtitle: s.text('عرض الفواتير المنجزة والوصول السريع إلى المرتجعات.', 'Review completed invoices and start returns quickly.')),
          Expanded(
            child: store.invoices.isEmpty && store.returns.isEmpty
                ? _EmptyState(icon: Icons.receipt_long_outlined, title: s.text('لا توجد فواتير', 'No invoices'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: store.invoices.length + store.returns.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index >= store.invoices.length) {
                        final record = store.returns[index - store.invoices.length];
                        return _RowCard(
                          icon: Icons.assignment_return_rounded,
                          title: '${s.text('مرتجع', 'Return')} • ${record.invoiceNumber} • -${record.total.toStringAsFixed(2)} ${store.settings.currency}',
                          subtitle: '${_time(record.createdAt)} • ${record.lines.fold<int>(0, (sum, l) => sum + l.quantity)} ${s.text('قطعة', 'items')} • ${s.text('من فاتورة', 'from invoice')} ${record.invoiceNumber}',
                          trailing: const Icon(Icons.check_circle_outline_rounded, color: AppColors.success),
                        );
                      }
                      final invoice = store.invoices[index];
                      final returned = store.returns.where((r) => r.invoiceId == invoice.id).fold<double>(0, (sum, r) => sum + r.total);
                      return _RowCard(
                        icon: Icons.receipt_long_outlined,
                        title: '${invoice.number}${invoice.title.trim().isEmpty ? '' : ' • ${invoice.title.trim()}'} • ${invoice.total.toStringAsFixed(2)} ${AppDataStore.instance.settings.currency}',
                        subtitle: '${_time(invoice.createdAt)} • ${invoice.itemCount} ${s.text('قطعة', 'items')} • ${_paymentLabel(s, invoice.paymentMethod)}${returned > 0 ? ' • ${s.text('مرتجع', 'Returned')}: ${returned.toStringAsFixed(2)}' : ''}',
                        trailing: Wrap(
                          spacing: 6,
                          children: [
                            IconButton.outlined(
                              tooltip: s.text('طباعة الفاتورة', 'Print invoice'),
                              onPressed: () => ThamanPrintService.printDocument(ThamanPrintTemplates.saleInvoice(store, invoice, isArabic: s.controller.isArabic)),
                              icon: const Icon(Icons.print_outlined, size: 16),
                            ),
                            if (allowReturn) FilledButton.tonalIcon(onPressed: () => onReturn(invoice), icon: const Icon(Icons.assignment_return_outlined, size: 16), label: Text(s.text('إرجاع', 'Return'))),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(fontSize: 9.5, color: AppColors.muted))])),
          IconButton.outlined(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded, size: 18)),
        ],
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.icon, required this.title, required this.subtitle, this.trailing});
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: AppColors.primary, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(fontSize: 8.8, color: AppColors.muted))])),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title});
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 36, color: AppColors.muted), const SizedBox(height: 10), Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted))]));
  }
}

String _time(DateTime date) => formatHour12(date);

String _paymentLabel(AppStrings s, String method) {
  return switch (method) {
    'Cash' => s.text('نقدي', 'Cash'),
    'Card' => s.text('بطاقة', 'Card'),
    'Wallet' => s.text('محفظة', 'Wallet'),
    'Debt' => s.text('آجل', 'Debt'),
    _ => method,
  };
}
