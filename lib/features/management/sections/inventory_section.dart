import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/printing/print_document.dart';
import '../../../core/printing/print_service.dart';
import '../../../core/printing/print_templates.dart';
import '../../../data/app_data_store.dart';
import '../../../data/models.dart';
import '../widgets/management_widgets.dart';
import '../../inventory/inventory_batch_dialog.dart';
import '../../inventory/barcode_station_screen.dart';
import '../../inventory/stock_count_start_dialog.dart';
import '../../staff/stock_count_screen.dart';

class InventorySection extends StatefulWidget {
  const InventorySection({super.key, required this.s}); final AppStrings s;
  @override State<InventorySection> createState()=>_InventorySectionState();
}
class _InventorySectionState extends State<InventorySection>{
  final search=TextEditingController();@override void dispose(){search.dispose();super.dispose();}
  @override Widget build(BuildContext context){final store=AppDataStore.instance;final s=widget.s;return AnimatedBuilder(animation:store,builder:(_,__){final q=search.text.trim().toLowerCase();final movements=store.stockMovements.where((m){final p=m.productId.isEmpty?null:store.productOrNull(m.productId);final item=p?.nameAr??m.itemName;return q.isEmpty||item.toLowerCase().contains(q)||m.type.toLowerCase().contains(q)||m.employeeName.toLowerCase().contains(q)||m.reference.toLowerCase().contains(q)||m.note.toLowerCase().contains(q);}).toList();return Column(children:[
    ManagementMetricsGrid(items:[ManagementMetric(s.text('إجمالي الوحدات','Total units'),'${store.products.fold<int>(0,(a,b)=>a+b.stock)}',Icons.warehouse_outlined,AppColors.primary),ManagementMetric(s.text('منخفض المخزون','Low stock'),'${store.lowStock.length}',Icons.warning_amber_rounded,AppColors.danger),ManagementMetric(s.text('حركات مسجلة','Movements'),'${store.stockMovements.length}',Icons.swap_vert_rounded,AppColors.blue),ManagementMetric(s.text('جلسات الجرد','Stock counts'),'${store.stockCounts.length}',Icons.fact_check_outlined,AppColors.accent)]),
    const SizedBox(height:12),
    SurfaceCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(s.text('عمليات المخزون الجماعية','Bulk inventory operations'),style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900)),
      const SizedBox(height:4),
      Text(s.text('حدد عدة أصناف بواسطة CHECKBOX، وكل صنف يحتفظ بكميته ووحدته وبياناته بشكل مستقل.','Select multiple items with checkboxes; each item keeps its own quantity, unit and operation data.'),style:const TextStyle(fontSize:8.5,color:AppColors.muted,height:1.5)),
      const SizedBox(height:10),
      Wrap(spacing:8,runSpacing:8,children:[
        FilledButton.icon(onPressed:()=>_batch(context,'receive'),icon:const Icon(Icons.move_to_inbox_outlined,size:17),label:Text(s.text('استلام / شراء','Receive / purchase'))),
        OutlinedButton.icon(onPressed:()=>_batch(context,'damage'),icon:const Icon(Icons.warning_amber_rounded,size:17),label:Text(s.text('تسجيل تالف','Record damage'))),
        OutlinedButton.icon(onPressed:()=>_batch(context,'transfer'),icon:const Icon(Icons.swap_horiz_rounded,size:17),label:Text(s.text('نقل بين الفروع','Branch transfer'))),
        OutlinedButton.icon(onPressed:()=>_startCount(context),icon:const Icon(Icons.fact_check_outlined,size:17),label:Text(s.text('بدء جرد','Start stock count'))),
        OutlinedButton.icon(onPressed:()=>_barcodeStation(context),icon:const Icon(Icons.qr_code_scanner_rounded,size:17),label:Text(s.text('محطة الباركود','Barcode station'))),
      ]),
    ])),
    const SizedBox(height:12),
    SurfaceCard(padding:EdgeInsets.zero,child:Column(children:[
      SectionCardHeader(title:s.text('جلسات الجرد الفعلية','Physical stock-count sessions'),subtitle:s.text('كل جلسة تحفظ الرصيد المتوقع والكمية الفعلية والفروقات، ويمكن فتحها لرؤية المبيعات والتالف والاستلام والنقل التي كوّنت الرصيد المتوقع.','Each session keeps system expected stock, physical count and variances, with movement-level reconciliation.')),
      const Divider(height:1),
      if(store.stockCounts.isEmpty) EmptyPanel(message:s.text('لا توجد جلسات جرد بعد.','No stock-count sessions yet.'),icon:Icons.fact_check_outlined) else for(final session in store.stockCounts.take(8))...[
        Builder(builder:(_){
          final counted=session.lines.where((l)=>l.counted).length;
          final differences=session.status=='completed'?session.lines.where((l)=>l.difference!=0).length:session.lines.where((l)=>l.counted&&l.actual!=store.stockCountExpectedQuantity(session,l)).length;
          return ListTile(
            onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>StockCountScreen(sessionId:session.id))),
            leading:Container(width:40,height:40,decoration:BoxDecoration(color:session.status=='completed'?AppColors.primarySoft:AppColors.accentSoft,borderRadius:BorderRadius.circular(12)),child:Icon(session.status=='completed'?Icons.verified_outlined:Icons.fact_check_outlined,color:session.status=='completed'?AppColors.primary:AppColors.accent,size:19)),
            title:Text('${session.number} • ${session.employeeName}',style:const TextStyle(fontSize:10.2,fontWeight:FontWeight.w900)),
            subtitle:Text('${formatDateTime(session.createdAt)} • ${s.text('معدود','Counted')}: $counted/${session.lines.length} • ${s.text('فروقات','Differences')}: $differences',style:const TextStyle(fontSize:8.4,color:AppColors.muted)),
            trailing:Row(mainAxisSize:MainAxisSize.min,children:[Text(session.status=='completed'?s.text('مكتمل','Completed'):session.status=='submitted'?s.text('بانتظار الاعتماد','Awaiting approval'):s.text('قيد الجرد','Counting'),style:TextStyle(fontSize:8.2,fontWeight:FontWeight.w900,color:session.status=='completed'?AppColors.success:session.status=='submitted'?AppColors.blue:AppColors.accent)),const SizedBox(width:6),Icon(s.controller.isArabic?Icons.chevron_left_rounded:Icons.chevron_right_rounded,size:18,color:AppColors.muted)]),
          );
        }),
        if(session!=store.stockCounts.take(8).last) const Divider(height:1),
      ],
    ])),
    const SizedBox(height:12),
    SurfaceCard(padding:EdgeInsets.zero,child:Column(children:[SectionCardHeader(title:s.text('سجل حركات المخزون','Stock movement ledger'),subtitle:s.text('اضغط السهم لرؤية اليوم والتاريخ والمنفذ والملاحظة والمرجع.','Open any movement to see date, actor, note and reference.'),trailing:Wrap(spacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[SizedBox(width:280,child:SearchField(controller:search,hint:s.text('صنف، نوع، موظف، مرجع...','Item, type, employee, reference...'),onChanged:(_)=>setState((){}),width:280)),OutlinedButton.icon(onPressed:()=>_printMovements(movements),icon:const Icon(Icons.print_outlined,size:16),label:Text(s.text('طباعة','Print')))])),const Divider(height:1),if(movements.isEmpty)EmptyPanel(message:s.text('لا توجد حركات مطابقة.','No matching movements.'))else for(final m in movements.take(100))...[
      ListTile(onTap:()=>_details(context,m),leading:Container(width:40,height:40,decoration:BoxDecoration(color:_tone(m.type).withValues(alpha: .09),borderRadius:BorderRadius.circular(12)),child:Icon(_icon(m.type),color:_tone(m.type),size:19)),title:Text(_name(store,m,s),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900)),subtitle:Text('${s.movementType(m.type)} • ${m.employeeName.isEmpty?s.text('النظام','System'):m.employeeName} • ${formatDateTime(m.createdAt)}',style:const TextStyle(fontSize:8.4,color:AppColors.muted)),trailing:Row(mainAxisSize:MainAxisSize.min,children:[Text('${m.quantity>0?'+':''}${m.quantity}',style:TextStyle(fontSize:9.8,fontWeight:FontWeight.w900,color:m.quantity>=0?AppColors.success:AppColors.danger)),const SizedBox(width:7),Icon(s.controller.isArabic?Icons.chevron_left_rounded:Icons.chevron_right_rounded,size:18,color:AppColors.muted)])),if(m!=movements.take(100).last)const Divider(height:1)
    ]]))
  ]);});}
  Future<void> _batch(BuildContext context,String type) async {
    final c=widget.s.controller;
    final role=c.role?.name??'management';
    await showInventoryBatchOperation(context,s:widget.s,type:type,actorId:'ADMIN-$role',actorName:c.currentUserName.isEmpty?role:c.currentUserName,actorRole:role);
  }
  Future<void> _barcodeStation(BuildContext context) async {
    final c=widget.s.controller;
    final role=c.role?.name??'management';
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>BarcodeStationScreen(s:widget.s,actorId:'ADMIN-$role',actorName:c.currentUserName.isEmpty?role:c.currentUserName,actorRole:role)));
  }
  Future<void> _startCount(BuildContext context) async {
    final ids=await showStockCountStartDialog(context,widget.s);
    if(ids==null||ids.isEmpty||!context.mounted)return;
    final store=AppDataStore.instance;
    final inventoryEmployees=store.employees.where((e)=>e.active&&e.roleKey=='inventory').toList();
    if(inventoryEmployees.isEmpty){
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(widget.s.text('لا يوجد موظف مخزون نشط لإسناد الجرد إليه.','No active inventory employee is available for this count.'))));
      return;
    }
    final assignee=await showDialog<EmployeeRecord>(context:context,builder:(_)=>AlertDialog(
      scrollable:true,
      title:Text(widget.s.text('إسناد الجرد لموظف المخزن','Assign stock count')),
      content:SizedBox(width:(MediaQuery.sizeOf(context).width-48).clamp(0.0,480.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text(widget.s.text('الموظف سيشاهد أسماء الأصناف وحقول الكمية فقط بدون الكمية المتوقعة أو أي فروقات.','The employee will see item names and count fields only, without expected stock or variances.'),style:const TextStyle(fontSize:9,color:AppColors.muted,height:1.5)),
        const SizedBox(height:10),
        for(final e in inventoryEmployees)ListTile(
          leading:const CircleAvatar(child:Icon(Icons.warehouse_outlined,size:18)),
          title:Text(widget.s.text(e.nameAr,e.nameEn),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900)),
          subtitle:Text('${e.id} • ${e.branch}',style:const TextStyle(fontSize:8.4,color:AppColors.muted)),
          onTap:()=>Navigator.pop(context,e),
        ),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(widget.s.text('إلغاء','Cancel')))],
    ));
    if(assignee==null||!context.mounted)return;
    final c=widget.s.controller;
    final role=c.role?.name??'management';
    final requester=c.currentUserName.isEmpty?role:c.currentUserName;
    AppDataStore.instance.startStockCount(
      employeeId:assignee.id,
      employeeName:widget.s.text(assignee.nameAr,assignee.nameEn),
      productIds:ids,
      requestedByName:requester,
      requestedByRole:role,
    );
    if(!context.mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(widget.s.text('تم إرسال طلب الجرد لموظف المخزن. ستظهر الفروقات للإدارة بعد إرساله للمراجعة.','Stock count assigned. Variances will appear to management after the employee submits it.'))));
  }
  Future<void> _printMovements(List<StockMovement> movements) async {
    final store=AppDataStore.instance;
    final s=widget.s;
    await ThamanPrintService.printDocument(PrintDocument(
      title:s.text('سجل حركات المخزون','Stock Movement Ledger'),
      subtitle:'${store.settings.storeName} • ${store.settings.branchName}',
      metadata:{s.text('عدد الحركات','Movements'):'${movements.length}',s.text('فلتر البحث','Search filter'):search.text.trim().isEmpty?'-':search.text.trim()},
      headers:[s.text('التاريخ','Date'),s.text('الصنف','Item'),s.text('النوع','Type'),s.text('الكمية','Qty'),s.text('الموظف','Employee'),s.text('المرجع','Reference'),s.text('الملاحظة','Note')],
      rows:movements.map((m)=>[formatDateTime(m.createdAt),m.itemName,m.type,'${m.quantity}',m.employeeName,m.reference,m.note]).toList(),
      footer:store.settings.receiptFooter,
    
      isArabic: widget.s.controller.isArabic,));
  }

  void _details(BuildContext context,StockMovement m){final s=widget.s;final store=AppDataStore.instance;showDialog<void>(context:context,builder:(_)=>AlertDialog(
          scrollable: true,title:Text(s.text('تفاصيل حركة المخزون','Stock movement details')),content:SizedBox(width:(MediaQuery.sizeOf(context).width - 48).clamp(0.0, 520.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[DetailLine(label:s.text('الصنف','Item'),value:_name(store,m,s)),DetailLine(label:s.text('نوع الحركة','Movement type'),value:s.movementType(m.type)),DetailLine(label:s.text('الكمية المؤثرة على المخزون','Base stock quantity'),value:'${m.quantity>0?'+':''}${m.quantity}'),if(m.operationQuantity>0)DetailLine(label:s.text('الكمية والوحدة المدخلة','Entered quantity & unit'),value:'${m.operationQuantity.toStringAsFixed(m.operationQuantity%1==0?0:2)} ${_unitLabel(s,m.operationUnit)}${m.unitsPerOperationUnit>1?' × ${m.unitsPerOperationUnit}':''}'),DetailLine(label:s.text('اليوم والتاريخ','Date & time'),value:formatDateTime(m.createdAt)),DetailLine(label:s.text('نفذها','Performed by'),value:m.employeeName.isEmpty?s.text('النظام','System'):'${m.employeeName} • ${m.employeeId}'),if(m.reference.isNotEmpty)DetailLine(label:s.text('المرجع','Reference'),value:m.reference),if(m.note.isNotEmpty)DetailLine(label:s.text('الملاحظة','Note'),value:m.note),if(m.amount>0)DetailLine(label:s.text('القيمة','Value'),value:'${m.amount.toStringAsFixed(2)} ${store.settings.currency}')])) ,actions:[OutlinedButton.icon(onPressed:()=>ThamanPrintService.printDocument(ThamanPrintTemplates.stockMovementNotice(store,m,isArabic:s.controller.isArabic)),icon:const Icon(Icons.print_outlined,size:17),label:Text(s.text('طباعة','Print'))),FilledButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إغلاق','Close')))]));}
}

class StockAlertsSection extends StatefulWidget {
  const StockAlertsSection({super.key, required this.s});
  final AppStrings s;

  @override
  State<StockAlertsSection> createState() => _StockAlertsSectionState();
}

class _StockAlertsSectionState extends State<StockAlertsSection> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final s = widget.s;
    return AnimatedBuilder(
      animation: store,
      builder: (_, __) {
        final q = search.text.toLowerCase();
        final data = store.lowStock.where((p) =>
          q.isEmpty ||
          p.nameAr.toLowerCase().contains(q) ||
          p.nameEn.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q)
        ).toList();
        return Column(
          children: [
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SectionCardHeader(
                    title: s.text('تنبيهات إعادة الطلب', 'Reorder alerts'),
                    subtitle: s.text(
                      'من هنا يمكنك إنشاء طلب توريد، إرسال رسالة لمسؤول المخزون أو إضافة ملاحظة على الصنف.',
                      'Create a restock request, message inventory or add an item note directly from each alert.',
                    ),
                    trailing: SearchField(
                      controller: search,
                      hint: s.text('بحث عن صنف...', 'Search item...'),
                      onChanged: (_) => setState(() {}),
                      width: 240,
                    ),
                  ),
                  const Divider(height: 1),
                  if (data.isEmpty)
                    EmptyPanel(
                      message: s.text('المخزون ضمن الحدود الحالية.', 'Inventory is within current thresholds.'),
                      icon: Icons.check_circle_outline_rounded,
                    )
                  else
                    for (final p in data) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final compact = c.maxWidth < 760;
                            final info = Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(14)),
                                  child: const Icon(Icons.warning_amber_rounded, color: AppColors.accent),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${s.text(p.nameAr, p.nameEn)} • ${p.sku}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 5),
                                      Text(
                                        '${s.text('الحالي', 'Current')}: ${p.stock} ${_unitLabel(s, p.baseUnit)}  •  ${s.text('حد الطلب', 'Reorder')}: ${p.minStock}  •  ${s.text('النقص', 'Shortage')}: ${(p.minStock - p.stock).clamp(0, 9999)}',
                                        style: const TextStyle(fontSize: 9.2, color: AppColors.muted, height: 1.45),
                                      ),
                                      if (store.notesForProduct(p.id).isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          '${s.text('آخر ملاحظة', 'Latest note')}: ${store.notesForProduct(p.id).first.text}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 8.6, color: AppColors.primary, fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            );
                            final actions = Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _addNote(context, p),
                                  icon: const Icon(Icons.sticky_note_2_outlined, size: 16),
                                  label: Text(s.text('إضافة ملاحظة', 'Add note')),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _messageInventory(context, p),
                                  icon: const Icon(Icons.notifications_active_outlined, size: 16),
                                  label: Text(s.text('إشعار المخزون', 'Notify inventory')),
                                ),
                                FilledButton.icon(
                                  onPressed: () => _requestStock(context, p),
                                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                                  label: Text(s.text('طلب بضاعة', 'Request stock')),
                                ),
                              ],
                            );
                            return compact
                                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, const SizedBox(height: 10), actions])
                                : Row(children: [Expanded(child: info), const SizedBox(width: 14), actions]);
                          },
                        ),
                      ),
                      if (p != data.last) const Divider(height: 1),
                    ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                SectionCardHeader(
                  title: s.text('طلبات التوريد المرتبطة بالمخزون', 'Inventory restock requests'),
                  subtitle: s.text('آخر الطلبات التي أنشأها المالك أو المدير بسبب النقص.', 'Recent shortage-driven requests created by management.'),
                  trailing: Text('${store.openRestockRequests.length} ${s.text('مفتوح', 'open')}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: AppColors.primary)),
                ),
                const Divider(height: 1),
                if (store.restockRequests.isEmpty)
                  EmptyPanel(message: s.text('لا توجد طلبات توريد بعد.', 'No restock requests yet.'), icon: Icons.shopping_cart_checkout_outlined)
                else
                  for (final request in store.restockRequests.take(6)) ...[
                    ListTile(
                      leading: const Icon(Icons.shopping_cart_checkout_outlined, color: AppColors.primary),
                      title: Text('${request.number} • ${request.lines.map((e) => e.itemName).take(2).join(s.text('، ', ', '))}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                      subtitle: Text('${request.createdByName} • ${formatDateTime(request.createdAt)} • ${s.status(request.status)}', style: const TextStyle(fontSize: 8.3, color: AppColors.muted)),
                    ),
                    if (request != store.restockRequests.take(6).last) const Divider(height: 1),
                  ],
              ]),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addNote(BuildContext context, ProductModel product) async {
    final s = widget.s;
    final controller = TextEditingController();
    String audience = 'inventory';
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          scrollable: true,
          title: Text('${s.text('إضافة ملاحظة', 'Add note')} • ${s.text(product.nameAr, product.nameEn)}'),
          content: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 500.0).toDouble(),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: controller, maxLines: 3, decoration: InputDecoration(labelText: s.text('الملاحظة', 'Note'))),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: audience,
                decoration: InputDecoration(labelText: s.text('تظهر لمن؟', 'Visible to')),
                items: [
                  DropdownMenuItem(value: 'inventory', child: Text(s.text('موظف المخزن', 'Inventory staff'))),
                  DropdownMenuItem(value: 'purchasing', child: Text(s.text('مسؤول الشراء', 'Purchasing staff'))),
                  DropdownMenuItem(value: 'both', child: Text(s.text('المخزون والشراء', 'Inventory & purchasing'))),
                ],
                onChanged: (v) => setD(() => audience = v ?? audience),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) return;
                AppDataStore.instance.addProductNote(
                  productId: product.id,
                  text: controller.text.trim(),
                  audience: audience,
                  createdBy: s.controller.currentUserName,
                );
                Navigator.pop(dialogContext);
              },
              child: Text(s.text('حفظ وإرسال', 'Save & send')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _messageInventory(BuildContext context, ProductModel product) async {
    final s = widget.s;
    final store = AppDataStore.instance;
    final body = TextEditingController(
      text: s.text(
        s.text('تنبيه مخزون: ${product.nameAr} (${product.sku}) الرصيد الحالي ${product.stock} وحد الطلب ${product.minStock}. يرجى المراجعة.','Stock alert: ${product.nameEn} (${product.sku}) current stock ${product.stock}, reorder level ${product.minStock}. Please review.'),
        'Stock alert: ${product.nameEn} (${product.sku}) current stock ${product.stock}, reorder level ${product.minStock}. Please review.',
      ),
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
          scrollable: true,
        title: Text(s.text('إرسال إشعار لمسؤول المخزون', 'Notify inventory')),
        content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 520.0).toDouble(), child: TextField(controller: body, minLines: 3, maxLines: 6, decoration: InputDecoration(labelText: s.text('نص الرسالة', 'Message')))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.text('إلغاء', 'Cancel'))),
          FilledButton.icon(
            onPressed: () {
              if (body.text.trim().isEmpty) return;
              final role = s.controller.role?.name ?? 'manager';
              store.sendMessage(
                senderId: 'ADMIN-$role',
                senderName: s.controller.currentUserName.isEmpty ? role : s.controller.currentUserName,
                senderRole: role,
                recipientType: 'inventory',
                body: body.text.trim(),
              );
              Navigator.pop(dialogContext);
            },
            icon: const Icon(Icons.send_rounded, size: 16),
            label: Text(s.text('إرسال', 'Send')),
          ),
        ],
      ),
    );
    body.dispose();
  }

  Future<void> _requestStock(BuildContext context, ProductModel product) async {
    final s = widget.s;
    final store = AppDataStore.instance;
    final suggested = ((product.minStock * 2) - product.stock).clamp(1, 99999);
    final qty = TextEditingController(text: '$suggested');
    final note = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
          scrollable: true,
        title: Text('${s.text('طلب بضاعة', 'Request stock')} • ${s.text(product.nameAr, product.nameEn)}'),
        content: SizedBox(
          width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 500.0).toDouble(),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DetailLine(label: s.text('المخزون الحالي', 'Current stock'), value: '${product.stock} ${_unitLabel(s, product.baseUnit)}'),
            DetailLine(label: s.text('حد إعادة الطلب', 'Reorder level'), value: '${product.minStock}'),
            const SizedBox(height: 8),
            TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('الكمية المطلوبة', 'Requested quantity'), suffixText: _unitLabel(s, product.baseUnit))),
            const SizedBox(height: 10),
            TextField(controller: note, maxLines: 2, decoration: InputDecoration(labelText: s.text('ملاحظة للطلب', 'Request note'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.text('إلغاء', 'Cancel'))),
          FilledButton.icon(
            onPressed: () {
              final value = double.tryParse(qty.text.trim()) ?? 0;
              if (value <= 0) return;
              final role = s.controller.role?.name ?? 'manager';
              store.createRestockRequestForProduct(
                product: product,
                quantity: value,
                unit: product.baseUnit,
                createdById: 'ADMIN-$role',
                createdByName: s.controller.currentUserName.isEmpty ? role : s.controller.currentUserName,
                createdByRole: role,
                note: note.text.trim(),
              );
              Navigator.pop(dialogContext);
            },
            icon: const Icon(Icons.check_rounded, size: 16),
            label: Text(s.text('إنشاء الطلب', 'Create request')),
          ),
        ],
      ),
    );
    qty.dispose();
    note.dispose();
  }
}


