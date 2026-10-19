---
title: "Counsel review audit — #10449 / PR #10446 (Art. 30 register PA-1 §(c): dev-only synthetic seed accounts named; ADR-064 I-cannot-spend data flow)"
type: counsel-review
date: 2026-10-18
issue: 10449
pr: 10446
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-10-18
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED. Every checkable claim in the added register sentence is true against the implementing scripts. The I-cannot-spend gate reads only the prod synthetic principal's own sentinel ciphertext and emits classes only; it creates no new processing of personal data, so no register, Privacy Policy, GDPR Policy or DPD amendment is required. Two non-blocking observations (N1, N2) are recorded."
blocking_findings: []
conditions:
  - "C1 — The sentence stays true only while both seeders keep BOTH the DOPPLER_CONFIG=dev refusal AND the host pin to the dev project. If either script's pin is loosened, or a seed account is ever created in the prod project, amend PA-1 §(c) and re-evaluate (a seeded account with a publicly committed password in prod is a security finding first, a register finding second)."
  - "C2 — If the I-cannot-spend gate ever reads a column other than the three sentinel ciphertext columns plus delegation ids, or the principal ever holds a real (non-sentinel) key, re-run this review: that would stop being a non-personal control record."
re_evaluation_triggers: "A seed script loses its dev-only refusal or host pin OR a synthetic account appears in the prod project OR the live-verify principal is given a real credential or a real person's data OR the gate's Sentry/annotation payload gains anything beyond a closed-vocabulary class tag OR first arms-length user OR EEA-out data subject OR regulated-industry user."
---

# Counsel review audit — #10449 (PR #10446)

Internal v1 counsel-review attestation. Gate fired because the diff touches `knowledge-base/legal/article-30-register.md` and the plan declares `brand_survival_threshold: single-user incident`. Draft material; external counsel is reserved for the frontmatter triggers.

**Scope of the legal change.** `git diff origin/main...HEAD -- knowledge-base/legal/` is one edited cell: PA-1 (Account & Authentication) limb (c), "Categories of data subjects", gains three sentences. The diff touches nothing under `docs/legal/`, `plugins/soleur/docs/pages/legal/` or `apps/web-platform/lib/legal/`.

**Method.** Claims checked against `apps/web-platform/scripts/seed-qa-user.sh`, `apps/web-platform/scripts/seed-dev-users.sh`, `apps/web-platform/scripts/seed-live-verify-user.sh`, `apps/web-platform/scripts/live-verify/run.ts` (`assertCannotSpend`, `SENTINEL_KEY`, `failureResult`), the register rows PA-1 §(c) and PA-11 §(c)/§(g)(11), `docs/legal/{gdpr-policy,privacy-policy,data-protection-disclosure}.md`, and the ADR-064 2026-10-18 amendment (read from `HEAD`). Code is cited by function or constant name, not line. No credentialed probe was run; the dev/prod separation rests on the repository's own records, cited below.

## Per-artifact verdicts

| Artifact | Verdict | Basis |
|---|---|---|
| `article-30-register.md` PA-1 §(c), added sentences | DISCHARGED | All six factual claims verified (table below). No overclaim, no contradiction with PA-11. |
| `docs/legal/privacy-policy.md`, `gdpr-policy.md`, `data-protection-disclosure.md` | NO AMENDMENT REQUIRED | No sentence addresses synthetic or test accounts; no sentence is contradicted. No heading changed, so no mirror-drift or SHA re-pin obligation. Register is not a published surface. |
| ADR-064 amendment data flow (I-cannot-spend) | NO REGISTER / POLICY CHANGE | Reads a non-personal machine principal's own sentinel rows; no new personal-data processing (analysis below). |
| Lawful basis / Art. 6(1)(f) LIA / retention / Chapter V for the above | NOT ENGAGED | No personal data is processed by any of the three flows; evidence below. |

## Claim-by-claim verification of the added register text

