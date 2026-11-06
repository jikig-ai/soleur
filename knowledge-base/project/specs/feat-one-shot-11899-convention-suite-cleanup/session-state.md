# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-03-chore-convention-suite-cleanup-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None. collision-precheck.sh exited 10 reporting only this pipeline's own draft PR #11957 plus unrelated sibling-worktree test-all.sh processes — no competing PR; recorded in the plan's Premise Validation.

### Decisions
- Seam-check strengthening decided concretely: fragment set {MUT_, _SKIP, GUARD, BASH_ENV, SHELLOPTS, BASHOPTS} asserted absent over comment-stripped whole-file view + enclosing-job slice banning GITHUB_ENV/GITHUB_PATH/defaults: — verified clean today (all $GITHUB_ENV writes confined to the `plan:` job).
- Family-wide scope over issue-named subsets: census measured 8 suites missing `if:`/`continue-on-error:` pins, 12 missing pre-battery `fail>0` gate, 5 relative-form `SELF` sites, 6 `MAIN_PLAN` awk overshoots.
- Item 8 floor self-reference → document-and-keep candidate (`pending - assumed:` row for the parent's CTO-ruling batch — the only alternative is a per-suite external constant table failing the "cheap invariant" bound).
- PROMOTED_FILES: consolidation (delete 3 stale sites) + `grep -cE "^PROMOTED_FILES='" == 1` self-pin.
- "Vestigial EXPECT_1" reconciled: compares are live; remedy is rename EXPECT_1→EXPECT_SQL (taste row persisted).

### Components Invoked
- `soleur:plan` (full run), `soleur:plan-review` (sequential-fallback inline panel), `soleur:deepen-plan` (all halt gates)
- Scripts: collision-precheck.sh, precommit-guard.sh, scripts/lint-guard-contract.py
- All fan-outs `Reviewed-Coverage: sequential-fallback` — no independent review ran (subagents cannot spawn on this harness)

## Collision Preflight (post-planning re-probe)
- #11899 OPEN; no linked PRs; merged body-citation only #11885 (predecessor that generated the findings — verified disjoint scope, genuinely new work).
- Anchor probe: open PRs #9745 + #11918 share `scripts/guard-vacuity-floor.test.sh` — pr-overlap-preflight exit 13 (advisory: continue; edit check re-runs before merge).
- Operator Holds section recorded in plan (delegation 6361717901 verified valid to 2026-11-20; all holds stand).

## Technical-Ruling Gate
- cto_spawns=1 (one batched spawn ruled rows 11-16 of decision-challenges.md; gate re-run PASS)
- Corrections applied to plan: suite-run-line job is `deploy-script-tests-fixed:` (infra-validation.yml:847-1353), NOT `validate:` (7 mislabels fixed); census donor is faithful-canary-sandbox CENSUS_* (egress-gw has no census block); Item 8 document-and-keep confirmed with floor-decrease-marker dissent noted.

## Work Phase
- Status: complete — 5-agent Tier B fan-out, disjoint file sets, 15 files edited (14 convention suites + meta-guard)
- Verification: all 15 suites rc=0 post-edit; meta-guard rc=0; MIN_FIRING_SUITES=71 unchanged; shellcheck -S warning clean; landmine sweep clean (no `| grep -q` pipes, no `env -u`, no literal `<<-`, `\x24` escapes used)
- Carry-overs flagged by workers (follow-ups, not blockers): (1) sandbox PRELUDE `Q = chr(39)` is dead (`grep -cw Q`==1) but not in the plan's 7-file dead-Q list — left in place; (2) inngest-524 python-side `main_plan` `re.search(...(?:rc=\$\?|\Z))` has the same run-to-EOF overshoot class — outside the six-carrier scope; (3) MAIN_PLAN terminator asserts pin byte-exact `rc=${PIPESTATUS[0]}` (generic `rc=` would land on `rc=0` at :984 and let delete/rename mutants survive).

## Review Phase
- Panel: 9 seats, 33 findings. Convergent P1: egress-gw missing step pins (4 seats). Convergent mediums: step-pin evasions (dash-line/post-steps/second-if), `^defaults:` file-wide channel, vacuous `ok` on missed slice, PROMOTED_FILES pin shape-bound, inngest-524 python main_plan overshoot, awk dialect divergence.
- CTO dissent spawn: D1 AMENDED — adopt registry-clientip step/job-key allowlist family-wide (fragment set stays); D2 — converge all slice dialects to clientip `hdr()` idiom this PR.
- Fix round: 5 workers, all four slice dialects → clientip idiom; STEP_BAD(name+run)/JOB_BAD(key allowlist); if:/c-o-e at both positions + whole-JOB_BLOCK; file-wide ^defaults:; +6 shape mutation rows per suite; PROMOTED_FILES pin widened to `^[[:space:]]*PROMOTED_FILES[+]?=` + 3 new ARM-11 probes + grading-vacuity fix; step-524 python main_plan terminated on `^[ \t]*rc=` + terminator assert + rc rows; trailing-// strip; dead Q (sandbox, registry-store); EXPECT_SQL in inngest-cutover; mutate_green signature unified; ALERT_PINS got-attr; EMITTER dup row; clientip ambient count-equality restored.
- Re-verified: all 15 suites rc=0 post-fix; shellcheck clean; landmine sweep clean.
