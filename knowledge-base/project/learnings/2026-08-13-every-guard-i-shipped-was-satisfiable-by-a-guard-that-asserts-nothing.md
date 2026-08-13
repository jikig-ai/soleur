---
date: 2026-08-13
issue: 7493
pr: 7504
category: test-failures
module: infra/github, .github/workflows, scripts
problem_type: security_issue
tags: [guard-contract, mutation-testing, anti-vacuity, positive-controls, terraform, github-actions, supply-chain]
---

# Learning: Every guard I shipped was satisfiable by a guard that asserts nothing

## Problem

PR #7504 shipped four guards protecting `jikig-ai/soleur-marketplace` — the plugin's sole
distribution channel, which decides what code lands on every installed user's machine. The plan
carried a Guard Contract with a per-guard mutation matrix. Every targeted suite was green: Guard 1
18/18, Guard 4 14/14, drift 58/58, destroy guard 8/8, ruleset audit 37/37.

A five-agent review found that **four of those guards were satisfiable by implementations that
assert nothing**, and that the feature did not protect the path it names.

## The generalizable lesson

**A mutation matrix that mutates only the system under test cannot see a vacuous harness.**

Every row in the plan's matrix asked "does the guard redden when the ARTIFACT is wrong?" None
asked "does the suite redden when the GUARD is wrong?" That second question is what the four
findings below have in common, and it is the one a Guard Contract has to ask explicitly, because
a harness that asserts nothing produces exactly the same output as one that works.

### The four measured instances

| Guard | Stub that scored green | Why the matrix could not see it |
|---|---|---|
| Guard 4 (manifest source) | `diff "$1" "$CANONICAL"` → **14/14**, *and* CI green with the #7471 `version` key restored | Every RED fixture was derived from the canonical by a `jq` edit, and the only must-PASS fixture WAS the canonical. A checksum satisfies all of them. `ci.yml` then validated the canonical against itself. |
| Guard 1 harness | `mutate()` fully broken → **16 of 18 rows still passed** | `mutate()` ran inside `$( )`. A failed `jq` yielded an EMPTY path, the verifier failed closed, and the RED row passed on the fail-closed branch — for a reason unrelated to the mutation. **A subshell cannot fail a run.** |
| canonical↔`.tf` | `required_approving_review_count = 0` + a 4th bypass actor → **all five suites green** | Nothing compared the canonical or the asserted rule values against the `.tf` that creates the ruleset. Both sibling rulesets already had this gate (`T-rsc-9`, `T-cla-1b`); this one shipped without it. |
| destroy guard | all 8 invocations deleted → `0 passed, 0 failed`, **exit 0** | Success was `fail == 0`, which an EMPTY suite satisfies. No anti-vacuity floor at all. |

The third row is the sharpest: `required_approving_review_count = 0` is *this feature's own shipped
defect*, the one the file header brags about catching. A widening would have merged green, applied
live to the distribution channel, and only then reddened.

## Solution

### 1. Must-PASS fixtures must DIFFER from the canonical

The fix is not more RED rows. It is accepted-variant rows — inputs the contract explicitly
permits that are not byte-identical to the canonical:

```bash
# Each of these is a spelling the validator's own regex accepts, and none was exercised.
# The ssh form is elided here as $SSH_FORM: `lint-fixture-content.mjs` scans learning files
# for `user@host` and cannot tell an ssh git URL from an email address. The literal lives in
# scripts/marketplace-manifest-validate.test.sh, which is not in that lint's scope.
jq --arg u "$SSH_FORM" '.plugins[0].source.url = $u' "$CANONICAL" > ok-ssh.json
expect_rc "control: accepts the ssh URL spelling" ok-ssh.json 0
# ... plus: no .git suffix, trailing slash, and edits to deliberately UNGOVERNED cosmetic fields
```

The `diff canonical canonical` stub now fails 4 rows. A guard whose only accepted input is the
byte-identical canonical is not a validator, it is a checksum.

### 2. A mutation helper must assert that its mutation LANDED

```bash
expect_mut() { # $1=label $2=jq-filter $3=want-rc
  if ! jq "$2" baseline.json > m.json 2>err.txt; then
    fail "$1" "mutate: jq filter failed: $2"; return          # a subshell could not do this
  fi
  if cmp -s baseline.json m.json; then
    fail "$1" "mutate: filter produced NO change — the row is vacuous: $2"; return
  fi
  expect "$1" m.json "$3"
}
```

Both failure modes matter and they fail differently: a broken filter, and a filter that *selects
nothing* (a renamed key, a changed `actor_type`) and silently returns the baseline unchanged.

### 3. Anti-vacuity floors must be PER-LAYER

The drift harness had `MIN_ASSERTIONS=58` — and three embedded Python blocks that made **three**
`pass()` calls between them while evaluating ~35 predicates. Deleting an entire structural block
left the suite at `58 passed, 0 failed`. A count of `pass()`/`fail()` calls is structurally blind
to predicates written in a different language.

```bash
MIN_PREDICATES=35
predicate_count="$(grep -c 'problems\.append(' "${BASH_SOURCE[0]}")"
```

