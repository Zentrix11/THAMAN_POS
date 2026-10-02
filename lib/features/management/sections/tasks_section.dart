import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/printing/print_document.dart';
import '../../../core/printing/print_service.dart';
import '../../../data/app_data_store.dart';
import '../../../data/models.dart';
import '../widgets/management_widgets.dart';

class TasksSection extends StatefulWidget{const TasksSection({super.key,required this.s});final AppStrings s;@override State<TasksSection> createState()=>_TasksSectionState();}
class _TasksSectionState extends State<TasksSection>{
  final search=TextEditingController();String filter='all';@override void dispose(){search.dispose();super.dispose();}
  @override Widget build(BuildContext context){final store=AppDataStore.instance;final s=widget.s;return AnimatedBuilder(animation:store,builder:(_,__){final q=search.text.trim().toLowerCase();final data=store.tasks.where((t){if(filter!='all'&&t.status!=filter)return false;final e=store.employeeOrNull(t.assignedEmployeeId);return q.isEmpty||t.titleAr.toLowerCase().contains(q)||t.titleEn.toLowerCase().contains(q)||t.assignedEmployeeId.toLowerCase().contains(q)||(e?.nameAr.toLowerCase().contains(q)??false)||(e?.nameEn.toLowerCase().contains(q)??false)||t.assignedBy.toLowerCase().contains(q);}).toList();final completed=store.tasks.where((t)=>t.done).length;final running=store.tasks.where((t)=>t.status=='in_progress').length;return Column(children:[
    ManagementMetricsGrid(items:[ManagementMetric(s.text('إجمالي المهام','Total tasks'),'${store.tasks.length}',Icons.task_alt_outlined,AppColors.primary),ManagementMetric(s.text('قيد التنفيذ','In progress'),'$running',Icons.play_circle_outline_rounded,AppColors.blue),ManagementMetric(s.text('مكتملة','Completed'),'$completed',Icons.check_circle_outline_rounded,AppColors.success),ManagementMetric(s.text('متأخرة','Overdue'),'${store.overdueTasks.length}',Icons.warning_amber_rounded,AppColors.danger)]),
    const SizedBox(height:12),
    SurfaceCard(padding:EdgeInsets.zero,child:Column(children:[SectionCardHeader(title:s.text('المهام حسب الموظف','Tasks by employee'),subtitle:s.text('الحالة التي يحددها الموظف تظهر هنا فورًا، مع وقت البدء والإنجاز.','Employee status updates appear here immediately with start and completion times.'),trailing:Wrap(spacing:7,runSpacing:7,children:[SizedBox(width:250,child:SearchField(controller:search,hint:s.text('مهمة أو موظف...','Task or employee...'),onChanged:(_)=>setState((){}))),DropdownButton<String>(value:filter,items:[DropdownMenuItem(value:'all',child:Text(s.text('الكل','All'))),DropdownMenuItem(value:'pending',child:Text(s.text('لم تبدأ','Pending'))),DropdownMenuItem(value:'in_progress',child:Text(s.text('قيد التنفيذ','In progress'))),DropdownMenuItem(value:'completed',child:Text(s.text('مكتملة','Completed')))],onChanged:(v)=>setState(()=>filter=v??'all')),OutlinedButton.icon(onPressed:()=>_printTasks(data),icon:const Icon(Icons.print_outlined,size:16),label:Text(s.text('طباعة','Print'))),FilledButton.icon(onPressed:()=>_create(context),icon:const Icon(Icons.add_rounded,size:17),label:Text(s.text('مهمة جديدة','New task')))])),const Divider(height:1),if(data.isEmpty)EmptyPanel(message:s.text('لا توجد مهام مطابقة.','No matching tasks.'))else for(final t in data)...[
      _TaskTile(task:t,s:s,onOpen:()=>_details(context,t),onDelete:()=>_delete(context,t),onNotify:()=>_notifyEmployee(context,t)),if(t!=data.last)const Divider(height:1)
    ]]))
  ]);});}

