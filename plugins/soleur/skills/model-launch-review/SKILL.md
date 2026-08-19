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

## Checklist (6 items) — auto-fix-vs-flag matrix

| # | Item | Disposition | Surface |
|---|------|-------------|---------|
| 1 | **Model-ID swaps** | **AUTO-FIX** | config-class files (server SDK call sites, Inngest `cron-*.ts`, `leader-prompts/constants.ts`, workflow `--model`, skill reference docs) — never test fixtures, archives, `knowledge-base/**`, or community digests |
| 2 | **claude-code-action pin freshness** | flag-only | `.github/workflows/*.yml` pins; auto-bump ONLY when coupled to a `--model` swap in the same workflow (#2540 invariant) |
| 2b | **Pinned `claude-code` CLI knows the new model** | flag-only (**blocks the swap**) | `apps/web-platform/package.json` + `Dockerfile`. The CLI carries a BUNDLED per-model table; an absent ID is treated as a garbage ID and silently gets **half** the `max_tokens` (measured 64000 → 32000, #6934). Invisible to the ID sweep, `tsc`, and the suite — argv is well-formed and the run succeeds |
| 3 | **Thinking-API shape** | flag-only | Config sets no `thinking`/`output_config`, but the **CLI injects both itself** off its bundled table (measured: `thinking:{type:"adaptive"}`, `effort:"high"`). So "no params in config" is NOT "defaults apply" — item 2b is what actually moves this |
| 4 | **Pricing-table drift** | flag-only | `agent-on-spawn-requested.ts` `MODEL_PRICING` (billing constant — never auto-edit); compare vs the `claude-api` source-of-truth |
| 5 | **Tier-map re-evaluation** | flag-only | cron model literals + ADR-053 / `plugins/soleur/AGENTS.md` policy vs new pricing; `workflow-model-pins.test.ts` `PIN_ALLOWLIST` is a don't-mutate invariant; also run `gh issue list --state open -L 200 --search "deferred model OR pricing"` for dormant work |

Only item 1 is auto-applied. Items 2–5 are reported in the PR body for human sign-off.

## How to run

1. **Audit** — see every finding (no silent green; all 5 checks always enumerated):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/model-launch-review/scripts/audit-models.sh
   ```

2. **Resolve the current landscape from authoritative sources** — never memory. Read the
   `claude-api` skill model table plus the official docs (the `claude-api` skill is bundled,
   not vendored, so cite the URLs directly — models:
   `https://platform.claude.com/docs/en/about-claude/models/overview.md`, pricing:
   `https://platform.claude.com/docs/en/about-claude/pricing.md`). If a new model shipped in
   an existing tier, do BOTH:
   - **add** a `"<superseded-id>=<current-id>"` entry to `AUTOFIX_PAIRS` in `audit-models.sh`, and
   - **retarget** every existing same-tier pair's RHS to the new current id.

   The second step is not optional. `--fix` applies pairs sequentially, so a CHAINED map
   (`4-7=4-8` left in place alongside `4-8=5`) is order-dependent and lands files on an
   intermediate id, which `--detect` then re-flags forever — a permanently-red drift cron
   auto-filing issues it cannot fix. `assert_single_hop` enforces this (exit 78) and
   `model-launch-review.test.ts` pins it, so a chained table fails fast rather than silently.

   Then verify item 2b: the new ID must appear in the **pinned** `@anthropic-ai/claude-code`
   bundle (`[2b]` in the audit output). If it reports DRIFT, bump the pin in
   `apps/web-platform/package.json` AND the `Dockerfile` global, regenerate
   `package-lock.json` (see the release-age sharp edge below), and re-run. Grep the bundle with `grep -a`
   — the linux-x64 CLI is a compiled binary and a text-mode grep reports zero hits for
   EVERY id, a null result that reads exactly like a real one.

3. **Auto-fix** model-ID swaps (mechanical; allowlist + deletion guard; never `git add -A`):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/model-launch-review/scripts/audit-models.sh --fix
   ```

   Then run the suite — config ID swaps red the coupled test fixtures; update them in the
   same PR so CI stays green.

4. **Pin freshness** (flag): resolve the action tip and each pinned SHA's date —

   ```bash
   gh api repos/anthropics/claude-code-action/releases --jq '.[0] | "\(.tag_name) \(.published_at)"'
   # TODAY's pins are ANNOTATED TAG objects: git/commits/<SHA> returns 404 and
   # commits/<SHA> returns 422, so git/tags is the resolver (the git/commits form
   # printed here until 2026-07-24 never worked). This is a property of how that repo
   # cuts releases, NOT of pinning in general — a pin produced by pin-github-action or
   # Dependabot is a plain COMMIT sha, where git/tags 404s instead. Try both; the 404
   # is the discriminator. `.tagger.date` is the TAG date (correct for freshness), not
   # the underlying commit's date — do not "correct" it to the latter.
   gh api repos/anthropics/claude-code-action/git/tags/<PIN-SHA> --jq '"\(.tag) \(.tagger.date)"' \
     || gh api repos/anthropics/claude-code-action/commits/<PIN-SHA> --jq '.commit.committer.date'
   # → v1.0.161 2026-06-30T17:58:29Z
   ```

   `audit-models.sh` now computes this itself (`[2]` in the audit output) and prints an
   explicit `UNKNOWN` when `gh` is missing or unauthenticated — an unreachable API is
   never a freshness pass.

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
  `@anthropic-ai/claude-agent-sdk`, `@anthropic-ai/sdk`), regenerate
  `package-lock.json` in the same PR.** Since ADR-191 there is one lockfile per
  directory — do NOT recreate `bun.lock`.

  The release-age floor still applies and still bites here: the new releases are
  <3 days old and `apps/web-platform/.npmrc` sets `min-release-age=3`, so
  regenerate with an explicit override:
  `cd apps/web-platform && npx --yes npm@11 install --package-lock-only --min-release-age=0`.
  CI's `lockfile-sync` job now covers this directory AND the repo root. Note the
  repo ROOT has no `.npmrc` precisely so that this skill's own
  `npm install -g "@anthropic-ai/claude-code@${CLI_VERSION}"` — an exact pin to a
  same-day release — is not blocked by the floor. See
  [2026-07-01-bun-lock-minimum-release-age-blocks-sdk-toolchain-bump.md](../../../../knowledge-base/project/learnings/best-practices/2026-07-01-bun-lock-minimum-release-age-blocks-sdk-toolchain-bump.md).
- Pricing is a billing constant — flag, never auto-edit; the opus `MODEL_PRICING` row is
  deferred to #5106 (do not fabricate it).
- When #5106 lands its `model-tiers.ts` registry, the model-ID grep target collapses to that
  registry — narrow `audit-models.sh`'s scan accordingly.
