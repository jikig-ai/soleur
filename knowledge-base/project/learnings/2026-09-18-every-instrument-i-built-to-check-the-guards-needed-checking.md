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

22. **My oracle had no row for the shape this repo actually emits.** Every one of the 337
    assertions across five suites drove the SINGLE-LINE directive; `ship/SKILL.md` and the golden
    fixture both emit it over FOUR lines. A stray fence between `script=` and `earliest=` in that
    multi-line body erased `earliest=`, `${earliest:-now}` skipped the soak gate, and the tracker
    closed PASS on day 0 — a live defect in the sweeper this PR exists to repair, invisible to
    the PR's own battery. — Recovery: a `test-design-reviewer` pass found it; guard added to all
    three parsers, pinned by a field-level assertion, mutation-verified both directions. —
    **Prevention:** when a suite tests a parser, enumerate the shapes the repo's own PRODUCERS
    emit and require one row per producer — `git grep` the emitters, do not derive the table from
    the fix you just wrote. A shape table written from the fix tests the fix, not the input.

23. **The absolute assertion I wrote to pin error 22 was vacuous the same way.** I asserted
    `authority_enrolled == 1` on the fence-interrupted body; that bit is TRUE both before and
    after the defect, because `script=` sits above the fence and enrolment only asks whether a
    directive exists. Removing the fix left the oracle **68/0 green**. — Recovery: assert the
    extracted `earliest=` VALUE. — **Prevention:** name the quantity the defect CHANGES before
    writing the assertion, then delete the fix and require RED. This is the third occurrence of
    the vacuous-fix-for-a-vacuous-assertion class in one session, which is why the rule is now in
    `plugins/soleur/skills/review/SKILL.md` rather than only here.

24. **My fix for the accounting-identity skew made the identity a tautology**, by moving `TOTAL`
    into `fail()`. `scripts/guard-vacuity-floor.test.sh` caught it immediately —
    `CASE counter incremented INSIDE a verdict helper`. — Recovery: call-site increment at the
    six direct `fail` sites instead. — **Prevention:** a repo-global ratchet is the one instrument
    a file-selected suite set cannot reach; run `guard-vacuity-floor.test.sh` after ANY edit to a
    suite's counters, not only after adding a suite.

25. **Three of four suites could have every verdict disarmed by one edit** and still report the
    honest run byte-for-byte, because their conservation identity and their assertion floor were
    both computed from a counter the disarmed helper still moves. The correct template was
    already in this PR, in two files, unpropagated. — Recovery: ported the instrument self-test
    plus an append-only ledger into all three. — **Prevention:** the durable unit for a guard
    pattern is a copy in every consumer, not a write-up — when a PR introduces a self-test block,
    the same PR ports it to every sibling suite, because the sibling that goes without it is the
    one nobody re-reads.

26. **A CI guard reported a file path nobody wrote, and the path was its own tokenizer's
    artefact.** `Block PR body citing files not in diff` failed on PR #8321 with
    `Orphan citations: skippingspecs/feat-.../upstream-reports.md`. No such string exists in the
    body: `skipping` is the tail of one inline-code span and `specs/feat-.../upstream-reports.md`
    is the whole of another, ~40 characters apart. `check-pr-body-vs-diff.sh` strips code spans
    with a naive backtick-pairing regex whose character class cannot express "a run of N
    backticks closes a run of N", so the four-backtick span I used to quote a three-backtick
    fence desynchronised the pairing for the rest of the line — gluing two spans together AND
    dropping every real citation on that line from the denominator. It invented a false finding
    and lost its true inputs in the same stroke, which is this PR's own subject matter arriving
    from a different subsystem. — Recovery: reworded the body to drop the nested backtick run,
    re-ran the gate against the live body (`cites no file paths`, rc 0), and filed **#8336**
    (different subsystem ⇒ file-tracked, not inlined, per the compound triage rule). —
    **Prevention:** when a guard names an artefact, grep the SOURCE for that exact string before
    believing it. A finding that cannot be located in the input is a finding about the
    instrument. Two filing gates also corrected me here and both were right: the body path had
    to be a literal (not `$BODY`) so the justification could be read, and "the guard is
    imperfect" is `meta/machinery`, never a user-impact claim.

