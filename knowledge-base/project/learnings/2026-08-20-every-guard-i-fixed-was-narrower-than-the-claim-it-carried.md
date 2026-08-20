---
module: infra-config gate (apps/web-platform/infra)
date: 2026-08-20
problem_type: logic_error
component: ci_workflow
symptoms:
  - "26 defects found in a PR where all five suites, a 40-row mutation battery, actionlint, shellcheck and 68 CI checks were green"
  - "a boundedness guard passed while a second production `terraform apply` was added"
  - "a one-character `&&` -> `||` inverted a production gate with every assertion still passing"
  - "a repo test committed into a live worktree, twice, moving a branch ref off six commits"
root_cause: guard_narrower_than_claimed_property
severity: critical
tags: [code-review, guard-vacuity, mutation-testing, worktree-isolation, anti-vacuity-floor, operator-facing]
synced_to: [review, git-worktree]
---

# Every guard I fixed was narrower than the claim it carried, and my own fix was too

## Problem

PR #7546 (issue #7104) shipped ~2,000 lines across ~11 commits that had been reviewed by
nothing — a prior six-agent panel reviewed an earlier SHA, and a later panel was killed before
returning a single report. A nine-agent panel plus lead measurement found **26 defects (9 P1 /
12 P2 / 5 P3)**.

Everything was green throughout: `infra-config-gate.test.sh` 132/0, `infra-config-verify.test.sh`
38/0, `infra-config-red-alert.test.sh` 66/66, `guard-vacuity-floor.test.sh` 19/0, the 40-row
mutation battery 40/40, `run-registered-suites.sh` 102/102, actionlint and shellcheck clean, and
68 CI checks passing.

The actuation path was **genuinely well built** — graded, address-asserted, destroy-filtered, and
its `-replace` targets a `terraform_data`, so it destroys no cloud resource. Essentially every
defect was in the **guards that certify it** or the **strings it hands a human**.

## The generalizable lessons

### 1. A guard's own comment often prescribes the fix it did not implement

Guard 3's comment said *"count occurrences within that body"*. The code counted **lines**:

```python
for line in code.splitlines():
    if 'terraform apply' in line and 'tfplan-repush' in line:
        n_apply += 1
```

So `terraform apply … tfplan-repush ; terraform apply … tfplan-repush` on one physical line read
as 1 — and so did an apply of the **first** plan file (`tfplan`, which survives on the runner
until `Reclaim the plan artifacts`). All three "independent producers" were keyed on the literal
`tfplan-repush`, so the chokepoint was **a filename**, not "a production write".

Measured, with a `for`-loop positive control confirming the instrument worked:

| mutation | landed | P1 lines | P2 steps | P3 n_apply | verdict |
|---|---|---|---|---|---|
| baseline | — | 1 | 1 | 1 | passes (correct) |
| + apply of `tfplan` | +1 apply | 1 | 1 | 1 | **EVADES** |
| two applies, one line | +1 apply | 1 | 1 | 1 | **EVADES** |
| `for`-loop (control) | — | — | — | — | caught |

**Gate:** when a comment states the rule, diff the CODE against the COMMENT.

### 2. A verdict SWAP is invisible to every count and every conservation identity

A helper that records a failure as a PASS keeps `PASS+FAIL == CASES` balanced — one verdict
leaves a bucket and enters another — and keeps every assertion-count floor satisfied.

Measured **with a live defect present**, on three of four sibling suites:

| suite | swapped helper | reported | rc |
|---|---|---|---|
| `infra-config-verify.test.sh` | `fail()` | 38 passed, 0 failed | 0 |
| `scripts/infra-config-red-alert.test.sh` | `bad()` | 66 passed, 0 failed (66 assertions) | 0 |
| `scripts/guard-vacuity-floor.test.sh` | `fail()` | 19 passed, 0 failed | 0 |
| `infra-config-gate.test.sh` | `fail()` | **caught** | 1 |

Only the gate suite survived, because it alone carried a ~4-line known-negative self-test.
Counts catch a **dropped** verdict; only driving the REAL helper and asserting **which counter
moved** catches a **swapped** one.

The corollary deserves its own sentence: the guard-vacuity **meta-guard**, whose stated purpose is
catching a floor enforced *through the machinery it guards*, was itself enforced through the
machinery it guards. Its finding printed verbatim as `[ok] 1 covered suite(s) have a floor that
EXITS 0 under a neutered assertion machinery`.

