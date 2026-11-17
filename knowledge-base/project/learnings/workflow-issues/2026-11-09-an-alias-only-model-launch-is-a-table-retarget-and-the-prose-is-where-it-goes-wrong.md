---
title: An alias-only model launch is a table retarget, and the prose is where it goes wrong
date: 2026-11-09
category: workflow-issues
tags: [model-launch, claude-fable-5-2, audit-models, pricing-basis, review-findings, local-gate]
issue: 12513
---

# Learning: an alias-only model launch is a table retarget, and the prose is where it goes wrong

## Problem

Fable 5.2 (`claude-fable-5-2`) launched 2026-11-09. Soleur reaches Fable only through the version-agnostic
`model: fable` alias on the two ADR-083 consult gates, so no config literal, no `MODEL_PRICING` row and no CLI
pin had to move. The launch was a two-line retarget of `AUTOFIX_PAIRS` in `audit-models.sh`, its tests, and
documentation. The code was correct on the first try. All 14 review findings were in the documentation and
in test comments.

## Solution

- `claude-fable-5` and `claude-fable-5-1` both rewrite to `claude-fable-5-2` in one hop; the ID boundary keeps
  `claude-fable-50`, `claude-fable-5-10` and dated variants untouched (measured, and idempotent on a second run).
- The CLI bump was deferred (#12514): pinned 2.1.311 has 0 hits for the new id, but nothing sends a Fable id as
  an argv value, so the unknown-id `max_tokens` halving does not apply.
- Fast mode, preserved thinking and the orchestrator role were evaluated and not adopted (ADR-083 addendum).
- Every price row was re-read from the official page; the AGENTS.md claim that the consult is a cold spawn with
  ~0 cache reads was replaced by ADR-053's measured statement.

## Key Insight

When the code change is two lines, the review budget moves entirely to the claims the diff adds. Five of the
findings were sentences written from memory or by mechanical rename (the effort constant named for the wrong
tier, a "5×" left live next to a new "4×", `5-2 -> 5-2-1` where the sed it describes would produce `5-2-2`).
Before writing any tier, multiple or id into prose, run the command that shows it. A test parser that does not
strip comment lines treats a commented-out pair as live, so a pair-table test stays green while the pair is
gone; strip comments in the parser and mutation-prove it.

## Session Errors

1. **`pgrep -f` denied by the self-match hook, taking the whole command (including `git push`) with it** — Recovery: re-ran the push alone. **Prevention:** already hook-enforced; never put a push in the same call as a process probe.
2. **Bare-token `grep -in fable` matched "unspoofable"; the AC then needed two corrections** — Recovery: word-bounded the pattern and scoped it to `server/`. **Prevention:** anchor presence probes on the id shape (`-w`, `claude-fable-[0-9-]*`), and run the AC command before writing it into a plan.
3. **The local affected gate selected 290 of 750 suites and ran 25+ minutes at load ~26** — Recovery: killed it, ran the directly related suites (1639 pass), relied on CI for the rest. **Prevention:** for docs/audit-table diffs, run the covering suites and the CI full battery; tracked in #12013 and #12263.
4. **A Monitor armed on the gate's rc file kept emitting after the gate was killed** — Recovery: `TaskStop`. **Prevention:** stop the watcher in the same step that kills the watched job.
5. **Five review findings were unverified prose claims (tier label, stale "5×", wrong rename comment, unverified vendor default, buried caveat)** — Recovery: fixed inline after verifying `AUDIT_MODEL`/`AUDIT_EFFORT` in `model-tiers.ts`. **Prevention:** for each causal or numeric sentence a diff adds, name and run the command that falsifies it before writing it.
6. **The stop hook fired twice on closing text that promised an action** — Recovery: performed the step in the same turn. **Prevention:** already hook-enforced; state a `Paused:` reason only for a real external wait.

## Tags
category: workflow-issues
module: model-launch-review
