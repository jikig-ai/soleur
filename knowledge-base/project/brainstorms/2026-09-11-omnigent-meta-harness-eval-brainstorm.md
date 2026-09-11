---
date: 2026-09-11
topic: omnigent-meta-harness-eval
status: decided
decision: watch-only
lane: cross-domain
brand_survival_threshold: single-user incident
domains_assessed: [Product, Legal, Engineering, Marketing]
ci_home: knowledge-base/product/competitive-intelligence.md (Tier 4 + New Entrants)
related_adrs: [ADR-110-harness-semantic-model-tier-map]
source: https://github.com/omnigent-ai/omnigent
snapshot_sha: be5cae72d9a96ee2cd8ddf6bb6fb0c306f80387a
snapshot_stars: 9844
github_issue: 8062
---

# Brainstorm: Should Soleur use Omnigent, and does the plugin fit?

## User-Brand Impact

- **Artifact:** Soleur plugin + harness adapter (`plugins/soleur/lib/harness.ts` union `claude | grok | unknown`)
- **Vector:** a third runtime that intercepts tool approval, `AskUserQuestion`, or SessionStart can skip worktree/`AGENTS.md` gates, or default-on vendor telemetry can leave with session context
- **Threshold:** `single-user incident` (still applies to this docs-only write: a false "plugin-compatible" line in CI is treated as ground truth by SEO/sales)

