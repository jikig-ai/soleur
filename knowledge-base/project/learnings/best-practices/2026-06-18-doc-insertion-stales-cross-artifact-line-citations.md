# Inserting lines into a doc stales every line-number citation that points INTO it

## Problem

A docs-only ops-remediation PR (#5548, re-arm Inngest reminders) appended a 10-line
blockquote callout into `inngest-oneshot-and-reminder-patterns.md` §A. That single
insertion shifted all subsequent runbook content down ~10 lines, silently staling the
line-number citations that **sibling planning artifacts** pointed at the same runbook:

- the plan (`…-plan.md`) cited the blessed `sentry-issue-rate` payload at `…patterns.md:71-74` (now `:81-84`) and the ~24h dedup note at `:126` (now `:132`);
- `tasks.md` and `session-state.md` carried the same stale `:71-74`.

The citations were correct when written (against `origin/main`) and were broken by **this
same PR's own edit** — so they are `pr-introduced`, not pre-existing. tsc/tests are blind
to prose line numbers; two review agents (pattern-recognition + code-quality) independently
caught them as P2 by following each cite and landing on the wrong block.

## Solution

Fixed inline (provenance = pr-introduced → no scope-out): re-grepped the true current
lines (`grep -n` the payload fence + dedup bullet) and updated every stale citation across
plan + tasks + PIR + session-state in the same review pass.

## Key Insight

When a PR **inserts or deletes lines** in a doc that other artifacts cite by line number,
every `path.md:N` (or `:N-M`) pointing into that doc below the insertion point goes stale —
even citations in files the PR is not "about". Two cheap defenses:

1. **Prefer insertion-stable references** — cite a section anchor / heading / fenced-block
   label (`§A "Worked example: sentry-issue-rate"`) instead of a bare line range when the
   target doc is churn-prone.
2. **If you must use line numbers, re-derive them after the edit** — after inserting into
   `<doc>`, `grep -rn '<doc-basename>:[0-9]' knowledge-base/` and fix every hit in the same
   edit cycle. The grep is one line; the cost of skipping it is a P2 round-trip at review.

This is the cross-artifact analogue of the in-code self-citation fragility in
[[2026-06-18-in-code-comment-rewrites-self-citations-and-forbidden-literal-quotes-are-fragile]]
and the same class as `hr-when-a-plan-specifies-relative-paths-e-g` (the doc is authoritative
for intent, never for exact offsets).

## Session Errors

- **Cross-doc line-citation drift (P2, recurring).** §A blockquote insertion shifted runbook
  content +10 lines; `:71-74`→`:81-84`, `:126`→`:132` stale in plan/tasks/PIR/session-state.
  Recovery: re-grep + fix all citations inline. Prevention: cite section anchors for
  churn-prone docs, or re-grep `<doc>:[0-9]` after any insertion.
- **Edit tool "modified since read" (one-off).** Ticked plan checkboxes via out-of-band
  `perl -i` after the Edit tool's read snapshot, invalidating it; two Edits failed.
  Recovery: re-read then Edit. Prevention: make checkbox/state edits through the Edit tool
  (which the harness state-tracks), or re-Read after any shell-level in-place edit.

## Tags
category: best-practices
module: knowledge-base / docs-citations
