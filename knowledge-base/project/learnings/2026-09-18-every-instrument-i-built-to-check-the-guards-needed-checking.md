---
title: "Every instrument I built to check the guards needed checking first"
date: 2026-09-18
category: workflow-patterns
issue: 7490
pr: 8321
tags: [guards, mutation-testing, vacuity, grep, shell, measurement]
---

# Every instrument I built to check the guards needed checking first

## Problem

Six of 56 open `follow-through` trackers were dead: their `soleur:followthrough` directive sat
inside a markdown code fence, which the sweeper deliberately skips. The failure was SILENT — it
logged `no directive — skipping`, byte-identical to a tracker nobody ever wrote a directive for.
The oldest had been quiet since 2026-06, each with its directive plainly visible in the body.

The fix is three guards. Ten review agents then found that **every merge-blocking defect was in
the verification, not the fix** — and four of my own measuring instruments were broken in ways
that produced confident wrong answers rather than errors.

## Key Insight

**A broken instrument does not error. It answers.** A search returns a line, a probe returns a
count, a runner returns an exit code — each already shaped like a result. That is why the rule
"verify the instrument before reading its output" is not optional hygiene: the failure mode is
indistinguishable from success at the point of reading.

Four instances in one session, each of which briefly produced a wrong conclusion:

1. **A grep pattern that matched every line.** `'^[ ]?[ ]?[ ]?(\`\`\`|~~~)'` — backslash-escaped
   backticks inside a SINGLE-QUOTED shell word. A backtick is already literal there, and GNU grep
   reads `` \` `` as the buffer-start anchor, so the alternation degenerated to zero-width anchors
   and matched the empty string at position 0 of any line. The fence branch it gated fired on
   every body that reached it, and the arm below it was unreachable. Caught by the test row whose
   deny reason never appeared — not by reading the pattern.

2. **A parser-comparison harness that returned 0 for the known-good case.** I built a `sed`
   extraction of an awk program to compare two parsers; it mangled the program. The tell was the
   POSITIVE CONTROL: the case I knew must answer 1 answered 0. Without that control I would have
   reported a divergence that did not exist.

3. **A shape-anchored slice that silently stopped matching.** My parity oracle sliced the hook's
   awk program by its closing `')`. Adding a `|| printf` fallback to that awk changed the closing
   line, the slice truncated, and the oracle reported a divergence in the SUT when the fault was
   in the instrument. Fixed with CONTENT markers (`# parity-extract:begin/end`) plus a refusal
   when the extracted program lacks the constructs that define it — a truncated program is worse
   than an absent one, because it parses and answers.

4. **Sourcing the SUT clobbered my own verdict helper.** The parity suite sources
   `sweep-followthroughs.sh` to get the authority; that file defines its own `fail()`. My helpers
   were declared ABOVE the source, so every verdict routed through the SUT's logger and my
   counters never moved. The instrument self-test caught it — which is the entire reason the
   self-test exists.

## The second insight: my fix for a vacuous assertion was vacuous the same way

A review agent PROVED one of my assertions vacuous: it deleted `claude plugin list` from the
runtime message in `sync.md`, left it only in the surrounding prose, and the suite stayed
**13/13 green**. The haystack was the whole file, so the sentence EXPLAINING the property pinned
the property.

My first fix scoped the haystack to the runtime messages — and was vacuous in exactly the same
way, because a bare `*"` opener also matches inside a bash snippet (`[[:space:]]*"`), opening a
span that never closed and swallowing 79 lines of prose. Only anchoring on ` *"` (space-star-quote)
made it real, verified in BOTH directions on two different literals.

This is `cq-assert-anchor-not-bare-token` at its sharpest: **the moment a task requires both
"assert X" and "document X", the documentation becomes false-match surface for the assertion**,
and the richer the rationale the larger the surface.

## The third insight: a back-derived number contradicts something you already measured

I published "the declared-`secrets=` population went 24 → 28". A review agent falsified it without
needing my population snapshot, using only my own other figure:

- honoured directives grew 25 → 31, i.e. by exactly **6**;
- all six newly-honoured trackers declare `secrets=` after the edit;
- so the declaring set must grow by 6, and 24 → 28 grows by 4.

The real answer is **22 → 28**. My 24 was `28 − 4` — back-derived from "four probes gained the
clause" — and it silently dropped the two trackers that already carried `secrets=` INSIDE their
fence, where no parser could read it. **A figure you did not measure will eventually contradict
one you did.**

## Solution

Three guards, plus two the review round added:

