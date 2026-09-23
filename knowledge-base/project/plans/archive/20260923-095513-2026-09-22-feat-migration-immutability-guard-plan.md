---
title: "feat: migration-immutability guard — fail PRs that mutate on-main supabase/migrations files"
date: 2026-09-22
slug: feat-migration-immutability-guard
branch: feat-one-shot-8583-migration-immutability
issue: 8583
closes: [8583]
type: feat
lane: cross-domain
brand_survival_threshold: none
---

# feat: migration-immutability guard — fail PRs that mutate on-main `supabase/migrations` files

## Enhancement Summary

**Deepened on:** 2026-09-22 (sequential fallback — no Task-agent fan-out in this harness)
**Sections enhanced:** Guard Contract (rename-detection hole verified live and made load-bearing),
Technical Considerations (merge_group coverage, apply-path analysis), Deepen-Plan Pass section.

### Key improvements

1. `git diff --name-only` with default rename detection emits only the rename **destination** —
   a `git mv` of an on-main migration would evade a naive enumeration. The guard's diff runs with
   `--no-renames` (verified live in a fixture repo: `R100` collapses to `D`+`A`).
2. The check compares `git ls-tree` mode+blob-sha between base and head, not diff status — so an
   `A`-status file whose path already exists on `origin/main` with different content (the
   add-collides merge race) still fails.
3. Placement in the always-run `detect-changes` job (not the secrets-holding heavy job) closes the
   merge-queue TOCTOU window for free and needs zero required-check/ruleset ABI churn.

### New considerations discovered

- The apply path cannot catch this class at all: `run-migrations.sh` skips filenames already in
  `_schema_migrations` (line ~331 `already_applied` → `skipped`), so an in-place edit is never even
  re-applied — only the `content_sha` drift probe sees it, post-merge, on the push-to-main run.
- Residual sibling gap (out of scope, named below): a PR that adds `NNN_*.sql`, has it applied to
  dev under `ALLOW_UNMERGED_DEV_APPLY=1`, then mutates it in place leaves dev drifted in exactly the
  #8583 shape — the post-section re-probe only warns on PR surfaces. The on-main guard does not
  cover files that are not yet on main.

## Overview

