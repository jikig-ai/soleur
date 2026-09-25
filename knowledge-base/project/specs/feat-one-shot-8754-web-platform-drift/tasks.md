# Tasks: clear the web-platform drift (#8754)

Plan: `knowledge-base/project/plans/2026-09-25-fix-web-platform-infra-drift-8754-plan.md`

Execution order: Phase 0, then PR-A, then 3.1, then 3.2, then PR-B, then 3.3. Each 3.x step needs
its own per-command go-ahead.

## Phase 0: Re-measure (read-only)

- [ ] 0.1 Re-read the newest drift comment on #8754 and diff it against the classification table.
      Re-check the issue state.
- [ ] 0.2 Record queued/in-progress runs on the three concurrency groups.
- [ ] 0.3 Re-run the ZOT consumer audit against `origin/main`, including the Doppler raw-value scan.
- [ ] 0.4 Make GET-only reads: firewall 11269127 `applied_to`, inngest public-port probe
      (22/6379/8288/8289/9000), and the live deployment policy id. If any data port answers,
      escalate to the CLO.

## Phase 1A: PR-A, the inngest firewall bound at server creation

- [ ] 1A.0 Write the Guard 1 assertions in `apps/web-platform/infra/inngest-host.test.sh` and
      observe them RED.
- [ ] 1A.1 In `inngest-host.tf`, add `firewall_ids = [hcloud_firewall.inngest.id]` and replace the
      attachment with `removed{destroy=false}`. Rewrite its comment.
- [ ] 1A.2 In the workflow, drop the attachment `-target` from the `inngest_host` job and add it to
      the per-merge `apply` list. Move the rationale to the runbook.
- [ ] 1A.3 In the parity test, reclassify `hcloud_firewall_attachment.inngest` using the
      `doppler-write-token.tf` precedent.
- [ ] 1A.4 In the shape gate and its test, drop the attachment from the allow list and the class,
      change the derived target count from 18 to 17, and re-point the two red rows. Fix the comments
      in the replace gate and the registry gate.
- [ ] 1A.5 Bump `BASELINE_DECLARED_PROBES` from 29 to 30, with the required comment.
- [ ] 1A.6 Add the ADR-100 amendment.
- [ ] 1A.7 Run the Phase 1 suites and check AC-A1 to AC-A4. The PR body's first line states the
      production effect. Use `Ref #8754`.
- [ ] 1A.8 Merge into a quiet group. Verify 2A (plan = forget + the two perpetual entries), then
      dispatch the drift run and post the residual.

## Phase 3.1: Inngest replace and resume (go-ahead required)

- [ ] 3.1.1 Coordinate with #8833: read the probe and boot-stage rows, and name the approver.
- [ ] 3.1.2 Dispatch `inngest-host-replace` and Monitor it to success.
- [ ] 3.1.3 Dispatch `cutover-inngest.yml op=resume`, get the environment approval, and Monitor it to
      success.
- [ ] 3.1.4 Check AC-C1 to AC-C3.

## Phase 3.2: Git-data G2 and G3 (go-ahead required)

- [ ] 3.2.1 Run G2 `plan_only`: success, with the gate PASS.
- [ ] 3.2.2 Run the G3 real replace, then Monitor `git-data-pin-redeploy.yml` to success (AC-C4).

## Phase 1B: PR-B, the standing tail (a branch cut from main after PR-A)

- [ ] 1B.1 Bot management: declare `sbfm_definitely_automated = "allow"` and
      `sbfm_verified_bots = "allow"`.
- [ ] 1B.2 Deployment policy:
  - [ ] rename it to `…_adopted` and add the `import` (id from 0.4);
  - [ ] add `removed{destroy=false}` for the old address;
  - [ ] keep both `-target`s;
  - [ ] fix the prose in the runbooks and the stale jq comment.
- [ ] 1B.3 Add `actions: read` to the `infra-validation.yml` job `plan`.
- [ ] 1B.4 Add a bare `-target=doppler_secret.zot_heartbeat_url_prd`, and update the NOTE and the
      parity comment.
- [ ] 1B.5 Heartbeat pair:
  - [ ] add the per-merge `-target`s;
  - [ ] remove the pair from `OPERATOR_APPLIED_EXCLUSIONS` only, leaving `GIT_DATA_BIRTH_REFUSED`
        intact;
  - [ ] add the parity assertion;
  - [ ] fix the stale TODO.
- [ ] 1B.6 Proxy TLS:
  - [ ] add `host_proxy_tls_enabled` (default false);
  - [ ] gate the four resources with `count` and index the references with `[0]`;
  - [ ] add the ADR-118 amendment.
- [ ] 1B.7 Config digest:
  - [ ] gate it with `count` on a non-empty digest;
  - [ ] update the header note and the `inngest-config-refresh.md` step 3.
- [ ] 1B.8 Put `[ack-destroy]` on its own line in the commit message and in `--body-file`. The PR
      body's first line states the production effect.
- [ ] 1B.9 Run the Phase 1 suites, check AC-B1 to AC-B6, and read the PR plan comment.
- [ ] 1B.10 Merge into a quiet group, and verify 2B:
  - [ ] the expected plan shape;
  - [ ] no bot-management entry;
  - [ ] the arm verdict;
  - [ ] AC-M2.

## Phase 3.3: Close out

- [ ] 3.3.1 Dispatch the drift run and expect no drift. Re-check the issue state, comment the run
      URL, and close #8754.
- [ ] 3.3.2 File the deferral issues:
  - [ ] the config-digest promotion route;
  - [ ] the pipeline-fix auto-close;
  - [ ] the recurrence of the exclusion class;
  - [ ] the other hosts' pre-boot firewall window;
  - [ ] removal of the adoption scaffolding.
- [ ] 3.3.3 On a withheld go-ahead for 3.1, file the dedicated P1 security issue linked to #8833.
      Post a status comment on #8754.
