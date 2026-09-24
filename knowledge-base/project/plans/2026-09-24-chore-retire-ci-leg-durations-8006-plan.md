---
title: "chore: Retire the ci-leg-durations-8006 soak probe"
type: chore
date: 2026-09-24
slug: chore-retire-ci-leg-durations-8006
branch: chore-retire-ci-leg-durations-8006
issue: 8006
lane: cross-domain
---

# chore: Retire the ci-leg-durations-8006 soak probe

Tracker issue 8006 auto-closed on PASS at 2026-09-24T19:24:18Z — the follow-through
sweeper's final comment records `examined=20 qualifying=20 breached=0`, every
`test-scripts*` leg under the 900 s budget. The soak is complete. Per the probe's
own `RETIREMENT:` note ("When #8006 closes, delete this file, its .test.sh, and the
`run_suite` line in scripts/test-all.sh") and the follow-through convention
(`knowledge-base/engineering/operations/runbooks/followthrough-convention.md` —
"when the tracker closes, the probe file usually goes with it — and anything else
that references it"), delete the probe and every live-code reference to it.

Precedent: commit `6957cf654d` (PR 8273) — identical retirement shape for the
issue-8159 postmerge-evidence probe: probe file + test file deleted, `run_suite`
registration replaced by a two-line retired note.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — worst case
  is a red `test-scripts` CI leg on this repo's own PRs (a phantom shard-manifest
  label reddens `scripts-shard-manifest.test.sh`), visible only to maintainers.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  exposure vector — the change deletes a measurement script and a manifest row;
  it touches no credential, data store, or user-data path.
- **Brand-survival threshold:** `none`

## Research Insights

**Premise validation (Phase 0.6) — all cited artifacts verified:**

- `gh issue view 8006` → `state: CLOSED`, `closedAt: 2026-09-24T19:24:18Z`; final
  comment is "Sweeper run: PASS (2026-09-24T19:24:17Z) … `summary: examined=20
  qualifying=20 breached=0` … Auto-closing per follow-through convention." The
  close is the sweeper's own PASS verdict, not an operator judgment — retirement
  is unconditional.
- `scripts/followthroughs/ci-leg-durations-8006.sh` exists; header line 2 names it
  the post-carve-out soak probe and the `RETIREMENT:` line prescribes this exact
  deletion.
- `scripts/followthroughs/ci-leg-durations-8006.test.sh` exists (exit-code harness).
- Precedent commit `6957cf654d` confirmed: deleted probe + test + registration in
  `scripts/test-all.sh` (12-line block → 2-line retired note).
- `followthrough-convention.md` confirms the convention and warns that unlisted
  references ("a parity arm in another suite, a back-pointer comment in a third
  file, a runbook section") are left dangling — the census below is the remedy.

**Premise gap found:** the delegation brief enumerated 4 touch-points; the census
found a **5th the brief missed** — `scripts/suite-shard-legs.tsv:264` carries the
row `scripts/ci-leg-durations-8006⇥6`. `plugins/soleur/test/scripts-shard-manifest.test.sh`
(phantom-label arm, "labels ⊆ registered set") goes RED if the row survives the
`run_suite` removal — this is exactly the STALE-SUBSET drift shape that suite
exists to catch. The row must be deleted in the same commit. Hand-edit, not a
regen: `regenerate-shard-manifest.py` re-derives ALL assignments from a CI run id
and would rewrite the whole table — out of scope for a deletion chore.

**Reference census (`git grep ci-leg-durations-8006` + unnumbered
`ci-leg-durations` / `leg.durations` variants) — complete live-code footprint:**

| Site | Disposition |
|---|---|
| `scripts/followthroughs/ci-leg-durations-8006.sh` | delete file |
| `scripts/followthroughs/ci-leg-durations-8006.test.sh` | delete file |
| `scripts/test-all.sh` comment block + `run_suite` (lines ~3445–3453) | replace with 2-line retired note (precedent shape) |
| `scripts/suite-shard-legs.tsv:264` (`scripts/ci-leg-durations-8006⇥6`) | delete row — **brief missed this** |
| `knowledge-base/…/ci-test-scripts-sharding.md` (~lines 195–196) bullet under `## Verification surfaces` | delete bullet — section lists *live* surfaces |
| `knowledge-base/project/{plans,specs}/…`, ADR-238, archived specs | historical records — leave untouched |
| `#8006` comments in `ci.yml`, `test-all.sh` (lines ~747/815/826/1022/1133), `plugins/soleur/test/*`, `regenerate-shard-manifest.py`, `pr-fanout-ledger.txt` | describe the shard carve-out/topology (still live and true) — leave untouched |

No consumer filters on the probe's output or label beyond the manifest row
(sweeper reads the directive from the issue body — now closed; no Sentry/Better
Stack alert, no parity arm in another suite). No `secrets=` wiring is probe-specific
(`GH_TOKEN` in `scheduled-followthrough-sweeper.yml` is shared).

**Property List (Phase 0.6b):** (a) the retired probe leaves no live-code
reference that a guard asserts against; (b) the deletion is one commit, matching
precedent shape; (c) the runbook stops describing a dead probe as a live
verification surface. **Cut List:** none — no new mechanism is proposed; the
change is pure deletion plus one comment note.

**Learnings applied:**

- `2026-05-09-retirement-cleanup-grep-must-scan-full-class-not-named-id.md` — the
  residual-zero AC greps the *unnumbered* stem (`ci-leg-durations`) across all
  live-code dirs, not just the named id, and each edited file is re-checked for
  remaining `8006` mentions that must be historical/topological only.
- Sharp-edges catalogue (plan Step 6.5): diff-scope AC avoided; gate-green claims
  use each gate's own invocation (`bash plugins/soleur/test/scripts-shard-*.test.sh`),
  never a hand-reconstruction; absence-claim ACs are paired with a positive
  assertion (adjacent suite registrations still present).

**Open Code-Review Overlap** (`gh issue list --label code-review`, bodies scanned
for each planned path):

- `#8659` (test-helpers EXIT-trap scope-outs, touches `scripts/test-all.sh`) —
  **acknowledge**: non-overlapping region (we delete lines ~3445–3453; that
  scope-out concerns suite-level trap composition), different concern.
- `#7942` (un-gated `*.mutation.sh` batteries, mentions `scripts/test-all.sh`) —
  **acknowledge**: different concern; this deletion removes a registration, it
  does not add an un-gated suite.

## Files to Delete

- `scripts/followthroughs/ci-leg-durations-8006.sh`
- `scripts/followthroughs/ci-leg-durations-8006.test.sh`

## Files to Edit

- `scripts/test-all.sh` — replace the 9-line block at ~lines 3445–3453 (8-line
  `#8006:` comment + `run_suite "scripts/ci-leg-durations-8006" …` line) with the
  precedent-shaped retired note:
  `# (#8006 retired 2026-09-24 — issue closed; probe script + suite deleted per the script's own RETIREMENT note.)`
- `scripts/suite-shard-legs.tsv` — delete the data row `scripts/ci-leg-durations-8006⇥6`
  (line ~264, between `ci-deploy-sentry-post-fail-6475` and `classify-workflow-transitions`;
  alphabetical order is preserved by the deletion). Do NOT regen the manifest.
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` —
  delete the 2-line bullet at ~lines 195–196 (`- scripts/followthroughs/ci-leg-durations-8006.sh
  — post-merge soak probe; auto-closes …`) under `## Verification surfaces`.

## Implementation Phases

### Phase 1 — Deletion sweep (single commit)

1. `git rm scripts/followthroughs/ci-leg-durations-8006.sh scripts/followthroughs/ci-leg-durations-8006.test.sh`
2. Edit `scripts/test-all.sh`: replace the comment block + `run_suite` line with
   the retired note (precedent `6957cf654d` shape).
3. Edit `scripts/suite-shard-legs.tsv`: delete the `scripts/ci-leg-durations-8006` row.
4. Edit `ci-test-scripts-sharding.md`: delete the probe bullet.
5. Verify (see Acceptance Criteria), commit, push.

**Commit/PR text constraint:** never write `#8006` (hash-prefixed) in the commit
message or PR body — the tracker is CLOSED and a hash ref would post a timeline
event to it. Use "issue 8006" phrasing. No `Closes #` line (nothing to close).
In-file comments keep the repo's `#8006` convention — file contents do not
generate issue events.

## Acceptance Criteria

- [ ] `git ls-files scripts/followthroughs/ | grep -c ci-leg-durations` prints `0`
      (both probe files deleted).
- [ ] `git grep -n "ci-leg-durations" -- scripts/ .github/ plugins/` prints
      nothing — unnumbered-stem census over live-code dirs, not just the named id.
- [ ] `bash plugins/soleur/test/scripts-shard-manifest.test.sh` exits 0 — the
      gate's own invocation proves no phantom manifest label remains.
- [ ] `bash plugins/soleur/test/scripts-shard-totality.test.sh` exits 0 —
      partitions still union exactly to the registered sets.
- [ ] `env -u SCRIPTS_SHARD TEST_GROUP=scripts bash scripts/test-all.sh --enumerate scripts | grep -c ci-leg-durations` prints `0`, AND the same enumerate still lists the adjacent registrations `scripts/anthropic-double-bill-8611`, `scripts/ship-merge-mergebase-verdict-8151`, `scripts/infra-config-activation-7220` (over-deletion check on the edited comment block).
- [ ] `bash -n scripts/test-all.sh` exits 0 (syntax).
- [ ] `grep -n "ci-leg-durations" knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` prints nothing.
- [ ] `git grep -n "8006" scripts/test-all.sh` returns only shard-manifest /
      carve-out context comments and the new retired note — no live-probe
      description survives in an edited file (class-wide residual check).
- [ ] Knowledge-base plans/specs/ADR mentions of `ci-leg-durations-8006` are
      untouched (historical records).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. Mechanical
UI-surface scan of Files to Edit/Delete: no `components/**/*.tsx`, `app/**/page.tsx`,
or other UI-surface path — Product/UX gate does not fire.

## Observability

Skipped per plan Phase 2.9 — this is a deletes-only plan (no new code or infra
surface). The change *removes* an observability probe whose soak completed; CI's
own shard-manifest suite is the guard that catches a botched removal.

## Test Scenarios

- Given the probe files and registration are deleted, when
  `bash plugins/soleur/test/scripts-shard-manifest.test.sh` runs, then it exits 0
  with no phantom-label failure.
- Given the `run_suite` line is removed, when
  `bash scripts/test-all.sh --enumerate scripts` runs, then no
  `ci-leg-durations` label is emitted and the count of registered suites drops by
  exactly one versus `origin/main`.
- Given the tsv row is removed, when `cut -f1 scripts/suite-shard-legs.tsv | sort -c`
  runs, then order is still sorted and the file retains ≥100 rows (manifest
  density floor).

## Context

- Issue 8006 (`ci: matrix-leg balance — LPT does not deliver insertion-stability
  and the chokepoint cannot compute it`) delivered the `test-scripts*` carve-out
  and the duration-aware shard manifests (ADR-240). This chore retires only the
  *post-merge soak probe* that verified the carve-out's effect — the shard
  topology, manifests, and heavy-leg jobs all stay.
- The probe is a one-shot measurement: its verdict already landed (the issue
  close). Nothing consumes its output going forward; the sweeper dispatches
  probes from tracker directives, and a closed tracker carries none.

## References

- Tracker: issue 8006 (closed 2026-09-24, sweeper PASS comment at 19:24:17Z)
- Precedent: commit `6957cf654d` / PR 8273 (issue-8159 probe retirement)
- Convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
  ("when the tracker closes, the probe file usually goes with it")
- Probe RETIREMENT note: `scripts/followthroughs/ci-leg-durations-8006.sh` header
- Manifest guard: `plugins/soleur/test/scripts-shard-manifest.test.sh` §"labels ⊆
  registered set" (phantom-label arm)
