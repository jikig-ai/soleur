# Tasks: retire the #6617 doublefire probe and drop the 14 dark-Inngest tables

Derived from `knowledge-base/project/plans/2026-09-19-chore-retire-doublefire-probe-drop-dark-inngest-tables-plan.md` after a five-lens review panel. Two commits (A, B) with a three-run dispatch sequence between them.

## Phase 1: Readiness (read-only, recorded in the PR body)

- [x] 1.1 Doppler: `INNGEST_CUTOVER_FLIP` == `done`; `INNGEST_POSTGRES_URI` username == `postgres.pigsfuxruiopinouvjwy` (username only, never the URI)
- [x] 1.2 Run the #6488 probe from the terminal → exit 1, `14/14` (the pre-state)
- [x] 1.3 Run the #6617 probe locally → exit 0, contrasting with sweeper run 35465233346
- [x] 1.4 `gh api repos/jikig-ai/soleur/collaborators/deruelle/permission` → `admin` under the operator token

## Phase 2: Commit A — the transient drop workflow and the verdict-filter fix

> **Two plan deviations, both forced, both recorded in the commit-A message.**
> (a) The shape guard's rename + dev-block strip and their registration sites moved from Phase 4
> into Phase 2: rewriting the workflow reds 15 of the guard's 40 assertions immediately (measured),
> so commit A cannot be green without them.
> (b) `check_workflow_allowlist_matches` was planned for deletion in Phase 4; it is REPOINTED at the
> new workflow's `NAMES` array instead, because the property it asserts got stronger — `NAMES` is the
> single source for both the catalog predicate and the `DROP TABLE` list.

- [x] 2.1 Rewrite `.github/workflows/apply-inngest-rls-dev.yml` into the dispatch-only drop
  - [x] 2.1.1 `workflow_dispatch` only; inputs `mode` (choice, default `dry-run`) and `reason`
  - [x] 2.1.2 Job-level pinned `PROJECT_REF`/`PROJECT_NAME`; identity preflight and anti-exfil helpers copied verbatim; `--max-time 30` retained
  - [x] 2.1.3 `NAMES=( … )` as the single source for both the catalog predicate and the DROP list
  - [x] 2.1.4 Blocking chain: identity 200 + `.name == soleur-dev`; then `tables_present == 14` and `posture_ok == 14`
  - [x] 2.1.5 Reported-only counters (`dependents_outside`, `foreign_sessions`, `runs`, `events`) plus the per-table `relname, relnamespace, reltuples, n_live_tup` listing
  - [x] 2.1.6 Drop arm echoes the exact statement before the POST; no `CASCADE`, no `IF EXISTS`; `SET lock_timeout TO '10s'`; post-verify requires 0
  - [x] 2.1.7 `LIFETIME: TRANSIENT` header naming its own retirement set
- [x] 2.2 `scripts/lib/trusted-verdict.sh`
  - Plan note corrected by measurement: the plan required the lib's credentialed call to carry
    `--disable` first and `--noproxy '*'` because Rule D of `lint-shell-trace-credential-refusal.py`
    drops the `^scripts/lib/` exclusion. Rule D's subject is **`curl`**, and the lib calls `gh api`
    — it never invokes curl — so the flags do not apply and adding them would be a syntax error.
    Verified rather than assumed: `python3 scripts/lint-shell-trace-credential-refusal.py --changed
    --base origin/main` over the committed diff reports `17 scanned file(s), 0 baselined (A/B/C),
    0 baselined (D)`, exit 0.
