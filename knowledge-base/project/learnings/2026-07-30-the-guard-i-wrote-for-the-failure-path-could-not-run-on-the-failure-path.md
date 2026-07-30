---
title: "The guard I wrote for the failure path could not run on the failure path"
date: 2026-07-30
category: build-errors
tags: [github-actions, errexit, artifacts, secrets, mutation-testing, guards, bare-token]
symptoms:
  - "A step gated on a failure condition is skipped on every run that satisfies it"
  - "An uploaded artifact contains a secret that the run log correctly masked"
  - "A mutation battery reports all-caught while single-token mutations survive"
  - "A scanner reports the comment that documents a class as an instance of that class"
module: CI
component: github_actions_workflow
problem_type: build_error
resolution_type: code_fix
root_cause: wrong_assumption
severity: high
issue: 7025
---

# The guard I wrote for the failure path could not run on the failure path

## Problem

Fixing a rung-2 rehearsal capture poll that executed 1 of 20 attempts, I added a diagnostic
artifact upload for the FAIL/TRANSIENT paths and a five-arm behavioural test suite. Review
found that the upload **could never execute**, the artifact **would have leaked two of three
Better Stack credential elements on a public repo**, and the suite had **11 surviving
mutants** including one that makes the job report success over a host that booted dark.

Every one of those is the same shape as the bug being fixed: something that reads as
protection while being structurally inert.

## The four transferable classes

### 1. A step `if:` with no status-check function is implicitly ANDed with `success()`

```yaml
# BROKEN — skipped on 100% of the runs it exists for
- name: Upload the capture log on a non-PASS
  if: ${{ steps.capture.outputs.capture_rc != '0' }}
```

The capture step ends `exit "$rc"`. So every path where `capture_rc != '0'` is a path where
that step **failed**, making `success() && capture_rc != '0'` a contradiction.

The trap is that the *sibling* step works:

```yaml
# WORKS — its gate coincides with a green step, which is what hides the class
- name: Upload the evidence file
  if: ${{ steps.capture.outputs.capture_rc == '0' }}
```

Copying the working sibling's shape is what produces the broken one. **Litmus:** for any step
gated on another step's *failure* condition, ask "is the step it depends on green on this
path?" If no, it needs `always()` / `failure()` / `!cancelled()`.

Worse than a silent skip: the same PR added job-summary text and a runbook section telling
the operator to download that artifact. A dead step plus live instructions to use it is a
runbook that sends someone looking for a file that cannot exist.

### 2. `::add-mask::` scrubs the log STREAM, not bytes on disk

`tee` writes raw bytes before Actions sees the stream, so a masked run log and an unmasked
artifact are the *normal* outcome, not an edge case. On a **public** repo an Actions artifact
is downloadable by any authenticated GitHub user for its whole retention window.

Traced concretely for a `doppler run … | tee capture.log` upload:

| reachable byte | how |
|---|---|
| `BETTERSTACK_QUERY_HOST` | `curl: (6) Could not resolve host: <host>` on any DNS/connect error |
| `BETTERSTACK_QUERY_USERNAME` | `--fail-with-body` prints ClickHouse's 401 body, which begins with the username |
| `BETTERSTACK_QUERY_PASSWORD` | **not** reachable — `-u` goes in the Authorization header, never echoed |

Two aggravations worth internalising: the credentials arrived via `doppler run`, **not**
`secrets.*`, so GitHub never learned to mask them even in the log; and the upload gate fired
on the *widest* possible set of paths (`capture_rc != '0'` is also true when the output was
never written).

Fix shape: redact under the scope where the values exist, with **literal** replacement (the
values are opaque and may contain regex metacharacters), gate the upload on the *redacted*
file so a failed scrub yields no artifact rather than a raw one, and set retention to the
diagnostic's actual useful life — on a public repo, retention is the exposure window.

### 3. A mutation battery is evidence about the mutations you imagined

I shipped three mutations, all passing. An independent reviewer ran 17 more; **11 survived**.
The two worst were single-token edits any reviewer would wave through:

- `exit "$rc"` → `exit 0` — the job goes **green on a host that booted dark**, the exact
  outcome the whole interlock exists to prevent. Suite: 56/0.
- deleting the `! grep -q RUNG2_CAPTURE_VERDICT=` sentinel — a genuine host FAIL is then
  reported as a credential problem, sending the operator to the one place the answer is not.

The root cause was not assertion count (56) but **fixture-space cardinality**: 2 stub modes
covering 3 of the step's 7 reachable terminal states. FAIL and TRANSIENT had zero coverage,
so every mutation living in those rows was invisible.

**The generalisable move:** after writing the mutation arms, enumerate the SUT's *terminal
states* and check each has a fixture — not the *edits* you can think of. A state with no
fixture is a blind spot no amount of mutating the states you did cover will reveal.

Corollary on direction: every arm asserted "stop" or "keep going" from one side, so nothing
could show a newly-added fast-fail was not *too* aggressive. Deleting its `wrapper_fails=0`
reset and tightening `-ge 2` to `-ge 1` both passed green. A guard needs a fixture on the far
side of the transform, or it only constrains one direction.

