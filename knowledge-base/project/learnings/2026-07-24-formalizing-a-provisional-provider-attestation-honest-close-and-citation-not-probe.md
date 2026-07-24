# Learning: formalizing a provisional provider attestation — honest-close scoping + citation-≠-probe

## Problem

The encryption-posture audit (#6885) seeded the ledger's provider-managed rows with
**provisional** attestations — a `provider-managed:<vendor>-<cipher>` mechanism pointing at the
vendor's *data-security docs* and a `live_verification: "unavailable:… pending; tracked #6896"`
placeholder. The follow-up issue #6896 was to formalize a **named** attestation on the 3 Cloudflare
R2 rows. Three traps made this more than a find-replace:

1. The `tracked #6896` placeholder was on **7** rows (3 R2 + 4 non-R2), but #6896's issue **body**
   named only the 3 R2 surfaces. The repo's own audit doc (`…audit-2026-07-23.md:74`) had
   over-grouped all 7 under #6896 — closing #6896 against that framing would silently mark 4
   unrelated rows resolved.
2. The obvious "clear the placeholder → set `live_verification: available`" is **wrong**: a named,
   NDA-gated compliance report (SOC 2 Type II) is an *attestation citation*, not a *live probe*.
   `available` in this ledger means a customer-side probe exists (e.g. a LUKS mapper check). Setting
   it on a provider row is a false claim a SOC 2-literate reviewer catches.
3. Asserting product-specific scope (`Cloudflare-R2-SOC2-Type-II`) requires confirming the *product*
   is in the vendor's attestation scope — not just that the company holds SOC 2.

## Solution

- **Scope the close to the issue BODY, not a doc's grouping.** Formalized only the 3 R2 rows; created
  a new P3 tracker (#6911) for the 4 non-R2 rows, re-pointed their `tracked #` + the audit-doc lines
  to it, and corrected the audit doc's over-grouping in the same PR. `Closes #6896` then leaves **no
  false-resolved state**.
- **Keep `live_verification: "unavailable:<reason>"`** with the reason reworded to drop `pending`/`#N`
  — cite the attestation via `mechanism` + `attestation_url` + `retrieved_on`, and state plainly that
  the report is NDA-gated (existence + scope public) and there is no customer-side probe.
- **Verify product scope live before asserting it.** WebFetched the Cloudflare Trust Hub SOC 2 page:
  R2 is explicitly listed under "Developer Platform" in-scope services → `Cloudflare-R2-SOC2-Type-II`
  is justified (else downgrade to company-level `Cloudflare-SOC2-Type-II`). Also confirmed the exact
  at-rest cipher (R2 = AES-256 in GCM mode) against the R2 data-security docs rather than trusting the
  provisional row's wording.
- **Match the canonical fixture shape.** The mechanism casing (`Cloudflare-R2-SOC2-Type-II`, CamelCase)
  intentionally matches `lint-encryption-posture.test.sh`'s PASS fixture + the linter's documented
  `provider-managed:<Provider>-<Standard>` format — do NOT "normalize" it to the lowercase sibling
  style, which would diverge from the fixture the gate validates against.

## Key Insight

Formalizing a provisional attestation is an **accuracy** deliverable, not a gate fix — Layer A already
PASSES on the provisional row (`live_verification` is only schema-validated, never a sweep FAIL). The
value is the named citation feeding the #6893 claim-unlock gate. So the bar is "is every word true and
does the close leave the tracker set honest?", not "is CI green?". Two reusable rules: (a) a named
NDA-gated compliance report is a **citation, not a live probe** — keep `unavailable:<reason>`; (b) when
an audit doc over-groups follow-up rows under one issue, re-point the extras to a new tracker so the
issue closes against its **body**, never a doc's looser grouping.

This recurs directly for #6911's 4 non-R2 provider rows (Supabase / Doppler / Better Stack SOC 2).

## Tags
category: security-issues
module: encryption-posture-ledger
related: [[2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it]]
issues: 6896, 6893, 6588, 6911, 6885
