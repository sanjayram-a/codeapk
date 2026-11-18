# Lifetime Pro paywall — design

Date: 2026-11-13
Status: draft for approval

## Intent

OpenCode Pocket is free to download and use, with a one-time **lifetime Pro** unlock. Free users keep the core app: chat, files, the editor, build tools, cache clearing and a 5-minute background run. Four capabilities are Pro:

- the terminal;
- Save to Downloads / export;
- the per-project size breakdown;
- background runs longer than 5 minutes.

Every gate opens the same paywall screen. Settings always shows the current plan and a way to unlock Pro. There is **no free trial**. There is **no subscription**. The launch price is a **founder price**; Play Console holds the real price and the app displays it.

## Goals

- One Play product: `pro_lifetime`, one-time, non-consumable.
- One paywall screen, opened from every gate with a reason-specific line.
- Settings shows Free/Pro plan details, the founder price and an unlock button.
- Buy, acknowledge, restore and refund/revocation checks work without a backend.
- Never hide or delete user data when a gate closes; only block the gated action.
- Never hardcode the charged price; display Play's localized `ProductDetails.price`.
- Keep the founder price visible in the launch build.

## Non-goals

- No trial, subscription, ads, accounts or RevenueCat.
- No server-side receipt validation. The app is local-only.
- No anti-piracy/DRM. A local entitlement boolean can be patched; accepted.
- No project, session or file-count limits; they are not enforceable.
- No new export/share sheet. “Export” means the existing Save to Downloads paths.
- No native enforcement of terminal/downloads; the gate is UI-level.

## Anti-goals

- A fake strikethrough or a countdown that is not backed by a real Play price change.
- A paywall on launch or a full-screen block of the app.
- Revoking Pro because the Play query failed once.
- Deleting or hiding existing files or sessions when a plan changes.

## Approaches considered

### Billing

1. **Official `in_app_purchase` ^3.3.1 — chosen.** Its Android implementation now uses Play Billing 9.1.0 and exposes `queryPastPurchases`, `completePurchase`, `restorePurchases` and offer details. First-party, least code, no third-party plugin.
2. **`flutter_inapp_purchase` 8.x.** More offer metadata and offer tokens, but a third-party dependency. Rejected for v1: a plain founder price does not need offer tokens.
3. **Custom Kotlin Play Billing 9 bridge.** Most control, most code and device testing. Rejected: the official plugin now covers this flow.

### Paywall presentation

1. **Full-screen route — chosen.** Matches the supplied reference, has room for the comparison table, price card and error/pending states, and is consistent from every gate.
2. **Modal bottom sheet.** Less intrusive, but cramped for a feature table and price card, and harder to show restore/pending states.

### Gate enforcement

1. **Central UI gate — chosen.** `ProController` plus `showPaywall(...)`; simple, testable, and enough for a local app.
2. **Native enforcement.** Bypassable without a server, and would touch the runtime/agent. Rejected.

## Decisions

- Product ID: `pro_lifetime`, one-time non-consumable.
- Price: configured in Play Console. Launch founder price **₹999**; scheduled change to **₹1,499** after the founder window. The app shows Play's price; the founder badge is copy, not a hardcoded charge.
- No trial. `isPro = owned`.
- Billing: official `in_app_purchase` ^3.3.1 (Android: Play Billing 9.1.0).
- Entitlement: local `pro_owned` flag plus `pro_last_verified_at` in SharedPreferences. Refreshed on launch, resume, paywall open and Settings.
- Offline grace: 7 days. A successful query with no purchase revokes immediately; a failed query keeps cached Pro for up to 7 days.
- Acknowledge immediately on `pendingCompletePurchase`; retry on the next launch if acknowledgement fails.
- Pending purchases do not grant Pro.
- Restore purchases is available in the paywall and Settings.
- No server/RTDN: a refund is detected on the next successful query (launch, resume, paywall or Settings).

## Gates

| Feature | Free | Pro | Where |
|---|---|---|---|
| Background run (idle) | 5 min fixed | 5 / 15 / 30 / 60 min | Settings idle timeout; `HomeShell` init |
| Terminal | locked tab → paywall | normal terminal | `HomeShell` nav; `TerminalTab` |
| Save to Downloads / export | paywall | enabled | Files selection; file editor |
| Per-project size breakdown | locked card → paywall | visible | Storage page Projects section |

Not gated: chat, files, editor, build tools, reset environment, cache clearing, project count, providers.

