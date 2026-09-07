# Tasks — net-issue-flow PR-body attribution arm (#7759)

Plan: `knowledge-base/project/plans/2026-09-07-fix-net-issue-flow-filing-cites-issue-plan.md`
Branch: `feat-one-shot-7759-net-issue-flow-filing-cites-issue`
Closes: #7759

Ordering is load-bearing. Phase 1 (RED) precedes Phase 2 (GREEN) per `cq-write-failing-tests-before`.
Phase 4 (floor ratchet) must follow Phase 1 and 2, because it reads the post-change assertion count.

## Phase 0 — Preconditions

- [ ] 0.1 Confirm baseline: `bash plugins/soleur/test/net-issue-flow.test.sh` prints
      `ALL PASS (84 assertions)` and `MIN_ASSERTIONS=84`.
- [ ] 0.2 Stage a pristine copy of the pre-change gate for the both-directions proof in AC-G4:
      `git show origin/main:plugins/soleur/skills/ship/scripts/net-issue-flow.sh` written to a temp
      path. Do NOT use `git stash` — forbidden in worktrees (`hr-never-git-stash-in-worktrees`).
- [ ] 0.3 Re-verify the ADR-205 ordinal is still free across all `origin/*` refs.

## Phase 1 — RED: pin the defect in the suite

Every assertion call site carries its own `cases=$((cases + 1))` — never inside `pass()`/`fail()`,
never inside `$( )`.

- [ ] 1.1 **R1** — issue cites the originating issue, PR body names it → expect `Filing: 1`, `exit 1`.
- [ ] 1.2 **R2** — body-attributed issue with `Mandated-By:` + `state: "OPEN"` + `Tracks #N` in the PR
      body → expect `exempt`, with `Filing:` unreduced.
- [ ] 1.3 **R3** — issue whose `title` cites the PR and whose body does not → expect counted.
- [ ] 1.4 **R4** — the always-emitted block carries an `Attributed:` line naming the numbers.
- [ ] 1.5 Bounding cases: named-but-created-before-the-PR; named only inside a fence; named via a close
      keyword (assert the `NET` arithmetic, not just the count); the PR's own number in its own body.
- [ ] 1.6 Multiplicity case: two body-attributed issues, first compliant → both counted.
- [ ] 1.7 Control cases: all-filings-cite-the-PR → `NET` identical to pre-change **and** no
      `net-issue-flow-body-attributed` telemetry row; PR body names a number absent from the issue list
      → no crash, no fail-open, not counted.
- [ ] 1.8 Confirm every new case is RED against the pre-change gate from 0.2.

## Phase 2 — GREEN: the gate change

Single file: `plugins/soleur/skills/ship/scripts/net-issue-flow.sh`.

- [ ] 2.1 Derive `ALL_REFS_JSON` from `PR_BODY_SCAN` (the already-fence-stripped body — do not re-strip
      and never read raw `PR_BODY`), `CLOSING_JSON` from `CLOSING_NUMS`, then
      `NAMED_JSON = $a - $c - [PR_NUMBER]`.
- [ ] 2.2 Give each new failure branch its own `_fail_open` message and its own rule id under
      `net-issue-flow-body-attribution-*`.
- [ ] 2.3 Add `title` to the `--json` field list: `--json number,title,body,createdAt,state`.
- [ ] 2.4 Widen the `select` as a **sibling disjunction** over the same array (body cites PR **or**
      title cites PR **or** `$named` contains the number), with `--argjson named "$NAMED_JSON"`. Keep
      the `createdAt` guard first, governing all three arms.
- [ ] 2.5 Change the row to `[number, verdict, attribution, detail]` and the consumer to
      `while IFS=$'\t' read -r _num _verdict _attr _detail`. Free-text `detail` stays **last**.
- [ ] 2.6 Add the conditional `Attributed:` report line; keep `Filing:` as the true total.
- [ ] 2.7 Emit `net-issue-flow-body-attributed` (`applied`) only when the arm attributed ≥1 issue.
- [ ] 2.8 Do not touch: the `NET > 0` threshold, the override marker, the fence-strip, the merge-base
      corpus read, or the `lint-rule-bodies.py` derivation.

## Phase 3 — Exemption revival (verification only, no code)

- [ ] 3.1 Confirm via R2 that a body-attributed row flows through the unchanged verdict ladder and is
      subtracted from `NET` while `Filing:` keeps its true count.

## Phase 4 — Anti-vacuity floor ratchet

- [ ] 4.1 Run the suite, read the reported assertion count, set `MIN_ASSERTIONS` **at** that number.
      No slack, no rounding down; the floor ratchets upward only (ADR-193).

## Phase 5 — Guard Contract execution

- [ ] 5.1 Run mutation rows M1–M7; record the observed verdict per row. All must RED.
- [ ] 5.2 Run harness rows H1–H3 (must RED) and H4–H5 (must PASS). Record verdicts.
- [ ] 5.3 Revert every mutation and confirm the suite returns to green.

## Phase 6 — Documentation

- [ ] 6.1 `plugins/soleur/skills/ship/SKILL.md` — document the attribution arm; keep all four query
      properties stated verbatim.
- [ ] 6.2 Extend the gate script's "Why the FILED query looks the way it does" header with the fifth
      defect and its remedy.
- [ ] 6.3 Author `ADR-205-attribute-a-prs-filings-by-the-prs-own-body.md` with: the two-arm attribution
      model; `## Alternatives Considered` carrying both rejected options with the measurement that
      rejected each; the supersession of the 2026-09-03 plan's §PR 4; the measured inertness of
      ADR-155's exemption and its revival; and a `Known adjacent gaps` section for the `/review`
      `Ref #N` probe that is dark against its own producer.
- [ ] 6.4 On any ADR renumber, sweep `grep -rn 'ADR-205' knowledge-base/project/{plans,specs}/feat-one-shot-7759-*/`
      in the **same** edit.

## Phase 7 — Adjacent finding triage

- [ ] 7.1 Triage the `/review` `Ref #N` probe inline first (`wg-defer-only-after-inline-triage`). If the
      fix stays inside the cost-of-filing auto-flip (≤100 lines AND ≤4 files, counting this PR's file
      set), fold it in; otherwise leave the ADR acknowledgement and file nothing.

## Phase 8 — Verification

- [ ] 8.1 AC-G1..AC-G3: suite green, `MIN_ASSERTIONS` exact, four call-shape properties intact.
- [ ] 8.2 AC-G4: R1 red-before / green-after, both directions demonstrated.
- [ ] 8.3 AC-G8: measure gate wall clock; confirm it stays well inside the hook's 25 s ceiling.
- [ ] 8.4 AC-G9: `git diff --stat origin/main -- .claude/hooks/ship-net-issue-flow-gate.sh` is empty and
      the four `hook remedy needle` assertions pass.
- [ ] 8.5 AC-G12: no broken `knowledge-base/` citation in the plan.
- [ ] 8.6 **AC-D1 (dogfooding).** Run the gate against this PR; expect
      `Closing: 1 (#7759) / Filing: 0 / Net: -1 / PASS`. Then **hand-reproduce the FILED selector**
      against the live issue list rather than trusting the verdict. If any issue was filed after all,
      its body must cite this PR's number and the hand-reproduction must confirm the gate sees it.
- [ ] 8.7 AC-D2: PR body carries `Closes #7759` (body, not title).
