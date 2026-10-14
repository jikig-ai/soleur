---
title: "The PR that fixed narrow guards shipped three narrow guards"
date: 2026-08-11
category: workflow-patterns
tags: [guards, mutation-testing, review, secret-scanning, gitleaks, enumeration]
issue: 5095
pr: 7438
adr: ADR-180
---

# The PR that fixed narrow guards shipped three narrow guards

## Problem

The preflight Check 10 execution-boundary work cost five adversarial review
rounds. Every round found real defects in the previous round's fixes, and ~20
findings reduced to one class:

> A guard's WINDOW, CHOKEPOINT or IDENTIFIER SET is narrower than the property it
> names.

PR #7438 was built to move that correction upstream: a plan-time **Guard
Contract** (property / structural ASSEMBLY / mutation matrix), a deepen-plan
halt, two mechanical lints, a `/work` class-not-instance rule, and a `/review`
structural-enumeration seat.

**Its first revision shipped all three of its own guards with exactly that
defect.** Every one was found by review, none by the author's own green suites
and mutation batteries.

## What each guard got wrong

### 1. `rename-guard.sh` — the property statement itself was false

The claim: *"laundering requires the source to be OUTSIDE the gitleaks
allowlist, so an allowlist→allowlist rename creates no new unscanned surface."*

**False.** `.gitleaks.toml` carries ONE global `[allowlist]` **plus EIGHTEEN
per-rule `[[rules.allowlists]]`**, and `parse-gitleaks-allowlists.mjs` flattens
them into a single `Set` with **no rule provenance**. "Allowlisted" is a property
of a *(path, rule)* pair, not a boolean.

Measured with a working control (gitleaks 8.24.2):

| Path | Exemption scope | Result |
|---|---|---|
| `srcdir/control.md` | none | **FLAGGED** (instrument works) |
| `knowledge-base/project/learnings/…` | 2 rules only | **FLAGGED** — genuinely scanned |
| `knowledge-base/plans/x.md` | global | **not flagged** |

So `git mv learnings/X.md plans/x.md` converted scanned content into unscanned
content, and the exemption passed it. The declared ASSEMBLY was "the `ALLOW_RES`
array"; the property quantifies over *(path, rule)* pairs.

Corrected to **scope-subset**: exempt iff every regex the destination matches,
the source already matched.

### 2. `lint-guard-contract.py` — no floor on its own dispatch

`scanned 0 plan file(s)` → **exit 0**. That is the *fourth instance from the very
evidence the PR was built on*, reproduced in the flagship guard, while its AC7
was checked `[x]` and unimplemented. Four more: non-recursive sweep (missing a
plan that exists in-repo today), first-section-only, exact-equality heading
match, and matrix rows counted from *any* table in the entry.

### 3. `lint-window-closure-assertion.py` — identifier set as naming convention

Walked `node_modules` (492 of 1420 "scanned" files), missed 247
`.test.tsx`/`.spec.ts` files outright, missed five declaration forms, lost a
whole file when the expected array was hoisted to a const, and accepted a bare
marker with no justification.

## Key insight

**A Guard Contract makes an assembly writable and reviewable. It does not make it
correct.** Writing "Assembly: the `ALLOW_RES` array" felt like performing the
enumeration; it was naming the thing I had already been looking at. The contract
is a prompt for the enumeration, never a substitute for performing it.

The load-bearing question is not *"what does my guard read?"* but *"what is the
smallest edit that adds a member my guard cannot see?"* — and it must be asked
against the **producer's** full vocabulary (gitleaks' allowlist scoping, git's
rename classification, TypeScript's declaration forms), not against the
implementation's current shape.

## The structural-enumeration seat justified itself empirically

The seat this PR adds to `/review` produced the **complete map in one pass**,
including six evasions no adversarial seat found:

- merge-commit diffs emit no `R` record at all (`git log --name-status`)
- copy-then-delete evades (`A`+`D`, never `R`)
- sub-threshold renames evade — measured **R011** at `--find-renames=5%`,
  invisible at git's ~50% default
