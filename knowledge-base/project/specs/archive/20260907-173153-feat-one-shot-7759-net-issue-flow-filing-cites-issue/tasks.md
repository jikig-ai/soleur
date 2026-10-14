# Tasks — net-issue-flow declared-filing attribution (#7759)

> **Superseded 2026-09-07 (#7896 review):** the "0 of 33" measurement below is FALSE. It classified cited numbers issue-vs-PR by range membership, which cannot work because GitHub issues and PRs share one number space here. Re-measured on `.pull_request`: **21 of 66 cited numbers are PRs and 20 of the 33 issues cite at least one**, over 29 pairs (one being #7710 -> #7702, the case #7759 was filed about). The exemption was under-reached, not inert. Likewise the "16 filing sites / 11 emit no PR number" figure: re-measured as **19 files / 48 invocations**, 14 files with no PR reference. And the `Possible unattributed filings:` mechanism described below was REMOVED in review — it reported numbers it had itself counted. See ADR-155 amendment and ADR-206.

Plan: `knowledge-base/project/plans/2026-09-07-fix-net-issue-flow-filing-cites-issue-plan.md`
Branch: `feat-one-shot-7759-net-issue-flow-filing-cites-issue`
Closes: #7759

Design in one line: the gate **counts** a declared `Filed:`/`Tracks:`/`Refs:` line in the PR body
(produced by `/ship` Phase 6 and carried through its full-replace), and **reports without counting**
any other post-PR issue number the body mentions.

Ordering is load-bearing. Phase 1 (RED) precedes Phase 2 (GREEN) per `cq-write-failing-tests-before`.
Phase 5 (floor ratchet) must follow Phases 1–4, because it reads the post-change assertion count.

## Phase 0 — Preconditions

- [x] 0.1 Confirm baseline: `bash plugins/soleur/test/net-issue-flow.test.sh` prints
      `ALL PASS (84 assertions)` and `MIN_ASSERTIONS=84`.
- [x] 0.2 Stage a pristine pre-change gate for the AC-G4 differential:
      `git show origin/main:plugins/soleur/skills/ship/scripts/net-issue-flow.sh` to a temp path, then
      **`chmod +x`** it (the suite's `[[ ! -x "$GATE" ]]` check exits 1 before any case runs, and that
      RED is indistinguishable from the defect being present). Do NOT use `git stash`
      (`hr-never-git-stash-in-worktrees`).
- [x] 0.3 Re-derive the ADR ordinal with **both** probes — `git ls-tree` across all `origin/*` refs AND
      `git log --all --oneline | grep ADR-<n>`. ADR-205 is free under the first and **claimed** under the
      second (commit `e6d6ec8c5`, unmerged branch), which is why the plan uses **ADR-206**.

## Phase 1 — RED: pin the defect in the suite

Every assertion call site carries its own `cases=$((cases + 1))` — never inside `pass()`/`fail()`,
never inside `$( )`.

- [x] 1.0 **Add the injection seam first.** Change the hardcoded
      `GATE="$REPO_ROOT/plugins/soleur/skills/ship/scripts/net-issue-flow.sh"` to
      `GATE="${NET_ISSUE_FLOW_GATE:-$REPO_ROOT/…}"`, and assert the **unset** default resolves to the
      shipped path — otherwise a stray env var silently redirects the suite, a fail-open in the harness.
- [x] 1.1 **R1** — issue cites the originating issue; PR body carries `Filed: #<issue>` →
      expect `Filing: 1`, `exit 1`.
- [x] 1.2 **R2** — body-attributed issue with `Mandated-By:` + `state: "OPEN"` + `Tracks #N` in the PR
      body → expect counted **and** `exempt`, with `Filing:` unreduced.
- [x] 1.3 **R3** — the always-emitted block carries the declared line's numbers, and separately a
      `possible unattributed filing` line for a prose-only mention; the prose number must NOT appear in
      `Filing:` or affect `NET`.
- [x] 1.4 Confirm every new case is RED against the pre-change gate staged in 0.2, keying on the named
      `FAIL <label>` lines — **not** on the suite's exit status.

## Phase 2 — GREEN: the gate change

`plugins/soleur/skills/ship/scripts/net-issue-flow.sh`.

- [x] 2.1 Derive both sets **inside the existing `jq` pass** from `$pb`. Pass `--arg closing "$CLOSING_NUMS"`.
      **Do NOT build them in bash** — `grep -oE … | jq … || _fail_open` under `set -uo pipefail` makes
      grep's no-match exit 1 fail the gate OPEN on every PR whose body names no issue, and turns the
      deliberately fail-closed unbalanced-fence path into a fail-open. Both measured.
- [x] 2.2 Use the **lookbehind** `(?<![0-9A-Za-z])#([0-9]+)`, not a consuming boundary group — the
      consuming form drops the second member of `#1#2`. Measured.
- [x] 2.3 `DECLARED` = numbers on lines matching `^[ \t\r]*(Filed|Tracks|Refs):?[ \t]+#[0-9]`, minus
      close targets and the PR's own number. This is the only set that counts.
- [x] 2.4 `UNATTRIBUTED` = all other post-PR body references, minus `DECLARED`. Reported only; must
      touch neither `FILED`, `EXEMPT` nor `NET`.
- [x] 2.5 Widen the `select` as a **sibling disjunction** over the same array (body cites PR **or**
      `$declared` contains the number), keeping the `createdAt` guard as a separate conjunct.
- [x] 2.6 Row becomes `[number, verdict, attribution, detail]`; consumer
      `read -r _num _verdict _attr _detail`. Free-text `detail` stays **last**. Update the
      `_emit_as "net-issue-flow-mandated-filing--${_detail}"` safety comment: with the field misordered,
      `_detail` becomes `pr-body` and every exemption is silently re-grouped under
      `net-issue-flow-mandated-filing--pr-body` — still `[a-z0-9-]`-shaped, still past the orphan filter.
- [x] 2.7 Add the `Attributed:` line (derived from the **rows actually counted**, never from the set —
      otherwise the report and the count desynchronise) and the `Possible unattributed filings:` line.
- [x] 2.8 Emit `net-issue-flow-body-attributed` (`applied`) only when the declared arm fired, and a
      distinct id for the conservation report.
- [x] 2.9 Do not touch: the `gh issue list` argv, the `NET > 0` threshold, the override marker, the awk
      fence-strip, the merge-base corpus read, or the `Filing:`-keeps-its-true-count contract.

## Phase 3 — Producer: the declared line in `/ship`

`plugins/soleur/skills/ship/SKILL.md`.

- [x] 3.1 Emit `Filed: #A #B #C` into the Phase 6 body template when the phase filed anything.
- [x] 3.2 Add it as a **third row** to Phase 6's existing carry-forward table — the one that already
      protects `Tracks #N`/`Refs #N` and `<!-- gate-override: net-issue-flow -->` because Phase 6
      full-replaces the body. Without this the line is erased before the gate ever reads it.
- [x] 3.3 Document the declared arm and the conservation line beside the four query properties, which
      stay stated verbatim.

## Phase 4 — Pin the `--json` field list

- [x] 4.1 Add a fifth Case 8 assertion: the `issue list` argv contains `--json` and the field list
      contains `number`, `body`, `createdAt`, `state`. Dropping `createdAt` makes every row fail the
      recency filter → `FILED=0` → **PASS on every PR, silently**, with no prior coverage.

## Phase 5 — Anti-vacuity floor ratchet

- [x] 5.1 Run the suite, read the reported count, set `MIN_ASSERTIONS` **at** it. No slack; ratchets
      upward only (ADR-193). Cut redundant assertions rather than counting them, so the floor measures
      discrimination and not padding.

## Phase 6 — Guard Contract execution

- [x] 6.1 Run the battery with **no** mutation applied and confirm GREEN before trusting any row.
- [x] 6.2 Mutation rows M1–M8 must each RED; for each, confirm the edit landed inside the
      `select`/derivation/`_emit_as` region rather than merely that the file changed.
- [x] 6.3 Harness rows H1–H3 must RED (H1 paired with an induced product defect; H3 **keeps** the floor
      at N and deletes a case); H4–H7 must PASS.
- [x] 6.4 Revert every mutation; confirm the suite returns to green.

## Phase 7 — Documentation

- [x] 7.1 Extend the gate header's "Why the FILED query looks the way it does" with the fifth defect and
      its remedy, and record that `Tracks #N` now both admits a row and satisfies exemption condition 4.
- [x] 7.2 Author `ADR-206-attribute-a-prs-filings-by-the-prs-own-body.md`: the declared/reported split;
      the first-party rationale **and its limit** (a mention is not a filing claim) with the 300-PR
      measurement; `## Alternatives Considered` carrying the sixteen-site producer sweep, the transitive
      widening, keyword-anchoring on free prose, and bare-`#N` counting, each with the measurement that
      rejected it; the supersession of the 2026-09-03 plan §PR 4; the ADR-155 conjunct collapse; the
      `Tracks #NNNN` cite-an-existing-issue interaction and why it self-neutralises; and
      `Known adjacent gaps` for the `/review` `Ref #N` probe.
- [x] 7.3 Amend ADR-155 with `## Amendment — 2026-09-07 (#7759)` recording the measured inertness
      (0 of 33 whole-line `Mandated-By:` issues cite a PR), the revival, and the conjunct collapse. An
      ADR-only note in ADR-206 would leave ADR-155 silently contradicted.
- [x] 7.4 On any ADR renumber, sweep
      `grep -rn 'ADR-206' knowledge-base/project/{plans,specs}/feat-one-shot-7759-*/` in the **same**
      edit — this file carried a stale ordinal after the 205→206 move and the sweep is what caught it.
- [x] 7.5 Add named aggregator fields in `scripts/rule-metrics-aggregate.sh` for both new ids. The
      rollup reads ids by **exact key** and its orphan gate filters the whole `net-issue-flow` prefix, so
      a new id is otherwise write-only telemetry — a mistake that file already documents happening once.

## Phase 8 — Adjacent finding triage

- [x] 8.1 Triage the `/review` `Ref #N` probe inline first (`wg-defer-only-after-inline-triage`). If the
      fix stays inside the cost-of-filing auto-flip (≤100 lines AND ≤4 files, counting this PR's set),
      fold it in; otherwise leave the ADR acknowledgement and file nothing.

## Phase 9 — Verification

- [x] 9.1 AC-G1..AC-G3: suite green, `MIN_ASSERTIONS` exact, `gh issue list` argv byte-unchanged.
- [x] 9.2 AC-G4: R1 red-before / green-after through the seam, keyed on named FAIL lines.
- [x] 9.3 AC-G7: firing fixture emits exactly one `net-issue-flow-body-attributed` row by exact
      `.rule_id` match; clean fixture emits none.
- [x] 9.4 AC-G8: stub-seam runtime delta vs the `origin/main` gate on the same fixture < 200 ms.
      **Measured on the PRIMITIVE, not the whole gate.** Under three concurrent sibling full-gate
      runs the whole-gate harness could not resolve a 200 ms budget: a batched A/B reported the new
      gate 295 ms FASTER and an interleaved A/B reported it 346 ms SLOWER — a sign flip, on a change
      that strictly adds work, with a per-arm spread of ~1237 ms swamping both the effect and the
      budget. Timing the jq pass that actually changed (25 reps x 3 interleaved rounds, 500-issue
      fixture) gives new 11-12 ms vs old 9 ms: **+2 to +3 ms**, spread ~1 ms, sign physically
      correct. That is the number; the whole-gate figures are discarded as unresolvable.
- [x] 9.5 AC-G9: `git diff --stat origin/main -- .claude/hooks/ship-net-issue-flow-gate.sh` empty and the
      four `hook remedy needle` assertions pass.
- [x] 9.6 Assert the declared `Filed:` line survives a Phase 6 body regeneration.
- [x] 9.7 Verify every `knowledge-base/` citation in the plan resolves.
- [x] 9.8 **AC-D1 (dogfooding).** Run the gate against this PR; expect
      `Closing: 1 (#7759) / Filing: 0 / Net: -1 / PASS`. Then **hand-reproduce the FILED selector**
      against the live issue list rather than trusting the verdict — a fix PR that passes by exploiting
      its own defect is the one outcome this plan must not produce.
- [x] 9.9 AC-D2: PR body carries `Closes #7759` (body, not title).
