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

- [x] 1.0 **Add a `pgit()` fixture-git wrapper** running under `GIT_CONFIG_GLOBAL=/dev/null
      GIT_CONFIG_SYSTEM=/dev/null`, and route all new arms through it. `state()`/`classify_in()` already pin
      those; the *fixture mutations* do not, which is why arm 36 needs `-c tag.gpgSign=false`. Arms 47/48 create
      commits and would break on any machine with global commit signing. **Do NOT** set `commit.gpgsign=false`
      in `new_probe` — arm 4 writes exactly that key as its fixture and would go vacuous.
- [x] 1.1 Each arm hard-fails fixture setup with a named message the way arm 36 does at `:649-651`, rather than
      falling through to a misleading assertion failure. Note `tag.forceSignAnnotated` governs **annotated**
      tags — it is the must-PASS annotated-tag case that needs it, not the lightweight one.
- [x] 1.2 Every new assertion is **end-anchored** (`\(tag\) was created$`). Un-anchored, it prefix-matches
      today's `was created or moved` and passes vacuously pre-fix. This is the difference between a real RED
      and a fake one.
- [x] 1.3 **Tighten arm 36 in place** (do not add a twin): assertion becomes
      `^FATAL[[:space:]]+refs.*probe-tag \(tag\) was created$` on its existing no-sibling `new_probe` fixture.
- [x] 1.4 **Arm 45** — sibling + tag created, collision-free name ⇒ exactly one
      `^REPORT[[:space:]]+refs.*\(tag\) was created$` and zero `^FATAL`. Assert the line is *present*, never
      merely that FATAL is absent. **Fails today.**
- [x] 1.5 **Arm 46** — sibling + tag deleted ⇒ `^FATAL[[:space:]]+refs.*probe-tag.*DELETED`, copying arm 40's
      anchor shape at `:774` (named ref + scoped negative). A bare `^FATAL[[:space:]]+refs` matches the sibling
      branch line and passes vacuously. Closes a real gap: no arm exercises tag deletion today.
- [x] 1.6 **Arm 47** — sibling + one created and one moved tag in the same run ⇒ exactly one `REPORT` and one
      `FATAL`, each naming its own tag. **Fails today.**
- [x] 1.7 **Arm 48** — sibling + tag created **and** default branch moved in the same run ⇒ two `REPORT`, zero
      `FATAL` (scope the negative to `^FATAL[[:space:]]+refs`). This is the measured incident shape (the bot
      merge moved `main` and published `v3.258.3`). **Fails today.**
- [x] 1.7b **Arm 49 — the collision guard.** Sibling + a created tag named `origin/main` ⇒ `FATAL`; and one
      named `$default_branch` ⇒ `FATAL`. `refs/tags/<n>` resolves ahead of `refs/heads/<n>` and
      `refs/remotes/<n>`, and `test-all.sh:780`/`:794` plus `/work`, `/qa`, `/ship` all resolve the bare
      `origin/main`. Without this arm the softening lets a pure creation silently rescope every later gate.
- [x] 1.7c **Arm 50 — the epilogue wiring.** Drive the sandboxed runner the way arms 23/24/26 do; assert a
      REPORT-only run exits 0 and a FATAL run exits 1. Every other arm asserts classifier stdout only, while
      property P1 is about the exit code and the Guard Contract's Assembly claims `test-all.sh:2217`/`:2406`.
- [x] 1.8 Raise `MIN_ASSERTIONS` from 44 by the number of new arms — **52** as landed (arms 45-52; the
      plan projected 50 for 45-50, and /work added arm 51 for the Guard Contract's *Fail-open input*
      mutation row and arm 52 for its *must-PASS annotated tag* harness row, both of which the arm list
      had missed). Derive it; never carry the literal.
- [x] 1.9 Confirm arm 43 is untouched and still green after the Phase 2 change.

## Phase 2 — GREEN: the classifier

All edits in `scripts/lib/repo-write-boundary.sh`.

- [x] 2.1 Split the `refs/tags/*)` arm of the created-or-moved loop (`:506-507`) on `bsha`:
      created + `shared_store` + collision-free ⇒ `REPORT`; created without `shared_store` ⇒ `FATAL`;
      moved ⇒ `FATAL`. Mirror the canonical `"refs/heads/$default_branch")` arm at `:510-515` (same
      `if [[ -n "$shared_store" ]]` test, same REPORT/FATAL ordering, same naming of the producing shape).
- [x] 2.1b **The collision guard.** Keep `FATAL` when the tag's short name equals `own_short` (`:382`), equals
      `$default_branch` (`:372`), appears in `elsewhere` (`:380`), or contains a `/`. Costs nothing: 3054 tags
      in this repo, zero contain a `/`, none is named `main`/`master`/`HEAD`/`origin`.
