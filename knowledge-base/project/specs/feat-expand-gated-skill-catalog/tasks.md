---
feature: expand-gated-skill-catalog
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-29-feat-expand-gated-skill-catalog-plan.md
issue: 5704
pr: 5719
---

# Tasks — expand gated-skill catalog

One PR, two commits. All paths under `plugins/soleur/skills/eval-harness/` unless noted.
Steps within each surface are in dependency order (registry row before prompt generation).

## Phase 1 — Commit 1: lane-inference

- [x] 1.1 Create `enums/lane.json` = `["procedural","single-domain","cross-domain"]`.
- [x] 1.2 Add sentinels around the §Lane Inference **rule block** in
  `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`
  (`<!-- eval-gate:block:lane-inference:start/end -->`). Span = table + fail-closed default;
  EXCLUDE USER_BRAND_CRITICAL composition (input-flag orchestration) + Carry-forward + Stability meta.
  Leave heading/table intact.
- [x] 1.3 Add `lane-inference` entry to `scripts/gen-skill-prompt.cjs` `TARGET_CONFIG`
  (`enumPath: "enums/lane.json"`, `render()` mirroring go-routing).
- [x] 1.4 Add `gated-skills.json` row (`block_id`/`target: lane-inference`, markers, `source_file`,
  `projected_prompt_path: .../prompts/lane-inference-skill.txt`).
- [x] 1.5 Hand-write `prompts/lane-inference-baseline.txt` (labels only); generate
  `prompts/lane-inference-skill.txt` via `node scripts/gen-skill-prompt.cjs lane-inference`.
- [x] 1.6 Create `tasks/lane-inference.jsonl`, ~6–8 synthesized tasks: ≥1 per lane + adversarial
  cross-domain∧procedural overlap cases (assert documented precedence).
- [x] 1.7 Create `promptfooconfig.lane-inference.yaml` mirroring `promptfooconfig.go-routing.yaml`.
- [x] 1.8 Add `lane-inference` entry to `scripts/eval-gate.cjs` `TARGET_RESOURCES`
  (`{tasks: "tasks/lane-inference.jsonl", enumPath: "enums/lane.json"}`).
- [x] 1.9 Commit 1.

## Phase 2 — Commit 2: incident-threshold

- [x] 2.1 Create `enums/incident-threshold.json` = `["none","single-user incident","aggregate pattern"]`.
- [x] 2.2 Add sentinels around the §Phase 1 — Classification **criteria block** in
  `plugins/soleur/skills/incident/SKILL.md` (`eval-gate:block:incident-threshold`). Span = the 3-tier
  bullets + intro; EXCLUDE the advisory-output example + the "Confirm advisory / override" prompt.
- [x] 2.3 Add `incident-threshold` entry to `gen-skill-prompt.cjs` `TARGET_CONFIG` (render wrapper:
  "you are the incident classifier; respond with ONLY one of: none | single-user incident | aggregate pattern").
- [x] 2.4 Add `gated-skills.json` row for `incident-threshold`.
- [x] 2.5 Hand-write `prompts/incident-threshold-baseline.txt`; generate
  `prompts/incident-threshold-skill.txt`.
- [x] 2.6 Create `tasks/incident-threshold.jsonl`, ~6–8 synthesized tasks: none / single-user /
  aggregate + a borderline single-vs-aggregate case.
- [x] 2.7 Create `promptfooconfig.incident-threshold.yaml`.
- [x] 2.8 Add `incident-threshold` entry to `eval-gate.cjs` `TARGET_RESOURCES`.
- [x] 2.9 Commit 2.

## Phase 3 — Shared test infra (fold into commit 1)

- [x] 3.1 Data-drive the `test/extract-block.test.sh` round-trip loop from `gated-skills.json`
  (iterate `target` + `projected_prompt_path`) so all current + future targets are covered with no
  per-surface edit.
- [x] 3.2 Add a registry-coverage consistency test (in `test/eval-gate.test.sh` or a new test):
  every `gated-skills.json` target ∈ `keys(TARGET_CONFIG)` ∩ `keys(TARGET_RESOURCES)`.

## Phase 4 — Verify, opt-in runs, PR

- [x] 4.1 `bash plugins/soleur/skills/eval-harness/scripts/test-all.sh` green (round-trip + consistency).
- [x] 4.2 `node scripts/eval-gate.cjs --check <each source>` → `gated:true`.
- [x] 4.3 `node scripts/eval-gate.cjs --dry-run --target lane-inference --repeat 5` and
  `--target incident-threshold --repeat 5` → valid estimate, exit 0 (no API). **Proves the gate is wired.**
- [x] 4.4 `npx promptfoo validate config -c promptfooconfig.<t>.yaml` for both (no API).
- [ ] 4.5 `bash scripts/gen-models.sh` then `npx promptfoo eval -c promptfooconfig.lane-inference.yaml --repeat 3`
  and the incident config; record both deltas + API-call count + spend in the PR body.
- [ ] 4.6 Mark PR ready; PR body uses `Ref #5704` (NOT `Closes`) + records both deltas. Guard:
  `gh pr view <PR> --json body --jq .body | grep -iqv 'clos.*#5704'`.
- [ ] 4.7 After merge: `gh issue close 5704` (automated by the merging agent); confirm #5722 stays open.
