# Tasks: CLA Legal-Rigor Evidence Layer

**Plan:** `knowledge-base/project/plans/2026-05-04-feat-cla-legal-rigor-evidence-layer-plan.md`
**Spec:** `knowledge-base/project/specs/feat-cla-legal-rigor/spec.md`
**Issue:** #3209 · **Branch:** `feat-cla-legal-rigor` · **Worktree:** `.worktrees/feat-cla-legal-rigor/` · **Draft PR:** #3201
**Brand-survival threshold:** `single-user incident` (PII) + `aggregate pattern` (IP, friction). CPO sign-off required.

## Phase 1: R2 evidence-bucket Terraform foundation

- [ ] 1.1 Create directory `apps/cla-evidence/infra/`
- [ ] 1.2 Write `main.tf` (R2 backend `key = "cla-evidence/terraform.tfstate"`, `use_lockfile = false`, Cloudflare provider `~> 4.0`)
- [ ] 1.3 Write `bucket.tf` (`cloudflare_r2_bucket name = "soleur-cla-evidence"`, `location_hint = "weur"`, `lifecycle.prevent_destroy = true`)
- [ ] 1.4 Write `object_lock.tf` (Governance mode, 3650-day default retention)
- [ ] 1.5 Write `iam.tf` (object-write token + state-write token, distinct; no IP allowlist)
- [ ] 1.6 Write `outputs.tf` (sensitive credentials, no plaintext)
- [ ] 1.7 Write `variables.tf` (cf_api_token, cf_account_id)
- [ ] 1.8 Write `README.md` (ownership, retention, single-writer apply assumption per learning #8)
- [ ] 1.9 Write `main.test.sh` (terraform validate, fmt-check, lint for Governance + 3650 + prevent_destroy)
- [ ] 1.10 **Operator action (per-command ack required):** `cd apps/cla-evidence/infra && terraform init && terraform apply`
- [ ] 1.11 Verify post-apply: `aws s3api get-object-lock-configuration` returns Governance + 3650
- [ ] 1.12 **Operator action:** `doppler configs create prd_cla --project soleur`
- [ ] 1.13 Set Doppler `prd_cla` config secrets (R2 access-key + secret) from Terraform outputs
- [ ] 1.14 Generate Doppler service token scoped to `prd_cla` (per learning #9 — config-pinned)
- [ ] 1.15 **Operator action:** `gh secret set DOPPLER_TOKEN_CLA --body "$token"`
- [ ] 1.16 Add expense ledger entry to `knowledge-base/operations/expenses.md`
- [ ] 1.17 Add cross-link section to `knowledge-base/engineering/ops/runbooks/cloudflare-service-token-rotation.md`
- [ ] 1.18 Extend `infra-validation.yml` to run `terraform plan` against `apps/cla-evidence/infra/` (zero-drift gate)

## Phase 2: Sidecar workflow + receipt comment (TDD, RED first)

### Phase 2a: RED-first tests (write before implementation per `cq-write-failing-tests-before`)

- [ ] 2.1 Create directory `apps/web-platform/scripts/cla-evidence/__tests__/`
- [ ] 2.2 Write `__tests__/hash.test.ts` (computeDocHash determinism)
- [ ] 2.3 Write `__tests__/schema.test.ts` (rejects missing fields; **TS23 schema_version mismatch → exit 3**)
- [ ] 2.4 Write `__tests__/allowlist.test.ts` (allowlist match + **DB-id 41898282 filter**)
- [ ] 2.5 Write `__tests__/comment-fetch.test.ts` (5xx/429 retry; 404 degraded; **4xx≠404 fast-fail**)
- [ ] 2.6 Write `apps/cla-evidence/scripts/upload-evidence.test.sh` (412 idempotent; **4xx≠412 fast-fail**)
- [ ] 2.7 Run all tests — confirm RED (no implementation yet)
- [ ] 2.8 Commit RED phase with message `test(cla-evidence): add RED-first tests for sidecar helpers`

### Phase 2b: Implementation (GREEN)

- [ ] 2.9 Implement `apps/web-platform/scripts/cla-evidence/hash.ts`
- [ ] 2.10 Implement `apps/web-platform/scripts/cla-evidence/schema.ts` (Zod + exit 3 on schema_version mismatch)
- [ ] 2.11 Implement `apps/web-platform/scripts/cla-evidence/allowlist.ts` (parse `cla.yml`; exclude DB-id 41898282)
- [ ] 2.12 Implement `apps/web-platform/scripts/cla-evidence/comment-fetch.ts` (retry classes: 5xx/429 retry; 404 degraded; 4xx≠404 fast-fail)
- [ ] 2.13 Implement `apps/cla-evidence/scripts/upload-evidence.sh` (R2 conditional-PUT; 412 → exit 0; 5xx/429 retry; **4xx≠412 fast-fail with `::error::`**)
- [ ] 2.14 Run tests — confirm GREEN
- [ ] 2.15 Commit GREEN phase

### Phase 2c: Sidecar workflow

- [ ] 2.16 Write `.github/workflows/cla-evidence.yml`:
  - [ ] 2.16.1 Triggers: `pull_request_target` + `issue_comment.{created,edited,deleted}`
  - [ ] 2.16.2 Permissions: `contents: read`, `pull-requests: write`, `statuses: write` (NOT `contents: write`)
  - [ ] 2.16.3 Concurrency group: `cla-evidence-${{ pr-or-issue-number }}`
  - [ ] 2.16.4 `actions/checkout` of base ref ONLY (no PR head)
  - [ ] 2.16.5 Doppler step (SHA-pinned) loads R2 keys with `DOPPLER_TOKEN_CLA`
  - [ ] 2.16.6 `::add-mask::` Doppler-fetched tokens (learning #6)
  - [ ] 2.16.7 Sanitize PR-derived data before `$GITHUB_OUTPUT` (learning #5)
  - [ ] 2.16.8 Compute doc hash from `git show $base.sha:docs/legal/individual-cla.md | sha256sum`
  - [ ] 2.16.9 Fetch comment body via `comment-fetch.ts` with retry semantics
  - [ ] 2.16.10 Build evidence record; assert `schema_version === "1.0"`
  - [ ] 2.16.11 Invoke `bash apps/cla-evidence/scripts/upload-evidence.sh "$payload"`
  - [ ] 2.16.12 Write `signatures/by-pr/<pr>/<comment_id>.json` pointer
  - [ ] 2.16.13 **Receipt comment** as final step (`gh api` with `continue-on-error: true`)
  - [ ] 2.16.14 Catch paths emit `::error::` + `$GITHUB_STEP_SUMMARY` (no Sentry helper)
  - [ ] 2.16.15 Set `cla-check` Check Run status (RED on failure)
  - [ ] 2.16.16 Bounded `--max-time 30` on the `license/cla` status poll (dual-check folding)

- [ ] 2.17 Add comment cross-link in `.github/workflows/cla.yml` pointing to `cla-evidence.yml`
- [ ] 2.18 Extend `scripts/create-cla-required-ruleset.sh` to include `cla-evidence` Check Run (integration_id 15368) — full PUT replacement per learning #11
- [ ] 2.19 Update `scripts/required-checks.txt` with `cla-evidence`
- [ ] 2.20 **Operator action (per-command ack required):** `bash scripts/create-cla-required-ruleset.sh`
- [ ] 2.21 Validate workflow YAML: `gh workflow view cla-evidence.yml`

## Phase 3: Backfill of existing 2 signers

- [ ] 3.1 Write `apps/web-platform/scripts/cla-evidence/__tests__/backfill.test.ts` (RED-first; idempotency + schema_version assertion + TS23)
- [ ] 3.2 Implement `apps/web-platform/scripts/cla-backfill-evidence.ts`:
  - [ ] 3.2.1 Read `signatures/cla.json` from `cla-signatures` branch
  - [ ] 3.2.2 Assert `schema_version === "1.0"` on every input record (consumer #1)
  - [ ] 3.2.3 For each row: fetch comment body, find git-SHA via `git log --until=<created_at>`, build record with `capture_method: "backfilled"`
  - [ ] 3.2.4 Handle pre-file-existence edge: tag `capture_method: "backfilled-pre-existed"` if doc didn't exist at sign-time
  - [ ] 3.2.5 Correct Elvalio's `pr_of_record.number` to 3196 (action recorded #3186 incorrectly)
  - [ ] 3.2.6 Invoke `bash apps/cla-evidence/scripts/upload-evidence.sh` (same path as sidecar — single source of truth)
- [ ] 3.3 Add `--dry-run` flag (prints payloads without R2 calls — pre-merge fixture verification)
- [ ] 3.4 Run tests — confirm GREEN
- [ ] 3.5 Commit Phase 3

## Phase 4: Allowlist-bypass logging (per-quarter canonical)

- [ ] 4.1 Write `__tests__/allowlist-bypass.test.ts` (RED-first; sanitized key, DB-id filter, TS14-16, TS16b)
- [ ] 4.2 Implement allowlist-bypass detection in sidecar (Phase 2c) flow:
  - [ ] 4.2.1 Sanitize key: `principal.replace(/\[bot\]/g, "-bot")` → e.g., `dependabot-bot`
  - [ ] 4.2.2 Deterministic key: `allowlist/<principal_safe>/<yyyy-qq>.json`
  - [ ] 4.2.3 Canonical record schema: `{schema_version, principal, principal_safe, db_id, quarter, first_seen_at, first_pr, allowlist_source}`
  - [ ] 4.2.4 Conditional PUT with `If-None-Match: *`; 412 → exit 0
  - [ ] 4.2.5 **Skip recording entirely if DB-id === 41898282** (`github-actions[bot]`)
- [ ] 4.3 Run tests — confirm GREEN
- [ ] 4.4 Commit Phase 4

## Phase 5: RFC 3161 monthly timestamping

- [ ] 5.1 Download FreeTSA cacert + TSA cert; commit to `apps/cla-evidence/freetsa/` (`cacert.pem`, `tsa.crt`)
- [ ] 5.2 Write `apps/cla-evidence/scripts/timestamp.test.sh` (RED-first; verify-replay + TS18b auto-issue trigger)
- [ ] 5.3 Write `.github/workflows/cla-evidence-timestamp.yml`:
  - [ ] 5.3.1 Schedule `cron: '0 6 1 * *'` (NOT `[skip ci]`)
  - [ ] 5.3.2 Permissions: `contents: read`, `pull-requests: write`
  - [ ] 5.3.3 Doppler step loads `R2_CLA_EVIDENCE_READ_*`
  - [ ] 5.3.4 List `signatures/`, `allowlist/`, `tombstones/` prefixes
  - [ ] 5.3.5 Build manifest JSONL; include YYYY-MM in pre-image (always-timestamp)
  - [ ] 5.3.6 `openssl ts -query -data <manifest> -sha256 -cert -no_nonce`
  - [ ] 5.3.7 `curl --max-time 30` to `https://freetsa.org/tsr`
  - [ ] 5.3.8 `openssl ts -verify` against vendored certs
  - [ ] 5.3.9 Upload `timestamps/<yyyy-mm>/manifest.tsr` + `manifest.jsonl` to R2
  - [ ] 5.3.10 7-day retry on TSA outage; auto-file `gh issue create --label cla-evidence,timestamp-failure` after 7 consecutive failures (Kieran F9)
  - [ ] 5.3.11 PR-with-auto-merge for `.tsr` commits (not direct push per learning #3)
- [ ] 5.4 Run tests — confirm GREEN
- [ ] 5.5 Commit Phase 5

## Phase 6: Legal-document updates

- [ ] 6.1 Invoke `legal-document-generator` agent for revocation-clause preamble draft
- [ ] 6.2 Invoke `legal-compliance-auditor` to review draft against existing CLA + Privacy Policy + DPA + GDPR Policy
- [ ] 6.3 Update `docs/legal/individual-cla.md` with revocation-clause preamble
- [ ] 6.4 Update `docs/legal/corporate-cla.md` with revocation-clause preamble
- [ ] 6.5 Update `docs/legal/privacy-policy.md` with R2 sub-processor entry
- [ ] 6.6 Update `docs/legal/data-protection-disclosure.md` with new processing activity
- [ ] 6.7 Update `docs/legal/gdpr-policy.md` with three-part balancing test (Art. 17(3)(e) basis)
- [ ] 6.8 Mirror updates to `plugins/soleur/docs/pages/legal/individual-cla.md` (both `Last Updated` locations per learning #15)
- [ ] 6.9 Mirror updates to `plugins/soleur/docs/pages/legal/corporate-cla.md`
- [ ] 6.10 Mirror updates to `plugins/soleur/docs/pages/legal/privacy-policy.md`
- [ ] 6.11 Mirror updates to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] 6.12 Mirror updates to `plugins/soleur/docs/pages/legal/gdpr-policy.md`
- [ ] 6.13 Write `apps/web-platform/test/legal-doc-consistency.test.ts` (source ↔ mirror diff guard per learning #16)
- [ ] 6.14 Run consistency test — confirm GREEN
- [ ] 6.15 CLO-equivalent review at PR review time (separate from work-time)
- [ ] 6.16 Commit Phase 6

## Phase 7: Inspection runbook + retrieval script

- [ ] 7.1 Implement `apps/cla-evidence/scripts/inspect-evidence.sh`:
  - [ ] 7.1.1 Subcommand `by-pr <number>` → `rclone copy r2:soleur-cla-evidence/signatures/by-pr/<number>/`
  - [ ] 7.1.2 Subcommand `by-contributor <login>` → grep + fetch
  - [ ] 7.1.3 **Schema-version assertion (consumer #3):** `jq -e --arg v "1.0" '.schema_version == $v'` on every fetched record; exit 3 on mismatch
  - [ ] 7.1.4 Output JSON to stdout for legal-counsel piping
- [ ] 7.2 Write `__tests__/inspect.test.sh` (TS25 schema mismatch → exit 3)
- [ ] 7.3 Create `knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md`:
  - [ ] 7.3.1 Trigger section (DMCA, IP dispute, Art. 17, revocation)
  - [ ] 7.3.2 Pre-step: CLO scope confirmation
  - [ ] 7.3.3 Read-token generation (Cloudflare dashboard, 24h TTL)
  - [ ] 7.3.4 Retrieve-by-contributor procedure
  - [ ] 7.3.5 Retrieve-by-PR procedure
  - [ ] 7.3.6 Notarized export procedure
  - [ ] 7.3.7 **GDPR Art. 17 admin-override + tombstone protocol** (resolves spec-flow gap #10)
  - [ ] 7.3.8 Audit-log read procedure
  - [ ] 7.3.9 Paid-TSA fallback procedure (DigiCert/GlobalSign)
- [ ] 7.4 Cross-link from `cloudflare-service-token-rotation.md`
- [ ] 7.5 Verify runbook contains no real PII (synthesized fixtures only per `cq-test-fixtures-synthesized-only`)
- [ ] 7.6 Commit Phase 7

## Phase 8: Bootstrap & smoke (post-merge)

- [ ] 8.1 Push branch; mark draft PR #3201 ready for review
- [ ] 8.2 Address any review-phase findings inline
- [ ] 8.3 CPO sign-off recorded in PR comments
- [ ] 8.4 `user-impact-reviewer` agent runs at review time
- [ ] 8.5 **Operator action (per-command ack required):** `gh pr merge 3201 --admin --squash`
- [ ] 8.6 **Sentinel test PR**: open `chore: noop sentinel`; sign as operator; verify:
  - [ ] 8.6.1 `cla-check` Check Run goes RED → PENDING → GREEN
  - [ ] 8.6.2 R2 contains `signatures/<sha>.json` with operator's record
  - [ ] 8.6.3 Receipt comment posted
  - [ ] 8.6.4 `cla.json` row unchanged for operator (already signed in #328)
- [ ] 8.7 **Sentinel allowlist-bypass test:** trigger dependabot PR; verify:
  - [ ] 8.7.1 `allowlist/dependabot-bot/2026-q2.json` created (sanitized key)
  - [ ] 8.7.2 Second invocation in same quarter returns 412
  - [ ] 8.7.3 `github-actions[bot]` (DB-id 41898282) trigger produces NO record
- [ ] 8.8 **Operator action:** `bun run apps/web-platform/scripts/cla-backfill-evidence.ts`
  - [ ] 8.8.1 Verify deruelle + Elvalio records appear in R2
  - [ ] 8.8.2 Verify Elvalio's `pr_of_record.number = 3196`
  - [ ] 8.8.3 Re-run produces zero 200s (all 412 — proves idempotency post-merge)
- [ ] 8.9 **Operator action:** `bash apps/cla-evidence/scripts/inspect-evidence.sh by-pr <sentinel-pr>`
  - [ ] 8.9.1 Returns valid JSON with `schema_version === "1.0"` asserted
- [ ] 8.10 **Operator action:** `gh workflow run cla-evidence-timestamp.yml`
  - [ ] 8.10.1 Poll `gh run view <id>` until complete
  - [ ] 8.10.2 Verify R2 contains `timestamps/2026-05/manifest.tsr` + `manifest.jsonl`
- [ ] 8.11 Verify CI workflows on the merge commit are all green per `wg-after-a-pr-merges-to-main-verify-all`
- [ ] 8.12 Verify `cla-evidence.yml` and `cla-evidence-timestamp.yml` runs are green per `wg-after-merging-a-pr-that-adds-or-modifies`

## Phase 9: Expense ledger entry + sharp-edges sweep + post-merge verification

- [ ] 9.1 Re-read `knowledge-base/operations/expenses.md` post-merge — confirm Phase 1 entry landed
- [ ] 9.2 Write `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md`:
  - [ ] 9.2.1 First `cloudflare_r2_bucket` Terraform resource declaration (greenfield precedent)
  - [ ] 9.2.2 Bootstrap chicken-and-egg lesson (`gh pr merge --admin`)
  - [ ] 9.2.3 Schema-version consumer-boundary assertion across 3 consumers
  - [ ] 9.2.4 `If-None-Match: *` race-free conditional-PUT pattern
  - [ ] 9.2.5 Allowlist-bypass DB-id 41898282 filter
  - [ ] 9.2.6 4xx (≠412) fast-fail vs 5xx/429 retry classification
- [ ] 9.3 Update brainstorm doc with open-question final answers (a/b/c/d resolutions)
- [ ] 9.4 Update spec.md with: spec-flow gap resolutions; Elvalio's `pr_of_record.number = 3196` correction
- [ ] 9.5 Open follow-up PR with brainstorm + spec updates (separate from main feature PR per `wg-when-a-workflow-gap-causes-a-mistake-fix`)

## Notes

- **TDD discipline:** Phases 2 and 3-7 require RED-first tests. Verify via `git log` that test commits precede implementation commits per `cq-write-failing-tests-before`.
- **Per-command ack:** Every `terraform apply`, `gh pr merge --admin`, `bash scripts/create-cla-required-ruleset.sh` requires explicit operator approval per `hr-menu-option-ack-not-prod-write-auth`. Show command, wait for go-ahead, then execute.
- **Sign-off lifecycle:** CPO sign-off at plan time → user-impact-reviewer at review time → preflight Check 6 at ship time. Three different gates; do not collapse.
- **Renumbering note:** Original draft had 11 phases referenced in 7+ places that didn't exist. Plan-review fixed this to 9 phases. Phase 4 (receipt comment standalone) folded into Phase 2c step 2.16.13.
