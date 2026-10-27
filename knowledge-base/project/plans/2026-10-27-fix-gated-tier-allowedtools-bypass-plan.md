---
title: "fix(security): gated approval tier is bypassed by allowedTools in the hosted legacy agent runner"
type: fix
date: 2026-10-27
slug: gated-tier-allowedtools-bypass
branch: feat-one-shot-11303-gated-tier-allowedtools-bypass
issue: 11303
closes: 11303
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(security): gated approval tier is bypassed by allowedTools in the hosted legacy agent runner

## Enhancement Summary

**Deepened on:** 2026-10-27 (headless). **Gates run:** 4.6 user-brand (pass), 4.7 observability (pass; discoverability probe uses an allowlisted verb with a declared credential), 4.8 PAT sweep (no hits), 4.9 UI wireframe (not triggered, no UI files), 4.10 encryption posture (not triggered, no store or connection), 4.11 guard contract (lint green, 3 guards, structural assembly), 4.12 scope check (one live section, no BLOCKED marker), 4.13 task design (not triggered, no new autonomous task). Cited rule IDs, issue numbers (#10054, #11289, #3242, #3454 all open as claimed) and the ADR ordinal (highest on a freshly fetched `origin/main` is ADR-303) were verified live. SDK semantics are cited verbatim from `sdk.d.ts` (`allowedTools?: string[]`: "List of tool names that are auto-allowed without prompting for permission ... To restrict which tools are available, use the `tools` option instead.") and `sdk.mjs` (the `CAN_USE_TOOL_SHADOWED` message: "Bare allowedTools entries auto-approve the whole tool before the callback is consulted ... remove the bare names from allowedTools so they fall through to canUseTool").

**Agents used:** security-sentinel, user-impact-reviewer, observability-coverage-reviewer, test-design-reviewer, learnings-researcher (plan phase), CTO, CPO, CLO ruling (carried forward), plus the five-seat plan-review panel.

### Key improvements from this pass
1. The assertion became an allowlist (exact auto FQN or validated plugin wildcard), closing rule-content, case and whitespace variants, plus a `bypassPermissions` check.
2. The card became part of the control: bounded and neutralised fields, an email truncation marker with total length, and content-free offline push/email messages for every gated tool (the fix makes that egress live for the first time).
3. The post-deploy check was corrected: real `host_name` values (`soleur-web-platform`, `soleur-web-2`), both hosts deployed first, a Phase 0.6 proof that the SHADOWED channel reaches Better Stack at all, and honest "unobservable" semantics.
4. Gate expiry now logs at warn so it ships to Better Stack; failure modes are named triage-only; one failure mode (no card) is explicitly stated to have no runtime layer.
5. Test design: derived floors, empty-result equivalence, negative and variant inputs, a by-equality call-site assertion, a distinct-op-message test, and a vacuity guard for the mocked Plausible registration.

### New considerations discovered
- The SDK warning itself recommends a PreToolUse hook as the alternative lever; rejected here because removing the names is what the brief ruled and what the probe measured.
- Sessions are instance-local, so the bypass persists per host until that host deploys.
- `edit_c4_diagram` is an `auto-approve` write-shaped tool; the ADR records the meaning of `auto-approve`.


## Overview

In the hosted legacy agent runner (`startAgentSession` in `apps/web-platform/server/agent-runner.ts`), the list of SDK-pre-approved tools (`allowedTools`) contains every platform tool. The Claude Agent SDK approves a bare `allowedTools` entry before it consults `canUseTool`, so the `gated` approval tier (the `review_gate` card with Approve or Reject) has not been enforced for the gated platform tools: `email_send`, `email_reply`, `email_suppress`, `github_push_branch`, `create_pull_request`, `github_trigger_workflow`, `kb_share_create`, `workspace_set_autonomous`, and every other gated or default-gated platform tool: `create_issue`, `kb_share_revoke`, `routine_run`, `crm_contact_upsert`, `crm_note_append`, `crm_contact_set_stage`, `workstream_issue_*`, and (default-gated until this plan gave them explicit entries) `account_export_enqueue`, `account_delete_initiate` and `plausible_*`. The real-SDK probe measured this on SDK 0.3.284 (CLI 2.1.284): with `allowedTools` as the legacy runner composes it, `canUseTool` is invoked for none of the eight probed tools and the handler runs; with the name removed, `canUseTool` is invoked, sees tier `gated`, and the deny is honoured. The SDK prints `CAN_USE_TOOL_SHADOWED` for these names.

This plan ships an **unconditional** fix (no flag; ruled by the CTO agent 2026-10-27), as three independently reviewable commits plus one ADR commit. All four land together in one PR; the order is for review and bisect, not for staged release:

1. **Gate lifecycle first** (`permission-callback.ts`): the gated platform-tool branch gets a fail-closed, status-restoring await. It goes first because the filter in commit 2 makes this branch reachable for the legacy runner (the cc-soleur-go path already ran the gated `crm_*` tools through this branch via `crmLeadPermissionToolNames`); "making a dead path live exposes its defects" (learning `2026-10-11-a-mocked-sdk-could-not-see-the-permission-callback-never-ran.md`).
2. **The filter** (`buildAllowedTools` in `tool-tiers.ts`, called at the `allowedToolsList` site, with a fail-closed second line of defence in `buildAgentQueryOptions`), explicit tier entries so the census can tell "decided" from "defaulted", informative gate messages for the tools whose card text is currently the generic default, and the census/mutation tests.
3. **The real-SDK probe** (cherry-pick of `0acc541b6f`, switched to build `allowedTools` via `buildAllowedTools` and to the production string-prompt shape), run against Doppler `ci`/`dev`, never `prd`.
4. **ADR** recording the invariant.

The ordering evidence (the SDK pre-approves a bare `allowedTools` entry before `canUseTool`) comes from the real-SDK probe on the sibling branch and the 2026-03-20 permission-chain learning, not from code in this repo; the SDK's own `CAN_USE_TOOL_SHADOWED` warning states it in `sdk.mjs`.

### Exposure window (corrected in review, 2026-10-27)

Earlier text dated the exposure from 2026-06-15. That date is only when the email tools were added. A gated platform tool has been pre-approved through `allowedTools` from the day it was registered, so the window is per tool and starts at **2026-04-06** (`create_pull_request`, commits f281666dca and 298bf96cca, #1654). The telemetry lower bound for the CLO follow-up (`outbound_sends`, GitHub and KB-share events) is therefore 2026-04-06, not 2026-06-15.

| Tool(s) | First registered in the legacy runner (and therefore pre-approved) |
|---|---|
| `create_pull_request` | 2026-04-06 |
| `plausible_*` | 2026-04-10 |
| `github_push_branch`, `github_trigger_workflow` | 2026-04-11 |
| `kb_share_*` | 2026-04-17 |
| `account_*` | 2026-05-26 |
| `workspace_set_autonomous` | 2026-06-03 |
| `create_issue`, `routine_run`, `email_send` / `email_reply` / `email_suppress` | about 2026-06-15 |
| `crm_*` | 2026-07-08 |
| `workstream_issue_*` | 2026-07-10 |

## Research Insights

### Premise Validation (Phase 0.6)

- `#11303` is OPEN, no closing PR. The only open change naming it is **PR #11304, this branch's own draft PR** (collision pre-check exit 10 lists it plus foreign `test-all.sh` processes from unrelated worktrees; none touch these files). No duplicate work.
- Cited artifacts all exist on `origin/main`: `server/agent-runner.ts` (`allowedToolsList` at the `const allowedToolsList =` site), `server/tool-tiers.ts` (`TOOL_TIER_MAP`, `getToolTier`), `server/permission-callback.ts` (`createCanUseTool`, gated branch, `holdForUser`), `scripts/betterstack-assert-absence.sh`. The probe is NOT on `main`: it exists only on `origin/feat-hitl-approval-queue` at `0acc541b6f` (`git cat-file -t` returns `commit`); it adds `apps/web-platform/scripts/dev-probe-approval-gate.ts` and `knowledge-base/project/specs/feat-hitl-approval-queue/phase-0-measurements.md` (the latter is left out here).
- ADR corpus check: no ADR rejects the mechanism. ADR-060 (outbound email) and ADR-109 (workstream writes) state the review gate is the trust boundary; their premise is exactly what this fix restores. ADR-113/ADR-284 concern the Bash lane, not platform-tool tiers.
- The measurement record names the fix as flag-conditional ("only under the approval-queue flag" was one option); the CTO ruled unconditional.

### Property List and Cut List (Phase 0.6b)

Properties the ask buys:

- P1. No platform tool whose effective tier is not `auto-approve` is pre-approved to the SDK in the legacy runner.
- P2. Auto-approve platform tools and plugin MCP wildcards stay pre-approved (no new prompts for read-only tools).
- P3. A new or unclassified platform tool defaults to gated and therefore to a prompt (fail-closed), and CI fails until someone decides its tier.
- P4. A gate that expires or is aborted denies, never throws, never allows, and the conversation status is restored.
- P5. A real SDK run, not a mock, shows the gate firing under the production option composition.
- P6. After deploy, telemetry shows no gated tool name in a `CAN_USE_TOOL_SHADOWED` warning, or says explicitly that it could not observe.

Mechanisms named in the ask and what already covers them (the Cut List):

| Mechanism in the ask | Property | Already on `origin/main`? | Disposition |
|---|---|---|---|
| `buildAllowedTools` | P1, P2 | no (the list is built inline) | keep |
| Census test + mutation battery | P1, P3 | no census over `allowedTools` exists | keep |
| try/finally around `abortableReviewGate` | P4 | partly: `holdForUser` (Bash gates) already implements hold/await/restore with a `null` verdict | **reuse `holdForUser`**, do not write a second try/finally (CTO ruling) |
| Real-SDK probe | P5 | `dev-probe-destroy-ask.ts` is the Bash precedent; the approval probe exists only on the sibling branch | keep (cherry-pick) |
| Post-deploy absence check | P6 | `scripts/betterstack-assert-absence.sh` exists | keep, reuse as-is |
| A feature flag | none | not applicable | **cut** (CTO: a flag reintroduces the hole) |
| Extending `bash_autonomous` to platform tools | none | not applicable | **cut** (CTO: Bash-only) |

### Repo findings

- The legacy `allowedToolsList` is `[...platformToolNames, ...pluginMcpServerNames.map(s => "mcp__plugin_soleur_" + s + "__*")]` or `undefined` when both are empty. `platformToolNames` is assembled from inline literal pushes plus builder `toolNames` (github, plausible, account, routines, workstream, workspace-settings) in `startAgentSession`. Counted universe on the legacy runner (all builders on, repo connected, Plausible key present): **46 names**. Today: 21 explicit `auto-approve`, 19 explicit `gated`, and 6 default-gated (no `TOOL_TIER_MAP` entry): `plausible_create_site`, `plausible_add_goal`, `plausible_get_stats`, `account_export_enqueue`, `account_delete_initiate`, and `conversations_lookup`. After this change: 22 auto-approve (`conversations_lookup` joins) and 24 gated (19 + the 5 now explicit). The 46 is a plan-time census to re-derive at work time, not a constant to hard-code.
- `canUseTool` branch for platform tools: `ctx.platformToolNames.includes(toolName)` then `getToolTier`; gated tier emits `review_gate`, sets status `waiting_for_user`, awaits `abortableReviewGate`, then restores `active`. The await is unguarded: `abortableReviewGate` rejects on timeout (5 min) or abort, which throws out of `canUseTool` and strands the conversation in `waiting_for_user`.
- `holdForUser` (permission-callback.ts, Bash gates, #10054) already: counts pending gates so parallel cards stack; flips status on the first pending gate and restores on the last; swallows a rejection into `null`; mirrors status-write failures to Sentry via `warnSilentFallback` with ops `bash-gate-status-hold` / `bash-gate-status-restore`.
- Other pre-approval routes ahead of `canUseTool` in the legacy runner (CTO ruling 8, each read in code): `permissionMode` defaults to `"default"`; `settingSources: []`; sandbox `autoAllowBashIfSandboxed: false`; the sandbox PreToolUse hook returns `allow` only for `Read|Write|Edit|Glob|Grep|LS|NotebookRead|NotebookEdit|Bash`. None shadows `mcp__soleur_platform__*` after the fix. Plugin MCP wildcards intentionally stay pre-approved.
- The cc path is unaffected: `CC_PATH_ALLOWED_TOOLS` contains built-ins plus `narrate`/`summarize` only (both auto-approve); crm-lead write tools stay on the review gate there. `pdf-chapter-router` passes `allowedTools: []`; Inngest crons use CLI `--allowedTools` of built-ins. `buildAgentQueryOptions` is the single assembly point for both real SDK runners (legacy `agent-runner.ts:2180`, cc `cc-dispatcher.ts:3165`).
- String-prompt reachability (a premise the probe header contradicts): `dev-probe-*` comments say the SDK wires `canUseTool` only for a streaming-input prompt, but the legacy runner passes a plain string. Read in `sdk.mjs` 0.3.284: `CA(query, prompt, ...)` writes a string prompt as a stdin `user` message, and `--permission-prompt-tool stdio` is added whenever `canUseTool` is set, independent of prompt shape. So the permission channel is reachable for the legacy runner, and the probe gets a string-prompt diagnostic row to measure it rather than assume it.
- `conversations_lookup` handler is read-only: `lookupConversationForPath` does `users` SELECT probe plus `conversations`+`messages(count)` SELECT through `getFreshTenantClient`; `getCurrentRepoUrl` is a SELECT; closure-bound `userId`; no writes. It is classified `auto-approve`.
- Registered-but-not-allowlisted siblings (`conversations_list`, ...) are denied by `canUseTool`'s deny-default today; unchanged.
- Callers of `startAgentSession` / `sendUserMessage`: only `ws-handler.ts` (lines around 2585, 2604, 2732), i.e. always a user-attached WebSocket session. That claim was false: `server/auto-sync-trigger.ts` calls `startAgentSession` with `HEADLESS_SYNC_PROMPT` (`/soleur:sync --headless`) after repo setup, with no human attached. A card there would sit for 5 minutes. Corrected in review: the auto-sync seam passes an explicit `nonInteractive` flag (not inferred from the prompt) through `startAgentSession` to `createCanUseTool`, and a gated platform tool in such a session is denied at once with a static message (no card, no `waiting_for_user` write, no offline notification).
- Abort and status ordering: the abort branch of `startAgentSession` writes its terminal status (`waiting_for_user` for a user Stop, `failed` for a disconnect) through `updateConversationStatusIfActive`, which writes only when the current status is `active` (`ACTIVE_STATUSES_FOR_FINALIZE = ["active"]`). While a gate is held the status is `waiting_for_user`, so that write is a no-op unless the gate's restore-to-`active` lands first. A restore that lands after the abort write leaves the conversation `active`. This is a real race, decided in Proposed Solution 4.
- Disconnect: `ws.on("close")` arms a 30 s grace (`DISCONNECT_GRACE_MS = 30_000`) after which `abortSession` fires, so a gate for a disconnected user dies at about 30 s, not at the 5-minute gate timeout. The push notification (`notifyOfflineUser`) can therefore only help within that window.
- Late click after expiry: `abortableReviewGate` deletes the resolver on timeout and on abort, so a late `review_gate_response` finds no pending gate; the work phase confirms the ws-handler handles that as a harmless error, not an allow.
- `buildGateMessage` has no `case` for `workspace_set_autonomous`, `account_delete_initiate`, `account_export_enqueue`, or `plausible_*`; they fall to the generic "Agent wants to use **name**. Allow?". Once the gate is reachable, the card for account deletion or switching off approvals must say what is being approved.
- Plugin skill and agent frontmatter is a separate pre-approval route (skill `allowed-tools`). Grep of `plugins/soleur/skills/*/SKILL.md` and `plugins/soleur/agents/**` today finds no `mcp__soleur_platform__` entry (only a reference doc mentions the string); a small sentinel keeps it that way.

### Institutional learnings applied

- `security-issues/2026-10-11-a-mocked-sdk-could-not-see-the-permission-callback-never-ran.md`: only a real-SDK probe proves a gate fires; a probe that can pass without proving anything returns CANT-RUN, not PASS. Drives the `:raw` canary and the "model did not attempt" handling.
- `2026-03-20-canusertool-caching-verification.md`: the permission chain order (hooks, deny rules, mode, allow rules incl. `allowedTools`, `canUseTool`); filtering `allowedTools` is the correct lever; test with `settingSources: []`.
- `security-issues/2026-04-06-mcp-tool-canusertool-scope-allowlist.md`: allowlists are explicit names, never prefix; here the keep-set is `getToolTier(n) === "auto-approve"` so a new tool defaults to gated.
- `2026-03-20-review-gate-promise-leak-abort-timeout.md`: `abortableReviewGate` rejects (not resolves) so cleanup runs; the lifecycle fix must keep reject semantics and catch at the caller.
- `2026-09-27-crm-lead-chat-tools-need-the-permission-allowlist.md`: "registered on the server" is not "allowed to call"; assert fully qualified names.
- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md` and `patterns/guard-pins-artifact-not-wiring.md`: the census must pin that the filter's output reaches the SDK options (wiring), and reverting the call-site edit must turn a test red.
- `2026-09-24-my-probe-accepted-more-evidence-than-its-absence-queries-could-see.md`: an absence assertion must cover the same window, host and row shapes as its paired evidence; shapes the post-deploy check below.
- `best-practices/2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md`: the probe depends on model compliance; the header must say a green run is not proof beyond the sampled behaviour.

## Research Reconciliation: Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Issue: "Fix-Size: about 120 lines / 4 files" | Honest footprint is larger: filter, call site, second-line assertion in `buildAgentQueryOptions`, explicit tier entries, lifecycle fix, 3 flipped test files + 2 `kb_share_create`-verbatim test sites, 2 new test files, probe, ADR (about 14 files, roughly 600 changed lines including tests) | Still one PR (below the split thresholds); scope check below maps each item |
| Probe header: "a bare string prompt runs the CLI without the permission callback" | `sdk.mjs` writes a string prompt over stdin and always sets `--permission-prompt-tool stdio` when `canUseTool` is set; the legacy runner uses a string prompt | Run all probe rows with the production string prompt (plus one streaming-prompt diagnostic); measure it in Phase 0.4 before building; correct the header comment; do not redesign the runner |
| Measurement doc: `prod` = "all eight FQNs" | Production lists 46 platform names plus plugin wildcards | Probe `:prod` input becomes the full legacy name set derived from the real builders, filtered through `buildAllowedTools` |
| `tool-tiers.ts` comment: Plausible tier entries "do not exist" and conversations_lookup is "deliberately omitted" | Both stay true only by omission; the census needs decided tiers | Add explicit entries; update both comments |
| Existing tests assert gated names ARE in `allowedTools` (`agent-runner-tools`, `agent-runner-kb-share-tools`, `email-triage-tools`) | They encode the defect | Flip to absence; keep the read-tier and plugin-wildcard assertions |
| Measurement doc offers "unconditional or only under the flag" as a product/risk call | CTO ruled unconditional | No flag anywhere |

## Problem Statement

A hosted domain-leader chat (legacy runner) can be steered by untrusted text it reads (an inbound email body, a GitHub issue, a CRM note) into calling `email_send`, `github_push_branch`, `create_pull_request`, `kb_share_create`, or `workspace_set_autonomous`. The product promises an Approve/Reject card first. Because the tool names are in `allowedTools`, the SDK runs the call without ever invoking `canUseTool`. Evidence limits: no telemetry shows any gated tool ran ungated, and no legacy sessions with platform tools were observed since 2026-09-30; the CLO ruled this an Art. 32 control-effectiveness gap, not a notifiable breach on present evidence.

## Proposed Solution

### 1. `buildAllowedTools` (pure, in `apps/web-platform/server/tool-tiers.ts`)

```ts
// signature only; the body is the work phase's job
export function buildAllowedTools(
  platformToolNames: readonly string[],
  pluginMcpServerNames: readonly string[],
): string[]
```

- Keeps a platform name only when `getToolTier(name) === "auto-approve"` (fail-closed: `gated`, `blocked` and unknown all drop out). Appends `mcp__plugin_soleur_${server}__*` for each plugin server. Always returns an array; the call site keeps the existing `...(list.length ? { allowedTools: list } : {})` shape.
- Lives in `tool-tiers.ts` because that file is import-free: the probe and tests import it without booting `agent-runner.ts`.
- **Call site:** `agent-runner.ts` `allowedToolsList` becomes `buildAllowedTools(platformToolNames, pluginMcpServerNames)`. `createCanUseTool` still receives the **unfiltered** `platformToolNames` (its own allowlist); only the SDK pre-approval list is filtered.
- `bash_autonomous` stays Bash-only; nothing in this change extends it to platform tools. `workspace_set_autonomous` stays gated.

### 2. Second line of defence in `buildAgentQueryOptions` (CTO ruling 1)

At the single assignment `opts.allowedTools = args.allowedTools` in `server/agent-runner-query-options.ts`, throw on any `mcp__`-prefixed entry that is not on an **allowlist** (same fail-closed pattern as `assertTrustedPluginPath`; security review: a denylist of known-bad shapes misses rule-content forms such as `mcp__soleur_platform__email_send(*)` and case or whitespace variants). Accepted: (a) an exact FQN whose `TOOL_TIER_MAP[fqn] === "auto-approve"`, looked up with no trimming or normalising; (b) `mcp__plugin_soleur_<name>__*` where `<name>` matches `^[a-z0-9-]+$`. Everything else starting with `mcp__` throws, including the bare server entry `mcp__soleur_platform` (the SDK reads it as "every tool on this server"), `mcp__*`, and `mcp__soleur*`. Entries that do not start with `mcp__` (`Read`, `WebFetch`) pass. `buildAllowedTools` applies the same `^[a-z0-9-]+$` check to plugin server names before interpolating them and omits an invalid name (fail closed). The same function also throws when `args.permissionMode` is `bypassPermissions` (and any other mode `sdk.d.ts` documents as auto-approving every tool; confirm in `PermissionMode`), since that also skips `canUseTool`; work time confirms `settings` and `extraArgs` are never set by either runner (`rg`). Both real runners (legacy, cc) and the probe's `:prod` rows flow through this choke point, so a future caller cannot reintroduce the bypass. The probe's `:raw` canary builds its options and then overrides `allowedTools` directly, bypassing the builder on purpose. The throw message carries the entry only (static prefix plus a server-controlled name), no tool input. The throw is inside `runWithByokLease`, so it surfaces as an ordinary session error; a test runs the builder with the real `CC_PATH_ALLOWED_TOOLS` and the support-persona filter so a cc-list edit that adds an unclassified platform name fails CI, not a live session.

### 3. Tier map hygiene (`tool-tiers.ts`)

- `conversations_lookup` → `"auto-approve"` (handler verified read-only above); replace the stale NOTE comment.
- Explicit `"gated"` entries for `plausible_create_site`, `plausible_add_goal`, `plausible_get_stats` (the user's own stored `PLAUSIBLE_API_KEY`; CTO: stay gated), `account_export_enqueue` (writes; bundles BYOK credentials and files), `account_delete_initiate` (destructive). Behaviour is unchanged (they were default-gated); the entries exist so the census can assert "every name in `platformToolNames` has an explicit `TOOL_TIER_MAP` entry" and a new tool fails CI until someone decides its tier. Update the `CC_ROUTER_TIER3_DENYLIST` comment that says Plausible entries do not exist.

Card integrity (user-impact review P1): once the gate is reachable, the card is the only control, and its text is built from model-controlled tool input (`to`, `subject`, `branch`, `title`, ... interpolated unbounded inside `**...**`). Add one small helper in `tool-tiers.ts` that bounds each interpolated scalar field (length cap) and neutralises newlines and markdown emphasis/link characters, applied to every scalar interpolation in `buildGateMessage`; the email body keeps its existing 240-character preview and "untrusted, display-only" framing. At work time confirm in `server/email-triage/outbound.ts` that the approved body is bound to the send (hash recomputed at the chokepoint) and cite the line in the PR body; if it is not bound, that is a stop-and-escalate finding, not something this PR silently accepts. A test asserts every gated tool's card text is length-bounded and carries no raw newline or markdown control sequence from a hostile input. The helper also strips control, bidi and zero-width characters, quotes the value, and treats a non-string field as the literal word `unknown` rather than interpolating an object. The `email_send` / `email_reply` body preview keeps its 240-character cap but appends an explicit `[+N more characters not shown, total M]` marker so a tail payload is never silently hidden (security review P2); the approved-body binding evidence above is the second half.

**Offline push egress (security review P2; newly reachable):** `buildOfflineGateMessage` is content-free only for `email_*`; every other gated tool falls through to `buildGateMessage`, which puts PR titles, issue titles, branch names, KB paths, CRM ids and (with the new cases) Plausible domains into push and Resend, stores the privacy notice does not list (#8532). Because this change is what makes the gate fire for the first time, it also makes that egress live. Invert the function to an allowlist: a static, content-free sentence with a fixed per-tool action label (for example "a GitHub push", "an account deletion") for **every** gated tool; the in-app card carries the detail. A test asserts no offline message contains any tool-input value. No published privacy text is edited.

Gate messages (`buildGateMessage`, informed consent for the cards that become reachable): add explicit cases, each free of tool-input PII and safe for the offline push path (`buildOfflineGateMessage` falls through to it): `workspace_set_autonomous` (states ON or OFF and that ON lets the agent run shell commands in the workspace without asking), `account_delete_initiate` (permanent deletion of the account and all data, no echo of the confirmation email), `account_export_enqueue` (a full account data export), `plausible_create_site` / `plausible_add_goal` / `plausible_get_stats` (name the site domain, goal type and value, or the stats read). A test asserts that no gated tool's gate message equals the generic default.

### 4. Gate lifecycle (`permission-callback.ts`, its own commit)

Generalize `holdForUser` with a trailing options object (`{ kind?, gateClass }`, not another positional argument) where `gateClass: "bash" | "platform"` selects the Sentry ops (`bash-gate-status-hold|restore` unchanged and still the default; new `platform-gate-status-hold` and `platform-gate-status-restore`, each with its own static `message`). The gated platform-tool branch keeps `sendToClient` + `notifyOfflineUser` as is, then replaces the unguarded `updateConversationStatus` / `await abortableReviewGate` / `updateConversationStatus` triple with a `holdForUser` call for `gateClass: "platform"`:

- `null` (timeout or abort) → `log.warn` (not `info`: the log shipper forwards only level 40 and above, so a warn row reaches Better Stack without SSH, observability review) with `sec: true`, `decision: "platform-gate-expired"`, `logPermissionDecision("canUseTool-platform-gated", tool, "deny", "gate expired")`, and a **static** deny: `The approval request expired before it was answered, so the action was not performed. Do not retry unless the user asks. Tell the user the action was not performed and ask how they want to proceed.` No Sentry capture for expiry (expected user behaviour); Sentry only for status-write failures, which are triage-only (no pager rule is added; stated, not implied).
- `"Approve"` → allow (unchanged); any other selection → deny `User rejected the action. Do not retry unless the user asks. Tell the user the action was not performed and ask how they want to proceed.` (CPO sign-off condition: the agent must not retry around the gate; no existing test pins the old string, re-grep at work time).
- Parallel gated calls now stack correctly (first answer does not mark the turn `active` while another card is open).
- **Status policy (corrected in review; ADR-305): one deterministic rule for BOTH gate classes.** (1) The hold write is a compare-and-set (`active` or `waiting_for_user` to `waiting_for_user`). (2) The restore runs only when the pending counter reaches 0 AND `ctx.controllerSignal.aborted` is false; on abort the restore is skipped for Bash and platform gates alike. (3) The restore is a compare-and-set, `waiting_for_user` to `active` only, so it never overwrites `completed`, `failed` or a status the abort branch wrote. (4) The abort branch of `startAgentSession` finalizes from `active` ONLY, by design (#3463; the set is `ACTIVE_STATUSES_FOR_FINALIZE`, shared by every finalize site): the result branch writes `waiting_for_user` as the normal turn-end status, and a widened finalize would let a disconnect right after a clean result overwrite it with `failed`. (5) An Approve that lands after the session aborted, or while the restore write is awaited, is not honoured: `holdForUser` returns null and every caller denies. Result: a disconnect or Stop while a card is pending leaves the row `waiting_for_user`, the same end state in either write order; that state is resumable and the 2-hour inactivity timer (`startInactivityTimer`, which completes `waiting_for_user` rows) closes it. The earlier text here (a widened abort finalize, so a disconnect with a card pending ends `failed`) re-opened #3463 and was reverted after the CTO's second-round ruling; the stuck-conversation reaper handles `status = 'active'` only. The other gate sites (`AskUserQuestion` around line 515, the destroy gate around line 777) are out of scope here.
- `options.agentID` (subagent) is present on the call context; a test sets it on a gated call to confirm the verdict path is identical.

### Alternatives considered

| Alternative | Why not |
|---|---|
| Flag-conditional filter | Reintroduces the hole when off; CTO ruled unconditional |
| Hide gated tools via `disallowedTools` | Removes capability instead of gating it; breaks the product promise |
| Wrap gated tool handlers with an approval call | Duplicates `canUseTool`; the SDK already routes un-pre-approved tools there |
| Separate try/finally in the gated branch | Second lifecycle path; `holdForUser` already stacks gates (CTO ruling 2) |
| Move `buildAllowedTools` to `agent-runner-query-options.ts` | Not import-free; the probe would boot more of the runner |

## Technical Considerations

### Attack Surface Enumeration

Every place a tool can be pre-approved ahead of `canUseTool`, and its disposition:

| Path | Checked by fix? | Disposition |
|---|---|---|
| `allowedTools` in legacy runner | yes | filtered by `buildAllowedTools` |
| `allowedTools` in cc-dispatcher (`CC_PATH_ALLOWED_TOOLS`) | yes (assertion) | auto-tier only; the `buildAgentQueryOptions` assertion pins it |
| `allowedTools: []` in `pdf-chapter-router` | not applicable | empty, direct SDK call, no platform tools |
| Inngest cron CLI `--allowedTools` | not applicable | built-in tools only; no `mcp__soleur_platform__*` |
| settings-file `permissions.allow` | not applicable | `settingSources: []` |
| `permissionMode` | not applicable | `"default"` (`bypassPermissions` would also print a shadow warning) |
| PreToolUse hook `allow` | not applicable | sandbox hook matcher excludes `mcp__` names; tool-attempt hook is observe-only and cc-only |
| Plugin skill / agent frontmatter `allowed-tools` | yes (sentinel) | grep today finds no `mcp__soleur_platform__` entry in `plugins/soleur/skills/*/SKILL.md` or `plugins/soleur/agents/**`; a one-assertion sentinel in the census suite keeps it that way |
| Resumed session (`resume:`) and Task subagents | not applicable | `allow(toolInput)` returns no `updatedPermissions`; no SDK `agents:` option is set; subagent calls reach `canUseTool` with `agentID` (covered by a test) |
| Server-level or wildcard entry (`mcp__soleur_platform`, `mcp__*`) | yes | the `buildAgentQueryOptions` assertion matches these forms, not only the `__`-prefixed FQN |
| Plugin MCP wildcards `mcp__plugin_soleur_*__*` | deliberately not | third-party plugin servers declared in `plugin.json`, allowed by design (`canUseTool` also allows them) |

Write-site sweep (`hr-write-boundary-sentinel-sweep-all-write-sites`): `rg -n "allowedTools" apps/web-platform/server apps/web-platform/scripts` at work time; the choke point is `buildAgentQueryOptions`, and the only other writers are the probe's deliberate `:raw` override and `pdf-chapter-router` (`[]`).

### Performance / UX

- One extra review card per gated call in legacy chats; gating was always the intended behaviour. 5-minute timeout is existing behaviour, unchanged. Read-only tools do not prompt (P2).
- The static deny text is read by the model and relayed to the user.

### Risks

- **String-prompt reachability (gate Phase 0, before any build):** if a probe row with the production string prompt shows `canUseTool` is NOT invoked, removing names from `allowedTools` would hard-deny gated tools instead of gating them. Read evidence (`sdk.mjs` `CA()` writes a string prompt over stdin and sets `--permission-prompt-tool stdio` whenever `canUseTool` is set) says it is reachable, but it is measured in Phase 0.4 (one paid call) before commits 1 and 2 are built; on `invoked=no` stop and re-plan, do not merge.
- **Abort and status race:** decided in Proposed Solution 4 (platform gate skips the `active` restore when the session controller is aborted). Covered by tests for both abort reasons (user Stop, disconnect grace).
- **Disconnect during a gate dies at about 30 s** (`DISCONNECT_GRACE_MS`), not 5 minutes; the CPO's offline-user risk is therefore sharper than stated. Fail-closed is still correct; the dead-end UX is a #11289 design item.
- **Plugin MCP wildcards stay pre-approved.** `canUseTool` also allows plugin MCP tools without a card (explicit server-name match), so the wildcard is not a bypass of an existing gate; it is the designed absence of one. The declared plugin servers (context7, cloudflare, vercel, stripe, as listed under `mcpServers` in `plugins/soleur/.claude-plugin/plugin.json`) include write-capable third-party tools. This is residual risk outside this fix, acknowledged in the PR body; no change here (CTO ruling).
- **Sibling branch churn:** PR #11289 (`feat-hitl-approval-queue`) carries `0acc541b6f` and likely touches `permission-callback.ts` and the allowedTools-presence tests. After this merges, its rebase will hit an add/add conflict on the probe file (git only drops a commit with an identical patch) and textual conflicts in the flipped tests; the resolution is to take main's version of the probe. Post one PR comment on #11289 at ship naming this (no new issue). If `origin/feat-hitl-approval-queue` is force-pushed or the SHA is unreachable, fall back to `git show origin/feat-hitl-approval-queue:apps/web-platform/scripts/dev-probe-approval-gate.ts` and keep the original author line (`git log -1 --format='%an <%ae>' 0acc541b6f` while it resolves). The author is the same CLA-signed user as this branch.
- **Model compliance:** the probe needs the model to attempt the tool; "did not attempt" is CANT-RUN, never PASS.
- **Rolling deploy / two hosts:** sessions are instance-local with sticky placement (ws-handler cites ADR-068/124 "replicas=1 today"), so the bypass stays live for users pinned to a host until it runs the new image. The post-deploy step waits for both hosts and records each host's deploy time; reconcile the host count against `apps/web-platform/infra` before relying on "two hosts".
- **Card emission is not observable post-deploy** (pino is not shipped to Better Stack); the pre-merge probe and the unit suite are the evidence that a card appears. Stated in the PR body rather than papered over.
- **Rollback:** if post-deploy evidence shows gated tools hard-deny (no card) the fix is wrong for the real prompt shape; revert commit 2 only after the CTO rules, because reverting reopens the bypass. If a gated name is still pre-approved, the image is stale or a tool lacks a tier entry: check the deployed tag against the merge commit, add the entry, redeploy.

## User-Brand Impact

- **If this lands broken, the user experiences:** `email_send`, `github_push_branch` or `kb_share_create` still run with no card (on any web host not yet redeployed, or if a tool lacks a tier entry); or the card never renders and the call is denied, leaving `conversation.status` at `waiting_for_user` until the 2-hour inactivity timer completes it (resumable meanwhile); or the card renders attacker-shaped text (markdown, newlines, an unbounded title) so the user approves something other than what runs. Rolling-deploy window: sessions are instance-local, so a user pinned to the not-yet-updated host stays unprotected until that host is on the new image; both hosts must be on the merge-commit image before the post-deploy check counts.
- **If this leaks, the user's workflow and third-party recipients are exposed via:** a prompt-injected agent (inbound email body, GitHub issue/PR text, CRM note content) calling `email_send` to an arbitrary recipient, `github_push_branch` / `create_pull_request` / `github_trigger_workflow` against the connected repo, `kb_share_create` (public URL for a KB document), or `workspace_set_autonomous` (switching off approvals on a code-executing surface), with no human approval.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one prompt-injected outbound email, push or public share from one user's workspace is brand-defining on its own, so this is not an aggregate-pattern risk.

Consent fatigue (accepted by the CPO): the `crm_*` and `workstream_issue_*` cards appear in legacy chat for the first time; reflexive Approve clicks weaken the gate, which is a #11289 design item, not a reason to leave the bypass. A late click on an expired card must say the action was not performed (Phase 0.5 asserts the wording of the ws-handler error), because no client frame marks a gate expired today.

**Scoped out, named (not silent).** Reconnect replay of an unresolved `review_gate` frame; `email_reply` sender lookup on the card; a `toolUseID`-keyed body-hash binding; a full non-MCP `allowedTools` allowlist; `nonInteractive` for Bash gates in headless sync; serialising the hold and restore writes per session; a per-Query closed flag instead of the sticky controller-abort skip (cc path); `failed` finalizers with active-only guards leaving a parked `waiting_for_user` row, and the AskUserQuestion / destroy-gate status writers bypassing `pendingGates` and the compare-and-set (pre-existing); Approve resolved, restore write in flight, then disconnect: the active-only abort finalize is a no-op against the still-waiting_for_user row and the restore then lands, leaving the row `active` with no session until the 5-minute stuck-active reaper corrects it (one DB round-trip window; same shape as AskUserQuestion). Accepted by CTO ruling; The destroy-ask Bash lane and AskUserQuestion have no post-hold abort recheck (pre-existing, #11289 follow-up); one shared `tool-tiers` `vi.mock` factory across the eight test files that mock it; consent fatigue; other-field cards print "not shown" notes. **The PR's honest limit:** "Approve" binds to `allow(toolInput)`, because the SDK passes the same object to `canUseTool` and then to the handler (probe-covered); there is no `toolUseID`-keyed binding of the reviewed body to the executed one.

CPO sign-off: **conditional approve** (Domain Review). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: "Regression guard, not a heartbeat: the census CI suite plus the buildAgentQueryOptions fail-closed assertion (a non-auto platform tool in allowedTools throws at session start, so a regression is a loud failed session rather than a silent bypass). Production corroboration: SDK CAN_USE_TOOL_SHADOWED warnings in Better Stack list the names still pre-approved; after the fix they list only auto-approve names"
  cadence: "every CI run; every legacy/cc session start; SDK warning once per legacy session"
  alert_target: "CI red on the PR; session-start throw surfaces through the existing startAgentSession error path to Sentry; post-deploy absence assertion fails the ship/postmerge check"
  configured_in: "apps/web-platform/server/tool-tiers.ts (buildAllowedTools), apps/web-platform/server/agent-runner-query-options.ts (assertion), apps/web-platform/test/build-allowed-tools-census.test.ts"

error_reporting:
  destination: "Sentry via warnSilentFallback in apps/web-platform/server/observability.ts (feature cc-permissions)"
  fail_loud: "gate status-write failures emit ops platform-gate-status-hold and platform-gate-status-restore, each with its own static message; gate expiry is log.warn sec:true decision platform-gate-expired (timeout) or platform-gate-aborted (abort), with delivered, conversationId and reason, by design no Sentry (warn is the level that reaches Better Stack); a card the input cannot be shown in full for, a non-interactive session and more than 5 pending cards each log their own static warn decision; assertion failure throws with the offending entry"

failure_modes:
  - mode: "a gated or default-gated platform tool re-enters allowedTools (new tool, tier flip, new runner)"
    detection: "census CI test (compares TOOL_TIER_MAP to a hand-written full tier table, fails on any non-auto tool in the output, on an empty census, and on a platform name with no explicit tier entry) plus the query-options assertion at session start. Runtime layer 2 (pino to Sentry): the assertion throws inside startAgentSession and the startAgentSession catch reports it through reportSilentFallback"
    alert_route: "CI red; Sentry session error (layer 2)"
  - mode: "gate expires or is aborted and canUseTool throws or strands the conversation status"
    detection: "permission-callback-platform-gate-expiry unit suite; a log.warn row decision platform-gate-expired or platform-gate-aborted shipped to Better Stack (log shipper forwards level 40 and above); Sentry warn events on status-write failure (pino-to-Sentry mirror via warnSilentFallback)"
    alert_route: "CI red; Better Stack row and Sentry platform-gate-status-* ops are triage-only, no pager rule (stated, not implied)"
  - mode: "canUseTool unreachable for the legacy string-prompt shape, so gated tools are denied silently"
    detection: "no runtime layer; probe-only: the pre-merge string-prompt probe row (invoked=yes expected). The post-deploy SHADOWED channel only shows a legacy session ran, not that canUseTool is reached"
    alert_route: "merge blocked on the probe result"
  - mode: "fix not live in production (stale image) or an unlisted gated name remains pre-approved"
    detection: "betterstack-assert-absence.sh over SHADOWED rows on both web hosts (host_name soleur-web-platform for web-1 and soleur-web-2 for web-2, per apps/web-platform/infra/betterstack-logs-alerts.tf; confirm at work time) with a positive control. The SDK stderr to container journald to Better Stack channel is UNPROVEN until Phase 0.6 finds a real CAN_USE_TOOL_SHADOWED row; if none exists the check is recorded as unobservable"
    alert_route: "postmerge verification fails; recorded on the PR and #11303"
  - mode: "a gated-tool call is denied or hangs with no card (canUseTool unreachable, resolver race)"
    detection: "no runtime signal that the SDK never invoked canUseTool or that a gate opened (neither is logged). What is observable: the offline-notification error log (\"Offline notification failed (tool gate)\") when the user is not connected, and the 5-minute expiry warn row (decision platform-gate-expired, delivered true or false) when a card went unanswered; the pre-merge probe and the unit suite cover the rest"
    alert_route: "merge blocked on the probe result; expiry and notification-failure rows are triage-only"

logs:
  where: "pino stdout in the web container (not shipped to Better Stack, per the issue's evidence limits); SDK CLI stderr warnings (CAN_USE_TOOL_SHADOWED) in Better Stack scoped by host_name; Sentry for the warn ops"
  retention: "per the Better Stack source retention setting and Sentry project retention; unchanged by this PR"

scoped_out:
  - "Not observable and not built here: reconnect replay of review_gate, email_reply sender lookup on the card, toolUseID-keyed body-hash binding, a full non-MCP allowedTools allowlist, nonInteractive for Bash gates, per-session serialisation of hold/restore writes, a per-Query closed flag (cc path), active-only `failed` finalizers leaving a parked row and the AskUserQuestion / destroy-gate writers bypassing pendingGates (pre-existing). Hold and restore writes report under distinct ops (updateConversationStatusGateHold / updateConversationStatusGateRestore) so one Sentry dedup window cannot hide the other."

discoverability_test:
  command: bash scripts/betterstack-assert-absence.sh --host soleur-web-platform --absence mcp__soleur_platform__email_send --absence mcp__soleur_platform__github_push_branch --absence-require CAN_USE_TOOL_SHADOWED --control mcp__soleur_platform__narrate --control-require-field source_kind=app_container --since 7d
  expected_output: outcome=clean
  credentials_required: "Better Stack ClickHouse read credentials (BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD, run under doppler prd_terraform) — production log content has no unauthenticated substitute; without them the script exits 3 (unknown), which is why Check 10 skips this probe as declared"
```

Post-deploy honesty: the issue records no legacy sessions with platform tools since 2026-09-30, so the positive control can legitimately return zero rows (`unshipping`, exit 2). That outcome is recorded as **"unobserved: no legacy session with platform tools in the window"** (the script's exit 2, `unshipping`), never as clean; correctness evidence is then the real-SDK probe plus the census. No soak-gated close is enrolled (the check is a point-in-time deploy verification, not a time-gated closure).

## Architecture Decision (ADR/C4)

### ADR

Create a new ADR via `soleur:architecture create` at work time (ordinal chosen then: highest on disk today is ADR-303, so provisional ADR-304; moved to ADR-305 at work time because two open PRs (#11298, #11225) already claim 304; re-verify against `origin/main` before merge per the ADR-ordinal collision gate and sweep this plan and `tasks.md` for the old ordinal if it moves): **"Gated-tier platform tools never enter SDK `allowedTools`; `canUseTool` is their only approver."** It records the invariant (a cross-cutting rule every runner and future caller must honour), the `getToolTier(name) === "auto-approve"` keep-rule, the fail-closed second line in `buildAgentQueryOptions`, the explicit-entry rule for `platformToolNames`, and `related_adrs: [ADR-060, ADR-109, ADR-284]`. It reverses the earlier implicit design in which `allowedTools` listed every registered platform tool. Status `accepted` (the decision is live in this PR). It is a plan deliverable, not a deferred issue.

### C4 views

No C4 impact. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4` under `knowledge-base/engineering/architecture/diagrams/`) for the feature's external actors, systems, stores and access relationships: the Founder/Operator actor (approves the gate), the Inbound Correspondent actor and Resend system (email path, unchanged), GitHub and Plausible systems (tool targets, unchanged), the Web Push Services system (offline gate notification, unchanged), the Beta-CRM and Operational Inbox stores (unchanged), and the `api` container description (lists SDK `options.hooks`, makes no `allowedTools` or tier claim). The change alters no actor, system, container, store, or relationship, and no element description it makes false. Work phase re-runs `plugins/soleur/test/c4-count-parity.test.sh` and expects green (no derived cardinality moves).

### Sequencing

The ADR describes the live state; it lands in this PR (commit 4). It also records the meaning of `auto-approve`: read-only, or a hard-scoped reversible write with its justification in `TOOL_TIER_MAP` (`edit_c4_diagram` is the one existing write-shaped entry, scoped to `engineering/architecture/diagrams/`; it is not in the legacy name set and not in `CC_PATH_ALLOWED_TOOLS` today).

## Guard Contract

### Guard 1 — allowedTools gated-exclusion census

**Property.** No platform tool whose effective tier (`getToolTier`) is not `auto-approve` appears in the `allowedTools` handed to the Agent SDK by any runner.

**Assembly.** The chokepoints, more than one: (a) `buildAllowedTools` and its single call site, the `allowedToolsList` expression feeding `allowedTools:` in `startAgentSession` (`agent-runner.ts`); (b) the `opts.allowedTools = args.allowedTools` assignment in `buildAgentQueryOptions`, which both real runners flow through (legacy `agent-runner.ts`, cc `cc-dispatcher.ts` with `CC_PATH_ALLOWED_TOOLS`); (c) the probe, which composes options through the same builder and overrides directly only for its `:raw` canary. The universe the property quantifies over is not a typed list: it is `TOOL_TIER_MAP` gated entries, plus every name in `platformToolNames`, derived from the real builders' `toolNames` (github, plausible, account, routines, workstream, workspace-settings) and the tool names of the kb-share, email-triage, inbox, auth-status, conversations and crm builders, plus the registered tool names read from the `soleur_platform` MCP server of a booted `startAgentSession` (repo connected, Plausible key present, so the inline-literal pushes are included without a brittle source scan), each asserted to have an explicit tier entry; plus `CC_PATH_ALLOWED_TOOLS` run through `buildAgentQueryOptions` for the cc chokepoint; plus plugin skill and agent frontmatter (sentinel: none names `mcp__soleur_platform__`). Other `allowedTools` writers swept at work time: `pdf-chapter-router` (`[]`), Inngest CLI args (built-ins only).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Make the filter keep one gated tool (e.g. special-case `email_send`) | RED: census reports `email_send` in the output |
| 2 | Empty census / vacuous filter: the derivation yields zero gated names, or the filter returns `[]` (also covers "drops the plugin wildcard" and "inverted predicate" because the floor requires at least one auto-approve tool and the wildcard in the output) | RED: floor assertions (census size at or above the pinned minimum, pinned must-stay-gated set present, at least one auto-approve tool and the plugin wildcard present) |
| 3 | Add an unclassified second tool after a compliant first: append `mcp__soleur_platform__new_write_tool` (no tier entry) after an auto-approve name | RED: a filter keyed on `TOOL_TIER_MAP[n] === "gated"` (explicit-only) keeps it; the real filter drops it; and the registered-name explicit-entry assertion fails for a booted tool without an entry |
| 4 | Revert the `agent-runner.ts` call site to the raw `[...platformToolNames, ...wildcards]` | RED: the `startAgentSession` wiring test finds a registered non-auto tool in `options.allowedTools` |
| 5 | Remove or narrow the assertion in `buildAgentQueryOptions` (prefix-only or denylist match) | RED: unit cases pass a gated FQN, the bare server name `mcp__soleur_platform`, `mcp__*`, `mcp__soleur_platform__email_send(*)`, a case variant and a whitespace variant, and expect a throw each |
| 6 | Flip a TOOL_TIER_MAP entry (`email_send` to `auto-approve`) in the same diff as the filter | RED against the pinned must-stay-gated set in the test (and the probe's case-table-drift refusal) |

**Harness rows.** (i) Suite edit that must go RED: replace the census oracle (`assertCensus`) with one that always reports "no violations". The battery runs mutants 1, 3 and 4 through the same oracle inside the suite and expects each to be flagged, so an always-green oracle fails the suite. (ii) Must-PASS inputs that are not the canonical: an input list in a shuffled order; a list with duplicate names; a list containing only auto-approve names; plugin server list empty and plugin list with two servers; a non-`soleur_platform` name (`Read`) passed through the builder assertion. **Anchor.** The pinned must-stay-gated set lives in the test (the eight probed tools); a single diff that edits both the tier map and the test is caught by the real-SDK probe's `case-table-drift` refusal (it asserts the eight are `gated` before spending money), by the required `soleur:engineering:review:user-impact-reviewer` pass, and by the CPO condition that the PR body states the behaviour change. There is no external registry; adding one is out of scope.

### Guard 2 — gated platform-tool gate lifecycle

**Property.** For every gated platform-tool invocation, `canUseTool` returns a verdict (never throws), the verdict is deny unless the selection is exactly `Approve`, and the conversation status follows the one rule in Proposed Solution 4 (restore to `active` only when the last pending gate resolves, the controller is not aborted, and the row is still `waiting_for_user`), observed both at function return and during the wait.

**Assembly.** Every exit of the gated branch: approve, any non-approve selection, gate rejection by timeout, gate rejection by abort, `updateConversationStatus` failing on hold, failing on restore, and two concurrent gated calls (plus a gated call concurrent with a Bash gate, since they share the `pendingGates` counter). One code path: `holdForUser`, now shared by the Bash gates and the platform gate; the `gateClass` argument only selects Sentry op labels.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `catch` in `holdForUser` (or in the gated branch) so a rejection escapes | RED: timeout test expects a deny result, not a rejection |
| 2 | Restore status only on the success path (move the restore out of `finally`) | RED: after a timeout the recorded statuses lack the final `active` |
| 3 | REORDER: flip status to `active` immediately after `waiting_for_user`, before the gate resolves | RED: the in-window case reads the status while the gate promise is pending and expects `waiting_for_user` (a return-time-only assertion cannot see this) |
| 4 | Make `null` fall through to allow | RED: timeout and abort tests expect deny |
| 5 | Second concurrent gated call: first resolves while second pending | RED if status flips to `active` early (pending-counter test) |
| 6 | Status write throws on hold or restore | RED if the throw replaces the verdict; GREEN requires the verdict preserved and a `warnSilentFallback` with the `platform-gate-status-*` op and its static message (this row also catches the gate-class label being dropped) |
| 7 | Restore `active` even when the session controller is aborted (either class) | RED: the abort case asserts no `active` write after `controllerSignal.aborted`, for both abort reasons |
| 8 | Drop the compare-and-set guard on the restore | RED: a concurrent `completed` is overwritten |
| 9 | Widen the abort-branch finalize to also accept `waiting_for_user` (#3463 regression) | RED: the disconnect-after-result race test (a row already `waiting_for_user` must not become `failed`) and the gate-expiry ordering tests |
| 10 | Approve honoured after abort: drop the post-hold abort recheck | RED: abort during the awaited restore write, a per-call abort and a controller abort each expect a deny |

**Harness rows.** Suite edit that must go RED: change the timeout-case stub to resolve `"Approve"` instead of rejecting; the case's precondition assertion (the stub was called and rejected) fails. Must-PASS non-canonical inputs: a gated tool outside the probed eight (`crm_note_append`, `workstream_issue_close`), an `AbortError`-shaped rejection and a plain `Error("timeout")` rejection, and a rejection after an already-aborted signal. **Anchor.** Not a stored-value comparison; the guard compares behaviour, so no anchor applies beyond the observation-inside-the-window row (3).

### Guard 3 — real-SDK probe cannot pass vacuously

**Property.** The probe reports PASS only if it observed, in one run, both that the production composition (`buildAllowedTools` output, production string-prompt shape) makes `canUseTool` fire and deny for each of the eight gated tools, and that the raw (unfiltered) composition still bypasses it.

**Assembly.** The probe's case table (eight `:prod` rows, one `email_send:raw` canary, one `email_send:prod-stream` diagnostic that differs from `:prod` only in using a streaming-input prompt), its verdict function, its exit-code mapping (0 PASS, 1 FAIL, 3 CANT-RUN, 4 DIAGNOSTIC), and its pre-spend checks (`refuses-prd`, `no-anthropic-key`, `case-table-drift`, case-count floor). The pre-spend checks and `PROBE_ONLY` handling are inherited from the cherry-picked probe and are not re-tested; only what this change adds is in the matrix.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `:prod` input bypasses `buildAllowedTools` (raw list) | FAIL (BYPASS on `:prod` rows) |
| 2 | Model never attempts the tool | CANT-RUN `model-did-not-attempt-tool`, never PASS |
| 3 | `:raw` canary row shows `invoked=yes` (SDK semantics changed or the probe is vacuous) | FAIL, loud non-zero exit |
| 4 | The legacy-name derivation (`registration()`) fails an import | CANT-RUN, never a silent fall back to the eight FQNs |

**Harness rows.** The probe is paid and model-dependent, so its matrix is exercised by edit-and-run at work time for rows 1 and 3 (one paid call each, `PROBE_ONLY`), and by reading the verdict function for rows 2 and 4. Must-PASS input differing from canonical: the `:prod` rows run with the production string prompt, while the diagnostic row uses a streaming prompt. **Anchor.** The `:raw` canary is the externally-anchored row: it ties the probe to the SDK's actual current behaviour independent of any repo edit.

## Mutation Evidence (recorded in fix-rounds 1 and 2)

Each row was applied in an allocated sandbox copy (never the live tree), after a green control of the same test files, with the edit asserted to have landed; the sandbox was removed afterwards. "Red" means the named tests failed with the mutation and passed without it.

**Round 2 (new guards):**

| Guard | Mutation | Landed | Test that reds |
|---|---|---|---|
| Abort finalize active-only | widen `ACTIVE_STATUSES_FOR_FINALIZE` to include `waiting_for_user` | yes | `agent-runner-disconnect-after-result-race` (row stays `waiting_for_user`, no applied `failed` write), gate-expiry ordering tests: 6 red |
| Post-hold abort recheck | remove the `signal.aborted \|\| controllerSignal.aborted` recheck after the restore write | yes | gate-expiry "an Approve is never honoured after the session aborted": 5 red |
| Restore skip on abort | remove `!ctx.controllerSignal.aborted` from the restore condition | yes | gate-expiry abort-first / gate-first / user-Stop / stacked rows: 9 red (the earlier rows stayed green because the failed row blocked the CAS; the new rows keep the row at `waiting_for_user`) |
| Recipient ASCII-only | remove the `CARD_ADDR_ASCII_RE` check | yes | `tool-tiers` non-ASCII local part, IDN domain, NBSP rows: 4 red |
| Recipient trim equality | remove `raw !== raw.trim()` | yes | leading / trailing whitespace, trailing newline rows (to, reply-to, suppress): 5 red |
| `endsWith(">")` | remove the guard | yes | "trailing text after the closing bracket" rows: 3 red |
| Display name revealed | `revealHidden(p.name, true)` replaced by the raw name | yes | hostile display name on a valid recipient: 1 red |
| Suppress reason | `cardField(reason)` replaced by `String(reason)` | yes | hostile suppress reason row: 1 red |
| Hidden-character class | drop U+3164, U+2800, U+034F (and its neighbours), narrow U+2060-206F, drop U+E0100-E01EF | yes (5 mutants) | per-code-point body, subject, recipient and plain-card rows: 2 to 4 red each |
| `[U+` escape | remove the literal `[U+` rewrite | yes | forged-marker row: 1 red |
| Exact quoting | subject back to the `"` to `'` rewrite | yes | quote-bearing subject / display name row: 1 red |
| zod caps | body cap +1; recipient cap removed; reply-to cap removed | yes (3) | `outbound-tools` schema cap rows: 1 red each |
| Card UI | drop `whitespace-pre-wrap`; drop `[overflow-wrap:anywhere]`; aria-label back to the question | yes (3) | `review-gate-card-layout`: 2, 1 and 2 red |
| `findOffenders` | never flags; skips bare wildcards | yes (2) | census known-positive control: 1 red each |
| Bash family grammar | regex without `\s*` before the paren | yes | `Bash (npm *)` and tab rows: 2 red |
| Pending-cap deny text | reverted | yes | gate-expiry cap row: 1 red |

**Round 1 guards, re-run in round 2:**

| Guard | Mutation | Landed | Test that reds |
|---|---|---|---|
| Guard 1 row 4 | `allowedToolsList` back to the raw list plus wildcards | yes | census: 47 red (the `buildAgentQueryOptions` assertion throws at session start, so the boot fails loudly) |
| Guard 1 row 1 | filter keeps every platform tool | yes | census: 47 red (same loud failure) |
| Guard 1 row 5 | assertion neutered / `permissionMode` check removed | yes | `agent-runner-query-options`: 21 and 6 red |
| Guard 2 row 1 | gate rejection no longer caught | yes | gate-expiry: 22 red |
| Guard 2 row 8 | restore CAS guard dropped / hold CAS guard dropped | yes | gate-expiry: 3 and 2 red |
| Non-interactive fast deny | removed | yes | gate-expiry: 1 red |
| Pending cap | raised to 50 | yes | gate-expiry: 1 red |
| Fail-closed card | deny ignored (card built anyway) | yes | gate-expiry: 4 red |
| Body cap | card cap +1 | yes | `tool-tiers` and `outbound-tools`: 2 red |

Round-1 panel mutations that had stayed green and drove round 2: dropping `endsWith(">")` (140/140 green), removing the controller-abort restore skip (47/47 green), removing the display-name reveal, the suppress-reason `cardField`, the subject quote rewrite and the CRLF handling. Each now has a row above that reds.

## Implementation Phases

Test-first per `cq-write-failing-tests-before`; each commit green on its own; all four land in one PR.

### Phase 0: Setup, baseline and the premise measurement (no commit)

- 0.1 `git fetch origin main origin/feat-hitl-approval-queue`; confirm `origin/main` has no `buildAllowedTools` and no probe file (`git grep` on `origin/main`).
- 0.2 Baseline: `cd apps/web-platform && ./node_modules/.bin/vitest run test/tool-tiers.test.ts test/agent-runner-tools.test.ts test/agent-runner-kb-share-tools.test.ts test/server/email-triage-tools.test.ts test/agent-runner-query-options.test.ts test/canusertool-tiered-gating.test.ts` and `./node_modules/.bin/tsc --noEmit`.
- 0.3 Re-derive the platform tool census from the builders (counts in this plan are plan-time numbers, never hard-coded in tests).
- 0.4 **String-prompt measurement before building anything.** `git cherry-pick -n 0acc541b6f` into the working tree (scratch, not yet committed); make a scratch edit so the prompt is a plain string, as in `startAgentSession`; run `PROBE_ONLY=email_send:no-allowed NODE_ENV=test doppler run -p soleur -c ci -- bun run apps/web-platform/scripts/dev-probe-approval-gate.ts` (one paid call; never `prd`). Expect `invoked=yes`. If `invoked=no`, stop and re-plan (Risks). Also capture the printed `CAN_USE_TOOL_SHADOWED` line to see whether it names auto-approve entries (decides the post-deploy positive control).
- 0.6 **Prove the post-deploy channel before designing around it.** With the read-only Better Stack query script (`scripts/betterstack-query.sh`, credentials via Doppler `prd_terraform`), look for any historical `CAN_USE_TOOL_SHADOWED` row (the issue says 30 days of them exist) and record its `host_name`, its journald fields (which one discriminates the web container, for `--control-require-field`), and whether it lists auto-approve names. Confirm the host names against `apps/web-platform/infra/betterstack-logs-alerts.tf` (web-1 rows carry `host_name='soleur-web-platform'`, web-2 `soleur-web-2`). No row found = the post-deploy check is recorded as unobservable up front and the PR says so.
- 0.5 Grep-confirm the late-click behaviour in `ws-handler.ts` (`review_gate_response` for an unknown or expired gate) and `rg -n "User rejected the action"` across tests.

### Phase 1: Gate lifecycle (commit 1, own commit with its test)

- 1.1 RED: `apps/web-platform/test/permission-callback-platform-gate-expiry.test.ts`, modelled on `permission-callback-bash-gate-expiry.test.ts`: timeout rejection, abort-shaped rejection with the session controller aborted (no `active` write; both abort reasons), a per-call abort with the session alive (restore), approve, reject, status-write failure on hold and on restore (verdict preserved, op labels and static messages asserted), two concurrent gated calls (single `waiting_for_user`, single `active`), a gated call stacked with a Bash gate, a gated call with `options.agentID` set, a Bash-class regression case (Bash abort behaviour unchanged), and the in-window observation (status read while the gate promise is pending).
- 1.2 GREEN: `holdForUser` options object with `gateClass`; the gated branch uses it; static deny texts; `Platform tool gated` log lines unchanged for approve/reject.
- Commit: `fix(security): gated platform-tool gate fails closed on expiry and restores status (#11303)`.

### Phase 2: The filter (commit 2)

- 2.1 RED: `apps/web-platform/test/build-allowed-tools-census.test.ts`: the unit census over `buildAllowedTools` (counts derived, floors pinned), the in-suite mutation battery as mutant implementations run through one `assertCensus` oracle (mutants: keep a gated tool; empty; explicit-only key; inverted), the explicit-entry assertion over registered tool names of a booted session, the `buildAgentQueryOptions` assertion cases (gated FQN, bare server name, `mcp__*`, wildcard; passes `Read`, plugin wildcards, `narrate`, `summarize`, and the real `CC_PATH_ALLOWED_TOOLS` with the support filter), the skills/agents frontmatter sentinel, the gate-message tests (no gated tool has the generic default message; every card text is length-bounded and free of raw newlines, markdown controls and bidi characters under hostile input; the email preview carries the `[+N more characters not shown, total M]` marker; no offline message contains any tool-input value), a sentinel that no platform tool definition passes `annotations`, and the extra census cases from test-design review: an empty result (`[]` and an omitted `allowedTools` key behave identically in the SDK options), `blocked`-tier names, unknown-prefix FQNs, an empty suffix (`mcp__soleur_platform__`), case variants, rule-content forms (`...email_send(*)`), source-array non-mutation, an injected unclassified platform name in the real `CC_PATH_ALLOWED_TOOLS` that must fail, the `startAgentSession` result passed to `query()` by equality with `buildAllowedTools(...)` (kills the call-site revert), a distinctness test over all `platform-*` and `bash-*` status-op messages, and an assertion that Plausible tools actually registered in the booted session (the harness mocks `service-tools`, so the explicit-entry check must not pass vacuously). Floors are derived from a pinned auto-approve name set, not a bare count. Flip the existing tests that encode the defect (`agent-runner-tools.test.ts`, `agent-runner-kb-share-tools.test.ts`, `email-triage-tools.test.ts`); switch the three `allowedTools: ["mcp__soleur_platform__kb_share_create"]` verbatim-wiring sites in `agent-runner-query-options.test.ts` (221, 498) and `agent-runner-helpers.test.ts` (422) to `kb_share_list`; add the `startAgentSession` wiring test (non-empty, contains at least one auto-approve tool and the plugin wildcard, no registered tool whose tier is not `auto-approve`, `canUseTool` still receives the unfiltered list).
- 2.2 GREEN: `buildAllowedTools`, explicit tier entries, the card-field helper, the six new gate-message cases and the content-free `buildOfflineGateMessage` in `tool-tiers.ts`; call site in `agent-runner.ts`; assertion in `agent-runner-query-options.ts`; refresh comments (`tool-tiers.ts` NOTE with its stale line reference, `CC_ROUTER_TIER3_DENYLIST` text, `agent-runner-query-options.ts` allowedTools doc line).
- 2.3 Run the production-code mutation rows (Guard 1 rows 1, 4, 5, 6) by editing and reverting with `git checkout -- <file>` (never `git stash`); record RED evidence for those rows only in the PR body (the in-suite battery rows are self-evidencing).
- Commit: `fix(security): stop pre-approving gated platform tools via allowedTools (#11303)`.

### Phase 3: Real-SDK probe (commit 3)

- 3.1 Keep only `apps/web-platform/scripts/dev-probe-approval-gate.ts` from the cherry-pick; delete `knowledge-base/project/specs/feat-hitl-approval-queue/phase-0-measurements.md` (left out of this PR).
- 3.2 Modify the probe per Guard 3: import `buildAllowedTools`; `:prod` input is the full legacy name set derived by the existing `registration()` plus a plugin wildcard server, filtered through `buildAllowedTools`, with the target FQN asserted absent; a failed builder import is CANT-RUN (no silent fall back to the eight FQNs); delete the `:no-allowed` rows (redundant once `:prod` is the filtered list); all rows use the production string prompt; add `email_send:raw` (unfiltered list, direct override after the builder, expects BYPASS) and `email_send:prod-stream` (streaming prompt, expects `invoked=yes`); update the header (10-case table, PASS semantics, corrected prompt-shape note, model-compliance caveat, and the `pyramid-justified: only the real SDK can show the permission-chain order, mocks cannot` marker; exit 4 DIAGNOSTIC is never treated as green by any caller); case-count floor to the new total. Correct the same stale claim in `scripts/dev-probe-destroy-ask.ts` (comment only) if Phase 0.4 contradicts it.
- 3.3 Run against Doppler `ci`: `NODE_ENV=test doppler run -p soleur -c ci -- bun run apps/web-platform/scripts/dev-probe-approval-gate.ts`. Expect `RESULT: PASS`, eight `:prod` rows `invoked=yes` with deny honoured, the canary `invoked=no verdict=BYPASS`. Paste `PROVENANCE`, `REGISTRATION` and `PROBE` lines into the PR body.
- Commit: `test(approval): real-SDK probe builds allowedTools via buildAllowedTools; prod rows now invoke canUseTool (#11303)`.

### Phase 4: ADR and docs (commit 4)

- 4.1 `soleur:architecture create` for the ADR (see above); run `plugins/soleur/test/c4-count-parity.test.sh`.
- 4.2 No published legal text, no `compliance-posture.md`, no register edits in this PR (CLO ruling).
- Commit: `docs(adr): gated-tier platform tools never enter SDK allowedTools`.

### Phase 5: Verification before ship

- `./node_modules/.bin/tsc --noEmit`, `./node_modules/.bin/vitest run` on the touched and new suites, `npx eslint` on touched files, markdown lint on the ADR, `python3 scripts/lint-guard-contract.py` on this plan.

## Files to Edit

- `apps/web-platform/server/tool-tiers.ts`: `buildAllowedTools`; `conversations_lookup` auto; explicit gated entries for `plausible_*`, `account_*`; six new `buildGateMessage` cases (`workspace_set_autonomous`, `account_*`, `plausible_*`); comments
- `apps/web-platform/server/agent-runner.ts`: `allowedToolsList` call site
- `apps/web-platform/server/agent-runner-query-options.ts`: fail-closed assertion at `opts.allowedTools`; doc line
- `apps/web-platform/server/permission-callback.ts`: `holdForUser` options object and `gateClass`; gated branch; abort restore policy; deny texts
- `apps/web-platform/test/tool-tiers.test.ts`: explicit tiers, `conversations_lookup`, gate-message cases
- `apps/web-platform/test/agent-runner-tools.test.ts`: flip presence assertions to absence; keep wildcard assertions
- `apps/web-platform/test/agent-runner-kb-share-tools.test.ts`: create/revoke absent, list present
- `apps/web-platform/test/server/email-triage-tools.test.ts`: reads present, writes absent (rename the test)
- `apps/web-platform/test/agent-runner-query-options.test.ts`: verbatim-wiring cases use `kb_share_list`; new assertion tests
- `apps/web-platform/test/agent-runner-helpers.test.ts`: `kb_share_list` in the shared-shape case
- `apps/web-platform/test/canusertool-tiered-gating.test.ts`: only if the call-order assertions need it
- `apps/web-platform/scripts/dev-probe-destroy-ask.ts`: comment only, conditional on Phase 0.4

## Files to Create

- `apps/web-platform/test/build-allowed-tools-census.test.ts`: census, mutation battery, explicit-entry assertion, assertion tests, sentinel, gate-message test
- `apps/web-platform/test/permission-callback-platform-gate-expiry.test.ts`: gate lifecycle suite
- `apps/web-platform/scripts/dev-probe-approval-gate.ts`: cherry-picked and modified probe
- `knowledge-base/engineering/architecture/decisions/ADR-305-gated-tier-platform-tools-never-enter-sdk-allowedtools.md`: ordinal provisional

Globs verified at plan time (`git ls-files`): every `apps/web-platform/test/*.test.ts` path above exists except the two new files; `scripts/betterstack-assert-absence.sh` exists.

## Open Code-Review Overlap

- #3242 (`agent-runner.ts`: tool_use WS event lacks raw name field). **Acknowledge:** different concern (client event shape); it stays open.
- #3454 (`agent-runner-tools.test.ts`: expose `pdf_metadata` as an agent-callable MCP tool). **Acknowledge:** a new tool would land under the new census (explicit tier entry required) but is a separate feature; it stays open.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "ship an UNCONDITIONAL fix, no flag" [brief] | Proposed Solution 1; no flag anywhere | mapped |
| 2 | "add a pure `buildAllowedTools` used by the legacy runner at the `allowedToolsList` site in apps/web-platform/server/agent-runner.ts that drops every `gated`-tier and unknown/default-gated platform tool from allowedTools, keeping auto-tier tools and plugin MCP wildcards" [brief] | Phase 2; Files to Edit `tool-tiers.ts`, `agent-runner.ts` | mapped |
| 3 | "bash_autonomous stays Bash-only and must NOT be extended to platform tools; workspace_set_autonomous stays gated" [brief] | Proposed Solution 1 (no change), Guard 1 row 6 | mapped |
| 4 | "classify `conversations_lookup` (and any other tool without a tier entry) as auto-approve only after confirming its handler is read-only, otherwise leave it gated" [brief] | Proposed Solution 3; Repo findings | mapped |
| 5 | "a unit census over TOOL_TIER_MAP gated entries plus default-gated platformToolNames against the output of buildAllowedTools, with a mutation battery (drop a gated tool from the filter; empty census; add an unclassified gated tool)" [brief] | Phase 2.1; Guard 1 rows 1-3 | mapped |
| 6 | "the real-SDK probe ... (cherry-pick that commit ...) and must be switched to build allowedTools via buildAllowedTools so its prod rows turn to invoked=yes; run it against the dev/ci Doppler config, never prd" [brief] | Phase 3 | mapped |
| 7 | "fix the gated branch of createCanUseTool ... wrap the abortableReviewGate await in try/finally that returns a static deny on timeout or abort and always restores conversation status, as its own commit with a test" [brief] | Phase 1 (via `holdForUser`) | mapped |
| 8 | "do NOT edit published legal text in this PR" [brief] | Phase 4.2 | mapped |
| 9 | "Post-deploy: confirm via scripts/betterstack-assert-absence.sh ... and verify the deploy" [brief] | Observability; Acceptance Criteria (post-merge) | mapped |
| 10 | "PR body: first line answers whether merging this alone changes production behavior (yes: gated tools now prompt), plus a plain one-line changelog note. Closes #11303." [brief] | PR Body Contract | mapped |
| 11 | "Do not flip any flag; new Sentry ops each get their own static message; no extra issues unless a rule requires one." [brief] | No flags; ops `platform-gate-status-hold` / `platform-gate-status-restore` with own messages; Non-Goals | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `tool-tiers.ts` `buildAllowedTools` | "add a pure `buildAllowedTools`" | asked |
| `agent-runner.ts` call site | "used by the legacy runner at the `allowedToolsList` site" | asked |
| Census test + mutation battery | asks 5 | asked |
| Probe cherry-pick and switch | asks 6 | asked |
| `permission-callback.ts` lifecycle (reuse `holdForUser`, `gateClass`) | "wrap the abortableReviewGate await in try/finally that returns a static deny" | asked (CTO ruling: implement via the existing helper) |
| `conversations_lookup` auto entry | "classify `conversations_lookup` ... as auto-approve only after confirming its handler is read-only" | asked |
| Explicit gated entries for `plausible_*`, `account_*` | — | inferred — justification: the census needs "decided" distinguishable from "defaulted" so a new tool fails CI (CTO ruling 3); behaviour unchanged |
| `buildAgentQueryOptions` fail-closed assertion | — | inferred — justification: enforcement contract; without a second line a future caller (cc path, new runner, probe) can reintroduce the bypass (CTO ruling 1) |
| `:raw` canary and the production string-prompt shape for all rows | asks 6 | inferred — justification: a probe whose only rows now pass cannot tell a real fix from a vacuous run (CTO ruling 5; learning 2026-10-11); the string prompt is the shape `startAgentSession` actually uses |
| Flipping existing tests that assert gated names present | asks 2 | inferred — justification: they encode the defect and would fail the contract change |
| ADR | — | inferred — justification: Phase 2.10 gate; a durable cross-runner invariant (CTO ruling 7) |
| "Do not retry unless the user asks" suffix on both deny texts | — | inferred — justification: CPO sign-off condition 1-3 (agent must not retry around the gate) |
| Platform-class Sentry ops | "new Sentry ops each get their own static message" | asked |
| Platform-gate restore skips `active` when the session controller is aborted | — | inferred — justification: safety/enforcement contract; the abort branch writes only against an `active` row, so an unconditional restore can strand a disconnected conversation as `active` (plan review: Kieran, architecture-strategist, spec-flow) |
| Six new `buildGateMessage` cases | — | inferred — justification: the gate becomes reachable for these tools for the first time; a generic "Allow?" card for account deletion or for switching off approvals is not informed consent (single-user-incident threshold; plan review: Kieran) |
| Skill/agent frontmatter sentinel and the bare-server-name/wildcard assertion forms | — | inferred — justification: other pre-approval routes that would silently re-open the same bypass (architecture-strategist, Kieran) |
| Card-text hardening (bounded, neutralised fields; email truncation marker) and content-free offline messages for every gated tool | — | inferred — justification: the fix makes the card the sole control and makes offline push/email egress of tool inputs live for the first time (user-impact review P1, security review P2, privacy notice #8532); without it the fixed gate can be spoofed or leak PR titles and KB paths to stores the notice does not list |
| Allowlist (not denylist) form of the `buildAgentQueryOptions` assertion, plugin-name validation, `bypassPermissions` check | — | inferred — justification: a denylist misses rule-content and case variants (security review P2) |
| `log.warn` for platform-gate expiry and Phase 0.6 channel proof | — | inferred — justification: observability review P1 (the info-level row is not shipped; the SHADOWED channel is unproven) |
| Phase 0.4 string-prompt measurement | asks 6 | inferred — justification: the fix depends on `canUseTool` firing for the legacy string prompt; measuring after commits 1-2 are built is too late (plan review) |

### Split Assessment

- Subsystems touched: 2 (`apps/web-platform`, `knowledge-base`)
- Planned files: 17 | Estimated changed lines: about 750
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (a P1 fix; splitting would leave the gate reachable without its lifecycle fix or the filter without its tests)

## Acceptance Criteria

### Functional (pre-merge)

- [x] `buildAllowedTools` exists in `apps/web-platform/server/tool-tiers.ts` and `startAgentSession` passes its result as `allowedTools` (`rg -n "buildAllowedTools" apps/web-platform/server/agent-runner.ts` shows the call).
- [x] For every name `n` in the legacy `platformToolNames` with `getToolTier(n) !== "auto-approve"` (24 of 46 at plan time; the test derives the counts), `options.allowedTools` does not contain it; every auto-approve name and every `mcp__plugin_soleur_<server>__*` wildcard remains. `createCanUseTool` still receives the unfiltered list.
- [x] `conversations_lookup` is `auto-approve`; `plausible_*` and `account_*` have explicit `gated` entries; every registered `soleur_platform` tool name of a booted legacy session has an explicit `TOOL_TIER_MAP` entry.
- [x] `buildAgentQueryOptions` throws on a gated FQN, the bare `mcp__soleur_platform`, and `mcp__*` / `mcp__soleur*` wildcard entries; passes `Read`, plugin wildcards, `narrate`, `summarize`, and the real `CC_PATH_ALLOWED_TOOLS` with the support filter.
- [ ] No gated tool's `buildGateMessage` equals the generic default; every card text is length-bounded and neutralised under hostile input; the email preview states truncation and total length; the approved-body binding at `server/email-triage/outbound.ts` is cited in the PR body (or the plan stops and escalates).
- [x] `buildOfflineGateMessage` is content-free for every gated tool (no tool-input value in any offline message); no published privacy text is edited.
- [x] `buildAgentQueryOptions` uses the allowlist form (exact auto FQN or validated `mcp__plugin_soleur_<name>__*` only for `mcp__` entries) and rejects `bypassPermissions`.
- [x] Phase 0.6 recorded: whether a real `CAN_USE_TOOL_SHADOWED` row exists in Better Stack, its `host_name` and discriminating field; the post-merge check uses the real host names.
- [x] Gated branch: timeout and abort return the static deny (never throw); status goes `waiting_for_user` then `active` except when the session controller is aborted (no `active` write; both abort reasons tested); parallel gated calls stack; status-write failures keep the verdict and emit `platform-gate-status-hold|restore` with static messages; a call with `options.agentID` behaves identically; Bash-class behaviour is unchanged.
- [x] Both deny messages include "Do not retry unless the user asks." and carry no tool input.
- [x] No plugin skill or agent frontmatter names `mcp__soleur_platform__` (sentinel).
- [x] Phase 0.4 result recorded: with the production string prompt, `canUseTool` is invoked for a gated tool whose name is absent from `allowedTools`.
- [x] Guard 1 production-code rows (1, 4, 5, 6) and Guard 2 rows were observed RED before revert; the in-suite battery passes. `python3 scripts/lint-guard-contract.py` passes on this plan.
- [x] Probe: `NODE_ENV=test doppler run -p soleur -c ci -- bun run apps/web-platform/scripts/dev-probe-approval-gate.ts` prints `RESULT: PASS`: eight `:prod` rows `invoked=yes` with deny honoured, `email_send:raw` `verdict=BYPASS`, `email_send:prod-stream` `invoked=yes`. Provenance and PROBE lines are pasted in the PR body. Never run against `prd`.
- [x] `tsc --noEmit`, the touched vitest suites, eslint, and `plugins/soleur/test/c4-count-parity.test.sh` are green. No published legal text, `compliance-posture.md`, or flag definition is changed (`git diff --stat origin/main`).
- [x] ADR created via `soleur:architecture`, ordinal re-verified against `origin/main` at ship.
- [ ] CPO sign-off conditions met (Domain Review); `soleur:engineering:review:user-impact-reviewer` ran at review.

### PR body contract

- [ ] First line: `Merging this alone changes production behavior: yes, gated platform tools in the legacy agent runner now prompt for approval (review card) instead of running unprompted.` Second line, a plain changelog note: `Fixed: hosted agent chats now ask for approval before sending email, pushing code, opening pull requests, sharing documents, or changing workspace autonomy.` Then: the gate timeout (5 minutes; about 30 s after a disconnect) is existing behaviour and unchanged; the CLO ruling is cited (Art. 32 control-effectiveness gap, no legal step gates the fix, no published text edited); plugin MCP wildcards stay pre-approved by design (residual risk named); the sibling-branch conflict note for PR #11289; `Closes #11303` in the body, not the title.

### Post-merge (performed by the agent through ship/postmerge, no operator step)

- [ ] Verify the deploy: `soleur:postmerge` (release workflow success, both web hosts healthy on the new image tag equal to the merge commit).
- [ ] Absence check on **each** prod web host (`host_name` values `soleur-web-platform` for web-1 and `soleur-web-2` for web-2, per `apps/web-platform/infra/betterstack-logs-alerts.tf`; confirm at work time), only after BOTH hosts run the merge-commit image (sessions are instance-local, so the bypass persists on a host until it deploys), with a window of at least 1h that is not older than the later host's deploy (a longer window can include pre-deploy rows and read as a false `present`), the gated list generated from the code, not typed, and the discriminating journald field found in Phase 0.6 added as `--control-require-field` / `--absence-require` so a webhook-payload row quoting these names cannot satisfy or defeat the check:

  ```bash
  GATED=$(cd apps/web-platform && bun -e 'import {TOOL_TIER_MAP} from "./server/tool-tiers"; for (const [k,v] of Object.entries(TOOL_TIER_MAP)) if (v==="gated") console.log(k)')
  for HOST in soleur-web-platform soleur-web-2; do
    ARGS=(); for n in $GATED; do ARGS+=(--absence "$n"); done
    doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-assert-absence.sh --host "$HOST" "${ARGS[@]}" --absence-require CAN_USE_TOOL_SHADOWED --control mcp__soleur_platform__narrate --control-require-field source_kind=app_container --since 7d
  done
  ```

  (The positive control assumes the SDK warning names auto-approve entries; Phases 0.4 and 0.6 confirm the format and the channel, and the control is adjusted to a name the warning does name if not. If Phase 0.6 found no historical SHADOWED row at all, the whole step is recorded as unobservable and not run as a pass/fail gate.) Record each `SOLEUR_ABSENCE_ASSERT` verdict line on the PR and on #11303. Exit 0 (`clean`) = verified. Exit 2 (`unshipping`, control zero) = **unobserved, not clean**: no legacy session with platform tools ran in the window; the probe plus census are then the sole evidence and the PR says so (the issue still closes with the merge, because `Closes #11303` is the contract). Exit 1 (`present`) or 3 (`unknown`) = failed verification: follow the rollback note in Risks before any closure comment.

## Test Scenarios

- Given a legacy session with a connected repo, a Plausible key and plugin MCP servers, when the SDK options are built, then `allowedTools` contains only auto-approve platform names and plugin wildcards, and `canUseTool` still receives the full platform name list (integration, `startAgentSession` wiring).
- Given each non-auto platform tool derived from the builders, when `buildAllowedTools` runs, then none is in the output (unit, property over the census).
- Given an unclassified new tool name, then the filter drops it and the explicit-entry assertion fails until it has an entry (unit).
- Given an input list in shuffled order, with duplicates, only auto names, zero or two plugin servers, then the output is correct (unit, must-PASS non-canonical).
- Given a gated tool call and a gate that rejects on timeout, then the static deny, status ends `active`, nothing throws (unit).
- Given a gate that rejects because the session controller aborted (user Stop; disconnect grace), then deny and no `active` write (unit).
- Given a per-call abort with the session alive, then deny and `active` restored (unit).
- Given two concurrent gated calls, when the first is approved while the second waits, then status stays `waiting_for_user` until the second resolves (unit).
- Given `updateConversationStatus` throws on hold or restore, then the verdict is preserved and a `platform-gate-status-*` warn event with its static message is emitted (unit).
- Given a late `review_gate_response` for an expired gate, then it is rejected harmlessly and no allow results (integration, ws-handler).
- Given the real SDK, the production option composition and the production string prompt, when the model calls each of the eight gated tools, then `canUseTool` is invoked, tier `gated` is seen, and the deny is honoured (real-SDK probe, paid, dev/ci only; `pyramid-justified: only the real SDK can show the permission-chain order, mocks cannot`).
- Given the raw unfiltered list, then the bypass is still observed (probe canary).
- Regression: existing KB-share, email-triage, plugin-wildcard and read-tier suites stay green with the flipped expectations.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Rulings of 2026-10-27 (issue ruling plus the eight residual forks): unconditional; `buildAllowedTools` in `tool-tiers.ts` keyed on `getToolTier(n) === "auto-approve"`, always returns an array; second line of defence in `buildAgentQueryOptions`; reuse and generalize `holdForUser` with platform-specific Sentry ops and own static messages, expiry as `log.info` only; `plausible_get_stats` and `account_export_enqueue` stay gated; explicit tier entries for default-gated names; census split (unit + wiring) plus a map-membership check (the regex source scan was replaced by reading registered tool names from a booted session, after three reviewers called the scan brittle); probe gets a `:raw` canary and runs the production string prompt; flip the existing presence assertions; ADR yes, ordinal assigned at work time; C4 no impact; no other pre-approval path shadows `canUseTool` after the fix.

### Product (CPO)

**Status:** reviewed
**Assessment:** Conditional approve. Ship ahead of #11289. Risks: consent fatigue on `crm_*` and `workstream_issue_*` writes (medium; do not weaken the gate), offline user whose card times out after 5 minutes (medium; fail-closed correct), agent retry after a deny (medium; mitigated by the static "Do not retry unless the user asks." suffix). Conditions: (1) PR body states the behaviour change in its first line; (2) tests assert every gated tool is absent from `allowedTools` and that the review card is emitted, plus the timeout deny path; (3) deny strings pass the copy check (state plainly the action was not performed, no "failed"/"error" wording, static, no interpolated user content); (4) follow-ups documented (below, in Non-Goals); (5) CLO ruling cited in the PR, no legal text edited. No UI surface is touched, so there is no Product/UX gate beyond this advisory.

### Legal (CLO)

**Status:** reviewed (carried forward from the CLO ruling of 2026-10-27)
**Assessment:** Art. 32 control-effectiveness gap, not an Art. 4(12) breach on present evidence; no legal step gates the fix; published text is not edited in this PR; the determination memo, the compliance-posture entry and the register corrections follow separately once telemetry on external effects (`outbound_sends`, GitHub and KB-share events since 2026-06-15) is read. `soleur:gdpr-gate` trigger (b) (single-user-incident threshold) fires; its output would be a write to `compliance-posture.md`, which the CLO ruling sequences after the telemetry read, so it is not invoked in this PR.

## Plan Review Revisions (2026-10-27, headless)

Panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow (single-user-incident threshold). Applied (mechanical): the assertion matches the bare server name and wildcards; the abort/restore race is decided (platform gate skips the `active` write when the session controller is aborted); six `buildGateMessage` cases added; the string-prompt shape is measured in Phase 0.4 and used by all probe rows; probe builder-import failure is CANT-RUN; `holdForUser` takes an options object; the source scan is replaced by a booted-session check; plugin frontmatter sentinel; counts derived in tests; post-deploy check loops both hosts with a generated name list and states rollback and "unobserved" semantics; the disconnect grace (30 s) and the #11289 add/add conflict corrected; matrices trimmed. Persisted to `decision-challenges.md`: the call-site-plus-throw duplication, probe cherry-pick, battery, follow-up issues, plugin wildcards.

## Non-Goals and Deferrals

Documented in place (`wg-when-deferring-a-capability-create-a`: no issue unless the triple test passes; none opened by this plan):

- Consent-fatigue policy for batches of write approvals (a per-session "allow this tool class" option): a product decision belonging to the #11289 approval-queue design.
- Offline or expired-gate UX (resume or re-request): same, under #11289.
- Legal determination memo, `compliance-posture.md` entry and register corrections: sequenced by the CLO after the external-effects telemetry read; they live in the issue's Legal-posture section, not in this PR.
- Whether a PreToolUse hook `allow` can pre-empt `canUseTool` for Bash on sdk 0.3.284: covered by `dev-probe-destroy-ask.ts` and ADR-284; unrelated to platform tools.
- Changing the 5-minute gate timeout, the review-card UI, plugin MCP wildcard pre-approval, or the cc path.

## Dependencies and Prerequisites

- Doppler `ci` (or `dev`) config with a usable `ANTHROPIC_API_KEY` for the probe (approx. 10 paid model calls at up to $0.5 each; the probe refuses `prd`).
- `origin/feat-hitl-approval-queue` reachable for `git cherry-pick -n 0acc541b6f`.
- Better Stack query credentials via Doppler `prd_terraform` for the post-deploy check (read-only).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one is filled.
- `getToolTier` defaults to `gated`, so "default-gated" cannot be told from "decided" without explicit entries; the explicit-entry assertion over registered tool names is what makes a new tool fail CI instead of silently landing gated.
- `createCanUseTool` must keep receiving the **unfiltered** `platformToolNames`; filtering it would turn every gated tool into deny-default.
- The probe's `:raw` rows must override `allowedTools` after `buildAgentQueryOptions` returns; passing the raw list through the builder now throws by design.
- Do not use `git stash` to revert mutation edits; use `git checkout -- <file>` on the single file.
- Re-verify the ADR ordinal against `origin/main` at ship and after every sync; sweep this plan and `tasks.md` for the old ordinal if it moves.
- Probe results depend on the model attempting the tool; a green run is evidence about the sampled behaviour only. "Did not attempt" is CANT-RUN.
- The post-deploy absence check can legitimately be unobservable (no legacy traffic); report it as such.
