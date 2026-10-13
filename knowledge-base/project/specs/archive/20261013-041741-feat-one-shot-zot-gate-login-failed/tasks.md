# Tasks — fix(infra): zot gate `login_failed`

Plan: `knowledge-base/project/plans/2026-07-15-fix-zot-gate-login-failed-plan.md`
Lane: `single-domain` · Threshold: `aggregate pattern` · Sentry: `WEB-PLATFORM-5B`

**Phase order is load-bearing.** Phase 1 (the discriminating probe) precedes Phase 2 (the fix) so the fix is
confirmed by telemetry rather than asserted — #6452/#6424/#6421 were three consecutive blind fixes in this area.

## Phase 0 — Preconditions (verify, do not assume)

- [x] 0.1 Confirm `htpasswd -v` is supported on the shipped Ubuntu 24.04 `apache2-utils` build
      (`htpasswd -vb` on a throwaway file locally; exit 0 = match, 3 = mismatch). The Phase 1 probe depends on it.
- [x] 0.2 Confirm the installed Terraform version's `replace_triggered_by` accepts a whole-resource reference
      (`random_password.zot_pull`, not `.result`). Cite the version.
- [x] 0.3 `git grep -n 'target=' .github/workflows/apply-web-platform-infra.yml` — confirm
      `hcloud_server.registry` is inside the `-target=` allow-list. **If it is not, the apply is a silent no-op**
      and the plan must gain a task to extend the allow-list (plus its guard suites — see the target-allowlist
      Sharp Edge).
- [x] 0.4 Re-run the Sentry + Better Stack probes from the plan's §Evidence to confirm E1/E2 still hold at
      /work time (the drift-snapshot staleness trap). Note the current `WEB-PLATFORM-5B` count.
- [x] 0.5 `grep -n 'rotat' knowledge-base/engineering/architecture/decisions/ADR-096-*.md` — does ADR-096 restate
      the false "one apply re-propagates htpasswd" guarantee? If yes, add it to Phase 2 scope.

## Phase 1 — Make the failure discriminating (ships first)

- [x] 1.1 **RED**: `ci-deploy.test.sh` — 5 failing cases, one per `zot_login_class` enum member
      (`authn_rejected`, `authz_denied`, `tls_mismatch`, `transport`, `unclassified`).
- [x] 1.2 **RED**: `ci-deploy.test.sh` — a `tls_mismatch` stderr fixture must NOT classify as `authn_rejected`.
- [x] 1.2b **RED**: `ci-deploy.test.sh` — a `403`/`denied` stderr fixture must classify as `authz_denied`, NOT
      `authn_rejected`. **Load-bearing (deepen-plan finding):** the precedent classifier
      `_pull_result_is_auth_denied` (`ci-deploy.sh:530-532`) buckets `unauthorized|denied|forbidden` TOGETHER.
      Copying it verbatim collapses H3 (401, stale htpasswd) and H4 (403, accessControl) into one bucket and the
      probe cannot discriminate — reintroducing the exact defect this plan fixes. Split 401 from 403.
- [x] 1.3 **RED**: `ci-deploy.test.sh` — payload hygiene: the raw stderr fixture string must be absent from the
      captured Sentry POST body.
- [x] 1.4 **GREEN**: `ci-deploy.sh` — capture `docker login` stderr (drop `>/dev/null 2>&1`); classify content
      into the enum, mirroring the `_pull_result_is_auth_denied` precedent at `:838`.
- [x] 1.5 **GREEN**: `ci-deploy.sh` — add `zot_login_class` + `zot_login_http` tags to `zot_gate_degraded_event`.
      Classify BEFORE emitting; never put raw stderr in the payload.
