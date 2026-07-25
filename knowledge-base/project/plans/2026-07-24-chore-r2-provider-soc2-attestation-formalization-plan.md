---
title: "chore(encryption-posture): formalize named Cloudflare SOC 2 Type II at-rest attestation across the three R2 rows"
date: 2026-07-24
type: chore
issue: 6896
parent_issue: 6893
context_issue: 6588
branch: feat-one-shot-6896-r2-soc2-attestation
lane: cross-domain
brand_survival_threshold: aggregate pattern
adr: ADR-139, ADR-140
status: draft
---

# chore(encryption-posture): formalize the named Cloudflare SOC 2 Type II at-rest attestation on the three R2 rows

## Enhancement Summary

**Deepened on:** 2026-07-24
**Sections enhanced:** grounded during planning (Layer A script fully read, test fixtures, audit doc, live WebFetch/WebSearch, fable advisor consult) — proportionate deepening for a data-file plan, not a 40-agent fan-out (YAGNI).
**Deepen-plan mandatory gates:** 4.6 User-Brand Impact ✅, 4.7 Observability ✅, 4.8 PAT-shaped ✅ (none), 4.9 UI-wireframe ✅ (skip, no UI), 4.10 Encryption Posture ✅ — all PASS.

### Key improvements folded in from the fable advisor consult
1. **Scope authority = issue #6896's BODY** (names the 3 R2 surfaces), not audit-doc line 74's all-7 over-grouping. B2 re-pointing *is* the correction of that doc drift → reframe the PR as "body-scoped close + audit-doc mis-grouping fix" so no reviewer relitigates B1.
2. **`live_verification` must stay `unavailable:<reason>`, never `"available"`** — a named, NDA-gated SOC 2 report is an *attestation citation*, not a live probe. This is the single highest-leverage correction (overclaim a SOC 2-literate reviewer would catch).
3. **Verify R2 is in Cloudflare's SOC 2 scope** before asserting `Cloudflare-R2-SOC2-Type-II`; downgrade to company-level `Cloudflare-SOC2-Type-II` if only that is confirmable.

### New considerations discovered
- Layer A already **PASSES** today (the placeholder is not a gate failure — `live_verification` is only schema-validated). Deliverable is *attestation accuracy*, not un-breaking a red gate.
- The `tracked #6896` placeholder is on **7** rows (3 R2 + 4 non-R2), not 3 — driving the B2 re-point + new tracking issue.
- `retrieved_on = today` means Layer A forces an annual re-fetch by design (~1yr FAIL is expected, not a bug — note in PR body).

### Research Insights (grounding evidence)
- **Layer A mechanics** (`scripts/lint-encryption-posture.py`): `check_provider_managed` requires a non-empty attestation after `provider-managed:`, a non-boilerplate `mechanism+evidence` (ban-list: `encrypted by default` / `provider handles` / `the provider handles it`), a present `attestation_url`, and a `retrieved_on` ≤365d (`STALE_ATTESTATION_DAYS=365`). `live_verification` is validated only by `_validate_store` against `^(available|unavailable:.+)$` — never a sweep FAIL.
- **Canonical shape from the repo's own test fixtures** (`lint-encryption-posture.test.sh:315` PASS case): `mechanism: "provider-managed:Cloudflare-R2-SOC2-Type-II"`, `attestation_url: "https://www.cloudflare.com/trust-hub/compliance-resources/soc-2/"`, and a fully-formalized provider row *still* keeps `live_verification: "unavailable:<reason>"` (fixture TS-5). Directly corroborates advisor point 2.
- **Attestation URLs verified live (2026-07-24):** the public SOC 2 page (`cloudflare.com/trust-hub/compliance-resources/soc-2/`) names AICPA SOC 2 Type II (Security/Confidentiality/Availability, report under NDA); R2 AES-256-GCM at rest is documented at `developers.cloudflare.com/r2/reference/data-security/`. /work re-confirms + pins the retrieval date.
- **No test regression risk:** no test asserts the *real* ledger content (fixtures are self-contained; `lint-encryption-posture.py` is unchanged). Changing the R2 mechanism strings to the `Cloudflare-R2-SOC2-Type-II` shape aligns with the existing PASS fixtures.
- **Live citations re-verified:** #6896, #6893, #6588 all OPEN; labels `priority/p3-low`, `domain/engineering`, `type/security` all exist.