Stated honestly in the comment: this is a *static* count, so it catches DELETION (the failure mode
that actually happens on a refactor or a bad conflict resolution) and not reachability. Same
guarantee `MIN_ASSERTIONS` gives, applied to the layer `MIN_ASSERTIONS` cannot see.

### 4. Guard the ASSEMBLY, not the artifact

Every guard was specified against its own artifact and each one held. Meanwhile the apply job had
no ref guard:

- Every ruleset on the monorepo targets `~DEFAULT_BRANCH` with an empty exclude → **non-default
  branches carry no protection at all**.
- Push a branch with a rewritten `infra/github/soleur-marketplace-manifest.json`, dispatch
  `apply-github-infra.yml`, and Terraform reads `content` from the CHECKED-OUT tree and publishes
  it through the App's own ruleset bypass.
- The marketplace repo is never touched. No PR, no approval, `marketplace-manifest-guard` never
  runs. **One actor holding only monorepo permissions suffices** — not the two colluding Apps the
  `.tf` advertised.

The threat model assumed writes reach the published file *through* the protected repo. They do not
have to. Fixed with `github.ref == 'refs/heads/main'` **and** a tree-equals-`origin/main`
assertion — the second because `gh run rerun` replays a historical run at its ORIGINAL commit, so
a ref-name test alone does not constrain what gets applied.

Related: a ruleset conditioned on `~DEFAULT_BRANCH` needs the default branch PINNED
(`github_branch_default`). Otherwise an `administration: write` holder pivots it, `refs/heads/main`
goes unprotected while Terraform still writes to `main` and the CDN still serves `main`, and every
ruleset assertion stays green — because `include == ["~DEFAULT_BRANCH"]` is exactly what they check.

## Key Insight

**Positive controls caught two defects that every RED row was blind to, in one review.**

1. jq's `//` fires on `false` as well as `null`. Four new sub-field reads were legitimately
   `false`, so `first // "<absent>"` mismatched on **every** input — including the canonical.
   Invisible to all fourteen RED rows, because a probe that rejects everything satisfies them all.
2. The drift harness's clean fixtures had no `.owner`, so a newly-added assertion failed every
   must-PASS row.

Both were caught only by rows expecting `rc 0`. The asymmetry is structural and worth stating as a
rule: **RED rows cannot detect a guard that rejects everything; only must-PASS rows can.** A suite
that is all-RED is not a strict suite, it is an untested one.

## Prevention

- **Guard Contract gets a harness-mutation axis.** For every guard, ask: what stub implementation
  passes this suite? If `diff input canonical`, `exit 1`, or `exit 0` passes, the suite is
  incomplete. Write that stub and run it — it takes two minutes and it is the only way to know.
- **Every suite needs at least one must-PASS row that is NOT the canonical**, differing in a way
  the contract explicitly permits.
- **Anti-vacuity floors are per-layer**, not per-suite. Count the predicates in each embedded
  language.
