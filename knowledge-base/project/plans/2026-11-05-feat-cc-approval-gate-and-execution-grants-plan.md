---
title: "feat(approval): wire the ADR-309 approval gate and ExecutionGrants into the cc dispatcher"
type: feat
date: 2026-11-05
slug: cc-approval-gate-and-execution-grants
branch: feat-one-shot-11635-cc-approval-gate
issue: 11635
closes: []
epic: 9601
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat(approval): wire the ADR-309 approval gate and ExecutionGrants into the cc dispatcher

Ref #11635 (epic Ref #9601). Spec lacks a valid `lane:` (no spec.md for this one-shot branch): defaulted to `cross-domain` (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-05
**Method (disclosed, bounded):** the deepen halt gates were run mechanically (4.6 user-brand impact present with threshold; 4.7 observability fields present, probe verb `grep` allowlisted, literal `expected_output`, no ssh; 4.8 no PAT-shaped variable; 4.11 `lint-guard-contract.py` green with 3 guard entries; 4.12 exactly one unfenced Scope Check, no BLOCKED marker; 4.9/4.10/4.13 not triggered: no UI file, no store or connection, no new autonomous task). Every rule id, `knowledge-base/` path and issue reference in the plan was verified live (no missing rule id, no broken path, no `#`-number beyond the two permitted refs). The broad per-skill and all-agent fan-out of this skill was NOT run: the evidence base is the CTO and CPO rulings, the learnings sweep, and a five-seat plan-review panel (DHH, Kieran, code-simplicity, architecture, spec-flow) already applied to the plan; running forty more seats on a ~60-line production change was judged poor value for the cost.

### Key improvements applied since the first draft
1. One deny site instead of two (two simplification seats; CTO ruled F1b), with a per-fall-through-path test requirement.
2. Dormancy proof and natural-repair line added; Guard 3 cut to three presence pins; the sweep folded into `tools-census.test.ts` with subset relations plus a floor.
3. ADR-309 self-contradiction fix named (the universal "per user message" statements) and the per-runner flag-off divergence made explicit.

