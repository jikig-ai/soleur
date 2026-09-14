# Tasks: chore — rule-ladder re-scope + migration tranche 2 (#8030, PR #8175)

Plan: `knowledge-base/project/plans/2026-09-14-chore-rule-ladder-rescope-migration-tranche-2-plan.md`

## Phase 1: Setup and baselines

- [ ] 1.1 `git fetch -q origin main && BASE=$(git merge-base origin/main HEAD)` (every absolute AC number is relative to `$BASE`, not `origin/main`); record `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` (expect `[OK] B_ALWAYS=43343`), `grep -c '^- \[id:' AGENTS.md` (100), `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.rules.md` (13 hook + 26 skill / 27 anchor), `grep -cE '^[0-9a-f]{64}' .claude/rule-body-hashes.txt` (74), `jq '.summary' knowledge-base/project/rule-metrics.json` (`rules_unused_over_8w: 81`) — these are the PR-body "before" lines.
- [ ] 1.2 Confirm both candidates carry no `[mandates-filing]` marker (`grep -c 'mandates-filing' <<< "$(grep -F '[id: hr-before-shipping-ship-phase-5-5-runs]' AGENTS.rules.md; grep -F '[id: hr-new-skills-agents-or-user-facing]' AGENTS.rules.md)"` → 0) and no test pins (`git grep -l -e hr-before-shipping-ship-phase-5-5-runs -e hr-new-skills-agents-or-user-facing -- plugins/soleur/test tests 'scripts/*.test.sh' '.claude/hooks/*.test.sh'` → empty).
- [ ] 1.3 Read the destination headings once: `grep -n '^### Pre-Ship Domain Review (conditional)' plugins/soleur/skills/ship/SKILL.md`; `grep -n '^## ' plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` (insert the new H2 above `## User-Brand-Critical Tag Processing`, never at/below `## Lane Inference`).

## Phase 2: Deliverable C — placement guard (RED first)

- [ ] 2.1 Write `scripts/lint-migrated-rule-ids.test.sh` with the 10 matrix rows as named cases, each on a `--root <mktemp -d> --min-rows 1` fixture (plain directories, never `git init`); case-count floor `CASES >= 10`; per-case `rc` assertion. H1/H2 are manual suite mutations run once and quoted in the PR body. Run it: every RED row must currently FAIL because the guard does not exist (RED phase).
- [ ] 2.2 Write `scripts/lint-migrated-rule-ids.sh` (`--root <dir>`, default repo root; `--min-rows N`, default 7): parse `scripts/migrated-rule-ids.txt` rows (`id | date | PR | path :: heading`, `#` and blank skipped), for each row assert (a) exact heading line exists in `path` (`grep -Fx`), (b) the `[id: <id>]` body line sits inside that heading's section — fence-aware awk that closes the section only on a heading of equal-or-higher level outside ``` fences, (c) `[id: <id>]` absent from `AGENTS.rules.md`, (d) a `^<id>[[:space:]]*\|` row exists in `scripts/retired-rule-ids.txt`; reverse: every file under `$ROOT/plugins/` found by plain `grep -rlF` (never `git grep` — fixtures are not repos and lefthook exports `GIT_DIR` in linked worktrees) containing the exact literal ``— migrated out of `AGENTS.rules.md` on`` names only ids with a registry row; floor `rows_checked >= MIN_ROWS` (comment: floor is the measured count, same convention as `MIN_CHECKS`); use `if grep -qF …` forms only (never `n=$(grep -c …) || echo 0`) and run `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`; print `OK: N row(s) checked`.
- [ ] 2.3 Run the test suite → 10/10 green; mutation-verify by hand once (comment out the heading-range check → row 1 must fail).
- [ ] 2.4 Wire: two `run_suite` lines in `scripts/test-all.sh` beside the enforcement-tags pair (`scripts/lint-migrated-rule-ids-live`, `-unit`); `lefthook.yml` pre-commit command `migrated-rule-ids-lint` with glob `scripts/migrated-rule-ids.txt`, `scripts/retired-rule-ids.txt`, `AGENTS.rules.md`, `plugins/soleur/**/*.md`, `scripts/lint-migrated-rule-ids.sh`.

## Phase 3: Deliverable B — migration tranche 2 (one commit)

