---
title: I fixed the guard twice and my test could not see either fix
date: 2026-08-10
category: test-failures
module: plugins/soleur/skills/plan
related: [7418, 7419, 7420, 7421, 4724]
related_adrs: [ADR-175]
---

# I fixed the guard twice and my test could not see either fix

## Problem

`soleur:plan` ran its entire research fan-out before writing any byte to the plan file, so an API
stall discarded the whole spend (measured: 44 tool calls, ~268k subagent tokens). The fix — a
skeleton checkpoint plus a `pipeline_resume:` frontmatter cursor — shipped with a **285/285 green
suite**, a clean typecheck, and a self-run 9-mutation battery reporting every mutation RED.

A 12-agent review then found **twelve blocking defects**, four of which I had introduced *while
fixing earlier ones*. The mechanism was rejected and replaced.

## The three-layer failure on one guard

The most instructive defect recurred three times on the same eight lines, and each "fix" felt like
diligence:

1. **Line-anchored reader.** `awk '/^pipeline_resume:/'` read the key from a document's *body*. Any
   plan that documents this mechanism contains the key in its body — including the plan for this
   very feature, which is how it was found.
2. **An inert guard.** The fix added `[[ ... ]] || CURSOR=""` followed by an *unconditional*
   `CURSOR=$(sed ...)`. The guard assigned into a variable the next line overwrote, so it could
   never change the outcome. **The contract test passed**, because it asserted the reader's SHAPE
   and both `head -n 1` and the `sed` range were present.
3. **A re-arming range.** The second fix bounded with `sed -n '/^---$/,/^---$/{...}'`. But **sed
   ranges re-arm**: after closing on the frontmatter terminator, the range opens again at the next
   bare `---`. Measured — a file with real frontmatter and a `---`-delimited body example returned
   `research` where the answer must be empty. 200 of 1531 plans have that shape.

Each fix was verified by a test that could not observe the property it claimed to pin.

## Key insight

**A test that asserts a guard's SHAPE cannot see a guard that does not RUN.** The escalation is to
*execute* the prescribed snippet against fixtures whose correct answers differ — but that is not
sufficient either. My executing tier used `blocks.find(...)` to pick the fenced block, and nothing
asserted uniqueness. Adding a decoy block above the operative one and reverting the real reader
left the suite at **26 pass / 0 fail**: the tier whose whole premise was "execute what the skill
prescribes" ran against documentation.

**A self-run mutation battery is evidence about the mutations you imagined.** Mine went 9-for-9 RED
and was blind to five axes it never touched: the dispatch layer (`PLAN_OWNED_TOKENS = []` → 26/0;
deleting the executing `describe` → 17/0, exit 0), fixture shape, fixture direction, extractor
uniqueness, and the harness's own `.trim()` — which normalized where production does not, making the
entire trailing-whitespace class *untestable as written*.

## The deeper lesson: the defect was the second signal, not any of its bugs

Every one of the twelve defects reduced to one sentence: **a dedicated progress key carried a signal
that could disagree with the file's own content, and every disagreement resolved to a fail-open arm.**
The tell was in the design itself — the verdict table was *conjunctive*. ANDing the cursor with a
content assertion concedes that the content is the real predicate and the cursor is advisory.

Two consequences were fatal and neither was a coding error:

- `deepening` is set *after* plan finalization and `finalize` *after* Acceptance Criteria land, so
  both always have all sections — and the table routed both to "re-plan from scratch". Every
  late-stage stall discarded a completed plan: the exact loss the feature existed to prevent.
- A cap-trip and every `deepen-plan` HALT **deleted** the key, so a designed refusal became
  indistinguishable from success and advanced a stub into `/work`.

The resolution was to delete the mechanism, not repair it: assert completion from
`## Acceptance Criteria` — the one heading in all three detail-level templates, written last. Nine
of twelve defects vanished with the machinery carrying them (ADR-175).

## Solution

- Read frontmatter with an `awk` state machine that **exits at the second `---`**, never a `sed`
  range (re-arms) and never a line-anchored scan (reads the body).
- Make drift-guard extractors demand **exactly one** matching block; a first-match extractor is
  defeated by a decoy.
