# Session state: feat-one-shot-argv-bearer-sweep-tier3

## Plan phase

- Plan file: `knowledge-base/project/plans/2026-10-07-fix-argv-bearer-sweep-tier3-guard-first-slice-and-review-skill-extraction-plan.md`
- Worktree: `.worktrees/feat-one-shot-argv-bearer-sweep-tier3`; draft PR #9674; tracker #9597; Ref #7797.
- Decisions recorded in the plan: D1 (lint: YAML arm by PyYAML `run:` extraction plus raw lines for cloud-init, non-Bearer vocabulary, no guard-order lint, `--changed` stays `*.sh`), D2 (five slices), D3 (shared helper for workflow YAML), D4 (python3 HMAC from env), D5 (review extraction: whole Defect Classes section), D6 (`Closes` policy).
- Measured, not copied: 55 Bearer hits in 21 YAML files are 35 argv sites in 16 files (11 already stdin, 9 comment or echo); the apply workflow has 6 argv sites, not 12; `cutover-inngest.sh` has 20 HMAC plus CF-Access sites; the widened vocabulary finds 86 sites in 34 files.
- Planning subagent note: one learnings subagent (haiku) returned generic constraints; the decisive facts came from direct measurement. Plan review panel not spawned in this run; `deepen-plan` follows.
- Out of scope, parent-owned: infra apply did not fire after Tier 2 merge (last push run on main 2026-09-27); web-2 tracking (replaced 2026-10-06 19:28Z from `2efc8025ff`).
