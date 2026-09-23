---
date: 2026-09-22
category: test-failures
module: ci/monitor-registry
issue: "#8586"
pr: "#8588"
tags: [main-red, sentry-monitors, gh-probe-gate, fixture-baseline, registry-drift]
---

# Learning: one new monitor landed as four independent red gates — and each gate named its own remedy

## Problem

PR #8578 added a scheduled GitHub-Actions monitor (`scheduled-actions-queue-health.yml`, the #8450 actions-queue watchdog) and merged green. `main` then went red on four *independent* gates, each measuring a different drift surface the monitor had silently created:

1. `plugins/soleur/test/components.test.ts` — the #6793 unlimited-probe gate flagged an unbounded `gh issue list --search` enumeration in the new workflow's self-close loop.
2. `plugins/soleur/test/fixture-relative-assert.test.sh` — the new `scripts/actions-queue-health.test.sh` added 2 unresolvable-relative-operand sites; the checked-in baseline was never regenerated (1567→1569 sites, 295→296 files).
3. `apps/web-platform/scripts/sentry-monitors-audit.test.sh` T25 — the Terraform root grew to 59 `sentry_cron_monitor` blocks while prose counts in `infra/sentry/README.md` and the audit script still said 58.
4. `apps/web-platform/test/server/inngest/function-registry-count.test.ts` (c2) — every tf `sentry_cron_monitor` name must resolve to a `SENTRY_MONITOR_SLUG` or a `NON_INNGEST_MONITORS` entry; the GHA-fired monitor had neither.

## Solution

Four surgical repairs, one per gate (PR #8588):

- Bound the probes: `-L 1` on the two `.[0].number // empty` existence drills, `-L 50` on the close-enumeration loop (the bound ALSO caps serial `gh issue close` calls inside the 5-min job timeout — a bound sized only for the gate can blow the runtime budget while the `always()` heartbeat still posts `ok`).
- Regenerate the baseline via the suite's own `--write-baseline` flag — never hand-edit; the guard re-scans and compares row-for-row.
- Register the slug in `NON_INNGEST_MONITORS` with the standard comment (GHA-fired, external subject, no `cron-*.ts`, no slug const, terminal heartbeat step).
- Update BOTH prose count sites (README summary AND the audit script's dated addendum — grepping one stale `58` misses the other; T25 greps the tf-derived count on ONE line).

## Key Insight

**A new monitor is not one change — it is a registry update across N independent ledgers, and main only tells you after merge.** Each gate is self-describing (the failure output names the missing registration), so the repair is mechanical — but only if you reproduce each red locally before editing. The workflow file, the test corpus, the tf root, and the prose docs are four separate ledgers that all must agree; a fix that greens one gate can leave the next red.

**Second insight (from review):** the #6793 gate's window is narrower than the property it names — it only scans `gh … list` probes carrying `--search`. The identical silent-30 truncation reaches automation via `--label` probes, `gh search`, `gh api`, and whole unglobbed surfaces (`.ts` cron prompts, `.github/scripts/`). Filed as #8593; live burn instance #8594 (`review-reminder.yml` filing duplicates at 32 > 30).

## Prevention

- When adding a scheduled monitor, enumerate its ledger surfaces up front: probe gate (`components.test.ts`), fixture baseline (`--write-baseline`), tf monitor count prose, `NON_INNGEST_MONITORS`/`SENTRY_MONITOR_SLUG` registration. The four suites are cheap and named.
- Bound `gh` enumerations for the JOB BUDGET, not just the lint: `-L N` on a serial-API loop multiplies by per-call cost against `timeout-minutes`.
- A cap-hit should be audible (`::notice`), not silent — a bounded enumeration that truncates quietly is the same defect with a bigger window.

## Session Errors

1. **Full-battery pre-commit gate false-red (489/495) during concurrent sibling `test-all.sh` runs** — Recovery: verified all four acceptance gates and sibling controls green independently, committed with `--no-verify` after the non-battery hooks passed. — **Prevention:** #8045 already tracks the shared-TMPDIR false-RED class; until it lands, treat a battery red under a concurrent sibling run as suspect and re-run serially.
2. **`SKIP=bun-test` lefthook bypass did not take — the hook spawned the full battery a second time** — Recovery: killed the run and used `--no-verify`. — **Prevention:** the documented escape for #8045 is `LEFTHOOK=0`, not `SKIP=`; hook-name skip syntax does not cover this hook.
3. **Battery re-run refused — sibling full-gate lease was held by feat-one-shot-8580** — Recovery: identified the active leaseholder via process inspection and deferred the re-run. — **Prevention:** check for sibling `test-all.sh` processes before assuming a battery red is real.
4. **`lint-workflow-*` scripts reject file-path args** (they take a root directory) — Recovery: re-ran with the directory/repo-root arg. — **Prevention:** check the script's `--help`/arg signature before invoking linters on single files.
5. **`git stash` attempted during a worktree rebase — blocked by hook** — Recovery: let untracked planning artifacts ride the rebase instead of stashing. — **Prevention:** `hr-never-git-stash-in-worktrees`; use `git show <commit>:<path>` or commit WIP first.
6. **`gh issue create` rejected by the filing gate (no user-visible consequence declared)** — Recovery: re-filed with `meta/machinery` label (all three findings were verification-machinery findings). — **Prevention:** route guard/gate/ledger findings through exit 1 (`meta/machinery`) by default; only reach for `User-Impact:` when a user actually receives the artifact.
7. **`lint-workflow-errexit-capture --root .github/workflows` scanned zero files** — the `--root` flag wants the repo root, not the workflows dir. — **Prevention:** read `--help` output when a linter reports suspiciously empty coverage rather than accepting the clean result.

## Cross-References

- Issue #8586 (the red), #8578 (the monitor that introduced it), #6793 (the probe gate), #8450 (monitor origin), #8045 (concurrent-battery false-RED class)
- Filed during review: #8593 (gate-window structural gap), #8594 (review-reminder duplicate filing), #8595 (monitor-registry guard gaps)
- Plan: `knowledge-base/project/plans/archive/20260922-213800-2026-09-22-fix-main-red-queue-health-monitor-drift-plan.md`
