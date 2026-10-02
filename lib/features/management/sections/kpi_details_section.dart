import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../data/app_data_store.dart';
import '../../../data/models.dart';
import '../widgets/management_widgets.dart';

enum KpiDetailType { netSales, profit, averageTicket, invoices }

class KpiDetailSection extends StatefulWidget {
  const KpiDetailSection({super.key, required this.s, required this.type});
  final AppStrings s;
  final KpiDetailType type;
  @override State<KpiDetailSection> createState() => _KpiDetailSectionState();
}

class _KpiDetailSectionState extends State<KpiDetailSection> {
  int days = 30;
  final search = TextEditingController();
  @override void dispose(){search.dispose();super.dispose();}

  @override
  Widget build(BuildContext context) {
    final store=AppDataStore.instance,s=widget.s;
    return AnimatedBuilder(animation:store,builder:(_,__){
      final from=DateTime.now().subtract(Duration(days:days));
      final invoices=store.invoices.where((i)=>!i.voided&&i.createdAt.isAfter(from)).toList();
      final returns=store.returns.where((r)=>r.createdAt.isAfter(from)).toList();
      final gross=invoices.fold<double>(0,(a,b)=>a+b.total);
      final returned=returns.fold<double>(0,(a,b)=>a+b.total);
      final net=gross-returned;
      final grossCost=invoices.fold<double>(0,(sum,inv)=>sum+inv.lines.fold<double>(0,(x,l)=>x+(store.productOrNull(l.productId)?.cost??0)*l.quantity));
      final returnedCost=returns.fold<double>(0,(sum,ret)=>sum+ret.lines.fold<double>(0,(x,l)=>x+(store.productOrNull(l.productId)?.cost??0)*l.quantity));
      final cost=grossCost-returnedCost;
      final profit=net-cost;
      final average=invoices.isEmpty?0:net/invoices.length;
      final high=invoices.isEmpty?0:invoices.map((e)=>e.total).reduce((a,b)=>a>b?a:b);
      final low=invoices.isEmpty?0:invoices.map((e)=>e.total).reduce((a,b)=>a<b?a:b);
      final q=search.text.trim().toLowerCase();
      final filtered=invoices.where((i)=>q.isEmpty||i.number.toLowerCase().contains(q)||i.cashier.toLowerCase().contains(q)||i.customer.toLowerCase().contains(q)||i.paymentMethod.toLowerCase().contains(q)).toList();
      final currency=store.settings.currency;
      return Column(children:[
        Align(alignment:AlignmentDirectional.centerEnd,child:SegmentedButton<int>(segments:[ButtonSegment(value:1,label:Text(s.text('اليوم','Today'))),ButtonSegment(value:7,label:Text(s.text('7 أيام','7 days'))),ButtonSegment(value:30,label:Text(s.text('30 يوم','30 days'))),ButtonSegment(value:90,label:Text(s.text('90 يوم','90 days')))],selected:{days},onSelectionChanged:(v)=>setState(()=>days=v.first))),
        const SizedBox(height:12),
        if(widget.type==KpiDetailType.netSales) ManagementMetricsGrid(items:[
          ManagementMetric(s.text('إجمالي المبيعات','Gross sales'),'${gross.toStringAsFixed(2)} $currency',Icons.add_chart_rounded,AppColors.primary),
          ManagementMetric(s.text('المرتجعات','Returns'),'${returned.toStringAsFixed(2)} $currency',Icons.assignment_return_outlined,AppColors.danger),
          ManagementMetric(s.text('صافي المبيعات','Net sales'),'${net.toStringAsFixed(2)} $currency',Icons.trending_up_rounded,AppColors.success),
          ManagementMetric(s.text('عدد الفواتير','Invoices'),'${invoices.length}',Icons.receipt_long_outlined,AppColors.blue),
        ]),
        if(widget.type==KpiDetailType.profit) ManagementMetricsGrid(items:[
          ManagementMetric(s.text('صافي المبيعات','Net sales'),'${net.toStringAsFixed(2)} $currency',Icons.payments_outlined,AppColors.primary),
          ManagementMetric(s.text('تكلفة البضاعة','Estimated COGS'),'${cost.toStringAsFixed(2)} $currency',Icons.inventory_2_outlined,AppColors.accent),
          ManagementMetric(s.text('الربح التقديري','Estimated profit'),'${profit.toStringAsFixed(2)} $currency',Icons.insights_outlined,profit>=0?AppColors.success:AppColors.danger),
          ManagementMetric(s.text('هامش الربح','Estimated margin'),net==0?'0%':'${(profit/net*100).toStringAsFixed(1)}%',Icons.percent_rounded,AppColors.blue),
        ]),
        if(widget.type==KpiDetailType.averageTicket) ManagementMetricsGrid(items:[
          ManagementMetric(s.text('متوسط الفاتورة','Average ticket'),'${average.toStringAsFixed(2)} $currency',Icons.shopping_bag_outlined,AppColors.primary),
          ManagementMetric(s.text('أعلى فاتورة','Highest ticket'),'${high.toStringAsFixed(2)} $currency',Icons.arrow_upward_rounded,AppColors.success),
          ManagementMetric(s.text('أقل فاتورة','Lowest ticket'),'${low.toStringAsFixed(2)} $currency',Icons.arrow_downward_rounded,AppColors.accent),
          ManagementMetric(s.text('عدد الفواتير','Invoices'),'${invoices.length}',Icons.receipt_long_outlined,AppColors.blue),
        ]),
        if(widget.type==KpiDetailType.invoices) ManagementMetricsGrid(items:[
          ManagementMetric(s.text('الفواتير','Invoices'),'${invoices.length}',Icons.receipt_long_outlined,AppColors.primary),
          ManagementMetric(s.text('إجمالي القيمة','Gross value'),'${gross.toStringAsFixed(2)} $currency',Icons.payments_outlined,AppColors.blue),
          ManagementMetric(s.text('عدد المرتجعات','Returns'),'${returns.length}',Icons.assignment_return_outlined,AppColors.danger),
          ManagementMetric(s.text('متوسط الفاتورة','Average ticket'),'${average.toStringAsFixed(2)} $currency',Icons.shopping_bag_outlined,AppColors.accent),
        ]),
        const SizedBox(height:12),
        if(widget.type==KpiDetailType.profit) _ProfitProducts(s:s,invoices:invoices),
        if(widget.type==KpiDetailType.averageTicket) _TicketBands(s:s,invoices:invoices),
        if(widget.type==KpiDetailType.netSales) _SalesByEmployee(s:s,invoices:invoices),
        if(widget.type!=KpiDetailType.profit&&widget.type!=KpiDetailType.averageTicket&&widget.type!=KpiDetailType.netSales) const SizedBox.shrink(),
        if(widget.type!=KpiDetailType.invoices) const SizedBox(height:12),
        SurfaceCard(padding:EdgeInsets.zero,child:Column(children:[
          SectionCardHeader(title:s.text('الفواتير الداخلة في الحساب','Invoices in this calculation'),subtitle:s.text('يمكن البحث برقم الفاتورة أو الموظف أو العميل.','Search by invoice, employee or customer.'),trailing:SearchField(controller:search,hint:s.text('بحث...','Search...'),onChanged:(_)=>setState((){}),width:250)),
          const Divider(height:1),
          if(filtered.isEmpty) EmptyPanel(message:s.text('لا توجد فواتير مطابقة.','No matching invoices.')) else for(final i in filtered.take(60))...[ListTile(dense:true,leading:const Icon(Icons.receipt_long_outlined,color:AppColors.primary,size:18),title:Text('${i.number} • ${i.customer}',style:const TextStyle(fontSize:9.4,fontWeight:FontWeight.w900)),subtitle:Text('${i.cashier} • ${formatDateTime(i.createdAt)} • ${s.paymentMethod(i.paymentMethod)}',style:const TextStyle(fontSize:8.1,color:AppColors.muted)),trailing:Text('${i.total.toStringAsFixed(2)} $currency',style:const TextStyle(fontSize:9.5,fontWeight:FontWeight.w900))),if(i!=filtered.take(60).last)const Divider(height:1)]
        ])),
      ]);
    });
  }
}

