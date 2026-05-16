---
title: CLA Legal-Rigor Evidence Layer
type: feature
classification: feature-with-infra
issue: 3209
brainstorm: knowledge-base/project/brainstorms/2026-05-04-cla-legal-rigor-brainstorm.md
spec: knowledge-base/project/specs/feat-cla-legal-rigor/spec.md
branch: feat-cla-legal-rigor
worktree: .worktrees/feat-cla-legal-rigor/
draft_pr: 3201
deferred_issues: [3210, 3211]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
domains_relevant: [legal, engineering, product, operations]
date: 2026-05-04
---

# Plan: CLA Legal-Rigor Evidence Layer

## Overview

Add a sidecar evidence layer alongside the existing `contributor-assistant/github-action` CLA flow so a future BSL → Apache 2.0 relicensing event is defensible in EU/France jurisdiction. The action remains the canonical signed-list writer; the sidecar captures the artifacts that make signatures evidentiary (doc-hash, verbatim comment body, PR-of-record, allowlist-bypass provenance) and mirrors them to a tamper-evident off-site archive (Cloudflare R2, EU region, Governance object-lock, 10-year retention).

Scope locked at brainstorm: 4 zero-friction fixes (gaps 1, 2, 4, 5) + 4 hidden gaps (allowlist-bypass logging, RFC 3161 monthly timestamping, CLA preamble revocation clause, inspection runbook). PII expansion + CCLA mechanism wiring deferred to #3210; contributor-side lookup page deferred to #3211.

The plan corrects 8 spec-vs-codebase reconciliations surfaced by repo research, handles 5 P1 flow gaps surfaced by spec-flow-analysis (`issue_comment.edited`/`.deleted` events, bootstrap chicken-and-egg, dual-check folding, comment-body 404 vs hard-fail semantics, GDPR Art. 17 tombstone protocol), and applies 7 plan-review fixes (phantom Phase 11 removed, bot-identity DB-ID 41898282 filter, schema-version third consumer, schema-mismatch test scenarios, 4xx-vs-5xx retry split, `upload-evidence.sh` reconciliation, allowlist-key bracket sanitization) plus 4 cross-reviewer-agreed simplifications (no Sentry-from-workflow helper, no R2 IP-allowlist + CIDR refresh script, receipt comment folded into sidecar workflow, Domain Review trimmed).

## User-Brand Impact

**If this lands broken, the user experiences:** a contributor whose evidence record is silently dropped — at relicensing time, Jikigai cannot defend the license grant for that contributor's code, forcing either re-acquisition (impossible if the contributor is unreachable) or removal of their commits from the relicensable corpus.

**If this leaks, the user's data is exposed via:** the only PII in this scope is GitHub identity (already public on github.com). PII expansion is deferred to #3210, so the R2 bucket holds no novel PII at this scope. However, the `gdpr-policy.md` balancing test must still cover the R2 sub-processor relationship since the bucket is a new processing location for already-public identifiers.

