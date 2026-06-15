# eval-harness

A [promptfoo](https://www.promptfoo.dev) harness that empirically measures whether a Soleur skill
or agent edit improves classification behavior. v1 ships two targets — `soleur:go` routing accuracy
and ticket-triage P-level accuracy — adapting the [ponytail](https://github.com/DietrichGebert/ponytail)
(MIT) benchmark methodology.

## Prerequisites

- Node `>=22.22` (the worktree ships v22.22.1) — no dependency is added to any `package.json`;
  the harness runs via `npx promptfoo`.
- `ANTHROPIC_API_KEY` in the environment (promptfoo's `anthropic:messages:*` providers read it).

## Reproduce

```bash
cd plugins/soleur/skills/eval-harness

# 1. Refresh the model IDs from the TS registry (writes models.generated.json).
bash scripts/gen-models.sh

# 2. (No-spend) sanity-check the configs — zero API calls.
npx promptfoo validate config -c promptfooconfig.go-routing.yaml
npx promptfoo validate config -c promptfooconfig.ticket-triage.yaml

# 3. Run a target (SPENDS — see cost below).
npx promptfoo eval -c promptfooconfig.go-routing.yaml
npx promptfoo eval -c promptfooconfig.ticket-triage.yaml

# 4. Inspect results in the browser.
npx promptfoo view
```

> **Use `validate config`, never bare `validate` or `validate target`** — the latter two spend API
> credits. `validate config` is config-only and free.

## Per-run cost

Each target's grid is **2 arms × 3 models × ~3 golden tasks × 3 repeats ≈ 54 API calls**; running
both targets is ≈ 108 calls. One arm runs on Opus, so cost is dominated by the Opus cells. This is
why the harness is **opt-in and manual** and is NOT wired into per-PR CI. See the `<decision_gate>`
in [SKILL.md](./SKILL.md) for the billing disclosure.

## Reading the baseline-vs-skill delta

Each run produces, per (arm × model) cell, the **classification-correct rate** recorded by the
measurement assert (mean of the per-task 1.0/0.0 scores; promptfoo has no native median, so read
the aggregate score promptfoo reports per cell, or compute the median across the `repeat` runs from
the JSON output).

> **delta = (skill-arm correct rate) − (baseline-arm correct rate)**

A **positive delta** is the evidence that the classifier prose (the `/go` routing table, the triage
rubric) *produces* the routing/triage behavior — not merely that the text is present. A delta near
zero means the model classifies just as well without the prose (the prose is not adding signal for
these tasks). The **gate assert** is orthogonal: it fails any cell whose emitted label is malformed
or outside the closed enum, independent of correctness — a baseline arm that hallucinates a
non-existent route is caught here even when its correct rate looks fine.

To regression-check a future edit to `/go` or ticket-triage: run the relevant config before and
after the edit and compare the skill-arm correct rate. A drop is a behavioral regression the prose
change introduced.

## Adding a new target (the additive recipe)

The two-target v1 exists to prove this is cheap. To add target N:

1. Add an enum SSOT `enums/<target>.json` (the closed label set).
2. Add two arm prompts `prompts/<target>-skill.txt` (embeds the production classifier prose) and
   `prompts/<target>-baseline.txt` (label set only, no rules). Each uses the `{{input}}` placeholder.
3. Add golden tasks `tasks/<target>.jsonl` — `{"vars": {"input": "...", "golden_label": "..."}}` per
   line, synthesized fixtures only.
4. Add `promptfooconfig.<target>.yaml` mirroring the existing configs: `providers: file://models.generated.json`,
   the two prompts, `defaultTest.vars.enum: file://enums/<target>.json`, and the two shared asserts
   ([measure-classification.cjs](./scripts/measure-classification.cjs),
   [gate-classification.cjs](./scripts/gate-classification.cjs)).

The generic asserts and `models.generated.json` are reused unchanged — no new script is needed
unless the target's output is not a single-token label (prose-output surfaces need an LLM-judge
assert, deferred out of v1).

## Files

| Path | Role |
|------|------|
| [promptfooconfig.go-routing.yaml](./promptfooconfig.go-routing.yaml) | `/go` routing target config |
| [promptfooconfig.ticket-triage.yaml](./promptfooconfig.ticket-triage.yaml) | ticket-triage target config |
| [scripts/gen-models.sh](./scripts/gen-models.sh) | single-sources the 3 model IDs → `models.generated.json` |
| [scripts/parse-label.cjs](./scripts/parse-label.cjs) | shared label parser |
| [scripts/measure-classification.cjs](./scripts/measure-classification.cjs) | MEASUREMENT assert (always passes, records the rate) |
| [scripts/gate-classification.cjs](./scripts/gate-classification.cjs) | GATE assert (fails on out-of-enum label) |
| [enums/go-routes.json](./enums/go-routes.json) · [enums/triage-levels.json](./enums/triage-levels.json) | closed label sets |
| [prompts/](./prompts/go-skill.txt) | skill + baseline arm templates per target |
| [tasks/go-routing.jsonl](./tasks/go-routing.jsonl) · [tasks/ticket-triage.jsonl](./tasks/ticket-triage.jsonl) | synthesized golden tasks |
| [test/](./test/gen-models.test.sh) | deterministic `.test.sh` unit tests (no live LLM) |
