# THAMAN POS V8.4

## New
- Owner-only **Reset financial accounts to zero** action in Settings.
- Reset requires the current manager password as a second confirmation factor.
- Reset starts a new financial period from zero for customer/supplier balances, cash/bank journals, payment totals, expenses, and financial summaries.
- Historical invoices, purchases, stock movements, products, assets, and audit history are retained.
- The reset event is written to the security audit log without storing the manager password.
- Supplier/customer payment allocation after a reset is restricted to transactions from the new financial period.
- Asset register printing with full details, totals, depreciation and book value.
- Single-asset printing from the asset details dialog.

## Version
- App version: `0.21.0+22`