| Claim in the sentence | Checked against | Result |
|---|---|---|
| A second synthetic account `qa-test@example.com` exists | `seed-qa-user.sh`: `QA_EMAIL="qa-test@example.com"` | TRUE |
| Seeded by `apps/web-platform/scripts/seed-qa-user.sh` for local Playwright runs | Script header "Seed a fully provisioned QA test user for local Playwright testing"; emits a Playwright cookie-injection recipe | TRUE |
| The script "refuses any Supabase project but the distinct dev one" | Two independent gates: (1) `DOPPLER_CONFIG != "dev"` exits 1; (2) `case "$SB_URL"` accepts only `https://mlwiodleouzwniehynfz.supabase.co`, everything else exits 1, with the comment that the prd project is "NOT accepted here". `mlwiodleouzwniehynfz` is identified as the dev project in `.github/workflows/scheduled-supabase-advisor-scan.yml` (`mlwiodleouzwniehynfz:soleur-dev`) and ADR-033 ("the **dev** project"). Prod is served on the custom host `api.soleur.ai` (`PROD_ALLOWED_HOSTS` in `validate-url.ts`); AGENTS.md rule `hr-dev-prd-distinct-supabase-projects` requires distinct refs, enforced by preflight Check 4 | TRUE. The claim is the host pin, not the Doppler variable alone, which is the correct anchor: `DOPPLER_CONFIG` is an env var, the host pin is not bypassable by one. |
| Therefore "never a member of the production tables this activity covers" | PA-1 covers `auth.users`, `public.users`, `public.workspaces`, `public.api_keys` in the production Supabase project. The seeder writes only through the dev host (`$SB_URL` pinned) | TRUE (conditional on C1) |
| `seed-dev-users.sh` seeds "three `dev-N@example.com` users in the same dev project" | `for slot in 1 2 3`, `email="dev-${slot}@example.com"`; three gates before any write: `DOPPLER_CONFIG=dev`, canonical 20-char ref shape, service-role JWT `ref` equal to the URL ref, then the same dev-host `case` pin | TRUE |
| "likewise outside them" | Same pin | TRUE |
| Purpose: "an inspector ... is not surprised by non-human accounts in the repository" | Matches the stated rationale of the existing live-verify sentence (Art. 58(1)(a)) | Reasonable; consistent with the existing row |

What the scripts write (for completeness, not a claim in the sentence): `seed-qa-user.sh` sets `users.tc_accepted_version` / `tc_accepted_at`, workspace and repo status, a decrypt-poisoned dummy `api_keys` row, and one conversation with four sample messages. It does not call `public.accept_terms`, so it writes no `tc_acceptances` ledger row. See N1.

## Lawful basis, consent, retention, LIA, Chapter V: do they arise?

No, and the evidence is the same for all three flows (qa-test, dev-N, and the I-cannot-spend gate):

