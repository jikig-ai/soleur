# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9998-ssh-residence/knowledge-base/project/plans/2026-10-12-fix-provisioner-parity-ssh-residence-plan.md
- Status: complete

### Errors
- No Agent/Task tool in the planning subagent's runtime — every skill-prescribed sub-agent spawn (Phase 1 research fan-out, spec-flow analyzer, scoped advisor, domain leaders, plan-review panel, CTO technical rulings) was performed inline instead. Technical forks recorded as `pending - assumed: <default>` rows in decision-challenges.md; disclosed in the plan's Enhancement Summary and Sharp Edges.
- Plan Review could not run as an agent panel — compensated by full sharp-edges catalogue read, lint-guard-contract.py (pass), markdownlint (0 issues), mechanical deepen-plan halt-gate verification, and live baseline runs of both suites.
- No `git push` performed (constraint); planning commits are local on the branch.

### Decisions
- Issue's "zero SSH terraform_data resources outside server.tf" premise is false — 4 legitimate web-1 dialers exist (root_authorized_keys in ci-ssh-key.tf:68; luks_monitor_token_install, luks_monitor_install, workspaces_boot_unlock_install in workspaces-luks.tf). Fix is a `fleet_elsewhere` residence arm PLUS a per-resource, host-scoped, reason-mandatory `EXT_RESIDENCE` allowance + stale-allowance arm — not a blanket rule.
- Residence scope is any `web-\d+` dialer (superset of declared fleet hosts) — fail-closed for future fleet growth; indirect host spellings (var.web_hosts, locals, literal IPs) named as a deliberate residual gap.
- Battery rows G2-19–G2-22 specified; FLOOR (mutations_run) bumps 58 → 62; stale arm anchors on literal `stale EXT_RESIDENCE entry`.
- §1 census deliberately untouched — extending srv-scoping cut at mechanism-minimality (would red the 4 legitimate one-off dialers' destinations).
- Baselines measured: guard 18+9 passed, 0 failed at ~2.4s; mutation battery 94/94 green.

### Components Invoked
- soleur:plan, soleur:deepen-plan (run inline — skill files read from plugin root)
- Mechanical gates: cloud-detect.sh, lint-guard-contract.py, markdownlint-cli2, gh issue/pr view, git ls-files/grep premise validation, both parity suites
- Artifacts: plan file + specs/feat-one-shot-9998-ssh-residence/{spec.md,tasks.md,decision-challenges.md}; commits 36c9596f3b, fca7219dda

## Technical Rulings
- cto_spawns=1 (one batched `soleur:engineering:cto` spawn, 8 rows ruled 2026-10-12; 7 confirmed, row 5 corrected: enclosing-resource resolution is type-generic, not `terraform_data`-pinned — plan amended)
