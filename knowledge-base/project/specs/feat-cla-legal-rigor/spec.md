# Feature: CLA Signature Recording — Legal Rigor

## Problem Statement

The current CLA recording system (`contributor-assistant/github-action` writing `signatures/cla.json` to the `cla-signatures` branch) captures GitHub username + numeric ID + comment ID + timestamp + repo ID + a `pullRequestNo` field, but lacks evidence-quality artifacts required for a defensible BSL → Apache 2.0 relicensing event in EU/France jurisdiction:

1. **No CLA document version is captured.** The signature points to a URL (`soleur.ai/pages/legal/individual-cla.html`), not a content hash. If the doc changes, prior signatures lose provenance.
2. **No off-site tamper-evident archive exists.** The `cla-signatures` branch lives in the same repo it protects — a `contents: write` compromise can rewrite history.
3. **The verbatim sign-comment body is not persisted.** Only `comment_id` is stored; comments are author-mutable / author-deletable.
4. **`pullRequestNo` records the FIRST PR a contributor signed against**, not the PR where the signing comment was posted (e.g., Elvalio's record says #3186 but he signed on #3196).
5. **Allowlisted bots and maintainers bypass signing without any provenance record.**

These gaps were surfaced during PR #3196 verification and assessed across CLO/CTO/CPO/COO domains. PII expansion (real-name/email capture) and the wired-up Corporate CLA mechanism are out of scope here — they are deferred to a follow-up brainstorm because they involve product-strategy decisions about contributor identity capture.

## Goals

- Record a content-addressable hash of the in-repo CLA document at sign-time so prior signatures remain verifiable across edits.
- Persist the verbatim sign-comment body (and its hash) at sign-time to defeat author-side comment edits/deletions.
- Capture `signed_on_pr` (the PR where the comment was posted) alongside the existing `pullRequestNo` so audit trails are unambiguous.
- Mirror each signature to an off-site, tamper-evident store (Cloudflare R2, EU region, Governance object-lock, 10-year retention).
- Hard-fail the merge if the evidence layer fails, surfaced as a single `cla-check` (no separate confusing yellow check for first-time contributors).
- Produce a contributor-facing receipt (bot reply with doc-hash + verification one-liner) so signers can confirm what they agreed to.
- Backfill evidence records for the 2 existing signers (deruelle, Elvalio) from git history, tagged `capture_method: backfilled`.
- Record allowlist-bypass events (dependabot, claude[bot], renovate) with a provenance flag.
- Add monthly RFC 3161 timestamping of the evidence manifest as low-cost evidentiary uplift.
- Clarify in `docs/legal/individual-cla.md` that the CLA grant is a copyright license (not consent), so an Art. 7 GDPR withdrawal claim cannot collapse the license.
- Document an inspection runbook for IP-dispute / DMCA / contributor-revocation responses.

## Non-Goals

- Capturing real names or email addresses for ICLA signers (deferred to follow-up brainstorm — needs CPO+CLO joint sync).
- Building the Corporate CLA submission/recording mechanism (deferred — multi-day product investment, separate brainstorm).
- Building a contributor-side `soleur.ai/account/cla` lookup page (deferred — receipt-comment + GitHub-side lookup is the v1 trust signal).
- Forking `contributor-assistant/github-action` (rejected — sidecar pattern preferred to avoid maintenance trap).
- Compliance-mode object-lock (rejected — Governance preserves GDPR Art. 17 escape hatch).
- Re-signing existing 2 contributors (rejected — backfill from git history is asymmetric-effort-vs-evidence-value).

## Functional Requirements

### FR1: Sidecar evidence workflow

A new GitHub Actions workflow (`.github/workflows/cla-evidence.yml`) triggers on the same `pull_request_target` and `issue_comment.created` events as the existing `cla.yml`. On a sign-event, it:

- Fetches the comment body via `octokit.issues.getComment(comment_id)`.
- Reads `docs/legal/individual-cla.md` at the PR's `base.sha`.
- Computes SHA-256 of (a) the doc, (b) the comment body, (c) the resulting evidence record.
- Writes an evidence record to R2 at `signatures/<sha256-of-payload>.json` and a navigation pointer at `signatures/by-pr/<pr_number>/<comment_id>.json`.
- Surfaces a follow-up bot comment on the PR confirming the doc-hash and providing a verification one-liner.

### FR2: Hard-fail merge gate

If the sidecar fails to write evidence (R2 outage, schema violation, hash mismatch), the `cla-check` status check turns RED. The existing `contributor-assistant` action's check status is folded into the same gate so contributors see one check, not two. Maintainers see the failure via Sentry; contributors see a maintainer-actionable error message, not a contributor-actionable one.

### FR3: Backfill of existing signers

A one-shot backfill script generates evidence records for deruelle (2026-02-27, PR #328) and Elvalio (2026-05-04, PR #3196 actual sign location). Records are tagged `capture_method: backfilled` and reference the git-SHA of `docs/legal/individual-cla.md` at each respective sign-time.

### FR4: Allowlist-bypass logging

Each `allowlist` hit (`dependabot[bot]`, `github-actions[bot]`, `renovate[bot]`, `claude[bot]`) produces an evidence record with `allowlist_bypass: true` and the bypass principal. Initial proposal: one canonical bypass record per principal per quarter, refreshed on first bypass of the quarter (avoids high-volume noise from auto-merge bots). Final cadence decided in plan phase.

### FR5: Receipt comment

After the sidecar writes evidence, the bot posts a follow-up comment on the PR:

> Recorded: signed against `docs/legal/individual-cla.md` at SHA `<git-sha>` (content `sha256:<hash>`). Verify with `git show <git-sha>:docs/legal/individual-cla.md | sha256sum`. Receipt: `<r2-evidence-pointer-url>`.

### FR6: Monthly RFC 3161 timestamping

A scheduled GitHub Actions workflow runs monthly, computes the SHA-256 of the R2 bucket manifest, submits it to a free TSA (e.g., FreeTSA), stores the response as an additional R2 object at `timestamps/<yyyy-mm>/manifest.tsr`. TSA selection finalized in plan phase.

### FR7: CLA preamble update

`docs/legal/individual-cla.md` and `docs/legal/corporate-cla.md` add a clarifying preamble paragraph: "This Agreement is a copyright license grant, not a contract requiring ongoing consent under GDPR Art. 7. Once signed, the grant is irrevocable per Section [...]." Final language drafted by `legal-document-generator` agent at plan phase; reviewed by `legal-compliance-auditor`.

### FR8: Inspection runbook

`knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md` documents: (a) generating a read-only scoped R2 token, (b) retrieving evidence records for a contributor or PR, (c) producing a notarized export for legal counsel, (d) handling a GDPR Art. 17 erasure request under Governance mode.

## Technical Requirements

### TR1: Terraform root for R2 evidence bucket

New TF root at `apps/cla-evidence/infra/` (or `infra/cla-evidence/`, layout decided at plan phase based on existing convention). Contents:

- `main.tf` — R2 backend (`bucket = "soleur-terraform-state"`, `key = "cla-evidence/terraform.tfstate"`); Cloudflare provider.
- `bucket.tf` — `cloudflare_r2_bucket` with `location_hint = "weur"`, `lifecycle { prevent_destroy = true }`.
- `object_lock.tf` — `cloudflare_r2_bucket_lock_configuration` with mode = "Governance", retention = 10 years.
- `iam.tf` — `cloudflare_api_token` (write-only on the bucket, IP-allowlisted to GitHub Actions egress ranges if feasible).
- `outputs.tf` — bucket name, endpoint, no secrets.
- `variables.tf`, `README.md` — ownership, runbook link, retention policy, change-control gate.

State-write credentials are scoped *separately* from object-write credentials to limit replay if either is compromised.

### TR2: Evidence record schema (sidecar-owned)

```json
{
  "schema_version": "1.0",
  "comment_id": 123456789,
  "comment_body": "I have read the CLA Document and I hereby sign the CLA",
  "comment_body_sha256": "sha256:...",
  "comment_html_url": "https://github.com/.../pull/N#issuecomment-...",
  "actor": {
    "login": "Elvalio",
    "id": 92384917,
    "type": "User",
    "node_id": "..."
  },
  "pr_of_record": {
    "number": 3196,
    "node_id": "...",
    "base_sha": "f7561e85..."
  },
  "first_pr_signed_against": 3186,
  "cla_doc": {
    "path": "docs/legal/individual-cla.md",
    "git_sha": "f7561e85...",
    "content_sha256": "sha256:..."
  },
  "signed_at": "2026-05-04T13:13:53Z",
  "capture_method": "live",
  "allowlist_bypass": false,
  "workflow_run_id": 25324469847,
  "workflow_run_url": "https://github.com/.../actions/runs/25324469847",
  "edits": []
}
```

The `edits` array is appended to (never overwritten) by an auxiliary subscriber on `issue_comment.edited` events for the same `comment_id`.

### TR3: `pull_request_target` security envelope

The sidecar reads only trusted inputs (`comment_id`, `base.sha`); never executes PR-head code; never adds `actions/checkout` of PR head; uses Doppler-sourced R2 credentials, not PR-controlled secrets. Same constraint envelope as the existing `cla.yml`.

### TR4: Doppler secret scope

- `R2_CLA_EVIDENCE_ACCESS_KEY_ID` + `R2_CLA_EVIDENCE_SECRET_ACCESS_KEY` — workflow object-write keys, in Doppler config `prd_cla` and `ci`.
- `R2_CLA_EVIDENCE_TF_ACCESS_KEY_ID` + `R2_CLA_EVIDENCE_TF_SECRET_ACCESS_KEY` — Terraform state-write keys, in `prd_terraform`. Distinct from object-write keys.

Both rotated per the existing `cloudflare-service-token-rotation.md` runbook cadence (verify and update if `gh secret set` from Doppler is not yet documented there).

### TR5: Observability

All sidecar catch paths use `reportSilentFallback(err, { feature: "cla-evidence", op, extra })` per `cq-silent-fallback-must-mirror-to-sentry`. R2 write failure → 3 retries with backoff → hard-fail with Sentry alert. Workflow run URL and event payload embedded in evidence record so 90-day GitHub Actions log expiry doesn't lose audit trail.

### TR6: Privacy / DPA / GDPR Policy updates

Per the 2026-02-26 GDPR-update learning, any new sub-processor or processing activity triggers a three-document update:

- `docs/legal/privacy-policy.md` — note R2/Cloudflare as evidence-archive sub-processor (verify already-listed; if so, no change).
- `docs/legal/data-protection-disclosure.md` — add processing activity entry for off-site evidence archive.
- `docs/legal/gdpr-policy.md` — re-run the three-part balancing test for the off-site archive; document the legitimate-interest basis (defense of legal claims under Art. 17(3)(e)).

Eleventy mirrors at `plugins/soleur/docs/pages/legal/` updated in the same commit.

### TR7: Brand-survival threshold

Inherited from brainstorm User-Brand Impact: `single-user incident` for PII axis, `aggregate pattern` for IP and friction axes. Plan phase carries this forward; review phase requires `user-impact-reviewer` sign-off.

### TR8: Backfill script

One-shot Bun/Node script (location TBD at plan phase, likely `scripts/cla-backfill-evidence.ts`) that:

1. Reads existing `signatures/cla.json` from the `cla-signatures` branch.
2. For each row, finds the git-SHA of `docs/legal/individual-cla.md` at the row's `created_at` timestamp via `git log --until=<timestamp> -1 --format=%H -- docs/legal/individual-cla.md`.
3. Reconstructs the comment body via `octokit.issues.getComment(comment_id)` (still available — comments not deleted).
4. Builds an evidence record with `capture_method: backfilled` and uploads to R2.

Idempotent: re-running produces identical content-addressed keys.

### TR9: Test coverage

- Unit tests: hash computation, schema validation, allowlist-bypass detection.
- Integration test: full sign-flow on a fixture PR, verifying evidence record matches expected schema and lands at expected R2 key.
- Backfill test: re-run produces stable output for the 2 known signers.
- Smoke test: hard-fail behavior when R2 is unreachable.

Per `cq-write-failing-tests-before` (skill-enforced at work Phase 2), tests are written before implementation when the plan includes Test Scenarios.