- **No natural person.** `example.com` is the reserved example domain (RFC 2606); the email addresses cannot belong to a person. The live-verify principal is already determined non-personal at PA-1 §(c) and PA-11 §(c) (restating ADR-064 §"Principle-register alignment", AP-009). The row content the gate reads is the seed's literal sentinel (`encrypted_key = "live-verify-dummy-not-real"`, a fixed `iv` and `auth_tag`), which is not a ciphertext of anything and identifies nobody.
- **Art. 4(1) not met, so Art. 6, Art. 7, Art. 5(1)(e) and Chapter III do not attach.** There is no lawful-basis entry to write, no consent evidence (the dev accounts' `tc_accepted_version` is a fixture value, not Art. 7(1) evidence), no retention clock to set, and no Art. 6(1)(f) LIA to run. Opening an LIA for non-personal data would itself be an inaccuracy in the record.
- **Chapter V.** The dev project's data location is irrelevant to a record that contains no personal data; the gate's Sentry event (a US-region processor already in the register for operational telemetry) carries a closed-vocabulary class tag only. No new transfer of personal data arises.

## ADR-064 amendment data-flow analysis (I-cannot-spend)

What the gate does, verified in `assertCannotSpend` and `failureResult`:

1. Via the principal's **own** RLS session (never the service role), selects `encrypted_key, iv, auth_tag` from `api_keys` (`KEY_COLUMNS`) and `id` from `byok_delegations` where `revoked_at IS NULL`.
2. Compares each row to `SENTINEL_KEY` in memory; a mismatch or a visible delegation throws a message carrying a **class only** (`cannot-spend-violated: api_keys-non-sentinel-row` and so on); unreadable/empty cases throw `cannot-spend-unverified: <class>`.
3. `failureResult` passes the message through `redact()` before it becomes the result line; `redact.ts` additionally scrubs the ciphertext keys as a backstop. The Sentry event carries level and a `reason=<token>:<class>` tag from a closed vocabulary.

Assessment:

| Question | Finding |
|---|---|
| Does the register's statement that the principal holds "a dummy, non-functional Anthropic key" change? | No. It is the same sentinel row; the gate now enforces the statement at each triggered release rather than assuming it. This strengthens the record's accuracy (Art. 5(1)(d)) and is a testable form of the "non-functional" claim. |
| Does a machine principal reading its own ciphertext rows create a processing activity involving personal data? | No. The rows belong to the non-personal principal, are read under its own RLS scope, and are a fixed literal. A real user's ciphertext is never selectable by this session (RLS), and the service role is not used (I-service-role-bootstrap-only unchanged). |
| Could the Sentry/annotation payload leak a real key or personal data? | Only if the principal held a real key, which is exactly the condition the gate blocks on and which the redactor scrubs. Payload is a class tag. If a violation ever occurs with a real key in the row, the real key is a secret, not an Art. 4 identifier of a person; the response is the ADR recovery runbook (delete the row, revoke the delegation) and, if a third party's key is found, the breach-triage threshold in `recommended-tools.md#breach-notice-triage`. No standing register change. |
| Does anything alter PA-11's discriminator/exclusion duty or PA-1's data-subject categories? | No. The sentinel row in `api_keys` is already within the PA-1 §(c) enumeration of the live-verify principal's rows. |
| Visibility gap (ADR: "Nothing alerts") | An engineering observability matter, not a legal one; a silent fail-open of the red run does not fail open the safety property (the throw still stops the browser launch). CTO domain; flagged only because a permanently unverifiable gate is a TOM-effectiveness question under Art. 32(1) if the register ever cites this gate as a measure. It does not cite it today, so no overstatement exists. |

## Public-disclosure cross-check

`grep` over `docs/legal/gdpr-policy.md`, `privacy-policy.md` and `data-protection-disclosure.md` for `live-verify`, `synthetic`, `qa-test`, `seed-` and `example.com` returns only unrelated hits (email-triage "synthetic-probe items", `ops@`/`legal@` addresses). The "synthetic-probe items 7 days" sentences concern the `ops@soleur.ai` triage probe, a different activity, and are not contradicted. No public document claims that no test accounts exist, so none is falsified by naming them in the internal register. Heading sequences are unchanged, so `legal-doc-consistency`, the mirror-drift ratchet, the scope-block lint and the SHA/`EXPECTED_COUNT` gates are not triggered (no `docs/legal/` or mirror file in the diff). These gates measure agreement, not truth; the truth check above was done by reading the scripts.

## Non-blocking observations

- **N1 — Art. 7(1) reconciliation scope.** `seed-qa-user.sh` and `seed-dev-users.sh` set `users.tc_accepted_version` without a `tc_acceptances` row, the same pattern PA-11 §(c) records as a permanent false positive in the Art. 7(1) reconciliation for the prod live-verify principal before #7969. The new sentence correctly places these accounts in the dev project, outside the production ledger, so the PA-11 exclusion duty does not extend to them. The trailing pointer "Discriminator and exclusion duty: PA-11 §(c) and §(g)(11)" now follows the dev-account sentences and could be read as covering them; it applies to the live-verify principal only. Optional clarification (not required): move that pointer to directly after the live-verify sentences. No action is needed to discharge.
- **N2 — Public credential in the dev project.** `seed-qa-user.sh` embeds a plaintext password in a public repository. The distinct dev project and the refusal gates are the control, and the account holds only synthetic data. If the dev project ever holds real personal data, that exposure becomes an Art. 32 item for the CTO; nothing in this diff says it does. Not a register matter today.

## Disposition

Reviewed artifacts: PA-1 §(c) added sentences (true as written), policy surfaces (no amendment), ADR-064 I-cannot-spend data flow (no register or policy change).

DISPOSITION: DISCHARGED
