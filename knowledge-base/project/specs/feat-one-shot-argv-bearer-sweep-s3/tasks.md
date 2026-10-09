# Tasks: argv-bearer sweep S3 (workflow YAML and composite actions)

Plan: knowledge-base/project/plans/2026-10-09-fix-argv-bearer-sweep-s3-workflow-yaml-and-composites-plan.md
Rules for every task: no credential value is printed, echoed or compared in the clear; no git stash and no process pattern-kill; poll with Monitor, never run_in_background; one push after the
committed-tree gates; baseline E regenerated only after the merge-from-main commit exists. PR carries `Ref #9597` and `Ref #7797` (never `Closes`). S4/S5 are out of scope.

## Phase 0: Gates, measure, then RED

- 0.0 Record CPO sign-off (yes-with-conditions) and the lead's choice on the D3 alternatives (default: hold `workspaces-luks-cutover.yml` back) before any edit.
- 0.1 `git fetch origin main`; read `gh pr diff 9785` and `gh pr view 9794 --json files`; merge main if either landed; re-run the census (28/61 baseline, 13 files / 20 sites, 22 rows under `.github`).
- 0.2 Derive the coupled-suite list with `git grep -l` (converted file names, `notify-ops-email`, `anthropic-preflight`) across `apps/web-platform/{infra,test,scripts}`, `plugins/soleur/test`, `scripts`, `tests`; run all hits read-only against a scratch conversion outside the worktree. Include `cutover-inngest-workflow.test.sh`, `terraform-target-parity.test.ts` AC2d, `resend-sender-domain.test.ts`, `prod-version-drift-check.test.sh`, `test-git-data-rung2-evidence-capture.sh`, `c4-count-parity.test.sh`. Any red row needing an `apps/web-platform/**` edit moves that site to the held-back set and is reported to the lead.
- 0.3 Credential-shape counts (value-free): Doppler-held classes by `case` glob; GitHub-only secrets by vendor format plus the live `sentry-audit-gate` run; optional temporary verdict job only with the lead's go.
- 0.4 `docker run ubuntu:24.04`: record bash/curl versions and python3 presence.
- 0.5 Verify `secret_unset` routing and issue dedupe in `scheduled-inngest-health.yml`; record the revert trigger.
- 0.6 Check the next free ADR ordinal against `origin/main`, every `origin/*` ref and every open PR's files (278 and 279 are held by PRs 9529 and 9787; 280 provisional); write the RED rows for each phase; record RED counts.

## Phase 1: library, suite, ADR, CODEOWNERS (commit 1)

- 1.1 `scripts/lib/bearer-curl.sh`: `bc_ok`, `bc_curl SCRIPT SPEC... -- args`, `bc_hmac_sha256_hex`, one `_bc_send`, xtrace refusal per credential-binding function (return 78), no `exit`, no default timeout, marker `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char>`, return 2.
- 1.2 `scripts/lib/bearer-curl.test.sh`: shim contract calibrated against `curl --libcurl`; loopback real-curl end to end; hostile/empty/unset per spec position; 0x01-0x7f byte sweep; `--disable` first; xtrace; chokepoint census; HMAC oracle (openssl, RFC 4231, empty key, python3 absent); negative canary; floors in harness form. Config-writer stderr silenced inside the process substitution; run with `trap '' PIPE`.
- 1.3 CODEOWNERS rows for the library and its suite; `scripts/lint-orphan-test-suites.sh` green.
- 1.4 ADR-280 via `soleur:architecture` (status adopting, ordinal re-verified).

## Phase 2: composites and the plugin-test fix (commit 2)

- 2.1 `notify-ops-email`: source after the missing-key block, `sent=false` failure arm, pre-guard, `::error::` annotation on refusal with exit 0; keep the Resend URL and sender literals; keep AC2d windows.
- 2.2 `anthropic-preflight`: pre-guard outside the substitution, exit 1; `PAYLOAD=` line byte-identical; re-read `gh pr diff 9785` right before editing.
- 2.3 `heartbeat-reconcile-issue-step.test.sh`: supply `GITHUB_WORKSPACE`, record stdin and argv in the curl stub, rows for 2xx, non-2xx, real-curl transport failure, missing key, malformed key, library absent.

## Phase 3: read-only and alert workflows (commit 3)

