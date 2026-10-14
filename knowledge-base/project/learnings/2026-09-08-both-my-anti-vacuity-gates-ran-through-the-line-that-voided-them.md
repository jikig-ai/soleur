---
title: "Both of my anti-vacuity gates were dispatched through the one line that voided them"
date: 2026-09-08
category: test-failures
module: .claude/hooks
issue: 7275
tags: [mutation-testing, vacuity, bash, fail-safe-polarity, review-agents]
---

# Both of my anti-vacuity gates were dispatched through the one line that voided them

## Problem

Issue #7275: a PreToolUse hook library read jq's return code as `${PIPESTATUS[1]:-0}` on the
line *after* a command substitution, where `PIPESTATUS` describes the assignment. Measured
on bash 5.3.9 it is `(0)` with length 1, so the read was unconditionally `0`, the
`jq_rc == 3` arm was dead code, and empty stdin, a rejected document and *our own program
failing to compile* were one reason. The file's own comment claimed the discriminator was
made.

The diagnosis was right and the fix was ~140 lines. A ten-agent review then found 27
findings, 8 of them merge-blocking — and **every blocking one was in the fix or its
verification, not in the diagnosis.**

This file records the three that are not already covered elsewhere. The general
"a guard that cannot fail is indistinguishable from one that passed" theme is
[[2026-09-08-every-guard-i-added-to-the-gate-could-not-fail]]; the mechanisms below are
different.

## 1. Two anti-vacuity gates, one blind spot, blind for different reasons

The contract suite has 95 assertions, ~90 of them routed through one helper:

```bash
want(){ if [[ "$2" == "$3" ]]; then ok "$1 → $3"; else bad "$1" "want: $2" "got:  $3"; fi; }
```

Drop the comparison — `want(){ ok "$1 → $3"; }` — and the suite prints
`=== hook-input-contract: 95/95 pass, 0 skipped ===` and exits 0. Byte-identical to a
healthy run. Six of the mutation battery's ten rows silently survive, and they are the six
that pin the change's thesis.

Two gates existed. Neither could see it, and the reasons do not overlap:

- **`MIN_ASSERTIONS` counts `TOTAL`, which `ok()` and `bad()` increment.** So the floor is
  dispatched *through* the helpers it backstops. A `want()` that always takes the pass
  branch keeps `TOTAL` at 95 and the floor never looks. This is the documented
  "a floor that shares a lifetime with what it guards" trap — but the sharp form is that
  the floor and the liar share a *call path*, not merely a lifetime.
- **The battery's "harness axis" row neutered `bad()`'s counter.** That is the one edit
  which leaves `ok()` *and* `TOTAL` intact, so it is precisely the mutation that cannot
  reach `want()`. I chose it because it looked like the harness's weakest point. It is the
  only harness edit the floor already covers.

Measured slack made it worse: the floor sat at **60** against a 95-assertion suite, so all
24 assertions the change added could be undispatched (`71/71 pass`, exit 0) without
tripping it. Slack under a floor is attack budget, not padding.

**The fix that works** is a helper self-test run before any case, reporting with `printf`
and `exit` and never through the helpers it guards — driving `want()` once with a matching
pair and once with a mismatching pair, and asserting *both* counters moved:

```bash
want "__selftest_match__"    X X >"$sink" 2>&1;  p1=$PASS f1=$FAIL
want "__selftest_mismatch__" X Y >>"$sink" 2>&1; p2=$PASS f2=$FAIL
PASS=$p0; FAIL=$f0; TOTAL=$t0        # unwind; the self-test is not an assertion
(( f2 == f1 + 1 )) || { printf 'FATAL: want() DID NOT FAIL...\n' >&2; exit 2; }
(( p2 == p1 ))     || { printf 'FATAL: want() recorded a PASS for a MISMATCH...\n' >&2; exit 2; }
```

Both arms are load-bearing. The second was missing until `shellcheck` flagged `p2` as
captured-and-unused — and a `want()` that calls **both** `ok` and `bad` satisfies the first
arm alone. That SC2034 was worth more than several agents.

## 2. Enumerate THEIR fault; default the residue to OURS

`baddoc` means "the model sent junk". The first revision enumerated *our* faults — jq
rc 3, the program failing to compile — and let everything else fall through to `baddoc`.
Measured with jq stubs:

| jq exits | means | reported as |
|---|---|---|
| 5 | invalid document | `baddoc` ✓ |
| 3 | our program will not compile | `internal:rc3` ✓ |
| 2 | usage / system error, e.g. a write failure | **`baddoc`** ✗ |
| 126 | exec failure | **`baddoc`** ✗ |
| 137 | killed by the OOM killer | **`baddoc`** ✗ |

That is #7275's own collapse, relocated one code over, inside its fix — on a surface whose
whole thesis is that a broken gate must never hide behind a plausible payload class.

**The general shape.** On any fail-safe surface, a fix that enumerates the faults it
*recognises* and defaults the remainder to the other party is backwards. Name the one
condition that means *their* fault; default everything else to ours. Over-paging an
engineer is recoverable; a broken gate hiding behind a plausible payload class is the
failure mode under repair.

