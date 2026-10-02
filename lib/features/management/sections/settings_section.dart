import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../core/app_controller.dart';
import '../../../core/app_strings.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../data/app_data_store.dart';
import '../../../core/subscription/subscription_repository.dart';
import '../widgets/management_widgets.dart';

class SettingsSection extends StatefulWidget {
  const SettingsSection({super.key, required this.s});
  final AppStrings s;
  @override State<SettingsSection> createState()=>_SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection>{
  late final TextEditingController storeName,currency,branch,tax,footer;
  @override void initState(){super.initState();final x=AppDataStore.instance.settings;storeName=TextEditingController(text:x.storeName);currency=TextEditingController(text:x.currency);branch=TextEditingController(text:x.branchName);tax=TextEditingController(text:'${x.taxPercent}');footer=TextEditingController(text:x.receiptFooter);}
  @override void dispose(){for(final c in [storeName,currency,branch,tax,footer]){c.dispose();}super.dispose();}
  @override Widget build(BuildContext context){final store=AppDataStore.instance, s=widget.s;return AnimatedBuilder(animation:store,builder:(_,__){final x=store.settings;return Column(children:[
    ManagementMetricsGrid(items:[ManagementMetric(s.text('المتجر','Store'),x.storeName,Icons.storefront_outlined,AppColors.primary),ManagementMetric(s.text('الفرع','Branch'),x.branchName,Icons.account_tree_outlined,AppColors.blue),ManagementMetric(s.text('الضريبة','Tax'),'${x.taxPercent.toStringAsFixed(2)}%',Icons.percent_rounded,AppColors.accent)]),
    const SizedBox(height:12),
    SurfaceCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(s.text('بيانات المتجر','Store information'),style:const TextStyle(fontSize:12,fontWeight:FontWeight.w900)),const SizedBox(height:14),LayoutBuilder(builder:(context,c)=>Wrap(spacing:10,runSpacing:10,children:[_field(storeName,s.text('اسم المتجر','Store name'),c.maxWidth),_field(branch,s.text('اسم الفرع','Branch name'),c.maxWidth),_field(currency,s.text('العملة','Currency'),c.maxWidth),_field(tax,s.text('نسبة الضريبة %','Tax %'),c.maxWidth,number:true)])),const SizedBox(height:10),TextField(controller:footer,maxLines:2,decoration:InputDecoration(labelText:s.text('تذييل الفاتورة','Receipt footer'))),const SizedBox(height:14),Align(alignment:AlignmentDirectional.centerEnd,child:FilledButton.icon(onPressed:()=>_save(context),icon:const Icon(Icons.save_outlined,size:18),label:Text(s.text('حفظ الإعدادات','Save settings'))))])),
    const SizedBox(height:12),
    SurfaceCard(padding:EdgeInsets.zero,child:Column(children:[SectionCardHeader(title:s.text('إعدادات التشغيل','Operational settings'),subtitle:s.text('هذه الخيارات محفوظة وتؤثر على سلوك النظام.','These options are persisted and affect system behavior.')),const Divider(height:1),SwitchListTile(value:x.allowCashierReturns,onChanged:(v)=>store.updateSettings(allowCashierReturns:v),title:Text(s.text('السماح للكاشير بالمرتجعات','Allow cashier returns'),style:const TextStyle(fontSize:9.5,fontWeight:FontWeight.w800))),SwitchListTile(value:x.requireClockOutConfirmation,onChanged:(v)=>store.updateSettings(requireClockOutConfirmation:v),title:Text(s.text('تأكيد تسجيل الانصراف','Confirm clock-out'),style:const TextStyle(fontSize:9.5,fontWeight:FontWeight.w800))),SwitchListTile(value:x.lowStockNotifications,onChanged:(v)=>store.updateSettings(lowStockNotifications:v),title:Text(s.text('إشعارات انخفاض المخزون','Low-stock notifications'),style:const TextStyle(fontSize:9.5,fontWeight:FontWeight.w800))),SwitchListTile(value:x.taskNotifications,onChanged:(v)=>store.updateSettings(taskNotifications:v),title:Text(s.text('إشعارات المهام','Task notifications'),style:const TextStyle(fontSize:9.5,fontWeight:FontWeight.w800)))])),
    if(s.controller.role==UserRole.owner) ...[
      const SizedBox(height:12),
      SurfaceCard(padding:EdgeInsets.zero,child:Column(children:[
        SectionCardHeader(title:s.text('أمان حسابات الإدارة','Management account security'),subtitle:s.text('المالك فقط يستطيع إنشاء أو تغيير بيانات دخول حسابات الإدارة.','Only the owner can create or change management account credentials.'),trailing:PopupMenuButton<String>(tooltip:s.text('بيانات دخول الإدارة','Management credentials'),icon:const Icon(Icons.admin_panel_settings_outlined),onSelected:(role)=>_editAdminCredentials(context,role),itemBuilder:(_)=>[PopupMenuItem(value:'owner',child:Text(s.text('بيانات المالك','Owner credentials'))),PopupMenuItem(value:'manager',child:Text(s.text('بيانات المدير','Manager credentials'))),PopupMenuItem(value:'accountant',child:Text(s.text('بيانات المحاسب','Accountant credentials')))])),
        const Divider(height:1),
        ListTile(leading:const Icon(Icons.verified_user_outlined,color:AppColors.primary),title:Text(s.text('صلاحية محمية للمالك','Owner-protected permission'),style:const TextStyle(fontSize:9.8,fontWeight:FontWeight.w900)),subtitle:Text(s.text('المدير يستطيع تغيير بيانات دخول الموظفين فقط، ولا يستطيع تعديل حسابات الإدارة.','The manager can change staff credentials only and cannot edit management accounts.'),style:const TextStyle(fontSize:8.4,color:AppColors.muted)),trailing:OutlinedButton.icon(onPressed:()=>_showAuditLog(context),icon:const Icon(Icons.history_rounded,size:16),label:Text(s.text('سجل الأمان','Security log')))),
      ])),
      const SizedBox(height:12),
      SurfaceCard(child:Row(children:[
        Container(width:42,height:42,decoration:BoxDecoration(color:AppColors.danger.withValues(alpha: .08),borderRadius:BorderRadius.circular(12)),child:const Icon(Icons.account_balance_wallet_outlined,color:AppColors.danger)),
        const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(s.text('إعادة الحسابات إلى صفر','Reset financial accounts to zero'),style:const TextStyle(fontSize:10.5,fontWeight:FontWeight.w900)),
          Text(s.text('يبدأ فترة مالية جديدة بصفر مع إبقاء الفواتير والمخزون والأصول والسجل القديم محفوظاً. يتطلب كلمة مرور المالك للتأكيد.','Starts a new zero-balance financial period while keeping invoices, inventory, assets and historical records. Owner password is required.'),style:const TextStyle(fontSize:8.5,color:AppColors.muted)),
        ])),
        const SizedBox(width:10),
        OutlinedButton.icon(onPressed:()=>_resetFinancialAccounts(context),icon:const Icon(Icons.restart_alt_rounded,size:16),label:Text(s.text('تصفير الحسابات','Reset accounts'))),
      ])),
    ],
    if(s.controller.role==UserRole.owner) ...[
      const SizedBox(height:12),
      SurfaceCard(child:Row(children:[Container(width:42,height:42,decoration:BoxDecoration(color:AppColors.danger.withValues(alpha: .08),borderRadius:BorderRadius.circular(12)),child:const Icon(Icons.restart_alt_rounded,color:AppColors.danger)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(s.text('مسح بيانات العمل','Clear business data'),style:const TextStyle(fontSize:10.5,fontWeight:FontWeight.w900)),Text(s.text('يحذف المنتجات والفواتير والعملاء والموردين والموظفين والحركات ويعيد التطبيق لحالة عمل فارغة مع إبقاء حسابات دخول الإدارة. هذا الخيار للمالك فقط.','Deletes products, invoices, customers, suppliers, employees and transactions, returning the app to a clean business state while keeping management access accounts. Owner only.'),style:const TextStyle(fontSize:8.5,color:AppColors.muted))])),OutlinedButton(onPressed:()=>_reset(context),child:Text(s.text('إعادة ضبط','Reset')))])),
    ],
  ]);});}
  Future<void> _editAdminCredentials(BuildContext context, String role) async {
    final s=widget.s; final store=AppDataStore.instance;
    if(role=='owner'){
      final owner=store.adminAccountByRole('owner');
      await showDialog<void>(context:context,builder:(_)=>AlertDialog(
        scrollable:true,
        title:Text(s.text('حساب المالك السحابي','Cloud owner account')),
        content:SizedBox(width:(MediaQuery.sizeOf(context).width-48).clamp(0.0,500.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(s.text('حساب المالك مرتبط بالمشترك على Supabase ويعمل على جميع الأجهزة المفعّلة. حفاظًا على تطابق الأجهزة، لا يتم تعديل كلمة المرور محليًا من هذه الشاشة.','The owner account is linked to the subscriber in Supabase and works across all activated devices. To keep devices synchronized, its password is not edited locally from this screen.'),style:const TextStyle(fontSize:9.2,color:AppColors.muted,height:1.55)),
          const SizedBox(height:12),
          if(owner!=null)...[
            Text('${s.text('الاسم','Name')}: ${owner.nameAr}',style:const TextStyle(fontWeight:FontWeight.w800)),
            const SizedBox(height:6),
            Text('${s.text('البريد','Email')}: ${owner.email}',style:const TextStyle(fontWeight:FontWeight.w800)),
          ],
          const SizedBox(height:12),
          Text(s.text('إذا نسيت كلمة المرور استخدم «نسيت كلمة المرور؟» من شاشة الدخول. إذا كان بريد المالك مسجلًا يمكنك طلب رابط استعادة آمن، أو مراسلة دعم THAMAN عند الحاجة.','If you forget the password, use “Forgot password?” on the sign-in screen. A registered owner email can receive a secure reset link, or you can contact THAMAN support if needed.'),style:const TextStyle(fontSize:9.2,fontWeight:FontWeight.w800)),
        ])),
        actions:[FilledButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('حسنًا','OK')))]
      ));
      return;
    }
    final account=store.adminAccountByRole(role);
    final displayName=TextEditingController(text:account?.nameAr ?? ''), email=TextEditingController(text:account?.email ?? ''), password=TextEditingController(), pin=TextEditingController();
    String? error;
    final roleAr=switch(role){'owner'=>'المالك','accountant'=>'المحاسب',_=>'المدير'};
    final roleEn=switch(role){'owner'=>'Owner','accountant'=>'Accountant',_=>'Manager'};
    await showDialog<void>(context:context,builder:(_)=>StatefulBuilder(builder:(context,setD)=>AlertDialog(
      scrollable:true,
      title:Text(s.text('تعديل بيانات دخول $roleAr','Edit $roleEn credentials')),
      content:SizedBox(width:(MediaQuery.sizeOf(context).width-48).clamp(0.0,500.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,children:[
        if(error!=null)Container(width:double.infinity,margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:AppColors.danger.withValues(alpha: .08),borderRadius:BorderRadius.circular(10)),child:Text(error!,style:const TextStyle(fontSize:8.7,color:AppColors.danger,fontWeight:FontWeight.w800))),
        TextField(controller:displayName,textCapitalization:TextCapitalization.words,decoration:InputDecoration(labelText:s.text('اسم المستخدم','User name'),hintText:s.text('مثال: عمر','Example: Omar'),prefixIcon:const Icon(Icons.person_outline_rounded))),const SizedBox(height:10),
        TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:InputDecoration(labelText:s.text('البريد الإلكتروني','Email'))),const SizedBox(height:10),
        TextField(controller:password,obscureText:true,decoration:InputDecoration(labelText:s.text(account==null?'كلمة المرور *':'كلمة مرور جديدة (اتركها فارغة للإبقاء عليها)',account==null?'Password *':'New password (leave blank to keep current)'))),const SizedBox(height:10),
        TextField(controller:pin,obscureText:true,keyboardType:TextInputType.number,maxLength:4,decoration:InputDecoration(labelText:s.text(account==null?'رمز الإدارة PIN (4 أرقام) *':'رمز إدارة جديد (اتركه فارغاً للإبقاء عليه)',account==null?'Management PIN (4 digits) *':'New management PIN (leave blank to keep current)'))),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إلغاء','Cancel'))),FilledButton(onPressed:(){
        final ok=store.updateAdminCredentials(targetRole:role,displayName:displayName.text,email:email.text,password:password.text,pin:pin.text,actorName:s.controller.currentUserName,actorRole:'owner');
        if(!ok){setD(()=>error=s.text('تعذر الحفظ. أدخل اسم المستخدم وتحقق من البريد، وأن كلمة المرور الجديدة 8 أحرف على الأقل والرمز 4 أرقام.','Could not save. Enter the user name and check the email; a new password must be at least 8 characters and PIN must be 4 digits.'));return;}
        Navigator.pop(context);
        ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content:Text(s.text('تم تحديث بيانات دخول $roleAr.','$roleEn credentials updated.'))));
      },child:Text(s.text('حفظ','Save')))]
    )));
    displayName.dispose();email.dispose();password.dispose();pin.dispose();
  }

  Future<void> _showAuditLog(BuildContext context) async {
    final s=widget.s; final store=AppDataStore.instance;
    await showDialog<void>(context:context,builder:(_)=>AlertDialog(
          scrollable: true,
      title:Text(s.text('سجل الأمان والتغييرات','Security & change log')),
      content:SizedBox(width:(MediaQuery.sizeOf(context).width - 48).clamp(0.0, 700.0).toDouble(),height:430,child:AnimatedBuilder(animation:store,builder:(_,__){
        final logs=store.auditLogs.take(100).toList();
        if(logs.isEmpty)return Center(child:Text(s.text('لا توجد تغييرات أمنية مسجلة بعد.','No security changes recorded yet.'),style:const TextStyle(fontSize:9,color:AppColors.muted)));
        return ListView.separated(itemCount:logs.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(_,i){final log=logs[i];return ListTile(leading:const Icon(Icons.shield_outlined,color:AppColors.primary),title:Text('${log.actorName} • ${log.targetId}',style:const TextStyle(fontSize:9.4,fontWeight:FontWeight.w900)),subtitle:Text('${log.action} • ${log.createdAt.toLocal()}\n${log.description}',style:const TextStyle(fontSize:8.1,color:AppColors.muted)));});
      })),
      actions:[FilledButton(onPressed:()=>Navigator.pop(context),child:Text(s.text('إغلاق','Close')))]
    ));
  }

  Future<void> _resetFinancialAccounts(BuildContext context) async {
    final s=widget.s;
    final password=TextEditingController();
    String? error;
    final confirmed=await showDialog<bool>(context:context,builder:(_)=>StatefulBuilder(builder:(context,setD)=>AlertDialog(
      scrollable:true,
      title:Text(s.text('تصفير الحسابات المالية','Reset financial accounts')),
      content:SizedBox(width:(MediaQuery.sizeOf(context).width-48).clamp(0.0,520.0).toDouble(),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Container(width:double.infinity,padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:AppColors.danger.withValues(alpha: .08),borderRadius:BorderRadius.circular(12)),child:Text(s.text('سيتم جعل أرصدة العملاء والموردين والحسابات والمدفوعات والملخص المالي تبدأ من صفر. السجلات السابقة لن تُحذف وستبقى محفوظة للرجوع إليها.','Customer, supplier, account, payment and financial-summary balances will restart from zero. Previous records will not be deleted and remain available for reference.'),style:const TextStyle(fontSize:8.8,fontWeight:FontWeight.w800,color:AppColors.danger))),
        const SizedBox(height:12),
        Text(s.text('أدخل كلمة مرور المالك للتأكيد','Enter the owner password to confirm'),style:const TextStyle(fontSize:9,fontWeight:FontWeight.w900)),
        const SizedBox(height:8),
        TextField(controller:password,obscureText:true,autofocus:true,onSubmitted:(_)=>setD(()=>error=null),decoration:InputDecoration(labelText:s.text('كلمة مرور المالك','Owner password'),errorText:error)),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(context,false),child:Text(s.text('إلغاء','Cancel'))),
        FilledButton(onPressed:() async {
          final store=AppDataStore.instance;
          var verified=store.verifyOwnerPassword(password.text);
          if(!verified){
            final owner=store.adminAccountByRole('owner');
            if(owner!=null && owner.email.trim().isNotEmpty && owner.pin.trim().isNotEmpty){
              try{
                await SubscriptionRepository().ownerLogin(email:owner.email,password:password.text,pin:owner.pin);
                await store.updateCachedOwnerPassword(owner.email,password.text);
                verified=true;
              }catch(_){verified=false;}
            }
          }
          if(!verified){setD(()=>error=s.text('كلمة مرور المالك غير صحيحة.','Incorrect owner password.'));return;}
          if(context.mounted) Navigator.pop(context,true);
        },child:Text(s.text('تأكيد التصفير','Confirm reset'))),
      ],
    )));
    if(confirmed==true&&context.mounted){
      final ok=AppDataStore.instance.resetFinancialAccounts(actorName:s.controller.currentUserName,actorRole:'owner',ownerPassword:password.text,alreadyVerified:true);
      if(context.mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(ok?s.text('تم تصفير الحسابات وبدء فترة مالية جديدة من الصفر.','Financial accounts were reset and a new zero-balance period has started.'):s.text('تعذر تصفير الحسابات. تحقق من صلاحية المالك وكلمة مروره.','Could not reset financial accounts. Check owner permission and password.'))));}
    }
    password.dispose();
  }

  Widget _field(TextEditingController c,String label,double width,{bool number=false})=>SizedBox(width:width<700?width:(width-10)/2,child:TextField(controller:c,keyboardType:number?const TextInputType.numberWithOptions(decimal:true):null,decoration:InputDecoration(labelText:label)));
  void _save(BuildContext context){AppDataStore.instance.updateSettings(storeName:storeName.text.trim(),branchName:branch.text.trim(),currency:currency.text.trim(),taxPercent:double.tryParse(tax.text.trim())??0,receiptFooter:footer.text.trim());ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(widget.s.text('تم حفظ الإعدادات.','Settings saved.'))));}
  Future<void> _reset(BuildContext context) async {
    final s = widget.s;
    final password = TextEditingController();
    String? error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          scrollable: true,
          title: Text(s.text('مسح كل بيانات العمل؟', 'Clear all business data?')),
          content: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 520.0).toDouble(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.text('سيتم حذف كل بيانات العمل المحلية الحالية نهائياً: المنتجات والفواتير والعملاء والموردين والموظفين والحركات والمصاريف والأصول. ستبقى حسابات دخول الإدارة فقط.', 'All current local business data will be permanently removed: products, invoices, customers, suppliers, employees, movements, expenses and assets. Only management access accounts will remain.')),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: s.text('كلمة مرور المالك', 'Owner password'),
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () async {
                final store = AppDataStore.instance;
                var verified = store.verifyOwnerPassword(password.text);
                if (!verified) {
                  final owner = store.adminAccountByRole('owner');
                  if (owner != null && owner.email.trim().isNotEmpty && owner.pin.trim().isNotEmpty) {
                    try {
                      await SubscriptionRepository().ownerLogin(email: owner.email, password: password.text, pin: owner.pin);
                      await store.updateCachedOwnerPassword(owner.email, password.text);
                      verified = true;
                    } catch (_) {
                      verified = false;
                    }
                  }
                }
                if (!verified) {
                  setD(() => error = s.text('كلمة مرور المالك غير صحيحة.', 'Incorrect owner password.'));
                  return;
                }
                if (context.mounted) Navigator.pop(context, true);
              },
              child: Text(s.text('تأكيد', 'Confirm')),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && context.mounted) {
      final ok = await AppDataStore.instance.resetBusinessData(
        actorRole: 'owner',
        ownerPassword: password.text,
        alreadyVerified: true,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? s.text('تم مسح بيانات العمل وأصبح التطبيق فارغاً.', 'Business data cleared. The app is now empty.')
              : s.text('تعذر مسح البيانات. تحقق من كلمة مرور المالك.', 'Could not clear data. Check the owner password.')),
        ));
      }
    }
    password.dispose();
  }
}
