# Tasks — feat-one-shot-8290-invocation-axis-budget-relief

Plan: `knowledge-base/project/plans/2026-09-21-refactor-invocation-axis-budget-relief-plan.md` (issue #8290, draft PR #8484).
lane: cross-domain (the spec has no valid lane, so the default fails closed).

## Phase 0 — Preconditions and the architecture-deciding probe (FIRST)

- [ ] 0.1 Re-measure the budget (`2561/2561`), `B_ALWAYS` (`lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1`), and the claude/devin/codex versions. Record them in `b5-eval-results.md`.
- [ ] 0.2 W0 probe plugin under `w0/probe8290/`:
  - [ ] a. headless slash runs
  - [ ] b. the Skill tool refuses
  - [ ] d. the tmux interactive TUI autocompletes and runs
  - [ ] e. Devin, required: the `devin skills list` marker
  - [ ] e'. Codex, best-effort
  - [ ] f. haiku listing self-report, before
- [ ] 0.3 Stop rule: a, d or e fails → apply the W0-STOP profile (B5 + B6 + the ADR-151 addendum only, ADR-236 `proposed`, `refs: 8290`).
- [ ] 0.4 Re-run the subject sweep (`git grep -nw <name>`) for the 12 names and diff it against the plan's classification.

## Phase 1 — Invocation axis (skipped under W0-STOP)

- [ ] 1.1 Write `plugins/soleur/test/invocation-axis.test.ts` first. It uses `:(glob)` pathspecs, per-glob floors, scanned = `ls-files`, the exact-set pin, keep-pins, and the failure message spec. `git add` it, then run it: RED is expected.
- [ ] 1.2 Add `disable-model-invocation: true` to 12 frontmatters: flag-create, flag-delete, flag-set-role, cron-list, cron-delete, provision-{cloudflare,doppler,github,hetzner}, admin-ip-refresh, user-set-role, cf-token-scope.
- [ ] 1.3 Rewordings:
  - `schedule:732,771`
  - `trigger-cron:26-27`
  - `tenant-provisioning.md` `**Skill:**` lines
  - `help.md` type-only marker
  - the `go.md` hand-off note, outside lines 513-527
  - `tool-selection-baseline.txt:10`
- [ ] 1.4 One-time read of the exempt intra-family group (`flag-create:41,72`, `cron-delete:37`). Rewrite operative lines and record them in the PR body.
- [ ] 1.5 Fill the ack table: one (file, skill) row per hit, each `doc-mention` or `operator-handoff`.
- [ ] 1.6 Budget filter in `components.test.ts:150-170`. Ratchet `SKILL_DESCRIPTION_WORD_BUDGET` to the measured total and add the line-21 comment. Add keep-pins for trigger-cron, invoice and flag-list.
- [ ] 1.7 Real-plugin W0:
  - [ ] `/soleur:cron-list` runs
  - [ ] the Skill tool refuses cron-list
  - [ ] trigger-cron and flag-list launch
  - [ ] tmux TUI `/soleur:flag-cr`
  - [ ] W0-f after
- [ ] 1.8 Drive the Guard 1 matrix (M1, M2, M5-M9, H2-H5) on a scratch copy and record each row.
- [ ] 1.9 File a follow-up issue for the typed-yes TTY gap (`delete.sh:146` and siblings), with verified labels and milestone.

## Phase 2 — skill-creator (B6)

- [ ] 2.1 `references/authoring-levers.md`:
  - four lever H2s;
  - the two-loads section carries the invocation choice, the headless-refusal policy and the 13th-flip checklist;
  - no flipped skill named;
  - the attribution comment, with both full peer paths verified at `c55ee46`.
- [ ] 2.2 D3 census edits:
  - `skill-structure.md`
  - `common-patterns.md`
  - `iteration-and-testing.md`
  - `audit-skill.md` (plus the invocation check)
  - `create-new-skill.md`
  - `create-domain-expertise-skill.md`
  - `add-reference.md`
  - `upgrade-to-router.md`
  - the `core-principles.md` pointer
- [ ] 2.3 `official-spec.md` frontmatter rows (source: the Claude Code docs), plus the `SKILL.md` reference index.
- [ ] 2.4 AC-S1 and AC-S2 census greps. Fix the allowlist.
- [ ] 2.5 Shingle check against the 3 peer blobs. Rewrite any shared 8-gram.
- [ ] 2.6 NOTICE `Used in:` / `Portions adopted:` (#8290).

## Phase 3 — B5 eval

- [ ] 3.1 Fixture:
  - `rule-phrasing-bodies.json` (pinned prohibition, sha256, positive; tags byte-identical)
  - `rule-phrasing.cjs` (chat-format, system = corpus, hash-lock)
  - `tasks/rule-phrasing.jsonl` (24 rows)
  - `measure-rule-compliance.cjs`
  - `rule-phrasing-verdict.cjs`
  - `promptfooconfig-rule-phrasing.yaml` (labelled arms)
- [ ] 3.2 Battery `test/rule-phrasing.test.sh`: E0-E9, the sample table, and the house anti-vacuity sentinel verbatim. `git add`, then run it.
- [ ] 3.3 Pre-spend:
  - [ ] arm diffs (AC-E2)
  - [ ] `B_ALWAYS` fit with the positive bodies
  - [ ] `promptfoo validate config`
  - [ ] no registry marker outside eval-harness
  - [ ] `registry-completeness` green
- [ ] 3.4 Cost estimate against the $60 cap (else `--repeat 2`). Run `ANTHROPIC_MAX_TOKENS=300 npx promptfoo eval … --repeat 3 -o <spec-dir>/b5-eval-raw.json`.
- [ ] 3.5 Run the verdict module and record everything in `b5-eval-results.md` (module sha256, truncation rates, tokens and cost).
- [ ] 3.6 Branch on the verdict:
  - EXTEND → follow-up PR (bodies + `--write` + WORM acks, @deruelle review, no auto-merge) and an issue for the other 6.
  - REJECT or CEILING → no-list entry (scope literal, `->` searched, `lint-rejected-register.sh --all`, typed-concept confirmation as a merge gate).
  - INCONCLUSIVE → ADR row and a `revisit_if` issue.
  - INVALID or ABORTED → one rerun.

## Phase 4 — Records

- [ ] 4.1 ADR-236:
  - K1-K3 "only if"
  - `POSTAMBLE` citation
  - the CLI-only web statement
  - the headless-refusal policy
  - the measured table
  - the verdict row
  - the admin-IP read-only path
  - rollback triggers
- [ ] 4.2 ADR-151 addendum (≤ 15 lines; `B_ALWAYS` Δ 0 and the live headroom).
- [ ] 4.3 `bash scripts/check-adr-ordinals.sh`.

## Phase 5 — Pre-push repo-global ratchets (MANDATORY before the first push)

- [ ] 5.1 Stage everything. `git status --short` shows no `??` under `plugins/`, `scripts/`, `knowledge-base/` or `.claude/`.
- [ ] 5.2 Run the full Phase 5 list from the plan (`bun test plugins/soleur/`, the webplat repo-wide vitest project, `guard-vacuity-floor`, the tree-enumerating `*.test.sh` loop, and the lints). Diagnose only after the whole list has run. Do NOT run `scripts/test-all.sh`.
- [ ] 5.3 Trap detectors over the PR's own prose: `lint-squash-ci-directives.sh`, the PR-body citation extractor, and `closingIssuesReferences` = `[8290]`.

## Phase 6 — Before merge

- [ ] 6.1 Re-run the ADR ordinal probe across every `origin/*` ref. On collision, renumber and sweep `ADR-236` in `knowledge-base/`, `plugins/` and the PR body.
- [ ] 6.2 Post-merge: after release, `soleur:postmerge` repeats the tmux TUI capture against the released plugin. A failure fires the ADR-236 rollback trigger.
