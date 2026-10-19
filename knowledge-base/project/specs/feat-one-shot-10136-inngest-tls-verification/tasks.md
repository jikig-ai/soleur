# Tasks: Inngest TLS with certificate verification

Plan: `knowledge-base/project/plans/2026-10-18-feat-inngest-tls-verification-plan.md` (deepened 2026-10-18)
Branch: `feat-one-shot-10136-inngest-tls-verification` | PR #10501 (draft) | Ref #10136, Ref #10205, Ref #10382, Ref #9139

Spec lacks a valid `lane:`; defaulted to cross-domain (fail-closed).

## Phase 0: Preflight and re-verification (no behaviour change)

- 0.1 Infra-merge checks: `gh run list` for `apply-web-platform-infra.yml` and `registry-host-replace-dispatch.yml` (nothing in flight); re-read `registry-host-replace-dispatch.md` and `inngest-server.md` "Replace triggers" and "Inherited done after a host replace (#7228)"
- 0.2 Measure the user_data delta first with `bash apps/web-platform/infra/inngest-userdata-budget.sh` on a scratch copy; margin at least 300 B and under the repo test budget (real headroom 1,852 B against the cap, 1,384 B against `INNGEST_GZIP_BUDGET`); apply the Risks fallback ladder if not; never raise or bypass the gate
- 0.3 `inngest start --help` at v1.45.1 from the sha256-verified tarball in a fresh scratch dir (record "no TLS flag")
- 0.4 Commit the fixtures captured at deepen (stunnel failure/success lines, nft chain text and counter parse, curl exit 60/56, Node error codes) and re-run them against the production package versions and the pinned `node:22-slim` digest; prove offline that Node accepts a self-signed `CA:FALSE` leaf as an extra root
- 0.5 NIC ordering for the stunnel unit (`soleur-inngest-nic-wait`); decide between binding `10.0.1.40` and the `accept = 8443` + nft-drop fallback; confirm no distro unit globs our conf
- 0.6 Coordination: grep `gh pr diff 10405` for pinned chain literals; trial-merge budget run (the PR that merges second yields bytes); measure replace duration (`provision-unit-armed` to `bootstrap-done`) and what the app does on a failed send; confirm `openssl` on the web hosts
- 0.7 Delivery census, bounded to files that change (plan "Delivery census" and Research Insights)

## Phase 1: Terraform (cert, key, Doppler copies, flag)

- 1.1 Failing tests/plan checks first: additive-only plan, no `hcloud_server` in the merge `-target` closure
- 1.2 `apps/web-platform/infra/inngest-tls.tf`: `tls_private_key`, `tls_self_signed_cert` (ECDSA P256, 10 y, SAN IP only, `is_ca_certificate = false`, `prevent_destroy`, no `early_renewal_hours`), `doppler_secret` x2 in `soleur-inngest/prd` (reference `doppler_project.inngest` / `doppler_environment.inngest_prd`), `INNGEST_TLS_CA` base64 in `soleur/prd`; `variable inngest_link_tls` + count-gated `doppler_secret.inngest_link_tls` (in `variables.tf`)
- 1.3 Merge `-target` list: add the five addresses (not the flag); run `terraform-target-parity.test.ts`, `test-infra-privileged-tier-census.sh` and the `git grep -ln -e '-target='` sweep; add the `tls_*`-create-aborts row to `test-inngest-host-replace-gate.sh`; no `templatefile` var in `inngest-host.tf` may reference the new resources
- 1.4 Isolation regex rows in `inngest-host.test.sh` (PASS for the two names, FATAL for a bare `TLS_KEY` and a look-alike), floor stays 5

## Phase 2: Inngest host (`cloud-init-inngest.yml`)

- 2.1 Failing tests first: `inngest-host.test.sh` (accept line unchanged, new rules), bootstrap and provision-unit suites, top-level key set, budget test
- 2.2 `stunnel4` package; stunnel conf outside `/etc/stunnel/*.conf`; `soleur-inngest-tls.service` (no `EnvironmentFile=`, hardening set, `Requires=`/`After=` the nftables unit and NIC wait, restart policy, RuntimeDirectory 0750 preserved on restart); fail-closed fetch with `umask 0077`, redirect-only key write, `openssl pkey` public-key match, key `0640 root:stunnel4`, after the heredoc that writes the script
- 2.3 nft block: named counters `legacy_8288` and `tls_8443`, counting rules before the accepts, `8443` accept + drop; existing `8288/8289` lines byte-identical
- 2.4 `tls-health` unit and timer (after `inngest-bs-token-restage.service`): phone-home series with `unit`, `nrestarts`, `fetch_rc`, `bind`, `listener`, `served_sha256`, `cert_sha256`, `notafter_days`, both counters, `nft8443_sha256`, `nft_rules`, dashed `boot_id`; multi-line `emit_refusal()` for `SOLEUR_INNGEST_TLS_REFUSED` on `listener=0` or `notafter_days < 90` only
- 2.5 Enable the units in `runcmd`, each failing loudly to the boot phone-home; do not touch the `net-health` emit region or `inngest-cutover-flip.sh`
- 2.6 Re-run the budget gate; register new tests in `infra-validation.yml`

## Phase 3: Web side (inert)

