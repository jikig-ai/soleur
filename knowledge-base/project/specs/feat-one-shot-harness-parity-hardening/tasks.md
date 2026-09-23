# Tasks: harness-parity hardening (Grok/Codex/Devin) + retire OpenHands/Gemini

Plan: `knowledge-base/project/plans/2026-09-22-feat-harness-parity-hardening-grok-codex-devin-plan.md`

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Phase 1: Setup

- [ ] 1.1 Re-measure every count in the plan's Research Reconciliation. Numbers go into the PR body later.
- [ ] 1.2 Re-probe the ADR-240 ordinal across all `origin/*` refs.

## Phase 2: Core Implementation (commit order)

- [ ] 2.1 Retire OpenHands/Gemini (item 7)
  - [ ] 2.1.1 `git rm -r .openhands .gemini`
  - [ ] 2.1.2 Derive the sweep list with the plan's `git grep`, then remove the OpenHands/Gemini arms from each live file. This includes the `guard-vacuity-floor.test.sh` `MIN_FIRING_SUITES` floor, the `worktree-write-guard.sh` allow, the NOTICE entry, the lint baselines, and `markdown-lint.sh` `EXPECTED_ROOTS`.
  - [ ] 2.1.3 Correct the Devin claim in the `components.test.ts` `ACKED_CROSS_ROOT_DUPES` comment (3000.11.1 lists each name once)
  - [ ] 2.1.4 Edit the guardrails description in `model.c4`, run `bash scripts/regenerate-c4-model.sh`, and commit `model.likec4.json`
  - [ ] 2.1.5 Add the retired banner to `platform-portability-comparison.md`
  - [ ] 2.1.6 `bash scripts/test-all.sh` green
- [ ] 2.2 Devin polling fix (item 2)
  - [ ] 2.2.1 RED: flip `harness.test.ts` and `devin-harness.test.ts` to `run_subagent` present and `get_output` absent
  - [ ] 2.2.2 GREEN: rewrite the `pollInstructions()` devin long-loop bullet
  - [ ] 2.2.3 Live check of a background `run_subagent` wait loop with the local Devin CLI. Record the outcome in the PR body.
- [ ] 2.3 Grok invoke block (item 1)
  - [ ] 2.3.1 RED: `plugins/soleur/test/grok-harness-invoke.test.ts`. Canonical block from `plan/SKILL.md`, md5 pinned; population from `git ls-files`, floor ≥ 100; one block per file, byte-equal, before the first heading; `init_skill.py` also covered
  - [ ] 2.3.2 Backfill 90 skills with a throwaway script (after the cloud-mode end marker, else after the frontmatter)
  - [ ] 2.3.3 Add the block to `skill-creator/scripts/init_skill.py` `SKILL_TEMPLATE`
  - [ ] 2.3.4 Post-backfill validation: census `--report` plus `bun test plugins/soleur/test`
- [ ] 2.4 Census covers references (item 4)
  - [ ] 2.4.1 Commit A: `globToRegex` `**` (replace `**/` first), the references glob, the `SKILL.md`-basename exclusion in `regionPolicyForPath`, fixture updates, and the tree test's independent enumeration via `regionPolicyForPath`
  - [ ] 2.4.2 Commit B, on a clean tree: census `--fix`, full human diff review, hand triage of bare leaves, `harness-forms` regions around verbatim quotes in `plan-sharp-edges.md`, then `--report` shows 0
- [ ] 2.5 Tool-map coverage (item 3)
  - [ ] 2.5.1 `plugins/soleur/lib/harness-tool-map.ts`: `CLAUDE_CODE_TOOLS` (verified against docs) plus `parseToolsTable`
  - [ ] 2.5.2 RED: `harness-tool-map.test.ts`. Coverage in both tables, actionable failure message, floors (table non-empty, population ≥ 280 re-measured), and a must-PASS fixture with the Grok block
  - [ ] 2.5.3 GREEN: rows for every used-but-unmapped name (`SendMessage`, `TaskCreate/TaskList/TaskUpdate`, `RemoteTrigger`, and anything else found) in both INSTRUCTIONS tables. Codex `followup_task` is measured; verify Devin `read_subagent`.
- [ ] 2.6 Plugin-root ratchet (item 5, #7453 slice)
  - [ ] 2.6.1 Third axis in `apps/web-platform/test/plugin-root-anchoring.test.ts` over all skill docs, forms (a) through (d)
  - [ ] 2.6.2 `fixtures/plugin-root-skills-ratchet.tsv` keyed on (path, normalized text) with a multiplicity count. Stale rows RED, all listed at once. The failure message prints the bare rewrite and "see #7453".
  - [ ] 2.6.3 Leave `safe-bash.ts` and `plugin-root-list-carveout-coupling.test.ts` untouched
- [ ] 2.7 Codex + Devin discovery (item 6)
  - [ ] 2.7.1 `plugins/soleur/scripts/harness-discovery-smoke.ts` with pure `expectedSkills` (dir basenames), the two parsers, and `verdict` (multiplicity 1 or k). Exit 0/1/3 with a reason line; 4 KB of raw output on failure; 90 s cap per call.
  - [ ] 2.7.2 `plugins/soleur/test/harness-discovery-smoke.test.ts` covering every Guard 6 row, with synthesized fixtures
  - [ ] 2.7.3 Find out whether Devin's `install.sh` accepts a pinned version. If not, use sha256 plus a `--version` assertion.
  - [ ] 2.7.4 `harness-discovery` job in `ci.yml` (setup-bun, `@openai/codex@0.156.1`, pinned Devin), not added to `ruleset-ci-required.tf`
- [ ] 2.8 ADRs + C4
  - [ ] 2.8.1 ADR-240 (retirement, vendor-CLI CI policy and pin owner, Devin wait primitive, gate map), written with `soleur:architecture`
  - [ ] 2.8.2 ADR-226 amendment/status line (drop the #8306 citation); ADR-165 status note
  - [ ] 2.8.3 C4 tests: `c4-count-parity.test.sh`, `c4-code-syntax.test.ts`, `c4-render.test.ts`

## Phase 3: Testing & Hygiene

- [ ] 3.1 `bash scripts/test-all.sh`, `bun test plugins/soleur/test`, and the `plugin-root-anchoring` vitest all green
- [ ] 3.2 `ci.yml` under the ADR-231 byte gate
- [ ] 3.3 Issue comments: #8317 (references half done), #7453 (ratchet landed, ADR-179 citation, Devin prerequisite), #6791/#7173 (OpenHands sub-items obsolete), #8236 (Devin measurement), #8574 (pin-freshness criterion)
- [ ] 3.4 PR body: `Closes #8390`, `Closes #8318`, `Closes #8306`, `Ref #8317`, `Ref #7453`, `Ref #8574`, plus the re-measured numbers and the Devin live-check outcome
