# Tasks — jikigai.com Cloudflare zone (Terraform-managed) + DNS cutover

Plan: `knowledge-base/project/plans/2026-09-09-feat-jikigai-cloudflare-zone-terraform-plan.md`
Branch: `feat-one-shot-jikigai-cloudflare-zone-terraform`
Brand-survival threshold: **single-user incident** — CPO sign-off required before work begins.

Mail continuity is the acceptance criterion. Zone existence is not.

**AC0 gates everything.** There is currently no alert channel that is not on jikigai.com — the
git commit address, both Better Stack recipients and GitHub's notification path are all on the
domain being changed, and the product's outbound chokepoint rejects `*@jikigai.com`. Provision
an off-domain recipient and confirm a test alert before starting.

## Phase 0 — Preconditions (verify; never assume)

- [ ] 0.1 Re-run the credential probe. Confirm no existing Cloudflare token lists a zone other than soleur.ai, and that `GET /zones?name=jikigai.com` still returns zero results. Paste output into the PR body.
- [ ] 0.0 **AC0** — provision an alert recipient NOT on jikigai.com; confirm a test alert arrives.
- [ ] 0.2 Re-dig the complete record set **including the widened sweep** (`resend._domainkey`, `send`, `_domainconnect`, `autodiscover`). Transcribe values from dig output, never from the plan.
- [ ] 0.2a **Enumerate the Google-side zone as a whole list** (registrar zone export or Cloud DNS API). `dig` cannot enumerate — it only answers names already known, so "the set is complete" is not establishable by dig. Any undeclared record here is silently destroyed at the flip, and Guard 1 cannot see it.
- [ ] 0.3 Dump the provider schema for `cloudflare_zone`, `cloudflare_zone_dnssec` and `cloudflare_record` from the pinned 4.52.7 via `terraform providers schema -json`. Never take attribute names from documentation.
- [ ] 0.4 **Gate — determine whether DS removal at the registrar is self-service**, by attempt rather than assertion. This is the plan's single point of failure. If it needs a vendor ticket, stop and defer with a tracked issue before any Terraform is written.
- [ ] 0.5 Read all three `.c4` model files in full and produce the actor / external-system / relationship enumeration ADR-214 requires. A keyword grep is not evidence.
- [ ] 0.7 File the cutover tracker issue; capture `#N` (the probe filename embeds it, and the directive gate rejects a `script=` path that does not yet exist).
- [ ] 0.8 Record the registrar account's contact address; if it is on jikigai.com, change it first.
- [ ] 0.6 Confirm F1: check `GET https://api.resend.com/domains` and the absence of Resend records on jikigai.com. File the issue for the two dead Inngest `from:` paths.

## Phase 1 — Credentials (two phases, one persistent)

- [ ] 1.1 Write and run `infra/jikigai-dns/bootstrap.sh`, modelled on `apps/cla-evidence/infra/bootstrap.sh`: mint a one-hour admin token, use it, **self-revoke it in the script**. Token scope lives in version control.
- [ ] 1.2 Create the zone by scripted `curl` to `POST /zones` — not a dashboard click. Capture zone id and assigned nameservers.
- [ ] 1.3 Mint the persistent `Zone:DNS:Edit` token scoped to jikigai.com only; write to Doppler `soleur/prd_terraform` as `CF_API_TOKEN_JIKIGAI`.
- [ ] 1.4 Run the ADR-130 retained-scope probe: new token reaches jikigai.com and 403s elsewhere; **no pre-existing token lost scope**.
- [ ] 1.5 Confirm the ephemeral token has expired.

## Phase 2 — Guards and root (RED first)

