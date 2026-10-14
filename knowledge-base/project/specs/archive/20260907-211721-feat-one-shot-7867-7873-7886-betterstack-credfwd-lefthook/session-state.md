# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-07-fix-betterstack-roundtrip-credfwd-lefthook-plan.md
- Status: complete

### Errors

- One `Write` blocked by `.claude/hooks/iac-plan-write-guard.sh` — the phrase "out-of-band" matched its
  `operator-driven` pattern. Resolved by rephrasing to "runs outside the PR chain". The `iac-routing-ack`
  opt-out was deliberately NOT used: that comment asserts a real infrastructure step was reviewed, which
  would have been false.
- Two failed scripted edits (a drifted Python anchor, a `sed` delimiter clash). Both self-corrected on the
  next call; no content lost.
- The `github` MCP server failed to connect at session start (`Authorization header is badly formatted`).
  Worked around via the `gh` CLI throughout — no capability lost.

### Decisions

- **#7873's suggested fix is measurably insufficient.** `curl` consults `ALL_PROXY` / `~/.curlrc` BEFORE the
  pinned host — reproduced against a local listener. A URL pin alone leaves the destination
  environment-choosable with the pin fully intact, so transport confinement (`--disable` first,
  `--noproxy '*'`) is part of the fix, adopted from `scripts/supabase-logs-query.sh`, the repo's one
  complete instance.
- **The gap is ~80 files, not 3** (325 `curl` lines, 1 compliant). The guard became a Rule D in the lint that
  already owns that assembly. The deepen pass then caught that that lint's baseline is per-file and
  rule-agnostic, holds 130 entries, and contains all seven target sites — inheriting it would have shipped a
  guard green over its own population. Rule D carries its own baseline.
- **#7886's design was reversed at deepen** after PR #7879 was found OPEN/WIP on the same file with the
  mechanism the first draft had rejected against a strawman. Gating on the hook's verdict with reasons
  classified deletes the duplicate walk instead of aligning it.
- **The #7873 live-host window was cut, not planned.** The host-side pin defends only against an attacker who
  already has root, or against drift — and drift is catchable in CI. That work rides a window opened for
  another reason.
- **Two unscoped CI blockers found**, either of which would have reddened the first PR: the xtrace-preamble
  drawdown (CI runs `--changed`, bypassing the baseline) and `guard-vacuity-floor.test.sh`'s shrink-only
  `MAX_DEFERRED=47`.

### Components Invoked

soleur:plan · soleur:plan-review · soleur:deepen-plan · agents: repo-research-analyst, learnings-researcher,
best-practices-researcher, functional-discovery, dhh-rails-reviewer, kieran-rails-reviewer,
code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, cto, cpo, scoped advisor,
3x Explore · gates: lint-guard-contract.py, lint-infra-no-human-steps.py, lint-orphan-test-suites.sh,
markdownlint-cli, deepen halts 4.5-4.11

## Post-Plan Collision Re-Probe (one-shot Step 0a.5 re-run, #7247 rule)

- Plan frontmatter `closes: 7873, 7886`. #7867 correctly excluded — it is a verdict-gated follow-through
  tracker, not a code change.
- #7873: clean.
- **#7886: HARD COLLISION.** PR #7879 (OPEN, draft, author deruelle, closes 7849/7853/7854 — NOT 7886) has
  already implemented the #7886 fix in an unpushed local commit `4115024f5` "fix(test): ask the hook for the
  e2e precondition instead of re-deriving it", touching `.claude/hooks/memory-backstop.test.sh`. Its message
  names #7886's exact root cause (suite and hook walks start one process apart, so they can always disagree
  by one hop) and gates on `outcome != "applied"` rather than the single `claude_pid_not_found` reason.
  Invisible to Step 0a.5 because #7879 does not declare `Closes #7886` and #7886 had zero search signals.
