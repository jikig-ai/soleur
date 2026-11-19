---
lane: cross-domain
plan: knowledge-base/project/plans/2026-11-19-fix-zot-bridge-tunnel-hosts-after-zone-move-plan.md
issue: 12937
---

# Tasks: re-home the tunnel hosts after the soleur.ai zone move (#12937)

No `spec.md` exists for this branch (one-shot entry), so `lane: cross-domain` is the default.

## Phase 0: Preconditions

- [ ] 0.1 Operator widens `CF_API_TOKEN` to the Soleur account and new zone (plan Phase 0.1).
- [ ] 0.2 Probe Zero Trust on the Soleur account read-only; operator enables it only if absent.
- [ ] 0.3 Verify the widened token with read-only GETs; record the output for the PR body.

## Phase 1: Terraform tunnel slice

- [ ] 1.1 `tunnel.tf`: locals, `_soleur` tunnel, config, Access apps, policies, tokens,
      notification policy, `replace_triggered_by` on the registry Doppler secrets, outputs.
- [ ] 1.2 `dns.tf`: three `_soleur` CNAMEs.
- [ ] 1.3 `server.tf`: point the cloud-init `tunnel_token` input at the new tunnel.
- [ ] 1.4 Push-plan `-target` list gains every new address.
- [ ] 1.5 Target-parity test: new registry addresses are push-applied.
- [ ] 1.6 Deploy-policy gate branch for the new address, with Guard 2 rows (write the RED rows
      first).
- [ ] 1.7 Verify script reads TF outputs and checks `registry.`, with Guard 3 rows.
- [ ] 1.8 Move the CI-SSH Doppler sync ahead of the verify step; fail on empty outputs when this run
      creates `ci_ssh`.
- [ ] 1.9 Verify script prints `SOLEUR_TUNNEL_VERIFY cause=…` and still exits non-zero.
- [ ] 1.10 Run every guard suite listed under Files to Edit; fix any that go red.

## Phase 2: Make the cause visible

- [ ] 2.1 Classifier body capture plus `host-nxdomain`, `edge-error-<NNNN>` and `tunnel-down`
      (Guard 1 RED rows first).
- [ ] 2.2 Remedies plus the `zot_bridge_marker` helper.
- [ ] 2.3 Bridge action prints the marker in both failure branches.
- [ ] 2.4 `reusable-release.yml` mirror failure path prints the marker and adds it to the email.
- [ ] 2.5 Tests for 2.1-2.4.
- [ ] 2.6 Zone-authority step in `scheduled-terraform-drift.yml` (Guard 4).

## Phase 2b: Docs

- [ ] ADR-329 (re-check the ordinal across all `origin/*` refs before merge), ADR-304 addendum.
- [ ] `model.c4` descriptions; run the C4 tests.
- [ ] Runbooks, `expenses.md`, `domains.md`.

## Phase 3: Credentials and DNS (explicit operator go per act)

- [ ] 3.1 Mint the deploy token through the API and commit its id to
      `local.deploy_service_token_ids_soleur`.
- [ ] 3.2 Write the deploy pair to the GitHub secrets (via the infra GitHub App) and both Doppler
      configs; check the hashes match.
- [ ] 3.3 Delete the 6 scanner A records one at a time, verifying each before and after.

## Phase 4: Merge

- [ ] 4.1 Merge with `[ack-deploy-policy]` and `[ack-destroy]`. Assert the run shape from the plan
      JSON. Expect a red `SOLEUR_TUNNEL_VERIFY cause=no-connector`.
- [ ] 4.2 Check the API and Doppler state after the apply.
- [ ] 4.3 Check the shape of the `apply-deploy-pipeline-fix.yml` merge run.

## Phase 5: Connector re-bake

- [ ] 5.1 Stock preflight for web-2's server type.
- [ ] 5.2 Dispatch `web-host-replace web-2` and arm a Monitor watch. The operator approves the
      environment.
- [ ] 5.3 New tunnel has at least one connection from web-2; old tunnel has 0.

## Phase 6: Prove the fix and unblock releases

- [ ] 6.1 `manual-rerun` apply green; re-dispatch `apply-deploy-pipeline-fix.yml`.
- [ ] 6.2 Token drift check reports LIVE in every config.
- [ ] 6.3 Re-run 44375972612 and then 44376350232; re-run 44427650817 and then 44427961170.
- [ ] 6.4 `deploy-arm.sh served <sha>` prints `CONTAINED`.
- [ ] 6.5 Run `soleur:postmerge` for `5d4851f7af`.
- [ ] 6.6 Close #12937 with a comment linking the green runs.

## Phase 7: Follow-ups

- [ ] 7.1 File the old-account teardown issue.
- [ ] 7.2 Comment on #12931.