### New considerations discovered during verification
- `cc-dispatcher.ts` already value-imports `getFreshTenantClient` from the tenant module and `isApprovalRequiredTool`, so `gate.ts` adds no new import of a module that factory tests have not already had to mock; the residual exposure is `notify.ts` and `flag.ts` only (lazy, closure-only), reduced from the draft's wording.
- Verify-the-negative: cc has exactly one `createSdkMcpServer(` call and `pluginMcpServerNames: []` (confirms the sweep's assembly claim); the architecture seat confirmed no `allowedTools`, `permissionMode`, hook or subagent path puts a required tool in front of `canUseTool` unguarded.
- Wiring-absent shares the `approval-gate-failed` Sentry group with real flow failures (CTO F2b: accepted; `stage` is an extra, not a fingerprint; a dedicated op is warranted only if an alert must page on it separately).

## Overview

Give the cc dispatcher (the Concierge and web-egress dispatch path) the same approval-gate dependency and a per-dispatch execution-grants object that the legacy runner already has, and make any approval-queue tool that reaches the cc `canUseTool` deny instead of falling to the in-memory review card. Today the cc path has neither, so a gated platform tool registered there later would have no grant object to read and no gate to pass.

The sweep (below) found that the cc path registers **no** `APPROVAL_REQUIRED_TOOLS` member and no gated tool that is reachable without a human gate. Per the binding ruling the PR therefore shrinks to: grants + gate wiring + an opt-in fail-closed switch + absence/sweep tests + a short ADR-309 addendum. Nothing in this PR registers a tool, creates or flips a flag, or changes behavior with the `approval-queue` flag absent for any input that can reach the cc path today.

## Research Insights

### Premise Validation (Phase 0.6)

- The target issue is open; its own open PR is this branch's WIP PR (the collision pre-check hit is self). Two other worktrees run the shared test runner, unrelated to these files.
- Cited symbols verified on this tree: `new ExecutionGrants()` once in `server/agent-runner.ts` (anchor: `const approvalGrants = new ExecutionGrants();`), `createApprovalGateDeps({` inside the `createCanUseTool({ ... deps: { approval:` block of the same file, `readCcMcpAllowlist` refusal in `server/cc-dispatcher.ts` (anchor: `isApprovalRequiredTool(fqn)`), the `ccDeps` object and `deps: ccDeps` in `realSdkQueryFactory`.
- ADR corpus check: ADR-309 (§Flag-off posture, §Bound versus executed: ExecutionGrants, §Residual risk) already states the cc runner "has no approval wiring" and uses `readCcMcpAllowlist` as the backstop; ADR-305 owns the gated branch. Neither rejects wiring the gate into cc: the gap this plan closes is the one ADR-309 named. ADR-309 says the grants object is created per user message (turn); the cc Query is multi-turn, reconciled below (CTO ruling F3).
- Existing census conflict (found, not assumed): `test/approval/runner-census.test.ts` asserts the cc runner never contains `createApprovalGateDeps|ExecutionGrants`. That assertion encodes the pre-change state and must be flipped, not worked around.

### Property List and Cut List (Phase 0.6b)

Properties the ask buys:

- P1. A gated approval-queue tool that reaches the cc `canUseTool` never reaches the in-memory review card; it is denied with the static "approval unavailable" text.
- P2. The cc path owns a per-dispatch grants object and gate deps built from the same factories the legacy runner uses, so a later grant-reading tool builder in cc has something to read.
- P3. With the flag absent/off, every tool that can reach cc today behaves byte-for-byte as before.
- P4. Every gated-tier tool registered in cc is enumerated, classified, and pinned by a derived (not hand-kept) sweep.

Mechanisms named in the ask and whether the repo already covers the property (authority grepped: `server/permission-callback.ts`, `server/approval/gate-flow.ts`, `server/approval/tools.ts`, `server/cc-dispatcher.ts`):

| Mechanism in the ask | Property | Already on main? | Verdict |
|---|---|---|---|
| per-dispatch `ExecutionGrants` in cc | P2 | No (agent-runner only) | Keep |
| `createApprovalGateDeps` in cc `canUseTool` deps | P2 | No | Keep |
| deny when gate/grants absent or flag unreadable | P1 | No: gated branch falls through when `deps.approval` is absent or the verdict is `null` | Keep (opt-in dep) |
| registration sweep + test | P4 | Partly: `runner-census` greps for builder names; `tools-census` classifies the tier map; neither enumerates what cc actually registers | Keep (derived sweep) |
| ADR-309 addendum | n/a | ADR-309 states the opposite today | Keep (short) |

Cut List (mechanisms the plan considered and removed): a new `APPROVAL_OPS` entry (reuse `gateFailed` with `extra.stage`; a new op churns the ops registry, ops-sink, and alert tests); a flag-read timeout wrapper in the gate (the flag client already has a request timeout and an env-mirror fallback, and the gate is not redesigned); a per-turn grants object threaded through `soleur-go-runner` (no cc tool builder reads grants yet); an edit to the Guard 1 mutation battery table (both of its `permission-callback.ts` anchors are preserved byte-identical instead); a wrapper `canUseTool` in cc-dispatcher (duplicates the tier/gate logic outside the branch that holds the fall-through).

### Institutional learnings applied

- `2026-10-29-hitl-approval-queue-...six-ci-guards-no-local-suite-selects`: build the production gate factory un-injected in at least one test; treat fix rounds as new code.
- `2026-10-26-sentry-groups-by-message-and-a-lost-grant-read-as-a-denial`: every failure arm needs its own static Sentry message; a missing wiring must not render as an ordinary denial.
- `2026-06-16-leaderless-conversation-system-prompt-seam-is-cc-dispatcher-not-agent-runner`: cc bypasses `startAgentSession`; place the wiring in `realSdkQueryFactory`, and prove the value reaches the callback.
- `2026-06-03-dispatcher-factory-new-import-sweep-all-exercising-test-files`: a new import in `realSdkQueryFactory` can break sibling tests that mock modules partially; grep every test exercising the factory and run them.
- `2026-10-04-my-new-dispatcher-tests-pinned-spelling-not-wiring...`: capture constructor and call arguments in the mock and assert them; strip comments before any source scan.
- `2026-10-19-a-fail-closed-gates-tests-asserted-the-safe-verdict-which-two-causes-produce`: for each deny assertion also assert which path produced it (the card was never sent; the gate was or was not consulted).
- `2026-09-29-a-source-census-...closed-file-list...`: derive the registered set from the registry function, with a non-vacuity floor, and mutate the census's own recognizers.

## Research Reconciliation: Spec vs. Codebase

| Brief / issue claim | Reality (verified) | Plan response |
|---|---|---|
| "new ExecutionGrants() ~line 1206; gate deps ~2264-2269" in agent-runner | Confirmed (`const approvalGrants = new ExecutionGrants();`; `approval: createApprovalGateDeps({ userId, workspaceId: activeWorkspaceId, repoSlug, workspacePath, grants: approvalGrants })`) | Mirror those five arguments in cc |
| Sweep "workspace-settings, the C4 write tool, the crm-lead set" | `workspace_set_autonomous` (workspace-settings builder) is registered only by agent-runner, NOT cc. C4 `edit_c4_diagram` is registered in cc but is an explicit `auto-approve` tier. The crm-lead set registers 4 reads (auto-approve) and 3 writes (`gated`, all in `APPROVAL_EXEMPT_TOOLS`) | Sweep table below; no gated tool is reachable without a gate |
| "if the cc path registers no gated tool, the PR shrinks" | cc registers 3 gated-tier tools (CRM writes), all deliberately exempt and on the in-memory human review gate; it registers zero approval-required tools | Treated as the shrink case (CTO F4); the 3 exempt tools get a "still on the review card, never reads the flag" test |
| "fail closed when ... the flag read errors/times out" | `isApprovalQueueEnabled` swallows read errors to `false`; `runApprovalGate` treats `false`/throw as `null` (fall-through). A clean OFF and a read error are indistinguishable at the gate. Flagsmith client has `requestTimeoutSeconds` and an env-mirror fallback | Deny on any `null` verdict in cc (CTO F2); no gate redesign |
| ADR-309: grants "created once per user message (turn)" | The cc Query is multi-turn, built once per cold dispatch in `realSdkQueryFactory` | One grants object per factory invocation (per Query); sticky `enforcing` spans the Query (stricter; CTO F3) |
| `readCcMcpAllowlist` message and comments: "the cc runner has no approval wiring" | False after this PR (cc has gate deps and grants; no cc tool builder is wired to read grants) | Keep the throw (backstop, scope-out), reword message/comments (CTO F5); keep `/approval/i` match |
| `runner-census`: "the cc runner never builds the approval gate dependency or the execution grants" | Encodes the pre-change state | Flip to positive wiring pins; keep the negative "cc registers no slice-1 tool" census |

## Registration Sweep (hr-write-boundary-sentinel-sweep-all-write-sites)

Commands run (content anchors, not line numbers): `git grep -n "createSdkMcpServer" -- apps/web-platform/server` (cc registration site: one `createSdkMcpServer({ name: "soleur_platform"` in `realSdkQueryFactory`; the other hit is agent-runner); `git grep -n "createCanUseTool(" -- apps/web-platform/server` (two production call sites: agent-runner and cc-dispatcher); `git grep -n "buildNarrationTools\|buildC4ConciergeTools\|buildCrmTools\|buildWorkspaceSettingsTools\|buildGithubTools\|buildKbShareTools\|buildEmailTriageTools"`.

cc registers its tool list through `soleurPlatformToolsForTests` (narration, then c4, then crm only when `crmLead`) and merges `readCcMcpAllowlist()` (always `{}` today) and `pluginMcpServerNames: []`.

| Hit | Registration site | Tier (`TOOL_TIER_MAP`) | Approval class | Reachable without a human gate? |
|---|---|---|---|---|
| `narrate`, `summarize` | `buildNarrationTools`, always | auto-approve (also in `CC_PATH_ALLOWED_TOOLS`) | n/a | Yes by design: pure emit tools, no write |
| `edit_c4_diagram` | `buildC4ConciergeTools`, flag + repo + non-support persona | auto-approve (explicit, rationale in `tool-tiers.ts`) | n/a | Yes by design: diagrams-dir-scoped, reversible; out of this PR |
| `crm_contact_list`, `crm_contact_get`, `crm_note_list`, `crm_stage_transitions_list` | `buildCrmTools`, crm-lead chats | auto-approve | n/a | Yes by design: reads |
| `crm_contact_upsert`, `crm_note_append`, `crm_contact_set_stage` | `buildCrmTools`, crm-lead chats | gated | `APPROVAL_EXEMPT_TOOLS` (in-memory review card) | No: human review card; deny on reject/timeout |
| `workspace_set_autonomous` | `buildWorkspaceSettingsTools` | gated | required | Not registered in cc (agent-runner only) |
| `github_push_branch`, `create_pull_request`, `github_trigger_workflow`, `kb_share_create`, `email_send`, `email_reply`, `email_suppress` | agent-runner builders only | gated | required | Not registered in cc; `readCcMcpAllowlist` throws on any attempt to promote them |

Finding: no existing gated tool is reachable in cc without a gate, so there is no same-PR fix to make. If a later change registers a required tool in cc it inherits the fail-closed switch added here, and the derived sweep test fails loudly naming the tool.

What this sweep cannot see (stated so the pins are not over-read): a tool registered through a path other than `soleurPlatformToolsForTests`/`createSdkMcpServer` (a future second MCP server in the cc options) would not be enumerated by the derived test; the census therefore also pins that cc contains exactly one `createSdkMcpServer(` call and `pluginMcpServerNames: []`. The SDK's refusal of unregistered `mcp__soleur_platform__*` calls before `canUseTool` is an SDK behavior, documented in the dispatcher and observed by the existing unregistered-tool mirror, not something a unit test here proves.

### Dormancy proof (flag absent means unchanged) and the natural repair

Prod inputs the change touches, and why none reaches a new behavior with the flag absent: (1) every cc dispatch now runs `createApprovalGateDeps(...)` and `new ExecutionGrants()`: closures and a `Map` only, no database, flag or network access at construction, so cold-dispatch behavior is unchanged; (2) every gated platform call in cc now evaluates `deps.approval && isApprovalRequiredTool(toolName)` with `deps.approval` defined: the only gated tools registered in cc are the three exempt CRM writes, for which `isApprovalRequiredTool` is false, so the gate and the flag are never consulted for them (pinned: `isEnabled` is not called); (3) the new deny sites only fire for an `APPROVAL_REQUIRED_TOOLS` member, and no member is registered in cc or listed in cc's `platformToolNames`, so no measured cc input reaches them. Every other tool class (Bash, file tools, skills, auto-approve platform tools) returns before the gated branch.

The most natural repair of the new refusal is for a developer who wants a required tool in cc to register it (or to set `CC_MCP_ALLOWLIST`). Both are refused: the allowlist throws, and the derived sweep and census fail naming the tool. The repair for an agent that is denied is to retry; the static text says not to, and the late deny is stable across retries.

## Proposed Solution

### 1. `server/cc-dispatcher.ts` (inside `realSdkQueryFactory`, never module scope)

- Import `createApprovalGateDeps` (from `./approval/gate`) and `ExecutionGrants` (from `./approval/grants`).
- Immediately before the `ccDeps` object: `const approvalGrants = new ExecutionGrants();` (exactly one construction in the file, inside the factory body, so grants cannot leak across users or Queries).
- Add to `ccDeps`: `approval: createApprovalGateDeps({ userId: args.userId, workspaceId: activeWorkspaceId, repoSlug: connectedOwner && connectedRepo ? \`${connectedOwner}/${connectedRepo}\` : "", workspacePath, grants: approvalGrants })` and `approvalFailClosed: true`.
- Reword the `readCcMcpAllowlist` doc comment, inline comment and thrown message: keep the throw and the `approval-required tool "<name>"` fragment and the `/approval/i` match; replace "has no approval wiring" with "no cc tool builder is wired to execution grants (ADR-309)".
- `createApprovalGateDeps` builds closures only (no database access until a required tool reaches the gate), so cold-dispatch cost and failure surface are unchanged.

### 2. `server/permission-callback.ts` (opt-in fail-closed, one deny site)

Add `approvalFailClosed?: boolean` to `CanUseToolDeps` with a doc comment ("set only by the cc dispatcher: a slice-1 tool never falls to the in-memory card; expected to become the default once the flag is promoted"). Unset (agent-runner, every existing test) leaves the branch byte-identical.

One deny site, immediately after the existing `if (deps.approval && isApprovalRequiredTool(toolName)) { ... if (approvalVerdict !== null) return approvalVerdict; }` block and before the in-memory `gateId`/`review_gate` card is built (the two anchor lines of that block stay byte-identical, see Guard 1 battery note):

```ts
if (deps.approvalFailClosed && isApprovalRequiredTool(toolName)) { /* deny, never the card */ }
```

It covers both reasons the block above did not return a verdict: `deps.approval` undefined (wiring absent) and a `null` verdict (flag off or unreadable). Inside it: when `!deps.approval`, mirror once via `reportApprovalOp("gateFailed", null, { toolName, conversationId, userId, extra: { stage: "wiring-absent" } })` (error level, existing op, static message, null first argument; trade-off accepted per the CTO ruling: it shares the `approval-gate-failed` Sentry group with real flow failures and is told apart by `extra.stage`, because a new op churns the registry, sink and alert tests for a path that cannot fire today); otherwise only a pino `log.warn` with `{ sec: true, tool, decision: "platform-gate-approval-fail-closed", enforcing: deps.approval.grants.enforcing }` (a flag read error is already mirrored, debounced, by the existing `flagReadFailed` op, and a clean OFF is a normal dormant state: the warn line is NOT a fault signal and must not be wired to an alert). Both paths call `logPermissionDecision("canUseTool-platform-gated", toolName, "deny", <reason>)` and return `deny` with the static `APPROVAL_UNAVAILABLE_DENY` (no tool input echoed). No flag read happens on the wiring-absent path.

Ordering, stated once: the earlier gated-branch steps (non-interactive session, `buildGateCard` unreviewable input, the pending-gates cap) each already return a deny with no card and run before this site, so a required tool in those states gets their static text instead of the unavailable text; the outcome (deny, no card, nothing executed) is the same. This is a deliberate per-runner divergence from the legacy flag-off posture: in cc, flag off denies a required tool where the legacy runner shows the review card.

Import `reportApprovalOp` from `./approval/ops` and `APPROVAL_UNAVAILABLE_DENY` from `./approval/gate-flow` (already imports `runApprovalGate` from there).

Why a tool must also be in `platformToolNames` to reach this branch: `canUseTool` only enters the gated branch for names in `ctx.platformToolNames` with tier gated; a required tool absent from that list hits the later default-deny. cc passes only the c4 FQN and the crm-lead FQNs, so both layers independently deny.

### 3. Tests (written first; see Phase 1)

### 4. ADR-309 addendum + stale comments

Short dated addendum to ADR-309 (see Architecture Decision section) and the two stale "no approval wiring" comments (`workspace-settings-tools.ts` header, `tools-census.test.ts`).

## Implementation Phases

### Phase 1 - RED tests (cq-write-failing-tests-before)

1. `test/approval/cc-approval-fail-closed.test.ts` (new, light imports; mirrors `permission-callback-gated-branch.test.ts`): through the real `createCanUseTool`.
2. `test/approval/tools-census.test.ts` (edit): one new `describe` with the derived cc registration sweep, reusing the file's existing `beforeAll` import of cc-dispatcher (120 s budget), so the cold import is paid once.
3. `test/approval/runner-census.test.ts` (edit): flip the cc negative assertion to positive wiring pins.
4. `test/cc-dispatcher-real-factory.test.ts` (edit, one new `describe`): call `createCanUseTool`'s mock `mockClear()` first, then read `calls[0]`/`calls[1]` (the file's mock accumulates across tests); capture the `ctx` and assert `deps.approval` is defined, `deps.approval.grants` is an `ExecutionGrants` with `enforcing === false`, `deps.approvalFailClosed === true`, `deps.approval.workspaceId` equals the resolved active workspace, and two factory invocations get distinct grants objects.
5. Confirm all four files are RED against the unmodified source for the right reason (the assertion about the missing wiring, not an import error).

