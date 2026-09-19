# Tasks: retire the #6617 doublefire probe and drop the 14 dark-Inngest tables

Derived from `knowledge-base/project/plans/2026-09-19-chore-retire-doublefire-probe-drop-dark-inngest-tables-plan.md` after a five-lens review panel. Two commits (A, B) with a three-run dispatch sequence between them.

## Phase 1: Readiness (read-only, recorded in the PR body)

- [ ] 1.1 Doppler: `INNGEST_CUTOVER_FLIP` == `done`; `INNGEST_POSTGRES_URI` username == `postgres.pigsfuxruiopinouvjwy` (username only, never the URI)
- [ ] 1.2 Run the #6488 probe from the terminal → exit 1, `14/14` (the pre-state)
- [ ] 1.3 Run the #6617 probe locally → exit 0, contrasting with sweeper run 35465233346
- [ ] 1.4 `gh api repos/jikig-ai/soleur/collaborators/deruelle/permission` → `admin` under the operator token

## Phase 2: Commit A — the transient drop workflow and the verdict-filter fix

- [ ] 2.1 Rewrite `.github/workflows/apply-inngest-rls-dev.yml` into the dispatch-only drop
  - [ ] 2.1.1 `workflow_dispatch` only; inputs `mode` (choice, default `dry-run`) and `reason`
  - [ ] 2.1.2 Job-level pinned `PROJECT_REF`/`PROJECT_NAME`; identity preflight and anti-exfil helpers copied verbatim; `--max-time 30` retained
  - [ ] 2.1.3 `NAMES=( … )` as the single source for both the catalog predicate and the DROP list
  - [ ] 2.1.4 Blocking chain: identity 200 + `.name == soleur-dev`; then `tables_present == 14` and `posture_ok == 14`
  - [ ] 2.1.5 Reported-only counters (`dependents_outside`, `foreign_sessions`, `runs`, `events`) plus the per-table `relname, relnamespace, reltuples, n_live_tup` listing
  - [ ] 2.1.6 Drop arm echoes the exact statement before the POST; no `CASCADE`, no `IF EXISTS`; `SET lock_timeout TO '10s'`; post-verify requires 0
  - [ ] 2.1.7 `LIFETIME: TRANSIENT` header naming its own retirement set
- [ ] 2.2 `scripts/lib/trusted-verdict.sh` (its `gh api` carrying `--disable` first and `--noproxy '*'` — Rule D reaches `scripts/lib/`)
- [ ] 2.3 `scripts/lib/trusted-verdict.test.sh` (the lib's own matrix, outliving any consumer)
- [ ] 2.4 `scripts/followthroughs/concierge-strand-754ee124-5733.test.sh`, committed `100755`
- [ ] 2.5 Source the lib from both live consumers (`concierge-strand-754ee124-5733.sh`, `cpx22-invoice-reconcile-7431.sh`) and transiently from the 6617 probe
- [ ] 2.6 6617 probe prints `observed authorAssociation=…` as its **last** stderr line (600-byte tail)
- [ ] 2.7 Authoring surfaces: `ship/SKILL.md` Step 3.5.B, `followthrough-stub-template.sh`, new `lint-followthrough-varq-ban.sh` rule
- [ ] 2.8 Delete `scripts/followthroughs/betterstack-quota-verdict-5105.sh`
- [ ] 2.9 `EXPECTED_TOTAL` floor in the shape guard, with an inline comment naming the measurement date and counts
- [ ] 2.10 Register both new test files in `scripts/test-all.sh` (no glob covers `scripts/followthroughs/`)
- [ ] 2.11 Local green: shape guard, lib test, both probe harnesses, varq-ban, trace-credential lint, exec-bit test, actionlint, Guard 1 and Guard 2 matrices
- [ ] 2.12 Commit, push, record `SHA_A`

## Phase 3: Dispatch (each dispatch arms a Monitor in the same turn)

- [ ] 3.1 Sweeper `dry_run=true` → log contains `issue #6617: DRY_RUN — would close with verdict=PASS`; read the `observed authorAssociation=` line
- [ ] 3.2 If the permission endpoint 403s → take the CODEOWNERS fallback, push, re-run 3.1
- [ ] 3.3 Quiesce: zero in-flight runs of `apply-inngest-rls-dev.yml`
- [ ] 3.4 Drop `mode=dry-run` → `head_sha == SHA_A`; read the 14 per-table rows before authorising anything
- [ ] 3.5 On `Unexpected inputs` → carry the mode in `reason`; re-dispatch; record which arm ran
- [ ] 3.6 Drop `mode=drop` → echoed statement in the log, `tables_remaining=0`
- [ ] 3.7 Re-assert quiesce
- [ ] 3.8 Terminal: the #6488 probe → exit 0
- [ ] 3.9 Capture the three run URLs and the echoed statement

## Phase 4: Commit B — retire, record, close

- [ ] 4.1 Delete the drop workflow, `0002`, `anon-probe.sh`, `inngest-rls-mutation.test.sh`, both probes, both lint-baseline entries
- [ ] 4.2 `git mv` the shape guard; strip the `dev_*` block **with** `argv[2]`, the `dev =` load, `DEV_WF=` and the two dev asserts (else 13 of 15 prd probes red)
- [ ] 4.3 `inngest-rls.test.sh`: hoist the `ALLOW_14` cardinality guard out of `profile_0002` first, then delete `profile_0002`, `SQL_0002`, the two cross-file checks and the newly dead helpers
- [ ] 4.4 `infra-validation.yml`: drop the paths entry, rename the shape-guard step, delete the mutation step
- [ ] 4.5 Both registration guards; `fixture-relative-assert.baseline.txt`; `lint-supabase-deprecated-endpoints.sh` allowlist (rename entry is mandatory — `UNPINNED-HOST`)
- [ ] 4.6 Re-measure `lint-supabase-deprecated-endpoints.highwater` at this commit and write the provenance line naming the departed call sites
- [ ] 4.7 Sweep the dangling prose references in surviving files (prd workflow header, `0001` RAISE message, advisor scan, CODEOWNERS, scrub-pat "FOUR places", rehearsal comment, 7431 comment)
- [ ] 4.8 ADR-100 addendum (the URL-bearing record); ADR-030 amendment-log pointer; `expenses.md` pointer
- [ ] 4.9 `followthrough-convention.md` rule citing the measured value; learning item 19 correction
- [ ] 4.10 De-enrol both trackers (label + directive block)
- [ ] 4.11 Re-run every suite whose population changed, including `--check-highwater`
- [ ] 4.12 PR body: Changelog, `Closes #6617`, `Closes #6488`, the dispatch arm taken, three run URLs, echoed DROP in `<details>`

## Phase 5: Post-merge

- [ ] 5.1 Merge-commit workflows green; `infra-validation` green with the renamed suite in its log
- [ ] 5.2 `git ls-files` of the seven retired paths → empty
- [ ] 5.3 Sweeper dispatch on `main` → names neither tracker (scoped to the two, not to run colour)
- [ ] 5.4 Ad-hoc Management-API read → 0 of the 14 names in `pg_class`
