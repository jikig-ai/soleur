---
title: "Every fix for a silent drop was itself a silent drop"
date: 2026-09-19
category: security-issues
tags: [followthrough, github-api, bash, subshell, log-injection, mutation-testing, vacuity]
issues: [6617, 6488, 7448]
---

# Every fix for a silent drop was itself a silent drop

Four defects in one session. All four DROP data while reporting success, all four were found by
RUNNING something rather than reading it, and three of them were introduced by the fix for the
one before.

## The original: a security fix that was undetectably lossy

`jikig-ai/soleur` is public with issues open, so an operator-confirmed follow-through probe
reading `.comments[].body` unfiltered accepts a `RESULT: PASS` from any authenticated GitHub
user. #7448 closed that by filtering
`authorAssociation in (OWNER, MEMBER, COLLABORATOR)`.

**`authorAssociation` is computed against the READING token's visibility.** Measured on the same
comment, two tokens, one hour apart:

| Token | `authorAssociation` for `deruelle` |
|---|---|
| operator PAT | `MEMBER` |
| sweeper `GITHUB_TOKEN` | `CONTRIBUTOR` |

The operator's `jikig-ai` membership is private (`GET orgs/jikig-ai/public_members/deruelle` →
404). So the probe ran under `GITHUB_TOKEN`, saw `CONTRIBUTOR`, dropped the verdict, and reported
FAIL — every night for two months, against an issue whose `RESULT: PASS` had been recorded on
2026-07-20. Nothing was broken; the filter was doing exactly what it said.

**The class:** a filter whose predicate is evaluated in a DIFFERENT security context than the one
it was authored and tested in. The author sees `MEMBER` and the filter works; the runtime sees
`CONTRIBUTOR` and it does not. No test written from the author's context can see it, because the
author's context is the one where it passes.

The replacement resolves `GET /repos/{owner}/{repo}/collaborators/{login}/permission`, which is
effective permission and does not depend on membership visibility.

## Fix defect 1: the memo lived in a subshell, so the filter rejected everyone

```bash
if ! perm="$(_trusted_verdict_permission "$login" "$repo")"; then return 2; fi
```

`_trusted_verdict_permission` memoizes into a global associative array. Command substitution runs
it in a SUBSHELL, so every memo write was discarded and the later lookup found nothing — every
author resolved as untrusted.

**What made it nearly invisible:** the untrusted-author fixture still PASSED. A filter that
rejects everyone and a filter that works correctly are indistinguishable on the negative case,
and the negative case is the one the security work is about, so it is the one you look at. Only
the three positive rows (trusted author must be HONOURED) failed. **A filter needs fixtures on
both sides or "rejects everything" reads as "working".**

Fix: `_trusted_verdict_permission "$l" "$r" >/dev/null` — a redirect, not a subshell.

## Fix defect 2: 404 as TRANSIENT wedges every thread a bot has touched

`gh api` exits non-zero on any non-2xx, and the first build mapped all of it to TRANSIENT
("a permission read that failed is not a negative answer" — correct, as far as it goes).

`github-actions` comments on nearly every tracker here, and GitHub answers
`{"message":"github-actions is not a user", "status":"404"}` for it. So every such thread returned
TRANSIENT forever. **That is the same permanent-red outcome the lib exists to remove, arrived at
from the opposite direction** — and it would have looked like the old bug, which is how it gets
"fixed" by reverting the wrong thing.

The split: **403/network/5xx = TRANSIENT** (the read failed). **404 = DEFINITIVE** (the login is
not a user of this repo) — reachable only because the issue read already succeeded against the
same repo, so repo visibility is established and the 404 is about the LOGIN. Both directions are
fixtured (rows 4b and 4c), because a discriminator branching on error TEXT needs a fixture on
each side or it silently widens.

Found by running the migrated probe against live #6617 — not by reading the code, which looked
right.

## Fix defect 3: the log sanitizer deleted the evidence's shape

The drop workflow prints a 14-row per-table listing. The plan makes that listing the evidence for
the NAME SET — stronger than any static guard, because the posture assertion is evaluated over
rows selected BY NAME and a table renamed onto one of those names would satisfy it.

The anti-exfil helper, copied verbatim from the workflow being replaced:

