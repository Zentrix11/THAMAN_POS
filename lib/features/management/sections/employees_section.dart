import 'dart:async';
import '../../../core/time_format.dart';
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

class EmployeesSection extends StatefulWidget {
  const EmployeesSection({super.key, required this.s});
  final AppStrings s;
  @override State<EmployeesSection> createState() => _EmployeesSectionState();
}

class _EmployeesSectionState extends State<EmployeesSection> {
  final search = TextEditingController();
  Timer? _refreshTimer;
  @override void initState(){super.initState();_refreshTimer=Timer.periodic(const Duration(minutes:1),(_){if(mounted)setState((){});});}
  @override void dispose(){_refreshTimer?.cancel();search.dispose();super.dispose();}

  @override Widget build(BuildContext context) {
    final store = AppDataStore.instance; final s = widget.s;
    return AnimatedBuilder(animation: store, builder: (_, __) {
      final q = search.text.trim().toLowerCase();
      final employees = store.employees.where((e) => q.isEmpty || e.id.toLowerCase().contains(q) || e.loginId.toLowerCase().contains(q) || e.nameAr.toLowerCase().contains(q) || e.nameEn.toLowerCase().contains(q) || e.roleKey.toLowerCase().contains(q) || e.phone.contains(q)).toList();
      return Column(children: [
        ManagementMetricsGrid(items: [
          ManagementMetric(s.text('الموظفون النشطون','Active employees'),'${store.activeEmployees.length}',Icons.badge_outlined,AppColors.primary),
          ManagementMetric(s.text('داخل الدوام الآن','On shift now'),'${store.openAttendance.length}',Icons.how_to_reg_outlined,AppColors.success),
          ManagementMetric(s.text('في إجازة','On leave'),'${store.employees.where((e)=>e.onLeave).length}',Icons.beach_access_outlined,AppColors.accent),
          ManagementMetric(s.text('مهام متأخرة','Overdue tasks'),'${store.overdueTasks.length}',Icons.warning_amber_rounded,AppColors.danger),
        ]),
        const SizedBox(height: 12),
        SurfaceCard(padding: EdgeInsets.zero, child: Column(children: [
          SectionCardHeader(title: s.text('إدارة الموظفين','Employee management'), subtitle: s.text('بحث بالاسم أو الرقم الوظيفي، ثم افتح قائمة التحكم لكل موظف.','Search by name or employee ID, then open controls for any employee.'), trailing: Wrap(spacing:8,runSpacing:8,children:[SearchField(controller: search, hint: s.text('اسم أو رقم وظيفي...','Name or employee ID...'), onChanged: (_) => setState((){}), width: 245),OutlinedButton.icon(onPressed:()=>_printEmployees(employees),icon:const Icon(Icons.print_outlined,size:16),label:Text(s.text('طباعة','Print'))),FilledButton.icon(onPressed:()=>_addEmployee(context),icon:const Icon(Icons.person_add_alt_1_rounded,size:17),label:Text(s.text('إضافة موظف','Add employee')))])),
          const Divider(height: 1),
          if (employees.isEmpty) EmptyPanel(message: s.text('لا توجد نتائج.','No matching employees.'))
          else for (final e in employees) ...[
            _EmployeeTile(employee: e, s: s, onAction: (action) => _handleAction(context, e, action)),
            if (e != employees.last) const Divider(height: 1),
          ],
        ])),
      ]);
    });
  }


  Future<void> _printEmployees(List<EmployeeRecord> employees) async {
    final store=AppDataStore.instance; final s=widget.s;
    await ThamanPrintService.printDocument(PrintDocument(
      title:s.text('كشف الموظفين','Employees Statement'),
      subtitle:'${store.settings.storeName} • ${store.settings.branchName}',
      metadata:{s.text('عدد الموظفين','Employees'):'${employees.length}',s.text('فلتر البحث','Search filter'):search.text.trim().isEmpty?'-':search.text.trim()},
      headers:[s.text('الرقم','ID'),s.text('الاسم','Name'),s.text('الدور','Role'),s.text('الهاتف','Phone'),s.text('الراتب','Salary'),s.text('الفرع','Branch'),s.text('الدوام','Shift'),s.text('الحالة','Status')],
      rows:employees.map((e)=>[e.loginId,s.text(e.nameAr,e.nameEn),s.roleKey(e.roleKey),e.phone,e.salary>0?'${e.salary.toStringAsFixed(2)} ${store.settings.currency}':s.text('غير محدد','Not set'),e.branch,e.shiftLabel,!e.active?s.text('منتهي الخدمة','Terminated'):e.onLeave?s.text('إجازة','On leave'):store.currentAttendance(e.id)!=null?s.text('داخل الدوام','On shift'):s.text('خارج الدوام','Off shift')]).toList(),
      footer:store.settings.receiptFooter,
    
      isArabic: widget.s.controller.isArabic,));
  }

  Future<void> _handleAction(BuildContext context, EmployeeRecord e, String action) async {
    switch(action) {
      case 'details': _showDetails(context,e); break;
      case 'rename': await _rename(context,e); break;
      case 'task': await _assignTask(context,e); break;
      case 'shift': await _shift(context,e); break;
      case 'leave': await _leave(context,e); break;
      case 'credentials': await _credentials(context,e); break;
      case 'payroll': await _payroll(context,e); break;
      case 'overtime': await _overtime(context,e); break;
      case 'terminate': await _terminate(context,e); break;
      case 'reactivate': await _reactivate(context,e); break;
      case 'delete': await _delete(context,e); break;
    }
  }