- `core.quotePath=true` quotes non-ASCII paths, and the trailing quote defeats
  every `$`-anchored allowlist regex
- a parser returning `[]` at exit 0 disarmed the whole gate
- plans in `plans/<subdir>/` were never swept

Four adversarial agents had each found *fragments* of one structural gap. One
enumeration dominated N samples on both cost and completeness — which is the
seat's whole thesis, demonstrated on the PR that introduces it.

## Harness vacuity that count-based floors cannot see

`test-design-reviewer` ran 18 mutations on axes the author's battery never
edited. **11 survived (61%).** The floors count **DISPATCH**; none of them
measures **DISCRIMINATION**:

- rewriting `fail()` to increment `PASS` kept every `EXPECTED_MIN` satisfied and
  reported a clean run
- swapping any assertion for a bare `pass` at constant count was invisible —
  **including the rename-guard's security assertion**
- `glob(...)[:1]` survived in **both** lints, because every fixture directory
  held exactly one in-scope file: the suites proved all-members at the ENTRY
  level and first-member at the FILE level
- `mb_case` credited a 0-byte mutant, because `python3` on an empty file exits 0

The fix is a positive control on the harness's own accounting plus a two-file
fixture — not a bigger number.

## Mutation seams must WEAKEN when deleted

Several first-attempt seams made the guard **stricter** when deleted (proving
nothing) or **crashed** (a broken mutant, not a weaker one). Both read as
"caught". The rule: a deletion mutation is only valid if the remaining code is a
*working, weaker* program. Where it cannot be, use a **semantic** mutation that
reverts to the prior behaviour — `MB-5` (rename-guard, revert to the old boolean)
and `MB-7` (lint-guard-contract, revert to entry-wide counting) both had to be
converted.

## Session Errors

1. **Outbound SSH to github.com blocked on ports 22 AND 443.** Worktree creation
   hung twice (5-min foreground kill, then background). — Recovery: repo-local
   `url.https://github.com/.insteadOf` + `gh auth git-credential`; fetch went
   from indefinite hang to 1.1s. — **Prevention:** probe SSH reachability before
   diagnosing a hung `git fetch` as anything else; `gh` working over HTTPS while
   `git` hangs is the tell.
2. **Killed my own worktree-create process that had already succeeded.** The
   SIGTERM raced with completion (exit 0 already written). — **Prevention:**
   check for the completion artifact before signalling a slow background job.
3. **A sibling session was creating a thematically-identical worktree.** Surfaced
   to the operator rather than guessed. — **Prevention:** resolve `/proc/<pid>/cwd`
   for sibling detection; a bash script's process name is `bash`.
4. **Plan-time probe reported "5 files, 7 helpers"; the precise population was 3
   files, 7 helpers.** Caught before it propagated into the allowlist. —
   **Prevention:** measure at the granularity you will assert, before the first write.
5. **Asserted in the plan's C4 section that I had read all three `.c4` files when
   I had not.** Self-caught and corrected to state exactly what was checked. —
   **Prevention:** never write a completeness claim you have not just executed.
6. **rename-guard's exemption was unsound** (per-rule vs global allowlist). —
   **Prevention:** when a fix rests on a vendor's semantics, read the vendor's
   config for scoping constructs before asserting the semantics are global.
7. **`lint-guard-contract.py` had no floor on its own dispatch**, plus four more
   fail-opens. — **Prevention:** every gate needs a positive-work floor; AC7 was
   checked `[x]` while unimplemented.
8. **`lint-window-closure-assertion.py` had six fail-opens.**
9. **`TS-8` was tautological** — its needle matched the summary unconditionally,
   including on the zero-file run it existed to make observable.
10. **`mb_case` credited a 0-byte mutant.** — **Prevention:** a landing check
    proves an edit happened, not that the mutant is still the program under test.
