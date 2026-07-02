---
date: 2026-07-02
category: workflow-patterns
tags: [brainstorm, ci-gate, drift-analyzer, blocking-gate, false-positive, diff-scoping]
issue: 5871
---

# Run an existing analyzer during brainstorm before designing a blocking gate around it

## Context

Brainstorming #5871 — mechanical enforcement gates around the domain-model drift
analyzer (`scripts/domain-model-drift.sh`, shipped by #5754). The issue framed three
gates (plan-flag / review drift-check / ship block) that all consume the analyzer's
`drift` exit code (1 = drift).

## What we did that paid off

Before designing anything, we **ran the analyzer against clean `main`** and read its
real exit code. It exited **1** — driven by a single "undocumented source fact"
(`public`). Reading the source (`domain-model-drift.sh:167`) showed the
undocumented-table extraction captures the *schema qualifier*, not the table name:
`capture("› (?<t>[^.]+)\\.")` grabs `public` from `migration › public.workspaces`.
A false positive.

**Consequence if we hadn't checked:** a naive "block when `drift` exits 1" gate would
have red-walled **every PR** from day one, because the analyzer was already non-green
on clean main. The issue's premise ("build after the analyzer ships and is trusted")
would have been satisfied on paper while the analyzer was, in fact, not gate-ready.

## Takeaways

1. **When a gate consumes an existing analyzer's exit code, run the analyzer against
   a clean baseline during brainstorm.** The exit code is the gate's whole contract;
   verify it's green where you expect green before sizing the gate.
2. **Watch for masked exit codes.** `analyzer | tail; echo $?` reports `tail`'s exit,
   not the analyzer's. Redirect to a file, then read `$?`.
3. **A whole-repo analyzer needs diff-scoping at the GATE, not the analyzer.** Fixing
   the analyzer to accept a diff is net-new engine work; instead the gate checks the
   changed-file path-set first and only runs the whole-register check when a relevant
   surface changed. This structurally kills the "unrelated PR blocked by pre-existing
   drift" failure mode. (Preflight already owns a cached diff classifier for exactly
   this.)
4. **The real sequencing blocker for a new gate is often analyzer hygiene, not the
   backlog.** Here #5882's auto-inferred backlog was already CLOSED/drained; the true
   prerequisite was the `public` false-positive fix.

See: brainstorm `knowledge-base/project/brainstorms/2026-07-02-domain-model-register-gates-brainstorm.md`,
spec `knowledge-base/project/specs/feat-domain-model-register-gates/spec.md`.