- [ ] 2.1 Write the Guard 1 and Guard 2 suites from the mutation matrices **before** implementing the guards. Confirm every matrix row drives RED and every harness must-PASS row passes.
- [ ] 2.2 Author `infra/jikigai-dns/{main,variables,zone,dns,outputs}.tf` and `README.md`. Apex records use the literal `jikigai.com`, never `@`. DKIM CNAMEs `proxied = false`. All TTLs 300.
- [ ] 2.3 `terraform init`, `validate`, `fmt -check` in the new root.
- [ ] 2.4 `terraform import` the zone created in 1.2; confirm state and config name the same address.

## Phase 3 — CI wiring

- [ ] 3.1 `.github/workflows/apply-jikigai-dns.yml`, modelled on `apply-github-infra.yml` (full-root plan, `[ack-destroy]` gate, no required-context aggregator, `workflow_dispatch` escape hatch, concurrency group).
- [ ] 3.2 Destroy-gate cap-coupling — **four mechanisms, not one**: `tests/scripts/lib/destroy-guard-filter-jikigai-dns.jq`; a **dedicated** `tests/scripts/test-destroy-guard-counter-jikigai-dns.sh` (the shared counter pins `MIN_ASSERTIONS=8` with `-ne`, so rows cannot be added to it); two new `EXPECTED_SITES` rows in `tests/scripts/test-destroy-guard-regex-parity.sh`; and the required-status-check trio (`scripts/required-checks.txt`, `scripts/ci-required-ruleset-canonical-required-status-checks.json`, `infra/github/ruleset-ci-required.tf`). Count `forget` as well as `delete`. **Note this touches a second auto-applied root.**
- [ ] 3.2a `.github/workflows/jikigai-dns-cutover.yml` — the actor for Phases 5-8, modelled on `git-data-cutover.yml` (typed `confirm`, `dry_run` default true). Every Phase 5-8 assertion becomes a gate step.
- [ ] 3.6 Add `cloudflare_zone` to `scripts/encryption-posture-ledger.json` `non_store_types` — `lint-encryption-posture.py` is fail-closed and `cloudflare_zone` is in neither partition today, so `zone.tf` reddens CI on first commit.
- [ ] 3.7 `.github/CODEOWNERS` row for `/infra/jikigai-dns/`; fixture row in `plugins/soleur/test/infra-validation-detect.test.sh`.
- [ ] 3.3 Add the `infra/jikigai-dns` leg to the hardcoded matrix in `scheduled-terraform-drift.yml`. **Without this the root has no drift detection — the exact absence that caused the incident.**
- [ ] 3.4 Add `CF_API_TOKEN_JIKIGAI` to `scheduled-followthrough-sweeper.yml`'s `env:` block and as a repository secret. `GH_TOKEN` and `BETTERSTACK_API_TOKEN` are already wired — verified.
- [ ] 3.5 Verify every new path glob matches at least one real file.

## Phase 4 — Records, docs, reconciliation, merge

- [ ] 4.1 Write ADR-214 (D1/D2 accepted, D3 adopting). Re-verify the ordinal is free across all `origin/*` refs immediately before merge; a renumber must sweep the plan, this file, and AC12/AC13.
- [ ] 4.2 Apply the C4 edits the 0.5 enumeration identified; run `c4-code-syntax.test.ts`, `c4-render.test.ts` and `c4-count-parity.test.sh`.
- [ ] 4.3 Add the jikigai.com row to `knowledge-base/operations/domains.md` (F2).
- [ ] 4.4 Record the registration renewal in `knowledge-base/operations/expenses.md`.
- [ ] 4.5 Reconcile the three stale artifacts (F3): `article-30-register.md` PA-15 §(g)(4), the outbound-email pilot plan, the LinkedIn re-apply plan.
- [ ] 4.6 Add the Article 32(1)(c) channel-availability TOM to the register's Cross-Cutting TOMs block (CLO P1).
- [ ] 4.7 Comment on #7845 with the two additional register omissions the CLO identified. Do not fold the substance in.
- [ ] 4.8 Merge with `Ref #N`, not `Closes #N`.

## Phase 5 — Retire the DS record FIRST

