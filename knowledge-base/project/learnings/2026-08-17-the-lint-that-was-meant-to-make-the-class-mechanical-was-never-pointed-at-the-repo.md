# The lint that was meant to make the class mechanical was never pointed at the repo

**Date:** 2026-08-17
**PR:** #7589 — `fix(registry): the delivery-refusal artifact could not post, and reported success anyway`
**Instruments:** 12-agent review panel, a `soleur:engineering:cto` ruling, a CONCUR gate.

## Problem

PR #7589 fixed a real defect: a delivery dispatcher's refusal-artifact step could not post
(no `issues: write`) and, because the call ended in `|| true`, reported SUCCESS while posting
nothing. Its third deliverable was a lint "so a tracker-writing workflow without `issues: write`
fails the build" — i.e. a mechanism to stop the class recurring.

Review found the same defect class three times inside that remedy.

## 1. The lint was registered as a fixture suite and never aimed at the tree

`scripts/test-all.sh` carried exactly one line:

```
run_suite "scripts/lint-workflow-issue-write-scope" bash scripts/lint-workflow-issue-write-scope.test.sh
```

Every `run_lint` in that suite targets `$TMP/wf`. So CI proved the lint *behaves* correctly
against synthesized fixtures, and nothing ever asked whether the repository is clean. Meanwhile
`.github/workflows/inngest-watchdog-restart-dispatch.yml` carried the comment
*"scripts/lint-workflow-issue-write-scope.py now fails the build instead"*, which was false.

Every peer workflow lint in the same file is registered as a **pair** — a fixture suite and a
`-live` arm pointing at the real tree (`lint-workflow-step-env-refs-live`,
`lint-workflow-errexit-capture-live`, `lint-window-closure-assertion-live`). This one had no
`-live` arm.

**The generalizable form:** *a green test of a gate is not a green gate.* For any new gate, name
the CI invocation that runs it against production inputs. If you cannot name one, the gate is
decoration — and it will read as protection to every later reader, which is worse than absence.

Six of twelve agents converged on this independently, and the decisive evidence was not
reasoning but a `grep` for the sibling registration pattern.

## 2. The PR broke a rule stated in the learning file it shipped

Its learning file said, in §2:

> **Whenever a step has an internal deadline, assert that the job's `timeout-minutes` exceeds the
> sum of every internal deadline on its path**

The workflow it shipped set `timeout-minutes: 45` while the two internal deadlines on one
sequential path — a 2100s preflight drain and a 1500s apply poll — sum to **60 minutes**. The
comment justifying 45 *states both numbers adjacently* and then draws the wrong conclusion.

Because a cancelled job does not satisfy `failure()`, the artifact step would not have run at
all. Setting 45 did not close that defect; it moved it from 15 minutes to 45.

**The generalizable form:** *a rule written in a learning file is not self-applying.* Run it
against the diff that introduces it. The highest-risk place for a new rule to be violated is the
PR that authors it, because the author is holding the *narrative* of the rule, not its predicate.