- **Rule 3** of the probe lint: every repo-relative path literal in a probe must name a tracked
  artefact, resolved from the repo root (where the sweeper actually runs probes).
- **A loud sweeper verdict** for a fenced-only directive, mirroring `MISSING_SECRET` exactly.
- **Producer/consumer agreement** across four readers of the directive.
- **`scripts/followthrough-predicate-parity.test.sh`** — a differential oracle over 16 body shapes
  × every executable reader, asserting EQUALITY with the authority rather than a direction. Added
  because the comment saying "mirror BOTH places" demonstrably does not work: this PR mirrored two
  of three, inside the commit titled "make every producer agree with its consumer".
- **Deletion of a sixth parser copy** in `ship-followthrough-directive.test.sh`, which diff-checked
  a stale mirror against the real parser over a fixture containing **no fence at all** — blind to
  every property that changed, and green throughout.

## Prevention

- **Run the known-positive before reading any negative.** An instrument never shown to produce a
  positive has not returned a negative; it has returned silence.
- **Anchor extractions on CONTENT, never on shape.** A slice keyed on a closing delimiter is
  coupled to every future edit of the thing it slices.
- **Define verdict helpers AFTER sourcing a SUT**, and give every suite an instrument self-test
  that drives both helpers and checks all their observables moved — counters AND the ledger the
  verdict reads.
- **Never escape a backtick inside single quotes.** It is already literal, and in an ERE the
  escape changes the meaning.
- **A number you did not measure is a liability.** Before publishing a delta, check it against
  every other delta you measured in the same change.
- **On a fix PR, review the new ASSERTIONS before the new code.** They are written while holding
  the defect in mind, and they inherit its framing.

## Session Errors

1. **Two plan premises were false and would have shipped as rationale.** The plan justified the
   dialect-safe fence predicate by claiming mawk would decline interval expressions and silently
   disable the fence skip across all 56 trackers. Measured against mawk 1.3.4 built from source:
   both spellings work, and the literal-bytes fallback does not occur. — Recovery: built mawk,
   measured, corrected the shipped comment to justify the safe form on its surviving grounds. —
   **Prevention:** a plan-quoted claim about a TOOL's behaviour is a precondition; the plan is
   authoritative for intent, never for the tool's semantics.

2. **AC7's own verification command was broken.** `sed -n 's/^REPORTS="\?//; s/"\?$//p'` puts `p`
   on the second substitution and `"\?$` matches empty at every line end, so it printed all 134
   lines. — Recovery: corrected to a single anchored substitution. — **Prevention:** run an AC's
   literal command once before trusting it as a gate.

3. **`pipefail` + `grep -q` SIGPIPE false-negative reported 22 tracked paths as MISSING on a clean
   tree.** `grep -q` closes the pipe on first match; the 18k-line producer takes SIGPIPE; the
   pipeline exits non-zero although grep MATCHED. — Recovery: grep a file operand, no pipe. —
   **Prevention:** the repo documents this trap; it recurred inside the file implementing a guard.
   Never `producer | grep -q` under `pipefail`.

4. **`local` outside a function aborted a fail-OPEN merge gate.** `bash -n` passes it; the suite's
   deny rows going to `<none>` caught it. — Recovery: dropped `local`, recorded why. —
   **Prevention:** for any gate that fails open, enumerate what makes it emit no decision.

