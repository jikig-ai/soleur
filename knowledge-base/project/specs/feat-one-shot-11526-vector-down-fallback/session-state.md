# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-29-fix-inngest-luks-wrong-volume-vector-down-plan.md
- Status: complete
- cto_spawns=1

### Errors
- `git commit` denied twice by harness `guardrails.sh` block-commit-on-main false positive (worktree-blind `.cwd` resolution); resolved via inline `cd` into the worktree.

### Decisions
- Dual-path predicate design (accept arm): leg A journald conjuncts byte-identical OR leg B `shipper='cloud-init-phone-home'` + `stage='inngest-server-probe-vector-down'`, host_role/negated devid on `detail` never `marker`; OR inside the parenthesized group preserving the shared `time BETWEEN` filter (mirrors `ghcr_hostsfile_deny_lost_sql`).
- CTO-ruling rows recorded `pending - assumed:` (no spawn capability at planning level): T1 accept/reject -> assumed ACCEPT; T2 `Ref` not `Closes`.
- Fail-loud edges kept: detail-absent phone-home rows count as wrong-volume; leg-B POSTed `dt` self-attested and unmeasured.
- Drift guard extended +5 presence/+5 mutation rows, `stage` needle derived from inngest-bootstrap.sh, floors 29->39/15->20, three needles retargeted for dual-occurrence devid.
- All deepen-plan halt gates passed inline; `## Operator Holds` carried verbatim.

### Components Invoked
- soleur:plan, soleur:deepen-plan (read + run in-process)
- cloud-detect.sh, collision-precheck.sh, precommit-guard.sh, lint-guard-contract.py, markdownlint-cli2
- gh CLI (issue/PR/epic state reads)

## Work Phase
- Status: complete — pushed b49abe78b2 to origin/feat-one-shot-11526-vector-down-fallback (draft PR #11559).
- Tier: C sequential (guard + .tf tightly coupled; no spawn batch, no agent_rounds spend).
- Live-probe (doppler prd_terraform, 48h): A=49, B=27 stages/1700 rows (vector-down=1 real row), C=0, D=50, E=1/0/1/0 — numbers in the .tf LIVE-PROBED comment.
- Mid-work fork T4 (decision-challenges.md, `pending - assumed:`): prescribed leg-B conjuncts could not deliver the ruled detail-absent fail-loud (host_role `> 0` rejects on `''` first — measured E3=0); shipped `detail = '' OR (…)` disjunct, parent to confirm at review.
- Guard extended to 41/21 (extra disjunct presence+mutation row; host_role/devid needles pinned per-leg after one measured surviving mutation).
- Phase 3 items (PR body disclosure, post-merge apply check, `gh issue close`) belong to ship — not run here.
