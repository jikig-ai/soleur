# Tasks: unblock web-platform deploys (file-cap'd bwrap), Closes #9871, Ref #9860

Plan: `knowledge-base/project/plans/2026-10-09-fix-deploy-canary-filecap-bwrap-rollback-plan.md`

## Phase 0 - Evidence and collision check (read-only, before any edit)

- 0.1 Re-check `gh pr list --search "linked:issue #9871" --state all` and open PRs touching `apps/web-platform/Dockerfile`, `ci-deploy.sh`, `sandbox-canary-soak.test.sh` (known: #9809); plan the rebase.
- 0.2 Re-run plan Phase 0.1 (tag to commit map, ancestry) and 0.2 (deploy job annotations) for the newest failed deploy.
- 0.3 Re-run the Better Stack query (Phase 0.4) for that deploy and compare `reason` / `bwrap_err` with the v0.333.1 signature.
- 0.4 If the signature differs, stop and re-plan (Phase 0.7 stop rule); do not edit the probe.

## Phase 1 - Repin the test (RED)

- 1.1 Edit `apps/web-platform/infra/sandbox-canary-soak.test.sh` section 8: invert the two Dockerfile asserts (no `setcap`, explicit emptiness-test audit); leave the `--cap-add` asserts for the follow-up PR.
  - 1.1.1 Add `check_no_filecap <dockerfile>` (comment-stripped, continuation-joined, returns non-zero on missing or empty input).
  - 1.1.2 Add test-time-derived mutants M1-M4 and the pass stubs H1; add H2 (grep replaced by `true` must make M1 fail the suite).
- 1.2 Run the suite: expect RED on the current tree.

## Phase 2 - Image posture (GREEN)

- 2.1 `apps/web-platform/Dockerfile`: delete the `RUN setcap ... /usr/bin/bwrap` line, rewrite its comment, keep `libcap2-bin`.
- 2.2 Replace the `{bwrap}`-only audit with the empty-set audit RUN (explicit `[ -z "$all" ]`, after every install layer).
- 2.3 Run the suite: expect GREEN; run `bash scripts/lint-orphan-test-suites.sh` and `plugins/soleur/test/c4-count-parity.test.sh`.
- 2.4 Local negative-direction repro (plan Phase 0.5, setcap step removed): never prints `Unexpected capabilities`.

## Phase 3 - Docs

- 3.1 ADR-075 amendment (about 10 lines).
- 3.2 `canary-probe-set.md`: "Which sub-check failed" paragraph.
- 3.3 Learning via `soleur:compound` (topic only).

## Phase 4 - Ship and verify

- 4.1 PR body: `Closes #9871`, `Ref #9860`; filtered evidence lines.
- 4.2 Create deferral issues: re-spike (Ref #9773), pre-merge real-bwrap-as-uid-1001 probe, follow-up PR (`--cap-add` removal + outer-wrap canary skip + stale comments).
- 4.3 After merge: poll with Monitor (15-minute budget) for deploy success, `/health` `build_sha`, `SANDBOX_PROBE_OK` for the tag.
- 4.4 Comment the fresh faithful-canary verdict on #9860; leave it open unless its own acceptance is met.