- [x] 2.3 `scripts/lib/trusted-verdict.test.sh` (the lib's own matrix, outliving any consumer)
- [x] 2.4 `scripts/followthroughs/concierge-strand-754ee124-5733.test.sh`, committed `100755`
- [x] 2.5 Source the lib from both live consumers (`concierge-strand-754ee124-5733.sh`, `cpx22-invoice-reconcile-7431.sh`) and transiently from the 6617 probe
- [x] 2.6 6617 probe prints `observed authorAssociation=…` as its **last** stderr line (600-byte tail)
- [x] 2.7 Authoring surfaces: `ship/SKILL.md` Step 3.5.B, `followthrough-stub-template.sh`, new `lint-followthrough-varq-ban.sh` rule
- [x] 2.8 Delete `scripts/followthroughs/betterstack-quota-verdict-5105.sh`
- [x] 2.9 `EXPECTED_TOTAL` floor in the shape guard, with an inline comment naming the measurement date and counts
- [x] 2.10 Register both new test files in `scripts/test-all.sh` (no glob covers `scripts/followthroughs/`)
- [x] 2.11 Local green: shape guard, lib test, both probe harnesses, varq-ban, trace-credential lint, exec-bit test, actionlint, Guard 1 and Guard 2 matrices
- [x] 2.12 Commit, push, record `SHA_A`

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
- [ ] 4.3 `inngest-rls.test.sh`: hoist the `ALLOW_14` cardinality guard out of `profile_0002` first,
  then delete `profile_0002`, `SQL_0002`, the cross-file check and the newly dead helpers.
  **Hoist verified at work time, so it is not taken on faith:** the guard is
  `if [[ "${#ALLOW_14[@]}" -eq 14 ]]` inside `profile_0002`, and `profile_0001`'s negative-noun loop
  (`for nt in "${ALLOW_14[@]}" users conversations`) consumes the same array. Deleting the profile
  therefore removes the only cardinality check while leaving a live consumer — the array could then
  silently shrink and `profile_0001` would report `ok` over fewer names. Hoist it to top level,
  immediately after the `ALLOW_14=(` declaration.
  Note: commit A left ONE cross-file check, repointed at the drop workflow's `NAMES` array; it goes
  here with the workflow it reads.
- [ ] 4.4 `infra-validation.yml`: drop the paths entry, rename the shape-guard step, delete the mutation step
- [ ] 4.5 Both registration guards; `fixture-relative-assert.baseline.txt`; `lint-supabase-deprecated-endpoints.sh` allowlist (rename entry is mandatory — `UNPINNED-HOST`)
- [ ] 4.6 Re-measure `lint-supabase-deprecated-endpoints.highwater` at this commit and write the provenance line naming the departed call sites
- [ ] 4.7 Sweep the dangling references in surviving files. **The work-list below is
  GREP-ENUMERATED against the live tree at `d5887b050`, not intuited** — the plan's prose
  enumeration (prd workflow header, `0001` RAISE, advisor scan, CODEOWNERS, scrub-pat "FOUR
  places", rehearsal comment, 7431 comment) is a starting hypothesis; these are the actual hits.
  Re-run each grep after the deletions rather than trusting this snapshot.
  - `git grep -nE 'anon-probe' -- . ':!knowledge-base' ':!*.md'`
    - [ ] `.github/workflows/apply-inngest-rls.yml:50` — comment naming `anon-probe.sh` as a dev-only artifact
    - [ ] `scripts/lint-shell-trace-credential-refusal.baseline.txt:17` and `-d.baseline.txt:15`
    - [ ] `scripts/lint-supabase-deprecated-endpoints.sh:18,177` — comments citing `anon-probe.sh:30,55,66`
    - [ ] `apply-inngest-rls-workflow.test.sh` — `prd_ignores_probe` KEEPS its assertion (the property
      is that the `paths:` filter stays narrow, and a re-widening to `**` would match the path again
      whether or not the file exists); the header note added in commit A already says so. Verify, do not delete.
  - `git grep -nE 'inngest-rls-drop-6488' -- . ':!knowledge-base' ':!*.md'`
    - [ ] both trace-credential baselines (`:58` / `:37`)
  - `git grep -nE 'inngest-doublefire-reading-6617' -- . ':!knowledge-base' ':!*.md'`
    - [ ] `scripts/followthroughs/cpx22-invoice-reconcile-7431.sh:65` — comment citing it as precedent
  - `git grep -nE 'inngest-rls-mutation' -- . ':!knowledge-base' ':!*.md'`
    - [ ] `.github/scripts/test/test-infra-suite-registration.sh:114`
    - [ ] `apps/web-platform/infra/run-registered-suites.test.sh:115`
    - [ ] `.github/workflows/infra-validation.yml:1525` (the step) — and its `paths:` entry
    - [ ] `apps/web-platform/infra/supabase-advisor/scan-workflow-mutation.test.sh:16` — comment citing it
    - [ ] `plugins/soleur/test/fixture-relative-assert.baseline.txt:175` — regenerate, do not hand-edit
  - `git grep -nE 'apply-inngest-rls-dev' -- . ':!knowledge-base' ':!*.md'`
    - [ ] `.github/workflows/apply-inngest-rls.yml:54` — "The dev counterpart is …"
    - [ ] `.github/workflows/infra-validation.yml:66,69` — the transitional comment and the `paths:` entry
    - [ ] `apply-inngest-rls-workflow.test.sh:154` — `prd_ignores_devwf`: same disposition as `prd_ignores_probe`
  - [ ] `scripts/lib/scrub-supabase-pat.sh:6` — "inlined in FOUR places"; re-count after the deletions
    (the dev workflow and `anon-probe.sh` were two of them) and write the measured number.
- [ ] 4.8 ADR-100 addendum (the URL-bearing record); ADR-030 amendment-log pointer; `expenses.md` pointer
- [ ] 4.9 `followthrough-convention.md` rule citing the measured value; learning item 19 correction
- [ ] 4.10 De-enrol both trackers (label + directive block)
- [ ] 4.10b De-enrol **#5110** too. Found at work time, not in the plan: #5110 is CLOSED but still
  carries a `<!-- soleur:followthrough script=scripts/followthroughs/betterstack-quota-verdict-5105.sh`
  directive, and commit A deletes that script. `sweep-followthroughs.sh` fails a tracker whose script
  is "missing in repo HEAD", and it runs a closed-set reopen pass — so after merge the directive would
  drive a nightly reopen attempt on #5110. Measured: the closed-set query is
  `closed:>=<today-CLOSED_LOOKBACK_DAYS>` with the default 14 days and #5110 closed 2026-07-24, so it
  is OUT of the window today and this is latent rather than live. De-enrol it anyway — a dangling
  directive whose script does not exist is exactly the cruft this PR exists to remove, and the window
  is a default someone can raise.
- [ ] 4.11 Re-run every suite whose population changed, including `--check-highwater`
- [ ] 4.12 PR body: Changelog, `Closes #6617`, `Closes #6488`, the dispatch arm taken, three run URLs, echoed DROP in `<details>`

## Phase 5: Post-merge

- [ ] 5.1 Merge-commit workflows green; `infra-validation` green with the renamed suite in its log
- [ ] 5.2 `git ls-files` of the seven retired paths → empty
- [ ] 5.3 Sweeper dispatch on `main` → names neither tracker (scoped to the two, not to run colour)
- [ ] 5.4 Ad-hoc Management-API read → 0 of the 14 names in `pg_class`
