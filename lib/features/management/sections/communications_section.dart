import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/printing/print_document.dart';
import '../../../core/printing/print_service.dart';
import '../../../data/app_data_store.dart';
import '../../../data/models.dart';
import '../widgets/management_widgets.dart';

class CommunicationsSection extends StatefulWidget {
  const CommunicationsSection({super.key, required this.s});
  final AppStrings s;

  @override
  State<CommunicationsSection> createState() => _CommunicationsSectionState();
}

class _CommunicationsSectionState extends State<CommunicationsSection> {
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
    final role = s.controller.role?.name ?? 'manager';
    final readerId = 'ADMIN-$role';
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final q = search.text.trim().toLowerCase();
        final rows = store.messagesForManagement(role, readerId: readerId).where((m) {
          if (q.isEmpty) return true;
          return m.body.toLowerCase().contains(q) ||
              m.senderName.toLowerCase().contains(q) ||
              m.recipientType.toLowerCase().contains(q);
        }).toList();
        return Column(
          children: [
            ManagementMetricsGrid(items: [
              ManagementMetric(s.text('كل الرسائل', 'All messages'), '${rows.length}', Icons.forum_outlined, AppColors.primary),
              ManagementMetric(s.text('غير مقروءة', 'Unread'), '${store.unreadManagementMessages(role, readerId)}', Icons.mark_email_unread_outlined, AppColors.accent),
              ManagementMetric(s.text('إلى كل الموظفين', 'Broadcasts'), '${store.messages.where((m) => m.recipientType == 'all_staff').length}', Icons.campaign_outlined, AppColors.blue),
              ManagementMetric(s.text('من المخزون', 'From inventory'), '${store.messages.where((m) => m.senderRole == 'inventory').length}', Icons.warehouse_outlined, AppColors.success),
            ]),
            const SizedBox(height: 12),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                SectionCardHeader(
                  title: s.text('الرسائل الداخلية', 'Internal messages'),
                  subtitle: s.text('تواصل الإدارة مع الموظفين، وردود مسؤول المخزون تظهر هنا مباشرة.', 'Management broadcasts and inventory replies appear here immediately.'),
                  trailing: Wrap(spacing: 8, runSpacing: 8, children: [
                    SearchField(controller: search, hint: s.text('بحث في الرسائل...', 'Search messages...'), onChanged: (_) => setState(() {}), width: 240),
                    OutlinedButton.icon(onPressed:()=>_printMessages(rows),icon:const Icon(Icons.print_outlined,size:16),label:Text(s.text('طباعة','Print'))),
                    FilledButton.icon(onPressed: () => _compose(context), icon: const Icon(Icons.edit_outlined, size: 17), label: Text(s.text('رسالة جديدة', 'New message'))),
                  ]),
                ),
                const Divider(height: 1),
                if (rows.isEmpty)
                  EmptyPanel(message: s.text('لا توجد رسائل مطابقة.', 'No matching messages.'), icon: Icons.forum_outlined)
                else
                  for (final m in rows) ...[
                    _MessageTile(
                      s: s,
                      message: m,
                      readerId: readerId,
                      onOpen: () => _openMessage(context, m, readerId),
                      onMarkUnread: () => store.markMessageUnread(m.id, readerId),
                      onDelete: () => store.hideMessageForReader(m.id, readerId),
                    ),
                    if (m != rows.last) const Divider(height: 1),
                  ],
              ]),
            ),
          ],
        );
      },
    );
  }


  Future<void> _printMessages(List<MessageRecord> rows) async {
    final store=AppDataStore.instance; final s=widget.s;
    await ThamanPrintService.printDocument(PrintDocument(
      title:s.text('سجل الرسائل الداخلية','Internal Messages Log'),
      subtitle:'${store.settings.storeName} • ${store.settings.branchName}',
      metadata:{s.text('عدد الرسائل','Messages'):'${rows.length}',s.text('فلتر البحث','Search filter'):search.text.trim().isEmpty?'-':search.text.trim()},
      headers:[s.text('التاريخ','Date'),s.text('المرسل','Sender'),s.text('الدور','Role'),s.text('الوجهة','Recipient'),s.text('الرسالة','Message')],
      rows:rows.map((m)=>[formatDateTime(m.createdAt),m.senderName,m.senderRole,_recipientLabel(s,m,store),m.body]).toList(),
      footer:store.settings.receiptFooter,
    
      isArabic: widget.s.controller.isArabic,));
  }

  Future<void> _compose(BuildContext context, {MessageRecord? replyTo}) async {
    final s = widget.s;
    final store = AppDataStore.instance;
    final body = TextEditingController();
    String target = replyTo != null && replyTo.senderRole == 'inventory' ? 'inventory' : 'all_staff';
    String employeeId = store.activeEmployees.isEmpty ? '' : store.activeEmployees.first.id;
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          scrollable: true,
          title: Text(replyTo == null ? s.text('إرسال رسالة', 'Send message') : s.text('رد على الرسالة', 'Reply to message')),
          content: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 560.0).toDouble(),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: target,
                decoration: InputDecoration(labelText: s.text('المستلم', 'Recipient')),
                items: [
                  DropdownMenuItem(value: 'all_staff', child: Text(s.text('كل الموظفين', 'All employees'))),
                  DropdownMenuItem(value: 'inventory', child: Text(s.text('مسؤول/موظفو المخزون', 'Inventory team'))),
                  DropdownMenuItem(value: 'employee', child: Text(s.text('موظف محدد', 'Specific employee'))),
                ],
                onChanged: (v) => setD(() => target = v ?? target),
              ),
              if (target == 'employee') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: employeeId.isEmpty ? null : employeeId,
                  decoration: InputDecoration(labelText: s.text('الموظف', 'Employee')),
                  items: store.activeEmployees.map((e) => DropdownMenuItem(value: e.id, child: Text('${s.text(e.nameAr, e.nameEn)} • ${e.id}'))).toList(),
                  onChanged: (v) => setD(() => employeeId = v ?? employeeId),
                ),
              ],
              const SizedBox(height: 10),
              TextField(controller: body, minLines: 3, maxLines: 6, decoration: InputDecoration(labelText: s.text('نص الرسالة', 'Message'))),
            ]),
          ),
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
                  recipientType: target,
                  recipientId: target == 'employee' ? employeeId : '',
                  replyToId: replyTo?.id ?? '',
                  body: body.text.trim(),
                );
                Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.send_rounded, size: 17),
              label: Text(s.text('إرسال', 'Send')),
            ),
          ],
        ),
      ),
    );
    body.dispose();
  }

  Future<void> _openMessage(BuildContext context, MessageRecord message, String readerId) async {
    final s = widget.s;
    final store = AppDataStore.instance;
    store.markMessageRead(message.id, readerId);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
          scrollable: true,
        title: Text(message.senderName),
        content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 520.0).toDouble(), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message.body, style: const TextStyle(fontSize: 12, height: 1.7, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          DetailLine(label: s.text('المرسل', 'Sender'), value: '${message.senderName} • ${message.senderRole}'),
          DetailLine(label: s.text('الوقت', 'Time'), value: formatDateTime(message.createdAt)),
          DetailLine(label: s.text('الوجهة', 'Recipient'), value: _recipientLabel(s, message, store)),
        ])),
        actions: [
          TextButton.icon(
            onPressed: () {
              store.hideMessageForReader(message.id, readerId);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 17),
            label: Text(s.text('حذف', 'Delete')),
          ),
          TextButton.icon(
            onPressed: () {
              store.markMessageUnread(message.id, readerId);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.mark_email_unread_outlined, size: 17),
            label: Text(s.text('تحديد كغير مقروء', 'Mark unread')),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إغلاق', 'Close'))),
          FilledButton.icon(onPressed: () { Navigator.pop(context); _compose(context, replyTo: message); }, icon: const Icon(Icons.reply_rounded, size: 17), label: Text(s.text('رد', 'Reply'))),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.s,
    required this.message,
    required this.readerId,
    required this.onOpen,
    required this.onMarkUnread,
    required this.onDelete,
  });
  final AppStrings s;
  final MessageRecord message;
  final String readerId;
  final VoidCallback onOpen;
  final VoidCallback onMarkUnread;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final unread = !message.readBy.contains(readerId) && message.senderId != readerId;
    return ListTile(
      onTap: onOpen,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: unread ? AppColors.accentSoft : AppColors.surfaceAlt, borderRadius: BorderRadius.circular(13)),
        child: Icon(unread ? Icons.mark_email_unread_outlined : Icons.mail_outline_rounded, color: unread ? AppColors.accent : AppColors.primary, size: 19),
      ),
      title: Row(children: [
        Expanded(child: Text(message.senderName, style: TextStyle(fontSize: 10.5, fontWeight: unread ? FontWeight.w900 : FontWeight.w800))),
        Text(formatDateTime(message.createdAt), style: const TextStyle(fontSize: 7.8, color: AppColors.muted)),
      ]),
      subtitle: Text(message.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8.8, height: 1.5, color: AppColors.muted)),
      trailing: PopupMenuButton<String>(
        tooltip: s.text('خيارات الرسالة', 'Message options'),
        onSelected: (value) {
          if (value == 'open') onOpen();
          if (value == 'unread') onMarkUnread();
          if (value == 'delete') onDelete();
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'open', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.open_in_new_rounded, size: 17), title: Text(s.text('فتح', 'Open')))),
          PopupMenuItem(value: 'unread', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.mark_email_unread_outlined, size: 17), title: Text(s.text('تحديد كغير مقروء', 'Mark unread')))),
          PopupMenuItem(value: 'delete', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.delete_outline_rounded, size: 17), title: Text(s.text('حذف', 'Delete')))),
        ],
      ),
    );
  }
}

String _recipientLabel(AppStrings s, MessageRecord message, AppDataStore store) {
  return switch (message.recipientType) {
    'all_staff' => s.text('كل الموظفين', 'All employees'),
    'inventory' => s.text('فريق المخزون', 'Inventory team'),
    'management' => s.text('المالك والمدير', 'Owner & manager'),
    'employee' => store.employeeOrNull(message.recipientId) == null ? message.recipientId : s.text(store.employeeOrNull(message.recipientId)!.nameAr, store.employeeOrNull(message.recipientId)!.nameEn),
    _ => message.recipientType,
  };
}
