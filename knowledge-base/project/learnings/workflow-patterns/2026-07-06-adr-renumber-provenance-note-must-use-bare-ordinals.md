---
title: "ADR-renumber provenance ('Ordinal note') must use BARE ordinals, not the old ADR-NNN literal"
date: 2026-07-06
category: workflow-patterns
tags: [adr, renumber, ordinal-collision, residual-grep, provenance-note]
issue: 6054
---

# ADR-renumber provenance notes must use bare ordinals, not the old `ADR-NNN` literal

## Problem

Resolving the 3-way `ADR-086` ordinal collision (#6054) renames two ADR bodies
(`086 → 093`, `086 → 094`) and adds a history-preserving **"Ordinal note"** to
each recording the renumber chain. The renumber's completeness gate — the
residual-zero acceptance criterion — is a scoped grep for the OLD ordinal
literal:

```
git grep -n 'ADR-086' -- '.claude/' '.github/' 'scripts/' 'tests/' 'apps/' \
  'plugins/' 'knowledge-base/engineering/'
```

That scope **includes `knowledge-base/engineering/architecture/decisions/`** —
i.e. the renamed ADR bodies themselves. My first draft of the Ordinal notes
wrote the history narrative with the literal string:

> "…three PRs concurrently authored **ADR-086** on 2026-07-05…"

So my own provenance note would have been flagged by AC7 as a "missed
reference," failing the very gate the renumber exists to turn green — even
though the note is a *correct, intentional* history record, not a stale
pointer. Caught before commit; the two review agents (pattern-recognition,
security-sentinel) would also have caught it, but the cheapest catch is at
write time.

## Solution

Write the provenance chain with **bare ordinals** — `086 → 093`, or "ordinal
086", or "085 (provisional) → 086 (ship) → 094" — never the `ADR-086` literal.
Bare numbers preserve the full history a reader needs while keeping the
residual-grep clean. The plan's own tasks (1.3/1.4) had implicitly specified
the bare form (`renumbered 086→093`); the trap is re-introducing `ADR-NNN`
prose when you expand the note into a sentence.

## Key Insight

A history-preserving note about a renamed identifier lives INSIDE the scope its
own completeness gate greps. Any residual-zero AC that scopes over the renamed
artifact's directory turns the artifact's provenance prose into a self-inflicted
false-positive unless the note refers to the retired identifier by a form the
grep does not match (bare ordinal, not `ADR-NNN`). Generalizes beyond ADRs: the
same trap applies to any "renumber X → Y and grep that no `X` remains" sweep
whose scope includes a changelog / migration-note / provenance record that must
still *mention* X.

See also [[2026-07-05-adr-ordinal-collision-on-rebase-renumber-mine-not-mains]]
(the renumber-mine-not-mains pattern this cleanup followed).

## Session Errors

1. **Ordinal-note drafted with the literal `ADR-086`.** Recovery: rewrote both
   notes to bare ordinals before commit. Prevention: when adding a provenance
   note during a `grep-no-old-literal-remains` renumber, refer to the retired
   ordinal in a form the residual grep does not match (bare number). Now a
   Sharp Edge on the sibling renumber learning.
2. **[forwarded, plan phase] Spurious "file has not been read yet" Write** on a
   pre-existing plan file. One-off; the subagent read + reconciled. No recurrence
   vector.
3. **[forwarded, plan phase] `git push` Dependabot advisory banner.**
   Informational, not an error.
