# Decision Challenges — feat-one-shot-7025-rung2-capture-poll-errexit

Recorded headless per ADR-084. These alter operator-stated scope, so they are **surfaced, not
auto-applied**. `ship` renders these into the PR body and files an `action-required` issue.

Source: 6-agent plan review (dhh, kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, cto) of
`knowledge-base/project/plans/2026-07-30-fix-rung2-capture-poll-errexit-plan.md`.

---

## DC-1 — A standalone repo-wide errexit lint was CUT (User-Challenge)

**Operator's stated scope:** *"Also consider pinning that no `run:` step in this workflow
relies on an errexit posture its own `set` line contradicts."*

**What was done instead:** the pin ships as **arm 13d** inside the already-registered
`apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` (~15 lines, zero new files, zero
waivers), scoped to *this workflow* — which is what was literally asked. A standalone
repo-wide lint script + companion test suite + `test-all.sh` registration was cut.

**Why (measured over 637 `run:` bodies):**

| rule | matches |
|---|---|
| reads `${PIPESTATUS[…]}`, no `set +e` (the drafted rule) | **1** — the bug itself |
| `PIPESTATUS` **or** bare `var=$?`, no `set +e` | 16 |
| `set` line omits `-e`, no `set +e` | 56 |

- **0 of the 3** sibling bugs this PR fixes read `PIPESTATUS`, so the drafted lint would have
  caught none of them.
- As drafted it **certifies the false-PASS shape**: `set +e` → pipeline → `set -e` → read
  satisfies the rule and always yields `rc=0` (Kieran P0).
- It bans two *correct* forms (`if pipeline; then … else rc=${PIPESTATUS[0]}`, and
  `pipeline || rc=${PIPESTATUS[0]}` — both errexit-exempt).
- Comparable in-repo lint pairs cost 234–793 LOC.
- **Build-vs-buy measured:** actionlint + shellcheck against a synthesized workflow with the
  exact shape returns only `SC2034 … i appears unused`. Structural — shellcheck lints each
  `run:` body as a standalone script and cannot know GitHub invokes it as `bash -e {0}`. So a
  bespoke lint *is* eventually warranted; that argues for a well-shaped one, not this one.

**Deferred to:** the Phase-3 tracking issue, to be shaped *after* the 56-step audit determines
the real rule and its real population.

**Reviewers converging:** dhh (P0), code-simplicity (rec 1), kieran ("must not ship as
specified"), cto (P1-1), architecture (P2).

**If the operator disagrees:** the lint can be added in a follow-up with the widened trigger
(`PIPESTATUS` **or** unguarded `var=$?`), which is 16 sites and a coherent invariant.

---

## DC-2 — Operator-journey scope was ADDED beyond the stated ask (Taste)

Added: the `## After a PASS` runbook procedure with a literal `gh run download` sequence, the
non-PASS `capture.log` artifact upload, and next-action text in the FAIL/TRANSIENT summaries.

**Rationale:** spec-flow found the artifact→PR path is otherwise a dead end — the retrieval
command exists nowhere in the repo, and on the two paths where diagnosis is needed the
diagnostic file is discarded with the runner. Per `hr-weigh-every-decision-against-target-user-impact`
and the standing note that Soleur operators are non-technical. All are docs/config; none fires
the rehearsal, so the Scope Limits hold.

---

## DC-3 — Two items were moved INLINE that a first draft had deferred (Taste)

1. **The birth-job boot-signal poll** in `apply-web-platform-infra.yml` carries the same
   defect class (`out=$(…); rc=$?` — the whole `rc != 0` path is dead). Architecture and CTO
   independently converged on fixing it inline: the operator's path is fix rung 2 → dispatch
   rung 2 → dispatch the birth → hit this. Deferring ships the identical failure on the very
   next dispatch.
2. **The `teardown_only` / `dry_run` survivor gate** — a `teardown_only=true` dispatch that
   leaves `dry_run` at its default (**true**) runs the destroy but skips the Hetzner survivor
   assertion. One-line `if:` fix, on the step whose purpose is proving no paid box survived,
   and the operator is about to enter exactly that re-dispatch loop.

---

## DC-4 — A `capture_only: <run_id>` recovery input was considered and NOT added (Taste)

spec-flow correctly notes the capture script does not need the host (Better Stack rows outlive
teardown by weeks), so a re-query would be a free retry instead of another paid host, and the
already-written-but-unwired `--verify-only` flag exists for it.

**Not added** because it is a new feature on a workflow this PR is trying to make *correct*,
and the 16-minute deadline it hedges is itself unmeasured. Deferred to the tracking issue.
AC15's live-anchor probe reduces the same risk at zero cost.
