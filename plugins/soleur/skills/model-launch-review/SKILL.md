---
name: model-launch-review
description: "This skill should be used when auditing the recurring per-Anthropic-model-release checklist (model IDs, claude-code-action pin freshness, pricing drift, tier-map re-evaluation): it auto-fixes stale model-ID swaps into a CI-gated PR and flags the rest."
---

# Model-launch review

`model-launch-review` runs the recurring per-Anthropic-model-release checklist. Each release
(Opus 4.6 → 4.7 → 4.8 → Fable 5) recurs the same five-item audit. This skill **audits** all
five, **auto-fixes** the one mechanical-bulk item (stale model-ID swaps) into a **CI-gated PR**
under operator identity, and **flags** the rest for human sign-off. ADR-053 names this skill as
the per-release re-pin trigger.

## When to invoke

- After a new Anthropic model ships (Opus/Sonnet/Haiku/Fable family bump).
- When the `model-drift` issue filed by `rule-audit.yml`'s detection step appears.
- Before relying on a model ID or pricing assumption that may have drifted.

## Precondition (CI-gated PR property)

The PR must be created under **interactive operator `gh` auth** — never `GITHUB_TOKEN`/a bot
token. A bot-token PR does not trigger CI or CLA checks, defeating the "CI-gated" guarantee.
Run this skill interactively. Headless/cron contexts must file an **issue** (the detection
step), not a PR.

## Checklist (5 items) — auto-fix-vs-flag matrix

| # | Item | Disposition | Surface |
|---|------|-------------|---------|
| 1 | **Model-ID swaps** | **AUTO-FIX** | config-class files (server SDK call sites, Inngest `cron-*.ts`, `leader-prompts/constants.ts`, workflow `--model`, skill reference docs) — never test fixtures, archives, `knowledge-base/**`, or community digests |
| 2 | **claude-code-action pin freshness** | flag-only | `.github/workflows/*.yml` pins; auto-bump ONLY when coupled to a `--model` swap in the same workflow (#2540 invariant) |
| 3 | **Thinking-API shape** | flag-only (no-op v1) | carried by the claude-code-action pin's embedded SDK; no `thinking`/`output_config` params in config today |
| 4 | **Pricing-table drift** | flag-only | `agent-on-spawn-requested.ts` `MODEL_PRICING` (billing constant — never auto-edit); compare vs the `claude-api` source-of-truth |
| 5 | **Tier-map re-evaluation** | flag-only | cron model literals + ADR-053 / `plugins/soleur/AGENTS.md` policy vs new pricing; `workflow-model-pins.test.ts` `PIN_ALLOWLIST` is a don't-mutate invariant; also run `gh issue list --state open -L 200 --search "deferred model OR pricing"` for dormant work |

Only item 1 is auto-applied. Items 2–5 are reported in the PR body for human sign-off.

## How to run

1. **Audit** — see every finding (no silent green; all 5 checks always enumerated):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/model-launch-review/scripts/audit-models.sh
   ```

2. **Resolve the current landscape from authoritative sources** — never memory. Read the
   `claude-api` skill model table + the official Anthropic models docs. If a new model
   shipped in an existing tier (the next Sonnet/Opus/etc.), add a
   `"<superseded-id>=<current-id>"` entry to the `AUTOFIX_PAIRS` array in `audit-models.sh`
   (each stale id maps to its OWN same-tier target, so tiers coexist).

3. **Auto-fix** model-ID swaps (mechanical; allowlist + deletion guard; never `git add -A`):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/model-launch-review/scripts/audit-models.sh --fix
   ```

   Then run the suite — config ID swaps red the coupled test fixtures; update them in the
   same PR so CI stays green.

4. **Pin freshness** (flag): resolve the action tip and each pinned SHA's date —

   ```bash
   gh api repos/anthropics/claude-code-action/releases --jq '.[0] | "\(.tag_name) \(.published_at)"'
   gh api repos/anthropics/claude-code-action/git/commits/<PIN-SHA> --jq '.committer.date'
   ```

   Bump a pin only when a `--model` swap lands in the same workflow (#2540).

5. **Open a CI-gated PR** under operator identity (`worktree-manager.sh create` + `gh pr create`).
   The PR body lists the model-ID diff plus a **flag section** (pin freshness, pricing drift,
   tier-map judgment, dormant deferred issues). Use `Ref #5106` for the registry-centralization
   follow-up (deliberate split — do not fold it in).

## Detection (dormancy fix)

`rule-audit.yml` runs `audit-models.sh --detect` on its schedule. On drift (exit 10) it
files/updates **one** idempotent `model-drift` issue, closing the gap where #3791's "pricing
change" trigger never fired when Fable 5 shipped. The cron files an issue, never a PR.

## Sharp edges

- Resolve every model ID / pin SHA / release tag via `gh api` or official docs in-pass — never
  from memory (2026-04-18 / 2026-02-22 learnings; SHA-from-memory errors recur).
- Inventory by independent grep, not by a checklist's file list (inventories undercount).
- **When the launch migration bumps the Anthropic SDK toolchain in
  `apps/web-platform/package.json` (`@anthropic-ai/claude-code`,
  `@anthropic-ai/claude-agent-sdk`, `@anthropic-ai/sdk`), regenerate BOTH
  lockfiles — `package-lock.json` AND `bun.lock` — in the same PR.** The new
  releases are <3 days old, so a plain `bun install` is blocked by
  `bunfig.toml`'s `minimumReleaseAge = 259200` (#1174) and silently leaves
  `bun.lock` stale; every CI job running `bun install --frozen-lockfile` then
  fails at the install step. Regenerate with
  `cd apps/web-platform && bun install --lockfile-only --minimum-release-age=0`,
  then prove CI-parity with `bun install --frozen-lockfile` (no override →
  "no changes"). CI's `lockfile-sync` job covers only `package-lock.json`, not
  `bun.lock`. See
  [2026-07-01-bun-lock-minimum-release-age-blocks-sdk-toolchain-bump.md](../../../../knowledge-base/project/learnings/best-practices/2026-07-01-bun-lock-minimum-release-age-blocks-sdk-toolchain-bump.md).
- Pricing is a billing constant — flag, never auto-edit; the opus `MODEL_PRICING` row is
  deferred to #5106 (do not fabricate it).
- When #5106 lands its `model-tiers.ts` registry, the model-ID grep target collapses to that
  registry — narrow `audit-models.sh`'s scan accordingly.
