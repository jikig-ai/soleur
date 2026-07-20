---
title: A guard that never ran has MORE THAN ONE reason — and indexOf block-scoping swallows sibling blocks into a vacuous GREEN
date: 2026-07-15
category: best-practices
module: scripts/followthroughs, scripts/sweep-followthroughs.sh, apps/web-platform/test, plugins/soleur/skills/{plan,review,work}
issue: 6435
pr: 6452
problem_type: best_practice
component: observability
symptoms:
  - "soak gate counted 2 of the 4 signals its companion alarm watches — an intermittently-degraded fleet PASSes"
  - "probe committed mode 100644; 'chmod +x' fixed a LATENT defect while the probe stayed unreachable"
  - "regression test extracts 4 signals while the script sums 2 — green all the way"
  - "set -u does not abort on an unset associative array; the loop iterates zero times and exits 0"
  - "MIN_SAMPLE=0 makes the sample arm pass vacuously and print 'Safe to retire GHCR'"
tags:
  - fail-open
  - drift-guard
  - vacuous-green
  - followthrough
  - bash
---

# A guard that never ran has MORE THAN ONE reason

## Problem

`scripts/followthroughs/zot-soak-6122.sh` gates the **irreversible** retirement of GHCR
(ADR-096 5.3–5.5 rotates *and revokes* the PAT — after it, a fleet still needing GHCR can pull
from neither registry, with no rollback). #6435 filed that it queried only 2 of the 4 signals its
companion Sentry alarm watches, so an intermittently-degraded fleet could PASS the soak.

That was true. It was also the smallest of the problems.

## Key insights

### 1. When you find a thing that never ran, enumerate EVERY reason before claiming you fixed it

The probe was mode `100644` — the only non-`100755` file in the probe set. That is a real defect,
it is trivially provable, and it is **not why the probe never ran**. `sweep-followthroughs.sh`
enumerates `gh issue list --label follow-through --state open` and reads a `soleur:followthrough`
directive from each body. #6122 carries **neither the label nor a directive**, and no issue in the
repo references the script — so `run_one` is never called and the `[[ ! -x ]]` guard is never
reached. The exec bit was a **latent second** defect that would have bitten *at enrollment*.

The first cause you find is the one that is easiest to see, not the one that is operative. The
mode bit is visible in `git ls-files -s`; the missing directive is visible only if you ask "what
actually invokes this?" Fixing the visible one and writing "now it runs" into a header, a test,
and an ADR ships a **false claim about a mechanism that has never executed**, where it will be
cited as precedent.

**Litmus:** before writing "this never ran because X", check whether the code path containing X is
itself reached. Trace from the *invoker* down, not from the artifact up.

**Corollary — don't force-enroll to make the story true.** The reviewer's prescription was "add the
label + directive in this PR". Its own next finding explained why that is wrong: the cutover has not
happened (`registry:"zot"` = 0 events/30d) and `START` is an unpinned placeholder, so enrolling
makes the daily sweeper post a TRANSIENT forever. **A gate that cannot converge gets bypassed** —
that trades silent inertness for loud non-convergence. The right move was to make the omission
*legible*: ADR-096 now names enrollment as a precondition 5.3 must not proceed without.

### 2. `indexOf`-based block scoping does not merely risk `-1` — it silently lands on the NEXT delimiter

The parity test extracted the soak's FAIL set by scoping to the array block:

```js
const start = soak.indexOf("declare -A FAIL_QUERIES=(");
const block = soak.slice(start, soak.indexOf("\n)", start));   // ← the bug
```

The obvious hazard is `-1` (anchor gone) → `slice(start, -1)` widens to nearly the whole file. We
guarded that. **The guard was insufficient, because it treats the symptom.** If `FAIL_QUERIES`'
closing paren is merely *indented*, `indexOf("\n)")` does not return `-1` — it **skips past it and
finds the next column-0 paren, i.e. a SIBLING array's**. The block swallows both arrays:

```bash
declare -A FAIL_QUERIES=(
  [rolling]='...registry:"ghcr-fallback"'
  [gate]='...registry:"zot-gate-degraded"'
  )                        # ← indented; indexOf("\n)") skips it
declare -A WARN_QUERIES=(  # ← ...and lands on THIS array's paren
  [freshboot]='stage:"inngest_ghcr_fallback"'
  [appboot]='stage:"app_ghcr_fallback"'
)
```

