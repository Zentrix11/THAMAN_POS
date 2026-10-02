import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/printing/print_document.dart';
import '../../../core/printing/print_service.dart';
import '../../../data/app_data_store.dart';
import '../widgets/management_widgets.dart';

class ReportsSection extends StatefulWidget {
  const ReportsSection({super.key, required this.s});
  final AppStrings s;
  @override State<ReportsSection> createState() => _ReportsSectionState();
}

class _ReportsSectionState extends State<ReportsSection> {
  int days = 7;
  DateTime get from => DateTime.now().subtract(Duration(days: days));

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final s = widget.s;
    return AnimatedBuilder(animation: store, builder: (_, __) {
      final sales = store.invoices.where((i) => !i.voided && i.createdAt.isAfter(from)).toList();
      final returns = store.returns.where((r) => r.createdAt.isAfter(from)).toList();
      final purchases = store.purchases.where((p) => p.createdAt.isAfter(from)).toList();
      final purchaseReturns = store.purchaseReturns.where((r) => r.createdAt.isAfter(from)).toList();
      final attendance = store.attendance.where((a) => a.clockIn.isAfter(from)).toList();
      final tasks = store.tasks.where((t) => t.createdAt.isAfter(from)).toList();
      final gross = sales.fold<double>(0, (a,b)=>a+b.total);
      final returned = returns.fold<double>(0, (a,b)=>a+b.total);
      final net = gross-returned;
      final grossCost = sales.fold<double>(0,(sum,inv)=>sum+inv.lines.fold<double>(0,(x,l)=>x+l.unitCost*l.quantity));
      final returnedCost = returns.fold<double>(0,(sum,ret)=>sum+ret.lines.fold<double>(0,(x,l)=>x+l.unitCost*l.quantity));
      final cost = grossCost-returnedCost;
      final profit = net-cost;
      final purchaseValue = purchases.fold<double>(0,(a,b)=>a+b.total);
      final purchaseReturnValue = purchaseReturns.fold<double>(0,(a,b)=>a+b.agreedAmount);
      final completed = tasks.where((t)=>t.status=='completed').length;
      final hours = attendance.fold<Duration>(Duration.zero,(a,b)=>a+b.duration).inMinutes/60;
      final productQty = <String,int>{};
      final cashierSales = <String,double>{};
      for(final inv in sales){
        cashierSales.update(inv.cashier,(v)=>v+inv.total,ifAbsent:()=>inv.total);
        for(final l in inv.lines){productQty.update(l.nameAr,(v)=>v+l.quantity,ifAbsent:()=>l.quantity);}
      }
      final topProducts=productQty.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
      final topCashiers=cashierSales.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
      return Column(children:[
        Row(children:[
          Expanded(child:Align(alignment:AlignmentDirectional.centerStart,child:OutlinedButton.icon(onPressed:()=>_printPeriod(store:store,s:s,sales:sales,returns:returns,purchases:purchases,purchaseReturns:purchaseReturns,attendance:attendance,tasks:tasks,net:net,profit:profit,purchaseValue:purchaseValue,purchaseReturnValue:purchaseReturnValue,hours:hours,completed:completed,topProducts:topProducts,topCashiers:topCashiers),icon:const Icon(Icons.print_outlined,size:17),label:Text(s.text('طباعة التقرير','Print report'))))),
          SegmentedButton<int>(segments:[
            ButtonSegment(value:1,label:Text(s.text('اليوم','Today'))),
            ButtonSegment(value:7,label:Text(s.text('7 أيام','7 days'))),
            ButtonSegment(value:30,label:Text(s.text('30 يوم','30 days'))),
            ButtonSegment(value:90,label:Text(s.text('90 يوم','90 days'))),
          ],selected:{days},onSelectionChanged:(v)=>setState(()=>days=v.first)),
        ]),
        const SizedBox(height:12),
        ManagementMetricsGrid(items:[
          ManagementMetric(s.text('صافي المبيعات','Net sales'),'${net.toStringAsFixed(2)} ${store.settings.currency}',Icons.payments_outlined,AppColors.primary),
          ManagementMetric(s.text('الربح التقديري','Estimated profit'),'${profit.toStringAsFixed(2)} ${store.settings.currency}',Icons.trending_up_rounded,profit>=0?AppColors.success:AppColors.danger),
          ManagementMetric(s.text('المشتريات','Purchases'),'${purchaseValue.toStringAsFixed(2)} ${store.settings.currency}',Icons.shopping_bag_outlined,AppColors.accent),
          ManagementMetric(s.text('مرتجعات المشتريات','Purchase returns'),'${purchaseReturnValue.toStringAsFixed(2)} ${store.settings.currency}',Icons.assignment_return_outlined,AppColors.accent),
          ManagementMetric(s.text('متوسط الفاتورة','Average ticket'),sales.isEmpty?'0.00 ${store.settings.currency}':'${(net/sales.length).toStringAsFixed(2)} ${store.settings.currency}',Icons.receipt_long_outlined,AppColors.blue),
          ManagementMetric(s.text('ساعات الحضور','Attendance hours'),hours.toStringAsFixed(1),Icons.schedule_outlined,AppColors.primary),
          ManagementMetric(s.text('إنجاز المهام','Task completion'),tasks.isEmpty?'0%':'${(completed/tasks.length*100).round()}%',Icons.task_alt_rounded,AppColors.success),
        ]),
        const SizedBox(height:12),
        LayoutBuilder(builder:(context,c){final stacked=c.maxWidth<850;final product=SurfaceCard(padding:EdgeInsets.zero,child:Column(children:[SectionCardHeader(title:s.text('الأصناف الأكثر مبيعاً','Top selling products'),subtitle:s.text('محسوبة من بنود الفواتير ضمن الفترة.','Calculated from invoice lines in the selected period.')),const Divider(height:1),if(topProducts.isEmpty)EmptyPanel(message:s.text('لا توجد مبيعات في الفترة.','No sales in this period.'))else for(final e in topProducts.take(8))ListTile(dense:true,title:Text(e.key,style:const TextStyle(fontSize:9.5,fontWeight:FontWeight.w800)),trailing:StatusPill(label:'${e.value} ${s.text('وحدة','units')}',color:AppColors.primary))]));final cashier=SurfaceCard(padding:EdgeInsets.zero,child:Column(children:[SectionCardHeader(title:s.text('المبيعات حسب الموظف','Sales by employee'),subtitle:s.text('إجمالي الفواتير لكل كاشير ضمن الفترة.','Invoice totals by cashier in the selected period.')),const Divider(height:1),if(topCashiers.isEmpty)EmptyPanel(message:s.text('لا توجد بيانات.','No data.'))else for(final e in topCashiers.take(8))ListTile(dense:true,title:Text(e.key,style:const TextStyle(fontSize:9.5,fontWeight:FontWeight.w800)),trailing:Text('${e.value.toStringAsFixed(2)} ${store.settings.currency}',style:const TextStyle(fontSize:9.5,fontWeight:FontWeight.w900))) ]));return stacked?Column(children:[product,const SizedBox(height:12),cashier]):Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:product),const SizedBox(width:12),Expanded(child:cashier)]);}),
        const SizedBox(height:12),
        SurfaceCard(padding:EdgeInsets.zero,child:Column(children:[SectionCardHeader(title:s.text('ملخص الفترة','Period summary'),subtitle:s.text('القيم أدناه ناتجة مباشرة من سجلات النظام.','The values below are calculated directly from system records.')),const Divider(height:1),Padding(padding:const EdgeInsets.all(18),child:Wrap(spacing:28,runSpacing:12,children:[_Mini(s.text('الفواتير','Invoices'),'${sales.length}'),_Mini(s.text('مرتجعات البيع','Sales returns'),'${returns.length}'),_Mini(s.text('استلامات الشراء','Purchase receipts'),'${purchases.length}'),_Mini(s.text('مرتجعات الشراء','Purchase returns'),'${purchaseReturns.length}'),_Mini(s.text('سجلات الحضور','Attendance records'),'${attendance.length}'),_Mini(s.text('المهام المنشأة','Tasks created'),'${tasks.length}'),_Mini(s.text('مرتجع البيع بالقيمة','Sales return value'),'${returned.toStringAsFixed(2)} ${store.settings.currency}'),_Mini(s.text('مرتجع الشراء بالقيمة','Purchase return value'),'${purchaseReturnValue.toStringAsFixed(2)} ${store.settings.currency}')]))]))
      ]);
    });
  }

  Future<void> _printPeriod({
    required AppDataStore store,
    required AppStrings s,
    required List sales,
    required List returns,
    required List purchases,
    required List purchaseReturns,
    required List attendance,
    required List tasks,
    required double net,
    required double profit,
    required double purchaseValue,
    required double purchaseReturnValue,
    required double hours,
    required int completed,
    required List<MapEntry<String,int>> topProducts,
    required List<MapEntry<String,double>> topCashiers,
  }) async {
    final average=sales.isEmpty?0.0:net/sales.length;
    await ThamanPrintService.printDocument(PrintDocument(
      title:s.text('تقرير الأداء التشغيلي','Operational Performance Report'),
      subtitle:'${store.settings.storeName} • ${store.settings.branchName}',
      metadata:{s.text('الفترة','Period'):'$days ${s.text('يوم','days')}',s.text('الفواتير','Invoices'):'${sales.length}',s.text('مرتجعات البيع','Sales returns'):'${returns.length}',s.text('المشتريات','Purchases'):'${purchases.length}',s.text('مرتجعات الشراء','Purchase returns'):'${purchaseReturns.length}'},
      headers:[s.text('المؤشر','Metric'),s.text('القيمة','Value')],
      rows:[
        [s.text('صافي المبيعات','Net sales'),'${net.toStringAsFixed(2)} ${store.settings.currency}'],
        [s.text('الربح التقديري','Estimated profit'),'${profit.toStringAsFixed(2)} ${store.settings.currency}'],
        [s.text('قيمة المشتريات','Purchases value'),'${purchaseValue.toStringAsFixed(2)} ${store.settings.currency}'],
        [s.text('مرتجعات المشتريات','Purchase returns'),'${purchaseReturnValue.toStringAsFixed(2)} ${store.settings.currency}'],
        [s.text('متوسط الفاتورة','Average ticket'),'${average.toStringAsFixed(2)} ${store.settings.currency}'],
        [s.text('ساعات الحضور','Attendance hours'),hours.toStringAsFixed(1)],
        [s.text('المهام المكتملة','Completed tasks'),'$completed / ${tasks.length}'],
        ...topProducts.take(8).map((e)=>['${s.text('صنف','Product')}: ${e.key}','${e.value} ${s.text('وحدة','units')}']),
        ...topCashiers.take(8).map((e)=>['${s.text('مبيعات موظف','Employee sales')}: ${e.key}','${e.value.toStringAsFixed(2)} ${store.settings.currency}']),
      ],
      notes:[s.text('جميع القيم محسوبة مباشرة من سجلات النظام ضمن الفترة المحددة.','All values are calculated directly from system records for the selected period.')],
      footer:store.settings.receiptFooter,
    
      isArabic: s.controller.isArabic,));
  }
}

class _Mini extends StatelessWidget{const _Mini(this.label,this.value);final String label,value;@override Widget build(BuildContext context)=>SizedBox(width:145,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(value,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w900)),const SizedBox(height:2),Text(label,style:const TextStyle(fontSize:8.5,color:AppColors.muted))]));}
