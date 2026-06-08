# Spec: Migrate Soleur fan-out skills to dynamic workflows

## Goal

Introduce dynamic-workflow (`Workflow` tool) implementations of the Soleur
skills whose shape is **deterministic multi-agent orchestration** — parallel
fan-out, loop-until-done, or fan-out-then-verify — where moving control flow
from prose (model-interpreted Task spawns) to a JS script buys: deterministic
fan-out, journaled resume, hard token budgets, schema-validated structured
output, and built-in adversarial-verify / loop patterns.

The `review` skill is the proven template (`skills/review/workflows/review.workflow.js`).

## What migrates, and why

| Skill | Shape | Workflow primitive | Notes |
|---|---|---|---|
| `review` ✅ | fan-out + verify | `pipeline()` | done (template) |
| `resolve-pr-parallel` | N comments → N resolvers → verify | `parallel()` + verify loop | re-fetch until 0 unresolved |
| `resolve-todo-parallel` | dependency-ordered todos → resolvers | staged `parallel()` | legacy `todos/*.md` only |
| `resolve-parallel` | TODO comments → resolvers | `parallel()` | dependency tiers |
| `plan-review` | fixed 3/5-agent panel | `parallel()` | 5-agent panel when `single-user incident` |
| `agent-native-audit` | 8 fixed principle audits → scored report | `parallel()` + synth | scored 0–100 report |
| `deepen-plan` | one research agent per plan section | `parallel()` | merge back into plan |
| `drain-labeled-backlog` | cluster issues → per-cluster work | `pipeline()` | each cluster → `/soleur:one-shot` |

## What deliberately stays a skill

- **Conversational / human-in-loop:** `brainstorm`, `plan`, `work` — interactive
  dialogue, incremental commits, approval gates. Workflows are headless/batch.
- **Sequential procedural with gates:** `ship`, `preflight`, `merge-pr`,
  `postmerge`, provisioning skills — linear, side-effectful, gate-by-gate.
- **Meta-orchestrators:** `one-shot` keeps its outer skill flow (it sequences
  plan→work→review→ship via the Skill tool); its **inner** review and
  resolve-pr stages invoke the migrated workflows.
- **Single-agent / documentation:** `compound`, `compound-capture`, `changelog`,
  legal/marketing/content generators, `go`/`help`/`sync`.

## Conventions

- One self-contained script per skill at `skills/<skill>/workflows/<skill>.workflow.js`.
  Workflow scripts **cannot import** (no filesystem/Node API in the runtime), so
  shared helpers (schemas, `safeTitle`) are duplicated per script by design.
- Each carries the same **API-budget disclosure** the source skill carries
  (`hr-autonomous-loop-skill-api-budget-disclosure`).
- Skills are **not replaced** — the workflow is an opt-in alternative the SKILL.md
  can invoke. Coexistence during calibration.
- Untrusted input (issue/PR/diff text reaching a shell argv) is sanitized; bodies
  go via `--body-file` (see `review.workflow.js` `safeTitle`).

## Validation

- `node --check` on each script's async-wrapped body (top-level `await`/`return`
  are runtime-legal, bare-`node` illegal — wrap to validate).
- Zero-token stub harness for control flow where practical.
- Live A/B on a real target before any skill flips its default.
