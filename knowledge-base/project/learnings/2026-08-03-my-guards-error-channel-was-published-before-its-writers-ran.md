---
title: My guard's error channel was published before its writers ran
date: 2026-08-03
category: best-practices
module: scripts/prod-version-drift-check.test.sh, plugins/soleur/test/c4-count-parity.test.sh
issue: 7160
pr: 7209
tags: [drift-guard, diagnosability, bash-set-e, mutation-testing, plan-premises]
---

# My guard's error channel was published before its writers ran

## Problem

#7160 asked for two things: a runtime ceiling on the `release` job, and a CI parity test over
the counts hard-coded in `model.c4` edge prose. Both landed. The interesting part is what the
work surfaced about **guards that report on themselves** — three separate defects in this PR
were not "the guard fails to detect X" but "the guard cannot TELL you what it detected."

Each was green until mutated.

## The main defect: a diagnostic emitted above its own writers

The new B8 extractor computes a critical path and, on any unreadable input, sets `ceiling_err`
so assertion B8d can name what could not be read. The emit was ordered like this:

```python
emit("RELEASE_CEILING_MIN", release_ceiling)
emit("RELEASE_CEILING_ERROR", ceiling_err)      # <-- published here

crit = max(release_ceiling, job_timeout("await-ci"))   # <-- job_timeout ALSO writes ceiling_err
for j in ("migrate", "verify-migrations", "deploy"):
    crit += job_timeout(j)
```

`job_timeout()` sets `ceiling_err` when a job's `timeout-minutes` is non-integer (an
`${{ inputs.x }}` expression). Those calls run *after* the emit, so the value published was
always the stale empty string.

Measured, not reasoned about — an expression-valued timeout on `deploy`:

```
PASS: B8d the release ceiling resolves out of jobs.release.uses
FAIL: B9 threshold >= release declared critical path
```

B8d actively asserts "the ceiling resolved fine" while a timeout is unreadable.

**It is not a silent-green hole** — the unreadable value defaults to 360, which inflates the
path, so B9 reds. That distinction matters and I nearly overstated it: the failure is
*diagnosability*, not safety. But naming the unreadable input is the entire reason B8d exists,
so the assertion was inert for its stated purpose while reading as protection.

**Generalizable:** when a variable is a REPORTING channel, its emit must come after every
writer to it. Ask, per diagnostic: *which code paths write this, and does the publish point
dominate all of them?* This is the intra-function sibling of the write-boundary sweep — same
question, one scope down.

## The sibling: `${VAR:-default}` when the SUCCESS value is the empty string

B8d compares `ceiling_err` against `""`. Written the obvious way:

```bash
assert_eq "B8d ..." "" "${X_RELEASE_CEILING_ERROR:-<unset>}"
```

`:-` substitutes on **unset OR empty**, and empty is the success value — so every clean run
reported `<unset>` and the assertion failed on correct code. The fix is `-`, not `:-`:

```bash
# `-` not `:-`: the SUCCESS value here is the empty string, and `:-` would substitute on it.
assert_eq "B8d ..." "" "${X_RELEASE_CEILING_ERROR-<unset>}"
```

Worth stating because the failure direction is the *safe* one (a false RED), which is exactly
why it gets "fixed" by loosening the assertion instead of the expansion.

## The third: a guard whose own failure message died under `set -e`

`c4-count-parity.test.sh` asserts exactly-one clause match per registered count, so a prose
rewrite that DROPS a clause fails loudly rather than passing vacuously. Mutating the prose
(`check-ins from 7 workflows` → `check-ins from several workflows`) produced:

```
PASS: model.c4 exists
PASS: cron-monitors.tf exists
rc=1
```

No message. `grep` exits 1 on zero matches, the suite runs `set -euo pipefail`, and the
command substitution computing the match count aborted the script *before* the branch that
prints which row went stale. It reds CI, so it is not fail-open — but a parity gate's whole
value is naming the stale edge, and it named nothing.

Every derivation now carries `|| true`, because a legitimately-zero derivation (someone
deletes the last Resend emitter) is exactly the case the gate must REPORT rather than die on.

## The measurement discipline that actually found these

All three were invisible to reading and to a green suite. What found them:

- **Mutate the artifact, not just the prose.** For the C4 gate, perturbing a number in
  `model.c4` is the *weak* half — a row whose derivation globs the wrong path passes that
  forever. The load-bearing check is adding a real 8th heartbeat workflow to the repo and
  confirming C1 reds. Prose-side proves the comparison; artifact-side proves the derivation.
