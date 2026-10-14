---
title: "A control that fails inside an earlier check proves nothing about the checks after it — and four other measurements from the #9703 feeder"
date: 2026-10-11
category: workflow-patterns
tags: [mutation-testing, controls, review, soak, adr, shell-tests, heartbeat]
issue: 9703
pr: 10042
branch: feat-one-shot-9703-inngest-heartbeat-feeder
---

# Learning: five measured traps from wiring the Inngest probe heartbeat feeder

## Problem

#9703 wired a dead-man's-switch feeder (`scripts/inngest-probe-heartbeat-feeder.sh`) whose
exit 0 must mean exactly {beat, fresh_heartbeat_paused}. Most of the effort went into proving
the guards, and most defects were in the proofs and the prose, not the feeder.

## Solution / Key Insights

1. **A control that fails inside an earlier check proves nothing about the checks after
   it.** The first `expect()` control (a mutant of the harness's own verdict helper) failed
   inside the invariant helper, so every check after it was never reached. Neutering
   `expect`'s verdict stayed green. The fix is one control per check, each attributed by its
   own diagnostic (the line it must print), with a landing assertion that the mutation
   actually changed the file. Three scratch mutants landed; a mutant that did not land
   reported a false "killed".
2. **Name what a figure measures before four seats build on it.** Review raised a P2 on an
   "ingest lag" of about 90 minutes. Those numbers were ages-at-check, not lag. A read-only
   soak that recorded each row's first sighting measured real lag at 83 s and 101 s, so the
   4500 s freshness bound stood. A soak costs a read-only token and wall-clock time; arguing
   from a mislabelled figure cost four seats.
3. **An eligibility argument written to fit the rule can be weaker than the real one.** The
   ADR-248 amendment first said the feeder fits the dispatch clock for failure-domain
   reasons. The real argument is attribution: an Inngest-fired feeder would false-page
   "probe dark" on any Inngest/web-1 outage, because the heartbeat is the only paging
   surface. The architecture seat and the CTO ruling replaced the first with the second, and
   the rejected Inngest dispatch cron was recorded as a rejected alternative.
4. **Slice edits keyed on a heading that appears twice duplicate content.** A python edit
   used `s.index("## Heading")`; the heading also appears earlier (in a table of contents
   and a pointer), so 180 lines of the plan were duplicated. Recover with
   `git restore --source=HEAD --worktree <file>` and anchor with `find(heading, start)` where
   `start` is past the earlier occurrence; read the file back afterwards.
5. **A stub whose `pass()` prints to stdout cannot be called inside `$(...)` to return a
   path.** The captured string then holds the pass line too. Return the value through a
   variable or a file, never through command substitution of a function that also reports.

## Session Errors

- **Vacuous first `expect()` control** — Recovery: rebuilt, one attributed control per check, landing assertions. **Prevention:** a control is valid only if a single-line diagnostic names the check it exercised; assert the mutation landed before reading the verdict.
- **Control mutants that did not land** — Recovery: landing assertions plus a `CTL_M` variable. **Prevention:** same landing assertion for every scratch mutant.
- **Mislabelled "ingest lag" premise** — Recovery: read-only soak with first-sighting timestamps (83 s / 101 s). **Prevention:** before a review finding rests on a latency, ask which timestamp pair produced it.
- **ADR rationale written to fit the rule** — Recovery: architecture seat plus CTO ruling replaced it. **Prevention:** state the claim as the property the rule protects, then check the case against that property.
- **Python slice edit duplicated 180 plan lines** — Recovery: restore from HEAD, find-after-start anchor. **Prevention:** read a file back after any scripted edit; anchor on `find(x, start)`.
- **Stub `pass()` inside `$(...)`** — Recovery: return via variable. **Prevention:** a helper that reports must not also be a value source.
- **`CALLS` subshell scoping and curl-count regex** — Recovery: counted from a file the stub appends to. **Prevention:** counters mutated in a pipeline or `$(...)` live in a subshell; use a file.
- **Census flagged `INNGEST_PROBE_MARKER` in the workflow; fixture-relative ratchet sites** — Recovery: adjusted per the ratchet's own message. **Prevention:** a repo-global ratchet cannot be seen by a file-selected suite set; run the named ratchets when adding a test.
- **Patch-script anchors failed; `git stash list` blocked by the hook** — Recovery: re-anchored; used `git show`. **Prevention:** none beyond the existing rule.
- **Preflight span threshold 2700 s would fail about half the time under dispatch jitter** (a real finding) — Recovery: 2400 s. **Prevention:** size a threshold from the dispatch cadence plus jitter, not from the happy path.
- **Stray untracked `zz-8322-untracked-probe.c4`** — Recovery: removed. **Prevention:** none (one-off).

## Tags
category: workflow-patterns
module: scripts/inngest-probe-heartbeat-feeder
