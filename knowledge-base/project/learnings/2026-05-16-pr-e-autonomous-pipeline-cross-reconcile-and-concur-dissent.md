---
date: 2026-05-16
category: best-practices
tags: [autonomous-pipeline, multi-agent-review, scope-out, cross-reconcile, single-user-incident, concur-dissent]
pr: 3922
issue: 3887
related_learnings:
  - 2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md
  - 2026-05-11-scope-out-bundling-hides-cheap-inline-fixes.md
  - 2026-05-04-wrapper-extension-test-mock-chain-sweep.md
---

# PR-E autonomous one-shot pipeline — cross-reconcile + CONCUR-DISSENT in practice

## Problem

PR-E (`feat(runtime): PR-E audit_byok_use writer sweep + is_jti_denied
consumer (#3887)`) drove the full one-shot pipeline (plan → work →
review → resolve → ship) against a single-file auth-domain change
with brand-survival threshold `single-user incident`. The
review-phase mandatory agents (`user-impact-reviewer`,
`data-integrity-guardian`, `security-sentinel`, `semgrep-sast`) all
fired. The 11-agent fan-out produced 25+ findings spanning P1
(performance Sentry-debounce) → P3 (forward-looking observability).

Two converging concerns surfaced that the project's existing
workflow patterns are designed for but had not previously been
exercised on the same PR:

1. **Two `user-impact-reviewer` P1s contested an architectural
   design lock** (deny-list as Node-process-local kill-switch vs
   PostgREST-side RLS predicate enforcement) — single-agent HIGH
   against silent/explicitly-endorsing agents. The
   cross-reconcile-triad downgrade rule (from
   `2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md`)
   applies but it had not previously been documented on a
   `user-impact-reviewer`-driven session.

2. **`code-simplicity-reviewer` DISSENTed on one item in an 8-item
   scope-out bundle** (item #7,
   `mapRuntimeAuthCauseToErrorCode` parity) — the bundling-pathology
   defense from
   `2026-05-11-scope-out-bundling-hides-cheap-inline-fixes.md`
   working as designed. Per-finding triage flipped #7 to fix-inline
   without disrupting the other 7 deferrals.

## Solution

**Cross-reconcile (user-impact P1 downgrade):**
- 5+ orthogonal agents (architecture-strategist, security-sentinel,
  data-integrity-guardian, agent-native-reviewer, semgrep-sast)
  either explicitly endorsed the operator-driven revocation
  architectural decision OR did not surface the cross-process JWT
  exposure as a blocker.
- 1 agent (`user-impact-reviewer`) flagged both as P1.
- Per the cross-reconcile-triad rule, single-agent HIGH against
  silent/contradicting agents is the modal false-positive shape.
- Downgrade disposition: document the residual exposure in the
  plan's `## User-Brand Impact` table (new "Residual exposure"
  column), file the two architectural pivots as scope-out follow-ups
  (#3930 admin `revoke_jti` RPC, #3932 PostgREST-side RLS
  predicate), and ship.
- The user-impact-reviewer's framing was substantively correct on
  the technical surface (the deny-list IS only Node-process-local);
  the disagreement was about severity, not about facts. Rewriting
  the plan's User-Brand Impact section to be explicit about which
  surfaces this PR closes vs which remain open turned the
  reviewer's concern into improved documentation rather than a
  blocker.

**CONCUR-DISSENT (per-finding flip):**
- Initial bundle submitted 8 plan-prescribed deferrals.
- code-simplicity-reviewer DISSENTed on #7
  (`mapRuntimeAuthCauseToErrorCode`): "PR-E introduces the third
  union member `denied_jti` and the operator-distinguishability
  rationale is the direct observability gap this PR creates —
  single-file <30 LOC change."
- Flipped #7 to fix-inline, shipped the mapper helper +
  exhaustive-switch unit test in commit `0b043feb`.
- Re-invoked CONCUR on the 7-item residual bundle; got CONCUR.
- Per the bundling learning: don't argue back, don't refile the
  full bundle inline, don't refile-as-is. Per-finding triage.

