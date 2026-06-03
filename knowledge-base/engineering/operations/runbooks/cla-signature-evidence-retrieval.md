---
category: legal
tags: [cla, evidence, r2, rfc-3161, gdpr, dmca, freetsa]
date: 2026-05-16
---

# CLA Signature Evidence Retrieval

Operations runbook for the off-site CLA evidence archive (`soleur-cla-evidence` R2 bucket, region `weur`, R2 Lock Rules age-based retention with a 10-year floor providing write-once-read-many (WORM) semantics). Covers IP-dispute response, DMCA notice handling, GDPR Article 17 erasure requests, and contributor-revocation flows.

**Cross-references:**
- Architecture: `apps/cla-evidence/infra/` (Terraform) + `apps/cla-evidence/scripts/` (helpers) + `.github/workflows/cla-evidence.yml` (sidecar) + `.github/workflows/cla-evidence-timestamp.yml` (monthly RFC 3161).
- Legal posture: [Privacy Policy §4.5 + §5.11](/docs/legal/privacy-policy.md), [DPD §2.3(d)+(n)](/docs/legal/data-protection-disclosure.md), [GDPR Policy §3.4](/docs/legal/gdpr-policy.md), CLA preambles §0.
- Adjacent runbook: [cloudflare-service-token-rotation.md](./cloudflare-service-token-rotation.md) (sibling read-token workflow for the Web Platform CDN tokens).

**Fixtures used in examples below are synthetic.** No real signer login, comment ID, or PR number appears in this document; substitute your real values per-incident. See `cq-test-fixtures-synthesized-only`.

---

## 1. Trigger

Open this runbook when ANY of the following occurs:

