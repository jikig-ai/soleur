# Tasks - code-only prework for the Inngest host-replace window

Plan: `knowledge-base/project/plans/2026-10-24-feat-inngest-host-replace-window-prework-plan.md`
Branch: feat-one-shot-inngest-window-prework. Draft PR: #10966. Refs only: #9927 (items 1, 2), #10112 (item 1), #10390.
Standing constraints: no replace dispatch, no credential mint, no Hetzner/Doppler/Supabase/R2 write, no `op=resume`, no #10382; never `git add -A`; no git stash; commits end with the Co-Authored-By line; PR bodies end with the generated-with line.

## Phase 0 - Setup (each PR starts from fresh origin/main in its own worktree)

- 0.1 Re-run `bash apps/web-platform/infra/inngest-userdata-budget.sh` on the branch base; record headroom (expect 256 B before PR-D).
- 0.2 Confirm host `curl` >= 7.75 can be assumed (`--aws-sigv4`); if not provable offline, record as the PR-2 open check and stop at that point for a CTO re-ruling.
- 0.3 Copy the CLO text from `clo-wording.md`; any wording change goes back to the CLO agent.

## Phase 1 - PR-1 baked-carrier hygiene (image-affecting)

- 1.1 Fix the retention sentence in `inngest-server-flip-guard.sh` (comment only; 90 days, dated basis).
- 1.2 Delete `inngest-luks-cutover.{sh,service,timer}` and `inngest-luks-cutover.test.sh`.
- 1.3 Remove the trio from `build-inngest-bootstrap-image.yml` (cp, COPY, chmod operand, ENTRYPOINT operands), `.github/scripts/check-inngest-bootstrap-build.sh`, `check-inngest-bootstrap-build.yml` paths.
- 1.4 Remove the install and enable blocks from `inngest-bootstrap.sh`.
- 1.5 Drop the member from `inngest-config-refresh-set.txt`; update every "five members" assertion and message (derive with `git grep`).
- 1.6 Update the tests and registrations listed in plan task 1.5 (derive the final list with `git grep -ln 'inngest-luks-cutover'`).
- 1.7 Add Guard 3 (cutover vocabulary absent from carriers) with its mutation rows; demonstrate RED once.
- 1.8 Run affected tests only; open PR with `Ref` lines, web-redeploy notice, apply expectation; no skip marker.

## Phase 2 - PR-2 keeper trio (image-affecting; merge right after PR-1)

- 2.1 Write the tests first (stubbed `cryptsetup`/`findmnt`/`curl`/`doppler`; loopback LUKS arm where root exists): Guard 2 matrix rows before the script.
- 2.2 Implement `inngest-luks-keeper.sh`, `.service`, `.timer` (design in plan).
- 2.3 Bootstrap install and enable block (non-fatal `install_missing`); build workflow and check-script sites.
- 2.4 `vector.toml` tag in the three lists; `betterstack-logs-alerts.tf` alert; shard manifests, durations, `infra-validation.yml` step, affected-audit baseline.
- 2.5 Run `scripts/lint-encryption-posture.py`; close the three open checks (curl version, drop-in shape, DEST_SPEC lockstep).
- 2.6 Open PR; plan read must show only the alert create.

## Phase 3 - Image release (automated; no operator tag push)

- 3.1 Watch `mint-inngest-bootstrap-tag.yml` and `build-inngest-bootstrap-image.yml`; confirm tags with `git tag --contains <merge-sha> --list 'vinngest-v*'`.
- 3.2 Merge only the bot pin-bump PR for the LAST tag; close earlier bot PRs unmerged after confirming the runbook recovery text; confirm zot mirror health. If the mint or build fails, STOP and surface it.

## Phase 4 - PR-3 gated header bucket + legal records (no image carrier)

- 4.1 Tests first: `inngest-luks-header.test.sh` (cardinality, distinctness, count gate default false, WEUR wording, no "EU residency").
- 4.2 `inngest-luks-header.tf`, inert `-target` line (check workflow byte gate), ledger row, lint.
- 4.3 Place the CLO text: Art. 30 PA-13 (e), (g)(15), (13) marker; compliance-posture pointer; ADR-142 and ADR-282 edits; ADR-297 (re-verify ordinal across all pushed refs); C4 edge and description edit; run C4 tests.
- 4.4 Runbook section 5c "Header backup: owner activation and recovery" (agent-run, owner-approved forms; Playwright attempt first; STOP if write-only cannot be minted).
- 4.5 Run `soleur:gdpr-gate` on the diff (advisory); request the CLO counsel-review audit file; merge only when DISCHARGED.
- 4.6 `mint-inngest-bootstrap-tag.sh --dry-run` expects `result=noop`.

## Phase 5 - PR-D user_data byte plan (LAST; after the pin bump)

- 5.1 Tests first: `--min-headroom` semantics row, Guard 1 matrix, STAGED membership and quiesce battery updates.
- 5.2 Edit `cloud-init-inngest.yml` (STAGED swap, quiesce and status-list references, volumes-file lines, `|LUKS_HDR_PUT`).
- 5.3 `inngest-userdata-budget.sh --min-headroom`; `infra-validation.yml` passes 300 with sunset comment.
- 5.4 Re-measure: headroom >= 350 B (planner 364 B). If under, shorten the keeper unit names before anything else.
- 5.5 PR body: dependency on the pin bump; no dispatch before the #10951 promotion apply; apply expectation; no skip marker unless the plan read shows unreviewed drift.

## Phase 6 - Follow-up issues (deferral tracking, `Ref` only)

- 6.1 File the five issues listed in the plan (dispatcher retirement, keeper dead-man, jurisdiction pin, stale tags/regex names, floor sunset).

## Phase 7 - Owner-reserved (NOT done by this work; recorded in the runbook entry and window preconditions)

- 7.1 Promotion apply (P0), replace dispatch, `INNGEST_LUKS_HDR_PUT` write after the replace, flipping `inngest_luks_header_backup_enabled`, `op=resume`, #10382.