**Both patterns landed without exception filings.** The autonomous
pipeline successfully:
- Plan + spec + tasks produced via plan-and-deepen subagent
- 22 tests written + green on first run (4 suites)
- 11-agent review fan-out (1 P1, ~9 P2, ~15 P3 + 7 scope-outs)
- All P1+P2 inline fixes applied (commits `a5d9347c`, `0b043feb`)
- 7 scope-outs filed (#3928–#3934) with co-signed CONCUR
- Full webplat suite stable (4478 tests / 415 files)

## Key Insight

The cross-reconcile-triad downgrade rule and the CONCUR-DISSENT
per-finding flip rule were both designed for the failure modes
they caught here. The pipeline's value isn't that every finding is
right — it's that the disagreement protocols work.

**Practical observation:** when `user-impact-reviewer` (a mandatory
agent at the `single-user incident` threshold) raises P1s that
contest an architectural decision the plan documented and other
agents endorsed, the right response is not to argue the agent down
or accept the P1 wholesale — it's to (a) check the cross-reconcile
posture, (b) rewrite the documentation that triggered the agent's
concern to be more explicit about scope, (c) file the deferred
architectural pivots with concrete re-evaluation triggers. The
agent's framing usually exposes documentation drift, not code
defects.

**Workflow observation:** when scope-out bundles include a
mixed-cost mix of items (some genuinely cross-cutting, some small
enough to be fix-inline), code-simplicity-reviewer reliably
identifies the small ones. Bundle filings are not atomic — the
DISSENT case is per-finding by design.

## Session Errors

- **bash-snapshot `ZSH_VERSION` unbound variable under `set -uo pipefail`** — Recovery: visually inspected file list and classified manually as `code` from `.ts` extensions. **Prevention:** review-skill classification snippet (in `plugins/soleur/skills/review/SKILL.md`) should source bash with `: "${ZSH_VERSION:=}"` guard or use a fresh subshell rather than inheriting `.claude/shell-snapshots/snapshot-bash-*.sh`.

- **Bash CWD drift (twice)** — `cd apps/web-platform && <cmd>` persisted across Bash tool calls; subsequent calls assuming CWD = worktree root failed with "No such file or directory". Recovery: prefixed with `cd /home/jean/.../feat-pr-e-audit-byok-jti-deny && <cmd>`. **Prevention:** in pipeline-mode work + review skills, always anchor multi-command sequences with an absolute `cd` at the start of each Bash call. The `Bash` tool's docstring already documents this; the persistent-CWD warning could be hoisted into a single-line reminder at the top of work skill Phase 2's "Test Continuously" section.

- **Mock-dispatcher coverage gap on existing tests** — `tenant-jwt-refresh.test.ts` failed 4/11 on first full webplat run because its `vi.mock("@/lib/supabase/service")` factory's `rpc:` mock didn't dispatch the new `is_jti_denied` RPC; the existing `precheck_jwt_mint` mint-count assertions saw extra calls and failed. Recovery: widened the mock to dispatch by `fn === "is_jti_denied"` and filtered count assertions via `mintCalls()` helper. **Prevention:** the existing learning `2026-05-04-wrapper-extension-test-mock-chain-sweep.md` covers this for `.eq/.select/.in/.maybeSingle` chain extensions; extend the guidance in the work skill's Phase 2 "Follow Existing Patterns" bullet to explicitly include **new RPC consumers added to a function with existing rpc-mock-based tests must sweep `test/**/vi.mock(...rpc` at task-start, not after the first test failure**.

- **Transient component-test flake** in `apps/web-platform/test/kb-chat-sidebar-banner-dismiss.test.tsx` (6/4478 component timeouts on first webplat run; second run clean). Recovery: re-ran the suite, stable green. **Prevention:** no PR-E-specific action — the flake is pre-existing fake-timer brittleness in unrelated component tests. The work skill's "When tests fail and are confirmed pre-existing" workflow gate (`wg-when-tests-fail-and-are-confirmed-pre`) covers this; no addition needed.
