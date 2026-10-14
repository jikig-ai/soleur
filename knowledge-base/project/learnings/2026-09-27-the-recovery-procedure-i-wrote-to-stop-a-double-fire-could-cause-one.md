---
title: The recovery procedure I wrote to stop a double-fire could cause one
date: 2026-09-27
category: workflow-issues
module: inngest-cutover
tags: [inngest, cutover, runbook, double-fire, doppler, jq, verification]
issue: 6939
pr: 8886
---

# Learning: the recovery procedure I wrote to stop a double-fire could cause one

## Problem

#6939: `op=verify` printed a `soleur:trigger-cron --function-id … --missed-tick …` line per empty
(function, bucket) pair. The flags do not exist, and the list included buckets a slower cron was
never due in, so acting on it double-fired the cron. The fix gated the list behind a default-off
`missed_tick_candidates` input and made the runbook's § Bounded-outage note the single recovery
procedure.

The review panel found that the replacement procedure had the same failure mode as the defect it
replaced. Its check (b), "the cron's Sentry monitor shows a missed check-in", is satisfied by two
ticks that must NOT be re-fired:

- a tick the scheduler drains itself on resume — ADR-100's 2026-09-19 addendum measured each missed
  tick firing exactly once when the host resumed, which contradicts the runbook sentence "Ticks
  missed in-window are not backfilled" that I had carried forward without checking;
- a tick that ran but whose best-effort heartbeat was lost.

## Solution

- Re-order the procedure so the authoritative record is read first: `public.routine_runs`
  (`routine_id` = fnId, written for every cron in `EXPECTED_CRON_FUNCTIONS`) must show no run since
  the tick, read AFTER the host has resumed. The Sentry check (matched on `expectedTime`, not
  `dateCreated`) comes second, and any read error means "do not re-fire".
- Run every prescribed command live before shipping it. Two were broken:
  `doppler run -- psql "$DATABASE_URL_POOLER"` expands the variable in the CALLER's shell before
  Doppler sets it (empty → local socket error). The fix is `doppler run -- sh -c 'psql "$DATABASE_URL_POOLER" -c "$0"' '<sql>'`.
  The same file carried two pre-existing lines with the identical bug; fixed and re-run.
- Anchor jq shape filters with `\A…\z`: jq's `$` also matches before a trailing newline, so
  `test("^[A-Za-z0-9._-]{1,128}$")` accepts `"fn-h\n"`, which `jq -r` then prints as the real `fn-h`.
- Guard the defect itself, not its two known spellings: the planned Guard 1 banned only the two
  flags, so an `--event` re-fire list re-added to the `verify)` arm stayed green. The suite now bans
  any non-comment `soleur:trigger-cron` and pins the call's neighbours, sole caller and sole env read.

## Key Insight

A procedure written to replace a harmful instruction inherits the harmful instruction's failure
mode unless each of its checks is asked the same question the defect failed: *which states satisfy
this check while the action is still wrong?* Here the answer was "a drained tick" and "a lost
heartbeat", and the evidence for the first was an ADR addendum one grep away. Every universal claim
added to operator prose ("not backfilled", "returns 403", "every monitor pages") is a measurement
to take before it is written — three of mine were false and each fell to one command.

## Session Errors

1. **Planning-brief premise drift** (block in `scripts/`, ADR-143 → ADR-146). Recovery: the planning subagent re-derived both. **Prevention:** already covered by plan premise validation.
2. **RED run aborted mid-suite** — a `grep -nF … | tail | cut` capture with no match died under `set -euo pipefail`. Recovery: `|| true` on every capture pipe. **Prevention:** wrap every command-substitution pipe whose first stage can legitimately match nothing in `{ …; } || true` at authoring time.
3. **A global `replace()` rewrote an unrelated pre-existing test line** (`LK_LASTG3_LN`). Recovery: code-quality review caught it; reverted and confirmed with a merge-base diff. **Prevention:** `assert s.count(old) == 1` on EVERY scripted replace, not only the anchored ones; diff against `git merge-base` afterwards.
4. **6 of 11 mutations did not land** — `\$` inside a single-quoted inline Python became a literal backslash. Recovery: the landing guard reported it; mutators moved to a quoted script file. **Prevention:** write mutators to a file; never inline Python with `$` in a bash string.
5. **`sleep 60` blocked by the hook.** Recovery: `until` loop in a background Bash. **Prevention:** one-off; the hook message states the pattern.
6. **Affected gate queued behind a sibling's lock.** Recovery: killed (rc 143, not a verdict) and ran the targeted ratchets per the operator's rely-on-CI ruling. **Prevention:** covered.
7. **`.git/info/exclude` absent in a worktree gitdir.** Recovery: none needed (never staged the dir). **Prevention:** one-off.
8. **All 10 review agents hit the weekly API limit (HTTP 429).** Recovery: resumed via `SendMessage` in batches of 3–4; all 10 completed with context intact. **Prevention:** covered by review Gate 2b (resume, do not respawn).
9. **`doppler run -- psql "$VAR"` outer-shell expansion** in my new step and two existing lines. Recovery: `sh -c '… "$VAR" …' "$0"` form, run live. **Prevention:** route-to-definition bullet in plan-sharp-edges (below); run every prescribed command once.
10. **Carried "not backfilled" forward, contradicted by ADR-100's addendum** — the P1. Recovery: procedure re-ordered around `routine_runs`. **Prevention:** before writing a universal claim about the system into operator prose, grep the owning ADRs for dated addenda that measure it.
11. **Rewrote a dated ADR-146 line with a false justification.** Recovery: restored verbatim, dated note appended. **Prevention:** covered by the append-only rule; `git diff origin/main -- <ADR> | grep '^-'` must be empty.
12. **"Every monitored cron opens an issue"** — measured 68 of 71. Recovery: corrected in plan and runbook. **Prevention:** same as 10.
13. **"`SENTRY_AUTH_TOKEN` returns 403 for this read"** — measured 200 on check-ins (the hard rule's 403 is about issues). Recovery: claim removed; no sibling runbook was actually broken. **Prevention:** same as 10 — a rule's scope is its text, not its neighbourhood.
14. **Guard 1 banned the spelling, not the defect.** Recovery: non-comment `soleur:trigger-cron` banned; call wiring pinned. **Prevention:** for a guard, name the implementation a reasonable engineer writes next that satisfies it while restoring the defect.
15. **jq `$` accepts a trailing newline.** Recovery: `\A…\z` plus a fixture. **Prevention:** anchor shape regexes with `\A…\z` in jq.

## Tags

category: workflow-issues
module: inngest-cutover
