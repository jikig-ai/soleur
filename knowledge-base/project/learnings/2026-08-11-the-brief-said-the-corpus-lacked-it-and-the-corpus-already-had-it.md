---
date: 2026-08-11
category: workflow-patterns
module: plan, plan-review, review, test-design-reviewer
tags: [minimality, restatement, instrument-verification, review-panel-cost, premise-validation]
branch: feat-one-shot-plan-phase-cost-controls
pr: 7439
---

# Learning: the brief said the corpus lacked it, and the corpus already had it

## Problem

A task brief asked for six prose changes installing one question at plan time —
*"which requirement does this mechanism satisfy, and does a simpler mechanism already
satisfy it?"* — after the ADR-176 session (merged `c1145dc4d`) spent ~1.8M tokens and
found twelve blocking defects behind a 285/285 green suite, **nine of which dissolved
when the redesign deleted the machinery they lived in**.

Item 5 of that brief asked for a seven-axis mutation checklist, justified thus:

> "The corpus already says 'audit the axes, not the count' but never enumerates them."

That justification is false, and it was written by a session that had just lived the
incident it was citing.

## Root cause

`plugins/soleur/skills/review/SKILL.md` on `origin/main` — the bullet beginning
*"Escalating a shape-matching guard to an EXECUTING one"* — already contained:

- **Five of the seven axes, inline and by name:** dispatch, fixture shape, fixture
  direction, extractor uniqueness, and the harness's own `.trim()`.
- **The same two measured survivors the brief cited as new evidence:**
  `TOKENS = []` → 26/0, and deleting the executing `describe` → 17/0 with exit 0.
- **The same meta-rule:** "enumerate the AXES a battery edits, not the count it reports."
- **The same learning-file citation**, from the same session.

`set's cardinality` was named in a sibling bullet. Only "SUT content" — the axis every
battery already covers — was genuinely absent, because it is the trivial one.

**The grep that made the gap look real measured the wrong artifact.**
`grep -in 'mutation|axes' plugins/soleur/agents/engineering/review/test-design-reviewer.md`
exits 1. That is true, and it is not evidence of a corpus gap: the agent file is empty of
axis guidance *by design*, because `review/SKILL.md` injects it at spawn time through five
separate "the spawn prompt for `test-design-reviewer` MUST say …" bullets. The negative grep
was run against the consumer, and read as a statement about the authority.

## Solution

Applied the change's own new minimality gate to the change itself. The seven-row table was
a second copy of live prose — numbers included — which is the restatement anti-pattern
item 1 exists to prevent. It was cut to a **pointer**: the agent file gets the axis
vocabulary and the instrument rule and is sent to `review/SKILL.md` for the substance.

The residual gap that justifies even the pointer was verified, not assumed: the agent
carried no standing mutation guidance at all, and it is spawned by callers other than
`review/SKILL.md` — which is the only thing that injects the axes.

Two further defects in the same PR, both caught by review and both verified before acting:

- **A caller-side instruction the callee is told to ignore.** Item 3 added a per-mechanism
  question to `plan-review/SKILL.md`. But `code-simplicity-reviewer.md` carries a standing
  fallback rendering `### Hidden Assumptions` and `### Goal Verification` as
  `_N/A — no diff in scope._` when invoked from **`plan-review`** — the exact caller. The
  new instruction was silently no-opped. Fixed by carving `plan-review` out of that
  fallback and defining the mechanism→requirement mapping as the no-diff analogue.
- **A cost gate that increased cost.** The new `design-risk` signal ran a design-validity
  pass using `code-simplicity-reviewer` + `architecture-strategist` + `performance-oracle`
  — all three of which the full panel *also* spawns (the first again at review Step 4).
  A `code`-class PR would have spawned **11 where it used to spawn 8**, on a gate whose
  entire justification is token cost. Fixed with a mandatory dedup rule, plus firing the
  economics lens only when there is an actual economics claim to check.

