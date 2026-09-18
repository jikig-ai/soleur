---
plan: knowledge-base/project/plans/archive/20260918-162640-2026-09-18-fix-local-test-battery-host-portability-plan.md
branch: feat-8231-parallel-test-all-next
issue: 8231
lane: cross-domain
---

# Tasks: local test battery host portability (#8231 precondition)

Every fix lands RED first (`cq-write-failing-tests-before`).

## 0. Setup

- [ ] 0.1 Read the pre-fix battery inventory from the session scratch run, if complete. Fold any
      red row beyond the nine into the matching phase, or file it (plan Phase 5.2 rules).
- [ ] 0.2 Record the host facts: `git config --show-origin --get-regexp '^(diff|color)\.'`,
      `node --version`, `command -v timeout gtimeout bc /usr/bin/time gitleaks`, `gitleaks version` rc.

## 1. Patch-output consumers (#8238, #8263 part 1)

- [ ] 1.1 RED: `guardrails.test.sh` rows:
      - lone-sentinel deny × {mnemonicprefix, noprefix};
      - cross-file allow × noprefix, with the `<<<<<<<` fixture moved to column 0;
      - lone-sentinel deny under `diff.relative=true` from a subdirectory;
      - H1 config-applied check.
- [ ] 1.2 RED: legal lint test rows × {mnemonicprefix, noprefix}; H2 histogram must-pass row.
- [ ] 1.3 RED: `git-commit-secret-scan.test.sh` staged-AWS-key deny × {`color.ui=always`, `color.diff=always`}.
- [ ] 1.4 GREEN: `guardrails.sh` staged-diff read gets `--src-prefix=a/ --dst-prefix=b/ --no-relative`.
- [ ] 1.5 GREEN: the legal lint's `git diff -U0` gets `--src-prefix=a/ --dst-prefix=b/ --no-ext-diff`.
- [ ] 1.6 GREEN: colour-pin env on the gitleaks call in `git-commit-secret-scan.sh` and on
      `lefthook.yml` `gitleaks-staged`. Append to an existing `GIT_CONFIG_COUNT` rather than clobber it.
- [ ] 1.7 Run mutations M1–M5 on scratch copies; record them in the PR body.
- [ ] 1.8 Defensive commit: add `--no-ext-diff`/`--no-color` to the four remaining parsers
      (brand-hex, context-reviewed, lint-trap, check-tc). Grep the lint baselines first and skip
      any baselined line.

## 2. scratch-root (#8263 part 2)

- [ ] 2.1 RED: export the ambient `XDG_CACHE_HOME` sentinel at the top of the suite.
- [ ] 2.2 GREEN: reorder `--unset=XDG_CACHE_HOME` before `HOME=…` in the fallback and containment
      cases; add the contract comment at `resolve()`.
- [ ] 2.3 Mutation: restore either case's old order → RED.

## 3. Tool runnability (#8266, #8250)

- [ ] 3.1 Add the `_skip_arm` helper per suite: per-arm skip, CI=true → exit 1 at the end, and a
      remediation message naming 8.24.2.
- [ ] 3.2 RED: `code-to-prd.test.sh` arms AC5 (a)–(d), with the PATH built from symlinks.
- [ ] 3.3 GREEN `code-to-prd.sh`:
      - timeout→gtimeout→bare probe;
      - scan before copying over the output path;
      - findings = rc 1 + non-empty report containing `"RuleID"`;
      - other non-zero → exit 2 "did not complete";
      - no dangling report path;
      - updated exit table.
- [ ] 3.4 Update `code-to-prd/SKILL.md` (§Redaction Layer 3, §Preconditions).
- [ ] 3.5 RED: `git-commit-secret-scan.test.sh` arms for absent, unrunnable, runnable-empty-report
      and no-`timeout`; each asserts the incidents prefix.
- [ ] 3.6 GREEN `git-commit-secret-scan.sh`: probe → absent-branch semantics; remediation text
      (no `brew install`); header names the three cases and the lefthook double-gate note.
- [ ] 3.7 `gitleaks-rules.test.sh`: runnability probe plus `_skip_arm`; the arity/anchor guards keep running.
- [ ] 3.8 `gitleaks-merge-commit.test.sh`: runnability probe plus `_skip_arm` (replacing `ABORT exit 2`).
- [ ] 3.9 RED then GREEN: T4, P1 and `arm_dash_m` switch to the RuleID oracle. Stub: `version` 0,
      scan 1, no report. Mutation M6.
- [ ] 3.10 TS-cron-5 in both notice-frontmatter copies uses `$EPOCHREALTIME` integer microseconds,
      failing on a non-`digits.digits` value; add a comma-radix unit row.
- [ ] 3.11 `registry-userdata-budget.test.sh`: awk sum instead of `bc`; verify on a symlink PATH without `bc`.
- [ ] 3.12 Update the gitleaks comments in `ci.yml` and `main-health-monitor.yml`.

## 4. Node 26 (#8261)

- [ ] 4.1 `vitest.config.ts`: guarded root `execArgv`; confirm project inheritance and the threads pool.
- [ ] 4.2 RED then GREEN: `kb-share-preview.test.ts` destroys streams in `afterEach`; show 5 errors → 0 under `--expose-gc`.
- [ ] 4.3 Run the component and unit projects on Node 26.8.1: 0 failures, 0 errors.

## 5. Evidence

- [ ] 5.1 Run each of the nine suites alone on this host; record rc and skipped arms.
- [ ] 5.2 Run the full serial battery with `tee` and `TEST_TIMING_LOG`; classify any red row outside
      the nine; wait at most 2 h if refused.
- [ ] 5.3 Add the evidence section and status row to the #8231 `acceptance-evidence.md`.

## 6. Ship

- [ ] 6.1 PR body: `Ref #8231`; `Closes` for #8238, #8250, #8261, #8263 and #8266, each on its own line.
