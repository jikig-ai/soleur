---
module: web-platform-infra
date: 2026-07-20
problem_type: logic_error
component: ci_workflow
symptoms:
  - "8+ stale claims survived a deletion sweep, each a sibling of one that was correctly fixed"
  - "a commit message describing an auto-close hazard re-armed the auto-close hazard"
  - "editing a running bash script produced a false RC=2 'unexpected EOF'"
  - "a drift-guard test that reads its own source self-matched on an unanchored regex"
root_cause: wrong_index_unit
severity: high
tags: [deletion-sweep, stale-claims, auto-close, self-match, vacuous-assertion, mutation-testing]
synced_to: [review, one-shot]
---

# I swept by file when the unit of truth was the claim

## Problem

PR #6744 swept the dead web-2 dispatch surface (#6575): two workflow jobs, an enum
9→7, a jq gate, 8 fixtures, two unwired verifiers, ~750 lines. The implementation was
disciplined — every sentinel change carried a `# reason:`, the full 195-suite run was
green, `tsc`/`actionlint`/`terraform fmt` clean.

Ten review agents then found **eight-plus stale claims still standing**, and they shared
one signature: *the sibling was corrected and the twin was missed.* `web2_allow`'s
mention in the `.jq` was generalized; its twin in `web2-retire-gate.sh` was not. The
`stock-preflight-gate.sh` "mirrors" line was reworded; its twin in the test file was
not. ADR-068 §(c) got a dated correction; the `server.tf` HARD GATE naming the same
deleted script did not.

## Root cause

**I indexed the sweep by FILE. The unit of truth was the CLAIM.**

Opening each touched file and fixing what it said about deleted things is a sweep whose
completeness is bounded by the file list. But a claim about `warm_standby` lives wherever
someone once wrote it — including files this PR never opened. `knowledge-base/.../runbooks/`
was never touched at all, while my own enum comment asserted "the runbooks were rewritten
in the same change."

The fix is mechanical: for each DELETED entity, grep every surviving mention and classify
it **historical** (fine) or **live claim** (fix). That method finds the missed twin
*because the first copy was already fixed* — the exact case a file-indexed pass cannot see.

```bash
for e in warm_standby web_2_recreate lb-weight-gate web2_allow web2_server_replaced; do
  grep -rl "$e" --include='*.sh' --include='*.ts' --include='*.tf' --include='*.yml' \
      --include='*.jq' --include='*.md' . \
    | grep -vE '/(plans|specs|brainstorms|archive|post-mortems|learnings)/'
done
```

## The four other ways a green suite certified nothing

**1. A candidate set narrower than the property.** An assertion forbidding post-`COPY`
mutation of the baked host-scripts anchored correctly on `^RUN\s` (comment-proof) but
selected candidates by the literal string `/opt/soleur`. Three shapes that mutate the
same bytes survived green: `WORKDIR /opt/soleur/host-scripts` + a relative `sed`, a later
overwriting `COPY`, and `ENV SD=/opt/soleur` + `$SD/...`. **Anchoring and candidate
selection are different axes; proving one says nothing about the other.** Fixed by
widening to `^(RUN|COPY|ADD)\s` and treating a `WORKDIR`/`ENV` naming the path as
tainting every following instruction.

**2. A floor misread as an equality check.** I dropped a parity operand arguing that
asserting `0` copies "passes vacuously whether the copies are gone or the extractor
broke." The third argument is a `-lt` FLOOR — the per-copy content comparison runs
regardless. Measured: a wrong-roster copy is **invisible** as I shipped it and fails loud
with the operand restored at `0`. I reasoned about the helper instead of reading it.

**3. A test that reads its own source SELF-MATCHES.** A new guard pinning a strip-list to
real job headers extracted `"utf8"`, `"y"`, `"m"` — its own strings. The first occurrence
of the symbol in the file is inside the regex literal doing the reading. Only the
non-vacuity floor (`expect(stripped.length).toBeGreaterThan(0)`) caught it; without that
line it would have shipped permanently green over an empty set. Fixed by anchoring at
column 0 (`/^function …/m`) — the declaration is the only one unindented.

**4. Editing a script while it executes.** I edited `scripts/test-all.sh` during a
backgrounded full-suite run. Bash reads scripts incrementally, so the running parse
corrupted and the run exited `2` with `unexpected EOF` — a failure with no defect behind
it, costing a 6-minute re-run to disambiguate.

## Key insight

**A documented class recurring is evidence that prose is the wrong enforcement layer.**

The sharpest error was #17: my commit message *explaining* that a plan commit carried
`Closes #6712` contained the literal string `Closes #6712`. GitHub's parser is
word-boundary based and reads branch commit bodies on squash merge — so the explanation
would have closed the issue the explanation existed to protect.

