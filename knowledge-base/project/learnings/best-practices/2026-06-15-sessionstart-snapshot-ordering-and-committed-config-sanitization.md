---
title: "SessionStart snapshot ordering, committed-config sanitization, and bash-test RED-abort traps"
date: 2026-06-15
issue: 5319
pr: 5332
category: best-practices
tags: [session-rules-loader, bash, hooks, test-authoring, set-e, pipefail, prompt-injection, jq]
---

# SessionStart snapshot ordering, committed-config sanitization, and bash-test RED-abort traps

## Problem

#5319 extended `.claude/hooks/session-rules-loader.sh` to inject a `[session-context]`
snapshot (branch | dirty count, worktree path, MCP roster) into `additionalContext`.
Three non-obvious traps surfaced during implementation + multi-agent review.

## Key Insights

### 1. Compute a `git status --porcelain` dirty count BEFORE the hook writes anything to the tree

The SessionStart hook writes `.claude/.session-manifests/<id>.json` mid-run. If the
dirty-count snapshot is computed *after* that write, the fresh `.session-manifests/`
dir counts as an untracked entry and inflates the count by 1 in any tree where it is
not gitignored. It IS gitignored in this repo (root `.gitignore:97`), so production is
safe — but the test fixture (`setup_repo`) has no gitignore, so a post-manifest dirty
count would read N+1 there. Fix: compute the snapshot variables right after the
STAMP/HINT block (before `mkdir -p "$MANIFEST_DIR"`), then place the rendered block
into `OUT_BODY` at the desired envelope position. Computation order ≠ envelope order.

### 2. Committed-config content that flows into agent context needs a control-char clamp

`.mcp.json` / `plugin.json` server names are arbitrary JSON-object keys — they may
legally contain newlines and control chars. Unsanitized, an embedded newline splits one
server into two roster entries (and a newline in the worktree path could shift the
load-bearing "session-context on envelope lines 4-6" invariant). The hook already treats
committed content as a prompt-injection surface (it rejects symlinked sidecars), so the
roster read must match that posture: strip control chars **per key** with
`jq -r 'keys[] | gsub("[[:cntrl:]]";"")'` (per-key, NOT on the whole stream — a
whole-stream `tr -d '\n'` would collapse all server names onto one line and break
sort/paste). Clamp the displayed worktree path with `tr -d '\000-\037'` on a
display-only copy (keep `REPO_ROOT` verbatim — it is reused for the manifest path + HINT).
Printable rule-mimicking text in a key (`[id: hr-fake] …`) is inherent to displaying any
committed content and is accepted within the existing committed-config trust model
(same as a malicious `AGENTS.core.md`), so the clamp targets structure (control chars),
not printable text.

### 3. `paste -sd,` already collapses an embedded-newline key into a comma-join

Empirically: `jq -r keys[]` on a key `"a\nb"` emits two physical lines; `sort -u | paste -sd, -`
then joins ALL lines with commas, so the newline becomes a comma (the key splits into two
roster entries `a` and `b`) rather than a physical line-break in the output. So MCP_SERVERS
itself never injects extra envelope lines — but it does pollute the roster with split
fragments, which the per-key `gsub` (insight #2) fixes cleanly.

### 4. In a `set -euo pipefail` bash test harness, grep-extraction ASSIGNMENTS abort on no-match (RED)

`var=$(printf '%s' "$x" | grep -F 'pat' | head -1)` aborts the whole script under
`set -e` + `pipefail` when grep matches nothing — pipefail propagates grep's exit-1 and the
failing command-sub in *assignment position* trips `set -e`. This is exactly the RED state of
a new test (the feature output does not exist yet), so the suite dies after the first new
test instead of running to a clean `N/N` RED count. Fix: append `|| true` to every
grep-extraction assignment whose match may legitimately be empty
(`var=$(… | head -1 || true)`). (Note: this is distinct from the *production hook*, where
`set -e` is deliberately OFF and assignment-position command-subs are ERR-exempt — there the
`|| true` guards are defense-in-depth, not load-bearing. Don't conflate the two contexts when
writing comments: an AC comment claiming a `|| true` is "load-bearing" was corrected at review.)

### 5. Build control-char JSON test fixtures with `jq -nc`, never hand-written `printf`

A literal control byte (e.g. `0x02`) inside a JSON string is INVALID JSON — jq rejects it
silently (exit 5, no stdout), so the fixture reads as empty and the test fails with a
confusing "(none)". Hand-editing such a fixture is also fragile: the Edit tool mangled
``/`\n` escapes ("String to replace not found"). Generate the fixture with
`jq -nc '{mcpServers:{"ab\ninjected":{}}}'` — jq emits valid JSON with the `\n` properly
escaped, and the consuming hook parses the key as containing a real newline. No literal
control bytes ever touch the source file.

## Session Errors

1. **RED suite aborted under `set -e`+`pipefail`** — grep-extraction assignments died on no-match. Recovery: `|| true` on each. Prevention: insight #4 (route to test-authoring guidance).
2. **Stray `0x02` byte in AC11 fixture → invalid JSON → jq `(none)`** — Recovery: rebuilt the fixture via `jq -nc`. Prevention: insight #5.
3. **Edit tool failed to match `\u`/`\n`-bearing lines** — Recovery: edited comment-only lines + python byte-level rewrite. Prevention: for control-char source edits, regenerate the line programmatically rather than string-matching escapes.
4. **AC10 comment overclaimed `|| true` as load-bearing** — Recovery: review (test-design-reviewer) caught it; corrected test + plan comments. Prevention: insight #4 (the production hook has `set -e` OFF; assignment command-subs are ERR-exempt).

## Tags
category: best-practices
module: session-rules-loader
