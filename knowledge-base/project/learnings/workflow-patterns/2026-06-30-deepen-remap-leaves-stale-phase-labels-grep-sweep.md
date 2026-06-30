# Learning: a deepen-pass that moves a substrate between phases leaves stale phase-labels scattered — grep-sweep the whole plan+spec to reconcile

## Problem

Executing **Phase 0** of an epic plan (`feat-multi-host-workspaces`, #5274 — author
ADR-068 + C4 edits, the only non-deferred step), multi-agent review found the plan
still bound **Redis to "Phase 3"** in multiple places even though the plan's own
deepen pass had **re-mapped Redis to Phase 4a** (the note at the top of
`## Implementation Phases` says so explicitly). The canonical ADR-068 was correct
(Phase 4a everywhere); the *plan* contradicted itself. The stale bindings were
scattered across structurally-distinct sections: the Research Reconciliation table,
the Phase-3 heading, Files-to-Create, Files-to-Edit, the ADR/C4 section, the
intro blockquote, `package.json` dep line, and a Sharp-Edges "Step 1" reference —
8 sites total. `code-quality-analyst` enumerated 5; a follow-up `grep` found **3
more**. The spec.md likewise still carried the pre-reconciliation "managed Redis /
migrate the 7 ADR-027 Maps" framing (FR1/FR3) with no supersession marker.

## Root cause

A deepen pass (or any plan revision) that **moves a component/substrate from one
phase to another** typically edits the section where the decision is narrated (here:
the Key-Improvements list + the IaC re-map note) but leaves the *phase label*
untouched everywhere else the substrate is mentioned. Phase labels are short tokens
(`Phase 3`, `Phase 4a`, `Step 1`, `1a`) sprinkled across headings, tables, file
lists, IaC, and sharp-edges — exactly the "replicated literal across N sites with no
parity test" drift class. Per-step planners later inherit the plan verbatim and would
hit the contradiction.

## Solution

When the plan's deepen/revision note says a substrate **moved phases**, treat the new
phase as canonical and **grep-sweep the entire plan + spec for the OLD phase-binding**,
reconciling every hit in one pass — do not trust a section-by-section read or a single
reviewer's enumeration (it found 5 of 8). Concretely:

```bash
# enumerate every place the moved substrate is still bound to a phase
grep -nE '<substrate>.*Phase [0-9]|Phase [0-9].*<substrate>' <plan> <spec>
# and the phantom old-numbering tokens the re-map orphaned
grep -nE '\b1a\b|\bStep [0-9]' <plan> <spec>
```

Reconcile each, then re-run the greps until they return nothing. Add a one-line
supersession banner to any upstream spec whose FRs the reconciliation falsified, so
the spec is honest standalone (pointer to the plan's Research Reconciliation + the
ADR's rejected-option section).

## Key insight

**The deepen pass is authoritative for the *decision*, never for the *consistency* of
every phase-label it implies.** A substrate re-map is a sweep-class edit: the canonical
statement lives in one section, but the phase token is a replicated literal across the
whole document. Reconcile with a grep-enumerated work-list, not an intuited or
single-reviewer-enumerated one — same discipline as `hr`/learning
"sweep-class fixes use grep-enumerated work-lists, not intuited ones," applied to
plan-internal phase labels. The cheapest catch is at Phase-0 /work time (when the
canonical ADR is authored), before per-step planners inherit the drift.

## Also: epic-plan Phase-0 compound must NOT auto-archive the plan/spec

This session ran inside an **epic plan** where only Phase 0 is complete (Phases 1–4b
are future per-step PRs). Compound's automatic-consolidation step archives a feature's
brainstorm/plan/spec on `feat-*` branches — which would have **buried the living epic
documents** the later phases depend on. For an incomplete epic, skip auto-archival;
the plan/spec stay active until the final phase ships.

## Session Errors

- **Bare-repo-root `ls` of the worktree-relative plan path returned exit 2** — Recovery: `cd` into `.worktrees/<branch>/` first. — Prevention: in a `core.bare=true` repo, resolve plan paths against the worktree, not the bare root (already covered by `hr-when-in-a-worktree-never-read-from-bare`).
- **`Edit` on tasks.md failed "File has not been read yet"** — I'd viewed it via Bash `cat`. Recovery: `Read` then `Edit`. — Prevention: viewing a file via `cat` does not satisfy the Edit Read-precondition; use the `Read` tool before editing.
- **Guessed wrong ADR-067 filename** (`cron-heartbeat` vs actual `adopt-swr-client-cache`) — Recovery: `ls ADR-067*`. — Prevention: `ls` the numbered-prefix glob before `Read`-ing a sequential artifact by a guessed slug.
- **likec4-export element-id grep returned 0** — ids are fully-qualified (`platform.infra.X`). Recovery: grep the qualified name. — Prevention: when verifying a likec4 export, grep the fully-qualified element id, and confirm `likec4 validate` is clean + no "Could not resolve" diagnostics (export exits 0 even on unresolved refs).
- **Pre-existing plan drift (Redis→Phase-3 ×8, argv contradiction) surfaced only at review** — Recovery: grep-sweep + reconcile inline. — Prevention: this learning (grep-sweep the moved-substrate phase labels at Phase-0 /work, before review).

## Tags
category: workflow-patterns
module: plan, deepen-plan, work, compound
issue: 5274
pr: 5710
