---
type: feature
lane: single-domain
domain: engineering+legal
issue: 3924
priority: p2-medium
requires_cpo_signoff: false
brand_survival_threshold: aggregate-pattern
---

# feat: Rewrite cla-evidence runbook §7 admin-override for R2 Lock Rules

## Enhancement Summary

**Deepened on:** 2026-05-17
**Sections enhanced:** Overview, Choice of Lock Rule Edit Shape, Files to Create, Acceptance Criteria, Sharp Edges, Test Strategy
**Research sources:**

- `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md` §12 — canonical CF R2 Lock Rules API contract (body shape, three valid `condition.type` values, bearer-vs-HMAC trap)
- `knowledge-base/project/learnings/2026-05-16-legal-prose-vocabulary-refactors-implicate-operational-runbooks.md` — drift class + session errors directly motivating this PR
- Codebase reads: `bootstrap.sh:55-78` (preflight + verify), `bootstrap.sh:218-247` (self-revoke), `object_lock.tf:31-86` (canonical PUT body), `main.test.sh:91-118` (jq-shape assertion), `r2-conditional-put.sh:53-100` (HTTP classification), `upload-bypass.test.sh:35-55` (PATH-stub idiom), `sentinel-pr.sh:110,167-192` (ERR-trap recovery pattern)
- `gh pr view 3920` + `gh issue view 3924` — both verified live (state + title match plan claims)
- AGENTS.md grep — all cited rule IDs (`hr-weigh-...`, `hr-gdpr-gate-...`, `cq-test-fixtures-...`, `wg-use-closes-...`, etc.) verified active; none in `scripts/retired-rule-ids.txt`
- `gh label list` — `domain/legal`, `domain/engineering`, `type/chore`, `priority/p2-medium`, `follow-through` all verified present

### Key Improvements
1. **Canonical R2 Lock Rules API contract pinned inline.** Body shape `{"rules":[...]}` is load-bearing (a bare array returns HTTP 400); three valid `condition.type` values enumerated; bearer-token ≠ HMAC-key trap surfaced as Sharp Edge to prevent the same 53-vs-32-char regression that bit #3920's first cron run.
2. **ERR-trap recovery pattern.** `gdpr-override.sh` adopts the `sentinel-pr.sh:167-192` idiom — `trap '_cleanup_partial_override "$snapshot"' ERR` is set BEFORE the PUT-disable and cleared (`trap - ERR`) only after successful restore. Guarantees a best-effort PUT-restore even if the operator Ctrl-C's mid-flow.
3. **Cross-artifact drift gate added to AC.** Per the 2026-05-16 learning, when this PR rewrites the runbook, the legal-prose mirror must stay in sync. AC8 (now strengthened) runs `git grep -nl 'Object Lock Governance\|--bypass-governance-retention'` across `knowledge-base/engineering/ops/runbooks/`, `docs/`, `apps/`, `plugins/` and asserts the runbook is the only file the new vocabulary touches (no other operational artifact accidentally inherits the old vocabulary).
4. **AC1-AC14 + AC15 grep verifications validated against awk-self-match sharp-edge.** AC8 region-extraction uses flag-based awk (`/start/{flag=1;next} /end/{flag=0} flag`), not the self-matching `/start/,/end/` range. Verified at deepen-time on the live legal-doc file: both `docs/legal/gdpr-policy.md` and `plugins/soleur/docs/pages/legal/gdpr-policy.md` yield 13-line bodies (parity confirmed).
5. **`--shape=narrow-prefix` precedence semantics flagged as load-bearing unknown.** CF docs describe Lock Rules as "rules without a prefix apply to all objects" (object_lock.tf:7-9 comment) but multi-rule precedence is NOT documented in the cited learning. Plan now prescribes that Shape C requires a synthetic-bucket dry-run before live use AND files a follow-up tracking issue to canonicalize precedence semantics if Shape C is ever exercised.
6. **ShellCheck integration explicit.** AC13 now also requires `bash -n` parse-validation as a pre-shellcheck gate (catches syntax errors shellcheck might tolerate). The driver inherits the same `set -euo pipefail` + color-helper structure as `bootstrap.sh`.
7. **Test parameter-injection hardening.** TS-OVERRIDE.j tightened: the test asserts neither `CF_ADMIN_TOKEN` nor `R2_CLA_EVIDENCE_SECRET` appears in `BASH_XTRACEFD` output AND grep over `set -x` output anchored on the actual token value (not the env var name).

### New Considerations Discovered

- **Bearer-token vs HMAC-key trap (cla-evidence-sidecar §12c).** The driver's DELETE step uses the operator's HMAC pair from Doppler `prd_cla` (32-char access-key + 64-char SHA-256-derived secret) — NEVER the bearer admin token (53 chars). The admin token is exclusively for `Bearer` auth on `/r2/buckets/.../lock` (rule-list edit) and `/user/tokens/{id}` (self-revoke). A regression where the operator passes the bearer token to the S3-compat DELETE would fail with the same "Credential access key has length 53, should be 32" error that bit #3919's first cron run. Codified as a Sharp Edge.
- **No `cloudflare_r2_bucket_lock` TF resource exists for bucket-default rules.** Future-work tracking issue (FW1, already in `object_lock.tf`) covers swapping when CF ships a typed resource. Current driver matches the `null_resource + curl` shape and ships no terraform.
- **`condition.type: "Indefinite"` is a third valid shape.** Not used today (the bucket uses `Age`), but enumerated in learning §12b. If a future migration adopts Indefinite, Shape A's `enabled:false` flip continues to work; Shape B's `maxAgeSeconds:1` does not apply (no maxAgeSeconds key on Indefinite rules); Shape C precedence semantics remain TBD. Surfaced for future-readers as a Non-Goal note.
- **AC1 grep false-positive risk on prose comments.** The 2026-05-16 learning's first session-error: a documentation-only comment matched the AC grep "no `aws s3api .* object-lock`" literals. AC4 (no STALE banner) and AC6 (driver invocation present) are anchored on phrase-substrings that span no internal punctuation, but the negative AC checking "no stale historical aws s3api commands" needs to allow the `<details>` historical blocks (which §7.1+§7.3 historical references currently contain). The plan REMOVES those historical blocks entirely; AC4 now greps for both `STALE` and `--bypass-governance-retention`, asserting zero matches.

---

## Overview