Three agents converged on this independently, which is the tell that it is structural
rather than a slip.

## 3. Count mutation AXES, not rows — two of mine were the same mutant

The battery declared eight axes over twelve rows. Two rows, `M7` (delete the rc append)
and `M10` (degenerate the record separator to `""`), were measured **identical**: both
made `hook_parse_input` return 1 for every input, and both reddened the same 22
assertions. `M10`'s comment claimed it measured whether the guard silently *widens* —
in fact `${raw##*""}` emptied the rc, tripped a guard *before* the split, and returned
without reaching the boundary at all.

So the declared "does the guard widen" axis had **zero rows**, and the battery banked a
row for it anyway.

Two mechanical companions, both now in the file:

- **`expect_red` must assert *which* assertion reddened.** Routing on `rc != 0` alone
  credits a kill to any mutant that merely crashes the suite, and to blast-radius mutants
  that break the parser for every input. Three of my rows reddened 18–22 assertions; a row
  whose mutant breaks everything cannot distinguish "this property is pinned" from "the
  SUT is alive".
- **`patch()` must assert the anchor occurs exactly once.** Presence is not enough:
  first-match replacement in this repo routinely lands on the *comment* documenting the
  anchor three lines above the code, which changes bytes (so a file-level "did it land"
  check passes), leaves the suite green, and reports SURVIVED.

## 4. The battery mutated the live guard library, and registering it made that worse

`restore()` wrote to `.claude/hooks/lib/hook-input.sh` in the working tree — the file 22
hooks source and 19 fire per Bash tool call. ~11 s per contract run × 13 rows is a
**~140-second window per invocation** with the parser deliberately broken, including the
row that removes the object-root check. `trap … EXIT INT TERM HUP` does not cover SIGKILL,
and `scripts/test-all.sh` ships a `[KILLED]` taxonomy because suites here do get
signal-killed.