- **Background:** this is the existing **idle timeout**, not a hard cap on a running agent. Free is clamped to 5 minutes at runtime and in the UI, even if an old stored value is 15/30/60. Pro can choose 5/15/30/60. A busy agent keeps the server alive for as long as it is working; the 5-minute limit applies when the app is closed and nothing is running. The Settings row shows `5 min (Free)` or the Pro value. The paywall says “Background run (idle)” and “up to 60 min” so the claim is accurate.
- **Terminal:** the tab stays visible with a small lock. Tapping it as a free user opens the paywall and no PTY starts. If Pro is revoked while the terminal is open, sessions close and the tab shows the locked state.
- **Save:** the download icons stay visible. A free tap opens the paywall. The controller-level download method is unchanged; the UI gate is the enforcement.
- **Project sizes:** caches and Clear remain free. The Projects list is replaced by a locked card; tapping it opens the paywall. The runtime still calculates cache sizes, but project sizes are not shown to free users.
- **Build tools:** `Install build tools` and `Restore extra packages` stay free, but they no longer open the interactive terminal. They open a read-only **task sheet** that runs the command through the existing PTY runtime, streams the output, and offers no text input, extra keys or terminal tab. Free users get the install convenience without terminal access; Pro gets the same sheet plus the interactive terminal.

## Paywall screen

One `PaywallPage` plus `showPaywall(context, pro, reason)`. Full-screen route, Material 3, app seed `#3F6BE0`, light and dark.

Layout follows the supplied reference (the Qaf Pro paywall image sent in chat), adapted to the app's icon, seed colour and Material 3 typography:

- Top bar: circular outlined close button on the left; `Restore` text button on the right.
- Hero: the app icon (`docs/play-icon-512.png`, copied into app assets) in a rounded container.
- Title: **Get OpenCode Pocket Pro**.
- Reason line under the title: “Terminal is a Pro feature.” / “Save and export with Pro.” / “See what every project uses.” / “Keep the server warm longer.” / “Unlock everything, once.”
- Feature comparison table:

  | Features | Free | Pro |
  |---|---|---|
  | Chat, files and editor | ✓ | ✓ |
  | Terminal | — | ✓ |
  | Save to Downloads / export | — | ✓ |
  | Project size breakdown | — | ✓ |
  | Background run (idle) | 5 min | up to 60 min |
  | Build tools and cache clearing | ✓ | ✓ |

  Free checks are muted; Pro checks use `colorScheme.primary`. The background row uses text values, not checkmarks. A small line under the table says “Background run means the server stays warm after you leave the app. A running task keeps it alive.”
- Price card: a single outlined card with a **Founder price** banner, “Lifetime” label, the localized Play price, “one-time”, and a muted “Lifetime access. No subscription.”
- Primary button: **Unlock Pro** (large, filled, full width). It is disabled while the price is loading or unavailable.
- Footer: “One-time purchase. No subscription. Restore anytime.”

States:

- Loading price: button disabled, “Loading price…”.
- Product unavailable: “Pro isn't available right now.” + Retry; never show a hardcoded price.
- Purchasing: spinner in the button, disabled.
- Pending: “Payment pending — Google will confirm shortly.” No Pro yet.
- Error: short message + Retry.
- Already Pro: “You own Pro” and a close action.

On success, pop the paywall and show a snackbar “Pro unlocked”; gates re-evaluate from the same `ProController`.

The visual reference was supplied in chat; the app uses its own theme and icon rather than the reference brand.

## Settings plan section

A plan card at the top of Settings, above Server:

- **Free:** “Free plan” title, a **Founder price** chip, and “5-minute background idle run. Terminal, save/export and project sizes are Pro.” A filled **Unlock lifetime Pro** button opens the paywall. Supporting line: “One-time purchase. No subscription.”
- **Pro:** “Pro — lifetime” with a check icon, “All features unlocked. Purchased on this Google account.” A `Restore purchases` text button.
- **Loading:** “Checking your purchase…” + Retry.
- **Error:** “Could not check your purchase” + Retry. Do not claim Free when cached Pro is still inside the offline grace.

The idle-timeout row gets a `Pro` badge on the 15/30/60 choices for free users. Selecting one opens the paywall; selecting 5 still works. Pro users see all four choices normally.

Wording note: the UI says **Unlock** and **one-time**, not “subscribe”. Play treats this as a one-time product; calling it a subscription would be inaccurate.

Name: the paywall and plan card use **OpenCode Pocket Pro**. As a small consistency call, the `MaterialApp` title and the About row change from “OpenCode” / “OpenCode for Android” to “OpenCode Pocket” in the same change. This is a builder's call; it can be dropped if the rename is out of scope.

