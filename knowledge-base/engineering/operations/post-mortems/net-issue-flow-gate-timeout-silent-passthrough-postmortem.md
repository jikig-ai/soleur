---
title: "net-issue-flow blocking merge gate silently failed open on timeout (rc=124 → exit 0) — a coin-flip against an 8 s ceiling it measured 5.7–8.1 s against"
date: 2026-08-02
incident_pr: 7161
incident_window: "2026-07-20 (gate made BLOCKING in #6785) → 2026-08-02 (fixed in #7161). Intermittent throughout: 1 of 3 measured runs returned rc=124 on the plan-phase host."
recovery_at: "2026-08-02 (ceiling raised 8→25 s via the TO=() probe + RC=124 telemetry, both behaviourally tested, merged in #7161)"
suspected_change: "#6785 made the net-issue-flow surface BLOCKING and wrapped it in `timeout 8`. The gate's dominant cost is `gh issue list --state all --limit 500` (~4–5 s across 5 sequential paginated REST calls) plus two `gh pr view` calls — measured 7.7–8.1 s on one host and 5.7–6.3 s on another. The hook then translated any RC != 1 to `exit 0`, so a timeout was indistinguishable from a pass."
brand_survival_threshold: none
status: resolved
triggers:
  - control-failure (a blocking merge gate that intermittently did not block)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: this is a CONTROL failure in developer tooling, not a
# production availability or confidentiality event. The gate governs whether a PR may
# merge; its failure mode admitted net-positive PRs that should have been blocked. No
# user-facing surface, no customer data, no credential — the gate reads public repo
# metadata (issue/PR bodies) and writes only local telemetry. brand_survival_threshold
# is `none`. GDPR Art. 33/34 do not apply (no personal-data processing whatsoever).
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

The `net-issue-flow` gate blocks a PR whose `NET = FILED - CLOSING` exceeds 0. PR #6785
promoted it from advisory to **blocking** on 2026-07-20, wiring it as a `PreToolUse` hook
on `gh pr ready` / `gh pr merge` and wrapping the delegated script in `timeout 8`.

The hook's decision line is:

```bash
OUT="$(timeout 8 bash "$GATE" 2>&1)"
RC=$?
[[ "$RC" -eq 1 ]] || exit 0
```

`timeout` returns **124** when it kills the child. `124 != 1`, so the hook returned
`exit 0` — no deny, no `emit_incident`, no output distinguishing it from a clean pass.

The gate's own wall clock straddles that ceiling. Measured on the unmodified gate:

| Host | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| plan-phase | 7.7 s (rc 0) | **8.1 s (rc 124)** | 8.1 s (rc 0) |
| implementation | 6.1 s (rc 0) | 5.7 s (rc 0) | 5.9 s (rc 0) |

So for roughly two weeks a **blocking** merge gate was a coin flip on one host and
comfortable on another — and when it lost the flip it reported success.

This was discovered incidentally while sizing an unrelated change to the same gate. It is
recorded here per the standing rule that every detected incident gets a PIR, including one
found while doing other work.

## Impact

- **Blast radius:** every agent-driven `gh pr ready` / `gh pr merge` between 2026-07-20 and
  2026-08-02 whose gate invocation exceeded 8 s. On the slower host that is ~1 in 3.
- **What it admitted:** net-positive PRs merging without the block the gate exists to apply.
  The queue-growth metric #6769 soaks against was therefore measured against a gate that was
  not consistently enforcing.
- **What it did NOT affect:** no production surface, no user data, no credential, no deploy
  path. The gate is repo-workflow tooling only.
- **Silent by construction:** because the fail-open emitted no telemetry, there is no
  retrospective count of how many merges took the timeout path. That absence is itself the
  finding — see Action Items.

## Timeline

| When | What | Actor |
|---|---|---|
| 2026-07-20 | #6785 makes the gate blocking; wraps it in `timeout 8`. The gate's own header already enumerates four "silently always-pass" defect classes it was designed against. | agent |
| 2026-07-20 → 2026-08-02 | Gate intermittently returns rc=124 → hook exits 0. No telemetry, no operator signal. | — |
| 2026-08-02 | While planning the mandated-filing exemption, the plan phase measures the gate's wall clock as a precondition and observes 8.1 s / rc=124 on 1 of 3 runs. | agent |
| 2026-08-02 | Folded in as blocking prerequisite FR0 rather than deferred — adding ~1 s of work to a gate with negative headroom would have made the timeout certain instead of intermittent. | agent |
| 2026-08-02 | Fix merged in #7161: ceiling 8 → 25 s via the repo's `TO=()` probe, plus an RC=124 `warn` row under a dedicated `net-issue-flow-timeout` rule_id. | agent |

