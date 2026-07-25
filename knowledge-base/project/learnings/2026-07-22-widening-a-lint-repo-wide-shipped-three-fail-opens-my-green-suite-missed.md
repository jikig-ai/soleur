---
title: Widening a lint repo-wide shipped three fail-opens my own green suite missed
date: 2026-07-22
category: test-failures
tags: [lint, fail-open, bun-glob, code-review, gh-search, truncation, mutation-testing]
issue: 6793
---

# Learning: widening a lint repo-wide shipped three fail-opens my own green suite missed

## Problem

#6793 extended the #6786 `gh (pr|issue) list --search` collision-gate lint
(`plugins/soleur/test/components.test.ts`) two ways: widen the scan from
`plugins/soleur/skills/**` to a repo-wide executable-surface allowlist, and add a
`-L`/`--limit` truncation detector (`findUnlimitedProbes`). The first cut passed
its own suite **1281/0 green** — and shipped **three latent fail-opens** in the
detector, none of which the green suite could see. All three were caught by
multi-agent review, and all three are the *exact* silent-open failure class the
lint exists to catch — the third recurrence of the 2026-07-20 "the lint I wrote
to catch a fail-open shipped the same fail-open" pattern
([[2026-07-20-the-lint-i-wrote-to-catch-a-fail-open-shipped-the-same-fail-open]]).

## Root cause — three independent fail-opens

1. **Bun `Glob` defaults `dot: false`, so a repo-scan silently skips every
   dot-directory.** `new Glob(glob).scanSync(REPO_ROOT)` matched **zero files**
   for `.github/workflows/**`, `.github/actions/**`, `.claude/hooks/**`,
   `.openhands/hooks/**` — the highest-value CI + hook surface the plan claimed to
   cover. The offender assertions (`findUnlimitedProbes(corpus) === []`) passed
   vacuously against an *absent* surface class, masking two live offenders
   (`apply-deploy-pipeline-fix.yml`, `cla-evidence-timestamp.yml`). A `git grep`
   during /work Phase 0 *did* see those dirs (git grep does not skip dot-dirs), so
   the discrepancy between "my grep found the surface" and "my lint scans the
   surface" was invisible until a reviewer mutation-probed the corpus with
   `{ dot: true }`.

2. **Widening a line-bounded extractor to join `\`-continuations reintroduced
   launder-by-neighbor across statement separators.** The `-L` detector needs
   whole-command capture (a `select(`/`--limit` on a jq continuation line must be
   seen — it is what makes the `content-publisher.sh` select-after-truncation case
   *detectable*). But a joined logical line can chain `cmd1 && cmd2` where only
   `cmd2` carries `--state`/`-L`; the greedy `GH_LIST_CMD` then captures both as
   one probe and `cmd2`'s flags launder `cmd1` — the #6786 bug, reborn.

3. **The narrowing predicate enumerated the *examples*, not the *invariant*.**
   `POST_SEARCH_NARROWING = /select\(|length/` caught the two shapes the plan named
   but not the class: *any* post-search operation whose answer depends on the full
   set. `sort_by(.createdAt) | .[0]` (an extreme-picker) was wrongly exempted — the
   true min/max can be evicted past the 30-row cap before the reorder runs.

## Solution

- **`dot: true` + a per-surface non-empty guard.** `scanSync({ cwd: REPO_ROOT,
  dot: true })`, plus a test asserting each surface class (`md`/`sh`/`yaml`) AND a
  dot-directory (`.github`/`.claude`) is represented in the live corpus — so a
  future dot-glob regression red-lines instead of passing vacuously.
- **Handle fence/comment on PHYSICAL lines and split logical lines on
  `&&`/`||`/`;`** (never on a single `|` pipe — the jq drill is part of the same
  command). This also fixes a sibling false-negative: a `.sh`/`.yaml` comment line
  ending in `\` no longer swallows the real probe on the next line.
- **Encode the invariant, not the examples:** add `sort_by`/`min_by`/`max_by`/
  `group_by`/bare-`sort`/`last` to `POST_SEARCH_NARROWING`.

## Key Insight

**A green suite over a scanner is evidence about the mutations you imagined, not
about the surface you claim to cover.** Three multipliers made the holes
invisible to my own run and visible only to adversarial review:

1. **A repo-scan's blind spot is a coverage claim, not a code claim.** When a test
   asserts `offenders === []` over a globbed corpus, the load-bearing question is
   "is every declared surface actually *in* the corpus?" — never assume the glob
   engine's defaults match your intent. Bun `Glob` is `dot:false`; a coverage scan
   must pass `dot:true` AND assert per-surface non-emptiness. Cross-check the
   scanner's file list against an independent `git grep` when the two should agree.
2. **Widening an extractor can reintroduce the exact bug it was hardened against.**
   Every capability you add to see MORE (continuation-joining) can also see WRONG
   (chained-command launder). Re-run the original defense's negative controls after
   any extraction/widening, and add a control for the new seam.
3. **A detector exemption must pin the invariant, and each alternative in the
   predicate needs its own mutation-proof control.** `\blength\b`, the `#` anchor
   in `linked:issue #`, and "`-L` not matched inside `--label`" all survived
   mutation green until a control was added per alternative — the review's
   "a mutation battery only covers what you mutate" rule applied to my own detector.

The mechanical fix that would have caught all three at authoring time: mutation-
test each detector branch on a sandbox copy, and assert the live corpus contains
every surface class before trusting an empty offender list.

## Session Errors

1. **`git grep … | grep -vE '--state'` — `--state` parsed as a grep option**
   (ugrep: `invalid option --state`). Recovery: restructure the pipeline / use
   `grep -v -e` or `--`. Prevention: when a grep PATTERN begins with `-`, pass it
   after `--` or via `-e`. One-off.
2. **Round-1 detector shipped 3 fail-opens the 1281/0 green suite missed** (dot-glob
   scan skip; statement-separator launder; reorder-after-search). Recovery: fixed
   inline after multi-agent review. Prevention: the Key Insight above — surface-
   representation guard + per-branch mutation control + re-run the defended negative
   controls after any extractor widening. Recurring.
3. **Offender set (24) was ~3× the plan's illustrative 8.** Not a defect — the `-L`
   detector applies to the whole already-scanned corpus; the plan explicitly
   delegated authoritative enumeration to /work ("re-derive; fix every flagged
   site"). Prevention: treat a plan's illustrative fix list as a starting
   hypothesis; the RED offender list from the implemented detector is the work-list
   ([[2026-05-18-sweep-class-fixes-grep-enumerated-not-intuited]]). One-off.
4. **`sweep-followthroughs.test.sh` broke (3 fails)** after migrating the closed
   query from in-query `state:closed` to an explicit `--state closed` flag (behavior-
   equivalent; the lint's convention is an explicit `--state` flag). Recovery:
   updated the mock dispatcher (`*"--state closed"*`) + the drift assertion.
   Prevention: when a lint-driven change edits a real script's command form, grep
   the script's own `.test.sh` for the old literal in the same edit cycle. One-off.

## Tags
category: test-failures
module: plugins/soleur/test/components.test.ts