## Build-tools task sheet

`EnvironmentPage`'s build-tools and restore actions currently call `ShellController.runInTerminal`, which switches to the Terminal tab and opens an interactive shell. Replace that path with a `CommandTaskPage` (or full-height sheet) that:

- takes a title (`Installing build tools…`, `Restoring extra packages…`) and an argv command;
- opens `runtime.openTerminal(rows, cols, command: argv)`, listens to `output`, and appends decoded text to a read-only log;
- shows a spinner/progress line and a `Done` state when the process exits;
- has no `TextField`, no extra-key row and no link to the Terminal tab;
- closes the PTY on dispose and shows a failure message if the command fails.

Free users can install build tools; they cannot use the sheet to run their own commands. This keeps the “build tools free” promise without weakening the terminal gate.

## Billing and refunds

`ProController` (ChangeNotifier) plus a small `BillingGateway` abstraction so tests can fake it.

`PlayBillingGateway` wraps `InAppPurchase.instance`:

- `isAvailable()`, `queryProductDetails`, `queryPastPurchases` (Android addition), `buyNonConsumable`, `completePurchase`, `restorePurchases`, and `purchaseStream`.

`ProController` owns `owned`, `lastVerifiedAt`, `status`, `product`, and `error`.

- `initialize()` is idempotent: connect, load the product, query past purchases, subscribe to the purchase stream. Called from `HomeShell` and lazily from Settings/paywall.
- `buy()`: launch the non-consumable purchase. On `purchased`/`restored`, verify `productID == pro_lifetime`, acknowledge if `pendingCompletePurchase`, set owned, persist `pro_owned` and `pro_last_verified_at`.
- `refresh()`: query past purchases. Success + product present → owned. Success + absent → revoke. Failure → keep cached Pro within the 7-day grace.
- `restore()`: `restorePurchases()` followed by `refresh()`.
- Pending: status pending, no grant; a later `purchased` event grants.
- Cancel/error: no grant; error text in the paywall.
- Acknowledge immediately. If acknowledgement fails, leave the purchase unacknowledged and retry on the next launch; Play refunds unacknowledged purchases after 3 days.
- Refund/chargeback: no backend and no RTDN, so it is detected on the next successful query. The app revokes then. This limitation is documented in the Play listing/README if needed.
- No server receipt validation. The purchase is validated by Play Billing on the device; the local boolean is the entitlement. Accepted for a local-only app.

## Data

`SettingsStore` gains:

- `pro_owned` (bool)
- `pro_last_verified_at` (int, milliseconds since epoch)

No trial keys. Existing consent and idle-timeout keys are unchanged.

## Wiring

- `AppDeps` gains a `ProController pro`.
- `main.dart` creates `ProController(PlayBillingGateway(), settings)`.
- `HomeShell` calls `pro.initialize()` in `initState`, calls `pro.refresh()` on resume, and passes `pro` to the tabs and pages it opens.
- `SettingsTab`, `FilesTab`, `TerminalTab`, `StoragePage`, `FileEditorPage` receive the controller. `PaywallPage` receives it from `showPaywall`.
- Tests use a `FakeBillingGateway` / `ProController.fake(...)`; no real Play calls in widget tests.

## Play Console setup

- Add `com.android.vending.BILLING` to the Android manifest.
- Upload an AAB with billing permission to a test track.
- Create one-time product `pro_lifetime` (name/description, ₹999 founder price, active).
- Schedule the price change to ₹1,499.
- Add license testers; test buy, pending, restore, refund.
- Acknowledge within 3 days; the app acknowledges immediately.
- Refunds are issued in Play Console order management; the app revokes on the next query.

## Testing

- Unit: free/pro gating, buy success, pending, cancel, error, acknowledgement, restore, refund revoke, offline grace, price loading.
- Widget: Settings plan free/pro; terminal tab paywall; download paywall; storage project lock; paywall reason, price, buy and restore states.
- Device: license-tester purchase, kill/relaunch restore, refund → revoke, offline → grace.
- `flutter analyze` and all Dart tests.

## Open items

- Confirm product ID `pro_lifetime` (proposed).
- Confirm founder ₹999 / regular ₹1,499 (proposed).
- The founder badge is shown in the launch build. Raising the price later should ship an update that removes the badge, or the app must keep the founder claim accurate another way.

Resolved product decisions:

- Background limit = existing idle timeout, not a hard cap.
- Build tools stay free through the read-only task sheet; the terminal stays Pro.
