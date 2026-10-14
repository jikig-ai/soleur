---
title: "A plan's paste-ready reference text propagates its own phantom anchors — a §-quote is a claim to grep, not prose to inherit"
date: 2026-10-03
category: workflow-patterns
tags: [review, plans, citations, propagation, drain-prs]
issue: 9418
pr: 9423
related:
  - knowledge-base/project/learnings/2026-09-18-three-sentences-i-pasted-from-the-plan-were-inherited-not-measured.md
---

# A plan's paste-ready reference text propagates its own phantom anchors

## Problem

The #9418 plan's reference shape for the corrected `drain-prs/SKILL.md` §4 bullets
carried the cross-reference `§"A SERVER-SIDE update cannot run the driver"` —
inherited verbatim from the pre-existing bullet it was rewriting. The
implementation applied it essentially verbatim (as the plan directed, "semantics
are the contract"), and it would have shipped: the `§"…"` notation reads as
deliberate and greppable, so neither author nor implementer re-checked it.
`grep 'SERVER-SIDE' plugins/soleur/skills/merge-pr/SKILL.md` returns zero — no
heading, no bold anchor. Three independent review seats (git-history, pattern,
code-quality) flagged the same phantom citation post-hoc; the fix was re-pointing
to §3.1 "Route conflicts", the real heading covering the substance.

Sibling miss in the same PR: a comment tidy deleted the premise of a causal
chain ("a queue mangled outside Terraform would leave the stall probe blind")
but kept the conclusion ("so `terraform plan` here is the real drift detector") —
a dangling "so" the code-quality seat caught.

## Solution

A `§"quoted heading"` citation is a machine-checkable claim, not decorative
prose. Before committing a `§"…"` or `§N.N "…"` cross-reference — especially
one inherited through a plan's paste-ready block — `grep -F` the quoted string
in the target file and require a heading (or the named anchor) to exist. The
plan's "apply verbatim" instruction amplifies the risk: the implementer's job
description is to *not* re-derive the text, so the phantom travels
plan → implementation → diff without any author ever asserting it.

When a doc edit deletes the premise of a `cause → so conclusion` chain, re-read
the sentence holding the connector: the conclusion either needs its premise
restored (generalized, if the specific cause retired) or the "so" dropped.

## Key Insight

Inherited prose fails at its *labels and anchors* before its numbers — the repo
already teaches "paste-ready prose is inherited sentences" for causal claims;
quoted anchors are the same class one level down and mechanically falsifiable in
one grep. A citation form that implies greppability (`§"…"`) creates the
obligation to grep it.

## Session Errors

1. `git stash` issued as a no-op reflex — denied by the
   `hr-never-git-stash-in-worktrees` hook. **Prevention:** none needed; the hook
   names the remedy (`git show <commit>:<path>`). Loud, self-describing denial.
2. `fix-round-seats.sh` invoked with a positional file-list argument — usage
   error (`--files` is required). **Prevention:** run `--help` first on
   unfamiliar repo scripts; the usage text is the contract.
3. `git diff --name-only HEAD..origin/main` misread as "files changed on main" —
   it diffs both directions of the tree (includes reverting the branch's own
   commits). **Prevention:** for "what did the incoming commit touch" use
   `git show --name-only <sha>`; the `..` form answers "how do the trees differ".
