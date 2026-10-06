---
title: "A refuse-before-send guard turned a paging 401 into a silent skip — the conversion moved the failure into a marker class that never pages"
date: 2026-10-06
category: integration-issues
tags: [argv-bearer-sweep, curl-stdin-config, observability, better-stack, review-panel, guard-vacuity-floor, subagent-reports]
issue: 9597
pr: 9654
branch: feat-one-shot-argv-bearer-sweep-tier2-residual
---

# Learning: a refuse-before-send guard changes WHICH failure fires, not only whether one does

## Problem

Moving a Resend key off curl's argv onto its stdin config needs a token-shape guard first (a quote or
newline in the value would inject a directive). I wrote the refusal as the script family's existing
`SOLEUR_<UNIT>_SEND_SKIPPED reason=token_shape` row. For `disk-monitor` and `resource-monitor` the
Resend email is the ONLY alert channel, and the Better Stack alert matches `_SEND_FAILED` / `_REFUSED`
only — `SEND_SKIPPED` never pages by construction. Before the change a malformed key reached Resend,
got a 4xx, emitted `SEND_FAILED` and paged. After it, the same fault was a quiet skip, and the cooldown
was still stamped. Three review seats (user-impact, observability, architecture) found it independently;
my own 153-row battery and every unit suite were green, because they asserted the refusal fired, not
that anything downstream heard it.

## Solution

Per unit: where Resend is the only channel the refusal is `SOLEUR_<UNIT>_REFUSED` (pages); where a Sentry
channel survives (`container-restart-monitor`, `cron-egress-alarm`) `SEND_SKIPPED` stays, because the
degraded channel is loud elsewhere. The betterstack guard baseline was re-pinned (65 passes / 9 cases) and
the runbook gained decode rows for `token_shape` and `bad_token_shape`.

## Key Insight

A guard that refuses before the network call replaces a failure the platform already reported (401 ->
SEND_FAILED -> page) with one the script reports itself, so the review question is "which sink hears the
refusal, and did the old failure page?" — not "does the guard refuse". Answer it per unit by reading the
alert predicate, never by reusing the sibling unit's marker.

## Session Errors

1. **A shell hook blocked a command whose heredoc BODY contained a forbidden process-matching spelling
   (twice — once in a brief, once in this very learning)** — Recovery: reworded, and wrote the file with
   the Write tool. **Prevention:** keep forbidden-command spellings out of any text sent through Bash; say
   "do not pattern-match other processes".
2. **Most panel seats ended on a tool call with no final report (about 9 of 12), and "completed"
   notifications fired per pause, not at the end** — Recovery: `SendMessage` "make no further tool calls,
   reply now with the report", then read the seat's last assistant text from its output with `jq` (never
   `Read`/`tail` the JSONL). **Prevention:** treat a transcript whose last block is `tool_use` as
   unfinished. (Not routed into the review skill: its body sits 3 bytes under the 477000-byte ceiling, so a Sharp Edge bullet fails `lint-skill-body-budget` until a block is extracted to `references/` first.)
3. **New anti-vacuity floors were invisible or unconstructible to `guard-vacuity-floor`** — `-ne N` floors
   are not recognised as floors, and a sentinel outside the harness vocabulary (`ANTI-VACUITY FLOOR` is
   upper-case; the grep is case-sensitive) scores CONSTRUCTION, growing the ratchet 15 -> 16. Recovery:
   `-lt N` literal on the `if` plus lower-case `anti-vacuity floor` text. **Prevention:** write floors in
   the form the harness derives (`if [[ $((PASS + FAIL)) -lt N ]]; printf 'anti-vacuity floor: …'; exit 1`)
   and run `scripts/guard-vacuity-floor.test.sh` after adding one.
4. **Repo lints that enumerate with `git grep` were run before the new test files were tracked** —
   `lint-supabase-deprecated-endpoints.sh` passed locally and would have failed CI on two new tests
   (`/v1/projects/` in a Flagsmith URL; a Management-API test without the pinned host literal). Recovery:
   pinned the host in the test, changed the probe URL. **Prevention:** run the pre-push lint set on a
   committed tree (or after `git add`), never with new files untracked.
5. **A planning subagent ended twice with an intent statement and no plan file (forwarded from
   session-state)** — Recovery: wrote the plan inline. **Prevention:** same as 2 — a subagent whose last
   message is a statement of intent has not delivered.
6. **Several seat "P2" claims were unverified assertions** (non-bash shebang on the zot scripts, piped
   `fs_api` bodies, a `cron-egress` reason overwrite) — Recovery: each refuted by one grep.
   **Prevention:** a seat's "unverified, needs a grep" item is the lead's grep to run, not a finding.