PR #3920 migrated the `soleur-cla-evidence` bucket from the (R2-unimplemented) S3 Object Lock surface to CF native R2 Lock Rules (`prefix:""`, age-based, `maxAgeSeconds=315360000`). The user-facing legal prose at `docs/legal/gdpr-policy.md` §3.4 sub-bullet (3) and its plugin mirror were rewritten to describe the GDPR Article 17 admin-override in the new vocabulary ("temporarily update the bucket lock-rule list to exclude the offending object, delete it, then restore the rule list"). The operational runbook at `knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md` §7 was *not* rewritten; PR #3920 only added stale-warning banners + an interim high-level outline.

This plan delivers the tested driver script + corrected runbook so that, when a GDPR Art. 17 erasure request lands and the CLO has signed off, a designated operator can execute the override deterministically. The deliverable closes the legal-ops gap that the runbook banner flags as "STALE — do not execute §7.3 verbatim."

**Sub-bullet of intent:** the legal-prose change in PR #3920 created the drift; this PR closes it. The runbook was untouched on `main` before PR #3920 and so is `pre-existing` in the strict sense, but PR #3920's user-facing prose now references a procedure the runbook does not document operationally.

## User-Brand Impact

**If this lands broken, the user experiences:** a delayed or refused GDPR Art. 17 erasure response, exceeding the Art. 12(3) 30-day window. Operator runs §7.3 verbatim against R2, gets `NotImplemented` errors on `--bypass-governance-retention`, has no tested fallback, escalates to ad-hoc commands not covered by the tombstone-protocol invariants, and risks (a) failing to write the tombstone (breaks RFC 3161 chain coherence next month), (b) leaving an admin token un-revoked, or (c) deleting the wrong object key.

**If this leaks, the contributor's data / workflow is exposed via:** the deletion path is the *minimisation* path, not a leak surface — the failure mode is the opposite (failing to delete, retaining data the contributor has the right to have erased). The admin-token leak vector (token left active past the override window) is a residual concern handled by the self-revoke step, mirroring `bootstrap.sh:235-247`.

**Brand-survival threshold:** `aggregate pattern`. A single failed Art. 17 erasure does not by itself constitute a brand-survival incident, but a pattern of refused/delayed erasures (e.g., the CLO cannot execute the procedure without operator intervention) would compound into a regulatory and contributor-trust failure. The runbook becoming "stale" again after the next R2-API churn falls into the same aggregate pattern.

Sharp edge: a plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled per `cm-challenge-reasoning-instead-of` + `hr-weigh-every-decision-against-target-user-impact`.

## Research Reconciliation — Plan-time Codebase Verification

| Plan claim | Reality (verified via grep/Read at plan time) | Plan response |
|---|---|---|
| "PR #3920 added stale banners" | Confirmed: runbook lines 9 (header) + §7.1 + §7.3 carry `[STALE — see banner at top]` + interim outline | Rewrite §7.1 + §7.3 + drop the runbook-header banner (issue Scope item 4) |
| "Bootstrap admin-token pattern is the precedent" | Verified at `apps/cla-evidence/infra/bootstrap.sh:60-71` (verify endpoint) + `:235-247` (self-revoke). Token capture order: verify → use → self-revoke. Verify response carries `result.id`. | Adopt the same three-step pattern in `gdpr-override.sh`; no new abstraction |
| "Doppler `prd_cla` carries HMAC creds for the DELETE step" | Verified at `bootstrap.sh:106-118`: `prd_cla` config holds `R2_CLA_EVIDENCE_ACCESS_KEY_ID`, `R2_CLA_EVIDENCE_SECRET`, `R2_CLA_EVIDENCE_ENDPOINT`, `R2_CLA_EVIDENCE_BUCKET` | Use `doppler run -p soleur -c prd_cla -- bash gdpr-override.sh ...` for the DELETE step (NOT the lock-rule edit) |
| "Lock Rule list shape is `{rules:[{id,enabled,prefix,condition:{type,maxAgeSeconds}}]}`" | Verified at `apps/cla-evidence/infra/object_lock.tf:31-40` (`local.lock_rule`) + `main.test.sh:91-99` (jq-shape assertion `condition.type == "Age" \| .maxAgeSeconds`) | The GET → mutate → PUT → restore cycle must preserve this exact shape; the restore PUT is byte-equal to the GET response's `result.rules` array |
| "main.test.sh --live verifies `rule_count >= 1 && maxAgeSeconds >= 315360000`" | Verified `MIN_LOCK_SECONDS=315360000` + the jq `[.result.rules[]? \| select(.condition.type == "Age") \| .condition.maxAgeSeconds] \| max` assertion | Post-restore verification re-invokes `bash apps/cla-evidence/infra/main.test.sh --live` to assert the rule list is back to canonical |
| "Tombstone schema is fixed at `{schema_version, deleted_at, admin_actor, gdpr_request_ref, prior_object_sha, override_reason}`" | Verified at runbook §7.4 (current) — the schema is correct and `schema_version: "1.0"` is the third consumer-boundary per learning #18 (`2026-05-04-cla-evidence-sidecar-pattern.md` §3) | Keep §7.4 as-is. The driver writes the tombstone using the same shape |
| "Curl stub pattern (`PATH=$work:$PATH`) is the established dry-run idiom" | Verified at `apps/cla-evidence/scripts/upload-bypass.test.sh:35-55` (`mk_curl_stub`) and `apps/cla-evidence/scripts/inspect.test.sh:30-55` (`mk_aws_stub`) | `gdpr-override.test.sh` adopts the same stub-via-PATH pattern; stubs cover `curl`, `aws`, `doppler`, `gh` |
| "Legal-prose mirror lives at `plugins/soleur/docs/pages/legal/gdpr-policy.md`" | Verified — second mirror at this path; `docs/legal/gdpr-policy.md` is the source. §3.4 sub-bullet (3) wording is already correct in BOTH copies post-#3920 | Re-verify by `diff` after the runbook rewrite; expected `no diff` (we are not editing legal prose, only re-confirming it matches the runbook) |
| "Bootstrap admin scope is `Account → Cloudflare R2 → Edit`" | Verified at `bootstrap.sh:8-17` header (scope: `Account → Cloudflare R2 → Edit` + `User → API Tokens → Edit`). For this gdpr-override flow we need ONLY `R2 → Edit` (no token-edit scope, since we are NOT creating tokens); the User → API Tokens → Edit scope is only needed for *self-revoke* | Document scope as `Account → Cloudflare R2 → Edit` + `User → API Tokens → Edit` (the latter only for the self-revoke; trade-off accepted to keep the one-token flow) |
| "CF Lock Rules GET response carries `result.rules` array of objects with `enabled` + `condition.maxAgeSeconds`" | Confirmed by reading `main.test.sh:97-99` jq assertions + `object_lock.tf:31-40` PUT body shape | The GET → PUT round-trip is just `curl -fsS ... \| jq '.result' > /tmp/lock-snapshot.json` then PUT `--data @/tmp/lock-snapshot.json` for restore |

