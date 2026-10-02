# THAMAN POS V8.9 — Premium Printing + Print Preview

## Print preview
- Every native print action now opens a THAMAN in-app preview before continuing to the operating-system print dialog.
- Web keeps an exact browser print-preview page with a dedicated Print button, avoiding popup-blocker regressions.
- Preview is responsive on phone, tablet and desktop and supports wide tables with horizontal scrolling.
- Very large reports preview the first 100 rows for UI safety; the real print still includes every row.

## Printed invoice redesign
- Cleaner THAMAN header hierarchy with logo, document title and store/branch subtitle.
- Metadata is grouped into readable information cards.
- Product/item column receives more width to reduce clipping.
- Grand total is visually highlighted.
- Notes use a separate warm information block.
- Better print page-break behavior and repeated table headers on Web.
- Print colors are preserved in browser printing.

## Sales invoice improvements
- Customer name, account number and phone are included when available.
- Invoice status is shown as paid / partially paid / due / voided.
- Totals distinguish paid-at-sale, due-at-sale, and the current invoice balance after later payments or returns.
- Currency is shown in monetary column headers.

## Purchase invoice improvements
- Supplier account number and phone are included when available.
- Current outstanding purchase balance is shown after later supplier payments.
- Currency is shown in monetary column headers.

## Platform coverage
The shared print service applies the flow to Windows, Android, iOS and macOS. Web uses its dedicated HTML preview path while retaining the same THAMAN visual system.
