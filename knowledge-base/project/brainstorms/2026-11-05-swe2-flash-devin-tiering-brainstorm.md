---
title: SWE-2 Flash adoption on the Devin harness — docs + routing, not a tier-map row
date: 2026-11-05
lane: cross-domain
brand_survival_threshold: single-user incident
related_adrs: [ADR-053, ADR-110]
---

# Brainstorm: SWE-2 Flash on the Devin harness

## What We're Building

Cognition released SWE-2 Flash on 2026-11-04: ~1/5 the price and ~3x the speed of SWE-2
(200 vs 60 tok/s, 276B-A12B MoE mid-trained on Inkling-Small), live in Devin CLI/Desktop
today. Verified slugs via `devin models` (2026-11-05): `swe-2-flash-medium` / `-high` /
`-max` under family `swe-2-flash` — all marked `Free, new`, and Cognition states Flash is
free in Devin through 2026-11-30. No post-promo rate card is published.

This feature routes Soleur's cheap-tier subagent work on the **Devin harness** onto the
Devin-native cheap mechanism — read-only spawns go to `subagent_explore` (the server-side
router's default subagent model), and the operator can pin that default to
`swe-2-flash-medium` via the user-scope `agent.subagent_model` config. It also corrects a
stale claim in `devin/INSTRUCTIONS.md` ("Claude model aliases are not Devin model
identifiers" — measured false: `opus`/`sonnet`/`swe`/`codex`/`gemini`/`gpt` are documented
family aliases resolving to latest-in-family), records an ADR-110 addendum, and adds a
Devin row to `model-launch-review`'s per-release freshness checklist.

Explicitly **not** built now: a `TIER_MAPS.devin` row with a literal SKU and generated
`.devin/agents/` custom subagent profiles. That machinery is deferred behind a measured
gate — see Key Decisions.

## Why This Approach

Two domain leaders (Engineering/CTO, Operations/COO) assessed independently and converged:

- **No delivery channel for a per-call pin exists in Soleur today.** `run_subagent` takes
  a profile, not a model; `harness.ts`'s `spawnAgent` devin arm instructs "inherit the
  session model". The only Devin levers are: profile choice (`subagent_explore` → router
  default; `subagent_general` → always parent model), `model:` on a custom subagent
  profile (experimental), `model:` on skill frontmatter, and user-scope
  `agent.subagent_model`.
- **A literal `swe-2-flash` pin violates ADR-053's absolute-pin criterion.** Free-tier
  Devin plans only get SWE-1.6, and org admins can restrict models — a forbidden pin is
  silently ignored (team default used), which is silent tier degradation, not an error.
  The router is the always-available entity, not any SKU.