### Phase 2 - GREEN

Implement sections 1 and 2 above; apply each Guard 1 mutation row once and confirm the named test reds; re-run the Phase 1 files until green; sweep every test file that exercises `realSdkQueryFactory` or mocks `@/lib/supabase/tenant` / `@/lib/supabase/service` (`git grep -ln "realSdkQueryFactory" -- apps/web-platform/test`; at least `cc-mcp-tier-allowlist`, `cc-dispatcher-prefill-guard`, `cc-effective-installation`, `cc-reprovision`, `cc-dispatcher-warm-presandbox-mkdir`, `agent-runner-helpers`; `gate.ts` pulls in `notify.ts` and `flag.ts`, whose mocks the factory tests do not all provide, so confirm by running them) and run them.

### Phase 3 - ADR addendum, comment fixes, verification

ADR-309 addendum and comment rewording; run the verification list under Test Plan.

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts` - imports, one `ExecutionGrants`, `approval` + `approvalFailClosed` in `ccDeps`, reword allowlist comment/message.
- `apps/web-platform/server/permission-callback.ts` - `approvalFailClosed` dep and the two deny sites.
- `apps/web-platform/server/workspace-settings-tools.ts` - header comment only ("no approval wiring" is no longer true).
- `apps/web-platform/test/approval/runner-census.test.ts` - flip cc assertions; update header comment.
- `apps/web-platform/test/approval/tools-census.test.ts` - stale comment above the `readCcMcpAllowlist` describe, plus the new derived cc registration sweep `describe` (Guard 2).
- `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` - new wiring `describe`.
- `knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md` - addendum, correct the sentinel bullet, add `11635` to `related`.

## Files to Create

- `apps/web-platform/test/approval/cc-approval-fail-closed.test.ts`
- `knowledge-base/project/specs/feat-one-shot-11635-cc-approval-gate/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-11635-cc-approval-gate/decision-challenges.md`

Files verified to exist with `git ls-files`; none is under the scope-out paths (`dsar-export-allowlist.ts`, `.github`, `scripts`, `docs/legal`, `plugins/soleur/docs`, migrations).

## Open Code-Review Overlap

Two open code-review issues name `apps/web-platform/server/cc-dispatcher.ts`: the one titled "arch: decompose cc-dispatcher.ts into focused modules" and the one titled "review: tool_use WS event lacks raw name field for agent consumers". **Acknowledge** both: the decomposition is a separate cycle (its own re-evaluation note says to revisit if the dispatcher is decomposed first, and this PR adds about fifteen lines to the factory body that a later extraction would move with it); the `tool_use` event concern is unrelated to approval wiring. No other planned file is named by an open code-review issue.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "per-dispatch ExecutionGrants instance in apps/web-platform/server/cc-dispatcher.ts plus createApprovalGateDeps wired into the cc canUseTool path, mirroring agent-runner.ts" | Proposed Solution 1; Files to Edit `cc-dispatcher.ts` | mapped |
| 2 | "Fail closed when gate/grants absent or the flag read errors/times out: any tool in APPROVAL_REQUIRED_TOOLS reaching the cc path must deny, never fall through to the in-memory gate." | Proposed Solution 2; Files to Edit `permission-callback.ts`; `cc-approval-fail-closed.test.ts` | mapped |
| 3 | "git grep every gated-tier tool actually registered in the cc path ... list every hit in the plan, and add a test that each fails closed without gate/grants" | Registration Sweep table; derived sweep in `tools-census.test.ts`; `cc-approval-fail-closed.test.ts` | mapped |
| 4 | "Tests first: flag OFF means cc behavior byte-for-byte unchanged; flag ON with no gate means deny; follow existing census/Sentry-mirror conventions." | Phase 1; Guard Contract; Observability | mapped |
| 5 | "Short ADR-309 addendum or See-also." | Architecture Decision section; Files to Edit ADR-309 | mapped |
| 6 | "If the sweep finds an existing gated tool reachable without a gate, fix it in the same PR and record it; if the cc path registers no gated tool, the PR shrinks to grants + gate wiring + absence test." | Registration Sweep finding (none reachable without a gate; shrink case) | mapped |
| 7 | "when adding a test under apps/web-platform/test/, also run test/repo-wide-contain* census tests" | Test Plan verification list | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cc-dispatcher.ts` edit | "per-dispatch ExecutionGrants instance ... plus createApprovalGateDeps wired into the cc canUseTool path" | asked |
| `permission-callback.ts` `approvalFailClosed` dep | "must deny, never fall through to the in-memory gate" | asked (the opt-in shape is a CTO ruling, F1) |
| `cc-approval-fail-closed.test.ts` | "add a test that each fails closed without gate/grants" | asked |
| derived sweep `describe` in `tools-census.test.ts` | "list every hit in the plan, and add a test" | asked |
| `runner-census.test.ts` flip | "follow existing census/Sentry-mirror conventions" | asked; also inferred - the existing assertion forbids the wiring this PR adds, so the suite is red without the flip |
| `cc-dispatcher-real-factory.test.ts` wiring describe | "Tests first" | inferred - justification: a source-text census cannot see that the live `ccDeps` object carries the grants and the switch; only the captured callback context can (it is also what lets Guard 3 stay at three presence pins) |
| `workspace-settings-tools.ts` and `tools-census.test.ts` comments | "Short ADR-309 addendum or See-also" | inferred - justification: both comments state "the cc runner has no approval wiring", which this PR makes false; leaving them would leave the recorded rationale contradicting the code |
| ADR-309 edit | "Short ADR-309 addendum or See-also" | asked |
| `readCcMcpAllowlist` rewording | "removal/loosening of the readCcMcpAllowlist refusal ... stays as backstop" | asked (the throw stays; only its stale wording changes, CTO F5) |
| `tasks.md`, `decision-challenges.md` | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table" | asked |

