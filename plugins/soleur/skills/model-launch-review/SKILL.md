---
name: model-launch-review
description: "This skill should be used when auditing the recurring per-Anthropic-model-release checklist (model IDs, claude-code-action pin freshness, pricing drift, tier-map re-evaluation): it auto-fixes stale model-ID swaps into a CI-gated PR and flags the rest."
---

# Model-launch review

`model-launch-review` runs the recurring per-Anthropic-model-release checklist. Each release
(Opus 4.6 → 4.7 → 4.8 → Fable 5 → Fable 5.1) recurs the same five-item audit. This skill **audits** all
five, **auto-fixes** the one mechanical-bulk item (stale model-ID swaps) into a **CI-gated PR**
under operator identity, and **flags** the rest for human sign-off. ADR-053 names this skill as
the per-release re-pin trigger.

## When to invoke

- After a new Anthropic model ships (Opus/Sonnet/Haiku/Fable family bump).
- When a dormant deferral's **date trigger** fires (e.g. #6942's 2026-09-01 pricing re-eval). The
  `[3]` dormant-work query exists to surface these; a trigger firing is not the same as the
  deferral's stated assumption holding — re-read the live source before acting on either.
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

   **`[2b]` measures `node_modules`, which is NOT the pin.** The check greps the installed
   tree because the model table ships in the platform binary
   (`@anthropic-ai/claude-code-linux-x64`) — the `@anthropic-ai/claude-code` npm tarball is a
   ~23 kB launcher stub with no model ids in it, so packing that tarball to "check the pin"
   returns ABSENT for *every* id including known-good ones. A stale `node_modules` therefore
   reports DRIFT against ids the pin knows perfectly well (2026-09-03: node_modules held
   2.1.142 while package.json pinned 2.1.219, and `[2b]` reported `claude-opus-5` and
   `claude-sonnet-5` ABSENT — both are present in 2.1.219). The script now prints both
   versions and refuses to describe a mismatch as a measurement of the pin; to actually test
   a candidate version, unpack `@anthropic-ai/claude-code-linux-x64@<version>` and grep that
   — **outside the repo**, e.g. in `$(mktemp -d)`. `npm pack` extracts to `./package/`, which no
   exclusion covers; unpacking under `$ROOT` puts a compiled blob full of model ids inside the
   auto-fix surface. Selection now skips binaries (`grep -I`), so `--fix` will not byte-patch it,
   but the tarball still has no business in the tree.

   Probe the PLATFORM package, never the `@anthropic-ai` scope: `claude-agent-sdk` and
   `claude-agent-sdk-linux-x64` both carry `claude-sonnet-5`, so a scope-wide grep answers
   "present" from the agent SDK while `claude-code` lacks the id entirely.

   **The 3-day release-age floor can make the required bump un-shippable.** If the only
   versions carrying the new id are <3 days old, `apps/web-platform/.npmrc`'s
   `min-release-age=3` (#1174) rejects them with `ETARGET … with a date before <date>`, and
   `--min-release-age=0` does not rescue it: CI's `lockfile-sync` job re-runs
   `npm install --package-lock-only` *without* the override, so the PR is red no matter what
   the local regen produced. Either wait for the version to age past the floor, or land the
   bump in its own PR — do not weaken the floor to get a launch sweep green.

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
- **Selection and rewriting must share ONE boundary — and the asymmetry was already live before
  anyone noticed it.** The `--fix` sed has been boundary-anchored since the script was created;
  selection was a bare alternation. Measured on `origin/main`: a config file carrying the DATED
  variant `claude-opus-4-7-20260101` reports `--detect` rc=10, `--fix` prints `fixed:` while
  changing nothing (the sed's boundary correctly declines), and `--detect` re-flags it forever —
  a permanently-red drift cron auto-filing issues it cannot fix, with no fable involved. So the
  invariant is the general one, and dated ids were its standing violation.
  `claude-fable-5` → `claude-fable-5-1` is what made it *unavoidable*: it is the first pair whose
  stale id is a strict PREFIX of its own target, so the mismatch fires on the id that is CURRENT
  rather than only on a longer variant nobody had written yet. `assert_single_hop` catches
  neither shape (the target is not itself a source id). Both halves now derive from `ID_BOUNDARY`
  in `audit-models.sh`; a bare alternation in either re-opens it. Pinned by
  `model-launch-review.test.ts` — one test derives the case from the live pair table, a second
  synthesizes a prefix pair so the coverage survives a launch where the live table has none.
- **A dormant deferral's stated assumption can expire along with its trigger.** #6942 pinned
  the sonnet pricing row to the *scheduled* post-intro $3/$15 so it would become correct on
  2026-09-01 with no second edit; Anthropic then cancelled that increase. Re-read the live
  source when the trigger fires — the deferral records what was true when it was written.
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
- **Run the repo's deterministic lints after each guard-shaped commit, BEFORE any agent panel —
  and audit a mutation battery's AXES, not its count.** Their yields are disjoint and the lints
  are orders of magnitude cheaper. Measured on #7774: `lint-shell-capture-exit` (a baseline-gated
  lint outside the panel) found a real defect in code written an hour earlier and was also the
  cause of the `test-scripts` CI failure, while a self-run battery that mutated ONE axis
  (selection anchoring) reported the new test load-bearing and missed **nine survivors across
  five axes it never touched** — fixture direction (dropping `|$` from `ID_BOUNDARY` made
  `--detect` report `model-drift: none`, exit 0, on real drift), the `--fix` sed's anchoring
  (three mutants each corrupting real source), dispatch (no assertion floor), fixture
  cardinality, and the whole `[2b]` block. N mutations of one shape is one mutation. Beware the
  lint's own remediation menu too: `lint-shell-capture-exit` accepts `x=$(cmd) || true`, which in
  `collect_config_hits` would flatten a load-bearing rc and re-open the #5100
  scan-failed-vs-clean conflation — use `if out=$(cmd); then … else rc=$?; fi`. See
  [2026-09-03-every-check-i-shipped-was-narrower-than-the-name-it-carried.md](../../../../knowledge-base/project/learnings/2026-09-03-every-check-i-shipped-was-narrower-than-the-name-it-carried.md).
