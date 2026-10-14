---
title: An env-scoped skipIf lets CI go green with the check dark
date: 2026-09-25
category: test-failures
module: plugins/soleur/test/skill-security-scan.test.ts, lefthook.yml, skill-security-scan workflows
tags: [lefthook, pre-commit, skipIf, calibration, ci-pin, quotePath, git-diff]
pr: 8878
---

# Learning: an env-scoped `skipIf` lets CI go green with the check dark

## Problem

The pre-commit `plugin-component-test` hook ran `bun test plugins/soleur/test/` on every staged
plugin `.md` (176 s measured; 204 s on a contended machine). The obvious remedy — route it through
`test-all.sh --affected` — was measured WORSE: a one-line SKILL.md edit selected 215/517 suites and
spent 241 s selecting, because `plugins/soleur` is one monolithic suite entry. The actual cost was
the skill-security-scan calibration (116.5 s): a full-corpus rescan of all 102 first-party
`SKILL.md`, although a verdict is a function of one `SKILL.md` plus the rule pack.

## Solution

1. The hook passes the staged paths in `SOLEUR_SKILL_SCAN_CALIBRATION_SCOPE`; the calibration scans
   only staged corpus `SKILL.md` files, skips the corpus-level REVIEW ratio, and ignores the
   variable under `CI`. Hook: 176 s → 48.6 s.
2. Review (test-design seat) found the new `test.skipIf(...)` call sites were a one-token disarm of
   the CI calibration: `skipIf(true)` or an inverted REVIEW skip exits 0 in CI because skipped tests
   are not failures and nothing asserted the calibration ran. Fixed by extracting a pure
   `resolveCalibrationScope()` (10 unit rows), a CI-only "unscoped over a non-empty corpus" test,
   and an `afterAll` that throws under CI unless both calibration tests ran — both mutants now rc 1.
3. Scope drift (a `./`-prefixed, absolute, space-joined, or unsubstituted `{staged_files}` value)
   throws instead of silently scoping to zero; an empty scope fails safe to full.
4. Found while reviewing, pre-existing: the skill-scan PR gate and postmerge audit read
   `git diff --name-only` without `-c core.quotePath=false`, so git quoted any non-ASCII path
   (`"plugins/soleur/agents/caf\303\251.md"`), the `^plugins/...` filter dropped it, and a
   weaponised agent named `café.md` was never scanned. Both now diff unquoted and fail closed on a
   path git still quotes (tab/newline/quote/backslash) under a scanned directory; 3 executing
   fixtures (RED 26/3 → GREEN 29/0).

## Key Insight

**A `skipIf` driven by the environment makes "skipped" a reachable outcome in CI, and a skipped test
exits 0.** Any edit that makes a check conditional must add a CI-side assertion that the check RAN
(a ran-set checked in `afterAll`, or a dedicated CI-only test pinning the unscoped mode) — the
env-guard on the scope expression protects that one expression, not the call sites that consume it.
My own mutation battery missed this because every row mutated the scope expression and was scored
by reading a `console.log` line; no row mutated a `skipIf` call site.

Two companions:

- **A path filter over `git diff --name-only` needs `-c core.quotePath=false` (or `-z`)**, and must
  fail closed on the paths git quotes regardless (control characters, `"`, `\`). A quoted path is not
  an error — it is silently a different string.
- **A drift regex keyed on a basename (`(^|/)SKILL\.md$`) also matches mirror trees.** This repo
  has `plugins/soleur/{codex,devin}/skills/*/SKILL.md`; key on the corpus SHAPE
  (`plugins/soleur/skills/<name>/SKILL.md`, any prefix) so mirrors are out of scope, not drift.

## Session Errors

1. **`git stash list` in a Bash call blocked by the guardrail hook** — Recovery: dropped it. — Prevention: already hook-enforced (`guardrails:block-stash-in-worktrees`).
2. **`git worktree add` for a baseline timed out at 120 s** — Recovery: `git archive` + `KB_DRIFT_FIXTURE_ROOT`. — Prevention: captured in `2026-09-25-kb-drift-walker-counts-are-environment-and-prose-sensitive.md`.
3. **Drift walker counted a literal `](x.md)` in plan prose as a link** — Recovery: reworded. — Prevention: same learning as #2.
4. **AC6 anchor baseline was environment-dependent (120 vs 121)** — Recovery: restated as a delta. — Prevention: same learning as #2.
5. **#8842 admin-merge aborted on DIRTY (`plan-sharp-edges.md` sibling append)** — Recovery: union-resolved both bullets, re-armed. — Prevention: the gated script already refuses non-CLEAN; one-off.
6. **Admin-merge Monitor expired silently because `tail -n` buffers until exit** — Recovery: `grep --line-buffered`. — Prevention: covered by the Monitor/poll guidance in `ship/SKILL.md`; one-off here.
7. **one-shot aborted on a closed `#N` in its args (Step 0a.5 gate)** — Recovery: scrubbed to dated prose. — Prevention: gate worked as designed; one-off.
8. **`pgrep -af` blocked by the self-match guard** — Recovery: dropped the pre-check. — Prevention: already hook-enforced (`pkill-self-match-guard.sh`).
9. **Two ship/SKILL.md replacement sentences exceeded the ≤0-byte budget** — Recovery: third wording at 113 ≤ 114 B, asserted in the edit script. — Prevention: the assertion in the edit caught it; one-off.
10. **Push rejected non-fast-forward after the rebase** — Recovery: `range-diff` confirmed the remote held only pre-rebase copies, then `--force-with-lease=<branch>:<old-sha>`. — Prevention: one-off; the lease pin is the right shape.
11. **My M1–M5 battery never mutated the `skipIf` call sites; review found CI could go green with the calibration skipped (P1)** — Recovery: `resolveCalibrationScope` + CI sentinel + `afterAll` ran-both; mutants MA/MB measured rc 1. — Prevention: routed to `plugins/soleur/skills/plan/references/plan-sharp-edges.md` (work/SKILL.md is at its body-budget ceiling) (a conditional check owes a CI-side "it ran" assertion).
12. **Reviewer's prototype drift regex `(^|/)SKILL\.md$` would have blocked commits to codex/devin mirror SKILL.md files** — Recovery: corpus-shaped regex + a mirror unit row. — Prevention: Key Insight above; grep `git ls-files '<dir>/**/<basename>'` for non-corpus members before keying a guard on a basename.
13. **Review ran at 5/10 seats (proportional per operator)** — Recovery: disclosed in the `Reviewed-Coverage` trailer; brand-survival threshold `none`. — Prevention: one-off, operator-directed.
