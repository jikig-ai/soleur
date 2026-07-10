---
name: eval-harness
description: This skill provides a promptfoo eval harness that measures whether a Soleur skill or agent edit actually improves behavior, comparing a skill arm against a baseline control arm.
---

# Eval Harness — empirical prompt/agent regression checking

A reproducible [promptfoo](https://www.promptfoo.dev) harness that answers the question
Soleur could not answer before: *does this prompt/agent edit actually change behavior, or
does it just carry new text?* It adapts the benchmark methodology of the
[ponytail](https://github.com/DietrichGebert/ponytail) Claude Code plugin (MIT) to Soleur's
own surfaces.

**v1 targets two high-traffic classifiers** (the design makes adding a third cheap):

1. **`soleur:go` routing accuracy** — does the routing table produce the correct route token?
2. **ticket-triage P-level accuracy** — does the priority rubric produce the correct P1/P2/P3?

**Grok Build arm (Phase C #6323):** The harness now covers Grok slash-command + `spawn_subagent` semantics for `/go` routes (in addition to Claude Skill/Task). Golden assertions and regression tests exercise the adapter contract from `lib/harness.ts` (detect via GROK_* markers or argv). The go-routing target in `gated-skills.json` + eval-gate block in `go.md` are the source; projections feed the skill arm for both harnesses. See plan 2026-07-11-feat-grok-phase-c-go-md-eval-harness-plan.md and self-ref in `go.md`.

<decision_gate>
**API budget.** Each `npx promptfoo eval --repeat 3` run calls the Anthropic API against the key in
your session — 2 arms × 3 models × the target's golden tasks × 3 repeats. At the current task counts
that is ≈ **126 API calls** for go-routing (7 tasks) and ≈ **108** for ticket-triage (6 tasks), so
≈ **230 to run both**. Cost scales with the model mix (one arm runs Opus), the task count, and the
`--repeat` value (outputs are single tokens, so per-call cost is small — the first full run was well
under $1). This harness is **opt-in and manual** — it is deliberately NOT wired into per-PR CI (that
cost decision is separate and later). Soleur does not bill or proxy these calls — Anthropic does,
against your key. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this
harness against your own budget. To inspect the config without spending, use
`npx promptfoo validate config` (no API calls).
</decision_gate>

## How it works (the four ponytail patterns)

1. **promptfoo-driven grid** — arms × models × tasks, N runs. One config file per target:
   [promptfooconfig.go-routing.yaml](./promptfooconfig.go-routing.yaml) and
   [promptfooconfig.ticket-triage.yaml](./promptfooconfig.ticket-triage.yaml).
2. **MEASUREMENT assert** (always passes, records a number) —
   [measure-classification.cjs](./scripts/measure-classification.cjs) records the
   classification-correct rate (1.0 if the emitted label matches the golden label, else 0.0). The
   ponytail `loc.js` analog.
3. **GATE assert** (fails on wrong output) —
   [gate-classification.cjs](./scripts/gate-classification.cjs) fails when the emitted label is not
   a member of the target's closed enum ([go-routes.json](./enums/go-routes.json),
   [triage-levels.json](./enums/triage-levels.json)). The ponytail `correctness.js` analog.
4. **BASELINE / CONTROL arm** — the baseline prompt
   ([go-baseline.txt](./prompts/go-baseline.txt),
   [triage-baseline.txt](./prompts/triage-baseline.txt)) knows only the label set, not the
   classifier rules; the skill prompt ([go-skill.txt](./prompts/go-skill.txt),
   [triage-skill.txt](./prompts/triage-skill.txt)) embeds the production classifier prose. The
   delta between the two arms is the evidence the rules *produce* the behavior — "that delta is the
   point."

Both asserts share one parser, [parse-label.cjs](./scripts/parse-label.cjs). Golden tasks are
synthesized fixtures only (no real user data): [go-routing.jsonl](./tasks/go-routing.jsonl),
[ticket-triage.jsonl](./tasks/ticket-triage.jsonl).

**Skill-arm prompts are generated projections (no hand-copy).** The skill-arm prompts
(`prompts/go-skill.txt`, `prompts/triage-skill.txt`) are a **mechanical projection** of the
production classifier block, not a hand-distilled paraphrase. Each gated source wraps its rules in
HTML-comment sentinels — the `/go` routing table in `plugins/soleur/commands/go.md`
(`<!-- eval-gate:block:go-routing:start -->` … `:end`) and the ticket-triage priority rubric in
`plugins/soleur/agents/support/ticket-triage.md` (`eval-gate:block:ticket-triage`). The block is the
single source of truth; [scripts/extract-block.cjs](./scripts/extract-block.cjs) projects it and
[scripts/gen-skill-prompt.cjs](./scripts/gen-skill-prompt.cjs) wraps it into the skill-arm prompt.
**Regenerate on any source-block edit** (`node scripts/gen-skill-prompt.cjs --all`); the AC4
round-trip test ([test/extract-block.test.sh](./test/extract-block.test.sh)) asserts the committed
projection equals the freshly generated one byte-for-byte, so a stale projection fails CI rather than
silently measuring an out-of-date classifier.

## Gate mode — validation-gated classifier-skill edits

Beyond measuring a delta, the harness gates *edits* to a classifier block: an edit must not regress
the corpus AND must make its targeted case pass before it is applied
([scripts/eval-gate.cjs](./scripts/eval-gate.cjs), proposer-agnostic — heal-skill, compound, or a
manual edit). The registry [gated-skills.json](./gated-skills.json) lists each gated block:
`{ source_file, block_id, block_start_marker, block_end_marker, target, projected_prompt_path }`.

- **`--check <file>`** — print `{gated, target, block_id}` for whether a file is a gated source
  (lookup-only, no API). A proposer runs this first; a non-gated edit proceeds unchanged.
- **`--dry-run --target <id>`** — print the **skill-arm-only** API-call estimate
  (`2 (current+candidate) × models × (corpus+1) × repeat`; the baseline control arm is skipped) and
  exit without spending.
- **Real run** (`--target <id> --candidate-file <edited-source> --target-task <json|path>
  [--repeat N] [--append-on-accept]`) — extract the current block (source on disk) and candidate
  block (edited file); if they are identical it prints `{accept:true, reason:"no gated-block
  change"}` (the ungateable no-op). Otherwise it projects both into skill-arm prompts, runs promptfoo
  skill-arm-only for each with `--output`, normalizes the JSON, and calls the **pure**
  [computeVerdict()](./scripts/verdict.cjs). On accept with `--append-on-accept`, the synthesized
  target task is appended to `tasks/<target>.jsonl` (real-data-shaped input is rejected per
  `cq-test-fixtures-synthesized-only`).

The verdict math is pure and unit-tested with zero API
([test/verdict.test.sh](./test/verdict.test.sh)): `corpus_regressed = candidate_rate < current_rate
− epsilon` (ε = one-task-equivalent; boundary equality is NOT a regression), `target_task_passes =
pooled candidate target rate ≥ 0.5`, `accept = !corpus_regressed && target_task_passes`. **Fail-closed:**
any gate error (missing key, promptfoo non-zero, malformed task) exits non-zero and defaults to NOT
accept. The gate is only honest while the skill-arm prompt is a mechanical projection of the block
(see ADR-069) — if the projection link is broken the gate silently no-ops on out-of-block edits.

## Run it

See [README.md](./README.md) for the reproduce commands, how to read the baseline-vs-skill delta,
and the additive recipe for adding a new target. In short:

```bash
cd plugins/soleur/skills/eval-harness
bash scripts/gen-models.sh                                            # refresh model IDs from the registry
npx promptfoo eval -c promptfooconfig.go-routing.yaml --repeat 3      # ~126 API calls (7 tasks)
npx promptfoo eval -c promptfooconfig.ticket-triage.yaml --repeat 3   # ~108 API calls (6 tasks)
npx promptfoo eval -c promptfooconfig.tool-selection.yaml --repeat 5  # ~450 API calls (15 tasks) — manual only
```

**`tool-selection`** is a **manual measurement-only** target (#5768 AC(c)): it
measures whether the L3 phase-scoped surface (the hint
`.claude/hooks/phase-surface-hint.sh` injects) lets the model pick the correct
next skill more often than the full-surface baseline. The mean of the MEASUREMENT
score across the two arms IS the before/after uplift. Unlike `go-routing` /
`ticket-triage` it is **not** in [gated-skills.json](./gated-skills.json) — there
is no prose block to project (the surface lives in `phase-surface-map.json`, not a
SKILL.md `eval-gate` block), so it never runs as a per-PR projection round-trip;
run it by hand when you want the AC(c) number.

`--repeat 3` runs each cell 3× so the rate can be a median over runs — a config-level `repeat:` key
is NOT honored by promptfoo, so the flag is required.

Model IDs are single-sourced via [gen-models.sh](./scripts/gen-models.sh), which reads the three
current IDs from the TypeScript registry into `models.generated.json` — no model literal is
hardcoded in any config-class file.

## Tests

Deterministic, no live LLM / no API (stubbed model outputs, recorded result fixtures):
[gen-models.test.sh](./test/gen-models.test.sh),
[measure-classification.test.sh](./test/measure-classification.test.sh),
[gate-classification.test.sh](./test/gate-classification.test.sh),
[extract-block.test.sh](./test/extract-block.test.sh) (block extraction + AC4 round-trip,
registry-driven target loop),
[verdict.test.sh](./test/verdict.test.sh) (pure `computeVerdict` — accept / corpus-regress /
target-fail / ε-boundary), [eval-gate.test.sh](./test/eval-gate.test.sh) (`--check`, `--dry-run`,
no-op — no API), and
[registry-completeness.test.sh](./test/registry-completeness.test.sh) (bidirectional parity
between `eval-gate:block` source markers and `gated-skills.json` `block_id`s — DEDUP +
set-equality + charset guard). They run under the standard `bash scripts/test-all.sh` discovery.
