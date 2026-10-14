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

## Addendum — 2026-09-18 (#8323 Phase 0 probe): the Solution above is SUPERSEDED

> **Superseded 2026-09-18 (#8323):** this file's title, its `## Solution` and the `## Key Insight`
> assert that the compaction signal can be read from the transcript. The implementation's blocking
> Phase 0 probe measured that it cannot, and the shipped design is a per-session ephemeral ledger.
> The body above is left intact — it is the reasoning as it stood, and the premise it refutes
> (§Problem's two wrong premises) is still correct and still load-bearing.

**What the probe measured** (Claude Code 2.1.273, scratch project, headless
`claude -p --continue "/compact"`; full table in the plan's `## Addendum — 2026-09-18`):

- At `SessionStart:compact` the **just-fired** compaction's `compact_boundary` is **not on disk**.
  Measured twice — compaction #1 read `count=0` with 1 present afterwards, compaction #2 read
  `count=1` with 2 present. The boundary's own `timestamp` *precedes* the hook fire, so the record
  is in memory and flushes after the hook returns. `PostCompact`, 100 ms later, reads the same
  lagging value.
- The `SessionStart` envelope carries **no `trigger`** (`PreCompact` has `trigger`; `SessionStart`
  has `source`), so the last on-disk boundary yields the *previous* compaction's trigger.
- `PreCompact` firing does **not** imply a compaction happened: 3 fires produced 2 boundaries,
  because a `/compact` with nothing left to compact fires `PreCompact` and then no
  `SessionStart:compact`.

So "count/last-trigger/token-ratio are all one bounded `grep` away" is false in the count and the
trigger, and the phase clause was separately deleted by the plan review. The token-ratio clause was
deleted too (the threshold sat above the only real measurement).

**What shipped instead:** a per-session ledger under `TMPDIR`, pending-then-commit —
`PreCompact` overwrites one pending slot, `SessionStart:compact` commits it as one line and counts,
and `SessionStart:startup|resume|clear` truncates. This is **not** the counter store §Problem
rejected: that one lived in the user's repository and needed an un-addable `.gitignore` entry; this
is machine-local, disposable and age-reaped. See **ADR-227**.

**The Key Insight survives, with its second clause corrected.** "Check whether the harness already
persists that state somewhere a hook can read" is still the right first question. The correction is
that *persisted* and *readable at the moment you need it* are different properties, and only a
probe distinguishes them — a transcript can be an append-only log of exactly the right events and
still be one flush behind at the one instant the hook runs.

**Prevention:** when a design depends on a harness having written something by the time a hook
fires, treat the write ORDERING as a separate claim from the record's existence and probe it
before implementing. The cheapest form is what Phase 0 did: bind a marker hook in a throwaway
project, drive the event headlessly, and log what the hook can actually see — no operator step, a
few minutes, and it falsified the design before a line of it was written.