- Pair every "returns empty" assertion with a **non-empty positive control**, and give the suite at
  least one fixture per direction — a suite armored only against reading *too much* is defenceless
  against reading *too little*, which is the direction that fails toward "complete".
- Prescribe the **writer** at the same site as the reader, or do not create the key. A pinned reader
  with an invented-per-site writer is a reader plus an unbounded set of producers.

## Prevention

- **Before trusting a mutation battery, enumerate the AXES it edits, not the count it reports.** N
  mutations of one shape is one mutation.
- **Mutate the guard OUT and re-run.** If the suite stays green, the guard is pinned by nothing.
- **`git add ""` aborts atomically.** An unbound path variable does not degrade to a partial add —
  it takes every sibling path in the same command with it. Guard with `: "${VAR:?message}"`.
- **An ordinal is provisional until merge.** ADR-144 collided because the probe was
  `origin/main`-scoped; ADR-174 then collided because a sibling landed it *after* I verified.
  Quantify over all pushed refs **and** re-check immediately before merge.
- **A measurement that justifies a decision must use the method the decision mandates.** The
  `338/1531` figure supporting "abandon `status:`" was produced by the unbounded reader the same
  document condemns (bounded: 321/1531).
- **Never `pgrep -f <pattern>` where the pattern appears in your own command line** — it matches the
  invoking shell. Cost me an exit-144 self-kill.
- **A forward-looking sentence is not a handoff.** "Continuing to /compound" as the last thing in a
  turn is an abandoned pipeline; the next tool call must be the successor.

## Session Errors

- **ADR-144 chosen via an `origin/main`-only probe.** Recovery: re-derived over all 62 pushed refs.
  Prevention: an ordinal probe quantifies over pushed branches, not the default branch.
- **ADR-174 collided after verification** — a sibling landed it on `main` mid-session. Recovery:
  ADR-175. Prevention: re-run the ordinal probe immediately before merge, not once at plan time.
- **Shipped an inert `||` guard.** Recovery: rewritten as `if/fi`. Prevention: a guard that assigns
  into a variable a later unconditional line overwrites is dead; mutate it out and confirm RED.
- **Contract test asserted shape, not behavior.** Recovery: extract-and-execute the prescribed
  block. Prevention: name a mutation that satisfies the assertion while violating the property.
- **`sed` range re-arms.** Recovery: `awk` state machine exiting at the second `---`. Prevention:
  bound to the FIRST block explicitly; ranges are re-triggerable by design.
- **`.find()` extractor admitted a decoy.** Recovery: require exactly one match. Prevention:
  first-match selection is not unique-match unless something asserts it.
- **`$PLAN_PATH` never bound.** Recovery: one variable name plus a `:?` guard. Prevention: for any
  `$VAR` in a prescribed shell block, assert an assignment exists in the same file.
- **Budget sweep missed two authoritative sites**, one of them injected into every session, because
  `1,800` is comma-formatted. Recovery: swept both. Prevention: sweep the semantic quantity, not the
  literal spelling.
- **Deleted a correct figure (2500 agent budget) while the stale one survived.** Recovery: restored.
  Prevention: when de-literalizing, check whether the number being removed is the stale one.
- **My own `awk` range ran to EOF**, producing a count that contradicted a correct review finding.
  Recovery: the explicit heading listing was authoritative. Prevention: verify the instrument before
  disputing a finding with it.
- **`pgrep -f 'test-all\.sh'` matched its own command line**; I killed my own shell (exit 144).
  Recovery: bracket trick (`grep '[t]est-all'`). Prevention: never pattern-match a string your own
  command contains.
- **Claimed contention had "eased", then measured `/tmp` at 98% with zero runners.** Recovery: the
  isolated re-run settled it. Prevention: `LOW_TMP_HEADROOM` fires on nearly every run here, so its
  presence alone is weak evidence — the isolated pass is the discriminator.
- **Ended a turn on "Continuing to `/compound`" without doing it.** Recovery: operator asked why I
  stopped. Prevention: the successor invocation must be the next tool call in the same turn.
- **Reported "12 agents back" when 11 had returned**, and wrote to a scratch dir before creating it.
  One-offs; noted.
