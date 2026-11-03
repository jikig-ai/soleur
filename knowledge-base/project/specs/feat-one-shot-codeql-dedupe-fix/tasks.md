# Tasks — feat-one-shot-codeql-dedupe-fix

Plan: `knowledge-base/project/plans/2026-11-03-fix-codeql-to-issues-dedupe-plan.md`
Scope: one file — `.github/workflows/codeql-to-issues.yml` (`check-alerts` `run:` block only).

## 1. Setup

- [ ] 1.1 Re-read the plan's Proposed Change, Guard Contract matrix, and Context residuals;
      confirm worktree is `feat-one-shot-codeql-dedupe-fix`.

## 2. Core Implementation

- [ ] 2.1 In `check-alerts`, after the `ALERTS` non-empty check and before the `while` loop,
      add the hoisted tracker-list read per the plan's Proposed Change:
      `gh issue list --label type/security --state open --limit 200 --json title` into
      `${RUNNER_TEMP}/sec-issues.json`, with `if !` fetch failure and `jq -e` non-JSON arms
      each printing a `::warning` and `exit 0` (fail-closed; mirrors `close-orphans`).
- [ ] 2.2 Inside the loop, delete the `SEARCH_QUERY` assignment, the `gh search issues … ||
      true` line and the stale "Existence drill (#8593)" comment; replace `EXISTING=` with
      the anchored jq `startswith` match on `"sec: CodeQL alert #${ALERT_NUMBER} "` (trailing
      space) reading `${RUNNER_TEMP}/sec-issues.json` via standalone `jq --arg` (never
      `gh --jq --arg`).
- [ ] 2.3 Leave everything else byte-identical: alert fetch, `TITLE=`/body build,
      `gh issue create --label type/security`, `CREATED`/`SKIPPED` counters, `close-orphans`.

## 3. Verification

<!-- MD038 disabled on the `#N ` anchor literals: the trailing space inside the code span IS the dedupe anchor, not stray whitespace. -->

- [ ] 3.1 `python3 scripts/lint-workflow-run-body-syntax.py .github/workflows/codeql-to-issues.yml`
      exits 0; extract the edited `run:` body and `bash -n` it.
- [ ] 3.2 `bun test plugins/soleur/test/components.test.ts` green (`findUnboundedEnumerations`
      bound satisfied by `--limit 200`).
- [ ] 3.3 Synthesized-fixture jq runs per the Guard Contract matrix: `#245 ` hits an open <!-- markdownlint-disable-line MD038 -->
      `sec: CodeQL alert #245 — …` title, `#2450 ` and `#245 ` do not cross-match, closed <!-- markdownlint-disable-line MD038 -->
      tracker does not dedupe, gate-filed `sec: CodeQL alert #7 — <rule>` title dedupes,
      empty list returns 0.
- [ ] 3.4 Live read-only spot check: `gh issue list --label type/security --state open
      --limit 200 --json title | jq -r --arg p "sec: CodeQL alert #245 " '[.[] | .title |
      select(startswith($p))] | length'` returns > 0.
- [ ] 3.5 Post-merge: observe next daily run (or `gh workflow run codeql-to-issues.yml`) —
      skips logged for tracked alerts, no duplicate `sec:` titles filed.
