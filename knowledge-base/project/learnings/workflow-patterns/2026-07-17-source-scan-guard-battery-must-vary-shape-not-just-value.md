---
title: "An anti-vacuity mutation battery that varies VALUE but not SHAPE fails open on the shapes it never mutated"
date: 2026-07-17
category: workflow-patterns
tags: [review, source-scan-guard, mutation-testing, anti-vacuity, fail-open, ci-guard]
issue: 6633
pr: 6634
---

# Learning: a source-scan guard's mutation battery must vary the input SHAPE, not just the value

## Problem

#6633 shipped an author-time CI guard (`credential-persist-home-guard.test.sh`) that scans
systemd units for a credential-login persisting to `$HOME` under `ProtectHome=read-only` (the
EROFS class that hit docker #6565 and doppler 2026-04-06). The plan's explicit north star was
**anti-vacuity**: "a guard whose deletion/inversion leaves the suite green pins nothing," with a
13-mutation battery (M1–M8 + M3b/M3c/M5b/M7b/AC5), each on a fresh copy, GREEN-before-mutation,
`assert_mutated`, finding-text attributed. The battery was 20/0 GREEN and the guard passed its own
gut-check.

It was still fail-open. Every mutation varied the **value** axis — home vs off-home config dir,
relocated vs not, in-RWP vs not — while exercising the ONE syntactic **shape** the scanner already
understood: a bare `docker login` in an `ExecStart=` of a `$VAR`-target heredoc. Review
(security-sentinel + test-design-reviewer, prompted specifically to *find the vacuity the battery
missed*) proved the scanner stayed GREEN on realistic house-style shapes it never enumerated:

- `/usr/bin/docker login` (absolute path — the `^docker` anchor missed it)
- `sudo -u deploy docker login`, `su … -c 'docker login'`, `runuser … -- docker login` (wrappers)
- `/bin/sh -c 'docker login …'` (shell `-c` body)
- `ExecStartPre=` / `ExecStartPost=` logins (only `ExecStart=` was captured)
- `cat > /etc/systemd/system/x.service <<'EOF'` literal-path heredocs (regex was `$VAR`-only) —
  and that exact shape already exists in the tree (`soleur-host-bootstrap.sh:461`)
- any tool other than docker/doppler (`cosign`, `gh auth login`, `aws configure`) — the class
  already recurred via a *different* tool (doppler), so a two-family vocabulary is a fail-open

The census (`cred_sites>=1`, `webhook_docker=relocated`) did NOT save it: a home-pointed login
added *alongside* the existing relocated one passes, because the census only needs ≥1 relocated
site to exist.

## Root cause

A mutation battery measures the tests against *the mutations its author thought of*. For a
source-scan/containment guard, the author's mental model of "the input" is the shape in front of
them, so the battery reflexively mutates the VALUE within that one shape and never the SHAPE
itself. The extractors (`find_*_sites`, `enumerate_units`) are exactly the code a value-only
battery cannot exercise — and they are where a source scanner fails open. The plan naming
"anti-vacuity" as the goal does not immunize the implementation (learning
`2026-07-17-buy-the-datum` SE#3 already said this; it recurred anyway).

## Solution

1. **Author the battery along the SHAPE axis, not just the value axis.** Enumerate the syntactic
   variants the real corpus uses — wrapper (`sudo`/`su`/`env`/`sh -c`), path form (bare vs
   absolute), directive (`ExecStart` vs `ExecStartPre/Post`), definition site (`.service` vs
   `$VAR`-heredoc vs literal-path-heredoc vs cloud-init vs `.tf`), and tool (the whole family, not
   the one in the tree today) — and add one positive-detection mutation per variant. The fix here
   added M9–M15 covering each.
2. **Make detection shape-robust, not shape-pinned.** Unanchored tool match (basename of an
   absolute path), a leading-wrapper stripper, one level of `-c '…'` unwrapping, scan every
   `Exec*` directive, and a tool-agnostic family table. A guard that recognizes only ONE form
   fails open on the next refactor that writes the login differently — the exact recurrence vector
   it exists to prevent.
3. **The review prompt is the lever.** The finding surfaced because the spawn prompt said "find
   the vacuity the battery MISSED — do NOT re-run its mutations" and named the candidate evasion
   shapes (`sh -c`, absolute path, `ExecStartPre`, literal-path heredoc, other tools). A generic
   "review this test" prompt would have re-confirmed the green battery.

## Key Insight

For any guard that classifies/contains by scanning source text, the anti-vacuity question is not
"does inverting the value flip the result?" but **"what SHAPE of the input does the battery never
vary, and does the scanner fail open on it?"** Litmus: name an implementation a reasonable engineer
might write next (an absolute path, a privilege wrapper, a different tool) that satisfies every
assertion while violating the property. If you can, the battery is value-complete and
shape-vacuous. Pair every guard-authoring session's mutation battery with a SHAPE enumeration, and
prompt the adversarial reviewer to attack the extractors, not the value logic.

## Session Errors

1. **First guard implementation was shape-pinned (P1 fail-open).** Detection anchored on `^docker`,
   `$VAR`-only heredocs, and `ExecStart=` only. Recovery: unanchored + wrapper/`sh -c`-aware
   detection, all `Exec*` directives, literal-path + `.tf` heredocs, extended family table.
   Prevention: enumerate the SHAPE axis at battery-authoring time (this learning).
2. **Mutation battery varied value, not shape.** 13 green mutations, all one shape. Recovery: added
   M9–M15 (abs-path, `sudo -u`+`sh -c`+ExecStartPre, literal-path heredoc, gh family, is_home
   abs clause, doppler flag-first, census self-fail). Prevention: same as #1.
3. **`rm -rf "$var"` blocked by the Bash tool's static guard** during exploratory mutation loops
   (twice). Recovery: fixed scratch subdirs, no `rm` in the exploratory command. Prevention: in
   throwaway mutation-loop exploration, create uniquely-named dirs under the scratchpad and let the
   session teardown reclaim them rather than `rm -rf "$dir"`.
4. **M8 attribution grep missed on `$` in the heredoc var name** (`unit=$M8_…` vs
   `unit=M8_…`). One-off; fixed by dropping the `unit=` prefix from the attrib substring.
5. **(plan phase, forwarded)** Initial plan `Write` rejected because the plan skill had already
   written the plan. One-off; adopted the existing plan.
