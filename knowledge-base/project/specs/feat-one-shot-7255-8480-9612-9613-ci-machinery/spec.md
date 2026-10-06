---
name: fix-ci-machinery-sweep
branch: feat-one-shot-7255-8480-9612-9613-ci-machinery
lane: cross-domain
status: in-progress
created: 2026-10-06
---

## Summary

Four sibling CI-machinery repairs on one PR (closes #7255, #8480, #9612, #9613):

1. **#7255** — repoint `cmd_cron_run_stale` in
   `plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh` from the dead
   `gh run list --workflow=scheduled-content-vendor-drift.yml` query to
   `gh pr list --search "head:ci/vendor-attest" --state all --limit 10 --json createdAt --jq '[.[].createdAt] | max // empty'`.
   The attestation PR (`ATTEST_BRANCH_PREFIX`, ADR-203) is created on every completed
   Inngest cron run — PR creation date is the liveness signal. All fail-safe guards
   (token, `command -v gh`, `timeout 5s`, strict RFC3339, `days<0→999`) preserved;
   dead-workflow literal must reach zero in parser AND `SKILL.md` in the same commit
   (gdpr-gate-self-test parity check).

2. **#8480** — swap the `rel_path` case arms in
   `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` so `/*/.github/workflows/*`
   (basename) wins over `"$PROJECT_DIR"/*`; regression test drives a worktree
   `file_path` under `CLAUDE_PROJECT_DIR` and asserts `allow` for an existing
   scheduled workflow / `deny` for a new one.

3. **#9612** — new `scripts/lint-gh-argv-arg.py` sentinel (continuation-joined,
   comment-stripped, argv-segmented scan of `.github/workflows/*.yml|yaml` +
   `scripts/*.sh` for a standalone jq-flag token (`--arg|--argjson|--argfile|--slurpfile|--rawfile`) inside a `gh` command segment)
   + `scripts/lint-gh-argv-arg.test.sh` + both registered in `scripts/test-all.sh`.
   Normalize 13 dedupe sites (zot :240/:293/:432/:480/:516; inngest-health
   :510/:537/:566/:586/:606/:633/:1052/:1354) to the fail-open-with-`::error::`
   `if ! VAR="$(gh … | jq …)"` shape; keep the documented `search_rc` fail-closed
   block at zot ~:391.

4. **#9613** — one `doppler_call()` helper in the `workspaces-luks-verify.yml`
   marker step capturing `2>&1` and printing the sanitized `[doppler-stderr]`
   diagnostic on failure; all four `doppler secrets` invocations route through it;
   `>/dev/null` stdout suppression preserved. Guard-3 anchors
   (`apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` — structural
   checks, census VERB regex, `g3_mut` rows 3 + 17g, `G3_EXPECTED_IDS` + new S57/S58)
   move in the same commit.

Plan: `knowledge-base/project/plans/2026-10-06-fix-ci-machinery-sweep-plan.md`
Draft PR: #9635. PR body must carry four `Closes #…` lines.
