---
title: "feat: support Claude Haiku 5.5 (claude-haiku-5-5) across model IDs, pricing, CLI pin, docs and tests"
date: 2026-10-08
slug: haiku-5-5-support
branch: feat-one-shot-haiku-5-5-support
issue: none
type: feat
lane: cross-domain
requires_cpo_signoff: false
---

## Overview

Anthropic shipped Claude Haiku 5.5 (`claude-haiku-5-5`, a fixed id with no date suffix and no separate
alias). Soleur's Haiku tier is a single SSOT constant, `HAIKU_MODEL` in
`apps/web-platform/server/inngest/leader-prompts/constants.ts`, currently
`claude-haiku-4-5-20251001`. This plan migrates that tier to 5.5 by following the
`soleur:model-launch-review` checklist (items 1 to 6), and records, per call site, where Haiku 5.5
would be a better fit than the model in use today.

The migration is **not** a string swap, for four verified reasons:

1. **The pinned CLI does not know the id.** `@anthropic-ai/claude-code` 2.1.284 (and the Agent SDK
   0.3.284 bundle) contain zero occurrences of `claude-haiku-5-5`
   (`grep -a -c` over the installed `node_modules/@anthropic-ai/claude-code-linux-x64/claude` = 0,
   positive control `claude-sonnet-5-5` = 10). The first CLI release carrying it is **2.1.293**
   (published 2026-10-07; 2.1.291 and 2.1.292 measure 0, 2.1.293/294/295 measure 8/8/10).
   `claude-cli-pin-knows-models.test.ts` harvests `HAIKU_MODEL` and would go red. Checklist item 2b
   says this **blocks the swap**.
2. **Haiku 5.5 changes request semantics.** Adaptive thinking is on by default with effort default
   `medium`; `budget_tokens`, non-default `temperature`/`top_p`, any `top_k`, and assistant prefill
   return 400; the tokenizer yields about 30% more tokens for the same text; thinking tokens count
   against `max_tokens`. Three call sites run with `max_tokens` of 200, 256 and 1 and would silently
   truncate before emitting a text block.
3. **Pricing has two rate cards by prompt length** ($0.10/$0.50 up to 100K prompt tokens, $0.50/$2.50
   above), while `MODEL_PRICING` is a flat per-token row that feeds a WORM ledger.
4. **Verification of pricing surfaced drift in the neighbouring Sonnet row** (cache read is
   $0.10/MTok on the official page, the repo carries $0.20).

## Research Insights

### Premise Validation (Phase 0.6)

Checked what the brief cites by reference:

- **PR #9236 (Sonnet 5.5 migration)**: merged (`6d27cd17da chore(models): migrate Claude Code to claude-sonnet-5-5 (#9236)`). Holds; used as the shape to mirror.
- **#8643 "agent-sdk bundled CLI model-id gate"**: the brief lists it as a prior launch to mirror. **It is OPEN, not merged** (`gh issue view 8643`: state OPEN, "ci(models): gate that the pinned claude-agent-sdk bundled CLI knows the Agent SDK model ids"). There is no SDK-bundle gate to mirror; the existing guard (`claude-cli-pin-knows-models.test.ts`) covers only `@anthropic-ai/claude-code`. Stale premise, handled in Phase A and the Open Code-Review Overlap section.
- **#6941 "haiku pricing row"** and **#6934 (unknown id halves max_tokens)**: both are historical fixes whose lessons apply; confirmed via learnings.
- **#8601 / #6934**: CLI-only bump precedent for the `sdk-bump-verified:` ack naming the hook control.
- **Cited code paths** (`model-tiers.ts`, `domain-router.ts`, `email-triage/summarize.ts`, `leader-prompts/*`, `.claude/hooks/agent-token-tee.sh`, `.github/actions/anthropic-preflight/action.yml`, `.github/workflows/ci.yml`, sandbox-canary scripts, `components/settings/api-usage-section.tsx`, ADR-053/083/110, `MODEL_PRICING`): all present on the branch. Two are corrected: `agent-token-tee.sh` only mentions the `haiku` alias in a comment (no id), and `api-usage-section.tsx` only says "Haiku" in prose (no id, no price). Neither needs an edit.
- **ADR corpus vs the proposed mechanism**: ADR-053 explicitly keeps founder-BYOK and operator-key crons out of re-tiering ("re-tiering a cron ... is a separate clo-attestation-class model-bump PR"). The "check for better-suited locations" half of the ask therefore produces a verdict table and tracked follow-ups, not silent re-tiering (see Phase E).
- **Pricing source**: verified live from `https://platform.claude.com/docs/en/about-claude/pricing.md` on 2026-10-08 and cross-checked with the bundled `claude-api` skill (`shared/model-migration.md` "Migrating to Claude Haiku 5.5").

### Coordinator-supplied launch facts, reconciled (2026-10-08)

The launch post facts passed in by the coordinator were checked against the pricing page and the bundled `claude-api` skill (`shared/models.md`, `shared/model-migration.md`). Agreement and gaps:

- **Model id, release date, tiered pricing (both cards), Haiku 4.5 comparison, Sonnet 5.5 cache read cut to $0.10 (and $2 / $10 / $2.50 write)**: all agree with the pricing page. The Sonnet cut is therefore not a possible drift but a confirmed repo discrepancy (the repo row says $0.20); Phase B item 4 applies it, gated only on the Phase 0 refetch. The post leaves batch pricing unstated; the pricing page states Haiku 5.5 batch at $0.05 / $0.25 (short card) and $0.25 / $1.25 (long card). No repo path uses the Batch API for Haiku, so no row is added.
- **Context window and max output (gap in the post)**: verified from `shared/models.md`: **1M context, 128K max output**, status Active (Haiku 4.5: 200K / 64K). Consequence: a leader or summarize prompt can now legally exceed 100K tokens, so the long-prompt card is reachable, not theoretical (Guard 2 covers it).
- **Effort setting**: first Haiku-class model with `low | medium | high | xhigh | max`, default `medium` (the bundled CLI row also reads `medium`). Used here as the thinking-budget control for small-`max_tokens` classification (Phase C). The effort/model router (#6000, open) is a future consumer and is out of scope; Phase E item 12 records it.
- **Tokenizer**: about 30% more tokens; covered in Risks and Phase 0.
- **Recommended uses** (summaries, compaction, DB queries, classification, subagent lookups, live support, browser/computer use) and **NOT for complex agentic coding**: applied as the fit test in Phase E. Complex agentic coding sites (`cron-bug-fixer`, the Concierge runtime, `fix-constraints-stage-a.yml`, the leader reasoning classes) are explicit "do not move" rows.
- **Safeguards**: Haiku 5.5 can return `stop_reason: "refusal"` with `stop_details.category` in `cyber | bio | frontier_llm | general_harms`; cyber safeguards are stricter than Haiku 4.5, looser than Sonnet 5.5, and pentest-style prompts stay blocked; there is **no server-side fallback** (do not send `fallbacks`). Consequence for the two Haiku leader classes: `triage.p0p1_issue` reads issue bodies that can be security-flavored, so a refusal on a legitimate vulnerability report is newly possible. The leader loop already ends non-`end_turn`/`tool_use` stops through `persistFailure` (the `refusal` branch at `agent-on-spawn-requested.ts` near line 810), which is the correct client-side handling; Phase C adds a regression test that a refusal turn on a Haiku class lands in that branch with the category in `extra`, and Phase E keeps `security.cve_alert` on Sonnet 5.5 (never-downgrade and cyber-flavored).
- **No deprecation of older Haiku models** is announced: the Haiku 4.5 swap is a migration for cost and support-currency reasons, not a forced retirement, which is why the SDK-path scripts can stay on 4.5 without urgency.
- **Platforms and SDKs**: the beta computer/browser-use SDK support does not touch Soleur (no computer-use callers; grep for `computer_20250124` and `browser_toolset` returns nothing in `apps/` and `plugins/`).

### Property List (Phase 0.6b)

- **P1** Every runtime caller that selects "Haiku" resolves to `claude-haiku-5-5` through the SSOT constant, and no config-class file carries a Haiku 4.5 id except an enumerated, documented carve-out.
- **P2** Each Haiku caller still returns usable output under Haiku 5.5's semantics: a text block is present at the call's output budget (the original, or the raised budget the Phase 0 probe justifies), with no silent empty-string fallback.
- **P3** Turn cost for Haiku 5.5 leader-loop turns is attributed from the correct rate card, and an unpriced model still fails closed.
- **P4** The pinned `claude-code` CLI knows the id, tier default efforts are unchanged or consciously re-reviewed, and the SDK-bump sandbox gate is satisfied honestly.
- **P5** The model-launch drift detector and its tests know the new tier, stay single-hop, and keep reporting real stragglers.
- **P6** Docs, ADR-053, the plugin tier-policy text, and the eval harness provider list reflect Haiku 5.5.
- **P7** Every other place that could use the cheap tier has a recorded verdict, and each non-adopted candidate has a tracked follow-up.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Verdict |
|---|---|---|
| Bump `@anthropic-ai/claude-agent-sdk` 0.3.284 to 0.3.293 | P1 for the two canary scripts only | **Cut.** The SDK bundle is the sandbox (bwrap) argv builder; a bump re-opens `sdk-bump-sandbox-gate` capture and the committed canary fixture (`infra/sandbox-canary-argv.json`, `sdkVersion 0.3.284`). The only gain is a cheaper paid turn on two rarely-run scripts. Carve those two scripts out of the audit instead (Guard 1). |
| Fold #8643 (SDK-bundle model-id gate) into this PR | P4 | **Cut, acknowledged.** The SDK path receives no new id in this PR (SDK stays 0.3.284), and the gate needs a named-constant refactor in the Concierge runtime. Re-evaluation note goes on #8643. |
| Bump `claude-code-action` pin (v1.0.236, tip v1.0.246) | pin freshness | **Cut.** #2540 invariant: bump only when coupled to a `--model` change in the same workflow. No workflow changes its `--model` here (all four pin `claude-sonnet-5-5`). Pin freshness stays reported flag-only by the audit. |
| Re-tier any cron, workflow pin or CI workflow to Haiku 5.5 in this PR | P7 | **Cut.** ADR-053 makes re-tiering a separately attested change; Phase E records verdicts and files follow-ups with an eval gate. |
| `Math.max(1, ceil())` interim in `cost-writer.ts` (CFO suggestion) | P3 | **Cut.** With #6945's dimensional bug (`token_count * unit_cost_cents` summed against a cents budget) a 1-cent floor makes every Haiku turn contribute its full token count, so a single 20K-token turn would trip a 2000-point cap. Fixing quantization without fixing the product is worse than the status quo. Handled by acknowledging #6945 with new numbers. |
| `LeaderPromptModule.effort` + `promptVersion` bump for the Haiku leader classes | P2 for the 4096-token leader loop | **Cut by default (plan review: two seats).** The budget is large and the prompt text is unchanged; kept only as a conditional activated by a probe showing truncation (Phase 0 item 3). |
| Per-message effort, task budgets, compaction, tool search on Haiku | none requested | **Cut.** Not needed for parity. |
| A generic rate-card registry | P3 | **Cut.** One optional field on `ModelPricing` is the minimum that expresses two cards. |

### Findings that shape the plan

- **CLI bundle, measured** (2026-10-08, `npm pack @anthropic-ai/claude-code-linux-x64@<v>` unpacked outside the repo, `grep -a`): id absent in 2.1.284/2.1.290/2.1.291/2.1.292; present from 2.1.293. In 2.1.293 the model-table rows read `default_effort:"medium"` for `claude-opus-5-5`, `claude-sonnet-5-5` and `claude-haiku-5-5`, so `REVIEWED_DEFAULT_EFFORT` (audit `medium`, execution `medium`) does not move and `AUDIT_EFFORT = "high"` needs no re-decision. The same 2.1.293 bundle resolves the `haiku` alias to `claude-haiku-5-5` (`haiku:"claude-haiku-5-5"`), so the five `model: haiku` research agents and every `'cheap'` workflow pin follow automatically on a CLI at or above 2.1.293. No repo edit; effect recorded in Phase E.
- **Capability flag to resolve live**: the bundled Haiku 5.5 row lists `rejects_disabled_thinking`, while the API migration guide says `thinking: {"type":"disabled"}` is accepted at effort `low`, `medium`, `high`. The plan does not depend on that question: Phase C uses `output_config.effort: "low"` with adaptive thinking (valid under both readings) and raises `max_tokens` headroom; a live probe then validates it.
- **Pricing, verified** (pricing page, 2026-10-08), USD per MTok:

| Card | Input | Output | 5m cache write | 1h cache write | Cache read |
|---|---|---|---|---|---|
| Haiku 5.5, prompt up to 100,000 tokens | 0.10 | 0.50 | 0.125 | 0.20 | 0.01 |
| Haiku 5.5, prompt over 100,000 tokens | 0.50 | 2.50 | 0.625 | 1.00 | 0.05 |
| Haiku 4.5 (being replaced) | 1.00 | 5.00 | 1.25 | 2.00 | 0.10 |
| Sonnet 5.5 (page) | 2.00 | 10.00 | 2.50 | 4.00 | **0.10** (0.05x; repo has 0.20) |

  The page does not define whether cached tokens count toward the 100,000. Resolution: select the card on `input + cache_read + cache_creation` tokens (a superset), which can only over-attribute (the safe direction for a cap input). The boundary follows the page literally ("over 100,000 tokens"): strictly greater than 100,000 selects the long card.

- **Quantization amplification (#6945)**: at the new rates a representative leader turn costs $0.0025 at 20K uncached input plus 1K output and about $0.0007 when mostly cache reads, and both round to 0 cents under `Math.round(x * 100)`. Haiku-class leader runs return to the "structurally immune to the cap" side of the cliff described in #6945. Money at risk is bounded by Layer 3 (8 turns x 4096 `max_tokens`, about $0.02 to $0.03 worst case on Haiku 5.5), so this is a bookkeeping accuracy limitation, not an exposure; it is disclosed, not fixed here.
- **Call-site audit of the Haiku callers**:

| Caller | Mechanism | Budget | Haiku 5.5 hazard |
|---|---|---|---|
| `server/domain-router.ts:154` | raw `fetch`, literal id, `output_config.format` json_schema | `max_tokens: 200` | thinking tokens can exhaust 200 before a text block; fallback silently returns `["cpo"]` |
| `server/email-triage/summarize.ts` | `@anthropic-ai/sdk`, `HAIKU_MODEL` | `max_tokens: 256` | same truncation; empty `raw` becomes an empty stored summary |
| leader loop `triage.p0p1_issue`, `knowledge.kb_drift` | SDK `messages.create` with tools, 8 turns | 4096 per turn | thinking at `medium` can end a turn at `max_tokens`, which `persistFailure`s the run; thinking blocks are echoed back unchanged by the loop (append-only, good) |
| `.github/actions/anthropic-preflight` | `curl` | `max_tokens: 1` | unknown whether a thinking-on 1-token request still returns 200; Sonnet 5.5 (thinking on) already works at `max_tokens: 1` in `cron-anthropic-credit-probe.ts`, which is encouraging but not proof |
| `scripts/learning-retrieval-bench.sh` | `curl`, parses first text block | per script | none known; reads by type already |
| `sandbox-canary.mjs`, `plugin-root-sandbox-propagation-probe.mjs` | Agent SDK `query()` (SDK-bundled CLI, 0.3.284) | not applicable | SDK bundle does not know the id: **keep `claude-haiku-4-5`** (carve-out) |

- **Institutional learnings applied** (from the learnings sweep): `2026-07-25-a-stale-presence-guard-fails-green-and-an-unknown-model-id-halves-max-tokens` (bundle grep needs `-a` with positive and negative controls; guards must derive ids from the SSOT, not restate literals), `2026-02-22-model-id-update-patterns` (grep every spelling, re-grep after editing), `2026-04-18-action-pin-sync-with-model-bump`, `2026-06-11-model-launch-review-skill-build-premise-corrections` (pricing is flag-only, hand-edited from the source), `2026-10-06-fail-closed-fix-must-sweep-all-writers-and-producers` (an unpriced model must be NaN, never 0, in a WORM ledger), `2026-09-23-my-guards-read-source-through-a-stripper-that-deleted-the-code` (no `/*` inside a `//` comment in `model-tiers.ts`), `workflow-patterns/2026-09-29-detached-precommit-watchdog-and-sdk-bump-attestation` (the `sdk-bump-verified:` trailer, orphan watchdog for background commits).

## Research Reconciliation: Brief vs Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "claude-code-action pins" need updating | Four workflows pin `claude-code-action@...# v1.0.236` (tip v1.0.246) and all four pass `--model claude-sonnet-5-5`; none uses Haiku. | No `--model` swap, so no pin bump (#2540). Report pin age in the PR body (flag-only). |
| "#8643 (agent-sdk bundled CLI model-id gate)" is a prior launch | Open, deferred issue; no SDK-bundle gate exists. | Acknowledge, keep SDK pinned, comment on #8643. |
| "Check the claude-agent-sdk / claude CLI pin knows claude-haiku-5-5" | Neither does (0 hits); CLI 2.1.293 and SDK 0.3.293 do. | Bump the CLI pin only (Phase A); carve out the SDK-path scripts. |
| `agent-token-tee.sh`, `api-usage-section.tsx` listed as Haiku references | Neither contains a model id or a price. | No edit. |
| "pricing/tier maps" | One tier map (`MODEL_PRICING`) plus prose tier tables in ADR-053 and `plugins/soleur/AGENTS.md`. | Phase B (code) and Phase D (prose). |

## Implementation Phases

Ordering follows the guard dependency: the CLI test forces the pin before the constant; tests are written red first (`cq-write-failing-tests-before`). Commit boundaries are the seams so each can be reverted alone.

### Phase 0: Evidence before edits (read-only)

1. Re-fetch the pricing page and confirm the Haiku 5.5 two-card table and the Sonnet 5.5 cache-read figure; paste the two lines into the PR body.
2. Live probe (only when an Anthropic key is reachable through the project secret store without printing it; otherwise record "unverified-live" and ship the conservative configuration below). Two cells per caller shape, N=5 each on synthesized inputs (`cq-test-fixtures-synthesized-only`), scripts kept in the scratchpad and not committed: (a) the default request at the caller's original `max_tokens` (200 router, 256 summarizer, 1 preflight, 512 retrieval bench, 4096 with a tool definition for the leader loop), (b) the same with `output_config.effort: "low"`. Record per cell: HTTP status, `stop_reason`, whether a `text` (or `tool_use`) block exists, `usage.output_tokens`.
3. Decision rule: the **router and summarizer ship with `effort: "low"`** and a budget raised to 1024 if cell (b) still truncates. The **leader loop ships with no extra field** (no `effort` plumbing, no `promptVersion` bump) unless cell (a) at 4096 shows truncation or a `max_tokens` stop on either Haiku class, in which case Phase C item 3 is activated. `thinking: {"type":"disabled"}` is not probed and not used (capability-flag ambiguity, see Risks).
4. The preflight cell (`max_tokens: 1`, default thinking) decides its swap: HTTP 200 swaps the action to `claude-haiku-5-5`; anything else keeps it on its current id and adds it to the audit carve-out (Guard 1) with a dated reason. No request parameter is added to a liveness check.

### Phase A: CLI pin (RED then GREEN)

1. RED: change `HAIKU_MODEL` locally and run `./node_modules/.bin/vitest run test/server/inngest/claude-cli-pin-knows-models.test.ts`; expect the id-set guard to fail on 2.1.284. Revert; this is the proof the guard bites.
2. Bump `@anthropic-ai/claude-code` 2.1.284 to **2.1.293** in `apps/web-platform/package.json`, the `npm install -g` line in `apps/web-platform/Dockerfile` (currently line 62), and regenerate `package-lock.json` with `cd apps/web-platform && npx --yes npm@11 install --package-lock-only --min-release-age=0`. Leave `.npmrc` untouched. Leave `@anthropic-ai/claude-agent-sdk` at 0.3.284.
3. Release-age floor: 2.1.293 was published 2026-10-07T17:18Z, inside the 3-day floor until 2026-10-10T17:18Z. Using the one-off override is the documented model-launch-review flow; disclose it under a "Supply-chain floor override" heading in the PR body with evidence: the exact version, `npm view @anthropic-ai/claude-code@2.1.293 dist.integrity`, that 2.1.294 and 2.1.295 shipped afterwards without a deprecation notice, and that the override is one-off. If work resumes after the floor has lapsed, skip the override.
4. Re-run the bundle table read for `REVIEWED_DEFAULT_EFFORT` (already measured medium/medium in 2.1.293) and extend the test's header comment with the 2026-10-08 date and the new version. Add no Haiku row to `REVIEWED_DEFAULT_EFFORT` (the Haiku id never reaches the cron CLI; it is covered by the id-set guard).
5. Satisfy `sdk-bump-sandbox-gate.sh` for a CLI-only bump: the commit trailer `sdk-bump-verified:` must name the control the CLI actually moves, per model-launch-review SKILL.md (#8601): probe `cron-bash-allowlist-hook.mjs` with `npx -y @anthropic-ai/claude-code@<v> -p --output-format json --model claude-sonnet-5-5` (an id **both** 2.1.284 and 2.1.293 know; 2.1.284 cannot resolve `claude-haiku-5-5`, so a Haiku 5.5 probe would make the old-version control fail on model resolution instead of on the hook) asking for a non-allowlisted `echo`, require the command in `.permission_denials[]`, with 2.1.284 as the control. Background commits need `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1 setsid`. Add one smoke run per tier on the new CLI so a CLI regression is not blamed on Haiku: `npx -y @anthropic-ai/claude-code@2.1.293 -p --output-format json --model <claude-sonnet-5-5 | claude-opus-5-5 | claude-haiku-5-5>` (Haiku 5.5 is new-version only) with a trivial prompt, requiring a result event with no `Unknown --effort` warning and non-empty `result`. The pin commit is not independently revertible once the constant depends on it; the PR body says so.
6. Sweep `git grep -n "2\.1\.284"`: the Dockerfile, `package.json` and the lock move; references to "vendored CLI 2.1.284" in `agent-runner-sandbox-config.ts` and sandbox tests describe the **SDK-bundled** builder (still 0.3.284) and stay; `c4-likec4-version-pin.test.ts` fixtures are synthetic strings and stay.

### Phase B: SSOT constant and pricing (billing constant, separate commits)

1. RED tests first in `apps/web-platform/test/server/inngest/model-tiers.test.ts`: `HAIKU_MODEL` equals `claude-haiku-5-5`; Haiku pricing short card and long card pinned with the source line and date; boundary cases at 100,000 and 100,001 prompt tokens; a cache-heavy usage case (cache tokens push the prompt over 100K while `input_tokens` alone would not); an unpriced model still returns NaN.
2. `constants.ts`: `HAIKU_MODEL = "claude-haiku-5-5" as const` (alias == id, like Sonnet 5.5 and Opus 5.5); update the doc comment; `LeaderPromptModule` gains an optional `effort` (see Phase C).
3. `agent-on-spawn-requested.ts`: extend `ModelPricing` with an optional `longPrompt` card: `{ aboveTokens: 100_000, inputPerToken, outputPerToken, cacheReadPerToken, cacheCreatePerToken }`. `resolveTurnCostUsd` computes `promptTokens = input_tokens + cache_read_input_tokens + cache_creation_input_tokens` and uses the long card when `promptTokens > aboveTokens`. Replace the Haiku 4.5 row with the Haiku 5.5 row (short card 0.10/0.50/0.01/0.125 per MTok; long card 0.50/2.50/0.05/0.625), with the pricing page URL and 2026-10-08 in the comment. Remove the Haiku 4.5 row: the key set must equal the `AnthropicModelId` union (`model-tiers.test.ts`), and `leaderModule.model` is read per step so no in-flight turn can look up 4.5 after deploy. Keep the 5-minute cache-write assumption note (the call site passes no `ttl`).
4. **Sonnet 5.5 cache-read correction, own commit**: set `cacheReadPerToken` to 0.10/M only if the Phase 0 refetch still shows $0.10 (page footnote: "Cache hits ... on Claude Opus 5.5 and Claude Sonnet 5.5 are priced at 0.05x the base input price"). Record the change as a regime boundary in the row comment with the merge SHA and UTC time added at ship; the WORM ledger has no model column, so earlier rows are not restated and rolling cap windows will blend (safe direction: attribution only decreases). The bundled `claude-api` skill still lists $0.20 for Sonnet 5.5; the official pricing page is the authority, and the discrepancy is stated in the PR body. If the refetch disagrees with this plan, leave the Sonnet row untouched and file an issue instead.
5. Sweep other readers of the rate fields: `git grep -nE "inputPerToken|MODEL_PRICING|resolveTurnCostUsd"` (currently only `agent-on-spawn-requested.ts`, `model-tiers.ts` comments and tests); update `model-tiers.ts` header comments (the "mixed alias/dated convention" paragraph now lists three aliases and no dated id; do not put `/*` inside a `//` comment).
6. `PER_SPAWN_COST_CEILING_CENTS` stays 260 (ADR-041; it is a dollar promise, not a token budget). Add one sentence to its docstring that Haiku 5.5 turns are far below it.

### Phase C: Call-site adaptation

1. `domain-router.ts`: literal id replaced by importing `HAIKU_MODEL` is **not** done (this module must stay leaf-light and avoids importing server constants); keep a literal `claude-haiku-5-5` and add it to a parity assertion in the test that compares it with `HAIKU_MODEL`. Apply the Phase 0 configuration: `output_config: { effort: "low", format: ... }` and `max_tokens` raised only if the probe requires it. Add a `reportSilentFallback` mirror (op `domain-router-no-text-block`, `extra` carrying `stop_reason`, `stop_details.category` when present, and the model; never the message) when the response has no text block or `stop_reason` is `max_tokens` or `refusal`, importing it from `@/server/observability` (its imports are `@sentry/nextjs`, the logger, and PII helpers, none of them the octokit graph that `_cron-shared` pulls in; `anthropic-text-block-parity.test.ts` plus a check that `domain-router.ts` still reaches no `octokit` module guard this), so the existing silent `["cpo"]` fallback becomes visible (`cq-silent-fallback-must-mirror-to-sentry`). Update the #8392 test comment, which says this path "emits no thinking block": it now does.
2. `email-triage/summarize.ts`: same effort setting and budget decision; mirror a missing text block through `reportSilentFallback` without any subject, sender or body value (TR3).
3. Leader loop (**conditional**, only when the Phase 0 leader-shape cell shows truncation): add optional `effort?: "low" | "medium" | "high"` to `LeaderPromptModule`, set `"low"` on `triage.p0p1_issue` and `knowledge.kb_drift`, pass `output_config: { effort }` only when defined, bump both `promptVersion`s to `v1.1.0` (this labels new runs' `action_sends.prompt_version`; it does not change how an already-suspended run replays), and assert in `prompt-version-stability.test.ts` that the Haiku classes carry it. Otherwise the leader modules change only through `HAIKU_MODEL`, and `prompt-version-stability.test.ts` needs no edit beyond its existing model assertions (which already read the constant).
3b. Refusal handling (new on Haiku 5.5, no server-side fallback): do not send a `fallbacks` parameter on any Haiku request. Add one assertion to the existing leader-loop test that a Haiku-class turn returning `stop_reason: "refusal"` ends in the existing non-`end_turn`/`tool_use` `persistFailure` branch; for the router and summarizer a refusal is a response with no text block and takes the Sentry-mirrored fallback from items 1 and 2.
4. `.github/actions/anthropic-preflight/action.yml`: swap the id to `claude-haiku-5-5` **only if** the Phase 0 preflight probe returns 200; else carve out per Phase 0 step 4.
5. `scripts/learning-retrieval-bench.sh` `MODEL_ID` to `claude-haiku-5-5` (reads the first text block by type already; add `output_config.effort: "low"` to its `jq` request body if the probe shows truncation at its `max_tokens`).
6. Test fixtures: `test/helpers/anthropic-stub.ts` default model, `test/sandbox-credential-deny-runtime.test.ts` literal (a runtime test; check whether it exercises a real CLI that needs a known id before editing), `test/domain-router.test.ts`.

### Phase D: Audit tooling, skill, docs, eval harness

1. `audit-models.sh`: add `claude-haiku-4-5-20251001=claude-haiku-5-5` and `claude-haiku-4-5=claude-haiku-5-5` to `AUTOFIX_PAIRS` (both spellings: the id boundary means the undated pair does not match the dated id). Both RHS are the current id, so `assert_single_hop` stays satisfied. Add the SDK-path carve-out for exactly `apps/web-platform/scripts/sandbox-canary.mjs` and `apps/web-platform/scripts/plugin-root-sandbox-propagation-probe.mjs` (plus `.github/actions/anthropic-preflight/action.yml` only when its Phase 0 probe fails; `EXCLUDE_RE` has no `.github` exemption today, so without that third entry `--detect` would exit 10 on the branch) to the exclusion pattern with a comment naming #8643 and the SDK pin, and update the `echo` guidance block in `[2b]`/`[3]` if it enumerates tiers. Rephrase the `scripts/lint-anthropic-content-position.py` docstring so it no longer carries a bare `claude-sonnet-5` token (the detector reports it today: `--detect` exits 10 on this branch for that file alone, a permanently red drift signal unrelated to Haiku).
2. `plugins/soleur/test/model-launch-review.test.ts`: `CURRENT_IDS` gets `claude-haiku-5-5` in place of the dated 4.5 id; the synthesized `[2b]` fixtures that embed `claude-haiku-4-5-20251001` as a "current" id move to `claude-haiku-5-5`; add the carve-out test and the two-spelling pair test (derived from the live pair table through `parseAutofixPairs`, not restated).
3. `model-launch-review/SKILL.md`: add "Haiku 5.5" to the lineage line (`Opus 4.6 -> ... -> Sonnet 5.5 -> Haiku 5.5`), update the `[2b]` probe example's `--model` from `claude-haiku-4-5` to an id that both the old and the new pin know (`claude-sonnet-5-5` today) and say why, and add two sharp edges learned here: (a) a model with a prompt-length-tiered price needs the tier boundary pinned, and the audit's pricing flag cannot see it; (b) a carve-out for SDK-bundled consumers must name the pin whose bump retires it.
4. `eval-harness`: run `bash plugins/soleur/skills/eval-harness/scripts/gen-models.sh` to regenerate `models.generated.json` (the generator is the sole writer; the file is excluded from the sweep by design); run `plugins/soleur/skills/eval-harness/test/gen-models.test.sh`. The README's dated delta record (haiku-4-5, 2026-06-15) is history and stays.
5. Docs prose, hand-edited next to each swapped id because the sweep fixes the id but not adjacent price text: `agent-native-architecture/references/{agent-execution-patterns,agent-native-testing,architecture-patterns,mobile-patterns}.md` (mobile-patterns line "claude-haiku-4-5: ~$1/1M input, $5/1M output" becomes ~$0.10/$0.50), `dspy-ruby/SKILL.md`, `dspy-ruby/references/providers.md` ("Haiku 4.5" lists and `anthropic/claude-haiku-4-5`).
6. `plugins/soleur/AGENTS.md` "Model Selection Policy": refresh only the Haiku figures in the pricing-basis paragraph (Haiku 5.5 is $0.10/$0.50 up to 100K prompt tokens) and add one clause that the `haiku` alias resolves to 5.5 on CLIs at or above 2.1.293.
7. ADR-053 amendment (dated 2026-10-08): update the tier table (Haiku 5.5 row, short and long card), surface rows 5a (founder BYOK domain routing now on 5.5), and add "Haiku 5.5 launch re-evaluation" with the Phase E verdicts and the re-evaluation trigger. No new ADR: the decision extends ADR-053's tier map.
8. The ADR-053 amendment names two launch-checklist items so they are not rediscovered: re-read the `longPrompt` card boundary for any model with a prompt-length price, and re-verify each small-`max_tokens` caller's effort/thinking behaviour. (The compound learning is written at ship, not tracked here.)

### Phase E: Where Haiku 5.5 fits better (evaluation deliverable)

Method: inventory by independent grep of every model-selecting site (`EXECUTION_MODEL`, `AUDIT_CLI_ARGS`, `SONNET_MODEL`, workflow `model:` pins, agent frontmatter, CI `--model`), then judge each against ADR-053's rule (mechanical, bounded, user-data-free steps may go cheap; never-downgrade list excluded). Price context: Haiku 5.5 is 20x cheaper than Sonnet 5.5 on short prompts and about 4x above 100K prompt tokens, with the tokenizer inflation (about 30% more tokens) already inside per-token terms.

| # | Site | Today | Haiku 5.5 verdict | Reason / action |
|---|---|---|---|---|
| 1 | domain-router, email summarize, `triage.p0p1_issue`, `knowledge.kb_drift` | Haiku 4.5 | **Move to 5.5** (this PR) | Classification shape; same tier. |
| 2 | Five `engineering/research/*` agents (`model: haiku`) | alias | **Follows automatically** | CLI at or above 2.1.293 resolves the alias to 5.5. Expect thinking-on token growth per agent, offset by about 10x lower rates. Measure once in a real `/plan` run; no edit. |
| 3 | Workflow `'cheap'` pins (`file:${fid}`, `fetch:round-${round}`) | alias | **Follows automatically** | Same alias mechanism. |
| 4 | `cron-anthropic-credit-probe.ts` (hourly, `maxTokens: 1`, `EXECUTION_MODEL`) | Sonnet 5.5 | Fits, **immaterial** | Cost is about 0.00002 USD per call; the probe's value is key liveness, not model parity. No change; revisit only if it moves to the shared helper's tier. |
| 5 | `pdf-chapter-router.ts` (`ROUTING_MODEL`, Agent SDK `query()`) | Sonnet 5.5 | **Candidate** | Routing/classification shape and `AMBIGUOUS` sentinel. Blocked on the Agent SDK pin (0.3.284 does not know the id) and on #8643. Follow-up issue: re-evaluate at the next SDK bump with an eval over real chapter-routing prompts. |
| 6 | `cron-daily-triage`, `cron-follow-through-monitor`, `cron-campaign-calendar`, `cron-community-monitor` (CLI agentic crons on `EXECUTION_MODEL`) | Sonnet 5.5 | **Candidate, not adopted** | Triage/summarize-shaped, but they are multi-turn tool-using agents on the operator key with `--max-turns` up to 80; failure is silent (green monitors). ADR-053 requires a separately attested model-bump PR. Follow-up issue with an eval arm built on `eval-harness` (`models.generated.json` already includes the new id after this PR). |
| 7 | `cron-compound-promote` (clustering, 16K tokens, structured output) | Sonnet 5.5 | **Not a fit** | Reads operator-session learnings and writes PRs (GDPR gate trigger c); keep the stronger tier. |
| 8 | `cron-weekly-release-digest` | Sonnet 5.5 | **Not a fit** | Self-identified never-downgrade shape. |
| 9 | Workflow `'standard'` pins (`classify`, `parse`, `analyze`, `commit`, `report`, `cluster`, `detect-threshold`) | Sonnet 5.5 | **Candidate, not adopted** | Mechanical on paper; `workflow-model-pins.test.ts` `PIN_ALLOWLIST` is a clo-attestation-class invariant. Follow-up: per-label eval, start with `commit` and `detect-threshold` (smallest blast radius). |
| 10 | CI `claude-code-review.yml` etc. (`--model claude-sonnet-5-5`) | Sonnet 5.5 | **Not a fit** | Review/judgment on the never-downgrade list; also no pin bump without a `--model` swap. |
| 11 | Audit tier (Opus 5.5), Concierge/leader reasoning classes (`engineering.pr_review_pending`, `engineering.ci_failed`) on Sonnet 5.5 | mixed | **Not a fit** | Deep reasoning and agentic coding; the launch post says Haiku 5.5 is not for complex agentic coding. |
| 12 | Effort/model router (#6000, open) | none | **Future consumer** | Haiku 5.5's effort levels make a single tier-to-model table plus an effort column viable; out of scope, comment on #6000 with the verified effort facts (default `medium`, five levels, CLI row `medium`). |
| 13 | `cron-bug-fixer`, `fix-constraints-stage-a.yml`, `test-pretooluse-hooks.yml` (agentic coding with edit tools) | Sonnet 5.5 | **Not a fit** | Complex agentic coding; also merge-gating or code-producing, so on the never-downgrade list. |
| 14 | `security.cve_alert` leader class (Sonnet 5.5) | Sonnet 5.5 | **Not a fit** | Security-flavored; Haiku 5.5's cyber safeguards decline pentest-style prompts with no server-side fallback, and a refusal here would drop a real alert. |
| 15 | Compaction and context-summarization steps | none in this repo | **Not applicable today** | `git grep` finds no Soleur-owned compaction call with a model choice (the Claude Code harness owns compaction). If a server-side compaction is added later, Haiku 5.5 is the default candidate; record in the ADR amendment as a placement rule, not as work. |
| 16 | Advisor consults (`resolveAdvisorTier()`, ADR-083) and harness tier map (ADR-110) | Fable 5.1 / `cheap` = `haiku` alias | **Unchanged** | ADR-083 upgrades are judgment gates and stay on the advisor tier; ADR-110's `cheap` tier maps to the `haiku` alias on Claude (it now resolves to 5.5 on CLIs at or above 2.1.293) and to `grok-4.5` on Grok. `harness-model-map.ts` needs no edit; `harness-model-map.test.ts` pins the alias, not an id. |

Follow-up issues (deferral tracking gate; each with milestone from `knowledge-base/product/roadmap.md`, "what, why, re-evaluation criteria", labels verified with `gh label list --limit 200` before use): (a) pdf-chapter-router to Haiku 5.5 after the SDK bump; (b) one eval-gated re-tiering issue covering the triage/summarize-shaped execution crons (row 6) and the `'standard'` to `'cheap'` workflow pins (row 9), so the `eval-harness` arm is built once; plus comments on the existing #6945 (quantization numbers), #8643 (evaluation, self-expiring carve-out) and #6000 (effort facts). Issues are created at ship time; their numbers go into the ADR amendment.

### Phase F: Verification

- `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/model-tiers.test.ts test/server/inngest/claude-cli-pin-knows-models.test.ts test/server/inngest/leader-prompts test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts test/server/cost-writer-unpriced.test.ts test/domain-router.test.ts test/anthropic-text-block-parity.test.ts` plus `test/server/email-triage/summarize.test.ts`, and `./node_modules/.bin/tsc --noEmit` (the repo root declares no workspaces, so no `npm run -w` form).
- `bun test plugins/soleur/test/model-launch-review.test.ts plugins/soleur/test/components.test.ts plugins/soleur/test/harness-model-map.test.ts plugins/soleur/test/workflow-model-pins.test.ts`.
- `bash plugins/soleur/skills/model-launch-review/scripts/audit-models.sh` (all groups) and `--detect` must print `model-drift: none (config model IDs current).` with rc 0; `[2b]` must print `ok      claude-haiku-5-5 present in the pinned CLI bundle`.
- `python3 scripts/lint-anthropic-content-position.py` exits 0; `bash plugins/soleur/test/c4-count-parity.test.sh` stays green.
- `bash plugins/soleur/skills/eval-harness/test/gen-models.test.sh`.
- Run the repo's deterministic lints on each guard-shaped commit before spawning any review panel (model-launch-review sharp edge).

## Files to Edit

- `apps/web-platform/server/inngest/leader-prompts/constants.ts` (HAIKU_MODEL, `LeaderPromptModule.effort`)
- `apps/web-platform/server/inngest/leader-prompts/triage.p0p1_issue.ts`, `knowledge.kb_drift.ts` (only if the conditional Phase C item 3 activates: effort, promptVersion)
- `apps/web-platform/server/inngest/leader-prompts/index.ts` (comment only, if it restates the Haiku id)
- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` (MODEL_PRICING tier, Sonnet cache-read, effort pass-through)
- `apps/web-platform/server/inngest/model-tiers.ts` (comments)
- `apps/web-platform/server/domain-router.ts`, `apps/web-platform/server/email-triage/summarize.ts`
- `apps/web-platform/package.json`, `apps/web-platform/package-lock.json`, `apps/web-platform/Dockerfile`
- `apps/web-platform/test/server/inngest/model-tiers.test.ts`, `claude-cli-pin-knows-models.test.ts` (header only), the leader-loop test (one refusal assertion)
- `apps/web-platform/test/domain-router.test.ts`, `test/helpers/anthropic-stub.ts`, `test/sandbox-credential-deny-runtime.test.ts`, `apps/web-platform/test/server/email-triage/summarize.test.ts`, `apps/web-platform/test/anthropic-text-block-parity.test.ts` (selection-predicate parity; also the import-graph check for the router)
- `.github/actions/anthropic-preflight/action.yml` (conditional on the probe)
- `scripts/learning-retrieval-bench.sh`, `scripts/lint-anthropic-content-position.py` (docstring only)
- `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh`, `plugins/soleur/skills/model-launch-review/SKILL.md`, `plugins/soleur/test/model-launch-review.test.ts`
- `plugins/soleur/skills/eval-harness/models.generated.json` (regenerated, never hand-edited)
- `plugins/soleur/AGENTS.md`
- `plugins/soleur/skills/agent-native-architecture/references/{agent-execution-patterns,agent-native-testing,architecture-patterns,mobile-patterns}.md`, `plugins/soleur/skills/dspy-ruby/SKILL.md`, `plugins/soleur/skills/dspy-ruby/references/providers.md`
- `knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-haiku-5-5-support/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-haiku-5-5-support/decision-challenges.md` (supply-chain floor override; Sonnet cache-read correction timing)

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200`, then `jq --arg path` over each planned path.

- **#8643** (ci(models): gate that the pinned claude-agent-sdk bundled CLI knows the Agent SDK model ids) matches `claude-cli-pin-knows-models.test.ts`. **Acknowledge.** Its stated trigger is "next Anthropic model launch or next SDK bump"; this launch does not put a new id on the SDK path (SDK stays 0.3.284) and the gate requires routing the Concierge default through a named constant. Add a comment on #8643 recording the evaluation and that the carve-out in `audit-models.sh` retires when the SDK pin moves.
- **#9648** (Mistral Large 4 + Mistral Vibe support) matches `MODEL_PRICING` conceptually (its Stage 2 adds a priced row). **Acknowledge.** The optional `longPrompt` field is additive and does not constrain a flat row.
- **#6945** (BYOK cap compares cents x tokens to a cents budget; sub-cent turns quantize to 0) and **#7920** (same product defect at founder scope) are not file matches but are the accounting behaviour this change interacts with. **Acknowledge** with a comment on #6945: Haiku 5.5 moves the two Haiku leader classes back below the 0.5 cent cliff (illustrative turn: $0.0025 uncached or about $0.0007 mostly cached, both under half a cent), which restores the "immune" side; bounded exposure is about 2 to 3 cents per run; the correct fix is the dimensional one, not a rounding floor (see Cut List).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Update Soleur everywhere it's needed to support this new model version" [brief] | Phases A to D | mapped |
| 2 | "model-ID references" [brief] | Phase B items 2, Phase C, Phase D items 1 to 5 | mapped |
| 3 | "pricing/tier maps" [brief] | Phase B items 3 to 5, Phase D items 6 to 7 | mapped |
| 4 | "claude-code-action pins" [brief] | Cut List and Research Reconciliation (evaluated; no `--model` swap so no bump); PR body reports pin age | mapped |
| 5 | "docs, tests" [brief] | Phase D items 2 to 7, tests in every phase | mapped |
| 6 | "check whether there are any locations where Haiku 5.5 would be better suited than the current model" [brief] | Phase E | mapped |
| 6b | "which call sites should NOT move" [coordinator message] | Phase E rows 7, 8, 10, 11, 13, 14 (explicit do-not-move rows) and the Cut List | mapped |
| 7 | "Use the soleur:model-launch-review skill's checklist as the baseline" [brief] | Phase A (item 2b), Phase B (item 4), Phase D (items 1, 5; item 3 thinking shape in Phase C), Phase E (item 5 tier map), Phase F audit run | mapped |
| 8 | "Pricing for Haiku 5.5 must be verified from Anthropic docs (context7 / claude-api skill / WebFetch), not guessed." [context hints] | Research Insights pricing table; Phase 0 item 1 | mapped |
| 9 | "Check the claude-agent-sdk / claude CLI pin knows claude-haiku-5-5" [context hints] | Phase A | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Constant, call-site and doc id swaps | "model-ID references" | asked |
| `MODEL_PRICING` Haiku 5.5 row | "pricing/tier maps" | asked |
| Optional `longPrompt` card + `resolveTurnCostUsd` tier selection | "Pricing for Haiku 5.5 must be verified from Anthropic docs" | asked (the verified page has two cards; a flat row cannot represent it) |
| CLI pin 2.1.284 to 2.1.293 | "Check the claude-agent-sdk / claude CLI pin knows claude-haiku-5-5" | asked |
| `audit-models.sh` pairs, test and SKILL updates | "Use the soleur:model-launch-review skill's checklist as the baseline" | asked |
| Phase E verdict table and follow-ups | "check whether there are any locations where Haiku 5.5 would be better suited" | asked |
| ADR-053 amendment, AGENTS.md pricing basis | "pricing/tier maps" | asked |
| Eval harness `models.generated.json` regeneration | "tests" | asked (generated artifact fed from the constant; stale otherwise) |
| Effort `low` on the router and summarizer (conditional leader-loop field) | — | inferred — justification: Haiku 5.5 turns thinking on by default; without it the 200- and 256-token routes can truncate to empty output (correctness dependency of the id swap) |
| Sentry mirrors on missing text block | — | inferred — justification: `cq-silent-fallback-must-mirror-to-sentry`; the existing fallbacks are silent and become reachable with thinking-on |
| Sonnet 5.5 cache-read correction | — | inferred — justification: found while verifying the pricing table the ask requires; same row table and regime comment, separate commit and gated on a live refetch so it can be dropped alone |
| `lint-anthropic-content-position.py` docstring rephrase | — | inferred — justification: it keeps `audit-models.sh --detect` red (rc 10) on the branch today, which would mask any real Haiku straggler the new pairs are meant to surface |
| Carve-out for the two SDK-path scripts | — | inferred — justification: without it the new pair would make `--fix` rewrite scripts whose SDK bundle does not know the id and make `--detect` permanently red |
| Supply-chain floor override disclosure | — | inferred — justification: required by the CLI bump per model-launch-review SKILL.md; keeps the waiver reviewable |

### Split Assessment

- Subsystems touched: 5 — `apps/web-platform`, `plugins/soleur`, `.github`, `scripts`, `knowledge-base`
- Planned files: about 34 | Estimated changed lines: about 650 (pin lockfile churn excluded)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **single PR, ordered commits** — thresholds exceeded on roots and file count, split considered and declined for a stated reason. Proposed seam if ever split: PR1 = Phase A (CLI pin, no model change), PR2 = Phases B to E. Declined because (i) the user asked for one end-to-end support change, (ii) roughly 14 of the files are mechanical doc/prose swaps with no behavioural risk, (iii) the seam is already commit-level (`git revert` of the Phase B/C commits restores 4.5 while the pin stays), and (iv) PR2 cannot be green before PR1 lands, so a split serialises two CI cycles with no isolated value for PR1 beyond a soak this pipeline cannot wait for. The soak risk that remains is recorded under Risks.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `grep -a -c 'claude-haiku-5-5' apps/web-platform/node_modules/@anthropic-ai/claude-code-linux-x64/claude` prints a number >= 1 after the lock regeneration, `node_modules/@anthropic-ai/claude-code-linux-x64/package.json` reports 2.1.293, `package.json`, `Dockerfile` and `package-lock.json` agree, and `@anthropic-ai/claude-agent-sdk` is still 0.3.284.
- [ ] AC2 `HAIKU_MODEL === "claude-haiku-5-5"`; `Object.keys(MODEL_PRICING)` equals the `AnthropicModelId` union; the Haiku row equals the committed short and long cards; `resolveTurnCostUsd("claude-haiku-5-5", {input_tokens: 100000, ...zeros})` uses the short card and `input_tokens: 100001` uses the long card; a usage with 60,000 `input_tokens` + 50,000 `cache_read_input_tokens` uses the long card; an unknown model returns NaN.
- [ ] AC3 `git grep -nE 'claude-haiku-4-5' -- . ':(exclude,glob)knowledge-base/**' ':(exclude,glob)**/test/**'` lists only: the two carve-out scripts (and the preflight action when its probe failed), the `AUTOFIX_PAIRS` left-hand sides in `audit-models.sh`, and explanatory comments that say the id is superseded; every other hit is a failure. (Expected-set assertion is written in `model-launch-review.test.ts`, not left to eyeball.)
- [ ] AC4 `bash plugins/soleur/skills/model-launch-review/scripts/audit-models.sh --detect` exits 0 and prints `model-drift: none (config model IDs current).`; the full audit prints `ok      claude-haiku-5-5 present in the pinned CLI bundle` in `[2b]`.
- [ ] AC5 Each Haiku caller has a test that feeds a response beginning with a `thinking` block and one with no text block (for the router and summarizer a `stop_reason: "refusal"` body is one such case; for the leader loop a refusal turn lands in `persistFailure`): the first yields the parsed result, the second produces a Sentry mirror (op `domain-router-no-text-block` for the router) and the documented fallback.
- [ ] AC6 Phase 0 probe results (or the explicit text "unverified-live: no reachable key") appear in the PR body with the chosen configuration per caller and the decision-rule outcome.
- [ ] AC7 The commit that bumps the lock carries a `sdk-bump-verified:` trailer naming the hook probe and its control (2.1.284), and `bash apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` passes against `origin/main`.
- [ ] AC8 Either the Phase 0 leader-shape cell showed no truncation and the leader modules are unchanged apart from the model constant (`prompt-version-stability.test.ts` passes as is), or the conditional Phase C item 3 landed and `prompt-version-stability.test.ts` passes with the two Haiku classes at `v1.1.0` carrying `effort: "low"` and the Sonnet classes carrying none.
- [ ] AC9 ADR-053 contains a dated 2026-10-08 amendment with the Haiku 5.5 rate cards, the surface-5a update and the Phase E verdict table; `plugins/soleur/AGENTS.md` pricing basis is refreshed.
- [ ] AC10 Follow-up issues (a) and (b) exist with milestone and re-evaluation criteria and are linked from the ADR amendment; comments are posted on #8643, #6945 and #6000.
- [ ] AC11 `python3 scripts/lint-anthropic-content-position.py`, `python3 scripts/lint-guard-contract.py` (over this plan), the vitest and bun suites listed in Phase F, `bash plugins/soleur/skills/eval-harness/test/gen-models.test.sh`, and `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` all pass; `npx markdownlint-cli2` passes on this plan and `tasks.md`.
- [ ] AC12 The PR body's first line states that merging deploys the web-platform image (CLI pin and Haiku routing change); it also carries the "Supply-chain floor override" section (if the override was used) and states the Sonnet cache-read correction and its regime-boundary caveat.

### Post-merge

None to execute by hand. Merging touches `apps/web-platform/**`, so `web-platform-release.yml` rebuilds the image (CLI 2.1.293) and restarts the container as part of the normal release; nothing else mutates production. The PR body's first line states exactly that. The drift detector's next scheduled run (`rule-audit.yml`, step "model-drift") is the standing post-merge check; it is not a gate for this PR and is not polled here.

## Test Scenarios

1. Pricing: short card at exactly 100,000 prompt tokens; long card at 100,001; cache-heavy usage crossing the boundary; zero usage; unpriced model NaN; Sonnet row values (including the cache-read figure if corrected).
2. Parity: literal in `domain-router.ts` equals `HAIKU_MODEL`; `models.generated.json` equals the constants.
3. CLI pin: guard reds on 2.1.284 with `HAIKU_MODEL` at 5.5 (RED proof), greens on 2.1.293; Dockerfile and `package.json` disagreement reds; `REVIEWED_DEFAULT_EFFORT` unchanged (medium, medium).
4. Response shape: thinking block first; no text block with `stop_reason: "max_tokens"`; redacted thinking; two text blocks (first wins).
5. Leader loop: the Haiku class request is unchanged except for the model id (or carries `output_config.effort: "low"` when the conditional item activated); top-level `cache_control` unchanged; a tool-use turn echoes assistant content (including thinking) back unchanged; a `refusal` stop ends in `persistFailure`.
6. Audit: dated and undated Haiku 4.5 spellings are both detected and rewritten; a file in the carve-out is neither detected nor rewritten; a second stale file in the same directory as a carve-out is still detected; `assert_single_hop` exits 78 on a chained RHS.
7. Live (conditional): matrix from Phase 0 against the real API.

## Guard Contract

### Guard 1 — model-launch drift detector (audit-models.sh pairs and carve-out)

**Property.** After this change, `audit-models.sh --detect` exits 10 if and only if a config-class file outside the documented SDK-path carve-out carries a superseded Haiku id in either spelling, and `--fix` rewrites exactly the files `--detect` selected.

**Assembly.** The property quantifies over: the two new `AUTOFIX_PAIRS` entries (dated and undated spelling), the selection regex built by `autofix_match_re`, the `--fix` sed that must share the same `ID_BOUNDARY`, the exclusion pattern (including the new carve-out for exactly two files), `assert_single_hop`, the `[1]` re-scan, and the test-side `CURRENT_IDS` plus `parseAutofixPairs`. The chokepoint is `ID_BOUNDARY`; any second spelling of the boundary is the defect. There is more than one injection site (selection, rewrite, re-scan, exclusion) and the contract covers all four.

**Mutation matrix.**

| # | Mutation (edit that must drive the guard RED) | Expected failing check |
|---|---|---|
| 1 | Delete the dated pair `claude-haiku-4-5-20251001=claude-haiku-5-5` | pair-table-driven test: a fixture carrying the dated id is no longer detected |
| 2 | Widen the carve-out to the whole `apps/web-platform/scripts/` directory | a second stale-id fixture in that directory (added after the compliant first member) must still be detected, so the test reds |
| 3 | Make the scan dispatch zero files (point `--root` at an empty directory) | must exit non-zero or report zero scanned; a clean "none" with zero files examined reds the anti-vacuity test |
| 4 | Remove the carve-out entirely | the carve-out test (the carve-out paths must not be selected or rewritten) reds |
| 5 | Raise the `@anthropic-ai/claude-agent-sdk` pin to 0.3.293 or later while the carve-out remains | the self-expiring test reds with the instruction to delete the carve-out and swap the two scripts to `claude-haiku-5-5` |

Rows for a chained map (`assert_single_hop`, exit 78) and for dropping `|$` from `ID_BOUNDARY` are already pinned by existing tests in `model-launch-review.test.ts` (the NON-CONVERGENT test and the end-of-line boundary test); they are not restated here.

**Harness rows.** (a) Edit the suite, not the guard: make `parseAutofixPairs` return an empty list; the test must red through a floor on pair count, because a table-driven test over zero pairs passes vacuously. (b) Must-PASS input that is not the canonical: a config file containing `claude-haiku-5-5` plus a longer dated lookalike `claude-haiku-4-5-20251001-x`... the lookalike differs from the canonical shape in the way the contract permits (a longer token is not the stale id) and must report clean.

**Anchor.** The pair table and the files it scans live in the same commit, so the guard proves consistency, not integrity. The carve-out is self-expiring (row 5): a test reads the SDK pin from `apps/web-platform/package.json` and fails once it reaches 0.3.293, the first SDK release whose bundle carries the id, so the exemption cannot outlive the reason for it. This is the cheap, mechanical slice of #8643. The independent anchor is the live pricing/models page and the bundled `claude-api` skill table, re-fetched at work time and quoted in the PR body; no merge-base diff can supply it.

### Guard 2 — MODEL_PRICING value and prompt-length-card pin

**Property.** For every model reachable through `MODEL_PRICING[leaderModule.model]`, `resolveTurnCostUsd` returns the published per-token price for the card that the turn's prompt length selects, and never returns 0 for an unpriced model.

**Assembly.** The property quantifies over: every key of `MODEL_PRICING` against the `AnthropicModelId` union; every rate field of every card (input, output, cache read, cache create); the tier-selection expression (which token counts enter it, and the comparison operator); and the single consumer call site in `agent-on-spawn-requested.ts` plus the NaN contract tested in `cost-writer-unpriced.test.ts`. The chokepoint is `resolveTurnCostUsd`.

**Mutation matrix.**

| # | Mutation (must drive the guard RED) | Expected failing check |
|---|---|---|
| 1 | Restore the Haiku 4.5 values (1/5/0.10/1.25) under the new key | committed-rates pin test |
| 2 | Change the comparison from `>` to `>=` at the boundary | the 100,000 exact case |
| 3 | Compute the tier from `input_tokens` only | the cache-heavy case (60K input + 50K cache read) |
| 4 | Change the Sonnet row after a compliant Haiku row (second member) | the Sonnet value pin, proving the check does not stop at the first row |
| 5 | Remove the Haiku key | key-parity test against the union |
| 6 | Replace the `!pricing` NaN arm with a zero-filled fallback | unpriced-model NaN test |

**Harness rows.** (a) Edit the suite: replace the exact `toEqual` pin with `toBeDefined`; a numeric end-to-end case (`resolveTurnCostUsd` result for fixed usage compared to a hand-computed dollar value) must still red. (b) Must-PASS non-canonical input: usage of exactly 100,000 prompt tokens with a nonzero cache-read split, which the contract explicitly permits (strictly-greater rule) and must price on the short card.

**Anchor.** The stored rates and the code reading them can be edited in one diff. The independent anchor is the official pricing page fetched during Phase 0 and the explicit regime-boundary note (merge SHA, UTC time) in the row comment; a Console invoice line is the only true external anchor and is not available to this pipeline.

## Observability

```yaml
liveness_signal:
  what: rule-audit.yml model-drift detection step (audit-models.sh --detect) plus the existing Sentry cron monitors for the Haiku-backed Inngest functions
  cadence: scheduled by rule-audit.yml; per-run for the Inngest functions
  alert_target: one idempotent model-drift GitHub issue; Sentry issues for the crons
  configured_in: .github/workflows/rule-audit.yml and apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts

error_reporting:
  destination: Sentry web-platform via reportSilentFallback (feature/op tagged), plus the pino mirror
  fail_loud: new op values domain-router-no-text-block and the email-triage equivalent are emitted when a Haiku response has no text block or ends at max_tokens; persistFailure records leader_max_turns_exceeded or stop_reason for the leader loop

failure_modes:
  - mode: Haiku 5.5 thinking consumes the small max_tokens budget and no text block is returned
    detection: reportSilentFallback op on the missing text block, with stop_reason and model in extra (no message content)
    alert_route: Sentry issue grouped by op
  - mode: a Haiku 4.5 id reappears in a config-class file
    detection: audit-models.sh --detect exit 10 in rule-audit.yml
    alert_route: model-drift GitHub issue
  - mode: pinned CLI loses knowledge of a tier id after a future bump
    detection: claude-cli-pin-knows-models.test.ts in CI
    alert_route: red required check on the PR
  - mode: a model is added to the leader loop without a pricing row
    detection: resolveTurnCostUsd returns NaN, both cost writers fail closed and alert
    alert_route: Sentry

logs:
  where: Sentry events and Inngest run logs for the web-platform app
  retention: per the Sentry plan retention window

discoverability_test:
  command: bash plugins/soleur/skills/model-launch-review/scripts/audit-models.sh --detect
  expected_output: model-drift: none
```

## Domain Review

**Domains relevant:** Engineering, Finance

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Overall risk medium. Riskiest step: flipping the shared constant and the router literal before a live probe, because the failure is silent (truncated or empty classification, then a mis-route to the fallback leader). Adopted: probe first, configuration chosen by a decision rule, Sentry mirror on a missing text block, router adapted last in Phase C. Recommended splitting the CLI pin from the flip for soak: considered and declined for the recorded reasons in the Split Assessment (commit-level seam retained). Recommended not bumping the Agent SDK for the canary scripts: adopted (Cut List). Flagged that the `domain-router.test.ts` #8392 comment becomes false: adopted. Suggested keeping the preflight on 4.5 or probing it: adopted as a conditional.

### Finance (CFO)

**Status:** reviewed
**Assessment:** Flat row cannot hold two cards; add an optional long-prompt card and select on the superset of input-side tokens so ambiguity can only over-attribute: adopted. Sonnet cache-read correction is a regime boundary in a WORM ledger, not a back-applied fix: adopted with merge SHA and UTC time, gated on a refetch, and a Console invoice line named as the only true external anchor. Ceiling stays 260 (ADR-041): adopted. Savings: 20x versus Sonnet 5.5 and about 10x versus Haiku 4.5 per token (about 7.7x after tokenizer inflation) at or below 100K prompt tokens; about 4x above 100K; no spawn-volume data exists in the repo, so no absolute dollar figure is claimed. Riskiest step named: integer-cent rounding (`Math.round(x * 100)`) storing 0 for sub-cent turns. Partially adopted: the rounding concern is real and pre-existing (#6945), but the proposed `Math.max(1, ceil())` interim is rejected because it interacts with the cents-times-tokens product in the cap SQL and would make single Haiku turns trip the cap (Cut List); disclosed and routed to #6945.

### Not relevant (assessed)

Product/UX (no UI surface; `api-usage-section.tsx` is prose only, no price or id), Marketing, Legal (same vendor, same data flows, no new processing activity or subprocessor; the GDPR gate is not triggered: no schema, auth, route or new LLM data movement), Operations, Sales, Support.

## User-Brand Impact

- **If this lands broken, the user experiences:** the domain-routing classifier silently falling back to the CPO leader for every message (wrong advisor on the first reply), or a triage/KB-drift leader run failing with a "max turns / max tokens" notification instead of an action.
- **If this leaks, the user's money is exposed via:** mis-attributed BYOK cost in the WORM `audit_byok_use` ledger (a wrong Haiku 5.5 rate card or tier selection would be permanent and feeds both cap layers); no credentials, content or personal data are newly exposed because the vendor, data flow and prompts are unchanged.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the failure shapes are uniform and fail-closed (unpriced model returns NaN, pricing pinned by tests, bounded Layer 3 spend of a few cents per run), so no single founder can suffer a distinct, irreversible harm, which rules out `single-user incident`; a systematic mis-attribution across founders is an aggregate pattern, which rules out `none`.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-053** (per-call model tiering): Haiku tier moves to 5.5, two-card price recorded, surface 5a updated, Phase E verdict table and re-evaluation trigger added. Task in Phase D item 7. No new ADR: no new substrate, boundary or ownership change; the decision extends the existing tier map.

### C4 views

No C4 impact. Read `model.c4`, `views.c4`, `spec.c4` (934/124/54 lines). Checked: (a) external human actors: none added or changed; (b) external systems: Anthropic API is modeled (`anthropic = system "Anthropic API"`) with edges `engine -> anthropic` (BYOK LLM calls), `claude -> anthropic`, `api -> anthropic` (admin cost report), `github -> anthropic` (CI turns), `evalharness -> anthropic`; the change swaps which model those edges call, and no model id, tier or price appears in any `.c4` file (grep for haiku, sonnet, opus, claude- finds only descriptions of unrelated components); (c) containers/data stores: none added (the WORM ledger is unchanged in shape); (d) actor-to-surface access relationships: unchanged. Run `bash plugins/soleur/test/c4-count-parity.test.sh` and the C4 syntax test to confirm no derived count moved.

### Sequencing

The decision is true immediately at merge; nothing is gated on a later slice.

## Risks and Sharp Edges

- **Soak risk accepted.** One PR carries a CLI bump across nine versions (2.1.284 to 2.1.293) plus the flip. Mitigation: the CLI feeds only the operator-key crons (sandbox disabled there, containment is the allowlist hook, probed in AC7); the interactive sandbox builder is the SDK bundle, which does not move. Reverting the Phase B/C commits restores 4.5 without touching the pin.
- **Unknown `disabled` thinking semantics** (API docs say accepted at effort at or below high; the CLI row says `rejects_disabled_thinking`): avoided by design; do not add `thinking: {type: "disabled"}` without a green live cell.
- **Prompt-length definition is unspecified** on the pricing page. The superset rule only over-attributes. If a Console invoice later shows cache reads excluded from the threshold, narrowing is a one-line change plus a regime note.
- **In-flight leader runs across the deploy.** A run suspended mid-loop resumes on the new code: memoized turns keep their recorded cost, later turns use 5.5 pricing and `effort: low`, and the replayed assistant content contains no Haiku 5.5 thinking blocks from before the deploy, so the history-editing check does not trigger. The `promptVersion` bump only affects new runs. No step return shape changes.
- **Tokenizer inflation** (about 30%) moves token-denominated budgets: re-check `max_tokens` on every small-budget route (Phase 0 covers 200, 256, 1) and `MAX_SUMMARIZE_BODY_BYTES` interplay (byte cap unchanged; token count rises).
- **Do not "fix" #6945 here.** Rounding up without fixing the cents-times-tokens product trips caps.
- **Comment hygiene in `model-tiers.ts`**: no `/*` inside a `//` comment (it blinds the guards that strip comments).
- **Plan fields that fail `deepen-plan` if left empty:** `## User-Brand Impact` and `## Observability` are filled; keep `discoverability_test.command` first token on the probe allowlist (`bash`).
- **Detector hygiene:** after editing `AUTOFIX_PAIRS`, re-run `--detect` and assert the file count moved from the baseline (1 stale file today); a zero exit alone is not evidence the new pairs are live.
- **Dated model-launch learnings recur:** resolve ids, prices and pins from the official page or `gh api` in-pass, never from memory.
