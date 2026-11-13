# Tasks — feat-one-shot-sentry-iac-token-rotation

Plan: `knowledge-base/project/plans/2026-11-13-feat-sentry-iac-token-rotation-profile-plan.md` (post-review, deepened).
Decisions: `decision-challenges.md` (this directory). Follow-up: #12740.

Ground rules:

- Never mint, rotate or store a real token.
- Make no real Sentry, Doppler or GitHub secret writes.
- Run single test files only.
- Keep scratch under `/var/tmp`.

## Phase 1 — Characterise `ro` (commit 1, script unchanged)

- [x] 1.1 Create `scripts/rotate-sentry-actions-ro-token.test.sh` with `set -euo pipefail` and one owning trap. The script under test always runs with `< /dev/null`, and `TMPDIR` points under the case dir. The token is a synthesized, non-hex value of at least 40 chars.
- [x] 1.2 Build the stubs from the plan's Phase 1.1 spec. They must never echo a recorded value.
  - `gh` records argv. It reads stdin only on `secret set`. `--no-store` prints a string of the computed length, and `secret list` prints the stored names. It supports rc injection.
  - `curl` routes on URL, writes the `-o` file, prints the code from an override map, and never reads stdin.
  - `doppler` keeps per-config state and has an enumeration fixture with the measured keys (`name`, `root`, `environment`, …). `get --plain` appends LF. `set` reads stdin and prints `STUB-ALL-OTHER-SECRETS-CANARY`. It supports rc and corrupt injection.
  - `agent-browser` implements `get value`.
- [x] 1.3 Rows R1-R8: xtrace and `SHELLOPTS` refusal, usage errors, dry run, live happy path, scope superset, probe 403, region pin, `--selector` capture. End with an exact assertion-count check.
- [x] 1.4 Register `run_suite "scripts/rotate-sentry-actions-ro-token" bash scripts/rotate-sentry-actions-ro-token.test.sh` in `scripts/test-all.sh`, beside `rotate-supabase-db-credential`.
- [x] 1.5 `git add` the test and `test-all.sh`, then run `python3 scripts/regenerate-shard-manifest.py --incremental --write`. Confirm it reports the suite as new.
- [x] 1.6 Run the test file, then `bash scripts/lint-orphan-test-suites.sh` (it needs the file tracked). Both must be green against the unchanged script. Commit.

## Phase 2 — `--profile` + `iac` (commit 2)

- [x] 2.1 Add rows I1, I2, I5-I12, H1, H2, plus R2 `--profile xyz` and R4 run again with `--profile ro`. Run them and confirm the RED.
- [x] 2.2 Remove the early `readonly` on `SECRET_NAME` and `EXPECTED_SCOPES`. Add the `--profile ro|iac` arg and a profile `case`, then a single `readonly` after it.
- [x] 2.3 `iac` profile:
  - the ADR-031 scope constant;
  - four org-subdomain probes: `projects/jikigai-eu/web-platform/`, `workflows/?per_page=1`, `monitors/?per_page=1`, `issues/?query=is:unresolved&limit=1&statsPeriod=24h`, each commented with its consumer;
  - no region read.
- [x] 2.4 `iac` preflight, before the trap and before capture:
  - tools `doppler`, `sha256sum`, `sed`;
  - one `doppler configs -p soleur --json` enumeration;
  - assert that `prd` is root, that `prd_terraform` is a `prd` branch, and that there is at least one branch;
  - build `TARGETS` and `STALE_COPIES` (other `prd` configs whose `--only-names` contains the key);
  - exit 2 on any failure; with `--from-file`, the message names the still-unshredded source.
