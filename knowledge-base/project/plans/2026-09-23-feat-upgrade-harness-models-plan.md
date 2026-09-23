---
title: "feat: move harness model pins to this week's releases (Grok 4.7 now; Opus 5.5 once the CLI pin clears the floor; Codex has no pin)"
type: feat
date: 2026-09-23
slug: feat-upgrade-harness-models
branch: feat-one-shot-upgrade-harness-models
lane: cross-domain
related: 7773
---

# feat: move harness model pins to this week's releases

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No spec.md exists for this branch.)

## Enhancement Summary

**Deepened on:** 2026-09-23. **Sections enhanced:** 6 (Proposed Solution A3/A4/A5, Acceptance Criteria, Domain Review, Technical Considerations).

**Agents used:**

- a verify-the-negative pass (standard tier);
- `soleur:engineering:research:best-practices-researcher` (live vendor re-check);
- `soleur:engineering:research:git-history-analyzer`;
- `soleur:engineering:review:architecture-strategist`.

**Halt gates (all passed):**

- 4.6: User-Brand Impact present, threshold `aggregate pattern`.
- 4.7: all 5 Observability fields present. The probe verb `grep` passes `probe-verb-gate.sh` rc=0, and the command prints no suite-shaped output and no prose.
- 4.8: no PAT shapes.
- 4.9, 4.10 and 4.11: not triggered (no UI, no store or connection, no new guard).
- Every cited issue and rule ID was resolved live via `gh` and `AGENTS.md`.

### Key Improvements

1. **The model-launch-review SKILL.md stays consistent with itself.**
   - The intro's "five-item audit" wording is updated.
   - The step-1 wording names the groups `audit-models.sh` actually prints (`[1]`, `[2]`, `[2b]`, `[3]`).
2. **ADR-110 addendum records two points.**
   - Decision item 6 is now met by an agent-run row.
   - On Grok, `cheap` vs `standard` saves only on cached input. This is recorded as a consequence, not a decision change.
3. **The #7773 retitle includes "deferred"**, so the skill's `[3]` dormant-work search surfaces Phase B.
4. **The AC suite list adds the harness-parity suites**, which scan the SKILL.md prose that A4 edits.

### New Considerations Discovered

- **Claude Code's `opus` alias already points at Opus 5.5.** Claude Code 2.1.278 (2026-09-19) made Opus the default model, and 2.1.280 (2026-09-22) points the `opus` alias at `claude-opus-5-5` (<https://code.claude.com/docs/en/changelog>).
  - `TIER_MAPS.claude` uses aliases, so every agent or workflow tier pinned `strong` → `opus` already runs Opus 5.5 on a user's own updated CLI, with no repo change.
  - Only the server-side `AUDIT_MODEL`, which runs on the repo's *pinned* CLI 2.1.219, needs Phase B.