Verified: the extractor reports **4**, the script's loop sums **2**, the suite is **GREEN**. That is
#6435 verbatim — reintroduced *through the regression test written to prevent it*.

**Fix the class, not the symptom:** match the delimiter at any indentation.

```js
const rest = soak.slice(start);
const end = rest.search(/\n[ \t]*\)/);
if (end === -1) throw new Error("FAIL_QUERIES array block is not closed");
const block = rest.slice(0, end);
```

The alarm-side `filters_v2` slice had the identical latent widen onto `actions_v2`'s bracket,
harmless *only by luck* (it holds no `tagged_event` today). A hand-rolled `indexOf` over a
whitespace-sensitive literal is coupled to the formatter's current output; `shfmt`/`terraform fmt`
are one PR away.

**Generalization:** an `indexOf`/`slice` block extractor has two failure modes, and the loud one
(`-1`) is the one everybody guards. The silent one — *anchor found in the wrong place* — produces
over-collection, which reads as coverage.

### 3. A comment claiming the scoping's safety made the fragile scoping look adequate

The extractor's rationale comment asserted two things, **both false**:

- *"the script header names all four signals in prose, so any whole-file assertion would stay GREEN
  with every query deleted"* — false. The regex is shape-specific (`[key]='...'`); against
  whole-file scope it yields **0 matches → RED**. The *regex shape* excludes prose, not the scoping.
- *"a comment cannot live inside the array"* — false. Bash accepts comments inside an array
  assignment.

This is not pedantry. **Crediting a mechanism for safety it does not provide is what makes a fragile
implementation look adequate.** The scoping's real and load-bearing job is excluding *sibling
arrays* — precisely where it failed.

### 4. `set -u` does not rescue an unset associative array

The design claim was that declaring, guarding, and summing in one loop makes "declared but never
counted" **structurally unrepresentable**. It holds in *source*. At *runtime* (verified, bash 5.3.9):

```bash
set -uo pipefail; declare -A Q; unset Q
for k in $(printf '%s\n' "${!Q[@]}" | sort); do :; done   # iters=0, rc=0 — NO abort
```

Zero iterations → `FALLBACKS=0` → PASS. With no `set -e`, a failed `declare` doesn't abort either.
So the only thing between "the array is gone" and `exit 0` was a CI test that parses **source text**
— but **CI parses while the sweeper executes**. A source-level invariant needs a runtime floor:

```bash
(( ${#FAIL_QUERIES[@]} == 4 )) || { echo "TRANSIENT: partial FAIL set" >&2; exit 2; }
```

### 5. `[[ -lt ]]` is arithmetic evaluation — an unvalidated bound silently disables the arm

`MIN_SAMPLE=0`, `""`, and `"abc"` all make `[[ "$ZOT_WEB" -lt "$MIN_SAMPLE" ]]` false, so the sample
arm passes vacuously and prints *"Safe to retire GHCR"* with **zero evidence** — silently disabling
the only detector for the Sentry-dark mode, the exact arm whose own comment argues it must never be
weakened. `a[$(cmd)]` also executes `cmd` (token in-process). Validate any numeric bound before an
arithmetic context: `[[ "$MIN_SAMPLE" =~ ^[1-9][0-9]*$ ]]`.

### 6. The third consecutive instance of the comment-fix class — including inside the PR guarding it