**Brand-survival threshold:** `single-user incident` (PII axis — for forward-compat with #3210 PII work) AND `aggregate pattern` (IP and friction axes — one missing record may not kill us, a dozen do). Carry-forward from brainstorm Phase 0.1. CPO sign-off is required at plan time (`requires_cpo_signoff: true` in frontmatter); `user-impact-reviewer` runs at review time per `plugins/soleur/skills/review/SKILL.md`.

## Research Insights

### Carry-forward from brainstorm domain assessments

- **CLO**: Doc hash (gap 1) and verbatim comment text (gap 4) are must-fix for relicensing in EU/France jurisdiction; off-site archive (gap 2) is must-fix-lite; PII (gap 3) is deferred to #3210; pullRequestNo (gap 5) is theater-adjacent. Strong-evidence fixes *activate* GDPR Art. 17(3)(e) legal-claims carveout — they reduce GDPR liability rather than add to it.
- **CTO**: Sidecar over fork. Per-event R2 upload at sign-time. Hash source: in-repo `docs/legal/individual-cla.md` at PR base SHA. Hard-fail on evidence-layer failure.
- **CPO**: Single folded check. Bot receipt comment with verification one-liner. Backfill, not re-sign.
- **COO**: Governance object-lock (preserves Art. 17 escape hatch). EU region. Distinct Doppler scopes for object-write vs state-write. New TF root, copy backend stanza from `apps/web-platform/infra/main.tf`. Inspection runbook required regardless.

### Institutional learnings to apply

| # | Learning | Application |
|---|---|---|
| 1 | `2026-02-26-cla-system-implementation-and-gdpr-compliance.md` | Baseline; new layer is additive. `pull_request_target` chicken-and-egg requires `gh pr merge --admin` for the bootstrap PR. Three-document GDPR update pattern. |
| 2 | `2026-04-27-cla-allowlist-graphql-vs-rest-bot-identity-surface.md` | The CLA action filters `github-actions[bot]` (DB-id 41898282) BEFORE the allowlist check; sidecar must apply the same filter or it overcounts bypasses. Bot identity surface = GraphQL `commit.author.user.login` (e.g., `claude[bot]`), NOT REST `app/<slug>`. |
| 3 | `2026-03-19-content-publisher-cla-ruleset-push-rejection.md` | The monthly RFC 3161 cron job CANNOT direct-push the `.tsr` file to `main` from `github-actions[bot]` — the CLA Required ruleset rejects the push. Must use PR-with-auto-merge pattern. |
| 4 | `2026-02-21-github-actions-workflow-security-patterns.md` + `2026-02-27-github-actions-sha-pinning-workflow.md` | Pin every action to SHA. Validate `workflow_dispatch` regex inputs. |
| 5 | `2026-03-05-github-output-newline-injection-sanitization.md` | `$GITHUB_OUTPUT` newline injection from PR-author-controlled fields (comment body, PR title). Sanitize via `${var//[$'\n\r']/}` before any `>> $GITHUB_OUTPUT`. |
| 6 | `2026-03-21-github-actions-heredoc-yaml-and-credential-masking.md` | Doppler-fetched secrets are NOT auto-masked — explicit `::add-mask::` required. Flush-left HEREDOCs break YAML. |
| 7 | `2026-03-21-ci-terraform-plan-workflow.md` | Randomize `GITHUB_OUTPUT` heredoc delimiter (`PLAN_EOF_$(openssl rand -hex 8)`) when piping multiline content. |
| 8 | `2026-03-21-terraform-state-r2-migration.md` | R2 backend `use_lockfile = false` (R2 lacks S3 conditional writes for state files). Single-writer `terraform apply` assumption. |
| 9 | `2026-03-20-doppler-secrets-manager-setup-patterns.md` + `2026-03-29-doppler-service-token-config-scope-mismatch.md` | Doppler service tokens are scoped to ONE project+config at creation. `prd_cla` config requires its own token; cannot reuse the `prd_terraform` token. |
| 10 | `2026-05-04-github-secrets-cannot-start-with-github-prefix.md` | `gh secret set` rejects names starting with `GITHUB_*` (HTTP 422). Avoid such prefixes. |
| 11 | `2026-04-03-github-ruleset-put-replaces-entire-payload.md` + `2026-03-19-github-ruleset-stale-bypass-actors.md` | Ruleset PUT is full-replace, not partial. Ghost bypass actors persist — sweep and rewrite the entire payload. |
| 12 | `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs.md` + `2026-03-20-github-required-checks-skip-ci-synthetic-status.md` | `[skip ci]` deadlocks required Check Runs. Required checks need Check Runs from `integration_id 15368`, not Status API. Monthly cron PR must NOT use `[skip ci]`. |
| 13 | `2026-03-16-scheduled-skill-wrapping-pattern.md` | Three-layer scheduled-skill pattern (workflow auth + composition). Adapt for monthly RFC 3161 job — but RFC 3161 is OpenSSL/curl, not a skill. Use the workflow-auth pattern only. |
| 14 | `2026-03-30-dependency-graph-enablement-and-synthetic-check-coverage.md` | Synthetic check coverage gaps cause vacuous passes. Required-checks integration_id matters. |
| 15 | `2026-03-20-eleventy-mirror-dual-date-locations.md` | Each Eleventy legal mirror has TWO `Last Updated` locations (hero `<p>` + body markdown). Update both. |
| 16 | `2026-03-18-dpd-processor-table-dual-file-sync.md` | `docs/legal/*.md` and `plugins/soleur/docs/pages/legal/*.md` drift silently. Edit both atomically. |
| 17 | `2026-03-02-legal-doc-bulk-consistency-fix-pattern.md` + `2026-02-20-dogfood-legal-agents-cross-document-consistency.md` | 16 legal files total. Scope edits across all of them first; budget for generate→audit→reaudit cycles. |
| 18 | `best-practices/2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.md` | Per AGENTS.md sharp-edge: `schema_version` constants are cosmetic unless the consumer asserts them on read. Backfill script + sidecar consumer + retrieval inspection script must each assert `schema_version === "1.0"` at parse time. |

### External research

- **FreeTSA** (verified via WebFetch 2026-05-04): free, no account required, endpoint `https://freetsa.org/tsr`, accepts RFC 3161 `Content-Type: application/timestamp-query`, supports SHA-256, returns binary `.tsr`, root CA at `https://freetsa.org/files/cacert.pem`, TSA cert at `https://freetsa.org/files/tsa.crt`. **No published SLA.** "Do not abuse" caveat — once-monthly submission for our manifest is well within reasonable use. <!-- verified: 2026-05-04 source: https://freetsa.org/index_en.php -->
- **Cloudflare R2 object-lock** (per CTO + COO): Governance mode permits admin override; Compliance mode is root-immutable. R2 supports `location_hint = "weur"` for EU bucket placement. R2 supports If-None-Match conditional PUT (used for race-free allowlist-bypass quarterly canonical record).

## Research Reconciliation — Spec vs. Codebase

| # | Spec claim | Reality | Plan response |
|---|---|---|---|
| 1 | `apps/web-platform/server/observability.ts` `reportSilentFallback` will be called from sidecar workflow catch paths (TR5). | The helper is **server-side TypeScript** (imports `@sentry/nextjs`, `@/server/logger`). Cannot be imported from a GitHub Actions shell step. | Plan-review converged on: do NOT introduce a Sentry-from-workflow helper. Sidecar catch paths emit `::error::` annotations, write to `$GITHUB_STEP_SUMMARY`, and rely on Check Run RED + GitHub workflow-failure email for operator visibility. The `cq-silent-fallback-must-mirror-to-sentry` rule is scoped to server-side code paths (Next.js runtime); workflow-level failures are already loud via the Check Run + email. Revisit if event volume ever justifies Sentry routing (will not at 2-signer scale). |
| 2 | `.github/workflows/secret-scan.yml` is a "read-only audit + Sentry mirror on failure" precedent. | Verified: `secret-scan.yml` is purely log-based (`::error::` / `::warning::` / `$GITHUB_STEP_SUMMARY`). No Sentry call exists in any workflow YAML. | Acknowledge: there is no Sentry-from-workflow precedent. Plan does NOT create one. Sidecar follows the existing `secret-scan.yml` pattern (annotations + step summary + Check Run RED). |
| 3 | Copy R2 backend + bucket-resource Terraform from `apps/web-platform/infra/main.tf`. | The backend stanza exists (lines 1–31). **No `cloudflare_r2_bucket` resource exists anywhere in the repo.** State bucket was provisioned out-of-band. | Phase 1 declares the `cloudflare_r2_bucket` resource greenfield. Document the resource shape with `location_hint = "weur"`, `lifecycle { prevent_destroy = true }`, and Governance object-lock configuration as the new precedent. |
| 4 | `secret-scan.yml` is a `pull_request_target` precedent. | Verified: `secret-scan.yml` is `pull_request`, NOT `pull_request_target`. Only `cla.yml` uses `pull_request_target`. | Cite `cla.yml` only as the security envelope precedent. |
| 5 | Cloudflare token-rotation runbook documents `gh secret set` from Doppler. | Verified: runbook pipes from `terraform output … \| gh secret set CF_*`. Doppler is not the source. | Phase 1 Step 7 documents the new `gh secret set` flow specifically for `R2_CLA_EVIDENCE_*` keys, sourced from Doppler `prd_cla` config (different pattern from existing CF token rotation, intentional — see learning #9). |
| 6 | Expense ledger lives at `knowledge-base/engineering/ops/runbooks/...`. | Verified: lives at `knowledge-base/operations/expenses.md`. | Phase 9 edits the correct path. |
| 7 | Doppler config for workflow secrets: spec referenced `prd_cla` + `ci`. | Verified: existing configs are `dev`, `dev_personal`, `ci`, `prd`, `prd_scheduled`, `prd_terraform`. `prd_cla` does NOT exist. | Phase 1 Step 5 creates `prd_cla` as a new Doppler config, separate from `prd_terraform` per learning #9. Workflow uses `DOPPLER_TOKEN_CLA` (matches existing `DOPPLER_TOKEN_PRD` suffix pattern from `web-platform-release.yml`). |
| 8 | Branch protection / required checks management is via Terraform. | Verified: managed via shell scripts (`scripts/create-cla-required-ruleset.sh`, `scripts/create-ci-required-ruleset.sh`). Required-checks list in `scripts/required-checks.txt`. PUT is full-replace per learning #11. | Phase 2 Step 6 extends `scripts/create-cla-required-ruleset.sh` to include `cla-evidence` Check Run (integration_id 15368, per learning #12). Full payload re-PUT to avoid ghost bypass actors. |

## Open Code-Review Overlap

**None.** Queried 34 open `code-review` issues against 12 paths the plan touches (`.github/workflows/cla.yml`, all six legal docs in source + Eleventy mirrors, `knowledge-base/operations/expenses.md`, `apps/web-platform/server/observability.ts`, `apps/web-platform/infra/main.tf`, `scripts/create-cla-required-ruleset.sh`, `knowledge-base/engineering/ops/runbooks/cloudflare-service-token-rotation.md`). Zero matches.

## Implementation Phases

The phasing prioritizes legal-evidence depth over feature breadth: foundation (TF + Doppler) → live capture (sidecar with receipt) → backfill of existing 2 signers → allowlist-bypass logging → RFC 3161 monthly chain → legal-doc updates → inspection runbook → bootstrap & smoke → ledger + sharp-edge sweep. Each phase is self-contained except Phase 1 (Terraform) which is a foundation for Phases 2–5.

### Phase 1: R2 evidence-bucket Terraform foundation

**Goal:** provision a tamper-evident off-site archive ready to receive evidence records, with separate scoped credentials for object-writes vs state-writes.

1. Create new TF root at `apps/cla-evidence/infra/`:
   - `main.tf` — R2 backend (`bucket = "soleur-terraform-state"`, `key = "cla-evidence/terraform.tfstate"`, `use_lockfile = false`); Cloudflare provider `~> 4.0`; `cf_api_token` variable.
   - `bucket.tf` — `cloudflare_r2_bucket` greenfield resource: `name = "soleur-cla-evidence"`, `location_hint = "weur"`, `lifecycle { prevent_destroy = true }`.
   - `object_lock.tf` — `cloudflare_r2_bucket_lock_configuration`: `default_retention { mode = "Governance", days = 3650 }` (10 years).
   - `iam.tf` — TWO `cloudflare_api_token` resources: one with **object-write only** (PutObject, PutObjectRetention) on `soleur-cla-evidence`, one with **state-write only** on the `cla-evidence/` prefix of `soleur-terraform-state`. Distinct tokens prevent state-compromise replay (per COO defense-in-depth). **No IP-allowlist** — already-public-data bucket; recurring CIDR-refresh ops cost exceeds marginal security gain (plan-review converged on this). Read access for the inspection runbook is generated ad-hoc via Cloudflare dashboard with 24h TTL (Phase 7 documents).
   - `outputs.tf` — bucket name, bucket endpoint, R2 access-key-id (sensitive), R2 secret-access-key (sensitive). No plaintext outputs.
   - `variables.tf` — `cf_api_token`, `cf_account_id`.
   - `README.md` — ownership (deruelle / ops@jikigai.com), runbook link (placeholder until Phase 7), retention policy, change-control gate, single-writer `terraform apply` assumption (R2 backend has no lock per learning #8).

2. Operator approves `terraform init && terraform apply` per `hr-menu-option-ack-not-prod-write-auth`. Per-command ack required: show the planned resource diff first, then apply with `-auto-approve` after explicit operator go-ahead.

3. Verify post-apply: `aws s3api get-object-lock-configuration --bucket soleur-cla-evidence --endpoint-url <r2-endpoint>` returns Governance mode + 3650 days.

4. Create new Doppler config `prd_cla` (operator action — `doppler configs create prd_cla --project soleur`). Set R2 access-key + secret-access-key from Terraform outputs. Generate Doppler service token scoped to `prd_cla` (per learning #9 — service tokens are config-pinned at creation); sync to GitHub repo secret as `DOPPLER_TOKEN_CLA`.

5. Add **expense ledger entry** to `knowledge-base/operations/expenses.md` (Phase 9 also confirms this; placed early so the entry exists if Phase 9 is interrupted):
   ```
   | Cloudflare R2 (cla-evidence) | Cloudflare | storage | 0.00 | active | - | Off-site CLA signature archive, Governance object-lock, 10yr retention, region weur. Pay-per-use: $0.015/GB-mo + $0.36/M writes. Sub-cent/mo at realistic scale. See apps/cla-evidence/infra/. |
   ```

6. Document the new Doppler-sourced workflow-secret rotation flow as a sibling section in `knowledge-base/engineering/ops/runbooks/cloudflare-service-token-rotation.md` (one-line cross-link; Phase 7 owns the standalone CLA evidence runbook).

**Tests (Phase 1):**
- `apps/cla-evidence/infra/main.test.sh` — `terraform validate`, `terraform fmt -check`, lint for `prevent_destroy = true`, lint for Governance mode + 3650 days.
- Integration: a sentinel `terraform plan` in CI (`infra-validation.yml` extension) that shows zero drift after apply.

### Phase 2: Sidecar workflow + receipt comment (TDD, RED first)

**Goal:** capture evidence at sign-time with hard-fail merge gating; post a contributor-visible verification receipt as a soft-fail final step.

1. Write failing tests (per `cq-write-failing-tests-before` — this phase has Acceptance Criteria so TDD applies):
   - `apps/web-platform/scripts/cla-evidence/__tests__/hash.test.ts` — `computeDocHash(repoRoot, baseSha)` returns deterministic SHA-256 of `docs/legal/individual-cla.md` at the given SHA. Test against fixture commits.
   - `apps/web-platform/scripts/cla-evidence/__tests__/schema.test.ts` — `validateEvidenceRecord(payload)` rejects missing required fields (`schema_version`, `comment_id`, `comment_body`, `comment_body_sha256`, `actor`, `pr_of_record`, `cla_doc`, `signed_at`, `capture_method`, `workflow_run_id`). Asserts `schema_version === "1.0"` at parse time and exits non-zero on mismatch.
   - `apps/web-platform/scripts/cla-evidence/__tests__/allowlist.test.ts` — `isAllowlistBypass(login, dbId)` returns true for `dependabot[bot]`, `renovate[bot]`, `claude[bot]`; **false for `github-actions[bot]` (DB-id 41898282) because the upstream CLA action filters that actor BEFORE the allowlist check** (learning #2). Reads allowlist from `.github/workflows/cla.yml` to stay in sync with the upstream filter.
   - `apps/web-platform/scripts/cla-evidence/__tests__/comment-fetch.test.ts` — `fetchCommentBody(comment_id)` retries 5xx/429 with exponential backoff (max 3 attempts); returns `{ status: "404", body: null }` on 404 (does NOT retry); returns `{ status: "ok", body, sha256 }` on success. `fetchCommentBody` returns `{ status: "fatal-4xx", code }` for 401/403/400 (does NOT retry — fast-fail).
   - `apps/cla-evidence/scripts/upload-evidence.test.sh` — content-addressed key `signatures/<sha256>.json`; conditional PUT (If-None-Match: *) returns 200 on first write, 412 on duplicate, fast-fails on any 4xx other than 412 (per Kieran F5); `signatures/by-pr/<pr>/<comment_id>.json` pointer is updated atomically only when payload-sha matches.

2. Implement helpers in `apps/web-platform/scripts/cla-evidence/`:
   - `hash.ts` — `computeDocHash`, `computeBodyHash`.
   - `schema.ts` — `EvidenceRecord` Zod schema, `validateEvidenceRecord` consumer-boundary assertion (schema_version === "1.0", exit 3 on mismatch — paralleling the cited learning's bash convention).
   - `allowlist.ts` — `isAllowlistBypass(login: string, dbId: number): boolean`. Allowlist source-of-truth = `.github/workflows/cla.yml` `with.allowlist`, parsed at workflow run-time. **Excludes DB-id 41898282** (`github-actions[bot]`) regardless of allowlist match because the upstream action drops these events upstream — including them would produce false-positive evidence records.
   - `comment-fetch.ts` — `fetchCommentBody` with retry-aware error classes; 5xx/429 → exponential backoff (max 3); 404 → degraded; 401/403/400 → fast-fail.
   - `apps/cla-evidence/scripts/upload-evidence.sh` — production R2 conditional-PUT helper. **The sidecar workflow invokes this script** (`run: bash apps/cla-evidence/scripts/upload-evidence.sh "$payload"`); the test runs the same script. No drift between test and production code path (resolves Kieran F7).

3. Implement `.github/workflows/cla-evidence.yml`:
   - Triggers: `pull_request_target` (`opened`, `synchronize`, `reopened`) + `issue_comment` (`created`, `edited`, `deleted`). The `edited` and `deleted` triggers handle spec-flow gap #1.
   - Permissions: `contents: read`, `pull-requests: write` (for receipt comment), `statuses: write` (for cla-check status). NOT `contents: write`.
   - Concurrency: `group: cla-evidence-${{ github.event.pull_request.number || github.event.issue.number }}` to serialize per-PR events.
   - Sanitize all PR-derived data before writing to `$GITHUB_OUTPUT`: `sanitized=${comment_body//[$'\n\r']/}` per learning #5.
   - Mask Doppler-fetched R2 tokens via `::add-mask::` per learning #6.
   - Step sequence:
     a. `actions/checkout` of base ref ONLY (no PR head) per `pull_request_target` security envelope.
     b. Doppler step (`doppler/cli-action` pinned to SHA) loads R2 keys with `DOPPLER_TOKEN_CLA`.
     c. Determine event type. On `pull_request_target`: skip evidence write (no sign event), proceed to status-check folding (Step 6 below). On `issue_comment.created` with sign-phrase + accepted by action: continue. On `.edited`: append to existing tombstone. On `.deleted`: append to existing tombstone.
     d. Compute `doc_git_sha = github.event.pull_request.base.sha`. Compute `doc_content_sha256` via `git show $doc_git_sha:docs/legal/individual-cla.md | sha256sum`.
     e. Fetch comment body (`comment-fetch.ts`). On 404, write degraded record with `comment_body_fetch_failed: true, fetch_error: "404", capture_method: "live-degraded"`. CLO sign-off accepted at plan time that degraded record IS sufficient evidence (the action's `cla.json` row + GraphQL audit log corroborate). On 5xx/429 after 3 retries, hard-fail. On 401/403/400, fast-fail (no retry — config bug, not transient).
     f. Build evidence record per TR2 schema; assert `schema_version === "1.0"` at validate-time.
     g. Invoke `bash apps/cla-evidence/scripts/upload-evidence.sh "$payload_json"`. The script handles conditional-PUT: 200 on first write, 412 (duplicate) → exit 0 cleanly; 5xx/429 → retry with backoff up to 3 times then hard-fail; **4xx other than 412 → fast-fail with `::error::` annotation** (per Kieran F5; e.g., 403 from a stale R2 token is a config bug, not transient).
     h. Write pointer at `signatures/by-pr/<pr_number>/<comment_id>.json` if `payload_sha` matches the content-addressed key.
     i. **Receipt comment as final step (folded from former Phase 4 per Code-Simplicity F4):** on success, post a follow-up comment via `gh api` with `continue-on-error: true`:
        > Recorded: signed against `docs/legal/individual-cla.md` at SHA `<git-sha>` (content `sha256:<hash>`). Verify with `git show <git-sha>:docs/legal/individual-cla.md | sha256sum`. Receipt: `signatures/by-pr/<pr-number>/<comment-id>.json` in the cla-evidence bucket.
        Receipt is **soft-fail** — failure does NOT block the merge gate (resolves spec-flow gap #11). Failure produces a `::warning::` annotation only. Evidence record is the canonical proof.
     j. On any caught error in steps a–h, emit `::error::` annotation + `$GITHUB_STEP_SUMMARY` entry (no Sentry helper per Reconciliation #1+#2). Set `cla-check` Check Run status to RED.

4. Handle the bootstrap chicken-and-egg (spec-flow gap #3): the workflow file does not exist on `main` until this PR merges, so it cannot self-validate. Plan acknowledges:
   - First merge uses `gh pr merge --admin` (operator action — explicit per-command ack per `hr-menu-option-ack-not-prod-write-auth`).
   - Phase 8 immediately follows up with a sentinel test PR exercising the live sidecar (per `wg-after-merging-a-pr-that-adds-or-modifies`).
   - Document this explicitly in PR body so reviewers do not block on "where are the green checks for the workflow itself."

5. Handle dual-check folding (spec-flow gap #4): the action's check is named `license/cla` (Status API); the sidecar's check is named `cla-check` (Check Runs API, integration_id 15368, per learning #12). Branch protection requires `cla-check` (sidecar) only — the action's check is informational. Sidecar's `cla-check` is RED until both (a) the action accepts the signature AND (b) the evidence write succeeds. Implementation:
   - Step 6 of the workflow polls the action's `license/cla` status via `gh api repos/.../statuses/<sha>` for up to 30s (bounded `--max-time 30`). If green, sidecar runs; if red or pending, sidecar reports `cla-check` as pending (matching the action's state).
   - Acknowledge in PR body and runbook: there is a brief two-check window during which the action's `license/cla` is visible but only `cla-check` is required.

6. Update `scripts/create-cla-required-ruleset.sh` to include `cla-evidence` workflow's `cla-check` Check Run as a required check (integration_id 15368). Full PUT payload re-PUT per learning #11. **NOT `[skip ci]`** anywhere in the cron flow per learning #12.

7. Branch-protection ruleset apply runs as an operator action — explicit per-command ack per `hr-menu-option-ack-not-prod-write-auth`.

**Tests (Phase 2):** all RED first per `cq-write-failing-tests-before`. Integration smoke deferred to Phase 8 (sentinel PR).

### Phase 3: Backfill of existing 2 signers

**Goal:** synthesize evidence records for deruelle and Elvalio retroactively, idempotently.

1. Implement `apps/web-platform/scripts/cla-backfill-evidence.ts` (TypeScript, runnable via `bun`):
   - Read existing `signatures/cla.json` from `cla-signatures` branch.
   - **Assert `schema_version === "1.0"` at parse time on every input record (consumer-boundary contract; failure → exit 3 per learning #18).** This is consumer #1 of three.
   - For each row:
     a. Fetch comment body via `octokit.issues.getComment(comment_id)` (still available — comments not deleted).
     b. Find git-SHA of `docs/legal/individual-cla.md` at the row's `created_at` timestamp via `git log --until="$created_at" -1 --format=%H -- docs/legal/individual-cla.md`. If `git log` returns no SHA (e.g., deruelle's PR #328 from 2026-02-27 may pre-date the file's introduction), use the first commit that introduced the file and tag `capture_method: "backfilled-pre-existed"` so the evidentiary tier is honest.
     c. Build evidence record with `capture_method: "backfilled"`.
     d. Invoke `bash apps/cla-evidence/scripts/upload-evidence.sh "$payload"` — same conditional-PUT path as the sidecar; idempotent.
   - Backfill the `signedOnPR` correction: Elvalio's row says `pullRequestNo: 3186` but he signed on `#3196` (per brainstorm note + verified in PR #3196 comments). Backfill record uses `pr_of_record.number = 3196` and `first_pr_signed_against = 3186`.

2. Run as a one-shot operator action AFTER Phase 2 ships and is verified via Phase 8 sentinel. Backfill against the live R2 bucket; `If-None-Match` ensures idempotency.

3. Document in spec.md TR8 reconciliation: deruelle 2026-02-27 PR #328, Elvalio 2026-05-04 PR #3196 (NOT #3186 as recorded by the action).

**Tests (Phase 3):**
- `apps/web-platform/scripts/cla-evidence/__tests__/backfill.test.ts` — fixture two-signature `cla.json`; backfill output is deterministic; re-run produces zero new R2 writes (412 on every conditional PUT); `schema_version` asserted on read.

### Phase 4: Allowlist-bypass logging (per-quarter canonical via If-None-Match)

**Goal:** record bot/maintainer bypass events with provenance, race-free.

1. Resolve **brainstorm open question (a)** to: **per-quarter canonical record** (one row per principal per quarter), race-free via R2 conditional-PUT.

2. Sidecar detects allowlist-bypass via `isAllowlistBypass(actor.login, actor.id)`. On bypass:
   - **Sanitize key** (per Kieran F8): `principal_safe = principal.replace(/\[bot\]/g, "-bot")`. Deterministic key: `allowlist/<principal_safe>/<yyyy-qq>.json` (e.g., `allowlist/dependabot-bot/2026-q2.json`). The canonical login (`dependabot[bot]`) is preserved inside the JSON payload's `principal` field.
   - Build canonical record: `{schema_version: "1.0", principal, principal_safe, db_id, quarter, first_seen_at, first_pr, allowlist_source: "cla.yml#with.allowlist"}`.
   - Conditional-PUT with `If-None-Match: *`. First write succeeds (201/200); subsequent writes for the same principal+quarter return 412 — workflow exits 0, no error.

3. **`github-actions[bot]` (DB-id 41898282) is NEVER recorded** because the upstream CLA action filters those events before the allowlist check fires (learning #2). The sidecar's `isAllowlistBypass(login, dbId)` returns false for that DB-id regardless of login string, preventing false-positive records.

4. This handles spec-flow gap #7 (allowlist-bypass timing race condition) deterministically. No separate scheduler.

**Tests (Phase 4):**
- `apps/web-platform/scripts/cla-evidence/__tests__/allowlist-bypass.test.ts` — first call writes 200, second call gets 412, third call (different quarter) writes 200. **`github-actions[bot]` DB-id input produces NO write** (returns false from `isAllowlistBypass`, sidecar skips). Sanitized key uses `dependabot-bot` not `dependabot[bot]`.

### Phase 5: RFC 3161 monthly timestamping

**Goal:** unbroken evidentiary chain over time.

1. Resolve **brainstorm open question (b)** to: **FreeTSA primary**, paid-TSA fallback documented but not implemented in v1.

2. Implement `.github/workflows/cla-evidence-timestamp.yml`:
   - Schedule: `cron: '0 6 1 * *'` (1st of every month, 06:00 UTC). NOT `[skip ci]` per learning #12.
   - Permissions: `contents: read`, `pull-requests: write` (for the auto-merge PR per learning #3).
   - Step sequence:
     a. Doppler step loads R2 read keys with `DOPPLER_TOKEN_CLA` (read-only token issued ad-hoc by operator and synced as `R2_CLA_EVIDENCE_READ_*` Doppler secrets — short-lived, rotated per-month).
     b. List all current objects in `signatures/`, `allowlist/`, and `tombstones/` prefixes; build manifest as JSONL with `{key, etag, size, last_modified}`. Hash with SHA-256.
     c. **Always-timestamp**: include the current month (YYYY-MM) in the manifest pre-image to force a unique payload per month even if no signers were added (resolves spec-flow gap #9).
     d. Build RFC 3161 TSQ via `openssl ts -query -data <manifest> -sha256 -cert -no_nonce -out request.tsq`.
     e. POST to FreeTSA: `curl --max-time 30 -H "Content-Type: application/timestamp-query" --data-binary @request.tsq https://freetsa.org/tsr -o response.tsr`. Bounded timeout per AGENTS.md plan-skill sharp-edge.
     f. Verify: `openssl ts -verify -in response.tsr -data <manifest> -CAfile freetsa-cacert.pem -untrusted freetsa-tsa.crt`. Bundle the FreeTSA cacert + TSA cert as repo assets at `apps/cla-evidence/freetsa/`.
     g. Upload TSR to R2 at `timestamps/<yyyy-mm>/manifest.tsr` and the manifest itself at `timestamps/<yyyy-mm>/manifest.jsonl`.
     h. **TSA-outage handling**: if curl fails or `openssl ts -verify` fails, retry on the next workflow_dispatch (operator-triggered) up to 7 days. After 7 consecutive failures: emit `::error::` AND **auto-file a tracking issue** (per Kieran F9): `gh issue create --label cla-evidence,timestamp-failure --title 'FreeTSA outage YYYY-MM' --body <runbook-link>`. Continue (gap acceptable, alert + tracking issue mandatory).
     i. Open a PR adding `timestamps/<yyyy-mm>/manifest.tsr` + `manifest.jsonl` to the `cla-signatures` branch via PR-with-auto-merge (NOT direct push from `github-actions[bot]` per learning #3). PR title `chore(cla-evidence): RFC 3161 timestamp YYYY-MM`. Auto-merge label `automerge` triggered by existing automation.

3. Document paid-TSA fallback (DigiCert, GlobalSign) in the inspection runbook (Phase 7). Not implemented in v1; switch trigger = "FreeTSA fails 3 consecutive months."

**Tests (Phase 5):**
- `apps/cla-evidence/scripts/timestamp.test.sh` — fixture manifest hash + recorded `.tsr` from a test FreeTSA submission; verify-then-replay test ensures `openssl ts -verify` produces the expected verdict.

### Phase 6: Legal-document updates (CLA preamble + GDPR three-document pattern)

**Goal:** preserve the GDPR Art. 17(3)(e) legal-claims defense and clarify the CLA grant is a license, not consent.

1. Engage `legal-document-generator` agent to draft the revocation-clause preamble for `docs/legal/individual-cla.md` and `docs/legal/corporate-cla.md`. Brief:
   > "This Agreement is a copyright license grant, not a contract requiring ongoing consent under GDPR Art. 7. Once signed, the grant is irrevocable for the contributions covered by this signature. A withdrawal of signature does not retract the license previously granted, but does indicate that future contributions will not be made."
   The agent's output is a draft requiring `legal-compliance-auditor` review.

2. `legal-compliance-auditor` reviews the draft against existing CLA text + Privacy Policy + DPA + GDPR Policy. Findings folded into a single edit batch.

3. Apply the three-document GDPR update pattern (per learning #1) — update ALL of:
   - `docs/legal/privacy-policy.md` — add R2/Cloudflare as evidence-archive sub-processor (verify Cloudflare is already listed; if so, no change to processor table — but add the bucket to the processing-locations section).
   - `docs/legal/data-protection-disclosure.md` — add new processing activity entry: "CLA evidence archive (off-site)."
   - `docs/legal/gdpr-policy.md` — re-run the three-part balancing test for the off-site archive; document legitimate-interest basis (defense of legal claims under Art. 17(3)(e)).

4. Apply Eleventy mirrors per learnings #15 and #16 — every edit lands in BOTH `docs/legal/<file>.md` AND `plugins/soleur/docs/pages/legal/<file>.md`. Both `Last Updated` locations updated (hero `<p>` + body markdown). 16 files total per learning #17 — scope-edit-first.

5. CLO sign-off on final language at review-time.

**Tests (Phase 6):**
- `apps/web-platform/test/legal-doc-consistency.test.ts` — diff `docs/legal/<f>.md` body content vs `plugins/soleur/docs/pages/legal/<f>.md` body content (frontmatter excluded). Drift = test fail. (Kept per learning #16: same-class drift has recurred; CI guard earns its keep.)

### Phase 7: Inspection runbook + retrieval script

**Goal:** documented IP-dispute / DMCA / contributor-revocation response, plus the third schema-version consumer.

1. Create `apps/cla-evidence/scripts/inspect-evidence.sh` (resolves Kieran F3 — third consumer for schema_version assertion):
   - Wraps `rclone copy` to fetch a subset of evidence records.
   - For every record fetched, asserts `jq -e --arg v "1.0" '.schema_version == $v'` — exits 3 on mismatch (paralleling backfill + sidecar exit codes).
   - Usage: `inspect-evidence.sh by-pr 3196` or `inspect-evidence.sh by-contributor Elvalio`. Outputs JSON to stdout for piping to legal counsel's preferred export tool.

2. Create `knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md`. Sections:
   - **Trigger:** DMCA notice, IP dispute, GDPR Art. 17 erasure request, contributor revocation.
   - **Pre-step**: confirm scope with CLO (legal counsel) before any data movement.
   - **Read-token generation**: operator generates a Cloudflare dashboard ad-hoc token (24h TTL, scoped to `soleur-cla-evidence` read-only). Document the dashboard click-path; revoked after use.
   - **Retrieve evidence by contributor**: `bash apps/cla-evidence/scripts/inspect-evidence.sh by-contributor <login>`.
   - **Retrieve by PR**: `bash apps/cla-evidence/scripts/inspect-evidence.sh by-pr <number>`.
   - **Notarized export for legal counsel**: assemble subset; submit `manifest.jsonl` to FreeTSA for fresh timestamp; bundle into a tarball; SHA-256 the tarball; legal counsel receives tarball + SHA + the latest monthly TSR + chain.
   - **GDPR Art. 17 admin-override procedure** (resolves spec-flow gap #10):
     1. Receive erasure request; CLO confirms Art. 17(3)(e) carveout does NOT apply (e.g., contributor's data is unrelated to a live legal claim).
     2. Operator generates one-time admin token with override permissions on `soleur-cla-evidence`.
     3. Admin override deletes the offending object: `aws s3api delete-object --bypass-governance-retention --bucket soleur-cla-evidence --key <key>`.
     4. **Tombstone protocol**: write `tombstones/<sha>.deleted.json` containing `{schema_version: "1.0", deleted_at, admin_actor, gdpr_request_ref, prior_object_metadata, override_reason}` to the separately object-locked `tombstones/` prefix. Tombstone is included in the next month's RFC 3161 manifest (Phase 5 step 2.b lists `tombstones/`) so the chain shows "object H replaced by tombstone T at month M+1."
     5. Update DPA with a private append-only log of the override (date, request ref, no PII).
     6. Revoke admin token.
   - **Audit-log read**: Cloudflare account audit log shows the override; pull and attach to the runbook execution.
   - **Paid-TSA fallback**: if FreeTSA fails 3 consecutive months, switch to DigiCert/GlobalSign — manual provisioning steps documented inline.

3. Cross-link from `knowledge-base/engineering/ops/runbooks/cloudflare-service-token-rotation.md` (the Phase 1 cross-link target).

4. Sharp edge: the runbook itself must NOT contain real signer names or PII — fixtures only, per `cq-test-fixtures-synthesized-only`.

### Phase 8: Bootstrap & smoke

**Goal:** verify the live sidecar end-to-end on a sentinel PR.

1. **Bootstrap merge** of the feature branch via `gh pr merge --admin --squash --auto` (operator action — explicit per-command ack per `hr-menu-option-ack-not-prod-write-auth`). Per spec-flow gap #3, the sidecar workflow file does not exist on `main` until this merge, so it cannot self-validate.

2. **Sentinel test PR**: open an empty fixture PR (`docs: noop sentinel`) from a feature branch. The PR body includes the sign-phrase from the operator's account (already in allowlist). Verify:
   - `cla-check` Check Run goes RED → PENDING (waiting for action) → GREEN (after sign + evidence write).
   - R2 contains a new object at `signatures/<sha>.json` with the operator's record.
   - Receipt comment is posted.
   - The `cla.json` row on `cla-signatures` branch is unchanged for the operator (already signed in #328).

3. **Sentinel allowlist-bypass test**: trigger a `dependabot[bot]` PR (or simulate via `gh pr create` from a fixture branch with `actions/github-script` impersonating the bot). Verify:
   - `allowlist/dependabot-bot/2026-q2.json` is created on first invocation (note: sanitized key, not `dependabot[bot]/`).
   - Second invocation in the same quarter returns 412 (no duplicate write).
   - Confirm `github-actions[bot]` triggers (e.g., a CI auto-commit) produce **no** record (DB-id 41898282 filter active).

4. **Run `bash apps/cla-evidence/scripts/inspect-evidence.sh by-pr <sentinel-pr>`** to exercise the third schema-version consumer end-to-end.

5. Per `wg-after-merging-a-pr-that-adds-or-modifies`, manually trigger the new monthly timestamping workflow once via `workflow_dispatch`, poll `gh run view <id> --json status,conclusion` until complete, verify R2 contains `timestamps/2026-05/manifest.tsr` + `manifest.jsonl`.

6. Per `wg-after-a-pr-merges-to-main-verify-all`, verify CI workflows on the merge commit are all green.

### Phase 9: Expense ledger entry + sharp-edges sweep + post-merge verification

**Goal:** capture operational truth and document new patterns.

1. Confirm `knowledge-base/operations/expenses.md` entry from Phase 1 lands in the merged commit (re-read post-merge).

2. Capture **sharp edges** as a learning at `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md`:
   - First `cloudflare_r2_bucket` Terraform resource declaration in repo (greenfield precedent).
   - Bootstrap chicken-and-egg lesson: `gh pr merge --admin` for self-validating workflows.
   - Schema-version consumer-boundary assertion pattern exercised across 3 consumers (sidecar, backfill, inspect script).
   - `If-None-Match: *` conditional PUT for race-free R2 quarterly canonical records.
   - Allowlist-bypass DB-id 41898282 filter pattern (avoid false-positive evidence records).
   - 4xx (≠412) fast-fail vs 5xx/429 retry-with-backoff classification.

3. Update brainstorm + spec docs with final answers in a follow-up commit:
   - Brainstorm Open Q (a): per-quarter canonical via If-None-Match.
   - Brainstorm Open Q (b): FreeTSA primary, paid fallback documented.
   - Brainstorm Open Q (c): **No IP-allowlist on R2 token** (plan-review converged — recurring CIDR refresh ops cost exceeds marginal benefit on already-public data).
   - Brainstorm Open Q (d): tombstone protocol per Phase 7 runbook.

4. CPO sign-off recorded in PR comments at review time per `requires_cpo_signoff: true`.

5. `user-impact-reviewer` agent at review time (PR review phase, NOT plan phase) per `hr-weigh-every-decision-against-target-user-impact`.

## Files to Create

| Path | Phase | Purpose |
|------|-------|---------|
| `apps/cla-evidence/infra/main.tf` | 1 | R2 backend + Cloudflare provider |
| `apps/cla-evidence/infra/bucket.tf` | 1 | `cloudflare_r2_bucket` resource (greenfield) |
| `apps/cla-evidence/infra/object_lock.tf` | 1 | Governance + 10yr retention |
| `apps/cla-evidence/infra/iam.tf` | 1 | 2 scoped tokens (object-write + state-write); no IP allowlist |
| `apps/cla-evidence/infra/outputs.tf` | 1 | Bucket name, endpoint, sensitive credentials |
| `apps/cla-evidence/infra/variables.tf` | 1 | Provider config |
| `apps/cla-evidence/infra/README.md` | 1 | Ownership, retention, change-control gate |
| `apps/cla-evidence/infra/main.test.sh` | 1 | TF validate, fmt-check, lint |
| `apps/cla-evidence/freetsa/cacert.pem` | 5 | FreeTSA root CA bundle |
| `apps/cla-evidence/freetsa/tsa.crt` | 5 | FreeTSA TSA certificate |
| `apps/cla-evidence/scripts/upload-evidence.sh` | 2 | R2 conditional-PUT helper invoked by sidecar AND backfill (single source of truth) |
| `apps/cla-evidence/scripts/upload-evidence.test.sh` | 2 | RED-first test for conditional-PUT semantics including 4xx fast-fail |
| `apps/cla-evidence/scripts/inspect-evidence.sh` | 7 | Retrieval script + schema-version consumer #3 |
| `apps/cla-evidence/scripts/timestamp.test.sh` | 5 | RED-first test for RFC 3161 verify-replay |
| `apps/web-platform/scripts/cla-evidence/hash.ts` | 2 | Doc + body SHA-256 |
| `apps/web-platform/scripts/cla-evidence/schema.ts` | 2 | Zod evidence record + consumer assertion (exit 3 on mismatch) |
| `apps/web-platform/scripts/cla-evidence/allowlist.ts` | 2 | Allowlist parser; DB-id 41898282 filter |
| `apps/web-platform/scripts/cla-evidence/comment-fetch.ts` | 2 | Octokit fetcher with 5xx-retry / 4xx-fast-fail / 404-degraded |
| `apps/web-platform/scripts/cla-evidence/__tests__/hash.test.ts` | 2 | RED-first |
| `apps/web-platform/scripts/cla-evidence/__tests__/schema.test.ts` | 2 | RED-first; includes schema_version mismatch coverage (TS23-25) |
| `apps/web-platform/scripts/cla-evidence/__tests__/allowlist.test.ts` | 2 | RED-first; DB-id filter coverage |
| `apps/web-platform/scripts/cla-evidence/__tests__/comment-fetch.test.ts` | 2 | RED-first; 4xx-fast-fail + 5xx-retry semantics |
| `apps/web-platform/scripts/cla-evidence/__tests__/allowlist-bypass.test.ts` | 4 | RED-first; sanitized key + DB-id filter |
| `apps/web-platform/scripts/cla-evidence/__tests__/backfill.test.ts` | 3 | RED-first; idempotency + schema_version assertion |
| `apps/web-platform/scripts/cla-backfill-evidence.ts` | 3 | One-shot backfill of 2 existing signers |
| `apps/web-platform/test/legal-doc-consistency.test.ts` | 6 | source ↔ Eleventy mirror diff guard |
| `.github/workflows/cla-evidence.yml` | 2 | Sidecar workflow (includes receipt comment as final soft-fail step) |
| `.github/workflows/cla-evidence-timestamp.yml` | 5 | Monthly RFC 3161 cron |
| `knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md` | 7 | Inspection + erasure runbook |
| `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md` | 9 | Post-merge learning capture |

## Files to Edit

| Path | Phase | Change |
|------|-------|--------|
| `.github/workflows/cla.yml` | 2 | No semantic change; add comment cross-linking to `cla-evidence.yml` |
| `scripts/create-cla-required-ruleset.sh` | 2 | Add `cla-evidence` Check Run (integration_id 15368) to required checks; full-PUT replace |
| `scripts/required-checks.txt` | 2 | Add `cla-evidence` |
| `docs/legal/individual-cla.md` | 6 | Revocation-clause preamble |
| `docs/legal/corporate-cla.md` | 6 | Revocation-clause preamble |
| `docs/legal/privacy-policy.md` | 6 | R2 sub-processor entry |
| `docs/legal/data-protection-disclosure.md` | 6 | New processing activity entry |
| `docs/legal/gdpr-policy.md` | 6 | Three-part balancing test for off-site archive |
| `plugins/soleur/docs/pages/legal/individual-cla.md` | 6 | Mirror; both `Last Updated` locations |
| `plugins/soleur/docs/pages/legal/corporate-cla.md` | 6 | Mirror; both `Last Updated` locations |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | 6 | Mirror |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 6 | Mirror |
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` | 6 | Mirror |
| `knowledge-base/operations/expenses.md` | 1, 9 | New R2 line entry |
| `knowledge-base/engineering/ops/runbooks/cloudflare-service-token-rotation.md` | 1 | Cross-link to new CLA runbook |
| `knowledge-base/project/brainstorms/2026-05-04-cla-legal-rigor-brainstorm.md` | 9 | Open-question final answers |
| `knowledge-base/project/specs/feat-cla-legal-rigor/spec.md` | 2, 9 | Spec-flow gap resolutions; pr_of_record correction for Elvalio |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] All Phase 1 Terraform files exist and `terraform validate` passes; lint asserts Governance mode + 3650 days + `prevent_destroy = true`. No IP-allowlist on tokens.
- [ ] All Phase 2 RED-first tests are written before any helper implementation lands (verified via git log: test commit precedes implementation commit per `cq-write-failing-tests-before`).
- [ ] All Phase 2 helpers have ≥80% line coverage with tests passing.
- [ ] `allowlist.ts` filter excludes DB-id 41898282 (`github-actions[bot]`) in addition to allowlist string match (Kieran F2).
- [ ] `comment-fetch.ts` distinguishes 5xx/429 (retry) from 4xx≠404 (fast-fail) from 404 (degraded record).
- [ ] `upload-evidence.sh` is the single source of truth for R2 conditional-PUT — sidecar workflow `run: bash apps/cla-evidence/scripts/upload-evidence.sh` (Kieran F7).
- [ ] Sidecar workflow file at `.github/workflows/cla-evidence.yml` syntactically valid (`gh workflow view` parses), uses sanitization for PR-derived data per learning #5, uses `::add-mask::` for Doppler secrets per learning #6, and uses `actions/checkout` of base ref only.
- [ ] Receipt comment is the final soft-fail step in the sidecar workflow (`continue-on-error: true`), NOT a separate phase or workflow.
- [ ] No `apps/web-platform/scripts/sentry-envelope.mjs` file is created (Reconciliation #1+#2 — workflow uses `::error::` only).
- [ ] No `apps/cla-evidence/infra/refresh-gh-actions-cidrs.sh` file is created (no IP-allowlist).
- [ ] `scripts/create-cla-required-ruleset.sh` includes `cla-evidence` Check Run with integration_id 15368.
- [ ] Backfill script (Phase 3) deterministic: dry-run output (no R2 calls; mock harness) matches a recorded fixture (Kieran F10 — pre-merge).
- [ ] Allowlist-bypass deterministic key + If-None-Match contract verified by Phase 4 test. Key uses sanitized form (`dependabot-bot`, not `dependabot[bot]`).
- [ ] RFC 3161 verify-replay test passes against a recorded `.tsr` fixture (Phase 5).
- [ ] All five legal docs (source) updated with revocation clause + sub-processor + processing activity + balancing test; CLO-equivalent (`legal-compliance-auditor`) reviewed at review time.
- [ ] All five Eleventy mirror docs updated with both `Last Updated` locations; `legal-doc-consistency.test.ts` passes (zero body drift).
- [ ] Inspection runbook at `knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md` covers all 7 sections from Phase 7.
- [ ] `apps/cla-evidence/scripts/inspect-evidence.sh` exists and asserts `schema_version === "1.0"` on every fetched record (third schema-version consumer per Kieran F3).
- [ ] Test suite includes TS23 (backfill aborts on schema_version mismatch), TS24 (sidecar tombstone-append aborts on schema mismatch), TS25 (inspect script exits 3 on schema mismatch) per Kieran F4.
- [ ] Expense ledger updated at `knowledge-base/operations/expenses.md`.
- [ ] `## User-Brand Impact` section present and CPO sign-off recorded in PR comments per `requires_cpo_signoff: true`.
- [ ] `user-impact-reviewer` agent invoked at review time (review phase responsibility).
- [ ] PR body uses `Closes #3209` (this is a feature with all artifacts in-PR; not ops-remediation).

### Post-merge (operator)

- [ ] `gh pr merge --admin --squash` for the bootstrap PR (sidecar cannot self-validate per spec-flow gap #3) — explicit per-command ack required per `hr-menu-option-ack-not-prod-write-auth`.
- [ ] `cd apps/cla-evidence/infra && terraform init && terraform apply` — explicit per-command ack required for the apply step.
- [ ] Doppler config `prd_cla` created; service token issued; synced to GitHub repo secret as `DOPPLER_TOKEN_CLA`.
- [ ] Branch-protection ruleset re-applied via `bash scripts/create-cla-required-ruleset.sh` — explicit per-command ack.
- [ ] Sentinel test PR opened, signed, evidence record verified in R2 at `signatures/<sha>.json`, receipt comment posted.
- [ ] Sentinel allowlist-bypass test on `dependabot[bot]` writes record at `allowlist/dependabot-bot/<quarter>.json` (sanitized key); on `github-actions[bot]` writes NO record (DB-id 41898282 filter active).
- [ ] `gh workflow run cla-evidence-timestamp.yml`; poll until complete; verify `timestamps/2026-05/manifest.tsr` lands in R2.
- [ ] Backfill script run: `bun run apps/web-platform/scripts/cla-backfill-evidence.ts`; verify deruelle + Elvalio evidence records appear in R2; verify Elvalio's record uses `pr_of_record.number = 3196`. Second invocation produces zero 200 responses (all 412) — proves idempotency post-merge per Kieran F10.
- [ ] `bash apps/cla-evidence/scripts/inspect-evidence.sh by-pr <sentinel-pr>` returns valid JSON with `schema_version === "1.0"` asserted (third consumer exercised end-to-end).
- [ ] All release/deploy workflows on the merge commit succeed per `wg-after-a-pr-merges-to-main-verify-all`.
- [ ] Manual run of `cla-evidence-timestamp.yml` and `cla-evidence.yml` (via fixture PR) — both green per `wg-after-merging-a-pr-that-adds-or-modifies`.
- [ ] Brainstorm + spec docs updated with open-question final answers; committed in a follow-up PR.

## Test Scenarios

| ID | Scenario | Type | Phase |
|---|---|---|---|
| TS1 | Doc-hash determinism | Unit | 2 |
| TS2 | Schema validation: missing required fields rejected | Unit | 2 |
| TS3 | Allowlist parser stays in sync with `cla.yml`; **excludes DB-id 41898282** | Unit | 2 |
| TS4 | Comment-fetch retries 5xx/429 with exponential backoff | Unit | 2 |
| TS5 | Comment-fetch returns degraded record on 404 (no retry) | Unit | 2 |
| TS5b | Comment-fetch fast-fails on 4xx≠404 (no retry) | Unit | 2 |
| TS6 | R2 conditional-PUT idempotency (412 on duplicate); fast-fail on 4xx≠412 | Integration | 2 |
| TS7 | Sign-then-edit-comment sequence: append to tombstone, do not overwrite | Integration | 2 |
| TS8 | Sign-then-delete-comment sequence: tombstone written | Integration | 2 |
| TS9 | Backfill dry-run output matches fixture (no R2 calls; pre-merge) | Integration | 3 |
| TS10 | Backfill re-run produces zero new writes (post-merge) | Smoke | 3 |
| TS11 | Backfill schema-version asserted on read | Unit | 3 |
| TS14 | Allowlist-bypass first-write succeeds; sanitized key | Integration | 4 |
| TS15 | Allowlist-bypass duplicate-quarter returns 412 | Integration | 4 |
| TS16 | Allowlist-bypass new-quarter writes new record | Integration | 4 |
| TS16b | `github-actions[bot]` DB-id 41898282 produces NO record | Integration | 4 |
| TS17 | RFC 3161 verify-replay against recorded fixture | Integration | 5 |
| TS18 | TSR upload PR-with-auto-merge (not direct push) | Integration | 5 |
| TS18b | TSA-outage 7-day retry triggers `gh issue create` (Kieran F9) | Integration | 5 |
| TS19 | Legal-doc consistency: source ↔ Eleventy mirror | Integration | 6 |
| TS20 | Sentinel PR end-to-end: sign → evidence → receipt | Smoke | 8 |
| TS21 | Allowlist-bypass on dependabot fixture | Smoke | 8 |
| TS22 | Monthly cron `workflow_dispatch` end-to-end | Smoke | 8 |
| **TS23** | **Backfill aborts (exit 3) when reading `schema_version: 2.0` payload** | Unit | 3 |
| **TS24** | **Sidecar tombstone-append aborts on schema mismatch** | Integration | 2 |
| **TS25** | **Inspect script exits 3 on schema mismatch** | Integration | 7 |

(TS12, TS13 receipt-comment scenarios removed — receipt is now a soft-fail step in Phase 2 verified at sentinel TS20.)

## Risks

| # | Risk | Likelihood | Mitigation |
|---|------|-----------|------------|
| 1 | Bootstrap PR sidecar can't self-validate; admin-merge introduces blast-radius if workflow is broken on main. | Medium | Sentinel PR (TS20) immediately after merge; can revert via PR if sentinel fails. Phase 8 verification mandatory. |
| 2 | FreeTSA SLA unknown; could be down on cron day. | Medium | 7-day retry-on-workflow-dispatch; auto-file tracking issue on persistent failure (Kieran F9); paid-TSA fallback documented in Phase 7 runbook. |
| 3 | `cloudflare_r2_bucket` resource may not support `location_hint` or object-lock in current Cloudflare TF provider version. | Low | Pin provider version; verify capability in Phase 1 dry-run; if unsupported, document the gap and use Cloudflare API directly via `null_resource` + `local-exec` (one-time). |
| 4 | Comment-body 404 (contributor edits-then-deletes faster than `created` event handler runs) leaves degraded record; CLO must accept this is sufficient evidence. | Low | CLO sign-off at plan time on degraded-record sufficiency. Schema includes `comment_body_fetch_failed: true` so the evidence quality tier is honest. |
| 5 | Force-push on PR branch after sign changes head SHA but not base SHA; sidecar should not re-run unless base changes. | Low | `pull_request_target.synchronize` only runs on push to PR; document non-impact in runbook. |
| 6 | `[skip ci]` accidentally added to monthly cron PR; required-check deadlock per learning #12. | Low | Lint check in PR template; runbook explicitly forbids `[skip ci]`. |
| 7 | Doppler service token for `prd_cla` rotated incorrectly (wrong config scope per learning #9). | Low | Token-rotation runbook explicitly cites learning #9; rotation as separate step from Cloudflare token rotation. |
| 8 | RFC 3161 cron PR auto-merge gets blocked by CLA Required ruleset (learning #3 — `github-actions[bot]` rejected). | Low | Cron PR uses `[bot] auto-merge` allowlist label; CLA workflow allowlist already includes `github-actions[bot]`. Verified during sentinel test. |
| 9 | Stale R2 token returns 403 — without 4xx fast-fail, workflow retries for hours. | Low | 4xx≠412 → fast-fail with `::error::` annotation (Kieran F5). Token-rotation cadence in runbook. |
| 10 | Test path collision: `apps/web-platform/test/` is Vitest app-level; helpers belong elsewhere. | Low | Helpers + tests co-located at `apps/web-platform/scripts/cla-evidence/__tests__/` (Kieran F6); runner is Bun. |

## Domain Review

**Domains relevant:** Legal, Engineering, Product, Operations.

Carry-forward from brainstorm `## Domain Assessments` per Phase 2.5; full assessments in `knowledge-base/project/brainstorms/2026-05-04-cla-legal-rigor-brainstorm.md`. One-line summaries below per plan-review trim.

- **Legal:** doc-hash + verbatim comment text are must-fix (gaps 1, 4); off-site archive must-fix-lite (gap 2); PII deferred to #3210; CLO sign-off at review-time on revocation language and degraded-record sufficiency.
- **Engineering:** sidecar over fork; per-event R2 upload; hash from in-repo at PR base SHA; hard-fail merge gate; **8 spec-vs-codebase reconciliations resolved in the table above; 5 P1 spec-flow gaps resolved in plan body; 7 plan-review fixes applied.**
- **Product:** single folded `cla-check` (resolved via integration_id-based ruleset); receipt-comment soft-fail folded into sidecar workflow; backfill (no re-sign). CPO sign-off required per `requires_cpo_signoff: true`.
- **Operations:** Governance object-lock; EU region; distinct Doppler scopes; `lifecycle { prevent_destroy = true }`; expense ledger entry. **No IP-allowlist on R2 token (plan-review converged); no Sentry-from-workflow helper introduced (plan-review converged). Greenfield `cloudflare_r2_bucket` Terraform resource captured as learning post-merge.**

### Product/UX Gate

**Tier:** none. No new pages, no new components, no UI surfaces. The bot receipt comment is rendered by GitHub's native PR-comment UI; we author markdown only. Eleventy legal-doc edits modify existing docs.

**Brainstorm-recommended specialists:** `legal-document-generator` (Phase 6), `legal-compliance-auditor` (Phase 6). Both invoked at work-time. No copywriter, conversion-optimizer, or ux-design-lead in scope.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan has it filled with carry-forward from brainstorm Phase 0.1.
- **`reportSilentFallback` is server-only TS** — do NOT attempt to import from a workflow shell step. Workflow uses `::error::` annotations + `$GITHUB_STEP_SUMMARY` + Check Run RED instead (no Sentry-from-workflow helper).
- **`pull_request_target` chicken-and-egg** — first merge must be `gh pr merge --admin`. Sentinel PR validates the live behavior post-merge.
- **Doppler service tokens are config-pinned** (learning #9) — `DOPPLER_TOKEN_CLA` works only against `prd_cla` config. Cannot reuse `DOPPLER_TOKEN_PRD` for the sidecar.
- **Eleventy mirror has TWO `Last Updated` locations** (learning #15) — hero `<p>` AND body markdown. Both update atomically.
- **Ruleset PUT is full-replace** (learning #11) — `scripts/create-cla-required-ruleset.sh` rewrites the ENTIRE bypass-actors + required-checks payload. Sweep ghost actors before re-applying.
- **`[skip ci]` deadlocks required Check Runs** (learning #12) — cron PR commit messages MUST NOT contain `[skip ci]`.
- **Schema-version consumer assertion** (learning #18 + AGENTS.md sharp-edge): `schema_version === "1.0"` asserted at parse-time in (a) sidecar workflow on R2 read for tombstone-append, (b) backfill script on `cla.json` read, (c) `inspect-evidence.sh` on every retrieved record. Failure to assert is cosmetic-only contract.
- **DB-id 41898282 filter** (learning #2) — `github-actions[bot]` is filtered out by the upstream CLA action BEFORE the allowlist check fires. Sidecar must apply the same filter or it produces false-positive bypass records.
- **Bot identity surface** (learning #2) — read `commit.author.user.login` via GraphQL (e.g., `claude[bot]`), NOT REST `app/<slug>`.
- **CLA Required ruleset rejects direct push from `github-actions[bot]`** (learning #3) — RFC 3161 cron MUST use PR-with-auto-merge.
- **R2 backend has no lock** (learning #8) — single-writer `terraform apply` only; document this in the new TF root README.
- **R2 conditional-PUT 4xx classification** — 412 → exit 0 (idempotent); 5xx/429 → retry up to 3 with backoff; 4xx≠412 → fast-fail with `::error::` (resolves Kieran F5; e.g., 403 from token issue is config bug, not transient).
- **Allowlist-bypass key sanitization** — `dependabot[bot]` → `dependabot-bot` in R2 key (Kieran F8); canonical login preserved in payload `principal` field.
- **`upload-evidence.sh` single source of truth** — sidecar workflow + backfill script both invoke the same script; tests exercise the same code path as production (Kieran F7).
- **Tombstone protocol is the only Art. 17 escape hatch** under Governance mode. Object deletion without writing a tombstone breaks the evidence chain on the next monthly TSR. Tombstones live at `tombstones/` prefix with their own object-lock and are included in monthly manifest.
- **Sanitize PR-derived data** before any `>> $GITHUB_OUTPUT` (learning #5).
- **`::add-mask::` Doppler-fetched R2 tokens** (learning #6).
- **Avoid `GITHUB_*` prefix on secret names** (learning #10).
- **All `curl` / `dig` / `nslookup` invocations bound by `--max-time` / `+time=`** per the AGENTS.md plan-skill sharp-edge.

## Alternative Approaches Considered

| Approach | Why rejected | Tracked? |
|---|---|---|
| Fork `contributor-assistant/github-action` | Long-term maintenance trap; security review of every upstream rebase. CTO recommended sidecar. | No — rejected outright. |
| Cron mirror (daily rsync of `cla-signatures` to R2) | Creates tampering window between sign-time and mirror. Per-event has no window. CTO recommended per-event. | No — rejected outright. |
| R2 Compliance object-lock mode | Root-immutable; no GDPR Art. 17 escape hatch. COO flagged as brand-suicidal under EU enforcement. | No — rejected outright. |
| 30-year retention (FR Code civil art. 2227) | Operationally fine, but GDPR proportionality is harder to defend at 30yr. 10yr covers BSL change date + DE/UK statutory. Extendable later via admin override. | No — captured as "extendable to 30yr later." |
| Compliance-mode immutable "evidence" bucket + Governance "PII" bucket (hybrid) | Brainstorm option C; doubles operational surface. Under current scope (no PII), single-bucket Governance is sufficient. | Captured implicitly; revisit if #3210 PII work changes the calculus. |
| Real-name + email PII expansion (gap 3) | Friction-high; deferred to #3210 with joint CPO+CLO sync. | Yes — issue #3210 created. |
| Wired-up Corporate CLA mechanism | Multi-day product investment with strategy questions. Deferred to #3210. | Yes — issue #3210 created. |
| Contributor-side `soleur.ai/account/cla` lookup page | High product investment; receipt-comment + GitHub history is the v1 trust signal. Deferred to #3211. | Yes — issue #3211 created. |
| Sentry-from-workflow envelope helper | Inventing a new pattern to satisfy `cq-silent-fallback-must-mirror-to-sentry` which is scoped to server runtime. Workflow failures are already loud (Check Run RED + email). | No — rejected by plan-review (DHH F2 + Code-Simplicity F1). Can revisit if event volume justifies it. |
| IP-allowlist on R2 token + quarterly CIDR refresh | Marginal security gain on already-public-data bucket; recurring ops cost (CIDR refresh) creates a quarterly forgotten-chore risk. | No — rejected by plan-review (DHH F1 + Code-Simplicity F2). |
| Receipt comment as standalone Phase 4 with dedicated tests | One `gh api` heredoc as final soft-fail step in sidecar workflow is sufficient. Verification at sentinel TS20. | No — rejected by plan-review (Code-Simplicity F4). |
| `actions/github-script` for octokit calls inside workflow | Adds JavaScript-in-YAML surface. Existing pattern is `gh api` shell; consistency wins. | No — captured as preference. |
| Schedule monthly RFC 3161 via Soleur cloud cron | Added a cross-system dependency for a job that's purely repo-scoped. GitHub Actions cron suffices. | No — rejected outright. |
| Dropping RFC 3161 entirely (DHH F3) | DHH argued 2 signers don't earn monthly cron; one-shot TSR at relicensing time is sufficient. Counter: user opted into RFC 3161 in brainstorm scope-locking; cost is cheap (~30s/month + 1 PR/month); evidentiary chain has compounding value. | No — kept per user scope decision; revisit if FreeTSA fails 3 consecutive months. |
| Shell-based backfill (Code-Simplicity F3) | Code Simplicity argued TS module + 3 tests is overengineered for 2 signers. Counter: TS allows schema_version assertion + Zod parse + reuse with sidecar helpers. Marginal cost. | No — kept TS path; lean tests. |

## Out of Scope / Non-Goals

- ICLA PII expansion (real name, email) — see #3210.
- Corporate CLA submission/recording mechanism — see #3210.
- Contributor-side `soleur.ai/account/cla` lookup page — see #3211.
- Forking `contributor-assistant/github-action`.
- Compliance-mode object-lock.
- Re-signing existing 2 contributors.
- Automated paid-TSA fallback (FreeTSA primary; paid is documented as a manual fallback path only).
- Org-wide CLA coverage (Soleur-only).
- Migration of any existing CLA records into a different schema/store.
- Sentry-from-workflow envelope helper (plan-review removed; revisit if event volume warrants).
- IP-allowlist on R2 workflow token (plan-review removed; revisit if threat model changes).

## Sign-off Reminders

- **CPO sign-off required at plan time** before `/work` begins (`requires_cpo_signoff: true`). CPO context already covered in brainstorm Phase 0.1; confirm CPO has reviewed the brainstorm document or invoke CPO domain leader for plan-time ack.
- **`user-impact-reviewer` invoked at review time** (PR review phase, not plan phase) per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.
- **CLO sign-off at review time** on revocation-clause language (Phase 6) and degraded-record sufficiency (Phase 2 Step 3e).
- **Per-command ack required** for all destructive operator actions per `hr-menu-option-ack-not-prod-write-auth`: `gh pr merge --admin`, `terraform apply`, `bash scripts/create-cla-required-ruleset.sh`.