- 3.1 Failing tests first: `inngest-link-resolver.test.sh` (flag absent, `pending:<epoch>` in/out of lease and beyond now+31 min, `1` with good/bad CA, non-allowlisted values, snapshot read error, third resolver value, CA variants as shipped: PRIVATE KEY block, `CA:TRUE`, `Certificate Sign`, expired, more than one certificate; the SAN check is carried by the self-gate, not the validator), tuple-gate K07/K10 rows, `NODE_*` env refusal rows
- 3.2 `ci-deploy.sh` `resolve_inngest_link` (snapshot read, scope guard, link env from constants only; for https only: read CA, validate, self-gate the candidate, then install; the pre-`docker run` re-check was dropped by the 2026-10-19 design-pass ruling), both docker run sites
- 3.3 `cloud-init.yml` first-boot site: mount, env, placeholder CA file
- 3.4 `lib/docker-run-tuple.py`: resolver expansion, `NODE_EXTRA_CA_CERTS`, CA `-v`, pinned absence of `NODE_TLS_REJECT_UNAUTHORIZED`; no posture-literal edit
- 3.5 `cron-egress-nftables.sh` `10.0.1.40 tcp dport 8443` accept; postapply assert greps the full `10.0.1.40 tcp dport 8443 accept` text (not a bare `dport 8443`); `cron-egress-firewall.test.sh`
- 3.6 `inngest-registry-probe.sh`: link resolution (parse the env file with a key allowlist, never source; override inherited `INNGEST_REMOTE_GQL_URL`) and `--tls-handshake` mode; `inngest-doublefire-probe.sh`; suites updated; new `inngest-tls-handshake` hook in `hooks.json.tmpl`; the consumer probe, `server.tf` and `web-probe-envwrite.sh` are not edited
- 3.7 Watchdog parity test to resolver-expansion membership; `INNGEST_HOST_FALLBACK` unchanged; test that the container always receives `INNGEST_BASE_URL`
- 3.8 `schedule-reminder/route.ts`: 503 for timeout and TLS causes, with a test
- 3.9 Flip actuator: flag `apply_target` job in `apply-web-platform-infra.yml` under `infra-privileged` (as shipped: the source key in `prd_terraform` is written first with `DOPPLER_TOKEN_WRITE`, verified, because `prd_terraform` does not inherit a Terraform-written `prd` key created after the branch; the value is also passed as `TF_VAR_inngest_link_tls` to the plan; then the `-target` apply; `off` deletes the key and fails the job if it survives), `inngest-link-flip.yml` orchestrator (pending, canary, on, best-effort off + redeploy), D8 census row and `infra-credential-tiers-8209.md`
- 3.10 Canary layer in `canary-probe-set.md`: `docker inspect` https, in-container fetch of the handed URL, real `inngest.send` of `soleur.tls-canary.ping` (test that no function triggers on it), CA-withheld negative control, registry over https

## Phase 4: Observability, follow-through, docs

- 4.1 Drift guard `betterstack-send-failed-alert.test.sh` baseline 79/9 to 81/10 (`BASELINE_PASSES`, `BASELINE_CASES`) plus a mutation row; decode rows in `monitor-send-failed-alert.md` (fix the "web-1 monitor unit" wording) and `betterstack-log-query.md`; synthetic `synthetic=1` proof through `scripts/betterstack-query.sh`
- 4.2 `scripts/followthroughs/inngest-tls-soak-10136.sh` plus test covering every Guard 2 row (query `--limit 1000` or more, trusted-verdict read of T, exit 2 on empty or transport failure); sweeper dry run
- 4.3 `inngest-server.md` runbook section "Link TLS (#10136)" with the Production Envelope, flag semantics, rollback, release-blocking note, replace order including A1b, cert expiry, replace duration and event behaviour, best-effort off step
- 4.4 ADR-292 (provisional; ordinal re-derived across all `origin/*` refs), ADR-100 addendum, C4 edits, C4 count-parity and render tests
- 4.5 `BASELINE_DECLARED_PROBES` bump in `preflight-discoverability-test.test.ts` with the PLACEMENT/TRUTH/NO-SUBSTITUTE comment
- 4.6 File the deferral issues before merge (plan "Deferral Tracking", items 1-11)

## Phase 5: Verification and ship

- 5.1 `scripts/lint-encryption-posture.py` PASS, `lint-guard-contract.py`, markdownlint, banned-word grep in changed files
- 5.2 Compound; PR body first line answers "does merging this alone mutate production"; `Ref #10136` only; `## Changelog`
- 5.3 Single bare `gh pr merge 10501 --squash --auto`, then no sync pushes; `deploy-arm.sh find --wait <full-sha>` then `served <full-sha>` from a detached `origin/main` worktree

## Post-merge (Production Actions, see plan; each only on its recorded owner go)

- A0 verify merge apply and delivery; A1 host replace (due 2026-11-05, bundled with #10405 unless the 2026-10-28 checkpoint passes); A1b `op=resume` approval (own owner go); A2 handshake hook; A3 flip workflow (own owner go); A4 48 h soak; A5 rotation (after the rotation follow-up lands; event key per O5); A6 "no known access" record; A7 leg-2 accepted-risk record (owner-typed)