- [x] 2.1c **Fail-closed input.** In `_repo_boundary_branches_elsewhere` (`:302`), change
      `|| here=""` to `|| return 1`. As written, an unreadable toplevel makes every branch read as `elsewhere`
      and manufactures `shared_store=1`. `_repo_state:270` already routes a non-zero return to
      `wt: not-measured`, which arm 44 proves withholds the softening.
- [x] 2.2 Emit distinct details `(tag) was created` / `(tag) was moved`. Leave the three non-tag
      `created or moved` strings at `:519`, `:521`, `:523` alone — they are out of scope.
- [x] 2.3 Leave the deleted loop's `refs/tags/*|"$own_branch")` arm (`:489`) unchanged.
- [x] 2.4 Replace the stale comment `tags too, since sibling traffic does not routinely move them`.
- [x] 2.5 Correct `_repo_boundary_dim_refs`'s `--heads --tags` rationale (`:200-201`): it justifies excluding
      `refs/remotes/**` as "a fetch is the only thing that writes it" without noting a fetch also writes
      `refs/tags/**` — the incompleteness that left tags at full strength.
- [x] 2.6 Record at the new arm, all four: the reversed #7652 premise + `worktree-manager.sh:2731`; the
      fail-closed asymmetry (a `+refs/tags/*` refspec or `fetch.pruneTags` yields a false FATAL, never a
      laundered pass); the `git-data-client.ts:244` graft residual; and that `-z "$bsha"` means *absent from
      the BEFORE measurement*, not *did not exist*.

## Phase 3 — remove the two battery-reachable tag authors we can close cheaply

- [x] 3.1 `scripts/plugin-delivery-canary.sh:335` — confirm no downstream consumer needs tags (the fetch exists
      only to make `$sha` available to `git archive`), then add `--no-tags`. Assert it in
      `plugin-delivery-canary.test.sh` (its own counter), anchored on the specific fetch command.
- [x] 3.2 `apps/web-platform/scripts/run-migrations.sh:200` — same. Battery-reachable via
      `run-migrations-schema-probe.test.sh`, which copies the script to a tmp dir and runs it **without `cd`**,
      so the unconditional fetch hits the live repo. Assert it in that suite (its own counter).
- [x] 3.3 Do **not** touch `lint-migration-fk-preconditions.sh` — its fetch is gated behind `--from-pr-diff`,
      which only `.github/workflows/tenant-integration.yml:145` passes; genuinely not battery-reachable.
- [x] 3.4 Do **not** put either assertion in `repo-write-boundary.test.sh` — sharing its `MIN_ASSERTIONS` is the
      shape this plan cut Guard 2 for.

## Phase 4 — the ADR

- [x] 4.1 Re-derive the next free ADR ordinal across **every** `origin/*` ref, not just `origin/main`.
- [x] 4.2 Write `ADR-<n>-repo-write-boundary-harm-partition.md`: the FATAL/REPORT/UNMEASURABLE partition and its
      attribution-not-severity rationale; the measurement invariant (classification inputs come from the BEFORE
      snapshot, never re-derived at classify time); and an **exemption ledger** of all three exemptions with the
      evidence for each, so a fourth request is visibly the fourth.
- [ ] 4.3 Re-verify the ordinal immediately before merge and sweep this branch's plan + tasks if it moved.

## Phase 5 — deferrals and verification

- [x] 5.1 File three tracking issues with their triggers (plan §Non-Goals): the battery tag-author sweep
      (root set from `scripts/test-all.sh --print-suite-globs`, built RED-first, own assertion counter,
      `-B2` in its AC); the graft residual; per-suite snapshotting + the `render_not_inspected` heredoc debt.
      Link all three in the PR body.
- [x] 5.2 Add the precision note to
      `knowledge-base/project/learnings/2026-08-27-i-committed-the-defect-class-i-was-closing-eleven-times.md`
      where it says arms 42-43 stop sibling presence laundering "a tag" — arm 43 tests a tag **move**.
- [x] 5.3 `bash scripts/lib/repo-write-boundary.test.sh` — `0 failed`, floor 50.
- [x] 5.4 `bash scripts/guard-vacuity-floor.test.sh`
- [x] 5.5 `bash scripts/plugin-delivery-canary.test.sh`
- [x] 5.6 `bash plugins/soleur/test/c4-count-parity.test.sh`
- [x] 5.7 `python3 scripts/lint-guard-contract.py` and `python3 scripts/lint-infra-no-human-steps.py` on the plan
- [ ] 5.8 `TEST_GROUP=scripts bash scripts/test-all.sh` — exit 0, no `[FATAL]` boundary block
- [ ] 5.9 Walk the plan's §Acceptance Criteria 1-16 and record each result.
