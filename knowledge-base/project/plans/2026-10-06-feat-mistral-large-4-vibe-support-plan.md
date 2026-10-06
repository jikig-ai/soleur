---
title: "feat: Mistral Large 4 + Mistral Vibe support (staged)"
date: 2026-10-06
slug: mistral-large-4-vibe-support
issue: 9648
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-mistral-large-4-and-vibe-support
---

## Overview

Add Mistral support to Soleur in gate-staged slices: dogfood Mistral models (ML4 preview API / Devstral) through vehicles that need no new harness (Codex custom `model_providers`, #1215 BYOM proxy), then a Mistral Vibe CLI harness adapter (skills-only v1, Agent Plugins 1.0 package, consuming the #9609 checklist once #9608's measurements stabilize it), then a flagged BYOK `mistral` provider gated on the legal train, plus small-class self-hosted open weights (Devstral Small 2 / Mistral Small 4, single GPU) under the ADR-120 spend gate — with ML4 frontier self-host tracked only (#9649). Phase A's primary beneficiary is positioning/distribution (harness-neutrality proof + Vibe marketplace optionality), not current users (CPO F7). The latent upside: BYOK key → Hetzner (EEA) → Mistral (EEA) is an end-to-end EU-resident inference path Anthropic/OpenAI BYOK cannot offer — claim locked until the legal train makes it true (CPO F11). An honest "evaluating" content piece ships inside the Oct 6→27 preview news window; capability claims wait for the eval table and legal train.

## Problem Statement / Motivation

Soleur has zero Mistral support (`git grep -il mistral` outside KB → only `plugins/soleur/skills/dspy-ruby/references/providers.md`). Mistral Large 4 shipped a public-preview API on 2026-10-06 with open weights promised ~Oct 27, and Mistral Vibe is an Apache-2.0 agentic CLI that natively loads `SKILL.md`. The operator's ask is EU-sovereignty positioning: Soleur users should be able to use this model and harness. Each surface (model dogfood, harness adapter, BYOK provider, self-host, content) has a different gate, so they ship as separate stages rather than one coupled PR.

## Proposed Solution

| Stage | Piece | Gate | PR shape |
|---|---|---|---|
| 0 | Hedge content ("harness-neutral, evaluating") | none | docs-only PR |
| 1 | A0 — model dogfood on existing vehicles (Codex `model_providers` / #1215 proxy path) | Mistral Studio API access | runbook + measured eval table on #9648 |
| 2 | A — Vibe as a new harness, skills-only, shipped as an **Agent Plugins 1.0 package** (operator-chosen) | A0 eval signal + prefers #9608 slice-1 merged | adapter arm + `vibe/` plugin tree + INSTRUCTIONS.md |
| 3 | B — BYOK `mistral` provider behind default-off flag | A0 eval signal + legal train (FR4) before flag-on | provider row + flag + keyed consumer |
| 4 | C1 — small-class self-host dogfood (Devstral Small 2 / Mistral Small 4) | operator spend ack + license memo + #6546 soak green | GEX44-shape runbook additions; host order is post-merge follow-through |
| — | C2 — ML4 frontier self-host | weights + license + hardware | tracked by #9649 only |

## Implementation Phases

**Two disjoint trust domains (arch P1):** the `vibe` harness arm lives plugin-side on the operator's machine; the `mistral` BYOK credential lives server-side. A Vibe session **cannot** consume a stored `mistral` BYOK key (`EXCLUDED_FROM_SERVICES_UI` blocks `getUserServiceTokens`→`buildAgentEnv`; `AgentAuthScheme` is anthropic-only), and a Vibe session **can** use an operator-local `MISTRAL_API_KEY` today with zero changes and zero legal gate — that local key is what A0/eval dogfood actually uses. "Store your Mistral key in the product" and "my Vibe session uses it" are unrelated paths in both directions.

### Phase A0 — Model dogfood on existing vehicles (no new harness)

- **Measured gate first:** Codex ≥0.59 (this repo pins 0.156.1) speaks `wire_api = "responses"` only — the real question is whether `https://api.mistral.ai/v1` serves `/v1/responses`, not generic OpenAI-compat. Probe live before committing to the Codex vehicle.
- **Codex path caveat (measured):** Codex ignores `model_provider`/`model_providers`/`profile` in project-local `.codex/config.toml` — provider config must live in `~/.codex/config.toml` or a `--profile` file on the dogfood host/operator machine. Ship a runbook recipe + host config seed, NOT a repo `.codex/config.toml` edit and NOT a `setup-codex.sh` install step.
- **Fallback vehicle:** the #1215 Ollama+`claude-code-proxy` pattern against a Mistral OpenAI-compatible endpoint works regardless of the Responses-API answer.
- **Measure:** `grok-measure.sh` hardcodes the `grok` binary; reuse its prompt classes + `--parse-only` NDJSON summarizer against a Codex/Vibe stream via a thin shape adapter (or a `mistral-measure.sh` sibling). Publish the eval table on #9648.
- Nothing in this phase is customer-facing; it is operator dogfood producing the quality signal that gates stages A and B (C1 gates on its own spend/license/VRAM gates — a weak hosted-API result can be evidence *for* self-hosting, not against it).

### Phase A — Vibe harness adapter (Agent Plugins 1.0 package)

**Measurement gate (runs BEFORE `harness.ts` is touched — advisor-consult finding):** in a live Vibe session, exec a probe script dumping `env`, `argv`, `process.title`, and `/proc/$PPID` ancestry — note `/proc` is Linux-only, so macOS detection may have no marker at all and `SOLEUR_HARNESS` becomes the load-bearing path there (argv heuristics inspect the *child's* argv — `node monitor.sh`, never `vibe` — so parent-ancestry walking is the candidate mechanism, not argv matching); install a minimal one-skill `.vibe-plugin` package and confirm skills load + are operator-invocable. Record results on #9648. **The gate emits a cut decision:** Agent Plugins 1.0 package OR `.agents/skills` path-sharing — the loser does not ship; do not carry two delivery tracks past the gate. If no marker is reachable, detection shifts from "detect and arm" to "declare/configure" and every arm below re-scopes — do not generate 103 marker blocks against an unproven primitive. Also measure `.vibe/hooks.toml` `pre_tool` blocking, the `task` primitive, and **whether Vibe's plugin loader substitutes `${CLAUDE_PLUGIN_ROOT}` in plugin content** — ~100 skills emit bare `${CLAUDE_PLUGIN_ROOT}/…` anchors (ADR-179 A18) which dead-end under Vibe if unsubstituted; `vibe/INSTRUCTIONS.md` carries the equivalent convention (precedent: `codex/INSTRUCTIONS.md:14` "set CLAUDE_PLUGIN_ROOT to the verified installed root").

- **Detection contract:** `SOLEUR_HARNESS=vibe` lands as an explicit configured override — precedence pinned: exported env markers (CLAUDECODE/CODEX_THREAD_ID/etc.) **> `SOLEUR_HARNESS`** > argv heuristics (a real harness's own marker beats an inherited stale override; the override exists for sessions with no marker — on conflict, warn rather than silently pick). Value is validated against the union (`SOLEUR_HARNESS=vibbe` warns, not silent `unknown`), and `setup-vibe.sh` or INSTRUCTIONS.md owns how it durably reaches Vibe sessions. Add a conflict fixture in `harness.test.ts` (precedence-test pattern at :79-95). (`detectHarness` already accepts an injected env — no extra test seam.) The `unknown` fallthrough gets an explicit, non-Claude arm — today `invokeSkill`/`spawnAgent` default to "Invoke via the Skill tool"/"Use the Task tool" (Claude-isms a Vibe session cannot execute), and `go.md`'s `harness-forms` fallback (:508) would tell a Vibe user to install a *different* harness. Add a `vibe` line to that fallback and an `unknown`-safe declaration. `spawnAgent`'s vibe arm emits an inline-execution instruction (the sequential-fallback contract), not a spawn-tool name Vibe lacks. Guard the `vibe` token against false-positives — `\bvibe\b` matches the repo's own `vibe-coding` content paths (the `env === process.env` guard at harness.ts:103 is the scar from Grok's argv false-positive).
- **No-marker contingency:** if measurement finds nothing reliable, the union member still ships but `INSTRUCTIONS.md` documents "detection stays `unknown`; run skills by reading SKILL.md directly" — an honest degrade, never a claimed detection.
- **Rule-corpus note (structural, not pending measurement):** Vibe's `hooks.toml` has `pre_tool`/`post_tool`/`post_agent` and **no SessionStart event** — `session-rules-loader.sh` can never run; AGENTS.rules.md is absent in Vibe sessions. INSTRUCTIONS.md states "absent" plainly.
- `scripts/setup-vibe.sh` writes `enable_telemetry = false` into BOTH layers (project `./.vibe/config.toml` beats user `~/.vibe/config.toml` — ship the key in the repo's `.vibe/config.toml` too) with a TOML-aware merge-or-refuse policy (the `cmp -s` refuse-if-differs precedent doesn't fit editing one key inside an existing file); discloses `log_interactions = true` local session logs.
- **Measurement-gate additions:** does Vibe's plugin scanner reject a package whose directory carries sibling foreign manifests (`.claude-plugin`/`.codex-plugin` beside `.vibe-plugin` — "ambiguous markers" rule)? Does `${CLAUDE_PLUGIN_ROOT}` substitute in plugin content? Does `allowed-tools` enforce literally?
- `plugins/soleur/lib/harness.ts`: add `"vibe"` to the `Harness` union (:22) + `detectHarness` (:80) marker + `formatSkillInvocation`/`invokeSkill`/`spawnAgent`/`pollInstructions`/`routingInstructions` arms (or explicit honest-degradation where a primitive is absent) — plus the sibling-arm sites `harness-parity.ts` (`Attribution`, `BOUNDARY` re-read obligation :146-151), `workflow-fidelity.ts`, `pr-merge-poll.ts`.
- `plugins/soleur/lib/harness-model-map.ts`: no TIER_MAPS row required — unmapped harnesses already warn→inherit (`resolveModelTier` :49-63); the 7 pinned workflow fences stay green even with a `vibe` marker added (both sides resolve `inherit`; `harness-model-map.test.ts:218-274` compares outputs) — re-fencing is required ONLY if `TIER_MAPS.vibe` ever gains a real SKU row, which v1 avoids.
- **No per-skill fleet block (decision):** the 104 `grok-harness-invoke` blocks exist because Grok has no skill primitive; Codex/Devin added zero. Vibe loads SKILL.md natively, so v1 ships **no `vibe-harness-invoke` marker block** — reversal trigger: measured inability to follow canonical `soleur:<name>` references.
- **`disable-model-invocation` class (CTO finding — safety):** Vibe's frontmatter set (`name`/`description`/`user-invocable`/`allowed-tools`) has no `disable-model-invocation` — the 8 operator-gated skills (`user-set-role`, `provision-*`, `flag-delete`, `cf-token-scope`, `admin-ip-refresh`) would become model-invocable under Vibe. The package must exclude them from its skills root (or `setup-vibe.sh` writes a disabled filter) and INSTRUCTIONS.md discloses it. Also measure `allowed-tools` name-mapping (`Bash`/`Read` vs Vibe's `read_file`/`bash` — 4 skills carry Claude names).
- Ship the plugin as an **Agent Plugins 1.0 package** (`plugin.json` + `skills/` + optional `mcp.json`/`ai.mistral.vibe` extension) — operator decision, replaces the path-shared `.agents/skills` assumption; opens a Vibe-marketplace listing later. Canonical skill tree stays the source; thin wrappers/generated names follow the Codex/Devin pattern (ADR-245: never a hand-copied tree).
- `plugins/soleur/vibe/INSTRUCTIONS.md` documenting supported surfaces, hooks/guardrails disclosed as **unverified/unused** (not "unsupported" — if `pre_tool` blocking measures green the disclosure upgrades), and sequential-fallback for agent fan-out with a `Reviewed-Coverage: sequential-fallback` disclosure (mirrors `codex/INSTRUCTIONS.md:63-65`'s never-claim-independent-review honesty clause).
- Harness-parity test additions (including an **exhaustive-membership enumeration test** so a sixth harness can't silently miss a surface — none exists today) + a non-required `harness-discovery` arm (`driveVibe` ~60-80 lines by precedent, `VIBE_PIN` in ci.yml AND `test/README.md`, sha256-pinned install, `continue-on-error` until soak — #8574 owns promotion).
- **Phase A prerequisite read:** `knowledge-base/engineering/architecture/principles-register.md` AP-021/AP-025 (cited in harness-parity/discovery comments) before writing the arms.
- **Eval-table row schema (the signal that gates stages A and B):** `prompt-class | vehicle | model | CLI version+pin | date | pass criterion | result | verifier | cost columns`. `grok-measure.sh` emits only perf/cost (`ttft_ms`, `tok_per_sec`, `total_cost_usd`, `num_turns`, `exit_code`) — a run can be fast, cheap, and wrong, so the pass criterion is **exit code AND artifact-presence** (e.g. `<promise>DONE</promise>` marker / brainstorm+spec files on disk), and "one pipeline skill completes its gates under Vibe" names the gate output that proves completion. **Decision rule for the signal:** if the measured vehicle fails ≥ half the prompt classes, stages A/B defer (recorded on #9648) rather than proceeding on a weak model — C1 is unaffected by this rule (DHH P1 reconciliation).

### Phase B-0 — standalone live-defect fixes (ships FIRST, not gated)

Two verified defects need no Mistral anything and must not ride the legal train (DHH P1):

- `agent-on-spawn-requested.ts:709` `MODEL_PRICING[model] ?? {zeros}` is a **latent fail-open** — `leaderModule.model` is typed `AnthropicModelId` so the arm is unreachable today, but it bills $0 into the WORM `audit_byok_use` ledger the day any non-union model reaches the lookup (Mistral's keyed path is exactly that future). Fix to fail-closed now; the fix is cheap hardening, not a new bug.
- `app/api/keys/route.ts:32` `body.provider === "openai" ? "openai" : "anthropic"` silently coerces any unrecognized provider to anthropic — a typo'd provider POSTs the user's key to `api.anthropic.com` for validation. Replace with an explicit allowlist + 400 — independent of whether `mistral` ever lands.

### Phase B — BYOK `mistral` provider (flagged)

The `openai` BYOK precedent is the 4-site shape: Provider union + `PROVIDER_CONFIG` + DB CHECK + validator + a consumer path.

**Named consumer (DHH P0 / CPO F5 / simplicity P1):** the flag-gated path is `apps/web-platform/server/email-triage/summarize.ts` — the existing non-agentic read-only LLM summarizer. When the `mistral` flag is on AND the user holds a validated `mistral` key, that call routes through `api.mistral.ai` on the user's key instead of the Anthropic SDK. Observable user effect: "inbox summaries run on your Mistral key." Its metering uses a small provider-keyed registry `server/mistral-pricing.ts` owned by the call site — NOT `MODEL_PRICING` (its keys are pinned to `AnthropicModelId` by `model-tiers.test.ts:99`).

- `apps/web-platform/lib/types.ts:609` — `Provider` += `"mistral"`; `api_keys_provider_check` DB constraint needs a new migration (precedent: `supabase/migrations/139_openai_api_key_provider.sql`).
- `apps/web-platform/server/providers.ts:9` — `PROVIDER_CONFIG` += `mistral: { envVar: "MISTRAL_API_KEY", category: "llm", label: "Mistral" }`; **`mistral` MUST land in `EXCLUDED_FROM_SERVICES_UI` in the same diff** (spec-flow P0 — the exclusion set does triple duty: `services/route.ts:21-26` `isValidServiceProvider` would accept `POST /api/services` for any PROVIDER_CONFIG key not excluded, `agent-runner.ts:357` `getUserServiceTokens` would inject `MISTRAL_API_KEY` into every agent subprocess env, and the Connected Services UI would list it before legal disclosures exist). A later "dedicated channel" change class re-gates both consumers — say so; it is NOT this plan. Same diff updates the `EXCLUDED_FROM_SERVICES_UI` comment — members today are excluded as *multi-value credentials*; `mistral` is single-value, excluded for gating/legal reasons — record the reason per member so Guard 3's pairing documents why, not just that.
- `server/token-validators.ts:11` `VALIDATOR_CONFIGS` += mistral entry (`api.mistral.ai/v1/models` Bearer) — missing config ⇒ `validateToken` returns false (:72).
- `app/api/keys/route.ts` — ordering pinned: allowlist-400 → flag-403 → `validateToken` → upsert (a flag-check placed after `validateToken` still leaks the submitted key to `api.mistral.ai` flag-off — server→Mistral traffic pre-DPA).
- **Flag-wrapped surfaces (enumerate all four):** store (`POST /api/keys` — flag-check 403, matching the `credential_type === "oauth_token"` precedent at :41-52), validate-probe (`validateToken` calls Mistral live at save — server→Mistral traffic that must not predate the DPA), env-inject (closed by `EXCLUDED_FROM_SERVICES_UI`), consume (the keyed path). Flag wraps store + consume at minimum.
- **Key lifecycle:** `/api/keys` has no DELETE and `DELETE /api/services` rejects excluded providers — a stored mistral key is currently undeletable. Phase B adds a delete path (extend `/api/keys` with a provider-scoped DELETE, or allow `mistral` specifically in services DELETE). v1 stores via the API surface only — no settings UI (which would re-tier the UX gate to BLOCKING).
- Credential read: mirror `codex-credential-provider.ts:64` `createCodexApiKeyProviderForUser` (direct `api_keys` read + decrypt, independent of `byok-lease`) — the lease is anthropic-only by construction; widen `fetchProviderRow`/`getAgentCredential` only if a lease-consuming path materializes.
- `MODEL_PRICING` gets **no `mistral` rows** — `model-tiers.test.ts:99` pins its keys to `AnthropicModelId` exactly, and the named consumer (email-triage summarize) never reaches :709; mistral metering lives in `server/mistral-pricing.ts`. The `?? {zeros}` latent fail-open fix itself ships in Phase B-0, not here.
- Flag plumbing (codex-engine shape verbatim): `lib/feature-flags/server.ts` `RUNTIME_FLAGS` += `mistral` default-off; per-org rollout needs NO new mechanism — Flagsmith identities already carry `orgId` traits (`server.ts:160-161`), so a Flagsmith org segment gates it (do NOT reuse `ENGINE_ROLLOUT_FLAGS`, which is engine-registry-keyed — a provider is not an engine). `FLAG_MISTRAL=0` is **present** in Doppler from the start (the `flag-create`/`codex-engine` convention; the role-blind-outage risk only materializes at `=1`), and `verify-required-secrets.sh` `MIRROR_FLAGS` += `FLAG_MISTRAL` in the same diff. Flag-fixture tests pinning RUNTIME_FLAGS (`kb-layout-panels.test.tsx:120`, `feature-flag-provider.test.tsx:13,22`, `c4-workspace.test.tsx:26`, `c4-diagram.test.tsx:19`, `server.test.ts`) extend in the same diff.
- **Flag-on checklist** also carries: the legal train merged AND roadmap line L29/#9500's canonical model-support claim updated to include Mistral — capability must not land while published copy contradicts it (CPO F2).
- Concierge stays on the Claude SDK. Flag flips only after the Phase-B legal train merges.

### Phase B-legal — the legal train (blocks flag-on)

- Mistral AI SAS sub-processor artifacts per the openai.md evidence-record shape: DPA snapshot under `knowledge-base/legal/data-processing-agreements/`, Privacy Policy §5.1, DPD §2.3 + sub-processor table, GDPR Policy §4.2 + balancing entry, T&C §3a.5/AUP, Art. 30 PA-22/PA-23 + vendor row, `compliance-posture.md`, both doc mirrors + SHA re-pins, T&C version bump, CLO attestation.

### Phase C1 — Small-class self-host dogfood

- Extend the GEX44/Robot runbook shape for Devstral Small 2 (24B, Apache-2.0, already released) or Mistral Small 4 (119B MoE) on a single-GPU host: ledger row (`approved-not-billing`) before order, license memo, loopback-only inference (vLLM/Ollama), no private-net, no passwordless sudo, YOLO off, destroy = Robot cancel. **VRAM-fit check before the ledger row** — cite the runbook's existing ≤20 GB pre-pull bound (`grok-build-hetzner-dogfood.md:164`) as precedent; the delta is the card class — a 119B MoE does not fit unquantized, so the runbook requires a quantization+VRAM calculation against the target card before any order (Devstral Small 2 at 24B is the safe default).
- **Demand framing (DHH P1):** the ledger row also requires one of (a) #9651 returning positive demand signal, or (b) the operator explicitly recording C1 *as* the demand test ("rent one GPU for a month to prove the sovereignty story boots") — either is honest; neither lets spend float on vibes.
- Host order is post-merge follow-through gated on operator spend ack + live stock check + #6546 soak green (or an explicit parallel-capacity note — two GPU dogfood hosts double operational surface mid-Phase-4).
- Same three `grok-measure.sh` measure classes; comparison table posted on the umbrella.

### Phase 0 — Hedge content ("evaluating" post)

- **Deliverable:** `knowledge-base/marketing/distribution-content/2026-10-XX-mistral-evaluating-thread.md` — an X/Bluesky technical-register thread (not blog — a mechanism-first post violates the blog's founder-register contract per #8774; a founder-problem-first reframe is a CMO call, not default). Publish target ≤ **Oct 13** (news-window decay is steepest week one; Oct 26 wastes it).
- **Producer chain:** `soleur:marketing:copywriter` drafts → `soleur:marketing:fact-checker` verifies vendor-reported facts (1T params, pricing, Oct 27 weights date, Apache-2.0 — attribution per brand-guide) → CLO reviews sovereignty phrasing. Declarative process register ("we're running Mistral Large 4 through the same gates every model passes"), never hedge-words.
- **Copy rules:** "Mistral Vibe" in full, never bare "Vibe" (collides with Soleur's own anti-vibe-coding position); sovereignty framed as *user choice of model/key* — not a positioning commitment (#9651 is unvalidated).
- **Pre-commit:** publish the eval table positive OR negative — "we measured, here's the table, here's why we're waiting" is the stronger brand move. Oct 27 (weights drop) is a second news event — the thread carries the sequel hook.
- **Per-stage allowed-claims table** (CMO+CLO signed, lives in the brainstorm/this plan): stage 0 = "evaluating"; stage A0+eval = "we measured (table)"; stage A + flag-on = "run Soleur skills under Mistral Vibe / bring your Mistral key"; C1 = "self-hosted small-class Mistral weights"; never = "EU-sovereign" / "data never leaves the EU" / "GDPR-compliant Mistral".
- **Roadmap placement (CPO F1):** add #9648 to the roadmap's Post-MVP table or verify it carries the `Post-MVP / Later` milestone — an open issue with no milestone is unsorted until placed (roadmap.md rule).

## Files to Edit

Phase A (adapter):

- `plugins/soleur/lib/harness.ts` — `vibe` union member (:22) + arms (:80/:120/:150/:217/:250/:323/:440)
- `plugins/soleur/lib/harness-parity.ts` — `Attribution` union + `POPULATION_GLOBS` + BOUNDARY comment update
- `plugins/soleur/lib/workflow-fidelity.ts` — `formatSkillRef`/`invokeSurface`/`pipelineInvocationSuffix` arms
- `plugins/soleur/lib/harness-model-map.ts` — nothing required v1 (unmapped→inherit); fences re-generate only if a real `TIER_MAPS.vibe` SKU row ever lands
- `plugins/soleur/lib/pr-merge-poll.ts` — optional arm (default suffices if honest)
- ~~`plugins/soleur/hooks/hooks.json` + `vibe-session-start.sh`~~ — REMOVED: Vibe has no SessionStart event (`pre_tool`/`post_tool`/`post_agent` only); any hook work belongs in the package's `ai.mistral.vibe/hooks.toml` and only if measured green
- `commands/go.md` `<!-- harness-forms:start/end -->` blocks (:482-509, :549-553, :569-571) + Step 2.1 (:535-545)
- `plugins/soleur/test/` — `harness.test.ts`, `harness-model-map.test.ts`, `harness-parity*.test.ts`, `harness-tool-map.test.ts` (needs vibe INSTRUCTIONS.md `## Tools` table), `components.test.ts` `manifestDirs` pin (:1387) + `ACKED_CROSS_ROOT_DUPES` (:1362)
- `.github/workflows/ci.yml` — `harness-discovery` job gains a vibe arm (`VIBE_PIN`, sha256-pinned install, `continue-on-error`)
- `plugins/soleur/scripts/harness-discovery-smoke.ts` — `vibe` arm (:39 union + drive/parse arms)
- `.gitignore` (`.vibe/*` + `!.vibe/config.toml` carve-out — mirrors `!.codex/config.toml` :29)
- `README.md` + `plugins/soleur/README.md` + `CONTRIBUTING.md` — Vibe install surface; also fix the stale harness table at README.md:192-199 (lists only Claude/Grok today)
- `apps/web-platform/test/README.md` — `VIBE_PIN` alongside the discovery job pin
- `knowledge-base/engineering/architecture/diagrams/{model,views}.c4` — `mistral` external + `vibeCli` element + edges

Phase B (BYOK provider):

- `apps/web-platform/lib/types.ts:609` — `Provider` += `"mistral"`
- `apps/web-platform/server/providers.ts` — `PROVIDER_CONFIG` row + `EXCLUDED_FROM_SERVICES_UI` membership (same diff — Guard 3)
- `apps/web-platform/server/token-validators.ts` `VALIDATOR_CONFIGS`
- `apps/web-platform/app/api/keys/route.ts` + `app/api/services/route.ts` — explicit allowlist-400 at :32 + flag-gated store + provider-scoped delete path
- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts:709` — fix `?? {zeros}` fail-open (mistral pricing lives in a separate provider-keyed registry, NOT this map)
- `apps/web-platform/server/agent-env.ts` — `AgentAuthScheme`/env channel if mistral is agent-consumed (else EXCLUDED_FROM_SERVICES_UI is enough)
- `supabase/migrations/` — extend `api_keys_provider_check` (precedent: `139_openai_api_key_provider.sql`)
- `apps/web-platform/lib/feature-flags/server.ts` `RUNTIME_FLAGS` — `mistral` flag (default-off, per-org segment decision)
- `apps/web-platform/scripts/verify-required-secrets.sh` — `MIRROR_FLAGS` += `FLAG_MISTRAL`
- flag-fixture tests pinning RUNTIME_FLAGS keys: `kb-layout-panels.test.tsx`, `feature-flag-provider.test.tsx`, `c4-workspace.test.tsx`, `c4-diagram.test.tsx`, `lib/feature-flags/server.test.ts`
- `apps/web-platform/test/providers.test.ts` — exclusion-pairing guard row
- `knowledge-base/legal/` + `docs/legal/` + `plugins/soleur/docs/pages/legal/` — B-legal train (Phase B-legal)

Phase A0/C1 (runbooks + dogfood):

- `knowledge-base/engineering/operations/runbooks/` — Mistral dogfood additions (Codex `~/.codex/config.toml` `model_providers` recipe, GEX44-class C1 section)
- `scripts/dogfood/` — thin shape adapter reusing `grok-measure.sh` `--parse-only` (or `mistral-measure.sh` sibling)

## Files to Create

- `plugins/soleur/.vibe-plugin/` Agent Plugins 1.0 package (`plugin.json` + `skills/` + optional `mcp.json`/`ai.mistral.vibe` ext) — Phase A
- `plugins/soleur/vibe/INSTRUCTIONS.md` (+ `vibe/skills/` thin wrappers if the plugin manifest requires them) — Phase A
- `plugins/soleur/test/vibe-plugin.test.ts`, `vibe-setup.test.ts`, `vibe-harness.test.ts` — Phase A
- `scripts/setup-vibe.sh` — Phase A (moved from Files to Edit — it doesn't exist)
- `.vibe/config.toml` (repo root) — `enable_telemetry = false` at project layer — Phase A
- `apps/web-platform/server/mistral-pricing.ts` — provider-keyed pricing registry owned by the summarize consumer — Phase B
- `knowledge-base/engineering/architecture/decisions/ADR-274-*.md` (provisional ordinal) — Phase A
- `knowledge-base/legal/data-processing-agreements/mistral.md` — Phase B-legal
- `scripts/dogfood/mistral-measure.sh` (if the shape adapter is cleaner as a sibling) — Phase A0

## User-Brand Impact

*(Carried from brainstorm 2026-10-06.)*

- **If this lands broken, the user experiences:** a Vibe/`mistral` option that dead-ends, silently bills $0 against a BYOK cap, or a marketed "EU-sovereign"/"runs on Mistral" claim the product cannot keep.
- **If this leaks, the user's [data / workflow / money] is exposed via:** user content reaching Mistral AI SAS without a DPA/disclosure update; an exposed inference port on the dogfood host; Vibe telemetry on customer repos if Soleur ships config.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** a new model sub-processor + new harness + new vendor surface — any one can silently reach a user's content or invoice; the worst single-user outcome is a real breach, not a cosmetic bug.

CPO sign-off required at plan time; `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Research Insights

**Premise Validation (Phase 0.6):** all cited refs verified live — #9648 OPEN, #9649–9651 OPEN deferred, #9608 OPEN (Cursor adapter in flight, draft PR #9598), #9609 OPEN (checklist deferred until Cursor measurements), #1215 OPEN (BYOM doc), #6546 OPEN (GEX dogfood post-merge soak), #6547 OPEN (Concierge epic, parked), PR #6597 MERGED. `Harness` union confirmed `claude|grok|codex|devin|unknown`; `TIER_MAPS` covers claude+grok only. No stale premises.

**Property List (Phase 0.6b):** (1) Mistral model callable from Soleur before any adapter exists — bought by A0 via existing Codex/proxy vehicles, no new mechanism; (2) Soleur skills runnable under Vibe — needs the harness arm + plugin package (the only genuinely new mechanism); (3) user-supplied Mistral key usable in product — bought by extending the existing `Provider`/`api_keys` registry, no new mechanism; (4) open-weight self-host dogfood — bought by reusing the GEX44 runbook substrate, no new mechanism. **Cut List:** none — every stage maps to an existing primitive except the harness arm itself.

**Community/discovery (functional-overlap):** no install candidates. Reference prior art: `wshobson/agents` adapter framework (no Vibe adapter exists), `claude-octopus` PR #402 (Vibe dispatch + `~/.vibe`/env detection pattern), `adewale/skill-eval-harness` (lists Vibe as a runner — eval-table reference). Structural: Vibe ships an **Agent Plugins 1.0** plugin format with marketplace support — adopted as the delivery vehicle (operator decision). `allowed-tools`/`user-invocable` are native Vibe frontmatter (partially answers skills-compat).

**Learnings applied:** ADR-245 re-entry rule (union member + generator/native load, never hand-copy); ADR-224 skills-root semantics differ per harness; ADR-223 per-harness hook dispositions (Vibe has `pre_tool`/`post_tool` in `.vibe/hooks.toml`, blocking unmeasured); ADR-110 inherit-tier default; ADR-120 Robot-console exception + ledger-before-birth; Devin 3-layer silent-fail hook trap; Grok alias double-fire; `Ref` not `Closes` on umbrella #9648; `Mandated-By:` bodies for deferred issues; fail-closed MODEL_PRICING (spec TR3).

**Repo-research surprises (measured):** (a) Codex ignores `model_providers` in project-local `.codex/config.toml` and speaks `wire_api = "responses"` only — A0's real gate is whether Mistral serves `/v1/responses`; (b) `MODEL_PRICING` **fails open today** — `agent-on-spawn-requested.ts:709` `?? {zeros}` bills $0 for any unknown model, so Guard 1 fixes a live defect, not a hypothetical; (c) adding `mistral` to `PROVIDER_CONFIG` auto-injects `MISTRAL_API_KEY` into every agent env via `ALLOWED_SERVICE_ENV_VARS` — needs exclusion or the `codex-credential-provider.ts` direct-read pattern; (d) `byok-lease` is anthropic-only by construction; (e) `TIER_MAPS` needs no vibe row (unmapped→inherit) but the 7 pinned workflow fences must be re-fenced if a marker lands; (f) `components.test.ts:1387` pins exactly 3 manifest dirs — the `.vibe-plugin/` dir reds it deliberately; (g) Vibe `VIBE_*` vars are config inputs, not exported session markers — detection may have nothing to read beyond argv heuristics.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Vibe loads `.agents/skills` natively | True, AND Vibe ships an Agent Plugins 1.0 package format | Phase A delivers a plugin package (operator decision), path-sharing becomes fallback |
| BYOK = extend provider registry | `Provider` union + exhaustive `PROVIDER_CONFIG` — a new member must have a row or `tsc` fails | Phase B edits both in one diff |
| Self-host deferred entirely | Session 2 rescoped: small-class (Devstral Small 2 / Mistral Small 4) is a live C1 stage; only ML4 is deferred (#9649) | Phase C1 in-plan |
| Vibe adapter needs checklist first | #9609 defers the checklist until #9608 slice-1 measures stable rows | Phase A sequencing note, not a blocker |
| `.agents/skills` path-sharing is the load path | `.agents/` holds only `plugins/marketplace.json`; plugin-package is primary, `.agents/skills` stays a fallback arm that must confirm no collision with `.agents/plugins/` | Phase A measurement gate covers it |
| Detection via env markers | `VIBE_*` are config inputs, not exported session markers — detection may have nothing to read; `SOLEUR_HARNESS` override + `unknown` non-Claude arm are the honest fallback | Phase A detection contract |
| "Unknown model bills at zero" is forward-looking | `MODEL_PRICING` fails open TODAY (`?? {zeros}` at :709) — live defect, not hypothetical | Guard 1 + Phase B fix |

## Observability

```yaml
liveness_signal:
  what: "harness-discovery CI job result + eval-table presence on #9648; for C1: grok-dogfood host heartbeat class reused"
  cadence: "per-PR (discovery job) / per-dogfood-run"
  alert_target: "operator via failed CI / issue comment"
  configured_in: ".github/workflows/ (vibe discovery job, non-required until soak)"
error_reporting:
  destination: "Sentry (existing) for web-platform provider paths; CI failure for harness surfaces"
  fail_loud: "MODEL_PRICING fail-closed error on unknown model; Vibe detector returns unknown, never a guessed arm"
failure_modes:
  - mode: "Mistral provider key absent/invalid at flag-on"
    detection: "fail-closed MissingByokKeyError class on the keyed path"
    alert_route: "Sentry + operator-visible error"
  - mode: "vibe arm misdetected in a non-Vibe session"
    detection: "harness-parity test on marker fixtures + discovery job output"
    alert_route: "CI"
  - mode: "dogfood host spend with no eval output"
    detection: "14-day no-table kill criterion (GEX precedent) + expense ledger row"
    alert_route: "operator review"
logs:
  where: "workflow run logs; dogfood host journald; Sentry for provider paths"
  retention: "GHA retention / journald default"
discoverability_test:
  command: "grep -l MISTRAL_API_KEY apps/web-platform/server/providers.ts"
  expected_output: "apps/web-platform/server/providers.ts"
```

## Encryption Posture

```yaml
at_rest:
  - store: "supabase api_keys row (provider='mistral') — existing store, existing envelope"
    mechanism: "app-layer-envelope:<existing api_keys encryption, encrypted_key+iv+auth_tag columns>"
    evidence: "apps/web-platform/lib/types.ts ApiKey shape; byok-lease.ts read path"
    defends_against: "DB exfiltration of the raw Mistral key"
    does_not_defend: "a compromised server process decrypting at runtime; RLS bypass"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available: is_valid round-trip on the keyed path"
in_transit:
  - connection: "web-platform server -> api.mistral.ai (BYOK relay)"
    enforced_at: "provider call site in the flagged path (Phase B)"
    tls: "https, TLS >= 1.2"
    cert_verification: "on"
    does_not_defend: "prompt/key content visibility to Mistral as processor — the legal train, not TLS, covers it"
    disclosed_as: "not-publicly-claimed until flag-on"
  - connection: "operator host -> local inference endpoint (C1)"
    enforced_at: "runbook loopback-only bind (ADR-120 pattern)"
    tls: "none — loopback by design"
    cert_verification: "off"
    does_not_defend: "any non-loopback exposure — the runbook forbids public bind"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "C1 inference is loopback-only on the dogfood host; no TLS needed on a non-network surface"
  tracking_issue: "#9648"
  reevaluate_when: "any non-loopback bind or multi-host inference topology"
  expires_on: "2027-01-06"
```

## Infrastructure (IaC)

- **Terraform changes:** none new in-repo — C1 uses the **Robot-console exception recorded in ADR-120** (ephemeral dogfood host, no Cloud SKU, lifecycle via runbook + expense ledger + Robot-cancel destroy). If C1 ever becomes a durable host it re-enters TF per that ADR's revisit rule.
- **Vendor account:** Mistral Studio account + API key — `automation-status: UNVERIFIED` — a vendor dashboard mint is presumptively Playwright-automatable until attempted; `soleur:work` runs a Playwright attempt (named human gate = sign-up/OAuth consent or CAPTCHA) before any operator handoff. Key landing in Doppler `soleur/dev` is an operator-terminal write per `hr-never-paste-secrets-via-bang-prefix`.
- **C1 GPU host order:** genuinely operator-gated — the spend ack + license-memo review are human-judgment calls (ADR-120 shape), not automatable actions; the *order button* itself may be Playwright-attempted at soleur:work time but the ack is the operator's.
- **Apply path:** n/a for C1 (console order + bootstrap script + measure + cancel); no `-replace` of running prod.
- **Distinctness/drift:** dogfood host is fully separate from prd; no shared state.
- **Vendor-tier reality check:** Mistral preview API access is limited-audience — A0 starts only after a live probe confirms access.

## Architecture Decision (ADR/C4)

### ADR

- **Create provisional ADR-274** via `soleur:architecture` scoped to Phase A only: "Add Mistral Vibe as a supported harness via an Agent Plugins 1.0 package." Covers the union member, inherit-tier default, plugin-package vehicle, SOLEUR_HARNESS override, hooks-unverified disclosure, sequential-fallback contract. Ordering-agnostic phrasing ("a new supported harness," not "fifth") — if Cursor (#9608) merges first the ordinal is wrong (CPO F3).
- **The BYOK provider is a separate ADR** authored at flag-on time (arch-strategist finding 4: different gate, different blast radius, different reversibility — a credential-store decision can't be `accepted` while flag-on is legally impossible). This plan names it now so it isn't deferred to a follow-up issue: the flag-on PR carries "provider ADR" in its own deliverables.

### C4 views

- Read of all three model files: `model.c4` has `anthropic`, `codex`, `grokBuild` externals; `views.c4` includes them in the relevant views. **No Mistral or Vibe element exists** → in-scope edits: add `mistral` external system (Mistral AI API), `vibeCli` external (CLI harness), edges `engine -> mistral` (BYOK relay, flag-gated) + `founder/ci -> vibeCli` (harness runs) + C1 dogfood host element if that stage proceeds; add the `include` lines in `views.c4`. Then run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Guard Contract

### Guard 1 — no model reaches a $0 bill, on either pricing surface

**Property.** A model absent from the applicable pricing map can never bill $0 — `MODEL_PRICING`'s fallback at `agent-on-spawn-requested.ts:709` fails closed, and the `mistral` consuming path refuses to meter a model absent from `server/mistral-pricing.ts`.

**Assembly.** Two chokepoints: (a) `MODEL_PRICING[leaderModule.model]` lookup at :709 — all Anthropic leader-loop metered calls flow through it; (b) the new `mistral-pricing.ts` lookup inside the flagged summarize path. Note the :709 arm is unreachable in committed code today (`model` is typed `AnthropicModelId`) — the guard tests the seam via a synthetic model id, not a reachable runtime path.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Call the pricing resolution with a synthetic model id absent from `MODEL_PRICING` | RED — a restored `?? {zeros}` bills $0 instead of erroring |
| 2 | Delete the fail-closed branch entirely so the lookup returns undefined | RED — the guard's own dispatch must catch a missing fallback, not just a wrong one |
| 3 | A `mistral` model consumed by the flagged path but absent from `mistral-pricing.ts` | RED — supported-but-unpriced fails closed on the second chokepoint too |
| 4 | must-PASS: a `mistral` model present in `mistral-pricing.ts` meters normally; an `AnthropicModelId` member meters via `MODEL_PRICING` | PASS |

### Guard 2 — `vibe` harness parity

**Property.** Every harness-keyed surface in the repo (union member, TIER_MAPS arm, adapter functions, plugin manifest, discovery job, parity test) either has a `vibe` arm or an explicit, test-asserted refusal.

**Assembly.** The chokepoints are `Harness` union members: `plugins/soleur/lib/harness.ts` (`detectHarness`, `formatSkillInvocation`, `invokeSkill`, `spawnAgent`, `routingInstructions`), `harness-model-map.ts` + the byte-identical `TIER_MAPS` copies in `*.workflow.js`, `test/harness-parity-tree.test.ts` `POPULATION_GLOBS`, and the harness-discovery CI job list.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `vibe` to the union without a `detectHarness` marker arm | RED — parity test must enumerate unmapped members |
| 2 | Give `TIER_MAPS.vibe` a real SKU but leave a workflow.js inlined copy stale | RED — byte-identical drift guard |
| 3 | Register the vibe plugin manifest but omit the discovery job entry | RED — discovery job enumerates the manifest set |
| 4 | must-PASS (two arms): `vibe` in union + manifest + discovery row + (a) measured marker arm, OR (b) no-marker degrade: `SOLEUR_HARNESS=vibe` override path + INSTRUCTIONS.md honest-degrade statement | PASS — whichever branch measurement chose |
| 5 | must-PASS (suite-side): a `vibe` session fixture where detection legitimately stays `unknown` (marker absent, no override) | PASS — detector must not over-claim |

### Guard 3 — `mistral` provider row implies exclusion-set membership

**Property.** A `mistral` entry in `PROVIDER_CONFIG` cannot exist without `mistral` in `EXCLUDED_FROM_SERVICES_UI` — the moment it does, `POST /api/services`, `getUserServiceTokens`, and Connected Services GET all open to it flag-blind.

**Assembly.** The chokepoint is the provider-key derivation itself: `PROVIDER_CONFIG` keys vs. the `EXCLUDED_FROM_SERVICES_UI` set, asserted in `providers.test.ts` — not the three downstream consumers (those each have their own behavior, and the invariant is membership-pairing, not consumer behavior).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `PROVIDER_CONFIG` carries `mistral`; `EXCLUDED_FROM_SERVICES_UI` does not | RED |
| 2 | Delete the pairing assertion (guard's own dispatch) | RED via a sentinel case asserting the check ran ≥1 provider |
| 3 | Add a second excluded llm provider after `mistral` (e.g. a future vendor row) — pairing must hold for every member, not just mistral | RED if the guard is mistral-literal rather than per-key |
| 4 | must-PASS: `mistral` in both | PASS |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "I'd like for Soleur users to be able to use this model" | Phase A0 + Phase B | mapped |
| 2 | "or even their Mistral Vibe Harness" | Phase A | mapped |
| 3 | "what would it take to add it to Soleur?" | whole plan + staged gates | mapped |
| 4 | "in light of our EU sovereignty play" | Phase 0 content + legal train + C1 self-host | mapped |
| 5 | "Agent Plugins 1.0 plugin format is valuable to be supported" (second steer) | Phase A delivery vehicle | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| Phase A0 dogfood | "I'd like for Soleur users to be able to use this model" + operator "Dogfood first" | asked |
| Phase A plugin package | "Mistral Vibe Harness" + "Agent Plugins 1.0 plugin format is valuable to be supported" | asked |
| Phase B BYOK provider | "use this model" + operator "BYOK + bundled later" | asked |
| Phase B-legal train | — | inferred — justification: CLO requirement; no user content may reach Mistral before DPA/docs |
| Phase C1 small-class self-host | operator "Small-class dogfood" answer | asked |
| Hedge content | "EU sovereignty play" news window | inferred — justification: decouple-build-from-news-window precedent; CMO-owned |
| ADR-274 + C4 edits | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — a fifth harness is an architectural decision |

### Split Assessment

- Subsystems touched: 5 — `plugins/soleur/lib` + `plugins/soleur/vibe` + `apps/web-platform/server` + `.github/workflows` + `knowledge-base/legal`/`docs/legal`
- Planned files: ~25 | Estimated changed lines: ~2500–3000 (adapter floor is the measured 1940-line Devin class)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — **all three exceed**
- Recommendation: **split** — one PR per stage boundary (A0 runbook+eval, A adapter, B provider+legal train, C1 runbook), exactly as the stage table draws them; this plan is the umbrella's coordination doc, not a single-PR diff.

## Domain Review

**Domains relevant:** Engineering, Legal, Marketing, Product, Operations

### Engineering (CTO)

**Status:** reviewed (session 1) + orchestrator-synthesized (session 2)
**Assessment:** A0 is trivial; A is M-effort contained in `plugins/soleur/` with hooks as the risk surface; B is L (provider registry + pricing + flag); C1 reuses the GEX44 substrate. Order confirmed: dogfood model first, adapter second.

### Legal (CLO)

**Status:** reviewed (session 1)
**Assessment:** Mistral AI SAS becomes a sub-processor only at the flagged BYOK path — legal train (DPA snapshot, six-doc lockstep, Art. 30, attestation) must merge before flag-on. Vibe CLI is Apache-2.0 clean; its default telemetry must be off in any Soleur-shipped config. Open-weight license must be read live before any pull.

### Marketing (CMO)

**Status:** reviewed (session 1)
**Assessment:** honest ladder — "evaluating" now, "runs on Mistral" after the eval table, "self-hosted open weights" after license + hardware. EU sovereignty is a new pillar needing demand validation (#9651).

### Product (CPO)

**Status:** reviewed (session 1)
**Assessment:** Post-MVP/Later; dogfood-gated rollout; no claims before green. Sovereignty ICP unverified — validation tracked by #9651.

### Operations (COO)

**Status:** reviewed (session 1)
**Assessment:** near-zero cost until C1; GPU order is spend-ack gated (ADR-120); ledger row before birth.

### Product/UX Gate

**Tier:** none — no UI-surface files in Files to Edit/Create (plugin lib, server credential plumbing, workflows, docs all outside the ui-surface glob set).

## GDPR Gate (Phase 2.7)

Advisory pass ran over the plan + regulated surfaces (migration path, `app/api/keys/route.ts`, `MISTRAL_API_KEY` env var). Findings:

- `GDPR-Chapter-V` **Important (informational)**: new vendor env var matched, but Mistral AI SAS is EEA-resident — no cross-border trigger. Art. 28 DPA + vendor row still required before flag-on; covered by Phase B-legal.
- `GDPR-Art-6/5e/17` **Suggestion**: the migration widens a CHECK list — no new PII column/table/FK; migration comment should record that `provider='mistral'` inherits `api_keys`' existing lawful basis (contract necessity).
- `GDPR-Art-9`: not triggered.
- Art. 25 data-minimization note: the `PROVIDER_CONFIG`→`ALLOWED_SERVICE_ENV_VARS` leak (repo-research c) means the Phase-B exclusion/dedicated-channel decision is compliance-relevant, not just hygiene.

## Open Code-Review Overlap

Queried 87 open `code-review` issues against the Files to Edit list:

- **#9188** (`token-validators.ts` linkedin provider probes openid-only userinfo) — **Acknowledge**: same file, different provider/fix; the mistral `VALIDATOR_CONFIGS` row must not regress the linkedin fix. Remains open.
- **#3374, #3242, #2963, #2197** (`types.ts`) — **Acknowledge**: the file is the shared type barrel; none concern the `Provider` union. Remain open.
- **#8881, #2965** (`ci.yml`) — **Acknowledge**: unrelated jobs/test-rebalance; the vibe discovery arm is additive. Remain open.
- **#8593** (`components.test.ts`) — **Acknowledge**: probe-gate window concern, unrelated to the `manifestDirs` pin update. Remains open.

## Acceptance Criteria

- [ ] Phase 0: the `knowledge-base/marketing/distribution-content/2026-10-*-mistral-evaluating-thread.md` artifact exists, fact-checked + CLO-reviewed, published ≤ Oct 13.
- [ ] A0: a measured eval table for Mistral model(s) via an existing vehicle is posted on #9648, with the vehicle and OpenAI-compat finding recorded.
- [ ] A: `detectHarness` returns `vibe` only for a marker measured on a real Vibe install; `Harness` union + TIER_MAPS + adapter arms + `vibe/` plugin package (Agent Plugins 1.0) + INSTRUCTIONS.md ship; harness-parity tests pass; discovery job is non-required with `continue-on-error`.
- [ ] A: `/go` classifies and one pipeline skill completes its gates under Vibe, or every gap is a named, test-asserted refusal.
- [ ] B: `Provider` union + `PROVIDER_CONFIG` carry `mistral`; `MODEL_PRICING` fails closed on unknown model; flag default-off; flag-on blocked until the legal train merges.
- [ ] B-legal: Mistral DPA snapshot + six-doc lockstep + Art. 30 row + attestation committed (canonical + Eleventy mirrors together).
- [ ] C1: runbook extended for a small-class Mistral model with ledger-first/spend-ack/license-memo/VRAM-fit gates; no host ordered inside this PR.
- [ ] B hard gates: `POST /api/keys {provider:"mistral"}` refuses 403 while the flag is off; a provider-scoped delete path exists and round-trips; `keys/route.ts` returns 400 on an unrecognized provider value (no silent anthropic coercion).
- [ ] Umbrella lifecycle: `#9648` closes when the A0 eval table is posted AND the flag-on decision is recorded **— including an explicitly recorded `deferred → <successor>` decision** (an umbrella must not rot waiting on a legal train; residual C1/C2 outcomes move to #9649/#6546).
- [ ] `spawnAgent`'s `vibe` arm is test-asserted to emit the inline-execution/sequential-fallback instruction (never a spawn-tool name Vibe lacks) — covered by a `harness.test.ts` case, not just prose.
- [ ] ADR-274 (provisional) committed; C4 model+views updated; c4 tests green.
- [ ] PR bodies use `Ref #9648`, never `Closes #9648`.
- [ ] Claims grep (scoped, case-insensitive): `git grep -inE '(mistral|vibe).{0,80}(EU[- ]sovereign|data never leaves|data stays in Europe|GDPR[- ]compliant|sovereign AI)|runs on mistral|Mistral-powered|supports Mistral' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/project/brainstorms' ':!knowledge-base/project/learnings'` returns zero hits — until the eval table posts on #9648 AND the B-legal train merges, after which the earned rungs in the allowed-claims table unlock. (Scoped to Mistral-proximity: bare `sovereignty` and sanctioned legal/blog phrasing are legitimate existing copy.)

## Test Scenarios

- Given a session env without Vibe markers, when detectHarness runs, then it returns a non-`vibe` value (no over-claim).
- Given a measured Vibe marker fixture, when detectHarness runs, then `vibe`.
- Given `MODEL_PRICING` lacks the requested model, when a BYOK metered call resolves price, then it errors/blocks — never $0.
- Given the flag off, when the mistral BYOK path is invoked, then it refuses closed.
- Given `git grep -il vibe plugins/soleur/lib/harness.ts` in CI, then the parity suite enumerates every arm or fails.
- C1 (post-merge soak): given a licensed small-class model on loopback, when `grok-measure.sh --model <name>` runs, then the comparison table fills.

## Success Metrics

- Eval table on #9648 (ML4/Devstral on Soleur's measure classes) exists inside the preview window.
- Vibe arm green in CI for two consecutive weeks before "supported" language (ADR-245 soak rule).
- Zero BYOK $0-billing incidents; zero public-claim retractions.

## Dependencies & Risks

- **Vibe primitives unmeasured** (env markers, hook blocking, wait primitive, `skills`-key semantics) — every one is a "measure before asserting" TR; none may be guessed.
- **ML4 preview access is limited** — A0 depends on actually getting API access; if denied, A0 narrows to Devstral (already released weights/API).
- **Custom weights license (~Oct 27)** — field-of-use/revenue caps unknown until published; blocks C2 and any weight pull.
- **Cursor adapter (#9608) in flight** — Vibe is the #9609 checklist's second consumer; sequencing drift is expected and absorbed by the stage gates, not by coupling.
- **Harness-parity blast radius** — ~103 SKILL.md files carry harness marker blocks; a `vibe` arm must be generated/declared consistently or parity tests red.
- **Legal train is long** — six docs + register + mirrors + attestation; it gates only B's flag-on, not A0/A.

## References & Research

- Brainstorm: `knowledge-base/project/brainstorms/2026-10-06-mistral-large-4-vibe-support-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-mistral-large-4-and-vibe-support/spec.md`
- ADRs: 053, 083, 110, 120, 215, 223, 224, 226, 236, 245
- Issues: #9648 (umbrella), #9649/#9650/#9651 (deferred), #9608/#9609 (Cursor + checklist), #1215 (BYOM), #6546/#6547 (open-weight/Concierge)
- External: mistral.ai/news/mistral-large-4, mistral.ai/news/devstral-2-vibe-cli, docs.mistral.ai/vibe/code, github.com/mistralai/mistral-vibe, wshobson/agents harnesses.md, claude-octopus PR #402, adewale/skill-eval-harness
