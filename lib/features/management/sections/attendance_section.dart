import 'dart:async';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/app_controller.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/printing/print_document.dart';
import '../../../core/printing/print_service.dart';
import '../../../data/app_data_store.dart';
import '../../../data/models.dart';
import '../widgets/management_widgets.dart';

class AttendanceSection extends StatefulWidget {
  const AttendanceSection({super.key, required this.s});
  final AppStrings s;
  @override State<AttendanceSection> createState() => _AttendanceSectionState();
}

class _AttendanceSectionState extends State<AttendanceSection> {
  final search = TextEditingController();
  String statusFilter = 'all';
  String periodFilter = 'all';
  int weekdayFilter = 0;
  DateTime? exactDate;
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    search.dispose();
    super.dispose();
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  bool _matchesPeriod(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    if (weekdayFilter != 0 && date.weekday != weekdayFilter) return false;
    return switch (periodFilter) {
      'today' => _sameDay(day, today),
      'yesterday' => _sameDay(day, today.subtract(const Duration(days: 1))),
      'week' => !day.isBefore(today.subtract(Duration(days: today.weekday - 1))) && !day.isAfter(today),
      'custom' => exactDate != null && _sameDay(day, exactDate!),
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final s = widget.s;
    return AnimatedBuilder(animation: store, builder: (_, __) {
      final openNow = store.openAttendance; // also closes forgotten shifts that reached their scheduled end.
      final now = DateTime.now();
      final todayRecords = store.attendance.where((r) => _sameDay(r.clockIn, now)).toList();
      final lateCount = todayRecords.where((r) => store.lateMinutes(r) > 0).length;
      final todayIds = todayRecords.map((r) => r.employeeId).toSet();
      final absent = store.activeEmployees.where((e) => !e.onLeave && e.weeklyOffDay != now.weekday && !todayIds.contains(e.id)).length;
      final q = search.text.trim().toLowerCase();
      final records = store.attendance.where((r) {
        if (statusFilter == 'open' && r.clockOut != null) return false;
        if (statusFilter == 'late' && store.lateMinutes(r) <= 0) return false;
        if (statusFilter == 'auto' && !r.automaticClockOut) return false;
        if (!_matchesPeriod(r.clockIn)) return false;
        final employee = store.employeeOrNull(r.employeeId);
        final employeeNo = employee?.loginId ?? r.employeeId;
        return q.isEmpty || r.employeeName.toLowerCase().contains(q) || r.employeeId.toLowerCase().contains(q) || employeeNo.toLowerCase().contains(q) || formatDate(r.clockIn).contains(q);
      }).toList()..sort((a,b)=>b.clockIn.compareTo(a.clockIn));

      return Column(children: [
        ManagementMetricsGrid(items: [
          ManagementMetric(s.text('الحاضرون الآن','On shift now'),'${openNow.length}',Icons.how_to_reg_outlined,AppColors.success),
          ManagementMetric(s.text('سجلات اليوم','Today records'),'${todayRecords.length}',Icons.event_available_outlined,AppColors.primary),
          ManagementMetric(s.text('تأخير اليوم','Late today'),'$lateCount',Icons.schedule_outlined,AppColors.accent),
          ManagementMetric(s.text('غياب متوقع','Expected absent'),'$absent',Icons.person_off_outlined,AppColors.danger),
        ]),
        const SizedBox(height:12),
        SurfaceCard(padding:EdgeInsets.zero,child:Column(children:[
          SectionCardHeader(
            title:s.text('سجل الحضور والانصراف','Attendance register'),
            subtitle:s.text('يعرض موعد بداية الدوام، وقت الحضور الفعلي، الانصراف، التأخير، والإغلاق التلقائي عند نسيان الانصراف.','Shows scheduled start, actual arrival, clock-out, lateness and automatic shift closing.'),
            trailing:Wrap(spacing:7,runSpacing:7,crossAxisAlignment:WrapCrossAlignment.center,children:[
              SearchField(controller:search,width:230,hint:s.text('اسم، رقم وظيفي، تاريخ...','Name, employee ID, date...'),onChanged:(_)=>setState((){})),
              DropdownButton<String>(value:periodFilter,items:[
                DropdownMenuItem(value:'all',child:Text(s.text('كل التواريخ','All dates'))),
                DropdownMenuItem(value:'today',child:Text(s.text('اليوم','Today'))),
                DropdownMenuItem(value:'yesterday',child:Text(s.text('أمس','Yesterday'))),
                DropdownMenuItem(value:'week',child:Text(s.text('هذا الأسبوع','This week'))),
                DropdownMenuItem(value:'custom',child:Text(s.text('تاريخ محدد','Specific date'))),
              ],onChanged:(v)async{if(v=='custom'){final d=await showDatePicker(context:context,initialDate:exactDate??DateTime.now(),firstDate:DateTime(2020),lastDate:DateTime.now().add(const Duration(days:365)));if(d==null)return;setState((){exactDate=d;periodFilter='custom';});}else{setState(()=>periodFilter=v??'all');}}),
              DropdownButton<int>(value:weekdayFilter,items:[DropdownMenuItem(value:0,child:Text(s.text('كل الأيام','All weekdays'))),for(var d=1;d<=7;d++)DropdownMenuItem(value:d,child:Text(_weekday(s,d)))],onChanged:(v)=>setState(()=>weekdayFilter=v??0)),
              DropdownButton<String>(value:statusFilter,items:[
                DropdownMenuItem(value:'all',child:Text(s.text('كل الحالات','All statuses'))),
                DropdownMenuItem(value:'open',child:Text(s.text('داخل الدوام','On shift'))),
                DropdownMenuItem(value:'late',child:Text(s.text('متأخر','Late'))),
                DropdownMenuItem(value:'auto',child:Text(s.text('انصراف تلقائي','Automatic clock-out'))),
              ],onChanged:(v)=>setState(()=>statusFilter=v??'all')),
              if(s.controller.role==UserRole.owner)
                PopupMenuButton<String>(tooltip:s.text('طباعة','Print'),icon:const Icon(Icons.print_outlined,size:18),onSelected:(v){if(v=='staff'){_printAttendance(records.where((r)=>!r.employeeId.startsWith('ADMIN-')).toList());}else{_printAttendance(records.where((r)=>r.employeeId=='ADMIN-manager'||r.employeeId=='ADMIN-accountant').toList());}},itemBuilder:(_)=>[
                  PopupMenuItem(value:'staff',child:Text(s.text('كشف حضور الموظفين','Staff attendance'))),
                  PopupMenuItem(value:'management',child:Text(s.text('كشف حضور المدير والمحاسب','Manager & accountant attendance'))),
                ])
              else OutlinedButton.icon(onPressed:()=>_printAttendance(records.where((r)=>!r.employeeId.startsWith('ADMIN-')).toList()),icon:const Icon(Icons.print_outlined,size:16),label:Text(s.text('طباعة','Print'))),
            ]),
          ),
          const Divider(height:1),
          if(records.isEmpty)EmptyPanel(message:s.text('لا توجد سجلات مطابقة.','No matching attendance records.'))
          else for(var i=0;i<records.length;i++)...[
            _AttendanceRow(record:records[i],s:s,store:store,onTap:()=>_showDetails(context,records[i])),
            if(i<records.length-1)const Divider(height:1),
          ]
        ]))
      ]);
    });
  }

  Future<void> _printAttendance(List<AttendanceRecord> records) async {
    final store=AppDataStore.instance;final s=widget.s;
    final sorted=[...records]..sort((a,b)=>a.clockIn.compareTo(b.clockIn));
    final rows=<List<String>>[];
    String lastDay='';
    for(final r in sorted){
      final day=formatDate(r.clockIn);
      if(day!=lastDay){
        rows.add(['—— $day ——','','','','','','','']);
        lastDay=day;
      }
      final employee=store.employeeOrNull(r.employeeId);
      final scheduled=store.scheduledStartForAttendance(r);
      rows.add([
        r.employeeName,
        employee?.loginId??r.employeeId,
        day,
        scheduled==null?'-':formatTime(scheduled),
        formatTime(r.clockIn),
        r.clockOut==null?'-':formatTime(r.clockOut!),
        formatDuration(r.duration),
        store.lateMinutes(r)<=0?s.text('في الموعد','On time'):'${formatReadableMinutes(s,store.lateMinutes(r))} ${s.text('تأخير','late')}${r.automaticClockOut?' • ${s.text('انصراف تلقائي','auto out')}':''}',
      ]);
    }
    await ThamanPrintService.printDocument(PrintDocument(
      title:s.text('كشف الحضور والانصراف','Attendance Statement'),
      subtitle:'${store.settings.storeName} • ${store.settings.branchName}',
      metadata:{s.text('عدد السجلات','Records'):'${records.length}',s.text('التاريخ/الفترة','Date / period'):periodFilter=='custom'&&exactDate!=null?formatDate(exactDate!):s.text('حسب الفلتر الحالي','Current filter')},
      headers:[s.text('الموظف','Employee'),s.text('الرقم','ID'),s.text('التاريخ','Date'),s.text('موعد البداية','Scheduled'),s.text('حضر','Clock in'),s.text('انصرف','Clock out'),s.text('المدة','Duration'),s.text('الحالة','Status')],
      rows:rows,footer:store.settings.receiptFooter,isArabic:s.controller.isArabic,
    ));
  }

  void _showDetails(BuildContext context, AttendanceRecord record){
    final s=widget.s;final store=AppDataStore.instance;final employee=store.employeeOrNull(record.employeeId);final scheduledStart=store.scheduledStartForAttendance(record);final scheduledEnd=store.scheduledEndForAttendance(record);
    showDialog<void>(context:context,builder:(dialogContext)=>AlertDialog(scrollable:true,title:Text(s.text('تفاصيل الدوام','Attendance details')),content:SizedBox(width:(MediaQuery.sizeOf(context).width-48).clamp(0.0,520.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[
      DetailLine(label:s.text('الموظف','Employee'),value:'${record.employeeName} • ${employee?.loginId??record.employeeId}'),
      DetailLine(label:s.text('التاريخ','Date'),value:formatDate(record.clockIn)),
      DetailLine(label:s.text('الموعد المفروض يبدأ فيه','Scheduled start'),value:scheduledStart==null?'-':formatTime(scheduledStart)),
      DetailLine(label:s.text('نهاية الدوام المفروضة','Scheduled end'),value:scheduledEnd==null?'-':'${formatDate(scheduledEnd)} • ${formatTime(scheduledEnd)}'),
      DetailLine(label:s.text('وقت الحضور الفعلي','Actual clock in'),value:formatTime(record.clockIn)),
      DetailLine(label:s.text('تسجيل الانصراف','Clock out'),value:record.clockOut==null?s.text('لم يسجل بعد','Not clocked out'):formatTime(record.clockOut!)),
      DetailLine(label:s.text('طريقة الانصراف','Clock-out type'),value:record.automaticClockOut?s.text('تلقائي بعد انتهاء مدة الدوام','Automatic at scheduled shift end'):s.text('يدوي','Manual')),
      DetailLine(label:s.text('المدة','Duration'),value:formatDuration(record.duration)),
      DetailLine(label:s.text('التأخير','Late'),value:formatReadableMinutes(s,store.lateMinutes(record))),
    ])),actions:[FilledButton(onPressed:()=>Navigator.pop(dialogContext),child:Text(s.text('إغلاق','Close')))]));
  }
}

class _AttendanceRow extends StatelessWidget{
  const _AttendanceRow({required this.record,required this.s,required this.store,required this.onTap});
  final AttendanceRecord record;final AppStrings s;final AppDataStore store;final VoidCallback onTap;
  @override Widget build(BuildContext context){
    final employee=store.employeeOrNull(record.employeeId);final scheduled=store.scheduledStartForAttendance(record);final isOpen=record.clockOut==null;final late=store.lateMinutes(record);final color=isOpen?AppColors.success:AppColors.primary;
    return ListTile(onTap:onTap,leading:Container(width:42,height:42,decoration:BoxDecoration(color:color.withValues(alpha: .09),borderRadius:BorderRadius.circular(13)),child:Icon(isOpen?Icons.how_to_reg_rounded:Icons.schedule_outlined,color:color)),
      title:Wrap(spacing:7,runSpacing:4,crossAxisAlignment:WrapCrossAlignment.center,children:[Text('${record.employeeName} • ${employee?.loginId??record.employeeId}',style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900)),if(record.automaticClockOut)StatusPill(label:s.text('انصراف تلقائي','Auto out'),color:AppColors.blue),if(late>0)StatusPill(label:'${formatReadableMinutes(s,late)} ${s.text('تأخير','late')}',color:AppColors.accent)]),
      subtitle:Text('${formatDate(record.clockIn)} • ${s.text('الموعد','Scheduled')}: ${scheduled==null?'—':formatTime(scheduled)} • ${s.text('حضر','In')}: ${formatTime(record.clockIn)} • ${s.text('انصرف','Out')}: ${record.clockOut==null?'—':formatTime(record.clockOut!)}',style:const TextStyle(fontSize:8.4,color:AppColors.muted)),
      trailing:Row(mainAxisSize:MainAxisSize.min,children:[Text(formatDuration(record.duration),style:const TextStyle(fontSize:9,fontWeight:FontWeight.w900)),const SizedBox(width:5),const Icon(Icons.arrow_outward_rounded,size:16)]));
  }
}

String _weekday(AppStrings s,int day)=>switch(day){DateTime.monday=>s.text('الاثنين','Monday'),DateTime.tuesday=>s.text('الثلاثاء','Tuesday'),DateTime.wednesday=>s.text('الأربعاء','Wednesday'),DateTime.thursday=>s.text('الخميس','Thursday'),DateTime.friday=>s.text('الجمعة','Friday'),DateTime.saturday=>s.text('السبت','Saturday'),_=>s.text('الأحد','Sunday')};