A companion in the same family: `dup_adjacent` was `grep '^  PASS: ' | uniq -d`, and the comment
above it claimed *"the one mutation that CAN keep all three in sync is printing each assertion
twice"*. That is a false universal — a **differently-worded** second line keeps counter, log and
stdout consistent and produces no adjacent duplicate. Measured: `264 passed, 0 failed`, `OK`,
rc=0, with 66 arms deletable.

### 3. A substring test cannot see a boolean structure

`&&` → `||` in a workflow `if:` — **one character** — made the production container swap run on
`success()` alone, ignoring both verdicts:

```yaml
if: >-
  success()
  && (steps.infra_config_gate.outputs.verdict == 'verified'
      || steps.infra_config_gate_pass2.outputs.verdict == 'verified')
```

`AC18_SUCCESS_STEPS` stayed **5** because it tested for the *substring* `success()`;
`G1_EXPECTED_REFERENCES` stayed unchanged because the same references still exist; and a ship
test's three `toMatch` checks all still passed because it reads the file raw — so deleting the
clause into a **YAML comment** also passed.

**Fix:** pin the whitespace-normalised condition by exact equality, keyed by step NAME. Membership,
not cardinality — a scalar over a set samples only its size, so a substitution (gut one member,
add a `success()`-gated no-op) is invisible to a count.

### 4. The operator-facing half is the unguarded half

**Zero of four** emission sites carried `-target=`, while the same file's own comment says
*"-replace alone would plan the whole graph"* — 230 resources, 20 variables with no default, on a
root holding a host the repo treats as unreplaceable. The workflow gets its **own** invocation
right (`-replace=` **and** `-target=` behind `doppler run --name-transformer tf-var`) and the one
it hands a human wrong.

The guardrail sweep also missed exactly one arm: three of four sites named the forbidden
`hcloud_server.web` target; the one that did not was the **backstop arm that fires when the
re-push has already bricked the channel** — the state with no fallback. That is the
"two-thirds false annotation" class the PR existed to close, recurring inside the fix.

### 5. "Could not measure" must never be reported as "the subject is broken"

```bash
CF_ACCESS_ID=$(doppler secrets get CF_ACCESS_CLIENT_ID --plain 2>/dev/null \
  || doppler secrets get CI_SSH_ACCESS_TOKEN_ID --plain)
```

Under `set -euo pipefail` this **aborts at the assignment**. Measured: the step printed nothing
and exited 1 — no `::error::` at all. Three consumers keyed on that raw outcome then filed a P1
saying an unreplaceable host's sole no-SSH channel was bricked, **on a healthy host**, and routed
the operator to a production apply.

The same probe's alive test was a **deny-list**: `401`, `403`, `404`, `500` all read ALIVE —
including the `403` an expired CF Access token (the very credential it had just read) returns.
This is in a PR whose own headline lesson, stated three times, is *"INVERTED TO AN ALLOW-LIST …
THIS IS THE IMPORTANT PART OF THIS GUARD"*.

### 6. An anti-vacuity floor that counts rows while claiming to count shapes

```python
# The controls must also cross more than one shape … Counted structurally rather than trusted.
if len(CONTROLS) < 20:
```

It counted **rows**, which is precisely "trusted". Twelve of its twenty rows were the single
degenerate axis the file itself calls *"twelve rows crossing one axis is one row"* — so the floor
was propped up by the rows it was written to make unnecessary.

### 7. A review finding can be a regression, and the lead's ruling can be wrong twice

I ruled **against** a tee→`CASES` migration on the grounds both mechanisms were mutation-proven.
Measurement then showed the tee's `uniq -d` is evadable by **wording** while `CASES` is not — and
later that **both** are blind to a swap. The real fix was neither migration nor status quo: it was
the self-test.

Separately, an agent recommended symmetrising a pass-1/pass-2 skew tolerance. Applying it would
have accepted a **pre-apply** frame as proof of delivery — a false `verdict=verified` that re-arms
the container swap. The asymmetry was **documented** instead, with the measured ~1–2 s fleet skew
and the reason the strictness is the cheaper error.

Four further agent claims were refuted by measurement: a temp-file leak where `rm -f` precedes
every `exit 1`; a "64 of 163" divergence figure that measured **33**; and a proposed ADR-189 /
AP-024 renumber where both ordinals were free (re-derived three times, including after a merge
that brought ADR-194 onto main).

### 8. Verify the instrument before reading its verdict

