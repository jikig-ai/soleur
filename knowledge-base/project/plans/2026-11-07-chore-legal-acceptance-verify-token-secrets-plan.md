---
title: "chore: legal-acceptance verify endpoint secrets (Terraform file for the status token)"
date: 2026-11-07
slug: legal-acceptance-verify-token-secrets
branch: feat-one-shot-12196-legal-acceptance-verify-token-tf
issue: 12196
type: chore
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-11-07
**Sections enhanced:** Research Insights (verification record), Operator-Visible Plan Output (edge branches, second check), Reconciliation (two rows), Test Scenarios (lexing rows), Acceptance Criteria
**Agents used:** CTO (rulings R1 to R7 and F1 to F6), CPO (plan-time sign-off), plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow), a sharp-edges catalogue pass, and the gdpr-gate trigger (b); the deepen halts 4.6 to 4.13 were run mechanically (results below)

### Key improvements

1. The literal "exactly four creates" cannot be read from the PR comment (untargeted, substitute credentials, standing baseline noise); the stop rule is now address-keyed plus a baseline-header diff, and the literal line is read from the merge run log.
2. The merge itself triggers the standard web release and deploy (`apps/web-platform/**` path filter, evidenced by merge d875862); the plan states this and sets the probe expectation accordingly.
3. The parent criterion `verify/185 bad = 0` was not measured by the pipeline (`verify-migrations` skipped in 4 of the 5 recent runs where `migrate` succeeded, all four on the `workflow_run` arm; the fifth was a manual dispatch); reported plainly, tracking issue in the work phase.

### New considerations discovered

- The PR comment's `hcloud_server.inngest` replace is an artifact of substitute credentials rendering a different cloud-init, even though that server is in the allow-list closure.
- `random_password` is invisible to key-rotate Guard 5 and to the `random_*` redaction classifier, so no parity row, ledger row or rotation-table row is needed; rotation has no automated route (ruling F4).
- Doppler names-only read: neither `soleur/dev` nor `soleur/prd` lists `LEGAL_ACCEPTANCE_VERIFY_TOKEN`, so the create overwrites nothing.

## Overview

Follow-up to merged PR #12187 (parent #12011). The check endpoint for the founder's legal acceptance (`GET /api/internal/legal-acceptance/[key]`) exists and answers 503 until its bearer token and the founder id are configured. This change adds the one Terraform file that mints the token for the Doppler `dev` and `prd` configs of project `soleur`:

- `apps/web-platform/infra/legal-acceptance-secrets.tf`: per config, one `random_password` (`length = 48`, `special = false`) and one `doppler_secret` named `LEGAL_ACCEPTANCE_VERIFY_TOKEN` (`visibility = "masked"`, no `ignore_changes`), in the shape of `egress-audit.tf`.
- Four allow-list entries in `.github/workflows/apply-web-platform-infra.yml`, because the per-merge run only touches what that list names (ruling R1 below).
- One test layer, three doc edits and nothing else.

The founder id (`LEGAL_ACCEPTANCE_FOUNDER_ID`) is not Terraform. The token is outside ADR-320 decision 1 (read-only status token, CTO ruling 2026-11-05).

**The merge of this change IS the infra run.** The operator wrote "terraform plan, I approve it" on 2026-11-07 approving exactly: two `random_password` creates, two `doppler_secret` creates, nothing else. That approval is bounded by the stop rule under `## Operator-Visible Plan Output`: any other change, replace or destroy stops the merge and is reported.

**What this change does not do (stays with the operator):** enter the founder uuid, flip the `approval-queue` flag, redeploy the web app. The endpoint keeps answering 503 after this merge.

The PR body says `Ref #12196` and `Ref #12011`, never `Closes`.

## Research Insights

### Premise Validation

- `gh issue view 12196`: OPEN, labels `type/chore`, `priority/p2-medium`, `domain/engineering`; body matches the brief (file name, `random_password` per config, `doppler_secret`, no `ignore_changes`). PR #12187 is merged (files list includes ADR-319, ADR-320, migration 185 and the verify route). PR #12307 is the draft for this branch. `collision-precheck.sh 12196` reports only #12307 (this branch), no foreign runs.
- The artifact is absent on `origin/main`: `git ls-files apps/web-platform/infra | grep legal-acceptance` returns nothing, so this is a build, not a fix.
- ADR corpus: ADR-320 decision 1 bars `random_password` for secrets granting write, root or production access in a Tier-A-readable root. The ADR-320 scope note (2026-11-05) and the ADR-319 PR-D amendment already rule this token outside decision 1 and say the decision-4 review applies "to the Terraform change when it is proposed". The mechanism is therefore settled, not unconsidered; this plan records the review disposition (task 4.2).
- Names-only Doppler read (no values), run with the session's own Doppler CLI: `soleur/prd` lists 157 names and `soleur/dev` 66, **zero** match `LEGAL_ACCEPTANCE`. So a create does not overwrite an existing secret. The check is re-run immediately before merge (AC pre-merge 6).
- Deploy arm observation (open item, reported plainly): in run 42368554066 (workflow `web-platform-release.yml`, `workflow_run`, head 7df4f3c04099) job `migrate` concluded success (`Applying: 185_legal_acceptance_ack.sql`, `Applied successfully.`, `1 applied, 193 skipped`) and job `verify-migrations` concluded **skipped** with zero steps. The same pattern appears in runs 42354619098, 42351350428 and 42336553951 (migrate success, verify-migrations skipped); the only recent run where it ran is a manual dispatch (42357001048, before migration 185 existed). So the parent's re-evaluation criterion `verify/185 bad = 0` was **not measured by the pipeline**. A read-only service-role GET of `legal_acceptance_ack` returned 403 (the table exists and the API role has no privilege, consistent with the sentinel) but that is not the sentinel's `bad = 0` count. This plan does not run the sentinel against production and does not claim it passed.

### Property List (Phase 0.6b)

1. After the merge run, `LEGAL_ACCEPTANCE_VERIFY_TOKEN` exists in `soleur/dev` and `soleur/prd` with two different values, each 48 characters of `[A-Za-z0-9]`.
2. The merge run changes exactly those four resources and no other resource.
3. A minted value always satisfies the route's `TOKEN_RE` and the shell helper's bounds (otherwise the endpoint stays 503 and reports a bad configuration).
4. The state exposure of the value is disclosed where an approver reads it before merging.
5. A leak is handled by rotation through the same file, with the next run writing the new value to Doppler.