[[2026-07-15-comment-fix-pr-wrote-a-new-false-comment-and-vacuous-ac-classes]] (#6424) and
[[2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name]] (#6421) recorded this class two and
one PRs ago. **This PR hit it five more times, while explicitly citing both learnings as required
reading:**

| False claim | Reality |
|---|---|
| both bare-stage signals emit via `soleur-boot-emit` | `app_ghcr_fallback` is `_emit`; two emitters, two schemas |
| "1 of 26 probes" | 27 |
| "THREE distinct emitters, two schemas" | its own table listed four emit functions |
| "no issue in the repo references this script" | #6435 and #6462 both do — *this PR made it false* |
| "FAIL set is 4-of-5" | 4-of-6; falsified by the bullet **four lines below it** |

Two free self-checks, both of which this PR failed:
- **Reconcile every N against the carve-out in its own comment block.** "4-of-5" sat directly above
  a bullet describing the *second* uncovered mode.
- **Re-derive counts from the files, never from an upstream framing.** "2 of 4 signals" (the issue
  title) became the plan's pin set; "26 probes" came from the issue body.

**Reading the learning is not the same as applying it.** Three PRs, all authored with the prior
learnings in context, all shipped the class. That is evidence the prose control does not work and
the enforcement has to be mechanical (a review agent prompted to re-derive every count, which is
what actually caught these).

### 7. The PR that preaches a discipline is the one that violates it

The soak header says *"anchored on EMIT NAMES, not line numbers — line citations rot."* The same PR's
+128 lines **rotted a live tripwire**: `ci-deploy.sh`'s 5.3 guidance cited `zot-soak-6122.sh:57`/`:58`
and named the legs `FB_ROLLING`/`FB_FRESHBOOT` — which this PR deleted. `:57` is now an unrelated
comment, and there are four legs, not two. The 5.3 author would have read it.

**When you delete or rename a symbol, grep for citations TO it** — not just citations *in* the file
you changed: `git grep -n 'FB_ROLLING\|zot-soak-6122.sh:[0-9]'`. Complements
[[2026-06-18-doc-insertion-stales-cross-artifact-line-citations]] (which covers insertions shifting
line numbers) with the rename/delete direction, and extends it from prose to **live code comments**.

## Session Errors

- **Skipped writing `session-state.md`.** one-shot mandates it after the plan subagent returns; the
  subagent's five reported errors were never persisted, so a compaction would have lost them.
  **Prevention:** the parse-and-write step is not optional — it is the only artifact carrying
  pre-compaction errors into compound.
- **A mutation test that prints nothing proves nothing.** My first mutation battery's `grep` was
  defeated by vitest's ANSI codes and printed **zero output for all four mutations**; I nearly read
  the silence as success. **Prevention:** strip ANSI (`sed -r 's/\x1b\[[0-9;]*m//g'`) and assert on
  the runner's own summary line + explicit `EXIT=$rc`.
- **Background bash reported exit 0 that was the trailing `echo`'s.** Caught it, but only because the
  rule is documented. **Prevention:** always grep the redirected log for the runner's summary.
- **Plan-quoted guidance lost to the convention it cites.** The plan said "use the sibling's token
  loop"; the sibling loops because it guards *two* vars, and `followthrough-convention.md` prescribes
  the `if` form verbatim. shellcheck SC2043 caught it. **Prevention:** when a plan says "mirror
  precedent X", read the *convention* X implements — the precedent may carry incidental shape.
- **Reflexive `git stash list` tripped the guardrails hook.** One-off. **Prevention:** the hook worked.
- **CWD persisted across Bash calls** (this harness *does* persist it), breaking a relative `sed`.
  **Prevention:** always `cd <abs> && cmd` in one call — correct under both semantics.
- **Push rejected non-fast-forward** after rebasing a branch the plan subagent had already pushed.
  **Prevention:** `--force-with-lease` is correct on your own feature branch post-rebase.
- **5 of 6 review agents died on an API session limit mid-run**, several *mid-mutation*.
  **Prevention:** check `git status --short` for contamination before trusting any post-crash state;
  the worktree was clean here, but the documented trap is real — and one agent confirmed a prior run
  had left a mutation that confused a sibling.
- **Concurrent mutating agents share one worktree.** **Prevention:** instruct agents to mutate only
  in a strict mutate→run→restore cycle, restore from a backup taken *after* your own uncommitted
  edits (never `git checkout --`, which wipes them), and verify `git status --short` is empty.

## Discovered, filed

- **#6462** — the soak has no denominator; the *dominant* fresh-boot GHCR path emits nothing at all.
  Adding numerator terms (all this PR did) cannot close a denominator gap. Blocks 5.3–5.5.
- **#6464** — four `scripts/*.test.sh` suites are registered nowhere (`test-all.sh` uses an explicit
  list, not a glob); **one has been RED on `main` undetected**. Same class as #6435, one layer up.
- **#6470** — `sweep-followthroughs.sh` has **7 skip paths that emit only to stderr** (`fail()` is
  `printf >&2` and nothing else), and nothing detects an orphaned probe. 36 trackers exposed.