  Future<void> _printTasks(List<TaskRecord> data) async {
    final store=AppDataStore.instance;final s=widget.s;
    await ThamanPrintService.printDocument(PrintDocument(title:s.text('كشف المهام','Tasks Statement'),subtitle:'${store.settings.storeName} • ${store.settings.branchName}',metadata:{s.text('عدد المهام','Tasks'):'${data.length}',s.text('فلتر البحث','Search filter'):search.text.trim().isEmpty?'-':search.text.trim()},headers:[s.text('المهمة','Task'),s.text('الموظف','Employee'),s.text('الحالة','Status'),s.text('الأولوية','Priority'),s.text('إنشاء','Created'),s.text('استحقاق','Due'),s.text('إنجاز','Completed')],rows:data.map((t){final e=store.employeeOrNull(t.assignedEmployeeId);return[s.text(t.titleAr,t.titleEn),e==null?t.assignedEmployeeId:s.text(e.nameAr,e.nameEn),taskStatusLabel(s,t.status),s.priority(t.priority),formatDateTime(t.createdAt),formatDateTime(t.dueAt),t.completedAt==null?'-':formatDateTime(t.completedAt!)];}).toList(),footer:store.settings.receiptFooter,
      isArabic: widget.s.controller.isArabic,));
  }

  Future<void> _create(BuildContext context) async {final s=widget.s;final store=AppDataStore.instance;final title=TextEditingController();final desc=TextEditingController();String? employeeId=store.activeEmployees.isEmpty?null:store.activeEmployees.first.id;String priority='medium';DateTime due=DateTime.now().add(const Duration(hours:6));await showDialog<void>(context:context,builder:(_)=>StatefulBuilder(builder:(context,setD)=>AlertDialog(
          scrollable: true,title:Text(s.text('إنشاء مهمة للموظف','Create employee task')),content:SizedBox(width:(MediaQuery.sizeOf(context).width - 48).clamp(0.0, 540.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[DropdownMenu<String>(enableFilter:true,enableSearch:true,expandedInsets:EdgeInsets.zero,initialSelection:employeeId,label:Text(s.text('الموظف','Employee')),dropdownMenuEntries:store.activeEmployees.map((e)=>DropdownMenuEntry(value:e.id,label:'${s.text(e.nameAr,e.nameEn)} • ${e.id}')).toList(),onSelected:(v)=>setD(()=>employeeId=v)),const SizedBox(height:10),TextField(controller:title,decoration:InputDecoration(labelText:s.text('عنوان المهمة','Task title'))),const SizedBox(height:10),TextField(controller:desc,maxLines:2,decoration:InputDecoration(labelText:s.text('التفاصيل','Details'))),const SizedBox(height:10),DropdownButtonFormField<String>(value:priority,decoration:InputDecoration(labelText:s.text('الأولوية','Priority')),items:[DropdownMenuItem(value:'low',child:Text(s.text('منخفضة','Low'))),DropdownMenuItem(value:'medium',child:Text(s.text('متوسطة','Medium'))),DropdownMenuItem(value:'high',child:Text(s.text('عالية','High')))],onChanged:(v)=>setD(()=>priority=v??'medium')),const SizedBox(height:8),ListTile(contentPadding:EdgeInsets.zero,title:Text(s.text('موعد الاستحقاق','Due date'),style:const TextStyle(fontSize:9,fontWeight:FontWeight.w800)),subtitle:Text(formatDateTime(due),style:const TextStyle(fontSize:8.5,color:AppColors.muted)),trailing:OutlinedButton(onPressed:()async{final d=await showDatePicker(context:context,firstDate:DateTime.now(),lastDate:DateTime.now().add(const Duration(days:365)),initialDate:due);if(d!=null)setD(()=>due=DateTime(d.year,d.month,d.day,23,59));},child:Text(s.text('تغيير','Change'))))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إلغاء','Cancel'))),FilledButton(onPressed:(){if(employeeId==null||title.text.trim().isEmpty)return;store.createTask(title:title.text.trim(),employeeId:employeeId!,dueAt:due,priority:priority,assignedBy:s.controller.currentUserName,description:desc.text.trim());Navigator.pop(context);},child:Text(s.text('إرسال المهمة','Assign task')))])));title.dispose();desc.dispose();}

  void _details(BuildContext context,TaskRecord t){final s=widget.s;final store=AppDataStore.instance;final e=store.employeeOrNull(t.assignedEmployeeId);showDialog<void>(context:context,builder:(_)=>AlertDialog(
          scrollable: true,title:Row(children:[Expanded(child:Text(s.text(t.titleAr,t.titleEn))),StatusPill(label:taskStatusLabel(s,t.status),color:taskStatusColor(t.status,overdue:t.isOverdue))]),content:SizedBox(width:(MediaQuery.sizeOf(context).width - 48).clamp(0.0, 540.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[DetailLine(label:s.text('الموظف','Employee'),value:'${e==null?t.assignedEmployeeId:s.text(e.nameAr,e.nameEn)} • ${t.assignedEmployeeId}'),DetailLine(label:s.text('كلفه','Assigned by'),value:t.assignedBy),DetailLine(label:s.text('إنشاء','Created'),value:formatDateTime(t.createdAt)),DetailLine(label:s.text('الاستحقاق','Due'),value:formatDateTime(t.dueAt)),DetailLine(label:s.text('الحالة','Status'),value:taskStatusLabel(s,t.status)),if(t.startedAt!=null)DetailLine(label:s.text('بدأ التنفيذ','Started'),value:formatDateTime(t.startedAt!)),if(t.completedAt!=null)DetailLine(label:s.text('أنجزها الموظف','Completed by employee'),value:'${e==null?t.assignedEmployeeId:s.text(e.nameAr,e.nameEn)} • ${formatDateTime(t.completedAt!)}'),if(t.description.isNotEmpty)DetailLine(label:s.text('التفاصيل','Details'),value:t.description)])),actions:[if(t.isOverdue&&!t.done)TextButton.icon(onPressed:(){Navigator.pop(context);_notifyEmployee(context,t);},icon:const Icon(Icons.notifications_active_outlined,size:17),label:Text(s.text('إرسال تنبيه','Send reminder'))),FilledButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إغلاق','Close')))]));}

  void _notifyEmployee(BuildContext context,TaskRecord task){final s=widget.s;final store=AppDataStore.instance;final employee=store.employeeOrNull(task.assignedEmployeeId);if(employee==null){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s.text('لم يتم العثور على الموظف المكلف.','Assigned employee was not found.'))));return;}final role=s.controller.role?.name??'manager';store.sendMessage(senderId:'ADMIN-$role',senderName:s.controller.currentUserName.isEmpty?role:s.controller.currentUserName,senderRole:role,recipientType:'employee',recipientId:employee.id,body:s.text('تنبيه: المهمة المتأخرة «${task.titleAr}» كان موعدها ${formatDateTime(task.dueAt)}. يرجى تحديث حالتها أو إنجازها.','Reminder: overdue task "${task.titleEn}" was due ${formatDateTime(task.dueAt)}. Please update its status or complete it.'));ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s.text('تم إرسال التنبيه إلى ${employee.nameAr}.','Reminder sent to ${employee.nameEn}.'))));}
  Future<void> _delete(BuildContext context,TaskRecord t)async{final s=widget.s;final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(
          scrollable: true,title:Text(s.text('حذف المهمة؟','Delete task?')),content:Text(s.text('سيتم حذف المهمة من حساب الموظف وسجل المهام.','The task will be removed from the employee workspace and task register.')),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:Text(s.text('إلغاء','Cancel'))),FilledButton(onPressed:()=>Navigator.pop(context,true),child:Text(s.text('حذف','Delete')))]));if(ok==true)AppDataStore.instance.deleteTask(t.id);}
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.s, required this.onOpen, required this.onDelete, required this.onNotify});
  final TaskRecord task;
  final AppStrings s;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onNotify;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final e = store.employeeOrNull(task.assignedEmployeeId);
    final tone = taskStatusColor(task.status, overdue: task.isOverdue);
    return ListTile(
      onTap: onOpen,
      leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: tone.withValues(alpha: .09), borderRadius: BorderRadius.circular(13)), child: Icon(task.done ? Icons.check_circle_outline_rounded : task.status == 'in_progress' ? Icons.play_circle_outline_rounded : Icons.task_alt_outlined, color: tone)),
      title: Text(s.text(task.titleAr, task.titleEn), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
      subtitle: Text('${e == null ? task.assignedEmployeeId : s.text(e.nameAr, e.nameEn)} • ${task.assignedEmployeeId} • ${formatDateTime(task.dueAt)}', style: const TextStyle(fontSize: 8.4, color: AppColors.muted)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        StatusPill(label: task.isOverdue && !task.done ? s.text('متأخرة', 'Overdue') : taskStatusLabel(s, task.status), color: tone),
        const SizedBox(width: 6),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'open') onOpen();
            if (v == 'notify') onNotify();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'open', child: Text(s.text('التفاصيل', 'Details'))),
            if (task.isOverdue && !task.done) PopupMenuItem(value: 'notify', child: Text(s.text('إرسال تنبيه للموظف', 'Send employee reminder'))),
            PopupMenuItem(value: 'delete', child: Text(s.text('حذف', 'Delete'))),
          ],
        ),
      ]),
    );
  }
}

