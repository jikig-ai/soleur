# Tasks: fix dev-machine disk leaks (scratch dirs and caches)

Plan: `knowledge-base/project/plans/2026-10-01-fix-dev-machine-disk-leak-scratch-and-cache-cleanup-plan.md`
Issue: Ref #7004 (does not close), Closes #9117; deferral tracked by #9341.

CPO sign-off required before starting (`requires_cpo_signoff: true`).

## Phase 0 - RED harness (tests first)

- 0.1 Write `tests/scripts/test-scratch-residue.sh`: per-leaf private `TMPDIR`, delta == 0 on rc 0 and SIGTERM, anti-vacuity (each leaf created at least one entry), SIGKILL arm (marker-bearing dead-owner root), nested-root arms (valid adopt, stale not adopted)
- 0.2 Measure and record the baseline: the eight measured leakers plus one direct vitest, one pytest and one unittest run; commit the table to the PR body
- 0.3 Write `tests/scripts/test-soleur-sandbox.sh` (new/rm/refusals/disk-base)
- 0.4 Add `--report`, `--base`, `--older-than-days`, `--attest` arms, a `SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 --drain` arm and Guard 3 fixture rows to `tests/scripts/test-tmp-purge.sh` (new `.test.sh` files install their EXIT trap before sourcing test-helpers)
- 0.5 Add lint fixtures for rules (d)/(e) and the merge-base highwater check to the lint's `.test.sh`
- 0.6 Confirm every new arm is RED before any production change

## Phase 1 - Runner chokepoints

- 1.1 Create `plugins/soleur/test/lib/scratch-session.ts` (`ensureScratchSession`, validated adoption, atomic marker, exit handlers that preserve 128+n, `SOLEUR_KEEP_SCRATCH=1`)
- 1.2 Call it in line before `ensureIncidentSandbox()` in `plugins/soleur/test/lib/git-tripwire.ts`
- 1.3 Only if Phase 0 shows a vitest leak: add to `apps/web-platform/test/global-setup-git-tripwire.ts` with teardown; prove forks and threads
- 1.4 Only if Phase 0 shows a pytest/unittest leak: `ensure_scratch_session()` in `tests/conftest.py` and `tests/scripts/_git_fixture_env.py`
- 1.5 Call `soleur_scratch_mark_owned` on the `soleur-inc-*` dir right after `mktemp` in `.claude/hooks/lib/test-incident-sandbox.sh` and `plugins/soleur/test/test-helpers.sh`
- 1.6 Extend `.claude/hooks/incident-sandbox-coverage.test.sh` with the call-order assertion; keep its count floor
- 1.7 Add the single marker-contract fixture (all writers parsed by `tc_marker_owner_pid`)

## Phase 2 - Agent sandbox allocator

- 2.1 Add `soleur_sandbox_new` / `soleur_sandbox_rm` to `scripts/lib/scratch-root.sh` (forced disk base, deterministic owner pid, dirty tree copy, no default node_modules link)
- 2.2 Create `scripts/soleur-sandbox.sh new|rm`; register in `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh`
- 2.3 Create `plugins/soleur/skills/work/references/work-scratch-sandboxes.md`; replace the sandbox bullets in `work/SKILL.md` (net <= 0 bytes) and `review/SKILL.md` (<= +900 bytes) with linked pointers; run `python3 scripts/lint-skill-body-budget.py --base origin/main`
- 2.4 Move `shutil.rmtree(sb)` into a `finally` in `apps/web-platform/infra/doppler-download-error-channel.mutation.py`

## Phase 3 - Report, drain guidance, ADR (3b is separable)

- 3.1 `--report` in `scripts/soleur-tmp-purge.sh` (per-class and per-prefix-family bytes, `.git` / non-`.git` split, `SOLEUR_TMP_PURGE_REPORT` header)
- 3.2 Runbook: report/attest/drain workflow, `SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 ... --drain`, cache table with `du -sh` and clear commands, `DEBUGINFOD_URLS=`, `~/.codex/.tmp/marketplaces` ownership
- 3.3 (3b) `tc_attested_class` in `plugins/soleur/scripts/lib/tmp-classify.sh` (explicit-arg globs only, hardened glob and age guards)
- 3.4 (3b) `--attest` with caps (500 entries / 20 GiB), dry-run default, disk-only; test that Reaper 3 and the sweep never pass globs
- 3.5 Amend ADR-250 (Alternatives Considered section, `Amends: ADR-195`, Consequences (d), A1.1-A1.4) via `soleur:architecture`

## Phase 4 - Measured leak sites and the lint

- 4.1 Fix `tests/scripts/test-weakness-miner.sh` (one root, owning trap before sourcing helpers)
- 4.2 Fix `.claude/hooks/grep-rewrite.test.sh` (compose the sandbox cleanup into its trap)
- 4.3 Lint: rule (e); narrow rule (d) (Python `ast`, TS/JS comment-stripped); merge-base `--check-highwater`; TS/PY census and `scripts/lint-trap-tempfile-ownership-tspy.highwater`; keep `ci.yml` job set
- 4.4 Register new suites as `run_suite` rows in `scripts/test-all.sh` and `AFFECTED_<LABEL>_PATHS` arrays in `scripts/lib/test-affected-paths.sh` (sourced at test-all.sh:917); confirm `scripts/lint-orphan-test-suites.sh` and the fixture-relative baseline gate are green

## Phase 5 - Durable log GC and docs

- 5.1 Age-reap `soleur-test-all-logs/*` older than 14 days at `scripts/test-all.sh` startup, namespace-scoped; add a test arm (`Closes #9117`)
- 5.2 Verify cache documentation against this host (dated, host-class labelled numbers)

## Phase 6 - Verify and ship

- 6.1 Run the verification protocol (T0 stamp, private `TMPDIR`, T1 newer-than-stamp listing); paste results into the PR body
- 6.2 Run `bun test plugins/soleur/test/components.test.ts`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `python3 scripts/lint-guard-contract.py`
- 6.3 PR body: per-site fix table, #7004 AC mapping (stays open for #8786), `Closes #9117`
