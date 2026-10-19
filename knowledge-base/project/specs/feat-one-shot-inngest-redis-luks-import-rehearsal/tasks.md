# Tasks: offline local-state rehearsal of terraform import for random_password.inngest_redis_luks

Plan: `knowledge-base/project/plans/2026-10-19-feat-inngest-redis-luks-import-rehearsal-plan.md`
Branch: feat-one-shot-inngest-redis-luks-import-rehearsal | Draft PR 10524 | Refs #9927, #10112 (never a closing keyword)

Hard constraints (every phase): never touch web-1's LUKS volume 106443278; no SSH; no host reboot or replace; no
deletion of the rehearsal volume (#10112 lands after); targeted local tests only (CI is the authority); merge
`main` with a merge commit, never rebase; no `git stash`; the real passphrase is never read, imported or printed.

## Phase 1: RED first

- 1.1 Create `apps/web-platform/infra/inngest-redis-luks-import-rehearsal.test.sh` (executable) with the dynamic oracle written against the INTENDED behavior only: scratch root from the extracted block, mint, state loss, env-route import, then assert "plan after import reports no changes".
- 1.2 Run it locally; confirm RED for the stated reason (replacement + `Instance cannot be destroyed`, rc 1). Record failing assertion NAMES only (never output files) for the PR.
- 1.3 Add the doc-pin `grep -q` per document (ADR-282 row, runbook row name the suite); confirm RED (the rows do not name it yet).

## Phase 2: Scaffolding, static section, hygiene

- 2.1 Header comment: property list P1-P4, what the suite does NOT claim (R2-backed state, per-merge jq HALT after the edit, other passphrases, other versions). Avoid reproducing the resource block literal in comments.
- 2.2 Tool gate (`terraform`, `jq`): CI set = FATAL; local = loud SKIP of the dynamic section with a counted `SKIPPED <n> assertions` marker. Read the pinned version from `infra-validation.yml` (`TERRAFORM_VERSION`); CI mismatch FATAL, local mismatch a note.
- 2.3 Scratch dir (0700, trap on `EXIT INT TERM`), `tf()` wrapper (`env -i`, per-dir `TF_DATA_DIR`, `-no-color`, output to files never printed), failing `terraform()` stub + absolute-path call in `tf()`, argv shim, `say()`/`fail()` pre-print funnel, xtrace-off assertion.
- 2.4 Source `tests/scripts/lib/hcl-effective-text.sh` from the repo root; `block_of ... random_password inngest_redis_luks`; zero blocks = failure; assert `length = 40`, `special = false`, `prevent_destroy = true` inside it; assert parent lock has a `hashicorp/random` entry and read the constraint from `main.tf`.
- 2.5 Seams: `SOLEUR_IMPORT_REHEARSAL_SRC_TF`, `SOLEUR_TF_PLUGIN_DIR`, `SOLEUR_IMPORT_REHEARSAL_NO_MUT=1`; anti-vacuity floor counted on non-skipped runs.
- 2.6 Add ONE additive pointer assertion to `inngest-provision-rehearsal.test.sh` (suite exists, executable, `bash -n` clean) beside the "Cross-checks on the sibling artifacts" block; no other line moves (PR 10405 edits section 8 of this file).

## Phase 3: Dynamic section and mutation battery

- 3.1 Provider acquisition: offline-first `init -backend=false -input=false -lockfile=readonly -plugin-dir` with `HTTPS_PROXY=http://127.0.0.1:9`; registry `init` (retried once) only when `CI` is set; copy the PARENT root lock entry (3.9.0).
- 3.2 Mint the synthetic value (value file 0600), record `sha256` digest prefix, delete state files (loss).
- 3.3 Env-route import (`TF_CLI_ARGS_import` with the flags inside, read from the value file via `bash -c ... exec`); assert plan = replace (`forces replacement`) + `Instance cannot be destroyed` rc 1; assert apply refused with digest unchanged.
- 3.4 Repair: `state pull | jq (serial+1, special=false) | state push -`; assert `plan -detailed-exitcode` rc 0 and digest equal to the pre-loss digest.
- 3.5 Negative control: same fixture without `prevent_destroy` (validated well-formed) mints a different digest on apply.
- 3.6 `import {}` characterization: plan = 1 import / 1 add / 1 destroy + error; report `note import_block_plan_prints_value=yes|no` (not gated); canary through the scan path; scan terraform files with `grep -F -f`.
- 3.7 In-suite mutation battery per the plan's Guard Contract (Guard 1 five rows, Guard 2 four rows, harness rows), each mutated fixture proven well-formed first; child runs bounded.
- 3.8 Run the full suite locally (provider from the plugin cache) GREEN; run it once with the cache hidden and `CI` unset (SKIP path) and once with `CI=1` and no provider (FATAL path).

## Phase 4: Records (CTO R4, CPO conditions)

- 4.1 ADR-282: dated addendum (states its convention exception explicitly) with UNVERIFIED first, VERIFIED scoped to local state and the terraform versions actually run; in-place edit of the `| Terraform state entry lost |` row limited to the false `import {}` parenthetical, the "remains UNVERIFIED" sentence and the DEFERRED clause. Finalize wording after reading the first green CI leg (1.10.5) and quote the `import_block_plan_prints_value` observation.
- 4.2 Runbook `inngest-luks-cutover-6894.md` row: same correction; passphrase-echo warning; shell prefix-assignment form (never `env VAR=value terraform`); R2-backed state not run.
- 4.3 Paraphrase sweep (`import ?\{\}|plans as a no-op|candidate recipe|NOT rehearsed|state-loss recovery`) over `knowledge-base/engineering` and `apps/web-platform/infra`; read every hit; list the left-unchanged hits (ADR-142 history, `inngest-arm-write-token.tf`, ADR-006 and the rationale runbook web-class text).
- 4.4 Run `scripts/test-affected-kb-consumers.test.sh` once after the doc edits.

## Phase 5: Registration, verification, ship notes

- 5.1 `git add -N` the new suite, then `python3 scripts/regenerate-shard-manifest.py --group infra --incremental --write` (commits `suite-shard-legs.tsv` and `suite-durations.tsv`).
- 5.2 Targeted local checks: the new suite, `inngest-provision-rehearsal.test.sh`, `.github/scripts/test/test-infra-suite-registration.sh`, `python3 scripts/lint-trap-tempfile-ownership.py`, `bash scripts/lint-orphan-test-suites.sh`.
- 5.3 Confirm `git diff --stat origin/main` shows no change under `apps/web-platform/infra/inngest-provision-rehearsal/` or `.github/workflows/`.
- 5.4 Commit via file with the trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR body via file with `Ref #9927`, `Ref #10112`, ending `🤖 Generated with [Claude Code](https://claude.com/claude-code)`; after every body edit assert `gh pr view 10524 --json closingIssuesReferences` is `[]`.
- 5.5 Do not mark ready until the `deploy-script-tests` leg that owns the suite is green at terraform 1.10.5 (the only allowed unrelated red: push-arm "Tenant integration (dev-Supabase)" on `test/server/action-sends-worm.test.ts`, not touched).