11. **Bulk-toggled `tasks.md` checkboxes** `- [ ]` → `- [x]`, the documented
    anti-pattern; two then claimed more than the evidence supported and had to be
    corrected in a follow-up commit.
12. **Mutation seams that strengthened-or-crashed on deletion** (see above).
13. **`MB-7` initially ran the pristine SUT, not the mutant** — `assert_case`
    hardcodes `$SUT`. It reported a "surviving mutation" that was never run. —
    **Prevention:** verify the instrument before reading its verdict.
14. **`TS-7`'s fixture similarity was wrong twice** — first ~0% (no threshold can
    classify that as a rename), then ~77% (git's default already catches it).
    Only a measured `R011` put it in the 5–50% band that proves the flag
    load-bearing.
15. **`AskUserQuestion` called with malformed JSON** once; retried.
16. **ADR ordinal collided TWICE in one session** — `origin/main` said 176 while a
    branch held 177 (took 178); at ship time two further unmerged branches had
    each claimed 178 (took 179). — **Prevention:** this is the evidence behind
    #7446; a `main`-scoped presence check passes while three branches race.
17. **First exploit probe used a low-entropy token and scanned a subdirectory**,
    returning "no leaks found" at both paths — an inconclusive instrument I
    nearly read as a refutation of a live security finding. — **Prevention:**
    every measurement needs a known-positive control; a fixture that cannot
    contain the thing it looks for is not a test.
18. **Duplicated-word typos in `review/` and `deepen-plan/SKILL.md`** — one
    sentence copy-pasted into two files, which is the drift class this PR is
    about, committed by this PR.
19. **Seat-number collision at `14.`** in `review/SKILL.md`.
20. **First full-suite run: 291/293** with two contention failures (port-5000
    bind, vitest under load) — confirmed three ways as not mine; the post-rework
    run was **295/295**.

## Recurring-vs-one-off triage

| Item | Recurring? | Disposition |
|---|---|---|
| 1 SSH blocked | recurring (this machine) | one-off env fix applied; documented here |
| 2, 3 process/sibling races | recurring | already covered by `/proc` guidance in work/SKILL.md |
| 4, 5, 17 unverified measurement | **recurring** | fix-now-inline — captured in this learning + the `/work` rule |
| 6, 7, 8 narrow guards | **recurring** | fix-now-inline — all fixed in this PR |
| 9, 10, 12, 13 harness vacuity | **recurring** | fix-now-inline — positive controls added to all three suites |
| 11 bulk checkbox toggle | **recurring** | already documented; recurred anyway — worth a mechanical gate |
| 14 fixture band | one-off | measured and fixed |
| 15 malformed JSON | one-off | retried |
| 16 ADR ordinal | **recurring** | file-tracked as **#7446** |
| 18, 19 typo/numbering | one-off | fixed |
| 20 contention | recurring (this box) | already banner-reported by `test-all.sh` |

## Two agent claims checked and REJECTED

- *"ADR says merged 2026-08-10 but the commit is 2026-08-11."* The agent read
  **local** time: `00:31:29 +0200` is `2026-08-10 22:31 UTC`. The date stands.
- *"`rename-guard.test.sh` needs a `-live` counterpart."* It hard-requires
  `BASE_SHA`/`HEAD_SHA`; a live line would assert nothing.

A converged panel is not proof, and a finding is a hypothesis with evidence
attached — including when it is confidently wrong about a timezone.

## Prevention

- For any guard, state the property in one sentence and the check's scope in
  another, then ask whether the second covers the first.
- Audit a mutation battery's **axes**, not its count. N mutations of one shape is
  one mutation.
- Give every fixture set **two** members on the axis the guard quantifies over —
  one in-scope file per fixture directory is what let `[:1]` survive twice.
- Every measurement needs a known-positive control before its result is evidence.
- Prefer one structural-enumeration seat to N adversarial seats when the
  deliverable is a guard.