  void _showDetails(BuildContext context, EmployeeRecord e) {
    final s=widget.s; final store=AppDataStore.instance;
    final tasks=store.tasks.where((t)=>t.assignedEmployeeId==e.id).toList();
    final att=store.attendance.where((a)=>a.employeeId==e.id).toList();
    final completed=tasks.where((t)=>t.done).length;
    final overdue=tasks.where((t)=>t.isOverdue).length;
    showDialog<void>(context:context,builder:(_)=>AlertDialog(
          scrollable: true,
      title: Text(s.text(e.nameAr,e.nameEn)),
      content:SizedBox(width:(MediaQuery.sizeOf(context).width - 48).clamp(0.0, 620.0).toDouble(),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        DetailLine(label:s.text('الرقم الوظيفي','Employee ID'),value:e.loginId),
        DetailLine(label:s.text('الدور','Role'),value:s.roleKey(e.roleKey)),
        DetailLine(label:s.text('الهاتف','Phone'),value:e.phone),
        DetailLine(label:s.text('الفرع','Branch'),value:e.branch),
        DetailLine(label:s.text('الوردية','Shift'),value:e.shiftLabel),
        DetailLine(label:s.text('الراتب الشهري','Monthly salary'),value:e.salary>0?'${e.salary.toStringAsFixed(2)} ${store.settings.currency}':s.text('غير محدد','Not set')),
        DetailLine(label:s.text('يوم القبض','Pay day'),value:e.salaryPayDay.toString()),
        DetailLine(label:s.text('الحالة','Status'),value:!e.active?s.text('منتهي الخدمة','Terminated'):e.onLeave?s.text('إجازة','On leave'):store.currentAttendance(e.id)!=null?s.text('داخل الدوام','On shift'):s.text('خارج الدوام','Off shift')),
        const Divider(height:24),
        Wrap(spacing:8,runSpacing:8,children:[StatusPill(label:'${s.text('المهام','Tasks')}: ${tasks.length}',color:AppColors.blue),StatusPill(label:'${s.text('مكتملة','Completed')}: $completed',color:AppColors.success),StatusPill(label:'${s.text('متأخرة','Overdue')}: $overdue',color:AppColors.danger),StatusPill(label:'${s.text('سجلات حضور','Attendance')}: ${att.length}',color:AppColors.primary)]),
        const SizedBox(height:18),
        Text(s.text('آخر المهام','Latest tasks'),style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900)),
        const SizedBox(height:8),
        if(tasks.isEmpty)Text(s.text('لا توجد مهام.','No tasks.'),style:const TextStyle(fontSize:9,color:AppColors.muted)) else for(final t in tasks.take(6))Container(margin:const EdgeInsets.only(bottom:6),padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:AppColors.surfaceAlt,borderRadius:BorderRadius.circular(11)),child:Row(children:[Expanded(child:Text(s.text(t.titleAr,t.titleEn),style:const TextStyle(fontSize:8.9,fontWeight:FontWeight.w800))),StatusPill(label:taskStatusLabel(s,t.status),color:taskStatusColor(t.status,overdue:t.isOverdue))])),
      ]))),actions:[FilledButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إغلاق','Close')))]));
  }

  Future<void> _rename(BuildContext context,EmployeeRecord e) async {final s=widget.s;final ar=TextEditingController(text:e.nameAr);final en=TextEditingController(text:e.nameEn);await showDialog<void>(context:context,builder:(_)=>AlertDialog(
          scrollable: true,title:Text(s.text('تعديل اسم الموظف','Rename employee')),content:SizedBox(width:(MediaQuery.sizeOf(context).width - 48).clamp(0.0, 450.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:ar,decoration:InputDecoration(labelText:s.text('الاسم بالعربية','Arabic name'))),const SizedBox(height:10),TextField(controller:en,decoration:InputDecoration(labelText:s.text('الاسم بالإنجليزية','English name')))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إلغاء','Cancel'))),FilledButton(onPressed:(){if(ar.text.trim().isEmpty)return;AppDataStore.instance.renameEmployee(e.id,nameAr:ar.text.trim(),nameEn:en.text.trim().isEmpty?ar.text.trim():en.text.trim());Navigator.pop(context);},child:Text(s.text('حفظ','Save')))]));ar.dispose();en.dispose();}

  Future<void> _assignTask(BuildContext context,EmployeeRecord e) async {final s=widget.s;final title=TextEditingController();final desc=TextEditingController();String priority='medium';DateTime due=DateTime.now().add(const Duration(hours:4));await showDialog<void>(context:context,builder:(_)=>StatefulBuilder(builder:(context,setD)=>AlertDialog(
          scrollable: true,title:Text('${s.text('تكليف مهمة','Assign task')} • ${s.text(e.nameAr,e.nameEn)}'),content:SizedBox(width:(MediaQuery.sizeOf(context).width - 48).clamp(0.0, 500.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:title,decoration:InputDecoration(labelText:s.text('عنوان المهمة','Task title'))),const SizedBox(height:10),TextField(controller:desc,maxLines:2,decoration:InputDecoration(labelText:s.text('التفاصيل','Details'))),const SizedBox(height:10),DropdownButtonFormField<String>(value:priority,decoration:InputDecoration(labelText:s.text('الأولوية','Priority')),items:[DropdownMenuItem(value:'low',child:Text(s.text('منخفضة','Low'))),DropdownMenuItem(value:'medium',child:Text(s.text('متوسطة','Medium'))),DropdownMenuItem(value:'high',child:Text(s.text('عالية','High')))],onChanged:(v)=>setD(()=>priority=v??'medium')),const SizedBox(height:10),ListTile(contentPadding:EdgeInsets.zero,title:Text(s.text('موعد الاستحقاق','Due date'),style:const TextStyle(fontSize:9,fontWeight:FontWeight.w800)),subtitle:Text(formatDateTime(due),style:const TextStyle(fontSize:8.5,color:AppColors.muted)),trailing:OutlinedButton(onPressed:()async{final d=await showDatePicker(context:context,firstDate:DateTime.now(),lastDate:DateTime.now().add(const Duration(days:365)),initialDate:due);if(d!=null)setD(()=>due=DateTime(d.year,d.month,d.day,23,59));},child:Text(s.text('تغيير','Change'))))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إلغاء','Cancel'))),FilledButton(onPressed:(){if(title.text.trim().isEmpty)return;AppDataStore.instance.createTask(title:title.text.trim(),employeeId:e.id,dueAt:due,priority:priority,assignedBy:s.controller.currentUserName,description:desc.text.trim());Navigator.pop(context);},child:Text(s.text('إرسال المهمة','Assign')))])));title.dispose();desc.dispose();}

  Future<void> _shift(BuildContext context,EmployeeRecord e) async {final s=widget.s;int start=e.shiftStartMinutes,end=e.shiftEndMinutes,off=e.weeklyOffDay;await showDialog<void>(context:context,builder:(_)=>StatefulBuilder(builder:(context,setD)=>AlertDialog(
          scrollable: true,title:Text(s.text('تعديل أوقات الدوام','Edit work schedule')),content:SizedBox(width:(MediaQuery.sizeOf(context).width - 48).clamp(0.0, 500.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[_TimeSetting(label:s.text('بداية الوردية','Shift start'),minutes:start,onPick:()async{final t=await showTimePicker(context:context,initialTime:TimeOfDay(hour:start~/60,minute:start%60));if(t!=null)setD(()=>start=t.hour*60+t.minute);}),const SizedBox(height:8),_TimeSetting(label:s.text('نهاية الوردية','Shift end'),minutes:end,onPick:()async{final t=await showTimePicker(context:context,initialTime:TimeOfDay(hour:end~/60,minute:end%60));if(t!=null)setD(()=>end=t.hour*60+t.minute);}),const SizedBox(height:10),DropdownButtonFormField<int>(value:off,decoration:InputDecoration(labelText:s.text('يوم الإجازة الأسبوعي','Weekly off day')),items:List.generate(7,(i){final day=i+1;return DropdownMenuItem(value:day,child:Text(_weekday(s,day)));}),onChanged:(v)=>setD(()=>off=v??DateTime.friday))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إلغاء','Cancel'))),FilledButton(onPressed:(){AppDataStore.instance.updateEmployeeShift(e.id,start,end,off);Navigator.pop(context);},child:Text(s.text('حفظ','Save')))])));}

  Future<void> _leave(BuildContext context,EmployeeRecord e) async {final s=widget.s;DateTime start=DateTime.now(),end=DateTime.now();String type='annual';final note=TextEditingController();await showDialog<void>(context:context,builder:(_)=>StatefulBuilder(builder:(context,setD)=>AlertDialog(
          scrollable: true,title:Text('${s.text('تحديد إجازة','Set leave')} • ${s.text(e.nameAr,e.nameEn)}'),content:SizedBox(width:(MediaQuery.sizeOf(context).width - 48).clamp(0.0, 500.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField<String>(value:type,decoration:InputDecoration(labelText:s.text('نوع الإجازة','Leave type')),items:[DropdownMenuItem(value:'annual',child:Text(s.text('سنوية','Annual'))),DropdownMenuItem(value:'sick',child:Text(s.text('مرضية','Sick'))),DropdownMenuItem(value:'unpaid',child:Text(s.text('بدون راتب','Unpaid')))],onChanged:(v)=>setD(()=>type=v??'annual')),const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton(onPressed:()async{final d=await showDatePicker(context:context,firstDate:DateTime.now().subtract(const Duration(days:30)),lastDate:DateTime.now().add(const Duration(days:365)),initialDate:start);if(d!=null)setD(()=>start=d);},child:Text('${s.text('من','From')}: ${formatDate(start)}'))),const SizedBox(width:8),Expanded(child:OutlinedButton(onPressed:()async{final d=await showDatePicker(context:context,firstDate:start,lastDate:DateTime.now().add(const Duration(days:730)),initialDate:end.isBefore(start)?start:end);if(d!=null)setD(()=>end=d);},child:Text('${s.text('إلى','To')}: ${formatDate(end)}')))]),const SizedBox(height:10),TextField(controller:note,maxLines:2,decoration:InputDecoration(labelText:s.text('ملاحظة','Note')))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إلغاء','Cancel'))),FilledButton(onPressed:(){if(end.isBefore(start))return;AppDataStore.instance.setEmployeeLeave(employeeId:e.id,start:start,end:end,type:type,createdBy:s.controller.currentUserName,note:note.text.trim());Navigator.pop(context);},child:Text(s.text('اعتماد الإجازة','Set leave')))])));note.dispose();}

  Future<void> _credentials(BuildContext context,EmployeeRecord e) async {
    final s=widget.s;
    final loginId=TextEditingController(text:e.loginId);
    final pin=TextEditingController();
    String? error;
    await showDialog<void>(context:context,builder:(_)=>StatefulBuilder(builder:(context,setD)=>AlertDialog(
          scrollable: true,
      title:Text(s.text('بيانات دخول الموظف','Employee login credentials')),
      content:SizedBox(width:(MediaQuery.sizeOf(context).width - 48).clamp(0.0, 460.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[
        if(error!=null)Container(width:double.infinity,margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:AppColors.danger.withValues(alpha: .08),borderRadius:BorderRadius.circular(10)),child:Text(error!,style:const TextStyle(fontSize:8.7,color:AppColors.danger,fontWeight:FontWeight.w800))),
        Builder(builder:(context){
          final duplicate=AppDataStore.instance.activeEmployeeUsingLoginId(loginId.text,exceptEmployeeId:e.id);
          return TextField(controller:loginId,onChanged:(_)=>setD((){}),decoration:InputDecoration(
            labelText:s.text('الرقم الوظيفي / رقم الدخول','Employee / login ID'),
            errorText:duplicate==null?null:s.text('هذا الرقم مستخدم بواسطة ${duplicate.nameAr}.','This ID is used by ${duplicate.nameEn}.'),
            enabledBorder:duplicate==null?null:const OutlineInputBorder(borderSide:BorderSide(color:AppColors.danger)),
          ));
        }),
        const SizedBox(height:10),
        TextField(controller:pin,maxLength:6,keyboardType:TextInputType.number,obscureText:true,decoration:InputDecoration(labelText:s.text('PIN جديد (اتركه فارغاً للإبقاء عليه)','New PIN (leave blank to keep current)'))),
        const SizedBox(height:4),
        Text(s.text('هذه الصلاحية متاحة للمالك والمدير فقط، ويتم تسجيل التغيير في سجل التدقيق.','Only the owner and manager can change staff credentials. The change is written to the audit log.'),style:const TextStyle(fontSize:8.2,color:AppColors.muted)),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إلغاء','Cancel'))),FilledButton(onPressed:(){
        final actorRole=s.controller.role==UserRole.owner?'owner':'manager';
        final ok=AppDataStore.instance.updateEmployeeCredentials(employeeId:e.id,loginId:loginId.text,pin:pin.text,actorName:s.controller.currentUserName,actorRole:actorRole);
        if(!ok){setD(()=>error=s.text('تعذر الحفظ. تأكد أن رقم الدخول غير مستخدم وأن PIN الجديد 4 أرقام على الأقل.','Could not save. Make sure the login ID is unique and a new PIN is at least 4 digits.'));return;}
        Navigator.pop(context);
      },child:Text(s.text('حفظ بيانات الدخول','Save credentials')))]
    )));
    loginId.dispose();pin.dispose();
  }

  Future<void> _payroll(BuildContext context, EmployeeRecord e) async {
    final s=widget.s;
    final salary=TextEditingController(text:e.salary<=0?'':e.salary.toStringAsFixed(2));
    final day=TextEditingController(text:'${e.salaryPayDay}');
    String? error;
    await showDialog<void>(context:context,builder:(_)=>StatefulBuilder(builder:(context,setD)=>AlertDialog(
      scrollable:true,
      title:Text('${s.text('الراتب وموعد القبض','Salary & pay date')} • ${s.text(e.nameAr,e.nameEn)}'),
      content:SizedBox(width:(MediaQuery.sizeOf(context).width-48).clamp(0.0,460.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[
        if(error!=null)Container(width:double.infinity,margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:AppColors.danger.withValues(alpha: .08),borderRadius:BorderRadius.circular(10)),child:Text(error!,style:const TextStyle(fontSize:8.7,color:AppColors.danger,fontWeight:FontWeight.w800))),
        TextField(controller:salary,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:s.text('الراتب الشهري','Monthly salary'),suffixText:AppDataStore.instance.settings.currency)),
        const SizedBox(height:10),
        TextField(controller:day,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:s.text('يوم القبض من الشهر (1-31)','Pay day of month (1-31)'))),
        const SizedBox(height:8),
        Text(s.text('تفاصيل الرواتب سرية ولا تظهر إلا للمالك والمدير والمحاسب. صرف الراتب يتم من قسم الرواتب ويضاف تلقائيًا للمصاريف.','Payroll details are confidential and visible only to owner, manager and accountant. Salary payment is recorded from Payroll and automatically added to expenses.'),style:const TextStyle(fontSize:8.2,color:AppColors.muted,height:1.5)),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إلغاء','Cancel'))),
        FilledButton(onPressed:(){
          final amount=double.tryParse(salary.text.trim())??-1;
          final payDay=int.tryParse(day.text.trim())??0;
          if(amount<0||payDay<1||payDay>31){setD(()=>error=s.text('أدخل راتبًا صحيحًا ويوم قبض بين 1 و31.','Enter a valid salary and pay day between 1 and 31.'));return;}
          final role=s.controller.role?.name??'';
          final ok=AppDataStore.instance.updateEmployeePayroll(employeeId:e.id,salary:amount,payDay:payDay,actorName:s.controller.currentUserName,actorRole:role);
          if(!ok){setD(()=>error=s.text('تعذر حفظ بيانات الراتب.','Could not save payroll settings.'));return;}
          Navigator.pop(context);
        },child:Text(s.text('حفظ','Save'))),
      ],
    )));
    salary.dispose();day.dispose();
  }

  Future<void> _overtime(BuildContext context, EmployeeRecord e) async {
    final s=widget.s;
    var date=DateTime.now();
    var start=TimeOfDay.now();
    var end=TimeOfDay(hour:(start.hour+2)%24,minute:start.minute);
    final note=TextEditingController();
    final multiplier=TextEditingController(text:'1.0');
    String? error;
    await showDialog<void>(context:context,builder:(_)=>StatefulBuilder(builder:(context,setD)=>AlertDialog(
      scrollable:true,
      title:Text('${s.text('تسجيل دوام إضافي','Record overtime')} • ${s.text(e.nameAr,e.nameEn)}'),
      content:SizedBox(width:(MediaQuery.sizeOf(context).width-48).clamp(0.0,500.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[
        if(error!=null)Container(width:double.infinity,margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:AppColors.danger.withValues(alpha: .08),borderRadius:BorderRadius.circular(10)),child:Text(error!,style:const TextStyle(color:AppColors.danger,fontWeight:FontWeight.w800,fontSize:8.7))),
        OutlinedButton.icon(onPressed:()async{final d=await showDatePicker(context:context,initialDate:date,firstDate:DateTime.now().subtract(const Duration(days:365)),lastDate:DateTime.now().add(const Duration(days:365)));if(d!=null)setD(()=>date=d);},icon:const Icon(Icons.calendar_month_outlined),label:Text(formatDate(date))),
        const SizedBox(height:8),
        Row(children:[Expanded(child:_TimeSetting(label:s.text('بداية الدوام الإضافي','Overtime start'),minutes:start.hour*60+start.minute,onPick:()async{final t=await showTimePicker(context:context,initialTime:start);if(t!=null)setD(()=>start=t);})),const SizedBox(width:10),Expanded(child:_TimeSetting(label:s.text('نهاية الدوام الإضافي','Overtime end'),minutes:end.hour*60+end.minute,onPick:()async{final t=await showTimePicker(context:context,initialTime:end);if(t!=null)setD(()=>end=t);}))]),
        const SizedBox(height:8),
        TextField(controller:multiplier,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:s.text('معامل الدوام الإضافي','Overtime multiplier'),helperText:s.text('مثال: 1.0 أو 1.5','Example: 1.0 or 1.5'))),
        const SizedBox(height:8),
        TextField(controller:note,maxLines:2,decoration:InputDecoration(labelText:s.text('بيانات / ملاحظة الدوام الإضافي','Overtime details / note'))),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إلغاء','Cancel'))),FilledButton(onPressed:(){
        var startAt=DateTime(date.year,date.month,date.day,start.hour,start.minute);
        var endAt=DateTime(date.year,date.month,date.day,end.hour,end.minute);
        if(!endAt.isAfter(startAt))endAt=endAt.add(const Duration(days:1));
        final mult=double.tryParse(multiplier.text.trim())??0;
        final role=s.controller.role?.name??'';
        final result=AppDataStore.instance.recordOvertime(employeeId:e.id,startAt:startAt,endAt:endAt,createdBy:s.controller.currentUserName,actorRole:role,note:note.text,rateMultiplier:mult);
        if(result==null){setD(()=>error=s.text('تعذر تسجيل الدوام الإضافي. هذه الصلاحية للمالك والمدير وتأكد من الأوقات.','Could not record overtime. Owner/manager permission and valid times are required.'));return;}
        Navigator.pop(context);
      },child:Text(s.text('حفظ الدوام الإضافي','Save overtime')))],
    )));
    note.dispose();multiplier.dispose();
  }

  Future<void> _reactivate(BuildContext context, EmployeeRecord e) async {
    final store=AppDataStore.instance;final s=widget.s;
    final duplicate=store.activeEmployeeUsingLoginId(e.loginId,exceptEmployeeId:e.id);
    if(duplicate==null){store.reactivateEmployee(e.id);return;}
    final login=TextEditingController(text:e.loginId);
    String? error=s.text('الرقم ${e.loginId} مستخدم حاليًا بواسطة ${duplicate.nameAr}. اختر رقمًا آخر قبل إعادة التفعيل.','ID ${e.loginId} is currently used by ${duplicate.nameEn}. Choose another ID before reactivation.');
    await showDialog<void>(context:context,builder:(_)=>StatefulBuilder(builder:(context,setD){
      final conflict=store.activeEmployeeUsingLoginId(login.text,exceptEmployeeId:e.id);
      return AlertDialog(scrollable:true,title:Text(s.text('تغيير الرقم قبل إعادة التفعيل','Change ID before reactivation')),content:SizedBox(width:460,child:Column(mainAxisSize:MainAxisSize.min,children:[
        if(error!=null)Container(width:double.infinity,margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:AppColors.danger.withValues(alpha: .08),borderRadius:BorderRadius.circular(10)),child:Text(error!,style:const TextStyle(color:AppColors.danger,fontWeight:FontWeight.w800))),
        TextField(controller:login,onChanged:(_)=>setD(()=>error=null),decoration:InputDecoration(labelText:s.text('الرقم الوظيفي الجديد','New employee ID'),errorText:conflict==null?null:s.text('هذا الرقم مستخدم بواسطة ${conflict.nameAr}.','This ID is used by ${conflict.nameEn}.'),enabledBorder:conflict==null?null:const OutlineInputBorder(borderSide:BorderSide(color:AppColors.danger)),focusedBorder:conflict==null?null:const OutlineInputBorder(borderSide:BorderSide(color:AppColors.danger,width:1.6))))
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إلغاء','Cancel'))),FilledButton(onPressed:conflict!=null?null:(){
        final role=s.controller.role?.name??'';
        final ok=store.updateEmployeeCredentials(employeeId:e.id,loginId:login.text,pin:'',actorName:s.controller.currentUserName,actorRole:role);
        if(!ok||!store.reactivateEmployee(e.id)){setD(()=>error=s.text('تعذر إعادة التفعيل. تحقق من الرقم الوظيفي والصلاحية.','Could not reactivate. Check employee ID and permission.'));return;}
        Navigator.pop(context);
      },child:Text(s.text('حفظ وإعادة التفعيل','Save & reactivate')))]);
    }));
    login.dispose();
  }

  Future<void> _addEmployee(BuildContext context) async {
    final s=widget.s;
    final id=TextEditingController(), ar=TextEditingController(), en=TextEditingController(), pin=TextEditingController(), phone=TextEditingController(), salary=TextEditingController(), payDay=TextEditingController(text:'1');
    String role='general';
    int start=8*60,end=16*60,off=DateTime.friday;
    String? error;
    await showDialog<void>(context:context,builder:(_)=>StatefulBuilder(builder:(context,setD)=>AlertDialog(
          scrollable: true,
      title:Text(s.text('إضافة موظف','Add employee')),
      content:SizedBox(width:(MediaQuery.sizeOf(context).width - 48).clamp(0.0, 520.0).toDouble(),child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        if(error!=null)Container(width:double.infinity,margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:AppColors.danger.withValues(alpha: .08),borderRadius:BorderRadius.circular(10)),child:Text(error!,style:const TextStyle(fontSize:8.7,color:AppColors.danger,fontWeight:FontWeight.w800))),
        Builder(builder:(context){final duplicate=AppDataStore.instance.activeEmployeeUsingLoginId(id.text);return TextField(controller:id,onChanged:(_)=>setD((){}),decoration:InputDecoration(labelText:s.text('الرقم الوظيفي','Employee ID'),errorText:duplicate==null?null:s.text('هذا الرقم مستخدم بواسطة ${duplicate.nameAr}.','This ID is already assigned to ${duplicate.nameEn}.'),enabledBorder:duplicate==null?null:const OutlineInputBorder(borderSide:BorderSide(color:AppColors.danger))));}),const SizedBox(height:8),
        TextField(controller:ar,decoration:InputDecoration(labelText:s.text('الاسم بالعربية','Arabic name'))),const SizedBox(height:8),
        TextField(controller:en,decoration:InputDecoration(labelText:s.text('الاسم بالإنجليزية','English name'))),const SizedBox(height:8),
        TextField(controller:phone,decoration:InputDecoration(labelText:s.text('الهاتف','Phone'))),const SizedBox(height:8),
        TextField(controller:pin,keyboardType:TextInputType.number,obscureText:true,decoration:InputDecoration(labelText:s.text('PIN الموظف','Employee PIN'))),const SizedBox(height:8),
        TextField(controller:salary,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:s.text('الراتب الشهري (اختياري)','Monthly salary (optional)'),suffixText:AppDataStore.instance.settings.currency)),const SizedBox(height:8),
        TextField(controller:payDay,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:s.text('يوم القبض (1-31)','Pay day (1-31)'))),const SizedBox(height:8),
        DropdownButtonFormField<String>(value:role,decoration:InputDecoration(labelText:s.text('نوع الموظف','Employee role')),items:[DropdownMenuItem(value:'cashier',child:Text(s.text('كاشير','Cashier'))),DropdownMenuItem(value:'inventory',child:Text(s.text('موظف المخزن','Warehouse employee'))),DropdownMenuItem(value:'general',child:Text(s.text('موظف عام','General employee')))],onChanged:(v)=>setD(()=>role=v??'general')),
        const SizedBox(height:8),_TimeSetting(label:s.text('بداية الوردية','Shift start'),minutes:start,onPick:()async{final t=await showTimePicker(context:context,initialTime:TimeOfDay(hour:start~/60,minute:start%60));if(t!=null)setD(()=>start=t.hour*60+t.minute);}),
        _TimeSetting(label:s.text('نهاية الوردية','Shift end'),minutes:end,onPick:()async{final t=await showTimePicker(context:context,initialTime:TimeOfDay(hour:end~/60,minute:end%60));if(t!=null)setD(()=>end=t.hour*60+t.minute);}),
        DropdownButtonFormField<int>(value:off,decoration:InputDecoration(labelText:s.text('الإجازة الأسبوعية','Weekly off')),items:List.generate(7,(i){final day=i+1;return DropdownMenuItem(value:day,child:Text(_weekday(s,day)));}),onChanged:(v)=>setD(()=>off=v??DateTime.friday)),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إلغاء','Cancel'))),FilledButton(onPressed:(){
        final employeeId=id.text.trim().toUpperCase();
        if(employeeId.isEmpty||ar.text.trim().isEmpty||pin.text.trim().length<4){setD(()=>error=s.text('أدخل الرقم والاسم وPIN من 4 أرقام على الأقل.','Enter ID, name and a PIN of at least 4 digits.'));return;}
        final existingLogin=AppDataStore.instance.employees.where((e)=>e.active&&e.loginId.trim().toUpperCase()==employeeId).toList();
        if(existingLogin.isNotEmpty){setD(()=>error=s.text('الرقم الوظيفي مستخدم فعليًا لموظف نشط.','Employee ID is currently assigned to an active employee.'));return;}
        final salaryValue=salary.text.trim().isEmpty?0.0:double.tryParse(salary.text.trim())??-1;
        final salaryDay=int.tryParse(payDay.text.trim())??0;
        if(salaryValue<0||salaryDay<1||salaryDay>31){setD(()=>error=s.text('تحقق من الراتب ويوم القبض.','Check salary and pay day.'));return;}
        final internalId=AppDataStore.instance.employeeOrNull(employeeId)==null?employeeId:'${employeeId}__${DateTime.now().millisecondsSinceEpoch}';
        AppDataStore.instance.addEmployee(id:internalId,loginId:employeeId,nameAr:ar.text.trim(),nameEn:en.text.trim().isEmpty?ar.text.trim():en.text.trim(),roleKey:role,pin:pin.text.trim(),phone:phone.text.trim(),branch:AppDataStore.instance.settings.branchName,shiftStartMinutes:start,shiftEndMinutes:end,weeklyOffDay:off,salary:salaryValue,salaryPayDay:salaryDay);
        Navigator.pop(context);
      },child:Text(s.text('إضافة','Add')))])));
    for(final c in [id,ar,en,pin,phone,salary,payDay]){c.dispose();}
  }

  Future<void> _terminate(BuildContext context,EmployeeRecord e) async {
    final s=widget.s;
    if(e.managementOnly && s.controller.role!=UserRole.owner){
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s.text('المالك فقط يستطيع إنهاء خدمة المدير أو المحاسب.','Only the owner can terminate a manager or accountant.'))));
      return;
    }
    final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(
      scrollable:true,
      title:Text(s.text('إنهاء خدمة الموظف؟','Terminate employee?')),
      content:Text(e.managementOnly
          ? s.text('سيتم تعطيل حساب الإدارة ومنع تسجيل دخوله، مع الاحتفاظ بسجل الحضور والرواتب والحركات السابقة.','The management account will be disabled and login blocked while historical attendance, payroll and transactions remain preserved.')
          : s.text('سيتم تعطيل الحساب ومنع تسجيل الدخول، مع الاحتفاظ بسجل الحضور والمهام السابقة.','The account will be disabled while attendance and task history remain preserved.')),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:Text(s.text('إلغاء','Cancel'))),FilledButton(onPressed:()=>Navigator.pop(context,true),style:FilledButton.styleFrom(backgroundColor:AppColors.danger),child:Text(s.text('إنهاء الخدمة','Terminate')))]
    ));
    if(ok==true) AppDataStore.instance.terminateEmployee(e.id);
  }

  Future<void> _delete(BuildContext context,EmployeeRecord e) async {
    final s=widget.s;
    if(s.controller.role!=UserRole.owner){
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s.text('حذف الموظفين متاح للمالك فقط.','Deleting employees is available to the owner only.'))));
      return;
    }
    final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(
      scrollable:true,
      title:Text(s.text('حذف الموظف نهائيًا؟','Delete employee permanently?')),
      content:Text(s.text('سيُحذف الموظف من قائمة الموظفين، لكن سجلاته التاريخية مثل الحضور والرواتب والفواتير ستبقى محفوظة. إذا كان مديرًا أو محاسبًا فسيُحذف حساب دخوله أيضًا ويمكن إنشاء حساب جديد لاحقًا.','The employee will be removed from the employee list, while historical attendance, payroll and invoice records remain preserved. If this is a manager or accountant, their login account will also be removed and can be recreated later.')),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:Text(s.text('إلغاء','Cancel'))),FilledButton(onPressed:()=>Navigator.pop(context,true),style:FilledButton.styleFrom(backgroundColor:AppColors.danger),child:Text(s.text('حذف','Delete')))]
    ));
    if(ok==true){
      final deleted=AppDataStore.instance.deleteEmployee(e.id,actorRole:'owner');
      if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(deleted?s.text('تم حذف الموظف مع إبقاء سجلاته التاريخية.','Employee deleted while historical records were preserved.'):s.text('تعذر حذف الموظف.','Could not delete employee.'))));
    }
  }
}