| Trigger | Typical urgency | Lead actor |
|---|---|---|
| DMCA takedown notice naming a Soleur contribution | 24h response window | CLO + ops |
| IP dispute (third-party claim that a contributor's submission infringes) | Per case; usually 7d initial response | CLO |
| GDPR Article 17 erasure request from a contributor | 30 days (Art. 12(3)) | CLO + ops |
| Contributor-initiated revocation of CLA signature | No statutory deadline; respond within 14d | CLO |
| FreeTSA monthly cron failure persists ≥3 consecutive months | Operational; switch to paid TSA | ops |

The first three are legal triggers — always loop in the CLO before any data movement (Section 2). The last two are operational.

---

## 2. Pre-step: confirm scope with CLO

Before generating any credentials or fetching any evidence:

1. Capture the request artifact (forwarded email, DMCA notice PDF, GDPR DSAR ticket) in the legal counsel's case folder.
2. CLO confirms in writing:
   - The legal basis for the response (DMCA, Art. 17, IP dispute).
   - The specific signers / PR numbers / time window in scope.
   - Whether the Art. 17(3)(e) defense-of-claims carveout applies (relevant for erasure requests only; see GDPR Policy §3.4).
3. Document the CLO sign-off in the incident ticket before proceeding. If the trigger is a GDPR erasure, the CLO sign-off must explicitly state whether the carveout is invoked or whether the deletion proceeds.

**Do not skip this step.** The off-site archive is the canonical evidence chain; ad-hoc reads still leave audit log entries (Section 8) and create a window where over-broad disclosure is possible. CLO scope-confirmation is the legal safeguard.

---

## 3. Read-token generation (ad-hoc, 24h TTL)

The R2 tokens provisioned by `apps/cla-evidence/infra/iam.tf` are scoped object-write-only (sidecar) and state-write-only (Terraform). Neither has list/read permission. For inspection, operators generate an ad-hoc read token in the Cloudflare dashboard:

1. Navigate to **Cloudflare dashboard → R2 → Manage R2 API Tokens → Create API Token**.
2. Configure:
   - **Permissions:** Object Read (for the `soleur-cla-evidence` bucket only — set the bucket-level scope).
   - **TTL:** 24 hours (the dashboard default; do not extend).
   - **Specify bucket:** `soleur-cla-evidence`.
3. Copy the Access Key ID and Secret. **Do NOT add to Doppler.** Export to your local shell only:

   ```bash
   export R2_CLA_EVIDENCE_ACCESS_KEY_ID="<from dashboard>"
   export R2_CLA_EVIDENCE_SECRET="<from dashboard>"
   export R2_CLA_EVIDENCE_BUCKET="soleur-cla-evidence"
   export R2_CLA_EVIDENCE_ENDPOINT="https://<account>.r2.cloudflarestorage.com"
   ```

4. After the inspection is complete, revoke the token from the same dashboard page (**Manage R2 API Tokens → … → Delete**). Do NOT wait for the 24h TTL to expire.

---

## 4. Retrieve evidence by contributor

Use `apps/cla-evidence/scripts/inspect-evidence.sh` (the third schema-version consumer per learning #18; exits 3 on schema mismatch).

```bash
bash apps/cla-evidence/scripts/inspect-evidence.sh by-contributor <login>
```

Example (synthetic):

```bash
bash apps/cla-evidence/scripts/inspect-evidence.sh by-contributor synthetic-signer-1 \
  | tee /tmp/cla-evidence-contributor-synthetic-signer-1.json
```

Each record is emitted as one JSON object on stdout with a `_key` field appended showing the content-addressed R2 key. Pipe to `jq` for filtering (e.g., `jq 'select(.pr_of_record.number == 9999)'`).

If the script exits 3, the bucket contains a record with a `schema_version` other than `"1.0"` — file a P1 issue immediately; the evidence chain integrity is at risk.

---

## 5. Retrieve evidence by PR

```bash
bash apps/cla-evidence/scripts/inspect-evidence.sh by-pr <pr-number>
```

Example (synthetic):

```bash
bash apps/cla-evidence/scripts/inspect-evidence.sh by-pr 9999 \
  | tee /tmp/cla-evidence-pr-9999.json
```

Records are written content-addressed at `signatures/<sha>.json`. `by-pr` mode lists the full `signatures/` prefix and filters server-side by `.pr_of_record.number` matching the PR number — this avoids a second R2 PUT per sign event (no pointer prefix is maintained at write-time). The output is the same JSON shape as `by-contributor` with a `_key` field appended.

For allowlist-bypass records (bot accounts):

```bash
bash apps/cla-evidence/scripts/inspect-evidence.sh by-quarter 2026-q2
```

Note that `github-actions[bot]` (DB-id 41898282) is filtered upstream and will not appear in bypass records by design (per learning #2).

---

## 6. Notarized export for legal counsel

When evidence is being handed to outside counsel, bundle it with a fresh RFC 3161 timestamp so counsel can independently verify the chain:

1. Assemble the subset on local disk (output of Section 4 or 5):

   ```bash
   mkdir -p /tmp/cla-export/records
   bash apps/cla-evidence/scripts/inspect-evidence.sh by-pr <n> > /tmp/cla-export/records/pr-<n>.json
   ```

2. Build a fresh manifest of the subset and submit to FreeTSA:

   ```bash
   cd /tmp/cla-export
   sha256sum records/*.json > manifest.txt
   openssl ts -query -data manifest.txt -sha256 -cert -no_nonce -out request.tsq
   curl -sS --max-time 30 \
     -H "Content-Type: application/timestamp-query" \
     --data-binary @request.tsq \
     -o response.tsr \
     https://freetsa.org/tsr
   ```

3. Verify the export-time timestamp locally before sending:

   ```bash
   openssl ts -verify -in response.tsr -data manifest.txt \
     -CAfile <repo>/apps/cla-evidence/freetsa/cacert.pem \
     -untrusted <repo>/apps/cla-evidence/freetsa/tsa.crt
   ```

   Output must contain `Verification: OK`.

4. Bundle into a tarball and hash it. Also include the LATEST monthly RFC 3161 manifest+`.tsr` from the bucket (`timestamps/<yyyy-mm>/`) so counsel can verify the historical chain back to the original sign event:

   ```bash
   cp records/*.json .
   # Fetch the most-recent monthly TSR
   aws --endpoint-url "$R2_CLA_EVIDENCE_ENDPOINT" s3 cp \
     "s3://${R2_CLA_EVIDENCE_BUCKET}/timestamps/$(date -u +%Y-%m)/manifest.tsr" \
     monthly.tsr
   aws --endpoint-url "$R2_CLA_EVIDENCE_ENDPOINT" s3 cp \
     "s3://${R2_CLA_EVIDENCE_BUCKET}/timestamps/$(date -u +%Y-%m)/manifest.jsonl" \
     monthly.jsonl
   tar czf /tmp/cla-export.tar.gz records/*.json manifest.txt request.tsq response.tsr monthly.tsr monthly.jsonl
   sha256sum /tmp/cla-export.tar.gz | tee /tmp/cla-export.tar.gz.sha256
   ```

5. Deliver to counsel: the tarball + the SHA-256 (out-of-band, e.g. by phone) so counsel can confirm the tarball was not modified in transit. Document the delivery (recipient, channel, timestamp) in the incident ticket.

6. Counsel verifies offline using only the bundled FreeTSA cacert (from the repo, also independently downloadable from `https://freetsa.org/files/cacert.pem`) — no Soleur infrastructure required.

---

## 7. GDPR Article 17 admin-override procedure (with tombstone protocol)

Use this procedure ONLY when the CLO has confirmed in writing that Article 17(3)(e) defense-of-claims **does NOT** apply (i.e., the contributor's data is not materially related to a live or reasonably anticipated legal claim). Resolves spec-flow gap #10.

### 7.1 Generate one-time admin token

Mint a 1-hour Cloudflare admin token whose scopes let the override driver edit
the bucket Lock Rule list AND self-revoke at the end. The token is operator-
minted per-incident (NEVER persisted in Doppler) and lives only in the
operator's local shell.

1. **Cloudflare dashboard → My Profile → API Tokens → Create Token → Create
   Custom Token**.
2. Configure:
   - **Permissions:**
     - `Account → Cloudflare R2 → Edit` (mutates the Lock Rule list).
     - `User → API Tokens → Edit` (lets the driver DELETE the token itself
       at the end — closes the residual-window risk).
   - **Account Resources:** the jikigai account only.
   - **TTL:** 1 hour. Do not extend.
3. Copy the token value, then export it to the local shell alongside the
   other required vars (see `gdpr-override.sh --help` for the full list and
   exit-code matrix):

   ```bash
   export CF_ADMIN_TOKEN="<paste from dashboard>"
   export CF_ACCOUNT_ID="$(doppler secrets get CF_ACCOUNT_ID -p soleur -c prd_terraform --plain)"
   export R2_CLA_EVIDENCE_BUCKET="soleur-cla-evidence"
   export R2_CLA_EVIDENCE_ENDPOINT="https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com"
   export TARGET_KEY="signatures/<sha>.json"      # output of §7.2
   export PRIOR_SHA="<sha>"                       # 64-char lowercase hex
   export GDPR_REQUEST_REF="<DSAR-or-incident-id>"
   export OVERRIDE_REASON="GDPR Article 17 erasure — Art. 17(3)(e) carveout confirmed inapplicable by CLO on <date>"
   export ADMIN_ACTOR="$(git config user.email)"
   ```

4. Sanity-check via `bash apps/cla-evidence/scripts/gdpr-override.sh --help`
   — the help text enumerates the exit-code semantics (0 success; 1 pre-PUT
   abort; 2 DELETE failed; 3 PUT-restore failed AFTER DELETE; 64 usage).
   Re-read these before invoking the override step in §7.3.

The driver self-revokes the admin token at the end of a successful run; if
the run aborts at exit code 3 (restore failed) the token is deliberately
left active so the operator can manually restore — revoke it via the same
dashboard page (My Profile → API Tokens → Roll/Delete) once the bucket is
back to canonical.

### 7.2 Locate the offending object

```bash
bash apps/cla-evidence/scripts/inspect-evidence.sh by-contributor <login> \
  | jq -r 'select(.pr_of_record.number == <pr>) | ._key'
# Example output: signatures/<sha>.json
```

Capture this key and the full record body — both are needed for the tombstone.

### 7.3 Delete the object via Lock Rule edit (driver-mediated)

The override is a single driver invocation. With the env vars from §7.1
exported, run:

```bash
doppler run -p soleur -c prd_cla -- \
  bash apps/cla-evidence/scripts/gdpr-override.sh --shape=enabled-false
```

The `doppler run -p soleur -c prd_cla --` wrapper supplies the R2 S3-compat
HMAC pair (the 32-char access key + 64-char SHA-256-derived secret) ONLY to
the DELETE / tombstone steps; the 53-char Cloudflare bearer admin token
flows separately to the curl-based lock-rule edits via `CF_ADMIN_TOKEN`.
Crossing the wires reproduces the `Credential access key has length 53,
should be 32` failure from PR #3919's first cron run — the driver enforces
the separation by construction.

What the driver does (mirrors `bash gdpr-override.sh --help`):

1. **Verify the admin token** via `GET /user/tokens/verify`; capture
   `result.id` for the self-revoke at the end.
2. **GET the current Lock Rule list** and snapshot it (byte-equal restore
   body). Aborts if `success != true`, `rule_count < 1`, or `maxAgeSeconds
   < 315360000` (mirrors `apps/cla-evidence/infra/main.test.sh:96-110`).
3. **PUT a temporarily-modified list** per `--shape=`. Default
   `--shape=enabled-false` flips `rules[0].enabled = false`. Fallbacks:
   `--shape=age-1s` (drops `maxAgeSeconds` to 1) and `--shape=narrow-prefix`
   (adds an override rule for `TARGET_KEY`; gated behind
   `--I-have-verified-precedence` because R2 multi-rule precedence is not
   yet empirically verified on the live bucket).
4. **DELETE the object** via `aws s3api delete-object` running under the
   `prd_cla` Doppler HMAC env. NO bypass-flag argument — the rule itself is
   temporarily disabled. If DELETE fails, the driver best-effort PUT-restores
   the snapshot, self-revokes the token, and exits 2 without writing a
   tombstone.
5. **PUT-restore the snapshot** (byte-equal), then verify via `bash
   apps/cla-evidence/infra/main.test.sh --live --strict-rule-count` —
   asserts the bucket is back to exactly one rule, age-floor intact. If
   PUT-restore FAILS the driver emits a `::error::CRITICAL` annotation and
   exits 3 WITHOUT self-revoking (operator needs the token to manually
   restore) and WITHOUT writing a tombstone (the bucket state is degraded;
   tombstoning would silently fold the incident into the next monthly RFC
   3161 manifest).
6. **Write the tombstone** per §7.4 (driver writes `{schema_version:"1.0",
   deleted_at, admin_actor, gdpr_request_ref, prior_object_sha,
   override_reason}` at `tombstones/<sha>.deleted.json` via the same `prd_cla` HMAC
   env). PRIOR_SHA is validated against `^[0-9a-f]{64}$` at entry — a
   malformed value breaks the third-consumer schema invariant at
   `inspect-evidence.sh`.
7. **Self-revoke** the admin token via `DELETE /user/tokens/{id}` (skipped
   only on exit 3 per step 5).

Exit codes: 0 success; 1 pre-PUT abort (token verify or GET failed; revoke
ran); 2 DELETE failed (restore + revoke ran; no tombstone); 3 PUT-restore
FAILED (no revoke, no tombstone — CRITICAL); 64 usage / config error.

If all three shapes fail empirically against the live bucket, the operator
can fall back to executing the underlying steps directly via curl + `aws
s3api` — the driver source at `apps/cla-evidence/scripts/gdpr-override.sh`
is the authoritative command sequence. Always pair a manual override with
the tombstone in §7.4 and the revoke in §7.6; the integrity of the
timestamp chain depends on it.

### 7.4 Tombstone protocol (mandatory)

The driver writes the tombstone automatically in step 6 of §7.3. The
schema below is the canonical contract — also referenced by
`inspect-evidence.sh` (the third consumer-boundary per learning
`2026-05-04-cla-evidence-sidecar-pattern.md` §3; `schema_version: "1.0"`
is load-bearing). The tombstone is what keeps the timestamp chain
coherent — the next monthly RFC 3161 manifest (Phase 5 step 2.b lists
`tombstones/` along with `signatures/` and `allowlist/`) will include
the tombstone, so auditors see "object H replaced by tombstone T at
month M+1" rather than "object H vanished."

If the driver's step 6 fails (network blip after a successful restore in
step 5 — the driver surfaces this as a non-fatal `::error::tombstone PUT
failed` and continues to self-revoke), write the tombstone manually
using the same `prd_cla` HMAC envelope:

```bash
tombstone_key="tombstones/<sha>.deleted.json"
tombstone_body=$(jq -n \
  --arg schema_version "1.0" \
  --arg deleted_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg admin_actor "$(git config user.email)" \
  --arg gdpr_request_ref "<incident-ticket-or-DSAR-id>" \
  --arg prior_object_sha "<sha>" \
  --arg override_reason "GDPR Article 17 erasure -- carveout 17(3)(e) confirmed inapplicable by CLO on <date>" \
  '{schema_version: $schema_version, deleted_at: $deleted_at, admin_actor: $admin_actor, gdpr_request_ref: $gdpr_request_ref, prior_object_sha: $prior_object_sha, override_reason: $override_reason}')

doppler run -p soleur -c prd_cla -- \
  aws --endpoint-url "$R2_CLA_EVIDENCE_ENDPOINT" s3api put-object \
    --bucket "$R2_CLA_EVIDENCE_BUCKET" \
    --key "$tombstone_key" \
    --body /dev/stdin \
    --content-type application/json <<< "$tombstone_body"
```

Tombstones contain **no contributor PII** — only the SHA-256 of the deleted record, the timestamp, the admin actor's email (operator, not contributor), the GDPR request reference, and the override reason. This satisfies the right-to-erasure obligation without breaking the chain.

### 7.5 DPA log update

Append a private log entry (no PII) to the internal DPA-override log:

```
DATE: <ISO timestamp>
REQUEST_REF: <incident-ticket-or-DSAR-id>
PRIOR_SHA: <sha>
TOMBSTONE_KEY: tombstones/<sha>.deleted.json
CLO_SIGNOFF: <name, date>
```

This log is for internal audit (Article 5(2) accountability). It is NOT the public branch — store it in the secure incident ticket only.

### 7.6 Revoke the admin token

The driver self-revokes the admin token at the end of a successful run
(step 7 of §7.3). The only case where the operator must revoke manually is
exit code 3 (PUT-restore failed) — the driver deliberately leaves the
token active so the operator can manually restore the lock-rule list,
then revoke via Cloudflare dashboard (My Profile → API Tokens → Delete).
Do NOT wait for the 1-hour TTL.

### 7.7 Confirm in the next monthly manifest

After the next month's `cla-evidence-timestamp.yml` run, verify the tombstone is in the manifest:

```bash
aws --endpoint-url "$R2_CLA_EVIDENCE_ENDPOINT" s3 cp \
  "s3://${R2_CLA_EVIDENCE_BUCKET}/timestamps/<next-month>/manifest.jsonl" - \
  | grep "tombstones/<sha>.deleted.json"
```

If the tombstone is missing, the chain has a gap; file P1 and re-run the timestamp workflow.

---

## 8. Audit-log read

Every operation against the bucket (read, write, delete, governance bypass) is recorded in the Cloudflare account audit log. After any admin-override (Section 7) or notarized export (Section 6), pull the audit log entries and attach to the incident ticket:

**Option A — dashboard (interactive):**

1. **Cloudflare dashboard → Manage Account → Audit Log**.
2. Filter:
   - **Action:** R2 (Object operations).
   - **Time range:** the window of your operations.
3. Export to CSV. Attach to the incident ticket.

**Option B — API (scriptable, preferred for incidents):**

```bash
# Replace the placeholders. The token must have "Account Audit Logs: Read".
curl -sS \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/audit_logs?since=2026-01-01T00:00:00Z&before=2026-01-31T23:59:59Z&action.type=write&per_page=1000" \
  | jq '.result[] | select(.resource.type | test("r2|bucket"))' \
  > audit-log.json
```

Pagination: response includes `result_info.next_page` when more entries exist; iterate by appending `&page=<n>`. Reference: <https://developers.cloudflare.com/api/operations/audit-logs-get-account-audit-logs>.

The audit log captures: API token ID used, operation (Read/Write/Delete + BypassGovernance flag), key, timestamp, source IP. This is the operator-side counterpart to the tombstone — both must reconcile.

---

## 9. Paid-TSA fallback (when FreeTSA fails 3 consecutive months)

The monthly cron (`cla-evidence-timestamp.yml`) files a tracking issue per failed month (Kieran F9). If three consecutive monthly issues remain open, switch to a paid RFC 3161 TSA:

**Options (per plan):**
- **DigiCert** — RFC 3161 service, requires a DigiCert account + paid TSA endpoint. Approximate cost: $10-20/timestamp at low volume.
- **GlobalSign** — RFC 3161 service, requires GlobalSign account. Comparable cost.

**Switch procedure (manual, one-time):**

1. Operator creates account at chosen TSA vendor (DigiCert or GlobalSign).
2. Obtain:
   - TSA endpoint URL (replaces `https://freetsa.org/tsr` in the workflow).
   - Vendor's root CA bundle (`cacert.pem` equivalent — replaces `apps/cla-evidence/freetsa/cacert.pem`).
   - Vendor's TSA signing certificate (`tsa.crt` equivalent — replaces `apps/cla-evidence/freetsa/tsa.crt`).
   - Authentication credentials if required (DigiCert uses an API key; GlobalSign uses a client cert).
3. Open a PR updating:
   - `.github/workflows/cla-evidence-timestamp.yml` — swap the curl endpoint; add the auth header if required; bump the `Auto-file tracking issue` runbook reference.
   - `apps/cla-evidence/freetsa/{cacert.pem,tsa.crt}` — replace with vendor bundles. Rename the directory to `apps/cla-evidence/tsa/` (or vendor-specific) if the rename improves clarity.
   - `apps/cla-evidence/scripts/timestamp.test.sh` — re-capture the fixture `.tsr` from the new TSA.
   - This runbook — update Section 6 (notarized export) to reference the new vendor cert paths.
4. Document the switch in `knowledge-base/operations/expenses.md` (new line item for the paid TSA).
5. Close the three open `cla-evidence,timestamp-failure` issues with a comment linking the switch PR.

---

## Appendix A: Sharp edges

- **Tokens are config-pinned in Doppler** (learning #9). `DOPPLER_TOKEN_CLA` works only against the `prd_cla` config. Read tokens generated for inspection live in your local shell only, never in Doppler.
- **Ruleset PUT is full-replace** (learning #11). If the runbook ever needs to modify the CLA Required ruleset, use `scripts/create-cla-required-ruleset.sh` which rewrites the entire payload.
- **R2 backend has no lock** (learning #8). Concurrent `terraform apply` against `apps/cla-evidence/infra/` is unsafe. Single-writer only.
- **The runbook itself must NOT contain real signer PII.** All examples in this document use synthetic logins / PR numbers; preserve that convention per `cq-test-fixtures-synthesized-only`.
- **`[skip ci]` deadlocks required Check Runs** (learning #12). If you author a manual commit related to this runbook, never include `[skip ci]` in the message.
- **The admin-override is operator-only, ack-required.** Per `hr-menu-option-ack-not-prod-write-auth`, every `gdpr-override.sh` invocation must be explicitly approved by the operator at the prompt — no "approve all destructive ops" mode. The driver also requires `--I-have-verified-precedence` as a separate ack before `--shape=narrow-prefix` can run, because R2 multi-rule precedence semantics are not yet empirically verified on this bucket.
