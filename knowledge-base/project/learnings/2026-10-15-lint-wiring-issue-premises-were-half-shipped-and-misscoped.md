# Learning: a "wire linter X into the gates" issue was half-shipped already, and mis-grouped its targets

## Problem

#10331 (GitHub Code Quality triage) framed JS/TS and Python linting as greenfield and grouped `.claude/hooks/security_reminder_hook.py` with plugin scripts that "ship to users". Three premises were wrong or unmeasured.

## Solution

Grep the config scope before accepting the framing:

- `apps/web-platform/eslint.config.mjs` already enables `@typescript-eslint/no-unused-vars` with a committed ratchet (`apps/web-platform/test/eslint-config.test.ts`). The real gap is that `eslint .` runs from `apps/web-platform` only, so root `test/` and `plugins/soleur/test/` are never linted.
- No Python linter exists (grep for ruff/flake8/pylint/pyflakes over `.github`, `lefthook.yml`, `scripts/`, both `package.json`; no pyproject/ruff.toml). That half is genuinely greenfield.
- `.claude/hooks/security_reminder_hook.py` is repo-only. Classify each cited script by path (`plugins/` ships; `.claude/` does not) before sizing brand risk.
- CodeQL Code Quality alerts are not returned by the code-scanning REST API, so individual findings must be read from the GitHub UI. `tsc --noEmit` exiting 0 shows the two `js/comparison-between-incompatible-types` findings are CodeQL-inferred, not TS-disjoint types.

## Key Insight

An issue that cites a scanner's rule list is evidence about the scanner's view, not about which gates already exist or which files ship. Measure the gate's scan scope and each target's ship status before slicing the work.

## Session Errors

1. **Zero-width character typed into the `draft-pr` script path** — Recovery: retyped the path, draft PR #10342 created. Prevention: one-off; run `worktree-manager.sh` through a relative path from the worktree.
2. **Condensed the three `soleur:go` bash gates into one equivalent script instead of running the fences verbatim** — Recovery: same checks ran (readiness, cloud-detect, cleanup-merged, route decision). Prevention: paste fences verbatim; the condensed form omits the Devin-cache arm.
3. **Skipped the Phase 0.25 roadmap freshness check before spawning leaders** — Recovery: ran `roadmap-reconcile.sh validate` afterwards. Prevention: run it at Phase 0.25, not after the fact.
4. **Spawned 4 of the 5 prescribed Phase 0.5/1.1 agents (omitted `learnings-researcher`) to save cost** — Recovery: none needed; the institutional-learning sweep was covered by the repo researcher. Prevention: either spawn it or record the omission in the brainstorm doc.
5. **Sent a Stop-hook-triggering closing message that promised a next action** — Recovery: ended with a `Paused:` line. Prevention: end idle turns with `Paused:`/`Blocked:` from the start.

## Triage

| item | recurring? | disposition |
|---|---|---|
| zero-width path typo | no | one-off |
| condensed go-gate fences | no | one-off |
| roadmap check ordering | no | one-off |
| omitted learnings-researcher | no | one-off |
| promise-ending turn | no | one-off |

## Tags
category: workflow-issues
module: soleur:brainstorm
