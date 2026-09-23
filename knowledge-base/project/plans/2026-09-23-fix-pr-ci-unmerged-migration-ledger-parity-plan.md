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

## Enhancement Summary

**Deepened on:** 2026-09-23 (after a 4-agent plan review and a CTO devex pass)

**Sections enhanced:** Proposed Solution (all phases), Alternatives, Architecture Decision,
Observability, Guard Contract, Acceptance Criteria, Test Scenarios, Deferrals, Risks.

**Deepen agents:** security-sentinel, architecture-strategist, spec-flow-analyzer,
test-design-reviewer, observability-coverage-reviewer, plus live git probes (git 2.55, bare
`file://` fixtures) and the halt gates 4.6, 4.7, 4.8 and 4.11, all of which passed.

### Key improvements

1. **The main-side ownership check had a P0 false green, and it is closed.** Three reviewers found it
   independently. Every branch carries main's migrations, so a merged `131_x` "owned" the orphan
   `128_x`, which never merged, from every branch. Branches now own only files that are **absent from
   main**. A row whose name appears in main's history is never in-flight, and neither is a branch that
   is already merged.
2. **Ownership git work moved into a throwaway bare repo** with a single full-history blobless fetch.
   The v2 in-workspace fetch had four problems: it turned the checkout into a partial clone, made it
   shallow again, made `--unshallow` exit 128, and left stale refs between the two probes.
3. **Delete-after-apply (A4) is covered.** A4 checks the PR branch's own history in the throwaway
   repo. A 30-day freshness rule, with a blocking `stale` verdict, stops abandoned branches from
   hiding orphans forever.
4. **Fail-closed output no longer looks like drift.** It prints `ledger-classify: UNCLASSIFIED (rows= rc=)`
   first. Exit-2 messages say "not caused by this PR" and separate transient failures from config
   ones.
5. **AC10b, a read-only pre-merge dispatch**, exercises the Phase 4 classifier. Without it the
   classifier would first run on main. The P4 anchor now states honestly what the base-ref copy does
   and does not stop.

### New considerations discovered

- **#8606 (filed): the existing #4241 unmerged gate in `run-migrations.sh` does nothing in CI.** Its
  `ls-tree` pathspec is cwd-relative under `working-directory: apps/web-platform`, which was verified
  locally. The new guard uses `:(top,literal)` pathspecs everywhere, and harness row 11 pins it.
- **The classifier runs on the normal path, not a rare one.** Dev nearly always carries rows from open
  PRs, so AC8 budgets it: 6–10 s plus about 3 s, measured.
- **The ADR-061 amendment must say "ownerless rows count as main's".** It also marks ADR-061's rejected
  "blocking orphan probe" alternative as superseded in part. Without that, the amendment contradicts
  ADR-061's own ownership rule.

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
- **P2**: A PR that renamed, renumbered or deleted an unmerged migration after CI applied it cannot
  pass while an unowned old-name ledger row still carries that file's blob or slug, or a blob the PR
  branch's history carried. After merge, that row would be an orphan. Deepen-plan added the
  delete-after-apply arm (A4).
- **P3** *(cut at plan review)*: a post-apply assertion that every unmerged file is ledgered at its
  blob. It only guards a same-filename write by another ref *between* the pre-check and the apply, and
  both run inside the dev-suite mutex. The window exists only when that mutex fails open under
  contention. It is left as a named residual under #8049.
- **P4**: A PR cannot weaken the guard that judges it (base-ref copy; a deleted guard fails closed).
- **P5**: A main push (or the scheduled probe) is not failed by a ledger row that a **fresh, unmerged,
  live `origin` branch** holds, through a file that is not on main. Ownerless, stale (more than 30
  days), main-history and unclassifiable rows still fail closed.
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

- `check`: the PR-side, per-ref ledger-parity guard (arms 1 and 2). The workflow runs it once, before
  apply, as a **base-ref copy**.
- `classify-missing`: the authoritative-side ownership classification (arm 3). The drift probe runs it
  from the checkout under `fail-on-ledger-drift`.

Both follow ADR-061. They use git only: no `gh`, no new token permissions, and no GitHub API dependency
on the authoritative gate.

Scope of side effects:

- **Database:** the only access is one fixed `SELECT`.
- **Git:** all ownership and history work happens in a **throwaway bare repo** under a `mktemp -d`,
  which is removed on exit. The job's checkout is never mutated: no `promisor` config, no new shallow
  entries, no leftover refs (deepen-plan: architecture and test-design reviewers, verified on
  git 2.55).
- **dev / prd:** nothing writes to either.

### Phase 0 — RED first (cq-write-failing-tests-before)

Write `apps/web-platform/scripts/dev-ledger-parity.test.sh` before the script exists. It holds both
guards' matrices, the must-PASS rows, the harness rows, and the workflow and action wiring asserts.
Run it with the script absent: every row must fail at the harness level. "0 passed, 0 failed" with
exit 0 does not count.

Harness rules (test-design review):

- The suite runs a **copy** of the guard (`GUARD=${DLP_GUARD:-<tracked path>}`); mutation rows edit the
  copy, never the tracked file.
- A control run of the unmutated guard must pass.
- Only `rc=1` counts as a caught violation, and `rc=2` counts only where a row expects it.
- `EXPECTED_CASES` sits on the line directly above its `if`.

Fixtures, synthesized only (`cq-test-fixtures-synthesized-only`):

- a **bare `origin`** reached through a `file://` URL (a plain-path clone ignores `--depth`), with
  `uploadpack.allowFilter=true` to match GitHub;
- `main` history that includes one migration renamed on main;
- feature branches, **including the PR's own head branch pushed to origin**, since in CI the PR head
  is a live branch;
- a work clone;
- a fake `psql` on `PATH` that logs each invocation's argv NUL-delimited and returns scripted rows,
  empty output, or a non-zero exit;
- every fixture `git` call runs with `GIT_DIR`/`GIT_INDEX_FILE` scrubbed.

### Phase 1 — the ownership primitive (shared)

`owners_repo` builds the throwaway repo once per invocation, and only when some candidate row needs
it:

