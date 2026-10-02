# THAMAN POS V9.1.1 — License recovery & support contact

- When an existing subscription is deleted, suspended, expired, pending, or the device is blocked/unlinked, startup now returns to the activation-code screen instead of leaving the customer on a dead-end license screen.
- A definitive online denial clears only the stored activation binding and last validation timestamp; local POS data, device identity, and the existing owner account are preserved.
- Re-activation after a license reset no longer asks an existing shop owner to recreate credentials.
- Activation errors that require THAMAN administration now display support contact: `albhytytymr6@gmail.com`.
- While POS is open, the license/device state is revalidated every 5 minutes; a confirmed suspension/deletion/block sends the app back to activation without requiring a restart.
- Activation rejection messages were clarified for deleted/cancelled subscriptions and blocked/unlinked devices.
- Version bumped to 0.28.1+33.
