import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/printing/print_service.dart';
import '../../../core/printing/print_templates.dart';
import '../../../data/app_data_store.dart';
import '../../../data/models.dart';
import '../widgets/management_widgets.dart';

class SalesSection extends StatefulWidget {
  const SalesSection({super.key, required this.s});
  final AppStrings s;
  @override
  State<SalesSection> createState() => _SalesSectionState();
}

class _SalesSectionState extends State<SalesSection> {
  final search = TextEditingController();
  @override
  void dispose() { search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final s = widget.s;
    return AnimatedBuilder(animation: store, builder: (context, _) {
      final q = search.text.trim().toLowerCase();
      final invoices = store.invoices.where((invoice) {
        return q.isEmpty || invoice.number.toLowerCase().contains(q) || invoice.title.toLowerCase().contains(q) || invoice.cashier.toLowerCase().contains(q) || invoice.cashierId.toLowerCase().contains(q) || invoice.customer.toLowerCase().contains(q) || invoice.paymentMethod.toLowerCase().contains(q);
      }).toList();
      return Column(children: [
        ManagementMetricsGrid(items: [
          ManagementMetric(s.text('صافي المبيعات', 'Net sales'), '${store.totalSales.toStringAsFixed(2)} ${store.settings.currency}', Icons.trending_up_rounded, AppColors.primary),
          ManagementMetric(s.text('عدد الفواتير', 'Invoices'), '${store.invoices.length}', Icons.receipt_long_outlined, AppColors.blue),
          ManagementMetric(s.text('المرتجعات', 'Returns'), '${store.returnsValue.toStringAsFixed(2)} ${store.settings.currency}', Icons.assignment_return_outlined, AppColors.danger),
          ManagementMetric(s.text('المعلقة', 'Held'), '${store.heldSales.length}', Icons.pause_circle_outline_rounded, AppColors.accent),
        ]),
        const SizedBox(height: 12),
        SurfaceCard(padding: EdgeInsets.zero, child: Column(children: [
          SectionCardHeader(title: s.text('سجل الفواتير', 'Invoice register'), subtitle: s.text('اضغط على أي فاتورة لعرض كل تفاصيلها.', 'Open any invoice to inspect all details.'), trailing: Wrap(spacing: 8, runSpacing: 8, children: [SearchField(controller: search, hint: s.text('رقم فاتورة، كاشير، عميل...', 'Invoice, cashier, customer...'), onChanged: (_) => setState(() {}), width: MediaQuery.sizeOf(context).width > 700 ? 280 : 190), OutlinedButton.icon(onPressed: invoices.isEmpty ? null : () => _printInvoices(invoices), icon: const Icon(Icons.print_outlined, size: 17), label: Text(s.text('طباعة السجل', 'Print register')))])),
          const Divider(height: 1),
          if (invoices.isEmpty) EmptyPanel(message: s.text('لا توجد فواتير مطابقة.', 'No matching invoices.')) else ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: invoices.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final invoice = invoices[index];
              return ListTile(
                onTap: () => _invoiceDetails(context, invoice),
                leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.receipt_long_outlined, color: AppColors.primary)),
                title: Row(children: [Flexible(child:Text(invoice.title.trim().isEmpty?invoice.number:'${invoice.number} • ${invoice.title.trim()}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900))), const SizedBox(width: 8), Text(invoice.customer, style: const TextStyle(fontSize: 9, color: AppColors.muted))]),
                subtitle: Text('${invoice.cashier} • ${invoice.cashierId} • ${formatDateTime(invoice.createdAt)} • ${s.paymentMethod(invoice.paymentMethod)}', style: const TextStyle(fontSize: 8.4, color: AppColors.muted)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text('${invoice.total.toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)), const SizedBox(width: 7), Icon(s.controller.isArabic ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: AppColors.muted)]),
              );
            },
          ),
        ])),
      ]);
    });
  }

  Future<void> _printInvoices(List<SaleInvoice> invoices) async {
    final store = AppDataStore.instance;
    final s = widget.s;
    await ThamanPrintService.printDocument(ThamanPrintTemplates.customReport(
      title: s.text('سجل فواتير المبيعات', 'Sales Invoice Register'),
      subtitle: store.settings.storeName,
      metadata: {s.text('الفرع', 'Branch'): store.settings.branchName},
      headers: [s.text('الفاتورة', 'Invoice'), s.text('التاريخ', 'Date'), s.text('العميل', 'Customer'), s.text('الكاشير', 'Cashier'), s.text('الدفع', 'Payment'), s.text('الإجمالي', 'Total'), s.text('المتبقي', 'Due')],
      rows: invoices.map((i) => [i.title.trim().isEmpty?i.number:'${i.number} • ${i.title.trim()}', formatDateTime(i.createdAt), i.customer, '${i.cashier} • ${i.cashierId}', s.paymentMethod(i.paymentMethod), i.total.toStringAsFixed(2), store.invoiceOutstanding(i.id).toStringAsFixed(2)]).toList(),
      summary: {s.text('عدد الفواتير', 'Invoices'): '${invoices.length}', s.text('الإجمالي', 'Total'): '${invoices.fold<double>(0, (sum, i) => sum + i.total).toStringAsFixed(2)} ${store.settings.currency}'},
      footer: store.settings.receiptFooter,
      isArabic: s.controller.isArabic,
    ));
  }

  void _invoiceDetails(BuildContext context, SaleInvoice invoice) {
    final s = widget.s;
    final store = AppDataStore.instance;
    showDialog<void>(context: context, builder: (_) => AlertDialog(
          scrollable: true,
      title: Row(children: [Expanded(child: Text('${s.text('تفاصيل الفاتورة', 'Invoice details')} • ${invoice.number}')), StatusPill(label: invoice.voided ? s.text('ملغاة', 'Voided') : s.text('مكتملة', 'Completed'), color: invoice.voided ? AppColors.danger : AppColors.success)]),
      content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 620.0).toDouble(), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if(invoice.title.trim().isNotEmpty) DetailLine(label:s.text('اسم الفاتورة','Invoice name'),value:invoice.title.trim()),
        DetailLine(label: s.text('التاريخ والوقت', 'Date & time'), value: formatDateTime(invoice.createdAt)),
        DetailLine(label: s.text('الكاشير', 'Cashier'), value: '${invoice.cashier} • ${invoice.cashierId.isEmpty ? '-' : invoice.cashierId}'),
        DetailLine(label: s.text('العميل', 'Customer'), value: invoice.customer),
        DetailLine(label: s.text('طريقة الدفع', 'Payment'), value: s.paymentMethod(invoice.paymentMethod)),
        const Divider(height: 22),
        Text(s.text('الأصناف', 'Items'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        for (final line in invoice.lines) Container(margin: const EdgeInsets.only(bottom: 7), padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)), child: Row(children: [Expanded(child: Text(s.text(line.nameAr, line.nameEn), style: const TextStyle(fontSize: 9.4, fontWeight: FontWeight.w800))), Text('${line.quantity} × ${line.unitPrice.toStringAsFixed(2)}', style: const TextStyle(fontSize: 8.7, color: AppColors.muted)), const SizedBox(width: 15), Text('${line.total.toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900))])),
        const Divider(height: 22),
        Align(alignment: AlignmentDirectional.centerEnd, child: Text('${s.text('الإجمالي', 'Total')}: ${invoice.total.toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
      ]))),
      actions: [
        OutlinedButton.icon(onPressed: () => ThamanPrintService.printDocument(ThamanPrintTemplates.saleInvoice(store, invoice, isArabic: s.controller.isArabic)), icon: const Icon(Icons.print_outlined, size: 17), label: Text(s.text('طباعة', 'Print'))),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إغلاق', 'Close'))),
      ],
    ));
  }
}

class HeldSalesSection extends StatefulWidget {
  const HeldSalesSection({super.key, required this.s});
  final AppStrings s;
  @override
  State<HeldSalesSection> createState() => _HeldSalesSectionState();
}
class _HeldSalesSectionState extends State<HeldSalesSection> {
  final search = TextEditingController();
  @override void dispose(){search.dispose();super.dispose();}
  @override Widget build(BuildContext context) {
    final store = AppDataStore.instance; final s = widget.s;
    return AnimatedBuilder(animation: store, builder: (_, __) {
      final q=search.text.toLowerCase();
      final data=store.heldSales.where((h)=>q.isEmpty||h.label.toLowerCase().contains(q)||h.cashierName.toLowerCase().contains(q)||h.cashierId.toLowerCase().contains(q)||h.customer.toLowerCase().contains(q)).toList();
      return SurfaceCard(padding: EdgeInsets.zero, child: Column(children:[
        SectionCardHeader(title:s.text('الفواتير المعلقة','Held sales'),subtitle:s.text('السلات التي علّقها الكاشير ولم تُدفع بعد.','Carts held by cashiers before payment.'),trailing:Wrap(spacing:8,runSpacing:8,children:[SearchField(controller:search,hint:s.text('بحث...','Search...'),onChanged:(_)=>setState((){}),width:240),OutlinedButton.icon(onPressed:data.isEmpty?null:()=>_printHeld(data),icon:const Icon(Icons.print_outlined,size:17),label:Text(s.text('طباعة','Print')))])),
        const Divider(height:1),
        if(data.isEmpty) EmptyPanel(message:s.text('لا توجد فواتير معلقة.','No held sales.')) else for(final h in data)...[
          ListTile(onTap:()=>_details(context,h),leading:Container(width:42,height:42,decoration:BoxDecoration(color:AppColors.accentSoft,borderRadius:BorderRadius.circular(13)),child:const Icon(Icons.pause_circle_outline_rounded,color:AppColors.accent)),title:Text('${h.label} • ${h.customer}',style:const TextStyle(fontSize:10.3,fontWeight:FontWeight.w900)),subtitle:Text('${h.cashierName} • ${h.cashierId} • ${formatDateTime(h.createdAt)}',style:const TextStyle(fontSize:8.5,color:AppColors.muted)),trailing:Row(mainAxisSize:MainAxisSize.min,children:[Text('${h.itemCount} ${s.text('قطعة','items')}',style:const TextStyle(fontSize:9,fontWeight:FontWeight.w800)),const SizedBox(width:5),const Icon(Icons.arrow_outward_rounded,size:16)])),
          if(h!=data.last) const Divider(height:1),
        ]
      ]));
    });
  }
  Future<void> _printHeld(List<HeldSale> data) async {
    final store=AppDataStore.instance;final s=widget.s;
    await ThamanPrintService.printDocument(ThamanPrintTemplates.customReport(title:s.text('الفواتير المعلقة','Held Sales'),subtitle:store.settings.storeName,headers:[s.text('الرقم','Number'),s.text('الوقت','Time'),s.text('الكاشير','Cashier'),s.text('العميل','Customer'),s.text('الأصناف','Items')],rows:data.map((h)=>[h.label,formatDateTime(h.createdAt),'${h.cashierName} • ${h.cashierId}',h.customer,'${h.itemCount}']).toList(),summary:{s.text('الإجمالي','Total'):'${data.length}'},footer:store.settings.receiptFooter,isArabic:s.controller.isArabic));
  }
  void _details(BuildContext context,HeldSale h){final s=widget.s;final store=AppDataStore.instance;showDialog<void>(context:context,builder:(_)=>AlertDialog(
          scrollable: true,title:Text('${s.text('فاتورة معلقة','Held sale')} • ${h.label}'),content:SizedBox(width:(MediaQuery.sizeOf(context).width - 48).clamp(0.0, 520.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[DetailLine(label:s.text('الكاشير','Cashier'),value:'${h.cashierName} • ${h.cashierId}'),DetailLine(label:s.text('العميل','Customer'),value:h.customer),DetailLine(label:s.text('وقت التعليق','Held at'),value:formatDateTime(h.createdAt)),const Divider(),for(final e in h.lines.entries) DetailLine(label:store.productOrNull(e.key)==null?e.key:s.text(store.product(e.key).nameAr,store.product(e.key).nameEn),value:'${e.value}')])) ,actions:[FilledButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إغلاق','Close')))]));}
}

class ReturnsSection extends StatefulWidget {
  const ReturnsSection({super.key, required this.s}); final AppStrings s;
  @override State<ReturnsSection> createState()=>_ReturnsSectionState();
}
class _ReturnsSectionState extends State<ReturnsSection>{
  final search=TextEditingController();@override void dispose(){search.dispose();super.dispose();}
  @override Widget build(BuildContext context){final store=AppDataStore.instance;final s=widget.s;return AnimatedBuilder(animation:store,builder:(_,__){final q=search.text.toLowerCase();final data=store.returns.where((r)=>q.isEmpty||r.invoiceNumber.toLowerCase().contains(q)||r.reason.toLowerCase().contains(q)||r.processedBy.toLowerCase().contains(q)).toList();return Column(children:[ManagementMetricsGrid(items:[ManagementMetric(s.text('عدد المرتجعات','Returns'),'${store.returns.length}',Icons.assignment_return_outlined,AppColors.danger),ManagementMetric(s.text('قيمة المرتجعات','Return value'),'${store.returnsValue.toStringAsFixed(2)} ${store.settings.currency}',Icons.payments_outlined,AppColors.accent)]),const SizedBox(height:12),SurfaceCard(padding:EdgeInsets.zero,child:Column(children:[SectionCardHeader(title:s.text('سجل المرتجعات','Return register'),subtitle:s.text('مرتبط برقم الفاتورة الأصلية ومنفذ المرتجع.','Linked to original invoice and operator.'),trailing:Wrap(spacing:8,runSpacing:8,children:[SearchField(controller:search,hint:s.text('فاتورة أو موظف...','Invoice or employee...'),onChanged:(_)=>setState((){}),width:250),OutlinedButton.icon(onPressed:data.isEmpty?null:()=>_printReturns(data),icon:const Icon(Icons.print_outlined,size:17),label:Text(s.text('طباعة السجل','Print register')))])),const Divider(height:1),if(data.isEmpty) EmptyPanel(message:s.text('لا توجد مرتجعات.','No returns.')) else for(final r in data)...[ListTile(onTap:()=>_details(context,r),leading:const Icon(Icons.assignment_return_outlined,color:AppColors.danger),title:Text('${r.invoiceNumber} • ${r.total.toStringAsFixed(2)} ${store.settings.currency}',style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900)),subtitle:Text('${r.processedBy.isEmpty?'-':r.processedBy} • ${formatDateTime(r.createdAt)} • ${r.reason}',style:const TextStyle(fontSize:8.5,color:AppColors.muted)),trailing:const Icon(Icons.arrow_outward_rounded,size:16)),if(r!=data.last)const Divider(height:1)] ]))]);});}
  Future<void> _printReturns(List<ReturnRecord> data) async {
    final store=AppDataStore.instance;final s=widget.s;
    await ThamanPrintService.printDocument(ThamanPrintTemplates.customReport(title:s.text('سجل المرتجعات','Return Register'),subtitle:store.settings.storeName,headers:[s.text('الفاتورة','Invoice'),s.text('التاريخ','Date'),s.text('الموظف','Employee'),s.text('السبب','Reason'),s.text('طريقة الرد','Refund method'),s.text('القيمة','Amount')],rows:data.map((r)=>[r.invoiceNumber,formatDateTime(r.createdAt),r.processedBy,r.reason,s.paymentMethod(r.refundMethod),r.total.toStringAsFixed(2)]).toList(),summary:{s.text('عدد المرتجعات','Returns'):'${data.length}',s.text('الإجمالي','Total'):'${data.fold<double>(0,(sum,r)=>sum+r.total).toStringAsFixed(2)} ${store.settings.currency}'},footer:store.settings.receiptFooter,isArabic:s.controller.isArabic));
  }
  void _details(BuildContext context,ReturnRecord r){final s=widget.s;final store=AppDataStore.instance;showDialog<void>(context:context,builder:(_)=>AlertDialog(
          scrollable: true,title:Text('${s.text('تفاصيل المرتجع','Return details')} • ${r.invoiceNumber}'),content:SizedBox(width:(MediaQuery.sizeOf(context).width - 48).clamp(0.0, 520.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[DetailLine(label:s.text('التاريخ','Date'),value:formatDateTime(r.createdAt)),DetailLine(label:s.text('نفذها','Processed by'),value:r.processedBy.isEmpty?'-':'${r.processedBy} • ${r.processedById}'),DetailLine(label:s.text('السبب','Reason'),value:r.reason),DetailLine(label:s.text('رد المبلغ','Refund method'),value:s.paymentMethod(r.refundMethod)),const Divider(),for(final l in r.lines)DetailLine(label:s.text(l.nameAr,l.nameEn),value:'${l.quantity} × ${l.unitPrice.toStringAsFixed(2)} = ${l.total.toStringAsFixed(2)} ${store.settings.currency}')])) ,actions:[OutlinedButton.icon(onPressed:()=>ThamanPrintService.printDocument(ThamanPrintTemplates.returnNotice(store,r,isArabic:s.controller.isArabic)),icon:const Icon(Icons.print_outlined,size:17),label:Text(s.text('طباعة إشعار المرتجع','Print return notice'))),FilledButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إغلاق','Close')))]));}
}
