---
name: a-gate-that-proves-it-cannot-fail-open-shipped-its-own-proof-unwired
description: Building the "no public table without RLS" gate (#3366) reproduced the fail-open class it targets five times in its own code, and shipped its flagship harness registered in zero runners
category: best-practices
module: ci-gates
tags: [fail-open, drift-guard, test-wiring, supabase, rls, mutation-testing, review]
issues: [3366, 6506]
pr: 6520
date: 2026-07-16
---

# A gate that proves it cannot fail open shipped its own proof unwired

## Problem

#3366 ("nightly Supabase advisor lint scan") sat open 71 days. Its re-evaluation
trigger fired three times (2026-05-03, 2026-06-22, 2026-07-12); each firing
produced a comment and a hand-fix and nothing durable. The operator decided
(#6506) to build it, on the estimate that it was **~5 lines** — the existing
`apply-inngest-rls.yml` already queried the advisor endpoint and parsed
`rls_disabled_in_public` with jq, so asserting `== 0` looked trivial.

## The estimate was wrong for an instructive reason

The existing parse is **fail-open**. Verified live against the real Management
API: an expired PAT returns HTTP 401 with `{"message":"JWT could not be decoded"}`,
and the idiom

```jq
[.lints[]? | select(.name=="rls_disabled_in_public")] | length
```

scores that body as **`0`** — byte-identical to a clean scan, and jq exits 0 so
no `|| err` fallback fires. A literal 5-line `== 0` assertion on that parse would
be **permanently green on a dead token** while closing #3366 and retiring the
human vigilance currently substituting for it. Strictly worse than no gate.

That `?` is *correct* where it lives — there it is corroboration that must never
break an apply. It is fatal in an assertion. **Same token, opposite correctness,
depending on whether the caller asserts.** Never copy it mechanically.

## The actual lesson: the defect class is recursive

Knowing the bug cold did not stop me from rebuilding it. Multi-agent review found
the fail-open class reproduced **five times in the gate's own code**:

1. **The metadata rung.** jq piped into `while read` with stderr dropped. When jq
   errored (a `.metadata.name` that is not a scalar), the loop body never ran,
   `indeterminate` stayed empty, and the script announced *"every named table is
   now RLS-enabled"* and exited 0 — having verified nothing while the advisor
   reported a finding. **An empty result read as "nothing to report" instead of
   "nothing measured"** — the header's own rule ("a zero is only ever reported
   after we have established there was something to count") violated one tier up.

2. **The verdict branched on the SANITIZED value.** `if [[ -n "$fail_mode_safe" ]]`
   meant any degradation of `sanitize()` — an unsourced lib, a tr/sed error —
   turned *every* failure into `scan_result=clean` exit 0. A whole-gate fail-open
   reachable without touching a single assertion. **Sanitization is for output;
   it must never sit on the control-flow path.**

3. **The guard's "sources lib" check matched the `# shellcheck source=` COMMENT**,
   not the real `.` line — so deleting both real source lines kept it green,
   which chained directly into (2).

4. **The catalog was documented "AUTHORITATIVE, UNCONDITIONAL" but gated on `ok`**,
   which is false whenever the *advisor* failed. An advisor contract drift would
   silently retire the coverage-bearing tier behind a p2 infra ticket while a live
   violation went unpaged. ADR-112 inverted through the back door.

5. **`violation_confirmed` named no table.** The issue body instructed the operator
   to "identify the table from the per-project status above" where no such data
   existed — and in the stale-advisor case the advisor reports 0, so nothing named
   it either. Enormous care went into the gate not silently *passing*, none into
   what the operator does when it loudly *fails*.

## And the flagship guard was wired to nothing

`tests/scripts/test-supabase-advisor-scan.sh` — the 24-check harness carrying the
PR's entire value claim — was registered in **zero** runners. Nothing
auto-discovers `tests/scripts/`; `scripts/test-all.sh` hand-registers each suite,
and its own comment **six lines above where the registration belonged** documents
this exact trap:

> `# Registered HERE because nothing auto-discovers tests/scripts/ … Without this line the gate that stands between a -replace and a stranded fleet ships with zero coverage.`

So a PR whose thesis is *"an unwired guard is worse than no guard"* shipped its
best guard unwired — and mutation testing proved the consequence: deleting the
401 rung, or the **entire catalog assertion**, shipped GREEN.

## Solution

Every fix is pinned by a mutation that goes RED, not by a comment:

| Mutation | Before | After |
|---|---|---|
| Restore `?` + delete HTTP rung + delete structural rung (full predecessor) | 🔴 RED | 🔴 RED |
| Delete both real lib `.` source lines | 🟢 green | 🔴 RED |
| Delete the advisor HTTP-status rung | 🟢 green | 🔴 RED |
| Gate catalog on `ok` (ADR-112 inversion) | 🟢 green | 🔴 RED |

Plus: harness wired into `test-all.sh` (178/178 suites, was 177); the guard now
asserts **both** gates' wiring; the HTTP check is scoped to the advisor block via
`awk` (a whole-file grep matched any of 4 sites); a proven violation overrides
first-wins so class A outranks class B.

## Key Insights

- **Knowing a defect class does not inoculate you against rebuilding it.** I wrote
  a 260-line file whose header explains the fail-open in detail, and then shipped
  five of them. The only thing that caught them was an adversarial reader with a
  mutation harness.
- **An empty result is not a clean result.** Every place a loop, a parse, or a
  filter can produce *nothing*, ask: does "nothing" mean "nothing to report" or
  "nothing measured"? Reconcile the count against what upstream claimed.
- **Never put sanitization on the control-flow path.** Redaction is for output. A
  verdict derived from a scrubbed value fails open the moment scrubbing degrades.
- **A guard whose subject can be deleted while it stays green is not a guard.**
  The only way to know is to mutate the subject out and watch. Prove BOTH halves —
  mutations RED *and* unmutated GREEN.
- **"It will be picked up automatically" is false by default in this repo.** This
  is now the *fourth* documented instance (`-target=` enumeration, Inngest 4-site
  registration, `infra-validation.yml`, and now `test-all.sh`/`tests/scripts/`).
  Every registration surface is a hand-maintained list and every one fails
  silently and green. Grep the enumeration site before assuming discovery.
- **A gate is only as good as the seam it can be tested through.** Extracting the
  scan to a script (rather than inlining in workflow YAML) is what turned the
  central claim from prose into an executable test. Nothing can drive a `run:`
  block with a fixture body.

## Session Errors

- **Commit message backticks were command-substituted and silently ate text.**
  `git commit -m "…matched the \`# shellcheck source=\` COMMENT…"` ran the backtick
  content as a command; the words vanished from the message with only a stray
  `.: filename argument required` on stderr, and the commit still succeeded.
  Recovery: `git commit --amend -F <file>`.
  **Prevention:** any commit message containing a backtick or `$(` MUST be passed
  via `-F <file>` (written with the Write tool), never `-m` with an inline string.

- **`grep -qF '-supabase-advisor-scan'` parsed the pattern as an option.** The
  leading dash produced a usage error (exit 2), which is *not a match*, so the
  guard reported a legitimate-looking FAIL for a correct file.
  **Prevention:** `grep -F -- <pattern>` whenever the pattern can begin with `-`.

- **The stub's `${VAR:-default}` made the empty-body fixture vacuous.** `:-`
  substitutes on *empty*, not just unset, so the deliberately-empty fixture
  silently received a well-formed body and the test passed without testing.
  (The inner `}` also broke the expansion outright.)
  **Prevention:** in a stub modelling an empty/missing response, never use `:-`;
  export every fixture var unconditionally and reference it bare.

- **The shape guard false-FAILed twice on its own comment prose** (`soleur-prd`,
  `.lints[]?`) — the documented "grep-over-body matches own comments" class,
  rediscovered from the inside. **Prevention:** strip comments (`grep -vE '^\s*#'`)
  or anchor on a syntactic construct a comment cannot produce. Already documented;
  the failure was applying it, not knowing it.

- **A file-level `# shellcheck disable=SC2016` did not suppress the finding.**
  Wasted a cycle before adopting the repo's actual convention (keep backticks out
  of single-quoted `printf`; use escaped backticks in double quotes).
  **Prevention:** grep an existing precedent's comment before inventing a fix —
  `apply-inngest-rls.yml` states the convention explicitly.

- **`/ship` Phase 0's trailer-parse gate false-positives on mid-body prose.** It
  scans the WHOLE commit body for `^[A-Z][A-Za-z-]+:[[:space:]]` and asserts each
  match parses as a trailer — but `git interpret-trailers` only ever reads the
  FINAL paragraph, so an ordinary prose line (`Also: …`, `Route-to-definition: …`,
  `Note: …`) can never be a trailer and can never be the demotion the gate exists
  to catch. Both flagged commits here had `Ref #3366` as their final paragraph and
  no trailers at all. Cleared by inspection in ~30s; not filed, because the gate's
  protected invariant genuinely held and a tuning nit is not worth backlog growth.
  **Prevention (if it recurs often enough to matter):** scope the candidate scan to
  the final paragraph (`awk 'BEGIN{RS=""}{last=$0}END{print last}'`) before
  asserting, so the gate's domain matches git's.

- **`shellcheck` without `-x`** reported SC1091 on sourced libs (one-off).
- **`gh run list --json triggeringActor`** — invalid field (one-off; `gh` lists
  valid fields on error).
- **Missed the 5th registration site and the 6th derived surface** —
  `function-registry-count.test.ts` (route count + `NON_INNGEST_MONITORS`) and
  `model.likec4.json` (regenerate via `scripts/regenerate-c4-model.sh`). Both were
  caught by CI-wired guards doing exactly their job — reinforcing the
  "no auto-discovery" insight above rather than costing a bug.

## Tags

category: best-practices
module: ci-gates
