import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/printing/print_document.dart';
import '../../../core/printing/print_service.dart';
import '../../../data/app_data_store.dart';
import '../../../data/models.dart';
import '../widgets/management_widgets.dart';

class RestockRequestsSection extends StatefulWidget {
  const RestockRequestsSection({super.key, required this.s});
  final AppStrings s;

  @override
  State<RestockRequestsSection> createState() => _RestockRequestsSectionState();
}

class _RestockRequestsSectionState extends State<RestockRequestsSection> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final store = AppDataStore.instance;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final q = search.text.trim().toLowerCase();
        final rows = store.restockRequests.where((r) {
          if (q.isEmpty) return true;
          return r.number.toLowerCase().contains(q) || r.createdByName.toLowerCase().contains(q) || r.lines.any((l) => l.itemName.toLowerCase().contains(q));
        }).toList();
        return Column(children: [
          ManagementMetricsGrid(items: [
            ManagementMetric(s.text('طلبات مفتوحة', 'Open requests'), '${store.openRestockRequests.length}', Icons.pending_actions_outlined, AppColors.accent),
            ManagementMetric(s.text('كل الطلبات', 'All requests'), '${store.restockRequests.length}', Icons.shopping_cart_checkout_outlined, AppColors.primary),
            ManagementMetric(s.text('تنبيهات حالية', 'Current alerts'), '${store.lowStock.length}', Icons.warning_amber_rounded, AppColors.danger),
            ManagementMetric(s.text('تم استلامها', 'Received'), '${store.restockRequests.where((r) => r.status == 'received').length}', Icons.task_alt_rounded, AppColors.success),
          ]),
          const SizedBox(height: 12),
          SurfaceCard(padding: EdgeInsets.zero, child: Column(children: [
            SectionCardHeader(
              title: s.text('طلبات إعادة التوريد', 'Restock requests'),
              subtitle: s.text('طلبات فعلية مرتبطة بالأصناف منخفضة المخزون ويمكن متابعتها حتى الاستلام.', 'Track low-stock requests from creation through receiving.'),
              trailing: Wrap(spacing: 8, runSpacing: 8, children: [
                SearchField(controller: search, hint: s.text('طلب أو صنف...', 'Request or item...'), onChanged: (_) => setState(() {}), width: 230),
                OutlinedButton.icon(onPressed:()=>_printRequests(rows),icon:const Icon(Icons.print_outlined,size:16),label:Text(s.text('طباعة','Print'))),
                FilledButton.icon(onPressed: () => _create(context), icon: const Icon(Icons.add_shopping_cart_rounded, size: 17), label: Text(s.text('طلب بضاعة', 'Create request'))),
              ]),
            ),
            const Divider(height: 1),
            if (rows.isEmpty) EmptyPanel(message: s.text('لا توجد طلبات مطابقة.', 'No matching requests.'), icon: Icons.shopping_cart_checkout_outlined)
            else for (final r in rows) ...[
              ListTile(
                onTap: () => _details(context, r),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: _statusColor(r.status).withValues(alpha: .09), borderRadius: BorderRadius.circular(13)), child: Icon(Icons.shopping_cart_checkout_outlined, color: _statusColor(r.status), size: 19)),
                title: Row(children: [Expanded(child: Text('${r.number} • ${r.lines.length} ${s.text('صنف', 'items')}', style: const TextStyle(fontSize: 10.4, fontWeight: FontWeight.w900))), StatusPill(label: _statusLabel(s, r.status), color: _statusColor(r.status))]),
                subtitle: Text('${r.createdByName} • ${formatDateTime(r.createdAt)} • ${r.lines.map((e) => e.itemName).take(3).join(s.text('، ', ', '))}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8.4, color: AppColors.muted)),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 18),
              ),
              if (r != rows.last) const Divider(height: 1),
            ],
          ])),
        ]);
      },
    );
  }


  Future<void> _printRequests(List<RestockRequest> rows) async {
    final store=AppDataStore.instance; final s=widget.s;
    await ThamanPrintService.printDocument(PrintDocument(
      title:s.text('كشف طلبات إعادة التوريد','Restock Requests Statement'),
      subtitle:'${store.settings.storeName} • ${store.settings.branchName}',
      metadata:{s.text('عدد الطلبات','Requests'):'${rows.length}',s.text('فلتر البحث','Search filter'):search.text.trim().isEmpty?'-':search.text.trim()},
      headers:[s.text('الطلب','Request'),s.text('التاريخ','Date'),s.text('أنشأه','Created by'),s.text('الحالة','Status'),s.text('الأصناف','Items'),s.text('الملاحظة','Note')],
      rows:rows.map((r)=>[r.number,formatDateTime(r.createdAt),r.createdByName,_statusLabel(s,r.status),r.lines.map((l)=>'${l.itemName}: ${l.quantity} ${l.unit}').join(' | '),r.note]).toList(),
      footer:store.settings.receiptFooter,
    
      isArabic: widget.s.controller.isArabic,));
  }

  Future<void> _create(BuildContext context) async {
    final s = widget.s;
    final store = AppDataStore.instance;
    final selected = <String, TextEditingController>{};
    final searchController = TextEditingController();
    final note = TextEditingController();
    String query = '';
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (dialogContext, setD) {
        final products = store.products.where((p) => p.active && (query.isEmpty || p.nameAr.toLowerCase().contains(query) || p.nameEn.toLowerCase().contains(query) || p.sku.toLowerCase().contains(query))).toList();
        return AlertDialog(
          scrollable: true,
          title: Text(s.text('إنشاء طلب بضاعة', 'Create restock request')),
          content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 760.0).toDouble(), height: MediaQuery.sizeOf(context).height * .68, child: Column(children: [
            TextField(controller: searchController, onChanged: (v) => setD(() => query = v.trim().toLowerCase()), decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: s.text('ابحث واختر أكثر من صنف...', 'Search and select multiple items...'))),
            const SizedBox(height: 10),
            Expanded(child: ListView.separated(itemCount: products.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (_, index) {
              final p = products[index];
              final checked = selected.containsKey(p.id);
              return CheckboxListTile(
                value: checked,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) => setD(() {
                  if (v == true) {
                    final suggested = ((p.minStock * 2) - p.stock).clamp(1, 99999);
                    selected[p.id] = TextEditingController(text: '$suggested');
                  } else {
                    selected.remove(p.id)?.dispose();
                  }
                }),
                title: Text(s.text(p.nameAr, p.nameEn), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                subtitle: Text('${p.sku} • ${s.text('الحالي', 'Current')}: ${p.stock} • ${s.text('حد الطلب', 'Reorder')}: ${p.minStock}', style: const TextStyle(fontSize: 8.8, color: AppColors.muted)),
                secondary: checked ? SizedBox(width: 110, child: TextField(controller: selected[p.id], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('الكمية', 'Qty')))) : null,
              );
            })),
            const SizedBox(height: 10),
            TextField(controller: note, maxLines: 2, decoration: InputDecoration(labelText: s.text('ملاحظة للطلب', 'Request note'))),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton(onPressed: selected.isEmpty ? null : () {
              final lines = <RestockRequestLine>[];
              for (final entry in selected.entries) {
                final p = store.product(entry.key);
                final qty = double.tryParse(entry.value.text.trim()) ?? 0;
                if (qty <= 0) continue;
                lines.add(RestockRequestLine(productId: p.id, itemName: p.nameAr, quantity: qty, unit: p.baseUnit, currentStock: p.stock, reorderLevel: p.minStock));
              }
              if (lines.isEmpty) return;
              final role = s.controller.role?.name ?? 'manager';
              store.createRestockRequest(lines: lines, createdById: 'ADMIN-$role', createdByName: s.controller.currentUserName.isEmpty ? role : s.controller.currentUserName, createdByRole: role, note: note.text.trim());
              Navigator.pop(dialogContext);
            }, child: Text(s.text('إنشاء الطلب وإشعار المخزون', 'Create & notify inventory'))),
          ],
        );
      }),
    );
    for (final c in selected.values) { c.dispose(); }
    searchController.dispose();
    note.dispose();
  }

  Future<void> _details(BuildContext context, RestockRequest request) async {
    final s = widget.s;
    final store = AppDataStore.instance;
    await showDialog<void>(context: context, builder: (_) => StatefulBuilder(builder: (dialogContext, setD) => AlertDialog(
          scrollable: true,
      title: Row(children: [Expanded(child: Text(request.number)), StatusPill(label: _statusLabel(s, request.status), color: _statusColor(request.status))]),
      content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 650.0).toDouble(), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DetailLine(label: s.text('أنشأه', 'Created by'), value: '${request.createdByName} • ${request.createdByRole}'),
        DetailLine(label: s.text('التاريخ', 'Date'), value: formatDateTime(request.createdAt)),
        if (request.fulfilledPurchaseNumber.isNotEmpty)
          DetailLine(
            label: s.text('تم التوريد بفاتورة', 'Fulfilled by purchase'),
            value: '${request.fulfilledPurchaseNumber} • ${request.fulfilledByName} • ${request.fulfilledAt == null ? '' : formatDateTime(request.fulfilledAt!)}',
          ),
        if (request.note.isNotEmpty) DetailLine(label: s.text('الملاحظة', 'Note'), value: request.note),
        const Divider(height: 24),
        Text(s.text('الأصناف المطلوبة', 'Requested items'), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        for (final line in request.lines) Container(margin: const EdgeInsets.only(bottom: 7), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)), child: Row(children: [Expanded(child: Text(line.itemName, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900))), Text('${line.quantity.toStringAsFixed(line.quantity % 1 == 0 ? 0 : 2)} ${s.unit(line.unit)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primary))])),
      ]))),
      actions: [
        OutlinedButton.icon(onPressed:()=>ThamanPrintService.printDocument(PrintDocument(title:s.text('طلب إعادة توريد','Restock Request'),subtitle:request.number,metadata:{s.text('أنشأه','Created by'):request.createdByName,s.text('التاريخ','Date'):formatDateTime(request.createdAt),s.text('الحالة','Status'):_statusLabel(s,request.status)},headers:[s.text('الصنف','Item'),s.text('الكمية','Quantity'),s.text('الوحدة','Unit'),s.text('المخزون الحالي','Current stock'),s.text('حد الطلب','Reorder level')],rows:request.lines.map((l)=>[l.itemName,l.quantity.toStringAsFixed(l.quantity%1==0?0:2),s.unit(l.unit),'${l.currentStock}','${l.reorderLevel}']).toList(),notes:[if(request.note.isNotEmpty)request.note],footer:store.settings.receiptFooter,
      isArabic: s.controller.isArabic,)),icon:const Icon(Icons.print_outlined,size:16),label:Text(s.text('طباعة','Print'))),
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.text('إغلاق', 'Close'))),
        PopupMenuButton<String>(onSelected: (status) { final role = s.controller.role?.name ?? 'manager'; store.updateRestockStatus(requestId: request.id, status: status, actorName: s.controller.currentUserName, actorRole: role); setD(() {}); }, itemBuilder: (_) => [
          PopupMenuItem(value: 'requested', child: Text(s.text('مطلوب', 'Requested'))),
          PopupMenuItem(value: 'reviewing', child: Text(s.text('قيد المراجعة', 'Reviewing'))),
          PopupMenuItem(value: 'ordered', child: Text(s.text('تم الطلب', 'Ordered'))),
          PopupMenuItem(value: 'received', child: Text(s.text('تم الاستلام', 'Received'))),
          PopupMenuItem(value: 'cancelled', child: Text(s.text('ملغي', 'Cancelled'))),
        ], child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text(s.text('تغيير الحالة', 'Change status'), style: const TextStyle(fontWeight: FontWeight.w800)))),
      ],
    )));
  }
}

String _statusLabel(AppStrings s, String status) => switch (status) {
  'reviewing' => s.text('قيد المراجعة', 'Reviewing'),
  'ordered' => s.text('تم الطلب', 'Ordered'),
  'received' => s.text('تم', 'Done'),
  'cancelled' => s.text('ملغي', 'Cancelled'),
  _ => s.text('مطلوب', 'Requested'),
};

Color _statusColor(String status) => switch (status) {
  'reviewing' => AppColors.blue,
  'ordered' => AppColors.accent,
  'received' => AppColors.success,
  'cancelled' => AppColors.danger,
  _ => AppColors.primary,
};
