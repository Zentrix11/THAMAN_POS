import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/app_strings.dart';
import '../../core/app_controller.dart';
import '../../data/app_data_store.dart';

Future<List<String>?> showStockCountStartDialog(BuildContext context, AppStrings s) {
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _StockCountStartDialog(s: s),
  );
}

class _StockCountStartDialog extends StatefulWidget {
  const _StockCountStartDialog({required this.s});
  final AppStrings s;

  @override
  State<_StockCountStartDialog> createState() => _StockCountStartDialogState();
}

class _StockCountStartDialogState extends State<_StockCountStartDialog> {
  final search = TextEditingController();
  final selected = <String>{};

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final store = AppDataStore.instance;
    final q = search.text.trim().toLowerCase();
    final products = store.products.where((p) {
      if (!p.active) return false;
      if (q.isEmpty) return true;
      return p.nameAr.toLowerCase().contains(q) ||
          p.nameEn.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q);
    }).toList();
    final allVisible = products.isNotEmpty && products.every((p) => selected.contains(p.id));

    return AlertDialog(
          scrollable: true,
      title: Text(s.text('اختيار أصناف الجرد', 'Choose stock-count items')),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 650.0).toDouble(),
        height: MediaQuery.sizeOf(context).height * .68,
        child: Column(
          children: [
            Text(
              s.text(
                'حدد صنفًا واحدًا أو عدة أصناف بواسطة CHECKBOX. بعد بدء الجرد يمكنك إضافة أصناف أخرى أو أصناف يدوية.',
                'Select one or multiple items with checkboxes. More existing or manual items can be added after the count starts.',
              ),
              style: const TextStyle(fontSize: 10, color: AppColors.muted, height: 1.55),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: s.text('اسم، SKU أو باركود...', 'Name, SKU or barcode...')),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    if (allVisible) {
                      for (final p in products) {
                        selected.remove(p.id);
                      }
                    } else {
                      selected.addAll(products.map((p) => p.id));
                    }
                  }),
                  icon: Icon(allVisible ? Icons.deselect_rounded : Icons.select_all_rounded, size: 17),
                  label: Text(allVisible ? s.text('إلغاء تحديد الظاهر', 'Clear visible') : s.text('تحديد الظاهر', 'Select visible')),
                ),
                const Spacer(),
                Text('${selected.length} ${s.text('صنف محدد', 'selected')}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                child: ListView.separated(
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final p = products[index];
                    return CheckboxListTile(
                      dense: true,
                      value: selected.contains(p.id),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          selected.add(p.id);
                        } else {
                          selected.remove(p.id);
                        }
                      }),
                      title: Text(s.text(p.nameAr, p.nameEn), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                      subtitle: Text(s.controller.role == UserRole.inventory ? p.sku : '${p.sku} • ${s.text('المخزون', 'Stock')}: ${p.stock}', style: const TextStyle(fontSize: 9, color: AppColors.muted)),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إلغاء', 'Cancel'))),
        FilledButton.icon(
          onPressed: selected.isEmpty ? null : () => Navigator.pop(context, selected.toList()),
          icon: const Icon(Icons.fact_check_outlined, size: 17),
          label: Text(s.text('بدء الجرد', 'Start count')),
        ),
      ],
    );
  }
}
