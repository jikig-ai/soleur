---
title: "PR-1 per-cron containment re-triage (evidence-first, AC1)"
issue: "#5046"
branch: feat-tier2-cron-egress-firewall
created: 2026-06-09
status: analysis-complete
---

# PR-1 Cron Re-Triage — allowlistable vs needs-firewall (AC1)

Evidence from reading each cron's prompt bash surface (worktree, 2026-06-09). The #5018 hook
(`cron-bash-allowlist-hook.mjs`) denies, **regardless of the per-cron allowlist**: secret-reads,
egress (`curl`/`wget`), interpreters (`npx`/`node`/`bash <script>`), shell **pipes**, command
**substitution** `$(...)`, and arg-injection (`--body-file @`). So "allowlistable" = the cron's
REQUIRED surface is a finite set of `gh`/`git` sub-command **prefixes** with NO dependency on a
denied construct.

## Classification

| cron | invokes | bash surface | denied-construct dependency | verdict |
|---|---|---|---|---|
| **cron-bug-fixer** | /soleur:fix-issue | `gh api repos/…`, `gh issue create`, `gh pr create/edit/view/list`, `gh label …` | none | **ALLOWLISTABLE** ✅ (cleanest; CPO #1) |
| cron-agent-native-audit | /soleur:agent-native-audit | `gh issue list/create` + `gh issue list … \| wc -l` (cap) | **pipe** (`\| wc -l`) | allowlistable **IFF** cap-count works in-context (verify prompt) ⚠️ |
| cron-legal-audit | /soleur:legal-audit | `gh issue list/create` + `gh issue list … \| wc -l` (cap) | **pipe** (`\| wc -l`) | allowlistable **IFF** cap-count works in-context (verify prompt) ⚠️ |
| cron-campaign-calendar | /soleur:campaign-calendar | gh pr create/merge, git config/add/checkout -b/commit/push | `date -u`, dynamic `checkout -b`, `gh pr merge --auto` | needs-firewall |
| cron-community-monitor | (inline) | gh pr/issue/api, git | `bash community-router.sh`, pipes, `$()` | needs-firewall |
| cron-competitive-analysis | /soleur:competitive-analysis | gh pr create/merge, git | `date -u`, dynamic `checkout -b` | needs-firewall |
| cron-content-generator | /soleur:content-writer + /soleur:social-distribute + /soleur:growth | gh pr, git | `npx @11ty/eleventy`, `date -u`, `git diff --cached --quiet \| exit` | needs-firewall |
| cron-growth-audit | /soleur:growth + /soleur:seo-aeo | gh pr, git | `date -u`, dynamic `checkout -b` | needs-firewall |
| cron-growth-execution | /soleur:growth | gh pr, git | `npx @11ty/eleventy`, `bash validate-seo.sh`, `date -u` | needs-firewall |
| cron-seo-aeo-audit | /soleur:seo-aeo | gh pr create/merge, git | `date -u`, dynamic `checkout -b` | needs-firewall |
| cron-ux-audit | /soleur:ux-audit | (none) | Playwright MCP, Supabase `fetch` POST, file I/O | needs-firewall |

## How this inverts the plan's hypotheses

- The plan guessed **bug-fixer** might be needs-firewall (it creates PRs/runs tests). Evidence:
  `fix-issue` does its PR work through `gh` verbs only — **cleanly allowlistable**, and it's CPO's
  #1 restore priority. Good outcome: wave-1 can lead with it.
- The plan guessed the read-heavy audit crons (growth/competitive/seo/ux/campaign) were
  allowlistable. Evidence: they all build branches with `date -u` + dynamic `git checkout -b` and
  several run `npx @11ty/eleventy` / `bash <script>` — **needs-firewall**, restored in PR-2.
- Net allowlistable subset for PR-1: **bug-fixer** (confirmed) + agent-native-audit + legal-audit
  (pending the pipe-independence check below).

## Open verification before restore (the pipe nuance)

`agent-native-audit` and `legal-audit` use `gh issue list … | wc -l` for issue-cap enforcement.
The hook denies the pipe. Before restoring them, confirm ONE of:
1. The prompt's cap-count can be satisfied by the agent counting `gh issue list --json number`
   output **in-context** (no shell pipe) — then restore as-is and the agent adapts; OR
2. Edit the prompt to instruct in-context counting (drop the `| wc -l`), so the cap step doesn't
   dead-end on a denied pipe.

`bug-fixer` has no denied-construct dependency → restore without prompt changes.

## Allowlist entries to add (model on `cron-roadmap-review`, `_cron-claude-eval-substrate.ts:139`)

- `cron-bug-fixer`: `gh api repos/jikig-ai/soleur/`, `gh issue list/view/create/edit/close/comment`,
  `gh pr list/view/create/comment/edit`, `gh label list/create/delete`, `git status/add/commit/checkout/switch/push/rev-parse`. (Verify exact verbs against the fix-issue skill body at implementation.)
- `cron-agent-native-audit` / `cron-legal-audit`: `gh issue list/view/create/edit/comment` only
  (no PR/git — their prompts forbid commits). Pending the pipe check.

Token note (Phase 1.3): all three restored crons need the minted token to carry
`pull_requests:write` (bug-fixer creates PRs) + `issues:write` + `contents:write`, repo-scoped to
soleur — see plan Phase 1.3 / AC3.