1. `OWN=$(mktemp -d)`, `trap 'rm -rf "$OWN"' EXIT`, then `git init -q --bare "$OWN"`.
2. Run **one** fetch, with **full history and no blobs**, under `timeout 120` resolved through the
   repo's `timeout`→`gtimeout` precedent:

   ```text
   git -C "$OWN" \
     -c http.extraheader="$(git -C "$REPO" config --get http.https://github.com/.extraheader || true)" \
     fetch -q --no-tags --filter=blob:none "$(git -C "$REPO" remote get-url origin)" \
     '+refs/heads/*:refs/owners/*'
   ```

   - Reusing the checkout's `extraheader` keeps auth working if the repo is ever private. It is empty
     and harmless on the public repo and in `file://` fixtures.
   - A "filtering not recognized" warning is **not** a failure.
   - A non-zero exit gives exit 2, `transient` class.
   - Full history (no `--depth`) makes the main-history test and the PR-history test below correct.
     `--depth` combined with a later deepen is the exact trap the reviewers reproduced.
   - Measured cost 2026-09-23 against the real `origin` (architecture review): 6–10 s / 32 MB for
     main's blobless history, plus about 3 s for the heads.
3. `BASE_OWN=refs/owners/<base branch>`. The owner set is every `refs/owners/*` **except** the base
   branch and `gh-readonly-queue/*`, and except any head that is an ancestor of `BASE_OWN`
   (`git merge-base --is-ancestor`), because that head is already merged.
4. **Per-head map, excluding main's files.** A head owns only forward `.sql` files in its tree
   (`git -C "$OWN" ls-tree <ref> -- ':(top,literal)apps/web-platform/supabase/migrations/'`) that are
   **absent from `BASE_OWN`'s tree**.
   - This closes the P0 that three reviewers found independently: every branch carries main's
     migrations, so without the exclusion a merged `131_x` "owned" the never-merged orphan `128_x`
     from every branch.
   - `*.down.sql` is never owned.
5. **Freshness.** A head whose `%(committerdate:unix)` is more than **30 days** old does not own
   anything. Rows it would own get the verdict `stale`, which is blocking and names the branch and its
   age (observability and security reviews).
6. **Tiers.** The owners of row `R` (ledger sha `S`) are found in order: exact name, then blob `S`,
   then `slug(R)`, where `slug(x)` strips `^[0-9]+_`.
7. **Main history.** `R` never belongs to anyone if its filename appears in `BASE_OWN`'s history
   (`git -C "$OWN" log -1 --format=%H "$BASE_OWN" -- ':(top,literal)<path>'` is non-empty). This is
   the stale-fork case.

All regexes run under `LC_ALL=C`. Before any annotation:

- branch names must match `^[A-Za-z0-9._/-]+$`, or they print as `<unprintable-branch>`;
- filenames pass the runner's shape whitelist;
- SHAs match `^[0-9a-f]{40}$`, and anything else, including uppercase or short, counts as absent.

### Phase 2 — `dev-ledger-parity.sh check` (PR side)

```text
dev-ledger-parity.sh check --base <ref> --repo <dir> [--head-branch <name>]
dev-ledger-parity.sh classify-missing --base-branch <name> --repo <dir>   # stdin: "<file>|<sha>" lines
dev-ledger-parity.sh --help        # documents the "ledger-parity:" and "ledger-classify:" summary formats
Exit: 0 clean/classified | 1 violation(s), each named via ::error:: | 2 cannot measure
```

Conventions:

