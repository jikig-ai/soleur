---
title: "fix(grok): generated .grok/agents stubs pin Claude alias 'model: haiku' outside TIER_MAPS"
type: fix
date: 2026-09-23
slug: fix-grok-stubs-omit-haiku
branch: feat-grok-agent-haiku-tier-map
issue: 8604
closes: 8604
priority: p3
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix(grok): drop the Claude model alias from generated research stubs

## Overview

Five generated Grok research profiles copy the Claude alias `model: haiku`. On Grok Build 1.0.41 that alias is not a catalog model: startup warns and the session keeps its default. Stop writing that line for Claude aliases, leave the Claude sources on `haiku`, and record the measurement on ADR-110.

## Research Insights

Found brainstorm from 2026-09-23: grok-agent-haiku-tier-map. Using it as the planning context. External research skipped: the generator, the tier map, and the live measurement are already in this repo.

**Premise validation.** Issue #8604 is open and not closed by a PR. `plugins/soleur/scripts/sync-grok-agent-compat.ts` exists and writes `model: ${entry.model}` inside `compatStubMarkdown`. ADR-110 decision 4 still says leave the Claude research agents on `model: haiku` and do not pass the word `cheap` at those call sites. The issue's live plan path is archived at `knowledge-base/project/plans/archive/20260923-154226-2026-09-23-feat-upgrade-harness-models-plan.md`; the deferral is still the open issue. `subagent_model_inheritance` is unset (documented default off). This session's spawn tool exposed no `model` argument and no agent-type argument.

**Property list.**

- A Grok session that loads a research stub does not warn that `haiku` is missing from the catalog.
- The Claude research agents stay on the cheap alias ADR-110 decision 4 requires.
- Stubs that already say `model: inherit` still say that.
- The measurement is written on ADR-110, including that `cheap` is also not a catalog id and that a recognized `grok-4.5` pin can be overwritten by the headless client's later `SetSessionModel`.

**Cut list.**

- Mapping `haiku` to the word `cheap` — measured unknown, same warning. Cut.
- Writing `model: grok-4.5` — recognized, then clobbered on `grok -p`, and a client that stopped clobbering would downgrade the whole session. Cut. CPO and CTO both recommended omitting the line.
- Changing Claude frontmatter — forbidden by ADR-110 decision 4 until semantic tiers are accepted in agent spawn. Cut.

**Repo paths.** Generator: `plugins/soleur/scripts/sync-grok-agent-compat.ts` (`compatStubMarkdown`). Drift check: `plugins/soleur/scripts/grok-fidelity-gate.sh` and `plugins/soleur/test/grok-inspect-contract.test.ts` (`sync-grok-agent-compat --check`). Tier table: `plugins/soleur/lib/harness-model-map.ts`. Decision: `knowledge-base/engineering/architecture/decisions/ADR-110-harness-semantic-model-tier-map.md`. On `origin/main`, `.grok/agents` is 5× `model: haiku` and 62× `model: inherit`.

**Learnings.** A generated file's readers matter more than a second writer (`2026-09-19-enumerate-the-readers-before-proposing-a-writer-for-a-generated-artifact.md`). Here the reader is Grok's agent-profile loader, measured directly. ADR deferral triggers were re-checked against that measurement (`2026-07-03-brainstorm-re-verify-adr-deferral-triggers-against-live-state.md`): decision 4's trigger has not fired.

**Research reconciliation.**

| Spec claim | Reality | Plan response |
| --- | --- | --- |
| Map `haiku` through `TIER_MAPS.grok` to `cheap` | `cheap` warns the same way `haiku` does | Omit the line instead |
| Five stubs pin `haiku` | Confirmed, plus 62 `inherit` stubs | Touch only the alias path |
| Cited plan still at the live path | Archived after the model upgrade | No plan rewrite; issue stays the tracker |

## Proposed Solution

In `compatStubMarkdown`, omit the `model` line when the source value is `haiku`, `sonnet`, `opus`, or `fable`. Keep `model: inherit` (and any other non-alias value) as written. Run the generator so the five research stubs lose the line. Add an assertion that those five files have no `model` line and that an `inherit` stub still has `model: inherit`, so a paired edit of generator plus stubs cannot hide a copied alias. Append the measurement to ADR-110. Do not edit `plugins/soleur/agents/engineering/research/*.md`.

## Implementation Phases

### Phase 1: Generator

- Teach `compatStubMarkdown` to skip `model` for the four Claude aliases.
- Regenerate `.grok/agents` so the five research stubs match.

### Phase 2: Guard and record

- Extend `plugins/soleur/test/grok-inspect-contract.test.ts` so a research stub with a `model` line fails, and an `inherit` stub without `model: inherit` fails.
- Add the ADR-110 addendum.

## Files to Edit

- `plugins/soleur/scripts/sync-grok-agent-compat.ts`
- `.grok/agents/soleur-engineering-research-best-practices-researcher.md`
- `.grok/agents/soleur-engineering-research-framework-docs-researcher.md`
- `.grok/agents/soleur-engineering-research-git-history-analyzer.md`
- `.grok/agents/soleur-engineering-research-learnings-researcher.md`
- `.grok/agents/soleur-engineering-research-repo-research-analyst.md`
- `plugins/soleur/test/grok-inspect-contract.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-110-harness-semantic-model-tier-map.md`

## Files to Create

None.

## User-Brand Impact

- **If this lands broken, the user experiences:** a Grok research-agent profile that still warns about `haiku` on startup, or an `inherit` profile that loses its model line and no longer documents inheritance.
- **If this leaks, the user's workflow is exposed via:** no data path. The failure is a wrong model pin on an operator-local agent profile, which either warns or silently runs on the session default.
- **Brand-survival threshold:** `single-user incident`

