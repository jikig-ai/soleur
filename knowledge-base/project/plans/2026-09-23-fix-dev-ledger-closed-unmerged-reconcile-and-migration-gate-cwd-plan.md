---
title: "fix(ci): closed-PR ledger ownership, a dispatchable dev-reconcile discard path, and a repo-top-anchored run-migrations gate"
date: 2026-09-23
slug: fix-dev-ledger-closed-unmerged-reconcile-and-migration-gate-cwd
branch: feat-one-shot-8605-8606-dev-reconcile
issue: 8605
closes: [8605, 8606]
type: fix
lane: cross-domain
---

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `spec.md` exists for this branch; the one-shot path skipped brainstorm.)

## Enhancement Summary

**Deepened on:** 2026-09-23. **Agents:** security-sentinel, data-integrity-guardian, architecture-strategist, test-design-reviewer, observability-coverage-reviewer, and a verify-the-negative sweep (sonnet), on top of the plan-review panel (DHH, Kieran, code-simplicity, CTO) and the Step 4.5 advisor consult. Halt gates 4.6, 4.7, 4.8 and 4.11 passed; 4.5, 4.55, 4.9 and 4.10 did not fire.

### Key improvements

1. **The PR's own `.down.sql` can no longer run shell on the runner.** psql executes backslash meta-commands (`\!`, `\o |cmd`, `\copy … program`) from a `-f` file. Under `pull_request_target` that would expose main's cache scope and the dev secrets (security P0, data-integrity P2). Any backslash byte in a down body now refuses the run; 0 of the 95 down files on main contain one (measured).
2. **The refusal checks run on stripped SQL.** A line-anchored `BEGIN`/`END` match hit 51 of 95 down files, 48 of them only because of plpgsql function bodies. The writer now strips comments, quoted strings and dollar-quoted bodies before matching, then matches statement starts. The expected refusal set over all 95 down files on main is pinned by a test.
3. **One transaction per PR, not per row.** Every CAS delete and every down body run in a single `psql --single-transaction` unit, ordered by `applied_at` DESC (microseconds) then filename DESC, under `lock_timeout`/`statement_timeout`. The "rows already committed" partial-failure path is gone.
4. **Later-row safety covers redefinitions, not just CASCADE.** A down body that redefines shared objects (`CREATE OR REPLACE`, policies, grants, `ALTER FUNCTION`) or uses `CASCADE` is refused while any row applied after the PR's earliest row exists, because running it would silently revert main's later definition or drop another branch's objects. `allow_later_rows` (dispatch only) is the human override after a dry run.
5. **The grace lives in the classifier.** It emits `closed-grace` (under `CLOSED_GRACE_H=24`) or `closed`; the probe only maps verdict to severity.
6. **Unattended failures always file the issue.** The issue step fires on any job failure on the close path, not only a failed reconcile step. A failed `gh issue create` fails the job, and the 24 h `closed` verdict (with a Sentry event on the scheduled probe) is the backstop. Detection ceiling for a silent non-run: about 30 h.
7. **The test harness can see what it asserts.** The fake psql records `-f` contents at call time under a writer-mode contract; every zero-write row has a positive control; the fake gh is routed and sequenced, and can never fall through to a real `gh`.

### New considerations discovered

- The architecture review recommends a transient PR-state failure degrade to an unverified in-flight warning. That contradicts the operator's "keep the classifier fail-closed", so it is recorded as a User-Challenge (DC-5) and not applied. One bounded retry on 5xx/429 is added instead; 401/403/404 map to `config`.
- Sourcing the guard as a library needs `declare -gA` for its top-level associative arrays, or a source inside a function leaves the writer's "never in base history" test empty.
- A PR closed with "delete branch" reads `orphan` at once (blocking, no grace) until the close-time discard lands. P8 is narrowed to branch-retained closes, and the orphan line now carries a lookup hint.
- A dispatch with `execute=true` on an OPEN PR is limited to the PR's author and refuses ledger-only rows, so it cannot reproduce ADR-061's rejected "re-apply leaves residue" path.

## Overview

One pull request for three linked pieces of the shared-dev migration ledger work that follows PR #8602 (merged 2026-09-23 as `d42057b67d`).

1. **#8606 — run-migrations gate is inert from a subdirectory.** `apps/web-platform/scripts/run-migrations.sh` checks each file with `git ls-tree origin/main -- "apps/web-platform/supabase/migrations/$filename"`. `git ls-tree` resolves that path against the current directory, so when `tenant-integration.yml` and `rls-authz-fuzz.yml` run the script with `working-directory: apps/web-platform`, every file is "not on origin/main". Anchor both pathspecs on the repository top with `:(top,literal)` and prove it with tests that run from `apps/web-platform`. From the repository root (the prd release path) the anchored pathspec names the same path, so prd behaviour does not change.
2. **#8605 (a) — closed PRs stop protecting their rows.** `dev-ledger-parity.sh classify-missing` calls a missing-on-main row in-flight whenever a fresh, live, unmerged branch holds it. A branch whose PR was closed and never deleted protects its rows forever. The classifier gains a read-only PR-state lookup (GitHub REST, `pull-requests: read`, only for fresh owner branches) and two new verdicts: `closed-grace` (a warning, for 24 hours after the PR closed at the branch tip) and `closed` (blocking). It stays fail-closed: a lookup it cannot complete exits 2, which the probe reports as UNCLASSIFIED.
3. **#8605 (b) — an audited, dispatchable dev-reconcile path.** A new writer script, `apps/web-platform/scripts/dev-ledger-reconcile.sh`, that sources the guard's ownership primitive, driven by a new workflow `.github/workflows/dev-ledger-reconcile.yml`. For one pull request it discards the applied-but-unmerged migration versions that PR owns: a compare-and-set delete of each ledger row plus the paired `.down.sql` when there is one, all in one transaction for the PR, under the dev-suite mutex, on dev only. It runs automatically when a same-repo PR is closed without merging, and on `workflow_dispatch` from `main`.
4. **Archive the #8521 artifacts.** Tick AC11 of `2026-09-23-fix-pr-ci-unmerged-migration-ledger-parity-plan.md` with the recorded evidence, `git mv` the plan and `specs/feat-one-shot-8521-dev-ledger-content-drift/` through `archive-kb`, and repoint the one live reference.

