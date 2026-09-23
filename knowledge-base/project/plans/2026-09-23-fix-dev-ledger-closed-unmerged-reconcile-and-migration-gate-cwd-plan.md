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

## Overview

One pull request for three linked pieces of the shared-dev migration ledger work that follows PR #8602 (merged 2026-09-23 as `d42057b67d`).

1. **#8606 — run-migrations gate is inert from a subdirectory.** `apps/web-platform/scripts/run-migrations.sh` checks each file with `git ls-tree origin/main -- "apps/web-platform/supabase/migrations/$filename"`. `git ls-tree` resolves that path against the current directory, so when `tenant-integration.yml` and `rls-authz-fuzz.yml` run the script with `working-directory: apps/web-platform`, every file is "not on origin/main". Anchor both pathspecs on the repository top with `:(top,literal)` and prove it with tests that run from `apps/web-platform`. From the repository root (the prd release path) the anchored pathspec names the same path, so prd behaviour does not change.
2. **#8605 (a) — closed PRs stop protecting their rows.** `dev-ledger-parity.sh classify-missing` calls a missing-on-main row in-flight whenever a fresh, live, unmerged branch holds it. A branch whose PR was closed and never deleted protects its rows forever. The classifier gains a read-only PR-state lookup (GitHub REST, `pull-requests: read`, only for fresh owner branches) and a new verdict, `closed`: a warning for 24 hours after the PR closed, then blocking. It stays fail-closed: a lookup it cannot complete exits 2, which the probe reports as UNCLASSIFIED.
3. **#8605 (b) — an audited, dispatchable dev-reconcile path.** A new writer script, `apps/web-platform/scripts/dev-ledger-reconcile.sh`, that sources the guard's ownership primitive, driven by a new workflow `.github/workflows/dev-ledger-reconcile.yml`. For one pull request it discards the applied-but-unmerged migration versions that PR owns: a compare-and-set delete of the ledger row plus the paired `.down.sql` when there is one, in one transaction per file, under the dev-suite mutex, on dev only. It runs automatically when a same-repo PR is closed without merging, and on `workflow_dispatch` from `main`.
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
- P5 — An applied-but-unmerged version can be discarded without a hand-run SQL session: CAS ledger delete + the paired `.down.sql` if present, only for rows the named PR owns, and never by dropping another in-flight branch's objects.
- P6 — That path never writes to prd and never writes without holding the dev-suite mutex.
- P7 — Every discard, refusal and residue leaves a durable, human-readable record (who, which PR, which rows, which blobs), and a refusal reaches the operator.
- P8 — Closing a migration PR unmerged does not red main while its close-time discard can still succeed (grace window); a refused discard surfaces to the operator before it can red main.
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
- *(plan review)* Workflow-level Doppler `configs get` assertion → P6 → cut: the writer's in-process `DOPPLER_ENVIRONMENT=dev` check covers the workflow and laptops, and is tested (G3-M6).
- *(plan review)* Ops email → P7 → cut: the `action-required` issue carries the dispatch command and reaches operator-digest; one channel.
- *(plan review)* Mutant-copy control and static census for #8606 → no property → cut: the subdirectory cases written RED first prove the harness sees the defect, and the census as specified could not pass (five comment lines in `run-migrations.sh` mention `ls-tree`).
- *(plan review)* `NOTIFY pgrst` in each unit → cut: it cannot reach PostgREST over the pooler (#4285).
- *(plan review, declined)* Close to warning-only with dispatch-only reconcile (code-simplicity) → recorded as a User-Challenge in `knowledge-base/project/specs/feat-one-shot-8605-8606-dev-reconcile/decision-challenges.md`; the operator's direction (auto-handle closed PRs, e.g. a close job) stands.
- *(plan review, declined)* Scheduled probe auto-dispatches the reconcile for `closed` lines (CTO) → needs `actions: write` on a scheduled job; the 24 h grace plus the `action-required` issue plus a 600 s mutex wait cover P8 without it. Recorded as Taste.
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
   - `branch_pr_state <branch> <tip-sha>` — the only GitHub caller on the classify path. It runs `gh api -X GET "repos/$GH_REPO/pulls" -f state=all -f head="$GH_OWNER:$branch" -f per_page=100` (no `--paginate`: one page of 100 PRs per head branch is ample, and `--paginate` concatenates arrays a single jq reduction would misread), bounded by the script's `TIMEOUT_BIN`, and reduces the result with `jq -e` to one token: `open`, `none`, or `closed <number> <closed_at_epoch>` (the most recently closed PR). **The evidence is bound to the commit, not the name** (the #8490/PR #8493 class: a name-keyed lookup attaches an old closed PR to a reused or re-pushed branch). `closed` is returned only when that PR's `head.sha` equals `<tip-sha>`, the owner branch's current tip in the owner repo; a branch that received commits after its PR closed, or a recreated branch name, reads as `none` (live work with no PR, still in-flight). The epoch comes from jq's `fromdateiso8601`, never `date -d`. `GH_REPO` comes from `GITHUB_REPOSITORY` (validated `^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$`); unset or malformed → `cannot_measure config`. A non-zero `gh` exit, non-JSON output (`jq -e` fails), or a PR entry without a parseable `closed_at` → `cannot_measure transient`.
   - **Memo in a file, not an array.** `classify_row` runs in a `$( )` subshell per row, so an in-memory memo would be lost after every row. `branch_pr_state` memoises in a per-invocation TSV under `CLEAN` (`branch<TAB>token`), so each owner branch costs one API call per probe. It runs only when a fresh candidate exists, so a probe with no in-flight candidates makes zero API calls.
   - `classify_row`: for the `fresh` state, walk tiers exact → blob → slug; for each candidate, `open` or `none` → emit `in-flight` (as today, same fields). `closed` → remember the first such hit and keep looking. If no live holder is found in any fresh tier and a closed hit was remembered → emit `closed<TAB><file><TAB><branch><TAB><pr-number><TAB><hours-since-close>`. Otherwise fall through to the `stale` tiers exactly as today.
   - Summary line gains a field **at the end**: `ledger-classify: in-flight=N stale=M merged=J orphan=K closed=C` (appending keeps any prefix match on the old shape valid).
   - `usage()` documents the verdict, the grace, and the `GITHUB_REPOSITORY`/`GH_TOKEN` requirement.
   - **Library mode.** The dispatch `case` at the bottom runs unless `DLP_AS_LIBRARY=1` is set (an explicit opt-out env, not a `BASH_SOURCE`/`$0` comparison, which would silently skip dispatch under `bash -s` or stdin execution). Sourced in library mode, the file defines functions and exits nothing.
   - The two `check` error messages that say "(#8605 tracks self-service)" / "ask a dev operator to reconcile … (#8605)" now name the workflow: `gh workflow run dev-ledger-reconcile.yml --ref main -f pr=<your PR>` (dry run first).
2. Tests (existing suite): add a fake `gh` to the suite's `BIN` (logs argv; answers from a per-case fixture file; can be told to fail or emit non-JSON), export `GITHUB_REPOSITORY` in `run_classify` and `run_probe`, and update the two exact-summary-string cases to the new line. Every existing in-flight case keeps passing because the default fake answers `[]` (`none`).
3. In `action.yml`: new optional input `github-token` (default `''`), exported as `GH_TOKEN` ONLY on the classifier call. New `case` arm `closed)` reading a fifth field (`IFS=$'\t' read -r v vf vb vx vh`), validating `vb` against `branch_re`, `vx` against `^[0-9]+$` and `vh` against `^[0-9]+$`. **Severity by age:** `vh < 24` → append to a warning list (`closed-in-grace`); `vh >= 24` → append to `closed_lines`, which is blocking: `::error::` block, included in the fail condition next to `orphans`/`stale_lines`/`unclassified`/`content_drift`, and in `ledger_classes` as `closed` (one Sentry event on the scheduled surface). Line text states only what was measured and leads with the safe command: `- <file> (owner branch <b> has no open pull request; #<N> closed <h> h ago — check its action-required issue, or preview the discard: gh workflow run dev-ledger-reconcile.yml --ref main -f pr=<N>; if the dry run lists rows, re-run with -f execute=true)`. Update the stale-line text to name the reconcile workflow instead of "#8605".
4. Callers: `tenant-integration.yml` heavy job gets job-level `permissions: { contents: read, pull-requests: read }` and both probe calls pass `github-token: ${{ github.token }}`. `scheduled-dev-migration-drift.yml` gets `pull-requests: read` and passes the token. PR-mode runs never reach the classifier, so the token is unused there. Run `tests/scripts/test-dev-suite-mutex-wiring.sh` after the edit.

### Phase 3 — #8605 (b): the writer, `dev-ledger-reconcile.sh` (test first)

**A separate file from the guard** (advisor consult, adopted): `apps/web-platform/scripts/dev-ledger-reconcile.sh` is the only file in this area that writes to a database. It sets `DLP_AS_LIBRARY=1` and sources `dev-ledger-parity.sh` to reuse the ownership primitive. The guard stays one self-contained, read-only file, which keeps `tenant-integration.yml`'s base-ref single-file extraction of it valid, and its header's "Nothing writes to dev or prd" stays true. The writer installs its own EXIT trap that calls the guard's `cleanup` and then the mutex `release`, so a later trap added to the guard cannot silently replace the release (pinned by G3-M14).

`dev-ledger-reconcile.sh --pr <N> --repo <dir> --base-branch <name> [--execute] [--allow-cascade] [--require-closed]`

Order of operations (each step exits before the next on failure):

1. **Parse and refuse early.** `--pr` must match `^[1-9][0-9]{0,6}$`. `DOPPLER_ENVIRONMENT` must equal `dev` (both modes; `cannot_measure config` otherwise, with zero `psql` calls). `GITHUB_REPOSITORY` validated as in Phase 2.
2. **PR facts (API, read-only).** `gh api repos/$GH_REPO/pulls/$N` (shape-checked with `jq -e`) → `head.repo.full_name` must equal `GH_REPO` (fork → exit 1 "fork PRs never applied to dev"); capture `head.sha` and `state`.
3. **Git facts (owner repo, no DB).** `owners_repo "$base_branch"`, then a second bounded blobless fetch of `+refs/pull/$N/head:refs/prhead/$N` into the same owner repo (`--no-tags`, `--filter=blob:none`). Its tip must equal the API `head.sha`; a mismatch (a push landed between the two reads) → `cannot_measure transient`, re-run. `refs/pull/N/head` survives branch deletion, so a PR closed with "delete branch" is still reconcilable.
4. **PR history pairs.** Walk `ogit rev-list --reverse --first-parent "$BASE_OWN..refs/prhead/$N"`, and for each commit read its tree once (`ogit ls-tree <commit> -- ":(top,literal)$MIG_REL/"`), tracking each top-level forward file F's current blob. For each (F, B) that F ever carried, record the LAST commit at which F still had blob B (a later commit that edits only `F.down.sql` therefore moves the pairing forward, which a `--raw` walk cannot see). The down blob for (F, B) is `F.down.sql`'s blob in that commit's tree, or none. **If no (F, B) pair exists, print `ledger-discard: nothing to do (pr=N)` and exit 0 here** — before any mutex or database contact. This replaces a workflow pre-check.
5. **Mutex (execute mode only).** `DEV_SUITE_MUTEX_STATE_DIR="$(mktemp -d)"` (the writer's own, so `acquire` and `release` cannot disagree on `$PPID`), `DEV_SUITE_MUTEX_WAIT_S=600` (a tenant-integration critical section runs 5-9 min; the job has 15), `DEV_SUITE_MUTEX_IDENTITY=reconcile-${GITHUB_RUN_ID:-local}-pr$N`; then `bash "$REPO/scripts/dev-suite-mutex.sh" acquire`. Proceed only if its stdout has a line starting `DEV_SUITE_MUTEX_ACQUIRED`; otherwise run `release` and `cannot_measure transient "could not hold the dev-suite mutex (<banner token>); nothing was changed"`. `release` is in the EXIT trap from this point on.
6. **Re-check PR state (execute mode, `--require-closed`).** The close-time path passes `--require-closed`: re-read `state` inside the mutex; if the PR has been reopened (a common way to re-trigger CI), print `ledger-discard: skipped (pr=N reopened)` and exit 0 with no write.
7. **Ledger read (inside the mutex).** A writer-local SELECT that adds `applied_at` to the guard's shape: `filename || '|' || COALESCE(content_sha, '') || '|' || COALESCE(extract(epoch from applied_at)::bigint::text, '')`, parsed with the same one-delimiter-per-field discipline.
8. **Eligibility (all-or-nothing).** A ledger row (F, B) is eligible iff: `name_ok F`; F is not on the base tip and never appeared in base history (`OWN_ON_BASE`, `OWN_EVER`); B is 40-hex; (F, B) is in the PR history pairs; and no fresh live branch other than the PR's head branch holds F at B unless it inherited that from the PR's history (reuse `holders_at_blob` and the `merge-base --is-ancestor` test from `cmd_check`). Ineligible rows are not this PR's and are not errors. **Stacked branches:** an open branch stacked on this PR that inherited F does not protect F (the inherited-holder rule); its next CI run re-applies F. Stated in the audit comment when the owner repo shows such a descendant.
9. **Down bodies and refusals.** For each eligible row with a down blob: `gh api -H 'Accept: application/vnd.github.raw+json' repos/$GH_REPO/git/blobs/<id> > <tmp>`; `git hash-object <tmp>` must equal the id (else `cannot_measure transient`). Normalize one wrapping transaction: if the first non-comment statement is exactly `BEGIN;` and the last is exactly `COMMIT;`, strip those two lines (the unit already runs under `--single-transaction`). Then refuse the WHOLE run (exit 1, zero writes) when any eligible row's body:
   - still contains a transaction statement (`^[[:space:]]*(BEGIN|COMMIT|ROLLBACK|END|START[[:space:]]+TRANSACTION|SAVEPOINT)\b`, case-insensitive) — "needs manual handling per the learning";
   - contains a statement that cannot run in a transaction (`\bCONCURRENTLY\b|\bVACUUM\b|\bALTER[[:space:]]+SYSTEM\b|\bCREATE[[:space:]]+DATABASE\b`, case-insensitive; `132_drop_unused_indexes.down.sql` on main is one) — refusing up front keeps the run all-or-nothing;
   - contains the word `CASCADE` (case-insensitive) while the ledger holds a FOREIGN row applied after F (a row not on the base tip and not one of this PR's pairs, with `applied_at` later than F's). `CASCADE` there could drop another in-flight branch's dependent objects on shared dev. `--allow-cascade` (dispatch input `allow_cascade`, never passed by the close-time path) is the human override after a dry run. With no later foreign row, `CASCADE` can only reach this PR's objects and main's, and main's migrations never depend on an unmerged file. Residual, stated in the ADR: a foreign object created BEFORE F by an out-of-order apply that depends on F is not seen by this rule.
   A row with NO down blob is discarded ledger-only, per the operator's direction ("apply the applied blob's `.down.sql` if present, delete the row"): the run prints `::warning::ledger-discard: <F> has no .down.sql paired with applied blob <B>; objects its body created stay on dev`, and the audit step files an issue for the residue (Phase 4).
10. **Dry run (default).** Print one `would-discard <F> <B> down=<id|none>` line per row in execution order and `ledger-discard: dry-run (pr=N eligible=E down=K ledger-only=L)`; exit 0. No mutex, no write.
11. **Execute.** Rows in DESCENDING filename order. Per row, ONE `psql "$db" -w --no-psqlrc --single-transaction -v ON_ERROR_STOP=1 -f <unit.sql>` where `unit.sql` holds (a) a `DO $$ … $$` block that runs `DELETE FROM public._schema_migrations WHERE filename = '<F>' AND content_sha = '<B>'`, reads `GET DIAGNOSTICS n = ROW_COUNT`, and `RAISE EXCEPTION` unless `n = 1`; then (b) the normalized down body, if any. Putting the CAS first aborts before any DDL when the row changed; either order rolls back together, so the assertion that matters is one unit per row. A failed unit stops the run: exit 1, naming the file and listing the rows already committed. Each success prints `::notice::ledger-discard: discarded <F> (applied blob <B>, down <id|none>) for PR #<N>`. No `NOTIFY pgrst` (it cannot reach PostgREST over the pooler, #4285); the summary notes the ~10-min schema-cache poll.
12. **Summary.** `ledger-discard: executed (pr=N eligible=E discarded=D down=K ledger-only=L)` on stdout; exit 0. `--help` prints usage naming the `ledger-discard:` summary line.

Exit codes mirror the guard's contract: 0 done/dry-run/nothing-to-do/skipped, 1 refused or a unit failed (named), 2 cannot measure (nothing written, or — if a unit already committed — the committed rows are listed first).

**Races, stated.** A reopened PR's next CI run re-applies its forward files (they are no longer ledgered) — the ordinary pending path; the in-mutex state re-check stops a close-time run that lost the race to a reopen. A PR CI run that holds the mutex fail-OPEN (`CONTENDED_PROCEEDING`) can still interleave with a discard; the CAS keeps the ledger consistent, and the worst outcome is one red PR run that a re-run fixes. The post-section drift re-probe covers unserialized runs (#7964).

### Phase 4 — `.github/workflows/dev-ledger-reconcile.yml`

- **Triggers:** `workflow_dispatch` with inputs `pr` (string, required, `description: "PR number whose applied-but-unmerged migrations to discard on dev, e.g. 8605"`), `execute` (boolean, default `false`, description "false = dry run"), `allow_cascade` (boolean, default `false`, description "allow a .down.sql containing CASCADE while another branch's rows were applied later — dry run first"); `pull_request_target: { types: [closed], branches: [main] }`.
- **Top-level `permissions: contents: read`.** Job permissions: `contents: read`, `pull-requests: read`, `issues: write` (audit comment and issue; `lint-workflow-issue-write-scope.py`).
- **No concurrency group** (the mutex serializes writers; a repeated run is a CAS no-op).
- **Job `if:`:** `(github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main') || (github.event_name == 'pull_request_target' && github.event.pull_request.merged == false && github.event.pull_request.head.repo.full_name == github.repository)`. `timeout-minutes: 15`.
- **Steps:**
  1. `actions/checkout` (pinned SHA, as elsewhere) with NO `ref:` (main for both events), `fetch-depth: 1`, `persist-credentials: false`. (The writer does its own blobless fetches into the owner repo; the checkout only supplies main's scripts.)
  2. Install the Doppler CLI (pinned action, as in `tenant-integration.yml`).
  3. *Reconcile* (`id: reconcile`): env `DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_DEV_SCHEDULED }}`, `GH_TOKEN: ${{ github.token }}`, `PR` (event number or `inputs.pr`), `EXECUTE` (`inputs.execute`, or `true` on `pull_request_target`), `ALLOW_CASCADE` (`inputs.allow_cascade`, or `false` on `pull_request_target`), `EVENT_NAME` — all via `env:`, never interpolated into `run:`. Build argv in bash (`--execute` when `EXECUTE == true`; `--allow-cascade` when `ALLOW_CASCADE == true`; `--require-closed` when `EVENT_NAME == pull_request_target`), run `doppler run -p soleur -c dev_scheduled -- bash apps/web-platform/scripts/dev-ledger-reconcile.sh --pr "$PR" --repo "$GITHUB_WORKSPACE" --base-branch main …`, capture rc and output to a file, append it to `$GITHUB_STEP_SUMMARY`, expose `rc`, `eligible` and `ledger_only` as step outputs (parsed from the `ledger-discard:` line with numeric validation), and fail the step on rc ≠ 0.
  4. *Audit comment* (`if: always() && steps.reconcile.outcome != 'skipped' && (steps.reconcile.outputs.rc != '0' || steps.reconcile.outputs.eligible != '0')`): `gh api "repos/$GITHUB_REPOSITORY/issues/$PR/comments" -F body=@<file>` (REST, not `gh pr comment`'s GraphQL path), where the file is built with `{ printf …; } > file` (no heredoc): actor, event, run URL, mode (dry-run/executed), rc, the `would-discard`/`discarded`/`ledger-discard:` lines, the ledger-only residue list, and the schema-cache note. A failed post prints `::warning::` naming the rc (never `|| true` silence).
  5. *Action-required issue* (`if: always() && github.event_name == 'pull_request_target' && (steps.reconcile.outcome == 'failure' || steps.reconcile.outputs.ledger_only != '0')`): `gh issue create` labelled `action-required`, `domain/engineering`, `priority/p2-medium` (all three verified to exist), titled `dev ledger: close-time reconcile for PR #<N> needs attention`, body built with `{ printf …; } > file`: the run URL, the measured outcome (the `ledger-discard:` line or the last `::error::` line, verbatim — no inferred cause), the residue list if any, and the dry-run-first commands (`gh workflow run dev-ledger-reconcile.yml --ref main -f pr=<N>`, then `-f execute=true`, plus `-f allow_cascade=true` only when the refusal line names CASCADE). Before creating, search open issues for the exact title and comment on the existing one instead of opening a duplicate. This is the only alert channel for the unattended path: it reaches operator-digest, and the probe annotation points to it.
- **Never:** `doppler … -c prd`, any `DOPPLER_TOKEN_PRD*` secret, `ref: …head…` on checkout, or `${{ github.event.* }}`/`${{ inputs.* }}` inside a `run:` body.

### Phase 5 — ADR-061 amendment, learning pointer, #8521 archive

1. Append `## Amendment 2026-09-23 (#8605, #8606): closed-PR ownership and a dev reconcile path` to ADR-061 (Status: Accepted). Context: closed-unmerged branches kept rows in-flight forever; the only discard route was a hand-run SQL session. Decision: (1) the `closed` verdict, bound to the PR's head commit, a warning for 24 h after close and blocking after — the grace is sized so a refused or unfired close-time reconcile surfaces as an `action-required` issue and a scheduled-probe Sentry event before it can red main; (2) the classifier's GitHub read (`pull-requests: read`, lookup only for fresh owners, fail-closed) — this supersedes the previous amendment's "No GitHub API, no new permissions" sentence; (3) **DC-1**: `dev-ledger-reconcile.yml` writes to the shared DEV ledger and schema, never prd, under the mutex, CAS per row, triggered on same-repo close-unmerged and by dispatch from main; authorization boundary = repo write access (the same boundary that already lets a PR's CI apply its SQL to dev); audit = PR comment + job summary + an `action-required` issue on refusal or residue; the writer is its own file that sources the read-only guard, so the guard carries no write path; a `.down.sql` without its own transaction handling is required, and one containing `CASCADE` is refused while a foreign unmerged row was applied later unless the dispatcher passes `allow_cascade`. Rejected alternatives (additions): `pull_request: closed` (runs the PR-merge ref's workflow copy; a closed PR's branch may predate the workflow); dispatch with `--ref <branch>` (runs the branch's YAML, and branches that predate the workflow cannot be dispatched at all); refusing every row that has no `.down.sql` (the operator's direction is "apply the `.down.sql` if present, delete the row"; the residue is disclosed and filed instead); a warning-only `closed` verdict with dispatch-only reconcile (leaves closed PRs' rows unowned indefinitely); an audit table on dev (a migration that also lands on prd). Consequences: closing a migration PR unmerged discards its dev rows within minutes; a refused discard files an issue and turns blocking after 24 h; PRs closed by a `GITHUB_TOKEN` workflow fire no event and rely on the grace; a PR closed with "delete branch" still has no holder, so its rows read `orphan` (blocking) until the close-time run discards them — unchanged from the previous amendment, now bounded by minutes; the classifier depends on GitHub's API on the authoritative surfaces.
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

```yaml
liveness_signal:
  what: "ledger-discard: <executed|dry-run|nothing to do|skipped> summary line + PR audit comment per reconcile run with rows; ledger-classify: … closed=C on every authoritative probe"
  cadence: "per same-repo PR closed unmerged, per dispatch, per push to main, and per scheduled drift-probe run"
  alert_target: "action-required GitHub issue on a failed/refused or residue-leaving close-time reconcile; Sentry event per blocking class (now including closed) on the scheduled probe; red required check on main after the 24 h grace"
  configured_in: ".github/workflows/dev-ledger-reconcile.yml, .github/actions/dev-migration-drift-probe/action.yml"
error_reporting:
  destination: "GitHub Actions ::error:: annotations + job summary; action-required issue for the unattended close-time path; Sentry (scheduled probe) for blocking ledger classes"
  fail_loud: true
failure_modes:
  - mode: "PR-state lookup fails (API outage, token scope missing, malformed JSON)"
    detection: "classifier exits 2; probe prints ledger-classify: UNCLASSIFIED (rows=… rc=2)"
    alert_route: "red main run; Sentry on the scheduled surface"
  - mode: "close-time reconcile refuses the run (transactional or non-transactional-only down body, CASCADE with a later foreign row, fork, ownership)"
    detection: "dev-ledger-reconcile.sh exits 1 with a named ::error::; the PR audit comment carries it"
    alert_route: "action-required issue with the dry-run-first commands; after 24 h main's probe reports the row as closed (blocking)"
  - mode: "dev-suite mutex not acquired within 600 s (contended / unavailable)"
    detection: "dev-ledger-reconcile.sh exits 2 before any write: could not hold the dev-suite mutex (<banner token>); nothing was changed"
    alert_route: "action-required issue (close-time) or the dispatcher's red run"
  - mode: "a down body fails or the CAS matches zero rows"
    detection: "psql unit rolls back; dev-ledger-reconcile.sh exits 1 naming the file and the rows already committed"
    alert_route: "action-required issue / red dispatch run; residual rows reappear in the next probe"
  - mode: "ledger-only discard leaves schema residue"
    detection: "::warning:: per row naming the file; ledger_only > 0 in the summary"
    alert_route: "action-required issue listing the residue files"
  - mode: "close event never fires (PR closed by a GITHUB_TOKEN workflow)"
    detection: "probe reports closed (warning) with the PR number and hours since close"
    alert_route: "blocking after 24 h with the dispatch command; Sentry on the scheduled surface"
  - mode: "run-migrations gate regresses to cwd-relative"
    detection: "run-migrations-unmerged-gate.test.ts apps/web-platform positive control and collision cases fail in CI"
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

Amend **ADR-061** (append-only; new section dated 2026-09-23, issues #8605/#8606) — decision: closed-PR rows are not in-flight (commit-bound `closed` verdict, warning for 24 h then blocking), the classifier reads PR state with `pull-requests: read`, and DC-1: a base-branch reconcile workflow may write to the shared DEV ledger and schema (discard only, CAS, mutex-held, never prd). This is Phase 5 step 1, an in-scope task. No new ADR number is claimed, so there is no ordinal to collide.

### C4 views

No C4 impact. Checked against all three model files (`model.c4` 831 lines, `views.c4`, `spec.c4`):

- **Actors:** `founder` (operator, dispatches) and `contributor` (untrusted fork PR author). `contributor`'s description — PR-head code runs only under `pull_request` isolation, never in a privileged consumer — stays true: the new `pull_request_target` job excludes fork PRs and executes no PR-head code.
- **Systems:** `github` (CI) is modeled; the `supabase` database element is the product database, and the model carries no dev-project element and no `github -> supabase` edge even for the existing CI dev apply and prd migrate paths. This change adds a CI→dev write of the same class as `tenant-integration.yml`'s existing apply, so it introduces no element or relationship the model represents today. GitHub REST reads from CI are internal to `github`.
- **Counts:** the work phase runs `bash plugins/soleur/test/c4-count-parity.test.sh` (a new workflow file could move a workflow count in edge prose) and the C4 syntax/render tests if any `.c4` file changes. Recorded as AC13.

### Sequencing

The amendment describes the shipped state; nothing is soak-gated.

## Guard Contract

### Guard 1 — run-migrations gate is cwd-independent

**Property.** For every forward migration filename the runner globs, the unmerged-apply verdict and the coexists-with listing are identical whether `run-migrations.sh` is invoked from the repository root or from `apps/web-platform`.

**Assembly.** The chokepoint is every `git` call in `run-migrations.sh` that takes a repository-relative path: exactly the per-file gate `ls-tree` and the per-prefix collision `ls-tree` (the other five `ls-tree` mentions are comments). `git fetch` (no path) and `git hash-object "$migration_file"` (absolute path) are outside the property.

**Mutation matrix.**

| # | Mutation (to the SUT) | Must turn RED |
|---|---|---|
| G1-M1 | Revert the gate pathspec to the bare `apps/web-platform/…/$filename` | `apps/web-platform` positive control (merged file warned "not on origin/main") |
| G1-M2 | Revert only the collision-listing pathspec | `apps/web-platform` collision case (no `coexists-with: 053_append_kb_sync_row_rpc.sql`) |
| G1-M3 | Anchor with `:(top)` but switch the collision pipeline off `basename` (use the raw ls-tree path) | `apps/web-platform` collision case (paths print cwd-relative under `:(top)`) |
| G1-M4 | Anchor the gate on an absolute filesystem path (`$SCRIPT_DIR/../supabase/…`) instead of a tree path | root and subdir gate-blocks cases (a temp-dir synthetic name would then be judged against the wrong path) |

**Harness rows.** H1: remove the `cwd` argument from `runScript()` so every case runs from the root → the RED run recorded before the fix no longer fails (checked once, recorded in the PR body). Must-PASS non-canonical input: the same cases from the repo root (P2), and a synthetic filename absent from main still blocked from the subdirectory without the ack.

**Anchor.** No stored value; the guard compares live `git` output.

### Guard 2 — closed-owner rows are not in-flight, and the classifier stays fail-closed

**Property.** `classify-missing` emits `in-flight` for a missing row only if at least one fresh holder branch has an open PR, has no PR, or has a closed PR whose head commit is not the branch's current tip; when every fresh holder's latest PR is closed at the branch's tip, the verdict is `closed` with the PR number and hours since close; any PR-state lookup it cannot complete exits 2 (probe: UNCLASSIFIED, blocking). The probe treats `closed` as a warning under 24 h and blocking from 24 h.

**Assembly.** Chokepoint: `classify_row`'s fresh-state walk — every `in-flight` emission passes through `branch_pr_state`, the only GitHub caller on this path. Consumers: the probe's verdict `case` (`closed` arm, age split), its blocking aggregation (error block, fail condition, `ledger_classes`/Sentry). Callers that must pass the token: the two probe steps in `tenant-integration.yml` and the one in `scheduled-dev-migration-drift.yml`, and each job's `pull-requests: read`.

**Mutation matrix.**

| # | Mutation | Must turn RED |
|---|---|---|
| G2-M1 | `branch_pr_state` always returns `open` | closed-at-tip holder → expects `closed` |
| G2-M2 | A non-zero `gh` exit is swallowed and read as `none` | gh-fails case expects rc=2 and no verdict lines |
| G2-M3 | Second member: check only the first (lexically smallest) candidate | two holders `a-closed` + `b-open` → expects `in-flight … b-open`; and `a-open` + `b-closed` → `in-flight … a-open` |
| G2-M4 | Probe ignores the age field | `closed` with `vh=2` → expects a warning and exit 0; with `vh=30` → expects exit 1 and an `::error::` line |
| G2-M5 | Stop at the exact tier: a closed exact-name holder ends the walk | exact holder closed + slug holder open → expects `in-flight … slug` |
| G2-M6 | Dispatch: the lookup is skipped entirely | fresh-holder case asserts the fake gh's call log names that branch's `head=` |
| G2-M7 | Probe routes blocking `closed` to the warning list | probe case with a stubbed `closed … 30` verdict expects exit 1 and `closed` in the Sentry class list |
| G2-M8 | A caller stops passing `github-token`, or a job drops `pull-requests: read` | static wiring cases over all three probe call sites |
| G2-M9 | Drop the `head.sha == branch tip` binding | branch pushed after its PR closed (tip ≠ PR head.sha) → expects `in-flight`, not `closed` |
| G2-M10 | Memo kept in a shell array | two rows owned by the same branch → the fake gh's call log shows exactly one call for that branch |
| G2-M11 | Summary field inserted mid-line | summary case expects the line to end with `closed=C` |

**Harness rows.** H1: a fake gh that ignores the `head=` parameter and answers the same for every branch → G2-M3's branch-specific fixtures turn RED. H2: a fake gh missing from PATH → the laziness case (zero calls when no fresh holder) must still PASS and G2-M6 must turn RED. Must-PASS non-canonical: a branch with no PR at all stays `in-flight` (today's behaviour); a branch whose only PR MERGED at its tip yields `closed` with neutral text; every pre-existing in-flight case still passes under the default fake (`[]`).

**Anchor.** The 24 h split is a literal in `action.yml`, pinned by G2-M4's two ages.

### Guard 3 — `dev-ledger-reconcile.sh` writes only the named PR's rows, only on dev, only under the mutex, atomically

**Property.** `dev-ledger-reconcile.sh --execute` deletes the ledger row (F, B) only if F is not on the base tip and never in base history, B is a 40-hex blob F carried in a first-parent commit of `base..refs/pull/N/head`, no independent fresh branch holds F at B, `DOPPLER_ENVIRONMENT=dev`, and `dev-suite-mutex.sh acquire` printed `DEV_SUITE_MUTEX_ACQUIRED`; each delete is a one-row compare-and-set in the same single transaction as the paired down body; no run writes anything when any eligible row's down body keeps a transaction statement, holds a non-transactional statement, or holds `CASCADE` while a foreign row was applied later (without `--allow-cascade`).

**Assembly.** The writer file is the only file in this area that issues a write: the guard file contains exactly one `psql` invocation and it runs `LEDGER_SQL`, pinned by a static case. Inside the writer every database write flows through one function (`apply_discard_unit`: one `psql --single-transaction -f` per row). Eligibility and all refusals are computed before the first write. The environment check runs at entry before any `psql`; the mutex acquire precedes the ledger read. The only CI caller is `dev-ledger-reconcile.yml`.

**Mutation matrix.**

| # | Mutation | Must turn RED |
|---|---|---|
| G3-M1 | Drop the "never in base history" test | F was on main once (renamed there) → expects it ineligible, zero writes |
| G3-M2 | Drop the (F, B) ∈ PR-history test | another PR's same-named file at another blob → expects it ineligible |
| G3-M3 | Second member: evaluate refusals inside the write loop | three eligible rows, the LAST (lowest filename, executed last) has a CONCURRENTLY down → expects zero write calls in the psql log |
| G3-M4 | Split CAS and down body into two psql calls | unit-payload case asserts exactly one psql write call per row, carrying both |
| G3-M5 | REORDER: read the ledger before `acquire` | call-order case (fake mutex and fake psql append to one shared log) expects `acquire` before the ledger SELECT |
| G3-M6 | Remove the `DOPPLER_ENVIRONMENT` check | `DOPPLER_ENVIRONMENT=prd` → expects rc=2 and zero psql calls |
| G3-M7 | Ignore the mutex banner | fake mutex prints `DEV_SUITE_MUTEX_CONTENDED_PROCEEDING` → expects rc=2, zero writes, and a `release` call |
| G3-M8 | Pair the down body with the commit that last CHANGED F instead of the last commit where F == B | author edits only `F.down.sql` after apply → expects the NEWER down body in the payload; author edits F and `F.down.sql` after apply → expects the OLDER one |
| G3-M9 | Skip the blob integrity check | fake gh blob content whose hash ≠ id → expects rc=2 |
| G3-M10 | Drop the CASCADE refusal | down body with `DROP … CASCADE` + a foreign unmerged row applied later → expects rc=1, zero writes; the same body with no later foreign row → runs (must-PASS); with `--allow-cascade` → runs |
| G3-M11 | Second member for CASCADE: check only the FIRST later row | two later rows, the first on main and the second foreign → expects rc=1 |
| G3-M12 | A write path appears in the guard file | static case: the guard contains exactly one `psql` invocation and it runs `LEDGER_SQL` |
| G3-M13 | Library mode leaks the dispatch | sourcing with `DLP_AS_LIBRARY=1` prints nothing and does not exit; running without it still dispatches |
| G3-M14 | The writer's EXIT trap is replaced by the guard's | a refused run after `acquire` still logs a `release` call AND removes the owner repo temp dir |
| G3-M15 | Drop the BEGIN/COMMIT normalization, or widen it to strip mid-body statements | wrapped body → runs with the wrapper stripped; body with a mid-body `COMMIT;` → rc=1, zero writes |
| G3-M16 | `--require-closed` ignores a reopen | fake gh reports `open` on the in-mutex re-read → expects `skipped (pr=N reopened)`, zero writes |

**Harness rows.** H1: the fake psql stops recording `-f` payloads → an instrument self-test that a known fixture write appears in the log turns RED before any row. H2: a fake mutex that always prints ACQUIRED → G3-M7 turns RED. Must-PASS non-canonical: a closed PR whose branch was deleted (only `refs/pull/N/head` in the fixture origin) is reconcilable; a row whose applied blob equals the current head blob (in sync) is eligible; a row with no `.down.sql` is discarded ledger-only with the residue `::warning::`; a PR whose history carries no migration exits 0 with `nothing to do` and no mutex call; dry-run makes zero write calls and no mutex call.

**Anchor.** No stored value.

### Guard 4 — reconcile workflow wiring

**Property.** `dev-ledger-reconcile.yml` runs only main's copy of the writer, never checks out or executes PR-head code, never holds a non-dev Doppler token, never runs for a fork PR or a dispatch off `main`, and never interpolates event or input text into a `run:` body.

**Assembly.** The workflow's `on:`, the job `if:`, the checkout step's `with:`, every `secrets.*` reference, every `run:` body. Checked by static cases in `dev-ledger-parity.test.sh` (`wf_static`/`wf_mutant`) against the parsed YAML with comments stripped, not bare tokens.

**Mutation matrix.**

| # | Mutation | Must turn RED |
|---|---|---|
| G4-M1 | Checkout gains `ref: ${{ github.event.pull_request.head.sha }}` | checkout-ref case |
| G4-M2 | Any `DOPPLER_TOKEN_PRD*` secret, or `-c prd`, appears | secret-scope case |
| G4-M3 | The fork clause is dropped from `if:` | if-clause case |
| G4-M4 | The dispatch clause loses `github.ref == 'refs/heads/main'` | if-clause case |
| G4-M5 | `${{ inputs.* }}` or `${{ github.event.* }}` appears inside a `run:` body | injection case |

**Harness rows.** H1: the YAML parse returns zero jobs or zero steps → the cases fail on "0 steps parsed", not pass. Must-PASS non-canonical: a comment line mentioning `ref:` or `prd` does not trip the checks.

**Anchor.** No stored value.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `run-migrations-unmerged-gate.test.ts` runs every case from BOTH the repo root and `apps/web-platform`, plus the collision case from both; the PR body records that the `apps/web-platform` positive control and collision case FAILED before the pathspec change and pass after it, and that G1-M1..M4 each turned the named case RED.
- [ ] **AC2** From the repo root, the pre-existing three cases pass with their assertions unchanged (P2).
- [ ] **AC3** `bash apps/web-platform/scripts/dev-ledger-parity.test.sh` passes with `EXPECTED_CASES` equal to the new exact case count; every Guard 2, 3 and 4 mutation and harness row was run once and turned its named case RED (recorded in the PR body).
- [ ] **AC4** `classify-missing` with a fresh holder whose PR closed at the branch tip prints `closed<TAB><file><TAB><branch><TAB><N><TAB><hours>` and a summary ending `closed=1`; with the fake gh failing it exits 2; with no fresh holder the fake gh's call log is empty; two rows owned by one branch produce one call.
- [ ] **AC5** The probe, fed a `closed` verdict with `fail-on-ledger-drift: true`, exits 0 with a `::warning::` when hours < 24, and exits 1 with an `::error::` block naming the PR number and the dry-run command, with `closed` in the Sentry class list, when hours ≥ 24; with `fail-on-ledger-drift: false` it never calls the classifier.
- [ ] **AC6** `dev-ledger-reconcile.sh` (dry-run) prints `would-discard` lines and `ledger-discard: dry-run (…)` and makes zero psql write calls and zero mutex calls; `--execute` against the fixture writes one single-transaction unit per row in descending filename order.
- [ ] **AC7** `dev-ledger-reconcile.sh` exits 2 with zero psql calls when `DOPPLER_ENVIRONMENT` is not `dev`, and exits 2 with zero writes plus a `release` call when the fake mutex prints `CONTENDED_PROCEEDING` or `UNAVAILABLE`.
- [ ] **AC8** `.github/workflows/dev-ledger-reconcile.yml` passes `bash scripts/lint-workflows.sh .github/workflows/dev-ledger-reconcile.yml` (no new findings), `python3 scripts/lint-workflow-issue-write-scope.py`, `python3 scripts/lint-workflow-step-env-refs.py`, `python3 scripts/lint-workflow-local-action-checkout.py`, and the Guard 4 static cases.
- [ ] **AC9** Repo ratchets green: `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-diagnosis-claims.test.sh` with the highwater unchanged, `bash scripts/battery-tag-authorship.test.sh`, `python3 scripts/lint-shell-capture-exit.py` against its baseline, `bash tests/scripts/test-dev-suite-mutex-wiring.sh`, and the fixture-relative / fixture-dir-operand assertion scans the suite is already enrolled in.
- [ ] **AC10** ADR-061 ends with the new amendment; `git diff origin/main -- <ADR-061>` shows only added lines.
- [ ] **AC11** AC11 of the #8521 plan is ticked with run 35891815286's evidence before the move; both archive-kb runs moved exactly one artifact each via `git mv` (`git log --follow` shows history on the archived paths); `git grep -n -e 'plans/2026-09-23-fix-pr-ci-unmerged-migration-ledger-parity-plan.md' -e 'specs/feat-one-shot-8521-dev-ledger-content-drift'` returns only lines inside `knowledge-base/**/archive/**` and this plan.
- [ ] **AC12** Pre-merge dry look at live dev (read-only): `gh workflow run scheduled-dev-migration-drift.yml --ref feat-one-shot-8605-8606-dev-reconcile` runs this branch's classifier with the token; its log shows `ledger-classify:` or `No dev-vs-main migration drift detected.`, and no `UNCLASSIFIED`. Any `closed` line it prints (with its hours) is listed in the PR body, with the post-merge discard it needs.
- [ ] **AC13** `bash plugins/soleur/test/c4-count-parity.test.sh` passes (no `.c4` edit expected).
- [ ] **AC14** The PR body carries `Closes #8605` and `Closes #8606`, the DC-1 decision sentence, and the AC1/AC3 mutation records.

### Post-merge

- [ ] **AC15** The first push run of `tenant-integration.yml` on main is read with `gh run view <id> --log | grep -e 'ledger-classify:' -e 'No dev-vs-main migration drift detected.'`; no `UNCLASSIFIED` line. Its conclusion is not asserted: it depends on dev state other refs write (`cq-ac-must-not-depend-on-concurrent-sessions`).
- [ ] **AC16** One read-only exercise of the new path: `gh workflow run dev-ledger-reconcile.yml --ref main -f pr=<a closed same-repo PR that applied a migration>` completes and prints `ledger-discard: dry-run (…)` or `ledger-discard: nothing to do (…)`; when rows were listed, the audit comment is on that PR.
- [ ] **AC17** #8605 carries a closing comment recording DC-1 (CI writes to the shared DEV ledger/schema via `dev-ledger-reconcile.yml`, never prd; ADR-061 amendment link).

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CI and dev-database tooling. The load-bearing risks are (1) main-red from a new blocking verdict (mitigated by the close-time discard, the 24 h grace, the action-required issue, and AC12's pre-merge look at live dev), (2) a writer on shared dev (mitigated by a separate writer file, an in-process env check, a strict mutex with a 600 s wait, one single-transaction unit per row with CAS, all-or-nothing refusals for transactional/non-transactional/CASCADE downs, dry-run default on dispatch, a reopen re-check), and (3) the prd apply path edit (two pathspecs, fail-closed, byte-equivalent from the root). No product, marketing, legal, finance, sales, support or operations surface: no UI, no user data, no vendor, no spend. Plan review ran DHH, Kieran, code-simplicity and CTO (devex); their findings are folded into this revision (see `## Plan Review Revisions`).

Product/UX Gate: NONE (no UI-surface file in Files to Create/Edit).

## Test Scenarios

- Gate from `apps/web-platform`: merged file silent; synthetic unmerged file blocked without the ack; warned with it; collision listing sees main's `053_*`. Same from the root.
- Classifier: open / none / closed at tip / closed then pushed (in-flight) / merged-only / two holders in both orders / exact-closed + slug-open / gh fails / non-JSON gh output / no fresh holder (no gh call) / two rows one branch (one call) / `GITHUB_REPOSITORY` unset with a fresh holder (exit 2) / pre-existing in-flight cases under the default fake.
- Probe: `closed` under 24 h → warning; ≥ 24 h → blocking with Sentry class; malformed `closed` line (non-numeric PR or hours) → UNCLASSIFIED; summary line ends with `closed=`.
- Writer: dry-run; nothing-to-do; execute single row; multi-row descending order; main-history name ineligible; other PR's blob ineligible; independent holder ineligible, inherited holder not; deleted-branch PR via `refs/pull/N/head`; head-sha mismatch → rc 2; down pairing after a down-only edit and after a forward+down edit; no down → ledger-only with residue warning; wrapped BEGIN/COMMIT stripped; mid-body COMMIT refused; CONCURRENTLY refused; CASCADE with/without a later foreign row and with `--allow-cascade`; blob hash mismatch; env ≠ dev; mutex contended/unavailable; reopened PR skipped under `--require-closed`; a failing unit reports committed rows; library-mode sourcing runs nothing; EXIT trap releases and cleans up.
- Workflow static: checkout ref, secret scope, fork clause, dispatch-on-main clause, no interpolation in `run:`.

## Plan Review Revisions

Panel: `soleur:engineering:review:dhh-rails-reviewer`, `soleur:engineering:review:kieran-rails-reviewer`, `soleur:engineering:review:code-simplicity-reviewer`, `soleur:engineering:cto` (devex lens); plus the Step 4.5 advisor consult. Applied (mechanical):

- Kieran P1: down bodies fetched with the raw media type (`@base64d` rejects GitHub's wrapped base64 — reproduced); non-transactional statements (`CONCURRENTLY`, `VACUUM`, `ALTER SYSTEM`, `CREATE DATABASE`) refused up front; writer mutex wait raised to 600 s with its own state dir.
- Kieran + DHH + CTO + code-simplicity converged on the blocking-after-1 h risk (a refused or unfired close-time run would red main within the hour): grace raised to 24 h, split by age in the probe, with an `action-required` issue as the pre-block signal. `closed` stays blocking after grace (fail-closed), so the operator's direction holds.
- Kieran P2: census and summary-line consumers fixed (summary field appended, two exact-string cases listed, fake gh for existing in-flight cases); memo moved to a file (subshell per row); `--paginate` dropped; down pairing walks first-parent trees (a `--raw` walk misses down-only edits); `DLP_AS_LIBRARY` instead of a `BASH_SOURCE` main-guard; `NOTIFY pgrst` dropped (#4285); reopened PRs skipped inside the mutex; REST comment API instead of `gh pr comment`; stacked-branch behaviour stated.
- CTO P1: a single wrapping `BEGIN;`/`COMMIT;` pair is normalized away, so wrapped down files are self-service; annotation leads with the dry-run command and points at the issue; ledger-only residue files an issue; dispatch inputs carry descriptions.
- DHH/code-simplicity cuts: `--file`/`files`, the touched-migrations pre-check (replaced by the writer's own git-only early exit), the concurrency group and G4-M6, the workflow-level Doppler assertion, the ops email, the mutant-copy control and census; trap-composition row added (G3-M14).

Taste / User-Challenge findings persisted to `knowledge-base/project/specs/feat-one-shot-8605-8606-dev-reconcile/decision-challenges.md`: warning-only `closed` with dispatch-only reconcile (code-simplicity; User-Challenge — not applied); scheduled probe auto-dispatching the reconcile (CTO; not applied); a separate writer test suite (CTO; not applied); `--full-tree` instead of `:(top,literal)` (code-simplicity; not applied, convention kept).

## Sharp Edges

- `git ls-tree` under `:(top)` prints paths relative to the CWD. Anything that consumes the path (not the basename) must add `--full-name`; the collision code uses `basename`, which is why G1-M3 exists.
- The subdirectory runs of `run-migrations.sh` need `SUPABASE_ACCESS_TOKEN=""` in their env, exactly like the existing `runScript()` (the reload hook runs on every exit path).
- `gh api -X GET … -f key=value` is required: without `-X GET`, `-f` turns the call into a POST.
- The owner repo runs with `GIT_NO_LAZY_FETCH=1` and has no blob contents: down bodies come from the blobs API with `Accept: application/vnd.github.raw+json`, never from `git show` in the owner repo and never through `jq @base64d`.
- `classify_row` runs in a subshell per row; any state it must share across rows lives in a file under `CLEAN`.
- Portability (the scripts also run on operator laptops): ISO timestamps become epochs inside `jq` (`fromdateiso8601`), never `date -d`; network calls use the script's existing `TIMEOUT_BIN` (`timeout`→`gtimeout`→bare) pattern.
- PR-state evidence is keyed on the commit (`head.sha` == branch tip), not the branch name; a name-only lookup would let an old closed PR condemn a re-pushed or recreated branch.
- Every value that reaches an annotation (`::error::`, `::warning::`, `::notice::`) or a tab-delimited verdict line is a whitelisted filename, a validated branch label, a 40-hex sha or an integer; API strings (titles, bodies, logins) never do.
- A new blocking verdict on the authoritative probe can red main 24 h after merge if dev already holds closed-owner rows — AC12 measures that before merge.
- Every fixture `git fetch`/`clone`/`init` in the suite needs `--no-tags` where it fetches (battery-tag-authorship), and every `git -C` operand must pass the suite's `assert_fixture_dir`.
- Run `npx markdownlint-cli2` on this plan and `tasks.md` before handing off; lefthook lints both at the first work-phase commit.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
