# Tasks: Inngest TLS with certificate verification

Plan: `knowledge-base/project/plans/2026-10-18-feat-inngest-tls-verification-plan.md`
Branch: `feat-one-shot-10136-inngest-tls-verification` | PR #10501 (draft) | Ref #10136, Ref #10205, Ref #10382, Ref #9139

Spec lacks a valid `lane:`; defaulted to cross-domain (fail-closed).

## Phase 0: Preflight and spikes (no behaviour change)

- 0.1 Infra-merge checks: `gh run list` for `apply-web-platform-infra.yml` and `registry-host-replace-dispatch.yml` (nothing in flight); re-read `registry-host-replace-dispatch.md` and `inngest-server.md` "Replace triggers"
- 0.2 Measure the user_data delta first with `bash apps/web-platform/infra/inngest-userdata-budget.sh` on a scratch copy; margin must be at least 300 B and under the repo test budget; apply the Risks fallback ladder if not; never raise or bypass the gate
- 0.3 `inngest start --help` at v1.45.1 from the sha256-verified tarball in a fresh scratch dir (record "no TLS flag")
- 0.4 `NODE_EXTRA_CA_CERTS` with an empty file, a missing file and a directory on `node:22-slim` (record warnings)
- 0.5 Measure with real binaries and keep the output as fixtures: nft named counters on nftables v1.0.9 (Ubuntu 24.04 container), stunnel4 config semantics and the `stunnel4` user/group, `curl --cacert` exit 60 and SAN-mismatch cases
- 0.6 NIC ordering for the stunnel unit (`soleur-inngest-nic-wait`); decide between binding `10.0.1.40` and the `accept = 8443` + nft-drop fallback
- 0.7 Name the emitters: `inngest-boot-phone-home.sh` for the periodic `tls-health` series; `logger -p user.crit -t inngest-tls-health` for `SOLEUR_INNGEST_TLS_REFUSED`; confirm redaction keeps a labelled `sha256=` field
- 0.8 Coordination: grep `gh pr diff 10405` for pinned chain literals; trial-merge budget run (the PR that merges second yields bytes); measure replace duration and send-failure behaviour; show the doppler stderr parse separating "not found" from other errors (else treat every non-zero as an error)
- 0.9 Delivery census, bounded to files that change: workflow `paths:` filter plus provisioner `triggers_replace` for each web-host file

## Phase 1: Terraform (cert, key, Doppler copies)

- 1.1 Write failing tests/plan checks first (additive-only plan, no `hcloud_server` in the merge `-target` list)
- 1.2 `apps/web-platform/infra/inngest-tls.tf`: `tls_private_key`, `tls_self_signed_cert` (ECDSA P256, 10 y, SAN IP only, `prevent_destroy`, no `early_renewal_hours`), three masked `doppler_secret`s
- 1.3 Add the addresses to the merge `-target` list in `apply-web-platform-infra.yml`; sweep the `-target` guard suites (`git grep -ln -e '-target='`)
- 1.4 Boot isolation regex: add the two secret names, keep floor 5 (`doppler-injection-bound.test.sh` and the template check)

## Phase 2: Inngest host (`cloud-init-inngest.yml`)

- 2.1 Failing tests first: `inngest-host.test.sh` (accept line unchanged, new rules), bootstrap and provision-unit suites, top-level key set, budget test
- 2.2 `stunnel4` package, stunnel conf, `soleur-inngest-tls.service` (hardening, restart policy, packaged unit masked), explicit fail-closed key/cert fetch after the heredoc that writes the script
- 2.3 nft block: named counters `legacy_8288` and `tls_8443`, counting rules before the accepts, `8443` accept + drop; existing `8288/8289` lines byte-identical
- 2.4 `tls-health` unit and timer: phone-home series (`listener`, `cert_sha256`, `notafter_days`, `legacy_8288_packets`, `tls_8443_packets`, `nft8443_sha256`, `nft_rules`, `boot_id`) and the crit-priority refusal marker (`listener=0`, `notafter_days < 90` only)
- 2.5 Enable the units in `runcmd`, each failing loudly to the boot phone-home
- 2.6 Do not touch the `net-health` emit region or `inngest-cutover-flip.sh`
- 2.7 Re-run the budget gate; register new tests in `infra-validation.yml`

