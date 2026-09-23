---
title: "PR CI applies unmerged migrations to shared dev Supabase; a later edit to the file recreates ledger drift after merge"
date: 2026-09-23
slug: fix-pr-ci-unmerged-migration-ledger-parity
branch: feat-one-shot-8521-dev-ledger-content-drift
issue: 8521
closes: [8520, 8521]
type: fix
priority: p1-high
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

## Overview

The tenant-integration heavy job applies each pull request's not-yet-merged migration files to the
one shared dev Supabase project, and the runner never re-applies a filename it has already ledgered.
Three arms then turn every main push red after the fact:

1. a pull request edits a migration after CI applied it (#8521, the 26 content-drift rows of
   2026-09-21);
2. a pull request renames or renumbers an applied migration (orphan rows);
3. an open pull request's legitimately applied migration is reported "missing on main" by the
   fail-closed push probe (the 2026-09-22 recurrence in #8520, which is exactly the outcome ADR-061
   warned about).

This plan adds a read-only, per-ref ledger-parity guard to the pull-request heavy job. It runs as a
base-ref copy, before and after the apply step, and fails arms 1 and 2 before merge. It also adds a
git-only ownership classification to the authoritative drift probe, so rows owned by live branches
warn instead of failing. It names the repair path in every failure message and amends ADR-061. No
database writes; prd is untouched. It closes #8520 and #8521.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Insights

### Premise Validation (Phase 0.6)

Checked 2026-09-23:

- **#8521** OPEN, **#8520** OPEN, **#8049** OPEN (apply-path race; separate scope). **#8583** CLOSED by
  **PR #8597** (merged 2026-09-23T09:13Z). #8597's body defers exactly the residual arm this plan
  owns: "a PR that adds an unmerged migration, lets tenant-integration apply it to dev under
  `ALLOW_UNMERGED_DEV_APPLY=1`, then edits it before merge. Closing it needs a ledger-side comparison
  in the heavy job."
- `apps/web-platform/scripts/lint-migration-immutability.sh` (+ `.test.sh`) exists on `origin/main`
  and is wired as step `Assert on-main migration files immutable` in `detect-changes`. Not
  re-implemented here.