- [ ] 3.1 Append two rows to `scripts/retired-rule-ids.txt` (tranche-1 wording, date 2026-09-14, `#8175`, home path + heading).
- [ ] 3.2 Append two rows to `scripts/migrated-rule-ids.txt` (`<id> | 2026-09-14 | #8175 | <path> :: <heading>`) and the four header paragraphs from plan step 10 (`# Candidate test (bind-vs-check)`; `# Per-rule checklist (one commit)` steps 1–9; `# Placement is checked by …`; `# Reversal …`).
- [ ] 3.3 Append two `DELETED` ack rows to `.claude/rule-weakening-acks.txt` (`<id>|DELETED|2026-09-14|8175|<reason>`).
- [ ] 3.4 Add both ids to `HR_RETIREMENT_ALLOWLIST` in `scripts/lint-rule-ids.py` under a `# Tranche 2 migration (2026-09-14, #8175)` comment.
- [ ] 3.5 Insert the two callouts (banner + verbatim body, list marker dropped, tags intact): ship `### Pre-Ship Domain Review (conditional)` (after the heading's intro paragraph, before `### CMO Content-Opportunity Gate`); new `## New-capability leader mandate` H2 in `brainstorm-domain-config.md` whose banner uses the references-file wording from plan step 2 ("inside a domain sweep, and every sweep — brainstorm Phase 0.5, plan Phase 2.5 Step 1, product-roadmap — reads this file first"). Update ship's emit sentence ("see AGENTS.md …" → "see the migrated rule callout … below").
- [ ] 3.6 Delete the two body lines from `AGENTS.rules.md` and the two `- [id: …]` lines from `AGENTS.md`; replace the `cq-agents-md-tier-gate` line with the A11 text (596 B).
- [ ] 3.7 `python3 scripts/lint-rule-bodies.py --write` (manifest → 72 hash lines).
- [ ] 3.8 Measure `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.rules.md`; set `MIN_CHECKS` to the measured `skill_units`/`anchor_checks` (expected 24/25) with the tranche-2 comment; mirror in `scripts/lint-agents-enforcement-tags.test.sh` T1.
- [ ] 3.9 Verify every governance gate (AC7, AC8, AC13) and the budget (AC1 `[OK] B_ALWAYS=42640`); commit all of Phase 2 + 3 together.

## Phase 4: Deliverable A — ladder re-scope (12 sites)

- [ ] 4.1 `plugins/soleur/skills/compound/SKILL.md`: A1 WARN ladder bullets (Migrate / Trim / Retire-on-editorial-judgment + `not retirement evidence` sentence), A2 "for the informational hint below", A3 the single-line `[INFO] $unused rules recorded no ENFORCEMENT event …` echo (no `/soleur:sync rule-prune`), A10 placement-gate Already-enforced bullet.
- [ ] 4.2 `scripts/lint-agents-rule-budget.py`: A4 comment block + `remediation` string; run `bash scripts/lint-agents-rule-budget.test.sh`.
- [ ] 4.3 `plugins/soleur/skills/plan/SKILL.md` A5 and A12 (retirement-cleanup sweep excludes migrated ids); `plugins/soleur/skills/deepen-plan/SKILL.md` A6 and A9 (migrated-id check before the retired registry).
- [ ] 4.4 `plugins/soleur/commands/sync.md` A7; `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md` A8.
- [ ] 4.5 Run AC9 (old phrases → 0), AC10 (anchors present), AC11 (INFO line shape), AC12 (token-multiset vs `$BASE`), `bash scripts/lint-agents-compound-sync.sh`, AC15 `bash scripts/markdown-lint.sh <files>`.

## Phase 5: Verification and PR body

- [ ] 5.1 Run every Pre-merge AC (AC1–AC16) and paste the outputs; `bash scripts/test-all.sh` full battery at `/ship` Phase 4.
- [ ] 5.2 PR body: before/after budget lines (delta −703 vs `$BASE`), the two expected `::error::` mandatory-human-review annotations from `rule-body-lint`, the H1/H2 manual-mutation outcomes, the 36-row verdict table, the `rules_unused_over_8w=81` quote, the two AC5 verbatim diffs, `Closes #8030` on its own line, overlap dispositions (#4133 acknowledge, #3373 acknowledge).