## Phase 3: Web side (inert)

- 3.1 Failing tests first: `inngest-link-resolver.test.sh` (flag absent, `pending:<epoch>` in/out of lease, `1` with good/bad CA, read error, third value), tuple-gate mutation rows K07/K10 plus new rows
- 3.2 `ci-deploy.sh` `resolve_inngest_link`, CA file write, link env file, both docker run sites
- 3.3 `cloud-init.yml` first-boot site: mount, env, placeholder CA file
- 3.4 `lib/docker-run-tuple.py`: resolver expansion, `NODE_EXTRA_CA_CERTS`, CA `-v`, pinned absence of `NODE_TLS_REJECT_UNAUTHORIZED`
- 3.5 `cron-egress-nftables.sh` `8443` accept, `cron-egress-postapply-assert.sh`, `cron-egress-firewall.test.sh`
- 3.6 Probes prefer `/etc/soleur/inngest-link.env`; `inngest-registry-probe.sh --tls-handshake` mode; suites updated; hook template only if the mode argument needs passing
- 3.7 Watchdog parity test to resolver-expansion membership; `INNGEST_HOST_FALLBACK` unchanged
- 3.8 `.github/workflows/inngest-link-flip.yml` (lease, canary, prod, promote, revert on failure/cancel); resolve the credential-tier open item before writing it
- 3.9 Canary layer in `canary-probe-set.md` (docker inspect, in-container fetch of the handed URL, CA-withheld negative control, registry over https)

## Phase 4: Observability, follow-through, docs

- 4.1 Guard row for the new marker in the `monitor_send_failed` drift guard; decode row in `betterstack-log-query.md`; synthetic `synthetic=1` proof through `scripts/betterstack-query.sh`
- 4.2 `scripts/followthroughs/inngest-tls-soak-10136.sh` plus test covering every Guard 2 row; sweeper `secrets=` additions
- 4.3 `inngest-server.md` runbook section "Link TLS (#10136)" with the Production Envelope, flag semantics, rollback, replace order, release-blocking note, cert expiry, replace duration and event behaviour
- 4.4 ADR-292 (provisional ordinal, re-verify across `origin/*` before merge), ADR-100 addendum, C4 edits, C4 count-parity and render tests
- 4.5 `BASELINE_DECLARED_PROBES` bump in `preflight-discoverability-test.test.ts` with the PLACEMENT/TRUTH/NO-SUBSTITUTE comment
- 4.6 File the deferral issues before merge: sdk_url poll TLS, loopback bind and Connect ports, rotation apply route, `--only-secrets`

## Phase 5: Verification and ship

- 5.1 `scripts/lint-encryption-posture.py` PASS, `lint-guard-contract.py`, markdownlint, `git grep` for the banned word in changed files
- 5.2 Compound; PR body first line answers "does merging this alone mutate production"; `Ref #10136` only; `## Changelog`
- 5.3 Single bare `gh pr merge 10501 --squash --auto`, then no sync pushes; `deploy-arm.sh find --wait <full-sha>` then `served <full-sha>` from a detached `origin/main` worktree

## Post-merge (Production Actions, see plan; each only on its recorded owner go)

- A0 verify merge apply and delivery; A1 host replace (due 2026-11-05, bundled with #10405 unless the 2026-10-28 checkpoint passes); A2 handshake mode from both web hosts; A3 flip workflow (own owner go); A4 48 h soak; A5 rotation (after the rotation follow-up lands); A6 "no known access" record; A7 leg-2 accepted-risk record (owner-typed)
