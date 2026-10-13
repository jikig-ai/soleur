---
title: "fix: Bash sandbox worktree-rebind loop — runtime bounded fail-loud guardrail"
type: fix
date: 2026-06-15
issue: 5313
parent_epic: 5240
branch: feat-5240-bash-cwd-worktree-rebind
pr: 5311
app: web-platform
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_security_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-06-15-bash-sandbox-worktree-rebind-brainstorm.md
spec: knowledge-base/project/specs/feat-5240-bash-cwd-worktree-rebind/spec.md
---

# 🐛 fix: Bash sandbox worktree-rebind loop hangs Concierge sessions (#5313, deferred #5240 FR-half)

## Overview

A worktree-creating Concierge session (`/soleur:go → one-shot → worktree-manager.sh`) hung in a
"rebind loop": after creating a worktree the Bash tool's `pwd` stayed at `/home/soleur`, `ls
/workspaces/<uuid>/` returned nothing, `git -C <worktree>` failed — while Read/Edit/Grep read the repo
fine. The one-shot CWD-verification gate (`cd <worktree> && pwd`) could never pass; the agent looped
the verify command 4+ times and the turn died ("Agent stopped responding"). Deferred backend FR-half
of epic #5240; distinct from #5256 (logical reconnect rebind, merged) and #5306 (UI banner, draft).

**Scope (re-scoped twice — see Reconciliation + Review Revisions):** ship a **runtime,
compliance-independent bounded fail-loud guardrail** (the durable core) that detects the looping
CWD-verify pattern from observed Bash tool-results and terminates the turn fast with an honest status,
plus a **lightweight repro** confirming whether #5256 already fixed the binding-drift root cause. **No
`allowWrite`/`denyRead` change** (worktrees are already inside the mount — verified). No new
`WSErrorCode` variant (reuse the existing `WorkflowEnd` error path).

## Research Reconciliation — Premise vs. Codebase (two corrections)

| Premise | Reality (verified) | Plan response |
| --- | --- | --- |
| Worktree unreachable from Bash; needs a mount fix | Worktrees land at `/workspaces/<uuid>/.worktrees/<branch>` — **inside** `allowWrite:[workspacePath]` (`ensure-workspace-repo.ts:143,168`; `worktree-manager.sh:94`). gitdir → inside workspacePath. `isPathInWorkspace` (`sandbox.ts:110`, `startsWith`) passes. | **No `allowWrite` change.** |
| Fix = re-derive bwrap mount/cwd on worktree entry | SDK takes `cwd` only at `query()` (`sdk.d.ts:874`); no per-turn remount. | Config-value remount is not available; guardrail is the fix. |
| `EnterWorktree` is the SDK signal to key on | **`EnterWorktree` is NOT in `@anthropic-ai/claude-agent-sdk`** (Kieran grep: zero hits in `sdk.d.ts`/runner). It is a CLI-harness concept, absent from the Concierge SDK and irrelevant to the fix. | **Detector keys on observed Bash `cd … && pwd` tool-results, not any worktree event.** |
| Root cause is the sandbox config | Computed from `args.workspacePath`, which flows from the resolver **#5256 fixed**. Remaining failure mode is **binding drift** → likely already fixed. | Lightweight repro confirms; guardrail is root-cause-independent. |
| New `WSErrorCode` variant needed for honest status | `runner_runaway` already maps to a `{type:"error"}` honest wire event (`types.ts:438`); operator action is identical ("turn stopped, retry"). | **Reuse the `WorkflowEnd` error path**; add at most one `WorkflowEnd` *status*, NOT a `WSErrorCode` variant + 4-consumer sweep. |

**Net durable deliverable:** a **runtime detector** (compliance-independent) that fires on the looping
CWD-verify pattern. The mount work the brainstorm imagined is unnecessary.

## Review Revisions (4-agent plan-review: DHH, Kieran, Simplicity, SpecFlow)

The v1 plan keyed FR2.2 on a *cooperative marker the agent emits* — but the whole premise is the agent
**ignores prose contracts** (it ignored "abort"). Simplicity + SpecFlow + Kieran all flagged this as the
load-bearing hole. **The detector is now command-pattern-driven** off `extractBashToolResults`
(`soleur-go-runner.ts:696`), requiring zero agent cooperation. Other applied cuts: dropped the
speculative FR1.3 pre-built fix (→ a gated decision tree), dropped the `WSErrorCode` variant + union
sweep (→ reuse `WorkflowEnd` error path), scoped the prose gate to one-shot only, added the Zod-enum
duplicate (C2) and the two render surfaces (C3) to Files-to-Edit, fixed citations (I1/I2).

## As-Built Reconciliation (post-implementation, 2026-06-15)

The implemented design is simpler than C2/C3 anticipated — those plan sections are retained for
provenance but are **stale vs. the shipped diff** (do not "restore" the edits they describe):
- **C2 (Zod-enum duplicate):** dissolved. `WORKFLOW_END_STATUSES` (`lib/types.ts`) is a single-source
  tuple that `ws-zod-schemas.ts:501` consumes via `z.enum(...)` — NO duplicate enum to update. The new
  status propagates automatically; `_AssertWorkflowEndStatusMatches` + 2 exhaustive `Record` rails are
  tsc-enforced.
- **C3 (two render-surface edits):** not needed. `worktree_enter_failed` is intentionally NOT in
  `TERMINAL_WORKFLOW_END_STATUSES`, so cc-dispatcher routes it through the existing *recoverable* `error`
  frame carrying the `WORKFLOW_END_USER_MESSAGES` honest copy — no `chat-surface.tsx` /
  `message-bubble.tsx` edit was required to displace the false "Agent stopped responding" banner.
- **I2 (WSErrorCode if-chain):** N/A — the design uses a `WorkflowEnd` status, not a `WSErrorCode`
  variant, so the `ws-client.ts:883` if-chain Kieran flagged is not a consumer.

Verified by the 4-agent post-implementation review (security-sentinel + CTO APPROVE; user-impact +
code-quality CONCUR after the one P2 regex-tightening fix). Net new issues filed: 0.

## User-Brand Impact

**If this lands broken:** a worktree-creating turn loops and dies with "Agent stopped responding" — the
most trust-destroying state a non-technical operator sees, on the brand's headline "AI org that does
real git work in your repo" path. The guardrail's over-suppression failure mode would hide a genuine
hang behind a spinner; the genuine-hang exit MUST be preserved (FR2.4).

**If this leaks:** N/A for data — but the cross-tenant `denyRead:["/workspaces"]` boundary is
load-bearing isolation; letting Bash read sibling `/workspaces/<other>` would be a cross-tenant
incident. This plan does NOT touch that boundary (AC5).

**Brand-survival threshold:** `single-user incident` → `requires_cpo_signoff: true` (CPO covered by
#5240 brainstorm carry-forward); `requires_security_signoff: true` (security-sentinel at review);
`user-impact-reviewer` at PR time.

## Root Cause (verified)

File tools run **in-process** (Node `fs`, full FS visibility, not bwrap-sandboxed); **Bash runs in a
bwrap sandbox** with mount + `cwd` frozen once per `query()` (`agent-runner-query-options.ts:149`;
`agent-runner-sandbox-config.ts:92-95`). Worktrees live *inside* `workspacePath`, so they are reachable
when `workspacePath` resolves correctly — the failure reduces to **binding drift** (mount/cwd computed
from a wrong-`workspace_id` path), the physical sibling of #5256's logical fix. Separately, the one-shot
CWD gate (`one-shot/SKILL.md:70-76`) says "abort on mismatch" but has **no enforced bound**, so a
non-compliant agent loops until the 10-min runaway breaker fires with a generic status.

## Desired Fix

### FR1 — Lightweight repro + root-cause confirmation (gates FR1.3 only)

- **FR1.1 (repro, Phase 0):** confirm whether a mid-session worktree at
  `/workspaces/<uuid>/.worktrees/<b>` is `cd`/`ls`/`git -C`-able from the Bash sandbox under the
  **current (post-#5256)** resolver. Record the verdict. Lightweight — read-through + a targeted check,
  not a heavy bwrap harness (the guardrail tests are the durable artifact).
- **FR1.2 (guardrail regression test — re-aimed):** the durable test asserts the **guardrail behavior**
  (bounded detection → honest terminal status), NOT worktree-reachability (a `startsWith` tautology that
  can't catch resolver drift — that is #5256's territory). Covered by AC4/AC6.
- **FR1.3 (gated decision tree — NO pre-built fix):** act on FR1.1's verdict:
  - **(i) reachable post-#5256:** FR1.3 is a no-op; document "root cause fixed by #5256; #5313 ships the
    safety net." (Most likely outcome.)
  - **(ii) residual binding drift (wrong `workspace_id`):** add the minimal physical companion to #5256
    (ensure the value flowing to `cwd`/`allowWrite` is the same resolved `workspace_id`). Narrow.
  - **(iii) cwd-frozen-at-root (the original symptom) — NO in-scope fix exists** (cwd is `query()`-only,
    no remount API): **STOP, do not expand this PR**, file a follow-up routing to the deferred
    *skip-worktrees-in-sandbox* re-scope.
  - **(iv) `allowWrite`-child-vs-`denyRead`-parent precedence:** document the precedence + add a test;
    no code fix (boundary stays untouched, AC5).

### FR2 — Runtime bounded fail-loud guardrail (durable core, compliance-independent)

- **FR2.1 (prose gate — advisory, cheap, NOT load-bearing):** the one-shot CWD gate
  (`one-shot/SKILL.md:70-76` only — not a repo-wide sweep) SHOULD stop after ≤3 attempts. This is a
  near-free comment edit; it is explicitly NOT counted as protection (the live agent ignored "abort").
- **FR2.2 (runtime detector — LOAD-BEARING, agent-independent):** in the runner's existing Bash
  tool-result path (`extractBashToolResults`, `soleur-go-runner.ts:696`), detect **N=3 consecutive
  near-identical CWD-verification commands** (the `cd <path> && pwd` / `git -C <path>` verification
  shape) whose output shows a persistent mismatch (`pwd` ≠ expected worktree path), and terminate the
  turn. **N=3 rationale:** the observed loop ran 4+ identical iterations; 3 is below that and well above
  transient-fs jitter (model the counter on the existing `LEADER_MAX_TURNS` pattern,
  `agent-on-spawn-requested.ts:323`). No agent-emitted marker — the detector keys on observed commands,
  so it fires even when the agent ignores the prose gate.
- **FR2.3 (honest terminal status — reuse `WorkflowEnd`, single new status):** emit a `WorkflowEnd`
  with a new `status: "worktree_enter_failed"` (extend the discriminator union at
  `soleur-go-runner.ts:748-762`; the `_AssertWorkflowEndStatusMatches` rail at `:789` forces
  exhaustiveness — one compiler-enforced site, NOT the `WSErrorCode` 4-consumer sweep). Mirror via
  `reportSilentFallback(err, { feature: "agent-sandbox", op: "worktree_enter", extra: { expectedPath,
  observedCwd, attempts } })` — error tier, NOT `mirrorP0Deduped` (that pages oncall; this is a
  degraded-path operator error, safe because AC5 keeps the cross-tenant boundary intact).
  - **C2 — update the Zod duplicate:** `WorkflowEnd`/wire status has a hand-maintained `z.enum` duplicate
    in `ws-zod-schemas.ts` (the `WSErrorCode` precedent is at `:439-468`). A type-symbol grep MISSES it
    (it inlines literals). Add `worktree_enter_failed` to the Zod enum or the server emits a status that
    fails wire validation and never reaches the client.
  - **C3 — honest render, name both surfaces:** the failure must NOT render the literal "Agent stopped
    responding after: …" at `message-bubble.tsx:369-391`. Determine which surface fires for a
    `WorkflowEnd`-error and add an explicit honest title ("Couldn't enter the workspace — retry?") at
    `chat-surface.tsx:699-711` (the if/else title chain currently falls through to "Connection Error").
- **FR2.4 (single-terminal invariant + preserve genuine-hang exit):** emitting `worktree_enter_failed`
  MUST `clearTurnHardCap` (`soleur-go-runner.ts:1730`) so the armed 10-min runaway timer cannot
  double-fire a second `WorkflowEnd`. A turn with NO CWD-verify-loop signal still terminates via the
  existing runaway breaker — we add a *faster, more specific* exit, we do not remove the existing one
  (`2026-05-05-defense-relaxation-must-name-new-ceiling.md`).

## Files to Edit

- `plugins/soleur/skills/one-shot/SKILL.md:70-76` (FR2.1) — bound the CWD gate prose to ≤3. **Scoped to
  this one gate**; if a literal Task-prompt copy of the gate exists in plan/work/deepen-plan, fix only an
  exact copy (no broad `&& pwd` grep — it false-matches 10+ unrelated scripts).
- `apps/web-platform/server/soleur-go-runner.ts` (FR2.2/2.3/2.4) — detector in the
  `extractBashToolResults` path (`:696`); new `WorkflowEnd` status in the discriminator union
  (`:748-762`, assert at `:789`); emission + `clearTurnHardCap` (`:1730`); `reportSilentFallback`.
- `apps/web-platform/lib/types.ts` — add `worktree_enter_failed` to the `WorkflowEnd` status union
  (NOT `WSErrorCode`, which ends at `:161`).
- `apps/web-platform/lib/ws-zod-schemas.ts` (**C2**) — add `worktree_enter_failed` to the hand-maintained
  `z.enum` for the `WorkflowEnd`/wire status. **Sweep by grepping the literal status members, not the
  type symbol** (the enum inlines literals; a type-name grep misses it).
- `apps/web-platform/components/chat/chat-surface.tsx:699-711` (**C3**) — add the honest ErrorCard title
  branch for the worktree-enter failure.
- `apps/web-platform/components/chat/message-bubble.tsx:369-391` (**C3**) — ensure the worktree-enter
  failure does NOT render the false "Agent stopped responding" literal; confirm which surface fires.
- `apps/web-platform/lib/ws-client.ts:883-931` (**I2**) — if the status surfaces here, this is an
  **if-chain, NOT an exhaustive switch** → `tsc` will NOT flag a missing branch; add it by hand.
- `apps/web-platform/test/` — guardrail detector test + double-fire/single-terminal test (`.test.ts`,
  node project); honest-render test (`.test.tsx`, **DOM project**, `setup-dom.ts` — I3).
- `apps/web-platform/test/agent-runner-helpers.test.ts` — **must stay GREEN unchanged** (AC5 proof the
  sandbox config is untouched; NOT edited unless FR1.3(ii) fires, which must not touch `allowWrite`/`denyRead`).

## Files to Create

None expected (tests append to `test/`).

## Open Code-Review Overlap

7 open `code-review` issues touch the planned files; **none overlap the guardrail / `WorkflowEnd` /
runaway logic** — all Acknowledge:
- `#3243` decompose cc-dispatcher (Ref #3235) — Acknowledge (structural refactor; orthogonal).
- `#3242` tool_use raw-name field (types.ts) — Acknowledge (different concern).
- `#2224` / `#2220` chat-state-machine reducer purity — Acknowledge.
- `#2221` message-bubble memo test — Acknowledge.
- `#3739` observability `reportSilentFallbackWithUser` extraction — Acknowledge (we only *call*
  `reportSilentFallback`; either merge order is conflict-free).