## Key insight

**When a brief asserts "the repo does not have X", verify that claim against the repo
before building X — and check which artifact the supporting grep measured.** A negative
grep on a file that was never the authority is indistinguishable from a real gap, and it
reads as stronger evidence than prose because it is a command with an exit code.

The sharper form: a brief written by the session that lived an incident carries that
session's framing, and inherited *sentences* get none of the re-derivation we apply to
inherited *numbers*. This corpus already knows that ([[2026-08-06-i-shipped-two-unmeasured-causal-claims-inside-the-lint-that-forbids-them]]);
this is the same shape one level up, where the inherited claim is about the corpus itself.

**Corollary on gate economics:** a new gate that duplicates lenses a later phase re-runs is
a cost increase wearing a cost-saving justification. Count the spawns in **both** the
success and the failure case before claiming a saving — the ~1.2M figure that motivated
this gate is one measured failure case, not a base rate.

## Session Errors

- **`worktree-manager.sh cleanup-merged` timed out after 2 minutes**, emitting
  `SOLEUR_GIT_BARE_POISON`; `create` then hung 7 minutes. Root cause was neither script:
  SSH to the GitHub host on port 22 was unreachable (confirmed outside the sandbox too) while
  HTTPS was healthy. **Recovery:** repo-local `url.https://github.com/.insteadOf` plus a
  `gh auth git-credential` helper. **Prevention:** when a git-touching script hangs with no
  output, probe the transport before reading the script as broken — `git ls-remote` with a
  timeout separates a wedged remote from a wedged script in seconds.
- **My own TCP probe returned rc=124 and I nearly read it as "port 22 is unreachable".**
  The instrument was `head -c 40` against a ~19-byte SSH banner: it blocked waiting for
  bytes that would never arrive. **Prevention:** the known-positive/known-negative control
  this PR adds — re-running with a bounded `read` gave rc=0 on port 22 and rc=124 on a
  blackhole port, which is what made the reading trustworthy.
- **A review agent wedged for 26 minutes and had to be killed.** Its final message: its own
  comparison instrument was defective because the fail lines carry per-test timings, so
  every diff was noise. **Prevention:** the same generalized instrument rule — this is the
  failure class occurring live during the review of the fix for it.
- **Item 5 was built on a false premise** (above). **Prevention:** plan Phase 0.6b step 2,
  added by this PR, requires answering "does an existing repo mechanism already buy this
  property?" by grepping the authority — and this session is the proof it must name the
  right artifact.
- **Item 3 shipped inert** and **`design-risk` raised the panel 8→11** (above).
  **Prevention:** both were caught only because the review panel was asked the
  per-mechanism question rather than "is this good?" — which is item 3's whole thesis,
  validated against itself.
- **The 0.6b draft asked about "every mechanism the plan proposes" while running before any
  plan exists**, contradicting Phase 1.7.5's own "defer this check until they exist rather
  than guessing" five hundred lines below. **Prevention:** scope a pre-research check to
  the artifact that exists at that point — the feature description — and say so explicitly.
- **A new section was first inserted mid-group**, splitting `### Patterns Observed` in
  `test-design-reviewer.md`. One-off; corrected by appending at the end.

## Prevention

1. Treat "the corpus lacks X" in any brief as a claim to verify, not a premise to build on.
   The check is one grep against the **authority**, not against the consumer.
2. Before adding prose to a corpus at `[WARN]` budget, grep for the sentence you are about
   to write. If it exists, extend that site or point at it — never copy it, especially not
   with its measured numbers attached.
3. For any new review-panel stage, enumerate the spawns it adds and the spawns it
   duplicates. A stage justified on cost must show its arithmetic in the success case, not
   only the failure case that motivated it.
4. When a caller gains an instruction, check the callee for a standing rule that disables
   it under that caller. A no-op instruction is worse than no instruction: it reads as
   coverage.
