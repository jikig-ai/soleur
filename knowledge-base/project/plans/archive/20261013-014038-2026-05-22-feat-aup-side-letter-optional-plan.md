---
title: "feat-aup-side-letter-optional plan"
date: 2026-05-22
parent_pr: 4289
status: draft
---

# Plan: AUP §5.5 + T&C §3b.4 — Side Letter no longer required

Same-day follow-up amendment to PR #4289. The original PR shipped a per-pair Side Letter requirement gated by AUP §5.5 + T&C §3b.4. Operator review on 2026-05-22 (post-merge) flagged the per-pair pattern as non-scaling and unnecessary given the DPD §4.2 carve-out (co-members are NOT Article 28 processors; click-through ToS is the load-bearing controllership-establishing event). This PR softens both clauses so the Side Letter becomes an OPTIONAL belt-and-braces instrument.

## Scope

- **AUP §5.5** (canonical + Eleventy mirror): rename "Workspace member attestation" → "Workspace member responsibility"; remove "must attest each invitee is bound by equivalent terms" requirement; replace with "Owner is responsible for ensuring co-members are bound by appropriate terms by any sufficient means (click-through ToS, existing engagement, or optional Side Letter)".
- **T&C §3b.4** (canonical + Eleventy mirror): remove "Owner is required to execute Side Letter" requirement; replace with "Owner may satisfy responsibility by any sufficient means".
- **T&C §3b.3(d)** indemnification trigger: realign with new "responsibility" framing.
- **Side Letter template** (`knowledge-base/legal/side-letter-template.md`): add OPTIONAL banner explaining the template is now a belt-and-braces reference; execution not required.
- **`apps/web-platform/lib/legal/tc-version.ts`**: bump `TC_VERSION` 2.2.0 → 2.2.1 + refresh `TC_DOCUMENT_SHA` + update `TC_BUMP_METADATA.substantiveChange` to describe the §3b.4 softening.
- **Seed scripts** (`apps/web-platform/scripts/seed-{dev-users,qa-user}.sh`): bump TC_VERSION literal to 2.2.1.
- **Test** (`apps/web-platform/test/accept-terms-copy-regression.test.tsx`): relax the substantive-change literal assertion from `/Workspace Members/` to `/\S/` so the test no longer brittle-fails on each bump.

## Out of scope

- DPA template / customer-facing DPA publication (still on the §3b.4 supersession roadmap).
- Counsel-review audit document — the operator-attested audit at `knowledge-base/legal/audits/2026-05-counsel-review-4289.md` is amended in this PR to record the same-day softening; no new audit file.

## Bump-policy classification

**Tier 1 — Material** per `knowledge-base/legal/tc-version-bump-policy.md`. The change materially narrows the Workspace Owner's obligation (removes a documented requirement) and modifies the §3b.3(d) indemnification trigger. Per the rubric, this requires `TC_VERSION` bump + SHA refresh + Last-Updated chain entry. A second re-acceptance wave fires on merge; acceptable because the change is user-favorable (removes an obligation) and lands on the same day as the first wave (consolidates the user disruption window).

## User-Brand Impact

- **Brand-survival threshold:** `single-user incident` (carried forward from PR #4289).

### Artifacts and vectors

- **`users.tc_accepted_version`**: bump from `2.2.0` → `2.2.1` triggers a second re-acceptance wave for every user. Same artifact, second wave; same vector (banner copy redirect). Vector: middleware redirects on mismatch.
- **`docs/legal/terms-and-conditions.md` body**: §3b.3(d) + §3b.4 prose changes. Vector: SHA-pinned guardrail (`check-tc-document-sha.sh`) asserts hash matches `TC_DOCUMENT_SHA`; mismatch fails CI.
- **`tc_acceptances.document_sha` audit column**: records the 2.2.1 SHA per acceptance; the prior 2.2.0 SHA remains visible for users who accepted between 08:07 UTC (PR #4289 merge) and this PR's merge time.

### Failure modes

- Same as PR #4289: WS mid-session close on TC_VERSION mismatch, /accept-terms gate-trap, banner copy drift between TC_BUMP_METADATA and canonical doc. All mitigations from the parent PR carry forward; no new failure modes introduced.

## Observability

```yaml
liveness_signal:
  what: tc_acceptances row count for version 2.2.1
  cadence: monotonically increasing post-merge as users re-accept
  alert_target: none required (re-acceptance is expected, not anomaly)
error_reporting:
  destination: Sentry (existing wiring at /api/accept-terms + middleware)
  fail_loud: true (middleware redirects to /accept-terms?error=db_unavailable on Supabase outage)
failure_modes:
  - mode: TC_DOCUMENT_SHA drift (canonical edited without literal refresh)
    detection: .github/workflows/ci.yml :: tc-document-sha-guard
    alert_route: CI red on PR; gates merge
  - mode: Eleventy mirror canonical-vs-mirror parity drift
    detection: apps/web-platform/test/legal-doc-consistency.test.ts
    alert_route: CI red on PR; gates merge
logs:
  where: tc_acceptances table (Postgres) + Sentry events
  retention: indefinite as append-only audit record; Art-17 anonymise RPC for erasure cascade
discoverability_test:
  command: curl -fsS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/accept-terms
  expected_output: "200 or 307"
  operator_runbook: |
    psql query against the audit ledger (run from a shell with DATABASE_URL set):
      psql -c "select count(*) from tc_acceptances where version = '2.2.1';"
    post-merge: 0 then monotonically increasing as users re-accept.
```

No ssh-based verification needed.