- `#4254` / `#3820` cc-dispatcher fixture / safe-bash — Acknowledge.

None met the fold-in bar. Backlog not net-grown.

## Domain Review

**Domains relevant:** Engineering (CTO — carry-forward from #5240 brainstorm), Product (NONE),
Legal (NONE — see GDPR note).

### Engineering (CTO) — carry-forward

**Status:** reviewed (brainstorm 2026-06-15). **Assessment:** fault is the verification gate looping
with no bound; bounded fail-loud guardrail is the durable fix. YAGNI: mount-visibility, not durability —
no sandbox redesign. Research since confirmed no mount change (worktrees inside `allowWrite`) and the
detector must be runtime/command-pattern-driven (not a cooperative marker). ADR only if FR1.3(ii) fires.

### Product/UX Gate

**Tier:** none. The only user-facing output is an honest error title reusing the existing ErrorCard
render path (`chat-surface.tsx`); `## Files to Create` is empty; no new `components/**/*.tsx` /
`app/**/page.tsx` / `app/**/layout.tsx`. C3 adds ONE title-branch literal to an existing card — not a
new surface. Phase 3.55 visual-design not triggered.

### GDPR / Compliance

Considered (single-user-incident trigger). **No regulated-data surface touched.** No
schema/migration/auth/API-PII change; the error message carries a worktree path (not PII);
`reportSilentFallback` already hashes userId. The cross-tenant `denyRead:["/workspaces"]` boundary is
explicitly **preserved (AC5)** — the fix never weakens isolation.

## Infrastructure (IaC)

None. No `allowWrite`/`denyRead`/seccomp/AppArmor/Docker-bind change (AC5). Pure TS + skill-prose change
against already-provisioned infra. Phase 2.8 scan: no new server/secret/cron/vendor/DNS.

## Observability

```yaml
liveness_signal:
  what: "worktree_enter_failed WorkflowEnd emitted when the runtime detector sees N=3 looping CWD-verify commands; PLUS a detection-rate metric so a silently-dead detector (zero fires when loops occur) is visible"
  cadence: "per-occurrence (event-driven)"
  alert_target: "Sentry feature:agent-sandbox, op:worktree_enter (error tier, no page)"
  configured_in: "apps/web-platform/server/soleur-go-runner.ts (detector + emit) + observability.ts reportSilentFallback (existing)"
error_reporting:
  destination: "Sentry via reportSilentFallback(err, { feature:'agent-sandbox', op:'worktree_enter', extra:{ expectedPath, observedCwd, attempts } }) — error tier, no oncall page"
  fail_loud: "yes — runtime detector fires after ≤3 looping commands → explicit worktree_enter_failed WorkflowEnd + honest render; never a silent loop, never a silent solo-fallback"
failure_modes:
  - mode: "Detector silently dead (loop occurs but never fires — e.g., command-shape match drifts)"
    detection: "detection-rate metric + AC: a unit test feeds 3 real looping cd&&pwd tool-results through extractBashToolResults → asserts exactly one worktree_enter_failed WorkflowEnd"
    alert_route: "CI round-trip test; Sentry op:worktree_enter zero-rate is the runtime canary"
  - mode: "Guardrail too aggressive — suppresses a genuine hang"
    detection: "AC6: a turn with no CWD-verify-loop signal still terminates via the runaway breaker"
    alert_route: "CI test + existing runner_runaway Sentry path (unchanged)"
  - mode: "Double-terminal: worktree_enter_failed + runaway both fire"
    detection: "AC: marker arrives while runaway armed → exactly one WorkflowEnd; emission calls clearTurnHardCap"
    alert_route: "CI test"
  - mode: "False 'Agent stopped responding' rendered instead of honest title"
    detection: "AC7 render test (.test.tsx, DOM project): asserts the honest title, not the message-bubble literal"
    alert_route: "CI render test"
  - mode: "Binding drift recurs post-#5256"
    detection: "FR1.1 repro verdict; Sentry op:worktree_enter if it fires at runtime"
    alert_route: "Sentry + repro"
logs:
  where: "Sentry (reportSilentFallback) + pino structured log with expectedPath/observedCwd/attempts. No new persisted store; debug-stream events stay ephemeral."
  retention: "Sentry default (conversation-class); no new retention surface"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/<detector-test>.test.ts test/<render-test>.test.tsx test/agent-runner-helpers.test.ts"
  expected_output: "detector + double-fire + render tests green; agent-runner-helpers GREEN UNCHANGED (AC5)"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (FR2.2 round-trip — the load-bearing test):** a unit test feeds **3 real consecutive
      `cd <path> && pwd` Bash tool-results with mismatched `pwd`** through the detector
      (`extractBashToolResults` path) and asserts exactly one `worktree_enter_failed` `WorkflowEnd` is
      emitted. (Closes the v1 gap where the prose marker and the detector could diverge silently.)
- [ ] **AC2 (FR1.1):** repro verdict recorded (reachable post-#5256 → FR1.3 no-op; or a named residual
      routed per the FR1.3 decision tree). A *behavioral* note, paired with AC1/AC6 tests — not a
      standalone "we wrote it down" check.
- [ ] **AC3 (FR2.1):** the one-shot CWD gate prose bounds to ≤3 (advisory layer; not the enforcement).
- [ ] **AC4 (FR2.3 — honest status + Zod):** `worktree_enter_failed` is a valid `WorkflowEnd` status,
      added to BOTH `lib/types.ts` AND the `ws-zod-schemas.ts` `z.enum` duplicate; a test emits it and
      asserts it passes wire-schema validation (guards the C2 runtime-Zod-throw class).
- [ ] **AC5 (G3 — boundary untouched):** `agent-runner-helpers.test.ts` GREEN UNCHANGED; `git diff`
      touches no `allowWrite`/`denyRead`/seccomp/AppArmor/Docker-bind; security-sentinel confirms no new
      cross-tenant read surface.
- [ ] **AC6 (FR2.4 — genuine-hang preserved):** a turn with no CWD-verify-loop signal still terminates
      via the runaway breaker (no permanent suppression).
- [ ] **AC7 (C3 — honest render):** render test (`.test.tsx`, DOM project) asserts the failure shows the
      honest title, NOT "Agent stopped responding" (`message-bubble.tsx:369-391`).
- [ ] **AC8 (FR2.4 — single terminal):** test proves emitting `worktree_enter_failed` clears the hardcap
      timer (`clearTurnHardCap`) → exactly one `WorkflowEnd` when the runaway timer was armed.
- [ ] **AC9 (consumer sweep — tsc + manual if-chains):** `WorkflowEnd` status exhaustiveness via
      `_AssertWorkflowEndStatusMatches` + `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
      clean; AND manually verify `ws-client.ts:883-931` (if-chain, `tsc`-blind) handles the status if it
      surfaces there.
- [ ] **AC10 (full suite):** `cd apps/web-platform && ./node_modules/.bin/vitest run <changed-test-files>`
      green (node `.test.ts` + DOM `.test.tsx` projects).
- [ ] **AC11 (PR body):** `Ref #5240` (epic stays OPEN) + `Closes #5313`.

### Post-merge (operator)

- [ ] **AC12:** None. Client+server TS + skill-prose change shipped via `web-platform-release.yml`
      (path-filtered on `apps/web-platform/**`; merge IS the deploy + container restart); skill-prose
      ships in the plugin. No migration/infra/secret/operator step. (Automation-feasibility gate:
      nothing to automate post-merge.)

## Test Scenarios

1. **Detector fires (AC1):** 3 mismatched `cd && pwd` tool-results → one `worktree_enter_failed`.
2. **Detector does NOT over-fire:** 2 mismatched then a matching `pwd` → no termination.
3. **Genuine-hang preserved (AC6):** no CWD-verify-loop signal → runaway breaker still terminates.
4. **Single terminal (AC8):** loop detected while runaway armed → exactly one `WorkflowEnd`, hardcap cleared.
5. **Honest render (AC7):** `worktree_enter_failed` → honest title, not the false banner.
6. **Wire-schema (AC4):** status passes `ws-zod-schemas.ts` validation (C2 guard).
7. **Boundary untouched (AC5):** `agent-runner-helpers.test.ts` unchanged + green.

## Hypotheses

Not a network/SSH issue (Phase 1.4 N/A). File-vs-Bash sandbox asymmetry; root cause binding drift
(likely #5256-fixed) + an unbounded gate. The fix is detection+termination, independent of root cause.

## Alternative Approaches Considered

| Approach | Why not chosen |
| --- | --- |
| Widen `allowWrite` to add a worktrees mount | Worktrees already inside `allowWrite` — redundant; trips the drift-guard; needs security review for nothing. |
| Per-turn bwrap cwd/mount remount | SDK exposes `cwd` only at `query()`; no remount API. Infeasible. |
| Cooperative marker emitted by the agent (v1 design) | The agent ignores prose contracts (it ignored "abort"); a marker is equally ignorable. Detector must key on observed commands. |
| New `WSErrorCode` variant + 4-consumer sweep | `runner_runaway` already carries an honest error wire path; one `WorkflowEnd` status is the minimal honest distinction. |
| Skip worktree creation in the sandbox | Rejected at brainstorm; the fallback for FR1.3(iii) if cwd-frozen-at-root proves unfixable in scope. |
| Rely only on the 10-min runaway breaker | Too slow — 10 min of a visibly-looping agent is the brand-trust catastrophe; a ≤3 fast exit is the point. |
| Build a new stuck-loop detector subsystem | YAGNI — reuse `extractBashToolResults` + the `WorkflowEnd` discriminator + `LEADER_MAX_TURNS` counter pattern. |

## Sharp Edges

- **The detector MUST be command-pattern-driven, not a cooperative marker** — the agent ignores prose
  (it ignored "abort"). Key on `extractBashToolResults` observed commands. This is the whole fix; do not
  regress it to a marker.
- **The wire status union has a hand-maintained Zod `z.enum` duplicate** (`ws-zod-schemas.ts`, precedent
  `:439-468`). A `grep <TypeName>` MISSES it (literals inlined). Grep the literal members; a missing
  entry passes `tsc` and THROWS at the wire boundary (`2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md`).
- **Two render surfaces, different copy:** `chat-surface.tsx:699-711` (if/else title chain → "Connection
  Error" fallthrough) vs `message-bubble.tsx:369-391` (hard-coded "Agent stopped responding"). Name which
  fires; do NOT let the worktree failure render the false banner (AC7).
- **`ws-client.ts:883-931` is an if-chain, not an exhaustive switch** — `tsc` will NOT flag a missing
  branch (AC9 manual check); the union-widening grep convention assumes switches.
- **Render test is `.test.tsx` in the DOM project** (`vitest.config.ts` split projects; `setup-dom.ts`);
  a `.test.ts` or co-located component test is silently not run.
- **Single-terminal invariant:** emit `worktree_enter_failed` → `clearTurnHardCap` (`:1730`) or the armed
  runaway timer double-fires a second `WorkflowEnd` (AC8).
- **`reportSilentFallback`, NOT `mirrorP0Deduped`** — degraded-path operator error, not a write-boundary
  breach; `mirrorP0Deduped` pages oncall. Safe because AC5 keeps the boundary intact.
- **Test runner is vitest** (`./node_modules/.bin/vitest run`), typecheck `cd apps/web-platform &&
  ./node_modules/.bin/tsc --noEmit` (no root `workspaces` — `npm run -w` fails).
- A plan whose `## User-Brand Impact` is empty/placeholder fails `deepen-plan` Phase 4.6 — filled
  (threshold `single-user incident`).

## Deferred / Out of Scope

- Physical workspace durability (#5240 item #2), in-flight work durability (#4) — under epic #5240.
- Skip-worktrees-in-sandbox — only if FR1.3(iii) (cwd-frozen-at-root, unfixable in scope) fires.

## References

- `apps/web-platform/server/agent-runner-sandbox-config.ts:92-95`; `agent-runner-query-options.ts:149,188`
- `apps/web-platform/server/ensure-workspace-repo.ts:143,168`; `worktree-manager.sh:94,191`; `sandbox.ts:110`
- `apps/web-platform/server/soleur-go-runner.ts:696` (`extractBashToolResults`), `:748-762`
  (`runner_runaway` discriminator), `:789` (`_AssertWorkflowEndStatusMatches`), `:1730`
  (`clearTurnHardCap`), `:1736` (`armTurnHardCap`), emission `:1771-1780,1866-1875`, iterator `:2196`
- `apps/web-platform/lib/types.ts:130-161` (`WSErrorCode`), `:438` (`runner_runaway`→error wire),
  `WorkflowEnd` status union
- `apps/web-platform/lib/ws-zod-schemas.ts:439-468` (hand-maintained `z.enum` duplicate — C2)
- `apps/web-platform/components/chat/chat-surface.tsx:699-711`; `message-bubble.tsx:369-391`;
  `ws-client.ts:883-931`
- `apps/web-platform/server/observability.ts:183` (`reportSilentFallback`), `:550` (`mirrorP0Deduped`)
- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts:323` (`LEADER_MAX_TURNS`);
  `constants.ts:17`
- `apps/web-platform/test/agent-runner-helpers.test.ts:36-119` (sandbox drift-guard — AC5);
  `vitest.config.ts` (split node/DOM projects)
- `plugins/soleur/skills/one-shot/SKILL.md:56,70-76` (CWD gate)
- Learnings: `2026-06-15-bash-bwrap-sandbox-mount-visibility-vs-cwd-persistence.md`;
  `2026-03-18-ralph-loop-stuck-detection-hardening.md` + `2026-03-05-ralph-loop-stuck-detection-shell-counter.md`
  (bounded stuck-detection pattern); `2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md` (Zod authoritative);
  `2026-05-05-defense-relaxation-must-name-new-ceiling.md` (preserve genuine-hang exit);
  `2026-05-13-claude-agent-sdk-canusetool-not-invoked-for-unknown-mcp-tools.md` (detect at the iterator)
- Parent: `2026-06-14-durable-session-resume-brainstorm.md` (#5240); #5256 (merged logical rebind)
