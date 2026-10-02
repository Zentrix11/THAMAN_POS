# THAMAN POS V9.1 — 0.28.0+32

- First launch now requires a real THAMAN activation code before any management login is available.
- Valid activation registers the current installation as a device in Supabase and enforces the subscription/device limit server-side.
- After successful activation the real store owner creates name, email, password, password confirmation and a 4-digit management PIN.
- Removed bootstrap/default management credentials from fresh production data.
- Startup heartbeat checks subscription, device unlink/block state and expiry.
- Temporary network failure after a previously valid activation keeps local POS access available; activation itself requires internet.
- Device block state is shown in the subscription center.
- Requires Supabase migration `005_device_activation_blocking_and_deletes.sql`.
