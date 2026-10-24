# Tasks — feat: Mistral Large 4 + Mistral Vibe support (staged)

Derived from `knowledge-base/project/plans/2026-10-06-feat-mistral-large-4-vibe-support-plan.md` (post-review). Stage PRs use `Ref #9648`, never `Closes #9648`.

## Phase B-0 — standalone live-defect fixes (first code PR)

- [x] 0.5 `apps/web-platform/app/api/keys/route.ts` — replace provider ternary at :32 with explicit allowlist + 400 — **shipped #9684**
- [x] 0.6 `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts:709` — `MODEL_PRICING ?? {zeros}` → fail-closed (latent arm; synthetic-model test) — **shipped #9684** (panel widened: `persistTurnCost`, `?? 0` producers, `credential_type` ternary)
- [x] 0.7 Tests: unrecognized provider → 400; absent pricing → error not $0 — **shipped #9684** (`api-keys-provider-allowlist.test.ts`, `cost-writer-unpriced.test.ts`)

## Phase A0 — model dogfood on existing vehicles

- [x] 1.1 Probe `https://api.mistral.ai/v1/responses` (Codex 0.156.1 requires `wire_api = "responses"`); record result on #9648 — **done 2026-10-07**: endpoint exists (401 vs 404 disambiguation) + codex exec live-fire reaches it and fails only at auth
- [ ] 1.2 Mistral Studio account + API key — **operator gate (credential entry)**, attempt evidence in `runbooks/mistral-api-dogfood.md`; key lands in Doppler `soleur/dev` via operator terminal
- [x] 1.3 Runbook recipe: `~/.codex/config.toml` `[model_providers.mistral]` on the dogfood host (NOT project `.codex/config.toml` — Codex ignores it there); fallback = #1215 Ollama+claude-code-proxy pattern — **done**: `knowledge-base/engineering/operations/runbooks/mistral-api-dogfood.md`
- [ ] 1.4 `scripts/dogfood/mistral-measure.sh` (or `--parse-only` shape adapter) + eval table on #9648 (row schema per plan :60; pass = exit code AND artifact-presence) — **script + suite shipped this PR**; eval table rows pending the key (1.2)

## Phase A — Vibe harness adapter (Agent Plugins 1.0)

- [ ] 2.1 **Measurement gate (before harness.ts):** pinned Vibe CLI; probe env/argv/process.title/`/proc/$PPID`; one-skill `.vibe-plugin` load test; `pre_tool` blocking; `task` primitive; `${CLAUDE_PLUGIN_ROOT}` substitution; sibling-manifest ambiguity; `allowed-tools` name mapping → cut decision (package OR path-share), posted on #9648
- [ ] 2.2 `plugins/soleur/lib/harness.ts` — `vibe` union + all arms; `SOLEUR_HARNESS` override (markers > override > argv; validate value; warn on conflict); `unknown` non-Claude arm
- [ ] 2.3 `harness-parity.ts`, `workflow-fidelity.ts`, `pr-merge-poll.ts` arms (honest degradation where absent)
- [ ] 2.4 `.vibe-plugin/` package (plugin.json + skills/ + ext dirs) — exclude the 8 `disable-model-invocation` skills; no `vibe-harness-invoke` fleet block
- [ ] 2.5 `plugins/soleur/vibe/INSTRUCTIONS.md` (surfaces, unverified/unused hooks, rules-corpus absence, CLAUDE_PLUGIN_ROOT convention, Reviewed-Coverage disclosure)
- [ ] 2.6 `scripts/setup-vibe.sh` + repo `.vibe/config.toml` (telemetry off both layers; TOML-aware merge-or-refuse; write-if-absent loud-log on user config)
- [ ] 2.7 `commands/go.md` harness-forms blocks + :508 fallback `vibe`/`unknown` lines
- [ ] 2.8 Tests: `harness.test.ts` (conflict fixture, unknown arm, spawnAgent inline arm), parity/model-map/tool-map updates, `components.test.ts` manifestDirs pin
- [ ] 2.9 CI: `harness-discovery` vibe arm (`VIBE_PIN` in ci.yml + `test/README.md`, sha256-pinned, `continue-on-error`)
- [ ] 2.10 `.gitignore` `.vibe/*` + `!.vibe/config.toml`; README/plugins-README/CONTRIBUTING install surfaces (+ fix stale harness table at README.md:192-199)
- [ ] 2.11 ADR-274 (provisional; ordering-agnostic phrasing) + C4 `mistral`/`vibeCli` elements + edges + c4 tests
- [ ] 2.12 `/go` classifies + one pipeline skill completes gates under Vibe (or named refusals)

## Phase B — BYOK `mistral` provider (flagged)

- [ ] 3.1 `Provider` union + `PROVIDER_CONFIG` row + `EXCLUDED_FROM_SERVICES_UI` membership (same diff; Guard 3 test in `providers.test.ts`) + exclusion-reason comment update
- [ ] 3.2 `supabase/migrations/` — extend `api_keys_provider_check`
- [ ] 3.3 `token-validators.ts` VALIDATOR_CONFIGS; `keys/route.ts` ordering: allowlist-400 → flag-403 → validate → upsert; provider-scoped delete path
- [ ] 3.4 `RUNTIME_FLAGS` += `mistral` (default-off); `FLAG_MISTRAL=0` in Doppler; `MIRROR_FLAGS` += it; flag-fixture tests extend
- [ ] 3.5 Flagged consumer: `email-triage/summarize.ts` routes through `api.mistral.ai` on the user's key when flag on; `server/mistral-pricing.ts` registry; credential read mirrors `codex-credential-provider.ts`
- [ ] 3.6 Flag-on checklist: legal train merged + L29/#9500 canonical claim updated + provider ADR authored

## Phase B-legal — legal train (blocks flag-on)

- [ ] 4.1 DPA snapshot `knowledge-base/legal/data-processing-agreements/mistral.md` (openai.md shape)
- [ ] 4.2 Six-doc lockstep (PP §5.1, DPD §2.3 + sub-processor table, GDPR Policy §4.2, T&C §3a.5/AUP, Art. 30 PA-22/PA-23 + vendor row, compliance-posture.md) + mirrors + SHA re-pins + T&C bump + CLO attestation

## Phase C1 — small-class self-host dogfood

- [ ] 5.1 Runbook extension (GEX44 shape): ledger-first, license memo, ≤20 GB / VRAM-fit calc, loopback-only, no private-net, YOLO off, Robot-cancel destroy
- [ ] 5.2 Ledger row requires spend ack + live stock check + #6546 soak green + one of (#9651 positive | explicit "C1 is the demand test" record)
- [ ] 5.3 Comparison table on #9648

## Deferred (not this plan)

- #9649 ML4 self-host (weights+license+hardware) · #9650 Vibe TOML agents/hooks port · #9651 sovereignty demand · bundled Soleur-paid keys · `model-dogfood` skill · Hosted Concierge on Mistral