### Cut List (Phase 0.6b)

- Mechanism: a `random_id` instead of `random_password` -> buys nothing the issue asks for and would put the pair under key-rotate Guard 5, which only walks `random_id`; cut, keep `random_password`.
- Mechanism: a workflow-side plan-delta assertion -> property 2 is already bought by the pre-merge intersection check plus the post-merge log read; the workflow file has about 2 KB of byte headroom; cut (ruling R2).
- Mechanism: a new rotation route / `key-rotate.sh` row -> not asked; rotation is a `-replace` of the random resource; cut.
- Mechanism: an ADR for the token -> no new decision (applies the 2026-11-05 ruling); cut (R5).
- Mechanism: editing `apps/web-platform/.env.example` -> belongs to the parent plan (AC13), blocked there by a read deny rule, not part of #12196; cut and mentioned under Sharp Edges.

### Repo findings (files read, content anchors)

- `apps/web-platform/infra/egress-audit.tf`: `random_id` + `doppler_secret` with `project = "soleur"`, `config = "prd"`, `visibility = "masked"`, comment `# NO ignore_changes — rotation is operator-explicit via -replace.` and a "State exposure:" paragraph. `live-verify.tf` is the `random_password` shape (`length = 40`, `special = false`, `value = random_password.live_verify_user.result`); `git-data-luks.tf` is the same with `special = false`. `inngest.tf` carries the `_prd`/`_dev` naming and a `config = "dev"` `doppler_secret` per generator.
- `.github/workflows/apply-web-platform-infra.yml`, step "Terraform plan (allow-list, non-SSH resources only)": a `-target=` allow-list that writes `tfplan`; the later saved-plan step runs it with `-auto-approve` (step name "Terraform" followed by the verb). The egress targets (`random_id.egress_audit_ingest_token`, `doppler_secret.egress_audit_ingest_token`, `doppler_secret.egress_audit_ingest_token_previous`) are the insertion anchor. File size is 487,917 bytes against the 490,000 gate in `plugins/soleur/test/workflow-file-size.test.ts`; four lines cost about 300 bytes.
- `plugins/soleur/test/terraform-target-parity.test.ts`: the all-resources coverage test (its title starts "every managed resource has a ...") fails for a new resource in none of the three sets; `AUDIT_PENDING_UNCOVERED` says "Do NOT grow this set". Guard 5 (`keyRotateViolations`) walks `random_id.*` only; `LEAKING_RANDOM` excludes `random_password` (its `id` is the constant `none`). The redaction sweep already requires `tf_redact_random_ids` in every plan step of this root and it covers `random_password` `result` lines.
- Provider token scope: `provider "doppler"` uses `var.doppler_token_tf`; the per-merge list already targets `doppler_secret.inngest_signing_key_dev` (`config = "dev"`, project `soleur`) and the scheduled drift check is green (last five runs success), so the existing token writes the `soleur/dev` config. No new provider, no version change (`hashicorp/random` 3.9.0 is in `.terraform.lock.hcl`).
- Destroy guard (`tests/scripts/lib/destroy-guard-filter-web-platform.jq`): the LUKS-passphrase counter matches named LUKS addresses only, so the new addresses are counted only by the generic create/delete counters (zero deletes expected).
- The PR-visible plan is `infra-validation.yml` job `plan`: untargeted `terraform plan -refresh=false` over the whole root with bounded substitute credentials, posted as a sticky comment. PR #12268's comment shows standing baseline noise that the merge never applies: replace of `doppler_service_token.inngest`, create of `doppler_service_token.inngest_flip`, replace of `hcloud_server.inngest`, `hcloud_server_network.inngest`, `hcloud_volume_attachment.inngest_redis_luks` (all operator-applied exclusions) and the destroy of `cloudflare_record.google_gws_recovery` (state orphan).
- The merge-time targeted plan is clean at baseline: last main run 42369320061 printed `Plan: 0 to add, 0 to change, 2 to destroy.` where the 2 were that PR's own delta, then `Apply complete! Resources: 0 added, 0 changed, 2 destroyed.`.
- Consumer side: `route.ts` has `const TOKEN_RE = /^[A-Za-z0-9._~+/=-]{48,256}$/;` and answers 503 when the token or `LEGAL_ACCEPTANCE_FOUNDER_ID` is unset or malformed (emitting one configuration report event). `apps/web-platform/test/legal-acceptance/cross-layer-limits.test.ts` already extracts that bound and the bound in `plugins/soleur/scripts/lib/bearer-fetch.sh` and asserts both say 48 to 256; nothing reads the `.tf`.

### Institutional learnings applied

- `2026-03-25-doppler-secret-audit-before-creation.md`: audit every config before declaring a secret absent (done for dev and prd, names only; the other configs are inheritance-irrelevant for a create).
- The state-exposure convention: `egress-audit.tf` and `github-app.tf` header paragraphs; ADR-241 residual R2; ADR-320.
- `hr-tf-variable-no-operator-mint-default`: no Terraform variable, no default, the value is minted in the resource.

### Precedent diff (deepen Phase 4.4)

