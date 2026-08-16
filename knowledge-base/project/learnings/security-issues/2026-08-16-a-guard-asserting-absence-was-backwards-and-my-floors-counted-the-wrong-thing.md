---
module: ci-supply-chain
date: 2026-08-16
problem_type: security_issue
component: ci_workflow
symptoms:
  - "next.config.ts declared no `images` key and the guard asserted that absence"
  - "/_next/image?url=/api/shared/<token> decoded attacker bytes with sharp@0.34.5"
  - "deleting one line from fail() left both mutation batteries at exit 0"
root_cause: guard_asserted_absence_that_permits_rather_than_restricts
severity: critical
tags: [dependabot, lockfile, guard-design, anti-vacuity, next-image, supply-chain]
synced_to: [review, work]
---

# A guard that asserted ABSENCE was backwards, and my anti-vacuity floors counted the wrong thing

## Problem

PR #7566 (issue #7084) made npm the single lockfile of record: deleted both `bun.lock` files,
converted ~20 install sites to `npm ci --ignore-scripts`, and drained 35 of 39 Dependabot alerts.
Four alerts were deliberately left open — `sharp` (144) and `postcss` (161/162/170) — on the
argument that only the `next`-pinned NESTED copies are vulnerable and no attacker-controlled bytes
can reach them.

I wrote a guard to pin that argument: `next.config.ts` declares **no `images` key**, therefore the
image optimizer cannot be pointed at remote or user-supplied URLs.

Both halves were wrong, and they were wrong in the direction that reads as safety.

## Root cause

### 1. Absence of config does not restrict. It permits.

Next's optimizer checks a LOCAL url against `localPatterns` only — never `remotePatterns`. And
`imageConfigDefault.localPatterns` is `undefined`, for which `hasLocalMatch` returns **true** for
every path. Measured against the installed next@15.5.22:

```js
hasLocalMatch(undefined, "/api/shared/abc123")  // => true
```

So "no `images` key" is not a closed door; it is an open one. The guard asserted the open state and
would therefore have gone **RED on the change that closes the hole** and stayed **GREEN while it was
open** — an inversion, not a gap.

### 2. The reachability argument was falsified by a route I had not enumerated

The deferral note said the same-origin proxy path "does not exist today", scoping the residual to the
workspace-logo feature. A different, live, unauthenticated path already existed:

```
middleware.ts matcher excludes _next/image        -> no auth gate
/_next/image?url=/api/shared/<token>              -> optimizer LOCAL branch
/api/shared is in PUBLIC_PATHS                    -> unauthenticated
kb-binary-response.ts derives content type from the EXTENSION, serves bytes RAW
kb/upload validates the extension only — no decode, no re-encode
-> decoded by next/node_modules/sharp@0.34.5, the copy advisory 144 covers
```

The stated mitigation ("stored objects are re-encoded to WebP by the patched top-level sharp") is
specific to the logo bucket and does not apply on this path at all.

### 3. My anti-vacuity floors were placed on sets that are populated by construction

Three instances in one PR, each of which I wrote *while thinking about anti-vacuity*:

- The mutation batteries floored `asserted`, which `pass()` **and** `fail()` both increment. That
  measures whether assertions RAN, never whether they CONCLUDED. Deleting the single line
  `fails=$((fails + 1))` left both suites printing `5 passed, 0 failed, 16 asserted` and exiting 0.
- The drain assertion floored `checked`, and a row that matched nothing printed `(absent)` and still
  counted. Renaming all 17 packages to nonexistent names exited 0 reporting "17 rows clear".
- Its second floor compared `checked` against `len(REQUIRED)` — a tautology that cannot fire.

## Solution

```ts
// next.config.ts — a security control, not a preference
images: { localPatterns: [{ pathname: "/icons/**" }] },
```

Verified against Next's own matcher: `/icons/soleur-logo-mark.png` (the only `next/image` call site)
ALLOWS; `/api/shared/…`, `/api/workspace/logo/…` and `/icons/../api/shared/…` all DENY.

The guard was replaced with one that **executes Next's matcher** rather than pattern-matching config
text, and carries a must-ALLOW row so a deny-everything config cannot score full marks.

Floors moved to sets that are non-empty only in the passing state:

```bash
# batteries: passes, plus a reconciliation the neutered counter cannot satisfy
if [[ $((passes + fails)) -ne $asserted ]]; then ... exit 1; fi
if [[ $passes -lt $MIN_ASSERTIONS ]]; then ... exit 1; fi
```

```python
# drain: rows that RESOLVED to an installed version, plus a completeness pass
if resolved < MIN_RESOLVED: fail(...)
# every PRESENT major of a watched package must have a row
```

## Key insight

**Ask what a guard's passing state looks like, and whether that state is distinguishable from the
guard being broken or backwards.** Three distinct failures here shared one shape:

- *Absence-asserting guard*: the passing state ("no key") was the vulnerable state.
- *Floor on `asserted`*: the passing state ("N assertions ran") is identical whether they concluded.
- *Floor on `checked`*: the passing state ("N rows evaluated") is identical to N rows matching nothing.

