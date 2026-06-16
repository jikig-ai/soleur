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

> **Fixture-sync caveat.** The skill-arm prompts hand-copy the production classifier prose — the
> `/go` routing table (`plugins/soleur/commands/go.md`) and the ticket-triage priority rubric
> (`plugins/soleur/agents/support/ticket-triage.md`). There is no mechanical link, so when either
> production surface changes, re-sync the matching `prompts/<target>-skill.txt` (and the enum SSOT
> if routes/levels change) or the harness silently measures a stale classifier. Re-syncing on a
> production-classifier edit is the maintenance contract for this skill.

## Run it

See [README.md](./README.md) for the reproduce commands, how to read the baseline-vs-skill delta,
and the additive recipe for adding a new target. In short:

```bash
cd plugins/soleur/skills/eval-harness
bash scripts/gen-models.sh                                            # refresh model IDs from the registry
npx promptfoo eval -c promptfooconfig.go-routing.yaml --repeat 3      # ~126 API calls (7 tasks)
npx promptfoo eval -c promptfooconfig.ticket-triage.yaml --repeat 3   # ~108 API calls (6 tasks)
```

`--repeat 3` runs each cell 3× so the rate can be a median over runs — a config-level `repeat:` key
is NOT honored by promptfoo, so the flag is required.

Model IDs are single-sourced via [gen-models.sh](./scripts/gen-models.sh), which reads the three
current IDs from the TypeScript registry into `models.generated.json` — no model literal is
hardcoded in any config-class file.

## Tests

Deterministic, no live LLM (stubbed model outputs):
[gen-models.test.sh](./test/gen-models.test.sh),
[measure-classification.test.sh](./test/measure-classification.test.sh),
[gate-classification.test.sh](./test/gate-classification.test.sh). They run under the standard
`bash scripts/test-all.sh` discovery.