- [x] 1.6 **GREEN**: `ci-deploy.sh` — add `host_id` to `zot_gate_degraded_event` (reuse the `pull_failure_event`
      precedent from #6396/#6401).
- [x] 1.7 `cloud-init-registry.yml` — add `htpasswd_pull_matches` / `htpasswd_push_matches` (boolean only) to the
      `SOLEUR_ZOT_DISK` line in `zot-disk-heartbeat.sh`, via `htpasswd -vb`. Never emit the token or a hash.

## Phase 2 — Close the credential-convergence gap

- [x] 2.1 **RED**: `registry-insecure-config.test.sh` — assert `hcloud_server.registry` has
      `replace_triggered_by` naming both `random_password.zot_pull` and `random_password.zot_push`.
- [x] 2.2 **RED**: `registry-insecure-config.test.sh` — assert `depends_on` names all three secrets.
- [x] 2.3 **GREEN**: `zot-registry.tf` — add the `lifecycle.replace_triggered_by` block.
- [x] 2.4 **GREEN**: `zot-registry.tf:290` — extend `depends_on` with `doppler_secret.zot_pull_token_registry`
      and `doppler_secret.zot_push_token_registry`.
- [x] 2.5 `zot-registry.tf:78-80` — replace the false rotation comment with what is actually true.
- [x] 2.6 `terraform validate` + `terraform plan` (canonical triplet: export raw `AWS_ACCESS_KEY_ID` /
      `AWS_SECRET_ACCESS_KEY` from `prd_terraform`, `terraform init -input=false`, then
      `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan`). Assert exactly one
      replace (`hcloud_server.registry`), no other create/destroy.

## Phase 2b — H4 arm (conditional)

- [ ] 2b.1 Only if the Phase 1 probe returns `zot_login_http=403` + `htpasswd_pull_matches=true`: H3 is refuted;
      fix zot's `accessControl` at `cloud-init-registry.yml:116-126` instead. Phase 2 still ships regardless
      (proven latent defects).

## Phase 3 — Architecture + docs

- [x] 3.1 Amend ADR-115 `## Decision` with the boot-baked-credential convergence rule; add the two rejected
      alternatives (in-place SSH rewrite; cron-converging htpasswd) to `## Alternatives Considered`.
- [x] 3.2 If Phase 0.5 found it, correct ADR-096's rotation prose in the same PR.
- [x] 3.3 No `.c4` edit — the plan's §C4 enumeration found every actor/system/store/relationship already modeled.
      Re-confirm `spec.c4` at /work per the completeness mandate before relying on the "no impact" conclusion.

## Phase 4 — Exit gate

- [ ] 4.1 Full suite: `bash apps/web-platform/infra/ci-deploy.test.sh` and
      `bash apps/web-platform/infra/registry-insecure-config.test.sh`.
- [ ] 4.2 Verify every AC1-AC9 command literally (run them; do not assert from reading).
- [ ] 4.3 Citation check: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan>` → every path resolves.
- [ ] 4.4 Post-merge AC10-AC12 are automated reads (Better Stack + Sentry). Enroll the soak in the
      follow-through sweeper if AC11 is framed as a multi-release soak rather than a single-deploy check.


## /work verification record (2026-07-15)

Phase 0 preconditions — all VERIFIED, not assumed:

- **0.1 PASS** — `htpasswd -vb` on `ubuntu:24.04` (the shipped host image, not the plan's
  `httpd:alpine` proxy): exit 0 = match, exit 3 = mismatch, token never printed.
- **0.2 PASS** — Terraform v1.10.5; whole-resource `replace_triggered_by` refs accepted
  (`terraform validate` → "The configuration is valid").
- **0.3 PASS (but the plan drew the WRONG conclusion from it)** — `hcloud_server.registry` IS named in
  `-target=` at workflow `:1758`/`:1951`, so the plan's grep passed. Both are `workflow_dispatch` jobs.
  The registry resources are `OPERATOR_APPLIED_EXCLUSION`s and are NOT applied by the merge path at all.
  See the plan's corrected §Infrastructure → Apply path.
- **0.4 PASS** — E1/E2 re-pulled at /work: `WEB-PLATFORM-5B` still count=14 (unchanged since plan time);
  **zero** `registry:zot` issues in 90d ⇒ zot has still never served a pull.
- **0.5 NO-OP (plan item does not fire)** — ADR-096 does NOT restate the false "one apply re-propagates
  htpasswd" claim (`grep -niE 'one apply|re-propagat|htpasswd'` → only ":76 control-plane-minted
  htpasswd/JWT cred"). Phase 3.2 is therefore a no-op, not a skip. AC3's precondition also re-verified:
  the false phrase occurs exactly once in the repo, at `zot-registry.tf:80`.

Phase 2b — **NOT executed.** It is conditional on the Phase 1 probe's post-replace verdict (AC11b), which
cannot exist until the `registry-host-replace` dispatch runs. Phase 2's edges shipped regardless, as the
plan prescribes (they are proven latent defects independent of the H3/H4 outcome).

Phase 3.3 — `.c4` re-confirmed at /work (the plan's completeness mandate). `spec.c4` read directly: it
declares only the `selfhosted` **tag**, whose sole zot reference is a comment ("the self-hosted zot container
registry (ADR-096)"). This change adds no element, tag, or relationship — it alters *when a credential is
re-baked*, not who may reach what. `model.c4`/`views.c4` already carry `zotRegistry` and both views already
`include` it. No `.c4` edit.

Corrections applied to the plan during /work (both were plan errors, committed alongside the fix):
1. §Infrastructure → Apply path: merge does NOT apply this; the `registry-host-replace` dispatch does.
2. AC10 demoted to probe-wiring; AC11 is the fix gate; the "pre-fix returns false" claim removed as
   impossible (the probe ships in user_data, so deploying it repairs the divergence it would have measured).