class _SalesByEmployee extends StatelessWidget{const _SalesByEmployee({required this.s,required this.invoices});final AppStrings s;final List<SaleInvoice> invoices;@override Widget build(BuildContext context){final store=AppDataStore.instance;final map=<String,double>{};for(final i in invoices){map.update(i.cashier,(v)=>v+i.total,ifAbsent:()=>i.total);}final rows=map.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));return SurfaceCard(padding:EdgeInsets.zero,child:Column(children:[SectionCardHeader(title:s.text('مساهمة الموظفين','Employee contribution'),subtitle:s.text('قيمة المبيعات المسجلة باسم كل كاشير.','Sales value recorded by each cashier.')),const Divider(height:1),if(rows.isEmpty)EmptyPanel(message:s.text('لا توجد بيانات.','No data.'))else for(final e in rows)ListTile(dense:true,title:Text(e.key,style:const TextStyle(fontSize:9.3,fontWeight:FontWeight.w800)),trailing:Text('${e.value.toStringAsFixed(2)} ${store.settings.currency}',style:const TextStyle(fontSize:9.4,fontWeight:FontWeight.w900))) ]));}}

class _ProfitProducts extends StatelessWidget{const _ProfitProducts({required this.s,required this.invoices});final AppStrings s;final List<SaleInvoice> invoices;@override Widget build(BuildContext context){final store=AppDataStore.instance;final map=<String,double>{};for(final i in invoices){for(final l in i.lines){final p=store.productOrNull(l.productId);final contribution=(l.unitPrice-(p?.cost??0))*l.quantity;map.update(l.nameAr,(v)=>v+contribution,ifAbsent:()=>contribution);}}final rows=map.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));return SurfaceCard(padding:EdgeInsets.zero,child:Column(children:[SectionCardHeader(title:s.text('مساهمة الأصناف في الربح','Product profit contribution'),subtitle:s.text('سعر البيع ناقص التكلفة الحالية لكل صنف ضمن الفترة.','Sale price minus current product cost for the selected period.')),const Divider(height:1),if(rows.isEmpty)EmptyPanel(message:s.text('لا توجد بيانات.','No data.'))else for(final e in rows.take(12))ListTile(dense:true,title:Text(e.key,style:const TextStyle(fontSize:9.3,fontWeight:FontWeight.w800)),trailing:Text('${e.value.toStringAsFixed(2)} ${store.settings.currency}',style:TextStyle(fontSize:9.4,fontWeight:FontWeight.w900,color:e.value>=0?AppColors.success:AppColors.danger))) ]));}}

class _TicketBands extends StatelessWidget{const _TicketBands({required this.s,required this.invoices});final AppStrings s;final List<SaleInvoice> invoices;@override Widget build(BuildContext context){int low=0,medium=0,high=0;for(final i in invoices){if(i.total<20)low++;else if(i.total<75)medium++;else high++;}return SurfaceCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(s.text('توزيع أحجام الفواتير','Ticket-size distribution'),style:const TextStyle(fontSize:11.5,fontWeight:FontWeight.w900)),const SizedBox(height:14),Wrap(spacing:10,runSpacing:10,children:[_Band(label:s.text('أقل من 20','Under 20'),value:low,color:AppColors.accent),_Band(label:s.text('20 — 75','20 — 75'),value:medium,color:AppColors.primary),_Band(label:s.text('أكثر من 75','Over 75'),value:high,color:AppColors.blue)])]));}}
class _Band extends StatelessWidget{const _Band({required this.label,required this.value,required this.color});final String label;final int value;final Color color;@override Widget build(BuildContext context)=>Container(width:150,padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:color.withValues(alpha: .07),borderRadius:BorderRadius.circular(13)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('$value',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900,color:color)),Text(label,style:const TextStyle(fontSize:8.5,color:AppColors.muted))]));}
