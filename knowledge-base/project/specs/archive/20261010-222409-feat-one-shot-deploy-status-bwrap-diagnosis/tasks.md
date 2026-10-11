# Tasks — docs: deploy-status-debugging bwrap canary-signature diagnosis rows

Plan: `knowledge-base/project/plans/2026-10-09-docs-deploy-status-bwrap-diagnosis-plan.md`
Branch: `feat-one-shot-deploy-status-bwrap-diagnosis` | Ship target: draft PR #9887 (do NOT open a second PR)

## Phase 1 — Edit

- [x] 1.1 Edit `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — in `## Reason Taxonomy`, add TWO rows with `reason` = `canary_sandbox_failed`, `exit_code` = `1` (the state-file code, not the inner `rc=126`), keyed by stderr signature in `Meaning`:
  - Row A signature (verbatim): `bwrap: Unexpected capabilities but not setuid, old file caps config?` — file-cap'd `/usr/bin/bwrap` OR ambient/bounding caps reaching a non-root exec (stale installed `ci-deploy.sh` still passing `--cap-add SYS_ADMIN`); released bwrap 0.8–0.12 aborts on `real_uid != 0 && has_caps()`.
  - Row B signature (verbatim): `/usr/local/bin/bwrap: line 424: /usr/bin/bwrap: Operation not permitted` (inner rc 126) — execve EPERM: file caps on the real binary not covered by the container bounding set (capped image + clean container).
- [x] 1.2 Both rows' `Remediation` cells must state: a merged `ci-deploy.sh` change is NOT delivered at merge — the host runs the installed copy until `apply-deploy-pipeline-fix.yml` (push-triggered on `apps/web-platform/infra/ci-deploy.sh`, or `workflow_dispatch` when the push arm is cancelled) delivers it — and prescribe the no-SSH parity check: `.ci_deploy_sha256` in the `/hooks/deploy-status` body vs `git show origin/main:apps/web-platform/infra/ci-deploy.sh | sha256sum` (or `scripts/check-deploy-script-parity.sh`).
- [x] 1.3 Carry the resolution trail in the rows' prose or an adjacent note: issue #9871, apply run 37976212395, green deploy run 37980286319.

## Phase 2 — Verify

- [x] 2.1 `grep -c 'Unexpected capabilities but not setuid' plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` >= 1; `grep -c 'line 424' <same>` >= 1; `grep -c 'ci_deploy_sha256' <same>` >= 1.
- [x] 2.2 markdownlint clean on the edited file (`npx markdownlint-cli2 plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`); table pipes inside inline code stay escaped/consistent with existing rows.
- [x] 2.3 `git diff --name-only origin/main...HEAD` lists only the runbook file plus this feature's planning artifacts under `knowledge-base/project/{plans,specs}/`.

## Phase 3 — Ship

- [ ] 3.1 Commit + push on this branch (lands on draft PR #9887). PR body: `## Changelog` section; `semver:patch` label (docs update under `plugins/soleur/`).
- [ ] 3.2 PR body must NOT claim release/deploy is skipped — `plugins/soleur/skills/**` is inside the `web-platform-release.yml` push filter; a post-merge release+deploy arm is EXPECTED and is what vendors the corrected runbook onto the host mount.