Operator direction (2026-09-23): ship all of it in one PR; **DC-1 accepted** — a CI path that writes to the shared DEV Supabase ledger and schema (never prd). ADR-061 gets a new, append-only amendment recording that decision, and it reverses the previous amendment's "No GitHub API, no new permissions" for the classifier.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (measured 2026-09-23) | Plan response |
|---|---|---|
| #8606: the gate "does nothing" in CI. | Both CI callers set `ALLOW_UNMERGED_DEV_APPLY=1`, so CI never *blocks*; the defect is one false `::warning::` per merged file and a collision warning computed against an empty main listing. A LOCAL run from `apps/web-platform` without the ack is blocked on file 001 (fail-closed, not fail-open). Verified: from `apps/web-platform`, `git ls-tree origin/main -- ':(top)apps/web-platform/supabase/migrations/001_initial_schema.sql'` → 1 line; the bare path → 0 lines. | Fix both pathspecs; test from the subdirectory, including the collision listing. |
| #8606: prd not affected. | `web-platform-release.yml` runs `doppler run -c prd -- bash apps/web-platform/scripts/run-migrations.sh` from the repo root with no ack — the gate is live on prd. From the root `:(top,literal)X` names exactly `X`. | Keep the root-cwd tests as the regression control (AC2). |
| `ls-tree` output under `:(top)` from a subdir. | Paths print RELATIVE to cwd (`supabase/migrations/…`). The collision code reduces each path with `basename`, so it is unaffected. (`--full-tree` also works from the subdirectory — verified — and prints full names; `:(top,literal)` is kept because `dev-ledger-parity.sh` already uses it for the same tree, so one convention covers both scripts.) | Note in Sharp Edges. |
| ADR-061 amendment 2026-09-23: classifier "uses git only … No GitHub API, no new permissions". | Git cannot tell a closed PR from an open one: no ref records PR state. | A new amendment records the reversal and the least-privilege scope (`pull-requests: read`, `GITHUB_TOKEN`, lookup only for fresh owner branches). |
| "Must hold the dev-suite mutex." | `scripts/dev-suite-mutex.sh acquire` is **fail-OPEN**: on contention it prints `DEV_SUITE_MUTEX_CONTENDED_PROCEEDING` and exits 0; on an unusable primitive `DEV_SUITE_MUTEX_UNAVAILABLE` and exits 0. Its default wait is `WAIT_S=180`, shorter than a 5-9 min tenant-integration critical section. | The writer acquires with `DEV_SUITE_MUTEX_WAIT_S=600` and its own `DEV_SUITE_MUTEX_STATE_DIR`, and proceeds only on a `DEV_SUITE_MUTEX_ACQUIRED` line; anything else exits 2 before any write. No change to the mutex script. |
| Learning §Content drift: "fetch the applied body by its sha (`git show` / `gh api …/git/blobs`)". | The owner repo is blobless with `GIT_NO_LAZY_FETCH=1`. The blobs API's JSON `content` is base64 wrapped every 60 chars, which `jq @base64d` rejects (verified). `gh api -H 'Accept: application/vnd.github.raw+json' …/git/blobs/<id>` returns the raw bytes; `git hash-object` of the result equals the id (verified on `122_inbox_item.down.sql`). | The writer fetches down bodies with the raw media type and verifies the hash. |
| Learning Part 1: `NOTIFY pgrst, 'reload schema'` after function changes. | `run-migrations.sh` documents that a NOTIFY over the IPv4 pooler never reaches PostgREST (#4285); the working path is the Management API, and `dev_scheduled` deliberately holds no Management token (#8028 DC-1). | The writer does not NOTIFY; PostgREST's ~10-min schema poll picks the change up (stated in the audit comment). |
| AC11 of the #8521 plan is open. | Run 35891815286 (push, `main`, head `d42057b67d`, conclusion success) printed `No dev-vs-main migration drift detected.` and `ledger-parity: 0 unmerged migrations in this tree`. No `in-flight` lines, so the per-branch sub-check has nothing to confirm. | Tick AC11 citing that run, then archive. |

## Research Insights

**Premise Validation.** Checked: #8605 OPEN, #8606 OPEN, #8521 CLOSED (by PR #8602, MERGED `d42057b67d`). All cited paths exist on this branch (branched after `d42057b67d`): `run-migrations.sh`, `dev-ledger-parity.sh` (subcommands `check`, `classify-missing`), `dev-ledger-parity.test.sh` (`EXPECTED_CASES=100`, promoted in `scripts/guard-vacuity-floor.test.sh` `PROMOTED_FILES`), `.github/actions/dev-migration-drift-probe/action.yml`, the learning's §Content drift, ADR-061 with its 2026-09-23 amendment. The AC11 evidence run was re-read with `gh run view 35891815286 --log`. ADR corpus check for the proposed mechanisms: ADR-061 rejects "automatically re-apply an edited unmerged migration" (this plan never re-applies; the writer removes, and the PR's next CI run applies fresh) and "an `applied_by_ref` ledger column" (this plan adds no column). Its "no GitHub API" line is a property of the previous amendment, not a rejected alternative; the new amendment supersedes it explicitly. Nothing stale.

**Property List (Phase 0.6b).**

- P1 — The unmerged-apply verdict and the coexists-with listing are the same from the repo root and from `apps/web-platform`.
- P2 — Repo-root behaviour of `run-migrations.sh` (the prd apply path) is unchanged.
- P3 — A dev ledger row whose only fresh holders are branches whose PR is closed is not in-flight; after a grace window it blocks main's probe with a named repair.
- P4 — The classifier stays fail-closed: any PR-state lookup it cannot complete makes the row UNCLASSIFIED (blocking), never in-flight.
- P5 — An applied-but-unmerged version can be discarded without a hand-run SQL session: CAS ledger delete + the paired `.down.sql` if present, only for rows the named PR owns, never by dropping another branch's objects or reverting a later definition, and never by letting the PR's SQL reach a shell.
- P6 — That path never writes to prd and never writes without holding the dev-suite mutex.
- P7 — Every discard, refusal and residue leaves a durable, human-readable record (who, which PR, which rows, which blobs), and a refusal reaches the operator.
- P8 — Closing a migration PR unmerged with its branch retained does not red main while its close-time discard can still succeed (grace window); a refused or unfired discard surfaces to the operator before it can red main. (A PR closed with "delete branch" reads `orphan` until the discard lands — the existing ADR-061 behaviour, now bounded by minutes.)
- P9 — The #8521 plan and spec are archived with AC11 ticked, and no live file points at their old paths.

**Cut List.**

- `pull_request: closed` job as the *learning* mechanism for "closed" → P3 → cut as a learning mechanism: it only sees closures after it ships and cannot answer for branches closed earlier; the classifier's own PR-state lookup covers every branch. The close event is kept only as the *trigger* for P8's auto-discard, where `pull_request_target` (base-branch workflow, no PR-head code executed) is the safe form.
- Putting the writer inside `dev-ledger-parity.sh` as a subcommand → P5/P6 → cut (advisor consult): it would put database-write code in the file `tenant-integration.yml` extracts and runs as the read-only PR guard, and make every future guard edit a writer edit. The writer is its own file that sources the guard as a library.
- One paginated `gh api pulls?state=all` listing matched locally (advisor suggestion) → P3 → declined: the closed-PR list is unbounded and grows forever, while per-branch lookups are memoised and run only for fresh owner branches (0-3 on a typical probe).
- A dev audit table → P7 → cut: a table is a migration that also lands on prd. A PR comment, the job summary, `::notice::` lines and an `action-required` issue on refusal cover P7.
- Changing `check` (PR side) to consult PR state → no property needs it: `check` only *excuses* rows another fresh branch holds. `check` keeps its zero-API property.
- A strict mode in `dev-suite-mutex.sh` → P6 → cut: the caller reads the banner token and sets its own wait budget; the mutex script and its two suites stay untouched.
- *(plan review)* `--file` filter and `files` input → no property → cut: P5 is "rows the named PR owns", the whole PR.
- *(plan review)* Touched-migrations pre-check step → no property → cut: the writer exits 0 before the mutex when the PR's history carries no migration (step 4 is git-only), which also covers a PR that added then removed a migration (a `paths:` filter would miss that).
- *(plan review)* Per-PR concurrency group → no property → cut: the mutex serializes writers and the CAS makes a repeated run a no-op.
- *(plan review, reversed at deepen)* Workflow-level Doppler `configs get` assertion → P6 → restored: `DOPPLER_ENVIRONMENT` is settable by hand, so the in-process check alone is weaker than the `tenant-integration.yml` assertion (security review); both run, plus the `SUPABASE_ACCESS_TOKEN`-absent check.
- *(plan review)* Ops email → P7 → cut: the `action-required` issue carries the dispatch command and reaches operator-digest; one channel.
- *(plan review)* Mutant-copy control and static census for #8606 → no property → cut: the subdirectory cases written RED first prove the harness sees the defect, and the census as specified could not pass (five comment lines in `run-migrations.sh` mention `ls-tree`).
- *(plan review)* `NOTIFY pgrst` in each unit → cut: it cannot reach PostgREST over the pooler (#4285).
- *(plan review, declined)* Close to warning-only with dispatch-only reconcile (code-simplicity) → recorded as a User-Challenge in `knowledge-base/project/specs/feat-one-shot-8605-8606-dev-reconcile/decision-challenges.md`; the operator's direction (auto-handle closed PRs, e.g. a close job) stands.
- *(plan review, declined)* Scheduled probe auto-dispatches the reconcile for `closed` lines (CTO) → needs `actions: write` on a scheduled job; the 24 h grace plus the `action-required` issue plus a 600 s mutex wait cover P8 without it. Recorded as Taste.
- *(deepen, declined)* Degrade a transient PR-state failure to an unverified in-flight warning (architecture) → contradicts the operator's fail-closed direction; recorded as DC-5. One retry on 5xx/429 added instead.
- *(deepen, declined)* Refuse a `:6543` transaction-mode pooler URL in the writer (data integrity) → no measured basis: `run-migrations.sh` applies multi-statement files through the same `DATABASE_URL_POOLER` with the same `psql --single-transaction` mode on every CI run, so a port rule adds only false-refusal risk.
- *(deepen, declined)* A liveness `discoverability_test` via the public workflows API (observability) → it returns 404 before merge, so preflight Check 10 would fail at ship; kept as post-merge AC16 instead.
- *(plan review, declined)* Separate test suite for the writer (CTO) → recorded as Taste; cases stay in the existing suite, whose fixture origin, fakes and floor promotion already exist.

**Relevant files.**

- `apps/web-platform/scripts/run-migrations.sh` — gate pathspec in the per-file `if [[ -z "$(git ls-tree origin/main -- …$filename…)" ]]` block; collision listing in the `main_with_prefix=$(git ls-tree origin/main -- "apps/web-platform/supabase/migrations/" …)` pipeline; the header comment above `MIGRATIONS_DIR=` that says the gate "stays anchored to the canonical repo path".
- `apps/web-platform/test/scripts/run-migrations-unmerged-gate.test.ts` — `runScript()` hard-codes `cwd: REPO_ROOT`; 3 cases; minimal two-file fixture `{053_template_authorizations.sql, zzz_unmerged_gate_<hex>.sql}` via `RUN_MIGRATIONS_TEST_DIR`. Listed in `apps/web-platform/test/repo-wide-suites.ts`.
- `apps/web-platform/scripts/dev-ledger-parity.sh` — `owners_repo()` (blobless bare owner repo, `+refs/heads/*:refs/owners/*`), `owner_lookup()` (returns only the lexically smallest holder), `holders_at_blob()`, `classify_row()` (tiers exact/blob/slug over states fresh/stale; called in a `$( )` subshell per row from `cmd_classify_missing`), `cmd_classify_missing()`, `cmd_check()`. Two error messages point authors at "#8605 tracks self-service".
- `apps/web-platform/scripts/dev-ledger-parity.test.sh` — fake `psql` (argv log, `DLP_PSQL_EXPECT_SQL` refusal of any other `-c`), fake `doppler`, fake `curl`; `run_classify`, `run_probe`, `with_stub_classifier`, `wf_static`/`wf_mutant`/`extract_step`; floor `EXPECTED_CASES=100` on the line above its `if`. Two existing cases match the exact summary string `ledger-classify: in-flight=… stale=… merged=… orphan=…` (around lines 872 and 1254), and every existing in-flight case runs the real classifier.
- `.github/actions/dev-migration-drift-probe/action.yml` — the `classify-missing` call under `FAIL_ON_DRIFT` (greps only lines starting `ledger-classify:` for the summary), the verdict `case` (`in-flight|stale|merged|orphan|*`), blocking aggregation `ledger_classes` (Sentry per class on the scheduled surface), stale-line text naming #8605.
- `.github/workflows/tenant-integration.yml` — two probe calls (pre-apply and post-section re-probe) with `fail-on-ledger-drift` scoped to authoritative events; heavy job inherits workflow `permissions: contents: read`.
- `.github/workflows/scheduled-dev-migration-drift.yml` — `permissions: contents: read`, one probe call.
- `scripts/dev-suite-mutex.sh` — banner tokens `DEV_SUITE_MUTEX_ACQUIRED wait_ms=<N>`, `…_CONTENDED_PROCEEDING`, `…_UNAVAILABLE`; env `DEV_SUITE_MUTEX_WAIT_S` (default 180), `DEV_SUITE_MUTEX_STATE_DIR`; the holder's stdout is redirected, so capturing `acquire` output does not hang.
- `tests/scripts/test-dev-suite-mutex-wiring.sh` — pins tenant-integration's mutex window (W1–W8) and the scheduled cron's `fail-on-ledger-drift`; it reads the probe steps' `with:` blocks, so adding a `github-token:` line must not break its anchored greps.
- `knowledge-base/engineering/architecture/decisions/ADR-061-per-ref-behavioural-schema-gate-over-shared-dev.md` — append a second amendment; do not edit the earlier text.
- `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md` — §Content drift last paragraph ("Self-service reconcile … tracked in #8605") becomes a pointer to the new workflow.

**Institutional learnings applied.**

- `2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md` — down files live on the originating branch (fetch by introducing commit when the branch is gone); apply downs in strict reverse order; one transaction per repair unit; ledger writes as compare-and-set asserting one row; hold the dev-suite mutex; a down file with its own top-level `BEGIN`/`COMMIT` breaks `--single-transaction`.
- `2026-09-23-a-blocking-gate-over-shared-dev-must-say-who-owns-each-row.md` — ownership is per row; ownerless rows are main's; the ratchets that bit #8521 (vacuity floor, fixture-relative assert, capture-exit, diagnosis claims).
- `2026-06-15-per-ref-schema-gate-over-shared-dev-and-worm-cascade-contradiction.md` — why residue on shared dev matters (#5372: an orphan table broke the account-delete cascade). Why a ledger-only discard (no `.down.sql`) must disclose the residue, and why a `CASCADE` down must not reach another branch's objects.
- `2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md` — deleting a ledger row without undoing its schema is the schema-vs-ledger drift class; the runner's precondition probe catches only FK references.
- `2026-03-16-github-actions-workflow-dispatch-permissions.md` — dispatch permissions and `GH_TOKEN: ${{ github.token }}`.

**CI authoring constraints** (`plugins/soleur/skills/ship/references/ci-workflow-authoring.md`): no column-0 heredocs in `run:`; config-specific Doppler token names (`DOPPLER_TOKEN_DEV_SCHEDULED`); no `continue-on-error` belts; `set -uo pipefail` with numeric validation before arithmetic. `scripts/lint-workflow-issue-write-scope.py`: a step using `github.token` to comment or file an issue needs `issues: write` in the same workflow. `scripts/lint-diagnosis-claims.sh` (ADR-166, blocking, highwater 1): no `::error::`/`::warning::` may name a cause the step did not measure. `scripts/battery-tag-authorship.test.sh`: every fixture `git fetch`/`clone` carries `--no-tags`. `scripts/lint-shell-capture-exit.py` baseline: no `x=$(cmd)` whose failure is lost.

**External checks run (read-only).** `gh api -X GET repos/jikig-ai/soleur/pulls -f state=all -f head='jikig-ai:<branch>'` returns `number, state, merged_at, closed_at, head.sha, head.repo.full_name` per PR for that branch (verified: `8602 closed true 2026-09-23T16:52:59Z jikig-ai/soleur`), and `[]` for a branch with no PR. `gh api -H 'Accept: application/vnd.github.raw+json' repos/jikig-ai/soleur/git/blobs/<id>` returns raw bytes whose `git hash-object` equals `<id>` (verified). `jq '@base64d'` on GitHub's newline-wrapped base64 errors (verified, jq 1.8). `doppler run -p soleur -c dev -- env` exposes `DOPPLER_ENVIRONMENT=dev` to the child (verified locally). The repo is PUBLIC, so `pull-requests: read` exposes nothing a PR author cannot already read. Down-file census on main: 95 `.down.sql`; 10 carry a top-level `BEGIN`/`COMMIT`; 9 carry an uppercase `CASCADE` word; 1 carries `CONCURRENTLY` (`132_drop_unused_indexes.down.sql`).

**Security review of the new trigger.** `pull_request_target` runs the BASE branch's workflow with secrets. The job checks out `main` (the default ref for that event), never the PR head, and executes only main's script. It reads the PR's git objects as data and sends the PR's own `.down.sql` to the dev database. That SQL is authored by the same same-repo writer whose forward SQL `tenant-integration.yml` already ran against dev with the same credential, so it adds no privilege. Fork PRs are excluded in the job `if:` (their heads are not on origin, and fork PR runs never receive the dev secret, so they never applied anything). A PR closed by a `GITHUB_TOKEN`-authenticated workflow fires no `pull_request_target` event; those rows fall to the 24 h grace, then block with the dispatch command.

**No new store, no new connection class.** The writer reuses `DATABASE_URL_POOLER` from Doppler `dev_scheduled` (the same CI→dev-pooler connection `tenant-integration.yml` uses) and the GitHub REST API over HTTPS. No `.tf`, migration, cloud-init or compose file changes, so the Encryption Posture and IaC gates do not fire. No regulated-data surface: dev holds synthetic data only.

## Implementation Phases

### Phase 1 — #8606: anchor run-migrations pathspecs (test first)

1. RED: in `apps/web-platform/test/scripts/run-migrations-unmerged-gate.test.ts`, give `runScript()` a `cwd` parameter and run the existing three cases under `describe.each([["repo root", REPO_ROOT], ["apps/web-platform", APP_DIR]])`. Add a **collision case** for each cwd: a second minimal staging dir `{053_template_authorizations.sql, 053_zz_gate_<hex>.sql}`, run with `ALLOW_UNMERGED_DEV_APPLY=1`; assert stdout carries `coexists-with: 053_append_kb_sync_row_rpc.sql` (a main file NOT staged, so it can only come from the `origin/main` listing). Run the suite before the fix and record that the `apps/web-platform` positive control and collision case fail (the RED evidence goes in the PR body).
2. GREEN: in `run-migrations.sh`, change the gate to `git ls-tree origin/main -- ":(top,literal)apps/web-platform/supabase/migrations/$filename"` and the collision listing to `":(top,literal)apps/web-platform/supabase/migrations/"`. Rewrite the header comment above `MIGRATIONS_DIR=` to say the gate is anchored on the repo top via `:(top,literal)` and name #8606. Leave `git fetch` and `git hash-object "$migration_file"` alone: the first is cwd-independent within a worktree, the second takes an absolute path.
3. Update the `dev-ledger-parity.sh` header sentence that cites #8606 as a live defect to past tense.

### Phase 2 — #8605 (a): PR-state-aware classifier (test first)

1. In `dev-ledger-parity.sh`:
   - `owner_candidates <tier> <value> <state>` returns EVERY matching branch, sorted, one per line (`owner_lookup` becomes its first line, so `check` is untouched).
   - `branch_pr_state <branch> <tip-sha>` — the only GitHub caller on the classify path. It runs `gh api -X GET "repos/$GH_REPO/pulls" -f state=all -f head="$GH_OWNER:$branch" -f per_page=100 -i` (no `--paginate`: one page of 100 PRs per head branch is ample, and `--paginate` concatenates arrays), bounded by the script's `TIMEOUT_BIN`, and reduces the body with `jq -e` to one token: `open`, `none`, or `closed <number> <closed_at_epoch>`. Reduction rules: any PR with `state == "open"` → `open`; otherwise take the PR with the greatest `closed_at` (never array order); `closed` only when that PR's `head.sha` equals `<tip-sha>`, the owner branch's current tip in the owner repo, else `none`. **The evidence is bound to the commit, not the name** (the #8490/PR #8493 class: a name-keyed lookup attaches an old closed PR to a reused or re-pushed branch). The epoch comes from jq's `fromdateiso8601`, never `date -d`.
   - **Failure classes (fail-closed, operator direction).** HTTP 401/403/404 → `cannot_measure config`, naming the status code (a job that lost `pull-requests: read` returns 403 and a re-run will not help). HTTP 429/5xx or a network error → one retry after 5 s, then `cannot_measure transient`. Non-JSON body (`jq -e` fails) or a PR entry without a parseable `closed_at` → `cannot_measure transient`. `GITHUB_REPOSITORY` unset or not matching `^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$` → `cannot_measure config`. No response body text ever reaches an annotation; only the class and status code do.
   - **Memo in a file, not an array.** `classify_row` runs in a `$( )` subshell per row, so an in-memory memo would be lost after every row. `branch_pr_state` memoises in a per-invocation TSV under `CLEAN` (`branch<TAB>tip<TAB>token`). It runs only when a fresh candidate exists, so a probe with no in-flight candidates makes zero API calls.
   - `classify_row`: for the `fresh` state, walk tiers exact → blob → slug; for each candidate, `open` or `none` → emit `in-flight` (as today, same fields). `closed` → remember the first such hit and keep looking. If no live holder is found in any fresh tier and a closed hit was remembered → emit `closed-grace` (hours since close < `CLOSED_GRACE_H=24`) or `closed`, as `<verdict><TAB><file><TAB><branch><TAB><pr-number><TAB><hours-since-close>`. A remembered closed hit beats a stale holder (closed is decided before the stale tiers run). Otherwise fall through to the `stale` tiers exactly as today. `CLOSED_GRACE_H` sits next to `STALE_DAYS`, so both time policies live in one layer.
   - Summary line gains two fields **at the end**: `ledger-classify: in-flight=N stale=M merged=J orphan=K closed-grace=G closed=C`.
   - `usage()` documents both verdicts, the grace, and the `GITHUB_REPOSITORY`/`GH_TOKEN` requirement.
   - **Library mode.** Top-level associative arrays become `declare -gA` (a `declare -A` executed inside a sourcing function would be function-local, leaving `OWN_ON_BASE`/`OWN_EVER` empty for the writer). The dispatch `case` at the bottom runs unless `DLP_AS_LIBRARY=1`; when `DLP_AS_LIBRARY=1` is set but the file is executed rather than sourced (`${BASH_SOURCE[0]} == $0`), it exits 2 with `::error::dev-ledger-parity: DLP_AS_LIBRARY is set on a direct run` instead of silently doing nothing. A header comment block, `# Library API (used by dev-ledger-reconcile.sh)`, lists the functions and globals the writer may use. The inline `merge-base --is-ancestor` inherited-holder test in `cmd_check` is extracted to `independent_holder <file> <blob> <exclude-branch> <pr-ref>` so the guard and the writer share one copy.
   - Messages: the no-`content_sha` message in `cmd_check` (`…ask a dev operator to reconcile the row… (#8605)`) now names the workflow. The A1 edited-after-apply message keeps "restore the applied body, then a NEW migration" as the primary fix (ADR-061 Policy 2) and replaces "(#8605 tracks self-service)" with the alternative: "if your branch carries a `.down.sql` for the applied body, you can discard it instead: `gh workflow run dev-ledger-reconcile.yml --ref main -f pr=<your PR>` (dry run first)".
2. Tests (existing suite): add a fake `gh` to the suite's `BIN` (see Guard 2 harness); export `GITHUB_REPOSITORY=fixture-owner/fixture-repo`, `GH_CONFIG_DIR=$tmp/gh`, `GH_TOKEN=invalid`, `GH_HOST=fixture.invalid` suite-wide so no case can reach a real `gh`; update the two exact-summary-string cases (lines ~872 and ~1254) to the new line. Every existing in-flight case keeps passing because the default fake answers `[]` (`none`).
3. In `action.yml`: new optional input `github-token` (default `''`), exported as `GH_TOKEN` ONLY on the classifier call. Two new `case` arms reading a fifth field (`IFS=$'\t' read -r v vf vb vx vh`), validating `vb` against `branch_re` and `vx`/`vh` against `^[0-9]+$`: `closed-grace)` → a warning list; `closed)` → `closed_lines`, which is blocking: `::error::` block, included in the fail condition next to `orphans`/`stale_lines`/`unclassified`/`content_drift`, and in `ledger_classes` as `closed` (one Sentry event on the scheduled surface). Line text states only what was measured and leads with the safe command: `- <file> (owner branch <b> has no open pull request; #<N> closed <h> h ago — check its action-required issue, or preview the discard: gh workflow run dev-ledger-reconcile.yml --ref main -f pr=<N>; if the dry run lists rows, re-run with -f execute=true)`. The stale-line text names the reconcile workflow instead of "#8605". The orphan block gains a lookup hint: `(if a pull request applied it and its branch was deleted: gh pr list --state closed --search <file>, then preview the discard with -f pr=<N>)`.
4. Callers: `tenant-integration.yml` heavy job gets job-level `permissions: { contents: read, pull-requests: read }` and both probe calls pass `github-token: ${{ github.token }}`. `scheduled-dev-migration-drift.yml` gets `pull-requests: read` and passes the token. PR-mode runs never reach the classifier (verified: `fail-on-ledger-drift` is scoped to push and main dispatch), so the token is unused there. Run `tests/scripts/test-dev-suite-mutex-wiring.sh` after the edit.

### Phase 3 — #8605 (b): the writer, `dev-ledger-reconcile.sh` (test first)

**A separate file from the guard** (advisor consult, adopted): `apps/web-platform/scripts/dev-ledger-reconcile.sh` is the only file in this area that writes to a database. At top level (never inside a function) it sets `DLP_AS_LIBRARY=1` and sources `"$(dirname "${BASH_SOURCE[0]}")/dev-ledger-parity.sh"` — the guard from its OWN directory, never from `--repo`, so the writer and guard always come from the same tree (both workflow events check out `main`; no base-ref extraction discipline is needed). A test override, `DLR_GUARD`, points it at a mutated copy. The guard stays one self-contained, read-only file, which keeps `tenant-integration.yml`'s base-ref single-file extraction of it valid. The writer installs its own EXIT trap that removes its temp files (all created with `mktemp` under `${RUNNER_TEMP:-${TMPDIR:-/tmp}}`), calls the guard's `cleanup`, then the mutex `release` (pinned by G3-M14).

`dev-ledger-reconcile.sh --pr <N> --repo <dir> --base-branch <name> [--execute] [--allow-later-rows] [--require-closed] [--actor <login>]`

`--help` is handled first, before every refusal. Order of operations (each step exits before the next on failure):

1. **Parse and refuse early.** `--pr` must match `^[1-9][0-9]{0,6}$`; `--actor`, when given, must match `^[A-Za-z0-9-]{1,39}$`. `DOPPLER_ENVIRONMENT` must equal `dev` (both modes; `cannot_measure config` otherwise, with zero `psql` calls). `GITHUB_REPOSITORY` validated as in Phase 2.
2. **PR facts (API, read-only).** `gh api repos/$GH_REPO/pulls/$N` (shape-checked with `jq -e`; same failure classes as Phase 2). `head.repo` null or `head.repo.full_name != GH_REPO` → exit 1 "fork PRs never applied to dev". Capture `head.sha`, `state`, `user.login`.
3. **Git facts (owner repo, no DB).** `owners_repo "$base_branch"`, then a second bounded blobless fetch of `+refs/pull/$N/head:refs/prhead/$N` into the same owner repo (`--no-tags`, `--filter=blob:none`). Its tip must equal the API `head.sha`; a mismatch (a push landed between the two reads) → `cannot_measure transient`. `refs/pull/N/head` survives branch deletion.
4. **PR history pairs.** Walk `ogit rev-list --reverse --first-parent "$BASE_OWN..refs/prhead/$N"`; for each commit read its tree once (`ogit ls-tree <commit> -- ":(top,literal)$MIG_REL/"`), tracking each top-level forward file F's current blob. For each (F, B) that F ever carried, record the LAST commit at which F still had blob B (a later commit that edits only `F.down.sql` moves the pairing forward, which a `--raw` walk cannot see). The down blob for (F, B) is `F.down.sql`'s blob in that commit's tree, or none. **No pair → print `ledger-discard: nothing to do (pr=N)` and exit 0**, before any mutex or database contact.
5. **Open-PR authority (execute mode).** If `state == open`: `--actor` must equal `user.login` (the PR's author), else exit 1 "an open PR's rows can be discarded only by its author; close the PR to let the close-time run discard them". Closed PRs have no author restriction (the close-time run and any maintainer may clean up).
6. **Mutex (execute mode only).** `DEV_SUITE_MUTEX_STATE_DIR="$(mktemp -d)"` (the writer's own, so `acquire` and `release` cannot disagree on `$PPID`), `DEV_SUITE_MUTEX_WAIT_S=600` (a tenant-integration critical section runs 5-9 min; the job has 15), `DEV_SUITE_MUTEX_IDENTITY=reconcile-${GITHUB_RUN_ID:-local}-pr$N`; then `bash "$REPO/scripts/dev-suite-mutex.sh" acquire`. Proceed only if its stdout has a line starting `DEV_SUITE_MUTEX_ACQUIRED`; otherwise run `release` and `cannot_measure transient "could not hold the dev-suite mutex (<banner token>); nothing was changed"`. `release` is in the EXIT trap from this point on.
7. **Re-check PR state inside the mutex (`--require-closed`).** The close-time path passes `--require-closed`: re-read `state` (a second `pulls/N` call, after `acquire`); if the PR has been reopened, print `ledger-discard: skipped (pr=N reopened)` and exit 0 with no write.
8. **Ledger read (inside the mutex).** A writer-local SELECT: `filename || '|' || COALESCE(content_sha, '') || '|' || COALESCE(to_char(applied_at AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISSUS'), '')` (microseconds; one runner pass applies several files within a second), parsed with the same one-delimiter-per-field discipline and a `^[0-9]{20}$` check on the timestamp.
9. **Eligibility.** A ledger row (F, B) is eligible iff: `name_ok F` (the whitelist runs on the LEDGER string itself), F ends in `.sql` and not `.down.sql`; F is not on the base tip and never appeared in base history (`OWN_ON_BASE`, `OWN_EVER`); B is 40-hex; (F, B) is in the PR history pairs; and `independent_holder` finds no other fresh live branch holding F at B that did not inherit it from this PR's history. Ineligible rows are not this PR's and are not errors. **Stacked branches:** an open branch stacked on this PR that inherited F does not protect F; its next CI run re-applies F (stated in the audit comment when the owner repo shows such a descendant).
10. **Down bodies.** For each eligible row with a down blob: `gh api -H 'Accept: application/vnd.github.raw+json' repos/$GH_REPO/git/blobs/<id> > <tmp>`; `git hash-object <tmp>` must equal the id (else `cannot_measure transient`).
11. **Refusals (all-or-nothing: any refusal → exit 1, zero writes).** First, reject any down body containing a backslash byte (psql would execute a meta-command such as `\!` from a `-f` file; 0 of 95 down files on main contain one). Then normalize a single wrapping transaction: strip the first statement if it is exactly `BEGIN`/`BEGIN TRANSACTION`/`BEGIN WORK`/`START TRANSACTION` and the last if it is exactly `COMMIT`/`COMMIT TRANSACTION`/`COMMIT WORK`/`END` (case-insensitive, whole-line, trailing comment allowed). Then produce a **stripped view** of each body with a small `python3` tokenizer (comments `--`/`/* */`, single-quoted strings, quoted identifiers and `$tag$…$tag$` bodies removed; `python3` is on every GitHub runner and operator host already used by repo scripts) and match statement starts `(^|;)\s*<keyword>\b` on it:
    - transaction control still present: `BEGIN`, `COMMIT`, `END`, `ROLLBACK`, `ABORT`, `START TRANSACTION`, `SAVEPOINT`, `RELEASE`, `PREPARE TRANSACTION`, `COMMIT PREPARED`, `ROLLBACK PREPARED`, `CALL` → "needs manual handling per the learning";
    - cannot run in a transaction: `\bCONCURRENTLY\b`, `VACUUM`, `ALTER SYSTEM`, `CREATE DATABASE`, `DROP DATABASE`, `REINDEX … CONCURRENTLY` (`132_drop_unused_indexes.down.sql` on main is one);
    - **later-row sensitive**, refused while the ledger holds ANY row (main's or another branch's) whose `applied_at` is `>=` the earliest `applied_at` among this PR's eligible rows and which is not one of this PR's eligible rows: `CASCADE`, `CREATE OR REPLACE`, `CREATE POLICY`/`ALTER POLICY`/`DROP POLICY`, `GRANT`, `REVOKE`, `ALTER FUNCTION`/`ALTER PROCEDURE`. Running such a body after later rows could drop another branch's dependent objects or silently revert main's later redefinition of a shared function or grant — drift no probe sees, because the probe compares filenames and blobs. `--allow-later-rows` (dispatch input `allow_later_rows`, never passed by the close-time path) overrides after a dry run, which lists the later rows. Residual, stated in the ADR: a later row is detected by `applied_at`, so an object created by an out-of-order apply before F that depends on F is not seen.
    - **Open-PR ledger-only:** on an OPEN PR, an eligible row with no down blob refuses the run (discard-then-re-apply without a down would reproduce the residue ADR-061 rejected).
    A test runs the stripped-view refusal step over all 95 down files on main and pins the expected refusal sets (transaction-control, non-transactional, later-row-sensitive).
12. **Ledger-only rows on a closed PR.** Per the operator's direction ("apply the applied blob's `.down.sql` if present, delete the row"), a closed PR's eligible row with no down blob is discarded ledger-only: `::warning::ledger-discard: <F> has no .down.sql paired with applied blob <B>; objects its body created stay on dev`, and the workflow files an issue for the residue.
13. **Dry run (default).** Print one `would-discard <F> <B> down=<id|none>` line per row in execution order, one `later-row <file> <applied_at>` line per later row, and `ledger-discard: dry-run (pr=N eligible=E down=K ledger-only=L later-rows=R)`; exit 0. No mutex, no write.
14. **Execute — one unit for the whole PR.** Order rows by `applied_at` DESC, then filename DESC. Build ONE `unit.sql`: `SET LOCAL lock_timeout = '30s'; SET LOCAL statement_timeout = '120s';` then, per row in that order, (a) a `DO $$ … $$` block that runs `DELETE FROM public._schema_migrations WHERE filename = '<F>' AND content_sha = '<B>'`, reads `GET DIAGNOSTICS n = ROW_COUNT`, and `RAISE EXCEPTION` unless `n = 1`; then (b) the normalized down body, if any. Run `env -u GH_TOKEN psql "$db" -w --no-psqlrc --single-transaction -v ON_ERROR_STOP=1 -f <unit.sql>` (same URL and mode as `run-migrations.sh`, which applies multi-statement files the same way on every CI run). All-or-nothing: any failure rolls back everything; exit 1 naming the failing statement's file where psql reports it, or exit 2 for a lock/statement timeout (SQLSTATE 55P03/57014), with nothing written either way. On success print `::notice::ledger-discard: discarded <F> (applied blob <B>, down <id|none>) for PR #<N>` per row. No `NOTIFY pgrst` (it cannot reach PostgREST over the pooler, #4285); the summary notes the ~10-min schema-cache poll.
15. **Summary.** `ledger-discard: executed (pr=N eligible=E discarded=D down=K ledger-only=L)`; exit 0.

**Output hygiene.** psql output (which can carry `RAISE` text from PR-authored SQL) is written to the log inside a `::stop-commands::<random token>` block, indented, and never copied into the step summary, the comment or the issue. Those are built only from the writer's own lines (`ledger-discard:`, `would-discard`, `later-row`, `discarded`, and the writer's own `::error::` text), each re-validated against the filename, sha, timestamp and integer patterns, with `\x00-\x1f`, `\x7f`, U+2028 and U+2029 stripped.

Exit codes mirror the guard's contract: 0 done/dry-run/nothing-to-do/skipped, 1 refused or the unit failed (named), 2 cannot measure (nothing written).

**Races, stated.** A reopened PR's next CI run re-applies its forward files — the ordinary pending path; the in-mutex state re-check stops a close-time run that lost the race to a reopen. A PR CI run holding the mutex fail-OPEN (`CONTENDED_PROCEEDING`) can still interleave: `run-migrations.sh`'s check-then-insert against the filename primary key means a racing re-apply ends skipped or failing on the key, and the CAS keeps the ledger consistent; `lock_timeout` bounds the wait on its locks. The post-section drift re-probe covers unserialized runs (#7964).

### Phase 4 — `.github/workflows/dev-ledger-reconcile.yml`

- **Header:** a `SECURITY ENVELOPE` comment in the `cla-evidence.yml` form: `pull_request_target` runs with base-branch secrets; never check out or execute PR-head code; the PR's `.down.sql` is data that reaches only the dev database, after the writer's backslash and statement refusals; every PR-derived value is passed via `env:`.
- **Triggers:** `workflow_dispatch` with inputs `pr` (string, required, `description: "PR number whose applied-but-unmerged migrations to discard on dev, e.g. 8605"`), `execute` (boolean, default `false`, description "false = dry run"), `allow_later_rows` (boolean, default `false`, description "allow a .down.sql with CASCADE or a redefinition while other rows were applied after it — dry run first"); `pull_request_target: { types: [closed], branches: [main] }`.
- **Top-level `permissions: contents: read`.** Job permissions: `contents: read`, `pull-requests: read`, `issues: write` (audit comment and issue; `lint-workflow-issue-write-scope.py`).
- **No concurrency group** (the mutex serializes writers; a repeated run is a CAS no-op).
- **Job `if:`:** `(github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main') || (github.event_name == 'pull_request_target' && github.event.pull_request.merged == false && github.event.pull_request.head.repo.full_name == github.repository)`. `timeout-minutes: 15`.
- **Steps:**
  1. `actions/checkout` (pinned SHA `34e114876b0b11c390a56381ad16ebd13914f8d5`, v4.3.1, as in `cla-evidence.yml`) with NO `ref:` key (the event default is main's tip for both triggers), `fetch-depth: 1`, `persist-credentials: false`.
  2. Install the Doppler CLI (`DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c`, v4, 40-char pin as in `tenant-integration.yml`).
  3. *Assert the Doppler config is dev* — copied from `tenant-integration.yml`: `DOPPLER_TOKEN_DEV_SCHEDULED` is set; `doppler configs get dev_scheduled -p soleur --json` resolves `environment=dev`; `SUPABASE_ACCESS_TOKEN` is absent from `dev_scheduled` (#8028 DC-1). The writer repeats the environment check in-process (`DOPPLER_ENVIRONMENT=dev`) for laptop runs.
  4. *Reconcile* (`id: reconcile`): env `DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_DEV_SCHEDULED }}`, `GH_TOKEN: ${{ github.token }}`, `PR` (event number or `inputs.pr`), `EXECUTE` (`inputs.execute`, or `true` on `pull_request_target`), `ALLOW_LATER_ROWS` (`inputs.allow_later_rows`, or `false` on `pull_request_target`), `ACTOR: ${{ github.actor }}`, `EVENT_NAME` — all via `env:`, never interpolated into `run:`. Build argv in bash (`--execute` when `EXECUTE == true`; `--allow-later-rows` when `ALLOW_LATER_ROWS == true`; `--require-closed` when `EVENT_NAME == pull_request_target`; `--actor "$ACTOR"` on dispatch), run `doppler run -p soleur -c dev_scheduled -- bash apps/web-platform/scripts/dev-ledger-reconcile.sh --pr "$PR" --repo "$GITHUB_WORKSPACE" --base-branch main …`, capture rc and stdout to a file, append only the writer's validated lines to `$GITHUB_STEP_SUMMARY`, expose `rc`, `eligible` and `ledger_only` as step outputs (parsed from the `ledger-discard:` line with numeric validation), and fail the step on rc ≠ 0.
  5. *Audit comment* (`if: always() && steps.reconcile.outcome != 'skipped' && (steps.reconcile.outputs.rc != '0' || steps.reconcile.outputs.eligible != '0')`): `gh api "repos/$GITHUB_REPOSITORY/issues/$PR/comments" -F body=@<file>` (REST, not `gh pr comment`'s GraphQL path), the file built with `{ printf …; } > file` (no heredoc) from validated writer lines only: actor, event, run URL, mode, rc, the `would-discard`/`later-row`/`discarded`/`ledger-discard:` lines, the ledger-only residue list, and the schema-cache note. A failed post prints `::warning::` naming the rc.
  6. *Action-required issue* (`if: always() && github.event_name == 'pull_request_target' && (job.status == 'failure' || steps.reconcile.outcome != 'success' || steps.reconcile.outputs.ledger_only != '0')`) — fires on ANY failure of the unattended path, including a failed checkout or Doppler step before the reconcile step runs. `gh issue create` labelled `action-required`, `domain/engineering`, `priority/p2-medium` (all three verified to exist), titled `dev ledger: close-time reconcile for PR #<N> needs attention`, body built with `{ printf …; } > file`: the run URL, the failing step's name, the writer's validated `ledger-discard:` or `::error::` line when there is one (no inferred cause), the residue list if any, and the dry-run-first commands (`gh workflow run dev-ledger-reconcile.yml --ref main -f pr=<N>`, then `-f execute=true`, plus `-f allow_later_rows=true` only when the refusal line names a later-row refusal). Before creating, search open issues for the exact title and comment on the existing one instead. A failed create or comment prints `::error::` and fails the job (the run itself then stays red in the Actions tab; the 24 h `closed` verdict with its scheduled-probe Sentry event is the backstop).
- **Never:** `doppler … -c prd`, any `DOPPLER_TOKEN_PRD*` secret, a `ref:` key on checkout, or `${{ github.event.* }}`/`${{ inputs.* }}` inside a `run:` body.

### Phase 5 — ADR-061 amendment, learning pointer, #8521 archive

1. Append `## Amendment 2026-09-23 (#8605, #8606): closed-PR ownership and a dev reconcile path` to ADR-061 (Status: Accepted). Required content:
   - **Context:** closed-unmerged branches kept rows in-flight forever; the only discard route was a hand-run SQL session.
   - **Restated ownership rule.** The earlier amendment's "if and only if" in-flight rule is restated with the added condition: a fresh live holder counts only if it has an open PR, has no PR, or its latest closed PR's head is not the branch tip; a holder whose latest PR closed at the tip yields `closed-grace` (warning) for `CLOSED_GRACE_H=24` hours, then `closed` (blocking).
   - **Superseded sentences, named:** "No GitHub API, no new permissions" (replaced by a `pull-requests: read` lookup on fresh owners only, fail-closed: 401/403/404 → config, 429/5xx → one retry then transient) and "Self-service reconcile is tracked in #8605".
   - **DC-1:** `dev-ledger-reconcile.yml` writes to the shared DEV ledger and schema, never prd; under the mutex; one CAS-guarded transaction per PR; triggered on same-repo close-unmerged and by dispatch from main. Authorization boundary = repo write access (the same boundary that already lets a PR's CI apply its SQL to dev); an OPEN PR's rows can be discarded only by its author and only with a paired `.down.sql`. The PR author's `.down.sql` runs with the dev credential under `pull_request_target`, which a `pull_request` job never could: it is refused on any backslash byte (psql meta-commands) and on non-transactional or transaction-control statements, and runs with `GH_TOKEN` unset. This is why it is not a `contributor` path in C4: fork PRs are excluded, and same-repo authors already hold the same dev credential through PR CI.
   - **Policy 2 relaxation, bounded:** an applied-but-unmerged version may be discarded (down + CAS delete) instead of restored, only when the PR carries its paired `.down.sql`; the primary A1 fix stays "restore and ship a new migration".
   - **Later-row safety:** a down body with `CASCADE` or a shared-object redefinition is refused while later rows exist, unless the dispatcher passes `allow_later_rows`; residual: an out-of-order earlier object is not seen.
   - **Rejected alternatives (additions):** `pull_request: closed` (runs the PR-merge ref's workflow copy); dispatch with `--ref <branch>` (runs the branch's YAML; branches predating the workflow cannot dispatch); refusing every closed PR's row that has no `.down.sql` (contradicts the operator's direction; the residue is filed instead); a warning-only `closed` verdict with dispatch-only reconcile (leaves closed PRs' rows unowned indefinitely); degrading a transient PR-state failure to an in-flight warning (contradicts the fail-closed direction); an audit table on dev (a migration that also lands on prd).
   - **Consequences:** closing a migration PR unmerged, with its branch retained, discards its dev rows within minutes; a refused discard files an issue and turns blocking after 24 h; PRs closed by a `GITHUB_TOKEN` workflow fire no event and rely on the grace; a PR closed with "delete branch" reads `orphan` (blocking, no grace) until the close-time run lands — unchanged from the earlier amendment, now bounded by minutes, and the orphan line carries a lookup hint; detection ceiling for a silent non-run of the close path is about 30 h (24 h grace plus the 6 h probe cadence); a GitHub API outage on the authoritative probe can red main while fresh owners exist.
2. Learning `2026-05-21-…` §Content drift, final paragraph: replace "Self-service reconcile for PR authors without dev credentials is tracked in #8605." with the dispatch command, what it does and does not do (it discards unmerged rows; it does not repair class A/B/C content drift of MERGED rows).
3. #8521 artifacts: tick AC11 in `2026-09-23-fix-pr-ci-unmerged-migration-ledger-parity-plan.md` with "run 35891815286 (push, main, `d42057b67d`): `No dev-vs-main migration drift detected.`; `ledger-parity: 0 unmerged migrations` — no in-flight lines to cross-check". Commit that edit, then run `bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh pr-ci-unmerged-migration-ledger-parity` and `… archive-kb.sh one-shot-8521-dev-ledger-content-drift` (two runs: the plan and spec carry different slugs; dry-runs confirmed one artifact each). Repoint `apps/web-platform/scripts/dev-ledger-parity.test.sh`'s header `plan:` pointer to the archived path.

## Files to Edit

- `apps/web-platform/scripts/run-migrations.sh`
- `apps/web-platform/test/scripts/run-migrations-unmerged-gate.test.ts`
- `apps/web-platform/scripts/dev-ledger-parity.sh` (closed verdict, `branch_pr_state` with file memo, `owner_candidates`, `DLP_AS_LIBRARY` library mode, summary field, two error messages repointed at the workflow, header #8606 sentence)
- `apps/web-platform/scripts/dev-ledger-parity.test.sh` (fake `gh`; `GITHUB_REPOSITORY` in `run_classify`/`run_probe`; the two exact-summary cases; new classifier, probe, writer and workflow cases; `EXPECTED_CASES` raised to the new exact count; header plan pointer)
- `.github/actions/dev-migration-drift-probe/action.yml`
- `.github/workflows/tenant-integration.yml`
- `.github/workflows/scheduled-dev-migration-drift.yml`
- `tests/scripts/test-dev-suite-mutex-wiring.sh` (only if an anchored grep over the probe steps' `with:` blocks breaks; run it first)
- `scripts/guard-vacuity-floor.test.sh` (the promoted entry's comment names `EXPECTED_CASES=100` — update the number in that comment)
- `knowledge-base/engineering/architecture/decisions/ADR-061-per-ref-behavioural-schema-gate-over-shared-dev.md` (append only)
- `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`
- `knowledge-base/project/plans/2026-09-23-fix-pr-ci-unmerged-migration-ledger-parity-plan.md` (tick AC11, then `git mv` by archive-kb)
- `knowledge-base/project/specs/feat-one-shot-8521-dev-ledger-content-drift/` (`git mv` by archive-kb)

## Files to Create

- `apps/web-platform/scripts/dev-ledger-reconcile.sh` (the writer; sources `dev-ledger-parity.sh` with `DLP_AS_LIBRARY=1`)
- `.github/workflows/dev-ledger-reconcile.yml`

## Open Code-Review Overlap

1 open scope-out touches these files: #3364 (postgres-role ownership guard for `run-migrations.sh`). **Acknowledge:** a different concern (which role owns created objects on prd); this PR changes only two pathspecs in that script and must keep the prd path's diff minimal.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — every change is CI and dev-database tooling. The indirect path: a broken `run-migrations.sh` gate on the prd release would refuse to apply migrations and hold a release (fail-closed: an empty `ls-tree` result blocks, it never lets an unmerged file through), and a broken classifier or reconcile would red `main`'s required tenant-integration check and hold merges (the 2026-09-21 class, 5.5 h).

**If this leaks, the user's data is exposed via:** no user data is in scope. The new writer holds only the dev-scoped Doppler token (`dev_scheduled`, asserted `DOPPLER_ENVIRONMENT=dev` in-process before any `psql`); dev holds synthetic data (`hr-dev-prd-distinct-supabase-projects`). The GitHub token is `pull-requests: read` / `issues: write` on a public repo.

**Brand-survival threshold:** none

- `threshold: none, reason: CI/dev-only tooling; the one prd-path edit (two ls-tree pathspecs in run-migrations.sh) is fail-closed by construction and byte-equivalent from the repo root, and no path writes to prd.`

## Observability

Layers cited per `hr-observability-layer-citation`: (6) GitHub Actions workflow run log `::error::`/`::warning::` and job summary; (1) Sentry, via the scheduled drift probe's per-class event (`.github/actions/dev-migration-drift-probe/action.yml`, fired by the `cron-dev-migration-drift` schedule); the `action-required` GitHub issue, which operator-digest harvests.

```yaml
liveness_signal:
  what: "ledger-discard: <executed|dry-run|nothing to do|skipped> summary line + PR audit comment per reconcile run with rows; ledger-classify: … closed-grace=G closed=C on every authoritative probe"
  cadence: "per same-repo PR closed unmerged, per dispatch, per push to main, and per scheduled drift-probe run (6 h)"
  alert_target: "action-required GitHub issue on any failure or residue of the close-time path; Sentry event per blocking class (now including closed) from the scheduled probe; red required check on main after the 24 h grace"
  configured_in: ".github/workflows/dev-ledger-reconcile.yml, .github/actions/dev-migration-drift-probe/action.yml, apps/web-platform/scripts/dev-ledger-parity.sh (CLOSED_GRACE_H)"
error_reporting:
  destination: "layer 6 workflow run log ::error:: + job summary; action-required issue for the unattended close-time path; layer 1 Sentry (scheduled probe) for blocking ledger classes"
  fail_loud: true
failure_modes:
  - mode: "PR-state lookup fails transiently (5xx, 429, network, malformed JSON) after one retry"
    detection: "layer 6: classifier exits 2; probe prints ::error::ledger-classify: UNCLASSIFIED (rows=… rc=2)"
    alert_route: "red main run; layer 1 Sentry event on the scheduled surface"
  - mode: "PR-state lookup refused (401/403/404: token scope missing, wrong repo)"
    detection: "layer 6: ::error:: naming cannot measure (config) and the HTTP status; UNCLASSIFIED"
    alert_route: "red main run; layer 1 Sentry on the scheduled surface; the message says a re-run will not help"
  - mode: "close-time reconcile refused (backslash, transaction-control, non-transactional, later-row sensitive, fork, author)"
    detection: "layer 6: dev-ledger-reconcile.sh exits 1 with a named ::error::; the PR audit comment carries it"
    alert_route: "action-required issue with the dry-run-first commands; after 24 h the probe reports closed (blocking) with a layer 1 Sentry event"
  - mode: "close-time job fails before the reconcile step (checkout, Doppler install, Doppler dev assertion)"
    detection: "layer 6: the failing step's ::error::; job.status == failure"
    alert_route: "action-required issue naming the failing step"
  - mode: "dev-suite mutex not acquired within 600 s, or a lock/statement timeout inside the unit"
    detection: "layer 6: dev-ledger-reconcile.sh exits 2 before any write: could not hold the dev-suite mutex (<banner token>) / timed out; nothing was changed"
    alert_route: "action-required issue (close-time) or the dispatcher's red run"
  - mode: "the single unit fails (a down statement errors or a CAS matches zero rows)"
    detection: "layer 6: psql rolls back the whole unit; dev-ledger-reconcile.sh exits 1 naming the file"
    alert_route: "action-required issue / red dispatch run; the rows reappear in the next probe unchanged"
  - mode: "ledger-only discard leaves schema residue"
    detection: "layer 6: ::warning:: per row naming the file; ledger_only > 0 in the summary"
    alert_route: "action-required issue listing the residue files"
  - mode: "the close-time run never happens (PR closed by a GITHUB_TOKEN workflow, workflow disabled, job if: skipped)"
    detection: "layer 6: the probe reports closed-grace (warning) with the PR number and hours since close"
    alert_route: "blocking closed after 24 h; layer 1 Sentry on the scheduled surface; ceiling about 30 h"
  - mode: "branch deleted on close before the discard lands"
    detection: "layer 6: the probe reports orphan with the gh pr list lookup hint"
    alert_route: "red main run until the close-time run discards the rows; layer 1 Sentry on the scheduled surface"
  - mode: "the action-required issue cannot be created"
    detection: "layer 6: ::error:: and a failed job"
    alert_route: "the 24 h closed verdict and its layer 1 Sentry event are the backstop"
  - mode: "run-migrations gate regresses to cwd-relative"
    detection: "layer 6: run-migrations-unmerged-gate.test.ts apps/web-platform positive control and collision cases fail in CI"
    alert_route: "red PR check"
logs:
  where: "GitHub Actions run logs + job summaries; PR comments and issues (permanent)"
  retention: "90 days for run logs (repo default); PR comments and issues indefinitely"
discoverability_test:
  command: "bash apps/web-platform/scripts/dev-ledger-reconcile.sh --help"
  expected_output: "ledger-discard"
```

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-061** (append-only; new section dated 2026-09-23, issues #8605/#8606) — decision: closed-PR rows are not in-flight (commit-bound `closed-grace` warning for 24 h, then blocking `closed`), the classifier reads PR state with `pull-requests: read`, and DC-1: a base-branch reconcile workflow may write to the shared DEV ledger and schema (discard only, CAS, mutex-held, never prd). This is Phase 5 step 1, an in-scope task. No new ADR number is claimed, so there is no ordinal to collide.

### C4 views

No C4 impact. Checked against all three model files (`model.c4` 831 lines, `views.c4`, `spec.c4`):

- **Actors:** `founder` (operator, dispatches) and `contributor` (untrusted fork PR author). `contributor`'s description — PR-head code runs only under `pull_request` isolation, never in a privileged consumer — stays true: the new `pull_request_target` job excludes fork PRs and executes no PR-head code.
- **Systems:** `github` (CI) is modeled; the `supabase` database element is the product database, and the model carries no dev-project element and no `github -> supabase` edge even for the existing CI dev apply and prd migrate paths. This change adds a CI→dev write of the same class as `tenant-integration.yml`'s existing apply, so it introduces no element or relationship the model represents today. GitHub REST reads from CI are internal to `github`.
- **Privileged-consumer note:** `model.c4` records privileged CI consumers at trust boundaries (ADR-074 Stage B). The new `pull_request_target` job runs same-repo PR-authored SQL (the `.down.sql`) with a dev secret; it is deliberately not modelled as a `contributor` path because forks are excluded and same-repo authors already hold that credential through PR CI. The ADR-061 amendment states this, so `contributor`'s description is not read as covering it.
- **Counts:** the work phase runs `bash plugins/soleur/test/c4-count-parity.test.sh` (a new workflow file could move a workflow count in edge prose) and the C4 syntax/render tests if any `.c4` file changes. Recorded as AC13.

### Sequencing

The amendment describes the shipped state; nothing is soak-gated.

## Guard Contract

**Shared harness (all guards in `dev-ledger-parity.test.sh`).** Every new case is its own `CASES` increment with one verdict; multi-arm rows below are separate cases. `EXPECTED_CASES=<exact>` stays on the line directly above its `if` (the shape `scripts/guard-vacuity-floor.test.sh` checks). The fake `psql` gains a `-f` mode that copies the file's contents into the log at call time (the writer's EXIT trap deletes the file) and a **writer-mode contract**: every call is either the writer's ledger SELECT via `-c` or a `-f` unit; any other call shape is recorded as a breach and fails the case. "Zero writes" means zero calls other than that SELECT. The fake `gh` is routed (`pulls?head=` answers keyed by branch, with `head.sha` taken from `git rev-parse` of the pushed fixture tip; `pulls/N` answers sequenced per call; `git/blobs` returns raw bytes, with a hash-mismatch mode; failure modes for 403, 5xx and non-JSON) and logs to the same ordered call log as the fake psql and a fake `dev-suite-mutex.sh`. Suite-wide `GH_CONFIG_DIR=$tmp/gh`, `GH_TOKEN=invalid`, `GH_HOST=fixture.invalid`, `GITHUB_REPOSITORY=fixture-owner/fixture-repo`. The writer runs as a copy (`DLR_WRITER`) beside a guard copy (`DLR_GUARD`) in a separate writer clone (never `$WORK`, whose `feat_case` runs `git add -A`), with `DLP_OWNERS_CACHE` unset. Every new `git -C` operand passes `assert_fixture_dir`; every fixture fetch carries `--no-tags`; every new assertion matches a full anchored line (`cq-assert-anchor-not-bare-token`).

### Guard 1 — run-migrations gate is cwd-independent

**Property.** For every forward migration filename the runner globs, the unmerged-apply verdict and the coexists-with listing are identical whether `run-migrations.sh` is invoked from the repository root or from `apps/web-platform`.

**Assembly.** The chokepoint is every `git` call in `run-migrations.sh` that takes a repository-relative path: exactly the per-file gate `ls-tree` and the per-prefix collision `ls-tree` (the other six `ls-tree` mentions are comments). `git fetch` (no path) and `git hash-object "$migration_file"` (absolute path) are outside the property.

**Mutation matrix.**

| # | Mutation (to the SUT) | Must turn RED |
|---|---|---|
| G1-M1 | Revert the gate pathspec to the bare `apps/web-platform/…/$filename` | `apps/web-platform` positive control (merged file warned "not on origin/main") |
| G1-M2 | Revert only the collision-listing pathspec | `apps/web-platform` collision case (no `coexists-with: 053_append_kb_sync_row_rpc.sql`) |
| G1-M3 | Anchor with `:(top)` but switch the collision pipeline off `basename` (use the raw ls-tree path) | `apps/web-platform` collision case (paths print cwd-relative under `:(top)`) |

**Harness rows.** H1: remove the `cwd` argument from `runScript()` so every case runs from the root → the RED run recorded before the fix no longer fails (checked once, recorded in the PR body). Must-PASS non-canonical input: the same cases from the repo root (P2), and a synthetic filename absent from main still blocked from the subdirectory without the ack.

**Anchor.** No stored value; the guard compares live `git` output.

### Guard 2 — closed-owner rows are not in-flight, and the classifier stays fail-closed

**Property.** `classify-missing` emits `in-flight` for a missing row only if at least one fresh holder branch has an open PR, has no PR, or has a latest closed PR whose head is not the branch's current tip; when every fresh holder's latest PR closed at the branch's tip, the verdict is `closed-grace` under `CLOSED_GRACE_H` hours since close and `closed` from then on; any PR-state lookup it cannot complete exits 2 (probe: UNCLASSIFIED, blocking). The probe treats `closed-grace` as a warning and `closed` as blocking.

**Assembly.** Chokepoint: `classify_row`'s fresh-state walk — every `in-flight` emission passes through `branch_pr_state`, the only GitHub caller on this path. Consumers: the probe's verdict `case` (`closed-grace`, `closed` arms), its blocking aggregation (error block, fail condition, `ledger_classes`/Sentry). Callers that must pass the token: the two probe steps in `tenant-integration.yml` and the one in `scheduled-dev-migration-drift.yml`, and each job's `pull-requests: read`.

**Mutation matrix.**

| # | Mutation | Must turn RED |
|---|---|---|
| G2-M1 | `branch_pr_state` always returns `open` | closed-at-tip holder → expects `closed` |
| G2-M2 | A non-zero `gh` exit is swallowed and read as `none` | gh-5xx case expects rc=2 after exactly two calls, and no verdict lines |
| G2-M3a | Second member: check only the first (lexically smallest) candidate | `a-closed` + `b-open` → expects `in-flight … b-open` |
| G2-M3b | (same) | `a-open` + `b-closed` → expects `in-flight … a-open` |
| G2-M4a | Grace boundary off by one | closed 23 h ago → expects `closed-grace` |
| G2-M4b | (same) | closed 24 h ago → expects `closed` |
| G2-M5 | Stop at the exact tier: a closed exact-name holder ends the walk | exact holder closed + slug holder open → expects `in-flight … slug` |
| G2-M6 | Dispatch: the lookup is skipped entirely | fresh-holder case asserts the fake gh's call log names that branch's `head=` |
| G2-M7 | Probe routes `closed` to the warning list | probe case with a stubbed `closed` verdict expects exit 1 and `closed` in the Sentry class list |
| G2-M8 | A caller stops passing `github-token`, or a job drops `pull-requests: read` | static wiring cases over all three probe call sites |
| G2-M9 | Drop the `head.sha == branch tip` binding | branch pushed after its PR closed → expects `in-flight` |
| G2-M10 | Memo kept in a shell array | two rows owned by the same branch → the fake gh's call log shows exactly one call for that branch |
| G2-M11 | Summary fields inserted mid-line | summary case expects the line to end with `closed-grace=G closed=C` |
| G2-M12 | Reduction by array order | two closed PRs, older first in the array → the newer one is picked |
| G2-M13 | Reduction ignores an open PR listed after a closed one | `[closed-at-tip, open]` → expects `in-flight` |
| G2-M14 | 403 classified as transient | 403 case expects `cannot measure (config)` naming `403`, and exactly one call (no retry) |
| G2-M15 | Stale checked before closed | fresh closed holder + stale holder → expects `closed` |
| G2-M16 | Hours computed from the wrong timestamp | `closed_at` = now − 30 h → hours field between 29 and 31 |

**Harness rows.** H1: a fake gh that ignores the `head=` parameter and answers the same for every branch → G2-M3a/b turn RED. H2: a `$BIN/gh` that exits 127 (never a removed fake, which would fall through to a real `gh`) → the laziness case (zero calls when no fresh holder) must still PASS and G2-M6 must turn RED. Must-PASS non-canonical: a branch with no PR stays `in-flight`; a branch whose only PR MERGED at its tip yields `closed-grace`/`closed` with neutral text; every pre-existing in-flight case passes under the default fake (`[]`); a runtime check that `classify-missing` makes zero `psql` calls.

**Anchor.** `CLOSED_GRACE_H=24` is a literal in the guard, pinned by G2-M4a/b.

### Guard 3 — `dev-ledger-reconcile.sh` writes only the named PR's rows, only on dev, only under the mutex, atomically, and never lets PR text reach a shell

**Property.** `dev-ledger-reconcile.sh --execute` writes exactly one `psql --single-transaction -f` unit, only after `DOPPLER_ENVIRONMENT=dev` and a `DEV_SUITE_MUTEX_ACQUIRED` banner; the unit deletes (by CAS on filename AND content_sha, raising unless one row) only rows (F, B) where F is not on the base tip and never in base history, B is a blob F carried in a first-parent commit of `base..refs/pull/N/head`, and no independent fresh branch holds F at B; it contains no down body with a backslash byte, transaction control, a non-transactional statement, or (without `--allow-later-rows`) a later-row-sensitive statement while later rows exist; an open PR's rows are written only for its author and never ledger-only.

**Assembly.** The writer file is the only file in this area that issues a write; the guard's single `psql` call shape (`psql "$db" … -c "$LEDGER_SQL"`) is pinned statically and by the runtime zero-psql check in Guard 2. Inside the writer every database write flows through one function (`apply_discard_unit`), which is the only `-f` call site. Eligibility and every refusal are computed before the first write. The environment check runs at entry before any `psql`; the mutex acquire precedes the in-mutex PR re-read and the ledger read. The only CI caller is `dev-ledger-reconcile.yml`.

**Mutation matrix.**

| # | Mutation | Must turn RED |
|---|---|---|
| G3-M1 | Drop the "never in base history" test | F renamed on main once → F ineligible while an eligible sibling in the same run IS written |
| G3-M2 | Drop the (F, B) ∈ PR-history test | another PR's same-named file at another blob → ineligible, sibling written |
| G3-M3 | Second member: evaluate refusals inside the write loop | three eligible rows, the LAST in execution order has a `CONCURRENTLY` down → zero writes (writer-mode contract), with a paired run without that body writing one unit |
| G3-M4 | Split the unit into one psql call per row | two eligible rows → exactly one `-f` call whose logged payload holds both CAS blocks |
| G3-M5 | REORDER: read the ledger before `acquire` | ordered call log: `acquire` precedes the ledger SELECT |
| G3-M6 | Remove the `DOPPLER_ENVIRONMENT` check | `DOPPLER_ENVIRONMENT=prd` → rc=2, the env message, zero psql calls |
| G3-M7a | Ignore the mutex banner | fake mutex prints `DEV_SUITE_MUTEX_CONTENDED_PROCEEDING` → rc=2 naming that token, zero writes, a `release` call |
| G3-M7b | (same) | `DEV_SUITE_MUTEX_UNAVAILABLE` → rc=2 naming that token |
| G3-M8a | Pair the down body with the commit that last CHANGED F | author edits only `F.down.sql` after apply → the NEWER down body in the payload |
| G3-M8b | (same) | author edits F and `F.down.sql` after apply → the OLDER one |
| G3-M9 | Skip the blob integrity check | fake gh blob whose hash ≠ id → rc=2 |
| G3-M10a | Drop the later-row refusal | `DROP … CASCADE` body + a later foreign row → rc=1, zero writes |
| G3-M10b | Refuse without a later row (over-refusal) | same body, no later row → written (must-PASS) |
| G3-M10c | Ignore the override | same body + later row + `--allow-later-rows` → written |
| G3-M10d | Later-row check covers only CASCADE | `CREATE OR REPLACE FUNCTION` body + a later MAIN row → rc=1 |
| G3-M11 | Second member for later rows: check only the FIRST later row | two later rows, the first is one of the PR's own, the second foreign → rc=1 |
| G3-M12 | A write path appears in the guard file | static case: the guard's only `psql` call is the `-c "$LEDGER_SQL"` shape |
| G3-M13a | Library mode leaks the dispatch | sourcing with `DLP_AS_LIBRARY=1` prints nothing and does not exit |
| G3-M13b | Direct run with the flag set is silent | executing the guard with `DLP_AS_LIBRARY=1` → rc=2 and the error line |
| G3-M14 | The writer's EXIT trap is replaced by the guard's | a refused run after `acquire` logs `release` AND removes its temp dirs |
| G3-M15a | Drop the wrapper normalization | wrapped `BEGIN;`…`COMMIT;` body → written with the wrapper stripped |
| G3-M15b | Widen normalization to mid-body statements | body with a mid-body `COMMIT;` → rc=1, zero writes |
| G3-M16 | REORDER: the reopen re-read happens before `acquire` | ordered call log: the second `pulls/N` call follows `acquire`; sequenced `closed`→`open` answers → `skipped (pr=N reopened)`, zero writes |
| G3-M17 | Drop the backslash refusal | down body `\! touch <sentinel>` → rc=1, zero psql calls, sentinel absent |
| G3-M18 | Refusal regex runs on raw text | a down body restoring a plpgsql function (`BEGIN`/`END` inside `$$`) → written (must-PASS) |
| G3-M19 | Weaken the CAS | payload case: each `DO` block carries `AND content_sha = '<B>'` and the `n = 1` raise; argv carries `--single-transaction` and `ON_ERROR_STOP=1` |
| G3-M20 | Order by filename only | two rows where the lower filename was applied LATER → it comes first in the payload |
| G3-M21 | Drop the open-PR author check | open PR, `--actor` ≠ author → rc=1, zero writes; = author → written |
| G3-M22 | Allow ledger-only on an open PR | open PR, eligible row with no down, author actor → rc=1 |
| G3-M23 | `release` called before the unit | ordered call log: the `-f` call sits between `acquire` and `release` |

**Harness rows.** H1: the fake psql stops recording `-f` payloads → an instrument self-test (a known fixture unit appears verbatim in the log) turns RED before any row. H2: a fake mutex that always prints ACQUIRED → G3-M7a/b turn RED. H3: a fake psql that accepts any call → the writer-mode contract self-test turns RED. Must-PASS non-canonical: a closed PR whose branch was deleted (only `refs/pull/N/head` in the fixture origin) is reconcilable; an in-sync row (applied blob == head blob) is eligible; a closed PR's no-down row is discarded ledger-only with the residue `::warning::`; a PR whose history carries no migration exits 0 with `nothing to do` and no mutex call; dry-run makes zero write calls and no mutex call; a separate case runs the stripped-view refusal step over all 95 down files on main and matches the pinned refusal sets.

**Anchor.** The pinned refusal sets over the 95 down files are a stored value; a change to them shows in the diff of the test's expected-set literal, and a new down file on main that changes a set reddens the case until the literal is updated in review.

### Guard 4 — reconcile workflow wiring

**Property.** `dev-ledger-reconcile.yml` runs only main's copy of the writer, never checks out or executes PR-head code, never holds a non-dev Doppler token, never runs for a fork PR or a dispatch off `main`, never interpolates event or input text into a `run:` body, and passes the close-path flags (`--execute --require-closed`, never `--allow-later-rows`).

**Assembly.** The workflow's `on:`, the job `if:`, the checkout step's `with:`, every `secrets.*` reference, every `run:` body, and the reconcile step's argv construction. Static cases use `wf_static`/`wf_mutant` against the parsed YAML with comments stripped; the argv case runs `extract_step` on the reconcile step with a stub writer that records its argv.

**Mutation matrix.**

| # | Mutation | Must turn RED |
|---|---|---|
| G4-M1 | Checkout gains any `ref:` key | checkout case asserts no `ref:` key at all |
| G4-M2 | Any `DOPPLER_TOKEN_PRD*` secret, or `-c prd`, appears | secret-scope case |
| G4-M3 | The fork clause is dropped from `if:` | if-clause case |
| G4-M4 | The dispatch clause loses `github.ref == 'refs/heads/main'` | if-clause case |
| G4-M5 | `${{ inputs.* }}` or `${{ github.event.* }}` appears inside a `run:` body | injection case |
| G4-M6a | Close path loses `--require-closed` or gains `--allow-later-rows` | argv case, `EVENT_NAME=pull_request_target` → `--execute --require-closed`, no `--allow-later-rows` |
| G4-M6b | Dispatch defaults to execute | argv case, dispatch defaults → no `--execute` |
| G4-M7 | The issue step's `if:` narrows to the reconcile outcome only | static case: the condition includes `job.status == 'failure'` |

**Harness rows.** H1: the YAML parse returns zero jobs or zero steps → the cases fail on "0 steps parsed". Must-PASS non-canonical: a comment line mentioning `ref:` or `prd` does not trip the checks.

**Anchor.** No stored value.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** `run-migrations-unmerged-gate.test.ts` runs every case from BOTH the repo root and `apps/web-platform`, plus the collision case from both; the PR body records that the `apps/web-platform` positive control and collision case FAILED before the pathspec change and pass after it, and that G1-M1..M3 each turned the named case RED.
- [x] **AC2** From the repo root, the pre-existing three cases pass with their assertions unchanged (P2).
- [x] **AC3** `bash apps/web-platform/scripts/dev-ledger-parity.test.sh` passes with `EXPECTED_CASES` equal to the new exact case count; every Guard 2, 3 and 4 mutation and harness row was run once and turned its named case RED (recorded in the PR body).
- [x] **AC4** `classify-missing` with a fresh holder whose PR closed at the branch tip 30 h earlier prints `closed<TAB><file><TAB><branch><TAB><N><TAB><29..31>` and a summary ending `closed-grace=0 closed=1`; closed 23 h earlier prints `closed-grace`; with the fake gh returning 5xx it exits 2 after two calls; with 403 it exits 2 naming `config` and `403` after one call; with no fresh holder the fake gh's call log is empty; two rows owned by one branch produce one call.
- [x] **AC5** The probe, fed a `closed-grace` verdict with `fail-on-ledger-drift: true`, exits 0 with a `::warning::`; fed `closed`, it exits 1 with an `::error::` block naming the PR number and the dry-run command, with `closed` in the Sentry class list; with `fail-on-ledger-drift: false` it never calls the classifier.
- [x] **AC6** `dev-ledger-reconcile.sh` (dry-run) prints `would-discard` and `later-row` lines and `ledger-discard: dry-run (…)` and makes zero write calls and zero mutex calls; `--execute` against the fixture makes exactly one `-f` call whose logged payload orders rows by `applied_at` DESC then filename DESC, each CAS block before its down body, preceded by the `lock_timeout`/`statement_timeout` settings.
- [x] **AC7** `dev-ledger-reconcile.sh` exits 2 with zero psql calls when `DOPPLER_ENVIRONMENT` is not `dev`; exits 2 with zero writes plus a `release` call when the fake mutex prints `CONTENDED_PROCEEDING` or `UNAVAILABLE`; exits 1 with zero psql calls on a down body containing a backslash.
- [x] **AC8** `.github/workflows/dev-ledger-reconcile.yml` passes `bash scripts/lint-workflows.sh .github/workflows/dev-ledger-reconcile.yml` (no new findings), `python3 scripts/lint-workflow-issue-write-scope.py`, `python3 scripts/lint-workflow-step-env-refs.py`, `python3 scripts/lint-workflow-local-action-checkout.py`, and the Guard 4 static and argv cases.
- [x] **AC9** Repo ratchets green: `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-diagnosis-claims.test.sh` with the highwater unchanged, `bash scripts/battery-tag-authorship.test.sh`, `python3 scripts/lint-shell-capture-exit.py` against its baseline, `bash tests/scripts/test-dev-suite-mutex-wiring.sh`, and the fixture-relative / fixture-dir-operand assertion scans the suite is already enrolled in.
- [x] **AC10** ADR-061 ends with the new amendment carrying the restated ownership rule, the two named superseded sentences, DC-1, the bounded Policy 2 relaxation and the 30 h detection ceiling; `git diff origin/main -- <ADR-061>` shows only added lines.
- [x] **AC11** AC11 of the #8521 plan is ticked with run 35891815286's evidence before the move; both archive-kb runs moved exactly one artifact each via `git mv` (`git log --follow` shows history on the archived paths); `git grep -n -e 'plans/2026-09-23-fix-pr-ci-unmerged-migration-ledger-parity-plan.md' -e 'specs/feat-one-shot-8521-dev-ledger-content-drift'` returns only lines inside `knowledge-base/**/archive/**` and this plan's own artifacts (this plan, `specs/feat-one-shot-8605-8606-dev-reconcile/`).
- [ ] **AC12** Pre-merge dry look at live dev (read-only): `gh workflow run scheduled-dev-migration-drift.yml --ref feat-one-shot-8605-8606-dev-reconcile` runs this branch's classifier with the token; its log shows `ledger-classify:` or `No dev-vs-main migration drift detected.`, and no `UNCLASSIFIED`. Any `closed-grace`/`closed` line it prints is listed in the PR body with the post-merge dry-run command for that PR.
- [x] **AC13** `bash plugins/soleur/test/c4-count-parity.test.sh` passes (no `.c4` edit expected).
- [ ] **AC14** The PR body carries `Closes #8605` and `Closes #8606`, the DC-1 decision sentence, and the AC1/AC3 mutation records.

### Post-merge

- [ ] **AC15** The first push run of `tenant-integration.yml` on main is read with `gh run view <id> --log | grep -e 'ledger-classify:' -e 'No dev-vs-main migration drift detected.'`; no `UNCLASSIFIED` line. Its conclusion is not asserted: it depends on dev state other refs write (`cq-ac-must-not-depend-on-concurrent-sessions`).
- [ ] **AC16** One read-only exercise of the new path: `gh workflow run dev-ledger-reconcile.yml --ref main -f pr=<a closed same-repo PR that applied a migration>` completes and prints `ledger-discard: dry-run (…)` or `ledger-discard: nothing to do (…)`; when rows were listed, the audit comment is on that PR. `gh api repos/jikig-ai/soleur/actions/workflows/dev-ledger-reconcile.yml --jq .state` prints `active`.
- [ ] **AC17** #8605 carries a closing comment recording DC-1 (CI writes to the shared DEV ledger/schema via `dev-ledger-reconcile.yml`, never prd; ADR-061 amendment link).

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CI and dev-database tooling. The load-bearing risks are (1) main-red from a new blocking verdict (mitigated by the close-time discard, the 24 h grace, the action-required issue, and AC12's pre-merge look at live dev), (2) a writer on shared dev (mitigated by a separate writer file, an in-process env check, a strict mutex with a 600 s wait, one CAS-guarded transaction per PR, all-or-nothing refusals (backslash, transaction-control, non-transactional, later-row-sensitive downs), an open-PR author check, dry-run default on dispatch, a reopen re-check), and (3) the prd apply path edit (two pathspecs, fail-closed, byte-equivalent from the root). No product, marketing, legal, finance, sales, support or operations surface: no UI, no user data, no vendor, no spend. Plan review ran DHH, Kieran, code-simplicity and CTO (devex); their findings are folded into this revision (see `## Plan Review Revisions`).

Product/UX Gate: NONE (no UI-surface file in Files to Create/Edit).

## Test Scenarios

- Gate from `apps/web-platform`: merged file silent; synthetic unmerged file blocked without the ack; warned with it; collision listing sees main's `053_*`. Same from the root.
- Classifier: open / none / closed at tip (23 h, 24 h, 30 h) / closed then pushed (in-flight) / merged-only / two holders in both orders / exact-closed + slug-open / closed + stale / `[closed, open]` / two closed PRs out of order / 5xx (retry then rc 2) / 403 (config, no retry) / non-JSON / no fresh holder (no gh call) / two rows one branch (one call) / `GITHUB_REPOSITORY` unset (rc 2) / pre-existing in-flight cases under the default fake / zero psql calls.
- Probe: `closed-grace` → warning; `closed` → blocking with Sentry class; malformed `closed` line (non-numeric PR or hours) → UNCLASSIFIED; summary ends with `closed-grace=… closed=…`; orphan block carries the lookup hint.
- Writer: help before refusals; dry-run; nothing-to-do; single unit for several rows ordered by `applied_at` then filename; CAS payload shape; main-history name ineligible; other PR's blob ineligible; independent holder ineligible, inherited holder not; deleted-branch PR via `refs/pull/N/head`; head-sha mismatch → rc 2; fork or null `head.repo` → rc 1; down pairing after a down-only edit and after a forward+down edit; closed PR no-down → ledger-only with residue warning; open PR no-down → refused; open PR by a non-author → refused; wrapped BEGIN/COMMIT stripped; mid-body COMMIT refused; plpgsql function body accepted; CONCURRENTLY refused; backslash refused with no psql call; CASCADE and CREATE OR REPLACE with and without later rows, and with `--allow-later-rows`; blob hash mismatch; env ≠ dev; mutex contended/unavailable; lock timeout → rc 2; reopened PR skipped under `--require-closed` with the re-read after `acquire`; library-mode sourcing runs nothing; direct run with `DLP_AS_LIBRARY=1` → rc 2; EXIT trap releases and cleans up; refusal sets over the 95 down files on main.
- Workflow: checkout has no `ref:`; secret scope; fork clause; dispatch-on-main clause; no interpolation in `run:`; close-path and dispatch argv; the issue step fires on job failure.

## Plan Review Revisions

Panel: `soleur:engineering:review:dhh-rails-reviewer`, `soleur:engineering:review:kieran-rails-reviewer`, `soleur:engineering:review:code-simplicity-reviewer`, `soleur:engineering:cto` (devex lens); plus the Step 4.5 advisor consult. Applied (mechanical):

- Kieran P1: down bodies fetched with the raw media type (`@base64d` rejects GitHub's wrapped base64 — reproduced); non-transactional statements (`CONCURRENTLY`, `VACUUM`, `ALTER SYSTEM`, `CREATE DATABASE`) refused up front; writer mutex wait raised to 600 s with its own state dir.
- Kieran + DHH + CTO + code-simplicity converged on the blocking-after-1 h risk (a refused or unfired close-time run would red main within the hour): grace raised to 24 h, split by age in the probe, with an `action-required` issue as the pre-block signal. `closed` stays blocking after grace (fail-closed), so the operator's direction holds.
- Kieran P2: census and summary-line consumers fixed (summary field appended, two exact-string cases listed, fake gh for existing in-flight cases); memo moved to a file (subshell per row); `--paginate` dropped; down pairing walks first-parent trees (a `--raw` walk misses down-only edits); `DLP_AS_LIBRARY` instead of a `BASH_SOURCE` main-guard; `NOTIFY pgrst` dropped (#4285); reopened PRs skipped inside the mutex; REST comment API instead of `gh pr comment`; stacked-branch behaviour stated.
- CTO P1: a single wrapping `BEGIN;`/`COMMIT;` pair is normalized away, so wrapped down files are self-service; annotation leads with the dry-run command and points at the issue; ledger-only residue files an issue; dispatch inputs carry descriptions.
- DHH/code-simplicity cuts: `--file`/`files`, the touched-migrations pre-check (replaced by the writer's own git-only early exit), the concurrency group and G4-M6, the workflow-level Doppler assertion, the ops email, the mutant-copy control and census; trap-composition row added (G3-M14).

**Deepen-plan revisions (2026-09-23)**, applied as mechanical: backslash refusal and `GH_TOKEN` unset for psql (security P0); stripped-view refusal matching and the 95-file pinned refusal set (data integrity + security P1: the raw regex hit 51 of 95 files); one transaction per PR ordered by microsecond `applied_at` with lock and statement timeouts (data integrity P1); later-row refusal widened to redefinitions (data integrity P1); open-PR execute limited to the author and to rows with a down (security P2 + architecture P1); workflow-level Doppler dev assertion restored (security P2); `declare -gA`, library API block, `independent_holder` extraction, direct-run `DLP_AS_LIBRARY` error (architecture P1); grace moved into the classifier as `closed-grace` (architecture P2); 401/403/404 → config, one retry on 5xx/429 (observability P1); issue on any close-path job failure, failing job on a failed issue create, orphan lookup hint, layer citations, 30 h ceiling (observability P0/P1); fake-psql `-f` capture, writer-mode contract, positive controls, routed and sequenced fake gh with no fall-through, split multi-arm rows, order rows, argv case, G1-M4 dropped (test design P0/P1); `ls-tree` comment count corrected to six (negative sweep).

Taste / User-Challenge findings persisted to `knowledge-base/project/specs/feat-one-shot-8605-8606-dev-reconcile/decision-challenges.md`: warning-only `closed` with dispatch-only reconcile (code-simplicity; User-Challenge — not applied); scheduled probe auto-dispatching the reconcile (CTO; not applied); a separate writer test suite (CTO; not applied); `--full-tree` instead of `:(top,literal)` (code-simplicity; not applied, convention kept); degrading a transient PR-state failure to a warning (architecture; User-Challenge DC-5 — not applied, operator direction is fail-closed).

## Sharp Edges

- `git ls-tree` under `:(top)` prints paths relative to the CWD. Anything that consumes the path (not the basename) must add `--full-name`; the collision code uses `basename`, which is why G1-M3 exists.
- The subdirectory runs of `run-migrations.sh` need `SUPABASE_ACCESS_TOKEN=""` in their env, exactly like the existing `runScript()` (the reload hook runs on every exit path).
- `gh api -X GET … -f key=value` is required: without `-X GET`, `-f` turns the call into a POST. Use `-i` to read the HTTP status for the config/transient split.
- psql executes backslash meta-commands from a `-f` file (`\!` runs a shell). Any PR-authored text fed to psql must be refused on a backslash byte first.
- Refusal regexes over SQL must run on a view with comments, strings and dollar-quoted bodies removed; plpgsql bodies contain bare `BEGIN`/`END` lines.
- Sourcing a file that uses top-level `declare -A` from inside a function makes the arrays function-local; the guard uses `declare -gA`, and the writer sources at top level.
- A `pull_request_target` job shares main's cache scope; it must restore no cache and execute no PR-authored code outside the dev database.
- The owner repo runs with `GIT_NO_LAZY_FETCH=1` and has no blob contents: down bodies come from the blobs API with `Accept: application/vnd.github.raw+json`, never from `git show` in the owner repo and never through `jq @base64d`.
- `classify_row` runs in a subshell per row; any state it must share across rows lives in a file under `CLEAN`.
- Portability (the scripts also run on operator laptops): ISO timestamps become epochs inside `jq` (`fromdateiso8601`), never `date -d`; network calls use the script's existing `TIMEOUT_BIN` (`timeout`→`gtimeout`→bare) pattern.
- PR-state evidence is keyed on the commit (`head.sha` == branch tip), not the branch name; a name-only lookup would let an old closed PR condemn a re-pushed or recreated branch.
- Every value that reaches an annotation (`::error::`, `::warning::`, `::notice::`) or a tab-delimited verdict line is a whitelisted filename, a validated branch label, a 40-hex sha or an integer; API strings (titles, bodies, logins) never do.
- A new blocking verdict on the authoritative probe can red main 24 h after merge if dev already holds closed-owner rows — AC12 measures that before merge.
- Every fixture `git fetch`/`clone`/`init` in the suite needs `--no-tags` where it fetches (battery-tag-authorship), and every `git -C` operand must pass the suite's `assert_fixture_dir`.
- Run `npx markdownlint-cli2` on this plan and `tasks.md` before handing off; lefthook lints both at the first work-phase commit.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
