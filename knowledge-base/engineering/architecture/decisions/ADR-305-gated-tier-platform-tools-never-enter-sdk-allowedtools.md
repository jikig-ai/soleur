---
title: Gated-tier platform tools never enter SDK allowedTools; canUseTool is their only approver
status: accepted
date: 2026-10-27
supersedes: none
issue: 11303
related: [11303, 11289, 10054, 8532]
related_adrs: [ADR-060, ADR-070, ADR-109, ADR-113, ADR-284]
tags: [security, hosted, permission-callback, review-gate, allowedtools]
brand_survival_threshold: single-user incident
---

# ADR-305: Gated-tier platform tools never enter SDK allowedTools; canUseTool is their only approver

## Context

The Claude Agent SDK approves a bare `allowedTools` entry before it consults `canUseTool` (the SDK prints
`CAN_USE_TOOL_SHADOWED` for exactly this: "Bare allowedTools entries auto-approve the whole tool before the callback is consulted").
The hosted legacy agent runner (`startAgentSession`) listed every registered platform tool there, so the `gated` approval tier, the
Approve or Reject `review_gate` card that ADR-060 (outbound email) and ADR-109 (workstream writes) name as the trust boundary, was not
enforced for `email_send`, `email_reply`, `email_suppress`, `github_push_branch`, `create_pull_request`,
`github_trigger_workflow`, `kb_share_create`, `workspace_set_autonomous` and every other gated or default-gated platform tool. A
real-SDK probe (SDK 0.3.284, CLI 2.1.284) measured it: with `allowedTools` as the runner composed it, `canUseTool` was invoked for none of
the eight probed tools and the handler ran; with the name removed it was invoked, saw tier `gated`, and the deny was honoured (#11303).
A prompt-injected agent (inbound email body, issue text, CRM note) could therefore send, push, publish or switch off approvals with no
human decision.

## Considered Options

- **Option A: filter `allowedTools` by tier (chosen).** A pure `buildAllowedTools` keeps a platform name only when
  `getToolTier(name) === "auto-approve"`, plus validated plugin MCP wildcards. Pros: removes the cause, keeps read-only tools
  prompt-free, fail-closed for new tools (an unclassified tool defaults to gated). Cons: one extra review card per gated call in legacy
  chats (intended behaviour).
- **Option B: feature-flag the filter.** Rejected: a flag reintroduces the hole when off, and the fix is a security correction, not a
  product choice.
- **Option C: hide gated tools with `disallowedTools`.** Rejected: removes the capability instead of gating it and breaks the product
  promise (the agent can act once the human approves).
- **Option D: a PreToolUse hook that returns `ask`.** Rejected here: the SDK warning recommends it as an alternative, but removing the
  names is the smaller, probe-measured change and keeps one approval path (`canUseTool`).
- **Option E: wrap each handler with its own approval call.** Rejected: duplicates `canUseTool`, which the SDK already routes un-pre-approved
  tools to.

## Decision

1. **`canUseTool` is the only approver of every platform tool whose tier is not `auto-approve`.** No runner, probe or future caller may
   hand such a tool to the SDK as pre-approved (`allowedTools`, settings-file `permissions.allow`, skill or agent `allowed-tools`
   frontmatter, a permission mode that skips the callback, or a PreToolUse `allow`).
2. **The keep-rule is `isPreApprovable(name)` (`getToolTier(name) === "auto-approve"`)**, implemented once in `server/tool-tiers.ts` (it imports only the pure `outbound-compliance` validators, so tests and the real-SDK probe load it
   without booting the runner) and shared by `buildAllowedTools` and the `buildAgentQueryOptions` assertion; the plugin prefix helper (`pluginToolPrefix`) is the keep-rule shared with `canUseTool`'s plugin check, together with `pluginWildcard` / `parsePluginWildcard`, and `buildAllowedTools` is used at the legacy runner's `allowedToolsList` site. `createCanUseTool` keeps receiving the
   **unfiltered** `platformToolNames` (its own allowlist); only the SDK pre-approval list is filtered. `auto-approve` means read-only, or a hard-scoped
   reversible write whose justification is written next to its `TOOL_TIER_MAP` entry (`edit_c4_diagram` is the one existing write-shaped
   entry, scoped to `engineering/architecture/diagrams/`).
3. **Fail-closed second line in `buildAgentQueryOptions`**, the single assembly point of both real runners (legacy and cc): any
   `mcp__`-ish `allowedTools` entry must be an exact FQN whose tier is `auto-approve` or a `mcp__plugin_soleur_<name>__*` wildcard with
   `<name>` matching `^[a-z0-9-]+$`; everything else (a gated FQN, the bare server entry, `mcp__*`, rule-content forms, case or whitespace
   variants) throws at session start. So does any `Bash` or `Bash(...)` entry (any case), and any `permissionMode` other than undefined or
   `"default"`. This is an allowlist for MCP entries, not a denylist; a full allowlist of non-MCP entries is a follow-up.
4. **Every name handed to `createCanUseTool` as a platform tool has an explicit `TOOL_TIER_MAP` entry.** `getToolTier` still defaults to
   `gated`, but the census test fails until a new tool's tier is *decided*, so "decided" is distinguishable from "defaulted".
5. **The gate itself fails closed.** The gated branch runs through the shared `holdForUser` lifecycle: timeout or abort resolves to a static
   deny ("the action was not performed; do not retry unless the user asks; tell the user"), parallel cards stack (platform calls are denied once 5 cards, Bash and platform together, are pending; Bash cards are not themselves capped), and status-write failures mirror to Sentry under `platform-gate-status-hold|restore`, each with its own static
   message. **One deterministic status rule for both gate classes:** the hold is a compare-and-set into `waiting_for_user`; the restore
   runs only when the last pending gate resolves AND the session controller is not aborted, and is a compare-and-set
   `waiting_for_user` to `active` (it never overwrites `completed` or `failed`); the abort branch of `startAgentSession` finalizes from
   `active` ONLY, by design (#3463): the result branch writes `waiting_for_user` as the normal turn-end status, and a finalize that also
   accepted `waiting_for_user` would let a disconnect right after a clean result overwrite it with `failed`. A disconnect or Stop while a
   card is pending therefore leaves the row `waiting_for_user`; that state is resumable and the 2-hour sweep completes it. The end state is
   the same in either write order. An Approve that arrives after the session aborted (or while the restore write is awaited) is not
   honoured: the helper returns the aborted deny, never an `allow`. A session with no human present (the auto-sync seam sets an explicit
   `nonInteractive` flag) denies a gated platform tool at once, with no card, no status write and no notification.
6. **The card is part of the control.** Interpolated tool-input fields are bounded and neutralised, every accepted input that changes the
   outcome is shown or named as not shown, and the offline push/email text is content-free for every gated tool (privacy notice scope,
   #8532). The outbound-email cards show the full parsed recipient, reply-to, subject and the entire body (cap 4000), make hidden
   characters visible instead of deleting them (one shared hidden-character class; a literal `[U+` in the text is rewritten so it cannot
   forge a marker), and DENY with a static message when the input cannot be shown in full: an Approve card is
   never built from a truncated recipient or body. Recipients are ASCII-only and fail closed in v1 (punycode `xn--` is allowed) and must
   not carry leading or trailing whitespace, so the handler sends exactly the string the card parsed. The body hash (`approvedBodySha256`) is a handler-local integrity hash of the body as
   sent, not a binding to the card; the binding is `canUseTool` returning `allow(toolInput)`, the same object the handler runs on.
7. **Enforced by**, per forbidden pre-approval route in decision 1 (in the spirit of AP-020, not a quotation of it):
   - `allowedTools`: the `buildAllowedTools` filter plus the `buildAgentQueryOptions` assertion (both runners).
   - `permissionMode`: the same assertion (only undefined or `"default"`).
   - skill and agent `allowed-tools` frontmatter: the census sentinel, which parses the entries and applies the assertion's grammar to platform entries.
   - settings-file `permissions.allow`: not enforced here (the runner passes `settingSources: []`).
   - PreToolUse `allow` hook: matcher scope only. This is **NOT mechanically guarded**; nothing fails if a hook starts returning `allow` for a platform tool.
8. Plugin MCP wildcards (`mcp__plugin_soleur_<server>__*`) deliberately stay pre-approved: they are third-party servers declared in
   `plugin.json`, and `canUseTool` also allows them without a card, so the wildcard is the designed absence of a gate, not a bypass of one.
   That residual risk is outside this decision.

The honest limit of this decision: "Approve" binds to `allow(toolInput)`, because the SDK passes the same object to `canUseTool` and then to the
handler (probe-covered). There is no `toolUseID`-keyed binding of the reviewed body to the executed one.

This reverses the earlier implicit design in which `allowedTools` listed every registered platform tool.

## Scoped out

Known follow-ups, named here so they are not silent (tracked in the plan and `tasks.md` item 6.9):

- Reconnect replay of an unresolved `review_gate` frame.
- `email_reply`: look up the inbound sender and show it on the card.
- A `toolUseID`-keyed body-hash binding between the card and the executed call.
- A full non-MCP `allowedTools` allowlist (only MCP and the Bash family are checked today).
- `nonInteractive` for Bash gates in headless sync (only gated platform tools honour it).
- Serialising the gate hold and restore writes per session.
- A per-Query closed flag instead of the sticky controller-abort skip on the cc path.
- `failed` finalizers with active-only guards leaving a parked `waiting_for_user` row, and the AskUserQuestion / destroy-gate status writers bypassing `pendingGates` and the compare-and-set (pre-existing).
- Approve resolved, restore write in flight, then disconnect: the active-only abort finalize is a no-op against the still-waiting_for_user row and the restore then lands, leaving the row `active` with no session until the 5-minute stuck-active reaper corrects it (one DB round-trip window; same shape as AskUserQuestion). Accepted by CTO ruling.
- The destroy-ask Bash lane and AskUserQuestion have no post-hold abort recheck (pre-existing, #11289 follow-up).
- One shared `tool-tiers` `vi.mock` factory across the eight test files that mock it.
- Consent fatigue from one extra card per gated call.
- Other-field cards print "not shown" notes rather than the value.

## Consequences

- Gated tools now show their review card in the legacy runner (including `crm_*` and `workstream_issue_*` writes; the cc-soleur-go path already ran the gated `crm_*` tools through this branch via `crmLeadPermissionToolNames`);
  reflexive approval weakens the gate, which is an approval-queue design item (#11289), not a reason to re-open the bypass.
- A gated card unanswered for 5 minutes (about 30 s after a disconnect) denies with a static message; no client frame marks an expired card, and a late click gets "This prompt is no longer waiting for an answer. If it expired, nothing was done." Replaying unresolved `review_gate` frames on resume is a follow-up.
- A new platform tool without a tier entry fails CI; a new runner that passes a non-auto platform name fails at session start.
- Sessions are instance-local, so a host keeps the bypass until it runs the new image; the post-deploy absence check waits for every web host.
- The real-SDK probe (`apps/web-platform/scripts/dev-probe-approval-gate.ts`) must be re-run after any SDK, bundled-CLI, tier-map or option-builder change;
  its unfiltered `:raw` canary keeps proving the SDK still behaves as measured.

## Cost Impacts

None. The real-SDK probe is run by hand against a dev or ci config (about 10 model calls) and is not scheduled.

## NFR Impacts

None. No NFR register row changes tier.

## Principle Alignment

Aligns with AP-020 (untrusted input at the agent boundary): the tool-call a model emits is model-controlled, so the approval cannot be
skipped by a list the same runner composes. No deviation.

## Diagram

No C4 impact: no actor, system, container, store or relationship changes.

## Addendum (2026-10-29, #4672)

Decision 5 and the first Consequence describe the in-memory gate: a card unanswered for 5 minutes denies with "the action was not performed; do not retry unless the user asks". That wording stays exact for every
gated tool on the in-memory path, which is every tool when the `approval-queue` flag is off. For the eight tools in `APPROVAL_REQUIRED_TOOLS` with the flag on, the **durable path** replaces the in-memory wait
([ADR-307](./ADR-307-durable-action-bound-approval-requests.md)): a wait that ends undecided denies with a different static message ("saved for the workspace Owner; do not retry now") and leaves a `pending` row
that a later approval can release once. The decision of this ADR is unchanged: gated tools still never enter `allowedTools`, `canUseTool` is still the only approver, and the durable path sits inside the same
gated branch. Only the timeout text for those eight tools, flag on, differs. One further exception: in a session where the approval flow already ran, turning the flag off or a flag read error makes those eight tools deny with the static "approval unavailable" text for the rest of that session instead of falling back to the in-memory card (ADR-307, rollback).