| Attribute | `live-verify.tf` (random_password + doppler_secret) | `egress-audit.tf` (random_id + doppler_secret) | This change |
|---|---|---|---|
| Generator | `random_password`, `length = 40`, `special = false` | `random_id`, `byte_length = 32` | `random_password`, `length = 48`, `special = false` (the route's lower bound is 48) |
| Secret value | `random_password.live_verify_user.result` | `"eai-${random_id....hex}"` | `random_password.<own>.result` |
| Secret attributes | `project = "soleur"`, `config = "prd"`, `visibility = "masked"`, no `ignore_changes` | same | same, plus a `dev` twin as in `inngest.tf` |
| Per-merge reach | No: sits in `AUDIT_PENDING_UNCOVERED` (not converged by the merge) | Yes: three `-target=` lines | Yes: four `-target=` lines (required by the approval basis) |

Provider facts used: `hashicorp/random` 3.9.0 is the locked version (`apps/web-platform/infra/.terraform.lock.hcl`); `special` defaults to true in that provider, hence the explicit `special = false`; `result` is a sensitive attribute, so the plan prints `(sensitive value)`. `visibility = "masked"` is already used by sibling `doppler_secret` blocks in the pinned `DopplerHQ/doppler` provider.

### Deepen-plan halts (mechanical results, 2026-11-07)

- 4.6 User-Brand Impact: present, threshold `single-user incident`. Pass.
- 4.7 Observability: all five fields present; the probe starts with `curl`, no `ssh`, finishes well inside the 15 s cap, `expected_output` is the literal pair `503 or 401`; the probe is declared an endpoint-liveness check that cannot witness this change, the apply log line and the names-only read do. Pass.
- 4.8 PAT-shaped variables: no hit. Pass.
- 4.9 UI wireframe: no UI-surface file in the plan. Skipped.
- 4.10 Encryption Posture: present, `does_not_defend` non-empty on every entry, no plaintext exception. Pass.
- 4.11 Guard Contract: `lint-guard-contract.py` green (one guard, nine mutation rows, harness rows and anchor present); the Assembly names the directory-wide population and the `value` chokepoint, not today's two members. Pass.
- 4.12 Scope Check: one unfenced section, three sub-sections, no unmapped ask, no empty justification, `Recommendation:` line present. Pass.
- 4.13 Task Design: no new workflow, function, check or timer is created (the allow-list edit adds targets to an existing workflow). Skipped.
- Quality checks: rule ids `cq-write-failing-tests-before` and `hr-tf-variable-no-operator-mint-default` exist as active rules; labels `type/chore`, `domain/engineering`, `priority/p2-medium` exist; PR #12187 and #12268 merged, #12307 open, issue #12011 open; run ids 42369320061, 42368554066, 42357001048 resolved live with `gh run view`; no new ADR is created (no ordinal to derive).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| "the terraform plan output the CI posts" must show exactly four creates, anything else stops the merge | The PR comment is an untargeted `-refresh=false` plan over the whole root with standing baseline noise (5 adds and 5 destroys before this change, all outside the per-merge allow-list). The targeted plan that the merge converges is only visible after the merge (the run is `-auto-approve` on a main-only environment) | Stop rule keyed on addresses (ruling R2): intersect the comment's resource headers with the per-merge allow-list; the intersection must be exactly the four new addresses, each a create. The literal "exactly 4 creates" is read from the merge run log afterwards: `Plan: 4 to add, 0 to change, 0 to destroy.` |
| "the web-platform infra workflow applies on push" so the new file needs nothing else | The run only converges allow-listed addresses; a new resource in none of the three coverage sets also fails `terraform-target-parity.test.ts` | Add four allow-list lines (R1); do not add the pair to `AUDIT_PENDING_UNCOVERED` or `OPERATOR_APPLIED_EXCLUSIONS` |
| ADR-320 scope note: "no such `.tf` exists yet" | True until this change | Edit the note in the same change (R5) |
| "do NOT redeploy the web app" | Any merge touching `apps/web-platform/**` (the `.tf` included) triggers Web Platform Release and its deploy chain; the previous infra-only merge d875862 ran `release` changed=true, then `migrate` and `deploy` success on the `workflow_run` arm. The container reads Doppler when it is created, so this merge's automatic deploy races the infra run | Nothing is dispatched by this change, and nothing can avoid the automatic one (`[skip-web-platform-apply]` would make the merge inert). Stated truthfully in the PR body (ruling F3). With the founder id unset the endpoint stays 503 either way; the operator's redeploy after entering the uuid is still required |
| The PR sticky comment shows the plan the merge converges | The comment's baseline noise includes `hcloud_server.inngest` replace caused by substitute credentials rendering a different cloud-init, although that server is in the allow-list closure; the real merge run did not plan it | Two-part stop rule (literal intersection plus baseline-header diff), ruling F1 |
| Parent criterion `verify/185 bad = 0` | `verify-migrations` was skipped on the deploy arm; not measured | Reported in the PR body and final report; tracking issue filed for the pipeline gap; not claimed passed |
| ADR-319 / README: "the token does not exist yet" and "to be minted by #12196" | Becomes false at merge | Dated amendment line and README edit (R5) |

## User-Brand Impact

- **If this lands broken, the user experiences:** the web-acceptance hold keeps reading "endpoint not configured yet" (UNEVAL) so every legal hold stays held, or, if the minted value were malformed, the endpoint reports a bad configuration and stays 503. A broken run could also leave only one of the two configs written, so dev and prd diverge in a way the operator would not notice until the first probe. Fail-closed in every case: nothing is discharged.
- **If this leaks, the user's data is exposed via:** the token in Terraform state, readable by the Tier-A read pair (any branch workflow), or in the Doppler `prd` config (readable by the agent by design). A holder can query one founder's decision status for a given text: four fields (`status`, `text_hash`, `decided_at`, `row_ok`), never the free-text note, never a write. The value must never reach a log, a PR comment (the plan prints `(sensitive value)`) or a command line.
- **Brand-survival threshold:** `single-user incident` (inherited from the parent plan; CPO plan-time sign-off given 2026-11-07, conditioned on scope, `Ref` not `Closes`, and a PR body that says the endpoint is still off). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Infrastructure (IaC)

### Terraform changes

New file `apps/web-platform/infra/legal-acceptance-secrets.tf` (comment header only prose; the four blocks below; no variable, no output, no `lifecycle`):

| Address | Key attributes |
|---|---|
| `random_password.legal_acceptance_verify_token_prd` | `length = 48`, `special = false` (written explicitly: the provider default for `special` is `true`, which would break the route's `TOKEN_RE`) |
| `random_password.legal_acceptance_verify_token_dev` | same |
| `doppler_secret.legal_acceptance_verify_token_prd` | `project = "soleur"`, `config = "prd"`, `name = "LEGAL_ACCEPTANCE_VERIFY_TOKEN"`, `value = random_password.legal_acceptance_verify_token_prd.result`, `visibility = "masked"` |
| `doppler_secret.legal_acceptance_verify_token_dev` | same with `config = "dev"` and the `_dev` generator |

Header prose (ruling R6): the pair is the issue's #12196 / ADR-319 PR-D / ADR-320 scope note; read-only status token, reach is four fields about one founder; value sits in `terraform.tfstate` in the R2 bucket readable by the Tier-A read pair (ADR-241 residual R2); rotating it does not repair a leak; it moves out of Terraform if it ever gains write reach; `LEGAL_ACCEPTANCE_FOUNDER_ID` is deliberately not in Terraform; rotation is a `-replace` of the random resource and reaches Doppler because there is no `ignore_changes`, but it has no automated route (the dispatch targets offer no generic replace for a `random_password`): it is a local, operator-approved `-replace=random_password.*` under Tier-B credentials (ruling F4); a hand edit in Doppler is reverted by the next merge run and flagged by the drift check.

Allow-list edit in `.github/workflows/apply-web-platform-infra.yml`, step "Terraform plan (allow-list, non-SSH resources only)": four `-target=` lines inserted after `-target=doppler_secret.egress_audit_ingest_token_previous`, generators first then secrets, for the four addresses above. No comment prose inside the continued list (a `#` line there turns the next line into a command, shellcheck SC2215).

Providers: `random` and `doppler` are already declared; no pin change. Sensitive variables: none (`hr-tf-variable-no-operator-mint-default`).

### Apply path

(a) Not a host change: the per-merge convergence of the existing infra workflow, on the push that merges the file. Four creates, no downtime, no blast radius beyond two new Doppler secrets that nothing reads until the web app is redeployed (the container receives its environment through a file frozen when the container is created). No `[ack-destroy]` is needed (zero deletes) and `[skip-web-platform-apply]` must NOT be used (it makes the merge inert, ruling R7).

### Host fan-out

Not applicable: no `terraform_data` SSH provisioner is added or edited.

### Distinctness / drift safeguards

- dev != prd by construction: two independent `random_password` generators, asserted by the test layer (each secret's `value` references its own generator). Post-merge, a boolean-only read compares the two Doppler values for inequality without printing either (AC post-merge 3).
- No `lifecycle` block: a regenerated value must cascade to Doppler (same posture as `egress-audit.tf`). The scheduled 12-hour drift check covers a hand edit.
- State storage: the R2 backend has no versioning and no lock (ADR-006); both `random_password.result` and `doppler_secret.value` are written to `terraform.tfstate`. See `## Encryption Posture`.

### Vendor-tier reality check

Doppler: no tier gate on a secret in an existing project and config. Names-only read confirmed the name is free in both configs. No new vendor account.

## Operator-Visible Plan Output

What the operator and the ship session read before merging, and the stop rule (ruling R2):

1. **PR sticky comment "Terraform Plan: `apps/web-platform/infra`"** (untargeted, `-refresh=false`). It will contain the standing baseline noise (see Research Insights) plus exactly these four headers, each `will be created`:
   `random_password.legal_acceptance_verify_token_prd`, `random_password.legal_acceptance_verify_token_dev`, `doppler_secret.legal_acceptance_verify_token_prd`, `doppler_secret.legal_acceptance_verify_token_dev`. The values print as `(sensitive value)`.
2. **Mechanical stop rule.** Extract the per-merge allow-list with a grep of the `-target=` lines inside the plan step of the workflow (the parity test's `extractAllTargets` is not exported and reads the whole stripped workflow, so it is not reusable by a ship session), take every resource address that appears in a `# <addr> will be ...` or `must be replaced` header of the comment, and intersect. The intersection must equal the four new addresses, each a create. Any other address in the intersection, a non-create for the four, or any changed or destroyed `doppler_secret` or `random_*` means **do not merge, stop and report to the operator**. Baseline noise outside the allow-list is never converged by the merge.
   **Second check (ruling F1, amends R2):** the resource headers of this PR's sticky comment, minus the four, must equal the headers (address plus action only, attribute noise ignored) of the most recent infra PR's sticky comment on `main`, minus that PR's own delta; both are produced with the same bounded substitute credentials. Any new header stops the merge for investigation. A closure-keyed rule was considered and withdrawn: the comment's `hcloud_server.inngest` replace is standing noise from the substitute credentials rendering a different cloud-init, although that server is in the allow-list closure and the real merge run did not plan it.
3. **Clean-baseline check.** The last completed apply run on `main` must show a targeted plan whose resources equal that run's own PR delta (today: run 42369320061, `Plan: 0 to add, 0 to change, 2 to destroy.`, which was PR #12268's own two deletes).
4. **Doppler names-only re-check**, immediately before merging (no values): neither `soleur/dev` nor `soleur/prd` lists `LEGAL_ACCEPTANCE_VERIFY_TOKEN`. If the session cannot read Doppler, record `unverified - no-credential`; it does not block the merge, because the endpoint answers 503 until the founder id exists.
   **Edge branches (stop and report, never guess):** (a) the sticky comment is not `✅ Success`, is absent, stale (its head SHA differs from the PR head; wait with a bounded poll for the current one) or truncated at the 60,000-character cut: stop, and read the full plan from the `infra-validation.yml` job log instead; the comment is accepted only with Result success, no "plan output truncated" marker, and all four `will be created` headers present (a positive count, never an empty intersection read as a pass). (b) Never use `gh pr merge --auto`; the stop rule must run first. (c) Immediately before merging, re-run items 3 and 4 and confirm no apply run is in flight on `main` and `main` HEAD equals the comment's base, otherwise another infra merge would converge under this approval. (d) If the stop rule fails, return the PR to draft and report to the operator.
5. **After the merge**, wait (bounded poll) for the apply run of the merge commit on `main`; if it is missing, skipped or queued past the bound, report that the token is not minted, and do not claim otherwise. Read the apply run log: the plan step must print exactly `Plan: 4 to add, 0 to change, 0 to destroy.` and the apply step `Apply complete! Resources: 4 added, 0 changed, 0 destroyed.` Anything else is reported to the operator, not retried; a half-created pair shows as `N to add` on the next merge, which stays within the four-create approval, and any other delta stops that merge. The check is detective only (the run is `-auto-approve`); that residual is stated in the PR body (ruling F2): only an update to a `doppler_secret` or `random_*` inside the allow-list closure could slip past, and run 42369320061 shows a clean baseline. Results of the merge run are posted as a comment on #12196, which stays open until the operator-owned steps are done.

No local targeted plan is run: it needs R2 state-read and Doppler write-scope credentials, which are Tier-B. Offline `terraform fmt -check` and `terraform init -backend=false` followed by `terraform validate` are allowed.

## Encryption Posture

```yaml
at_rest:
  - store: "Terraform state object in R2 bucket soleur-terraform-state (existing; value of random_password.result and doppler_secret.value)"
    mechanism: "provider-managed:cloudflare-r2-aes256"
    evidence: "scripts/encryption-posture-ledger.json, the R2 state bucket entry (Cloudflare R2 AES-256-GCM at rest, SOC 2 Type II)"
    defends_against: "theft of the underlying storage media"
    does_not_defend: "any holder of the Tier-A read pair (r2-tf-state-read-8209 / prd_terraform AWS_* keys), which can read the token; the bucket has no versioning and no lock (ADR-006); rotating does not repair a leak because the next run writes the new value to the same readable state"
    disclosed_as: ".tf header, PR body, ADR-319 PR-D amendment and ADR-320 scope note"
    live_verification: "none new; the existing ledger entry resolves under lint-encryption-posture.py"
  - store: "Doppler secret LEGAL_ACCEPTANCE_VERIFY_TOKEN in soleur/dev and soleur/prd (masked)"
    mechanism: "provider-managed:doppler-aes256"
    evidence: "scripts/encryption-posture-ledger.json, the Doppler entry (AES-256-GCM at rest)"
    defends_against: "theft of Doppler's storage media"
    does_not_defend: "any principal with read access to the config, including the agent by design (the hold evaluator reads it); a read-only status token, four fields about one decision"
    disclosed_as: "ADR-319 PR-D amendment ('held by whoever can read the Doppler prd config, including the agent by design')"
    live_verification: "names-only Doppler read before and after the merge"
in_transit:
  - connection: "Terraform provider calls to the Doppler API and R2 (state) from the infra workflow runner"
    tls: "TLS 1.2+"
    cert_verification: on
    does_not_defend: "a compromised runner holding the Tier-B credentials"
    disclosed_as: "ADR-241"
```

## Architecture Decision (ADR/C4)

No new decision: this applies the 2026-11-05 CTO ruling recorded in ADR-319 and the ADR-320 scope note (ruling R5), so the Phase 2.10 detection does not fire. Deliverables that follow from it:

### ADR

- Amend ADR-320's scope note (the line beginning `Scope note 2026-11-05`): replace "no such `.tf` exists yet" with a dated statement that `legal-acceptance-secrets.tf` landed under #12196 and that the decision-4 review was applied to the file as proposed (read-only token, outside decision 1, two independent generators, no write reach). The note names the exemption criterion (ruling F5): the route returns only `status`, `text_hash`, `decided_at` and `row_ok` and never writes; widening the response, adding a non-GET method or adding any write path re-triggers the decision-4 review and moves the token out of Terraform. It also states that rotation has no automated route (F4). ADR-320 stays `proposed`.
- Add a dated line to the ADR-319 PR-D section ("token now minted by #12196, 2026-11-07") restating the four-field bound and the Tier-A state consequence without widening either.

### C4 views

No `.c4` edit. Checked against all three files (`model.c4`, `views.c4`, `spec.c4`): external human actor (the founder, modeled; `founder -> legalAcceptanceStore` exists), external system (Doppler, modeled as `doppler`; `ship -> doppler` already says "Once the token exists (#12196)"), container touched (`legalAcceptanceStore` and `webapp`, modeled; the plugin view already lists `webapp` and `doppler`), and the actor-to-surface relationship (`ship -> webapp` read-only bearer, modeled). The R2 Terraform state bucket is not a modeled element and no existing secret's state exposure is modeled either, so no relationship becomes false. Cardinalities embedded in edge prose are unchanged (no workflow, monitor or heartbeat is added), so `c4-count-parity` is expected to stay green; it is run at work time.

### Sequencing

The endpoint is dark until the founder id and a redeploy exist; nothing in the ADR text is conditional on a later slice.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Rulings R1 to R7 (see `knowledge-base/project/specs/feat-one-shot-12196-legal-acceptance-verify-token-tf/decision-challenges.md`): per-merge allow-list entries, address-keyed stop rule, resource names and attributes, one test layer in `cross-layer-limits.test.ts`, doc edits only, disclosure in the `.tf` header and PR body, no blocker to merging once the stop rule passes.

### Legal (CLO)

**Status:** reviewed (carry-forward, no new agent run)
**Assessment:** The parent CLO attestation (`knowledge-base/legal/audits/2026-11-counsel-review-12011.md`, item 3) says the Terraform change and the operator's Doppler entry are the operator's act and that the attestation authorises no production action; the operator's approval of 2026-11-07 is that act. This change adds a credential, not personal data or a processing activity, so PA-40, the LIA and the DPD are unchanged. Draft, not legal advice.

**GDPR gate (plan Phase 2.7, fired by trigger (b): threshold `single-user incident`; the canonical regulated-path regex matches no file in this plan).** Run inline against this plan on 2026-11-07. Output (advisory; not legal review; findings are heuristic): the five v1 checks have no trigger. No schema column or migration is added (Art. 6, 5(1)(e), 9 not reached), no foreign key to `users` (Art. 17), no new vendor or SDK (Chapter V: Doppler and the R2 state bucket are existing recorded processors; only column names and prose were assessed, no row values). Art. 32 note, already disclosed: the token sits in Tier-A-readable Terraform state and reaches four fields about one decision; rotation does not repair a leak. Severity: no Critical, no Important, one Suggestion (keep the state-exposure sentence in the PR body, done under Acceptance Criteria 8). No `compliance-posture.md` write and no `compliance/critical` issue.

### Product (CPO)

**Status:** reviewed
**Assessment:** CPO plan-time sign-off given 2026-11-07 (threshold unchanged, conditions listed under User-Brand Impact). Token-before-uuid is fail-closed: the endpoint stays 503 and the gate reports UNEVAL "not switched on, or temporarily down", which holds every hold; UNEVAL is not a decline and not a recorded Yes. No UI surface is created or edited, so there is no Product/UX Gate.

## Observability

```yaml
liveness_signal:
  what: "the apply run of this merge reports 'Apply complete! Resources: 4 added, 0 changed, 0 destroyed.'; afterwards the dark probe status code (503 before the founder id and a redeploy, 401 with a wrong token after)"
  cadence: "once per merge for the run; the drift check every 12 hours for the resources' continued existence"
  alert_target: "notify-apply-failure in apply-web-platform-infra.yml (email) for a failed run; scheduled-terraform-drift (issue) for drift; Sentry configuration report from the route for a malformed value"
  configured_in: ".github/workflows/apply-web-platform-infra.yml, .github/workflows/scheduled-terraform-drift.yml, apps/web-platform/app/api/internal/legal-acceptance/[key]/route.ts"
error_reporting:
  destination: "the Actions run log (values redacted: plan prints '(sensitive value)', tf_redact_random_ids on every stream) and Sentry for the route"
  fail_loud: "a failed plan or apply fails the job and triggers notify-apply-failure; a malformed token makes the route answer 503 and report once per process"
failure_modes:
  - mode: "plan contains anything beyond the four creates"
    detection: "the address-keyed stop rule before merge; the merge-run plan line after"
    alert_route: "merge stops; report to the operator"
  - mode: "partial apply (one config written, the other not)"
    detection: "apply step non-zero exit; the post-merge names-only read of both configs"
    alert_route: "notify-apply-failure email; report and do not retry; the missing members show as N to add on the next merge, which stays within the four-create approval (ruling F6)"
  - mode: "minted value rejected by the route (shape or length)"
    detection: "cross-layer-limits test layer before merge; route configuration report after redeploy"
    alert_route: "test failure in CI; Sentry event from the route"
  - mode: "hand edit or deletion in Doppler"
    detection: "scheduled-terraform-drift plan"
    alert_route: "drift issue"
logs:
  where: "GitHub Actions run logs of apply-web-platform-infra.yml (public repo: redaction required, in place)"
  retention: "GitHub's default Actions log retention"
# The probe below is an endpoint-liveness check only: it reads 503 both before and after this merge (founder id and redeploy are operator-owned), so it cannot witness this change. This change is proven by the apply log line and the names-only Doppler read in the Acceptance Criteria.
discoverability_test:
  command: "curl -s -o /dev/null -w %{http_code} https://app.soleur.ai/api/internal/legal-acceptance/probe"
  expected_output: "503 or 401"
```

## Test Scenarios

Written before the `.tf` (`cq-write-failing-tests-before`), in `apps/web-platform/test/legal-acceptance/cross-layer-limits.test.ts`, a new `describe` "the minted token (legal-acceptance-secrets.tf) against the route bound":

0. All reads happen inside the `it` bodies, never at module or `describe` level (a throw at collection would break the file's existing tests); HCL comments are stripped before parsing (the `.tf` header will itself contain the words `ignore_changes` and the resource names), as `stripComments` does in the parity test. The file is a member of the `repo-wide` vitest project (`apps/web-platform/test/repo-wide-suites.ts`), so the file-selected command is unchanged.
1. Extract every `resource "random_password"` and `resource "doppler_secret"` block whose address or `name` mentions `legal_acceptance_verify_token` / `LEGAL_ACCEPTANCE_VERIFY_TOKEN` from ALL `apps/web-platform/infra/*.tf` (not only the new file); an empty extraction throws.
2. Exactly two `doppler_secret` blocks carry `name = "LEGAL_ACCEPTANCE_VERIFY_TOKEN"`, one with `config = "dev"` and one with `config = "prd"`, both `project = "soleur"`, `visibility = "masked"`, neither with `ignore_changes` or any `lifecycle`.
3. Each `value` is `random_password.<own generator>.result` and the two generators differ.
4. Each generator has `length` within the route's `TOKEN_RE` bounds (parsed from `route.ts`, not restated) and `special = false` written explicitly; the alphabet property is carried by the static `special = false` check itself (with it, the value is `[A-Za-z0-9]`, inside the route's class); no sample-string check is added because it would be a tautology.
5. Negative controls on the real source: `length = 32`, `length = 300` (above the route's upper bound), `special = true`, a removed `special` line, a commented-out `special = false`, a one-line `resource "..." { ... }` form, a `lifecycle` block in a sibling block (must not be attributed to this secret), a dev secret pointing at the prd generator, a literal or `var.x` value, an added `ignore_changes`, and a second `doppler_secret` with the same name in another file each make the extraction-based check fail (assert the check function returns violations, not that the file changed).
6. Must-PASS non-canonical inputs: attributes reordered, trailing comments, `length = 64`.

Plus existing suites run file-selected (see Work Phases): `plugins/soleur/test/terraform-target-parity.test.ts`, `plugins/soleur/test/workflow-file-size.test.ts`, `tests/scripts/test-git-data-wipe-wedge.sh` (derives the allow-list closure from the root's HCL), `tests/scripts/test-infra-privileged-tier-census.sh` (Guard 4 walks the root's `.tf`), `plugins/soleur/test/c4-count-parity.test.sh`, and `terraform fmt -check` / `terraform validate`; the other c4 suites and `scripts/lint-encryption-posture.py` only if the selection names them (no `.c4` or ledger file is edited).

## Guard Contract

### Guard 1 — minted token versus the consumer's bound

**Property.** Every value the Terraform file can mint for `LEGAL_ACCEPTANCE_VERIFY_TOKEN`, in any config, satisfies the route's `TOKEN_RE` and lands under the exact name the route reads.

**Assembly.** The population is every `doppler_secret` block under `apps/web-platform/infra/*.tf` whose `name` is `LEGAL_ACCEPTANCE_VERIFY_TOKEN` (not "the two in the new file"), plus every `random_password` such a block references, resolved through `value = random_password.<x>.result`; the consumer side is `TOKEN_RE` in `route.ts` and the two bounds in `plugins/soleur/scripts/lib/bearer-fetch.sh`. The chokepoint is the secret's `value` reference: a secret whose value is not a `random_password.*.result` reference (a literal, a variable, a `random_id.hex`) is itself a violation. A second member added in another file after a compliant first is covered because the scan is directory-wide.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | `length = 48` becomes `32` in either generator | below the route's lower bound the endpoint stays 503 |
| 2 | `special = false` becomes `true`, or the line is removed (provider default is `true`) | symbols outside `[A-Za-z0-9]` can fall outside the class and break the shell helper's token handling |
| 3 | Add a second `doppler_secret` named `LEGAL_ACCEPTANCE_VERIFY_TOKEN` in another `.tf` file after a compliant first | the population is directory-wide, a check that stops at the first member is the defect |
| 4 | The dev secret's `value` references the prd generator | dev and prd would share a value |
| 5 | Add `ignore_changes = [value]` to either secret | a `-replace` of the generator would no longer reach Doppler |
| 6 | Rename both resources so the extraction finds nothing | an empty extraction must throw, never read as "all members agree" |
| 7 | Replace a `value` with a literal or `var.x` | the value would not be minted here |
| 8 | Comment out `special = false`, write a resource on one line, or put the `lifecycle` block in a sibling resource | the lexer must read comments, one-line blocks and block boundaries like the parity test's `stripComments` and brace matching, or the check passes on text that terraform would not read as written |
| 9 | `length = 300` | above the route's upper bound the value is rejected (the extracted max, not a restated 256) |

**Harness rows.** Edit to the suite: make the extractor return an empty list; the suite must fail rather than pass. Must-PASS inputs that are not the canonical file: attributes reordered, a trailing `# comment` on the `length` line, `length = 64`.

**Anchor.** The test proves consistency inside one commit (the `.tf` and the route are both editable by one diff), not integrity. What sits outside the commit: the literal `{48,256}` pin already asserted for the route and the helper (a second place that must move), and the post-merge dark probe (503 to 401 with the real deployed route) plus the apply run log. Allow-list presence is not re-asserted here: `terraform-target-parity.test.ts` already fails for a new resource in none of the coverage sets.

## Acceptance Criteria

### Pre-merge (PR)

1. `apps/web-platform/infra/legal-acceptance-secrets.tf` exists with exactly the four resources above; `terraform fmt -check` and `terraform validate` (with `init -backend=false`) pass.
2. The four allow-list lines exist in the plan step of `apply-web-platform-infra.yml` and the file stays under 490,000 bytes (`bun test plugins/soleur/test/workflow-file-size.test.ts`).
3. `plugins/soleur/test/terraform-target-parity.test.ts` passes unchanged (no new row, no `TEST_FLOOR` edit) and the all-resources test names none of the four as uncovered.
4. The new test layer in `cross-layer-limits.test.ts` passes (file-selected).
5. Stop rule (Operator-Visible Plan Output, items 1 to 3) evaluated on the PR sticky comment and the last main run; any deviation stops the merge and is reported.
6. Names-only Doppler re-check shows no existing `LEGAL_ACCEPTANCE_VERIFY_TOKEN` in dev or prd (or is recorded `unverified - no-credential`).
7. ADR-320 scope note, ADR-319 PR-D dated line and `server/legal-acceptance/README.md` edited as in `## Architecture Decision (ADR/C4)`; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the CI invocation) is clean.
8. PR body: its first line says that merging runs the per-merge infra apply and creates two passwords and two Doppler secrets; `Ref #12196`, `Ref #12011` (never `Closes`), states the state exposure, that the endpoint is still 503, the ordered operator-owned steps (founder uuid per project with a check against that project's `auth.users`, redeploy not restart, probe 503 to 401, first real acceptance verified, then the flag), the detective-only residual of the merge run (ruling F2), that the merge itself triggers the standard web release and deploy (ruling F3), and the open item below.
9. Open item stated plainly in the PR body and the final report: `verify-migrations` was skipped on the deploy arm for merge 7df4f3c04099 (migrate applied 185 and succeeded), so `verify/185 bad = 0` was not measured by the pipeline; a read-only service-role GET of `legal_acceptance_ack` returned 403. A tracking issue for the pipeline gap is filed and linked.

### Post-merge (read from the apply run, not done by hand)

1. The merge run plan step prints `Plan: 4 to add, 0 to change, 0 to destroy.` and the apply step `Apply complete! Resources: 4 added, 0 changed, 0 destroyed.`; otherwise report, do not retry.
2. Names-only read of `soleur/dev` and `soleur/prd` lists `LEGAL_ACCEPTANCE_VERIFY_TOKEN` in both.
3. A boolean-only read confirms the two values differ and each matches `^[A-Za-z0-9]{48}$`, printing only `true` or `false`: `a=$(doppler secrets get LEGAL_ACCEPTANCE_VERIFY_TOKEN -p soleur -c prd --plain); b=$(doppler secrets get LEGAL_ACCEPTANCE_VERIFY_TOKEN -p soleur -c dev --plain); [[ "$a" != "$b" && "$a" =~ ^[A-Za-z0-9]{48}$ && "$b" =~ ^[A-Za-z0-9]{48}$ ]] && echo true || echo false` (values stay in shell variables, no xtrace, nothing echoed). If the session cannot read Doppler, record `unverified - no-credential`.
4. The dark probe reads 503 while the founder id is unset (not 307); a 401 means the uuid was already entered, which is reported, not an error. A 503 cannot tell a missing token from a missing founder id, so the proof the token was minted is the apply log line in item 1, never the probe (ruling F3).

## Files to Create

- `apps/web-platform/infra/legal-acceptance-secrets.tf`
- `knowledge-base/project/specs/feat-one-shot-12196-legal-acceptance-verify-token-tf/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-12196-legal-acceptance-verify-token-tf/decision-challenges.md` (written at plan time)

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` (four allow-list lines)
- `apps/web-platform/test/legal-acceptance/cross-layer-limits.test.ts` (one new `describe`)
- `knowledge-base/engineering/architecture/decisions/ADR-320-terraform-minted-secrets-must-not-land-in-tier-a-readable-state.md` (scope note)
- `knowledge-base/engineering/architecture/decisions/ADR-319-legal-acceptance-record.md` (dated amendment line)
- `apps/web-platform/server/legal-acceptance/README.md` (the "to be minted at 48 characters by #12196" sentence)

## Open Code-Review Overlap

None. Queried open `code-review` issues for each file above; no body names any of them.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add apps/web-platform/infra/legal-acceptance-secrets.tf with a random_password (length 48, special = false) per config (dev, prd) and a doppler_secret named LEGAL_ACCEPTANCE_VERIFY_TOKEN (project soleur, visibility masked, no ignore_changes, as egress-audit.tf)" [issue #12196] | Files to Create (the `.tf`), Infrastructure (IaC) | mapped |
| 2 | "LEGAL_ACCEPTANCE_FOUNDER_ID is NOT Terraform (operator enters it per Doppler project)" [brief] | Overview, `.tf` header text, Sharp Edges | mapped |
| 3 | "The merge of this change IS the apply" and "before merging, read the terraform plan output the CI posts; if it contains ANYTHING beyond those four creates ... do NOT merge" [brief] | Operator-Visible Plan Output, Acceptance Criteria pre-merge 5 | mapped |
| 4 | "Open item to flag, not to hide: the deploy arm's verify-migrations job was SKIPPED on merge 7df4f3c040" [brief] | Research Insights (Premise Validation), Acceptance Criteria pre-merge 9 | mapped |
| 5 | "PR body uses Ref #12196 and Ref #12011, never Closes" [brief] | Acceptance Criteria pre-merge 8 | mapped |
| 6 | "Do NOT enter the founder uuid, do NOT flip the approval-queue flag, do NOT redeploy the web app" [brief] | Overview, Observability, Post-merge criterion 4 | mapped |
| 7 | "state exposure disclosure" and "which tests/ratchets a new .tf file in this root trips (file-selected only)" [brief] | Encryption Posture, `.tf` header, Test Scenarios, Work Phases | mapped |
| 8 | "state in the plan what the operator-visible plan output must show (exactly 4 creates)" [brief] | Operator-Visible Plan Output | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `legal-acceptance-secrets.tf` | "add apps/web-platform/infra/legal-acceptance-secrets.tf" | asked |
| Four allow-list lines in `apply-web-platform-infra.yml` | "the per-merge apply workflow (apply-web-platform-infra.yml) and its gate table / terraform-target-parity test must learn about the two new resources (apply_target, targets" | asked |
| New test layer in `cross-layer-limits.test.ts` | "which tests/ratchets a new .tf file in this root trips" | inferred — justification: no existing test reads the `.tf`; `cq-write-failing-tests-before` requires a failing test first and CTO ruling R4 chose this minimum |
| ADR-320 scope note edit | "ADR-320 and tier-A readable state rules" | asked |
| ADR-319 dated line and README edit | "state exposure disclosure" | inferred — justification: both texts say the token "does not exist yet" and become false at merge; CTO ruling R5 |
| Address-keyed stop rule | "if it contains ANYTHING beyond those four creates (any change, replace or destroy of another resource), do NOT merge" | asked |
| Names-only Doppler re-check | "never paste secrets" (values are never read) | inferred — justification: a `doppler_secret` create on an existing name overwrites silently; CTO ruling R2 |

### Split Assessment

- Subsystems touched: 3 (infra, `.github/workflows`, `apps/web-platform` test and docs) plus `knowledge-base`
- Planned files: 6 edits or creates | Estimated changed lines: about 250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. `knowledge-base` is not a subsystem root for this purpose; the files are one coherent unit and the operator approved one apply.

## Work Phases

1. **RED first.** Add the `describe` to `cross-layer-limits.test.ts`; run it file-selected (`cd apps/web-platform && npx vitest run test/legal-acceptance/cross-layer-limits.test.ts`); it must fail on "extraction found nothing" because the `.tf` does not exist.
2. **Write the `.tf`** (header per ruling R6, four blocks); `terraform fmt -check`, `terraform init -backend=false`, `terraform validate` in `apps/web-platform/infra`. Re-run the vitest file: green. Drive each Guard 1 mutation row red once on a scratch copy, then discard the copy.
3. **Allow-list.** Insert the four lines; run `bun test plugins/soleur/test/terraform-target-parity.test.ts` and `bun test plugins/soleur/test/workflow-file-size.test.ts`, then `bash tests/scripts/test-git-data-wipe-wedge.sh` and `bash tests/scripts/test-infra-privileged-tier-census.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh` (the "no C4 impact" conclusion rests on it being green; no `.c4` or ledger file is edited, so the other c4 suites and the encryption-posture lint run only if `--print-selection` names them). Use `bash scripts/test-all.sh --print-selection` once to see what the real diff selects and run only that plus these named files. Never a full battery.
4. **Docs.** 4.1 README sentence; 4.2 ADR-320 scope note with the review disposition; 4.3 ADR-319 dated line. Run `python3 scripts/lint-infra-no-human-steps.py` on the edited files.
5. **Tracking issue** for the `verify-migrations` skip on the deploy arm (what, why, re-evaluation criterion `verify/185 bad = 0` measured by a pipeline run, labels `type/chore`, `domain/engineering`, `priority/p2-medium`, milestone from the roadmap).
6. **Ship.** Commit with `LEFTHOOK_EXCLUDE=bun-test`; push only after ship's `prepush-secret-scan.sh`; mark the draft PR #12307 ready; CI is the merge gate. Evaluate the stop rule on the sticky comment; if clean, merge; read the apply run log (post-merge 1 to 4); report. If the stop rule fails, do not merge and report to the operator.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one carries the threshold `single-user incident`.
- Do not put prose comments inside the backslash-continued allow-list: a `#` line there makes the next line a command name (SC2215). Rationale lives in the `.tf` header.
- `special = false` must be written explicitly. The provider default is `true`; a removed line passes `terraform validate` and produces a value the route may reject.
- Do not add the pair to `AUDIT_PENDING_UNCOVERED` (closed to growth) or `OPERATOR_APPLIED_EXCLUSIONS` (the merge would be inert, defeating the approval basis). Do not use `[skip-web-platform-apply]`.
- The PR sticky comment is not the merge-run plan. Reading "Plan: N to add ..." off it and comparing to 4 is wrong; use the address-keyed intersection.
- Never print, echo or put the token on a command line. The boolean-only read must not use `set -x`, must pass the value through a pipe or a here-string only inside the comparison, and must print `true` or `false`.
- `apps/web-platform/.env.example` still lacks the two Doppler-only comment lines (parent AC13, blocked there by a read deny rule). Out of scope here; mention it, do not retry the edit.
- When this plan or the PR body mentions the apply, keep the words `terraform` and `apply` off the same line as an actor token in files under `knowledge-base/project/plans` and `specs` (the lint pairs them); describe it as "the merge run" instead.
- The name `LEGAL_ACCEPTANCE_FOUNDER_ID` must not appear as a Terraform resource or variable anywhere.