- [ ] 5.1 Remove the DS at the registrar via the automation ladder; record the rung reached.
- [ ] 5.2 Poll `dig DS jikigai.com @a.gtld-servers.net` until empty.
- [ ] 5.3 Wait ≥48h (1.5 × the 86400s DS TTL) from the moment the parent stops publishing.
- [ ] 5.4 Assert unsigned-but-resolving: no `ad` flag, all mail records still resolve.
- [ ] 5.5 **Lower the parent NS TTL** to 300-3600s and drain it alongside the DS drain (same 48h). Without this the Phase 7 rollback is bounded by 172800s, not 300s.
- [ ] 5.6 Run Guard 2.

## Phase 6 — Create the zone and verify exhaustively

- [ ] 6.1 Commit the restorable snapshot of the Google-side zone.
- [ ] 6.2 Apply the records at 300s TTL.
- [ ] 6.3 Read `cloudflare_zone.jikigai_com.name_servers`.
- [ ] 6.4 Assert **exact set equality** against the Cloudflare REST API — both directions, not a spot check.
- [ ] 6.5 Assert via `dig` against **each** assigned nameserver individually, never through a recursive resolver.
- [ ] 6.6 Confirm no undeclared record exists (the `jump_start` class).
- [ ] 6.7 Run Guard 1. A mismatch blocks the cutover.

## Phase 7 — Flip the nameservers

- [ ] 7.0 **Blocking pre-flight inside the registrar-write step**: re-read the zone; assert one result, id matches state, status pending, `name_servers` set-equal to what is about to be written; re-run Guard 1. A recreate changes both the zone id and the NS pair, so stale values delegate the domain to nameservers serving nothing.
- [ ] 7.1 Replace the four googledomains entries with the Cloudflare nameservers; record the rung reached.
- [ ] 7.2 Poll for zone `status == active`.
- [ ] 7.3 Assert the parent delegation names exactly the expected nameservers.
- [ ] 7.4 Re-assert the full record set through public resolvers.
- [ ] 7.5 Confirm Proton still reports the domain verified and the `protonmail-verification` TXT is byte-identical.
- [ ] 7.6 Assume zero nameserver overlap; do not treat the 48h parent NS TTL as a safety margin.

## Phase 8 — Telemetry and close

- [ ] 8.1 Add `rua=` to the `_dmarc` record — the only post-flip mail-auth telemetry that exists.
- [ ] 8.2 Raise TTLs from 300s after 72h of stability.
- [ ] 8.3 Extend the PA-27 synthetic-liveness-probe pattern to `legal@jikigai.com` (CLO P1 — the durable fix).
- [ ] 8.4a Enrol a **second, date-anchored** follow-through, `earliest` = merge + 14d, asserting only "the zone still exists" — the cutover directive is keyed to a flip date that may never exist.
- [ ] 8.4 Enrol the cutover follow-through with `earliest` = **filing date** (self-gating exit 2 until flip+7d; a far-future `earliest` stops the probe running at all during the window it watches), `secrets=GH_TOKEN,CF_API_TOKEN_JIKIGAI,BETTERSTACK_API_TOKEN`, label `follow-through`.
- [ ] 8.5 File the DNSSEC-restoration follow-through (≥48h post-flip gate + the Squarespace-custom-DS conditional) and the registrar-transfer follow-through (trigger: zone active ≥7d AND date ≥ 2026-10-07 AND mail probe green). Record the dependency edge between them.

## Verification

- [ ] V1 `python3 scripts/lint-guard-contract.py` and `lint-infra-no-human-steps.py --changed --base origin/main` both green.
- [ ] V2 All acceptance criteria AC1-AC23 evidenced in the PR body.
- [ ] V3 Follow-through probe exits 0 on the sweep at flip + 7 days.
- [ ] V4 SMTP acceptance limb passes for both `ops@` and `legal@`, with the catch-all discriminator asserted — the only check that verifies mail is *accepted* rather than merely resolvable, and the only one covering `legal@` at all.