PR #8507 (merge commit `19875b58bc`) edited
`apps/web-platform/supabase/migrations/138_agent_engine_runs.sql` in place after it had already been
applied to dev-Supabase (ledger `content_sha` moved `3a111e09` → `a90ab3e1`). The dev-migration-drift
probe (#7964) detected `applied != main` blob sha and failed `tenant-integration` on main closed.
Nothing prevented the in-place edit from merging — the missing third leg of migration hygiene:

- Leg 1 (#4241): `run-migrations.sh` refuses to apply files not on `origin/main` without
  `ALLOW_UNMERGED_DEV_APPLY=1` (apply-time gate).
- Leg 2 (#7964): the drift probe + scheduled cron detect ledger-vs-main drift (detection layer).
- Leg 3 (this issue, #8583): a PR-time guard that makes on-main migration files immutable —
  behavior changes ship as a new `NNN_*.sql`, never as an edit to a merged file.

## Problem Statement / Motivation

Once a migration file is on `main` it is, for all practical purposes, applied: `tenant-integration`
applies `main`'s migrations to dev on every push, and the ledger records `content_sha`. An in-place
edit then (a) is silently skipped by the runner (`already_applied` short-circuit), (b) drifts the dev
ledger until the next push-to-main probe run reds, and (c) on the 138 precedent required surgical
re-apply because the file was not re-runnable (`CREATE POLICY` without `DROP POLICY IF EXISTS`). The
fix is a cheap pure-git CI check: no DB, no secrets, runs before the heavy suite.

## Proposed Solution

New script `apps/web-platform/scripts/lint-migration-immutability.sh` (sibling of
`lint-migration-fk-preconditions.sh`), wired as a step in the **always-run `detect-changes` job** of
`.github/workflows/tenant-integration.yml`:

- Enumerate `git diff --no-renames --name-only <base>...HEAD --
  'apps/web-platform/supabase/migrations/*.sql'` where `<base>` = `origin/${BASE_REF:-main}`.
- For each changed path, `git ls-tree <base> -- <path>`: empty → file not on main → free to iterate
  (numbering beyond max-on-main is explicitly allowed). Non-empty → compare mode+blob sha against
  `git ls-tree HEAD -- <path>`; any difference (modify, delete, rename-source, mode flip, or the
  add-collides race) → `::error::` naming the file + remediation line, exit 1.
- `*.down.sql` files are **exempt** — the runner never applies them (glob-level skip at
  `run-migrations.sh:256`) and the ledger never tracks them, so their mutation cannot drift the
  ledger. Documented exemption, exercised as a must-PASS matrix row.
- Fail closed on "cannot measure": unresolvable base ref, failed diff, or a repo root that does not
  contain the migrations dir → exit 2 (mirrors `_assert_repo_root` in the FK lint).

The step runs on every event detect-changes runs on — `pull_request`, `merge_group` (the queue
re-check that closes the sibling-merged-while-in-flight race), `push`, `workflow_dispatch`. On
push-to-main the diff is empty and the step no-ops green. A detect-changes failure fails
`tenant-integration-required` closed via `scripts/tenant-integration-gate-verdict.sh` (the
allow-list verdict permits only `detect=success`), so the guard is a **blocking required check**
with no changes to `scripts/required-checks.txt`, `ruleset-ci-required.tf`, or the bot
synthetic-checks surface.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 8583` — OPEN, labels `meta/machinery`, title matches. Premise holds.
- `gh pr view 8507` — MERGED 2026-09-22; `git log` on
  `apps/web-platform/supabase/migrations/138_agent_engine_runs.sql` shows `a76f489b0d` (add, #8082)
  then `19875b58bc` (modify, #8507) — the in-place-mutation claim is confirmed by history.
- Existing gates verified by reading: `run-migrations.sh` unmerged-apply gate (~line 281,
  `git ls-tree origin/main`), drift probe `.github/actions/dev-migration-drift-probe/action.yml`
  (`content_sha` comparison + `fail-on-ledger-drift`), FK lint
  `apps/web-platform/scripts/lint-migration-fk-preconditions.sh` (`--from-pr-diff` mode, exit 0/1/2,
  `_assert_repo_root`).
- No existing "immutability" guard: `grep -rn immutab .github/workflows/ apps/web-platform/scripts/
  scripts/` returns only unrelated matches (release immutability, digests).

### Reproduction at plan time (fixture repo, /tmp)

- `git diff main...HEAD --name-status -- 'apps/web-platform/supabase/migrations/*.sql'` on a branch
  editing `001_a.sql` + adding `003_c.sql` → `M 001_a.sql`, `A 003_c.sql`; `git ls-tree` blob shas
  differ as expected.
- After `git mv 002_b.sql 010_b.sql`: default `--name-only` emits `010_b.sql` **only** — the source
  `002_b.sql` is hidden by rename detection. With `--no-renames` both `002_b.sql` (D) and `010_b.sql`
  (A) enumerate → the source hits the on-main ls-tree check and fails. `--no-renames` is
  load-bearing, not hygiene.
- On this branch: `git diff origin/main...HEAD -- 'apps/web-platform/supabase/migrations/*.sql'`
  is empty (rc=0) and `git ls-tree origin/main -- .../138_agent_engine_runs.sql` returns blob
  `a90ab3e1` — matching the issue's remediated sha.

### Property List (Phase 0.6b)

1. Every `apps/web-platform/supabase/migrations/*.sql` path present on `origin/main` is
   byte-identical (mode + blob sha) at the PR head; merges may add files, never mutate or remove
   merged ones.
2. The check runs on every event the required gate reports on — including `merge_group`, so a
   migration that lands on main while a mutating PR sits in the queue is still caught.
3. The guard's own wiring is asserted — a PR that deletes the step or detaches the script cannot
   leave a green-looking hole (companion suite greps the workflow).
4. "Cannot measure" (unresolvable base, failed diff, wrong repo root) fails closed, never
   silently green.

### Cut List (Phase 0.6b)

- A dev-ledger (`_schema_migrations.content_sha`) comparison arm — the property "applied to dev" is
  stricter than "merged to main", but the ledger needs Doppler/psql, which only the secrets-holding
  heavy job has; the post-section re-probe already detects the residual (warning on PRs, fail on
  authoritative refs). The on-main proxy is the check the issue prescribes and covers the #8507
  shape exactly.
- A dedicated new required job in `ci.yml` — rejected: registering a new required context touches
  `required-checks.txt` + `ruleset-ci-required.tf` + the canonical JSON, and adding a content gate
  to `required-checks.txt` fabricates a green synthetic check for bot PRs (the #6049 auto-fabrication
  warning). Folding into `detect-changes` is blocking with zero ABI churn.
- An `ALLOW_*`/label escape hatch — rejected: repo doctrine is already that applied migrations are
  never edited or deleted (deleting a tracked file creates missing-drift on the probe); the remedy
  for a bad merged migration is a new forward migration. Adding a bypass would re-open the class.

### Relevant file paths

- `.github/workflows/tenant-integration.yml` — `detect-changes` job (lines ~60-115, fetch-depth: 0,
  anchor regex at ~line 111); heavy `tenant-integration` job (FK lint step ~line 260); required
  aggregator `tenant-integration-required` (~line 545).
- `scripts/tenant-integration-gate-verdict.sh` — allow-list verdict; `detect=failure` → gate red.
- `apps/web-platform/scripts/lint-migration-fk-preconditions.sh` — precedent sibling (`--from-pr-diff`,
  `_assert_repo_root`, `git fetch --quiet origin main || true`, exit 0/1/2).
- `apps/web-platform/scripts/lint-migration-fk-preconditions.test.sh` — companion-suite conventions
  (mktemp fixtures, pass/fail counters).
- `apps/web-platform/scripts/run-migrations.sh` — `*.down.sql` glob skip (~line 256), unmerged-apply
  gate (~line 281), `already_applied` skip (~line 331).
- `.github/actions/dev-migration-drift-probe/action.yml` — `git ls-tree origin/main` + `content_sha`
  comparison precedent (~lines 146-158).
- `scripts/test-all.sh` — SUITE_GLOBS auto-registers `apps/web-platform/scripts/*.test.sh` (line ~90).
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` +
  `fixture-dir-operand-assert.baseline.txt` — per-file residue ratchets; regenerate via each suite's
  `--write-baseline` ONLY if the new test file adds rows.
- `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`
  — the incident and revert procedure the gates' messages cite.

### CLAUDE.md conventions

- Workflow `run:` blocks: results read via `env:` + quoted `"$VAR"`; no untrusted `github.event.*`
  interpolation in run bodies; fail-closed on "cannot measure" (the detect-changes `git diff` arm).
- `cq-test-fixtures-synthesized-only` — fixture repos are synthesized in mktemp, never copied from
  the live tree's git state.
- `cq-assert-anchor-not-bare-token` — test assertions name file basenames/messages, not bare flags.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (no brainstorm ran — direct one-shot entry). Reconciling the
issue's claims against measured reality:

| Claim | Reality (measured) | Plan response |
|---|---|---|
| Nothing prevented the in-place edit merging | Confirmed — no immutability check exists; drift was caught only post-merge by the #7964 probe | Build the PR-time guard |
| "diff files that exist on origin/main" is implementable | `git diff --no-renames --name-only base...HEAD` + `git ls-tree` per path — verified in fixture | Exact mechanism prescribed |
| "numbering beyond max-on-main is free to iterate" | Falls out of the ls-tree check (not-on-main → skip) | Property 1 |

## Technical Considerations

- **Placement: `detect-changes`, not the heavy job.** The heavy `tenant-integration` job is
  `if: needs.detect-changes.outputs.tenant == 'true'` and skipped on `merge_group` by design
  (#5585/#5780). `detect-changes` always runs, already does `fetch-depth: 0`, holds no secrets, and
  its failure is already fail-closed into the required verdict. The step is added AFTER the `filter`
  step so `outputs.tenant` is still written even when the guard reds.
- **Merge-queue coverage.** On `merge_group`, `github.base_ref` is empty → script defaults to
  `origin/main`; the temp ref contains latest main merged, so the diff surfaces the PR's changes
  against the newest baseline — the TOCTOU arm.
- **Baseline method: merge-base (`...`), not `HEAD~`.** Three-dot matches every sibling gate
  (`detect-changes`, FK lint, drift probe). Two-dot `origin/main..HEAD` or `HEAD~N` would misreport
  on stale branches.
- **Blob identity, not content diff.** `git ls-tree` column 3 is the same sha space the runner stores
  in `_schema_migrations.content_sha` (migration 054) and the probe compares — consistent semantics.
  Mode is compared too (mode-only change on a tracked file is still a mutation).
- **Self-triggering.** The new script path is added to the `detect-changes` anchor regex so a PR
  that edits the guard itself runs the heavy suite (same anti-bypass rationale that anchors the
  verdict script and the probe action).
- **NFRs:** pure-git check, ~1s; no data store, no network beyond the best-effort fetch; no new
  ADR/C4 surface — no new actor, system, datastore, or relationship (the `github` system in
  `model.c4` already models "Source control, CI/CD"); this extends an existing documented
  enforcement class rather than creating a boundary.

## Files to Edit

| File | Edit |
|---|---|
| `.github/workflows/tenant-integration.yml` | Add step `Assert on-main migration files immutable` to `detect-changes` after `filter` (`env: BASE_REF: ${{ github.base_ref }}`, `run: bash apps/web-platform/scripts/lint-migration-immutability.sh --from-pr-diff`); add `apps/web-platform/scripts/lint-migration-immutability` to the anchor alternation at ~line 111 |
| `plugins/soleur/test/fixture-relative-assert.baseline.txt` | Regenerate via `--write-baseline` ONLY if the new test file adds residue rows (inspect diff before commit) |
| `plugins/soleur/test/fixture-dir-operand-assert.baseline.txt` | Same conditional regen |

## Files to Create

| File | Purpose |
|---|---|
| `apps/web-platform/scripts/lint-migration-immutability.sh` | The guard. Modes: `--from-pr-diff` (CI; base=`origin/${BASE_REF:-main}`, head=HEAD, best-effort `git fetch --quiet --no-tags origin main`) and `--base <ref> --head <ref> [--repo <dir>]` (tests/local). Exit 0 clean / 1 violations / 2 cannot-measure. Pass output ends with the literal `migration-immutability: clean`. |
| `apps/web-platform/scripts/lint-migration-immutability.test.sh` | Companion suite driving the guard over a synthesized fixture repo (mktemp + `git init`), including the workflow-wiring assertion. Auto-registered by test-all.sh's `apps/web-platform/scripts/*.test.sh` glob. |

## Implementation Phases

### Phase 1: Guard script + companion suite

- 1.1 Write `lint-migration-immutability.sh` per the algorithm above; mirror the FK lint's
  `_assert_repo_root`, `set -uo pipefail`, exit-code triad, and `::error::` remediation lines
  ("land the change as a new `NNN_*.sql` — on-main migration files are immutable, #8583").
- 1.2 Write `lint-migration-immutability.test.sh`: synthesized fixture repo, the matrix below, and
  a wiring assertion (`grep -q 'lint-migration-immutability' "$REPO_ROOT/.github/workflows/tenant-integration.yml"`).
  Call-site-incremented case counter + floor (per `guard-vacuity-floor.test.sh`'s expectations).

### Phase 2: Workflow wiring

- 2.1 Add the step to `detect-changes` after `filter`.
- 2.2 Extend the anchor alternation so edits to the guard run the heavy suite.

### Phase 3: Baselines + verification

- 3.1 Run the new suite; run `fixture-relative-assert.test.sh` and `fixture-dir-operand-assert.test.sh`;
  regenerate whichever baseline moved (same commit), inspecting the diff for only-expected rows.
- 3.2 Verify `bash scripts/lint-orphan-test-suites.sh` stays green (auto-glob coverage).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — this is CI machinery over the
  repo's own migration files. The indirect exposure is a false-red blocking all migration-touching
  PRs (developer-facing), or a false-green re-opening the #8583 drift class (main reds post-merge,
  detected by the existing probe).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the
  guard reads local git objects only, holds no secrets, runs in a `contents: read` job.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff touches no sensitive-path surface (SENSITIVE_PATH_RE checked —
  tenant-integration.yml and apps/web-platform/scripts/ match no alternative) and the check is
  repo-internal tooling with no user-data reach.`

## Observability

```yaml
liveness_signal:
  what: "CI step 'Assert on-main migration files immutable' in the detect-changes job — its red/green IS the signal; the required context tenant-integration-required surfaces it on every PR"
  cadence: per pull_request + merge_group + push + workflow_dispatch run
  alert_target: red required check blocks merge; ::error:: annotations name each drifted file
  configured_in: .github/workflows/tenant-integration.yml (detect-changes job)
error_reporting:
  destination: GitHub Actions run log + PR check annotation (::error:: per drifted file, with remediation line)
  fail_loud: "step exit 1 → detect-changes failure → tenant-integration-gate-verdict.sh fails tenant-integration-required closed; exit 2 on cannot-measure fails the same way"
failure_modes:
  - mode: origin/main unresolvable or git diff fails (shallow clone, fetch failure)
    detection: exit 2 with ::error:: naming the measurement failure — never a silent green
    alert_route: red tenant-integration-required on the PR
  - mode: guard script deleted or step removed in the same PR
    detection: companion suite's wiring assertion greps the workflow; detect-changes anchor regex runs the heavy suite on guard edits
    alert_route: red test-scripts suite / red tenant-integration-required
  - mode: residual — PR mutates its own just-applied unmerged migration (applied under ALLOW_UNMERGED_DEV_APPLY then edited)
    detection: post-section dev-migration-drift re-probe (::warning:: on PR, ::error:: + exit 1 on push-to-main / scheduled)
    alert_route: red tenant-integration on main; NOT covered by this guard — see Remaining Risks
logs:
  where: GitHub Actions run log for 'Tenant integration (dev-Supabase)'
  retention: GitHub Actions default retention
discoverability_test:
  command: bash apps/web-platform/scripts/lint-migration-immutability.sh --base HEAD --head HEAD
  expected_output: "migration-immutability: clean"
```

## Guard Contract

### Guard 1 — on-main migration immutability

**Property.** Every `apps/web-platform/supabase/migrations/*.sql` path present on the base ref
(`origin/main`, modulo `*.down.sql`) is byte-identical — mode and blob sha — at the PR head; a PR may
add migration files but never mutate, delete, or rename a merged one.

**Assembly.** The chokepoint is the `detect-changes` job of
`.github/workflows/tenant-integration.yml` — the one job that runs on every `pull_request` AND
`merge_group` event, already `fetch-depth: 0`, already fail-closed into `tenant-integration-required`.
The enumeration is `git diff --no-renames --name-only <base>...<head> --
'apps/web-platform/supabase/migrations/*.sql'` — a pathspec over the whole directory, so new files
sort into it automatically; there is no numbered file list to drift. The per-path authority is
`git ls-tree` on base and head (mode + blob sha), never filename patterns or file content.
`--no-renames` is load-bearing: with default rename detection `--name-only` emits only the rename
destination and a `git mv` of an on-main file never enumerates its source (verified live). The
comparison is identity, not status, so an `A`-status file colliding with an existing on-main path
still fails.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Edit content of an on-main migration (the #8507 shape) | RED — names the file |
| 2 | Delete an on-main migration | RED — names the file |
| 3 | `git mv` an on-main migration to a new number (rename-detection evasion arm) | RED — source enumerated via `--no-renames` |
| 4 | PR adds `NNN_x.sql` where the same path already exists on main with different content (add-collides race) | RED — ls-tree identity, not diff status |
| 5 | Guard's own dispatch: force the changed-path enumeration to produce zero rows while the diff touches migrations (e.g., break the pathspec) | RED — suite asserts the run reports ≥1 checked file when the fixture diff touches migrations, not a bare exit 0 |
| 6 | Harness row: neuter the fixture's `git` stub to return empty `ls-tree` output | RED — suite detects "guard reported clean against a stubbed oracle" |
| 7 | must-PASS, non-canonical: add `140_new.sql` beyond max-on-main | GREEN — free iteration |
| 8 | must-PASS, permitted difference: modify an on-main `*.down.sql` | GREEN — documented exemption (never applied, never ledgered) |

**Anchor.** The stored value under comparison is `origin/main`'s tree — outside the PR's commit
content, so one diff cannot edit both sides. The anchor is the fetched ref at run time, not a
committed manifest; there is no in-commit ledger to weaken. The residual single-diff weakness —
weakening the guard script itself in the same PR — is closed by the anchor-regex self-trigger +
wiring assertion + mandatory review, not by the guard's own logic.

## Acceptance Criteria

- [ ] AC1: `bash apps/web-platform/scripts/lint-migration-immutability.test.sh` exits 0 locally and
  under `bash scripts/test-all.sh` (auto-glob registered — `lint-orphan-test-suites.sh` stays green).
- [ ] AC2: The `Assert on-main migration files immutable` step runs in `detect-changes` on THIS PR —
  visible in the PR's own CI run log, exiting 0 with `migration-immutability: clean` (this PR edits
  no migration files).
- [ ] AC3: The suite drives the guard RED on modify / delete / rename / add-collides fixtures and
  GREEN on new-beyond-max and `*.down.sql` fixtures — the mutation matrix above.
- [ ] AC4: The step carries no `pull_request`-only event gate — on `merge_group` it re-checks the
  candidate against fresh `origin/main` (the sibling-merged-in-flight arm).
- [ ] AC5: On measurement failure (unresolvable base, failed diff, wrong repo root) the script exits
  2 — demonstrated by a suite case pointing `--base` at a bogus ref.
- [ ] AC6: Any moved baselines (`fixture-relative-assert`, `fixture-dir-operand-assert`) are
  regenerated via each suite's own `--write-baseline` in the same commit, with the diff inspected
  for only-expected rows.
- [ ] AC7: PR body carries `Closes #8583` on its own line.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — repo-internal CI/git tooling over an existing enforcement
surface.

## Test Scenarios

- Given a fixture repo where the PR branch edits an on-main `002_b.sql`, when the guard runs, then
  it exits 1 and the error names `002_b.sql`.
- Given the PR branch deletes an on-main file, when the guard runs, then exit 1 (delete = mutation).
- Given `git mv 002_b.sql 010_b.sql`, when the guard runs with `--no-renames`, then the source is
  enumerated and exits 1.
- Given the PR adds `140_new.sql` (not on main), when the guard runs, then exit 0.
- Given an on-main `*.down.sql` edited, when the guard runs, then exit 0 (documented exemption).
- Given `--base bogus-ref`, when the guard runs, then exit 2 (fail-closed, cannot measure).
- Given the workflow loses the guard step, when the suite's wiring assertion runs, then it fails.
- Regression: `bash apps/web-platform/scripts/lint-migration-fk-preconditions.test.sh` and the
  detect-changes/verdict suites stay green.

## Success Metrics

- A repeat of the #8507 shape (in-place edit of an on-main migration) fails `detect-changes` →
  `tenant-integration-required` red at PR time, before merge.
- `gh run list --branch main` post-merge shows `tenant-integration` green (the 138 drift is already
  remediated; this guard prevents the next instance).

## Dependencies & Risks

- **Risk: fetch-depth on `detect-changes` regressions.** The job already pins `fetch-depth: 0`; if a
  future PR shallowens it, `...` merge-base diffs fail → exit 2 → fail closed (correct direction).
- **Risk: stale `origin/main` on local runs** false-reds a file main gained after the last fetch —
  mitigated by the script's best-effort fetch and by CI always fetching fresh.
- **No external dependencies;** no infra apply, no new secrets, no new required-check registration.

## Remaining Risks

- **Unmerged-apply self-mutation (named residual, out of scope).** A PR can still add `NNN_*.sql`,
  let `tenant-integration` apply it to dev under `ALLOW_UNMERGED_DEV_APPLY=1`, then mutate it in
  place — the on-main guard cannot see files not yet merged, and the post-section re-probe is
  `::warning::`-only on PR surfaces. The drift is still caught fail-closed on the push-to-main run.
  Closing it needs a ledger-side arm (heavy-job step comparing `content_sha` for the PR's changed
  files) — candidate follow-up issue at work/ship time per the deferral-tracking rule.
- **`.down.sql` exemption** is deliberate (never applied → cannot drift the ledger); a rollback-file
  fix must ship as a new down-file or forward migration.
- **Mode-only changes** are treated as mutations (mode is compared) — conservative, consistent with
  "immutable".

## Open Code-Review Overlap

`gh issue list --label code-review --state open` (checked 2026-09-22): #3221 and #3220 mention
`apps/web-platform/supabase/migrations` but scope to post-merge prd verification and env-gated
nightly tests — no overlap with the guard, the workflow job, or the script paths.

## References & Research

- Issue: #8583 (this plan). Prior legs: #4241 (unmerged-apply gate, `run-migrations.sh`),
  #7964 (drift probe + fail-closed authoritative surfaces), #5920 (RPC body markers).
- Incident: #8507 / `19875b58bc` in-place mutation of `138_agent_engine_runs.sql`; remediation note
  in the issue (`content_sha` `3a111e09` → `a90ab3e1`).
- Learning: `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`.
- Precedent files: `lint-migration-fk-preconditions.sh` (`--from-pr-diff`, `_assert_repo_root`),
  `dev-migration-drift-probe/action.yml` (`git ls-tree origin/main` + sha comparison),
  `tenant-integration-gate-verdict.sh` (fail-closed allow-list).

## Sharp Edges

- `--no-renames` is load-bearing. Without it, `git mv` on an on-main migration evades the
  enumeration entirely (verified live — `--name-only` emits only the destination).
- Do not use two-dot diff or `HEAD~` as the baseline — `origin/main...HEAD` (merge-base) is the
  convention and the correct semantics for stale branches.
- The guard's exemption is `*.down.sql` ONLY — do not broaden it to "files below some number" or
  "files not in the ledger"; the property is presence-on-main.
- `detect-changes` failure already fails the required gate closed — do not add a parallel verdict
  arm or a new required context; the wiring is deliberately zero-ABI.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's is filled.

## Deepen-Plan Pass — 2026-09-22

Executed sequentially by the planning session (no Task-agent fan-out available in this harness;
verdicts are the gates' own, not a delegated review).

### Halt-gate verdicts

| Gate | Verdict | Evidence |
|---|---|---|
| 4.4 Precedent-diff / scheduled-work | PASS | Precedent is `lint-migration-fk-preconditions.sh` — same dir, same `--from-pr-diff` mode, same exit triad, same `_assert_repo_root`; differences named in Technical Considerations. No scheduled job introduced — cron check non-triggering. |
| 4.45 Verify-the-negative | PASS | "No secrets" — new step runs in `detect-changes`, which references no `secrets.*` (verified, job spans lines ~60-115). "Blocking without ABI churn" — verdict script reads `needs.detect-changes.result` and permits only `success` (read `tenant-integration-gate-verdict.sh`). "Rename evasion" — reproduced live in fixture. |
| 4.5 Network-outage | SKIP | Zero trigger patterns; no tf apply with provisioners. |
| 4.55 Downtime & Cutover | SKIP | No infra-replace, DDL, or deploy-surface edits. |
| 4.6 User-Brand Impact | PASS | Section present; `threshold: none` carries a `reason:` scope-out; SENSITIVE_PATH_RE checked against Files to Edit — `tenant-integration.yml` matches no alternative in the workflow regex, `apps/web-platform/scripts/` matches no app-path alternative. |
| 4.7 Observability | PASS | All 5 fields non-empty/non-placeholder; `discoverability_test.command` starts with `bash` (allowlisted), no ssh, no suite/test-shaped token, sub-15s pure-git invocation; `expected_output` is the literal `migration-immutability: clean` the script prints on pass. |
| 4.8 PAT-shaped variables | PASS | Regex sweep: zero hits. |
| 4.9 UI wireframe | SKIP | No UI-surface files. |
| 4.10 Encryption posture | SKIP (recorded) | Files match no trigger glob (`.tf`, `migrations/*.sql`, cloud-init, docker-compose); no new store or connection — the check reads local git objects. |
| 4.11 Guard Contract | PASS | Section present with Property/Assembly/8-row matrix/Anchor; assembly names the chokepoint (detect-changes + pathspec + ls-tree authority), not member lists. |

### Citation verification (all live)

- #8583 OPEN; #8507 MERGED (`19875b58bc`, verified ancestor of origin/main); #4241/#7964 gates read
  in `run-migrations.sh` and `dev-migration-drift-probe/action.yml` — claim shapes confirmed.
- `git ls-tree origin/main -- apps/web-platform/supabase/migrations/138_agent_engine_runs.sql` →
  blob `a90ab3e1`, matching the issue's post-remediation sha.
- `tenant-integration-required` confirmed in `scripts/required-checks.txt`,
  `scripts/ci-required-ruleset-canonical-required-status-checks.json`, and
  `infra/github/ruleset-ci-required.tf` — the detect-changes folding keeps all three untouched.
- `scripts/test-all.sh` SUITE_GLOBS includes `apps/web-platform/scripts/*.test.sh` (line ~90) —
  auto-registration confirmed; `lint-orphan-test-suites.sh` producer is `git ls-files '*.test.sh'`.

### Learnings applied

- `2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md` — the drift class and
  the revert procedure the guard's error text cites.
- `plan-sharp-edges.md` pass: AC2's verification is a live-CI observation (the PR exercises its own
  gate), not a "cannot fail" command; the matrix contains harness rows and must-PASS arms, not only
  system-under-test mutations.
- `fixture-relative-assert` ratchet convention — baseline regen is conditional and inspected, never
  blind (`--write-baseline` refuses a failed/wrong-looking scan).

### Refinements folded in by this pass

1. `--no-renames` made explicit and load-bearing (fixture-verified rename evasion).
2. Merge-queue coverage stated as a property, not an accident — the step runs unconditionally on
   `merge_group`, which is the only surface that sees the post-sibling-merge baseline.
3. The dev-ledger self-mutation residual promoted to Remaining Risks with a follow-up-issue
   directive, rather than silently dropped.