### Split Assessment

- Subsystems touched: 2 - `apps/web-platform`, `knowledge-base`
- Planned files: 10 | Estimated changed lines: about 450 (about 60 production, about 350 test, about 40 prose)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** a Concierge or web-egress session in which a platform tool that the workspace Owner is meant to approve (an outbound email, a branch push, a public share link, an autonomy change) is shown as an ordinary in-chat card the requester can answer themselves, or runs with no approval row at all.
- **If this leaks, the user's workflow is exposed via:** an agent-driven external write (email to a third party, push to the connected repository) executed without the Owner's durable, action-bound approval; no data is exposed by this change itself.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** inherited from ADR-309, whose tools are external irreversible writes; one workspace's unapproved send is a single-user incident. The exposure is unreachable by construction today (no required tool is registered in cc), which lowers likelihood, not severity, so the tier stays. CPO sign-off obtained at plan time: yes (advisory, recorded in the Domain Review).

`soleur:engineering:review:user-impact-reviewer` is invoked at review time (single-user-incident threshold).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-309 (extension of an existing decision; no new ADR, ordinal not consumed) via `soleur:architecture`:

- Add a dated **Addendum** (2026-11-05, Ref #11635) stating: (1) the cc dispatcher builds `createApprovalGateDeps` and one `ExecutionGrants` per `realSdkQueryFactory` invocation, i.e. per Query, not per turn, so sticky `enforcing` spans every turn of that Query (stricter than the legacy lifetime; per-turn is out of scope until a cc tool builder reads grants); (2) cc sets `approvalFailClosed`, so an `APPROVAL_REQUIRED_TOOLS` member reaching the cc `canUseTool` is denied with the static unavailable text when the wiring is absent or the flow returns no verdict (flag off or unreadable), never the in-memory card; this is a deliberate per-runner divergence from the legacy flag-off posture of ADR-305/ADR-309 (the legacy runner still shows the card); wiring-absent is a Sentry error under the existing `approval-gate-failed` op with `extra.stage = wiring-absent`; (3) `readCcMcpAllowlist` still throws and is the backstop, no cc tool builder reads grants today; (4) one line of preconditions for the first PR that registers a required tool in cc: it passes the derived sweep and census, wires the grant-reading builders with the same grants object, and settles where the Owner finds a pending approval from a Concierge chat (a product decision, not made here). Verified at plan time, stated as fact: `activeWorkspaceId`, `connectedOwner` and `connectedRepo` are `const` bindings in the factory, so the values captured at gate construction cannot be reassigned; whether the user's active workspace can change while a Query is alive is not checked here.
- Make the existing universal statements consistent: in §Bound versus executed: ExecutionGrants ("created once per user message", "the next user message starts with a fresh ... grants object") and §Flag-off posture, add "except the cc dispatcher, see the Addendum"; and correct the §Residual risk bullet that says "the cc runner has no approval wiring" to the accurate statement (no cc tool builder is wired to grants).
- Add `11635` to the `related` frontmatter list. Status stays `adopting`.

### C4 views

No `.c4` edit. All three model files were read (`model.c4`, `views.c4`, `spec.c4`). Checked and already modeled: external human actors - the workspace Owner decides via the existing `webapp -> approvalStore` edge; no new actor. External systems/vendors - none added (no new API edge). Containers/data stores - the existing `engine -> approvalStore` edge already reads "Hosted agent sessions run the same gated branch of `canUseTool` in-process", which covers the cc dispatcher (same engine container; `cc-dispatcher.ts` and `agent-runner.ts` are both named at the plugin-trust-boundary comment). Actor-to-surface access relationships - unchanged. The webapp description already says the gated branch of `canUseTool` serves hosted sessions. Count parity: `bash plugins/soleur/test/c4-count-parity.test.sh` run at plan time: 13 passed, 0 failed; no cardinality on those edges changes.

### Sequencing

The ADR addendum is authored in this PR, describing the state after this PR (status unchanged: `adopting` until the flag is measured on a canary, which this PR does not do).

## Domain Review

**Domains relevant:** engineering, product (advisory sign-off only; no UI surface)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Technical rulings F1-F5 recorded in `decision-challenges.md` (opt-in `approvalFailClosed` dep; deny on flag off/unreadable in cc with Sentry only for wiring-absent; per-Query grants lifetime accepted; census additions accepted - same-object pin, tier pin, per-Query isolation, exempt tools never read the flag; reword the allowlist message and keep the throw). Risks named by the CTO and carried: closure capture of workspace/repo (UNVERIFIED, precondition in the ADR addendum); hold/pending-gate coupling (`controllerSignal` in cc is the Query's real abort controller: verified, `controllerSignal: controller.signal`); `sendToClient` for approval frames (cc uses the same `defaultSendToClient` as the legacy runner); reattach (ws-handler `reattachApprovals` is keyed on the conversation, reads `approval_request` rows, and cc writes none); the absent-wiring deny precedes any flag read.

### Product (CPO)

**Status:** reviewed
**Assessment:** CPO sign-off: yes at `single-user incident`. Notes: confirm the static deny text tells the agent not to retry in this conversation (it does: the unavailable text says "Do not retry in this conversation. Tell the user the action was not performed."); the wiring-absent case is a defect and is mirrored to Sentry with its own `stage` value; the ADR addendum must state that the first cc registration of a required tool needs a product decision on where the Owner finds the pending approval. The CPO could not locate the deny string in server source: it is `APPROVAL_UNAVAILABLE_DENY` in `server/approval/gate-flow.ts`.

No Product/UX gate: no new file under `components/`, `app/**/page.tsx` or `layout.tsx`.

## Observability

```yaml
liveness_signal:
  what: The wiring-absent and fail-closed deny decisions in the cc canUseTool (a Sentry error under feature approval-queue, op approval-gate-failed, extra.stage wiring-absent; a pino warn decision platform-gate-approval-fail-closed). Both fire only when an approval-queue tool reaches the cc path, which is zero by construction today, so the healthy state is silence.
  cadence: per event (a required tool reaching cc); no heartbeat is added because the path is dormant by design
  alert_target: Sentry issue stream for feature approval-queue (the existing approval-gate-failed error route)
  configured_in: apps/web-platform/server/approval/ops.ts (APPROVAL_OPS.gateFailed) and apps/web-platform/server/permission-callback.ts
error_reporting:
  destination: Sentry via reportApprovalOp -> reportSilentFallback (null first argument, never an Error object; static message)
  fail_loud: the model receives the static unavailable deny and the pino line carries sec:true, tool, decision, enforcing
failure_modes:
  - mode: the cc dispatcher is edited so approval deps or approvalFailClosed are dropped while a required tool is registered
    detection: CI (the runner-census presence pins and the real-factory capture of ctx.deps fail when approval or the switch is dropped); at runtime, with the switch still set and approval dropped, a Sentry error approval-gate-failed with extra.stage wiring-absent (emitted from the cc canUseTool itself); if both are dropped together only CI sees it
    alert_route: existing approval-gate-failed Sentry route
  - mode: the approval-queue flag is off or its read fails while a required tool is in cc
    detection: pino warn decision platform-gate-approval-fail-closed with enforcing true/false (true means the flow ran earlier in this Query and was then switched off); a read failure is separately mirrored by the existing debounced approval-flag-read-failed op
    alert_route: Better Stack (warn-level app log) and the existing flag-read-failed Sentry op
  - mode: a required tool is registered in cc and falls to the in-memory card
    detection: CI only (derived registration sweep and census fail naming the tool); at runtime this shape cannot occur once the switch is wired because the late deny precedes the card
    alert_route: required CI check on the PR
logs:
  where: app container pino stream shipped to Better Stack (warn level reaches the aggregator per the vector filter)
  retention: Better Stack plan retention; Sentry event retention per project settings
discoverability_test:
  command: grep -c "approvalFailClosed: true" apps/web-platform/server/cc-dispatcher.ts
  expected_output: 1
```

Keep the literal `approvalFailClosed: true` out of comments in `cc-dispatcher.ts` so the discoverability grep counts code only (the comment-stripped census is the authoritative check).

Blind-surface note (plan Phase 2.9.2): the cc dispatcher is a container dispatch surface; the discriminating fields in one event are `stage` (wiring absent) on the Sentry event and `enforcing` plus the decision name on the warn line. A single event cannot separate a clean flag-off from a flag read error (the gate cannot either); the read-failed op is the separate signal.

## Guard Contract

### Guard 1 - cc canUseTool never falls through to the in-memory card for an approval-required tool

**Property.** In a `CanUseToolDeps` with `approvalFailClosed` set, no `APPROVAL_REQUIRED_TOOLS` member produces an allow or an in-memory review card unless `runApprovalGate` itself returns that verdict.

**Assembly.** The chokepoint is the gated branch of `createCanUseTool` (the only place the in-memory `review_gate` card for a platform tool is built, after `tier === "gated"`); the single deny site sits between the existing gate call and the card build. The quantified set is `APPROVAL_REQUIRED_TOOLS` read live (eight members), exercised with `it.each` over the live array, never a copied list. The paths that could allow such a tool without reaching the branch are: the `allowedTools` auto-approve list (`CC_PATH_ALLOWED_TOOLS` plus the optional `WebFetch` spread; asserted on the captured options of the real factory, not only on the constant), earlier fast paths (`isSafeTool`, file tools) that do not match `mcp__soleur_platform__*` names, and `platformToolNames` membership; each is pinned (list content, tier pin that every required tool is `gated`, membership). One production call site sets the switch (cc); agent-runner leaves it unset.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the deny site | RED: "required tool, no approval wiring -> deny, no card, flag never read" and "flag off or throwing seam + switch -> deny, no card" |
| 2 | Delete only the `!deps.approval` Sentry mirror | RED: the wiring-absent test asserting one `approval-gate-failed` event with `stage: "wiring-absent"` |
| 3 | Make the check compare only the first member (`toolName === APPROVAL_REQUIRED_TOOLS[0]`) after a compliant first | RED: the `it.each` rows for members two to eight |
| 4 | Make `isApprovalRequiredTool` return false for all (the guard's own dispatch goes vacuous) | RED: the deny tests, and the non-vacuity floor (`APPROVAL_REQUIRED_TOOLS.length >= 8`, every member `gated` in `TOOL_TIER_MAP`) |
| 5 | Move the deny site after the `review_gate` card build (REORDER, not delete) | RED: the test asserting `abortableReviewGate` and `sendToClient({type:"review_gate"})` are never called |
| 6 | Invert the switch default (treat unset as set) | RED: the byte-identical-default test (switch unset + approval absent still produces the review card) |
| 7 | Drop `approvalFailClosed: true` from `ccDeps` | RED: the real-factory wiring test (captured `ctx.deps.approvalFailClosed`) and the runner-census presence pin |

**Harness rows.** (a) Suite edit that must go RED: change the `it.each` source to a hand-copied six-name list; the floor/identity assertion against the live array fails. (b) Must-PASS input that is not the canonical: a required tool with a different (still valid) sample input from the shared fixtures, same verdict; and an exempt CRM write with the switch set and approval absent must still reach the review card (a guard that denies everything cannot pass it).

**Anchor.** The stored values here are source anchors and a tool list, not a hash: the guard compares the switch's behavior to the live `APPROVAL_REQUIRED_TOOLS` array and the live `TOOL_TIER_MAP`, so a PR that edits the switch must also edit the array or the tests in the same diff to weaken it; CI's required `test-webplatform` job and the pre-existing Guard 1 mutation battery are the checks outside this diff. The battery's two `permission-callback.ts` anchors (`if (deps.approval && isApprovalRequiredTool(toolName)) {` and `if (approvalVerdict !== null) return approvalVerdict;`) stay byte-identical; verify with the battery's `--check-anchors` mode. Work-phase step: apply each mutation row to the implementation once and confirm the named test reds (a cut or a keep justified by "this already fails closed" is measured, not assumed).

### Guard 2 - derived cc registration sweep

**Property.** Every tool the cc dispatcher can register is explicitly tiered, no `APPROVAL_REQUIRED_TOOLS` member is among them, and every gated one is exempt-with-a-reason.

**Assembly.** The registry is the single function `soleurPlatformToolsForTests` (narration + c4 + crm) evaluated with `crmLead` true and the real `buildC4ConciergeTools` over synthetic options, unioned with the `crmLead` false variant; its output feeds `getToolTier` / `TOOL_TIER_MAP` / `APPROVAL_EXEMPT_TOOLS` / `APPROVAL_REQUIRED_TOOLS`. Assertions are subset relations (registered intersect required is empty; every registered gated tool is in `APPROVAL_EXEMPT_TOOLS`; every registered tool is explicitly in `TOOL_TIER_MAP`) plus a non-vacuity floor (at least ten names, including narrate, summarize, `edit_c4_diagram` and the three CRM writes). A second MCP server or a tool registered by another route is invisible to this function; that is stated under Sharp Edges rather than pinned by a text scan.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a required tool (for example the push tool) to the cc registry output | RED naming the tool |
| 2 | Add a registered tool absent from `TOOL_TIER_MAP` (defaults to gated) | RED: every registered tool must be explicitly tiered |
| 3 | Add a second registered gated tool after the three exempt CRM writes, not in `APPROVAL_EXEMPT_TOOLS` | RED: gated registered subset of exempt |
| 4 | Empty the registry (the sweep's own dispatch: "0 checked") | RED: the floor |

**Harness rows.** Suite edit: feed the sweep helper a fake registry containing a required tool and assert it is reported (a short self-test in the file). Must-PASS non-canonical: a fake registry with only auto-approve tools passes.

**Anchor.** Subset relations against the live `APPROVAL_EXEMPT_TOOLS` / `APPROVAL_REQUIRED_TOOLS` (the registries of record) plus the floor guarding only the dispatch; a legitimate new exempt tool needs one classified registry entry and no test edit.

### Guard 3 - cc wiring presence pins

**Property.** The cc dispatcher contains exactly one `new ExecutionGrants()`, hands that same identifier as `grants:` to `createApprovalGateDeps(`, and sets `approvalFailClosed: true`, in code (not a comment).

**Assembly.** `server/cc-dispatcher.ts` after `stripComments`, as three regexes in `runner-census.test.ts` (replacing the stale negative assertion); the `grants:` regex captures the identifier and equates it to the `const X = new ExecutionGrants()` binding (a prefix match would pass a longer identifier, so the existing longer-identifier self-test stays mandatory). The behavioral leg is the real-factory capture of `ctx.deps` (grants present and `enforcing === false`, switch true, distinct grants per invocation, which also rules out module-scope construction).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Pass a different identifier as `grants:` (for example `approvalGrantsB`) | RED: identifier must end at the constructed binding |
| 2 | Leave the wiring only inside a comment | RED: comment-stripped scan does not see it |
| 3 | Construct a second `ExecutionGrants` in a later helper | RED: exactly one construction |
| 4 | Move the construction to module scope | RED: real-factory test (two invocations share one object) |

**Harness rows.** The existing `runner-census` self-tests (comment variants, longer identifier) are reused, not duplicated. Must-PASS non-canonical: the same wiring with different whitespace and key order passes.

**Anchor.** Text census proves spelling, not wiring; the real-factory capture is the behavioral leg, which is why both exist. What neither can see: that the SDK's own permission chain consults `canUseTool` at runtime for a registered required tool (measured only by the manual real-SDK probe recorded for the original approval-queue work).

## Acceptance Criteria

### Pre-merge (PR)

- [x] `cc-dispatcher.ts` constructs exactly one `ExecutionGrants` inside `realSdkQueryFactory` and passes `approval: createApprovalGateDeps({ ... grants })` and `approvalFailClosed: true` in `ccDeps` (Guard 3 presence pins green).
- [x] With `approvalFailClosed` set, each of the eight `APPROVAL_REQUIRED_TOOLS` denies with the static unavailable text and sends no review card when approval is absent, when the flag seam returns false, and when it throws; wiring-absent mirrors one Sentry error `approval-gate-failed` with `extra.stage = wiring-absent`, null first argument, no tool input in the payload (Guard 1).
- [x] With `approvalFailClosed` unset, behavior is byte-identical (review card for a required tool with approval absent; card for flag off): pinned by a test.
- [x] The three exempt CRM writes, with the switch set and approval wired and the flag seam returning true, never call `isEnabled`, show the review card, and deny on Reject (no per-tool flag read for non-required tools).
- [x] The derived sweep (Guard 2) is green (registered intersect required is empty; every registered gated tool is exempt; floor met) and fails naming the tool under each mutation row.
- [x] Each Guard 1 mutation row was applied once to the implementation during work and the named test went RED (recorded in the PR).
- [x] `runner-census.test.ts` no longer forbids the wiring; the negative "cc registers no slice-1 tool and imports none of their builders" census still passes.
- [x] The cc real-factory wiring test asserts distinct grants per factory invocation, `enforcing === false` at construction, the switch, and that no required tool is in the final `allowedTools`.
- [x] `readCcMcpAllowlist` still throws for every `APPROVAL_REQUIRED_TOOLS` short name, matches `/approval/i`, and its message no longer claims "no approval wiring".
- [x] ADR-309 carries the dated addendum, the corrected sentinel bullet, and no universal statement that the addendum contradicts; no `.c4` change; `bash plugins/soleur/test/c4-count-parity.test.sh` still passes.
- [ ] PR title/body use only `Ref #11635` and `Ref #9601`, no close keyword. No new issue is filed. No other `#`-number appears in any line this PR adds (existing comments the PR leaves untouched may carry theirs; scope the check to added lines), and no issue number from the range the task brief excludes.
- [x] The Guard 1 mutation battery anchors are intact: `bash apps/web-platform/test/approval-guard1-mutation.test.sh --check-anchors` reports no anchor mismatch.

### Post-merge

- None. No flag, environment, migration or infrastructure is touched; the flag stays as it is.

## Test Scenarios

Layer labels are `unit` unless stated.

- Given a cc-shaped context (switch set, no `approval`) and any required tool, when `canUseTool` runs, then it denies with the unavailable text, `abortableReviewGate` and `sendToClient({type:"review_gate"})` are never called, `isEnabled` is never read, and one Sentry error carries `stage: "wiring-absent"` (unit, `it.each` over the live array).
- Given switch set and `approval.isEnabled` -> false, when a required tool arrives, then deny, no card, `isEnabled` called once, no Sentry error (a clean OFF is dormant, not a fault).
- Given switch set and `isEnabled` rejecting, then deny, no card (the production seam already swallows to false, so this pins the gate's own handling, not the production path).
- Given switch set and `isEnabled` -> true, then the gate's verdict is returned (resolver failure -> unavailable deny; `grants.enforcing` becomes true) and the card is not reached.
- Given switch set, `grants.enforcing` already true and `isEnabled` -> false (flag switched off mid-Query), then the gate's own sticky deny answers (assert which path produced it), not the new site.
- Given switch set and the gate dependency (`submit`) rejecting with flag on, then a static deny and no card; the throw never escapes `canUseTool`.
- Given switch unset (agent-runner and every legacy fixture), approval absent or flag off, when a required tool arrives, then the review card is sent exactly as before (byte-identical default).
- Given switch set and the pending-gates cap reached (five held gates), non-interactive session, or an unreviewable input, then the outcome is still a deny with no card (their static text may differ from the unavailable text; asserted as deny + no card + `isEnabled` unread). Fixtures: `email_send` with an invalid recipient is the unreviewable input (only the email builders can deny at card build); the cap is reached by holding five gates; non-interactive via `nonInteractive: true`.
- Given the call signal or the controller signal already aborted with the flag off, then the late site returns the deny promptly (no hang) and `pendingGates` is unchanged.
- Given persona support with a required tool name, then it never reaches the gate (`isEnabled` and Sentry unread).
- Given the three CRM writes, switch set, approval wired, flag seam true, then `isEnabled` is not called, the card is sent, and a Reject selection denies; with approval absent the same.
- Given the registry function with `crmLead` true and the real C4 builder, then the registered set contains narrate, summarize, `edit_c4_diagram` and the seven CRM tools, every one explicitly in `TOOL_TIER_MAP`, no member of `APPROVAL_REQUIRED_TOOLS`, every registered gated tool in `APPROVAL_EXEMPT_TOOLS` (integration-ish: imports the cc module graph in `beforeAll`).
- Given two `realSdkQueryFactory` invocations, then the captured `ctx.deps.approval.grants` objects are distinct, both `enforcing === false`, `deps.approval.workspaceId` equals the resolved workspace, `deps.approvalFailClosed === true`, and the captured options' final `allowedTools` contains no `APPROVAL_REQUIRED_TOOLS` member.
- Given `createApprovalGateDeps` built with an empty `repoSlug`, then a repo-binding tool's server-derived resolution throws and the gate denies (existing behavior, asserted once so a connected-repo-less cc Query is covered).
- Self-test: the sweep helper reports a fake required tool.
- Regression property: for every member of `APPROVAL_REQUIRED_TOOLS`, `TOOL_TIER_MAP[tool] === "gated"` (the fail-closed branch lives inside the gated tier; an auto-approve tier would bypass it silently).

## Test Plan (how verification is run)

Per the pipeline ruling, CI is the ship gate: do not wait on the slow local `--affected` battery; record that in the PR. Run locally, targeted only, from `apps/web-platform`:

1. Phase 1: the four new/edited test files, expecting RED for the right reason.
2. Phase 2/3: the same files green, plus every file returned by `git grep -ln "realSdkQueryFactory" -- test` and the existing `test/approval/` files that exercise `createCanUseTool` (`permission-callback-gated-branch`, `gate-flow`, `gate-deps`, `tools-census`, `decide-boundary`, `runner-census`, `builder-grants-required`).
3. Because two new tests sit under `apps/web-platform/test/`, run the repo-wide containment census: `test/repo-wide-containment.test.ts` (and any `test/repo-wide-contain*` sibling), and keep every fixture free of a parent-directory path segment beyond the app root (use the same `join(__dirname, ...)` depth as `runner-census.test.ts`; a `../` string in a fixture once turned a required job red).
4. `bash apps/web-platform/test/approval-guard1-mutation.test.sh --check-anchors` (fast; anchors only, not the full battery) and `bash plugins/soleur/test/c4-count-parity.test.sh`.
5. `npx tsc --noEmit -p apps/web-platform` equivalent used by the repo, and ESLint on the changed files.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it and sets `requires_cpo_signoff: true`.
- A guard test measures its scan window, not the property it names. What each pin here cannot see: Guard 3 reads one file's text (a second dispatcher file or a runtime reassignment of `deps` would not be seen; the real-factory capture covers the live object); Guard 2 enumerates the output of one registry function (a tool registered by some other route would not appear; the structural leg pins one `createSdkMcpServer(` and no plugin servers); Guard 1's unit tests drive `createCanUseTool` directly, so they cannot prove the SDK consults `canUseTool` for a required tool in cc, nor that the SDK refuses unregistered MCP names first (that stays an SDK behavior documented in the dispatcher and observed by the existing unregistered-tool mirror).
- The production flag seam never throws (it swallows to false); a test that makes `isEnabled` reject proves the gate's own handling, not the production path. State both in the test names.
- A hung flag read is not a fall-through: the call simply waits (the Flagsmith client has a request timeout and an env-mirror fallback, so it resolves to the mirror, normally off); the gate is deliberately not given a second timeout in this PR.
- The grants lifetime is per Query here and per turn in the legacy runner. Because `enforcing` is sticky, a cc Query that ever ran the flow keeps denying required tools after a mid-session flag-off: intended, and stricter.
- Citing line numbers rots: this plan cites content anchors. The Guard 1 battery matches exact strings; do not reformat the two anchor lines in `permission-callback.ts`.
- No `#<number>` other than the two permitted refs may appear in anything this PR writes, including test names, comments and the ADR addendum; sweep with a grep on the diff before pushing.

## Dependencies & Risks

- Risk: a new import in `realSdkQueryFactory` breaks sibling tests that mock modules partially. `cc-dispatcher.ts` already imports `getFreshTenantClient`, so the exposure is `gate.ts`'s other imports (`notify.ts`, `flag.ts`), accessed lazily inside closures; mitigated by running every test that exercises the factory (Phase 2).
- Risk: the cold import of cc-dispatcher in the sweep test exceeds the default budget (measured ~13 s cold in `tools-census`); import in `beforeAll` with a 120 s budget.
- Risk: closure capture of workspace/repo/workspacePath at gate construction versus a mutable active workspace within a Query. Not reachable today; recorded as UNVERIFIED and as a precondition in the ADR addendum.
- No dependency on the broker, credential vending, or any capability listed under scope-out.

## References & Research

- Source anchors: `apps/web-platform/server/permission-callback.ts` (gated branch, `deps.approval && isApprovalRequiredTool(toolName)`), `apps/web-platform/server/approval/gate-flow.ts` (`runApprovalGate`, `APPROVAL_UNAVAILABLE_DENY`), `apps/web-platform/server/approval/gate.ts`, `grants.ts`, `tools.ts`, `ops.ts`, `apps/web-platform/server/cc-dispatcher.ts` (`readCcMcpAllowlist`, `soleurPlatformToolsForTests`, `crmLeadPermissionToolNames`, `realSdkQueryFactory`, `ccDeps`).
- Tests: `apps/web-platform/test/approval/{runner-census,tools-census,permission-callback-gated-branch,gate-flow,gate-deps,flag}.test.ts`, `test/approval-guard1-mutation.test.sh`, `test/cc-dispatcher-real-factory.test.ts`, `test/repo-wide-containment.test.ts`.
- ADRs: ADR-309, ADR-305, ADR-284.
- Rulings: `knowledge-base/project/specs/feat-one-shot-11635-cc-approval-gate/decision-challenges.md`.
- PR body reminder: `Ref #11635`, `Ref #9601`; no close keyword.