## Root cause

Two independent defects, both in the same three lines.

**1. The ceiling was set below the measured cost.** `timeout 8` was chosen against a gate
whose dominant cost is pagination — `gh issue list --limit 500` makes 5 sequential REST
calls for ~2 MB. Measured: a trivial authenticated call round-trips in 0.449 s, the full
issue list takes 4.127 s, and stripping 98.7 % of the payload saves only 1.45 s. So the
cost is call count, not transfer, and there is no payload-shrink alternative — bare-`#N`
matching requires the bodies. The gate has a hard ~4.1 s floor before any of its own logic
runs.

**2. The translation of the timeout was silent.** `[[ "$RC" -eq 1 ]] || exit 0` maps every
non-1 exit to a pass. That is correct for rc=0 (a real pass) and defensible for a crash
(fail-open so an outage cannot wedge every merge) — but it must not be *silent*, and it was.
The gate's own header condemns exactly this pattern four times over for its FILED query;
the hook reproduced it one level up.

A third, latent defect was found in review of the fix: `timeout` was **hardcoded**, so on a
host without coreutils `timeout` the invocation returns 127 — which the same `-eq 1` test
also maps to a silent `exit 0`. Stock macOS ships both bash 3.2 and no `timeout`, i.e. the
exact host where the fallback matters. This had never fired here but was one `brew`-less
machine away.

## What went wrong beyond the bug

- **The gate had no test for its own timeout path.** Its suite pinned the counting logic
  thoroughly (23 assertions, four separately-measured always-pass defects) and asserted
  nothing about what the hook does with a non-1 exit code.
- **"Fails open" was documented as a virtue without the "not silently" half being enforced.**
  The header said fail-open emits telemetry; the timeout path emitted none, and nothing
  checked that claim.

## Resolution

Both fixes are in #7161 and are behaviourally tested (they drive the hook and read its
decision, rather than grepping its source):

1. **Ceiling raised to 25 s**, via the repo's existing `TO=()` probe rather than a hardcoded
   `timeout`, so a host without coreutils runs the gate unbounded instead of silently
   fail-opening at rc=127. Test: a stub that sleeps 9 s must still DENY; and with `timeout`
   removed from `PATH` entirely, the gate must still DENY.
2. **RC=124 emits a `warn` row** under its own `net-issue-flow-timeout` rule_id, placed
   *above* the early exit (below it, the line would be present in the file and never
   reached — which is the mutation the test asserts against). `warn`, not `transient`,
   because `rule-metrics-aggregate.sh` counts only deny/bypass/applied/warn. A dedicated
   id, not the shared one, because the gate script already emits `net-issue-flow` + warn for
   every generic fail-open — sharing would re-conflate "the API was down" with "the gate was
   killed", two conditions with different fixes.
3. **A discriminating control:** a clean pass must emit **no** timeout warn, so the
   assertion above cannot pass vacuously.

Re-measured after the fix: 5.3–6.3 s against the 25 s ceiling.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #7172 | `lint-agents-enforcement-tags.py` has validated zero of 42 enforcement tags since ADR-151 made `AGENTS.md` pointer-only — it reports `OK: all 0 hook + 0 skill checks resolve`, which is the same "a gate reporting nothing reads as a gate reporting fine" class as this incident. Found in the same session. | agent |

The timeout-visibility gap that made this incident silent is closed by the fix itself
(`gate_timeout_warn_count` in `summary.gate_exemptions`' sibling keys), so it needs no
separate tracker. No further residual work: the ceiling, the probe shape, the telemetry id
and its discriminating control are all pinned by tests in the same PR, and the 37-mutation
battery covers each.

## Prevention

- **A fail-open branch needs a telemetry row and a test that the row fires.** "Fails open,
  not fail-silent" is a claim about behaviour; if nothing asserts it, it is a comment.
- **Wrap-and-translate is where gates die.** When a hook wraps a script and maps exit codes,
  enumerate every code the wrapper itself can produce (124 from `timeout`, 127 from a missing
  binary) — not just the ones the wrapped script returns.
- **Measure a gate's wall clock against its own ceiling before shipping the ceiling.** The
  spread across hosts (5.7–8.1 s) is the hazard, not the mean; a ceiling set near the mean is
  a coin flip somewhere.
- **`timeout` is not universally present.** The repo already documented this
  (`supabase-loopback-warn.sh`, rc-127 dark tripwire) and the pattern was not reused here.
  Use the `TO=()` probe.