Three of mine were broken, and each produced a confident wrong reading:

- `grep -r --include=*.yml .` **silently skips `.github/`** on this host — the `grep` is ugrep,
  which excludes hidden directories. It returned zero hits for a producer that exists, and nearly
  got a present value reported as absent against an agent that was right.
- A hand-built `curl`/`doppler` stub returned rc=1 with empty output that read as a finding.
- `pkill -f "test-all.sh"` matched **its own command line** and killed the invoking shell (exit 144).
- A `diff -q … && echo NOT-LANDED || echo landed` guard printed **"mutation landed" for a missing
  file** after the Bash CWD drifted out of the worktree — a guard that reports success when its
  operand is absent.

### 9. The incident: a repo test escaped its sandbox and committed into a live worktree, twice

`plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` sandboxes **correctly** —
`TMP=$(mktemp -d)`, its own bare repo, `WT_PARENT="$TMP/wt-parent"`. The escape is not the sandbox,
it is the **`cd` into it**. All seven of its `git worktree add` calls swallow failure with
`>/dev/null 2>&1`, so sandbox-absent is reachable (a leftover branch from a crashed run suffices);
the bare `cd` then fails and every command in that subshell runs in the **inherited cwd** —
whatever worktree `test-all.sh` was invoked from.

It committed `victim change` / `victim2 change` / `v9 change` / `v12 change` (author `t <t@t>`,
dated 2025-01-01, adding `a.txt`…`d.txt`) onto a live feature branch, moving the ref off six
review commits, then checked the worktree out to `main` and pulled.

**Recovery that worked**, in this order:

1. The commits survived as **objects**. Push to origin **by SHA** first —
   `git push origin <sha>:refs/heads/<branch>` — so the work is durable before any local surgery.
2. `git update-ref refs/heads/<branch> <good-sha> <fixture-sha>` — a compare-and-swap off the
   fixture commit, which fails loudly if anything moved underneath.
3. Restore the checkout, then remove the untracked fixture files (after reading them).

**The fix was incomplete and I verified it wrongly.** I guarded the two `cd "$WT_ACTOR"` sites —
which cause the reap/checkout damage — re-ran, and it escaped **again**: HEAD moved
`63fa1f335` → `877ca02e7` with all four fixture commits back. The **commit-producing** sites are
four *different* `( cd "$X"` subshells with no `&&`, mapping one-to-one onto the four fixture
commits. The fifth unguarded site had no fixture to make it visible and is the worst:
`( cd "$SEED"` ends in **`git push origin main`**.

The `( cd "$X" && … )` forms in the same file are **safe** because `&&` short-circuits — which is
exactly why the unguarded ones read as equivalent and are not.

```bash
# unsafe: on a failed cd, everything below runs in the inherited cwd
( cd "$WT_VICTIM2"
  echo hi2 > b.txt
  git -c user.email=t@t -c user.name=t add b.txt
  …
)

# safe
( cd "$WT_VICTIM2" || { echo "FATAL: cd to sandbox failed; refusing to write git objects in $(pwd)" >&2; exit 90; }
  …
)
```

**Verification that actually proves it:** re-run and assert `git rev-parse HEAD` is **unchanged**.
Do not infer from the guard's presence — that is what produced the false all-clear the first time.

### Two smaller ones worth recording

- A CI `timeout-minutes` sized against *"17 → 22 rows"* for a battery that is now **40** rows.
  Re-measured 194 s at JOBS=4 on 16 cores (vs the recorded 85 s at 17 rows); CI caps at JOBS=2 on
  4 vCPU, so ~+218 s there. `581 + 218 = ~799 s` basis; `799 × 1.4 = 18.6 min → 20`. It fails in
  the direction that **cancels a job**, not the one that wastes a runner.
- A p1 alert that reached **no operator surface**: both the weekly digest and the
  `cron-action-required-sla` clock **select** on `--label action-required`, and neither selects on
  priority. The issue carried `priority/p1-high` and appeared in neither — while the p2
  `recovered` notice did get a digest line.

## Key Insight

**A guard is a claim, and the claim is almost always broader than the assembly.** Every defect in
this review reduces to the same shape: the property named in the comment, the failure message, or
the PR body quantified over a set that the code never walked — lines instead of occurrences, a
substring instead of a boolean, a filename instead of a write, rows instead of shapes, a count
instead of a membership, one direction of a comparison instead of two.