### Post-merge addendum (the ship of PR #8321, 2026-09-18 21:00 → 2026-09-19 05:04)

27. **Eleven consecutive CI cycles were invalidated by a `main` commit landing mid-run.** Every
    branch necessarily carries a regenerated `INDEX.md` (lefthook re-stages it on every commit)
    that GitHub cannot merge textually, so any `main` commit makes the PR DIRTY; with sibling
    sessions shipping on the same ~65-minute cadence, the window never closed. — Recovery: the
    one vector I could remove, I removed — reset `rule-metrics.json` to `main`'s blob so the
    branch carried no diff on it (the aggregator rebuilds from the jsonl + archives, so nothing
    is lost); queued auto-merge early so the merge fires the instant checks go green; let the
    Phase 7 BEHIND auto-sync do the rest. It merged on the thirteenth cycle. — **Prevention:**
    queue `--auto` as soon as the pre-ready gates pass, not after CI is green; carry no diff on
    regenerable aggregates the branch does not need to own; and accept that the admin hatch is
    correctly unavailable to a diff with real code and real overlap.

28. **`rename-guard` attributed `main`'s own rename to this branch.** It walks every commit in
    `BASE..HEAD` with `--diff-merges=first-parent`, so a merge commit of `origin/main` shows
    `main`'s renames as ours; `git diff -M origin/main...HEAD` showed zero. — Recovery: a
    `Rename-Allowed-By:` trailer on an empty commit whose body names the rename, its origin
    (#8301) and why it is in range — the auditable exit, not the label. — **Prevention:** when a
    guard names an artefact, reproduce it with the guard's OWN command before believing the
    attribution; a first-parent walk and an endpoint diff answer different questions.

29. **A born-blocking guard that landed mid-flight (#8299's canonical-name census) caught two
    bare `/ship` references in the paragraph this branch added to `compound/SKILL.md`.** —
    Recovery: `soleur:ship`; 156/0, full bun set 3079/0. — **Prevention:** after every sync
    merge, run the full plugin bun set, not the diff-selected subset — a guard that arrived
    with the sync is by definition not in the selection.

30. **Two watches run from `/var/tmp` reported `total=0` and `fetch-error` because `gh` could
    not resolve the repository outside a checkout** — one read as "no runs", the exact vacuous
    settle the ship skill warns about. — Recovery: `-R jikig-ai/soleur` on every `gh` call in a
    detached watch. — **Prevention:** a watch that must outlive a worktree runs from outside it
    and therefore MUST name the repo explicitly; and a settle condition must require a non-empty
    population, because `grep -vc pending` on empty input is 0.

31. **Guard 2 fired on its first live run on `main` — on a tracker that was not in my census.**
    #8210 gained a fenced directive tonight from a sibling ship using the pre-fix template. The
    sweeper run exited 1 by design. Its probe was not yet on `main`, so unfencing would have
    traded one loud error for a script-missing one, and the body belonged to an in-flight
    sibling. — Recovery: left exact unfence + `secrets=` instructions on the issue; did not edit
    it. — **Prevention:** none needed for the guard — this is the guard working. For the human
    half: a census is a snapshot, and the window between census and merge is where the next
    member arrives.

32. **The archive-kb glob missed this branch's plan** (`*one-shot-7490-…*` does not match
    `2026-09-18-fix-7490-…-plan.md`), exactly as the compound skill's own note warns. —
    Recovery: `git mv` by hand, then swept both old paths repo-wide and repointed the six
    references (all inside the archived artefacts themselves). — **Prevention:** after ANY
    archive move, `grep -rl` both old paths across the tree before committing — the script
    relocates, it does not sweep.