- [x] 2.5 Header: `--profile`, the targets, GNU userland, the historical filename, and the sentence "Doppler has no no-store mode … store form pinned by the test".
- [x] 2.6 `iac` dry run: preflight, sentinel diff, the gh no-store length check, the reachability line and the `STALE COPIES` line. Zero Doppler writes, zero curl.
- [x] 2.7 `iac` store:
  - Write the GitHub secret with a literal line, then run the list check. A list failure goes to UNVERIFIED and `store_fail`.
  - Doppler `prd` stdin write with output to `/dev/null`, then `dig_of`.
  - Doppler `prd_terraform` stdin write, unconditionally, then `dig_of`.
  - Compute `want_digest`.
  - In `dig_of`, a non-zero rc or the empty-string digest counts as a read failure (UNVERIFIED).
- [x] 2.8 `store_fail`:
  - If nothing landed, tell the user to revoke the NEW token.
  - Otherwise print `HOLD THE NEW TOKEN` / `UNVERIFIED (value unknown)` / `STILL HOLD THE OLD TOKEN` and `do NOT revoke the old token yet …`, then exit 1.
  - On success, print the revoke-old guidance only when HOLD_NEW == TARGETS, then the non-blocking `STALE COPIES (no known reader in repo): … #12740` line.
- [x] 2.9 GREEN, then run `shellcheck` and `bash -n` on both files. Commit.

## Phase 3 — Runbook

- [x] 3.1 Add the section `## IaC token rotation (SENTRY_IAC_AUTH_TOKEN, iac-terraform-prd)` with:
  - the integration;
  - the developer-settings URL, then `iac-terraform-prd`, then Tokens;
  - the `--profile iac` dry-run and live invocations;
  - three store targets, with independent copies and the stale-copies pointer to #12740.
- [x] 3.2 Prove, then revoke:
  - Dispatch `scheduled-sentry-alert-drift.yml` and `scheduled-terraform-drift.yml` and watch each by run id.
  - The gate is alert-drift `success` AND no Sentry 401/403/auth error in the terraform-drift Sentry leg.
  - Revoke by masked last four, then `get count` must be 1.
- [x] 3.3 Failure-table rows: the partial-store report, the doppler preflight failure, and a Sentry auth error in the terraform-drift leg. Scope the "One store" sentence to `ro` and add the tag.

## Phase 4 — postmerge (SKILL.md has 9 bytes of headroom)

- [x] 4.1 `SKILL.md`: make only two substitutions, net +8 bytes: `echo "jikigai")` → `echo "jikigai-eu")`, and the Production Debugging `SENTRY_API_TOKEN` → `SENTRY_ISSUE_RO_TOKEN`. Keep the single `--config -` + `monitors/` block exactly as-is.
- [x] 4.2 `references/sentry-error-count-delta.md`: change the fallback to `jikigai-eu`. Add one dated paragraph covering the measurements, that the monitors-only token is used, and that org search goes RO first with IAC as the last resort. The ladder is unchanged.
- [x] 4.3 `references/graceful-degradation.md`: correct two rows (SENTRY_AUTH_TOKEN → monitors only; RW → PUT only, and with neither RO nor RW the delta is SKIPPED).

## Phase 5 — Verification (single files)

- [x] 5.1 Run `bash scripts/rotate-sentry-actions-ro-token.test.sh`.
- [x] 5.2 Run `bash scripts/lint-orphan-test-suites.sh` and `bash scripts/test-all-corpus-weight-budget.test.sh`.
- [x] 5.3 Run `python3 scripts/lint-skill-body-budget.py --base origin/main` and `wc -c < plugins/soleur/skills/postmerge/SKILL.md` (must be ≤ 48000).
- [x] 5.4 Run `shellcheck` on both files and `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`.
- [x] 5.5 Run `timeout 600 bash tests/scripts/test-argv-bearer-sweep.sh > /var/tmp/argv-sweep.log 2>&1; tail -n 40 /var/tmp/argv-sweep.log`. The S7 rows must be green.
- [x] 5.6 Run `bun test plugins/soleur/test/components.test.ts`.
- [x] 5.7 Run `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch`.
- [x] 5.8 Run `npx markdownlint-cli2` on the plan, `tasks.md` and the runbook.