- **Assert the mutation landed on the CONSTRUCT.** My first "synthetic job on the deploy
  needs-path" mutation patched a block-style `needs:` — but `deploy` declares
  `needs: [release, migrate, ...]` in inline flow style, so the edit landed on a different
  job. The run came back `rc=0`, which reads exactly like "B8e doesn't work." It was the
  mutation that didn't work. A file-level "did something change?" check would have passed.
- **A `PASS` on the assertion under test is a finding.** B8d passing during the expression-timeout
  mutation was the whole signal.

## The plan-premise inversion

The repo already teaches that plan-quoted numbers go stale and must be re-derived. This session
hit the **opposite** direction, which I have not seen written down:

The plan filed a deferral for `scripts/test-all.sh` claiming a stale `"21 suites"` header. I
checked and there was no numeric suite claim anywhere in the file, so I declined to file it.
Two sibling commits then merged mid-session, and one of them (#7146) *added* that exact line —
`#   scripts  11 pre-suite bash/python + 21 plugins/soleur/test/*.test.sh` — against an actual
56. My refutation was correct when made and wrong an hour later.

**Generalizable:** a plan premise you refuted is only refuted **against the SHA you checked**.
On a fast-moving `main`, re-check refutations at ship time the same way you re-derive counts —
the rebase that brings in siblings can create the condition you just ruled out.

(That line is now genuinely stale and is a discovered defect in another subsystem — its whole
decomposition is wrong, claiming ~32 suites where the group runs 245 — so it is tracked
separately rather than half-fixed here.)

## Prevention

| Defect | Cheapest gate |
|---|---|
| Diagnostic published before its writers | Ask per reporting variable: does the emit dominate every write? |
| `:-` on an empty-string success value | Use `-` whenever "" is a legitimate value; `:-` only for unset-means-default |
| Guard's own message killed by `set -e` | `\|\| true` on every `grep` whose zero-match case is legitimate |
| Mutation didn't land where intended | Assert the construct changed, not that the file changed |
| Refuted plan premise re-created by a sibling merge | Re-check refutations after the ship-time rebase |

## Session Errors

1. **Apostrophes in comments terminated the single-quoted `PYEXTRACT` string.** Writing
   `GitHub's` / `release's` inside `PYEXTRACT='...'` closed the bash string, so the Python
   body was parsed as shell (`360-minute: command not found`).
   **Recovery:** reworded the comments to avoid apostrophes; verified with an
   `awk NR-range` scan for `'` inside the block.
   **Prevention:** any comment authored inside a single-quoted bash heredoc must be
   apostrophe-free — grep the block for `'` after editing.

2. **`${X:-<unset>}` fired on the empty-string success value** (above).
   **Recovery:** switched to `${X-<unset>}`. **Prevention:** in the table above.

3. **The C4 cardinality guard aborted with no message under `set -e`** (above).
   **Recovery:** `|| true` on every derivation and on the clause extraction.
   **Prevention:** in the table above.

4. **`RELEASE_CEILING_ERROR` emitted before its writers** (above). Found in self-review,
   confirmed by mutation before fixing.
   **Prevention:** in the table above.

5. **A mutation that did not land was nearly read as a negative result.** The block-style
   `needs:` patch missed `deploy`'s inline flow list; `rc=0` looked like "B8e is broken."
   **Recovery:** inspected the mutated YAML, rewrote the mutation against the real construct,
   re-ran (B8e then failed by name).
   **Prevention:** assert the specific construct changed before scoring any mutation.

6. **Launched the full-suite exit gate, then edited the tree under it.** The run spanned my
   edits, so its `240/240` was not attributable to any single tree state.
   **Recovery:** discarded that run and re-ran on a frozen, committed tree.
   **Prevention:** the discipline is already in `work/SKILL.md` ("confirm clean, then do not
   edit under it") — I launched before I was actually done. Confirm `git status --porcelain`
   is empty AND that no further edits are planned before launching.

7. **Read `git diff origin/main` (two-dot) after `main` advanced** and briefly reported a
   57-file diff including infra files that were not mine.
   **Recovery:** re-derived with three-dot `origin/main...HEAD` (9 files).
   **Prevention:** already an in-repo rule; the trigger to watch is a diff that suddenly grows
   — treat it as a moved ref, not a scope breach, until three-dot says otherwise.

8. **Declined a plan deferral that later became true** (the plan-premise inversion above).
   **Recovery:** re-checked after the ship-time rebase and tracked it separately.
   **Prevention:** re-check refuted premises after the final rebase.

9. **Plan Phase 5.2 prescribed updating `CHANGELOG.md`; no such file exists** in this repo
   (releases derive from git tags; the changelog is a PR-body section). One-off.
   **Recovery:** satisfied via the PR body's `## Changelog`.

## Related

- `knowledge-base/project/learnings/2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`
- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
- `knowledge-base/project/learnings/2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md`
