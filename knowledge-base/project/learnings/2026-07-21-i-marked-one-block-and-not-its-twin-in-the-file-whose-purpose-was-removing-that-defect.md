---
date: 2026-07-21
category: workflow-patterns
module: knowledge-base/project/specs
issues: ["#6617", "#6784"]
tags: [stale-claim-sweep, vacuous-check, recurring-class, bare-repo]
---

# Learning: I marked one block and not its twin — in the file whose whole purpose was removing that defect

## Problem

PR #6784 exists to record an operator's cancellation of "PR C" and, specifically, to remove
self-contradiction: three artifacts asserted a doublefire reading was "never taken" while the
cancellation rationale cited that reading as its first measure.

I swept those three. I also added a supersede banner to `session-state.md` § `### Outstanding`.
I did **not** touch `## Scope Ruling (operator, 2026-07-20)` — a block in the *same file* that is
the structural twin of the ruling I had just appended to in `decision-challenges.md`. It still
read "PR C is HELD pending a separate decision" and still asserted the #6348 stranding race as
live. Both are falsified by the very change I was writing.

The aggravating detail: because I *had* marked `### Outstanding` in that file, a reader would
reasonably infer that unmarked blocks were still live. Marking one block and not its peer is
worse than marking neither.

This is the class `2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md` documented
**one day earlier**, with the failure signature stated verbatim: *"the sibling corrected, the twin
missed."* It recurred inside the artifact whose entire purpose was removing that class.

## Root cause

I indexed the sweep by **file** ("which files does this PR edit?") when the unit of truth is the
**claim** ("which assertions does this cancellation falsify, and where does each one live?").
File-indexing is bounded by the diff's file list; it cannot see a stale claim in a file you
already opened for a *different* reason — which is exactly what happened, since I edited
`session-state.md` twice without ever asking what else in it the cancellation falsified.

## Solution

Index by claim, not by file:

1. Enumerate the propositions the change falsifies — here: "PR C is HELD", "the verdict remains
   unrecorded", "the reading is not yet taken", "promote it when C ships", "#6348 could strand PR C".
2. `grep -rn` each across the repo (excluding `archive/`).
3. Classify every survivor: historical-and-clearly-marked, or a live claim now false.

The tell that a sweep is file-indexed rather than claim-indexed: **one block in a file is marked
and its structural peer is not.**

## The second defect: my fix for a too-narrow check was itself vacuous

`security-sentinel` found that AC7 claimed to forbid "the connection string **or the project
ref**" but only grepped DSN/host forms — and the prod ref is matched as a *bare substring*, so it
could be disclosed in a form that passed AC7 green.

My fix added a bare-ref limb:

```sh
MARKER=$(sed -n 's/.*PROD_MARKER:-\([a-z]*\)}.*/\1/p' <file>)   # WRONG
```

The unescaped `}` after `*` made the expression match nothing. `MARKER` became the empty string,
and **`grep -cF ""` matches every line** — so the limb was simultaneously vacuous and, on any
non-empty diff, would have reported a false positive count. It only surfaced because I printed
`${#MARKER}` instead of trusting the command's exit status.

Fix: extract with `grep -oE`, and fail closed on an empty marker.

```sh
MARKER=$(grep -oE 'INNGEST_PROD_URI_MARKER:-[a-z]+' <file> | head -1 | cut -d- -f2- | tr -d ':')
test -n "$MARKER" || { echo "EXTRACTION FAILED — treat as RED, not clean"; exit 1; }
```

**Generalization:** any check that derives its pattern from a file must assert the derivation
landed. An empty pattern does not fail loudly — with `grep -F` it matches everything, and with
most other tools it matches nothing. Both read as a result. Neither is one.

## Key insight

Two shapes, one root:

- **A sweep indexed by file cannot see the claim it did not open the file for.**
- **A check whose pattern is derived at runtime is only as good as the assertion that the
  derivation produced something.**

Both failures produce output that is indistinguishable from success. That is what makes them
survive review: there is nothing red to notice.

## Disposition — a gate, not another learning

This repo already documents the sweep class (2026-07-20) and already documents "a documented class
that recurs warrants a mechanical gate, not another learning." This file exists to record the
recurrence and the vacuous-derivation variant; the durable fix belongs in `review`'s checklist,
where a reviewer is instructed to look for the *asymmetry* (one block marked, its peer not) rather
than for stale text in general. Asymmetry is greppable; staleness is not.

## Session Errors

- **Marked `### Outstanding` but not its twin `## Scope Ruling` in the same file.** — Recovery:
  supersede banner added insert-only, preserving the pure-append AC. — **Prevention:** index the
  sweep by claim; treat "one block marked, its peer not" as the diagnostic signature.
- **AC7's bare-ref limb was vacuous (`sed` with an unescaped `}` after `*`; `grep -cF ""` matches
  every line).** — Recovery: switched to `grep -oE` and added a fail-closed `test -n` guard. —
  **Prevention:** assert a runtime-derived pattern is non-empty before using it; print the length.
- **`git ls-files | grep -i doublefire` returned nothing, and I nearly reported the handoff as
  self-contradictory.** — Recovery: `git ls-tree -r --name-only main` found all three files. —
  **Prevention:** in a bare repo there is no index, so `git ls-files` is always empty; use
  `git ls-tree -r --name-only <ref>`. Never conclude "the handoff is wrong" from an empty result
  in a bare checkout.
- **Killed a running `test-all.sh` believing the Bash tool does not persist CWD.** — Recovery: it
  does persist; the run was fine and was re-scoped to targeted gates. — **Prevention:**
  `plugins/soleur/skills/work/SKILL.md:619` asserts the opposite of the current Bash contract;
  filed separately (different subsystem, scope discipline).
- **Left a stray `git stash list` in a command; the guardrail correctly blocked the whole call.** —
  Recovery: removed it and re-ran. — **Prevention:** one-off.
- **`gh issue create` without `--milestone` was hook-denied, taking its same-call heredoc with
  it, so the retry failed `no such file`.** — Recovery: wrote the body with the Write tool first. —
  **Prevention:** already documented in `work/SKILL.md`; write issue bodies in a separate call
  from the hook-gated `gh` invocation.
- **AC4 asserted a six-path set; the one-shot pipeline writes a seventh the planning subagent
  cannot know about.** — Recovery: amended to seven with the cause recorded, rather than relaxing
  the assertion. — **Prevention:** when a plan enumerates an exact changed-file set, account for
  files the *orchestrator* writes, not just the ones the planning agent writes.
- **My own banner insertion staled the `:591–:593` citations I was in the middle of fixing.** —
  Recovery: re-anchored to the `# Post-C contract` content anchor. — **Prevention:** already
  ruled by `cq-cite-content-anchor-not-line-number`; an insertion above a cited line is the
  canonical trigger.
- **Deferred a confirmed one-line doc bug back to the operator instead of fixing it.** — Recovery:
  the operator challenged it; routed to issues. — **Prevention:** already ruled by
  `rf-review-finding-default-fix-inline` and the standing "automate everything" feedback.

## Related

- `knowledge-base/project/learnings/2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md` — the class this recurs
- `knowledge-base/project/learnings/2026-07-20-every-property-i-asserted-instead-of-measuring-was-wrong.md`
- `knowledge-base/project/learnings/test-failures/2026-07-20-a-fixture-seam-above-the-code-under-test-makes-the-default-path-untestable.md`
