---
title: "Tasks — repo-write-boundary tag shared_store softening"
branch: feat-one-shot-7795-tag-shared-store-softening
issue: 7795
lane: cross-domain
plan: knowledge-base/project/plans/2026-09-07-fix-repo-write-boundary-tag-shared-store-softening-plan.md
---

# Tasks

Derived from the finalized (post-plan-review) plan. Read the plan's §Defense Relaxation Analysis before
starting: the softening's safety rests on a residual this PR deliberately does **not** close, and the plan must
not be re-described as closing it.

## Phase 1 — RED: pin the partition before changing it

All edits in `scripts/lib/repo-write-boundary.test.sh`. Use the existing `sibling_probe()` / `new_probe()` /
`state()` / `classify_in()` helpers; never mock `_repo_boundary_branches_elsewhere`.

- [ ] 1.1 Every arm that writes a tag carries `-c tag.gpgSign=false` (plus `-c tag.forceSignAnnotated=false`
      where it creates a lightweight tag), and hard-fails fixture setup with a named message the way arm 36
      does at `:649-651`. The global gitconfig forces signed/annotated tags.
- [ ] 1.2 Every new assertion is **end-anchored** (`\(tag\) was created$`). Un-anchored, it prefix-matches
      today's `was created or moved` and passes vacuously pre-fix. This is the difference between a real RED
      and a fake one.
- [ ] 1.3 **Tighten arm 36 in place** (do not add a twin): assertion becomes
      `^FATAL[[:space:]]+refs.*probe-tag \(tag\) was created$` on its existing no-sibling `new_probe` fixture.
- [ ] 1.4 **Arm 45** — sibling + tag created ⇒ exactly one `^REPORT[[:space:]]+refs.*\(tag\) was created$` and
      zero `^FATAL`. Assert the line is *present*, never merely that FATAL is absent. **Fails today.**
- [ ] 1.5 **Arm 46** — sibling + tag deleted ⇒ `^FATAL[[:space:]]+refs.*was DELETED`. Closes a real gap: no arm
      exercises tag deletion today.
- [ ] 1.6 **Arm 47** — sibling + one created and one moved tag in the same run ⇒ exactly one `REPORT` and one
      `FATAL`, each naming its own tag. **Fails today.**
- [ ] 1.7 **Arm 48** — sibling + tag created **and** default branch moved in the same run ⇒ two `REPORT`, zero
      `FATAL`. This is the measured incident shape (the bot merge moved `main` and published `v3.258.3`).
      **Fails today.**
- [ ] 1.8 Raise `MIN_ASSERTIONS` 44 → 49 (`:851`).
- [ ] 1.9 Confirm arm 43 is untouched and still green after the Phase 2 change.

## Phase 2 — GREEN: the classifier

All edits in `scripts/lib/repo-write-boundary.sh`.

- [ ] 2.1 Split the `refs/tags/*)` arm of the created-or-moved loop (`:506-507`) on `bsha`:
      created + `shared_store` ⇒ `REPORT`; created without ⇒ `FATAL`; moved ⇒ `FATAL`.
- [ ] 2.2 Emit distinct details `(tag) was created` / `(tag) was moved`. Leave the three non-tag
      `created or moved` strings at `:519`, `:521`, `:523` alone — they are out of scope.
- [ ] 2.3 Leave the deleted loop's `refs/tags/*|"$own_branch")` arm (`:489`) unchanged.
- [ ] 2.4 Replace the stale comment `tags too, since sibling traffic does not routinely move them`.
- [ ] 2.5 Correct `_repo_boundary_dim_refs`'s `--heads --tags` rationale (`:200-201`): it justifies excluding
      `refs/remotes/**` as "a fetch is the only thing that writes it" without noting a fetch also writes
      `refs/tags/**` — the incompleteness that left tags at full strength.
- [ ] 2.6 Record at the new arm, all four: the reversed #7652 premise + `worktree-manager.sh:2731`; the
      fail-closed asymmetry (a `+refs/tags/*` refspec or `fetch.pruneTags` yields a false FATAL, never a
      laundered pass); the `git-data-client.ts:244` graft residual; and that `-z "$bsha"` means *absent from
      the BEFORE measurement*, not *did not exist*.

## Phase 3 — remove the one battery-reachable author we can close cheaply

- [ ] 3.1 Verify no downstream consumer of `scripts/plugin-delivery-canary.sh:335` needs tags (the fetch exists
      only to make `$sha` available to `git archive`), then add `--no-tags`.
- [ ] 3.2 **Arm 49** asserts that flag is present.
- [ ] 3.3 Do **not** touch `lint-migration-fk-preconditions.sh` or `run-migrations.sh` — verified not
      battery-reachable, and the latter is release-path code.

## Phase 4 — the ADR

- [ ] 4.1 Re-derive the next free ADR ordinal across **every** `origin/*` ref, not just `origin/main`.
- [ ] 4.2 Write `ADR-<n>-repo-write-boundary-harm-partition.md`: the FATAL/REPORT/UNMEASURABLE partition and its
      attribution-not-severity rationale; the measurement invariant (classification inputs come from the BEFORE
      snapshot, never re-derived at classify time); and an **exemption ledger** of all three exemptions with the
      evidence for each, so a fourth request is visibly the fourth.
- [ ] 4.3 Re-verify the ordinal immediately before merge and sweep this branch's plan + tasks if it moved.

## Phase 5 — deferrals and verification

- [ ] 5.1 File three tracking issues with their triggers (plan §Non-Goals): the battery tag-author sweep
      (root set from `scripts/test-all.sh --print-suite-globs`, built RED-first, own assertion counter,
      `-B2` in its AC); the graft residual; per-suite snapshotting + the `render_not_inspected` heredoc debt.
      Link all three in the PR body.
- [ ] 5.2 Add the precision note to
      `knowledge-base/project/learnings/2026-08-27-i-committed-the-defect-class-i-was-closing-eleven-times.md`
      where it says arms 42-43 stop sibling presence laundering "a tag" — arm 43 tests a tag **move**.
- [ ] 5.3 `bash scripts/lib/repo-write-boundary.test.sh` — `0 failed`, floor 49.
- [ ] 5.4 `bash scripts/guard-vacuity-floor.test.sh`
- [ ] 5.5 `bash scripts/plugin-delivery-canary.test.sh`
- [ ] 5.6 `bash plugins/soleur/test/c4-count-parity.test.sh`
- [ ] 5.7 `python3 scripts/lint-guard-contract.py` and `python3 scripts/lint-infra-no-human-steps.py` on the plan
- [ ] 5.8 `TEST_GROUP=scripts bash scripts/test-all.sh` — exit 0, no `[FATAL]` boundary block
- [ ] 5.9 Walk the plan's §Acceptance Criteria 1-16 and record each result.