- **Stale sub-premise found — the 2026-09-22 recurrence was NOT the #8521 arm.** The parent brief
  says #8520 "stays open only because #8521 is unfixed". The failing-step annotations of the
  2026-09-22 red main runs show two *other* arms:
  - runs `35732801080` (13:20Z) and `35736906203` (13:57Z): `Missing-on-main: 139_openai_api_key_provider.sql`.
    That file was added to main by `19875b58bc` (#8507) at 14:52Z. So for ~1.5 h, an **open** PR's
    legitimately applied in-flight migration turned every main push red. This is precisely the
    failure ADR-061 predicted and rejected ("dev always carries orphans from open PRs, so a blocking
    orphan gate would persistently false-red main"). #7964/#8475 later made that probe blocking on
    push. Its plan (`2026-09-21-fix-tenant-integration-shared-fixture-contention-plan.md` §M2)
    assumed "on push … there is no legitimate unmerged-migration state". That assumption is false.
  - runs `35743332992` (14:52Z), `35744360560` (15:01Z) and `35747451585` (15:27Z): content drift
    `138_agent_engine_runs.sql (applied=3a111e0… main=a90ab3e…)`. This is #8507's in-place edit of an
    already-merged file, the #8583 class that #8597 now blocks.

  Consequence: shipping only the #8521 guard would leave the most frequent 2026-09-22 trigger
  (the in-flight arm) in place, and closing #8520 would be its third premature close. This plan
  therefore adds a main-side ownership classification (Phase 4). It follows ADR-061's per-ref rule,
  so it is a return to an accepted decision, not new scope. It is load-bearing for `Closes #8520`.
- The 2026-09-21 record in #8520 (26 content-drift rows classed A=13/B=7/C=5, plus 138) is the
  #8521 arm accumulated over months. Every row was reconciled on dev on 2026-09-21. The
  2026-09-22 138 row was reconciled by an unrecorded dev-side action between 15:27Z and 15:58Z.
  main has been green for 5 pushes since `ade3dff1b` (2026-09-22T21:58Z). No dev write is needed
  from this PR.

### Property List (Phase 0.6b)

- **P1**: A PR whose unmerged migration `F` was ledgered on dev at blob `B1` cannot pass
  `tenant-integration-required` while its `F` is at blob `B2 ≠ B1`, and it fails *before* its tests
  run against the stale schema.
- **P2**: A PR that renamed or renumbered an unmerged migration after CI applied it cannot pass while
  the old-name ledger row still carries that file's blob or slug. After merge, that row would be an
  orphan.
- **P3** *(cut at plan review)*: a post-apply assertion that every unmerged file is ledgered at its
  blob. It only guards a same-filename write by another ref *between* the pre-check and the apply, and
  both run inside the dev-suite mutex. The window exists only when that mutex fails open under
  contention. It is left as a named residual under #8049.
- **P4**: A PR cannot weaken the guard that judges it (base-ref copy; a deleted guard fails closed).
- **P5**: A main push (or the scheduled probe) is not failed by a ledger row that a **live `origin`
  branch** owns (in-flight; with `delete_branch_on_merge`, live ≈ unmerged).
  True orphans and all content drift still fail closed on authoritative refs.
- **P6**: Every drift or guard failure message names its repair path, including content drift,
  which today names none.
- **P7**: Nothing in the change writes to dev or prd. Guard queries are read-only, and the
  implementer performs no database writes.

### Cut List (Phase 0.6b)

- *Auto re-apply of an edited unmerged migration* (#8521 fix option 1a): it targets P1 by repairing
  instead of refusing. Cut. For idempotent files, a re-apply turns loud drift into **silent
  residue**, because objects the old body created and the new body does not touch survive. That is
  the #8520 C-class: the 075 `FOR ALL` policy, the 122 index. For non-idempotent files (bare
  `CREATE POLICY`/`CREATE TABLE`) it just fails later and more confusingly.
- *Ephemeral per-PR database / Supabase branching* (#8521 fix option 2): targets P1–P2. Cut, because
  ADR-023 rejected branching and ADR-061 rejected an "ephemeral throwaway DB per CI run" as
  heavyweight next to per-ref ownership checks. The per-ref ledger check gives P1–P2 at near-zero
  cost.
- *Lint refusing in-place edits to merged migrations* (#8521 fix bullet 3): already on main via
  #8597.
- *Ledger ownership column (`applied_by_ref`)*: targets P5. Cut. It needs a migration that also lands
  on prd, while branch-head ownership (git only) gets P5 with no schema change.
- *CI auto-delete of rename-orphan ledger rows*: targets P2 by repair. Cut, because CI would write to
  the shared ledger based on a heuristic.
- *CI attribution of which PR revision applied a blob* (deepen the fetch, walk history): targets P6.
  Cut. The failure message prints the applied blob SHA plus the local command that answers the
  question (`git log --all --find-object=<sha>`).
- *#8049 transaction-scoped apply lock*: out of scope (named residual, see P3).

### Relevant files (verified on this branch, `origin/main` = `251cfa650e`)

- `.github/workflows/tenant-integration.yml`: `detect-changes` (anchor alternation + #8597 base-ref-copy
  step `Assert on-main migration files immutable`); heavy job `tenant-integration` steps in order:
  `Lint migration FK preconditions` → Doppler asserts → `Acquire dev-suite mutex` →
  `Detect dev-vs-main migration drift` → `Preflight schema-vs-ledger consistency check` →
  `Seed bot fixtures (pre-migration)` → `Apply migrations to dev` (`ALLOW_UNMERGED_DEV_APPLY: "1"`) →
  `Preflight WORM-vs-cascade contradiction check` → `Run tenant-isolation tests` →
  `Re-probe dev-vs-main migration drift (post-section)` (`if: always()`) → `Release dev-suite mutex`.
  Workflow-level `permissions: contents: read`; the heavy job checks out with `fetch-depth: 2`.
- `apps/web-platform/scripts/run-migrations.sh`: the unmerged gate is the `git ls-tree origin/main -- …`
  block under `# Unmerged-apply gate (#4241)`. The skip is `already_applied=$(run_sql "SELECT count(*) …")`,
  and `content_sha=$(git hash-object "$migration_file")` writes the ledger blob. It walks the
  working-tree glob `"$MIGRATIONS_DIR"/*.sql`, skips `*.down.sql`, and applies the filename-shape
  whitelist `*[!a-zA-Z0-9._-]*`. The same script runs the **prd** release apply, so it is not modified
  here, and prd semantics stay unchanged. **Plan-review finding, verified 2026-09-23:** that gate's
  `git ls-tree origin/main -- apps/web-platform/…` pathspec is relative to the current directory. The
  heavy job runs the script with `working-directory: apps/web-platform`, so every file classifies as
  "not on origin/main" and the #4241 gate does nothing in CI. prd runs from the repo root and is
  unaffected. Filed as **#8606**. The new guard does not inherit this: it anchors every git call on
  the repo root.
- `.github/actions/dev-migration-drift-probe/action.yml`: step `probe` builds `missing_drift` /
  `content_drift`. Severity comes from `FAIL_ON_DRIFT`. The missing block names the revert
  procedure, but the content-drift block names none. Consumers are `tenant-integration.yml` (×2) and
  `.github/workflows/scheduled-dev-migration-drift.yml` (`fail-on-ledger-drift: 'true'`, dispatched
  every 6 h by `apps/web-platform/server/inngest/functions/cron-dev-migration-drift.ts`). The
  scheduled surface inherits the same in-flight false-red.
- `apps/web-platform/scripts/lint-migration-immutability.{sh,test.sh}`: the shape to mirror. That
  means the exit triad 0/1/2, a `need_value` flag parser, `_assert_repo_root`, a summary line with
  counts plus a `::notice::` on a degenerate zero, the `EXPECTED_CASES` vacuity floor directly above
  its `if`, and workflow-wiring grep asserts.
- `apps/web-platform/scripts/run-migrations-schema-probe.test.sh`: precedent for a fake `psql` on
  `PATH` (`make_temp_tree`).
- `apps/web-platform/scripts/preflight-schema-vs-ledger.sh`: precedent for a ledger read (prefers
  `DATABASE_URL_POOLER`, `ON_ERROR_STOP=1`).
- `scripts/test-all.sh` `SUITE_GLOBS` includes `'apps/web-platform/scripts/*.test.sh'`, so new suites
  there are auto-discovered. `scripts/lint-orphan-test-suites.sh` walks `git ls-files '*.test.sh'`.
- No `.gitattributes` affects `apps/web-platform/supabase/migrations/*.sql`, so `git hash-object` of
  the checkout file equals the blob the runner ledgers. There are 260 migration files, the highest
  prefix is `139`, and `053` is a known pre-existing prefix collision.
- Ownership data (Phase 4), measured 2026-09-23: `git ls-remote --heads origin` → 95 branches;
  repo is **public** with `delete_branch_on_merge: true` (`gh api repos/jikig-ai/soleur`), so a merged
  PR's branch disappears and a live branch is the owner of any row its PR CI applied. Fork PRs never
  receive the Doppler secret, so every dev row applied by PR CI came from an `origin` branch.
  (`gh pr list --json files` was also probed — 51 open PRs — and superseded: GraphQL caps `files` at
  100 per PR, it needs `pull-requests: read`, and it puts a GitHub-API dependency on the
  authoritative gate.)

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`:
  the revert procedure (obtain `.down.sql` from the branch, apply in reverse, `DELETE` ledger rows).
  Its documented gap (b) is that content drift was silent. It has **no content-drift repair section**;
  #8520's comments are the only record of the A/B/C procedure. Phase 5 adds that section.
- `knowledge-base/project/learnings/2026-09-23-a-pr-must-not-control-the-guard-that-judges-it.md`:
  a three-arm base-ref execution (base copy / introduction-window checkout copy / deleted-on-base
  fail-closed); tri-state oracles (`rc≠0` is a measurement failure, not "absent"); an audible degenerate
  pass; a `need_value` flag parser; the vacuity floor adjacent to its `if`.
- `knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md`: read the
  apply path before hypothesizing, and ledger claims can disagree with schema. The guard compares the
  ledger to the file and says nothing about the schema. `preflight-schema-vs-ledger.sh` stays the
  schema-side check.
- ADR-061 (`knowledge-base/engineering/architecture/decisions/ADR-061-per-ref-behavioural-schema-gate-over-shared-dev.md`):
  gates over shared dev block only on objects the **current ref** owns, and other refs'
  leave-behinds are `::warning::`. Phases 1–3 (PR side) and Phase 4 (main side) both apply it.
- ADR-023 rejects Supabase branching for the dev/prd split.

### CLAUDE.md / AGENTS conventions in play

`hr-dev-prd-distinct-supabase-projects` (the guard runs only under the `dev_scheduled` config that
the job already asserts resolves to `environment=dev`); `cq-write-failing-tests-before` (the
mutation matrix is written first); `hr-observability-as-plan-quality-gate`;
`cq-test-fixtures-synthesized-only`; `wg-use-closes-n-in-pr-body-not-title-to`.

### Functional overlap / community discovery

The functional-discovery search of 3 registries found no community artifact that implements a
PR-scoped ledger-vs-blob CI gate. The community-discovery stack check found no uncovered stack
(bash + GitHub Actions + TypeScript).

### External research

Skipped. Strong local precedent: #8597's guard, the drift probe, and ADR-061 cover the pattern
end-to-end. The only new external surface is `git ls-remote`/`git fetch` against `origin`, which the
probe already depends on (it fails closed when `git fetch origin main` fails).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (verified) | Plan response |
|---|---|---|
| #8521: "add a lint that refuses to edit an already-merged migration in place" | Shipped by #8597 (`lint-migration-immutability.sh`, `detect-changes` step) | Not re-implemented; #8597's deferred residual is this plan's Phases 1–3 |
| #8521 fix option: "re-apply it (the file must be idempotent)" | Idempotent re-apply leaves old-body residue silently (#8520 C rows 075/122) | Rejected; fail pre-merge instead (Cut List) |
| Brief: #8520 "stays open only because #8521 is unfixed" | 2026-09-22 reds were the in-flight arm (`139_…`, open PR #8507) and the #8583 arm (`138_…`) — zero #8521-arm rows | Phase 4 (in-flight ownership) added; it is what makes `Closes #8520` honest |
| #7964 plan §M2: on push "there is no legitimate unmerged-migration state" | ADR-061 Context: dev is "the union of main plus every open migration-PR's applied-but-unmerged objects" | Phase 4 restores ADR-061's per-ref rule on the ledger probe; ADR-061 amended |
| Drift probe comment: content drift "is caught by the content-sha check" | Caught post-merge only, with no repair procedure named anywhere | Phases 1–3 catch it pre-merge; Phase 5 names the A/B/C repair path |
| CTO review: "the 26 drifted rows keep the fix PR's own main run red" | All 26 + 138 reconciled on dev 2026-09-21 (#8520 comment "Resolved"); main green 5× since `ade3dff1b` | No dev write in this plan (P7); AC verifies post-merge green instead |

## Problem Statement

PR CI (`tenant-integration` heavy job) applies each PR's unmerged migrations to the one shared dev
Supabase project and never re-applies a ledgered filename. Three arms turn `main` red *after* the
fact, each blocking every merge:

1. **Edited-after-apply (#8521).** PR applies `F@B1`, then edits `F→B2`. Dev keeps `B1` — and the
   PR's own later test runs pass against the stale `B1` schema (a false green on the PR, not just a
   red on main). After merge the push probe reports content drift. This produced the 26 rows of
   2026-09-21, including two dev security gaps (075 catch-all policy; 091 `rename_organization`
   executable by `authenticated`).
2. **Renamed-after-apply.** PR applies `140_x`, renumbers to `141_x` (the runner's own collision
   warning *recommends* this). `140_x` stays ledgered, not on main → orphan (the 8 orphan rows of
   2026-09-21 were this class).
3. **In-flight (new evidence).** Any open PR's applied migration is "Missing-on-main" for every
   push to main until it merges — 2026-09-22 13:20–14:52Z, and the every-6h scheduled probe fails
   the same way.

(The fourth arm — editing an already-merged file — is closed by #8597.)

## Proposed Solution

One new script, `apps/web-platform/scripts/dev-ledger-parity.sh`, with two subcommands that share one
ownership primitive:

- `check` is the PR-side, per-ref ledger-parity guard, covering arms 1 and 2. It runs once, before
  apply, as a **base-ref copy**.
- `classify-missing` is the authoritative-side ownership classification, covering arm 3. The drift
  probe runs it from the checkout, and on every authoritative surface that checkout *is* main.

Both follow ADR-061. Both use git only: no `gh`, no new token permissions, and no GitHub API dependency
on the authoritative gate. The script's only database access is one fixed `SELECT`. Its only writes are
git refs under `refs/ledger-owners/*` in the CI workspace, made by the ownership fetch. Nothing writes
to dev or prd.

### Phase 0 — RED first (cq-write-failing-tests-before)

Write `apps/web-platform/scripts/dev-ledger-parity.test.sh` before the script exists. It must hold both
guards' mutation matrices, the must-PASS rows, the harness rows (see Guard Contract), and the workflow
and action wiring asserts. Run it: every row must fail at the harness level. A result of "0 passed,
0 failed" with exit 0 does not count as a pass.

Fixtures are synthesized only (`cq-test-fixtures-synthesized-only`):

- a **bare `origin` repo** holding `main` (with real history, including one migration renamed on main)
  plus feature branches, cloned into a work repo;
- a fake `psql` on `PATH` (precedent: `run-migrations-schema-probe.test.sh` `make_temp_tree`) that
  prints scripted `filename|sha` rows, prints nothing, or exits non-zero.

Every fixture `git` call runs with `GIT_DIR`/`GIT_INDEX_FILE` scrubbed. Plugin AGENTS.md §Test Fixture
Conventions explains why: this is the linked-worktree hazard.

### Phase 1 — the ownership primitive (shared, lazy)

`branch_owners` runs only when at least one candidate row needs it. The no-candidate path makes zero
remote calls.

1. **One fetch by refspec.** Run it under a 60 s timeout:
   `git -C "$REPO" fetch --no-tags --depth=1 --filter=blob:none origin '+refs/heads/*:refs/ledger-owners/*'`.
   - Using a refspec instead of `ls-remote` followed by a fetch by OID removes the force-push race
     between the two calls.
   - `ls-tree` needs trees, never blobs. At implementation, verify that `--filter` works on a
     non-promisor workspace clone (git may need `-c remote.origin.promisor=true`). If it does not,
     fall back to a plain `--depth=1` and record the measured wall time in the PR.
   - A failed fetch exits 2.
2. **Enumerate owners.** Use `git -C "$REPO" for-each-ref refs/ledger-owners/`, excluding the base
   branch and `gh-readonly-queue/*`.
3. **Map each head.** Per head, run `git -C "$REPO" ls-tree <ref> -- ':(top)apps/web-platform/supabase/migrations/'`
   and keep forward `.sql` entries only, never `*.down.sql`. This gives `branch → {name → blob}`.
4. **Find the owners of row `R`**, whose ledger `content_sha` is `S`. Try each tier in order and stop at
   the first that matches:
   1. branches that hold `R` **by exact name**;
   2. branches that hold a file whose **blob is `S`**;
   3. branches that hold a file whose **slug** matches `slug(R)`, where `slug(x)` strips the leading
      `^[0-9]+_`.

### Phase 2 — `dev-ledger-parity.sh check` (PR side)

```text
dev-ledger-parity.sh check --base <ref> --repo <dir>
dev-ledger-parity.sh classify-missing --base <ref> --repo <dir>   # stdin: "<file>|<content_sha>" lines
dev-ledger-parity.sh --help                                        # documents the summary line
Exit: 0 clean/classified | 1 violation(s), each named via ::error:: | 2 cannot measure
```

The shape follows `lint-migration-immutability.sh`: the `need_value` parser, the `_assert_repo_root`
check on `--repo` (required, because the base copy runs from `$RUNNER_TEMP`), the exit triad, and a
summary line. **Every** git call is `git -C "$REPO" …` with a `:(top)`-anchored pathspec. The
runner's cwd-relative bug (#8606) must not be reproduced.

- **Population `U`.** Glob `$REPO/apps/web-platform/supabase/migrations/*.sql` from the working tree,
  the same glob as the runner, and drop `*.down.sql`.
  - A name failing `*[!a-zA-Z0-9._-]*` means exit 2.
  - For each file, run `git -C "$REPO" ls-tree <base> -- ':(top)<path>'`. A non-zero rc means exit 2.
    Empty output means the file is unmerged, so it goes into `U`.
  - `blob(F)` is `git -C "$REPO" hash-object <path>`, identical to the runner's `content_sha`. A
    non-zero rc means exit 2.
  - Also build `M`, the forward names on `<base>`, and `T`, the forward names in the tree.
- **Ledger `L`.** Run this every time, even when `U = ∅`, so the pooler path and the floor are
  exercised on every run.
  - `DB="${DATABASE_URL_POOLER:-${DATABASE_URL:-}}"`. If it is empty, exit 2.
  - Query with `PGCONNECT_TIMEOUT=10 timeout 60 psql "$DB" -w --no-psqlrc -tAq --set ON_ERROR_STOP=1 -c "$LEDGER_SQL"`.
    `LEDGER_SQL` is the readonly constant
    `SELECT filename || '|' || COALESCE(content_sha, '') FROM public._schema_migrations ORDER BY filename`.
  - A non-zero rc means exit 2. **Zero rows means exit 2**, because dev has 260+ rows, so an empty
    result means the guard's own dispatch failed (wrong database or a broken query).
  - Ledger names failing the shape whitelist are skipped with a `::warning::` and never echoed raw.
  - A `content_sha` that does not match `^[0-9a-f]{40}$` counts as absent.
- **A1.** For each `F ∈ U` that has a ledger row, an empty sha is a violation (an unmerged row cannot
  be verified), and `sha ≠ blob(F)` is a violation.
- **A2.** The candidates are ledger rows `G ∉ M ∪ T` with `sha(G) == blob(F)` or
  `slug(G) == slug(F)` for some `F ∈ U`.
  - When there are candidates, compute `branch_owners`.
  - A candidate that some live branch holds **by exact name** belongs to that branch. Skip it with a
    `::notice::` that names the branch.
  - Every other candidate is a violation.
- **Output.** One `::error::` block per violation, then:
  `ledger-parity: RED|clean (unmerged=… ledgered-match=… pending=… merged-skipped=… ledger-rows=… a2-candidates=… violations=…)`.
  When `U = ∅`, also print `::notice::ledger-parity: 0 unmerged migrations in this tree — nothing to compare`.
  **Every exit-2 message** ends with `— infrastructure/measurement failure, not caused by this PR; re-run the job`.
- **Sanitization.** Everything echoed into an annotation passes a check first:
  - filenames pass the shape whitelist;
  - SHAs match `^[0-9a-f]{40}$`;
  - branch names match `^[A-Za-z0-9._/-]+$`, otherwise they print as `<unprintable-branch>`.

**Remediation texts (P6):**

- **A1:**

  > `<F>`: dev applied this unmerged migration at blob `<applied>`, but this tree has `<head>`. The
  > runner never re-applies a ledgered filename, so this PR's tests ran against the OLD body, and
  > main's drift probe fails after merge (#8521). Fix it without a database write: restore the applied
  > body (`git show <applied> > <path>`; `git log --all --find-object=<applied>` finds the commit),
  > then put the change in a NEW migration numbered after it. A migration applied to dev is as
  > immutable as a merged one (#8583). If the blob is not on your side, another branch applied a
  > same-named file: renumber yours.

- **A2:**

  > `<G>` is ledgered on dev but is not on `<base>`, not in this tree, and not held by any live
  > branch. It matches this PR's `<F>` by `<blob|slug>`, so `<F>` looks renamed after CI applied it.
  > After merge `<G>` is an orphan. Fix: rename `<F>` back to `<G>` if that name is free on main. If
  > the match is a coincidence of slug, re-slug or renumber yours. Otherwise revert the dev apply of
  > `<G>` per the learning (gap 2) and re-run.

### Phase 3 — wire `check` into `.github/workflows/tenant-integration.yml`

1. **`detect-changes` classifies the guard's base-ref state** in a new pure-git step. This job already
   has `fetch-depth: 0`, which is exactly the history the deleted-on-base arm needs. The heavy job's
   `fetch-depth: 2` would make `git log -1 origin/main -- <path>` return nothing and fail open (the
   Kieran and simplicity review finding).
   - The step emits `outputs.ledger_guard: base | introduction | deleted`, using #8597's three arms
     evaluated on full history.
   - It runs after `filter`, so `outputs.tenant` is still written.
2. **Heavy job: `Resolve dev-ledger-parity guard (base-ref copy)`.** Place it **after**
   `Lint migration FK preconditions`, so it cannot disturb that lint's `origin/main...HEAD` diff, and
   before `Acquire dev-suite mutex`. It is pure git and needs no secrets.
   - `base`: run `git fetch --no-tags --depth=1 origin "$base_ref"`, then
     `git show "origin/$base_ref:<path>" > "$RUNNER_TEMP/dev-ledger-parity.sh"`. A non-empty file is
     required, otherwise exit 1.
   - `introduction`: copy the checkout's copy.
   - `deleted`: print `::error::` and exit 1.
   - The value comes in as `LEDGER_GUARD: ${{ needs.detect-changes.outputs.ledger_guard }}` via `env:`
     and is quoted.
3. **`Assert unmerged migrations match the dev ledger`.** Place it after
   `Detect dev-vs-main migration drift`, which has just refreshed `origin/main`, and before
   `Preflight schema-vs-ledger consistency check`, inside the mutex window. Run:
   `doppler run -p soleur -c dev_scheduled -- bash "$RUNNER_TEMP/dev-ledger-parity.sh" check --base "origin/$base_ref" --repo "$GITHUB_WORKSPACE"`.
   It must run **before** apply. When A1 fires, the runner skips the stale file, and any later
   migration that depends on the new body fails inside `Apply migrations to dev` with an unrelated
   error. The guard's message has to come first.
4. **Anchor.** Append `|apps/web-platform/scripts/dev-ledger-parity` to the `detect-changes`
   alternation.
5. **Comment.** Add a comment block covering the property, why the guard fails instead of re-applying,
   ADR-061, and #8521. No `github.event.*` goes into a `run:` block.

The step runs on every heavy-job event. On `push` and on a main dispatch, `U = ∅` gives the notice,
the zero-row floor still applies, and the step is clean. On a feature-branch `workflow_dispatch` it is
live.

### Phase 4 — authoritative-side classification (arm 3)

Changes to `.github/actions/dev-migration-drift-probe/action.yml`, step `probe`:

- Keep `missing_drift` for display unchanged. Collect a **separate** `missing_pairs+="$f|$sha_applied"$'\n'`
  list for the classifier (Kieran P2). This keeps SHAs out of the Missing-on-main display, and the line
  count is taken on `missing_pairs`.
- **Only when `FAIL_ON_DRIFT == true` and `missing_pairs` is non-empty**, run
  `bash apps/web-platform/scripts/dev-ledger-parity.sh classify-missing --base origin/main --repo "$GITHUB_WORKSPACE" <<<"$missing_pairs"`
  from the checkout. PR-mode runs never reach this.
- Classification of each row:
  - **Merged-history exclusion (Kieran P1).** If the row's filename appears anywhere in `origin/main`
    history, it is an orphan and can never be in-flight. Test this with
    `git -C "$REPO" log -1 --format=%H origin/main -- ':(top)<path>'`, after making history available
    with `git fetch --no-tags --filter=blob:none --unshallow origin main`. Fall back to a plain
    `--unshallow` if the filter is refused. Any failure exits 2. This fetch happens only on this rare
    path. It closes the gap where a stale fork still holding a filename that main later renamed or
    deleted would excuse a real orphan.
  - Otherwise, the owners come from `branch_owners`.
  - Output is one line per input: `in-flight<TAB><file><TAB><branch><TAB><exact|blob|slug>`, or
    `orphan<TAB><file>`.
- In-flight rows print `::warning::  - <F> (in-flight: held by live branch <b> via <exact|blob|slug> — clears when it merges or the branch is deleted)`.
  Orphans keep the existing `::error::` Missing-on-main block.
- **Fail-closed.** If the classifier exits non-zero, or its output line count differs from the input,
  every missing row stays `::error::`, plus
  `::error::cannot classify missing-on-main rows (git remote failure — not evidence of drift); failing closed`.
- `drift-detected` keeps meaning "any row reported". The exit decision uses orphans plus content drift.
- No workflow edit or permission change is needed. `scheduled-dev-migration-drift.yml` uses the same
  action, and the checkout credentials cover `fetch` on this public repo.

### Phase 5 — repair paths named (P6) + records

- **`action.yml` content-drift block.** Add:
  `::${sev}::Repair: knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md §Content drift — class each row A (comment/whitespace-only → rewrite content_sha), B (file idempotent AND safe against later redefinitions → re-apply main's file, then content_sha), C (targeted SQL against the LATEST main definition of each object). Pre-merge prevention: apps/web-platform/scripts/dev-ledger-parity.sh check (#8521).`
- **`action.yml` missing block.** Add one line naming renamed-after-apply rows: a ledger-only delete,
  done only after verifying that the renamed file on main owns every object (gap 2).
- **Learning `2026-05-21-…md`.** Add a new section, `## Content drift (same filename, different blob)`.
  It records the A/B/C procedure distilled from #8520's 2026-09-21 comments:
  - triage read-only first;
  - judge each row against the latest main definition, not against the drifted file;
  - use one transaction per row;
  - worked ordering example: 094 before 117.
- **ADR-061 amendment.** See Architecture Decision.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Re-apply the edited unmerged file (issue option 1a) | Rejected. Idempotent files leave old-body residue silently (#8520: the 075 `FOR ALL` policy, the 122 index). Non-idempotent files fail later, and less clearly. |
| Ephemeral per-PR DB / Supabase branching (issue option 2) | Rejected (ADR-023, ADR-061). Per-ref checks achieve P1, P2 and P5 at near-zero cost. |
| Ownership via `gh pr list --json files` (first draft) | Superseded. It caps at 100 files per PR, needs `pull-requests: read`, and a GitHub API outage would red the authoritative gate. Branch-head ownership needs only git. |
| Downgrade Missing-on-main to `::warning::` on authoritative refs unconditionally (advisor option a) | Rejected. Orphans from abandoned or renamed branches would go silent again, which is how the 8 orphan rows of 2026-09-21 accumulated. |
| Slug-only A2 match as a plain `::warning::` (CTO, advisor) | Refined instead. Slug candidates owned by exact name on another live branch are skipped as a notice. Unowned ones still block, because they are the renamed-and-edited rows (064→067, 128→131), half of the 2026-09-21 orphans. The message offers "re-slug yours" for coincidental collisions. |
| Post-apply second check (P3) | Cut at plan review. Its window exists only when the mutex fails open. #8049 is the residual. |
| A single post-apply check instead of pre (DHH) | Rejected. A1 makes the runner skip the stale file, so a later dependent migration fails *inside* apply with an unrelated error, and the guard's message never prints. |
| Content-sha check inside `run-migrations.sh` (CTO) | Cut. That script is PR-controlled and also the prd apply path. Its existing `run-migrations-unmerged-gate.test.ts` psql stub returns empty for non-count SELECTs, and the logic would be duplicated. |
| Extract the three-arm base-ref resolution into a composite action (DHH) | Not taken. The state decision moves into `detect-changes` (full history), leaving about 6 lines in the heavy job. Refactoring #8597's step would also break its wiring asserts (T10/T11) for no property gain. |
| `--ledger-file` offline mode, `BEGIN READ ONLY` wrapper, pinned `LEDGER_PARITY_BASE` (first draft) | Cut at plan review. They satisfy no property: the fixed SELECT is read-only by construction, and with one invocation there is nothing to keep in step. |
| CI auto-delete of rename orphans / dispatchable dev-reconcile workflow | Deferred to #8605 (CI writing to the shared ledger). The CTO's argument for pulling a minimal version in is recorded in `decision-challenges.md`. |
| Ledger `applied_by_ref` column | Cut. A schema change landing on prd, for a property branch heads already give. |

## Files to Create

- `apps/web-platform/scripts/dev-ledger-parity.sh`
- `apps/web-platform/scripts/dev-ledger-parity.test.sh`. `scripts/test-all.sh` discovers it
  automatically through the `SUITE_GLOBS` entry `'apps/web-platform/scripts/*.test.sh'`.

## Files to Edit

- `.github/workflows/tenant-integration.yml`:
  - `detect-changes`: the `ledger_guard` output step and the anchor;
  - heavy job: the resolve step and the check step.
- `.github/actions/dev-migration-drift-probe/action.yml`: `missing_pairs`, the `classify-missing` call
  (fail-on only), and the repair-path lines.
- `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`:
  the §Content drift section.
- `knowledge-base/engineering/architecture/decisions/ADR-061-per-ref-behavioural-schema-gate-over-shared-dev.md`:
  the amendment.

Not edited, by decision:

- `apps/web-platform/scripts/run-migrations.sh` (its cwd bug is #8606);
- `apps/web-platform/scripts/lint-migration-immutability.sh`;
- `.github/workflows/scheduled-dev-migration-drift.yml`.

## Open Code-Review Overlap

One open scope-out touches a file named in this plan's research: #3364, a postgres-role ownership guard
in `run-migrations.sh`.

**Acknowledge.** This plan deliberately does not edit `run-migrations.sh`, because it is the prd apply
path. #3364 is an unrelated concern and stays open.

No open code-review issue names `tenant-integration.yml`, the drift-probe action, the learning, or
ADR-061.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-061**
(`knowledge-base/engineering/architecture/decisions/ADR-061-per-ref-behavioural-schema-gate-over-shared-dev.md`)
via `soleur:architecture`, adding `## Amendment 2026-09-23 (#8520, #8521): ledger gates are per-ref too`:

1. **The authoritative ledger probe blocks only on unowned rows.** This covers push-to-main, main
   dispatch and the scheduled run.
   - A row a live `origin` branch holds (by exact name, blob, or slug) is an in-flight `::warning::`,
     unless its filename appears in main's history.
   - The blob and slug tiers are load-bearing. With exact-name matching alone, a rename orphan still
     owned by an open PR would red main for that PR's whole lifetime.
   - The amendment records that #7964 §M2 re-introduced the rejected alternative "blocking orphan
     probe on push:main", and cites the confirming runs 35732801080 and 35736906203.
2. **Policy: a migration applied to shared dev is immutable, merged or not.** Changes ship as a new
   file.
   - **Accepted cost:** fix-up migrations become permanent on prd, and the migration count grows.
   - Automatic re-apply joins Rejected alternatives, because it leaves silent residue (#8520 C rows).
   - `dev-ledger-parity.sh check` is the per-ref "owning PR fails" half of this.

The ADR keeps its number, so there is no ordinal collision risk.

### C4 views

**No C4 impact.** Checked against all three files (`model.c4`, `views.c4`, `spec.c4`):

- **External human actors:** none added. `contributor` already models PR authors, including PR-head
  code running under `pull_request` isolation.
- **External systems:** `github` and `doppler` are already modeled. The only new calls are git
  `fetch` from Actions to GitHub, which stay inside `github`.
- **Data stores:** `platform.infra.supabase` is the prd store. The shared dev project and the CI edge
  to it are not modeled today. This plan adds no new edge class: the heavy job already reads and
  writes dev, and the new query is one SELECT on the same connection.
- **Access relationships:** none change.

`plugins/soleur/test/c4-count-parity.test.sh` ran on 2026-09-23 and reported `ALL TESTS PASSED`.

### Sequencing

The ADR amendment ships in this PR. The status stays Accepted.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. Every surface is repo CI over the
  shared **dev** project.
  - Broken toward false-red: migration PRs, or main via Phase 4, cannot merge, which delays
    user-facing fixes.
  - Broken toward false-green: dev keeps a stale or residue schema, and main reds after merge. This is
    the #8520 class, which included a dev policy that let workspace members modify others' shared
    conversations.
  - prd is unaffected: it applies only main's files, in order.
- **If this leaks, the user's data is exposed via:** no user-data vector.
  - Dev holds synthetic data only (`hr-dev-prd-distinct-supabase-projects`).
  - The guard reads filenames and hashes.
  - The classifier reads public branch heads over the job's existing read-only checkout credentials.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: no touched path matches preflight SENSITIVE_PATH_RE (tenant-integration.yml, .github/actions/**, apps/web-platform/scripts/** and knowledge-base/** checked 2026-09-23) and no step reaches prd or user data.`

## Observability

```yaml
liveness_signal:
  what: "ledger-parity: clean|RED (unmerged=… ledger-rows=… …) summary line printed by dev-ledger-parity.sh check in every tenant-integration heavy-job run; on authoritative runs the drift probe prints 'in-flight:' warnings or 'No dev-vs-main migration drift detected.'"
  cadence: "per heavy-job run (every migration-touching PR push, every push to main) + every 6 h via scheduled-dev-migration-drift.yml (dispatched by cron-dev-migration-drift)"
  alert_target: "required check tenant-integration-required (red PR / red main commit); scheduled probe failure = failed workflow run, with dispatch liveness on the existing cron watchdog"
  configured_in: ".github/workflows/tenant-integration.yml (detect-changes ledger_guard step; heavy-job steps 'Resolve dev-ledger-parity guard (base-ref copy)' and 'Assert unmerged migrations match the dev ledger'); .github/actions/dev-migration-drift-probe/action.yml (step probe)"
error_reporting:
  destination: "GitHub Actions ::error:: annotations + required-check status; no Sentry (dev-only CI surface; the probe's Sentry path stays scoped to rpc-body drift on the scheduled surface, unchanged)"
  fail_loud: "'ledger-parity: RED (…)' plus one ::error:: per violation naming file, applied blob, head blob and repair path; exit 2 prints an ::error:: ending '— infrastructure/measurement failure, not caused by this PR; re-run the job'; classifier failure prints '::error::cannot classify missing-on-main rows (git remote failure — not evidence of drift); failing closed'"
failure_modes:
  - mode: "PR edits an unmerged migration after CI applied it (A1)"
    detection: "check step exits 1 before apply and before any test"
    alert_route: "PR's tenant-integration-required red; annotation names the restore-plus-new-file remedy"
  - mode: "PR renames or renumbers an applied unmerged migration and leaves the old name unowned (A2)"
    detection: "check step exits 1"
    alert_route: "PR check red; annotation names rename-back / re-slug / gap-2 revert"
  - mode: "ledger unreadable, no DB URL, zero rows, base unresolvable, owner fetch failed"
    detection: "check exits 2 (fail closed)"
    alert_route: "PR check red with 'not caused by this PR; re-run' annotation"
  - mode: "PR edits the guard, or the guard is deleted on base"
    detection: "resolve step runs the base-ref copy; detect-changes (full history) reports 'deleted' and the resolve step exits 1"
    alert_route: "PR check red with deleted-guard annotation"
  - mode: "live branch's in-flight row on dev during a push to main or a scheduled run (arm 3)"
    detection: "classify-missing → in-flight → ::warning:: naming the branch; main stays green"
    alert_route: "annotation only, by design (ADR-061)"
  - mode: "true orphan (branch deleted, renamed-away row unowned, or filename in main history)"
    detection: "classify-missing → orphan → existing ::error:: Missing-on-main, exit 1"
    alert_route: "main tenant-integration-required and scheduled probe red"
  - mode: "git remote failure during classification"
    detection: "classifier exits 2, or the line count mismatches → every missing row stays ::error:: with an annotation naming the outage"
    alert_route: "main check red (fail closed); message says not evidence of drift"
logs:
  where: "GitHub Actions run logs for tenant-integration.yml and scheduled-dev-migration-drift.yml (gh run view <id> --log)"
  retention: "GitHub Actions log retention (repo default, 90 days)"
discoverability_test:
  command: "bash apps/web-platform/scripts/dev-ledger-parity.sh --help"
  expected_output: "ledger-parity:"
```

`--help` prints the exit triad and the literal format of the `ledger-parity:` summary line, which is
the string an operator greps for in the run log. It needs no database and no network, and finishes
well inside preflight Check 10's 15 s cap.

## Guard Contract

### Guard 1 — unmerged-migration ledger parity (`dev-ledger-parity.sh check` + its workflow step)

**Property.** For every forward migration in the checkout that is absent from the base tree, the dev
ledger either lacks it or records exactly this tree's blob. No ledger row that is absent from the base
tree, from this tree, and from every live branch (by exact name) carries one of those files' blob or
slug.

**Assembly.** There is one chokepoint on each side.

- **Population:** the working-tree glob `apps/web-platform/supabase/migrations/*.sql`, minus
  `*.down.sql`. "Unmerged" means a `git -C $REPO ls-tree <base> -- ':(top)<path>'` result that is
  empty and has rc 0. The blob is `git -C $REPO hash-object`, which is the same function the runner
  uses for `content_sha`.
- **Ledger:** a single `SELECT … FROM public._schema_migrations` read.
- **Ownership:** the single `branch_owners` primitive, shared with Guard 2.
- **State:** one `detect-changes` output, `ledger_guard`.
- **Wiring:** exactly one invocation site in `tenant-integration.yml`. It sits after
  `Detect dev-vs-main migration drift`, before `Apply migrations to dev`, and inside the mutex window.
  It executes `$RUNNER_TEMP/dev-ledger-parity.sh`, which the single resolve step produces. A second
  invocation site, or a checkout-path invocation, is a defect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Ledger row `F` with `content_sha ≠ blob(F)`, and `F` unmerged | RED exit 1, names `F` and both SHAs |
| 2 | Two unmerged files: `F1` ledgered at its blob (compliant), `F2` mismatched | RED exit 1, names `F2` only (second member) |
| 3 | Ledger row `G` not on base, not in the tree, and on no live branch, with `content_sha == blob(F)` | RED exit 1 (A2 blob) |
| 4 | As row 3, but a different blob and `slug(G) == slug(F)` | RED exit 1 (A2 slug) |
| 5 | Ledger row `F` with an empty `content_sha` | RED exit 1 |
| 6 | Stub `psql` exits 2 | exit 2 |
| 7 | Stub `psql` returns 0 rows | exit 2 (own-dispatch floor) |
| 8 | Neither `DATABASE_URL_POOLER` nor `DATABASE_URL` is set | exit 2 (not 1) |
| 9 | `--base` does not resolve, or `--repo` is missing or lacks the migrations dir | exit 2 |
| 10 | An A2 candidate exists and the `origin` URL points at a missing path | exit 2 |
| 11 | Run with cwd = `$REPO/apps/web-platform` (row-1 fixture) | still RED exit 1: no cwd-relative pathspec (#8606 class) |
| 12 | Workflow: the check step moves AFTER `Apply migrations to dev`, or after `Release dev-suite mutex` (reorder) | wiring assert RED |
| 13 | Workflow: the invocation uses the checkout path instead of `$RUNNER_TEMP/dev-ledger-parity.sh` | wiring assert RED |
| 14 | Workflow: the resolve step loses its `deleted` → `exit 1` arm, or `detect-changes` loses `fetch-depth: 0` | wiring assert RED |
| 15 | Fixture: shallow (`--depth=1`) clone where the guard was deleted on base, run through the `ledger_guard` classifier logic | reports `deleted` only when computed on full history; the suite asserts that the classifier runs in `detect-changes` |

**Must-PASS rows** (non-canonical inputs the contract permits):

- (a) unmerged `F` ledgered at its blob → 0;
- (b) unmerged `F` with no row → 0, `pending=1`;
- (c) a *merged* file whose ledger blob differs → 0 (this is another ref's pre-existing drift);
- (d) an unmerged `F.down.sql` with no row → 0;
- (e) an unrelated orphan `Z` (different slug, different blob) → 0, with **no** remote call (the
  fixture's origin URL is poisoned);
- (f) a slug candidate held by exact name on another live branch → 0, with a `::notice::` naming it;
- (g) tree == base → 0, with the `::notice::` and the floor still enforced.

**Harness rows:**

- (H1) guard body → `exit 0`: the suite goes RED;
- (H2) guard body → `exit 1`: the suite goes RED;
- (H3) delete a case block: `CASES < EXPECTED_CASES` goes RED (the floor is adjacent to its `if`);
- (H4) script absent: RED, not "0 passed, 0 failed".

**Anchor.** The compared value, the ledger `content_sha`, lives outside the commit. It is on dev, and
only the runner writes it, at apply time. The judging code comes from the base ref via `git show`, and
the `deleted` decision comes from full history. One PR diff cannot move both the guard and the verdict.

Residual: `pull_request` runs the PR's own workflow file, so a PR can delete the step. That deletion
is visible in review and self-triggers the heavy suite via the anchor. It is the same residual #8597
accepted.

### Guard 2 — in-flight ownership classification (`dev-ledger-parity.sh classify-missing` + probe wiring)

**Property.** Under `fail-on-ledger-drift`, a missing-on-main ledger row is downgraded to a warning
iff both hold:

- its filename never appeared in main's history;
- a live `origin` branch head holds it by exact name, by identical blob, or by identical slug.

Every other missing row, every content-drift row, and every row that cannot be classified stays a
blocking error.

**Assembly.** A single chokepoint:

- The `probe` step's `missing_pairs` list goes to the classifier's stdin, which returns a per-line
  verdict.
- The exit decision reads only the `orphan` lines plus the unchanged `content_drift`.
- Ownership comes from `branch_owners`. Main-history exclusion comes from one unshallow of
  `origin/main`.
- Both consumers of the action flow through that step: tenant-integration (×2) and the scheduled run.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Row held by no live branch head (branch deleted) | `orphan` → probe `::error::`, exit 1 |
| 2 | Two rows: first in-flight, second owned by nobody | second `orphan` (second member) |
| 3 | **Stale fork:** main renamed `128_x→131_x`, and a live branch forked earlier still holds `128_x` | `orphan` (main-history exclusion) |
| 4 | `origin` URL broken (fetch fails) | exit 2 → probe keeps all rows `::error::` + outage annotation |
| 5 | Classifier emits fewer lines than its input (stubbed) | probe line-count check → all `::error::` |
| 6 | The only same-slug match is a `.down.sql` in a head | `orphan` (down files own nothing) |
| 7 | Content-drift row whose file sits on a live branch | still `::error::` (classification is missing-class only) |
| 8 | Row's only holder is a `gh-readonly-queue/*` ref | `orphan` |
| 9 | Missing-on-main display, after the change | lists filenames only, with no `|sha` suffix |

**Must-PASS rows:**

- exact-name owner → `in-flight … exact`;
- renamed with an equal blob → `in-flight … blob`;
- renamed and edited, with an equal slug → `in-flight … slug`;
- empty input → exit 0, with **no** remote call.

**Harness rows:**

- (H1) classifier body → `exit 0` with no output: the suite goes RED;
- (H2) the classifier prints `in-flight` for everything: rows 1–3 go RED;
- (H3) the `CASES` floor sits adjacent to its `if`.

**Anchor.** Ownership evidence is `origin`'s live refs plus main's history, both outside this commit.
Laundering a true orphan requires pushing a branch to `origin`, which needs repo write, and that
branch's PR is blocked by its own Guard 1 (A1/A2) until the orphan is resolved.

## Acceptance Criteria

### Functional Requirements

- [ ] **AC1**: The Guard 1 matrix rows 1–11 and must-PASS rows (a)–(g) hold. Implementation:
  `apps/web-platform/scripts/dev-ledger-parity.sh` `check`. Verified by
  `bash apps/web-platform/scripts/dev-ledger-parity.test.sh`.
- [ ] **AC2**: The Guard 2 matrix and its must-PASS rows hold. Implementation: `classify-missing`,
  plus `.github/actions/dev-migration-drift-probe/action.yml` step `probe`. That step makes the
  fail-on-only call, splits `missing_pairs` from the display, applies the line-count fail-closed
  check, and exits on orphans plus content drift.
- [ ] **AC3**: `tenant-integration.yml` satisfies the Guard 1 wiring rows 12–14:
  - `detect-changes` emits `ledger_guard` and keeps `fetch-depth: 0`;
  - the resolve step sits after `Lint migration FK preconditions` and before `Acquire dev-suite mutex`;
  - the single check step sits between `Detect dev-vs-main migration drift` and `Apply migrations to dev`,
    and runs `$RUNNER_TEMP/dev-ledger-parity.sh check`.

  The suite asserts all of this by step name and relative order.
- [ ] **AC4**: The `detect-changes` alternation contains the token `apps/web-platform/scripts/dev-ledger-parity`.
  This is a wiring assert on the anchor token itself.
- [ ] **AC5**: The drift probe's content-drift block prints a `Repair:` line that names
  `§Content drift` and `dev-ledger-parity.sh check`. The missing block names renamed-after-apply rows.
  The suite asserts this by grepping `action.yml`.
- [ ] **AC6**: The learning contains `## Content drift (same filename, different blob)`, and ADR-061
  contains `## Amendment 2026-09-23` with both points.
- [ ] **AC7**: Scope stays narrow.
  - `git diff origin/main...HEAD --name-only` touches no `apps/web-platform/supabase/migrations/**`,
    no `run-migrations.sh`, and no `lint-migration-immutability.sh`.
  - No workflow gains a `permissions:` key.
  - The suite asserts that the script's only SQL is the literal
    `SELECT filename || '|' || COALESCE(content_sha, '') FROM public._schema_migrations ORDER BY filename`.
    It does this by capturing the fake-psql argv and comparing it byte-for-byte (P7).

### Non-Functional Requirements

- [ ] **AC8**: No-candidate runs make zero remote calls (must-PASS (e) poisons the origin URL). The
  PR body records the measured wall time of `branch_owners` against the real `origin`, which must stay
  under 60 s.
- [ ] **AC9**: The following all pass:
  - `shellcheck` is clean on the new script and suite;
  - `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/lint-workflow-step-env-refs.test.sh`,
    `bash scripts/lint-workflow-errexit-capture.test.sh` and
    `bash apps/web-platform/scripts/lint-migration-immutability.test.sh` stay green.

### Quality Gates

- [ ] **AC10**: This PR's own heavy job runs, because the workflow is anchored.
  - In the `introduction` state, it prints `ledger-parity: clean` with `unmerged=0` and
    `ledger-rows=<N>`, where N > 0.
  - This is the one live proof of the pooler query path.
- [ ] **AC11 (post-merge smoke check, not a correctness gate)**: Read the first `push` run of
  tenant-integration on main after merge with
  `gh run view <id> --log | grep -e 'ledger-parity:' -e 'in-flight:' -e 'No dev-vs-main migration drift detected.'`.
  - It must show that the new step executed.
  - Any red in that run must be attributed, by its own annotation, to an orphan or content-drift row,
    never to a row held by a live branch.
  - The run's conclusion depends on dev state that other refs write, so it is **not** asserted
    (`cq-ac-must-not-depend-on-concurrent-sessions`). The deterministic properties are AC1 and AC2.
- [ ] **AC12**: The PR body carries `Closes #8520` and `Closes #8521`, cites the 2026-09-22 run
  evidence for the #8520 close, and references #8606 as a finding filed during planning.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed

**Assessment.** The CTO agrees with the layering: a read-only guard, run as a base-ref copy (the #8597
pattern), with ADR-061 per-ref ownership on main. The CTO also agrees with rejecting auto re-apply and
a per-PR DB.

Folded in from the first pass:

- remedy text that states the PR's tests ran against the old body;
- the anchor addition;
- classifier fixtures;
- a named outage message.

Folded in from the plan-review devex pass:

- exit-2 messages that say "not caused by this PR; re-run";
- A2 "re-slug yours";
- accepted immutability cost recorded in the ADR.

Not folded in:

- **"The 26 drifted rows keep main red":** those rows were already reconciled on 2026-09-21.
- **`run-migrations.sh` content check:** see Alternatives.
- **Pulling a minimal dev-reconcile workflow into scope, and a push-time git-only warning:** these are
  scope additions, persisted to `knowledge-base/project/specs/feat-one-shot-8521-dev-ledger-content-drift/decision-challenges.md`.

**Product/UX Gate:** not applicable. There is no UI surface, and no Files-to-Create/Edit path matches
the UI-surface terms. No other domain is implicated: this is repo CI over a dev-only database.

## Test Scenarios

All scenarios live in the single suite `apps/web-platform/scripts/dev-ledger-parity.test.sh`: the
Guard Contract rows plus these arcs:

1. **Edit-after-apply.** The ledger holds `140_x|B1`, and the branch has edited `140_x` to `B2`.
   `check` exits 1 with the A1 text, which includes `git show B1`.
2. **Remedy.** Restore `140_x@B1` and add `141_y`. `check` exits 0 with `pending=1`.
3. **Rename.** The ledger holds `140_x|B1`, and the tree holds `141_x@B1`. With no live branch
   holding `140_x`, `check` exits 1 (A2 blob). With a fixture branch `feat-other` holding `140_x`, it
   exits 0 with a notice.
4. **In-flight.** The probe's pairs are `139_z|S`, and a live branch holds `139_z@S`. The result is a
   warning with exit 0. After the branch is deleted from the bare origin, the result is an error with
   exit 1.
5. **Stale fork.** Main renamed `128_x→131_x`. The ledger holds `128_x`, and an old branch still holds
   `128_x`. The row is an orphan and the result is an error.

## Deferrals

- **#8605** (filed during planning; labels `deferred-scope-out`, `meta/machinery`; milestone
  Post-MVP / Later). Two related gaps:
  - dev rows from closed, unmerged PRs whose branches were never deleted stay in-flight indefinitely;
  - there is no dispatchable dev-reconcile path for discarding an applied version.

  The CTO argues the re-evaluation trigger fires almost at once (26 edit-after-apply rows across about
  260 files). That challenge is recorded in `decision-challenges.md`.
- **#8606** (filed during planning; labels `type/bug`, `meta/machinery`): the #4241 unmerged gate in
  `run-migrations.sh` does nothing under `working-directory: apps/web-platform`. This is a pre-existing
  issue, and the prd path is unaffected.
- **#8049** stays open and separate. It absorbs the P3 residual: a same-filename write between check
  and apply while the mutex fails open.

## Risks & Sharp Edges

- **Head-fetch cost inside the mutex.** The fetch is lazy, and it runs only when an A2 candidate or a
  missing row exists. `--filter=blob:none` support on the CI clone is verified at implementation.
  AC8 pins the time budget, with a 60 s timeout.
- **`--unshallow` cost on the classifier path.** It runs only under fail-on, and only when rows are
  missing. A blobless unshallow of main is bounded by commit and tree count. Record the measured time
  in the PR.
- **Friction from "applied means immutable".** An author iterating after the first CI apply must add
  files. The A1 message states that cost, and the ADR records it as accepted. #8605 tracks the
  convenience path.
- **Slug collisions.** An unowned slug match blocks a PR that did nothing wrong. The message offers
  "re-slug yours", and matches owned by exact name are skipped.
- **Wiring asserts are keyed on step names and relative order**, not line numbers
  (`cq-cite-content-anchor-not-line-number`). They assert the full anchor token
  (`cq-assert-anchor-not-bare-token`). The suite's header states that renaming a step breaks it, by
  design.
- **User-Brand Impact.** A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one is
  filled.

## References

- **Issues:** #8520, #8521, #8583 (closed by #8597), #8049, #7964, #8475, #8507, #3364, #8605, #8606
- **Runs:**
  - 35732801080 and 35736906203: in-flight 139;
  - 35743332992, 35744360560 and 35747451585: 138 content drift;
  - green streak from `ade3dff1b` (run 35789724725).
- **ADRs:** ADR-061, ADR-023
- **Learnings:**
  - `2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`
  - `2026-09-23-a-pr-must-not-control-the-guard-that-judges-it.md`
  - `2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md`
- **Prior plan whose §M2 premise this corrects:** `2026-09-21-fix-tenant-integration-shared-fixture-contention-plan.md`
