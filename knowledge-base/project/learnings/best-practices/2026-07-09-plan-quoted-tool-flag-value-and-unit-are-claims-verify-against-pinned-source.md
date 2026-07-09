---
title: A plan-quoted tool-flag value/unit is a claim to verify against the pinned tool's source — units especially
date: 2026-07-09
category: best-practices
tags: [verify-before-assert, tool-flags, units, inngest, plan-preconditions, hr-verify-repo-capability-claim-before-assert]
issue: 6258
pr: 6265
---

## Problem

The #6258 plan prescribed the inngest durable ExecStart flags as `OPEN=5 IDLE=2 SECS=30`
— the variable was literally named `SECS` and the reasoning read "`SECS=30` closes idle
conns fast so they release the Supavisor session." The intent was a **30-second** idle
drain.

But `--postgres-conn-max-idle-time` on `inngest start` is an **`IntFlag` in MINUTES**
(default 5), not seconds. Shipping `30` would have set a **30-minute** idle timeout —
the *opposite* of the intended fast drain, and worse than the default. The idle-drain
lever (release pinned Supavisor sessions so cutover-probe scans can't ratchet the pool to
`EMAXCONNSESSION`) would have been defeated silently: tests pass, typecheck passes, the
flag is accepted by the binary, and the bug only manifests as a still-ratcheting pool in
production.

## Root cause

`framework-docs` research had confirmed the flag *exists* but not its *unit*. The plan's
`SECS=30` was a plausible-but-unverified value that rode straight through deepen-plan and
into the tasks/ACs. `hr-when-a-plan-specifies-relative-paths-e-g` already establishes that
plan-quoted **paths/globs** are claims to verify; `hr-verify-repo-capability-claim-before-assert`
covers **capability** claims. This is the same class applied to a tool-flag's **value and
unit**: the plan is authoritative for *intent* (fast idle drain), never for the *literal
value* that realizes it.

## Solution

During /work Phase 0.1 (verify CLI flags exist in the pinned version), don't stop at
"the flag exists" — verify its **type, unit, default, and validation** against the pinned
version's source/`--help`:

```
# pinned version from inngest.tf locals: v1.19.4
WebFetch https://raw.githubusercontent.com/inngest/inngest/v1.19.4/cmd/start/cmd.go
  → "--postgres-conn-max-idle-time" is IntFlag, Usage "…in minutes…", default 5
  → "--postgres-max-idle-conns" default 10; validation: idle-conns ≤ max-open-conns
  → "--postgres-max-open-conns" default 100; validation: must be > 1
```

The unit discovery flipped the shipped value: `--postgres-conn-max-idle-time 1` (1 minute
= fastest non-zero drain; `0` means *unlimited* in Go's `database/sql`, the opposite
again). Fixed inline as a mechanical units correction (not an architecture fork — a ≤10-line
correctness fix), then reconciled across every artifact (bootstrap, ADR-104, test, runbook,
health workflow) and the plan's own `SECS=30` mentions + AC1 verify grep.

## Key Insight

**A plan-quoted tool-flag VALUE is a precondition to verify against the pinned tool, not a
fact — and the UNIT is the highest-risk part.** A wrong unit (minutes/seconds/ms, bytes/KB,
count/percent) passes type-checking and the binary's own validation, so nothing but reading
the pinned source/`--help` catches it. When the plan names a flag value, before writing it:
(1) resolve the pinned version, (2) read that version's flag registration for type + unit +
default + validation, (3) confirm the value realizes the plan's stated *intent* in the real
unit, (4) pin the verification in the spec (`<!-- verified: DATE source: … -->`). Generalizes
`hr-verify-repo-capability-claim-before-assert` and `hr-when-a-plan-specifies-relative-paths-e-g`
from paths/capabilities to flag values/units. Sibling: [[2026-05-14-plan-prescribed-runtime-shapes-must-be-grepped-against-installed-version]],
[[2026-04-19-verify-reviewer-prescribed-cli-flags-before-applying]].

## Session Errors

1. **Plan unit error (minutes vs seconds)** — see above. Recovery: WebFetched inngest
   v1.19.4 `cmd/start`, corrected `30`→`1` across all artifacts. Prevention: /work Phase-0
   flag verification must confirm unit + default, not just existence (this learning +
   the work-skill bullet it routes to).
2. **`curl`-parity test false-tripped twice** — `cutover-inngest-workflow.test.sh` asserts
   `count('curl ') == count('--max-time')`; the naive `grep -c 'curl '` also counts prose
   mentions ("on a curl failure", "`$(curl …)`") in comments/error strings, so a workflow
   comment that says "curl " (with a trailing space) fails a *correct* file. Recovery:
   reword prose to avoid the literal `curl ` where it is not an actual invocation
   (`curl(rc=…)`, "the 2>/dev/null redirect", "a bare `$(…)` capture"). Prevention: when
   editing a `.github/workflows/*.yml` that has a curl/max-time count-parity test, keep
   "curl" out of prose, OR (deferred, riskier) anchor the parity count on the invocation
   shape (`\$\(curl|^\s*curl (--|-)`) rather than the bare token. Same family as the
   grep-over-body-false-matches-own-comments trap.
3. **AC6 grep false-matched own comment** — the `inngest.tf` correction quoted the
   falsified phrase "holds inngest…under 15" to refute it, tripping AC6's
   `grep -c 'holds inngest' = 0`. Recovery: reword the refutation to drop the literal
   ("bounded inngest's TOTAL … under 15"). Prevention: known class — when a correction must
   *mention* a forbidden literal to negate it, paraphrase so the literal is absent.
4. **inngest.tf edit (+10 lines) staled cross-file line-range citations** in `git-data.tf`
   (`inngest.tf:258-288`/`:267-271`/`:313-319`). Recovery: uniform +10 shift (the edit's
   net delta was +10, so every citation below the edit point shifts by exactly that).
   Prevention: known class ([[2026-06-18-doc-insertion-stales-cross-artifact-line-citations]]).
5. **ADR ordinal collision** — plan said ADR-103; sibling #6242 merged ADR-103 while this
   branch was open. Recovery: rebased onto origin/main, re-derived next-free = ADR-104,
   swept all ADR-103 refs in the spec/plan. Prevention: known class (verify ADR number vs
   origin/main at ship; the plan already flagged the ordinal provisional).
6. **One review agent returned degenerate output** (0 tool calls, echoed a system-reminder
   instead of findings). Recovery: ran that agent's mechanical cross-file consistency checks
   inline via grep. Prevention: known class (review agents can stall/degenerate — proceed
   with partial coverage per the Rate-Limit-Fallback gate; substitute inline checks for a
   dead agent's mechanical scope).
