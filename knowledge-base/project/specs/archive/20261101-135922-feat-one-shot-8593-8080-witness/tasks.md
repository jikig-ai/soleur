# Tasks — feat-one-shot-8593-8080-witness

Plan: `knowledge-base/project/plans/2026-11-01-feat-inngest-witness-gh-enum-gate-plan.md`
Issues: `Closes #8593` + `Refs #8080` (witness half only). Landmines: no `MUT_SKIP`/`*_GUARD_*`
literals in infra-validation.yml text; no `env -u` run-line prefixes; no `grep | grep -q`; no
`inngest_luks_key_probe_dark`; floor bumps are TWO write sites (PRESENCE_ROWS + mutate_floor_red
sed anchor); commit with the repo CLA-allowlisted identity via `git -c user.name=… -c user.email=…`.

## 1. Setup

- [x] 1.1 Re-read the plan's Guard Contracts and Landmine constraints; confirm worktree is
      `feat-one-shot-8593-8080-witness`.
- [x] 1.2 Write failing tests first per workstream (cq-write-failing-tests-before): the new
      `findUnboundedEnumerations` controls in `components.test.ts` and the new
      `inngest-gate-witness-classify.test.sh` decision table BEFORE the implementation.

## 2. Core Implementation — Workstream A (gate widening, #8593)

- [x] 2.1 `plugins/soleur/test/components.test.ts` — add capture patterns for
      `gh search (issues|prs)` and `gh api` list endpoints (plural collections; NOT
      `…/<resource>/<N>` single-resource reads).
- [x] 2.2 Add `findUnboundedEnumerations` (sibling of `findUnlimitedProbes`): enumeration /
      post-narrowing shapes (`.[].`, `| grep`, `select(`, `map(`, `length`, `sort_by`/`min_by`/`max_by`/`last`)
      require `-L N ≥ 100` or `--paginate`; keep `EXISTENCE_DRILL`/`POST_SEARCH_NARROWING`/
      `BOUNDED_LINKED_ISSUE` exemptions and add coded `BOUNDED_HEAD = /--head\b/` (CTO ruling:
      `--head` is domain-bounded by headRefName cardinality; covers bump-inngest-bootstrap-pin.sh
      :503/:556 post-narrowing probes).
- [x] 2.3 Add `"ts"` surface to `surfaceOf` + full-line `//` comment handling (flush+skip).
- [x] 2.4 Extend `EXEC_SURFACE_GLOBS`: `.github/scripts/**/*.sh` (exclude `*/test/`),
      `apps/web-platform/server/inngest/functions/*.ts` (exclude `*.test.ts` if any exist in that
      dir — verify).
- [x] 2.5 Synthesized controls per Guard-1 matrix rows 1–8 (incl. `-L 1` insufficiency,
      `gh api` item-vs-list pair, `//`-comment probe, must-PASS `gh pr list --head` post-narrowing
      fixture for BOUNDED_HEAD, must-PASS set).
- [x] 2.6 Bound the six named sites: `scheduled-inngest-health.yml` (both `for n in $(…)` loops,
      `--limit 100`), `review-reminder.yml` + `strategy-review-check.sh` (`--search` server-narrow
      + `--limit 100` + keep `grep -cxF`), `codeql-to-issues.yml` (existence-drill rewrite),
      `cron-follow-through-monitor.ts` (`--limit 200` ×2 + instruction note),
      `cron-roadmap-review.ts` (`--paginate` + `-L`).
- [x] 2.7 **A3 census**: run the widened detector over the full corpus; bound or document-exempt
      every newly-flagged site; record site→disposition in a spec artifact; corpus assertions stay
      `toEqual([])`; `bun test plugins/soleur/test/components.test.ts` green.

## 3. Core Implementation — Workstream B (witness, #8080-1)

- [x] 3.1 `scripts/inngest-gate-witness-classify.sh`: token→`satisfy`/`refusal`/`suppressed` table
      (unknown token → `refusal`), suppression via `_erg_flag_class`, `--selftest` printing
      `inngest-gate-witness-classify selftest: ok`.
- [x] 3.2 `apps/web-platform/infra/inngest-gate-witness-classify.test.sh`: decision table +
      lib-derived `_ihdg_verdict` token census + Guard-2 matrix rows (filesystem registration —
      no infra-validation.yml edit).
- [x] 3.3 `scheduled-inngest-health.yml` witness arm in the `probe` job: `monitor-streak-state.sh
      fetch` (artifact `inngest-gate-witness-streak`, `STREAK_BRANCH=main`) → BS reads (probe
      `--since 24h --limit 500`; heartbeat `inngest-cutover-flip` `--since 30m --limit 200`,
      rc-captured + stderr classified) → source `tests/scripts/lib/inngest-host-dark-gate.sh` →
      `inngest_execute_registry_gate` report-only → classify → `seal`/`assert` →
      `actions/upload-artifact` (overwrite, retention-days 90) → verdict log line.
- [x] 3.4 Filing/close/crash steps: streak ≥ 8 → dedupe + create/comment
      `[ci/inngest-gate-witness]` issue (labels `ci/inngest-gate-witness`, `action-required`,
      `priority/p2-medium`); `dark` → auto-close open witness issue; armed-class flag → suppress;
      `steps.witness.outcome != 'success'` crash arm; all filing steps carry status-check `if:`.

## 4. Testing

- [x] 4.1 `bun test plugins/soleur/test/components.test.ts` green (AC1–AC3).
- [x] 4.2 `bash apps/web-platform/infra/inngest-gate-witness-classify.test.sh` green (AC8).
- [x] 4.3 `bash scripts/inngest-gate-witness-classify.sh --selftest` →
      `inngest-gate-witness-classify selftest: ok` (AC9).
- [ ] 4.4 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-follow-through-monitor.test.ts` green.
- [x] 4.5 `bash scripts/alarm-issue-filing-guard.test.sh` green over the edited workflow.
- [x] 4.6 Landmine sweep over the final diff: no `MUT_SKIP`/`*_GUARD_*` in workflow executable
      text, no `env -u` run-line prefixes, no `grep | grep -q`, no `inngest_luks_key_probe_dark`.
- [x] 4.7 PR body: `Closes #8593` own line, `Refs #8080` (optional `Refs #8594`); KB specs/plans
      land under `archive/` paths via ship's archive-kb.sh at ship time.
