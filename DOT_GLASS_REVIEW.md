# Dot Glass marketplace review candidate

Ready for maintainer review; not an approved or published marketplace release.

## Candidate and validation

- Widget source: current `codex/dot-glass-review` branch in https://github.com/appleforever11/DotGlass-Marketplace, including the latest personal-fix port.
- Upstream base: `11d38623d7d30071a74003042ab0aed06ff61056`.
- Exact upstream builder produced the universal arm64/x86_64 bundle. Distribution archive is unchanged and unsigned, as produced by that builder; the installed local test copy is ad-hoc signed.
- Earlier candidate GitHub macOS 14 / Xcode 15.4 / Swift 5.10 build and regression suite passed (not validation of this latest port): https://github.com/appleforever11/DotGlass-Marketplace/actions/runs/36960627997
- Local universal build and the same suite passed. Checks cover URL/origin policy, rendered message/send/acknowledgment behavior, duplicate prevention, inbound-only audio metering, muted calls, microphone controls, native connection state, actual WebKit responsive layout, and Bundle.principalClass loading against the SDK. All 11 widget folders pass the upstream validator.
- DockDoor settings and its preview were inspected live: plugin discovery, ring rendering, all six theme choices, and Rose-to-Aurora color propagation. The user's chosen theme and dock profiles were preserved.
- The user verified real two-way Dot voice, continuation while the panel is hidden, and mute/unmute in the installed candidate. Runtime events corroborate microphone capture, WebRTC connection, inbound audio and explicit call teardown. User confirmation supplies the audible/interactive proof; logs alone do not.
- The native muted warning and microphone button were visually inspected in a clearly labeled example preview. Existing conversation and tour screenshots are examples, not recordings of a live call or private user messages.

## Product behavior

Dot Glass provides a compact animated dock ring and a host-owned glass conversation panel. Six host-managed themes color the ring and Dot's message bubbles; outgoing messages remain grey with a subtle theme tint. Text uses the signed-in Dot conversation. Calls use ChatGPT's own call control and actual Dot voice, with native mute/unmute and End call controls.

A call belongs to the plugin session and continues when DockDoor auto-dismisses the panel. Reopen the panel to mute, unmute or end it. Microphone mute state is visible; the widget never silently unmutes. A visible dock timeline samples active voice while the panel is hidden; WebRTC events also report connection transitions. Connected hidden-panel transcripts refresh at most every three seconds while the dock timeline is rendered, supporting observed-session unread badges. No long-lived JavaScript interval or background helper is installed.

The embedded Dot page uses a desktop-sized WebKit frame scaled into the compact panel so its call control remains available. WebKit pageZoom stays at 1 to preserve virtualized message measurements. Sign-in pages retain normal scale. The native glass conversation is the primary interface.

## Marketplace boundaries

- Independent `dot-glass` identity; the personal variant is `dot-glass-personal`. No Codex Tracker imports, helper or data source.
- `Widgets/DotGlass` contains only widget.json, its explicitly listed Swift files and approved preview.png.
- Provider metadata and manifest match. Both dock orientations support compact and extended slots using WidgetMetrics; dock root has no fixed frame.
- DockDoor owns panel presentation. No custom NSWindow/NSPanel, subprocess, installer, agent, updater, private API or global event monitor in widget source.
- Plugin owns its @Observable connection; views use @Bindable. No singleton ObservableObject.
- Theme and glass opacity are read through WidgetDefaults and declared by settingsSchema. No direct appearance-setting writes; runtime preferences are namespaced `dot-glass.*`. No migration or other-app configuration writes.
- Standard persistent WKWebView website storage manages sign-in. The widget does not read cookies, tokens, credentials or keychain contents.
- The JavaScript bridge reads rendered page elements and operates existing Send, Call and Mute controls. Origin, room, duplicate-send and acknowledgment guards apply. No private network endpoints are called.
- Audio metering uses public inbound WebRTC getStats only. Microphone audio is not inspected, recorded or logged; no synthesized replacement voice.
- Microphone permission requests are restricted to the main ChatGPT origin during a user-started call. Call diagnostic logging contains fixed events and state booleans only, never account, message, room, credential or audio content.
- English labels, semantic panel fonts and Reduce Motion support.
- Approved preview: opaque sRGB PNG, 1080x608, 757254 bytes; no text/UI. Promotional hero remains outside the widget folder.

## Review limits and maintainer checks

Read receipts are shown only when ChatGPT renders explicit read/seen evidence. Delivery alone is never labeled Read. Receipt visibility changes (`data-read` and `aria-hidden`) are observed; timestamps remain rendered source text. An unread badge counts newly observed replies after the initial snapshot, not account-wide unread history. Notifications are opt-in, delivered by the DockDoor host, and omit message content. Native notification authorization and delivery require maintainer testing in the host.

This is a third-party rendered-page integration, not an official OpenAI API or endorsement. It requires an account with Dot access and microphone permission. ChatGPT UI changes may require adapter updates. Calls are conversations with the AI Dot, not telephone/PSTN calls. The integration cannot create additional Dots; its selector remembers valid conversations encountered in ChatGPT.

Live voice was checked with the user's existing authenticated session. Fresh-account sign-in, provider-specific authentication, and microphone permission onboarding should also be checked on the maintainer's account; no user session was erased to simulate a first install. Historical prototype sign-in is not represented as fresh-account validation of this final candidate.

The authenticated WebKit session and native/page bridge are explicitly disclosed for maintainer acceptance. Passing builds and lint does not guarantee approval. Prepared for upstream PR review; no marketplace deployment, GitHub release or Discord post is performed by this submission. The manual read-only review workflow is enabled on the review repository; no deployment workflow has been dispatched.

## Prior maintainer decisions applied

- PR #20: no other-app config writes or background-agent workaround, separate identity from Tracker, no auxiliary widget-folder files: https://github.com/ejbills/dockdoorpro-widgets/pull/20
- PR #21: native host settings and honest absent-data reporting: https://github.com/ejbills/dockdoorpro-widgets/pull/21
- Current CONTRIBUTING.md and scripts/widget_rules.py remain authoritative.

## Personal build is separate

The personal repository and Sparkle feed are separate from this marketplace candidate: https://github.com/appleforever11/DotGlass-Private . Its empty feed was tested previously; a notarized production update/install cycle is not part of this marketplace validation. The latest personal 0.9.3 receipt, unread badge, opt-in notification, speaking-aura and opacity fixes are now ported with the marketplace identity and original WebKit session store preserved. The personal companion, updater and build/install scripts are excluded.

## Latest port validation and review limits

The candidate includes semantic read-receipt parsing and visibility-change regression fixtures, receipt retention, reply baseline/deduplication checks, hidden-call continuity, mute controls and bounded transcript sampling. The speaking aura no longer draws the white arc; its shape/light animation depends on speaking state rather than meter amplitude. Speech activity is inferred from inbound WebRTC measurements with a hold interval, not an official semantic speaking API.

The universal upstream build, widget validator, URL/origin checks, JavaScript adapter fixtures, unread state tests, connection checks, real local WebKit viewport tests and bundle class loading are run for this port. Prior signed-in voice acceptance predates this port. Live read receipts, unread badge clearing, native notifications and final glass/aura appearance still require signed-in host acceptance. No new live visual or receipt verification is claimed.