Tagged user-brand-critical (auto, per #5175). CPO + CLO + CTO spawned with CMO (external-product default).

## What We're Building

A **watch-only** competitive-intelligence record. Not a third harness, not a plugin port, not a Concierge runtime, not an operator dogfood.

Operator (`/go` analyze Omnigent) confirmed two forks:

1. **Job:** watch-only (rejected dogfood probe, plugin port, Concierge substrate).
2. **Seat:** Tier 4 overlap-matrix row + New Entrants pointer (rejected Tier 3-next-to-Multica and Tier 5-Openship-only).

No `spec.md`. Openship 2026-07-26 already established that a declined adoption does not get a build spec. The CI row *is* the artifact.

## Why This Approach

Omnigent is an Apache-2.0 **alpha** Python meta-harness (~9.8k stars on 2026-09-11, HEAD `be5cae72d9a96ee2cd8ddf6bb6fb0c306f80387a`). It wraps Claude Code, Codex, Cursor, OpenCode, Hermes, Pi, Grok Build (ACP), and Devin (ACP). YAML agents, policies, bwrap/seatbelt, web/desktop/phone, telemetry **on by default** from v0.6.0 ([Usage Telemetry](https://omnigent.ai/docs/deploy/telemetry)).

It is the same *class* as Multica's 14-provider daemon (run existing CLIs) and CrewAI's DIY substrate (productized). It is **not** Soleur's class (8-domain CaaS). CI already recorded **do not adopt a 14-provider runtime** on the Multica row (2026-07-04). ADR-110 maps semantic model tiers across **Claude + Grok only**. `git grep -i omnigent` in this worktree was empty at eval time.

Approaches considered:

| Approach | Verdict |
|---|---|
| Third `Harness` union member / YAML port of the plugin | Rejected. Category error: Omnigent is a supervisor over Claude/Grok, not a Skill/Task/slash surface. |
| Concierge runtime | Rejected. Same Multica door. |
| Operator dogfood (`omnigent claude` + Soleur installed) | Rejected this session. Residual: Claude-native hooks intercept `AskUserQuestion` and rotate SessionStart. |
| Watch-only, Tier 3 next to Paperclip/Multica | Rejected. CMO: Tier 3 is the "runs your company" shelf; seating a CLI switchboard there *creates* the substitution we refuse. |
| Watch-only, Tier 5 like Openship | Rejected. Under-weights a productized meta-harness that already has a Grok ACP row. |
| **Watch-only, Tier 4 + New Entrants** | **Chosen.** Full row so it is not a parking lot; not Tier 3 so we do not invite comparison pages. |

## Plugin fit (the second question)

**The Soleur plugin does not fit Omnigent as a first-class plugin.** Product/runtime observation, not a BUSL prohibition (CLO: Additional Use Grant bars competing *hosted* service, not a user loading the plugin in another local harness).

Verified from Omnigent source (not README marketing):

- **No marketplace / no `plugin.json` of its own.** `omnigent/inner/bundle_skills.py` writes a stub `.claude-plugin/plugin.json` (`name` + `description`) and passes `--plugin-dir <tmp-bundle>` so a YAML agent's `skills/` show up in Claude.
- **`omnigent claude` with no bundle** uses host `~/.claude` — an already-installed Soleur plugin *can* piggyback on the inner Claude CLI. Omnigent then injects its own hooks (permission long-poll, `AskUserQuestion` intercept, SessionStart rotation, `route-turn`). That collides with Soleur SessionStart (worktree lease, AGENTS.md, `.mcp.json`).
- **Grok** is one ACP catalog row in `omnigent/acp_cli_harnesses.py`: binary `grok`, args `("agent", "stdio")`, aliases `grok-build`. `--model` refused. `XAI_API_KEY` is not in the host-to-runner allowlist; auth is `grok login --device-auth` on disk. Plugin load is whatever Grok ACP mode does — unproven. Not a third Soleur harness.
- **YAML `claude-sdk` / `claude-native` agents** do not load the Soleur marketplace plugin. Skills that say "invoke via Skill tool / spawn_subagent" would be dead letters.
- Soleur manifest: `plugins/soleur/.claude-plugin/plugin.json` — `engines.claude-code >= 2.1.139`, BUSL-1.1, four MCP servers. Grok load path is `.grok/config.toml` + symlink `.grok/plugins/soleur` → `../../plugins/soleur`, **not** a `.grok-plugin` marketplace. Catalog snapshot this worktree: 96 skill dirs / 95 `SKILL.md` / 67 canonical agents / 3 commands.

Do **not** write "Soleur runs on Omnigent", "plugin compatible with Omnigent", or "we support Omnigent" on any public surface.

## Key Decisions

| Decision | Rationale |
|---|---|
| Watch-only; no `harness.ts` change | `Harness` is an invocation-surface discriminator. Omnigent has no third Skill/slash/Task API. Adding `"omnigent"` would steal Claude- or Grok-shaped processes. |
| Do not add `"omnigent"` to `detectHarness` | Inner `CLAUDECODE` / `GROK_*` already classify the wrapped process. |
| Seat in Tier 4 + New Entrants | Productized DIY/control-plane substrate (CrewAI class), not CaaS (Tier 3), not a tiny DIY adjacency (Tier 5). |
| No `spec.md`, no battlecard, no comparison page, no specialist cascade | Openship decline template + CPO: CI is ground truth; a public "Soleur vs Omnigent" page would *create* a plugin-fit claim. |
| Plugin-fit = false as first-class; piggyback-only on inner Claude/Grok CLIs | Stub `--plugin-dir` ≠ marketplace load. BUSL is not why. |
| Apache-2.0 citing is paraphrase + URL; no SKILL.md/YAML/Python copy | CLO GO-with-guardrails. Multica G1–G5 (clean-room vs "Other" license) do **not** apply. Nominative "Omnigent" is required identification. |
| Telemetry: their claim, not ours; ingest processor unnamed | Default-on from v0.6.0; opt-out `OMNIGENT_ANALYTICS=0` / `DO_NOT_TRACK=1` / `telemetry: false`. Writing the row creates **no** processing relationship. Any later install re-opens CLO + gdpr-gate + Vendor DPA. |
| No `/soleur:gdpr-gate` on this docs write | No PII schema, auth route, or vendor env in *our* runtime. |
| Re-open only on explicit triggers (stars do not count) | See below. |

### Re-open triggers (any one re-opens architecture, not a drive-by union edit)

1. Omnigent ships a real plugin loader that honors `engines.claude-code` **and** does not intercept SessionStart / `AskUserQuestion` in a way that skips Soleur gates, **and** either (a) same-ICP CaaS with business-domain agents or (b) named founder demand to run Soleur under it.
2. Grok ACP path grows hook injection comparable to Claude-native.
3. A distinct Skill/Task-equivalent API of Omnigent's own (then it would be a third *surface*, still a product decision).
4. Concierge proposes `omnigent` as a hosted runtime.
5. Their public copy ships company templates, business-domain packs, or "run your company" (CMO re-tier toward Paperclip-class narrative risk).

## Open Questions

- None blocking. CLO's verbatim-quote cap is encoded as: paraphrase; pre-merge grep the CI diff for their README/source. Ingest processor stays "unidentified — blocker for dogfood."

## Next Steps

CI row + New Entrants pointer land in this same PR. No `/plan`. No product code.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** GO watch-only. Founder outcome of writing: next session stops instead of re-opening port/third-harness. Over-rotate is the live risk, not a missed product window. Brand-survival remains `single-user incident` for the docs write. No cascade.

### Legal

**Summary:** GO-with-guardrails. Public Apache-2.0 facts + nominative identification; no vendoring; no Art. 28 from a markdown row. BUSL is not a bar on local load. Disclose alpha + default-on telemetry as *their* docs. Re-open CLO if scope grows past watch-only.

### Engineering

**Summary:** Watch-only is YAGNI vs the `detectHarness` trap. Residual runtime risk is none. Category-error PR ("just add the union member") is the process risk the row exists to block. Latent hook collision is do-not-run, not a patch.

### Marketing

**Summary:** Non-ICP peer (Multica/CrewAI), not a Paperclip narrative substitute. Forbidden public language listed above. One sentence: Omnigent is a switchboard for coding tools an engineering team already runs; Soleur is the company a solo founder still has to operate.

Operations, Sales, Finance, Support: not spawned (no vendor spend, pipeline, budget, or support-workflow change).

## Capability Gaps

None for this watch-only call. Evidence: `git grep -i omnigent` empty; `export type Harness = "claude" | "grok" | "unknown"` in `plugins/soleur/lib/harness.ts`; existing Multica "do not adopt 14-provider runtime" takeaway; Openship watch-entry template already in Tier 5.

## Productize Candidate

None. Recurring competitive evals already have `soleur:competitive-analysis` / `peer-plugin-audit`. Omnigent is a meta-harness, not a skill library — `peer-plugin-audit` correctly refuses a skills overlap matrix.

## Session Errors

None this session. Premise (Omnigent as possible third harness / plugin host) was falsified against source before leaders spawned; operator then locked watch-only + Tier 4 seat.
