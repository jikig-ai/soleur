# Tasks — feat-one-shot-ci-ssh-token-replace

Derived from `knowledge-base/project/plans/2026-07-31-fix-ci-ssh-access-token-replace-path-plan.md`.

Lane: `cross-domain` (no `spec.md` on the one-shot path — defaulted fail-closed per TR2).

Phase order is dependency-directed: the guard exists before the job that sources it.

## Phase 1 — Scoped destroy-guard (RED first)

- [ ] 1.1 Read `tests/scripts/lib/registry-host-replace-gate.sh` in full — it is the
      model for both the function shape and the sourced-by-workflow contract.
- [ ] 1.2 Write `tests/scripts/test-ci-ssh-token-replace-gate.sh` FIRST (RED), with four
      fixtures: expected shape (pass), registry-replace smuggled in (fail), extra
      unrelated create (fail), empty plan (fail).
- [ ] 1.3 Confirm the test FAILS before the gate exists — a suite that passes against a
      missing implementation is testing nothing.
- [ ] 1.4 Write `tests/scripts/lib/ci-ssh-token-replace-gate.sh` exposing
      `ci_ssh_token_replace_gate <tfplan.json>`:
  - [ ] 1.4.1 Exactly one `create` + one `delete` for
        `cloudflare_zero_trust_access_service_token.ci_ssh` (the
        `create_before_destroy` pair).
  - [ ] 1.4.2 At most one `update` for
        `cloudflare_zero_trust_access_policy.ci_ssh_service_token`.
  - [ ] 1.4.3 Zero actions on any other address; assert explicitly that
        `hcloud_server.registry`, `hcloud_server_network.registry`,
        `hcloud_volume_attachment.registry`, `doppler_secret.zot_heartbeat_url_prd`
        are absent (these are the LIVE pending-drift destroys).
  - [ ] 1.4.4 No `delete` on any `hcloud_*` address (belt-and-braces).
- [ ] 1.5 Test goes GREEN. Re-run after every subsequent edit — a green run only
      certifies the tree it ran on.

## Phase 2 — The `ci-ssh-token-replace` job

- [ ] 2.1 Add `ci-ssh-token-replace` to the existing `apply_target` enum. Add NO new
      `workflow_dispatch` inputs (cap is 10, 7 used; the file's own note routes the
      next input PAIR to a dedicated workflow).
- [ ] 2.2 Add the job, gated
      `if: github.event_name == 'workflow_dispatch' && inputs.apply_target == 'ci-ssh-token-replace'`.
- [ ] 2.3 Add a `confirm` literal check using the EXISTING `confirm` input, with a
      literal distinct from every other target's.
- [ ] 2.4 Plan step with the exact three flags:
      `-replace=cloudflare_zero_trust_access_service_token.ci_ssh`,
      `-target=cloudflare_zero_trust_access_service_token.ci_ssh`,
      `-target=cloudflare_zero_trust_access_policy.ci_ssh_service_token`.
      Invocation form: `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform ...`;
      R2 backend needs `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` as BARE env vars.
- [ ] 2.5 `terraform show -json tfplan > tfplan.json`; source the Phase 1 gate; abort
      with `::error::` naming the offending address on failure.
- [ ] 2.6 Apply step.
- [ ] 2.7 Reuse the existing "Sync CF Access CI-SSH service token to Doppler" step
      verbatim — VERIFIED at plan time to already write BOTH `_ID` and `_SECRET`.
      Do not re-implement it.
- [ ] 2.8 No `environment:` (matches the four sibling dispatch-only jobs). Record the
      decision in the PR body per the plan's Authorization section.

## Phase 3 — Close the silent-success hole + verify

- [ ] 3.1 In the replace job's sync path, make empty `terraform output` a LOUD failure.
      Do NOT change the shared bootstrap path — the `::warning:: … exit 0` is correct
      for the first-apply case it was written for.
- [ ] 3.2 Add a post-sync probe against `ssh.soleur.ai` with the newly-written
      credential pair; require a non-403. Mask both values before use.
- [ ] 3.3 Run `scripts/check-cloudflare-token-drift.sh` and require BOTH `dead == 0`
      AND `unverifiable == 0`. Asserting `dead == 0` alone accepts an unchecked
      fleet as a clean one — the detector's own error text says so.

## Phase 4 — Verification

- [ ] 4.1 `bash tests/scripts/test-ci-ssh-token-replace-gate.sh` → exit 0, and the
      fail-fixtures visibly fail.
- [ ] 4.2 `actionlint .github/workflows/apply-web-platform-infra.yml` clean. NOT
      `bash -n` (it parses the YAML header as bash and is meaningless).
- [ ] 4.3 Extract every added `run:` block and check with `bash -c`.
- [ ] 4.4 `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes.
- [ ] 4.5 Confirm `workflow_dispatch` still declares exactly 7 inputs.
- [ ] 4.6 Confirm the new `confirm` literal is unique across all targets.
- [ ] 4.7 Anchored grep for the three `-replace`/`-target` flags inside the new job
      body (anchor on the job, not a bare token — `cq-assert-anchor-not-bare-token`).
- [ ] 4.8 Run the repo's full suite before declaring done.

## Phase 5 — Ship

- [ ] 5.1 `/review` → resolve ALL findings inline (P1, P2, P3).
- [ ] 5.2 `/qa` against the plan's Test Scenarios.
- [ ] 5.3 `/compound`.
- [ ] 5.4 `/ship` — PR body must carry `Ref` (not `Closes`) semantics for the
      remediation, since the actual token replace happens on a POST-merge operator
      dispatch, not at merge.

## Out of scope (explicit)

- Dispatching `ci-ssh-token-replace` in production. Building the mechanism and
  firing it are separate acts; the dispatch is an operator decision after merge.
- Fixing the notification gap that let two RED drift runs go unread for two days.
  Worth a follow-up issue; not this PR.