- **`TIER_MAPS.devin` would have no consumer.** `harness-model-map.ts` is a canonical spec
  consumed by tests and read as prose; nothing at Devin spawn time resolves it. A
  non-inherit row earns its keep only alongside generated custom profiles — machinery for
  a need (write-capable cheap spawns) that does not exist yet, gated on an unverified
  unknown (whether plugin `agents/` register as `soleur:<name>` profiles on current CLI;
  a 2026-10-09 measurement says only the two built-ins are exposed, and Soleur's nested
  `agents/<domain>/...` tree does not match Devin's flat `agents/<name>.md` layout).
- **The free window is the measurement period.** Flash is free through 2026-11-30; the
  `1/5 price` claim is a ratio with no published rate card. Adopting the router path now
  captures the intended savings with zero code and lets a quality/cost measurement decide
  whether profile machinery is worth building before the window closes.

## Key Decisions

- **Route read-only spawns to `subagent_explore`:** the five `model: haiku` research
  agents (`agents/engineering/research/*`) and other read-only fan-out should spawn as
  `subagent_explore` on Devin — the profile lands on the router's default subagent model,  <!-- amended at PR #12135 review: shipped mapping is rule-form — researchers stay subagent_general -->
  which the operator (or an org admin) can pin. `subagent_general` is reserved for
  write-capable work and always inherits the parent model. Ruled by CTO agent.
- **Document `agent.subagent_model: "swe-2-flash-medium"` as an operator opt-in**, not a
  plugin default: it is user-scope config (cannot be committed to project
  `.devin/config.json`), must be org-allowed, and overrides the router and admin default.
- **All tiers stay `inherit` on Devin:** no `TIER_MAPS.devin` row is added. The warn→inherit
  fallback in `resolveModelTier` already covers Devin; adding a row with only `inherit`
  values is noise. `devin-harness.test.ts`'s `"Inherit the session model"` pin stays true.
- **Fix the stale aliases claim** in `devin/INSTRUCTIONS.md`: Claude family aliases DO
  resolve on Devin. This is a standalone correction riding along because it was discovered
  here and is wrong independently of this feature.
- **ADR-110 addendum** (not a new ADR): records the measured `devin models` output, the
  router-not-SKU decision, the org-allowlist silent-degradation caveat, and the Free-plan
  availability boundary.
- **Devin freshness row in `model-launch-review`:** a third-vendor checklist item —
  compare `devin models` output against any Devin slugs Soleur references, on the Grok
  item-6 pattern. Productize candidate absorbed here: per-Cognition-launch re-check is a
  recurring task, and the checklist is the artifact.
- **Deferred (measured gate):** `TIER_MAPS.devin` + `sync-devin-agent-compat.ts` profile
  generator + drift test, unblocked only when all three measurements land: (a) plugin
  `agents/` (or committed `.devin/agents/`) profiles verified invocable on current Devin
  CLI, (b) forbidden-model pin behavior measured (fail vs silent reroute), (c) post-promo
  Flash rate card published. Filed as a follow-up issue.

## Open Questions

- Does `devin` CLI's subagent router actually pick Flash-class models by default during
  the free window? (Undocumented; the router list "can change over time".)
- What does a forbidden-model `model:` pin do on a custom profile — fail or silently
  reroute? (Undocumented; measurement needed before any pin ships.)
- Does the org's Devin usage dashboard break spend down per model? Without it, per-subagent
  cost attribution is unverifiable — Soleur's per-run tier `log()` line is the only record.
- Is `model: haiku` in plugin agent frontmatter inert on Devin forever, or does Devin's
  family-alias resolver accept `haiku`? If plugin agents ever register as profiles, that
  pin could silently bill Anthropic inside a Devin session — generator must translate it
  (Grok `sync-grok-agent-compat.ts` precedent).

## Domain Assessments

**Assessed:** Engineering, Operations

### Engineering (CTO)

- Canonical-spec reality: `harness.ts`/`harness-model-map.ts` are specs consumed by tests,
  not runtime dispatch on Devin; "wiring the spawn path" = changing instruction text +
  delivering a model-bearing profile.
- Recommendation: `cheap → swe-2-flash` only if a consumer ships; `standard`/`strong`/
  `advisor` → `inherit` is the honest value (heterogeneous Devin families make any absolute
  pick a potential downgrade).
- Preferred sequence: (1) `agent.subagent_model` opt-in docs, (2) read-only spawns to
  `subagent_explore`, (3) profiles only after the registration probe.
- If profiles ever ship: `harness.ts:394` instruction text, `devin/INSTRUCTIONS.md`
  Domain-agents section, profile generator + drift check (Grok `--check` precedent), and
  `model: haiku`→cheap-SKU translation.
- ADR: ADR-110 addendum, not a new ADR (Grok/OpenCode rows landed as dated addenda).

### Operations (COO)

- Billing: credits/ACU at payment layer but a per-token per-model meter — router pricing
  genuinely cuts marginal cost for the traffic it covers. Flash free through 2026-11-30
  on paid plans; no published post-promo rate card (implied ~$0.60/$3 per 1M, unverified).
- Org policy: Default-subagent-model = None disables `run_subagent` org-wide; a specific
  model forces unpinned customs; user `subagent_model` still overrides admin default.
  Forbidden-pin behavior (fail vs silent reroute) undocumented — must be measured.
- Plan gate: Free-tier plans get only SWE-1.6 — no `swe-2-flash` SKU is always-available;
  the router is the always-available entity.
- Spend visibility: Devin CLI does not label a running subagent's model; Soleur's tier
  `log()` line is the only in-repo attribution trail. `expenses.md` has no Devin row at all.
- Scope: profile pins are local-only — cloud sessions stay router/parent regardless;
  coverage trailers stay honest.

## Next Steps

→ Use `skill: soleur:plan` for implementation details (docs edits, ADR-110 addendum,
model-launch-review row, follow-up issue for the deferred profile machinery).