Also: `[[ "" -eq 0 ]]` and `[[ "" -le 2 ]]` are both **TRUE** in bash arithmetic, so a helper
that returns with no stdout on an internal abort makes downstream numeric assertions pass
vacuously. Default every parsed field to a sentinel that cannot be mistaken for a real value.

### 4. The fix for a class documents the class, and then your scanner reports the documentation

This fired **three times in one session**, in the session whose subject was that trap, and
`cq-assert-anchor-not-bare-token` was already in the rule corpus the whole time.

- An audit script over `.github/workflows/` reported a violation whose only `PIPESTATUS[` was
  inside the comment *explaining why that site deliberately does not use a bracket*.
- An acceptance check for "no `|| rc=$?` on this pipeline" found one — in the comment listing
  `|| rc=$?` as disqualified.
- The new drift-guard arm itself lacked comment-stripping, so a future comment writing
  `${PIPESTATUS[0]}` would have reddened the suite spuriously.

Knowing the rule does not protect you, because the collision is *created by writing the fix*:
the moment a task requires both "assert X is absent" and "document why X is forbidden", the
two requirements collide in the same file. **Strip comments before every content assertion,
and treat any assertion added in the same change as its explanatory comment as guilty until
mutation-tested.**

## Key insight

Every defect in this session reduces to **asserting a property of my own work instead of
measuring it**. The upload's `if:` was written by analogy to a sibling rather than traced. The
artifact's safety was assumed from "the log is masked". The guard's strength was inferred from
a passing battery. Two behaviour-change claims in the PR body were stated in the past tense
(*"a genuine RLS violation **was** filed as class B"*) when the run history showed the failure
path had never fired — the claim was a reachable consequence, not an observed incident, and
the reviewing agent that "verified" it cited **my own commit message** as the evidence.

The cheap gate for all of them is the same question: *what measurement would distinguish this
claim from its negation, and did I run it?*

## Session Errors

1. **The bare-token/comment collision, three times** (items above). Recovery: comment-strip
   every content assertion. **Prevention:** when a change both asserts a literal is absent and
   documents why it is forbidden, strip comments first and mutation-test the assertion.
2. **The diagnostic upload could never run** — a step `if:` with no status function.
   Recovery: `always() &&`, plus an arm asserting every non-PASS-gated step carries a status
   function, mutation-proven. **Prevention:** trace the depended-on step's colour on the path
   the gate describes; never copy a sibling gate whose condition coincides with success.
3. **The artifact was an unredacted secret sink on a public repo.** Recovery: redaction step
   under `doppler run`, upload gated on the redacted file, retention 90 → 7 days.
   **Prevention:** treat any `tee`-produced file that becomes an artifact as unmasked, and
   enumerate what the producer's error paths print.
4. **11 surviving mutants.** Recovery: fixtures for the FAIL and blip states; exit-code
   assertions per verdict class. **Prevention:** enumerate terminal states, not edits.
5. **The sibling fix was incomplete two lines below itself** — re-arming `set -e` newly
   exposed `mode=$(… | grep -m1 …)`, which exits 1 when the marker is absent. **Prevention:**
   after re-arming errexit, read forward to the next command that can legitimately return
   non-zero.
6. **Two PR claims asserted rather than measured.** Recovery: checked run history, found the
   advisor scan green on every run and the closure-guard job `skipped` on every run; both
   restated as conditional. **Prevention:** a behaviour-change disclosure is a claim about
   history — query it.
7. **Stale counts** (631 bodies, "nine near-copies"). Recovery: re-derived at HEAD (637; 3
   files). **Prevention:** publish the command beside the number.
8. **A house rule contradicted by 2 of its own 3 sites** — "bracket iff a `PIPESTATUS` read
   follows" when both other sites read a plain `rc=$?`. Recovery: reworded to "iff you need a
   numeric exit code". **Prevention:** check a newly-written rule against every site the same
   change touches.
9. **Deleted a worktree while `test-all.sh` was running in it** → exit 1 from `getcwd` with
   every test passing. **Prevention:** check for running jobs before removing a worktree.
10. **`git push` rejected** after rebasing over a subagent's push. Recovery:
    `--force-with-lease` after confirming `git cherry` showed the remote fully contained.
    **Prevention:** expect divergence whenever a subagent pushes and the parent then rebases.
11. **A mutation that did not land** (shell `$` escaping) reported the baseline. Recovery: the
    `diff -q`-against-backup check caught it and the result was declared VOID.
    **Prevention:** keep asserting the mutation landed — it works.
12. **`test-all.sh` came back 238/239** on `changelog.js data file > returns html from GitHub
    Releases API` — a 5 s timeout on a live network call. Confirmed transient: 3 pass / 0 fail
    in isolation, and the diff does not touch that file. **Prevention:** none needed for the
    diff; but note the background-task notification reported "exit code 0" while the captured
    `TEST_ALL_EXIT` was 1 — the notification reads the trailing `echo`, not the runner.
    Always read the captured rc and the terminal `=== N/M suites passed ===` marker.
13. **Bare-repo-root invocations failed** (`must be run in a work tree`) and
    `worktree-manager.sh create` blocked on an interactive prompt. Both already covered by
    existing AGENTS rules; noted as one-offs.

## Tags
category: build-errors
module: CI
