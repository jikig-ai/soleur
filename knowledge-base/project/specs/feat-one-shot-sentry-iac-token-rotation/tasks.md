# Tasks — feat-one-shot-sentry-iac-token-rotation

Plan: `knowledge-base/project/plans/2026-11-13-feat-sentry-iac-token-rotation-profile-plan.md`.
Decisions: `decision-challenges.md` (this directory). Never mint, rotate or store a real token; no
real Sentry, Doppler or GitHub secret writes; single test files only; scratch under `/var/tmp`.

## Phase 1 — Characterise `ro` (commit 1, script unchanged)

- [ ] 1.1 Create `scripts/rotate-sentry-actions-ro-token.test.sh` with stub `gh`/`curl`/`doppler`/`agent-browser` that record argv + stdin to files and never echo values; `TMPDIR` under the case dir; synthesized ≥ 40-char non-hex token.
- [ ] 1.2 Rows R1-R8 (xtrace refusal, usage errors, dry run, live happy, scope superset, probe 403, region pin, `--selector` capture). Add the assertion-count floor.
- [ ] 1.3 Register via `run_suite` in `scripts/test-all.sh` beside `rotate-supabase-db-credential`.
- [ ] 1.4 `python3 scripts/regenerate-shard-manifest.py --incremental --write` (expect 1 new).
- [ ] 1.5 Run the test file and `bash scripts/lint-orphan-test-suites.sh`, both green against the unchanged script. Commit.

## Phase 2 — `--profile` + `iac` (commit 2)

- [ ] 2.1 Add rows I1-I14 and H1-H3, then run them and confirm they are RED.
- [ ] 2.2 Add `--profile ro|iac` to the arg loop, plus a profile table made `readonly` after it.
- [ ] 2.3 `iac`: ADR-031 scope constant, the seven org-subdomain probes (each commented with its consumer), and no region read.
- [ ] 2.4 `iac` tool preflight (`doppler`, `sha256sum`, `sed`), followed by the read-only `doppler configs get` for `prd` and `prd_terraform`. Both run before the trap scope and exit 2 on failure.
- [ ] 2.5 Header: document `--profile` and the stores, and add the sentence "Doppler has no no-store mode; store form pinned by the test".
- [ ] 2.6 `iac` dry run: sentinel diff, the gh no-store length check, and the reachability line. It makes zero Doppler writes.
- [ ] 2.7 `iac` store, in order:
  - the GitHub secret, then the list check;
  - the Doppler `prd` stdin write, with output sent to `/dev/null`;
  - `dig_of` read-back;
  - the conditional `prd_terraform` write;
  - the digest loop over the other `prd_*` branch configs.
- [ ] 2.8 `store_fail` reporter. When nothing landed, revoke the NEW token. When something landed, print `HOLD THE NEW TOKEN` / `STILL HOLD THE OLD TOKEN` / `do NOT revoke the old token yet`.
- [ ] 2.9 GREEN, then run `shellcheck` and `bash -n` on both files. Commit.

## Phase 3 — Runbook

- [ ] 3.1 Add a short IaC section to `knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md` covering:
  - the integration name and the developer-settings URL, then `iac-terraform-prd` and Tokens;
  - the `--profile iac` dry-run and live invocations;
  - the store targets;
  - `gh workflow run scheduled-sentry-alert-drift.yml` as the proof;
  - revoking the old token by its masked last four, then `get count` = 1.
- [ ] 3.2 Add two failure-table rows: the partial-store report and a branch-config override. Scope the "One store" sentence to `ro` and add the tag.

## Phase 4 — postmerge

- [ ] 4.1 `SKILL.md` Phase 3.5: add the prerequisites note that the token is monitors-only and change the fallback to `jikigai-eu`. Keep the single `--config -` + `monitors/` block and the `SENTRY_AUTH_TOKEN`-first order.
- [ ] 4.2 `SKILL.md` Production Debugging bullet: name `SENTRY_ISSUE_RO_TOKEN` first and `SENTRY_IAC_AUTH_TOKEN` as the last resort.
- [ ] 4.3 `references/sentry-error-count-delta.md`: change the fallback to `jikigai-eu` and add one dated measurement sentence. The ladder is unchanged.
- [ ] 4.4 `references/graceful-degradation.md`: correct two rows and add one.

## Phase 5 — Verification (single files)

- [ ] 5.1 Run `bash scripts/rotate-sentry-actions-ro-token.test.sh`.
- [ ] 5.2 Run `bash scripts/lint-orphan-test-suites.sh` and `bash scripts/test-all-corpus-weight-budget.test.sh`.
- [ ] 5.3 Run `shellcheck` on both files and `python3 scripts/lint-shell-trace-credential-refusal.py`.
- [ ] 5.4 Run `timeout 600 bash tests/scripts/test-argv-bearer-sweep.sh > /var/tmp/argv-sweep.log 2>&1; tail -n 40 /var/tmp/argv-sweep.log` and confirm the S7 rows are green.
- [ ] 5.5 Run `bun test plugins/soleur/test/components.test.ts`.