class _EmployeeTile extends StatelessWidget{
  const _EmployeeTile({required this.employee,required this.s,required this.onAction});
  final EmployeeRecord employee;final AppStrings s;final ValueChanged<String> onAction;
  @override Widget build(BuildContext context){
    final store=AppDataStore.instance;
    final current=store.currentAttendance(employee.id);
    final tasks=store.tasks.where((t)=>t.assignedEmployeeId==employee.id).toList();
    final now=DateTime.now();
    AttendanceRecord? today;
    for(final a in store.attendance){if(a.employeeId==employee.id&&a.clockIn.year==now.year&&a.clockIn.month==now.month&&a.clockIn.day==now.day){today=a;break;}}
    final late=today==null?0:store.lateMinutes(today!);
    final status=!employee.active?s.text('منتهي الخدمة','Terminated'):employee.onLeave?s.text('إجازة','On leave'):current!=null?s.text('داخل الدوام','On shift'):s.text('خارج الدوام','Off shift');
    final color=!employee.active?AppColors.danger:employee.onLeave?AppColors.accent:current!=null?AppColors.success:AppColors.muted;
    final canOvertime=const {UserRole.owner,UserRole.manager}.contains(s.controller.role);
    return ListTile(
      onTap:()=>onAction('details'),
      leading:CircleAvatar(backgroundColor:color.withValues(alpha: .1),child:Text(employee.nameAr.isEmpty?'E':employee.nameAr.substring(0,1),style:TextStyle(color:color,fontWeight:FontWeight.w900))),
      title:Wrap(spacing:7,runSpacing:4,crossAxisAlignment:WrapCrossAlignment.center,children:[Text('${s.text(employee.nameAr,employee.nameEn)} • ${employee.loginId}',style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900)),if(employee.managementOnly)StatusPill(label:s.roleKey(employee.roleKey),color:AppColors.blue),if(late>0)StatusPill(label:'${s.text('متأخر','Late')} $late ${s.text('د','m')}',color:AppColors.danger)]),
      subtitle:Text('${s.roleKey(employee.roleKey)} • ${employee.shiftLabel} • ${s.text('الراتب','Salary')}: ${employee.salary>0?'${employee.salary.toStringAsFixed(2)} ${store.settings.currency}':s.text('غير محدد','Not set')} • ${s.text('مهام','Tasks')}: ${tasks.length}',style:const TextStyle(fontSize:8.4,color:AppColors.muted)),
      trailing:Row(mainAxisSize:MainAxisSize.min,children:[StatusPill(label:status,color:color),const SizedBox(width:6),PopupMenuButton<String>(onSelected:onAction,itemBuilder:(_)=>[
        PopupMenuItem(value:'details',child:Text(s.text('عرض الملف','View profile'))),
        PopupMenuItem(value:'task',child:Text(s.text('توكيل مهمة','Assign task'))),
        PopupMenuItem(value:'shift',child:Text(s.text('تعديل الدوام','Edit schedule'))),
        if(canOvertime)PopupMenuItem(value:'overtime',child:Text(s.text('تسجيل دوام إضافي','Record overtime'))),
        PopupMenuItem(value:'leave',child:Text(s.text('تحديد إجازة','Set leave'))),
        PopupMenuItem(value:'rename',child:Text(s.text('تعديل الاسم','Rename'))),
        if(!employee.managementOnly)PopupMenuItem(value:'credentials',child:Text(s.text('بيانات تسجيل الدخول','Login credentials'))),
        PopupMenuItem(value:'payroll',child:Text(s.text('الراتب وموعد القبض','Salary & pay date'))),
        if(!employee.managementOnly || s.controller.role==UserRole.owner)
          PopupMenuItem(value:employee.active?'terminate':'reactivate',child:Text(employee.active?s.text('إنهاء الخدمة','Terminate'):s.text('إعادة التفعيل','Reactivate'))),
        if(s.controller.role==UserRole.owner)
          PopupMenuItem(value:'delete',child:Text(s.text('حذف الموظف','Delete employee'),style:const TextStyle(color:AppColors.danger)))
      ])])
    );
  }
}

class _TimeSetting extends StatelessWidget{const _TimeSetting({required this.label,required this.minutes,required this.onPick});final String label;final int minutes;final VoidCallback onPick;@override Widget build(BuildContext context)=>ListTile(contentPadding:EdgeInsets.zero,title:Text(label,style:const TextStyle(fontSize:9,fontWeight:FontWeight.w800)),subtitle:Text(formatMinutes12(minutes, arabic: true),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900)),trailing:OutlinedButton(onPressed:onPick,child:const Icon(Icons.schedule_rounded,size:17)));}
String _weekday(AppStrings s,int day)=>switch(day){DateTime.monday=>s.text('الاثنين','Monday'),DateTime.tuesday=>s.text('الثلاثاء','Tuesday'),DateTime.wednesday=>s.text('الأربعاء','Wednesday'),DateTime.thursday=>s.text('الخميس','Thursday'),DateTime.friday=>s.text('الجمعة','Friday'),DateTime.saturday=>s.text('السبت','Saturday'),_=>s.text('الأحد','Sunday')};
