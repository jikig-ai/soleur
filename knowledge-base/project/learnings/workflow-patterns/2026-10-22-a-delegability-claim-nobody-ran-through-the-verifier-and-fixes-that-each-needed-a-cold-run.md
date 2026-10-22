# Learning: a delegability claim nobody ran through the verifier, and fixes that each needed a cold run

## Problem

The owner asked that no human be needed to review a PR or a technical decision, and the CTO
agent ruled (T1 to T4) that the post-merge acts of the Inngest TLS rollout (A0, A1, A3, A4) become
delegable. PR #10783 carried that ruling into the runbook, `go.md` Step 1.5, the ship gate and the
review wording. Two rounds of review plus one dry run then found defects in the ruling's own
consequences, most of them introduced by the previous round's fix:

- **A3 was declared delegable, and it cannot be.** The A3 command carries `-f confirm=FLIP-INNGEST-LINK`,
  and `plugins/soleur/scripts/delegation-verify.sh` denies any `confirm=` or `rollback_ack*` input as
  `non-delegable-command`. Five of ten seats found it independently. The ruling had never run the
  verifier on the command line it was ruling on.
- **A brief fact was stale.** The brief said A1 (the host replace) was pending and asked for it. It had run
  on 2026-10-20 under a different reason, and the `op=resume` that follows had run too. Reading the
  apply run list before dispatching showed the replace would have been a second disruption for no gain.
- **A step read a field that does not exist.** `go.md` read the epic's author with
  `gh issue view --json authorAssociation`, which exits `Unknown JSON field`. The REST field is
  `author_association` through `gh api`.
- **A dedupe matched too loosely.** "Title or body names epic #N" returned unrelated issue #10606 for epic
  #10205, so headless mode would have reused it and the real question would never have surfaced. Only a
  cold-agent dry run of the rewritten text found it.
- **Mirrors of a hook regex were hand-copied.** The hook test restated the regex, and the bun test
  carried a narrower copy, so both stayed green when the hook changed. Prefixing the hook's first
  group with a Delegated-act arm left 30/30 and 31/0 green.
- **Bare-token pins stayed green under inversion.** A seat inverted 13 security-relevant `go.md`
  clauses; 11 survived.
- **Round-1 fixes introduced defects.** The fix-issue close rule named "the agent that merges", which
  does not exist on the auto-merge path (the real closer is `post-merge-monitor.yml`); ADR-294 had a dated
  sentence rewritten in place; the one-shot pointer narrowed a three-source trigger to one; a control row
  for the `Tracks` companion was vacuous.

## Solution

- A3 `action=flip` and A1 are in-session per-command go only; only A4 (`action=off`, before A5) is
  envelope-delegable (CTO ruling R1, recorded in `decision-challenges.md`). A3 success evidence is the
  `flip_verify` handshake line in the run log; a re-dispatch after a failed replace is form (b) only.
- `go.md` reads the author with `gh api ... author_association`, anchors the dedupe on a
  `Standing-delegation epic: #<N>` first line of the filed issue, and prints issue numbers (one per
  line, `--paginate`) instead of counting.
- The hook test derives `GROUP_A..D` and the trigger regex from the hook at runtime and drives the real
  hook with a stub `gh` that exits 64 on unexpected argv and asserts the PR-body call was reached.
  Security-relevant `go.md` clauses are pinned as whole clauses with an inverted-rule mutation row each.
- ADR-294 keeps its dated sentence and gets an appended addendum.

## Key Insight

A claim that an act is delegable is a claim about a verifier, so it is checked by running the verifier
on the exact command line, not by reading the policy that describes it. The same holds for every
prescribed command in added prose: run it once (`gh` field names, flags, dedupe filters) before it ships.
And a fix round is the least-reviewed surface in the diff: each fix here was written holding the
previous defect in mind, so its verification inherited the previous framing. What found the
defects each round was a cold reader executing the text (a dry run, a seat running the real hook),
not a seat reading the diff.

## Session Errors

1. **The brief's "A1 is pending" was stale** — Recovery: read the apply run list, found run 39400431311
   (reason `#10390 arc window`) and `op=resume` run 39445004559, reported the evidence and did not
   dispatch — Prevention: before any dispatch named by a brief, read the workflow run list and the live
   evidence column; the runbook now records A0, A1, A1b as done and says to read the apply run list first.
2. **The CTO's T1 ruling declared A3 delegable without running `delegation-verify.sh`** — Recovery:
   five-seat finding, CTO ruling R1 narrowed T1 — Prevention: a plan or ruling that names an act
   delegable cites the verifier's verdict on that exact line (plan sharp edge added).
3. **`go.md` used the nonexistent `authorAssociation` field** — Recovery: `gh api ... author_association`,
   pins updated — Prevention: run each CLI shape a skill prescribes once before committing it.
4. **A headless dedupe matched an unrelated issue (#10606)** — Recovery: marker-line dedupe, found by a
   cold-agent dry run — Prevention: dry-run any rewritten skill prose against a real read-only case
   (the QA skill already says so).
5. **Hand-copied hook regex in two tests** — Recovery: derive from the hook, run the real hook with a
   stub `gh` — Prevention: a test that mirrors a gate's regex derives it from the gate.
6. **Bare-token pins stayed green under semantic inversion** — Recovery: whole-clause pins and
   inverted-rule rows — Prevention: ask of every pin which one-word edit inverts the rule, and which test
   reds.
7. **Round-1 fixes introduced defects (fix-issue close actor, in-place ADR rewrite, one-shot pointer,
   vacuous companion row)** — Recovery: a second targeted round and a verification pass — Prevention:
   review the fix's new assertions before its new code; already documented in the review skill.
8. **One panel seat left the worktree on a detached HEAD** — Recovery: the branch was checked before every
   commit and had been re-attached — Prevention: later seat briefs forbade `git checkout`; documented in
   the review skill.
9. **The first full plan write was rejected by the plan-write guard** — Recovery: reworded and rewrote —
   Prevention: one-off.
10. **The affected-test gate returned rc=6 (budget-deferred) behind sibling runs** — Recovery: the five
    owning suites were run one at a time and CI is the authoritative gate — Prevention: none needed.

## Tags

category: workflow-patterns
module: standing-delegation, go, ship, runbook-inngest-server
