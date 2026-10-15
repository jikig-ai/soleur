# Tasks: G1 webhook trio to Tier B (#9294)

Plan: knowledge-base/project/plans/2026-10-15-feat-g1-webhook-trio-tier-b-plan.md. CPO sign-off granted 2026-10-15 (conditions: owner stamps the rotation start date at the wipe). Sequencing: PR-0 now; PR-1 only if released before the rehearsal dispatch; PR-2 to PR-4 only if green by then; nothing between the rehearsal and the wipe; rotation after the wipe; git-data-cutover.yml frozen from the rehearsal dispatch (Ruled by CTO agent, 2026-10-15).

## 1. PR-0: docs and tests (no behaviour change)
- [x] 1.1 ADR-241 D1 amendment (inventory, G1b census miss, orphan CF_TUNNEL_TOKEN, narrow project, host-coverage result)
- [x] 1.2 Census as its own suite (tests/scripts/test-trio-baseline-census.sh): derived (file, name) scan over every read shape; TIER_B_NAMES left for the migrating PRs
- [x] 1.3 Census: tests/scripts/trio-baseline.tsv, merge-base comparison via git show, rows for the fallback ban and HMAC-not-in-state (H1 to H3). The empty-secret render row and the reintroduced-fallback row need PR-2 code and are PR-2 rows (3.5)
- [x] 1.4 Read-only id reconciliation command, result pasted in the PR body
- [x] 1.5 Comment on #9294 adding G1b: posted with the owner's go on 2026-10-15 (https://github.com/jikig-ai/soleur/issues/9294#issuecomment-6193008574); a standalone G1b issue is still to be filed (1.8)
- [ ] 1.6 Review-round rework of the census as Guard 1a (Ruled by CTO agent, 2026-10-15): git-derived population, structural test exemption, name token family and pinned stems, ALIAS rows, tag/class/expiry compare with `@allow` and renames, fail-closed base, `tier-a`/`tier-b`/`sink` classes, strict ISO expiry with the event table, 20 new mutation rows; ADR amendment and plan narrowed to match
- [ ] 1.7 File the two expiry follow-throughs (due 2026-11-16 and 2026-11-30, each carrying the owner's rotation start date stamp at the wipe, CPO condition 2) so the CPO condition has an owner-visible hook
- [ ] 1.8 File the deferral issue for G1b (a standalone issue, not only a comment) and the G1b-names-join-the-census deferral, each with a concrete re-evaluation trigger; both gated on the second-reviewer CONCUR

## 2. PR-1: prep
- 2.1 ci-deploy.sh fan_out_to_peers reads the first secret under trigger-rule; ci-deploy.test.sh both shapes (lands first)
- 2.2 hooks.json.tmpl: or of two matches on all 13 rules only when next is non-empty; template tests
- 2.3 deploy-channel-environment.tf (project, environment, main-only policy); census constants for it
- 2.4 Loader narrow mode (doppler-project allowlist, doppler-token-deploy-channel, fail closed on empty token); fixtures
- 2.5 webhook_deploy_secret_next variable (default empty, validated); webhook_secret_generation trigger literal
- 2.6 Spend the three `@allow` lines for `WEBHOOK_DEPLOY_SECRET_NEXT` (variables.tf, server.tf, hooks.json.tmpl) as rows; add `deploy-channel` to the Tier-B sets of both censuses; widen H1 to H3 (subdirectories, `null_resource.triggers`, `local_sensitive_file`/`local_file`, an indirected `sha256(`)

## 3. PR-2: Terraform-fed group (forward-fix only)
- 3.1 Owner-named hash-equal copy into soleur-infra-privileged/prd; canary reads source=tier_b
- 3.2 tunnel.tf: policy takes var.deploy_service_token_ids (default = live id); removed block; delete sensitive outputs; keep the -target line
- 3.3 CI gate: variable default equals the live token id; plan fixture 0 add / 0 destroy
- 3.4 Move apply-web-platform-infra, apply-deploy-pipeline-fix, git-data-cutover, track.sh and script consumers; drop infra-config-verify fallback
- 3.5 PR-2 census rows: reintroduced `|| doppler secrets get CI_SSH_ACCESS_TOKEN_ID` fallback is RED; `hooks.json.tmpl` `or` render with an empty secret is RED; the `removed` block row and the deploy token address not declared in any `.tf`; the CF pair in state; delete the ALIAS and FALLBACK rows; decide how the `deploy_service_token_ids` default-equals-live-id check works offline or drop that claim from the plan

## 4. PR-3: release chain
- 4.1 web-platform-release, canary-status to deploy-channel; non-main dispatch fixture
- 4.2 Reformulate the HCLOUD_TOKEN-creep row by carrier (narrow or privileged), not by file

## 5. PR-4: inngest group and retirements
- 5.1 cutover-inngest, deploy-inngest-image, restart-inngest-server, scheduled-inngest-health, inngest-soak-6178
- 5.2 Delete the five closed-issue probes and their tracker directives; sweeper and github-app-key-status.sh lose trio reads
- 5.3 Decide the execution home of inngest-soak-6178.sh (its tracker #6178 is still open and the probe only runs under the sweeper, which is said to need none of the trio): retire the probe or give it a dedicated workflow
- 5.4 Rewrite the four agent-executed skill-doc reads of the trio from Tier A (ship, postmerge x2, qa) and tag them PR-4 in the plan table

## 6. Owner-named, irreversible
- 6.1 Re-verify Tier-B copies equal; delete Tier-A copies, repo secrets and CF_TUNNEL_TOKEN; no tier-a, FALLBACK or ALIAS row left; record the live absence postcondition in the PR body

## 7. Rotation (after 6; freeze from phase A to C)
- 7.1 Access pair: mint, add id, update both copies, canary, remove old id, delete old token, probe
- 7.2 HMAC: phases A, B, C with generation bumps; probe the old secret returns 403
- 7.3 ADR-241 closing amendment; census asserts zero tier-a, FALLBACK and ALIAS rows
