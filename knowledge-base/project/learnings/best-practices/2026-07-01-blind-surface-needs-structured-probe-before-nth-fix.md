# Learning: For a symptom on a surface you can't inspect, ship a structured discriminating-field probe FIRST — a speculative blind fix is not diagnosis

## Problem

The operator's Concierge `/soleur:go` stranded on `not a git repository` for workspace `754ee124`. It took **six** merged+deployed fixes over ~2 weeks to resolve:

| PR | Hypothesis | Layer | Result |
|----|-----------|-------|--------|
| #5716 | warm-dispatch race (absent `.git`) | cc-dispatcher | no heal |
| #5584 | validity-not-presence (corrupt `.git`) | cc-dispatcher | no heal |
| #5730 | reconcile-on-push re-clone | Inngest reconcile | no heal |
| #5734 | (reconcile variant) | Inngest | no heal |
| #5790 | in-process rev-parse confirm + partial C2 probe | cc-dispatcher | no heal + **still blind** |
| #5802 | in-process clone + **structured in-sandbox backstop** | cc-dispatcher + agent surface | **made it diagnosable** |

Every fix through #5790 was a *speculative* fix against a hypothesis with **no event that could confirm or refute it**. The failing surface — the agent's **bwrap sandbox** — emitted zero telemetry, and the operator is non-technical (no SSH). We were guessing in the dark and shipping the guesses.

The break came only when #5802 shipped an **in-sandbox backstop probe** (`agent_readiness_self_stop`) carrying **structured discriminating fields**. On the next repro, ONE event (WEB-PLATFORM-46) decided the root cause instantly:

```
source:           in-sandbox-backstop   ← emitted FROM the agent surface, not the host
gitKind:          dir-valid             ← the HOST sees a valid .git
gitRevParseValid: false                 ← the AGENT's in-sandbox rev-parse fails
```

Host-valid + sandbox-invalid ⇒ the repo is cloned fine on the host but the agent's bwrap mount can't read it. The actual fix was one line in the sandbox config (`allowRead: [workspacePath]`, #5733) — never a server-side clone/gate change.

## Solution

**When a symptom manifests on a surface you cannot directly inspect (an agent bwrap sandbox, a remote container, a cron worker) and a fix must ship blind, the first-class deliverable is a STRUCTURED probe emitted FROM that surface whose fields discriminate ALL competing hypotheses — not another speculative fix.** Ship the probe BEFORE (or WITH) the first fix attempt, so the very next repro either succeeds or emits an event that picks the layer.

Two failure sub-modes this session exposed, now encoded in `observability-coverage-reviewer` §Step 4.6:

1. **Probe must run ON the affected surface.** Every host-side gate correctly reported `ready` — they cannot see inside the sandbox. Only the in-sandbox backstop (`source: in-sandbox-backstop`) observed the true state. A host-side event for an in-surface failure is not observability of that failure.
2. **Discriminating fields must span EVERY hypothesis, not one.** #5790's gate emitted only on the `dir-valid`-but-invalid shape and short-circuited `ready` on absent-`.git` → no event → still blind. And its detector didn't match the stderr-suppressed empty output (`git rev-parse … 2>/dev/null`) the Step 0.0 gate actually produces (fixed in #5802). A probe that fires for one of N shapes, or whose detector can't match the real emission form, keeps you blind.

## Key Insight

This is the next chapter after [[2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface]] ("a recurring symptom means the fix is in the wrong LAYER — prove the path executes on the affected surface"). That learning says *find the right layer via runtime evidence*; this one says **if the affected surface has no runtime evidence to find, building the discriminating probe IS the fix's first deliverable.** The order is inverted from instinct: on a blind surface, observability is not a follow-up you add after the fix works — it is the thing that tells you what to fix, and it must exist before attempt #1, not attempt #6. The cheapest version of six weeks of blind fixes was one structured event.

Codified as the affected-surface extension of `hr-observability-as-plan-quality-gate` — enforced at plan-time (plan Phase 2.9.2 — affected-surface `failure_modes`) and review-time (`observability-coverage-reviewer` §Step 4.6). It was folded under the existing observability rule rather than minted as a new AGENTS.core hard rule because the always-loaded rule payload is at its byte budget (`scripts/lint-agents-rule-budget.py`); the enforcement lives in the reviewer + plan gate, which carry no always-loaded cost.

## Session Errors

- **Shipped 5 speculative blind fixes before shipping the probe that made the bug diagnosable.** Recovery: #5802's structured in-sandbox backstop turned a 2-week guess into a one-event diagnosis (#5733). **Prevention:** for a symptom on a non-inspectable surface, the FIRST PR ships the structured discriminating-field probe emitted from that surface; fixes come after the event picks the layer.
- **#5790's readiness gate emitted for only one failure shape and short-circuited `ready` on the others — so it stayed blind on the actual shape.** Recovery: #5802 widened the probe fields + fixed the detector to match stderr-suppressed empty output. **Prevention:** a readiness/self-stop probe's fields must discriminate ALL competing hypotheses in one event, and the detector must match the path's real emission form.

## Tags
category: best-practices
module: web-platform/agent-sandbox
related: "[[2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface]]"
issues: "#5733 #5802 #5790 #5730 #5716 #5584"
