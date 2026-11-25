# Learning: new-harness brainstorm — a research subagent invented symbols it never read, and a greenfield feature cannot satisfy the issue gate's measured size line

## Problem

Brainstorm for Mistral Large 4 + Mistral Vibe support (#9648) ran six parallel agents. The repo-research agent returned a confident gap table that was wrong in four checkable ways: it listed `"cursor"` as a member of the `Harness` union (the union on main is `claude|grok|codex|devin|unknown`, `plugins/soleur/lib/harness.ts`), named `VIBE_HOME`/`VIBE_ROOT` env markers that no source supports, described Vibe skills as TOML (Vibe loads `SKILL.md`), and reported 51/44 files for the Grok/Codex harness PRs (measured 49/42 via `gh pr view --json files`). The CTO, reading the same file directly, had the union right. Separately, the first `gh issue create` for the umbrella was refused by the filing gate: the `meta/machinery` label is defined as "not a user-facing surface" (wrong for a user-facing harness), and the `User-Impact:`/`Fix-Size:` exit requires a *measured* `N lines / M files` that a feature with no diff does not have.

## Solution

- Re-derived every subagent claim before it entered the spec: read the union directly, re-ran the PR file counts, and recorded the corrections under `## Session Errors` of the brainstorm doc. Unmeasured items (Vibe env markers, hook blocking, skill frontmatter compatibility) went into Open Questions as "measure on a real install", not into the spec as facts.
- For the issue gate, took exit 2 honestly: `User-Impact:` named the user surface (`/soleur:go` and skills inside Vibe, plus the provider-key entry) and `Fix-Size:` carried the measured size of the comparable merged Codex harness PR (#8507: 1208 lines / 42 files), with a plain-language note in the body that it is a reference measurement, not a measurement of this work.

## Key Insight

A research agent asked to "map the gap" for an external product will fill the gaps in its own knowledge with plausible symbols (env-var names, enum members, file formats). Plausibility is the failure signature: every invented item was shaped like a real one. The cheap control is to read the one file that defines the closed set (here the `Harness` union) and to grep any identifier the agent presents as existing in the repo. For the issue gate: when there is no diff, a measured size can only come from a comparable merged PR, and the body must say so, otherwise the line asserts a measurement that was never taken.

## Session Errors

1. **repo-research invented a `cursor` union member, `VIBE_*` env markers and TOML skills; file counts 51/44 vs actual 49/42** — Recovery: read `harness.ts`, re-ran `gh pr view --json files` — Prevention: brainstorm Phase 1.1 already says re-derive subagent counts and grep claimed symbols; add the closed-set read ("read the union/registry that defines the set") when a leader and a research agent disagree.
2. **`gh issue create` blocked by the filing gate (no user-visible consequence named / Fix-Size unmeasured)** — Recovery: user-impact exit with the comparable PR's measured size plus a disclosure line — Prevention: proposed one-line Sharp Edge for brainstorm Phase 3.6: "greenfield user-facing feature with no diff: measure the comparable merged PR, state in the body that Fix-Size is a reference, never use `meta/machinery` for a user-facing surface".
3. **WebFetch summarizer misdated Mistral Medium 3.5 (April 2025 vs April 2026)** — Recovery: cross-checked against the search result's own date before use — Prevention: treat a fetch summary's dates as a claim; corroborate with a second source.
4. **Stop hook fired twice when turns ended with a stated future action while background agents ran** — Recovery: ended with `<stop>BLOCKED: …</stop>` naming the pending agents, and did independent work (worktree, draft PR) between notifications — Prevention: when waiting on background agents, do the independent next step or declare BLOCKED explicitly.

## Tags

category: workflow-issues
module: brainstorm, harness-parity