**RECURRENCE, 2026-08-20 (#7587) — and this time the two numbers disagreed for a *reason*.**
The plan for the ARM-gate timeout ladder **sized** itself from one sum and **wrote its own guard**
against a different one:

| | Σ |
|---|---|
| **Nominal** — every hand-written `arm_one` call site | **1660 s** |
| **Reachable** — only the sites present in tfstate today | **1430 s** |

`arm_step_timeout` was set to `1430 × 1.1 = 1573` → 27 min, while the acceptance criterion it
wrote quantified over `sum(arm_one deadlines)` = 1660, and `1620 < 1660 × 1.1 = 1826`. The plan's
own ladder failed the plan's own AC. Caught by the implementation's Phase 0 measurement pass,
before any code was written.

Above, the disagreement was an arithmetic slip with both numbers stated adjacently. Here it was
**structural: guard and sizing quantified over different populations.** That is the more dangerous
version, because re-reading the comment does not reveal it — both numbers are individually correct.
**Size from nominal:** a call site absent from state today is still a call site on the day it is
not. Whenever a budget is computed over "the members that exist" and asserted over "the members
that are declared", name the two sets separately and write the inequality against the larger. See
[the channel was silent on the path it was built for](./2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md) §4.

## 3. The wait budget was charged in `sleep`, not elapsed

`waited=$(( waited + POLL_SECS ))` never counted the three `gh run list` round-trips each
iteration makes. At 105 iterations that is 315 unbilled calls, so the loop's real duration was
`2100 + 315*T_gh` — minutes of drift that grows exactly when the API is slow, i.e. during the
incidents the workflow fires for. `timeout-minutes` was being derived from `WAIT_SECS`, so a
declared budget that is not the real ceiling made that derivation unsound.

**The generalizable form:** if a budget is used to size a timeout, it must measure wall clock.

**RECURRENCE, 2026-08-20 (#7587):** the ARM gate's poll loop had the identical shape —
`elapsed=$(( elapsed + ARM_POLL_INTERVAL_S ))`, blind to the per-iteration `curl`. Against a 200 s
deadline and a 15 s round-trip the *reported* elapsed stopped at 200 while the real clock reached
~620 s, which is why the job kept exceeding a ceiling derived from the declared deadlines. Note what
this implies for the **test**: an assertion on the number the loop *reports* passes over this defect
entirely. The fix is asserted by injecting a fake clock and asserting the **observed** clock, not
the reported one (`arm-heartbeats.test.sh` T3 + mutation row M1) — two different numbers, and only
one of them can see the bug.

## 4. "Cancelled" is two failure modes with opposite semantics

This one is the sharpest, because a domain-owner ruling got it wrong and a simplicity gate caught it.

The concurrency group drops a *pending* run when a third arrives. The CTO ruled correctly on the
delivery half (base the delta gate on a **delivery watermark** — the head SHA of the last
successful run — so a successor's range subsumes every range it displaced, and eviction coalesces
instead of dropping). It then proposed a new `workflow_run` sweeper for the remaining
"cancelled leaves no artifact" residual, and scoped it as a follow-up.

The CONCUR gate DISSENTed, on a distinction both the CTO and I had collapsed:

- **cancelled while PENDING** — the run executes **no steps**. Nothing in-band can fire. And
  nothing needs to: the watermark already makes that case lossless.
- **cancelled by `timeout-minutes`** — the job **started**, and `always()` steps run inside the
  runner's cancellation grace window. `failure()` does not.

Only the second was the actual residual, and it is one line — `if: failure()` →
`if: always() && job.status != 'success'` — in the file the PR was already rewriting. The file
*already depended on that exact distinction*: its poll step carries the comment
"`always()` IS LOAD-BEARING."

The deferred sweeper would also have been the anti-pattern the PR exists to remove: a
`workflow_run` observer whose firing on a never-started run was explicitly flagged as
**unmeasured**, plus a second workflow whose own silence nobody observes.

**The generalizable form:** before deferring a residual, ask whether it is **one** failure mode
or two. Collapsing two modes with different mechanics is what makes an in-band fix look like it
needs an external observer. And an external observer added to close an observability gap opens a
structurally identical one — who observes the observer?

## Session Errors

- **A mutation harness that reported six false `DID NOT LAND` rows.** `\x27` inside a heredoc is
  not interpreted by bash, so six of nine mutation scripts died on SyntaxError. **Recovery:**
  re-ran them from a separate Python file with literal string replacement. **Prevention:** the
  landing assertion is what made this visible rather than silently green — it worked as designed.
  Already covered by `review/SKILL.md` ("a `perl`/`sed` mutation whose replacement contains `$`
  interpolates it as the TOOL's variable"); the same class, a different quoting layer.
- **Scored a mutation as KILLED when it had crashed, not weakened.** The M7 replacement left a
  dangling `except`, so the mutant died on SyntaxError. **Recovery:** re-ran it as a working
  weaker program (bare read restored), verified it compiles AND still passes on the real tree as
  a positive control, then confirmed the *named* arm reddens. **Prevention:** already stated in
  `review/SKILL.md` ("a deletion that crashes reads as caught while proving nothing") — the gap
  was applying it, not knowing it.
- **Read a piped `rc=$?` as the lint's exit code.** `python3 lint.py | tail -1; echo rc=$?`
  reports `tail`'s status; briefly reported `rc=0` for a run that had flagged a violation.
  **Recovery:** re-measured without the pipe. **Prevention:** already stated in
  `review/SKILL.md` ("assert the EXIT STATUS, which is what a caller branches on").
- **`git archive origin/main | tar --strip-components=2` extracted 0 files,** so the first
  `origin/main` comparison scanned nothing. **Recovery:** the lint's own `scanned == 0 → rc 2`
  guard refused the vacuous clean, which is exactly what that guard is for; re-extracted with
  `git ls-tree` + `git show`. **Prevention:** one-off.
- **Plain `git push` rejected after a rebase.** **Recovery:** `--force-with-lease`.
  **Prevention:** one-off; expected after any rebase-before-ship.

- **Routed a skill edit to the bare-repo checkout instead of the worktree.** The route-to-definition
  edit targeted `/home/jean/.../soleur/plugins/soleur/skills/review/SKILL.md` — the main checkout —
  while working inside `.worktrees/feat-fix-registry-dispatch-artifact-permission`. **Recovery:**
  the `guardrails` PreToolUse hook BLOCKED it and named the correct worktree path; re-applied there
  and confirmed with `git status --short`. **Prevention:** already stated verbatim in
  `compound/SKILL.md` ("Always use worktree-absolute paths … never `../../plugins/...` relatives
  from inside a worktree, which escape the worktree and resolve to the bare repo root"). The hook
  is the reason this cost seconds rather than a silently-lost edit — this is the enforcement
  hierarchy working as designed: prose said it, the hook enforced it.

Four of the six are instances of one class — *an instrument reporting a result it did not
produce* — and all three were already documented in `review/SKILL.md`. The corrective is not a
new rule; it is that the mutation loop should run its landing assertion, its compile check, and
its positive control as a **fixed preamble** rather than as things remembered per row.

## Related

- `knowledge-base/project/learnings/2026-08-17-the-artifact-that-proves-a-refusal-happened-could-not-be-written.md`
  — the author-side learning for the same PR.
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
- `knowledge-base/project/learnings/2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`

## Tags

category: workflow-patterns
module: ci-guards
