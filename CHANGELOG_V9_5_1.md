# THAMAN POS V9.5.1

- Keeps the StartupGate alive under cashier/staff/management routes so license enforcement continues after login.
- Revalidates the active device every 5 seconds while online.
- Revalidates immediately when the app returns to the foreground.
- If Admin suspends the store/subscription or disconnects/blocks the device, protected workspaces are popped and the POS returns to the license gate within seconds.
- Confirmed activation flow: owner setup occurs only when the business has no cloud owner; later licensed devices go directly to the management/staff access screen after activation.
- Version: 0.32.1+40.