- **Nothing else shipped this week.**
  - Anthropic: Sonnet 5.5 and Haiku 5.5 are announced for "coming weeks", so they are out of scope.
  - OpenAI: there is no `-codex` variant of GPT-6 Sol. `gpt-6-sol` is the Codex default.
  - xAI: nothing else (<https://docs.x.ai/developers/pricing>).
- **The verify-the-negative pass confirmed all six negative claims**, with file:line evidence (Codex no-pin at `codex-app-server-protocol.ts:160-165`, and so on). No Files-to-Edit additions.
- **No C4 impact** (architecture review grepped `model.c4`, `views.c4`, `spec.c4` and `c4-model.md`). The docs pages, README and `grok-onboarding.md` name no Grok SKU.

## Overview

The request is to move Soleur's three harnesses (Claude Code, Codex, Grok Build) to the models
each vendor shipped in the week of 2026-09-21. Every model ID below was checked on 2026-09-23
against vendor docs or a live CLI. None comes from memory.

| Vendor | Released this week | API / CLI id | Date | Soleur pins it? | Disposition |
|---|---|---|---|---|---|
| Anthropic | **Claude Opus 5.5** | `claude-opus-5-5` | 2026-09-22 | Yes: `AUDIT_MODEL` (Inngest audit crons, via `claude` CLI argv) + eval-harness + skill reference docs | **Phase B.** Blocked by checklist item 2b until the CLI version that knows the id clears the 3-day release-age floor (2026-09-25T15:44:39Z) |
| Anthropic | nothing else (Fable 5.1 shipped 2026-09-01; Sonnet 5 and Haiku 4.5 are unchanged) | — | — | — | none |
| xAI | **Grok 4.7** (+ `grok-4.7-build-fast`, Grok Build/Cursor only, 2x rate) | `grok-4.7` | 2026-09-21 | Yes: `TIER_MAPS.grok` + 7 inlined workflow fences | **Phase A (this PR)** |
| OpenAI | **GPT-6 Sol** and **GPT-6 Luna** (GPT-6 Astra shipped 2026-09-04, a different week) | `gpt-6-sol`, `gpt-6-luna` | 2026-09-22 | **No.** Codex inherits the session model: no `model` param in `apps/web-platform/server/codex-*.ts`, no `model =` in `.codex/config.toml`, and `plugins/soleur/codex/INSTRUCTIONS.md:51` says to inherit | **No code change.** Record the finding, and add a no-pin note to the launch checklist's "When to invoke" |

**Sources:**

- Anthropic: <https://platform.claude.com/docs/en/models/opus-5-5/overview> ("Released September 22, 2026", `claude-opus-5-5`, $4/$20, cache read $0.20, 5m write $5, 1h write $8) and <https://platform.claude.com/docs/en/about-claude/models/overview>.
- xAI: <https://docs.x.ai/developers/grok-4-7> and <https://docs.x.ai/developers/release-notes> (`grok-4.7`, 500k context, $2/$0.50/$6). Release date 2026-09-21 per <https://sqmagazine.co.uk/xai-launches-grok-4-7-coding-model/>. Checked live with `grok models` on CLI 1.0.40, which returned `grok-4.7 (default)`, `grok-4.7-build-fast`, `grok-4.6`, `grok-4.5`.
- OpenAI: <https://developers.openai.com/api/docs/models/gpt-6-sol> ($2/$0.20/$10), <https://developers.openai.com/api/docs/models/gpt-6-luna> ($0.10/$0.01/$0.50) and <https://learn.chatgpt.com/docs/models> ("GPT-6 Sol … primary recommendation for Codex"). Announcement dated 2026-09-22 per <https://9to5mac.com/2026/09/22/openai-upgrading-chatgpt-and-codex-with-two-more-gpt-6-models/>. The local Codex CLI 0.156.1 model cache (`~/.codex/models_cache.json`, fetched 2026-09-23) lists `gpt-6-astra`, `gpt-6-sol`, `gpt-6-luna`.

**Delivery shape:** two PRs, fixed by the release-age floor, not by choice.

- **Phase A (this PR, shipped by this one-shot run):**
  - Grok tier-map bump.
  - Model-launch checklist gains a Grok row and a Codex no-pin note.
  - Issue #7773 is retargeted to carry Phase B.
- **Phase B (follow-up PR, not before 2026-09-25T15:44:39Z, tracked by #7773):**
  - `@anthropic-ai/claude-code` 2.1.219 → a version ≥ 2.1.280.
  - `AUDIT_MODEL` `claude-opus-5` → `claude-opus-5-5`.
  - `AUTOFIX_PAIRS` retarget.
  - eval-harness regen.
  - Everything else runs through `soleur:model-launch-review`.

`soleur:work` in this pipeline executes **Phase A only**.

## Research Reconciliation — Spec vs. Codebase

| Claim (task brief) | Reality (measured 2026-09-23) | Plan response |
|---|---|---|
| "Bump each harness's configured/pinned model IDs" | Codex has **no** pinned model anywhere in the repo. `resolveModelTier(_, "codex")` returns `inherit` by design (`harness-model-map.test.ts` "codex … inherits instead of throwing") | Codex needs no bump. Say so in the PR body, and add a one-sentence note to the checklist so the next launch does not look for a pin again |
| "Opus 5.5 `claude-opus-5-5` is a current id" | True at the API. The **pinned** CLI `@anthropic-ai/claude-code@2.1.219` does not carry it. Unpacked `claude-code-linux-x64`: **2.1.278 → 0 hits, 2.1.280 → 14 hits** (grep -a). 2.1.280 was published 2026-09-22T15:44:39Z; `apps/web-platform/.npmrc` `min-release-age=3` blocks it until 2026-09-25T15:44:39Z | Swapping the id now would pass an id the CLI does not know. Per #6934 the CLI then silently halves `max_tokens`, and Opus 5.5 rejects "thinking disabled". So the swap is Phase B, in its own PR (the SKILL.md sharp edge prescribes this: "land the bump in its own PR — do not weaken the floor") |
| ADR-110: "cheap maps to grok-4.5, the only non-default CLI model" | CLI 1.0.40 now lists three non-default slugs. The docs.x.ai catalog prices grok-4.5, 4.6 and 4.7 **identically** ($2 in / $6 out). grok-4.5 is only cheaper on cached input ($0.30 vs $0.50). `grok-4.7-build-fast` bills at 2x | Keep `cheap = grok-4.5` with a **new** rationale (lowest cached-input rate among CLI slugs; build-fast costs more; `grok-build-0.1` and `grok-4.3` are cheaper but are not CLI spawn slugs). Move standard/strong/advisor to `grok-4.7` |
| ADR-110 Decision item 6: "`model-launch-review` gains a Grok tier-table freshness check" | Never built: `grep -ci grok` over the skill returns 0 | Add one flag-only checklist row (prose, no new script logic) |
| Grok dogfood host "tracks" the model (`cloud-init-grok-dogfood.yml` `default = "grok-4.5"`) | This is the Phase 1 **measurement baseline** (`grok-gpu-bootstrap.sh:199` "Phase 1 baseline retained for dual-host comparison"). `hcloud_server.grok_dogfood.user_data` has **no** `ignore_changes`, so any edit replaces the live host (expenses.md: active, id 151628547) | Out of scope: a measurement config, not a harness pin. Editing it would destroy a live host (`hr-prod-host-config-change-immutable-redeploy`) |

## Research Insights

**Premise Validation.** The feature description cites no issue, PR or file by reference. The parent-supplied ID list (Fable 5.1 `claude-fable-5-1`, Opus 5.5 `claude-opus-5-5`, Sonnet 5 `claude-sonnet-5`, Haiku 4.5 `claude-haiku-4-5-20251001`) was checked against the live Anthropic models overview and holds. Of those, only Opus 5.5 is new this week (released 2026-09-22). The parent's premise that Codex has pinned IDs is **stale**: the repo pins none. Related open work: #7773 (CLI pin stuck at 2.1.219 since the Fable 5.1 launch, still OPEN) becomes the Phase B vehicle. #5106 (the model-tier registry) is CLOSED and already landed `model-tiers.ts`.

**Property List (Phase 0.6b):**

- P1: Soleur's Grok Build workflow tiers spawn xAI's newest flagship (`grok-4.7`) wherever the tier's role is "best model" (standard/strong/advisor).
- P2: Soleur's Opus-class operator crons (`AUDIT_MODEL`) run on Opus 5.5, and the CLI that executes them knows the id (no silent `max_tokens` halving).
- P3: Codex sessions run on OpenAI's newest Codex model.
- P4: The next vendor launch finds every surface that tracks a model (the checklist covers all three vendors).

**Cut List (Phase 0.6b):**

- `TIER_MAPS.codex` (a new pin mechanism) → P3 → already bought by Codex's session-model inheritance (`plugins/soleur/codex/INSTRUCTIONS.md:51`) plus OpenAI's server-side catalog. Authority grepped: `apps/web-platform/server/codex-*.ts` (zero `model` hits) and `.codex/config.toml`.
- A scripted Grok check in `audit-models.sh` → P4 → a flag-only checklist row buys it without a new guard.
- Dogfood cloud-init `default` bump → no property in the list (it is a measurement baseline, not a harness tier).

**Value measurement (0.6c):** not applicable. The justification is currency, not a cost saving. The Grok tier move is cost-neutral (identical $2/$6 list price). Opus 5.5 is cheaper than Opus 5 at $4/$20, but no saving is claimed as justification.

**Files (verified on this worktree):**

- `plugins/soleur/lib/harness-model-map.ts:42-48`: `TIER_MAPS.grok`.
- Workflow fences at `review.workflow.js:410`, `plan-review.workflow.js:316`, `deepen-plan.workflow.js:348`, `resolve-parallel.workflow.js:252`, `resolve-pr-parallel.workflow.js:236`, `resolve-todo-parallel.workflow.js:245`, `drain-labeled-backlog.workflow.js:271`.
- `plugins/soleur/test/harness-model-map.test.ts:63-72,130-143`.
- `apps/web-platform/server/inngest/model-tiers.ts:46`: `AUDIT_MODEL`, consumed by 6 `cron-*.ts` files.
- `plugins/soleur/skills/eval-harness/scripts/gen-models.sh`: generates `models.generated.json` from `AUDIT_MODEL`.
- `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh:46-53`: `AUTOFIX_PAIRS`.
- `apps/web-platform/package.json` / `Dockerfile:57`: claude-code 2.1.219.
- `apps/web-platform/.npmrc`: `min-release-age=3`.

**Audit baseline:** `audit-models.sh` on 2026-09-23 reported:

- `[1]` none (the pair table does not know Opus 5.5 yet).
- `[2]` pinned v1.0.161 vs tip v1.0.231.
- `[2b]` ok for `claude-opus-5`, `claude-sonnet-5` and `claude-haiku-4-5-20251001` @ 2.1.219.

**Applicable learnings:**

- `knowledge-base/project/learnings/2026-04-18-action-pin-sync-with-model-bump.md`: bump the action pin only with a coupled `--model` swap. Here there is none.
- `plugins/soleur/skills/model-launch-review/SKILL.md` §sharp edges: prefix pairs (fable 5→5-1), the release-age floor makes the bump un-shippable (land it in its own PR), and the `[2b]` measure must use `grep -a` on the platform package outside the repo.
- `knowledge-base/project/learnings/2026-05-27-npm-update-rewrites-lockfile-name-in-worktrees.md`: Phase B lockfile regen.
- ADR-110 (`knowledge-base/engineering/architecture/decisions/ADR-110-harness-semantic-model-tier-map.md`): the 7 fences stay byte-identical, and `grok-build-0.1` is not a CLI slug.
- ADR-053: aliases auto-retarget, so the Claude map and agents need no edit.

**CLI verification (#2566 gate):**

- `grok models` (Grok CLI 1.0.40, run 2026-09-23) printed `grok-4.7 (default)`, `grok-4.7-build-fast`, `grok-4.6`, `grok-4.5`.
- `codex --help` (codex-cli 0.156.1) prints `-m, --model <MODEL>`.
- `npm view @anthropic-ai/claude-code time --json` shows 2.1.280 at 2026-09-22T15:44:39.443Z.

## Open Code-Review Overlap

None. 75 open `code-review` issues were queried. None names `harness-model-map.ts`, its test, any of the 7 workflow files, ADR-110 or `model-launch-review/SKILL.md`.

## Problem Statement / Motivation

Two things decay in this repo whenever a vendor ships:

1. **Grok tier drift.** The Grok side is a hand-maintained table (`TIER_MAPS.grok`) plus 7
   byte-identical inlined copies. Nothing flags it on a Grok release (ADR-110 promised a check
   that was never built).
2. **Claude audit crons on the old model.** On the Claude side, `soleur:model-launch-review`
   exists and covers this. But the CLI pin has been stale since the Fable 5.1 launch
   (#7773, still open at 2.1.219), so every new Anthropic id hits the release-age floor.

## Proposed Solution

### Phase A: this PR (executed now)

**A0. Tests first (`cq-write-failing-tests-before`).** Edit
`plugins/soleur/test/harness-model-map.test.ts` so it expects the new Grok map:

- the test named `grok fixture map uses live CLI spawn slugs (grok models 1.0.29: grok-4.6, grok-4.5)`:
  - Rename it to `grok fixture map uses live CLI spawn slugs`, with no version (so the next launch does not need a rename).
  - Expect standard/strong/advisor `grok-4.7` and cheap `grok-4.5`.
  - Keep `expect(TIER_MAPS.grok.cheap).not.toBe("grok-build-0.1")`.
  - Rewrite the comment at lines 64-66 ("cheap is grok-4.5 — the only non-default slug") to the cached-input rationale, because that statement is false on CLI 1.0.40.
- `resolveAdvisorTier("grok")` / `resolveAdvisorFallback("grok")` → `grok-4.7`.
- `TIER_MAPS.grok.standard` → `grok-4.7`.

Run `bun test plugins/soleur/test/harness-model-map.test.ts` and confirm RED.

**A1. SSOT.** In `plugins/soleur/lib/harness-model-map.ts`:

- `TIER_MAPS.grok` becomes `{ cheap: "grok-4.5", standard: "grok-4.7", strong: "grok-4.7", advisor: "grok-4.7", inherit: "inherit" }`.
- Shorten the header provenance comment to three lines:
  - "Grok SKUs confirmed 2026-09-23 (docs.x.ai catalog + `grok models` on CLI 1.0.40) — evidence in the ADR-110 addendum 2026-09-23."
  - "cheap = grok-4.5: same $2/$6 list price as 4.7, lowest cached-input rate ($0.30) among CLI slugs; grok-4.7-build-fast bills 2x; grok-build-0.1 is an API SKU, not a CLI slug."
  - The full evidence lives in one place, the ADR addendum (per DHH review).

**A2. The 7 inlined fences.** Each file below carries the literal
`{ cheap: 'grok-4.5', standard: 'grok-4.6', strong: 'grok-4.6', advisor: 'grok-4.6', inherit: 'inherit' }`
inside `<!-- harness-model-map:start/end -->`. Swap only the three `grok-4.6` values:

- `plugins/soleur/skills/review/workflows/review.workflow.js`
- `plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js`
- `plugins/soleur/skills/deepen-plan/workflows/deepen-plan.workflow.js`
- `plugins/soleur/skills/resolve-parallel/workflows/resolve-parallel.workflow.js`
- `plugins/soleur/skills/resolve-todo-parallel/workflows/resolve-todo-parallel.workflow.js`
- `plugins/soleur/skills/resolve-pr-parallel/workflows/resolve-pr-parallel.workflow.js`
- `plugins/soleur/skills/drain-labeled-backlog/workflows/drain-labeled-backlog.workflow.js`

Use one exact-string replacement per file (the full `standard: 'grok-4.6', strong: 'grok-4.6', advisor: 'grok-4.6'` triple), not a regex over `grok-4.6`.

No extra greps are needed. The existing parity test (`harness-model-map.test.ts:156-185`) asserts that all 7 fences are byte-identical and contain every `TIER_MAPS.grok` value, so a missed fence reds CI.

**A3. ADR-110 refresh** (`knowledge-base/engineering/architecture/decisions/ADR-110-harness-semantic-model-tier-map.md`):

- Update the "Fixture tier map" table to `grok-4.7` for standard/strong/advisor (fallback `grok-4.7`).
- Line 39: replace the cheap-row note "(only non-default CLI spawn slug)", which is now false, with "(lowest cached-input rate among CLI slugs)".
- Line 35: change the heading "confirmed 2026-09-11 — docs.x.ai + `grok models` CLI 1.0.29" to 2026-09-23 / 1.0.40.
- Update the line saying "Do **not** pin `grok-build-0.1` … as of 1.0.29" to cite 1.0.40.
- Append `## Addendum — 2026-09-23 (Grok 4.7 launch)`. It must carry:
  - the live `grok models` output, the catalog prices and the server-fetched model list note;
  - **(a)** Decision item 6 ("`model-launch-review` gains a Grok tier-table freshness check") is now met by an agent-run checklist row, not a script;
  - **(b)** a recorded consequence: on Grok, `cheap` and `standard` now differ only on cached input ($0.30 vs $0.50), so Decision item 1's cost split saves almost nothing on this harness. This is recorded, not a decision change (architecture review P2).

The data changes; the decision does not. No new ADR.

**A4. Checklist rows** (`plugins/soleur/skills/model-launch-review/SKILL.md`, body only; the `description:` stays untouched, so the budget check is not triggered):

- Rename "Checklist (6 items)" to "(7 items)".
- Add row **6 — Grok tier-map freshness** (flag-only; the agent runs it, not `audit-models.sh`, because it needs a local `grok` CLI):
  - Compare the `grok models` output and <https://docs.x.ai/developers/models> against `TIER_MAPS.grok` in `plugins/soleur/lib/harness-model-map.ts`.
  - Fallback, one clause (CTO): if `cheap`'s slug has disappeared, move `cheap` to the oldest listed slug that is not `-build-fast`.
  - Cite ADR-110 Decision item 6.
- Codex gets **no** row (all three reviewers cut it: it would guard a pin nobody intends to add). Add one sentence to "When to invoke" instead: "Codex: Soleur pins no Codex model (it inherits the session model per `plugins/soleur/codex/INSTRUCTIONS.md`), so an OpenAI launch needs no bump." The AC below checks the no-pin claim at merge time.
- Update the "Only item 1 is auto-applied. Items 2–5 …" sentence to "Items 2–6".
- Change "all 5 checks always enumerated" (How to run, step 1) to name the groups the script actually prints: "`audit-models.sh` prints `[1]`, `[2]`, `[2b]`, `[3]` (items 1–5); row 6 is run by the agent". Without this, the no-silent-green claim is false.
- Lines 12-14 (intro), which say "recurs the same five-item audit … audits all five": make them say the audit covers the Anthropic items plus a Grok row run by the agent, and mention xAI releases. Otherwise the intro contradicts the table (architecture review P1).
- In "When to invoke", add "an xAI model launch (row 6)".

**A4b. Model Selection Policy prose.** `plugins/soleur/AGENTS.md:180` currently reads "a Haiku session still runs a `standard`-pinned step on Sonnet / grok-4.6". Rewrite it tier-generically so it cannot drift again: "…on the `standard` tier's SKU (Sonnet on Claude; see `TIER_MAPS.grok` on Grok)" (simplicity review). This is the only other live doc naming the standard-tier Grok SKU; `git grep -nI 'grok-4\.6'` outside plans/specs/archives returns just the files in A1–A3 plus this line. ADR-110's 2026-09-11 addendum (line 57) is a dated historical record and stays verbatim.

**A5. Retarget #7773 to carry Phase B** (`gh issue edit 7773`, done in the work phase, not at plan time):

- New title: `chore(model-launch): deferred Opus 5.5 — bump @anthropic-ai/claude-code to >=2.1.280 and AUDIT_MODEL to claude-opus-5-5 (not before 2026-09-25T15:44Z)`. "deferred" keeps it visible to the skill's `[3]` dormant-work search (`deferred model OR pricing`). Phase A leaves `AUTOFIX_PAIRS` untouched, so this issue is the only thing that brings Phase B back (architecture review P2).
- Append a comment that links this plan's `### Phase B` section. Do not paste the checklist into the comment: two copies would drift apart.
- The PR body carries `Ref #7773` (not `Closes`).

### Phase B: follow-up PR (not before 2026-09-25T15:44:39Z; tracked by #7773)

Run `soleur:model-launch-review` interactively under operator `gh` auth, then:

- **B0. Commit order in the one PR.**
  - **Commit 1:** CLI pin bump only (B1–B2), with `AUDIT_MODEL` unchanged. CI runs green on this commit.
  - **Commit 2:** the model swap (B3–B7).

  The scoped advisor suggested separate PRs, to isolate a CLI regression from the id swap. That is rejected: the only runtime evidence either way is a *weekly* audit-cron fire, so a split PR would need a week-long soak to prove anything. The swap is also meaningless without the bump. Commit-level separation keeps the regression revertable (`git revert <commit-2>`) without a soak.
- **B1. Choose the CLI version.** Pin **exactly 2.1.280** (measured: the first version carrying `claude-opus-5-5`; it clears the floor at 2026-09-25T15:44:39Z). Pick a newer ≥ 3-day-old version only if 2.1.280 fails the re-probe below. Pinning the oldest qualifying version keeps what was measured identical to what ships (advisor).
  - List versions: `npm view @anthropic-ai/claude-code time --json`.
  - Unpack `@anthropic-ai/claude-code-linux-x64@<v>` in `$(mktemp -d)` **outside the repo**.
  - `grep -raqE '<id>([^-0-9a-z]|$)'` must find `claude-opus-5-5`, `claude-fable-5-1`, `claude-sonnet-5` and `claude-haiku-4-5-20251001` (measured: 2.1.280 carries `claude-opus-5-5`).
- **B2. Bump the pin.**
  - Change `apps/web-platform/package.json` `@anthropic-ai/claude-code` and `apps/web-platform/Dockerfile` `npm install -g @anthropic-ai/claude-code@<v>` together (the file carries a KEEP IN SYNC comment).
  - `cd apps/web-platform && npx --yes npm@11 install --package-lock-only`. No `--min-release-age=0`: CI's `lockfile-sync` would reject it.
  - Check that the lockfile `"name"` did not become the worktree name (learning 2026-05-27).
- **B3. `audit-models.sh` `AUTOFIX_PAIRS`.**
  - Retarget `claude-opus-4-8`, `claude-opus-4-7` and `claude-opus-4-6` to `claude-opus-5-5`.
  - Add `"claude-opus-5=claude-opus-5-5"`.
  - This is a **prefix pair** (same shape as fable 5 → 5-1). `ID_BOUNDARY` handles it; `assert_single_hop` passes because `claude-opus-5-5` is not a source id.
  - The advisor's "terminal-target invariant" already exists: `assert_single_hop` exits 78 on a chained table, `model-launch-review.test.ts` pins it, and the prefix-pair test synthesizes a prefix pair. No new test is needed. Re-running `--fix` twice must be a no-op; check with `git diff --stat` after the second run.
- **B4. Tests.** In `plugins/soleur/test/model-launch-review.test.ts`:
  - `CURRENT_IDS`: `claude-opus-5` → `claude-opus-5-5`.
  - Every synthetic fixture that uses `claude-opus-5` as a *current* id is now a *source* id. Re-read each one (the `toContain("claude-opus-5")` after `--fix` passes vacuously by prefix; tighten it to the quoted `"claude-opus-5-5"`).
  - Run the whole file.
- **B5. Run the swap.** `audit-models.sh --fix` rewrites `apps/web-platform/server/inngest/model-tiers.ts:46`, the `cron-*-audit.ts` comments, `plugins/soleur/skills/agent-native-architecture/references/*.md` and `plugins/soleur/skills/dspy-ruby/references/providers.md`. Then fix by hand:
  - the `model-tiers.ts` header comment "AUDIT_MODEL (opus-5)";
  - the `mobile-patterns.md` price comment "~$5/1M input, $25/1M output" → "$4/$20";
  - ADR-053 line 89 `AUDIT_MODEL = claude-opus-5`.
- **B6. Coupled test.** `apps/web-platform/test/server/inngest/model-tiers.test.ts`: change `expect(AUDIT_MODEL).toBe("claude-opus-5")` to `"claude-opus-5-5"`, and update the test title. This suite runs on **vitest**, not bun: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/model-tiers.test.ts`.
- **B7. Regenerate eval-harness models.** Run `bash plugins/soleur/skills/eval-harness/scripts/gen-models.sh`, which regenerates `models.generated.json` from `AUDIT_MODEL`.
- **B8. Flag-only items.** Report the skill's items 2–5 as it prescribes. The one launch-specific fact to add: Opus 5.5 rejects forced `tool_choice` and cannot disable thinking. `git grep -n tool_choice apps/web-platform/server` must stay empty.
- **B9. Verify.**
  - `audit-models.sh --detect` exits 0.
  - `[2b]` prints `ok claude-opus-5-5 present in the pinned CLI bundle`.
  - The next scheduled audit cron checks in green on its Sentry monitor (`scheduled-legal-audit` / `scheduled-agent-native-audit`, `apps/web-platform/infra/sentry/cron-monitors.tf`).
  - The Phase B PR body carries `Closes #7773`.

## Files to Edit

Phase A (this PR):

- `plugins/soleur/lib/harness-model-map.ts`
- `plugins/soleur/test/harness-model-map.test.ts`
- `plugins/soleur/skills/review/workflows/review.workflow.js`
- `plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js`
- `plugins/soleur/skills/deepen-plan/workflows/deepen-plan.workflow.js`
- `plugins/soleur/skills/resolve-parallel/workflows/resolve-parallel.workflow.js`
- `plugins/soleur/skills/resolve-todo-parallel/workflows/resolve-todo-parallel.workflow.js`
- `plugins/soleur/skills/resolve-pr-parallel/workflows/resolve-pr-parallel.workflow.js`
- `plugins/soleur/skills/drain-labeled-backlog/workflows/drain-labeled-backlog.workflow.js`
- `plugins/soleur/skills/model-launch-review/SKILL.md` (body only)
- `plugins/soleur/AGENTS.md` (line 180 prose)
- `knowledge-base/engineering/architecture/decisions/ADR-110-harness-semantic-model-tier-map.md`

Phase B (follow-up PR; listed so the #7773 executor has the whole set):

- `apps/web-platform/package.json`
- `apps/web-platform/package-lock.json`
- `apps/web-platform/Dockerfile`
- `apps/web-platform/server/inngest/model-tiers.ts`
- `apps/web-platform/test/server/inngest/model-tiers.test.ts`
- `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh`
- `plugins/soleur/test/model-launch-review.test.ts`
- `plugins/soleur/skills/eval-harness/models.generated.json` (regenerated)
- the `--fix`-rewritten reference docs (`agent-native-architecture/references/*.md`, `dspy-ruby/references/providers.md`) and `cron-*-audit.ts` comments
- `knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md`

## Files to Create

None.

## Non-Goals / Out of Scope

- **Codex model pin.** Soleur inherits the Codex session model by design (ADR-215, `codex/INSTRUCTIONS.md`). Adding `TIER_MAPS.codex` would be a new mechanism the ask does not need. Codex users get GPT-6 Sol through OpenAI's own server-side catalog.
- **Grok dogfood host `default = "grok-4.5"`** (`apps/web-platform/infra/cloud-init-grok-dogfood.yml`, `scripts/dogfood/grok-gpu-bootstrap.sh`, `scripts/dogfood/grok-measure.test.sh`, runbook). This is the Phase 1 measurement baseline, and a `user_data` edit force-replaces a live host. Not deferred; excluded on purpose.
- **Claude `TIER_MAPS.claude` / agent `model:` frontmatter.** These use aliases (`opus`, `fable`, `inherit`) that retarget automatically (ADR-053).
- **`claude-code-action` pin bump (v1.0.161 → tip v1.0.231).** No coupled `--model` swap (#2540 invariant).
- **dspy-ruby `gpt-4o*` examples.** Illustrative third-party DSPy config, not a harness pin.
- **Weakening the npm release-age floor.** This is the #1174 supply-chain defense.

## Alternative Approaches Considered

| Alternative | Rejected because |
|---|---|
| Swap `AUDIT_MODEL` now, without the CLI bump | Pinned 2.1.219 lacks `claude-opus-5-5` (measured). An unknown id silently gets half `max_tokens` (#6934), and the CLI's bundled thinking shape for unknown ids risks 400s on a model where thinking can't be disabled |
| `--min-release-age=0` override for 2.1.280 now | CI `lockfile-sync` re-runs without the override, so the PR is red. It also defeats #1174 |
| Hold the whole PR until 2026-09-25 | Blocks the Grok half (fully verified and ready) on an unrelated npm floor |
| Add the `claude-opus-5=claude-opus-5-5` AUTOFIX pair in Phase A as a reminder | `rule-audit.yml`'s scheduled `--detect` would file a `model-drift` issue whose `--fix` is unsafe until the CLI bump. #7773 plus the date carry the reminder without handing anyone an unsafe fix |
| `cheap = grok-4.7` (or `grok-4.6`) | Same base price as 4.5 but a higher cached-input rate. The `cheap` tier exists to minimize cost |
| `cheap = grok-4.7-build-fast` | 2x token rate: it is a speed SKU, not a cost SKU |
| Add a scripted Grok check to `audit-models.sh` | New guard with its own test and mutation matrix. A flag-only checklist row honors ADR-110 at a fraction of the cost. Revisit if a Grok drift slips past the row |

## Technical Considerations

- **Grok model-list provenance.** `~/.grok/models_cache.json` has `etag`/`fetched_at`, so the list is server-driven. Users on older Grok CLIs still resolve `grok-4.7`, so no minimum CLI version is needed.
- **Grok pricing parity.** grok-4.7 costs the same as grok-4.6 ($2/$0.50/$6 under 200k tokens; $4/$1/$12 above). Moving standard/strong/advisor is cost-neutral.
- **Byte-identity of fences.** The fences are hand-synced, with no generator (`harness-model-map.ts` header). The parity test is the guard, and it already exists.
- **NFRs:** none affected. No latency, availability or security surface changes.

## User-Brand Impact

- **If this lands broken, the user experiences:** a Grok Build user invokes `soleur:review` / `soleur:plan-review` / `soleur:deepen-plan` / `resolve-*` / `drain-labeled-backlog`, and the pinned workflow steps fail to spawn a subagent because the model slug is rejected. Phase B broken: the weekly Opus audit crons (legal / agent-native / competitive / growth / ux / architecture-sync) produce truncated or 400-failed runs.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. No credentials, data paths or permissions change; only model-name strings.
- **Brand-survival threshold:** `aggregate pattern`. One wrong slug degrades every Grok user's pinned steps at once. It is recoverable by a one-line revert and involves no data exposure.

## Observability

```yaml
liveness_signal:
  what: "Phase A: harness-model-map parity test (bun) in CI. Phase B: Sentry cron monitors for the AUDIT_MODEL crons (scheduled-legal-audit, scheduled-agent-native-audit, …)"
  cadence: "per-PR CI run (Phase A); per scheduled cron run (Phase B)"
  alert_target: "GitHub PR check failure (Phase A); Sentry cron-monitor missed/failed check-in issue (Phase B)"
  configured_in: "plugins/soleur/test/harness-model-map.test.ts; apps/web-platform/infra/sentry/cron-monitors.tf"
error_reporting:
  destination: "Sentry web-platform project (SENTRY_DSN) via reportSilentFallback in cron-*-audit.ts (Phase B)"
  fail_loud: "cron check-in status=error on the scheduled-*-audit monitor; CI red on harness-model-map.test.ts"
failure_modes:
  - mode: "a workflow fence left on grok-4.6 (drift from SSOT)"
    detection: "harness-model-map.test.ts fence-parity assertion fails in CI"
    alert_route: "PR check failure"
  - mode: "grok-4.7 slug rejected by Grok Build"
    detection: "grok models listing verified live pre-merge (CLI 1.0.40); server-fetched catalog"
    alert_route: "user-reported workflow spawn error; revert one-line map"
  - mode: "Phase B: CLI pin does not know claude-opus-5-5"
    detection: "audit-models.sh [2b] DRIFT line; rule-audit.yml scheduled --detect"
    alert_route: "model-drift GitHub issue (auto-filed)"
  - mode: "Phase B: audit cron 400 / truncated output on Opus 5.5"
    detection: "Sentry cron monitor error check-in + reportSilentFallback event"
    alert_route: "Sentry issue to operator email"
logs:
  where: "GitHub Actions CI logs (Phase A); Inngest run logs + Sentry events (Phase B)"
  retention: "GitHub Actions 90 days; Sentry per plan retention"
discoverability_test:
  command: "grep -c advisor...grok-4.7 plugins/soleur/lib/harness-model-map.ts"
  expected_output: "1"
```

## Acceptance Criteria

### Phase A (this PR)

- [ ] `resolveModelTier("standard"|"strong"|"advisor", "grok")` returns `grok-4.7`, and `resolveModelTier("cheap","grok")` returns `grok-4.5`. Both are asserted in `plugins/soleur/test/harness-model-map.test.ts`. The same suite's existing fence-parity tests (lines 156-185) prove the 7 inlined fences are byte-identical and carry these values.
- [ ] `bun test plugins/soleur/test/harness-model-map.test.ts plugins/soleur/test/workflow-model-pins.test.ts plugins/soleur/test/components.test.ts plugins/soleur/test/harness-parity.test.ts plugins/soleur/test/harness-parity-tree.test.ts` exits 0, and PR CI is green. The harness-parity suites scan `skills/*/SKILL.md` prose, so any skill the new row 6 names must be written `soleur:<name>`.
- [ ] `git grep -l 'grok-4\.6' -- plugins/soleur` prints nothing, or only `plugins/soleur/lib/harness-model-map.ts`. This catches prose drift such as `plugins/soleur/AGENTS.md:180`, which the parity test cannot see.
- [ ] ADR-110 fixture table reads `grok-4.7` for standard/strong/advisor. The line-35 heading cites 2026-09-23 / CLI 1.0.40. The line-39 "(only non-default CLI spawn slug)" note is gone. The file carries `Addendum — 2026-09-23` with the live `grok models` output and docs.x.ai prices.
- [ ] `plugins/soleur/skills/model-launch-review/SKILL.md` has a row 6 (Grok tier-map freshness) and a Codex no-pin sentence under "When to invoke". Its frontmatter `description:` is unchanged: `git diff origin/main -- plugins/soleur/skills/model-launch-review/SKILL.md | grep -c '^[-+]description:'` prints `0`.
- [ ] `git grep -nE -e 'gpt-[0-9]' -e 'codex-mini' -- apps/web-platform/server .codex plugins/soleur/codex` returns no lines, so the Codex no-pin claim holds at merge.
- [ ] `git diff --name-only origin/main...HEAD` lists no path under `apps/` or `scripts/dogfood/`. Phase A does not touch the dogfood host, the CLI pin, or `AUDIT_MODEL`.
- [ ] #7773 is retitled to the Phase B title and carries a comment linking this plan. The PR body says `Ref #7773`.

### Phase B (follow-up PR, tracked by #7773; not executed by this pipeline)

- [ ] `apps/web-platform/package.json` and `Dockerfile` pin the same `@anthropic-ai/claude-code` version ≥ 2.1.280, and `package-lock.json` regenerated without a floor override (CI `lockfile-sync` green).
- [ ] `AUDIT_MODEL === "claude-opus-5-5"`, and `models.generated.json` lists `anthropic:messages:claude-opus-5-5`.
- [ ] `audit-models.sh --detect` exits 0, and `[2b]` reports `ok` for `claude-opus-5-5`.
- [ ] No file contains `claude-opus-5-5-5` (prefix-double guard: `git grep -c 'claude-opus-5-5-5'` → no output).

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment (soleur:engineering:cto):** Go, with small edits. The work is a few hours and needs no new ADR; the ADR-110 addendum is enough. The two-PR split is right because the #1174 floor blocks only the Claude half.

Concerns, all folded in:

- (1) The `plugins/soleur/AGENTS.md:180` grok-4.6 prose is now A4b.
- (2) The `.grok/agents` `model: haiku` stubs are pre-existing and filed as #8604.
- (3) The cheap=grok-4.5 rationale is thin and 4.5 is the first slug xAI will drop; the row-6 fallback rule covers it.
- (4) The Codex check pattern was too narrow; it is widened.
- (5) The SKILL.md "all 5 checks" wording is corrected: the scripted groups are named and row 6 is marked agent-run (Codex needs no row).

Scope: no architectural decision (ADR-110 data refresh only) and no new infrastructure. No C4 impact either: no new external actor, system, container or access relationship. xAI, OpenAI and Anthropic are already modeled as the external model vendors the harnesses call.

**Scoped advisor consult (plan Step 4.5, `advisor` tier):**

- Keep Phase A as is. State the cached-input rationale for `cheap = grok-4.5` explicitly in the ADR-110 addendum, so the next launch does not "fix" it back.
- In Phase B, isolate the CLI bump from the id swap. Adopted as two commits in one PR (B0), not two PRs.
- Add a CI guard that the pinned CLI knows `AUDIT_MODEL`: filed as #8603.
- Terminal-target invariant: it already exists (`assert_single_hop`).
- Pin the oldest qualifying CLI version: adopted (exactly 2.1.280).

No Product/UX surface: no file under the UI-surface globs is touched.

### Plan Review (DHH, Kieran, code-simplicity; 2026-09-23)

**Applied (mechanical):**

- **Codex checklist row cut** (all three flagged it):
  - it guards a pin nobody intends to add;
  - its regex would break a Markdown table cell;
  - calling it "manual" conflicts with `hr-never-label-any-step-as-manual-without`.
- **A2 before/after greps and two ACs cut.** The existing parity test (`harness-model-map.test.ts:156-185`) already proves fence identity and values.
- **`AGENTS.md:180` made tier-generic.**
- **A0 test changes:**
  - version dropped from the test name;
  - stale "only non-default slug" comment added to the edit;
  - redundant `.not.toBe` dropped.
- **ADR-110 line-35 heading and line-39 note added to A3.** The citation corrected to "Decision item 6".
- **Provenance comment shortened.** The evidence lives only in the ADR addendum.
- **The #7773 comment links the plan** instead of pasting the checklist.
- **B8 trimmed.**
- **Phase B PR uses `Closes #7773`.**
- **`discoverability_test` rewritten** with no escaped quotes (Kieran simulated Check 10's parser).
- **Final AC names the exact bun suites.**

**Not applied (taste, recorded):**

- DHH suggested replacing Phase B with a pointer to #7773. It is kept: the plan is the one durable artifact the #7773 comment links to.
- DHH suggested trimming the Observability block and merging the Research subsections. Both are kept: plan Phase 2.9 requires the Observability schema, and plan-review consumes the Property/Cut lists.

## Test Scenarios

1. RED→GREEN: after A0, `harness-model-map.test.ts` fails on the grok expectations. After A1+A2 it passes.
2. `bun test plugins/soleur/test/workflow-model-pins.test.ts` stays green (tier *names* unchanged; only Grok SKUs moved).
3. Live slug check: `grok models` lists `grok-4.7` (re-run at work time; record output in PR body).

## Risks

- **Grok free-tier accounts:** `grok-4.7` is the Grok Build default and is available on the free tier. Only `grok-4.7-build-fast` is excluded, and we do not pin it.
- **Phase B slips past the floor date:** #7773 carries an explicit not-before timestamp. `rule-audit.yml` will not flag it (the pair is added in Phase B), so the issue is the reminder. Accepted: the other path (adding the pair now) hands out an unsafe `--fix`.
- **2.1.280 regressions:** Phase B pins exactly 2.1.280 (what was measured) and lands the CLI bump as its own commit ahead of the swap, so the swap alone can be reverted.
- **Grok `subagent_model_inheritance`** (a pre-existing risk, not introduced here): per Grok's `16-subagents.md` user guide, with `[features] subagent_model_inheritance = true` "a spawn that still names one [model] fails". That affects every Grok workflow pin (grok-4.5 and grok-4.7 alike), so this plan does not change it. It is tracked in #8604, together with the `.grok/agents/*.md` `model: haiku` stubs written by `plugins/soleur/scripts/sync-grok-agent-compat.ts:58`.
- **No CI gate on "the pinned CLI knows `AUDIT_MODEL`"** (pre-existing; `[2b]` is hand-run only): a model-first swap would pass CI. Phase B follows `[2b]` by hand. The CI guard is tracked in #8603.
- **`cheap = grok-4.5` is the first slug xAI will drop** (CTO): the row-6 fallback rule says what to do when it disappears.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- `claude-opus-5` is a strict prefix of `claude-opus-5-5`. Never `sed s/claude-opus-5/claude-opus-5-5/g`: it produces `claude-opus-5-5-5` on a second pass and on any already-migrated line. Phase B goes through `audit-models.sh --fix` (boundary-anchored), and AC "no `claude-opus-5-5-5`" pins it.
- A `toContain("claude-opus-5")` assertion passes on `claude-opus-5-5` by prefix. Assert the quoted id.
- Phase A exact-string swap: match the full `standard: 'grok-4.6', strong: 'grok-4.6', advisor: 'grok-4.6'` triple, never bare `grok-4.6` (the ADR addendum and comments legitimately name `grok-4.6` as a still-listed slug).