A floor belongs on a set that is **non-empty in the passing state and empty when the mechanism
breaks**. `asserted` and `checked` are populated by construction; `passes` and `resolved` are not.

## Session Errors

1. **`learnings-researcher` reported as failed prematurely** (forwarded) — it had returned after ~106
   min with a materially new finding. **Prevention:** a long-running agent that has not emitted a
   terminal marker is still running; do not report it dead from elapsed time alone.
2. **Unbounded `grep -ci` "no bun in Dockerfile" returned 6 hits, all `bun` inside `bundle`**
   (forwarded). **Prevention:** word-bound every existence probe (`grep -ciowE`) before treating a
   count as a refutation.
3. **Guard 2's first implementation hung** — ~150k lines through a per-line bash function plus
   catastrophic backtracking on a 4209-char workflow line. **Prevention:** for any scan over the
   whole tree, do the extraction in one `awk` pass; bash regex per line does not scale and its
   pathological cases are silent.
4. **`local a="$1" b="$2" c="$SANDBOX_ROOT/$a"` tripped `set -u`.** **Prevention:** never reference
   an earlier name inside the same `local` statement; split the declarations.
5. **Row-3 fixture emptied the git index**, so the guard hit its "ls-files returned nothing" arm
   rather than the floor it meant to exercise. **Prevention:** a fixture must isolate the ONE
   mechanism under test — add a filler tracked file so removing the subject does not also trip an
   earlier guard.
6. **Guard 2 scanned its own mutation fixtures** (heredocs containing `bun install`).
   **Prevention:** any tree-scanning guard must exclude `*.test.sh`, and the exclusion belongs in the
   stated boundary list, not left implicit.
7. **Converted the root `constraint-gates.yml` but not its two byte-parity siblings.**
   **Prevention:** when a file is byte-diffed against siblings, grep for the parity test before
   editing and move all members in one commit.
8. **Retired the sdk-gate's parity tests without replacing their coverage.** **Prevention:** when a
   property is retired, replace the tests with ones for the property that SURVIVES; do not delete.
9. **Push rejected — my rebase rewrote commits `draft-pr` had already pushed.** **Prevention:**
   expect a force-with-lease after rebasing a branch whose init commit was pushed by tooling.
10. **Added a backticked `scripts/…` path to a SKILL.md**, violating the no-backtick-file-reference
    convention. **Prevention:** use markdown links for `references/`, `assets/`, `scripts/` paths in
    skills; `components.test.ts` enforces it.
11. **An apostrophe in my own comment closed a single-quoted awk block.** **Prevention:** never write
    an apostrophe inside `awk '...'`; grep the block for `'` after editing.
12. **`MIN_JOBS_PARSED=80` hardcoded to the live tree false-REDded the battery's own fixtures.**
    **Prevention:** derive a floor from an independent count in the same run (here: one job per
    workflow file), never from a literal calibrated to production.
13. **The njobs sentinel used a LEADING empty field.** Tab is IFS whitespace, so `read` collapsed it
    and the count landed in the wrong variable — "parsed 0 jobs". **Prevention:** put a sentinel in a
    non-empty FIRST field; never rely on an empty leading or middle field surviving `read`.
14. **My first drain checker took `min()` across `js-yaml`'s two major lines**, reporting a
    correctly-patched 3.15.1 as VULNERABLE. **Prevention:** key version thresholds per MAJOR LINE for
    any package shipping more than one supported major.
15. **My drain anti-vacuity floor was a tautology** (`checked` vs `len(REQUIRED)`). **Prevention:**
    see Key Insight — floor a set that is empty when the mechanism breaks.
16. **My S1 mutation test was incomplete** — I mutated `fail()` without also neutering the guard, so
    everything legitimately passed and I read it as a survival. **Prevention:** a mutation is only
    valid if the fixture would otherwise FAIL; state what the case should produce before running it.
17. **My commit message claimed the `case` globs "cover arbitrary depth."** True of the wrong axis:
    `scripts/*.sh` is anchored, so it covered depth BELOW `scripts/` and missed every `scripts/`
    directory elsewhere (~185 tracked scripts). **Prevention:** when claiming a pattern's reach, name
    the axis and test a member on the other one.
18. **I told the operator the propagation gate had "succeeded on four other branches, so it
    cleared."** Those runs SKIPPED the step. **Prevention:** before citing another run as evidence,
    check the step's own conclusion — `skipped` is not `success`.
19. **I tripped the no-backtick-file-reference convention TWICE in one session** — once in
    `preflight/SKILL.md` (caught by the full battery) and again in the routed bullet for
    `work/SKILL.md`, in a sentence whose whole subject was path-pattern anchoring. Writing the
    prevention line did not stop the recurrence 40 minutes later. **Prevention:** the durable fix is
    mechanical, not a remembered rule — run `bun test plugins/soleur/test/components.test.ts` after
    ANY skill-file edit, which is one command and catches it before the full battery does.
20. **All four review agents died on a session limit; CI's gate then failed twice on exhausted
    credit.** **Prevention:** resume dead agents rather than respawning (a resume keeps partial
    findings), and re-prioritise their task lists so an interruption still leaves value.

## Cross-references

- ADR-191 — npm is the single lockfile of record
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