String _unitLabel(AppStrings s,String value)=>switch(value){'piece'=>s.text('قطعة','Piece'),'pack'=>s.text('عبوة','Pack'),'carton'=>s.text('كرتونة','Carton'),'box'=>s.text('صندوق','Box'),'bag'=>s.text('كيس','Bag'),'kg'=>s.text('كيلو','Kg'),'gram'=>s.text('غرام','Gram'),'liter'=>s.text('لتر','Liter'),'bottle'=>s.text('زجاجة','Bottle'),'roll'=>s.text('رول','Roll'),''=>'',_=>value};
String _name(AppDataStore store,StockMovement m,AppStrings s){final p=m.productId.isEmpty?null:store.productOrNull(m.productId);return p==null?(m.itemName.isEmpty?'-':m.itemName):s.text(p.nameAr,p.nameEn);}
IconData _icon(String t)=>switch(t){'receive'=>Icons.move_to_inbox_outlined,'damage'||'damage_manual'=>Icons.warning_amber_rounded,'transfer'||'transfer_manual'=>Icons.swap_horiz_rounded,'count'=>Icons.fact_check_outlined,'return'=>Icons.assignment_return_outlined,'sale'=>Icons.point_of_sale_outlined,_=>Icons.inventory_2_outlined};
Color _tone(String t)=>switch(t){'receive'=>AppColors.success,'damage'||'damage_manual'=>AppColors.danger,'transfer'||'transfer_manual'=>AppColors.blue,'count'=>AppColors.accent,'return'=>AppColors.primary,'sale'=>AppColors.muted,_=>AppColors.primary};
