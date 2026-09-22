# Tasks — feat-one-shot-8292-roadmap-fog-blocking

Plan: `knowledge-base/project/plans/2026-09-22-feat-product-roadmap-fog-and-native-blocking-plan.md`
Issue: #8292 (closes only this). Draft PR: #8536. Never run `scripts/test-all.sh`; commit with
`LEFTHOOK_EXCLUDE=bun-test`.

## Phase 0 — Preconditions (no writes to shipped files)

- [ ] 0.1 `gh --version` >= 2.94.0; `GH_DEBUG=api gh issue list --state open --limit 1 --json number,assignees,blockedBy 2>&1 | grep -c 'state,repository'` >= 1.
- [ ] 0.2 Baselines: `wc -c plugins/soleur/skills/plan/SKILL.md` (119,300); `bash plugins/soleur/test/roadmap-reconcile.test.sh`; `bun test plugins/soleur/test/components.test.ts`.
- [ ] 0.3 `SCRATCH=$(mktemp -d)`; capture milestones once to `$SCRATCH/ms.json`; `git show origin/main:knowledge-base/product/roadmap.md > $SCRATCH/roadmap-before.md`.

## Phase 1 — Script, tests first (own commit)

- [ ] 1.1 Add TS8, TS8c-e, TS9-TS12, TS11b, TS13-TS17 (fake `gh` on `PATH` for TS13-TS16), extend TS7; guard with `declare -F`; capture exit codes with `rc=0; out=$(...) || rc=$?`. Confirm red for the right reason.
- [ ] 1.2 `_milestones_json` projects `state`; add `pick_phase` (open `^Phase [0-9]+[:( ]`, `open_issues > 0`, numeric sort; one jq pass).
- [ ] 1.3 Add `filter_frontier` → `{frontier, blocked, claimed}` in one jq pass; blocker resolved only on `state == "CLOSED"`; hold back when `totalCount > (nodes|length)`; defensive `has("blockedBy") and has("assignees")` check returns 2.
- [ ] 1.4 Rewrite `main next`: `--frontier` flag (other args → 64); `--limit 1000`; `if ! issues=$(gh ... 2>"$errf")` → exit 2, `Unknown JSON field` → "requires gh >= 2.94.0"; render summary-first `--frontier` output, single-pass classification; NONE keeps phase + counts; usage `[validate|next [--frontier]]`.
- [ ] 1.5 Suite green. Live read-only (informational): `next` names a Phase 4 issue; `next --frontier` lists it first.
- [ ] 1.6 Commit `fix(product-roadmap): next picks from the live phase and the unblocked frontier` (body names the Phase-5 mis-selection and 30-issue truncation).

## Phase 2 — product-roadmap SKILL.md (about +45 lines, description unchanged)

- [ ] 2.1 Sub-commands `next` row; `### Sub-command: next` paragraph + both commands + argument pass-through.
- [ ] 2.2 `## Where Work Lives on the Roadmap` with the attribution comment first: four-places table, `### Not Yet Specified` (test + "can you write the issue title today?" gloss), `### Out of Scope`, `### Blocking Edges`.
- [ ] 2.3 Workshop `### 1.6 Fog and Scope Walk`; Phase 2 required sections; Phase 3 one-sentence pointer; Headless Mode D8 sentence.

## Phase 3 — roadmap.md, plan note, NOTICE

- [ ] 3.1 roadmap.md: `## Not Yet Specified` and `## Out of Scope` (bullet lists, `_None recorded._`) between `### Post-MVP / Later` and `## Pricing`; bump `last_updated` only.
- [ ] 3.2 plan/SKILL.md: the ~210-byte note after the Phase 0.7 "Stub no conditional section" paragraph; `wc -c` < 120000; `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`.
- [ ] 3.3 NOTICE: `skills/product-roadmap/SKILL.md (#8292)` in `Used in:`; Bundle 5 paragraph (~8 lines).
- [ ] 3.4 Diff `reconcile_counts $SCRATCH/roadmap-before.md $SCRATCH/ms.json` vs the edited roadmap.md against the same snapshot: identical.

## Phase 4 — Verification

- [ ] 4.1 Constrained dry run: subagent gets only the new prose + 3 synthetic cases + one sharp-but-blocked question; lists unfollowable sentences; rewrite each.
- [ ] 4.2 Shingle check via the plan's `bun -e` command against wayfinder at the pinned SHA.
- [ ] 4.3 Targeted suites: `roadmap-reconcile.test.sh`, `components.test.ts`, `plan-skeleton-checkpoint.test.ts`, `devin-cloud-mode.test.ts`, skill-body-budget lint.
- [ ] 4.4 Check AC1-AC12.

## Phase 5 — PR

- [ ] 5.1 PR body: `Closes #8292` only; live API verdict; the two folded-in `next` defects; line-count restatement; dry-run summary; `Filed:` line (expected none); decision-challenges rendered by ship.
