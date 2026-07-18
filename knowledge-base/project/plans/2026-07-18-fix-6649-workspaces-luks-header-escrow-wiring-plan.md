---
title: "Wire WORKSPACES_HEADER_BUCKET + R2 creds into the /workspaces LUKS freeze path (C4 escrow)"
issue: 6649
epic: 6604
date: 2026-07-18
branch: feat-one-shot-6649-luks-header-wiring
type: fix-infra
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-119 (amend — no new ADR)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 (IaC Routing Gate) reviewed. The residual `doppler secrets set` steps are genuinely
  operator-required and CANNOT be `doppler_secret` Terraform resources:
    (1) CF_API_TOKEN_R2 is the provider-auth token Terraform itself uses (chicken-and-egg — TF cannot
        mint the credential it authenticates with); it lives in prd_terraform beside the 3 existing
        scoped Cloudflare tokens.
    (2) The R2 S3 API-token creds are dashboard-minted and PROVABLY NOT derivable from any TF resource
        field (learning 2026-05-18-cla-evidence-r2-s3-creds-not-derived.md — sha256(token.value) fails
        SigV4). The BUCKET + bucket-name + endpoint ARE Terraform-managed (see ## Infrastructure (IaC)).
  terraform-architect was invoked at plan time; both steps carry Playwright automation-status: UNVERIFIED.
-->

# 🛠️ fix(infra): wire the /workspaces LUKS header-escrow (C4 off-host bucket + R2 creds)

`Ref #6649` (closed via `gh issue close #6649` AFTER the post-merge R2-cred mint + a GREEN dry-run probe — NOT auto-closed at merge; spec-flow F3). **Part of epic #6604 — do NOT close #6604** (that closes only after the step-7 soak).

## Overview

On a real freeze (`dry_run=false`), `apps/web-platform/infra/workspaces-cutover.sh` backs up the LUKS
header and uploads it off-host via `aws s3 cp "$hdr" "s3://${HEADER_BACKUP_BUCKET}/…"` (`:196`), a
**BLOCKING pre-freeze C4 escrow gate** that dies at `:184` if `WORKSPACES_HEADER_BUCKET` is unset and
at `:197` if the upload fails. Today nothing satisfies it:

- **No bucket is provisioned** — no `cloudflare_r2_bucket`/`aws_s3_bucket` exists in `apps/web-platform/infra/*.tf`.
- **Nothing reaches the host** — the freeze runs on web-1 via `ssh "$WEB_HOST" "sudo DRY_RUN='…' ROLLBACK='…' bash -s"` (`workspaces-luks-cutover.yml:166`); only `DRY_RUN`/`ROLLBACK` cross the SSH+`sudo` boundary.
- **The dry-run hides it** — the whole header block is gated by `if [ "$DRY_RUN" != "1" ]`, so a green dry-run gives false confidence.

This is a wiring gap in the cutover mechanism (fail-safe: the freeze aborts BEFORE touching data), not
an operator omission. This plan lands the **additive freeze prep** — the escrow that must exist before
the freeze — with **no data-path change**, following the issue's "Recommended fix (secure)" exactly.

**Scope:** (1) provision an off-host Cloudflare R2 bucket via Terraform, distinct from
`soleur-terraform-state` (C4 different blast radius), riding the DEFAULT allow-list apply; (2) deliver
the bucket name + R2 S3 creds + endpoint to web-1 host-side via the pinned
`doppler secrets get … --plain --config prd_workspaces_luks` form (mirroring the `WORKSPACES_LUKS_KEY`
read at `:59`) — never on the sudo command line, never via `doppler run`/`download`; (3) add a wiring
test; plus two correctness fixes the wiring exposes (the `aws` calls target real AWS today; and no S3
client is provisioned on web-1) and a DRY_RUN-safe escrow-reachability probe.

## Enhancement Summary (deepen-plan, 2026-07-18)

**Research/gate agents:** terraform-architect + CTO + functional-discovery + learnings-researcher (plan-time); security-sentinel + architecture-strategist + code-simplicity-reviewer + spec-flow (deepen review panel). Gates 4.6/4.7/4.9 pass; 4.8 PAT-match is a Cloudflare-token false-positive; 4.5/4.55 N/A (see Gate reconciliations).

**Load-bearing deltas folded in:**
1. **Dry-run probe is a PUT, not `head-bucket`** (spec-flow F1 + simplicity #2) — a read-only probe false-greens an Object-Read-only token that then dies at the real freeze's PUT. One probe-PUT (write→read-back→delete) subsumes reachability + auth + endpoint + cred-shape + writability.
2. **Probe runs OUTSIDE the `DRY_RUN != 1` gate** (spec-flow F2) — a probe inside the gate is inert and re-creates the false-green the issue targets; mutation-tested AC added.
3. **`Ref #6649` + post-mint `gh issue close`, NOT `Closes` at merge** (spec-flow F3) — the escrow is non-functional until the post-merge cred mint.
4. **Negative probe** — escrow creds MUST be DENIED against `soleur-terraform-state` (security F2); the `:185` name-compare cannot catch an over-scoped account-wide token.
5. **Post-provision cross-config assertion** — the R2 secret must be in `prd_workspaces_luks` and ABSENT from `prd` root (security F3).
6. **`aws` CLI: SHA-pinned live on-demand install (load-bearing for web-1) + preflight-die** (security F1 + architecture P1) — web-1's `ignore_changes=[user_data]` + unrebuildability means cloud-init is future-host-only, so the in-script install is the REAL delivery and must be pinned, not dropped (this overrides simplicity #3's "cloud-init + redeploy").
7. **Endpoint derived from `var.cf_account_id`**, dropping the duplicated literal + a drift-guard test (simplicity #1).
8. **Per-field fail-loud** on all 4 host reads (`read_key`'s `|| true` swallows failures to empty); **pre-merge stubbed-`aws`/`doppler` harness** makes the fail-loud claim testable at PR time (spec-flow F6).
9. **Stale die text** at `:197`/`:199` updated (creds are host-side now, not workflow-env; spec-flow F7).

**Residual items carried for /work (lower severity, do not re-litigate):**
- **R2 token revoke/rotate runbook** (spec-flow F4) — the one credential the User-Brand Impact names has no recovery path; add: revoke in CF → re-mint bucket-scoped → re-write `prd_workspaces_luks` → re-run dry-run probe.
- **Revert story** (spec-flow F5) — `prevent_destroy` blocks `terraform destroy`; the infra half is forward-only (revert the script wiring only; `terraform state rm` + manual bucket disposition if the bucket must go).
- **R2 object immutability residual** (security F5) — `prevent_destroy` guards Terraform, not an API-delete by the Object-R&W escrow token; either add R2 object-retention (cla-evidence `object_lock.tf` precedent) or document that the escrow copy is deletable by the same token that writes it.
- **Host-token blast radius** (security F4) — the `prd_workspaces_luks` host token inherits all ~116 `prd` root secrets (pre-existing for `WORKSPACES_LUKS_KEY`, tracked by #6167); name it in the ADR threat-model since the escrow now depends on the same token.
- **Probe key isolation + cleanup** (security F7 / spec-flow F8) — namespaced `.probe/` key, deleted after.

## Research Reconciliation — Spec vs. Codebase

<!-- lint-infra-ignore start: retrospective premise-vs-codebase VALIDATION table (what was verified on main) — describes the escrow MECHANISM this PR automates, not a runtime step a Soleur user performs -->

| Spec/issue premise | Codebase reality (verified) | Plan response |
|---|---|---|
| "read the R2 creds/endpoint via the pinned scoped-config read … existing R2 backend creds may already be readable — verify scope" | The R2/AWS tfstate backend creds live in the **`prd_terraform` BRANCH** config (`tunnel.tf:230-245`). `prd_workspaces_luks` is a branch of **`prd`** and inherits **only** the `prd` root — branch configs do NOT propagate to each other. So the host **cannot** read the tfstate creds via `prd_workspaces_luks`. **Dedicated escrow creds MUST be written into `prd_workspaces_luks`.** | Provision escrow bucket-name + R2 creds + endpoint as secrets in `prd_workspaces_luks`. |
| "provision … a Cloudflare R2 bucket reachable from `terraform apply`" | web-platform's `var.cf_api_token` is scoped **"Tunnel, Access, DNS, Notifications"** (`variables.tf`) — **not** R2. cla-evidence's same-named var carries "R2 admin + API tokens management" but that is a **separate root** with its own broad token. Creating a `cloudflare_r2_bucket` needs a provider token with **Workers R2 Storage:Edit**. | **Phase 0 live-probe** the token's R2 scope. If present → use default provider. If absent → new scoped provider alias `cloudflare.r2` + no-default `var.cf_api_token_r2` (R2:Edit), sequenced per ADR-065. See Sharp Edge #1. |
| (cla-evidence `outputs.tf` prose) "R2 S3 secret_access_key = `sha256(token.value)`" — the terraform-architect research agent also recommended `secret_access_key = sha256(cloudflare_api_token.value)` | **REFUTED, empirically.** Learning `2026-05-18-cla-evidence-r2-s3-creds-not-derived.md` proved (real R2 error body, PR #3965) that `sha256(token.value)` fails SigV4 `SignatureDoesNotMatch`. R2 S3-compat creds are issued **only** by minting an **R2 API Token** (Storage → R2 → Manage API Tokens → Create Account API token), which returns a 32-char accessKeyId + 64-char secretAccessKey shown once — **not derivable** from any `cloudflare_api_token` field. | **Do NOT derive.** The R2 S3 creds are an operator/Playwright-minted **R2 API Token** → written to `prd_workspaces_luks`. Only the bucket, bucket-name secret, and endpoint secret are TF-managed. A **probe-PUT gate** (mirroring `cla-evidence/infra/bootstrap.sh`) measures the creds before they are trusted. See Sharp Edge #2. |
| "backs up the LUKS header and uploads it with `aws s3 cp`" | The `aws s3 cp` / `aws s3api head-object` at `:196`/`:198` pass **no `--endpoint-url`, no region, no creds** — against R2 they resolve to real AWS S3 and die on auth. And **no `aws` CLI is installed on web-1** by cloud-init/`soleur-host-bootstrap.sh`, and the script never checks for it. | The script edit adds `--endpoint-url`, `AWS_DEFAULT_REGION=auto`, the checksum env, and host-side cred exports; plus an `aws`-presence preflight (loud die) and a durable install path. See Phase 2 + Sharp Edge #3. |
| "add a wiring test … alongside `workspaces-luks.test.sh`" | `workspaces-luks.test.sh` A11 (`p_no_laundering_resource:213`) asserts **file-scoped exact cardinality** on `workspaces-luks.tf`: exactly one `doppler_secret`/`doppler_service_token`/`random_password`/`hcloud_volume`, and `config = "prd"` nowhere. Adding any escrow `doppler_secret` **into that file turns A11 RED.** | Escrow resources live in a **separate file** `workspaces-luks-header.tf`; the wiring test carries a parallel addition-blind guard for that file. See Phase 1 + Phase 3. |

<!-- lint-infra-ignore end -->

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — the escrow gate is fail-safe. A wiring
bug dies BEFORE the freeze touches sole-copy data (identical to today), so the concrete failure artifact
is an aborted cutover run + a `workspaces-luks-drift` Sentry event, not data loss. The freeze simply
cannot complete until the wiring is correct.

**If this leaks, the user's data is exposed via:** the R2 escrow credential crossing the SSH+`sudo`
boundary. The realistic exposure vector is a **confidentiality regression** — R2 creds leaking to the
host process list / audit log (an argv mistake) or CWE-522 re-exposure into the agent container's
`--env-file`. The credential is low-value **only while it is bucket-scoped**: it then reaches one bucket
of LUKS **headers**, which are inert without the separately-held passphrase (`WORKSPACES_LUKS_KEY`,
unchanged by this PR). **The true worst case is an OVER-SCOPED (account-wide) escrow token** — a
plausible operator mint error: it can reach `soleur-terraform-state`, which holds
`random_password.workspaces_luks.result` (the passphrase) in **plaintext state**, so header-access +
plaintext-passphrase = **full decryption of the user's sole-copy source**. The control that keeps the
credential low-value is the **negative over-scope probe** (`escrow_probe`, the
`head-bucket … "$TFSTATE_BUCKET"` leg → `emit_drift escrow_creds_overscoped; die`), which fails the
freeze CLOSED if the token is not bucket-scoped (and, post-review, on an inconclusive/transport error
rather than trusting a bare non-zero). That probe is itself drift-guarded by test H10.

**Brand-survival threshold:** single-user incident. Justification (CTO-confirmed): the escrow path
itself carries **no data-loss** risk (fail-safe before the freeze), so it is not `none` only because it
delivers new secret material across the sudo boundary and mutates the secret-inheritance surface the
at-rest guarantee depends on — a single-user-class *confidentiality* incident, bounded to a low-value
credential. The **aggregate** sole-copy-data-destruction risk belongs to the #6604 freeze itself, which
is why this prep issue stays distinct and must not close #6604. `requires_cpo_signoff: true`;
`user-impact-reviewer` runs at review-time.

## Infrastructure (IaC)

### Terraform changes

New file **`apps/web-platform/infra/workspaces-luks-header.tf`** (SEPARATE from `workspaces-luks.tf` —
A11 cardinality landmine, above):

- `cloudflare_r2_bucket.workspaces_luks_header` — `account_id = var.cf_account_id`, `name = "soleur-workspaces-luks-header"`, `location = "WEUR"` (provider v4 attribute is `location`, not `location_hint`), `lifecycle { prevent_destroy = true }`. Distinct from `soleur-terraform-state` by construction. Provider pinned to `cloudflare.r2` (Phase-0-dependent — see Apply path).
- `doppler_secret.workspaces_luks_header_bucket` — `project="soleur"`, `config="prd_workspaces_luks"`, `name="WORKSPACES_HEADER_BUCKET"` (the exact name the script reads), `value = cloudflare_r2_bucket.workspaces_luks_header.name` (a **reference**, never a literal — the distinctness edge), `visibility="masked"`.
- `doppler_secret.workspaces_luks_header_r2_endpoint` — `name="WORKSPACES_HEADER_R2_ENDPOINT"`, `value = local.r2_s3_endpoint` where `local.r2_s3_endpoint = "https://${var.cf_account_id}.r2.cloudflarestorage.com"` (account-root, path-style — the bucket goes in the S3 path, NOT a bucket-suffixed host), `visibility="masked"`. **Derive from the existing `var.cf_account_id`, do NOT hardcode the account-id literal** (simplicity #1): correct-by-construction, removes the duplicated magic constant AND the drift-guard test that would otherwise be needed to keep a literal in sync with the `main.tf` backend endpoint.

**R2 S3 credentials are NOT Terraform-managed** (Research Reconciliation row 3): the `WORKSPACES_HEADER_R2_ACCESS_KEY_ID` (32-char) + `WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY` (64-char) are an operator/Playwright-minted **R2 API Token** written to `prd_workspaces_luks` (a Post-merge operator step — see AC). A `cloudflare_api_token` resource is NOT created (it cannot be reused as a SigV4 pair, and this escrow needs no CF management-API Bearer calls).

If Phase 0 finds the primary `cf_api_token` lacks R2:Edit: add to **`main.tf`** `provider "cloudflare" { alias = "r2"  api_token = var.cf_api_token_r2 }` (mirrors the 3 existing scoped aliases), and to **`variables.tf`** a no-default `sensitive` `var.cf_api_token_r2` (scope: Workers R2 Storage:Edit only — no API Tokens:Edit needed since no token resource is minted).

### Apply path

<!-- lint-infra-ignore start: deferred-orchestrator apply-path MECHANISM (CI-driven default-apply + ADR-065 pre-merge var sequencing) this PR builds — the pre-merge var provision is surfaced as an operator step in the PR body, not run by a Soleur user here -->

- **cloud-init + idempotent behaviour, riding the DEFAULT allow-list apply.** The new `cloudflare_r2_bucket` + 2 `doppler_secret`s are appended to the default `-target=` list in `.github/workflows/apply-web-platform-infra.yml` (at/after **line 361**, beside `github_repository_environment.workspaces_luks_cutover` — the established precedent for a workspaces-luks resource that rides the default apply). CI *can* create Cloudflare + Doppler resources, so they are NOT `OPERATOR_APPLIED_EXCLUSIONS`. Merge → the push/`apply_target=manual-rerun` apply creates them.
- **Do NOT** attach them to `apply_target=workspaces-luks-cutover`: that job's `workspaces_luks_cutover_gate` (`tests/scripts/lib/workspaces-luks-cutover-gate.sh`) permits EXACTLY the 5 volume/attachment/passphrase/secret/token creates; a 6th create reddens `out_of_scope`.
- `plugins/soleur/test/terraform-target-parity.test.ts` "every managed resource has a `-target` or exclusion" (general coverage test) passes automatically once the `-target` lines exist — no exclusion-set edit. The `doppler_secret`s are the `doppler_secret` type, so the "every CI-publish token targeted" assertion does not bind them.
- **Sequencing (ADR-065, if a new var is introduced):** operator provisions `CF_API_TOKEN_R2` into `prd_terraform` **BEFORE** merge — Terraform resolves all root vars before `-target` pruning, so an unprovisioned no-default var fails the WHOLE merge-triggered apply. Only after that does the PR merge. (No new var → no pre-merge provision; this branch is chosen only if Phase 0 shows the token lacks R2:Edit.)

<!-- lint-infra-ignore end -->

### Distinctness / drift safeguards

- Runtime C4 enforcement already exists: `workspaces-cutover.sh:185` `[ "$HEADER_BACKUP_BUCKET" != "$TFSTATE_BUCKET" ] || die`.
- TF-side guard (new test): the `WORKSPACES_HEADER_BUCKET` value MUST be `cloudflare_r2_bucket.workspaces_luks_header.name` (a reference), never the literal `soleur-terraform-state`; and no `doppler_secret` in the escrow file targets `config = "prd"` (the CWE-522 A11 leg, applied to the escrow file). **The `config = "prd"` guard MUST use the END-ANCHORED regex** (`^…config…=…"prd"[[:space:]]*$`, copied from `workspaces-luks.test.sh:216`) — a naive `grep 'config.*"prd"'` false-matches `config = "prd_workspaces_luks"` and the guard would be permanently RED (architecture P2). Anchor on the resource address (a bare grep is addition-blind — learning `2026-07-17-a-drift-guard-scoped-by-resource-name-is-addition-blind.md`); pin cardinality.
- `prevent_destroy` on the bucket converts an accidental `-destroy`/rename into a plan-time error rather than silent escrow loss.

### Vendor-tier reality check

R2 has no S3 conditional writes ⇒ no state lock (irrelevant here; escrow objects are write-once, keyed
`workspaces-luks-header-${live_uuid}.img`). Storage + Class-A/B ops for a handful of ~2-16 MB header
images are well within R2's free tier; egress is zero-rated. No meaningful spend; no new recurring
vendor expense to record. *Pricing reflects training data — verify at the provider's pricing page before
budget decisions.* Location `WEUR` matches the EU residency posture of the encrypted data.

## Observability

```yaml
liveness_signal:
  what: "DRY_RUN-safe escrow probe-PUT — write a tiny namespaced object (.probe/<run-id>) to the header bucket via aws --endpoint-url … s3 cp, read it back (head-object), then delete it. Proves reachability + auth + endpoint + cred-shape + WRITABILITY in one round-trip (a read-only head-bucket would false-green an Object-Read-only token, which then dies at the real :196 PUT). PLUS a NEGATIVE probe: the same escrow creds MUST be DENIED (403) against soleur-terraform-state — a success proves an over-scoped account-wide token and MUST emit_drift + die (the :185 name-compare cannot catch over-scoping). Both run in the dry-run arm — a GREEN signal BEFORE any irreversible freeze."
  cadence: "every workspaces-luks-cutover.yml dispatch (dry-run and real)"
  alert_target: "the workflow run + step summary; failures also emit_drift → Sentry"
  configured_in: "apps/web-platform/infra/workspaces-cutover.sh — the probe block is lifted OUT of the existing `if [ \"$DRY_RUN\" != \"1\" ]` gate at :173 (or duplicated into the else arm) so it actually runs during the rehearsal; a probe placed inside that gate is inert and re-creates the false-green (spec-flow F2)"
error_reporting:
  destination: "Sentry (feature=workspaces-luks op=workspaces-luks-drift) via workspaces-luks-emit.sh"
  fail_loud: true   # emit_drift on every escrow failure leg; the die aborts before the freeze
failure_modes:
  - mode: "escrow bucket/creds unreadable on host (any of the 4 doppler reads empty)"
    detection: "load_escrow_creds per-field [ -n ] check → emit_drift header_creds_unreadable; die (before aws)"
    alert_route: "Sentry workspaces-luks-drift + non-zero workflow run"
  - mode: "escrow bucket == tfstate bucket (distinctness violated)"
    detection: "load_escrow_creds compare → emit_drift header_bucket_equals_tfstate; die"
    alert_route: "Sentry workspaces-luks-drift + non-zero workflow run"
  - mode: "aws CLI absent / install failed on web-1"
    detection: "ensure_aws → emit_drift aws_cli_absent; die (download/unzip/install/post-install-absence)"
    alert_route: "Sentry workspaces-luks-drift + non-zero workflow run"
  - mode: "aws-cli installer SHA256 mismatch (possible tampering)"
    detection: "ensure_aws sha256sum -c gate → emit_drift aws_cli_sha_mismatch; die"
    alert_route: "Sentry workspaces-luks-drift + non-zero workflow run"
  - mode: "escrow probe-PUT / read-back fails (wrong creds/endpoint/checksum/writability)"
    detection: "escrow_probe → emit_drift escrow_probe_put_failed / escrow_probe_readback_failed; die (runs in the DRY_RUN arm — one rehearsal before the freeze)"
    alert_route: "Sentry workspaces-luks-drift + non-zero workflow run"
  - mode: "escrow creds are OVER-SCOPED (reach soleur-terraform-state)"
    detection: "escrow_probe negative probe: head-bucket against $TFSTATE_BUCKET → emit_drift escrow_creds_overscoped; die"
    alert_route: "Sentry workspaces-luks-drift + non-zero workflow run"
  - mode: "over-scope negative probe INCONCLUSIVE (transport error, not a 403)"
    detection: "escrow_probe fail-closed branch → emit_drift escrow_negprobe_inconclusive; die"
    alert_route: "Sentry workspaces-luks-drift + non-zero workflow run"
  - mode: "real header upload/read-back fails (real-freeze arm)"
    detection: "existing emit_drift header_backup_upload_failed / header_backup_unverified (aws s3 cp / head-object with --endpoint-url); the DRY_RUN probe catches it one rehearsal earlier"
    alert_route: "Sentry workspaces-luks-drift"
logs:
  where: "GitHub Actions run logs + host journald (workspaces-luks-emit.sh); NO SSH needed"
  retention: "Actions default; Sentry event retention"
discoverability_test:
  command: "gh run view <run-id> --log  # + Sentry op=workspaces-luks-drift search (no-SSH path)"
  expected_output: "on failure: a workspaces-luks-drift event with WL_REASON in {header_creds_unreadable, header_bucket_equals_tfstate, aws_cli_absent, aws_cli_sha_mismatch, escrow_probe_put_failed, escrow_probe_readback_failed, escrow_creds_overscoped, escrow_negprobe_inconclusive, header_backup_upload_failed, header_backup_unverified}"
```

## Architecture Decision (ADR/C4)

Escrow-to-a-distinct-bucket is already ADR-119's decision (§'The LUKS header is an independent terminal
limb', C4). This plan implements it; it does **not** open a new architectural axis → **no new ADR**.

### ADR
Amend **ADR-119** with a one-paragraph addendum recording the *implementation* decision: the escrow
credential is a **distinct, bucket-scoped R2 API token** delivered via `prd_workspaces_luks`, and it
must **never** also reach `soleur-terraform-state` (which holds `random_password.workspaces_luks.result`
in plaintext state) — reusing the tfstate R2 token would hand a host-compromise adversary write/read on
the passphrase-bearing state bucket (the real C4 property for this issue). Record the residuals: the header
bucket's confidentiality-at-rest is already gated on tfstate secrecy (not improved by escrow); the
`prd_workspaces_luks` host token inherits all ~116 `prd` root secrets (pre-existing, #6167), and the escrow
now depends on that same token; and `prevent_destroy` protects the bucket only against Terraform, not against
an API-delete by the Object-R&W escrow token (consider R2 object-retention — cla-evidence `object_lock.tf`).

### C4 views
Edit the model directly (this feature's lifecycle, not a deferred issue). Enumeration checked against all
three `.c4` files (`knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`):
- **External human actors:** none new (the operator triggers via the already-modelled dispatch).
- **External systems:** Cloudflare (`cloudflare`, "DNS, CDN, R2 storage, …") is already modelled; the header-escrow **bucket** is a new R2 data-store not yet represented, and there is **no `hetzner → cloudflare` edge for the header upload** today (only `doppler → hetzner` for the passphrase at model.c4:390).
- **Relationships that change:** add a `hetzner -> cloudflare` edge — "uploads the LUKS header backup off-host to an R2 bucket DISTINCT from tfstate (C4 escrow, blocking pre-freeze gate)"; and amend the `doppler -> hetzner` edge description to note the R2 escrow creds are delivered via the same `prd_workspaces_luks` scoped-read path.
- Add the new edge to the relevant `views.c4` `include` so it renders; run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after editing.
- **Honest C4 limitation (architecture P2):** a single `hetzner → cloudflare` edge collapses both R2 buckets (tfstate + header) into the one `cloudflare` node, so the diagram does NOT visually encode the "distinct blast radius" property — that distinctness lives only at runtime (`workspaces-cutover.sh:185`) + the new TF test. State this in the ADR addendum rather than implying the diagram encodes it.

## Implementation Phases

<!-- lint-infra-ignore start: implementation-phase MECHANISM this PR builds (terraform/script/test edits authored in-PR + one ADR-065 pre-merge operator var-provision, surfaced separately in the PR body) — not runtime steps a Soleur user performs -->

**Phase 0 — Preflight / verification (blocking; resolves the two contested decisions).**
1. **Provider R2 scope:** determine whether the existing `cf_api_token` (as stored in `prd_terraform`) can create a `cloudflare_r2_bucket` — via a scoped `terraform plan -target='cloudflare_r2_bucket.workspaces_luks_header'` on a throwaway branch, or a CF token-verify/permission-groups read. Result decides: default provider (no new var) vs new `cloudflare.r2` alias + `var.cf_api_token_r2` (ADR-065 pre-merge provision). Record the finding in the plan/PR. Do NOT assert scope from the var description (`hr-verify-repo-capability-claim-before-assert`).
2. **R2 cred contract:** confirm from learning `2026-05-18-cla-evidence-r2-s3-creds-not-derived.md` that S3 creds are a minted R2 API Token, not `sha256(token.value)`. The Phase 3 probe-PUT is the live measurement.
3. **aws CLI on web-1:** cloud-init + `soleur-host-bootstrap.sh` show no install — treat as absent (high confidence). Decide the durable path (Phase 2): a `command -v aws` preflight (loud die) + on-demand idempotent install in the escrow block, and a cloud-init addition for future boots.

**Phase 1 — Terraform (IaC).** Create `workspaces-luks-header.tf` (bucket + 2 doppler_secrets + `local.r2_s3_endpoint`); conditionally add the `cloudflare.r2` alias + `var.cf_api_token_r2`; append the 3 new managed-resource `-target=` lines to the default apply list in `apply-web-platform-infra.yml` (near :361). `terraform validate` early (provider v4 attribute names).

**Phase 2 — Host-side script (`workspaces-cutover.sh`).** Add pinned host-side reads mirroring `read_key()` (`:59`): `WORKSPACES_HEADER_BUCKET`, `WORKSPACES_HEADER_R2_ACCESS_KEY_ID`, `WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY`, `WORKSPACES_HEADER_R2_ENDPOINT` — each `doppler secrets get <NAME> --plain --config prd_workspaces_luks`, never argv, never `doppler run`/`download`. **Per-field fail-loud (security + spec-flow):** `read_key`'s `2>/dev/null || true` swallows a failed read into an empty string, so each of the 4 reads MUST be individually `[ -n ]`-checked → `emit_drift header_creds_unreadable; die` (a half-populated cred pair must die BEFORE `aws`, not surface as a confusing mid-freeze SigV4 error). In the escrow block: export `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, set `AWS_DEFAULT_REGION=auto` + `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` + `AWS_RESPONSE_CHECKSUM_VALIDATION=when_required` (aws-cli ≥2.23 sends CRC32 checksums R2 rejects), and add `--endpoint-url "$WORKSPACES_HEADER_R2_ENDPOINT"` to BOTH the `cp` and `head-object`. **`aws` CLI presence (security F1 + architecture P1 — reconciled):** web-1 carries `lifecycle { ignore_changes = [user_data] }` and is unrebuildable (cx33), so a cloud-init addition reaches ONLY future hosts — it can NOT deliver `aws` to the running web-1. Therefore the **live on-demand install in the escrow block is the real (load-bearing) delivery for web-1, not a convenience** — do NOT drop it. Because it runs as root with `$KEY` live in memory just before the freeze, it MUST be **SHA256-pinned** (fetch a pinned aws-cli-v2 artifact + verify the digest, mirroring the `CLOUDFLARED_SHA256` pattern at `workspaces-luks-cutover.yml:50`), idempotent, and emit an observability breadcrumb. Add the cloud-init install too, labelled **future-host coverage only** (so nobody "completes" the cloud-init path and assumes web-1 is covered). The `command -v aws` preflight (`emit_drift aws_cli_absent; die`) is the loud safety net after the install attempt. **Update the now-stale die text** at `:197`/`:199` ("the workflow env must provide S3 creds") — after this change creds are host-side via Doppler, so redirect the operator to the `prd_workspaces_luks` reads (spec-flow F7). Header temp file: prefer a mode-0700 dir under `$STATE_DIR` over shared `/tmp` (a tmpfs `/tmp` makes the `shred -u` at `:201` a no-op; security F7).

**Phase 3 — Wiring test + DRY_RUN probe.** Extend `workspaces-luks.test.sh` (or a new `workspaces-luks-header.test.sh` registered in `infra-validation.yml`) mirroring the multi-artifact `git-data-luks.test.sh` shape (reads `.tf` + `.sh`), mutation-tested. Assert: (a) `cloudflare_r2_bucket.workspaces_luks_header` exists, its `name =` argument literal is `soleur-workspaces-luks-header` (≠ `soleur-terraform-state`), and `WORKSPACES_HEADER_BUCKET.value` is a **reference expression** (`cloudflare_r2_bucket.workspaces_luks_header.name`), not a literal (spec-flow F9 — at PR time nothing "resolves"; assert the argument form); (b) file-scoped addition-blind guard on `workspaces-luks-header.tf` (no `config = "prd"`; escrow doppler_secrets masked); (c) the script reads bucket + all R2 creds via `doppler secrets get … --config prd_workspaces_luks`; (d) the creds never appear on a `sudo … bash -s` command line and the workflow env never carries them; (e) no `doppler run`/`secrets download` for the escrow reads; (f) **the probe call is NOT lexically within the `if [ "$DRY_RUN" != "1" ]` block** (spec-flow F2 — mutation: move it inside → RED). Add the DRY_RUN-safe **probe-PUT** (write→read-back→delete of a namespaced `.probe/<run-id>` key) + the **negative probe** (escrow creds DENIED against `soleur-terraform-state`) to the script's dry-run arm. **Pre-merge fail-loud harness (spec-flow F6):** a function-level shell test that sources the escrow function with stubbed `aws`/`doppler` and asserts the empty-cred path exits non-zero + `emit_drift` — so Test Scenario 6 is a green-cannot-stay-green predicate at PR time, not a post-merge hope. Mirror the probe-PUT credential-shape check from `cla-evidence/infra/bootstrap.sh`.

**Phase 4 — ADR/C4 + registration sweep.** ADR-119 addendum; `model.c4`/`views.c4` edges; run c4 tests. Sweep all guard suites touched by the `-target` extension (`terraform-target-parity.test.ts`, and grep `tests/scripts/` for any destroy-guard scope guard that enumerates resource types — learning `2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md`).

<!-- lint-infra-ignore end -->

## Files to Create
- `apps/web-platform/infra/workspaces-luks-header.tf` — bucket + 2 doppler_secrets + `local.r2_s3_endpoint` (+ conditional provider-alias usage).
- (optional) `apps/web-platform/infra/workspaces-luks-header.test.sh` — if a separate test file is preferred over extending `workspaces-luks.test.sh` (register in `infra-validation.yml`).

## Files to Edit
- `apps/web-platform/infra/workspaces-cutover.sh` — host-side R2 cred/bucket/endpoint reads; `aws` `--endpoint-url`+region+checksum+creds; `aws`-presence preflight + install; new emit_drift leg; DRY_RUN probe.
- `apps/web-platform/infra/main.tf` — (conditional) `provider "cloudflare" { alias = "r2" }`.
- `apps/web-platform/infra/variables.tf` — (conditional) no-default `sensitive` `var.cf_api_token_r2`.
- `.github/workflows/apply-web-platform-infra.yml` — 3 new `-target=` lines in the default allow-list (near :361).
- `apps/web-platform/infra/workspaces-luks.test.sh` (or new test file) — the wiring assertions.
- `.github/workflows/infra-validation.yml` — register the new test step (only if a new test file).
- `knowledge-base/engineering/architecture/decisions/ADR-119-*.md` — addendum.
- `knowledge-base/engineering/architecture/diagrams/{model,views}.c4` — escrow edge.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **Merge precondition:** the `prd_workspaces_luks` Doppler config must already exist (same operator precondition as `workspaces-luks.tf:95`; #6604 provisions it) — else the escrow `doppler_secret` creates fail on the merge-apply (architecture P2).
- [ ] `workspaces-luks-header.tf` declares `cloudflare_r2_bucket.workspaces_luks_header` (name `soleur-workspaces-luks-header`, `location="WEUR"`, `prevent_destroy`) + `doppler_secret.workspaces_luks_header_bucket`/`_r2_endpoint` (config `prd_workspaces_luks`, masked). No escrow resource lives in `workspaces-luks.tf` (A11 stays green: `bash apps/web-platform/infra/workspaces-luks.test.sh` passes).
- [ ] `WORKSPACES_HEADER_BUCKET` doppler value is a reference to `cloudflare_r2_bucket.workspaces_luks_header.name`, and the resolved bucket literal ≠ `soleur-terraform-state` (asserted by the new test).
- [ ] `workspaces-cutover.sh` reads bucket + all 3 R2 secrets via `doppler secrets get <NAME> --plain --config prd_workspaces_luks`; `grep` proves none appear on the `sudo … bash -s` line and the workflow `env:` never carries them; no `doppler run`/`secrets download` for these reads.
- [ ] `aws s3 cp` and `aws s3api head-object` both carry `--endpoint-url "$WORKSPACES_HEADER_R2_ENDPOINT"`; region=auto and the checksum env are set; an `aws`-presence preflight exists.
- [ ] The 3 new resource addresses appear in the default `-target=` list in `apply-web-platform-infra.yml` and NOT in `apply_target=workspaces-luks-cutover`; `terraform-target-parity.test.ts` passes; no other guard suite reddens.
- [ ] New/extended wiring test passes and every predicate is mutation-tested (green cannot stay green under the broken mutant), including: the probe is NOT inside the `DRY_RUN != 1` gate (moving it in → RED), and the pre-merge stubbed-`aws`/`doppler` harness proves the empty-cred path exits non-zero + `emit_drift`.
- [ ] ADR-119 addendum + `model.c4`/`views.c4` escrow edge added; c4 syntax+render tests pass.
- [ ] `terraform validate` clean; `tsc`/relevant test suites green. **PR body uses `Ref #6649` (NOT `Closes`)** — the escrow is non-functional at merge (creds are minted post-merge), so auto-closing would close an issue whose own post-merge AC is unmet and could green-light the #6604 freeze on a prep that isn't usable (spec-flow F3). Reference #6604 as "Part of" (never Closes).

### Post-merge (operator)
- [ ] **(Provision pre-merge if Phase 0 shows the token lacks R2:Edit)** Operator provisions `CF_API_TOKEN_R2` (Workers R2 Storage:Edit) into Doppler `prd_terraform` **before** merge. `automation-status: UNVERIFIED — /work MUST attempt a Playwright mint (soleur:provision-cloudflare) before any operator handoff`; a CF dashboard token mint under an authenticated session is presumptively automatable.
- [ ] Confirm the merge-triggered default apply completed GREEN (bucket + both doppler_secrets created) BEFORE minting creds / dispatching the dry-run (spec-flow F10 — a dry-run before apply-completion fails loud but wastes a cycle).
- [ ] After the merge-apply creates the bucket: operator mints an **R2 API Token** (Object Read & Write, scoped to `soleur-workspaces-luks-header` only) and provisions `WORKSPACES_HEADER_R2_ACCESS_KEY_ID` (32-char) + `WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY` (64-char), **`masked`**, into `prd_workspaces_luks`. `automation-status: UNVERIFIED — /work MUST attempt Playwright first`. The probe-PUT must return 200/201 before the creds are trusted.
- [ ] **Post-provision cross-config assertion (security F3):** `WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY` is present in `prd_workspaces_luks` AND **absent from `prd` root** (`doppler secrets get … --config prd --plain` fails/empty) — catches a fat-fingered `--config prd` that would re-open the CWE-522 container leak.
- [ ] A `dry_run=true` dispatch of `workspaces-luks-cutover.yml` shows BOTH the escrow probe-PUT GREEN **and** the negative probe GREEN (escrow creds DENIED 403 against `soleur-terraform-state` — proves the token is bucket-scoped, not account-wide; security F2) before any real freeze is authorized. THEN `gh issue close #6649`.

## Test Scenarios
1. A11 regression: adding a `doppler_secret` into `workspaces-luks.tf` still reddens A11 (unchanged); the escrow file's parallel guard reddens on a `config = "prd"` addition.
2. Command-line-leak mutant: injecting an R2 cred into the `sudo … bash -s` argv → new test RED.
3. `doppler run`/`download` mutant for an escrow read → new test RED.
4. Missing `--endpoint-url` mutant on either `aws` call → new test RED.
5. Bucket == tfstate mutant (name literal `soleur-terraform-state`) → new test RED.
6. DRY_RUN probe: with creds unset, the dry-run probe fails loud (emit_drift) and the run is non-zero — the false-green is gone.

## Domain Review

**Domains relevant:** Engineering (CTO), Operations (R2 vendor resource — de minimis).

### Engineering (CTO)
**Status:** reviewed. **Assessment:** Security posture SOUND — R2 creds in `prd_workspaces_luks` hold the CWE-522 boundary via one-directional root→branch inheritance; distinct bucket-scoped token is MANDATORY (reusing the tfstate R2 token would hand a host-compromise adversary write/read on the passphrase-bearing state bucket — a catastrophic escalation, HIGH). Confirmed the `aws`-endpoint correctness bug (HIGH, blocks the feature), the A11 file-scoped-cardinality landmine (separate file required), the two self-brick landmines (new-var pre-merge sequencing; scoped-vs-default apply gate), and recommended the DRY_RUN-safe reachability probe to kill the false-green. No re-scope; scope ADDITION (the probe) adopted. Brand threshold: single-user incident.

### Operations
**Status:** reviewed (inline). **Assessment:** one new R2 bucket, free-tier, no recurring expense to record; `wg-record-recurring-vendor-expense-before-ready` does not fire.

### Product/UX Gate
NONE — no UI-surface file in Files to Create/Edit (infra + shell + docs only).

## GDPR / Compliance
Advisory: touches at-rest-encryption escrow of user source code (regulated-data-adjacent) and declares
`single-user incident`, so the (b) trigger fires — but the artifact escrowed is a LUKS **header**
(key material), not personal data, and there is no new processing activity, schema, auth, or API route.
No new lawful-basis/Art.30 obligation; the encryption posture this supports is the compliance *win*.
`/soleur:gdpr-gate` advisory only at deepen-plan; no Critical expected.

## Risks & Sharp Edges
1. **Provider-token scope is a capability claim to VERIFY, not assert.** The `cf_api_token` var description says no R2, but descriptions drift — Phase 0 must live-probe before choosing the default-provider vs new-scoped-var path. If a new no-default var is introduced, it MUST be in `prd_terraform` before merge or the whole merge-apply bricks (ADR-065 / `2026-06-17-operator-mint-tf-var-must-sequence-before-auto-applied-iac.md`).
2. **`sha256(cloudflare_api_token.value)` does NOT yield the R2 S3 secret — it fails SigV4** (proven, `2026-05-18-cla-evidence-r2-s3-creds-not-derived.md`). Do not derive; mint an R2 API Token. Both cla-evidence's `outputs.tf` prose AND the terraform-architect research agent recommended the broken derivation — this plan overrides both, and the probe-PUT is the measurement that would have caught it.
3. **The escrow's S3 client is unprovisioned.** No `aws` on web-1 (no cloud-init/bootstrap install); the script never checks. A durable install + loud preflight is in scope — else the escrow dies with a misleading `command not found` at the critical pre-freeze moment.
4. **A11 file-scoped cardinality:** escrow resources in `workspaces-luks.tf` turn A11 RED — separate file only.
5. **Vendor-behavior claims measure, never derive** (`hr` corpus): the R2 endpoint is path-style (bucket in path, not host-suffixed — do not copy cla-evidence's `${endpoint}/${bucket}` output shape for the `aws` consumer); the checksum env is a known aws-cli≥2.23 R2 breakage.
6. **`-target` extension must sweep all guard suites** (`2026-05-29-…-sweep-all-guard-suites.md`) — parity test + any destroy-guard scope guard.
7. A plan whose `## User-Brand Impact` is empty/placeholder fails `deepen-plan` Phase 4.6 — this one is filled with a concrete artifact + vector + threshold.

### Gate reconciliations (deepen-plan)
- **Phase 4.8 (PAT-shaped var) — false positive, not a halt.** The GitHub-PAT regex matches `var.cf_api_token` / `var.cf_api_token_r2`, but those are **Cloudflare** provider tokens (mirroring the 3 existing scoped Cloudflare token vars in `main.tf`), not GitHub PATs. `hr-github-app-auth-not-pat` governs infra-time **GitHub** writes (this repo already uses App auth); this plan introduces no GitHub token. Proceed.
- **Phase 4.5 (network-outage) — N/A.** The plan references SSH only as the existing CF-Tunnel SSH bridge (`cf-tunnel-ssh-bridge` action) over which the cutover already runs — it is not diagnosing a connectivity failure and adds no new SSH-provisioner (`connection`/`remote-exec`) resource. No firewall/egress hypothesis to verify.
- **Phase 4.55 (downtime & cutover) — N/A.** This plan is additive freeze-prep with no host reboot/replace, no migration, no deploy-path change; the downtime event (the freeze) belongs to #6604.

## Open Code-Review Overlap
None — no open `code-review` issue references any file in this plan's edit set.
