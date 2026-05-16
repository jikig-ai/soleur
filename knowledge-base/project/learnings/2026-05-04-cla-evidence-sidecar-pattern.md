---
category: best-practices
tags: [cla, evidence, r2, terraform, github-actions, rfc-3161, gdpr, object-lock]
date: 2026-05-04
issue: 3209
pr: 3201
---

# CLA Evidence Sidecar Pattern — Sharp Edges and Greenfield Precedents

Captured during the feat-cla-legal-rigor build (PR #3201 / issue #3209). The work added an off-site, tamper-evident archive of CLA signatures alongside the existing upstream `contributor-assistant/github-action` workflow, plus monthly RFC 3161 timestamping, allowlist-bypass logging, schema-version assertions, a backfill path, and the GDPR Article 17 admin-override + tombstone protocol. Several patterns from this build are reusable for any future "alongside-a-vendor-action workflow that needs its own evidence trail" feature.

---

## 1. First `cloudflare_r2_bucket` Terraform resource in the repo

Before this PR, the repo's only R2 usage was the *backend* for Terraform state (`bucket = "soleur-terraform-state"`, provisioned out-of-band). There was no `cloudflare_r2_bucket` resource declared anywhere. The plan-time research surfaced this as Reconciliation #3 — the spec assumed we'd "copy the existing bucket-resource pattern" but no such pattern existed.

Sharp edges of the greenfield bucket-resource declaration (`apps/cla-evidence/infra/bucket.tf`):

- **Attribute is `location`, not `location_hint`.** The Cloudflare TF provider v4.52 renamed the attribute; older blog posts and AI training data still cite `location_hint`. The provider rejects the old spelling at plan time.
- **Values are uppercase.** `WEUR`, not `weur`.
- **`location` is not `region`.** The provider has both attributes for different resource types; pick the one declared on `cloudflare_r2_bucket` schema.
- **Object Lock cannot be set via `cloudflare_r2_bucket_lock_configuration` directly for default-retention mode.** That resource is *rule-based age/date conditions*, not a default-retention setter. Use `null_resource` + `local-exec` calling `aws s3api put-object-lock-configuration` — Phase 1 documented this gap.
- **`lifecycle { prevent_destroy = true }` is non-negotiable** for any bucket holding legal-evidence data; a `terraform destroy` on a renamed resource silently nukes the bucket otherwise.
- **R2 backend has no state lock** (learning #8 — `use_lockfile = false`). Single-writer `terraform apply` only; document this in the new TF root's README.

---

## 2. Bootstrap chicken-and-egg for self-validating workflows

Any workflow that gates merges (via Check Run + required-checks ruleset) cannot self-validate on the PR that introduces it. The workflow file does not exist on `main` yet, so it does not run against its own PR.

The fix is a two-step bootstrap:

1. **First merge with `gh pr merge --admin`** — operator action, explicit per-command ack per `hr-menu-option-ack-not-prod-write-auth`. Blast-radius is limited to the bootstrap PR; revertible via PR if the sentinel fails.
2. **Sentinel test PR immediately after** — exercises the live workflow end-to-end. Required by `wg-after-merging-a-pr-that-adds-or-modifies` for any workflow change.

Document this explicitly in the bootstrap PR body so reviewers don't block on "where are the green checks for the new workflow itself?" — the answer is "the sentinel PR will produce them post-merge." Same constraint as the original `cla.yml` introduction in 2026-02-26.

---

## 3. Schema-version consumer-boundary assertion across N consumers

Per best-practice `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.md`, a `schema_version` field is cosmetic unless every consumer asserts it at parse time. This PR exercised the pattern at three boundaries:

- **Backfill (TS)** — `validateEvidenceRecord` in `apps/web-platform/scripts/cla-evidence/schema.ts`; `process.exit(3)` on mismatch.
- **Sidecar workflow (bash + TS)** — same `validateEvidenceRecord` called from `build-record.ts` before the upload.
- **Inspect script (bash + jq)** — `assert_schema_version()` in `apps/cla-evidence/scripts/inspect-evidence.sh`; `exit 3` on mismatch. Paralleled by `inspect.test.sh` TS25.

Exit code `3` is the cross-language convention adopted across all three (backfill + sidecar + inspect). If a future consumer is added (e.g., a CLI export tool), repeat the same pattern; do not weaken to a warning.

The test surface (TS23 backfill, TS24 sidecar tombstone-append, TS25 inspect) catches drift across all three consumers. Adding a 4th consumer without adding a TS-* assertion is the failure mode the rule guards against.

---

## 4. `If-None-Match: *` conditional PUT for race-free R2 canonical records

R2 supports the S3 `If-None-Match: *` header for conditional PUT — first write succeeds (200/201), subsequent writes for the same key return 412 (PreconditionFailed). This is the right primitive for "per-principal, per-quarter canonical record" (Phase 4 allowlist-bypass log): two concurrent workflow runs may both detect the same bypass event, but only one can win the write, and the loser exits cleanly without an error.

The pattern also covers content-addressed evidence writes (`signatures/<sha256>.json`): if a sign-then-edit-then-resign sequence produces identical bytes (idempotent), 412 is the expected outcome and signals success, not failure.

Classification matters — see Section 5 below.

---

## 5. R2 4xx classification: 412 ≠ other 4xx (Kieran F5)

Every conditional-PUT helper (`upload-evidence.sh`, `upload-bypass.sh`) classifies the response code into three exit paths:

| Code | Meaning | Action |
|---|---|---|
| 200 / 201 | First write succeeded | exit 0 |
| 412 | PreconditionFailed (duplicate idempotent write) | exit 0 — log as `duplicate status=412` |
| 5xx / 429 | Transient | retry up to 3 with exponential backoff (250ms, 500ms, 1000ms) |
| 4xx ≠ 412 | Config bug (stale token, missing perms, bucket lock violation) | fast-fail with `::error::`, exit 2 |

The 4xx fast-fail path is load-bearing. Without it, a stale R2 token returning 403 would cause the workflow to spin in the retry loop until timeout (or hit the retry cap and then fail, but only after 3 wasted attempts). The `::error::` annotation also surfaces the issue to operator visibility immediately.

Same classification applied symmetrically in `inspect-evidence.sh` (fetch path) — though there the 4xx-on-read case is rarer.

---

## 6. Allowlist-bypass DB-id 41898282 filter (learning #2 carry-forward)

The upstream `contributor-assistant/github-action` filters `github-actions[bot]` (database id 41898282) BEFORE the allowlist check fires. Any sidecar that naively re-implements the allowlist check against `actor.login` will produce false-positive bypass records for github-actions[bot] events (which the upstream action never raised).

The fix: `isAllowlistBypass(login: string, dbId: number)` checks BOTH the allowlist string AND the DB-id. DB-id 41898282 always returns `false` regardless of the login string. This is encoded in `apps/web-platform/scripts/cla-evidence/allowlist.ts` and verified by TS16b.

Related: when building sanitized bucket keys for allowlist-bypass records (`allowlist/<principal_safe>/<yyyy-qq>.json`), strip `[bot]` to `-bot` (e.g., `dependabot[bot]` → `dependabot-bot`). The canonical login is preserved inside the payload's `principal` field. See Kieran F8.

---

## 7. GDPR Art. 17 tombstone protocol for Object Lock Governance

Object Lock Compliance mode is root-immutable — no escape hatch for Art. 17 erasure requests. Object Lock Governance mode permits an administrator override (`--bypass-governance-retention`), but a naive override breaks the evidence chain: the next month's RFC 3161 manifest will show "object H vanished" rather than "object H legitimately removed."

The fix is a **tombstone protocol**:
1. Operator generates a one-hour admin token (Cloudflare dashboard, dashboard-only, never Doppler).
2. Delete the object with `--bypass-governance-retention`.
3. **Immediately** write `tombstones/<sha>.deleted.json` to a separate `tombstones/` prefix; payload contains `{schema_version, deleted_at, admin_actor, gdpr_request_ref, prior_object_sha, override_reason}` — **no contributor PII**.
4. The next monthly RFC 3161 manifest (`cla-evidence-timestamp.yml`) lists `tombstones/` along with `signatures/` and `allowlist/`, so the chain shows "object H replaced by tombstone T at month M+1."
5. Revoke the admin token immediately.
6. Append an entry to the internal DPA-override log (incident ticket; not the public branch).

Runbook: `knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md` §7.

---

## 8. Always-timestamp YYYY-MM in manifest pre-image (spec-flow gap #9)

RFC 3161 TSAs hash the input bytes. If the bucket state is unchanged between two monthly runs, the manifest bytes are identical, the SHA-256 is identical, the TSQ is identical, and FreeTSA may return an identical (or near-identical) `.tsr` — making "this month's chain link" indistinguishable from last month's.

The fix: fold the current month (YYYY-MM) into the manifest header line as the first record:

```json
{"manifest_yyyy_mm":"2026-05","schema_version":"1.0"}
```

This forces a unique TSQ per month even on a quiet bucket, so the chain advances regardless of activity. The header is part of the timestamped bytes, so an auditor can verify the YYYY-MM matches the upload key (`timestamps/<yyyy-mm>/manifest.jsonl`).

---

## 9. FreeTSA fixture capture for offline `openssl ts -verify` testing

The Phase 5 test (`apps/cla-evidence/scripts/timestamp.test.sh`) is a *real* RFC 3161 verify-replay against a `.tsr` captured from `https://freetsa.org/tsr` at fixture-creation time. This is preferable to a stubbed openssl test for two reasons:

1. **No mock drift.** A stub for `openssl ts -verify` would have to be re-tuned every time openssl's output format changes; the real binary against a real fixture is stable.
2. **It detects FreeTSA cert rotation.** When FreeTSA rotates their TSA cert, the bundled `apps/cla-evidence/freetsa/tsa.crt` becomes invalid; the fixture verification fails; the operator refreshes the bundle before next month's cron — *before* the monthly run silently fails.

The fixture-capture is a one-time submission (well within FreeTSA's "do not abuse" policy). The captured `.tsr` is checked in alongside the fixture manifest.

The test also includes a **tamper-detection assertion** (TS17.c): mutating the fixture manifest by one byte must fail verification. Without this, the test could pass vacuously if `openssl ts -verify` ever started ignoring the `-data` argument.

---

## 10. Multi-line bash strings inside `run: |` YAML blocks need files, not heredocs

The Phase 5 workflow (`cla-evidence-timestamp.yml`) initially used a multi-line bash variable assignment for the PR commit message:

```yaml
run: |
  commit_msg="chore(...): timestamp ${YYYY_MM}

  Manifest sha256: ${MANIFEST_SHA}
  ..."
  git commit -m "$commit_msg"
```

This broke YAML parsing because YAML block-scalar `|` requires every continuation line to be indented at the block's start column; the un-indented prose lines (`Manifest sha256:`, etc.) terminate the block early and produce ScannerError at parse time.

The fix: write multi-line content to a file via `printf` (which gives full control over newlines without breaking YAML indentation), then use `git commit -F file` and `gh pr create --body-file file`:

```yaml
run: |
  {
    printf 'chore(...): timestamp %s\n\n' "$YYYY_MM"
    printf 'Manifest sha256: %s (%s lines)\n' "$MANIFEST_SHA" "$MANIFEST_LINES"
    printf 'Run: %s\n' "$RUN_URL"
  } > out/commit-msg.txt
  git commit -F out/commit-msg.txt
```

Same applies to `gh issue create --body-file`, `gh issue comment --body-file`, etc. Generally: if a string spans multiple lines AND is destined for a CLI tool that accepts a `--body-file` / `--message-file` / `-F` flag, prefer the file route over inline assignment.

---

## 11. Phase 6 legal-doc-consistency test: prefer structural + sentinel match over strict body equality

The plan called for a CI guard that diffs `docs/legal/<f>.md` vs `plugins/soleur/docs/pages/legal/<f>.md` body content. A naive strict equality test failed across all five docs due to pre-existing legacy drift: extra blockquote characters, missing intro paragraphs in mirrors, link-format differences (`(foo.md)` vs `(/legal/foo/)`).

The pragmatic guard (in `apps/web-platform/test/legal-doc-consistency.test.ts`) uses three layers:

1. **Heading-sequence parity** — extract `## ` and `### ` headings in order; assert source and mirror have identical heading lists. Catches "section added to one but not the other" without choking on whitespace/wrappers.
2. **Sentinel-string match** — 15 load-bearing patterns from the Phase 6 edits (each preamble opening, each new section header, each new sub-processor row) must appear in BOTH source and mirror.
3. **Last Updated date parity** — the date (not the "previous:" history fragment) must match between source body, mirror body, and mirror hero `<p>`.

Tightening to full body equality is a follow-up after a one-off legacy-drift cleanup PR. The structural+sentinel guard catches all Phase 6-class drift today without false positives.

---

## See also

- `2026-02-26-cla-system-implementation-and-gdpr-compliance.md` — baseline CLA learnings
- `2026-04-27-cla-allowlist-graphql-vs-rest-bot-identity-surface.md` — DB-id 41898282 filter
- `2026-03-19-content-publisher-cla-ruleset-push-rejection.md` — PR-with-auto-merge for cron PRs
- `2026-03-21-terraform-state-r2-migration.md` — R2 backend no-lock constraint
- `2026-03-20-doppler-secrets-manager-setup-patterns.md` — Doppler config-pinned service tokens
- `best-practices/2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.md` — consumer-boundary assertion source rule