- `need_value` parser; `--repo` is required, followed by `_assert_repo_root`.
- Every git call on the checkout is `git -C "$REPO" … ':(top,literal)<path>'`. The runner's
  cwd-relative bug (#8606) must not be reproduced.
- **Exit-2 messages come in two classes:**
  - `transient` (fetch timeout, psql connect failure): the message ends
    `— not caused by this PR; re-run the job`;
  - `config` (no DB URL, zero ledger rows, base unresolvable, `--repo` invalid): the message ends
    `— not caused by this PR; check the Doppler dev_scheduled config / workflow wiring; a re-run will not help`.

Steps:

- **Population `U`.**
  - Glob `$REPO/apps/web-platform/supabase/migrations/*.sql` and drop `*.down.sql`.
  - A name failing `*[!a-zA-Z0-9._-]*` gives exit 2.
  - A file is unmerged when `git -C "$REPO" ls-tree <base> -- ':(top,literal)<path>'` succeeds with
    empty output. A non-zero exit there gives exit 2.
  - `blob(F) = git -C "$REPO" hash-object <path>`.
  - `M` holds the forward names on `<base>`, and `T` holds the forward names in the tree.
- **Ledger `L`.** Read it on **every** run, including `U = ∅`, so the pooler path and the floor are
  exercised each time:
  - `DB="${DATABASE_URL_POOLER:-${DATABASE_URL:-}}"`; empty gives exit 2 (`config`);
  - query with
    `PGCONNECT_TIMEOUT=10 timeout 60 psql "$DB" -w --no-psqlrc -tAq --set ON_ERROR_STOP=1 -c "$LEDGER_SQL"`,
    where `readonly LEDGER_SQL="SELECT filename || '|' || COALESCE(content_sha, '') FROM public._schema_migrations ORDER BY filename"`;
  - a non-zero exit gives exit 2 (`transient`);
  - **zero rows gives exit 2** (`config`), because a wrong database or broken query must not pass
    silently.
- **A1.** For each `F ∈ U` that has a ledger row, it is a violation if:
  - the sha is empty or not valid (its own message, `the ledger row carries no verifiable content_sha`);
  - or the sha is not `blob(F)`.
- **Candidates `C`.** Ledger rows `G ∉ M ∪ T`. When `C` is non-empty, build `owners_repo`. Then, for
  each `G ∈ C`:
  - held **by exact name** by a fresh owner head (not ancestor-merged, not stale) other than
    `--head-branch`: skip it with a `::notice::` that names the branch (that PR's in-flight row);
  - otherwise, **A2**, a violation when `sha(G) == blob(F)` or `slug(G) == slug(F)` for some `F ∈ U`
    (this PR renamed it after apply, even across a force-push);
  - otherwise, **A4**, a violation when `--head-branch` is given and `sha(G)` is one of the blob IDs in
    `git -C "$OWN" log --raw --no-abbrev --format= "$BASE_OWN..refs/owners/<head-branch>" -- ':(top,literal)apps/web-platform/supabase/migrations/'`.
    The PR once carried that exact body and then deleted it, or renamed and re-slugged it (spec-flow
    review P0-2). A force-pushed history that dropped the commit is a named residual.
  - Any other row in `C` is not this PR's: no output.
- **Output.**
  - One `::error::` block per violation;
  - then `ledger-parity: RED|clean (unmerged=… ledgered-match=… pending=… ledger-rows=… candidates=… skipped-owned=… violations=…)`;
  - when `U = ∅`, also `::notice::ledger-parity: 0 unmerged migrations in this tree — nothing to compare`.

**Remediation texts (P6):**

- **A1:** `<F>`: dev applied this unmerged migration at blob `<applied>`, but this tree has `<head>`.
  - Why it matters: the runner never re-applies a ledgered filename. This PR's tests therefore ran
    against the OLD body, and main's drift probe will fail after merge (#8521).
  - Fix without a database write:
    - restore the applied body with `git show <applied> > <path>`;
    - if the object is not local, use
      `gh api repos/$GITHUB_REPOSITORY/git/blobs/<applied> --jq .content | base64 -d > <path>`;
    - then put the change in a NEW migration numbered after it.
  - A migration applied to dev is as immutable as a merged one (#8583).
  - If `git log --all --find-object=<applied>` finds nothing on your side, another branch applied a
    same-named file: renumber yours.
  - If you cannot recover the body and hold no dev credentials, ask a dev operator to reconcile per
    the learning's §Content drift (#8605 tracks self-service).
- **A2 / A4:** `<G>` is ledgered on dev but is not on `<base>`, not in this tree, and not held by any
  other live branch. It matches this PR's `<F>` by `<blob|slug|history>`, so `<F>` was renamed or
  removed after CI applied it, and after merge `<G>` becomes an orphan. Fix:
  - rename `<F>` back to `<G>` if that name is free on main;
  - otherwise, have `<G>` reverted on dev per the learning (gap 2), then re-run.
  - For a **slug-only** match with no history match, add: "if `<G>` is unrelated to your change,
    re-slug yours."

### Phase 3 — wire `check` into `.github/workflows/tenant-integration.yml`

1. **`detect-changes`: new step `Resolve dev-ledger-parity guard state`.**
   - This job already has `fetch-depth: 0`, the full history the deleted-on-base arm needs. On the
     heavy job's `fetch-depth: 2`, `git log -1` falls back to `introduction`, which fails open
     (Kieran and simplicity reviews).
   - It uses #8597's three arms with `base_ref="${BASE_REF:-main}"`, stripped of `refs/heads/`.
   - It emits `outputs.ledger_guard: base | introduction | deleted`, or `n/a` on `merge_group`.
   - The step **never exits non-zero**: it only emits. A failure here would fail the always-run
     aggregator and stall the merge queue.
   - It runs after `filter` for every event.
2. **Heavy job: `Resolve dev-ledger-parity guard (base-ref copy)`.**
   - Placement: **after** `Lint migration FK preconditions` and before `Acquire dev-suite mutex`.
   - Input: `LEDGER_GUARD: ${{ needs.detect-changes.outputs.ledger_guard }}` via `env:`.
   - `case "$LEDGER_GUARD" in`:
     - `base)`: run `git fetch --no-tags --depth=1 origin "$base_ref"`, then
       `git show "origin/$base_ref:<path>" > "$RUNNER_TEMP/dev-ledger-parity.sh"`. The file must be
       non-empty, otherwise exit 1.
     - `introduction)`: copy the checkout copy.
     - `deleted)`: `::error::` naming the fix, "retire the guard by removing the script **and** its
       workflow steps together in one PR", then exit 1.
     - `*)`: `::error::unknown ledger_guard state`, then exit 1. This covers the empty output an
       earlier `detect-changes` failure leaves.
3. **`Assert unmerged migrations match the dev ledger`.**
   - Placement: after `Detect dev-vs-main migration drift`, before
     `Preflight schema-vs-ledger consistency check`, inside the mutex window.
   - Command:
     `doppler run -p soleur -c dev_scheduled -- bash "$RUNNER_TEMP/dev-ledger-parity.sh" check --base "origin/$base_ref" --repo "$GITHUB_WORKSPACE" --head-branch "$HEAD_BRANCH"`.
   - `HEAD_BRANCH: ${{ github.head_ref }}` via `env:`, and it is empty on push and dispatch.
   - It runs before apply because of how A1 plays out: the runner skips the stale file, so a later
     dependent migration fails **inside** apply with an unrelated error, and the guard's message must
     come first.
4. **Anchor.** Append `|apps/web-platform/scripts/dev-ledger-parity` to the `detect-changes`
   alternation.
5. **Comment block.** Cover the property, why the job fails instead of re-applying, ADR-061 and #8521.
   No `github.event.*` appears in `run:`. `github.head_ref` goes through `env:` only.

### Phase 4 — authoritative-side classification (arm 3)

`.github/actions/dev-migration-drift-probe/action.yml`, step `probe`:

- **Pre-existing log-injection fix (security review).** The `skipping suspicious _schema_migrations row: $f`
  warning echoes a raw, PR-writable ledger name. It becomes a count-only line.
- **Collect pairs separately.** Keep `missing_drift` for display unchanged, and collect
  `missing_pairs+="$f|$sha_applied"$'\n'` separately for the classifier.
- **Call the classifier** only when `FAIL_ON_DRIFT == true` and `missing_pairs` is non-empty:
  `bash apps/web-platform/scripts/dev-ledger-parity.sh classify-missing --base-branch main --repo "$GITHUB_WORKSPACE" <<<"$missing_pairs"`
  from the checkout.
  - PR-mode runs never reach this, because `fail-on` is `false` on `pull_request` (tenant-integration.yml's `Detect dev-vs-main migration drift` step).
  - A scheduled dispatch on a non-main ref runs that ref's copy. Dispatch requires repo write, the
    same trust as pushing a branch.
  - This is the **normal** case, not a rare path. Dev nearly always carries open PRs' rows, so it
    runs twice per push and once per scheduled run, and AC8 budgets it.
- **`classify-missing` re-validates its stdin.** It checks the filename whitelist and
  `^[0-9a-f]{40}$`, and any bad input line gives exit 2. It then emits one line per input line, in
  input order: `in-flight<TAB><file><TAB><branch><TAB><exact|blob|slug>`, `stale<TAB><file><TAB><branch><TAB><age-days>`,
  or `orphan<TAB><file>`. It ends with the stderr summary `ledger-classify: in-flight=N stale=M orphan=K`.
- **The action checks the classifier's output.** Line *i* must name file *i*. A count match alone is
  not enough (security review).
- **Mapping verdicts to annotations:**
  - in-flight becomes `::warning::  - <F> (in-flight: unmerged on live branch <b> via <tier> — merging clears it; deleting the branch unmerged turns main red)`;
  - stale becomes `::error::  - <F> (stale: only owner <b> has had no commit for <n> days — push to it, or have the dev apply reverted and delete the branch; #8605)`;
  - orphan keeps the existing Missing-on-main `::error::` block, with one added line: `no live branch owns these rows — a dev reconcile is required (learning gap 2; #8605)`.
- **Fail-closed (observability review).**
  - When the classifier exits non-zero, or the per-line check fails, **first** print
    `::error::ledger-classify: UNCLASSIFIED (rows=<n> rc=<rc>) — could not classify missing-on-main rows; not evidence of drift; failing closed`.
  - Then list those rows under an `Unclassified:` heading, not under `Missing-on-main:`.
- **Exit decision.** Exit 1 on any orphan, stale, unclassified or content-drift row. `drift-detected`
  keeps meaning "any row reported".
- No workflow or permission change is needed.

### Phase 5 — repair paths named (P6) + records

- **`action.yml` content-drift block.** Add:
  `::${sev}::Repair: knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md §Content drift — class each row A (comment/whitespace-only → rewrite content_sha), B (file idempotent AND safe against later redefinitions → re-apply main's file, then content_sha), C (targeted SQL against the LATEST main definition of each object). Pre-merge prevention: apps/web-platform/scripts/dev-ledger-parity.sh check (#8521).`
- **Learning `2026-05-21-…md`.** Add a new `## Content drift (same filename, different blob)` section
  with the A/B/C procedure distilled from #8520's 2026-09-21 comments:
  - triage read-only first;
  - judge each row against the latest main definition;
  - run one transaction per row;
  - worked example: apply 094 before 117.
- **ADR-061 amendment.** See Architecture Decision.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Re-apply the edited unmerged file (issue option 1a) | Rejected. Idempotent files leave old-body residue silently (#8520: the 075 `FOR ALL` policy, the 122 index). Non-idempotent files fail later and less clearly. |
| Ephemeral per-PR DB / Supabase branching (issue option 2) | Rejected (ADR-023, ADR-061). Per-ref checks reach P1, P2 and P5 at near-zero cost. |
| Ownership via `gh pr list --json files` (first draft) | Superseded. The files list is capped at 100 per PR, it needs `pull-requests: read`, and a GitHub API outage would red the authoritative gate. |
| Ownership fetch into the workspace (`refs/ledger-owners/*`, `--depth=1`, `--unshallow`) (v2) | Superseded at deepen-plan. `--filter` converts the checkout to a partial clone, and `--depth=1` re-shallows it. `--unshallow` on a complete repo exits 128, stale refs survive between probes, and fetch order can cut main's history. A throwaway bare repo with one full blobless fetch avoids all of it. |
| Downgrade Missing-on-main to `::warning::` unconditionally (advisor option a) | Rejected. Orphans from abandoned or renamed branches would go silent again. |
| Unbounded branch-lifetime ownership | Rejected at deepen-plan (security, observability). 95 branches versus 51 open PRs means "live" is not "unmerged". Owners need a commit in the last 30 days, and otherwise the verdict is `stale`, which blocks. |
| Post-apply second check (P3) | Cut at plan review. Its window exists only while the mutex fails open, and #8049 tracks that residual. |
| A single post-apply check instead of pre (DHH) | Rejected. A1 makes the runner skip the stale file, so a dependent migration fails inside apply before any post check could run. |
| Content-sha check inside `run-migrations.sh` (CTO) | Cut. That script is PR-controlled and is also the prd apply path. Its test stub would break, and the logic would be duplicated. |
| Composite-action extraction of the three-arm resolution / a list-driven `detect-changes` guard step (DHH, architecture) | Not taken now. The state logic lives once, in `detect-changes`, and the list generalization is recorded in `decision-challenges.md`. |
| `--ledger-file` mode, `BEGIN READ ONLY` wrapper, pinned `LEDGER_PARITY_BASE` (v1) | Cut at plan review. They buy no property. |
| CI auto-delete of rename orphans / a dispatchable dev-reconcile workflow | Deferred to #8605. The CTO's argument for bringing it into scope is in `decision-challenges.md`. |
| Ledger `applied_by_ref` column | Cut. It is a schema change on prd, for a property that branch heads already give. |

## Files to Create

- `apps/web-platform/scripts/dev-ledger-parity.sh`
- `apps/web-platform/scripts/dev-ledger-parity.test.sh` (auto-discovered via `scripts/test-all.sh`
  `SUITE_GLOBS` `'apps/web-platform/scripts/*.test.sh'`)

## Files to Edit

- `.github/workflows/tenant-integration.yml`:
  - `detect-changes`: the `ledger_guard` step and output, and the anchor;
  - heavy job: the resolve step and the check step.
- `.github/actions/dev-migration-drift-probe/action.yml`:
  - the count-only suspicious-row line;
  - `missing_pairs`;
  - the classifier call and verdict mapping;
  - the fail-closed `UNCLASSIFIED` arm;
  - the repair-path lines.
- `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`:
  §Content drift.
- `knowledge-base/engineering/architecture/decisions/ADR-061-per-ref-behavioural-schema-gate-over-shared-dev.md`:
  the amendment.

Not edited, by decision:

- `apps/web-platform/scripts/run-migrations.sh` (#8606 tracks its cwd bug);
- `apps/web-platform/scripts/lint-migration-immutability.sh`;
- `.github/workflows/scheduled-dev-migration-drift.yml`.

## Open Code-Review Overlap

One open scope-out touches a file named in this plan's research: #3364, a postgres-role ownership
guard in `run-migrations.sh`.

**Acknowledge.** This plan does not edit `run-migrations.sh`, because it is the prd apply path. #3364
stays open.

No open code-review issue names `tenant-integration.yml`, the drift-probe action, the learning, or
ADR-061.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-061**
(`knowledge-base/engineering/architecture/decisions/ADR-061-per-ref-behavioural-schema-gate-over-shared-dev.md`)
via `soleur:architecture`, adding `## Amendment 2026-09-23 (#8520, #8521): ledger gates are per-ref too`:

1. **Ownership on the authoritative probe.** This covers push-to-main, main dispatch and the scheduled
   probe. A missing-on-main row that a fresh, unmerged `origin` branch holds, by exact name, or by
   blob or slug among files **not on main**, is an in-flight `::warning::`. **An ownerless row counts
   as main's**, because no other ref can fix it, so it blocks. So does a row whose only owner is
   stale (older than 30 days), and a row whose filename is in main's history.
   - This reconciles with ADR-061's "current ref owns it" rule.
   - It records that the rejected alternative "Blocking orphan-migration-drift probe on push:main" is
     **superseded in part**: the alternative was right about in-flight rows and wrong about ownerless
     ones.
   - It cites #7964 §M2 and runs 35732801080 and 35736906203.
   - The blob and slug tiers are load-bearing. Exact-name matching alone would red main for the whole
     lifetime of a PR that renamed its migration.
2. **Policy: a migration applied to shared dev is immutable, merged or not.** Changes ship as a new
   file.
   - **Accepted cost:** fix-up migrations become permanent on prd, and the migration count grows.
   - Automatic re-apply joins Rejected alternatives, because it leaves silent residue.
   - `dev-ledger-parity.sh check` is the per-ref half of this that makes the owning PR fail.
   - Also added to Rejected alternatives: the ephemeral DB (trigger fired, re-evaluated, still
     rejected).

The ADR keeps its number, so there is no ordinal collision risk.

### C4 views

**No C4 impact.** Checked against all three files (`model.c4`, `views.c4`, `spec.c4`):

- **External human actors:** none added. `contributor` already models PR authors and PR-head
  isolation.
- **External systems:** `github` and `doppler` are already modeled. The only new calls are git
  fetches inside `github`.
- **Data stores:** `platform.infra.supabase` is prd. The shared dev project and its CI edge are
  unmodeled today and unchanged in kind: one extra SELECT on an existing connection.
- **Access relationships:** none change.

`plugins/soleur/test/c4-count-parity.test.sh` reported `ALL TESTS PASSED` on 2026-09-23.

### Sequencing

The ADR amendment ships in this PR. Its status stays Accepted.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. Every surface is repo CI over the
  shared **dev** project.
  - Broken toward false-red: migration PRs, or main via Phase 4, cannot merge, which delays
    user-facing fixes.
  - Broken toward false-green: dev keeps a stale or residue schema, and main reds after merge. This is
    the #8520 class, which included a dev policy that let workspace members modify each other's shared
    conversations.
  - prd is unaffected: it applies only main's files, in order.
- **If this leaks, the user's data is exposed via:** no user-data vector.
  - Dev holds synthetic data only (`hr-dev-prd-distinct-supabase-projects`).
  - The guard reads filenames and hashes.
  - The classifier reads public branch heads with the job's existing read-only checkout credentials.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: no touched path matches preflight SENSITIVE_PATH_RE (tenant-integration.yml, .github/actions/**, apps/web-platform/scripts/** and knowledge-base/** checked 2026-09-23) and no step reaches prd or user data.`

## Observability

```yaml
liveness_signal:
  what: "'ledger-parity: clean|RED (…)' from dev-ledger-parity.sh check in every tenant-integration heavy-job run; 'ledger-classify: in-flight=N stale=M orphan=K' from the probe on every authoritative run that sees missing rows"
  cadence: "per heavy-job run (every migration-touching PR push, every push to main) + every 6 h via scheduled-dev-migration-drift.yml (dispatched by cron-dev-migration-drift)"
  alert_target: "layer 6 — required check tenant-integration-required (red PR / red main commit). The scheduled run's failure has no dedicated reader; an orphan/stale row it finds also reds main's required check on the next push, which is the effective alert."
  configured_in: ".github/workflows/tenant-integration.yml (detect-changes 'Resolve dev-ledger-parity guard state'; heavy job 'Resolve dev-ledger-parity guard (base-ref copy)' and 'Assert unmerged migrations match the dev ledger'); .github/actions/dev-migration-drift-probe/action.yml (step probe)"
error_reporting:
  destination: "layer 6 — GitHub Actions ::error:: annotations + required-check status; no Sentry (dev-only CI surface; the probe's Sentry path stays scoped to rpc-body drift, unchanged)"
  fail_loud: "'ledger-parity: RED (…)' plus one ::error:: per violation naming file, blobs and repair path; exit 2 ends '— not caused by this PR; re-run the job' (transient) or '— … a re-run will not help' (config); classifier failure prints '::error::ledger-classify: UNCLASSIFIED (rows=<n> rc=<rc>) …' first"
failure_modes:
  - mode: "PR edits an unmerged migration after CI applied it (A1)"
    detection: "layer 6 — workflow run log (::error:: from the check step, before apply and tests)"
    alert_route: "PR's tenant-integration-required red"
  - mode: "PR renames, re-slugs or deletes an applied unmerged migration (A2/A4)"
    detection: "layer 6 — workflow run log (::error:: from the check step)"
    alert_route: "PR check red"
  - mode: "ledger unreadable, no DB URL, zero rows, base unresolvable, owner fetch timeout"
    detection: "layer 6 — workflow run log (::error:: exit-2 message classed transient or config)"
    alert_route: "PR check red; message says not caused by this PR"
  - mode: "guard deleted on base, or unknown ledger_guard state"
    detection: "layer 6 — workflow run log (::error:: from the resolve step)"
    alert_route: "PR check red"
  - mode: "live, fresh branch's in-flight row during a push to main or a scheduled run (arm 3)"
    detection: "layer 6 — workflow run log (::warning:: naming the branch + 'ledger-classify:' summary)"
    alert_route: "annotation only, by design (ADR-061)"
  - mode: "stale owner (> 30 days) or ownerless orphan or name in main history"
    detection: "layer 6 — workflow run log (::error:: stale/Missing-on-main, exit 1)"
    alert_route: "main tenant-integration-required red; scheduled probe red"
  - mode: "classifier failure (git remote, timeout, script abort)"
    detection: "layer 6 — workflow run log ('ledger-classify: UNCLASSIFIED (rows= rc=)' printed first, rows listed as Unclassified)"
    alert_route: "main check red (fail closed); message says not evidence of drift"
logs:
  where: "GitHub Actions run logs for tenant-integration.yml and scheduled-dev-migration-drift.yml (gh run view <id> --log)"
  retention: "GitHub Actions log retention (repo default, 90 days)"
discoverability_test:
  command: "bash apps/web-platform/scripts/dev-ledger-parity.sh --help"
  expected_output: "ledger-parity: or ledger-classify:"
```

`--help` prints the exit triad and the literal formats of both summary lines, which are the strings
an operator greps for in a run log. It needs no database and no network. It proves only that the
script and its vocabulary exist. That the script is **wired** in is proven by AC3's wiring asserts.

## Guard Contract

### Guard 1 — unmerged-migration ledger parity (`dev-ledger-parity.sh check` + its workflow step)

**Property.** For every forward migration in the checkout that is absent from the base tree, the dev
ledger either lacks it or records exactly this tree's blob. In addition, no ledger row that is on
neither main nor this tree, and that no other fresh live branch holds by exact name, may match one of
this PR's files by blob or slug, or match a blob this PR's branch history carried.

**Assembly.** There is one chokepoint on each side.

- **Population.** The working-tree glob `apps/web-platform/supabase/migrations/*.sql`, minus
  `*.down.sql`. A file is unmerged when `git -C $REPO ls-tree <base> -- ':(top,literal)<path>'` returns
  empty output with rc 0. Its blob is `git -C $REPO hash-object`, the same function the runner uses.
- **Ledger.** One `SELECT … FROM public._schema_migrations` read.
- **Ownership and history.** One `owners_repo` build, shared with Guard 2.
- **State.** One `detect-changes` output, `ledger_guard`.
- **Wiring.** Exactly one invocation site: after `Detect dev-vs-main migration drift`, before
  `Apply migrations to dev`, and inside the mutex window. It executes
  `$RUNNER_TEMP/dev-ledger-parity.sh`, produced by the single resolve step.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Ledger row `F` whose `content_sha ≠ blob(F)`, with `F` unmerged | RED exit 1, names `F` and both SHAs |
| 2 | Two unmerged files: `F1` ledgered at its own blob, `F2` mismatched | RED exit 1, names `F2` only (second member) |
| 3 | Ledger `G` not on base, not in tree, and not on any branch, with `content_sha == blob(F)`; PR head branch pushed to origin | RED exit 1 (A2 blob) |
| 3b | As row 3, but another fresh branch holds `G` only by **blob or slug**, not by name | RED exit 1 (Guard 1 accepts exact-name ownership only) |
| 4 | Ledger `G` with a different blob and `slug(G) == slug(F)` | RED exit 1 (A2 slug) |
| 4b | The PR branch's history once held `G@S`, the tree no longer has it, and the ledger has `G\|S` | RED exit 1 (A4) |
| 5 | Ledger row `F` with an empty `content_sha` | RED exit 1, with the empty-sha message (no bare `git show` with an empty SHA) |
| 5b | Ledger row `F` whose `content_sha` is uppercase or short | RED exit 1 (treated as absent) |
| 6 | Stub `psql` exits 2 | exit 2 `transient` |
| 7 | Stub `psql` returns 0 rows, with `U` non-empty, and again with `U = ∅` | exit 2 `config` in both cases (order row: no early return before the floor) |
| 8 | No `DATABASE_URL_POOLER` and no `DATABASE_URL` | exit 2 `config` (not 1) |
| 9 | `--base` does not resolve | exit 2 |
| 9b | `--repo` is missing or lacks the migrations dir | exit 2 |
| 10 | A candidate exists and the origin URL points at a missing path | exit 2 `transient` |
| 11 | Run with cwd `$REPO/apps/web-platform` on the row-1 fixture | still RED exit 1 (#8606 class) |
| 12 | Workflow: the check step moved after `Apply migrations to dev`, or after `Release dev-suite mutex` | wiring assert RED (step names anchored `^      - name: <exact>$`, count 1) |
| 13 | Workflow: the invocation uses the checkout path instead of `$RUNNER_TEMP/dev-ledger-parity.sh` | wiring assert RED |
| 14 | Workflow: the resolve step loses its `deleted)` or `*)` → `exit 1` arm | wiring assert RED |
| 15 | Workflow: the `ledger_guard` step leaves `detect-changes`, or `detect-changes` loses `fetch-depth: 0` | wiring assert RED |

**Must-PASS rows:**

- (a) unmerged `F`, ledgered at its blob → 0;
- (b) unmerged `F` with no row → 0, `pending=1`;
- (c) a *merged* file with a differing ledger blob → 0;
- (d) unmerged `F.down.sql` with no row → 0;
- (e) an unrelated orphan `Z` (different slug and blob, never in PR history) → 0;
- (f) a slug candidate held **by exact name** on another fresh branch → 0, with a `::notice::`;
- (g) tree == base → 0, with the notice and the floor still enforced;
- (h) a merged `G` with `slug(G) == slug(F)` → 0 (`∈ M` exclusion);
- (i) both DB URLs set → the pooler is used;
- (j) only `DATABASE_URL` set → that is used.

**Harness rows:**

- (H1) guard body replaced by `exit 0` → suite RED;
- (H2) guard body replaced by `exit 1` → suite RED;
- (H3) a case block deleted → floor RED;
- (H4) script absent → RED, not "0 passed, 0 failed";
- (H5) psql argv capture: exactly one call, exactly one `-c`, no `-f`/`--file`, the SQL byte-equal to
  `LEDGER_SQL`, and a grep that the script source contains exactly one `psql` invocation (AC7).

**Anchor, stated honestly (security review).** The base-ref copy stops a diff that edits the **script
alone**. It does not stop two things:

- `pull_request` runs the PR's own workflow file, so the PR controls the `ledger_guard` and resolve
  steps;
- PR code holds dev write credentials (migrations and tests run under `dev_scheduled`), so a PR can
  rewrite `_schema_migrations`.

Both are visible in review, and both are covered by the anchor that self-triggers the suite and by
the post-merge probe on main, which the PR does not control. It is the same trust boundary #8597
accepted. The deleted-guard decision comes from full history, so a shallow checkout cannot flip it.

### Guard 2 — in-flight ownership classification (`dev-ledger-parity.sh classify-missing` + probe wiring)

**Property.** Under `fail-on-ledger-drift`, a missing-on-main ledger row is downgraded to a warning if
and only if all three hold:

- its filename never appeared in main's history;
- a live `origin` branch holds it;
- that branch is not merged into main and has had a commit within 30 days. "Holds" means by exact
  name, or by an identical blob or slug among the branch's files that are **not on main**.

Every other missing row, every content-drift row, and every row that cannot be classified stays a
blocking error.

**Assembly.**

- **Chokepoint:** the `probe` step's `missing_pairs` goes to the classifier's stdin, and the classifier
  returns an ordered verdict per line.
- **Exit decision:** reads only the `orphan`, `stale` and `unclassified` verdicts plus the unchanged
  `content_drift`.
- **Ownership:** one `owners_repo` build per invocation, fresh each time, so nothing carries over
  between the pre-section and post-section probes.
- **Consumers:** both consumers of the action flow through the step: tenant-integration (twice) and
  the scheduled probe.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | The row is on no live branch head, because the branch was deleted | `orphan` → probe `::error::`, exit 1 |
| 2 | Two rows: the first in-flight, the second owned by nobody | the second is `orphan` (second member) |
| 3 | **Stale fork:** main renamed `128_x→131_x`, and a live branch forked earlier still holds `128_x` | `orphan` (main-history exclusion) |
| 3b | **Never-merged rename:** `128_x` was never on main, main has `131_x` with the same blob and slug, and every branch holds `131_x` | `orphan` (branches own only files absent from main) |
| 3c | Rows 3 and 1 in both input orders, in one invocation | the stale fork is `orphan` in both orders |
| 4 | Origin URL broken (fetch fails) | exit 2 → probe prints `UNCLASSIFIED (rows= rc=2)` first, rows listed under `Unclassified:`, exit 1 |
| 5 | The classifier emits lines in the wrong order, or fewer lines than input (stub) | the per-line check fails → `UNCLASSIFIED`, exit 1 |
| 6 | The only same-slug match is a `.down.sql` | `orphan` |
| 7 | A content-drift row whose file sits on a live branch | still `::error::` (only the missing class is classified) |
| 8 | The only holder is a `gh-readonly-queue/*` ref, or a head that is an ancestor of main | `orphan` |
| 9 | The only holder's last commit is 31 days old | `stale` → `::error::` naming the branch and its age, exit 1 |
| 10 | The branch is deleted between two classifier calls in the same workspace | first call `in-flight`, second `orphan` (no stale owner state) |
| 11 | Bad stdin line (bad name or bad sha) | exit 2 |
| 12 | Display after the change | Missing-on-main lists filenames only, with no `\|sha` |

Rows 4, 5, 7, 9 and 12 run the **extracted `probe` block** with stubbed `psql`/`doppler` and
`GITHUB_OUTPUT`. A grep of `action.yml` cannot see a logic change.

**Must-PASS rows:**

- an exact-name owner → `in-flight … exact`;
- a renamed file with an equal blob (not on main) → `in-flight … blob`;
- a renamed and edited file with an equal slug (not on main) → `in-flight … slug`;
- empty input → exit 0 with **no** remote call (origin URL poisoned);
- no filter support (the fixture origin has `uploadpack.allowFilter` unset) → same verdicts and rc.

**Harness rows:**

- (H1) classifier body replaced by `exit 0` with no output → RED;
- (H2) classifier prints `in-flight` for everything → rows 1–3b RED;
- (H3) the `CASES` floor stays adjacent to its `if`.

**Anchor.** The ownership evidence is `origin`'s live refs, their commit dates and main's history, all
outside this commit. Turning a true orphan into a warning takes a push to `origin` (repo write, bots
included) of a branch that is fresh, unmerged, and holds a file not on main. The deception expires
30 days after the branch's last commit. The threat model is "repo writers and bots only".

## Acceptance Criteria

### Functional Requirements

- [x] **AC1**: Guard 1 rows 1–11 plus 3b/4b/5b/9b hold, and must-PASS rows (a)–(j) hold, in
  `apps/web-platform/scripts/dev-ledger-parity.sh` `check`. Verified by
  `bash apps/web-platform/scripts/dev-ledger-parity.test.sh`.
- [x] **AC2**: Guard 2 rows 1–12 and its must-PASS rows hold, in `classify-missing` plus
  `.github/actions/dev-migration-drift-probe/action.yml` step `probe`. The probe logic rows run
  against the extracted block.
- [x] **AC3**: Guard 1 wiring rows 12–15 hold, asserted by exact anchored step names and relative
  order:
  - the `ledger_guard` step lives in `detect-changes`, which keeps `fetch-depth: 0`;
  - the resolve step sits after `Lint migration FK preconditions` and before
    `Acquire dev-suite mutex`, with `deleted)` and `*)` exit arms;
  - one check step sits between `Detect dev-vs-main migration drift` and `Apply migrations to dev`,
    running `$RUNNER_TEMP/dev-ledger-parity.sh check`.
- [x] **AC4**: The `detect-changes` alternation contains the token
  `apps/web-platform/scripts/dev-ledger-parity`.
- [x] **AC5**: `action.yml` has:
  - the `Repair:` line naming `§Content drift` and `dev-ledger-parity.sh check`;
  - the `no live branch owns these rows` line;
  - the `UNCLASSIFIED` arm;
  - the count-only suspicious-row line, with no `$f` in that annotation.

  The suite asserts all four.
- [x] **AC6**: The learning has `## Content drift (same filename, different blob)`, and ADR-061 has
  `## Amendment 2026-09-23` with both points and the "superseded in part" note on its Rejected
  alternative.
- [x] **AC7**: Scope stays narrow.
  - `git diff origin/main...HEAD --name-only` touches no `apps/web-platform/supabase/migrations/**`,
    no `run-migrations.sh` and no `lint-migration-immutability.sh`.
  - No workflow gains a `permissions:` key.
  - Harness row H5 holds: one `psql` call site, and the SQL is byte-equal to the literal.
  - The suite asserts that the checkout's `.git/config` and `.git/shallow` are unchanged after both
    subcommands run.

### Non-Functional Requirements

- [x] **AC8**: No-candidate runs make zero remote calls (must-PASS (e) and the Guard 2 empty-input row
  use a poisoned origin). The PR body records the measured wall time of one `owners_repo` build
  against the real `origin`, run twice per push inside the mutex window. Each build must stay under
  30 s, and the scheduled job must stay under its `timeout-minutes: 5`.
- [x] **AC9**: These pass or stay green:
  - `shellcheck` on the new script and suite;
  - `bash scripts/lint-orphan-test-suites.sh`;
  - `bash scripts/lint-workflow-step-env-refs.test.sh`;
  - `bash scripts/lint-workflow-errexit-capture.test.sh`;
  - `bash apps/web-platform/scripts/lint-migration-immutability.test.sh`.

### Quality Gates

- [ ] **AC10**: This PR's own heavy job runs (the change is anchored) in the `introduction` state and
  prints `ledger-parity: clean` with `unmerged=0` and `ledger-rows=<N>`, where N > 0.
- [ ] **AC10b (pre-merge, read-only)**: `gh workflow run scheduled-dev-migration-drift.yml --ref feat-one-shot-8521-dev-ledger-content-drift`
  runs this branch's action and script with `fail-on-ledger-drift: 'true'`. Its log shows either
  `ledger-classify:` (rows were missing) or `No dev-vs-main migration drift detected.`, and no
  `UNCLASSIFIED`. The wall time is recorded (architecture review: this is the only pre-merge
  exercise of Phase 4).
- [ ] **AC11 (post-merge smoke, not a correctness gate)**: the first `push` run on main is read with
  `gh run view <id> --log | grep -e 'ledger-parity:' -e 'ledger-classify:' -e 'No dev-vs-main migration drift detected.'`.
  - For each `in-flight … <branch>` line, confirm that
    `git diff --name-only origin/main...origin/<branch> -- apps/web-platform/supabase/migrations/`
    lists that file. This catches wrongly hidden orphans, not just false reds.
  - The run's conclusion depends on dev state that other refs write, so it is not asserted
    (`cq-ac-must-not-depend-on-concurrent-sessions`).
- [ ] **AC12**: The PR body carries `Closes #8520` and `Closes #8521`, the 2026-09-22 run evidence,
  the AC8 and AC10b timings, and #8606.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed

**Assessment.** The CTO agrees with the layering: a read-only guard running as the base-ref copy,
with ADR-061 per-ref ownership on main. The CTO also agrees with rejecting both automatic re-apply
and a per-PR database.

Folded in from the plan-review devex pass:

- exit-2 wording that says "not caused by this PR";
- A2 "re-slug yours";
- the accepted immutability cost, recorded in the ADR.

Folded in from the deepen pass:

- throwaway-repo ownership (architecture);
- the ownership exclusion for files absent from main, found as a P0 by security, spec-flow and
  test-design;
- the 30-day freshness rule plus the `stale` verdict (security, observability);
- A4, the PR-history check (spec-flow);
- the `UNCLASSIFIED` labelling (observability);
- AC10b, the pre-merge exercise of the classifier (architecture);
- the honest P4 anchor (security).

Taste and User-Challenge items went to
`knowledge-base/project/specs/feat-one-shot-8521-dev-ledger-content-drift/decision-challenges.md`:

- the dev-reconcile workflow;
- a push-time warning;
- the 30-day threshold value;
- generalizing the guard list.

**Product/UX Gate:** not applicable. There is no UI surface. No other domain is implicated.

## Test Scenarios

All scenarios live in one suite, `apps/web-platform/scripts/dev-ledger-parity.test.sh`. It covers the
Guard Contract rows plus these arcs:

1. **Edit-after-apply.** The ledger holds `140_x|B1` and the branch now has `140_x@B2`. `check` exits
   1 with A1, whose message includes `git show B1` and the `gh api` fallback.
2. **Remedy.** `140_x` is restored to `B1` and `141_y` is added. `check` exits 0 with `pending=1`.
3. **Rename.** The ledger holds `140_x|B1` and the tree holds `141_x@B1`.
   - With `feat` (the PR head) pushed, `check` exits 1 (A2 blob).
   - With `feat-other` holding `140_x` by name, `check` exits 0 with a notice.
4. **Delete-after-apply.** The PR branch history carried `140_x@B1`, and the tree no longer has it.
   `check` exits 1 (A4).
5. **In-flight.** Pairs `139_z|S`, and a fresh live branch holds `139_z@S`, which is not on main. The
   classifier warns and exits 0. After the branch is deleted on origin, it reports an error and exits
   1, run in the same workspace.
6. **Stale fork and never-merged rename.** Guard 2 rows 3, 3b and 3c.

## Deferrals

- **#8605** (filed during planning; labels `deferred-scope-out`, `meta/machinery`; milestone Post-MVP
  / Later). It tracks the missing self-service dev-reconcile path for discarding an applied version
  or clearing an orphan. The stale-branch arm it originally tracked is now partly closed by the
  30-day `stale` verdict. The CTO's view that the trigger fires almost at once is recorded in
  `decision-challenges.md`.
- **#8606** (filed during planning; labels `type/bug`, `meta/machinery`). The #4241 unmerged gate in
  `run-migrations.sh` does nothing under `working-directory: apps/web-platform`. This is pre-existing,
  and prd is unaffected.
- **#8049** stays open and separate. It absorbs the P3 residual (a same-filename write between check
  and apply while the mutex fails open) and the merge-queue residual (a same-named apply after this
  PR's last green run).

## Risks & Sharp Edges

- **Ownership cost is on the normal path.** It runs twice per push inside the mutex window and once
  per scheduled run. The measured cost is 6–10 s plus about 3 s. AC8 caps a build at 30 s, and the
  fetch timeout is 120 s, which exits 2 as `transient`.
- **The 30-day freshness rule can red main because of one abandoned PR's applied migration.** That is
  intended: the row is an orphan in the making. The error names the branch and gives both fixes. The
  threshold value is Taste and is recorded for operator review.
- **"Applied means immutable" adds friction.** The A1 message states the cost, and the ADR accepts
  it. #8605 tracks the self-service reconcile path.
- **Slug collisions** with an unrelated, unowned row block a PR that did nothing wrong. The message
  offers "re-slug yours" when the match is slug-only.
- **Wiring asserts** key on anchored exact step names and relative order, never line numbers
  (`cq-cite-content-anchor-not-line-number`). They assert whole tokens
  (`cq-assert-anchor-not-bare-token`). `Re-probe dev-vs-main migration drift (post-section)` contains
  the text of `Detect dev-vs-main migration drift`, so the step-name greps must be anchored.
- **Test fixtures** use `file://` URLs, with and without `uploadpack.allowFilter`.
- **User-Brand Impact.** A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one is
  filled.

## References

- **Issues:** #8520, #8521, #8583 (closed by #8597), #8049, #7964, #8475, #8507, #3364, #8605, #8606
- **Runs:** 35732801080 and 35736906203 (in-flight 139); 35743332992, 35744360560 and 35747451585
  (138 content drift); the green streak from `ade3dff1b` (run 35789724725)
- **ADRs:** ADR-061, ADR-023
- **Learnings:** `2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`,
  `2026-09-23-a-pr-must-not-control-the-guard-that-judges-it.md`,
  `2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md`
- **Prior plan whose §M2 premise this corrects:** `2026-09-21-fix-tenant-integration-shared-fixture-contention-plan.md`
