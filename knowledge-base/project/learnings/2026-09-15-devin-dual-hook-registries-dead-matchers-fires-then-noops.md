---
title: Devin loads both hook registries — dead matchers are loaded-not-unloaded, and coincidental twins already double-fire
date: 2026-09-15
category: engineering
tags: [devin, hooks, matcher, tool_name, double-fire, cross-source, two-layer-gate]
symptoms:
  - "23 Bash matcher objects in .claude/settings.json silently never fire under Devin (tool_name is exec)"
  - "guardrails.sh bound on write in BOTH .claude/settings.json and .devin/config.json — cross-source double-fire already live"
  - "widening a matcher to ^(Bash|exec)$ still no-ops: the hook body re-gates tool_name == Bash and exits 0"
module: plugins/soleur
component: hooks
problem_type: integration_issue
resolution_type: config_change
root_cause: config_error
severity: high
issues: [8205, 8155, 8159, 8172]
---

# Learning: Devin dual hook registries — dead matchers and fires-then-no-ops

## Problem

Issue #8205 reported `matcher: "Bash"` in `plugins/soleur/hooks/hooks.json` dead under Devin (shell tool is `exec`). The brainstorm audit found the defect is larger and differently-shaped than the issue framed it:

1. **Loaded, not unloaded.** Devin CLI reads `.claude/settings.json` hooks by default (`read_config_from.claude`, on by default; vendor doc `extensibility/hooks/overview.mdx` "Where Hooks Live"). The matchers are dead *regexes* — the registry loads, nothing matches.
2. **A second registry already exists.** `.devin/config.json` binds `guardrails.sh` on `^exec$` and `^(write|edit|multi_edit|notebook_edit)$`. Devin loads BOTH files with no documented cross-source dedup — so `guardrails.sh` already double-fires on `write`/`ask_user_question` today (the lowercase twins were added for Grok in #8061 and coincidentally match Devin's tool names).
3. **Matcher fix ≠ guard live.** ~10 hook scripts re-gate `tool_name` inside the body (`browser-snapshot-credential-guard.sh:90` `[[ "$TOOL" == "Bash" ]] || exit 0`, `pre-ask-technical-fork-gate.sh:66`, `doppler-secrets-delete-redirect.sh:35`, `post-dispatch-watch-gate.sh:59,64`, etc.). PR #8155 widened the hooks.json matcher to `^(Bash|exec)$` but left the body check — the guard fires then silently exits under Devin. **Fires-then-no-ops** is strictly worse than dead: it looks covered.
4. **The cohort is the mechanism, not the literal.** Write-family matchers (`Write|Edit|MultiEdit|NotebookEdit`), `AskUserQuestion`, `Skill`, `Monitor`, `Task`, `CronCreate`, and `permissions.allow/deny` tool prefixes (`Bash(...)`, `Read(...)`) share the dead-binding class. The existing lowercase `write` twins also over-bind `todo_write` (unanchored substring).
5. **Cloud is a different arm.** The 2026-09-15 probe measured NO repo-level hooks dispatching in Devin Cloud at all — the matcher question is local-CLI only.

## Solution

Per-hook disposition audit, not a sweep: for every registry entry decide bind / register-in-`.devin/config.json` / documented-skip (`reason=no-tool` for tools Devin lacks), per the Grok FR6 precedent. Normalize in-body `tool_name` gates through a single tool-kind mapping in `hook-input.sh`. Assert the matrix with an executable parity test (regex-evaluating assertions per #8155's `test($m)` pattern) — not prose. Anchor the `write` twins (`^write$`) to stop `todo_write` over-binding.

## Key Insight

A hook has THREE places it can silently not run: the registry never loads it (harness doesn't read the file), the matcher never matches (tool_name vocabulary differs), and the body exits 0 (in-script re-gate on the old name). "Fixing the matcher" only addresses layer 2. Audits must enumerate all three layers per hook, and the disposition belongs in a checked-in table asserted by a test — the same "documented skips, not silent offs" rule the Grok parity work established.

Cross-source double-fire is the mirror image: two registries binding the same hook+tool pair is not "extra coverage," it is two invocations. Whichever registry strategy a repo picks, dedup must be treated as cross-source by default.

## Session Errors

1. **Issue filing took 4 attempts.** `gh issue create` inline `--body` failed tokenization; `--body-file /tmp/x.md` rejected (gate can't read /tmp); worktree file rejected by the filing gate (needs `meta/machinery` label, `User-Impact:`/`Fix-Size:` lines, or `Mandated-By: <rule-id>` on its own line). — Recovery: added `Mandated-By: wg-when-deferring-a-capability-create-a` to the body. — Prevention: brainstorm SKILL.md step 7's issue-create template should carry the filing-gate exits (routed as a domain-scoped edit).
2. **`CLAUDE_PLUGIN_ROOT` unset under Devin CLI.** go.md's Step 0.0 probe would degrade to `plugin-root-unverified`; resolved the installed plugin cache path manually. — Prevention: Devin harness adapter docs should name the plugin-cache resolution fallback.
3. **Leader subagents told to `gh issue view` but Explore profile has no exec.** All three domain leaders returned UNVERIFIED caveats; orchestrator re-verified. — Prevention: the domain-config Task Prompt should scope `gh` verification to the orchestrator when the subagent profile lacks shell.
4. **`cleanup-merged` skipped on lock contention** during the session-start preamble (a sibling session held the lock). — Recovery: none needed; worktree list confirmed no merged worktrees pending cleanup. — Prevention: one-off environmental; no action.

## Prevention

- Treat every hook registration as a 3-layer claim: registry-loads × matcher-matches × body-runs. A green test on any one layer is not coverage.
- For a new harness, first measure which registries it loads and whether it aliases tool names (Grok unions, Devin does neither) BEFORE writing bindings.
- Anchor tool-name matchers (`^write$`) — unanchored regexes over-bind (`todo_write`).
- Coverage claims in docs ("Devin supports X") must cite the envelope/tool_name evidence that was measured, or condition on the PR that makes it true.
