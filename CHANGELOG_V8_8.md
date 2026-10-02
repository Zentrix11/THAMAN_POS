# THAMAN POS V8.8

## Attendance readability
- Late attendance is displayed as readable hours/minutes instead of raw minutes.
- Examples: 600 minutes -> 10 ساعات, 125 minutes -> ساعتين و5 دقائق.
- The same readable format is used in attendance rows, details, and printed attendance statements.

## Inventory purchasing
- Inventory staff now have a dedicated **Purchase stock / شراء بضاعة** action.
- They can purchase an existing product or create a new product with full operational details.
- New-product fields include Arabic/English name, SKU, barcode, Arabic/English category, low-stock threshold, purchase unit, unit conversion, purchase cost, package weight, sale unit, and sale price.
- SKU and barcode uniqueness are validated before saving.
- Purchases flow through the normal purchase receipt, inventory movement, supplier balance, and accounting journal logic.
- Product creation from this flow is restricted to owner, manager, or inventory roles.