5. **A degenerate fence grep matched every line** (see Key Insight #1). — Recovery: unescaped the
   backticks. — **Prevention:** routed to definition below.

6. **Rule 3's `literal-default` arm silently dropped hyphenated first segments.** The backward
   walk to the nearest `-` finds the `-` of `:-` only when segment one is hyphen-free, so
   `${OV:-knowledge-base/…}` yielded `base/…` and vanished with no diagnostic. — Recovery: capture
   the default directly; fixtured both ways. — **Prevention:** when a parser walks backwards to a
   delimiter, ask which OTHER occurrences of that delimiter the input can contain.

7. **My own assertion was satisfied by prose I added — and my first fix was vacuous the same way.**
   (see Key Insight #2). — Recovery: anchored the italic opener on ` *"`; proved non-vacuity in
   both directions on two literals. — **Prevention:** routed to definition below.

8. **Two mutation rows were silently disarmed** when I edited the expressions they anchor on
   (the soak gate's enrolment grep; the directive gate's branch comment). — Recovery: both landing
   assertions reported "mutation did NOT land" and I re-anchored. — **Prevention:** already
   working as designed. Grep the battery for any literal you change.

9. **The `24 → 28` figure was back-derived** (see Key Insight #3). — Recovery: re-measured 22 → 28,
   corrected the shipped workflow comment and the record. — **Prevention:** in Key Insight.

10. **AC26's premise was wrong** — it prescribed FILING a sweeper-dedup tracker; **#7923** already
    existed and its §1 is exactly that scope. — Recovery: cited it, filed nothing. —
    **Prevention:** search by the BEHAVIOUR, not by the phrase the plan uses for it.

11. **The rule-3 census found 5 misses, not the plan's 2.** Three were false positives: `git
    ls-files` lists no directories and four probes legitimately cite one. — Recovery: membership
    set = tracked files PLUS their ancestor directories. — **Prevention:** when an existence check
    consults a file list, ask whether the thing being checked can be a directory.

12. **Sourcing the SUT clobbered my `fail()`** (Key Insight #4). — Recovery: moved helpers below
    the source. — **Prevention:** routed to definition below.

13. **My parser-comparison harness returned 0 for the known-good case** (Key Insight #2 of the
    instrument list). — Recovery: abandoned the reconstruction, drove the real hook end to end. —
    **Prevention:** a reconstruction of a SUT is a second implementation; drive the real one.

14. **A shape-anchored slice stopped matching after I edited the sliced program** (Key Insight #3
    of the instrument list). — Recovery: content markers + an extraction self-check. —
    **Prevention:** routed to definition below.

15. **The full battery was REFUSED (rc=4)** with a sibling full-gate run 48 minutes in. —
    Recovery: derived 35 substitute suites from consumers AND the diff's new vocabulary; the full
    battery runs at the `/ship` checkpoint. — **Prevention:** working as designed.

16. **`guard-vacuity-floor.test.sh` reddened on a repo-global ratchet** no file-selected suite
    could surface — the new directive-gate floor grew the deferral ledger 47 → 48. — Recovery:
    promoted into `PROMOTED_FILES` per the gate's own FAIL message, not by raising the ceiling. —
    **Prevention:** the documented class; it fires whenever a change adds a test, a floor or a
    regex.

17. **Ran the Eleventy build from `plugins/soleur/docs` instead of the repo root**, where the
    config lives, and briefly read `filter not found: dateToShort` as a build failure caused by my
    edit. — Recovery: read the workflow's own build command. — **Prevention:** take a build's
    invocation from its CI job, never from intuition.

18. **`gh run view --log` returns CR-laden lines** that truncated every extraction until stripped
    with `tr -d '\r'`. — Recovery: strip CR before parsing. — **Prevention:** one-off.

19. **UNRESOLVED: #6617 reads rc=0 PASS locally and exit 1 FAIL under the sweeper.** Measured both
    with and without `GH_REPO`, so repo resolution is not the cause; the remaining difference is
    token identity, which should not affect `authorAssociation`. — Recovery: the record and the PR
    body state the SWEEPER's verdict, because it is the authority. — **Prevention:** when a local
    reading contradicts the authority, publish the authority's and say the cause is unestablished.

20. **The sweeper dry run sat queued ~28 minutes** behind a repo-wide Actions backlog (13 of 15
    recent runs queued) and my first Monitor expired silent. — Recovery: re-armed; the run
    completed and AC17 was read from the log. — **Prevention:** one-off; a silent Monitor expiry
    is a re-arm signal, not an answer.

21. **I ran `archive-kb.sh` at compound Step E and it archived the spec of the STILL-IN-FLIGHT
    branch** — `measurements.md`, `tasks.md` (two boxes still open), `session-state.md` and both
    `upstream-reports` files moved to `specs/archive/20260918-194554-…/`, leaving four references
    in this branch's own plan pointing at a path that no longer existed. That is defect (b)(2) of
    this very PR — a probe/record broken by an archive move inside the PR that shipped it —
    reproduced by the pre-ship step, against the plan's own line 511: *"compound's archival of this
    spec dir must be deferred until after Phase 6 or step 2.5 reads nothing."* — Recovery: reverted
    with `git mv` back to the live path (the rename was staged, nothing was lost), re-ran
    `generate-kb-index.sh`, and deferred archival to after `/ship` Phase 6. — **Prevention:**
    `archive-kb.sh` takes no signal from merge state, so the ordering constraint has to be read
    from the plan before Step E runs, not after. Before invoking it, grep the branch's plan and
    spec for `archival`/`archive` deferral language, and grep the tree for references to the live
    spec path — a script whose whole job is to MOVE an artefact is the one place a reference sweep
    is mandatory, and it is the class this PR exists to close.
