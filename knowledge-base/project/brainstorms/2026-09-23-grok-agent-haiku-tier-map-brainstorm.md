---
date: 2026-09-23
topic: grok-agent-haiku-tier-map
lane: cross-domain
issue: 8604
---

# Grok research-agent stubs should not copy `model: haiku`

## What We're Building

The five generated Grok profiles under `.grok/agents/soleur-engineering-research-*.md` stop shipping the Claude alias `model: haiku`. The generator in `plugins/soleur/scripts/sync-grok-agent-compat.ts` omits the `model` line for those stubs. The Claude sources stay `model: haiku`. The other Grok stubs stay `model: inherit`. ADR-110 gets an addendum that records the measurement.

## Why This Approach

Issue #8604 (open, no comments) asked for a live Grok 1.0.40+ measurement before choosing between "map `haiku` through `TIER_MAPS.grok`" and "drop the pin". Measured on Grok Build 1.0.41 with `grok --agent <file> -p` (the spawn tool's schema has no agent-type argument, so an in-session spawn cannot select these files; the pin is read when the file is the session agent):

| Profile `model` | Result |
| --- | --- |
| `haiku` (the repo-research stub) | Warning: model not in catalog, keep session default. Call billed `grok-4.7`. Exit 0. |
| `cheap` | Same warning. The semantic word is not a catalog id. |
| `grok-4.5` | Recognized ("override applied"), then this headless client sends `SetSessionModel` `grok-4.7` and the call bills `grok-4.7`. |
| `inherit` (the product profile) | No unknown-model warning. Call billed `grok-4.7`. |
| key omitted | No unknown-model warning. Exit 0. Call billed `grok-4.7`. |

`origin/main` has 5 stubs with `model: haiku` and 62 with `model: inherit` (`git grep -h '^model:' origin/main -- '.grok/agents/*.md'`). ADR-110 decision 4 still holds: the harness does not accept semantic tiers in agent spawn, so the Claude files stay on `haiku` and the generator must not write the word `cheap`.

Pinning `grok-4.5` would put a catalog slug on a session profile. A client that stops overwriting it would downgrade the whole session, not a research child. The 2026-09-23 ADR-110 addendum already says the Grok cheap-versus-standard gap is cached input only. Dropping the line matches today's effective behavior and removes the warning.

## User-Brand Impact

- **Artifact:** the five generated Grok research-agent stubs and the sync script that writes them.
- **Vector:** a Claude alias in a Grok profile warns on startup and fails open onto the session model, so a planning session looks unfinished and the cheap-tier intent is silently dropped.
- **Threshold:** single-user incident.

Tagged user-brand-critical (auto, per the standing brainstorm rule). Lane is `cross-domain`. Marketing was not consulted: this is operator-facing agent infra, not a new user-facing capability.

## Key Decisions

- Drop the `model` line on the five Grok research stubs. Do not write `cheap` or `grok-4.5`.
- Leave `plugins/soleur/agents/engineering/research/*.md` on `model: haiku`.
- Leave every `model: inherit` stub as it is.
- Record the table above as an ADR-110 addendum. Decision 4's trigger (semantic tiers accepted in Task/Agent spawn) has not fired.
- The headless client's later `SetSessionModel` to the configured default is out of scope. This issue does not change how `grok -p` picks the session model.
- The cited plan path in the issue body is the archived copy `knowledge-base/project/plans/archive/20260923-154226-2026-09-23-feat-upgrade-harness-models-plan.md`. The live path is gone because that plan was archived after the model upgrade landed. The deferral itself is still the open work.

## Open Questions

- When a future Grok can select these stubs as child agents, confirm that a missing `model` key still inherits. Today both "omitted" and `inherit` are silent on a session agent. Revisit only if child spawn starts reading the stub.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** The warning is the harm (a planning session looks unfinished). Running on the session model is not. Pinning `grok-4.5` spends a generation for a price gap the founder will not feel. Recommendation: drop the line.

### Engineering

**Summary:** ADR-110 decision 4 is not violated by omitting the Grok line. A `grok-4.5` pin is the wrong scope: these files are session profiles, and the headless client already overwrites a recognized pin. Recommendation: drop the line. A missing key was unmeasured at assessment time; it was measured afterward and is silent.

### Legal

**Summary:** No compliance document and no GDPR gate. The change does not touch personal data or a sub-processor.

## Capability Gaps

None. `plugins/soleur/scripts/sync-grok-agent-compat.ts` already writes the stubs (`model: ${entry.model}` at the compat-stub builder). The gap is the copied value, not a missing generator. Evidence: `git grep -n 'model:' origin/main -- plugins/soleur/scripts/sync-grok-agent-compat.ts .grok/agents/soleur-engineering-research-repo-research-analyst.md`.

## Next Steps

Plan the generator change, the five stub updates, the drift check, and the ADR-110 addendum. Use `/plan`.
