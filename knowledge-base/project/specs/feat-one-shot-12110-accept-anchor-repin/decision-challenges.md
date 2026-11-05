---
title: "Decision challenges — feat-one-shot-12110-accept-anchor-repin"
date: 2026-11-05
branch: feat-one-shot-12110-accept-anchor-repin
issue: 12110
---

# Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Disposition of the 3 `new-pair` findings — uniform accept rows vs uniform narrow `glob:` edges vs per-suite-convention split (`plugins/soleur`→`glob:scripts/*sentry-issue.sh` edge, `tests/hooks/emissions`→4 accept rows) | technical | pending - assumed: split disposition. `plugins/soleur` arm declares the narrow glob (the array's post-PR5d convention: four sibling mention-pair globs citing "every boundary line anchored on >8-commits/90d file — accept rows refused", including the sibling script `betterstack-query.sh` at test-affected-paths.sh:1306; components.test.ts measures 26 commits/90d and its vendor-assertion block is designed to grow per vendor — accept rows there would re-stale on the next vendor PR and reproduce this issue). `tests/hooks/emissions` arm takes accept rows (the suite's established convention: 10 live rows anchored on the same file, citing test_hook_emissions.sh:161's synthetic command-string reach). Alternatives enumerated with exact row/member text in plan Phase 2 steps 4-5 so either flip is executable. |
| Issue body's proposed mechanism ("re-pin the stale accept rows' anchor SHAs to the commits that last touched the referenced files, or regenerate the accept file") | technical | pending - assumed: descoped (recorded as `descoped` in the plan's Scope Check). Impossible as stated: anchors are sha256 content prefixes over whitespace-collapsed lines, not git SHAs (`ci-pr-affected-replay.py:125`); `stale-accept` rows are delete-only by the script's own remedy; no "regenerate accept file" command exists (`--print-baseline` is prune-only and writes the baseline). |
| Brand-survival threshold `none` on a CI-oracle repair | taste | assumed: `none` — diff is exemption rows / a declared edge inside repo-internal test-selection machinery; no user-facing artifact, no regulated-data surface. Challengeable per the plan's User-Brand Impact section. |
| Advisor consult + plan-review panel (soleur:plan Step 4.5, Plan Review stage) | technical | assumed: skipped — no agent-spawn capability inside this subagent (Devin CLI Grok-style contract). Orchestrator self-review applied instead; coverage disclosure recorded in the Session Summary rather than claimed as an independent panel. |

## Not Yet Specified candidates

- None. The fix is fully specified by the ratchet's own remedy classes.
