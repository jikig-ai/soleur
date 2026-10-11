# Learning: the fix landed green and left its own pin red — and my plan fabricated its decisive reason

## Problem

#9970: squash `21331e94e3` shipped the correct `_norm()` normalization in the provisioner-parity
guard, and post-merge CI went RED anyway — on the mutation battery row that pinned the *old*
diagnostic. `control-C` still called `expect_red` against `uncovered=['Cosign-Trusted_Root@web-2']`,
an emit the normalized guard can no longer produce: a case/hyphen rename now resolves to one
identity, stays swept and justified, and is correctly GREEN. A fix that changes a mechanism's
diagnostic surface orphans every anchor written against the old surface. The resume prompt said
"FIXED — close it"; the merged-commit CI leg said otherwise. Verify-before-close caught it —
`gh run view` on the merge commit's failing leg, not the prompt's prose, was the truth source.

The follow-up fix flipped the row to `expect_green` and added siblings — and the review round then
found the battery's own coverage story was overstated in four directions at once:

- The normalization-collision emit (`no("…collide after normalization")`, added by the same #9970
  fix) had NO row — silently deletable. An add-shape shadow (two SSH resources normalizing to one
  key) is detected nowhere else: the later block overwrites the key and every other diagnostic
  passes. New `M4k` row pins it.
- The SECOND `_norm` call site (`_all_tf_names`, feeding only the twin-base exemption) was
  invisible to the battery — a case/hyphen rename of the non-SSH `deploy_pipeline_fix` twin base
  would over-fire RED if `_norm` were deleted there. New `control-D` green row pins it.
- `M4j`'s label claimed `uncovered + stale` but anchored only `uncovered` — neutering the stale
  arm was battery-invisible. A new optional extra-needle vararg on `expect_red` pins both.
- My own plan claimed "the bare flip drops the landed count to 56 and trips `FLOOR=57`" — a
  decisive-sounding derivation that was wrong: `mutations_run` is also incremented at three
  inline sites (M33b, `_g2_json_row` ×3, G2-C2), so ~75 land and the floor had ~18 slack. The
  sibling row was still correct — for the detection-preservation reason, not the floor reason.

## Solution

- When a fix changes what a mechanism emits, the fix and its pins are one deliverable: grep every
  expected diagnostic against the NEW emit shapes before declaring it done. `control-C` flipped
  to `expect_green` (normalization transparency), `M4j` pins `uncovered`+`stale` (detection not
  swallowed), `M4k` pins the collision emit, `control-D` pins the second `_norm` consumer.
- The scorer already supported multi-needle all-of semantics; the harness passed one. An optional
  vararg after the positional mutator extended `expect_red` without touching 70 existing rows.
- The floor is a derivation ledger, not just a number: comment records `+1 net` and `FLOOR=58`
  stays ~18 under the ~76 landed count, per the file's own convention.
- One finding outranks the PR: the G2 residence check only flags `dials_web_2` outside server.tf —
  a web-1 SSH `terraform_data` in another `.tf` evades the whole classification (filed #9998,
  deferred-scope-out; guard-side, pre-existing, >100 lines).

## Key Insight

Two lessons, both variants of "the pin must reflect the mechanism, not the prose about it":

1. **A mechanism fix can make its own test lie in EITHER direction.** Here the guard got better and
   the battery's `expect_red` turned into a false failure. The merge was "deployed + served" and
   still left a red leg behind — deployment success says nothing about the pin surface.
2. **A decisive-sounding derivation is the most dangerous sentence in a plan.** "The bare flip
   trips the floor" was concrete, checkable, and wrong — `mutations_run` had three more increment
   sites than the planner grepped. Rule of thumb: any plan claim of the form "X causes counter Y
   to reach Z" must name the command that enumerates every contributor to Y, and the plan phase
   must run it. The review panel caught it, which is the pipeline working — but the wrong
   rationale rode into the PR body too, and would have shipped as a false explanation.

## Session Errors

1. **Read `.github/workflows/scheduled-integration-suites.yml` from local `main` — stale.**
   Recovery: fetched, read `origin/main`. **Prevention:** on a repo whose local `main` may lag,
   `git fetch` and read `origin/main` (or `git show`) before asserting file state.
2. **`gh run list --json actor` rejected — unsupported field.** Recovery: queried supported
   fields, fetched actor separately. **Prevention:** run `gh run list --json` queries only with
   fields from the documented set; on `Unknown JSON field` errors, re-query, don't guess.
3. **Dispatched `scheduled-integration-suites.yml` while an identical run was in flight, then
   canceled the duplicate.** Recovery: `gh run cancel` succeeded; the mutex held. **Prevention:**
   before dispatching a mutexed workflow that performs real shared-environment writes, run
   `gh run list --workflow <file> --status in_progress` — in-flight runs are the cancel target,
   not the new dispatch.
4. **Accepted the resume prompt's "#9970 is FIXED" premise provisionally.** Recovery: checked the
   merge commit's CI legs first, found the stale row, converted the close-task into a fix-task.
   **Prevention:** treat resume-prompt status claims as leads, not facts — the merge commit's own
   check suite is the authoritative verdict.
5. **Plan-phase rationale fabricated: "bare flip trips FLOOR=57" was arithmetically wrong.**
   Recovery: git-history fix-round seat re-derived the count; corrected the plan, session-state,
   and PR body. **Prevention:** a plan asserting a counter derivation must include the command
   that derives it (here: `grep -n 'mutations_run=' <file>` or `grep -c 'expect_red'`), and the
   author runs it.
6. **`gh issue create` refused by the filing gate — no milestone, no filing exit.** Recovery:
   re-issued with `--milestone`, `meta/machinery`, and `User-Impact:`/`Fix-Size:` body lines.
   **Prevention:** the gate's refusal message names the three exits; include them on first pass.
7. **`sed`/`awk` on grep-derived line ranges failed on multi-match patterns.** Recovery: read the
   file region directly. **Prevention:** resolve multi-match symbols with `grep -n` first, then
   address by line number or unique context.
8. **`edit` failed on a non-unique `old_string` (a sibling helper had the identical line).**
   Recovery: re-edited with more surrounding context. **Prevention:** before editing a repeated
   call shape, include a distinguishing neighbor line in `old_string`.
