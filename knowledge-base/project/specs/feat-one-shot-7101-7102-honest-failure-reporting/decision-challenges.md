# Decision Challenges — feat-one-shot-7101-7102-honest-failure-reporting

Recorded per ADR-084 / `decision-principles.md`. Headless pipeline run, so these were
**not** applied unilaterally and **not** resolved by asking. `ship` renders this into the
PR body and files it as an `action-required` issue. **The operator decides.**

---

## UC-1 — Plan-review recommends dropping the Docker fallback that the task ARGUMENTS explicitly requested

**Class:** User-Challenge (departs from stated operator direction)
**Status:** plan v3 proceeds WITHOUT the fallback; operator can reinstate

### What you asked for

The task ARGUMENTS for #7102 specified two deliverables:

> Fix: (a) check the `rm` status and report honestly … (b) **wire in the no-sudo fallback
> when the plain `rm` hits EACCES** … `docker run --rm -v "<abs>/.worktrees:/wt" alpine:3
> sh -c 'rm -rf /wt/<name>'`

Plan v1 implemented both. Plan v3 ships only (a).

### Why the plan departed from it

Four review agents ran. Three independently recommended against shipping (b). More
importantly, the premise (b) rests on was **falsified by verification**, not by opinion:

1. **The surface is not operator-only.** The ARGUMENTS' reasoning — "The Bash tool is
   non-interactive with no sudo, but Docker runs as root" — implies a local operator
   machine. But `apps/web-platform/server/git-lock-marker-telemetry.ts:3` states verbatim
   that `worktree-manager.sh` runs "**INSIDE the agent sandbox**", and
   `apps/web-platform/server/safe-bash.ts:165-166` names `cleanup-merged` — the exact verb
   that reaches this reaper — as a write verb that runs "via the autonomous/sandbox path,
   never here." ADR-081 §Alternatives (ii) rejected auto-`rm -rf` on precisely that
   surface ("blind surface + no privilege"). v1 argued the rejection didn't apply; it
   does.

2. **The remediation hint is a verified guardrail bypass.**
   `guardrails:block-rm-rf-worktrees` (`.claude/hooks/guardrails.sh:129`) matches
   `rm -rf … .worktrees/`. Tested both forms against that regex:

   | form | result |
   | --- | --- |
   | plain `rm -rf .worktrees/<name>` | **MATCH — blocked** |
   | `docker run … sh -c 'rm -rf /wt/<name>'` | **NO MATCH — bypassed** |

   v1 would have printed that command on stdout — the stream it documents as "the stream
   the orchestrating agent greps" — from inside the very script the guardrail's deny
   message names as the safe alternative.

3. **`sh -c` with an interpolated basename is shell injection as root.** The loop is
   `for dir in "$WORKTREE_DIR"/*/` — any directory, not only git-created ones. A directory
   named with a quote and a semicolon yields arbitrary root commands against a read-write
   mount of the whole `.worktrees/` tree.

4. **The orphan classifier is too weak to remove the ownership backstop.** It is "not in
   `git worktree list`" + "no `.git` file" — much weaker than ADR-081's falsifiable
   `-type c` invariant. Today an unprivileged `rm` physically cannot destroy what the
   operator doesn't own; escalation removes that backstop exactly where the classifier is
   most likely to be wrong, since root-owned content is by definition evidence that a
   different system placed something there.

Also relevant: the issue itself records the triggering event as **one-off and
non-blocking**, and there is currently **no root-owned residue on disk** to reclaim.

### What ships instead

Honest counting, the stdout sentinel with `reason=rm-partial`, and an unconditional
failure summary whose hint points at `git-worktree SKILL.md §Sharp Edges` rather than a
pasteable root command. Both issues' stated defects close with this alone — v1's own ADR
text conceded "the escalation is the convenience, the honesty is the fix."

The escalation is **deferred with its safe design fully recorded** in **#7112**: opt-in
default, code-enforced surface predicate, positive object-class predicate, exec-form
`docker run` with no `sh -c`, digest pin, mount-the-target-not-the-parent, `timeout 5
docker info`, local-socket assertion, and the ADR the gate will demand. The guardrail
matcher gap is **#7113** (pre-existing; not widened here) and the producer-side Supabase
root-residue fix is **#7114**.

**Framing correction (recorded during /work).** This entry originally described the
Docker fallback as "stated operator direction". It was not: the operator's input was
`7101 7102`. The `docker run` form came from the **body of issue #7102**, and was relayed
into the task arguments by the routing step — so dropping it is an ordinary engineering
call on a suggestion, not a departure from an instruction. The verification that
falsified it stands either way; only the escalation class changes.

### Your options

- **Accept** — the escalation lands later, behind the tracking issue, designed safely.
- **Reinstate** — say so, and it returns in this PR with the safe design above (larger
  diff, and it needs an ADR plus the ADR-081 pointer).
- **Reinstate as-specified** — not recommended: the `sh -c` injection vector and the
  guardrail bypass are defects regardless of the surface question.

---

## UC-2 — Plan-review recommends splitting #7101 and #7102 into separate PRs

**Class:** User-Challenge (departs from stated operator direction)
**Status:** plan v3 keeps ONE PR as instructed

### What you asked for

> Fix two open dev-infra reliability bugs **in one PR**. Closes #7101 and #7102.

### The challenge

Two reviewers argued for splitting: #7101 is four integer literals plus a guard and
unblocks a red `main` today; #7102 touches a bash reaper. "Both are instances of the same
defect" is a narrative, not a shared review surface, and coupling makes the fast fix wait
on the slower argument.

### Why the plan did not split

This was explicit operator direction, and the strongest argument for splitting — that
#7102 carried a dangerous root `rm -rf` — **dissolved when UC-1 removed it**. What
remains in #7102 is ~14 lines of inline bash with no privileged operation, which is a
comparable review surface to the #7101 half. The coupling cost is now low.

### Your options

- **Accept** — one PR, as instructed.
- **Split** — say so; #7101 can merge within the hour and #7102 follows.

---

## Note on classification

Both entries are User-Challenges rather than mechanical findings, so neither was
auto-applied on the plan's own authority. The **mechanical** findings from the same
review pass — two unrunnable acceptance criteria, a false arithmetic claim headed into a
committed source comment, a numeric-separator parsing trap, and a live rc=1 defect in the
function being rewritten — were applied directly in plan v3, since those are correctness
issues with no operator judgment involved.