## Overview

The audit PR (#6885) seeded the encryption-posture ledger (`scripts/encryption-posture-ledger.json`)
with **provisional** rows for the three Cloudflare R2 surfaces. Each carries
`mechanism: "provider-managed:cloudflare-r2-default-aes256"`, an `attestation_url` pointing only at
Cloudflare's **developer data-security documentation** (`developers.cloudflare.com/r2/reference/data-security/`),
and a placeholder `live_verification: "unavailable:attestation formalization … pending; tracked #6896"`.

Issue **#6896** closes when those three rows cite a **named at-rest attestation** — Cloudflare's public
**AICPA SOC 2 Type II** (Security / Confidentiality / Availability), citable without an NDA from the
Cloudflare Trust Hub — with `name + URL + current retrieval date`, and the `tracked #6896` placeholder
retired. The three surfaces (issue-body-scoped) are:

1. `cloudflare_r2_bucket.cla_evidence` — `apps/cla-evidence/infra/bucket.tf:1` (CLA-evidence bucket).
2. `cloudflare_r2_bucket.workspaces_luks_header` — `apps/web-platform/infra/workspaces-luks-header.tf:40` (LUKS-header escrow).
3. `r2.terraform_state_backend` — the `backend "s3"` R2 bucket `soleur-terraform-state` (`apps/web-platform/infra/main.tf:2-6`); a `non_iac_stores` catalog row.

This is a **substantive / honest-close** deliverable, **not** a gate fix: Layer A
(`lint-encryption-posture.py --repo-sweep`) already **PASSES** today (14 stores, 0 failing) — the
provisional rows satisfy every mechanical check. `live_verification` is only *schema-validated*
(`^(available|unavailable:.+)$`), never a sweep FAIL trigger. So the value of this change is the named
attestation itself (feeding the #6893 claim-unlock gate that governs external "encrypted" copy) and a
clean close of #6896.

This plan **applies** ADR-139 / ADR-140; it makes no new architectural decision.

## Research Reconciliation — Spec vs. Codebase

| Premise (from parent's VERIFIED CURRENT STATE) | Reality found in repo | Plan response |
|---|---|---|
| "THREE R2 rows carry the `tracked #6896` placeholder." | The **identical** placeholder is on **SEVEN** rows: the 3 R2 rows **plus** `supabase.prd`, `supabase.inngest`, `doppler.secrets`, `betterstack.logs` (ledger lines 163–247). | Formalize only the **3 R2 rows** (per #6896's issue **body**, which names exactly the two `cloudflare_r2_bucket` resources + the R2 state backend). Re-point the 4 non-R2 rows so #6896 closes honestly — see Decision below. |
| #6896 == R2 only (issue title). | The repo's own audit doc `encryption-posture-audit-2026-07-23.md:74` **defines** "#6896 (provider-managed attestations, P3)" and its table (lines 40–45) stamps **all 7** provider rows with #6896. | The all-7 stamp is **doc drift** (over-grouping). #6896 closes against its **body** (3 R2 surfaces). The audit-doc mis-grouping is corrected as part of this PR. |
| "Layer A FAILs a `retrieved_on` older than 365 days" → placeholder is the open work / gate risk. | Confirmed the 365-day rule (`check_provider_managed`, `STALE_ATTESTATION_DAYS=365`), **but** the current rows already PASS (retrieved_on `2026-07-24`). `live_verification` is not a sweep check. | Set `retrieved_on` to the **current** verification date; keep the rows PASSING. The deliverable is the *named SOC 2 attestation*, not un-breaking a red gate. |
| "Clear the `live_verification` placeholder." | The ledger convention: `"available"` means a **live probe exists** (e.g. `hcloud_volume.workspaces_luks`); provider rows have no customer-side probe (test fixture TS-5 keeps `unavailable:<reason>`). | Do **NOT** set `available` (a SOC 2 report is an attestation *citation*, not a live verification — nobody read the NDA-gated report). Rewrite the **reason**, dropping `#6896`/`pending`. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing directly; the failure surface is
the encryption-posture ledger — either Layer A turns red in CI (blocking merges of the infra roots), or
the ledger cites an attestation Cloudflare does not actually hold / does not cover R2, which would let a
future external "encrypted at rest" claim rest on an over-stated citation (the #6588 claim-vs-reality
class this whole system exists to prevent).

**If this leaks, the user's data / workflow / money is exposed via:** no new exposure vector — this
change edits public attestation *metadata* about existing R2 buckets; it moves no user data and opens no
credential path. The R2 buckets themselves (CLA evidence: names/signatures; LUKS-header escrow) are
unchanged.

**Brand-survival threshold:** `aggregate pattern` — a *systematically* over-stated attestation could
weaken the legal claim-unlock posture (#6893) across all users' external copy, but no single-user
incident arises from a metadata edit. No per-PR CPO sign-off required; the section is present per gate.

## Decision: scope + the non-R2 rows (B2, advisor-confirmed)

**#6896 closes against its issue body — the 3 R2 surfaces — not against audit-doc line 74's over-grouping.**
Chosen path **B2**:

- **Formalize the 3 R2 rows** (the named deliverable).
- **Re-point** the 4 non-R2 rows' `tracked #6896` reference — and audit-doc lines 43–45 & 74 — to a **new
  P3 tracking issue** ("encryption-posture: non-R2 provider rows need named SOC 2 attestations"), so
  closing #6896 leaves **no false-resolved state**. The new issue's body records that audit-doc line 74
  previously mis-attributed these 4 rows to #6896 (the paper trail explains itself).
- The 4 non-R2 rows keep their current (passing) `provider-managed:*-aes256` mechanism + URLs; naming
  their SOC 2 attestations is the deferred work the new issue tracks.

**Alternative (B1 — recorded as a decision-challenge, NOT implemented):** formalize all 7 provider rows
in this PR and close #6896 per the audit-doc's all-7 definition. Rejected as default: it silently
widens a P3 issue to 4 rows the operator did not name and blurs what "#6896 closed" attests to. Persisted
to `knowledge-base/project/specs/feat-one-shot-6896-r2-soc2-attestation/decision-challenges.md` for the
operator to pull scope back to strict-R2 or expand to all-7 at review; `ship` renders it into the PR body
+ files an `action-required` issue.

## Target row shape (the 3 R2 rows)

For **each** of `cloudflare_r2_bucket.cla_evidence`, `cloudflare_r2_bucket.workspaces_luks_header`,
`r2.terraform_state_backend`, set `at_rest` to:

```jsonc
{
  "mechanism": "provider-managed:Cloudflare-R2-SOC2-Type-II",   // canonical shape; matches the test-suite PASS fixture (lint-encryption-posture.test.sh:315). Downgrade to "provider-managed:Cloudflare-SOC2-Type-II" ONLY if /work cannot confirm R2 is in Cloudflare's SOC 2 scope (see Phase 1).
  "evidence": "Cloudflare R2 stores objects encrypted at rest with AES-256-GCM (developers.cloudflare.com/r2/reference/data-security/); Cloudflare holds an AICPA SOC 2 Type II attestation (Security/Confidentiality/Availability) per the Cloudflare Trust Hub — the report is available under NDA, the attestation's existence and scope are public.",
  "attestation_url": "https://www.cloudflare.com/trust-hub/compliance-resources/soc-2/",
  "retrieved_on": "<YYYY-MM-DD verification date — 2026-07-24 if /work verifies same-day>",
  "defends_against": "<keep the existing per-row string>",
  "does_not_defend": "<keep the existing per-row string>",
  "disclosed_as": "not-publicly-claimed",
  "live_verification": "unavailable:provider-managed at-rest; SOC 2 Type II report is NDA-gated — public attestation cited via mechanism/attestation_url; no customer-side live probe of Cloudflare disk encryption"
}
```

Per-row `evidence` keeps its distinguishing clause:
- `workspaces_luks_header`: append "; holds LUKS-header escrow, itself useless without the separately-held passphrase."
- `r2.terraform_state_backend`: append "; the R2-backed Terraform state bucket (soleur-terraform-state, main.tf:2-6) — in-repo comments in doppler-write-token.tf:23 / ghcr-minter-doppler-token.tf:36 previously asserted 'encrypted' with no attestation, now substantiated."

**Boilerplate-ban guardrail (Layer A `check_provider_managed`):** the lowercased `mechanism`+`evidence`
must NOT contain the substrings `"encrypted by default"`, `"provider handles"`, or `"the provider handles it"`.
The strings above avoid all three (note: use "encrypted at rest with AES-256-GCM", never "encrypted by default").

## Implementation Phases

### Phase 0 — Preconditions + new tracking issue (all `gh`/`python3`, no operator step)
1. Confirm branch, Layer A green baseline: `python3 scripts/lint-encryption-posture.py --repo-sweep` → expect `… 0 failing checks -> PASS`.
2. Re-confirm the 7 `tracked #6896` rows and their line numbers: `grep -n "tracked #6896" scripts/encryption-posture-ledger.json` (expect 7 hits: 3 R2 + 4 non-R2).
3. Create the non-R2 tracking issue and **capture its number** (`NEW`):
   ```bash
   gh issue create \
     --title "encryption-posture: non-R2 provider rows need named SOC 2 attestations" \
     --label priority/p3-low --label domain/engineering --label type/security \
     --milestone "Phase 4: Validate + Scale" \
     --body "supabase.prd, supabase.inngest, doppler.secrets, betterstack.logs carry provider-managed AES-256 mechanisms with documentation-only citations and still need named at-rest attestations (Supabase/Doppler/Better Stack SOC 2 or equivalent). These 4 rows were previously mis-attributed to #6896 by encryption-posture-audit-2026-07-23.md line 74; #6896 is body-scoped to the 3 R2 surfaces. Re-evaluation: formalize each row's mechanism to provider-managed:<Provider>-<Standard> with a trust-center attestation_url + current retrieved_on, mirroring the R2 formalization in #6896. Ref #6893 (claim-unlock umbrella). Ref #6588."
   ```

### Phase 1 — Verify the Cloudflare SOC 2 attestation (WebFetch, no fabrication)
1. WebFetch `https://www.cloudflare.com/trust-hub/compliance-resources/soc-2/` — confirm it names **AICPA SOC 2 Type II** for Cloudflare and states the report is available (typically under NDA). Confirm the URL is live (200) at verification time.
2. Confirm **R2 is within Cloudflare's SOC 2 scope** (check the SOC 2 page / Cloudflare's SOC 2 scope listing). If R2 is explicitly in-scope → keep `provider-managed:Cloudflare-R2-SOC2-Type-II`. If only company-level SOC 2 is confirmable → use `provider-managed:Cloudflare-SOC2-Type-II` and word `evidence` so it does not overclaim R2-specific SOC 2 scope (still cite R2 AES-256-GCM from the R2 data-security docs).
3. Pin `retrieved_on` to the verification date. (This verification was performed during planning on 2026-07-24 and both facts held — R2 encrypts with AES-256-GCM per the data-security docs; Cloudflare holds SOC 2 Type II per the Trust Hub SOC 2 page. /work re-confirms and pins the date it runs.)

### Phase 2 — Formalize the 3 R2 rows
Edit `scripts/encryption-posture-ledger.json` — set `at_rest` on the 3 R2 rows per **Target row shape** above (mechanism, evidence, attestation_url, retrieved_on, live_verification). Leave `defends_against`, `does_not_defend`, `disclosed_as`, and all non-`at_rest` fields unchanged. Do NOT touch `kind`, `store`, `device_binding`.

### Phase 3 — Re-point the 4 non-R2 rows to `#<NEW>`
In `scripts/encryption-posture-ledger.json`, for `supabase.prd`, `supabase.inngest`, `doppler.secrets`, `betterstack.logs`: change only `live_verification` from `"unavailable:attestation formalization pending; tracked #6896"` to `"unavailable:named SOC 2 attestation formalization pending; tracked #<NEW>"`. Leave mechanism/evidence/URLs unchanged.

### Phase 4 — Correct the audit-doc mis-grouping
Edit `knowledge-base/engineering/architecture/encryption-posture-audit-2026-07-23.md`:
- Lines 40–42 (R2 rows): update the Source column to "Cloudflare Trust Hub SOC 2 Type II" and the Finding column to note #6896 resolved (SOC 2 Type II named).
- Lines 43–45 (non-R2 rows): change `#6896` → `#<NEW>`.
- Line 74: change "#6896 (provider-managed attestations, P3)" → "#6896 (R2 provider-managed attestations, P3 — SOC 2 Type II named) / #<NEW> (non-R2 provider attestations, P3)".

### Phase 5 — Verify + close
1. `python3 scripts/lint-encryption-posture.py --repo-sweep` → PASS (0 failing).
2. `python3 scripts/lint-encryption-posture.py --json > /dev/null` → exit 0 (schema still valid).
3. `bash scripts/lint-encryption-posture.test.sh` → all cases PASS (script unchanged; tests use own fixtures — no regression expected).
4. Assert no `tracked #6896` remains in the ledger: `grep -c "tracked #6896" scripts/encryption-posture-ledger.json` → `0`.
5. PR body carries `Closes #6896` (the remediation is complete at merge — no post-merge apply — so `Closes`, not `Ref`).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 — `grep -c "tracked #6896" scripts/encryption-posture-ledger.json` returns `0`.
- [ ] AC2 — The 3 R2 rows each have `mechanism` matching `provider-managed:Cloudflare(-R2)?-SOC2-Type-II`, a non-empty `attestation_url` on `cloudflare.com`, and a `retrieved_on` within 365 days of today. Verify: `python3 -c "import json;d=json.load(open('scripts/encryption-posture-ledger.json'));r=[s for s in d['stores'] if s['store'] in ('cloudflare_r2_bucket.cla_evidence','cloudflare_r2_bucket.workspaces_luks_header','r2.terraform_state_backend')];assert len(r)==3;[print(s['store'], s['at_rest']['mechanism'], s['at_rest']['attestation_url'], s['at_rest']['retrieved_on']) for s in r]"`.
- [ ] AC3 — None of the 3 R2 rows has `live_verification == "available"`; each is `unavailable:` with a reason containing "SOC 2" and NOT containing "tracked #".
- [ ] AC4 — Boilerplate guard: for each R2 row, lowercased `mechanism+" "+evidence` contains none of `"encrypted by default"`, `"provider handles"`, `"the provider handles it"`.
- [ ] AC5 — `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0 and prints `-> PASS`.
- [ ] AC6 — `python3 scripts/lint-encryption-posture.py --json` exits 0 (schema valid).
- [ ] AC7 — `bash scripts/lint-encryption-posture.test.sh` passes (no test regressions).
- [ ] AC8 — The 4 non-R2 rows' `live_verification` cites `#<NEW>` (the new issue number), not `#6896`; `grep -c "tracked #<NEW>" scripts/encryption-posture-ledger.json` returns `4`.
- [ ] AC9 — Audit doc: lines 43–45 & 74 reference `#<NEW>`; no non-R2 row line still references `#6896`.
- [ ] AC10 — The new tracking issue exists (`gh issue view <NEW>` returns state OPEN) with labels priority/p3-low + domain/engineering + type/security.
- [ ] AC11 — PR body contains `Closes #6896` and references the new issue + `Ref #6893` + `Ref #6588`.

### Post-merge (operator)
- None. `Closes #6896` auto-closes at merge; the remediation is fully in-diff. No terraform apply, no operator step. (Automation note: issue create/close + gh verification are all `gh` CLI — no manual step.)

## Encryption Posture

This plan modifies attestation metadata for **existing** provider-bucket stores; it introduces no new
store and no new connection (Phase 2.11 detection does not strictly fire — no `.tf`/migration/cloud-init
edit — but the section is included because the change is *about* at-rest posture).

```yaml
at_rest:
  - store: cloudflare_r2_bucket.cla_evidence | cloudflare_r2_bucket.workspaces_luks_header | r2.terraform_state_backend
    mechanism: provider-managed:Cloudflare-R2-SOC2-Type-II   # named attestation (was: provider-managed:cloudflare-r2-default-aes256, docs-only)
    evidence: R2 AES-256-GCM at rest (R2 data-security docs) + AICPA SOC 2 Type II (Cloudflare Trust Hub SOC 2 page, NDA-gated report / public attestation)
    attestation_url: https://www.cloudflare.com/trust-hub/compliance-resources/soc-2/
    retrieved_on: <verification date, <365d — Layer A re-fetch cadence is annual by design>
    defends_against: provider-managed at-rest encryption vs. physical-media compromise in Cloudflare's infrastructure
    does_not_defend: a leaked R2 API token, an application-layer read, or any legitimate-credential access; a provider-managed key is not a customer-held key
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:provider-managed at-rest; SOC 2 Type II report is NDA-gated — public attestation cited; no customer-side live probe
in_transit: n/a — this change adds no connection.
exception: n/a — mechanism is provider-managed (named attestation), not plaintext-exception; no exception block required.
```

## Observability

```yaml
liveness_signal:   what=Layer A encryption-posture gate result / cadence=every CI run on infra-root + ledger changes / alert_target=CI red (blocks merge) / configured_in=scripts/lint-encryption-posture.py + its CI wiring
error_reporting:   destination=CI job stderr (one `FAIL: <what> -> <fix>` line per violation) / fail_loud=true (non-zero exit fails the job)
failure_modes:
  - mode=over-stated attestation (R2 not actually in SOC 2 scope) / detection=Phase 1 WebFetch verification + human PR review / alert_route=PR review
  - mode=stale retrieved_on (>365d) / detection=Layer A check_provider_managed / alert_route=CI red
  - mode=boilerplate phrase reintroduced / detection=Layer A BOILERPLATE_PHRASES check / alert_route=CI red
  - mode=schema break (missing required at_rest field / bad live_verification) / detection=validate_ledger / alert_route=CI red
logs:              where=CI job output / retention=per CI retention policy
discoverability_test:
  command: python3 scripts/lint-encryption-posture.py --repo-sweep    # runs locally / in CI, no remote shell needed
  expected_output: "encryption-posture: 14 stores, 3 connections, 0 unledgered, 0 failing checks -> PASS"
```

## Infrastructure (IaC)

N/A — introduces no server, service, cron, vendor account, DNS record, secret, or firewall rule. The R2
buckets + state backend already exist and are unchanged; this edits ledger metadata + a doc + creates a
GitHub issue (all `gh`/file edits). Phase 2.8 skipped (no infra surface).

## Architecture Decision (ADR/C4)

N/A — no architectural decision. This **applies** the already-accepted ADR-139 / ADR-140 (encryption-posture
ledger as a design-time default). No new store, actor, or system → no C4 change (the three R2 buckets are
already modeled and audited). Test: a competent engineer reading the existing ADRs + C4 is not misled by
this change → skip per Phase 2.10.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal/Compliance (CLO — advisory)

### Engineering (CTO)
**Status:** reviewed (inline)
**Assessment:** Pure ledger/data-file + doc change; no code path altered (`lint-encryption-posture.py`
unchanged). Layer A stays green; test fixtures already use the target `Cloudflare-R2-SOC2-Type-II` shape.
The one engineering trap (advisor-confirmed) is `live_verification` semantics — `available` would be a
false claim; the plan keeps `unavailable:<reworded>`. No regression risk beyond the boilerplate-substring
guard, which the Target row shape observes.

### Legal / Compliance (CLO)
**Status:** reviewed (inline; CLO consult deferrable to deepen-plan if the operator wants a formal pass)
**Assessment:** The attestation cited is Cloudflare's AICPA SOC 2 Type II. Legal nuance encoded directly:
the **report** is NDA-gated; only its **existence + scope** are public. The ledger `evidence` must state
this (does not imply the report is freely downloadable) and must not overclaim R2-specific SOC 2 scope
unless Phase 1 confirms R2 is in-scope. This attestation feeds the #6893 claim-unlock gate that governs
external "encrypted at rest" copy — accuracy here is the whole point of the ledger (#6588 class). GDPR
gate (2.7) not triggered: no schema/migration/auth/API/.sql surface, no new processing.

### Product/UX Gate
Not relevant — no UI surface in Files to Edit (NONE).

## Files to Edit
- `scripts/encryption-posture-ledger.json` — 3 R2 rows formalized (Phase 2) + 4 non-R2 rows re-pointed (Phase 3).
- `knowledge-base/engineering/architecture/encryption-posture-audit-2026-07-23.md` — correct the #6896 mis-grouping (Phase 4).
- `knowledge-base/project/specs/feat-one-shot-6896-r2-soc2-attestation/decision-challenges.md` — record the B2-vs-B1 challenge (created by this plan flow).

## Files to Create
- (via `gh issue create` in Phase 0) the non-R2 provider-attestation tracking issue — not a repo file.

## Open Code-Review Overlap
None — `gh issue list --label code-review --state open` returned no issue whose body references
`encryption-posture`, `lint-encryption`, or `attestation`.

## Sharp Edges
- **Do NOT set `live_verification: "available"`.** In this ledger `available` means a *live probe exists*
  (`hcloud_volume.workspaces_luks`). A named, NDA-gated SOC 2 report is an *attestation citation* carried
  by `mechanism`+`attestation_url`+`retrieved_on`, not a live verification. Keep `unavailable:<reason>`,
  drop the `#6896`/`pending` text. (Advisor-flagged; a SOC 2-literate reviewer would catch `available`.)
- **Boilerplate substring ban is exact-substring.** `check_provider_managed` FAILs if lowercased
  `mechanism+evidence` contains `"encrypted by default"` / `"provider handles"` / `"the provider handles it"`.
  Write "encrypted **at rest** with AES-256-GCM", never "encrypted by default".
- **`live_verification` must still satisfy `^(available|unavailable:.+)$`.** A bare `"unavailable:"` (no
  reason) FAILs schema validation. Keep a non-empty reason.
- **`retrieved_on` re-fetch cadence is annual by design.** Layer A FAILs `retrieved_on` >365 days. Pinning
  today's date means a future FAIL ~1 year out is expected, not a bug — note it in the PR body so it isn't
  a surprise. (Consider whether a follow-through enrollment is warranted; see below.)
- **Confirm R2 is in Cloudflare's SOC 2 scope before asserting `Cloudflare-R2-SOC2-Type-II`.** The generic
  compliance landing page naming company-level SOC 2 is weaker than R2-in-scope; record whichever the page
  supports (downgrade the mechanism string if only company-level is confirmable).
- **Capture the new issue number before editing rows/audit-doc.** Phases 3 & 4 write `#<NEW>` — create the
  issue in Phase 0 first, then substitute. A concurrent guess would dangle.
- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails `deepen-plan`
  Phase 4.6 — this plan's section is complete (`aggregate pattern`).
- The same-day learning `knowledge-base/project/learnings/2026-07-24-a-security-gate-detector-nearly-shipped-the-false-green-it-was-built-to-prevent.md`
  documents how this exact detector nearly false-greened — reinforces that attestation accuracy (not just
  a passing gate) is the deliverable.

## Non-Goals / Deferred
- **Formalizing the 4 non-R2 provider rows** (supabase.prd, supabase.inngest, doppler.secrets,
  betterstack.logs) — deferred to the new tracking issue `#<NEW>` (created Phase 0), Ref #6893. This is the
  B2 default; B1 (do all 7 now) is the recorded decision-challenge.
- **Editing the `backend "s3"` .tf comment** in doppler-write-token.tf / ghcr-minter-doppler-token.tf — the
  ledger already marks those "now substantiated"; the comments are informational, out of scope.
- **Legal-copy reconciliation** of privacy/GDPR docs against these attestations — that is a separate
  `/soleur:legal-audit` run (tracked under #6897 per the audit doc), not #6896.
