---
title: "PR-1 per-cron containment re-triage (evidence-first, AC1)"
issue: "#5046"
branch: feat-tier2-cron-egress-firewall
created: 2026-06-09
status: superseded-by-work-phase-reverification
---

# PR-1 Cron Re-Triage — allowlistable vs needs-firewall (AC1)

> **Outcome (work phase, 2026-06-09): ZERO crons restorable under the #5018 hook.**
> The initial analysis below classified bug-fixer / agent-native-audit / legal-audit as
> allowlistable on a **surface read of their top-level `gh`/`git` verbs**. Tracing the actual
> skill bodies the crons invoke proved all three depend on **hook-denied tool classes or shell
> constructs**. PR-1 therefore restores **no crons** and ships the least-privilege token narrowing
> only. All 11 stay deferred to PR-2 (the egress firewall lets the hook relax `Task`/`Skill`/egress).
> See `## Work-phase re-verification (corrects AC1)`.

Evidence from reading each cron's prompt bash surface (worktree, 2026-06-09). The #5018 hook
(`cron-bash-allowlist-hook.mjs`) denies, **regardless of the per-cron allowlist**: secret-reads,
egress (`curl`/`wget`), interpreters (`npx`/`node`/`bash <script>`), shell **pipes**, command
**substitution** `$(...)`, arg-injection (`--body-file @`), AND every non-Bash tool class except
Read/Glob/Grep/Write/Edit/ToolSearch/TodoWrite — notably **`Task` (sub-agents) and `Skill` are
denied by the catch-all** (`decide()` default branch; the hook author's comment: *"sub-agent
classes are denied until the Tier-2 firewall lands; no Tier-1 cron needs these"*). So
"allowlistable" = the cron's REQUIRED surface is a finite set of `gh`/`git` sub-command **prefixes**
with NO dependency on a denied construct AND no dependency on `Task`/`Skill`/egress.

## Classification (corrected at work phase)

| cron | invokes | actual surface (traced into the skill body) | denied dependency | verdict |
|---|---|---|---|---|
| cron-bug-fixer | /soleur:fix-issue | fix-issue Ph2 `node -e "$(…)"` + `eval "$TEST_CMD" \| tail`; Ph3 `bash …/worktree-manager.sh` / `git worktree add`; Ph5 `gh pr create --body "$(cat <<EOF)"`; Ph6 `git branch -D` | **`$()`, pipe, `eval`, `node -e`, `bash <script>`, `git worktree`/`git branch`** | **needs-firewall** (original Tier-1 classification was right) |
| cron-agent-native-audit | /soleur:agent-native-audit | SKILL.md:37 *"Launch 8 parallel sub-agents using the **Task** tool"* | **`Task` tool** (+ pipe `\| wc -l`) | **needs-firewall** |
| cron-legal-audit | /soleur:legal-audit | SKILL.md:44 *"Invoke the legal-compliance-auditor agent via the **Task** tool"* | **`Task` tool** (+ pipe `\| wc -l`) | **needs-firewall** |
| cron-campaign-calendar | /soleur:campaign-calendar | gh pr create/merge, git config/add/checkout -b/commit/push | `date -u`, dynamic `checkout -b`, `gh pr merge --auto` | needs-firewall |
| cron-community-monitor | (inline) | gh pr/issue/api, git | `bash community-router.sh`, pipes, `$()` | needs-firewall |
| cron-competitive-analysis | /soleur:competitive-analysis | gh pr create/merge, git | `date -u`, dynamic `checkout -b` | needs-firewall |
| cron-content-generator | /soleur:content-writer + /soleur:social-distribute + /soleur:growth | gh pr, git | `npx @11ty/eleventy`, `date -u`, `git diff --cached --quiet \| exit` | needs-firewall |
| cron-growth-audit | /soleur:growth + /soleur:seo-aeo | gh pr, git | `date -u`, dynamic `checkout -b` | needs-firewall |
| cron-growth-execution | /soleur:growth | gh pr, git | `npx @11ty/eleventy`, `bash validate-seo.sh`, `date -u` | needs-firewall |
| cron-seo-aeo-audit | /soleur:seo-aeo | gh pr create/merge, git | `date -u`, dynamic `checkout -b` | needs-firewall |
| cron-ux-audit | /soleur:ux-audit | (none) | Playwright MCP, Supabase `fetch` POST, file I/O | needs-firewall |

## Work-phase re-verification (corrects AC1)

The initial analysis (above the corrected table) over-credited three crons. The reference baseline
is **cron-roadmap-review** — the one validated Tier-1 cron — which deliberately *"invokes no
/soleur:* skill"* (cron-roadmap-review.ts:43) and uses `--allowedTools
Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch` (**no `Task`, no `Skill`**). That is the shape
the hook permits.

- **agent-native-audit / legal-audit** structurally require the **`Task` tool** (8 sub-agents / the
  legal-compliance-auditor). The hook's `decide()` routes `Task` to the catch-all `deny`. Even with
  a perfect bash allowlist, their core mechanism is denied → degraded/empty output → a restored cron
  that silently fails (the single-user incident this plan exists to prevent). The `| wc -l` pipe was
  a red herring; `Task` is the load-bearing blocker.
- **bug-fixer** runs `/soleur:fix-issue`, whose Phase 2–6 bash (traced from the SKILL.md) depends on
  command substitution `$(…)`, pipes (`eval "$TEST_CMD" | tail`), `node -e`, `bash <script>`
  (`worktree-manager.sh`), and `git worktree`/`git branch` — all hook-denied. You cannot allowlist
  your way to a working fix-issue without re-admitting the exfil primitives (`$()`, pipes, `node`),
  which defeats containment. The **original** defer-set rationale (`_cron-shared.ts:183`, "bash that
  cannot be expressed as a finite allowlist") was correct for bug-fixer.

**Net allowlistable subset for PR-1: none.** This realizes plan risk **R3** ("if few of the 11 are
cleanly allowlistable incl. bug-fixer = CPO #1, PR-1's restore scope shrinks… AC1 surfaces this with
evidence rather than discovering it mid-build") and the Phase 1.0 directive ("Do NOT pre-commit the
split… the evidence decides… surface this in the PR body, don't silently reshuffle"). Operator
decision (recorded in the work session): **token-narrowing only**.

`TIER2_DEFERRED_CRONS` is therefore unchanged; no `CRON_BASH_ALLOWLISTS` entries are added.

## What PR-1 ships instead — least-privilege cron token (Phase 1.3 / AC3)

The token narrowing is the salvageable, independently-valuable half of PR-1. It hardens the LIVE
claude-spawning crons that already run agent bash with `GH_TOKEN` in scope, without depending on any
restore:

- `generateInstallationToken` (`github-app.ts`) gains optional `permissions` / `repositories`,
  posted as the access_tokens body, **and folded into the token cache key** — the critical fix: the
  cache was keyed on `installationId` alone, so a narrowed cron token and the broad token the ~10
  interactive/agent callers mint for the SAME installation id would have collided (silent
  over-privilege OR defeated narrowing).
- `mintInstallationToken` (`_cron-shared.ts`) threads the scope through; `DEFAULT_CRON_TOKEN_PERMISSIONS`
  = `{ contents, issues, pull_requests }:write`. **Opt-in per cron, not a blanket default** — the
  workflow-dispatch crons (`actions:write`), pages crons (`pages`), and ruleset-bypass-audit
  (`administration:read`) legitimately need broader scope and pass none → full grant.
- Applied to **cron-daily-triage** and **cron-follow-through-monitor** — the two live claude-spawn
  crons verified to stay within the `{contents,issues,pull_requests}` envelope (allowlisted Bash is
  `gh issue …` only) + repo-scoped to `["soleur"]`. daily-triage reads arbitrary issue bodies (the
  highest prompt-injection surface of any cron), so bounding its token is the highest-value
  narrowing. roadmap-review (unbounded `gh api repos/…` allowlist prefix) and content-publisher /
  content-vendor-drift (`checks:write`) are left broad — a documented follow-up.
