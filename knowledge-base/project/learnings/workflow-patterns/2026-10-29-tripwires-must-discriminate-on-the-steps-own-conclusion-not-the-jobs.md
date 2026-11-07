---
title: "A drift tripwire must discriminate on the step's own conclusion — the job's conclusion cannot tell a designed skip from drift"
date: 2026-10-29
tags: [followthrough-probe, tripwire, plan_only, truncation-doctrine, roster-anchor, pipefail]
---

## Problem

Three silent-shrink/false-alarm classes surfaced in one review fix-round on the `web-first-deploy-10585.sh` standing probe (PR #11500):

- **A tripwire keyed on the JOB's conclusion false-fires on input-gated steps.** `web_host_replace` jobs skip the `Surface fresh-host Sentry breadcrumb trail` step under `plan_only=true` (the step is `if: always() && plan_only != true`), yet the JOB still concludes `success`. A "success job + zero trail lines = drift" tripwire therefore fires on every rehearsal for 30 days — and as a mid-enumeration `exit 3` it outranked a real OVERDUE from other runs, reintroducing the exact precedence inversion the verdict loop had just fixed. The discriminator was already in the fetched payload: REST `jobs[].steps[].conclusion` — emit the step's own conclusion in the `--jq` TSV; `skipped` = designed absence (contributes nothing), `success`+empty = real drift.
- **Paginated enumerations need cap-tripwires at EVERY level, not just the outer one.** `-L 100` on `gh run list` was tripwired, but the `jobs?per_page=100` read had the identical silent-shrink shape — `.total_count > (.jobs|length)` in the same `--jq` is the free guard.
- **`awk|grep -q` under `pipefail` flips a match to a miss via SIGPIPE** — `grep -q` exits on first match, awk dies 141 past the pipe buffer, and the pipeline status reads false. Capture the block once (`roster_block=$(awk …)`) — then awk's rc is inspectable AND an empty anchor block while the owed set is non-empty reads as CANNOT ESTABLISH, not quiet-2. An unguarded `variable "x" {` anchor is the same class as an unguarded emitted literal: the suite's emitter-parity greps must cover EVERY cross-file anchor the probe consumes (emitted literals, step names, job-name keys, variable declarations).

## Prevention

- When a tripwire infers "the step ran" from the job's conclusion, fetch the step's own `conclusion` (or presence) and gate on that — input-gated `if:` conditions on steps are invisible at the job level.
- Every bounded enumeration (`-L`, `per_page`, `LIMIT`) earns a count-equals-cap → CANNOT ESTABLISH arm in the same hunk; a silent shrink reads as a quiet verdict on a standing notify-only probe.
- Never `awk|grep -q` under `set -o pipefail` on an unbounded intermediate — capture, then grep a herestring; and treat "the anchor block parsed empty while obligations exist" as unmeasured (exit 3).
- Emitter-parity greps should pin every foreign literal a probe derives from — emitted log lines, step names, job keys, and declaration anchors — because the suite that synthesizes the fixture cannot see a production drift.

Found by the PR #11500 fix-round panel (five seats, `git diff <panel-sha>..HEAD`); fixed inline. Companion doctrine: the probe's never-quiet-on-unmeasured exit vocabulary is what makes these tripwires safe to add — every false positive reads loud, never quiet.