```bash
strip_log_injection() { printf '%s' "$1" | LC_ALL=C tr -d '\000-\037' ... }
```

`0x00-0x1F` includes TAB (`0x09`) and LF (`0x0A`). Correct for a one-line message; destructive for
a table. The listing arrived as one unreadable 300-character log line. Every value was present.
None of it was legible — and it is also the record the ADR addendum cites.

The repair keeps `0x09` and `0x0A` and strips everything else **including CR (`0x0D`)** — CR is
what enables log-line overwriting, so that is the part of the original scrub that was actually
load-bearing here. Verified against a fixture (`printf 'a\tb\nc\td\r\x01\x7f\n'` → two aligned
rows, CR/NUL/DEL gone) before pushing, rather than by re-reading the `tr` range.

**The class:** a helper copied verbatim into a context whose DATA SHAPE differs from the one it
was written for. The copy was faithful; the fit was not.

## Fix defect 4: a mutation row that could not be observed

Guard 1's matrix row 3 was "make `assert()` never increment `FAIL` → RED". Run as written, it
reported **PASS**. With the guard otherwise intact NO assertion fails, so a mutation to the
failure path changes nothing observable.

The matrix's own text said so — "a known-bad inline fixture must register a FAIL; if it does not,
the harness is lying" — and the row was run without it anyway, because a row that produces a
verdict looks like a row that worked.

**A mutation row that cannot be observed is VOID, not passing.** Re-run paired with a nonexistent
`PRD_WF`, `PASS + FAIL == 0` against `EXPECTED_TOTAL=17` and the floor reds. Before recording any
row's verdict, ask what in the SUT's output would differ if the mutation had not landed.

## Prevention

- **A predicate that reads identity, permission or visibility is evaluated in the RUNTIME's
  security context, not the author's.** Print what the runtime actually observes, from the
  runtime, and put that reading in the log. The 6617 probe was made to emit
  `observed authorAssociation=<value> for verdict author <login> (token=GITHUB_TOKEN)` as its last
  stderr line specifically so the next reader gets the measurement instead of re-deriving it.
- **Fixture a filter on BOTH sides.** "Rejects everything" passes every negative row.
- **Never call a memoizing function through `$( )`.** Redirect instead. The symptom is not an
  error; it is a cache that never hits.
- **An error-code discriminator needs a fixture per branch**, or it widens into "all errors are
  the reassuring one".
- **A helper copied verbatim carries its original DATA SHAPE assumption.** Ask what the new
  caller's data looks like before reusing a scrubber, parser or formatter.
- **Before recording a mutation row's verdict, name what would differ if the mutation had not
  landed.** If nothing would, the row is void and needs a paired fixture.

## Review round (2026-09-20): the same shape, now in the guards

The review found nine more instances. All but one were in code I had written to CHECK the
work, not in the work — and the one exception was a live hole the PR's own claim denied.

### The claim that was false as shipped

Rule 4 of `lint-followthrough-varq-ban.sh` banned an inline `authorAssociation` select and its
header asserted that this "makes 'the lib is the chokepoint' a fact rather than an assertion."

It banned the presence of the WRONG mechanism. The property the lib establishes is the ABSENCE
of the right one, and those are different claims. Measured: `grep -rn authorAssociation
scripts/followthroughs/` found **zero** live filters to ban, while
`inngest-zot-client-authz-6500.sh` read `.comments[].body` with **no author filter at all** —
the verbatim #7448 forgery shape, strictly worse than what the rule banned, and invisible to
it. The lint ran **rc=0** over it. That probe's `exit 0` closes #6500, the ADR-096 supply-chain
authorization gate, on a public repo with issues open.

**A rule that is green over the exact hole it advertises protection from is worse than the
documentation alone**, because it converts "we wrote this down" into "we gated it".

It was inert rather than exploitable only because `--comments` and `--json` are mutually
exclusive on current `gh` — so the probe had been permanently TRANSIENT, the identical
dead-probe defect #6617 carried, sitting unmigrated in the same directory as the PR fixing that
class. Repairing the flag pair without adding a filter would have armed the forgery.

### Four defects in the fix for it

Each found by mutating the thing I had just written:

1. **`LIB_CALL` matched the filename.** Sourcing the lib and then reverting the read passed at
   rc 0 — both endpoints pinned, the wire between them unpinned. Anchor on the CALL.
2. **The floor's denominator counted direct readers only**, and I derived it from the
   PRE-migration tree — so it fired at 2-of-3 on the very run proving the migration had worked.
   A floor that falls every time the rule succeeds is a floor that punishes compliance.
3. **An edit batch failed its anchor assertion and I read the rows anyway.** The `python3`
   heredoc raised `AssertionError: LIB_CALL anchor missing`, wrote nothing, and the four
   mutation rows below it measured the UNCHANGED rule — all reporting the reassuring answer.
   A failed edit batch looks exactly like a landed one unless you read the artifact back.
4. **The harness stubbed `gh` through an injected `GH_BIN` path.** A security lib must not take
   an injectable binary path, so the seam could not reach it. Moved to a PATH shim, which also
   intercepts the lib's own permission call — and the harness then had no forgery row at all,
   because every fixture was implicitly the operator.

### Three anti-vacuity floors that could not fire

`guard-vacuity-floor.test.sh` — a repo-global ratchet no file-selected suite set can see — went
RED, and the causes came in the wrong order:

- **The slice was not the problem.** The subtrahend was bound ~200 lines above the `if`, which
  is a real defect and I fixed it first. The hand-built mutant had been exiting 1 correctly the
  whole time.
- **The MESSAGE was.** The floor printed `FLOOR: executed N real assertions`, which matches no
  term in the meta-guard's FIRES sentinel vocabulary — so a correctly-firing floor was scored
  CONSTRUCTION (status unknown) and silently left the covered set. **A floor whose message the
  meta-guard cannot recognise is indistinguishable from a floor that crashed.**
- **I fixed the instance, not the class**, so it recurred on a second file. The sweep afterwards
  found 19 of 20 floor messages in the diff already carried the vocabulary; one did not.
- **A fourth floor was written `-ne`**, a shape the meta-guard's population regex does not match
  (it admits `-lt|-le|-ge`), so it was bounded by NOTHING while the three others were enrolled.
  That is the one failure mode the meta-guard's own header says it cannot report on itself.
  `-lt` is also the correct semantics: the count is developer-incremented, so `-ne` makes every
  added assertion a spurious failure and trains exactly the reflex the message asks the reader
  not to form.
- **My first repair re-broke it.** I pinned the threshold against a second declaration, and the
  drift-pin `if` sat between the binding and the floor — putting the file straight back into
  the uncovered set. **"Contiguous" is literal.** Two variables pinned to each other was the
  wrong shape; one literal in one place was the right one.

### Instrument errors, again

- **`PATH=/nonexistent` does not simulate one missing binary** — it removes `cat` too, so the
  fallback under test could not have run either. The empty output proved nothing. Shadow the
  ONE binary with a stub that exits 127.
- **A mutation row whose fixture fails for a second reason proves nothing.** Guard-1 row 3
  ("make `assert()` never increment FAIL") reported PASS on its first run because, with the
  guard otherwise intact, no assertion fails — so the mutation changed nothing observable. Its
  own matrix text had already said it needed a known-bad fixture.

### Prevention

- **A rule that bans a spelling is not a rule that establishes a property.** Write the property
  as one sentence, then ask whether the predicate expresses THAT. Prefer the positive
  obligation: it subsumes the ban and covers the shapes nobody enumerated.
- **A new floor owes three things, not one:** a shape inside the meta-guard's population
  (`-lt`, not `-ne`), a threshold literal ADJACENT to the `if` with nothing between, and a
  MESSAGE carrying the sentinel vocabulary. Two of the three are invisible to the suite's own
  green run.
- **After any scripted edit, read the artifact back.** An `AssertionError` in a heredoc writes
  nothing and the next command reports the baseline, which is the reassuring answer.
- **When a finding names an instance, sweep the class in the same commit.** Measured here: one
  sweep over 20 floor messages found the second instance in seconds, after the first had been
  fixed in isolation and had already recurred.
- **The review summary is a continuation gate, not a turn boundary.** I stopped at it and the
  operator had to ask "why did you stop?". Findings are fixed inline, so a clean review means
  the PR is ready to go out — not ready to be handed over.