The corollary that cost the most time here: **this applies to the fix as well as to the code being
fixed.** My guard for a sandbox escape closed two of five sites and I declared it verified; the
pass-2 upper bound I added shipped with no fixture until I noticed the suite count had not moved.
A fix is exactly as unpinned as the blind spot it closes, because it is written after the tests
and nothing forces coverage for it.

## Prevention

- When a comment states a rule, diff the **code** against the **comment** before trusting either.
- For any assertion helper, add a known-negative self-test that drives the REAL helper and asserts
  **which** counter moved. Counts and conservation identities cannot see a swap.
- For any `∀ x ∈ S` guard, ask where S comes from and whether the derivation can see a new member.
- Name the mutation that satisfies the assertion while violating the property. If you cannot, the
  assertion probably pins spelling or placement.
- After fixing a sandbox/`cd` escape, re-run and assert **HEAD is unchanged**.
- Verify every instrument against a known-positive before reading its verdict, and treat a
  baseline taken while another process mutates the tree as **void**.

## Session Errors

1. **`security-sentinel` wedged** — returned three status lines across two `SendMessage` resumes and
   never delivered a report. Recovery: the lead ran its scope directly and found five evasions.
   **Prevention:** panel prompts must state "your final assistant message IS the deliverable" at
   SPAWN time, not on resume.
2. **`grep -r --include=*.yml .` skipped `.github/`** (ugrep excludes hidden directories); nearly
   reported a present producer as absent, contradicting a correct agent. Recovery: explicit `find`
   enumeration. **Prevention:** enumerate with `find` for dot-directory paths on this host.
3. **A hand-built `curl`/`doppler` stub gave rc=1 / empty output** that read as a finding about the
   I3 case. Recovery: instrumented the real suite instead. **Prevention:** verify an instrument
   against a known-positive before reading its verdict.
4. **`pkill -f "test-all.sh"` matched its own command line** and killed the invoking shell (exit
   144). Recovery: `ps -eo pid,cmd | grep -E "test-all[.]sh"`. **Prevention:** bracket a character
   in any self-matching pattern.
5. **Bash CWD drifted out of the worktree** — `cp` failed on a file that exists, and a
   `diff -q … && … || echo landed` guard printed "mutation landed" for a **missing** file.
   **Prevention:** `cd <abs> &&` on every call, and assert the operand exists before diffing.
6. **Heredoc delimiter collision** — an outer `<<'PYEOF'` was terminated by the inner `PYEOF` being
   written into the body. Recovery: distinct outer delimiter. **Prevention:** use a distinct outer
   delimiter whenever the body contains heredocs.
7. **`rc=$?` after a pipe measured `tail`'s exit**, so a lint that exits 1 was reported as rc=0.
   Recovery: re-measured without the pipe. **Prevention:** capture rc before piping, or use
   `PIPESTATUS`.
8. **A stray `git stash list`** tripped `hr-never-git-stash-in-worktrees` (deny). It served no
   purpose in the command. **Prevention:** do not include probes that serve no purpose.
9. **A backgrounded CI poll was denied** by `hr-monitor-not-run-in-background-for-polling`. Correct
   denial; switched to the Monitor tool. **Prevention:** none needed — the hook works.
10. **The lease test corrupted the worktree twice, and the first fix was declared verified while
    incomplete.** Recovery: recovered by SHA, then guarded all five sites. **Prevention:** after
    guarding a sandbox escape, re-run and assert HEAD is UNCHANGED rather than inferring from the
    guard's presence.
11. **A false claim was written into a commit message** — that the lease test "previously passed by
    writing to a live worktree", when the first run of it was already `rc=1 PASS: 30`. Recovery:
    amended with `--force-with-lease`. **Prevention:** apply the same claim-verification discipline
    to one's own prose that the review applies to the diff's.
12. **A `TEST_GROUP=scripts` result (35 failed suites) was taken during the corruption window** — a
    contaminated baseline that would have voided any conclusion drawn from it. Recovery: re-run
    clean. **Prevention:** a baseline taken while another process is mutating the tree is void.

## See also

- `2026-08-16-...` — the prior panel on this PR, whose headline finding (three fixes defeated by
  executed mutations while both suites reported perfect green) is the same class one pass earlier.
- `knowledge-base/project/learnings/2026-08-19-my-battery-reverted-the-fix-it-was-testing.md`
- `knowledge-base/project/learnings/2026-08-11-the-pr-that-fixed-narrow-guards-shipped-three-narrow-guards.md`
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
