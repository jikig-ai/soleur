---
title: "Compaction state lives in the transcript, not a counter file — and a local SOLEUR_* marker never reaches Better Stack"
date: 2026-09-18
category: workflow-patterns
tags: [compaction, hooks, postcompact, sessionstart, transcript, telemetry, brainstorm, session-manifest]
issue: 8323
branch: feat-compaction-aware-session-hooks
---

# Learning: compaction state lives in the transcript, not a counter file

## Problem

Brainstorming a "recommend a fresh session only when the evidence says so" gate on top of Claude Code 2.1.76's `PostCompact` hook (anthropics/claude-code#14258), the first design was stateful: `PostCompact` writes a per-session counter, `SessionStart:compact` reads it. Two premises behind it were wrong.

1. The obvious counter host, `.claude/.session-manifests/<sid>.json`, is repo-side (bound in `.claude/settings.json`, not the plugin), gitignored, absent for marketplace installs, and **overwritten** by `session-rules-loader.sh` on every `SessionStart` — including the `compact` source the counter would be read on.
2. A deferred "ship a `SOLEUR_COMPACTION` marker to Better Stack" follow-up assumed local `SOLEUR_*` stdout markers reach Better Stack. They do not: `rule-incident-marker-capture.sh` writes them to the gitignored `.claude/.rule-incidents.jsonl`, `rule-metrics-aggregate.sh` rolls that into `knowledge-base/project/rule-metrics.json`, and `scripts/betterstack-query.sh` reads the *production Vector* source only.

## Solution

Read the session transcript. Every compaction is a `{"type":"system","subtype":"compact_boundary"}` record carrying `compactMetadata.{trigger, preTokens, postTokens, cumulativeDroppedTokens, durationMs}` (verified on a live transcript: `auto`, 1,006,181 → 105,006), and every skill call is a `Skill` tool-use with `"skill":"soleur:<name>"`. `SessionStart:compact` receives `transcript_path`, so count/last-trigger/token-ratio/current-phase are all one bounded `grep` away — no store, no ordering dependency between `PostCompact` and `SessionStart:compact` (undocumented), no `.gitignore` entry the plugin cannot add to a user's repo. `PostCompact` is only needed for what nothing else has: `compact_summary` on stdin.

The telemetry follow-up (#8324) was re-filed as a local-ledger metric following the `incidents.sh` → `rule-metrics-aggregate.sh` pattern; the CLO note that a Jikigai-operated sink would contradict privacy policy §4.1 became moot.

## Key Insight

Before designing a state store for a harness lifecycle event, check whether the harness already persists that state somewhere a hook can read — Claude Code's transcript is an append-only event log the hooks receive a path to. And before naming a telemetry *sink* in a follow-up, grep the *consumer* (`betterstack-query.sh`) not the *producer* (`SOLEUR_RULE_APPLIED` echo sites): a marker's existence says nothing about where it lands.

## Session Errors

1. **Asked the operator to pick the fresh-session trigger rule** — `pre-ask-technical-fork-gate.sh` blocked the AskUserQuestion. Recovery: decided the rule (`auto` AND (2nd+ auto-compaction OR post/pre > 0.15)) and recorded it as a Key Decision. **Prevention:** a decision rule with numeric thresholds is a technical fork; present it as a decision, ask only about scope/authorization (`hr-technical-fork-is-not-an-operator-question`).
2. **`gh issue create --body-file` blocked because the heredoc that wrote the body and the `gh` call were one compound Bash command** — the filing gate reads the file at PreToolUse time, before the heredoc has run, and the block aborts the whole command so the file is never written either. Recovery: wrote the body with the Write tool, then ran `gh` separately. **Prevention:** write the body file in its own tool call; never `cat > body.md <<EOF … EOF && gh issue create --body-file body.md`. Routed as a bullet to brainstorm SKILL.md Phase 3.6.
3. **Filing gate rejected prose `User-Impact:`/`Fix-Size:` lines** — needs a *named* surface (route/page/CLI command) and a *measured* `N lines / M files`. Recovery: rewrote both lines. **Prevention:** copy the gate's two-line shape verbatim; "a founder gets a better prompt" is not a named surface.
4. **Wrong telemetry-sink premise** (markers → Better Stack) in the go-route summary and the CLO prompt. Recovery: repo-research corrected it; brainstorm records the reconciliation. **Prevention:** grep the consumer before naming a sink (`hr-verify-repo-capability-claim-before-assert`).
5. **`CLAUDE_PLUGIN_ROOT` unset at session start** → readiness probe fell back to `plugin-root-unverified` (known, #7442); Playwright MCP failed to connect (unused). **Prevention:** none new — both already tracked/benign.