- 3.1 `board-status-sync.yml`, `sentry-audit-gate.yml`, `kb-drift-walker.yml`, `scheduled-terraform-drift.yml` (sweep step only), `rule-audit.yml` (drop `2>/dev/null` on the UB_HDR call), `scheduled-prod-version-drift.yml` (source after `set +e`).
- 3.2 Explicit-path Rule E run clean on each; owning suites green.

## Phase 4: rehearsal workflow (commit 4)

- 4.1 `git-data-rung2-rehearsal.yml` four sites, URL literals and POST line order preserved; `git-data-rung2-rehearsal.test.sh` green after each edit.

## Phase 5: cutover, canary, inngest-health (commit 5)

- 5.1 `canary-status.yml`: plain checkout, `contents: read`, HMAC via `bc_hmac_sha256_hex`, `bc_curl` triple.
- 5.2 `scheduled-inngest-health.yml`: pre-guard before the attempt loop (`secret_unset`, never `inngest_down`), HMAC, census x2, reader stderr `::warning::` behind a `declare -F` guard.
- 5.3 `git-data-cutover.yml`: flip-precondition conversion without `2>/dev/null`, assertion-step stderr `::warning::`.
- 5.4 Run `git-data-cutover-access` (long timeout), `git-data-flag-precheck`, `inngest-dedicated-host-classify`, `inngest-host-state-workflow-guard`.

## Phase 6: battery stage and lint extension (commit 6)

- 6.1 Stage S3 in `tests/scripts/test-argv-bearer-sweep.sh` reusing the shim, oracle and `CLASSIFIED`: derived population, structural rows, Guard 2 representative verdict rows, slice-drift row, source-path row, marker drift guard; bump `EXPECTED_TESTS`.
- 6.2 Extend `scripts/lint-workflow-local-action-checkout.py` (+ suite): usable checkout including `scripts/lib/`, no `path:`, no `pull_request_target`.
- 6.3 Fixtures use `git_fixture_env "$dir"`; `assert_fixture_dir` below the xtrace refusal; no pathological YAML committed.
- 6.4 If a `knowledge-base/` read was added: `scripts/test-affected-kb-consumers.test.sh` and edges in `AFFECTED_TESTS_SCRIPTS_ARGV_BEARER_SWEEP_PATHS`.

## Phase 7: docs and tracking inputs (commit 7)

- 7.1 Rule E docstring S3 paragraph and the D8 keying decision; finish ADR-280 text; draft tracker comments and issue bodies.

## Phase 8: runner-userland verification

- 8.1 Every new or changed shell suite on the dev host and in `ubuntu:24.04` with identical row counts; floors are invariants over named sets; `${v//pat/repl}` assigned to a variable first.
- 8.2 Run the repo-global ratchets by hand (fixture-relative, fixture-dir-operand, shell-capture-exit, window-closure, trap-tempfile-ownership).

## Phase 9: gates, baseline-only commit (commit 8)

- 9.1 Merge `origin/main`; regenerate baseline E with `--write-baseline-e`; remove the 12 converted rows from the ceiling table; commit; push once after all gates on the committed tree.
- 9.2 Gates: explicit-path and repo-wide Rule E, battery, library suite, lint suite, grep-q pipe guard, supabase endpoints lint, orphan suites, vacuity floor, fixture-env adoption, ratchets, workflow lints, skill-body-budget and rule-bodies (`--base` merge-base), `lint-guard-contract.py`, vitest marker drift guard, c4-count-parity, derived infra/plugin suites read-only, gitleaks `origin/main..HEAD`, apply-exposure diff check.
- 9.3 Live proof on the PR: `sentry-audit-gate` and `board-status-sync` runs; `canary-status` dispatch only with the lead's go. Re-merge main and re-check equality immediately before merge.

## Phase 10: PR and tracking

- 10.1 PR body: first line names the plugin release run and the absence of `apps/web-platform/**`; `Ref` only; no plan/spec paths; no `*-soak-*` names; avoid soak/outage/"Pro"/"subscription"; `Filed: #N ...` plus the net-issue-flow override with one justification per issue.
- 10.2 File the held-back-file issue (owner, deadline, S4 dependency, token wording) and the post-merge first-run follow-through issue (table, owner, merge + 3 days).
- 10.3 Comment on #9597 (counts, partition, baseline 16/42, keying decision, apply-exposure and plugin-release findings) and on #9757.
- 10.4 Post-merge: fill the first-run table; confirm the plugin release run is green.