CPO sign-off is the brainstorm Product assessment (drop the line; do not pin `grok-4.5`). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: "grok-fidelity CI job runs sync-grok-agent-compat --check"
  cadence: "per pull request"
  alert_target: "GitHub check grok-fidelity on the PR"
  configured_in: "plugins/soleur/scripts/grok-fidelity-gate.sh"
error_reporting:
  destination: "GitHub Actions log for the grok-fidelity job"
  fail_loud: "sync-grok-agent-compat --check prints DRIFT compat stub and exits 1"
failure_modes:
  - mode: "a research stub regains a model line"
    detection: "grok-inspect-contract test fails"
    alert_route: "the PR check fails"
logs:
  where: "GitHub Actions job log"
  retention: "GitHub's default run retention"
discoverability_test:
  command: "python3 -c \"import pathlib; root=pathlib.Path('.grok/agents'); hits=[p.name for p in root.glob('soleur-engineering-research-*.md') if any(l.startswith('model:') for l in p.read_text().splitlines()[:12])]; print('omitted' if not hits else 'bad')\""
  expected_output: "omitted"
```

## Guard Contract

### Guard 1 — research stubs omit Claude model aliases

**Property.** No file under `.grok/agents/` whose name starts with `soleur-engineering-research-` contains a `model` line, and every other stub that the generator classifies as `inherit` still contains `model: inherit`.

**Assembly.** The only writer is `compatStubMarkdown` in `plugins/soleur/scripts/sync-grok-agent-compat.ts`. The population is `discoverAgentEntries()`. The check reads generator output against disk (`--check`) and reads the five research filenames plus one `inherit` stub directly in `plugins/soleur/test/grok-inspect-contract.test.ts`.

**Mutation matrix:**

| # | Mutation | Expected |
| --- | --- | --- |
| 1 | Put `model: haiku` back on `soleur-engineering-research-repo-research-analyst.md` only | RED |
| 2 | Delete the new assertions so the test only runs `--check` while both the generator and the stubs still copy `haiku` | RED on the content assertion; a green `--check` alone is the vacuous dispatch this row exists to catch |
| 3 | Add `model: sonnet` to a second research stub after the first is clean | RED |
| 4 | Remove `model: inherit` from `soleur-product-cpo.md` | RED |
| 5 | A clean tree after the generator change | PASS, and this input is not the pre-change tree |

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-110. Do not create a new ADR. The addendum records the 2026-09-23 Grok 1.0.41 measurement and the choice to omit `model` on Grok stubs whose source value is a Claude alias. Decision 4 is unchanged.

### C4 views

No C4 impact. Read `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`, and `spec.c4`. External actors and systems already modelled and unchanged: the operator workstation, `grokBuild` (Grok Build CLI, described as loading the plugin via ADR-110), `plugin` (Soleur Plugin), GitHub, Anthropic. No new human actor, vendor, data store, or access relationship. No cardinality on a workflow or monitor count moves, so `plugins/soleur/test/c4-count-parity.test.sh` is not expected to change.

### Sequencing

The addendum lands in the same change as the generator. Status stays Accepted.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering

**Status:** reviewed
**Assessment:** Carried forward from the brainstorm. Omitting the line does not violate ADR-110 decision 4. A `grok-4.5` session pin is the wrong scope.

### Legal

**Status:** reviewed
**Assessment:** Carried forward. No compliance document and no regulated-data surface.

### Product

**Status:** reviewed
**Assessment:** Carried forward. The warning is the harm. Pinning `grok-4.5` is not. Tier for the Product/UX gate: NONE. No page, component, or flow. No specialist was named.

**Brainstorm-recommended specialists:** none

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` returned 75 issues; none of the bodies contain the generator path, the test path, the ADR path, or the repo-research stub path.

## Acceptance Criteria

- [ ] The five `.grok/agents/soleur-engineering-research-*.md` files have `name` and `description` and no `model` line.
- [ ] `soleur-product-cpo.md` still has `model: inherit`.
- [ ] `plugins/soleur/agents/engineering/research/*.md` still have `model: haiku`.
- [ ] `bun run scripts/sync-grok-agent-compat.ts --check` from `plugins/soleur` exits 0.
- [ ] `plugins/soleur/test/grok-inspect-contract.test.ts` fails if a research stub contains `model:` or if the product stub loses `model: inherit`.
- [ ] ADR-110 has a 2026-09-23 addendum covering the `haiku` warning, the `cheap` warning, the `grok-4.5` then `SetSessionModel` sequence, the unset inheritance flag, and the omit decision.
- [ ] Closes #8604.

## Test Scenarios

- Given the generator and a source agent with `model: haiku`, when stubs are written, then that stub has no `model` line.
- Given a source agent with `model: inherit`, when stubs are written, then the stub still has `model: inherit`.
- Given a research stub that has had `model: haiku` put back, when the test runs, then it fails.
- Given the Claude research agent files, when this change is done, then each still starts with `model: haiku`.

## Sharp Edges

- A plan whose User-Brand Impact section is empty fails deepen-plan Phase 4.6. This plan fills it.
- `--check` alone stays green if the generator and the files both copy `haiku`. The content assertion is the guard that sees that pair.
- Do not write `model: cheap` or `model: grok-4.5` into these stubs.

## References

- Issue: #8604
- Brainstorm: `knowledge-base/project/brainstorms/2026-09-23-grok-agent-haiku-tier-map-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-grok-agent-haiku-tier-map/spec.md`
- ADR-110: `knowledge-base/engineering/architecture/decisions/ADR-110-harness-semantic-model-tier-map.md`
