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

- [x] 1.1 `tunnel.tf`: locals, `_soleur` tunnel (name `soleur-web-platform`), config, account-scoped
      Access apps and policies, tokens, notification policy, outputs; drop `ignore_changes = [value]` on
      the registry Doppler secrets; fix the two stale comments.
- [x] 1.2 `dns.tf`: three `_soleur` CNAMEs.
- [x] 1.3 `server.tf`: point the cloud-init `tunnel_token` input at the new tunnel.
- [x] 1.4 Push-plan `-target` list gains every new address.
- [x] 1.5 Target-parity test: new registry addresses are push-applied.
- [x] 1.6 Deploy-policy gate branch for the new address, with Guard 2 rows (write the RED rows
      first).
- [x] 1.7 Verify script reads TF outputs and checks `registry.`, with Guard 3 rows.
- [x] 1.8 Move the CI-SSH Doppler sync ahead of the verify step; fail on empty outputs when this run
      creates `ci_ssh`.
- [x] 1.9 Verify script prints `SOLEUR_TUNNEL_VERIFY cause=…` and still exits non-zero.
- [x] 1.10 Repoint the connector census (workflow + script) and the six `ci_ssh_token_replace`
      literals; add the Access policy-parity test.
- [x] 1.11 Run every guard suite listed under Files to Edit; fix any that go red.

## Phase 2: Make the cause visible

- [x] 2.1 Classifier body capture plus `host-nxdomain`, `edge-error-<NNNN>` and `tunnel-down`
      (Guard 1 RED rows first).
- [x] 2.2 Remedies plus the `zot_bridge_marker` helper.
- [x] 2.3 Bridge action prints the marker in both failure branches.
- [x] 2.4 `reusable-release.yml` mirror failure path prints the marker and adds it to the email.
- [x] 2.5 Tests for 2.1-2.4.
- [x] 2.6 Zone-authority step in `scheduled-terraform-drift.yml` (Guard 4).

## Phase 2b: Docs

- [x] ADR-330 (renumbered from ADR-329, which two local branches already hold; re-check the ordinal across all `origin/*` refs before merge). ADR-304 addendum dropped (decision-challenges: one record).
- [x] `model.c4` descriptions; run the C4 tests.
- [x] Runbooks, `expenses.md`, `domains.md`.

## Phase 3: Credentials and DNS (explicit operator go per act)

- [ ] 3.1 Mint the deploy token through the API and commit its id to
      `local.deploy_service_token_ids_soleur`.
- [ ] 3.2 Write the deploy pair to the GitHub secrets (via the infra GitHub App) and both Doppler
      configs; check the hashes match.
- [ ] 3.3 Delete the 6 scanner A records one at a time, verifying each before and after.

## Phase 4: Merge

- [ ] 4.1 Merge with `[ack-deploy-policy]` (no `[ack-destroy]`). Assert from the plan JSON: creates plus
      in-place updates of the two registry Doppler secrets. Expect a red
      `SOLEUR_TUNNEL_VERIFY cause=no-connector`. Record this merge's release and deploy-arm run ids.
- [ ] 4.2 Check the API and Doppler state after the apply.
- [ ] 4.3 `apply-deploy-pipeline-fix.yml` merge run is expected red at its bridge step.
- [ ] 4.4 Uncredentialed probes of the 3 hosts return an Access-stamped 403; deploy-status probe with
      the GitHub-secret pair reaches Access.

## Phase 5: Connector re-bake

- [ ] 5.0 Read the authoritative zone's load balancers and `app.` record; drain web-2 there first if it
      serves, else record that it serves nothing.
- [ ] 5.1 Stock preflight for web-2's server type.
- [ ] 5.2 Dispatch `web-host-replace web-2` (no `image_tag`) and arm a Monitor watch. The operator
      approves the environment. Hold `host_script_files` merges until 5.3.
- [ ] 5.3 New tunnel has at least one connection from web-2; old tunnel has 0.

## Phase 6: Prove the fix and unblock releases

- [ ] 6.1 `manual-rerun` apply green.
- [ ] 6.2 Token drift check reports LIVE in every config.
- [ ] 6.3 Freeze deployable merges; rebuild the failed-run list; check drafts (one per tag); re-run
      releases one at a time oldest first (wait for each to publish), then only the newest deploy arm.
      Includes 44375972612, 44427650817 and this PR's merge release.
- [ ] 6.4 `deploy-arm.sh served <sha>` prints `CONTAINED`.
- [ ] 6.5 Run `soleur:postmerge` for `5d4851f7af`.
- [ ] 6.6 Re-dispatch `apply-deploy-pipeline-fix.yml`; re-read the old zone status.
- [ ] 6.7 Close #12937 after 6.4, with a comment linking the green runs.

## Phase 7: Follow-ups

- [ ] 7.1 File the old-account teardown issue (before merge), including the expiry-monitor repoint and
      that it must land before #12931's account/zone flip.
- [ ] 7.2 Comment on #12931, including the collision note for its variable flip and PR #12932.