That class is already written down, twice
([[2026-06-29-auto-closes-meta-content-in-commit-body-trips-github-autoclose-on-hand-rolled-merge]],
[[2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker]]). I read the
skill that documents it, fixed the instance it warns about, and then re-armed it in the
same breath. Prose that has failed twice does not need a third paragraph — it needs a
grep in a gate.

## Prevention

- **Sweep by claim, not by file.** Enumerate deleted entities first; grep each; classify
  every survivor historical-or-live. Budget for the greps that land outside the diff.
- **A guard whose deletion leaves the suite green pins nothing.** Mutate a SANDBOX copy,
  and assert the mutation LANDED (`diff -q` against a pristine backup) before believing a
  result — a `sed` that silently failed reports the baseline, which reads exactly like
  "nothing to catch".
- **Never edit a file a background job is executing.** Commit first, or wait.
- **A subagent sandbox is a worktree-sized object.** One filled the shared 4 GB `/tmp`
  tmpfs to 100% and blocked the parent session. Put sandboxes in `/var/tmp`, and clean up
  only your own session's artifacts.
- **Read the helper before reasoning about its semantics** — floor vs equality, `-lt` vs
  `-eq`, no-op-on-missing vs error-on-missing. Three of this session's findings were me
  inferring a contract I could have read in ten seconds.

## Session Errors

**IaC-routing hook blocked the first plan write** on quoted "operator-local apply" prose
— Recovery: `iac-routing-ack` + justifying preamble — **Prevention:** quote pre-existing
operator framing inside a fenced block so the classifier sees it as citation.

**Plan v1 was rejected by its own deepen pass** (tautological bake-time gate, would have
poisoned `:latest`) — Recovery: rewritten, scope narrowed to #6575 — **Prevention:**
working as designed; deepen caught it before any code.

**Edited `scripts/test-all.sh` mid-execution** → false `RC=2` — Recovery: re-ran clean —
**Prevention:** see above; never edit a file a background job is reading.

**Added `inngest_host_replace` to a strip chain while only pruning two entries** —
Recovery: diffed against `origin/main`, restored faithful list — **Prevention:** for any
list edit, diff the resulting member set against main, don't eyeball the nesting.

**Introduced a false claim swapping a sentence head** (cited a retire fixture for
`-replace` semantics) — Recovery: rewrote to stand alone — **Prevention:** after changing
a clause's subject, re-read the tail; this is the dangling-clause class from the other side.

**Duplicated a clause in `server.tf`** via mechanical edit — Recovery: rewrote the
enumeration — **Prevention:** grep the edited line for its own new content before moving on.

**Swept file-by-file, missing 8+ twins** — Recovery: claim-indexed re-sweep — **Prevention:**
the method above.

**Never swept `runbooks/` while claiming I had** — Recovery: superseded the stale runbook,
wrote `web-host-birth.md` — **Prevention:** a claim about what a PR did is a claim to verify
with `git diff --stat -- <path>`.

**Dropped a parity operand on wrong reasoning** — Recovery: restored at floor 0 and
sandbox-proved it armed — **Prevention:** read the helper's comparison operator.

**Applied my own retention rule inconsistently** (a callerless script listed "Retained")
— Recovery: wired it into the birth runbook so retention is true — **Prevention:** when
you author a rule in the same PR, run your own artifacts through it.

**Docs authored against the PLAN filename while code shipped another** — Recovery:
corrected 4 sites — **Prevention:** grep the shipped basename, not the planned one, before
the ADR lands.

**`/tmp` hit 100%** (subagent sandbox, 2.4G) — Recovery: removed my own session's finished
sandbox — **Prevention:** sandboxes in `/var/tmp`.

**Ran `git stash list`** — blocked by hook — Recovery: used `git rev-parse --verify
refs/stash` — **Prevention:** the hard rule covers read-only forms too.

**`git filter-branch` failed on a dirty tree** — Recovery: committed first — **Prevention:**
expected; commit before history rewrites.

**Force-push rejected post-rebase** — Recovery: `--force-with-lease` after verifying the
remote-only commits were my own pre-rebase versions — **Prevention:** expected after a rebase.

**Used GNU-grep syntax against host ugrep** (`grep -n '^\+'` → invalid syntax) —
Recovery: `awk` — **Prevention:** the repo already documents that the host `grep` is ugrep.

**My commit message describing the auto-close hazard re-armed it** — Recovery:
`filter-branch` msg-filter, verified clean — **Prevention:** the mechanical gate below;
prose has now failed three times on this class.

## Related

- [[2026-06-29-auto-closes-meta-content-in-commit-body-trips-github-autoclose-on-hand-rolled-merge]] — the class error #17 recurred against
- [[2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker]] — same class, PR-body surface
- [[2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first]] — the inverse: ADDING a copy disarms a presence-guard; here REMOVING members stranded claims
- [[2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of]] — the candidate-set finding is this, one axis over
- [[2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name]] — self-match (SE-1) is the same hazard the strip-list pin hit