The part worth recording: **naming it into `SUITE_GLOBS` — done deliberately, for gating
hygiene, and defensible on its own terms — converted an opt-in hazard into an every-run
one.** The two ungated sibling batteries (#7942) only ever ran when someone chose to. A
change that improves a file's *gating* can worsen its *blast radius*, and the two were
never weighed against each other.

The contract suite resolves its library through `BASH_SOURCE`, so a sandbox built from
`git ls-files` runs correctly and the tracked tree is never written.

## Session Errors

**`/tmp` scratchpad is swept between turns.** Probe scripts and a full suite log vanished
mid-session; one backgrounded run's verdict was lost entirely and its empty output nearly
read as a clean result. **Prevention:** long-lived logs go to `/var/tmp` or the worktree —
already documented in `work/SKILL.md`, and I still used `/tmp` because the scratchpad path
is handed to me at session start.

**A backgrounded loop's stdout never reached the output file**, and the completion
notification reported exit 0 — the trailing `echo`'s status, not the loop's.
**Prevention:** write the verdict to a file the next call reads; never infer from a
notification. Documented; hit anyway.

**`local id="$1" desc="$2" log="$WORK/$id.log"`** — referencing a name the same `local` is
still declaring is an unbound-variable abort under `set -u`, not a left-to-right read.
**Prevention:** split the declaration; comment added at the site.

**Literal `0x1E` bytes written into a source file.** Invisible in diffs and editors, and
they tripped tool-input validation. **Prevention:** write control characters as `\u001e`
escapes and let jq expand them; assertion added that the jq program contains no raw
separator. Recorded with some embarrassment: the first draft of THIS paragraph contained
a literal `0x1E`, caught by a byte-count check on the finished file. A document about not
writing invisible bytes is exactly where one hides.

**MD018 three times** — a line opening `#7942` / `#7275` parses as an ATX heading. Twice
in prose edits, and once in the opening sentence of THIS file, four lines above the section
documenting it. Already hook-enforced (markdownlint at pre-commit), so each occurrence cost
a cycle rather than shipping — but three in one session makes it a class, not a slip, and
the enforcement catches it after the fact rather than preventing it.
**Prevention:** never begin a markdown line with `#<digits>`; write `Issue #N` or `PR #N`.
This repo cites issue numbers constantly, so any paragraph opening with a citation is the
trap. Not routed to a rule: the budget linter is at `[WARN]`, and the placement gate says
an already-enforced insight belongs with its enforcer, not in the always-loaded corpus.

**`readonly _HOOK_INPUT_RS` broke double-sourcing under `set -e`** and I shipped it
briefly. This library has no include guard, so a second `source` aborts with
"readonly variable" before any guard runs. **Prevention:** measured and reverted; the
hardening that costs nothing is the `${VAR-}` read spelling, not `readonly`.

**`out=$(want …)` ran the helper in a subshell**, so its counter increments never reached
the caller and the self-test read `p1 == p0` for a perfectly healthy helper — hit while
writing the anti-vacuity guard itself. **Prevention:** redirect to a file; comment added.

**My own instrument nearly killed a correct P1.** Reproducing the `want()` finding with a
partial tree copy returned `94/95 rc=1`, which reads as "the agent was wrong". A full
`git archive` copy returned `95/95 rc=0`. The single failure was an unrelated assertion
scanning a set of roots I had not copied. **Prevention:** verify the instrument before
reading its verdict — including when the instrument is your own check of someone else's
finding, which is exactly when a false negative is most welcome.

**A non-vacuity control silently did not fire.** `sed '0,/WARNING: /'` replaced the first
occurrence, which was a comment, not the emitter. **Prevention:** assert the *construct*
changed (`s.count(old) == 1`), never that the file changed.

**A report-only review agent detached HEAD**, orphaning a commit I had made. Found via
reflog only because a fix was missing from a file; nothing was lost, since the branch ref
still held it. **Prevention:** the prompt said "Review `git show <sha>`", which reads as an
instruction to check that commit out — say "do not change what is checked out", and re-run
`git branch --show-current` after a panel returns.

**A category slide in a scope-out filing.** I claimed `contested-design` by importing an
agent disagreement about a *different* surface (the output enum's taxonomy) to satisfy a
criterion about the *predicate's input domain*. The CONCUR gate rejected it correctly.
**Prevention:** quote the criterion's conjuncts and check each against evidence from the
same surface.

**Claimed "24 hooks" without measuring** — the figure came from the plan and went into a
commit message. Measured: 22 source the library. Correcting the commit message did not
correct the claim: at ship time a grep for the SUBJECT (`[0-9]+ (non-test )?hooks` across
the whole changed set, not for the remembered wording) still found the stale 24 in two
artifacts — the plan's own Risks table and `decision-challenges.md` — one of them the file
the figure was originally read out of. **Prevention:** the repo already says plan-quoted
numbers are preconditions; this one was prose, and prose got no such treatment. And a
measurement correction is not done when the site you noticed is fixed — sweep the subject
across the diff's whole file set, because the number's own source document is the site most
likely to still be asserting it.

**A mutation helper built Python source by `sed` substitution** — fragile against any
metacharacter in an anchor. Rewritten to pass anchors as argv before it broke.
**Prevention:** never interpolate into program text you are about to execute; argv is free.

### Added at ship time — three more, one of them the whole shape again

**A refused full gate is not a licence to substitute a changed-file predicate.** `TEST_GROUP=all`
refused (`rc=4`, no marker, `reason=sibling_runs,low_tmp` — a sibling worktree was mid-run), and
its own message says "Run the suite covering your files instead." I did, 52/52 green, and CI then
went red on `fixture-relative-assert.test.sh`: a repo-wide RATCHET that any new shell file joins.
No changed-file predicate reaches it — the suite is not in the diff and never will be, because the
diff is what perturbs it. **Prevention:** when the gate is refused, run the suites covering the
changed files AND every suite that ratchets a repo-wide corpus (a committed baseline, a site
count, a component tally). The second set is enumerable once: `grep -rl 'baseline' plugins/soleur/
test/*.test.sh`. Substituting only the first is how a "green" stands in for a gate that never ran.

**Its failure message named the wrong remedy first, and the suite's own header named the right
one.** `regenerate with --write-baseline in the same commit as the fix` would have accepted 9 real
findings — two `mktemp -d` roots whose `rm -rf` traps resolve relatively under a relative `TMPDIR`.
The header three screens up says *"Dogfooding the rule rather than baselining its author."*
**Prevention:** a ratchet's remedy line is written for the case where the corpus legitimately grew.
Read what the new rows ARE before regenerating; the baseline is the last resort, not the first.

**Two instruments reported on themselves and I nearly believed both.** A non-vacuity control for a
new fixture guard exited 127 and read as "the guard never fired" — the suite resolves its subject
from `BASH_SOURCE`, so a copy outside `scripts/` cannot run at all. And a markdownlint baseline
comparison linted `origin/main`'s copies from a temp directory where `.markdownlint.json` does not
resolve, returning a uniform `main=0` that made every unchanged file look like a fresh regression.
**Prevention:** this is the same failure as §5 in the body above, twice more. Before reading an
instrument's verdict, drive it once against a case whose answer you already know.

**One-offs, recorded without action:** calling `hook_parse_input` bare under `set -e` in a
probe (abort read as a code bug); a battery `EXPECTED_ROWS` miscount caught by its own
reconciliation; running a lint whole-file and reading pre-existing findings as new; and
the same MD018 heading trap during the planning phase, forwarded via `session-state.md`
and fixed there — the repeat in this phase is why its Prevention line is stated above
rather than treated as closed. A
`hr-never-git-stash-in-worktrees` deny appears in the incident log for this window; I did
not invoke `git stash` and cannot attribute it, so it is recorded rather than claimed.

## Key Insight

An anti-vacuity gate must not share a call path with the thing it guards. Both of mine
did — one because it counted a variable the helpers increment, the other because I chose
the harness mutation that leaves those helpers intact. The remedy is not a better floor;
it is a self-test that drives the helpers and reports through neither.

And on a fail-safe surface, enumerate the condition that means *their* fault and default
everything else to *ours*. The inverse is how a fix reproduces the collapse it was written
to close.
