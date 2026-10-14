---
title: "My guards read source through a comment stripper that deleted the code they guard"
date: 2026-09-23
category: test-failures
module: apps/web-platform/test (source-walk guards), server/inngest model tiers
issue: 8603
pr: 8639
tags: [guard-vacuity, comment-stripping, source-walk, claude-cli, effort, mutation-testing, review]
---

# Learning: my guards read source through a stripper that deleted the code they guard

## Problem

PR #8639 pinned `--effort high` on the six audit crons (`AUDIT_CLI_ARGS` in
`model-tiers.ts`) and added CI guards over the pinned `@anthropic-ai/claude-code`
bundle (#8603). A self-run 25-row mutation battery reported every row as expected.
A 10-seat review panel still found 2 P1 and ~11 P2, almost all in the guards:

1. **The shared comment stripper deleted real code.** `stripComments` used
   `src.replace(/\/\*[\s\S]*?\*\//g, "")` before handling `//` lines. A `/*` inside a
   `//` comment (`bot-fix/*`, `functions/*.ts`) opens a phantom block that runs to the
   next `*/`: 246 lines of `_cron-shared.ts`, 326 of `cron-inngest-cron-watchdog.ts`,
   and 47 lines of `model-tiers.ts` (including its import) vanished from every walk.
   Two comment-only edits could hide a raw model literal from Guard 1 and from the
   Guard 2 id harvest. This exact regex-not-lexer class was already documented in
   `best-practices/2026-06-12-source-scan-containment-gate-call-detection-and-fail-closed-lexing.md`
   — and I promoted the regex helper to a SHARED one anyway.
2. **Guard 1 matched a token, not the property.** `/\.\.\.AUDIT_CLI_ARGS\b/` accepted
   `...AUDIT_CLI_ARGS.slice(0, 2)` (drops `--effort`), a hoisted copy spread after
   `"--"`, and a second `"--model"` after the spread. The CLI's other model/effort
   channels (`--fallback-model`, `--settings`/`--agents` JSON, `effortLevel`,
   `CLAUDE_CODE_EFFORT_LEVEL`) were unguarded.
3. **The warning needle lived in four places.** The substrate's Sentry matcher, the
   probe's constant, and two fixtures each spelled `Unknown --effort value`; the
   test header told a future maintainer to "update EFFORT_WARNING" on a CLI reword —
   which keeps CI green while the production mirror goes silently dead.
4. **A claim the ADR made was unbacked.** The amendment said execution-tier effort
   drift is "visible"; nothing extracted `default_effort` from the bundle.
5. **The probe proved less than it read.** `--version` exits before any model lookup,
   so the Guard 3 spawn validates the effort VALUE against the CLI's global enum and
   says nothing about whether the model row supports effort.

## Solution

- `test/helpers/strip-comments.ts` now takes comment ranges from the TypeScript
  parser (`getLeadingCommentRanges`/`getTrailingCommentRanges` at every token,
  punctuation included) and blanks them to spaces, keeping newlines — a self-test
  pins "`// a/*b` does not eat the next line", a comment before a closing `}`, and
  equal line counts per file.
- Guard 1: whole-line `^\s*\.\.\.AUDIT_CLI_ARGS,\s*$` inside `CLAUDE_CODE_FLAGS`,
  before the single `"--"`; no other tuple use; no `--model` capture in an audit cron;
  new G1-f banning the other channels; a positive control per walk pattern.
- One `CLI_EFFORT_FALLBACK_NEEDLE` in `model-tiers.ts`, read by the substrate and the
  probe; the mirror goes through `formatTailForSentry`.
- `REVIEWED_DEFAULT_EFFORT` pins each CLI-reaching tier's `default_effort` read out of
  the bundle's model-table row (`{id:"<id>",family:…` up to `},{id:"`), plus the audit
  row's `effort` capability — so a CLI bump that moves either default reds CI.
- `audit-models.sh [2b]` gained the same left boundary as its CI twin.

A second 16-row battery over the review fixes left one survivor: deleting the
capability check stayed green because the real bundle always satisfies it — a
fixture gap, closed by extracting `tierRows()` and testing it on a synthesized row
without `effort`.

The same regex stripper was hand-copied in 13 other test files. All of them now
import the shared helper (the SQL stripper in a migrations test and the
shell-aware one in `resend-sender-domain.test.ts` stay local by design).

## Key Insight

A source-walk guard inherits every blind spot of the text transform in front of it,
and no mutation of the guard's assertions can reach that transform. When you build
or promote a comment stripper, parse — never regex — and give it a self-test with
`/*` inside a `//` comment. When a guard's regex names a token (`...X\b`), ask what
else can follow the token on that line. When runtime code and a test's positive
control match the same vendor string, make it one constant, or the documented
"update the test" step disarms production. And when a PR's own ADR says drift is
"visible", name the test that reds — if there is none, the word is prose.

## Session Errors

1. **Watched the wrong deploy arm for #8601.** The session's loaded ship skill said to
   select the deploy run by the merge SHA; a `workflow_run` run carries `main`'s tip
   at trigger time, so run 35889174381 was deploying the previous commit. —
   **Prevention:** `deploy-arm.sh find` (current `origin/main` ship skill already
   routes through it, #8492); re-read a skill from `origin/main` when a session has
   compacted across a long pipeline.
2. **The repo-root checkout is detached and 145 commits behind**, so its
   `cleanup-merged` kept a merged branch ("no merge evidence"). — **Prevention:** run
   `cleanup-merged` from a detached `origin/main` worktree's copy of the script (did
   so; it reaped). Surfaced to the operator.
3. **`git rev-parse HEAD` at the repo root failed** (no HEAD). — **Prevention:** run
   git queries from a worktree.
4. **Hook blocks: foreground `sleep 45`; self-matching `pgrep -f`.** — **Prevention:**
   Monitor for waits; `pgrep` without `-f` or capture PIDs.
5. **First commit refused by the typecheck hook: TS2769, `NODE_ENV` missing from a
   `spawnSync` env literal** (Next augments `ProcessEnv`). — **Prevention:** run
   `./node_modules/.bin/tsc --noEmit` before the first commit of any new test that
   builds an explicit env; add `NODE_ENV` (the `roster-entry-gate.test.ts` precedent).
6. **`console.log` evidence line never printed** — vitest drops console output from
   passing tests in this config. — **Prevention:** `process.stdout.write` for any line
   a CI log grep depends on.
7. **Battery rows went VOID/invalid**: an anchor (`AUDIT_EFFORT = "high"`) that also
   matched the header comment, and a `void (a, b,)` rewrite that was a syntax error.
   The harness's landing guard (exact-once count + sha changed) caught both. —
   **Prevention:** anchor mutations on the declaration form (`export const X =`), and
   treat a row with "no tests" as UN-RUN, never as a verdict.
8. **The background battery notified `exit code 0` while it wrote `BATTERY_RC=1`.** —
   **Prevention:** read the rc line from the log, never the notification.
9. **Write refused because the file changed since read** (my own earlier `sed`). —
   **Prevention:** after a shell edit, Read before a wholesale Write.
10. **A compound `cd apps/web-platform && …` failed on a drifted CWD**, so one re-run
    silently did not run. — **Prevention:** absolute `cd` in every chained command.
11. **Review found 2 P1 + ~11 P2 in the guards this PR added** (above). —
    **Prevention:** before the panel, mutate the TRANSFORM the guard reads through,
    not only its assertions; grep learnings for the helper's defect class before
    promoting a local helper to a shared one.
12. **A review-added guard survived its own mutation** (capability check always
    satisfied by the real bundle). — **Prevention:** every check against a real
    artifact needs a synthesized fixture on the failing side.
13. **My parser-backed replacement had its own blind spot.** Collecting comment
    ranges only at AST nodes (`forEachChild`) missed a comment directly before a
    closing `}` — leading trivia of a punctuation token. Migrating the 13 other
    regex copies (the CONCUR gate DISSENTed on filing them as a tracker: same
    top-level directory, three of them scan this PR's own crons) surfaced it
    immediately in `installation-id-source-of-truth.test.ts`. — **Prevention:** walk
    every token (`node.getChildren(sf)`) and pin a before-brace case in the
    self-test; migrating consumers is itself a test of a new shared helper.
14. **Plan overclaims corrected at review:** "walk (c) proves completeness";
    "abortedByTimeout surfaces an overrun" (the Sentry 60-min check-in margin fires
    first for the 60/70-min crons). — **Prevention:** falsify each "proves"/"surfaces"
    sentence with the command or config that owns it before writing it.

## Tags

category: test-failures
module: apps/web-platform/test, server/inngest
