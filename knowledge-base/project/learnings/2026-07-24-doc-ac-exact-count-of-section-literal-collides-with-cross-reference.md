# Learning: A doc AC that pins `grep -c '<literal>' == 1` collides with a legitimate cross-reference using the same literal

## Problem

Plan AC6 for #6901 asserted the ADR-140 amendment section exists exactly once:

```
grep -c 'Amendment (2026-07-24, #6901)' ADR-140*.md   # expected == 1
```

While applying the amendment I did two correct things that together broke the AC:
1. Added the `## Amendment (2026-07-24, #6901)` section header (the referent AC6 counts).
2. Updated the stale alternatives-table cell ("three coupled edits") to **cross-reference** that amendment — and I wrote the cross-ref using the *same full literal*: "see the **Amendment (2026-07-24, #6901)** below".

`grep -c` then returned **2**, failing an AC that was actually satisfied (the section does exist exactly once). The count was measuring "occurrences of the literal string", not "occurrences of the section".

## Solution

Reword the cross-reference to a distinct short form so the full dated literal remains unique to the section header:

- Section header: `## Amendment (2026-07-24, #6901)` (the one referent AC6 counts)
- Cross-ref elsewhere: `see the **#6901 Amendment** below` (does NOT contain the counted literal)

`grep -c` → 1. AC6 satisfied, and the cross-reference still resolves for a human reader.

## Key Insight

An AC of the form `grep -c '<exact string>' == 1` is a proxy for "this section exists once" — but the command counts the **string**, not the **section**. Any legitimate cross-reference, TOC entry, or "see X below" pointer that quotes the same string inflates the count and false-fails a correct artifact. Two ways to keep them from colliding:

- **Author side:** make cross-references use a *distinct* short form (`#6901 Amendment`) so only the section header carries the exact counted literal.
- **AC side (better where you control the AC):** anchor the count on a form only the header can take — `grep -c '^## Amendment (2026-07-24, #6901)'` (the `^## ` prefix a prose cross-ref cannot produce). This is the same "anchor on syntax, not a bare token" discipline as `cq-assert-anchor-not-bare-token`, applied to an existence-count AC.

## Session Errors

- **AC6 literal-collision (recurring class)** — Recovery: reworded the cross-ref to `#6901 Amendment`. Prevention: anchor count-ACs on `^## <literal>` OR keep cross-refs on a distinct short form. Routed to the plan skill's authoring guidance.
- **Double-backgrounded `test-all.sh` (one-off)** — Ran `run_in_background: true` AND an inner `( … ) &`, so the harness tracked only the launcher (immediate exit 0) and the real subshell's `EXIT=` line never landed in the tracked output. Recovery: found the real log + PID via `ps -ef | grep test-all`. Prevention: pick ONE backgrounding mechanism — `run_in_background: true` with a foreground body, never `run_in_background` + inner `&`. Already covered by the documented "background wrapper exit code ≠ the command's" trap; no new rule needed.

## Tags
category: workflow-patterns
module: doc-acceptance-criteria
