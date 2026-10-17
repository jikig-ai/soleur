---
title: Codex settings and history-transfer implementation screenshot QA
date: 2026-09-30
status: component-evidence-complete-runtime-pending
pr: 9051
---

## Evidence boundary

These are rendered implementation components, not Pencil exports. A lightweight
esbuild browser bundle imports the actual `AgentEngineSettings`, `ChatSurface`,
`ErrorCard`, `MessageBubble`, `ChatInput` and `Button` implementations from the
PR worktree. PostCSS compiles the application's actual `app/globals.css` with
installed Tailwind v4 and the application source scan. Browser dimensions are
1440 × 900 and 390 × 844 in the application's dark theme, using system fallback
fonts rather than the Next font loader.

The isolated harness binds only `127.0.0.1:19051`, uses the separate
`codex9051-components` browser session, supplies synthesized settings and
conversation data, and mocks fetch, WebSocket, workspace/team/flag hooks,
navigation and observability boundaries. The alert copy mirrors the API-key and
managed billing strings in `lib/ws-client.ts`. The mocked acknowledgment updates
the supplied view model; it does not run the real WebSocket reducer or server.
Stored messages, account identities, credential values and provider responses
are entirely absent from the evidence.

This establishes component rendering and callback wiring. It does **not**
establish authenticated full Web behavior, generation fencing, server-side
authorization, credential validity, provider execution, routine qualification,
erasure, CLO approval or rollout readiness. The complete acceptance chain stays
open. No local test suite or Next build ran; the operator's CI-only direction
applies to those checks.

The current design intent is the committed
[`workspace-default-engine.pen`](../workspace-default-engine.pen) and the
[2026-09-27 live-handler plan](../../../../project/plans/2026-09-27-feat-codex-web-live-handler-wiring-plan.md).
The September 11 section of the owning brief remains historical context.

## Rendered states

**Result:** component rendering and measured callback wiring PASS;
authenticated Web qualification remains PENDING.

| State | Evidence | Observation |
| --- | --- | --- |
| Owner default, desktop | [08](08-owner-default-implementation.png) | Claude Code and managed mode render; the native engine selector exposes available settings. |
| Codex settings only, desktop | [09](09-codex-settings-only-implementation.png) | Selecting disabled-execution Codex settings preserves the Claude workspace default and makes no PUT request. |
| Owner confirmation, desktop | [10](10-owner-mode-confirmation-implementation.png) | Preview count is 3; workspace scope, each member's credential, provider charges and history acknowledgment are disclosed before applying. |
| Owner confirmation, mobile | [11](11-owner-mode-confirmation-mobile-implementation.png) | Copy and both actions fit; the long apply label wraps without horizontal document overflow. |
| API-key mode after apply, mobile | [12](12-owner-api-key-disclosure-mobile-implementation.png) | Disclosure and applied count render; the mock PUT carries Codex, api-key, explicit existing-conversation intent and expected count 3. Claude remains the workspace default. |
| Member API-key history acknowledgment, mobile | [13](13-member-history-acknowledgment-mobile-implementation.png) | The actual client notice discloses stored-history transfer and the member's billing; both held messages show Message not sent and no Resend control before acknowledgment. |
| Acknowledged held messages, mobile | [14](14-member-held-messages-after-ack-mobile-implementation.png) | After the synthetic generation-3 acknowledgment updates the view model, both original messages expose an enabled Resend control. The acknowledgment invokes only its callback; clicking the first Resend invokes only that message's callback. |
| Member settings, mobile | [15](15-member-readonly-settings-mobile-implementation.png) | Both selectors are disabled and owner-only access copy is visible. |
| Disconnected chat, mobile | [16](16-disconnected-resend-disabled-mobile-implementation.png) | Reconnecting banner is visible; both held-message Resend controls and the composer are disabled. |
| Managed history acknowledgment, desktop | [17](17-managed-history-acknowledgment-implementation.png) | The actual managed notice identifies the workspace's connected ChatGPT account and asks the member to confirm applicable billing. |
| Connected but session unconfirmed, mobile | [18](18-session-unconfirmed-resend-disabled-mobile-implementation.png) | Both held-message Resend controls remain disabled despite connected transport status. |
| Requested managed mode, desktop | [19](19-owner-managed-mode-confirmation-implementation.png) | Confirmation explicitly names Managed ChatGPT sign-in as the destination while the committed dropdown remains api-key until Apply. |

Settings preview only performs a GET. Apply sends this synthetic request:

```json
{"engineId":"codex","authMode":"api-key","applyToExistingCodexConversations":true,"expectedAffectedConversationCount":3}
```

No layout overflow was measured in the inspected settings/chat states, and no browser
JavaScript errors were reported. Visible component structure differs from the
older September 11 exploratory layout: the latest design uses native dropdowns
and explicit confirmation instead of connection radio cards.

## Finding resolved during QA

The initial confirmation omitted the pending destination mode while its native
dropdown retained the current mode. The parent corrected the production
component's confirmation copy. Recaptured screenshots 10/11 identify API key;
19 identifies Managed ChatGPT sign-in. This finding is resolved by source and
browser-render evidence; CI validation of the accompanying assertion remains
the parent workflow's responsibility.

Screenshots 13/14/16/18 were captured after the independent reviewer added the
`sessionConfirmed` condition to `ChatSurface`'s resend-disabled prop. This
demonstrates its rendered state; the mocked WebSocket hook does not establish
the underlying socket-send or reconnect/replay protocol.

Source fingerprints at final compilation (HEAD `8a48f59163` plus the same-session
uncommitted review fixes):

```text
AgentEngineSettings: d4ca7b6f68290336f26f0287cf22f16017461690bd9381d9f2cd25eedf687e96
ChatSurface: 961a8fd8a442ea853b5b56a8ca4d101221fe1bc11e3e6d3791f1a3d210e38ec1
MessageBubble: 1c797526d3fb928d9180b5e5ba588982bc72bf6e1753f274a9b983982867ac17
```

## Harness diagnostics

The installed `@tailwindcss/node` dependency emits Node's `DEP0205` warning
because it calls deprecated `module.register()`. A traced build attributes the
warning to that installed dependency; compilation completed and the browser
reported no JavaScript errors. Temporary harness inputs and compiled output live
under `/tmp/codex9051-component-qa`; they do not alter production source.

CLI invocation correction: this installed `agent-browser` uses
`find role button click --name '…'`; the reversed positional form is rejected.
Only successfully completed interactions are represented as evidence here.

The first temporary HTTP server exited on SIGTERM after successful captures.
A repeat navigation therefore could not load the page; restarting the same
loopback server restored the harness, and the final acknowledgment/resend
captures were repeated with hydrated textarea and viewport geometry probes.
This interruption is harness lifecycle evidence, not a product-runtime result.
The harness server and isolated browser were stopped after final captures.
