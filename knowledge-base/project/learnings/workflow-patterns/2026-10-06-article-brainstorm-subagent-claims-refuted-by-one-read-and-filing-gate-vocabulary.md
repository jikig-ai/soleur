# Learning: article-review brainstorm — two subagent claims refuted by one read, and the filing gate's hidden vocabulary

## Problem

A brainstorm reviewing an external article ("three layers of AI agent security") against Soleur's own controls fanned out six agents. Two of their confident claims were wrong, and filing the umbrella issue was refused three times before it passed.

## Solution

- Re-derived each load-bearing claim with one command before it shaped scope: `agent-env.ts` (credentials), `plugins/soleur/hooks/hooks.json` (hook set), `git grep` for `SUBPROCESS_ENV_SCRUB` / `ANTHROPIC_BASE_URL` / scanner names, and the raw CrabTrap README for the vendor claim.
- Read the filing gate's predicate in `.claude/hooks/guardrails.sh` instead of guessing a fourth time. Exit 2 needs `User-Impact:` to contain a word from `.claude/hooks/lib/user-surface-taxonomy.txt` (route, endpoint, page, screen, component, button, form, dashboard, CLI command, email, notification, document, report, invoice, digest) plus exactly one measured `Fix-Size: N lines / M files`.

## Key Insight

A subagent's claim about a negative ("not stored in the agent process", "no learnings on approval gates") is the cheapest thing to falsify and the most damaging if wrong. Here the repo-research audit said BYOK keys never reach the agent process; `agent-env.ts` injects `ANTHROPIC_API_KEY`/`CLAUDE_CODE_OAUTH_TOKEN`, `GH_TOKEN` and service tokens into the CLI subprocess. That claim would have removed the epic's headline slice. The same pass also confirmed the article's own vendor claim was wrong (CrabTrap has no human-in-the-loop), so external sources get the same treatment as internal agents.

## Session Errors

1. **Repo-research agent asserted BYOK keys are not in the agent process** — Recovery: read `apps/web-platform/server/agent-env.ts`; the CTO report already had it right — Prevention: already covered by the brainstorm skill's "subagent claim is a claim to re-derive" rule; no change.
2. **Learnings agent asserted no approval-gate learnings exist** — Recovery: `prod-write-defer-gate.sh` and `hr-menu-option-ack-not-prod-write-auth` refute it — Prevention: covered by the same rule; no change.
3. **First CVE-scanner grep was not word-bounded** and matched ~10 unrelated files — Recovery: re-ran with `-w` and found only `dependency-review` — Prevention: use `git grep -w` for tool-name sweeps.
4. **`gh issue create` refused three times** — Recovery: read the gate predicate; User-Impact needed a taxonomy word and Fix-Size a measured count — Prevention: the refusal text does not name the taxonomy file; filed as a tooling issue.
5. **Stop hook fired on a closing line that promised a synthesis while a background agent was still running** — Recovery: ended the turn with `<stop>BLOCKED: …</stop>` naming the pending agent — Prevention: when waiting on a background agent, say the wait explicitly with the stop tag instead of a future-tense promise.
6. **Playwright MCP failed to connect** during the session — Recovery: fact-check used WebSearch/WebFetch instead — Prevention: none (environment).

## Tags

category: workflow-patterns
module: brainstorm
