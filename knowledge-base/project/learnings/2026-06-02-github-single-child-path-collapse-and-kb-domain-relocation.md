---
title: "GitHub single-child path-collapse looks like a stray dir; KB domain relocation + path-segment regex pitfall"
date: 2026-06-02
category: workflow-patterns
tags: [github-ui, knowledge-base, taxonomy, bash, hooks, code-review]
issue: null
pr: 4812
---

# Learning: GitHub single-child path-collapse, KB domain relocation, and the path-segment regex pitfall

## Problem

A screenshot of the GitHub file browser showed `security/skill-overrides` as an
apparently anomalous top-level entry in `knowledge-base/`, alongside
`sales/battlecards` and `support/community`. The premise handed to the workflow
was "a stray dir got created outside the main domains — remove it."

Investigation contradicted the premise: `knowledge-base/security/skill-overrides/`
was a **deliberate, load-bearing** directory (the GDPR Art. 32 override-evidence
location for the skill-security-scan advisory gate, added by PR #3524), wired into
hooks, CI workflows, and skill scripts, with an explicit repo-lifetime retention
policy ("must NOT bulk-delete"). Removing it would have silently disabled a
security gate.

## Key Insight

**GitHub's file browser collapses single-child directory paths.** A directory
that contains exactly one subdirectory (and nothing else at that level) renders
as a collapsed `parent/child` entry — `security/` containing only
`skill-overrides/` shows as `security/skill-overrides`. This is standard GitHub
UI, NOT evidence of a misplaced or compound directory. `sales/battlecards` and
`support/community` in the same screenshot were the same artifact. The Soleur
web-app file tree (which does NOT collapse) rendered them correctly as plain
folders.

**Before deleting/moving a directory described as "stray," grep for its
references.** `grep -rn "<path>"` surfaced ~16 live wiring sites (hooks, CI,
scripts) + a documented retention policy. The contradiction between "stray" and
"load-bearing GDPR evidence dir" is the signal to surface findings and ask,
not to proceed with deletion.

## Resolution

Rather than delete, the directory was **relocated** under an existing sanctioned
domain (`knowledge-base/engineering/security/skill-overrides/`, via history-
preserving `git mv`), removing the top-level `security/` anomaly while keeping
the path semantics. All live references were rewritten; 5 dated historical
artifacts (brainstorm/plan/spec/learning) were left untouched (point-in-time
records). An advisory `kb-domain-allowlist-guard.sh` PreToolUse hook was added to
flag future new top-level KB dirs outside the sanctioned set (tier `ask`, not
`deny` — adding a domain is legitimate-but-rare).

## Session Errors

1. **Planning subagent: Task fan-out unavailable + early write-guard/CWD-reset hiccups.** — Recovery: deepen gates run inline against the codebase; absolute paths used. — Prevention: already covered by the one-shot CWD-verification step and `hr-when-in-a-worktree-never-read-from-bare`.
2. **Wrong self-test path** (`…/references/test-fixtures/run-self-test.sh` → exit 127; real path `…/scripts/run-self-test.sh`). — Recovery: `find … -name run-self-test.sh`. — Prevention: `find`/`ls` to locate a script before invoking when its path is inferred from an `ls -R` listing (the `dir:` header in `ls -R` output is the parent, not a path prefix).
3. **Bash path-segment regex pitfall (hook T8 RED).** A regex of the form `(^|.*/)knowledge-base/([^/]+)` fails to match a path that appears mid-command with no leading `/` (e.g. `mkdir -p knowledge-base/observability` — the `.*/` alternative needs a slash before `knowledge-base`, and `^` needs the string to start with it). — Recovery: match the segment anywhere (`knowledge-base/([^/[:space:]"']+)`) and resolve the directory prefix separately via `${TARGET%%knowledge-base/*}`. — Prevention: when extracting a path segment that can appear in a bash command string (not just a bare path), do NOT anchor the prefix on a slash boundary; the test harness with a Bash-command case (`mkdir`/`cat >`) catches this.
4. **Review found 3 P2s in the new hook** (out-of-enum `emit_incident` event_type `ask` vs `{deny,bypass,applied,warn}`; allowlist duplicated as a prose literal in the reason string; on-disk-existence branch uncovered by any test). — Recovery: fixed inline (event_type → `warn`; reason list derived from the array via `jq --arg`; added test T10). — Prevention: when adding an `emit_incident` call, use a documented `event_type` from `lib/incidents.sh` (the harness `permissionDecision` is a separate field); single-source any list that also appears in a user-facing message; ensure each code branch has at least one test that reaches it (T3 short-circuited before the existence branch).

## Tags
category: workflow-patterns
module: knowledge-base, .claude/hooks