**Gap callout:** Empirical R2 Lock Rule edit-shape choice (Scope item 1 — three candidates) cannot be settled by static codebase reading alone; the rule-precedence semantics differ across the three candidates and the canonical CF docs need to be the source of truth. The plan picks the safest shape (Candidate A: `enabled:false` flip) for the following reasons enumerated under §Choice of Lock Rule Edit Shape, and prescribes a `--dry-run-cf` mode in the driver that operators can use to confirm the cycle on a synthetic test bucket before live invocation. If empirical R2 behavior diverges from Candidate A's expected semantics, the driver's `--shape=age-1s` and `--shape=narrow-prefix` modes give the operator a fallback without re-implementing.

## Canonical CF R2 Lock Rules API Contract (Research Insights)

**Source:** `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md` §12b — verbatim. Confirmed against `apps/cla-evidence/infra/object_lock.tf:31-86` and `apps/cla-evidence/infra/main.test.sh:91-110`.

### Endpoints

```text
GET  /accounts/{account_id}/r2/buckets/{bucket_name}/lock
PUT  /accounts/{account_id}/r2/buckets/{bucket_name}/lock
```

### Auth

`Authorization: Bearer <CF_ADMIN_TOKEN>` — the same one-hour CF admin token used in `bootstrap.sh:60-78`. Required scope: `Account → Cloudflare R2 → Edit`. **Self-revoke requires additional `User → API Tokens → Edit` scope** (mints the operator's own DELETE-permission against `/user/tokens/{id}`); the plan documents both in §7.1.

### Body Shape (PUT)

```jsonc
{
  "rules": [                            // load-bearing wrapper; bare array → HTTP 400
    {
      "id": "cla-evidence-10yr-retention",
      "enabled": true,                  // boolean; Shape A flips to false
      "prefix": "",                     // empty string = bucket-wide
      "condition": {
        "type": "Age",                  // one of "Age" | "Date" | "Indefinite"
        "maxAgeSeconds": 315360000      // only for type=Age; Shape B lowers to 1
      }
    }
  ]
}
```

### GET Response Shape

```jsonc
{
  "success": true,
  "result": {
    "rules": [ /* same per-rule shape as PUT body */ ]
  },
  "errors": [],
  "messages": []
}
```

The driver captures `response.result` (the rules array, wrapped) and re-emits it as `{"rules": <captured>}` for the PUT-restore. **Byte-equal restore** requires preserving field ordering, which jq does by default (`jq -c '.result'`).

### Error Modes Observed

- **HTTP 400** — body is a bare array instead of `{"rules":[...]}`. The wrapper key is load-bearing.
- **HTTP 401** — admin token missing `Account → R2 → Edit` scope, or token expired (1-hour TTL).
- **HTTP 404** — bucket name does not exist or token has no bucket-scoped access.
- **`success: false` with `errors:[...]`** — schema-level rejection (e.g., `condition.maxAgeSeconds` missing for `type:"Age"`).
- **`success: true` with malformed body** — verified mitigation: jq-assert `rule_count >= 1 && maxAgeSeconds floor` per `object_lock.tf:73-78` AND `main.test.sh:96-110`. The driver replicates this assertion on the GET response BEFORE proceeding to the PUT-disable step.

### Multi-Rule Precedence (UNVERIFIED)

CF docs cited at `object_lock.tf:8-10`: "rules without a prefix apply to all objects in the bucket". Multi-rule precedence (e.g., Shape C: broad-bucket rule + narrow-prefix override) is **NOT documented in the cited learning**. The plan flags this as a load-bearing unknown for `--shape=narrow-prefix`. Operator MUST exercise Shape C against a synthetic test bucket before the first live use, and the `--I-have-verified-precedence` flag is the gating ack.

---

## Choice of Lock Rule Edit Shape

The issue scope enumerates three candidate shapes for the temporary rule edit. The plan chooses **Candidate A (flip `enabled` false → DELETE → flip back true)** as the default, and ships the other two as alternate `--shape=` modes the operator can select if A fails empirically. Reasoning:

| Shape | Pros | Cons | Plan disposition |
|---|---|---|---|
| **(A) `enabled:false` flip** | Atomic semantic ("rule temporarily disabled"); the cleanest revert path (PUT-restore is byte-equal to the GET response's `result.rules`). Single key flipped; minimal surface for typos. | Brief window (sub-second on a single-operator workflow) where the rule is fully off and any concurrent bulk DELETE could race. Mitigation: the admin token is scoped to a single operator's CLI; no other writer has DELETE permission. | **Default.** `--shape=enabled-false` |
| **(B) Lower `maxAgeSeconds` to 1** | Narrower meaning ("rule still applies but to nothing past 1 second"); preserves the "rule is enabled" semantic. | Same window as (A); plus relies on R2 honoring `maxAgeSeconds:1` as an immediate-eligibility predicate (vs treating it as the floor for the next age tick). Adds a numeric-edit surface vs (A)'s boolean. | Available as `--shape=age-1s` fallback |
| **(C) Add narrow-prefix override rule** | Most surgical (only the offending key prefix is affected; broader bucket-default rule stays intact). | R2 multi-rule precedence is "longest matching prefix wins" (per CF docs); needs verification. Adds a `rules.length=2` window the post-restore `main.test.sh --live` does not currently assert against (asserts `rule_count >= 1`, not `== 1`). Mitigation: extend `main.test.sh --live` to also assert canonical `rule_count == 1`. | Available as `--shape=narrow-prefix` fallback; gated behind `--I-have-verified-precedence` flag |

**Why a single shape isn't sufficient:** the canonical CF R2 API surface is a `null_resource` + curl shim (per `object_lock.tf:42-86`) because the provider does not (yet) carry a typed resource for `PUT /accounts/{id}/r2/buckets/{name}/lock`. Empirical behavior of the three shapes is therefore the only ground truth, and we want a fallback if A fails on the live bucket. The dry-run test (`gdpr-override.test.sh`) covers all three shapes via stubbed curl; the live invocation defaults to (A) and the operator picks an alternate only if A is rejected.

## Files to Edit

- `knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md` — drop runbook-header stale banner (line 9); rewrite §7.1 (admin token mint — replace dashboard click-path with `gdpr-override.sh --help` and the operator's pre-flight checklist) and §7.3 (delete via Lock Rule edit — replace stale historical block with the tested driver invocation). Keep §7.2, §7.4 (tombstone), §7.5 (DPA log), §7.6 (revoke), §7.7 (next-month manifest) as-is — they remain operationally correct.
- `apps/cla-evidence/infra/main.test.sh` — extend `--live` mode to optionally assert `rule_count == 1` (current: `>= 1`) when `--strict-rule-count` flag is passed. The driver's post-restore verification uses `--live --strict-rule-count` to detect a leftover narrow-prefix rule from Shape C. Default `--live` semantics unchanged for backward compatibility with the bootstrap.

## Files to Create

- `apps/cla-evidence/scripts/gdpr-override.sh` — the tested driver. Flow: pre-flight (verify deps, verify env, verify Doppler auth, verify gh auth) → admin-token verify → GET current rule list → save snapshot → PUT modified list (per `--shape=`) → DELETE object via `doppler run -p soleur -c prd_cla -- aws s3api delete-object ...` → PUT-restore from snapshot → verify via `main.test.sh --live --strict-rule-count` → write tombstone via the same `doppler run` HMAC creds → self-revoke admin token. Each step is idempotent on retry. Modes: `--dry-run` (stub all network calls, print the planned sequence), `--shape=enabled-false|age-1s|narrow-prefix` (default `enabled-false`), `--help` (print operator one-pager). All sensitive material passed via env vars, never argv; secrets never echoed to stdout/stderr.
- `apps/cla-evidence/scripts/gdpr-override.test.sh` — dry-run test. Same stub-via-PATH pattern as `upload-bypass.test.sh` and `inspect.test.sh`. Cases:
    - `TS-OVERRIDE.a` — happy path Shape A: pre-flight passes; GET returns canonical 1-rule list; PUT flips `enabled:false`; DELETE returns 204; PUT-restore byte-equal to snapshot; `--live --strict-rule-count` passes; tombstone PUT returns 200; self-revoke returns 204. Exit 0.
    - `TS-OVERRIDE.b` — happy path Shape B (`--shape=age-1s`): same as (a), PUT body differs (`maxAgeSeconds:1`).
    - `TS-OVERRIDE.c` — happy path Shape C (`--shape=narrow-prefix --I-have-verified-precedence`): GET returns 1-rule list; PUT appends a narrow-prefix `maxAgeSeconds:1` rule; DELETE returns 204; PUT-restore returns to 1-rule list; verification passes.
    - `TS-OVERRIDE.d` — failure mode: GET returns `success:false` → driver aborts BEFORE any PUT. Tombstone is NOT written. Admin token IS still revoked. Exit 1.
    - `TS-OVERRIDE.e` — failure mode: DELETE returns 403 → driver attempts PUT-restore (best-effort); does NOT write tombstone; surfaces `::error::` annotation; admin token revoked; exit 2.
    - `TS-OVERRIDE.f` — failure mode: PUT-restore fails after a successful DELETE → driver writes a high-priority alert annotation (`::error::CRITICAL: lock rule restore failed; bucket WORM property may be void; manual restore required immediately`), does NOT self-revoke (operator needs the token), exits 3.
    - `TS-OVERRIDE.g` — missing required env (`CF_ADMIN_TOKEN`, `CF_ACCOUNT_ID`, `GDPR_REQUEST_REF`, `TARGET_KEY`, `PRIOR_SHA`) → exit 64 with `::error::usage:` matching the canonical Soleur convention.
    - `TS-OVERRIDE.h` — `--shape=narrow-prefix` without `--I-have-verified-precedence` → exit 64 with explicit "narrow-prefix shape requires precedence verification ack" guidance.
    - `TS-OVERRIDE.i` — tombstone schema-version assertion: the driver writes `schema_version: "1.0"`; if the operator-supplied `PRIOR_SHA` is empty/non-hex, exit 64 BEFORE any PUT.
    - `TS-OVERRIDE.j` — argv contains no secrets: `ps -ef`-equivalent check via `set -x` capture — the admin token value (NOT the env var name) must not appear in any rendered command. Test sets `CF_ADMIN_TOKEN="bearer-secret-fingerprint-do-not-leak"` and `R2_CLA_EVIDENCE_SECRET="hmac-secret-fingerprint-do-not-leak"`, then asserts neither fingerprint appears in `BASH_XTRACEFD`-redirected trace output. Anchoring on the value (not the env var name) catches both argv-leak AND `echo "$CF_ADMIN_TOKEN"`-class regressions.
    - `TS-OVERRIDE.k` — bearer-vs-HMAC separation: when the driver's stub-curl is invoked for the `/r2/buckets/.../lock` PUT, env contains `CF_ADMIN_TOKEN`; when the stub-aws is invoked for `s3api delete-object`, env does NOT contain `CF_ADMIN_TOKEN` (only `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` from `doppler run -p soleur -c prd_cla --`). Asserts the trap from `cla-evidence-sidecar §12c` cannot recur.
- `apps/cla-evidence/scripts/fixtures/lock-rule-canonical.json` — fixture snapshot of the canonical rule list (`{rules:[{id:"cla-evidence-10yr-retention",enabled:true,prefix:"",condition:{type:"Age",maxAgeSeconds:315360000}}]}`). Used by `gdpr-override.test.sh` as the stubbed GET response and the asserted PUT-restore body.

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in \
  "apps/cla-evidence/scripts/gdpr-override.sh" \
  "apps/cla-evidence/scripts/gdpr-override.test.sh" \
  "apps/cla-evidence/scripts/fixtures/lock-rule-canonical.json" \
  "apps/cla-evidence/infra/main.test.sh" \
  "knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md"; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Result at plan-write time: **None.** No open code-review scope-outs reference any of the planned target files. The runbook is also untouched by any open code-review item.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — driver exists & is executable.** `test -x apps/cla-evidence/scripts/gdpr-override.sh` returns 0.
- [ ] **AC2 — `--help` documents the modes.** `bash apps/cla-evidence/scripts/gdpr-override.sh --help` exits 0; stdout includes substrings: `--shape=enabled-false`, `--shape=age-1s`, `--shape=narrow-prefix`, `--dry-run`, `CF_ADMIN_TOKEN`, `GDPR_REQUEST_REF`, `TARGET_KEY`, `PRIOR_SHA`. (Verifier uses `grep -F` over the help output; substrings chosen to avoid punctuation breaking per sharp-edge "ci-sentinel-paren-safety-substring-match-against-canonical-prose".)
- [ ] **AC3 — dry-run test passes.** `bash apps/cla-evidence/scripts/gdpr-override.test.sh` exits 0. All 11 cases (a-k) emit `PASS:` lines; no `FAIL:` lines on stderr.
- [ ] **AC4 — runbook §7.1 + §7.3 are rewritten.** All three stale markers — `STALE`, `--bypass-governance-retention`, `Bypass Governance Retention` — have zero matches in `knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md`. Verifier: `grep -cE 'STALE|--bypass-governance-retention|Bypass Governance Retention' knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md` returns `0`. (The historical `<details>` blocks are dropped entirely — keeping them invites operators to read past the new procedure and try the deprecated form. Provenance lives in PR #3920's git history.)
- [ ] **AC5 — runbook header banner is removed.** The string `§7 admin-override procedure under revision (2026-05-16)` no longer appears in the runbook.
- [ ] **AC6 — runbook §7.1 includes the driver invocation verbatim.** `grep -F "bash apps/cla-evidence/scripts/gdpr-override.sh" knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md` returns ≥ 1 match (the operator paste-line; substring chosen to span no punctuation boundary).
- [ ] **AC7 — runbook §7.3 names the canonical PUT-restore verification.** `grep -F "main.test.sh --live --strict-rule-count" knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md` returns ≥ 1 match.
- [ ] **AC8 — legal-prose §3.4 sub-bullet (3) is unchanged.** `diff <(awk '/^### 3\.4/{flag=1; next} /^### 3\.5/{flag=0} flag' docs/legal/gdpr-policy.md) <(awk '/^### 3\.4/{flag=1; next} /^### 3\.5/{flag=0} flag' plugins/soleur/docs/pages/legal/gdpr-policy.md)` shows no semantic divergence on the admin-override prose (link-format differences acceptable; the "tombstone protocol" sentence + the "temporarily updating the bucket lock-rule list" sentence must appear in both). Note: awk flag-pattern over self-matching `/start/,/end/` ranges per sharp-edge "plan-ac-verification-commands-awk-self-match-and-marker-conjunction".
- [ ] **AC9 — `main.test.sh --live --strict-rule-count` is recognised but does not regress default behavior.** `bash apps/cla-evidence/infra/main.test.sh --strict-rule-count` (without `--live`) prints a no-op message AND exits 0; `bash apps/cla-evidence/infra/main.test.sh --bogus-flag` still exits 64. (Backward-compat: existing `bootstrap.sh:200` invocation of `main.test.sh --live` continues to pass without the new flag.)
- [ ] **AC10 — fixture exists and is valid JSON.** `jq -e '.rules[0].condition.maxAgeSeconds == 315360000 and .rules[0].enabled == true and .rules[0].prefix == ""' apps/cla-evidence/scripts/fixtures/lock-rule-canonical.json` returns 0.
- [ ] **AC11 — no new dependencies introduced.** `git diff --stat main -- package.json plugins/*/package.json apps/*/package.json` shows no edits to any `package.json`. Tooling used: `bash`, `jq`, `curl`, `aws`, `doppler`, `gh`, `openssl` — all already preflighted by `bootstrap.sh:55`.
- [ ] **AC12 — secrets never echoed.** `grep -nE 'echo.*CF_ADMIN_TOKEN|echo.*R2_CLA_EVIDENCE_SECRET' apps/cla-evidence/scripts/gdpr-override.sh` returns no matches (the driver MUST NOT echo any secret; the test asserts this and CI repeats the assertion).
- [ ] **AC13 — driver script lints clean.** Both `bash -n apps/cla-evidence/scripts/gdpr-override.sh` (parse-only validation) and `shellcheck apps/cla-evidence/scripts/gdpr-override.sh apps/cla-evidence/scripts/gdpr-override.test.sh` exit 0. The `bash -n` step catches syntax errors that shellcheck tolerates; matches the convention used in `apps/cla-evidence/scripts/r2-conditional-put.sh` + `apps/cla-evidence/scripts/sentinel-pr.sh`.

- [ ] **AC13b — cross-artifact drift gate (per 2026-05-16 learning).** After the runbook rewrite, `git grep -nl 'Object Lock Governance\|--bypass-governance-retention\|Bypass Governance Retention' knowledge-base/engineering/ops/runbooks/ docs/ apps/ plugins/ | grep -v knowledge-base/project/learnings/ | grep -v knowledge-base/project/plans/ | grep -v knowledge-base/project/specs/` returns ZERO matches. (Excluded paths preserve historical record: learnings, plans, and specs may legitimately reference the deprecated vocabulary while explaining migration history.) If any path is returned, the vocabulary refactor has leaked into a sibling operational artifact and must be aligned in this PR per `2026-05-16-legal-prose-vocabulary-refactors-implicate-operational-runbooks.md`.
- [ ] **AC14 — Ref provenance.** PR body contains `Closes #3924` (NOT `Fixes #3924`; the issue closes at merge because the deliverable is the driver + runbook, not a post-merge operator action).

### Post-merge (operator, only when a real Art. 17 erasure lands)

- [ ] **AC15 — first live execution.** When the first real GDPR Art. 17 erasure request lands AND the CLO confirms the Art. 17(3)(e) carveout does not apply, the designated operator runs `bash apps/cla-evidence/scripts/gdpr-override.sh ...` (per the rewritten §7.1) and confirms (a) the offending object is deleted, (b) the tombstone is written, (c) the rule list is restored to canonical (`rule_count==1`, `maxAgeSeconds==315360000`), (d) the admin token is revoked. Operator captures the run log to the incident ticket. **Automation: not feasible** because the trigger is an external legal request and the deletion of a specific object key requires CLO scope-confirmation per `hr-menu-option-ack-not-prod-write-auth`.

## Implementation Phases

### Phase 0 — Preconditions (Operator Verification)

- [ ] **P0.1 — branch + worktree.** Already on `feat-one-shot-3924` in `.worktrees/feat-one-shot-3924`.
- [ ] **P0.2 — tools present.** Re-confirm `bash`, `jq`, `curl`, `aws`, `doppler`, `gh`, `openssl`, `shellcheck` are on PATH. (`shellcheck` for AC13; the others are already preflighted by `bootstrap.sh`.)
- [ ] **P0.3 — verify the canonical rule shape.** `cat apps/cla-evidence/infra/object_lock.tf:31-40` matches `{id,enabled,prefix,condition:{type,maxAgeSeconds}}`. Confirm `MIN_LOCK_SECONDS=315360000` at `main.test.sh:33`.
- [ ] **P0.4 — verify no in-flight conflicting PR.** `gh pr list --state open --search "cla-evidence runbook"` returns nothing scope-overlapping.

### Phase 1 — RED tests

- [ ] **P1.1** Write `apps/cla-evidence/scripts/fixtures/lock-rule-canonical.json` with the canonical 1-rule body.
- [ ] **P1.2** Write `apps/cla-evidence/scripts/gdpr-override.test.sh` cases (a) through (k). All cases reference the not-yet-created `gdpr-override.sh`. Run the suite — expect every case to FAIL with `gdpr-override.sh: No such file or directory`. Confirm RED.
- [ ] **P1.3** Verify (`bash apps/cla-evidence/scripts/gdpr-override.test.sh`) — exit non-zero, output contains expected `FAIL` lines. Commit RED tests with message `test(cla-evidence): RED gdpr-override dry-run suite (#3924)`.

### Phase 2 — GREEN driver

- [ ] **P2.1** Write `apps/cla-evidence/scripts/gdpr-override.sh` following the bootstrap.sh template (color helpers, `set -euo pipefail`, `step "[N/M]"` progress lines).
- [ ] **P2.2** Implement: arg parsing (`--help`, `--dry-run`, `--shape=`, `--I-have-verified-precedence`), env validation, dep check, admin-token verify (curl to `/user/tokens/verify`, capture `result.id` for self-revoke), GET lock rules + snapshot to `$WORK/snapshot.json`.
- [ ] **P2.3** Implement: PUT modified rules per `--shape=` (default Shape A: jq-mutate `rules[0].enabled = false`); shape selectors via case statement; explicit refusal for Shape C without ack flag.
- [ ] **P2.4** Implement: DELETE object via `aws --endpoint-url "$R2_CLA_EVIDENCE_ENDPOINT" s3api delete-object --bucket "$R2_CLA_EVIDENCE_BUCKET" --key "$TARGET_KEY"` (NO `--bypass-governance-retention`; rule is temporarily disabled). Wrap with `doppler run -p soleur -c prd_cla -- ...` for HMAC creds (NOT the admin token).
- [ ] **P2.5** Implement: PUT-restore (byte-equal to `$WORK/snapshot.json`); verify via `bash apps/cla-evidence/infra/main.test.sh --live --strict-rule-count`.
- [ ] **P2.6** Implement: tombstone PUT using the same `doppler run -p soleur -c prd_cla --` HMAC envelope and the existing tombstone schema from runbook §7.4. Tombstone body: `{schema_version:"1.0", deleted_at, admin_actor, gdpr_request_ref, prior_object_sha, override_reason}`.
- [ ] **P2.7** Implement: self-revoke admin token via `curl -X DELETE` (matches `bootstrap.sh:235-245`); warn-don't-fail on revoke error (operator can manually revoke). EXCEPTION: do NOT self-revoke if PUT-restore failed (`TS-OVERRIDE.f`); the operator needs the token to manually restore.
- [ ] **P2.8** Extend `apps/cla-evidence/infra/main.test.sh` to recognise `--strict-rule-count`; when present AND `LIVE_MODE=1` AND `rule_count != 1`, FAIL with explicit message. When `--strict-rule-count` is alone (no `--live`), no-op exit 0.
- [ ] **P2.9** Run `bash apps/cla-evidence/scripts/gdpr-override.test.sh` until all 10 cases PASS. Run `shellcheck` (AC13). Commit GREEN with `feat(cla-evidence): gdpr-override.sh driver + dry-run suite (#3924)`.

### Phase 3 — Runbook rewrite

- [ ] **P3.1** Read `knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md` head to tail. Note the existing §7.2/§7.4/§7.5/§7.6/§7.7 prose — preserve verbatim.
- [ ] **P3.2** Drop the runbook-header `> §7 admin-override procedure under revision (2026-05-16).` block (lines ~7-9).
- [ ] **P3.3** Rewrite §7.1 — replace dashboard-click-path historical block with: (a) mint scope (`Account → R2 → Edit` + `User → API Tokens → Edit`), (b) export the token to `CF_ADMIN_TOKEN`, (c) one-line driver invocation example with copy-pasteable env-var setup, (d) `--help` reference.
- [ ] **P3.4** Rewrite §7.3 — replace stale historical block with: the canonical driver invocation (`doppler run -p soleur -c prd_cla -- bash apps/cla-evidence/scripts/gdpr-override.sh --shape=enabled-false --target-key=signatures/<sha>.json --gdpr-request-ref=<ticket> --prior-sha=<sha> --override-reason="..."`), plus a 5-bullet "what the driver does" enumeration matching the actual flow.
- [ ] **P3.5** Keep §7.2 (locate offending object), §7.4 (tombstone protocol — already correct), §7.5 (DPA log), §7.6 (revoke), §7.7 (manifest verify) verbatim.
- [ ] **P3.6** Re-verify legal-prose mirror parity (AC8): run the awk-flag diff command; expect zero semantic divergence on the admin-override sub-bullet.
- [ ] **P3.7** Commit `docs(runbook): rewrite cla-evidence §7 admin-override for R2 Lock Rules (#3924)`.

### Phase 4 — Verification

- [ ] **P4.1** Re-run `bash apps/cla-evidence/scripts/gdpr-override.test.sh` (regression).
- [ ] **P4.2** Run all ACs in order (AC1 → AC14). All pass.
- [ ] **P4.3** Run `shellcheck apps/cla-evidence/scripts/gdpr-override.sh apps/cla-evidence/scripts/gdpr-override.test.sh`.
- [ ] **P4.4** `gh pr create` with body containing `Closes #3924`, the Phase-0/1/2/3 commit list, and the AC checklist (all checked). Add labels `domain/legal`, `domain/engineering`, `type/chore`, `priority/p2-medium`, `follow-through`.

## Test Strategy

- **Framework:** plain `bash` with PATH-stubbed binaries (`curl`, `aws`, `doppler`, `gh`). Matches the existing convention at `apps/cla-evidence/scripts/upload-bypass.test.sh`, `inspect.test.sh`, `upload-evidence.test.sh`, `sentinel-pr.test.sh`, `timestamp.test.sh`. No new dependency.
- **Fixtures:** `apps/cla-evidence/scripts/fixtures/lock-rule-canonical.json` is the GET response and the PUT-restore body. The deletion target is a synthetic `signatures/<placeholder-sha>.json` — NEVER a real signer key (per `cq-test-fixtures-synthesized-only`).
- **Determinism:** All network IO is stubbed; no live CF/R2/Doppler/gh calls inside the test. Reusable across local dev and CI.
- **Negative cases:** TS-OVERRIDE.d-f cover the three load-bearing failure modes (GET error pre-PUT, DELETE 403, PUT-restore failure). TS-OVERRIDE.g-h cover usage errors. TS-OVERRIDE.j covers the secret-leak invariant (token not in process argv).
- **CI integration:** Add `bash apps/cla-evidence/scripts/gdpr-override.test.sh` to whatever runs the sibling test files (`infra-validation.yml` or the dedicated `cla-evidence` job — verify the existing pattern at plan-execution time). Cost: negligible; the test is pure local bash.

## Sharp Edges

- **Tombstone after a failed restore is worse than no tombstone.** If PUT-restore fails post-DELETE, the bucket is in a degraded state (rule list disabled or narrow-prefix leftover); writing a tombstone *and* leaving the rule degraded would silently fold the incident into the next monthly RFC 3161 manifest and obscure the operator's need to act. The driver must NOT write the tombstone if restore fails — only after both DELETE and restore succeed. TS-OVERRIDE.e + TS-OVERRIDE.f verify this ordering.
- **Self-revoke must not run if restore failed.** Operator needs the token for manual restore. TS-OVERRIDE.f asserts the self-revoke is skipped.
- **`--shape=narrow-prefix` requires R2-precedence verification.** R2 multi-rule precedence semantics are documented as "longest matching prefix wins" but the live behavior on a real bucket has not been verified in this codebase. The `--I-have-verified-precedence` flag is a tripwire — operator must explicitly acknowledge they have tested the shape on a synthetic bucket before live use. TS-OVERRIDE.h tests this gate.
- **Lock-rule edit window race.** Under Shape A or B, there is a sub-second window where the rule is fully off (A) or maxed at 1s (B). Mitigation: the admin token is single-operator; no concurrent writer has DELETE permission via R2 IAM. Reviewers may ask whether to widen the protocol to a per-key fine-grained Lock Rule edit (Shape C); the answer is "yes when R2 multi-rule precedence is verified — until then, A is the canonical default."
- **`main.test.sh --strict-rule-count` is the only consumer.** Adding a flag to a shared verifier is a contract change; explicit no-op behavior when `--strict-rule-count` is passed without `--live` keeps the gate predictable for any future caller. AC9 covers backward compat.
- **Empty/non-hex `PRIOR_SHA` breaks tombstone schema.** The tombstone's `prior_object_sha` field has no enforced schema at the bucket; a malformed value would silently land. TS-OVERRIDE.i asserts the driver validates `PRIOR_SHA` matches `^[0-9a-f]{64}$` before any PUT.
- **No `Closes #3924` in PR title.** Per `wg-use-closes-n-in-pr-body-not-title-to`, use `Closes #3924` in the PR body, not title. The title is `feat(cla-evidence): R2 Lock Rules GDPR override driver (#3924)` or similar.
- **The trigger is rare; the cost of staleness is high.** This procedure may not fire for months; when it does, the operator needs deterministic execution. The dry-run test is the only routinely-exercised verification; treat it as the canonical contract. If the R2 Lock Rules API changes shape, the test will pass while the live invocation will fail — same drift class as the original §7.3 staleness. Mitigation: file a follow-up to add a quarterly live sentinel that exercises the driver against a synthetic-test bucket (scope-out — outside this PR; track as a separate issue if the team wants the safety net).
- **AGENTS.md sharp-edges applied:** awk flag-based section extraction (AC8) per `2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md`. ShellCheck for the driver. Substring-grep verifiers (AC2/AC6/AC7) span no punctuation boundary in the source per `2026-05-15-ci-sentinel-paren-safety-substring-match-against-canonical-prose.md`.
- **ERR-trap recovery is load-bearing.** Operator-Ctrl-C between PUT-disable and PUT-restore leaves the bucket in a degraded state (rule disabled, retention floor void). The driver MUST install `trap '_cleanup_partial_override "$snapshot"' ERR` BEFORE the PUT-disable AND clear it (`trap - ERR`) only after PUT-restore succeeds. Pattern verbatim from `apps/cla-evidence/scripts/sentinel-pr.sh:167-192`. `_cleanup_partial_override` attempts a best-effort restore from `$snapshot`, surfaces a high-priority `::error::CRITICAL` annotation, and does NOT self-revoke the admin token (operator needs it). TS-OVERRIDE.f covers this code path via a stub that simulates an ERR mid-flow.
- **Bearer-token vs HMAC-key trap (cla-evidence-sidecar §12c).** The DELETE step uses the operator's HMAC pair from Doppler `prd_cla` (32-char access-key + 64-char SHA-256-derived secret), NEVER the 53-char Cloudflare API bearer token. Mixing them up reproduces the "Credential access key has length 53, should be 32" R2 error that bit #3919's first cron run. Driver invokes the DELETE via `doppler run -p soleur -c prd_cla -- aws s3api delete-object ...` (HMAC pair comes from Doppler env); the bearer admin token is exposed ONLY to the `curl` invocations for `/r2/buckets/.../lock` (rule-list edit) and `/user/tokens/{id}` (self-revoke). TS-OVERRIDE.k (added below) asserts the DELETE step does NOT have `CF_ADMIN_TOKEN` in its env.

## Non-Goals

- **Not adding a typed Terraform resource for R2 Lock Rules.** The provider does not yet ship one; tracked separately. The driver uses the same `curl + jq` envelope as `object_lock.tf:42-86`.
- **Not changing the tombstone schema.** §7.4 is operationally correct; the schema-version third-consumer assertion stays at `"1.0"` per learning #18.
- **Not changing the legal prose at `docs/legal/gdpr-policy.md` §3.4.** AC8 verifies the prose still matches the operational procedure; no edit needed because PR #3920 already aligned them.
- **Not adding a CF account-admin token to Doppler `prd_cla`.** The admin token is operator-minted per-incident with 1-hour TTL (matches `bootstrap.sh` pattern); never persisted.
- **Not adding a live sentinel test.** Listed as a sharp-edge follow-up; not in scope for this PR.
- **Not handling `condition.type: "Indefinite"` rules.** The current bucket uses `Age`; future migrations to `Indefinite` would invalidate Shape B (`age-1s`) but Shape A (`enabled:false`) continues to work. If the canonical rule list ever migrates to a multi-type or Indefinite shape, the driver's stub fixture (`lock-rule-canonical.json`) must be refreshed and an additional test case added — but this is out of scope until the migration lands.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| **Single-shape driver (only `enabled:false`).** | Brittle if A fails empirically; operator would have no scripted fallback. Cost of supporting three shapes via `--shape=` flag is ~15 LoC of case-statement branching. |
| **Persist admin token in Doppler `prd_cla`.** | Violates the "one-hour TTL, mint-per-incident" pattern; would broaden blast radius significantly and conflict with `hr-menu-option-ack-not-prod-write-auth`. |
| **Write the tombstone first, then DELETE.** | Inverted ordering — if DELETE fails after tombstone PUT, the chain shows "object H tombstoned but still present" which is operationally incoherent. Tombstone-after-DELETE is the load-bearing invariant from learning §3. |
| **Don't validate `PRIOR_SHA` format.** | Tombstone with empty/malformed SHA breaks the third-consumer schema assertion at `inspect-evidence.sh` (exit 3). Validating at driver entry is cheaper than discovering at the next inspect run. |
| **Make `--strict-rule-count` the default in `main.test.sh --live`.** | Would break the bootstrap invocation if a future migration ever introduces a multi-rule canonical (e.g., one rule for `signatures/`, another for `tombstones/`). Keep it opt-in. |
| **Embed the driver inside `bootstrap.sh`.** | Conflates one-time bootstrap with per-incident operator action. Separation matches the `inspect-evidence.sh` / `upload-evidence.sh` / `upload-bypass.sh` per-purpose script convention. |
| **Use the Cloudflare TF provider's `cloudflare_r2_bucket_lock_configuration` to edit the rule from a one-off Terraform run.** | The provider's resource is for object-key-level rules, not bucket-default; `object_lock.tf` documents this gap explicitly. Using TF for a one-off edit also pollutes state and requires the admin token to be passed through Terraform — broader blast radius than a single-purpose bash script. |

## Rollback

If the driver ships and a future R2 API change breaks Shape A:

1. Operator falls back to `--shape=age-1s` or `--shape=narrow-prefix --I-have-verified-precedence`.
2. If all three shapes fail, the operator can still execute the procedure manually using the curl commands embedded in §7.3 prose — those are documented for transparency, not just as driver internals.
3. The dry-run test surfaces shape changes immediately when re-run against a stub adapted from real CF response captures.

If the driver is found to have a critical bug in production:

1. Revert the PR (single commit reversal restores §7.3 to the stale-banner state from PR #3920).
2. The stale banner explicitly tells operators to coordinate with CLO + cla-evidence infra owner — the legal SLA still applies but execution is ad-hoc.
3. File a follow-up plan with the failure-mode learning captured.

## Skill Description Budget Headroom

This plan does NOT edit any `plugins/soleur/skills/*/SKILL.md description:` field. The 1800-word cumulative cap check (per `cq-skill-description-budget-headroom`) is not load-bearing for this PR. No baseline measurement required.

## AGENTS.md Rule Application

- `hr-when-a-plan-specifies-relative-paths-e-g` — every file path in this plan is verified against `git ls-files` or via direct read at plan-write time.
- `hr-weigh-every-decision-against-target-user-impact` — `## User-Brand Impact` filled with concrete artifact + threshold.
- `hr-gdpr-gate-on-regulated-data-surfaces` — the plan touches the operational runbook for a regulated-data surface; gdpr-gate skip rationale: the plan does NOT add a new processing activity, does NOT change the lawful basis, does NOT touch the lawful-basis prose at §3.4. It rewrites the *operational procedure* that implements an existing Art. 17 erasure flow already disclosed at §3.4 sub-bullet (3). The skip is consistent with Phase 2.7's "Skip silently if no regulated-data surface is touched AND none of the (a)-(d) triggers fire" guidance.
- `cq-test-fixtures-synthesized-only` — fixture uses placeholder SHA (`<placeholder-sha>` / `abc123...`), never a real signer key.
- `wg-use-closes-n-in-pr-body-not-title-to` — `Closes #3924` in PR body, not title.
- `wg-before-every-commit-run-compound-skill` — applied per commit.
- `rf-review-finding-default-fix-inline` — review findings folded in unless explicit DEFER with rationale.

## Domain Review

**Domains relevant:** engineering, legal-ops.

- **Engineering domain leader (CTO):** review focuses on the `gdpr-override.sh` script's idempotency and the tombstone-ordering invariant. Bootstrap.sh's self-revoke pattern is the precedent; the driver inherits it. Phase 2.5 carry-forward — sufficient codebase precedent (`bootstrap.sh`, the three sibling `upload-*` scripts, `inspect-evidence.sh`) covers the engineering surface.
- **Legal domain leader (CLO):** review focuses on whether the runbook prose at §7.1/§7.3 (post-rewrite) still maps cleanly to the legal-prose at `docs/legal/gdpr-policy.md` §3.4 sub-bullet (3). AC8 enforces this at PR-time. Phase 2.5 finding: the legal prose was already rewritten in PR #3920; this PR's runbook rewrite is a downstream alignment, not a new legal claim. CLO sign-off is not required at plan time (threshold is `aggregate pattern`, not `single-user incident`).
- **Product (no relevance):** no user-facing UI change.
- **Other domains:** not relevant.

### Product/UX Gate

Not applicable — no user-facing UI change, no new flow, no copy.

## Research Insights (consolidated)

- **Bootstrap admin-token pattern.** `apps/cla-evidence/infra/bootstrap.sh:60-71` (verify) + `:235-247` (self-revoke). Adopt verbatim.
- **R2 Lock Rules canonical shape.** `apps/cla-evidence/infra/object_lock.tf:31-40` (`local.lock_rule`). Single source of truth.
- **`main.test.sh --live` post-apply gate.** `apps/cla-evidence/infra/main.test.sh:91-110`. Reusable for post-restore verification.
- **PATH-stub test convention.** `apps/cla-evidence/scripts/upload-bypass.test.sh:35-55`, `inspect.test.sh:30-55`. Reusable shape.
- **Tombstone schema.** Runbook §7.4 — `{schema_version:"1.0", deleted_at, admin_actor, gdpr_request_ref, prior_object_sha, override_reason}`. Third consumer-boundary per learning `2026-05-04-cla-evidence-sidecar-pattern.md` §3.
- **R2 4xx classification.** Learning `2026-05-04-cla-evidence-sidecar-pattern.md` §5. 412 ≠ other 4xx; 5xx/429 retry with backoff; 4xx ≠ 412 fast-fail. The override driver reuses this classification for the DELETE path.
- **Sharp edges absorbed:** awk self-match (sharp-edge 2026-05-15); paren-safety substring (sharp-edge 2026-05-15); CLI-form-verification gate (#2566 — see AC2 substring choice); secrets-never-in-argv (sharp-edge applied to AC12 + TS-OVERRIDE.j).

## Provenance

- PR #3920 — created the runbook-vs-policy drift; added stale banners. (`gh pr view 3920` confirms title alignment.)
- Issue #3924 — this PR closes it.
- Multi-agent review finding #2 from PR #3920 (git-history-analyzer) — origin of this work.
- Learning `2026-05-04-cla-evidence-sidecar-pattern.md` §7 + §12 — the tombstone protocol + the R2 Lock Rules migration context.
- Learning `2026-03-21-terraform-state-r2-migration.md` — earlier R2 work context.
