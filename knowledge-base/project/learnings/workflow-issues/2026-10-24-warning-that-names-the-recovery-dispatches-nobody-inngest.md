---
title: "A warning that names the recovery still dispatches nobody — the preflight warned, and the scheduler stranded anyway"
date: 2026-10-24
category: workflow-issues
tags: [inngest, terraform-apply, advisory-surfaces, warnings, ops-recovery, alerting]
module: Infra / Inngest Scheduler
---

# A warning that names the recovery still dispatches nobody — the preflight warned, and the scheduler stranded anyway

## Problem

This session (alongside PR #10997) an `apply_target=inngest-host-replace` dispatch on
`.github/workflows/apply-web-platform-infra.yml` produced exactly the deterministic stranding the
runbook predicts: `INNGEST_CUTOVER_FLIP=done` lives in Doppler and outlives the host, the matching
`done-owner` marker lives on the root disk the replace destroys, and `inngest-server-flip-guard.sh`
correctly refuses a prod start on an inherited `done` (#7228 — a second prod scheduler is the
thing being prevented).

The inherited-`done` preflight (added after the 2026-09-17 incident, PR #8252) fired correctly:
it read the flag, found `done`, emitted `::warning::INNGEST_CUTOVER_FLIP=done -- this replace WILL
leave inngest-server refusing to start`, and wrote the full recovery — `gh workflow run
cutover-inngest.yml -f op=resume` plus the `inngest-cutover` environment approval — into
`$GITHUB_STEP_SUMMARY`. And the scheduler still stranded: **nobody read the job summary and
nobody dispatched the named recovery** until after the strand was noticed. The recovery itself
was one dispatch plus an approval, no re-FLUSHALL, queue intact — known, scripted, cheap, and
still not taken until the outage was observed by other means.

Two surfaces existed and neither closed the gap: the preflight's `::warning::` is a pull-channel
(workflow log + step summary — someone has to go read it), and the `scheduled-inngest-health.yml`
watchdog (`[ci/inngest-no-live-scheduler]` issues) IS a push channel but fires only on the
*symptom* — the scheduler already dark — never on the *precondition* the preflight had already
measured. The precomputed knowledge and the alarm that eventually fired were the same fact at
different timestamps, connected by nothing.

## What didn't work

The preflight is *designed* not to block — the replace is often exactly what the operator wants
and the recovery is one dispatch — and it degrades open on an unreadable flag for the same
reason. Those choices are correct. The gap is one layer up: the warning's only consumers are the
workflow log and the step summary, which are pull-channels. The actor who needs the recovery (the
dispatcher of the replace, or the on-call agent) is never *sent* anything. A `::warning::` is
documentation that renders after the fact, not a notification that arrives before it.

## Key Insight

**A detection surface that names the remedy but delivers to no actor is a runbook footnote,
not a control** — and a push channel keyed on the *symptom* does not compensate for a pull
channel holding the *precondition*. The preflight satisfied every criterion a reviewer would
check — it fires, it measures the real flag, it names the exact recovery, it cannot
false-positive on an unreadable flag — and it still produced a zero-action outcome, because
"the warning was emitted" and "an actor was armed with the recovery" are different claims.
This is the same shape as `2026-07-20-an-advisory-gate-is-not-a-weak-gate` (an advisory gate in
an autonomous pipeline is a display, not a gate), one level further along: even when the
advisory names a *one-command* remedy, nothing consumes it. The three surfaces that actually
close the loop are: (a) block the apply on the flag with a deliberate bypass (a gate), (b)
dispatch the recovery automatically after the replace (an actuator), or (c) route the warning
to a channel someone reads — a filed issue or paged alert (a notification). The current
preflight does none; the watchdog is (c)-shaped but wired to the symptom, not the measured
precondition.

A second, sharper observation: the condition is **deterministic and fully knowable before the
replace** — `done` plus a replace *always* strands, and the flag is one Doppler read away. A
control attached to a deterministic precondition has no excuse to be advisory in the way a
heuristic check does; the false-positive budget that justifies "warn and proceed" is zero here.

## Resolution (this session)

One dispatch — `gh workflow run cutover-inngest.yml -f op=resume` — plus approval of the
`inngest-cutover` environment gate (the run holds in `Waiting` until a human approves; no step
executes before then). Verified via the FSM row `reason="flushed-resume-no-reflush"` →
`noop-done`, scheduler serving, queue preserved.

## Session Errors

1. **Forwarded (plan phase): no Task/subagent spawn capability** — research fan-out, domain
   review, advisor consult, and the deepen-plan panel all ran inline sequentially; disclosed as
   `Reviewed-Coverage: sequential-fallback`. **Recovery:** sequential execution + disclosure
   marker. **Prevention:** none — environment constraint; the disclosure convention is the
   mitigation.
2. **Forwarded (plan phase): `lint-infra-no-human-steps.py` flagged the plan's live spot-check
   line.** **Recovery:** reworded the line; lint re-run green. **Prevention:** the lint is the
   enforcement — covered, no new guardrail proposed.
3. **Forwarded (plan phase): stale negative-AC** — `bootstrap-live-verify.sh`'s header claimed
   `seed-live-verify-user.sh` was not wired into CI; it IS at `web-platform-release.yml:2207`.
   Deepen-plan §4.45 caught it; AC7 rescoped to `bootstrap-live-verify` only. **Recovery:**
   header-comment fix folded into Edit 2. **Prevention:** a "not wired" claim in a script
   header is a verifiable assertion — grep the consumer before repeating it.
4. **Forwarded (work/review phase): review found 2 P2 + 4 P3** (verb-set widening in the census
   guard, `doppler run`/`download` pair reads, script hardening). **Recovery:** all fixed inline
   in `038271ad18`/`80691c102c`; census suite 402/0 green. **Prevention:** none — the review
   panel did its job.
5. **This session: the stranding itself** — the preflight warned and nobody dispatched.
   **Recovery:** `op=resume` dispatch + environment approval. **Prevention:** tracked as
   deferred-scope-out design issue #11011 — pair the preflight warning with a blocking gate,
   an auto-dispatch actuator, or a notification channel (three candidate directions in the
   issue body).

## Related

- Incident post-mortem (the original two-replace strand, 2026-09-17):
  `knowledge-base/engineering/operations/post-mortems/inngest-inherited-done-host-replace-strand-postmortem.md`
- Adjacent learning — advisory surfaces are inert:
  `knowledge-base/project/learnings/2026-07-20-an-advisory-gate-is-not-a-weak-gate-it-is-no-gate-and-a-ratio-needs-its-denominator-checked.md`
- Runbook contract (the preflight "warns, does not block, degrades open" design):
  `knowledge-base/engineering/operations/runbooks/inngest-server.md` §Inherited `done` after a host replace
- Preflight implementation: `.github/workflows/apply-web-platform-infra.yml`,
  "Preflight - warn if this replace will strand the scheduler (#7228)"
