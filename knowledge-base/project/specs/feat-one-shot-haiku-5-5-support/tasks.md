# Tasks: support Claude Haiku 5.5 (claude-haiku-5-5)

Plan: `knowledge-base/project/plans/2026-10-08-feat-haiku-5-5-support-plan.md`. Commit seams follow the phases; write tests red first.

## Phase 0: Evidence before edits

- [ ] 0.1 Re-fetch the official pricing page; confirm the Haiku 5.5 two-card table and the Sonnet 5.5 cache-read figure; keep the two lines for the PR body
- [ ] 0.2 Live probe when a key is reachable without printing it (two cells per caller shape, N=5): router 200, summarizer 256, preflight 1, leader loop 4096 with a tool definition; cell (a) default, cell (b) `effort: low`
- [ ] 0.2b Probe handling: dev/probe key via the secret store's run wrapper, headers from a 0600 file, `umask 077`, delete scripts, log only status/stop_reason/block types/usage; include the router `effort`+`format` combination and one synthesized security-flavored leader input
- [ ] 0.3 Apply the decision rule: router and summarizer ship `effort: low` (budget 1024 if still truncating); leader loop unchanged unless truncation is observed; preflight swaps only on HTTP 200

## Phase 1: CLI pin (RED then GREEN)

- [ ] 1.1 RED: point `HAIKU_MODEL` at `claude-haiku-5-5` locally and confirm `claude-cli-pin-knows-models.test.ts` fails on 2.1.284; revert
- [ ] 1.2 Bump `@anthropic-ai/claude-code` to 2.1.293 in `apps/web-platform/package.json` and the `Dockerfile` global install; regenerate `package-lock.json` with npm@11 `--package-lock-only` (one-off `--min-release-age=0` unless the 3-day floor has lapsed); leave `.npmrc` and the Agent SDK pin alone
- [ ] 1.3 Verify `grep -a -c claude-haiku-5-5` on the installed platform binary is at least 1; confirm `REVIEWED_DEFAULT_EFFORT` is unchanged (medium, medium); update the test header comment
- [ ] 1.4 Hook probe and per-tier smoke runs on 2.1.293; write the `sdk-bump-verified:` trailer naming the allowlist hook control with 2.1.284 as the control
- [ ] 1.4b Compensating supply-chain checks: dist.integrity equality (lock vs global install, claude-code and linux-x64 platform package), `npm audit signatures`, lockfile diff gate, override on one command only, rollback trigger
- [ ] 1.5 Sweep `git grep -n 2.1.284`; leave the SDK-bundled-builder references and synthetic fixtures (the paid `plugin-root-propagation-gate` CI job runs on the lock change through the unchanged SDK 0.3.284)

## Phase 2: SSOT constant and pricing

- [ ] 2.1 RED tests in `model-tiers.test.ts`: constant value, four distinct token values per card, boundary at 100,000 (with cache split) and 100,001 via `input_tokens` and via `cache_creation` alone, cache-heavy case, $0.005 rounding-edge pin, unpriced model NaN, literal key list
- [ ] 2.2 `constants.ts`: `HAIKU_MODEL = "claude-haiku-5-5"`; update doc comments
- [ ] 2.3 `agent-on-spawn-requested.ts`: optional `longPrompt` card on `ModelPricing`; tier selection on `input + cache_read + cache_creation` with a strictly-greater comparison; replace the Haiku 4.5 row; source line and date in the comment
- [ ] 2.4 Own commit: Sonnet 5.5 cache-read to $0.10/MTok only if the Phase 0 refetch still shows it; regime-boundary note in the row comment
- [ ] 2.5 Update `model-tiers.ts` comments (no `/*` inside a `//` comment); keep `PER_SPAWN_COST_CEILING_CENTS` at 260

## Phase 3: Call-site adaptation

- [ ] 3.1 `domain-router.ts`: literal id, `effort: low` (budget per probe), message-path (`err = null`) mirror `feature: domain-router`, op `no-text-block` on missing/empty text, `max_tokens` or `refusal`, exact-key `extra` test with sentinel, `stop_reason` on the catch log, adversarial fixture; update the #8392 test comment; parity assertion against `HAIKU_MODEL`
- [ ] 3.2 `email-triage/summarize.ts`: same effort handling and message-path mirror (`feature: email-triage`, op `no-text-block`, covers `max_tokens`/`refusal`/empty text), no subject, sender, body or SDK error object; adversarial fixture in `summarize.test.ts`
- [ ] 3.3 Conditional: leader-loop `effort` field and `promptVersion` bump only if the probe shows truncation
- [ ] 3.4 One refusal assertion in the leader-loop test; no `fallbacks` parameter on any Haiku request
- [ ] 3.5 Preflight action and `scripts/learning-retrieval-bench.sh` per probe; test helpers (`anthropic-stub.ts`, `sandbox-credential-deny-runtime.test.ts`, `domain-router.test.ts`)

## Phase 4: Audit tooling, skill, docs, eval harness

- [ ] 4.1 `audit-models.sh`: two Haiku 4.5 pairs (dated and undated), carve-out for the two SDK-path scripts (plus the preflight action only if its probe fails), rephrase the `lint-anthropic-content-position.py` docstring
- [ ] 4.2 `model-launch-review.test.ts`: `CURRENT_IDS`, `[2b]` fixtures, carve-out test, two-spelling pair test, self-expiring SDK-pin test
- [ ] 4.3 `model-launch-review/SKILL.md`: lineage line, probe example model, two sharp edges
- [ ] 4.4 Regenerate `models.generated.json` with `gen-models.sh`; run `gen-models.test.sh`
- [ ] 4.5 Hand-edit price prose next to swapped ids in the agent-native-architecture and dspy-ruby docs; refresh Haiku figures in `plugins/soleur/AGENTS.md`
- [ ] 4.6 ADR-053 append-only: supersession notes (row 5a, Haiku tier table) and a dated addendum (verdicts, carve-out, trigger); row 10 reclassified as eval-gated candidate; cite the `model-tiers.ts` comment for the re-tiering attestation
- [ ] 4.7 ADR-041 addendum: `longPrompt` card, superset rule, Sonnet cache-read regime boundary, Layer 2 vs Layer 3 for sub-cent Haiku turns
- [ ] 4.8 `anthropic-console-workspace-key.md` Haiku probe id follows the preflight verdict (AC15)

## Phase 5: Verification and follow-ups

- [ ] 5.1 Run the vitest, bun, tsc, lint and audit commands listed in plan Phase F; `--detect` must print `model-drift: none` with rc 0
- [ ] 5.2 Create the two follow-up issues (pdf-chapter-router after the SDK bump; eval-gated re-tiering of crons and workflow pins) after verifying labels and milestone; comment on #6945, #8643, #6000
- [ ] 5.3 PR body first line states that merging deploys the web-platform image; include the pricing lines, probe results, floor override section and Sonnet correction note