- **Never mutate inside a command substitution** in a test harness — a subshell cannot fail a run.
- **A lint's alphabet is part of its threat model** (see Session Errors #1–3).
- **When a guard names a quantifier (`~DEFAULT_BRANCH`, "the default config", "the current
  release"), pin what the quantifier resolves to.** A correct assertion over a redirected
  quantifier is green and meaningless.

## Session Errors

1. **`${mp_checked}` shipped, disabling two guards.** Assigned nowhere in the repo, on the LAST
   line of a step under `set -euo pipefail`. It aborted the step on every apply *after* all
   assertions passed, which skipped the next step (published-manifest verifier, implicit
   `success()`) on every run. Guard 3 had never executed once.
   **Recovery:** removed the interpolation; the script already reports its own count.
   **Prevention:** `scripts/lint-workflow-step-env-refs.py` exists for exactly this class but
   restricts to ALL_CAPS for measured reasons, so it could never have caught a lowercase name.
   Added a file-scoped lint to the drift harness; repo-wide widening tracked in #7524.

2. **Reintroduced the identical shape while fixing it.** The remediation-text branch read
   `$dispatch_eligible`, which is computed in the `check` step's shell — a different process from
   the `issue` step. Under `set -u` that would have aborted the alarm's own filing step.
   **Recovery:** self-caught by reading the step's `env:` before running; wired through
   `DISPATCH_ELIGIBLE` with a `${VAR:-}` default at the use site.
   **Prevention:** the lint above, which now covers this file.

3. **My new lint missed its own motivating case.** First draft matched `[A-Z_][A-Z0-9_]*` only.
   Every shell local in these steps is lowercase, including `dispatch_eligible`.
   **Recovery:** caught by mutation-testing the lint against both shapes — the uppercase mutant
   failed, the lowercase one passed green.
   **Prevention:** mutation-test a new lint against **the exact defect that motivated it**, not a
   synthesized analogue. Three instances of one class in one review is the signal.

4. **`pkill -f 'scripts/test-all.sh'` was pattern-matched repo-wide, not scoped to my PID.**
   Five sibling worktrees were running the same suite; one may have been reaped.
   **Recovery:** none possible after the fact; disclosed to the operator.
   **Prevention:** kill background work by the PID you captured when launching it. On a machine
   with 28 worktrees, `pkill -f` on a shared script name is never scoped to your own process.

5. **A JSON round-trip rewrote 12 lines I never touched.** `json.dumps(..., ensure_ascii=False)`
   on `encryption-posture-ledger.json` re-encoded `—` escapes as literal em-dashes.
   **Recovery:** `git checkout --` the file, redone as a two-line text insert.
   **Prevention:** never round-trip a config file through a serializer to add an entry. The
   blanket-sweep rule already covers `sed` renames; it covers this too — the diff, not the intent,
   is what reviewers and gates see.

6. **`encryption-posture` was red for several commits and I did not notice.** ADR-140's lint fails
   closed on any unclassified Terraform resource type, and this PR introduced two
   (`github_repository_file`, then `github_branch_default`).
   **Recovery:** CI caught it; classified both as non-stores.
   **Prevention:** read `gh pr checks` after a push that adds a new resource TYPE, not only after
   the final push. A new type is a new gate surface.

7. **Misread a background task notification's "exit code 0" as the suite's verdict.** It was the
   `nohup` wrapper's exit, not `test-all.sh`'s.
   **Recovery:** read the `.rc` file written by the wrapper instead.
   **Prevention:** a wrapper's exit code is never the wrapped command's verdict. Write the rc to a
   file and read that. (Second occurrence in this feature.)

8. **jq's `//` fires on `false`.** Five new `pull_request` sub-field reads used
   `first // "<absent>"`; four of the five values are legitimately `false`, so every read
   mismatched on every input.
   **Recovery:** caught by the two positive controls; rewritten as
   `if length == 0 then "<absent>" else (.[0] | tostring) end`.
   **Prevention:** `//` is "alternative on null OR false", not "default on absent". For any
   boolean-valued field, test `length` explicitly.

9. **Harness fixtures lacked `.owner`,** so a newly-added assertion failed every must-PASS row.
   **Recovery:** added `.owner` to all 14 clean-base fixtures.
   **Prevention:** when adding an assertion over a field, update the clean fixtures FIRST — the
   must-PASS rows are the ones that will tell you, and they are the rows most suites have fewest of.

10. **Added a count to a header whose own stated lesson is "named rather than counted."** The
    header explains that a count in prose goes stale silently; my edit appended "(fourteen now)".
    **Recovery:** self-caught one edit later; count dropped, list updated.
    **Prevention:** when editing a comment that states a policy, check the edit against that policy.

11. **False claims propagated further and faster than code.** "Bounded ETag poll" was prescribed in
    the plan, written into `infra/github/README.md`, `tasks.md`, and my own brief to five review
    agents — and never implemented; there is no ETag or `If-None-Match` anywhere in the repo. The
    `.tf`'s "raises the bar from ONE App acting alone to TWO Apps colluding" was false, and I
    repeated it to those same five agents as an established fact. Five separate sites still
    asserted "no CI, no required review, no CODEOWNERS" about the repo this PR was protecting.
    **Recovery:** swept all sites; plan corrected by APPENDED addendum (dated records are
    append-only), not by editing its body.
    **Prevention:** a plan prescribes a MECHANISM; the implementation may choose another. Before
    quoting the plan's mechanism in docs or a review brief, grep for it in the code. And treat a
    claim you are about to hand reviewers as a claim to verify, not as context to supply — a false
    premise in the brief is a false premise in every finding built on it.

12. *(forwarded from the work phase)* C4 description broken by embedded double quotes, dropping
    every external element out of scope. Both C4 tests passed 23/23; only
    `regenerate-c4-model.sh` caught it. **Prevention:** regenerate after every `model.c4` edit.

13. *(forwarded)* `issue_number` referenced by the dispatch step but never produced by the issue
    step. Self-caught. **Prevention:** the unbound-variable lint's sibling class — an Actions
    `steps.X.outputs.Y` that no step writes.

14. *(forwarded)* Task 6.11 claimed done while `grep` showed the old text in place.
    **Prevention:** grep for the OLD string after an edit, never the new one.

15. *(forwarded)* `git stash list` rejected by the hook on substring match. One-off; hook behaving
    as designed.

16. *(forwarded)* Push rejected non-fast-forward after my own rebase; verified the five "lost"
    commits were pre-rebase SHAs of the same subjects before `--force-with-lease`. One-off.

## Related

- ADR-182 — keyless manifests and a dedicated marketplace source (amended by this work)
- ADR-139 — bot-PR synthetic checks, `ALLOWED_PATHS ∩ SCAN_DIRS`
- ADR-140 — encryption posture ledger (Session Error #6)
- #7520 — narrow `actions: write` off the untrusted-input job (deferred, trigger stated)
- #7524 — widen the workflow env-ref lint to lowercase; `apply-github-infra.yml` has no
  structural harness at all
- #7532 — Sentry Audit Gate red after a vendor API removal (not caused by this work)
- `knowledge-base/project/learnings/2026-08-12-certifying-a-deferral-means-re-deriving-its-benefit-not-just-its-blockers.md`
  — the brainstorm-phase learning from the same issue
