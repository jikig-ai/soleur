---
module: soleur:brainstorm
date: 2026-09-26
problem_type: best_practice
component: development_workflow
symptoms:
  - "issue #8966 item 1 duplicated open issue #8861 verbatim (flag AND views gate)"
  - "issue claimed a test file 'does not exist on origin/main' — it existed with different coverage"
  - "CPO/CLO recommended derive-at-read while CTO recommended a Supabase side table"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: low
tags: [brainstorm, premise-validation, dedupe, adr-corpus, c4, tracker-issue]
---

# Troubleshooting: a multi-item residual tracker was one-third already filed — the dedupe and the prior rejection both lived in the ADR corpus

## Problem

Issue #8966 tracked three C4 hardening residuals. Item 1 turned out to be open issue #8861
verbatim (filed two days earlier by the same audit lineage), and item 3's candidate fix
(persist the save outcome server-side) collided with ADR-059's standing rejection of
durable storage for transient frames. Both facts were invisible in the issue body and
surfaced only by grepping the ADR corpus and sibling issues *per item* before scoping.

## Environment

- Module: `soleur:brainstorm` orchestration (issue-anchored tracker)
- Affected Component: brainstorm premise validation + Phase 2 approach selection
- Date: 2026-09-26

## Symptoms

- The issue asserted "no `c4-render-tenant-config.test.ts` exists on `origin/main`" — the
  file existed (landed two days prior); its coverage was tenant-config sandboxing, not the
  flag parity the issue meant. Verbatim filename claims in issues drift in days.
- The issue counted "three script-side writers"; one was a pure `exec` wrapper — the real
  argv census is derivable, and `plugins/soleur/test/c4-canonical.test.ts` already
  maintained it.
- Two domain leaders recommended different substrates for the same residual; the deciding
  evidence was ADR-059's rejected-alternatives note (Art. 30 surface + write
  amplification), not either leader's reasoning.

## What Didn't Work

**Reading the issue body as the scope of record.** Its writer-count, file-existence, and
"no parity guard" claims were each individually wrong-or-stale even though the *substance*
(parity guard missing) held. An issue body is written once; residual trackers especially
accumulate drift between filing and brainstorm.

## Session Errors

**AskUserQuestion rejected by `pre-ask-technical-fork-gate.sh`**

- **Recovery:** resolved routing (all three items, issue order) via leader consensus and
  proceeded per "resolve it yourself, then ACT".
- **Prevention:** on this harness, brainstorm's Phase-2/Phase-4 AskUserQuestions framed as
  technical choices (pipeline route, substrate, approach) will be blocked — decide via
  evidence, and reserve operator questions for scope/authorization in plain product terms.

**`write` of `spec.md` rejected by `iac-plan-write-guard.sh`**

- **Recovery:** added the documented `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->`
  opt-out with a justification line.
- **Prevention:** the guard scans spec/plan bodies for manual-infra phrasing without
  honoring Non-Goals/"rejected alternative" context — phrase rejection lines to keep the
  mechanism token away from imperative framing, or expect the ack trip.

**`edit` on `spec.md` failed after the rejected `write`**

- **Recovery:** rewrote the file with the ack inline instead of editing.
- **Prevention:** a hook-rejected `write` never lands the file — re-issue the write with
  the fix incorporated rather than following with an `edit`.

**Inherited stale premise from the issue body**

- **Recovery:** premise probe (`git ls-tree origin/main`, `git show`) before framing, per
  the skill's pre-worktree probe.
- **Prevention:** verify every file-existence and count claim in a tracker issue verbatim
  against `origin/main` — the probe caught it because it ran before the worktree, not after.

## Solution

For each item in a multi-item tracker, run three per-item probes before scoping:

1. **Dedupe:** `gh issue list --search "<mechanism keywords>" --state all` + grep ADR
   addenda for the mechanism's literal tokens. #8861 named the same two files; ADR-050's
   2026-09-25 addendum recorded the identical residual.
2. **Write-site census:** derive the argv/invocation set from the repo (git grep +
   invocation-form regex), not from the issue's enumeration — `regenerate-c4-model.sh`
   was an `exec` wrapper miscounted as a third writer.
3. **Prior-rejection check:** when leaders disagree on substrate, grep
   `knowledge-base/engineering/architecture/decisions/` for the mechanism — an ADR's
   rejected-alternatives table is decided law, not one more opinion.

## Why This Works

Tracker issues are authored once and drift; ADR addenda and sibling issues are where
dedupe and prior rejections actually live. The probes are ~3 commands per item and run
before leader spawns would have priced options on a stale floor.

## Prevention

- Verify file-existence claims and enumerations in tracker issues against `origin/main`
  before the worktree — never propagate an issue's census into a leader prompt unchecked.
- When domain leaders split on substrate, adjudicate against the ADR corpus's rejected
  alternatives before weighing recommendations.
- Record the dedupe target in the spec's `refs:` and the PR's `Closes #N` so the umbrella
  and the concrete issue both resolve.

## Related Issues

- See also: `2026-09-25-listener-survival-is-not-channel-survival.md` (item 3's deferred
  hole, recorded verbatim)
- Similar to: `2026-05-11-brainstorm-parallel-domain-and-research-fan-out-and-duplicate-issue-discovery.md`
  (the parent/sibling issue check that inspired probe 1)
