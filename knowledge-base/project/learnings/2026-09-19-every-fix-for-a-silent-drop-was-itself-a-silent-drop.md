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
