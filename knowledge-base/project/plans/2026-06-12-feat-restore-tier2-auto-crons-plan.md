---
title: Restore the 7 mergeMode:auto Tier-2-deferred crons (#5199)
date: 2026-06-12
type: feat
branch: feat-one-shot-restore-tier2-auto-crons-5199
issue: 5199
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# feat: Restore the 7 mergeMode:auto Tier-2-deferred crons (#5199)

## Enhancement Summary

**Deepened on:** 2026-06-12
**Sections enhanced:** Per-cron enumeration, Egress reconciliation, Files to Edit/Create, Test Strategy, User-Brand Impact.
**Review agents used:** security-sentinel, user-impact-reviewer, code-simplicity-reviewer (single-user-incident threshold triad). All load-bearing claims ground-truthed against installed code.

### Key Improvements
1. **Committed to eleventy decision A** (defer build to CI; no `registry.npmjs.org` egress broadening). Under A, the no-node_modules `--depth=1` clone makes `npx @11ty/eleventy` + the `_site`-consuming `validate-seo.sh`/`validate-csp.sh` unreachable → those verbs DROP from the growth/seo allowlists, collapsing `cron-growth-execution` + `cron-seo-aeo-audit` to `ISSUE_CREATOR_BASH_ALLOWLIST`. (simplicity #1/#2, security P2-3)
2. **Extend the existing parity test, not a new file.** `cron-safe-commit-parity.test.ts` already self-discovers via `readdirSync` AND hardcodes all 7 crons in `MIGRATED_PROMPT` (`:38-46`) AND invariant 3 (`:146-176`) asserts no persistence-verb re-arm. Only the token-mint check + the `gh api` negative are genuinely new — add them to the existing file. (simplicity #3)
3. **community-monitor prompt rewrite constraint:** the `gh api` replacement MUST stay within the allowlist. Use `gh issue list --json updatedAt,number` ONLY (NOT `gh pr list` — it is not in the allowlist). Cross-check AC: every `gh` verb the rewritten prompts emit appears in that cron's allowlist. (security P1-2)
4. **User-Brand Impact extended** to name community-monitor's broader secret surface (Discord/X/Bsky/LinkedIn tokens) and the write-containment chain (Discord = no write sub-command in `discord-community.sh`; X/Bsky/LinkedIn = `*_ALLOW_POST` unset). For this cron the egress firewall — not the hook — is the load-bearing exfil control (script-internal curl is a grandchild process the hook never sees). (user-impact F1/F6, security P2-1)

### New Considerations Discovered
- The `bash <script>` allowlist entries (community-router.sh) are a leading-prefix surface: the router `exec`s into children whose `curl`/`gh api` are grandchild OS processes outside the PreToolUse hook — gated ONLY by the L3 egress firewall. Correct boundary reading, but the security posture for community-monitor reduces to "trust the script bodies + egress firewall," documented in User-Brand Impact.
- Verify at `/work`: `validate-seo.sh`/`validate-csp.sh` take a built `_site` as `$1` (confirmed) — so decision A drops them; do not leave them in the allowlist.

## Overview

PR #5200 (issue #5138, merged 2026-06-12 16:48 UTC) landed the stale-bot-PR watchdog: a
daily age-scan in `cron-cloud-task-heartbeat.ts` that catches any `ci/*` or
`self-healing/auto-*` bot PR whose `enablePullRequestAutoMerge` silently disarmed on a
merge conflict. That was the gate on restoring the seven `mergeMode:"auto"` Tier-2-deferred
crons. PR #5202 (the same issue #5199 durable anchor, merged 2026-06-12 17:04 UTC) restored
the FIRST cron (cron-ux-audit) via the file-driven `mcp__*` hook allowance.

This plan restores the remaining seven `mergeMode:"auto"` PR-flow crons:
`cron-campaign-calendar`, `cron-competitive-analysis`, `cron-growth-audit`,
`cron-seo-aeo-audit`, `cron-content-generator`, `cron-growth-execution`,
`cron-community-monitor`. After this, ONLY `cron-bug-fixer` remains deferred (its
`bot-fix/*` head pattern is outside the PR-5200 watchdog's `ci/*` + `self-healing/auto-*`
scan — extending that scan is OUT OF SCOPE here; bug-fixer stays deferred). Use **Ref #5199**
in the PR body (NOT `Closes` — bug-fixer remains).

For EACH of the seven crons:
1. Remove it from `TIER2_DEFERRED_CRONS` (`_cron-shared.ts`).
2. Add a finite, per-construct, **evidence-gated** `CRON_BASH_ALLOWLISTS` entry
   (`_cron-claude-eval-substrate.ts`), enumerated by reading the cron handler prompt + the
   `/soleur:*` SKILL it invokes. NO blanket metachar drop. NO `gh api` (F4a).
3. Narrow the token mint in each `cron-<name>.ts` to
   `{ permissions: DEFAULT_CRON_TOKEN_PERMISSIONS, repositories: [REPO_NAME] }`.
4. KEEP the defensive `deferIfTier2Cron` guard (no-op once out of the set).
5. Verify NON-GitHub egress targets are in `cron-egress-allowlist.txt`; add finite,
   evidence-gated entries only if a real target is missing.
6. Validate via `/soleur:trigger-cron <name>.manual-trigger` (post-merge).

## Research Reconciliation — Spec vs. Codebase

The one-shot ARGUMENTS prescribed a recipe assumption that the **current codebase
contradicts**. Reading the actual handler prompts, `_cron-safe-commit.ts`, and the existing
parity test corrects three premises. This table is load-bearing — building to the recipe
verbatim would (a) ship a security regression AND (b) fail an existing CI guard.

| Recipe claim | Codebase reality | Plan response |
| --- | --- | --- |
| "These are PR-flow crons that commit + open PRs via safeCommitAndPr … so their bash surface includes git add/commit/checkout/switch/push + gh pr create/comment/list" | **FALSE for the spawned-eval bash surface.** `safeCommitAndPr` (`_cron-safe-commit.ts`) runs git add/commit/push via **node-level `execFile`** and gh-pr create/merge via **Octokit** — OUTSIDE the containment hook's jurisdiction (`_cron-safe-commit.ts:200-221` `runGit` uses `execFile`; PR create at `:608` uses `octokit.request`). EVERY one of the 7 prompts **explicitly FORBIDS** `git add/commit/push` and `gh pr create/merge` (`cron-content-generator.ts:120`, `cron-seo-aeo-audit.ts:121`, `cron-campaign-calendar.ts:104`, `cron-growth-audit.ts:105`, `cron-growth-execution.ts:128`, `cron-competitive-analysis.ts:136`, `cron-community-monitor.ts:194`). | **The bash allowlists contain NO git verbs and NO `gh pr` verbs.** Only the issue/label verbs the prompt actually emits + per-cron domain tooling. This is independently REQUIRED: `cron-safe-commit-parity.test.ts` invariant 3 (`:146-176`) FAILS CI if a restored cron's allowlist contains `git add`/`git commit`/`git push`/`gh pr create`/`gh pr merge`. |
| "Mirror the existing cron-roadmap-review allowlist shape (the Tier-1 PR-flow precedent)" — implying roadmap-review's git/gh-pr verbs | roadmap-review is **EXEMPT** from the safe-commit migration (`cron-safe-commit-parity.test.ts:64` EXEMPT map: "hook-guarded Tier-1 self-commit") — its model improvises git WITHIN the hook allowlist. The 7 crons are the **migrated** cohort: persistence is node-side, NOT in the eval. So they are the OPPOSITE shape from roadmap-review's git block. | Mirror roadmap-review's **issue/label verb subset** (`gh issue list/create/view/edit/close/comment`, `gh label list/create`) where the prompt needs it; do NOT mirror its `git *` / `gh pr *` block. The closest true precedent is `ISSUE_CREATOR_BASH_ALLOWLIST` (`_cron-claude-eval-substrate.ts:138-143`) + per-cron domain tooling. |
| Token narrows to `DEFAULT_CRON_TOKEN_PERMISSIONS` (contents:write, issues:write, pull_requests:write) | **CORRECT.** Unlike ux-audit (issue-creator only → `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS` contents:read/issues:write), these 7 DO push + open PRs via `safeCommitAndPr`, which consumes the **same minted token** (`_cron-safe-commit.ts:279` builds Octokit from `installationToken`; push at `:584`). `contents:write` (push) + `pull_requests:write` (PR create) + `issues:write` (label/issue) are all required. | Use `DEFAULT_CRON_TOKEN_PERMISSIONS` + `repositories: [REPO_NAME]` exactly as prescribed. NOT the issue-creator preset. Mirrors the mint shape at `cron-ux-audit.ts:240-244`, substituting the permissions const. |

## User-Brand Impact

**If this lands broken, the user experiences:** a security-boundary regression on a public,
auto-deploying repo. A too-broad allowlist entry (e.g. accidentally re-adding a git/gh-pr verb
or `gh api`) widens the containment surface of a cron that spawns `claude --print` with a
GitHub installation token — the exfil defense the whole hook exists to provide. Conversely a
too-narrow entry breaks the cron at runtime: its weekly output issue silently stops appearing
(the visible-degradation contract), and a non-technical operator cannot tell a deny-storm from
a healthy quiet run.

**If this leaks, the user's workflow/code is exposed via:** the installation token in the
spawned eval. The token carries `contents:write` (push to the public auto-deploying soleur
repo), `pull_requests:write`, `issues:write`, scoped to `repositories: [soleur]`. A leaked
token bounded to this set is a single-user incident (push/PR/issue on one repo) — but only if
the allowlist does not hand the eval an egress or arbitrary-`gh api` primitive that turns the
token into an exfil channel. The mcp/egress probes in `runHookSelfTest` and the egress
firewall are the load-bearing closes; this plan must not weaken either.

**community-monitor carries the widest secret surface of the seven.** Its `buildSpawnEnv`
(`cron-community-monitor.ts:228-247`) additionally injects `DISCORD_WEBHOOK_URL`,
`DISCORD_BOT_TOKEN`, `BSKY_APP_PASSWORD`, `LINKEDIN_ACCESS_TOKEN`, and the four `X_*` OAuth1
credentials — write-capable credentials on the operator's OWN brand-facing social accounts (a
rogue post is a single-user-incident artifact). The read-only contract rests on a write-containment
chain the plan must keep load-bearing and documented, NOT incidental:
- **X / Bluesky / LinkedIn** writes are gated behind `X_ALLOW_POST` / `BSKY_ALLOW_POST` /
  `LINKEDIN_ALLOW_POST` (confirmed: `x-community.sh:611`, `bsky-community.sh:233`,
  `linkedin-community.sh:261`), and `buildSpawnEnv` sets NONE of them → all three scripts refuse
  to post. The contract depends on ALL THREE unset guards, not just X's.
- **Discord** has NO `*_ALLOW_POST` guard — its write containment depends entirely on
  `discord-community.sh` exposing no write sub-command (only `messages`/`members`/`guild-info`/
  `channels`). A future router change adding a Discord post command would silently arm posting
  via the already-injected webhook token. The PreToolUse hook also denies the raw `curl` that
  would be needed to use the webhook directly.
- For community-monitor the **egress firewall (not the hook) is the sole egress control** for
  these tokens: the agent legitimately reaches 5 social APIs via `bash …community-router.sh`,
  whose `curl` runs in a grandchild process the hook never sees. A token smuggled into a
  path/query to an allowlisted host is not caught by the content-blind host-level firewall —
  this is a pre-existing residual of community-monitor's design that this plan, by restoring the
  cron, surfaces. Any future PR adding a write sub-command to those scripts re-opens this and
  must re-trigger security + user-impact review.

**Brand-survival threshold:** single-user incident.

CPO sign-off required at plan time before `/work` begins (carry forward from #5199 framing or
confirm CPO has reviewed). `user-impact-reviewer` runs at review-time (review/SKILL.md
conditional-agent block).

## Per-Cron Allowlist Enumeration (evidence-gated)

Each entry below is enumerated from the handler prompt + the `/soleur:*` SKILL it invokes,
with file:line evidence. The containment hook (`cron-bash-allowlist-hook.mjs`) **unconditionally
denies** `$(...)`/backtick/`${...}` substitution, pipes, redirects, `curl`/raw egress binaries,
`gh api` (when not allowlisted), and blanket-staging git forms — regardless of the allowlist.
Allowlist matching is leading-verb-prefix at sub-command granularity.

### 1. cron-growth-audit
- Handler: `--allowedTools Bash,…,Skill,Task` (`cron-growth-audit.ts:70`), `--plugin-dir plugins/soleur` present, `safeCommitAndPr` called (`:263`), label `scheduled-growth-audit`.
- Prompt emits: `gh issue create` (Step 5 `:99`), dedup `gh issue list` + tracking `gh issue create` (Step 5.5 `:101`). FORBIDS git/gh-pr (`:105`).
- Invokes `/soleur:growth auditing` + `/soleur:seo-aeo` (Step 3). seo-aeo SKILL emits `npx @11ty/eleventy` + `bash …/validate-seo.sh _site` + `bash …/validate-csp.sh _site` (`seo-aeo/SKILL.md:97-105`).
- **Sharp edge — `$(date +%Y-%m-%d)` in prompt (`cron-growth-audit.ts:84`) is hook-DENIED** (command substitution). NOT allowlistable. Prompt must be hardened to use the literal date / agent-computed date. Flag as a `Files to Edit` prompt fix.
- **Decision A applied:** eleventy build defers to CI → `npx @11ty/eleventy` + the `_site`-consuming validate scripts DROP. growth-audit keeps `gh issue view`/`gh issue edit` (Step 5.5 dedup/tracking), so it stays bespoke (not the shared const).
- Proposed entry:
  ```ts
  "cron-growth-audit": [
    "gh issue list", "gh issue create", "gh issue view", "gh issue edit",
    "gh label list", "gh label create",
  ],
  ```

### 2. cron-growth-execution
- Handler: `--allowedTools Bash,…,Skill,Task` (`cron-growth-execution.ts:99`, no WebFetch), plugin-dir present, `safeCommitAndPr` (`:291`), label `scheduled-growth-execution`.
- Prompt emits: `npx @11ty/eleventy` (`:121`), `bash …/validate-seo.sh _site` (`:122`), `gh issue create` (`:124`,`:126`). FORBIDS git/gh-pr (`:128`). Uses literal `<today>` (no `$(date)` hazard).
- Invokes `/soleur:growth fix` (`:118`) → growth-strategist agent (eleventy).
- **Decision A applied:** eleventy build defers to CI → `npx @11ty/eleventy` + validate script DROP. What remains (`gh issue list/create`, `gh label list/create`) is EXACTLY `ISSUE_CREATOR_BASH_ALLOWLIST` → collapse to the shared const.
- Proposed entry:
  ```ts
  "cron-growth-execution": ISSUE_CREATOR_BASH_ALLOWLIST,
  ```

### 3. cron-competitive-analysis
- Handler: `--allowedTools Bash,…,Task,Skill` (`cron-competitive-analysis.ts:108`), plugin-dir present, `safeCommitAndPr` (`:311`), label `scheduled-competitive-analysis`.
- Prompt emits: `gh issue create` (`:132-134`) only. FORBIDS git/gh-pr (`:136`). Uses literal date.
- Invokes `/soleur:competitive-analysis` → competitive-intelligence agent (WebSearch/WebFetch tools only — no bash, no git). **Stale SKILL.md note:** `competitive-analysis/SKILL.md:61` still says "commit and push the report to main" (old GHA path); the handler prompt's explicit forbid + `safeCommitAndPr` is authoritative — do NOT allowlist git/push from that stale line.
- Pure issue-creator bash surface → reuse the shared const:
  ```ts
  "cron-competitive-analysis": ISSUE_CREATOR_BASH_ALLOWLIST,
  ```

### 4. cron-seo-aeo-audit
- Handler: `--allowedTools Bash,…,Skill,Task` (`cron-seo-aeo-audit.ts:100`), plugin-dir present, `safeCommitAndPr` (`:287`), label `scheduled-seo-aeo-audit`.
- Prompt emits: `gh issue create` (`:119`). FORBIDS git/gh-pr (`:121`). "Run /soleur:seo-aeo fix" (`:117`).
- seo-aeo `fix` flow emits `npx @11ty/eleventy` + `bash …/validate-seo.sh _site` + `bash …/validate-csp.sh _site` (`seo-aeo/SKILL.md:78-79`,`:97-105`). The validate scripts take a built `_site` as `$1` (confirmed) — unreachable without a local build.
- **Decision A applied:** eleventy build defers to CI → `npx @11ty/eleventy` + both validate scripts DROP (no local `_site` exists in the node_modules-free clone). What remains (`gh issue create/list`, `gh label`) is `ISSUE_CREATOR_BASH_ALLOWLIST` → collapse to the shared const. **`/work` must also harden the seo-aeo prompt** to tell the agent NOT to build locally (mirror content-generator `:111-112`), else the agent's denied `npx`/validate calls are a Finding-2-class silent degradation.
- Proposed entry:
  ```ts
  "cron-seo-aeo-audit": ISSUE_CREATOR_BASH_ALLOWLIST,
  ```

### 5. cron-content-generator
- Handler: `--allowedTools Bash,…,Skill,Task` (`cron-content-generator.ts:83`), plugin-dir present, `safeCommitAndPr` (`:294`), label `scheduled-content-generator`.
- Prompt emits: `gh issue create` (Step 1b/6 `:101`,`:118`). FORBIDS git/gh-pr (`:120`). **Explicitly forbids local eleventy build** ("This ephemeral workspace is a shallow clone with no node_modules, so a local `npx @11ty/eleventy` build cannot run here … Do NOT attempt a local build", `:111-112`) — validation deferred to CI on the PR. So NO `npx @11ty/eleventy` in this allowlist.
- Invokes `/soleur:growth plan`, `/soleur:content-writer --headless`, `/soleur:social-distribute --headless`. These delegate via Task/skill; no inline git/gh/npx surface beyond the issue create (content-writer fact-checker uses WebFetch tool, not bash).
- Pure issue-creator bash surface:
  ```ts
  "cron-content-generator": ISSUE_CREATOR_BASH_ALLOWLIST,
  ```

### 6. cron-campaign-calendar
- Handler: `--allowedTools Bash,…,Skill,Task` (`cron-campaign-calendar.ts:67`), plugin-dir present, `safeCommitAndPr` (`:266`), label `scheduled-campaign-calendar`.
- Prompt emits: `gh issue list` (dedup search STEP 2a `:89`), `gh issue comment` (STEP 2b `:90`), `gh issue create` (STEP 2c/2.5 `:91`,`:96`), `gh issue close` (STEP 2.5 heartbeat issue `:96`). FORBIDS git/gh-pr (`:104`). NO eleventy, NO `date -u`.
- Invokes `/soleur:campaign-calendar`. SKILL's staleness path uses read-only `git log` (`campaign-calendar/SKILL.md:63`); its Phase-4 CI self-persist block (`git add/commit/push`, `:131-136`) is GATED on `GITHUB_ACTIONS`/commit-instructions which the cron prompt does NOT supply, so it must NOT fire. **Decision:** OMIT `git log` from the allowlist — the `--depth=1` clone makes `git log` staleness unreliable anyway (the SKILL offers filename-date fallback `:61-62`), and omitting keeps the boundary tighter. If `/work` finds the skill hard-requires `git log` at runtime, add ONLY `git log` (read-only) with a one-line evidence note — never the add/commit/push block.
- Proposed entry:
  ```ts
  "cron-campaign-calendar": [
    "gh issue list", "gh issue view", "gh issue create",
    "gh issue comment", "gh issue close",
    "gh label list", "gh label create",
  ],
  ```

### 7. cron-community-monitor
- Handler: `--allowedTools Bash,Read,Write,Edit,Glob,Grep` (`cron-community-monitor.ts:127`, **no Skill/Task**), `--plugin-dir` ABSENT (prompt calls scripts directly), `safeCommitAndPr` (`:379`), label `scheduled-community-monitor`. Wider `buildSpawnEnv` (`:228-247`) injects Discord/X/Bsky/LinkedIn read tokens; `X_ALLOW_POST` deliberately excluded (read-only monitor).
- Prompt emits: `bash plugins/soleur/skills/community/scripts/community-router.sh <args>` (`:149`,`:160`,`:162`,`:164`,`:167`), `gh issue list` (DEDUP `:200`), `gh issue create` (`:144`,`:153`,`:190`), `gh issue comment` (`:201`). FORBIDS git/gh-pr (`:194`).
- **Sharp edge — `gh api` in prompt (`:203`, CLONE DEPTH RULE for `updatedAt` staleness) must be EXCLUDED (F4a).** The script-internal `gh api`/`curl` inside `community-router.sh` runs as a grandchild OS process (the router `exec`s into the platform script at `community-router.sh:68`) and is NOT re-intercepted by the PreToolUse Bash hook (the hook is invoked per tool-call, sees only the top-level `bash …router.sh` string) — those are gated by the egress firewall, NOT the allowlist. But the PROMPT-LEVEL `gh api` at `:203` IS hook-visible and must be denied. **Files to Edit:** rewrite prompt `:203` to use **`gh issue list --json updatedAt,number` ONLY** — NOT `gh pr list`, which is NOT in this cron's allowlist and would be hook-denied at runtime (security review P1-2). The rewrite's every `gh` verb must already appear in the allowlist below.
- Proposed entry:
  ```ts
  "cron-community-monitor": [
    "bash plugins/soleur/skills/community/scripts/community-router.sh",
    "gh issue list", "gh issue create", "gh issue comment",
    "gh label list", "gh label create",
  ],
  ```

## Egress Allowlist Reconciliation (`cron-egress-allowlist.txt`)

| Cron | Non-GitHub egress needed | In allowlist? | Action |
| --- | --- | --- | --- |
| growth-audit | `soleur.ai` (live-page fetch, seo-aeo-analyst) | YES (`:56`) | none |
| growth-audit / growth-execution / seo-aeo | `registry.npmjs.org` IF `npx @11ty/eleventy` downloads (no node_modules in `--depth=1` clone) | **NO** | **Resolved by decision A** — eleventy build defers to CI; no npmjs.org added |
| competitive-analysis | arbitrary competitor sites via WebFetch/WebSearch (tool-level, content-blind L3 firewall — cannot be finitely enumerated) | N/A (this is the "non-GitHub egress" reason it was deferred) | Accept — WebFetch/WebSearch are model tools, not bash; the egress firewall is content-blind by design. Document the residual. No host added. |
| campaign-calendar | none | — | none |
| content-generator | none (defers eleventy to CI) | — | none |
| **community-monitor** | `discord.com`, `api.x.com`, `bsky.social`, `api.linkedin.com`, `api.github.com` | YES | none |
| **community-monitor** | **`hn.algolia.com`** (`hn-community.sh:15`, prompt `bash $ROUTER hn mentions`/`hn trending` `:167`) | **NO — MISSING** | **ADD `hn.algolia.com`** to `cron-egress-allowlist.txt` with evidence comment. `news.ycombinator.com` (string-built `hn_url` only, not dialed) NOT added. `bsky.app` (doc-message URL only) NOT added. |

### Eleventy-build decision (cross-cutting — growth-audit, growth-execution, seo-aeo) — COMMITTED TO (A)
The `--depth=1` clone has **no `node_modules`** (`cron-content-generator.ts:110` states this explicitly; `git ls-files | grep node_modules/@11ty` returns 0). So `npx @11ty/eleventy` in the ephemeral clone would attempt to DOWNLOAD eleventy from `registry.npmjs.org` (NOT in egress allowlist → blocked at the firewall → build fails). The `validate-seo.sh`/`validate-csp.sh` scripts take a built `_site` as `$1` (confirmed) — equally unreachable without the build. The ground truth FORCES the decision; there is no real fork, so this plan COMMITS to (A) rather than deferring:

- **(A) — CHOSEN. Defer the build to CI (mirrors content-generator).** Harden the seo-aeo/growth prompts to instruct "do NOT build locally; CI runs `npx @11ty/eleventy` on the PR" (content-generator pattern, `:111-112`). DROP `npx @11ty/eleventy` + both validate scripts from the allowlists. Effect: `cron-growth-execution` + `cron-seo-aeo-audit` collapse to `ISSUE_CREATOR_BASH_ALLOWLIST`; `cron-growth-audit` keeps only its `gh issue view/edit` extension. The audit issue still files; validation moves to the PR's required checks. Egress stays finite (NO `registry.npmjs.org`), and the seo-aeo `bash <script>` deny-bypass surface closes for free.
- **(B) — REJECTED.** Add `registry.npmjs.org` to the egress allowlist. Broadens egress to the full npm registry — a security regression at single-user-incident threshold. Retained only as a one-line row in Alternatives Considered.

## Files to Edit

- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — remove the 7 crons from `TIER2_DEFERRED_CRONS` (`:346-355`), leaving only `cron-bug-fixer`. Update the block comment (`:311-345`) to reflect: 7 restored, only bug-fixer deferred (bot-fix/* outside #5138/#5200 ci/* scan, OUT OF SCOPE).
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — add 7 `CRON_BASH_ALLOWLISTS` entries (per enumeration above). Do NOT touch `CRON_MCP_ALLOWLISTS` (these are git/gh PR-flow crons, not Playwright).
- `apps/web-platform/server/inngest/functions/cron-growth-audit.ts` — narrow token mint (`:167`) to `{ tokenMinLifetimeMs, permissions: DEFAULT_CRON_TOKEN_PERMISSIONS, repositories: [REPO_NAME] }`; import both from `_cron-shared`. Harden prompt `:84` to drop `$(date +%Y-%m-%d)` substitution.
- `apps/web-platform/server/inngest/functions/cron-growth-execution.ts` — narrow token mint; (decision A) drop local-build instruction if present.
- `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts` — narrow token mint.
- `apps/web-platform/server/inngest/functions/cron-seo-aeo-audit.ts` — narrow token mint (`:182`); (decision A) harden prompt to instruct "do NOT build locally; CI runs the eleventy build on the PR" (mirror content-generator `:111-112`).
- `apps/web-platform/server/inngest/functions/cron-content-generator.ts` — narrow token mint (`:206`).
- `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts` — narrow token mint.
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — narrow token mint; rewrite prompt `:203` to drop `gh api`, using **`gh issue list --json updatedAt,number` ONLY** (NOT `gh pr list` — not in the allowlist).
- `apps/web-platform/infra/cron-egress-allowlist.txt` — add `hn.algolia.com` with evidence comment (`hn-community.sh:15`).
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` — update the Tier-2 deferred-cron section: 7 restored, only cron-bug-fixer remains deferred.
- `apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts` — add the token-mint assertion + the `gh api` negative for the 7 restored crons (extend, do not duplicate the self-discovery scaffold).

## Files to Create

- None. **EXTEND** the existing `apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts` rather than create a new file (simplicity review #3). That file already self-discovers via `readdirSync`, hardcodes all 7 crons in `MIGRATED_PROMPT` (`:38-46`), and invariant 3 (`:146-176`) already asserts each one's allowlist excludes persistence verbs — so the parity invariant (in CRON_BASH_ALLOWLISTS + absent from TIER2_DEFERRED_CRONS) and the no-persistence-verb regression are already covered. Add ONLY the two genuinely-new assertions there (or a small sibling that imports its `MIGRATED_PROMPT`): the token-mint test + the `gh api` negative. Add `cron-safe-commit-parity.test.ts` to `## Files to Edit`.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open` against the planned file paths at plan time. **None** of the planned files (`_cron-shared.ts`, `_cron-claude-eval-substrate.ts`, the 7 `cron-*.ts`, `cron-egress-allowlist.txt`, the runbook) appear in an open code-review scope-out. (Re-verify at `/work` per the two-stage `gh --json` + standalone `jq` pattern.)

## Test Strategy (failing-first)

Write these BEFORE the source edits (RED → GREEN):

1. **Parity test** — for each of the 7 restored crons: assert it IS a key in `CRON_BASH_ALLOWLISTS` AND is ABSENT from `TIER2_DEFERRED_CRONS`. (Self-discovering shape per the `cron-safe-commit-parity.test.ts` readdir precedent; keyed on the explicit 7-cron set so a drift is loud.)
2. **Token test** — for each of the 7, assert the handler source mints `DEFAULT_CRON_TOKEN_PERMISSIONS` + `repositories: [REPO_NAME]` (source-grep against `mintInstallationToken({ … permissions: DEFAULT_CRON_TOKEN_PERMISSIONS … repositories: [REPO_NAME] … })`, mirroring how `cron-ux-audit.test.ts` asserts its mint). Distinguish from `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS` (which ux-audit uses — these 7 must NOT).
3. **Existing guard must stay green** — `cron-safe-commit-parity.test.ts` invariant 3 (`:146-176`) already asserts no restored cron's allowlist re-arms `git add/commit/push`/`gh pr create`/`gh pr merge`. The new allowlists MUST pass it (they contain no such verbs by design). Run it as a regression gate.
4. **Allowlist content negative test** — assert NO allowlist entry begins with `gh api` (F4a) for any of the 7.
5. **Post-merge validation** — `/soleur:trigger-cron <name>.manual-trigger` for each of the 7 over the full containment path (the `runHookSelfTest` bash-allow[0] probe proves delivery per cron). Each manual-trigger event is `cron/<name-minus-cron->.manual-trigger` (e.g. `cron/growth-audit.manual-trigger`).

Test runner: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-safe-commit-parity.test.ts` (extend this file per Files to Create; NOT `npm run -w` — repo has no root `workspaces`). Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] All 7 crons removed from `TIER2_DEFERRED_CRONS`; only `cron-bug-fixer` remains (grep: the Set has exactly 1 member).
- [ ] All 7 crons present in `CRON_BASH_ALLOWLISTS` with finite, evidence-gated entries; no entry contains `git add`/`git commit`/`git push`/`gh pr create`/`gh pr merge`/`gh api`.
- [ ] All 7 handlers mint `DEFAULT_CRON_TOKEN_PERMISSIONS` + `repositories: [REPO_NAME]`.
- [ ] `deferIfTier2Cron` guard retained in all 7 handlers (no-op once out of the set).
- [ ] `cron-growth-audit.ts` prompt no longer contains `$(date` (substitution removed).
- [ ] `cron-community-monitor.ts` prompt no longer contains `gh api` (rewritten to `gh issue list --json updatedAt,number` ONLY — no `gh pr list`).
- [ ] Cross-check: every `gh` verb each rewritten prompt emits appears in that cron's `CRON_BASH_ALLOWLISTS` entry (not just absence-of-`gh api`).
- [ ] `hn.algolia.com` added to `cron-egress-allowlist.txt` with evidence comment.
- [ ] Decision A applied consistently: NO allowlist entry contains `npx @11ty/eleventy` or `bash …/validate-seo.sh`/`validate-csp.sh`; `cron-growth-execution` + `cron-seo-aeo-audit` collapse to `ISSUE_CREATOR_BASH_ALLOWLIST`; `registry.npmjs.org` NOT added to the egress allowlist; seo-aeo/growth prompts hardened to defer the build to CI.
- [ ] New parity + token tests RED before edits, GREEN after.
- [ ] `cron-safe-commit-parity.test.ts` stays green; full vitest suite for `test/server/inngest/` green; `tsc --noEmit` clean.
- [ ] `TIER2_DEFERRED_CRONS` block comment + `cloud-scheduled-tasks.md` runbook updated (only bug-fixer deferred).
- [ ] PR body uses **Ref #5199** (NOT Closes — bug-fixer remains).

### Post-merge (operator-automatable via /soleur:ship + /soleur:trigger-cron)
- [ ] `hn.algolia.com` egress edit auto-applies (`terraform_data.cron_egress_firewall` folds the file hash into `triggers_replace`; `apply-web-platform-infra.yml` re-runs the provisioner on push to main — no SSH).
- [ ] Container restart on merge syncs the Inngest function registry (`web-platform-release.yml` path-filtered restart on `apps/web-platform/**`).
- [ ] `/soleur:trigger-cron <name>.manual-trigger` fires each of the 7 successfully over the full containment path (hook self-test passes per cron; the scheduled output issue/PR appears). Automatable via the trigger-cron skill (reads the trigger secret read-only from Doppler).

## Domain Review

**Domains relevant:** Engineering (security boundary), Product (CPO sign-off gate).

### Engineering (security boundary)
**Status:** reviewed (plan-author + agent enumeration)
**Assessment:** This is a 7-entry security-boundary diff over a deny-by-default containment hook on a public auto-deploying repo. The dominant risk is a too-broad allowlist entry (exfil-surface widening) or a too-narrow one (silent cron breakage). Mitigations: every verb is evidence-gated to a prompt/SKILL line; git/gh-pr verbs excluded by design AND by the existing parity-test guard; `gh api` excluded (F4a); egress additions limited to the one evidenced missing host (`hn.algolia.com`); eleventy-build default avoids broadening egress to npmjs.org. `runHookSelfTest` proves per-cron delivery of the allowlist at spawn time. CTO concern carried forward: confirm at `/work` that the seo-aeo local-build path is genuinely unreachable without node_modules (validates decision A).

### Product/UX Gate
**Tier:** none — no UI surface. Plan edits server-side inngest functions, an infra allowlist file, a runbook, and a test. No `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` touched.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/cron-egress-allowlist.txt` (one line: `hn.algolia.com`). This file is hashed into `terraform_data.cron_egress_firewall.triggers_replace`; no new TF resource, no new variable.

### Apply path
- (b) cloud-init + idempotent provisioner: a merged edit to this file auto-applies — `apply-web-platform-infra.yml`'s SSH block re-runs `cron-egress-resolve.sh` on push to main (per the file's own header). No manual/SSH step. Blast-radius: additive-then-prune nftables set update — adds `hn.algolia.com` IPv4s to `@soleur_egress_allow`. Zero downtime.

### Distinctness / drift safeguards
- The egress file is the single source; the resolver timer reconciles. No `dev != prd` concern (egress allowlist is host-level, environment-agnostic). No secrets land in state.

### Vendor-tier reality check
- N/A — `hn.algolia.com` is a public read-only API (no tier gate).

## Observability

```yaml
liveness_signal:
  what: per-cron Sentry Crons monitor (scheduled-<name>) heartbeat + the weekly scheduled-<name> output issue/PR
  cadence: each cron's schedule (weekly/biweekly per existing registration)
  alert_target: Sentry Crons (RED on missed/late check-in); cron-cloud-task-heartbeat watchdog (issue-count gap)
  configured_in: each cron-<name>.ts postSentryHeartbeat + resolveOutputAwareOk; infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry via reportSilentFallback/warnSilentFallback (already wired in every handler)
  fail_loud: yes — a hook self-test failure throws, the cron aborts, FAILED self-report issue (ensureScheduledAuditIssue) + RED monitor
failure_modes:
  - mode: too-narrow allowlist denies a needed verb at runtime
    detection: claude-eval stderr/stdout tail folded into scheduled-output-missing Sentry extra; output issue absent -> monitor RED
    alert_route: Sentry scheduled-output-missing + cron-cloud-task-heartbeat watchdog
  - mode: hn.algolia.com egress not applied -> community-monitor HN fetch fails
    detection: community-router.sh hn step errors surface in the eval tail; partial digest
    alert_route: Sentry (eval tail) + the cron's output issue content
  - mode: eleventy local build attempted without node_modules (if decision A not applied)
    detection: npx download blocked at egress firewall -> build error in eval tail
    alert_route: Sentry scheduled-output-missing
logs:
  where: Sentry events (reportSilentFallback); app stdout is NOT shipped to Better Stack (tails captured into Sentry extras instead)
  retention: Sentry default
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-safe-commit-parity.test.ts (NO ssh); plus /soleur:trigger-cron <name>.manual-trigger then read the scheduled-<name> issue via gh issue list
  expected_output: each of the 7 fires, hook self-test passes, scheduled output issue/PR appears
```

## Hypotheses

N/A — no network-outage / SSH diagnostic class. (Egress firewall change is additive and auto-applied; not a connectivity-failure investigation.)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, only `TBD`, or omits the threshold fails `deepen-plan` Phase 4.6. (Filled above; threshold = single-user incident.)
- The recipe's git/gh-pr verb assumption is wrong for this cohort (node-side persistence). Adding those verbs both widens the boundary AND fails `cron-safe-commit-parity.test.ts` invariant 3. Enumerate from the PROMPT, not from the recipe.
- `$(date +%Y-%m-%d)` in growth-audit's prompt is hook-denied — must be hardened, not allowlisted.
- community-monitor's prompt-level `gh api` (`:203`) is hook-visible and must be excluded/rewritten; the script-internal `gh api`/`curl` inside `community-router.sh` is a child of `bash <script>` (egress-gated, not hook-gated) and needs no allowlist entry beyond `bash …/community-router.sh`.
- Eleventy local build is unreachable in the no-node_modules `--depth=1` clone — default to deferring it to CI (decision A) rather than broadening egress to npmjs.org.

## Alternative Approaches Considered

| Approach | Decision |
| --- | --- |
| Mirror roadmap-review's full git/gh-pr allowlist block | REJECTED — roadmap-review is the EXEMPT Tier-1 self-commit cron; these 7 are node-side-persistence (migrated cohort). Would fail parity invariant 3. |
| Add `registry.npmjs.org` to egress for the eleventy builds | REJECTED as default (decision B) — broadens egress to the full npm registry at single-user-incident threshold. Defer build to CI instead (decision A). |
| Use `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS` (ux-audit's preset) | REJECTED — these 7 push + open PRs via safeCommitAndPr, which needs contents:write + pull_requests:write. Use `DEFAULT_CRON_TOKEN_PERMISSIONS`. |
| Restore cron-bug-fixer too | OUT OF SCOPE — bot-fix/* is outside #5138/#5200's ci/* + self-healing/auto-* watchdog scan; extending it is a separate change. bug-fixer stays deferred (tracked by #5199). |
