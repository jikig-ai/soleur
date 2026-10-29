---
title: "Legal wording: Cloudflare-to-origin is not TLS for app.soleur.ai (#10479)"
type: fix
date: 2026-10-29
issue: 10479
---

# Legal wording: Cloudflare-to-origin hop (Ref #10479, Ref #10205)

Wording PR only. It changes what we PUBLISH and RECORD about the hop; it adds no TLS and changes no
Cloudflare mode. The technical fix (Origin CA, `strict`, handshake probe) is the owner-gated follow-up.

## Authority

CLO ruling on #10479, 2026-10-27 (verbatim text for Privacy Policy Section 11 and DPD 8.1(c)), re-affirmed
2026-10-29: fix the hop, no accepted-risk path. Dates from the ruling: target 2026-11-12 (Origin CA, `strict`,
handshake probe), hard stop 2026-11-19 (after which the published "not claimed" wording stays; no extension
or acceptance record is ruled).

## Scope

| File | Change |
|---|---|
| `docs/legal/privacy-policy.md` + Eleventy mirror | Section 11 bullet per the ruled text; Last Updated entry; mirror hero date |
| `docs/legal/data-protection-disclosure.md` + mirror | 8.1(c): browser-to-Cloudflare only; NOT FULFILLED beyond the edge; Last Updated entry |
| `apps/web-platform/lib/legal/legal-doc-shas.ts` | re-pin `privacy-policy`, `data-protection-disclosure` |
| `docs/legal/gdpr-policy.md` | grep only; no TLS-in-transit claim found; unchanged (SHA unchanged) |
| `knowledge-base/legal/article-30-register.md` | append `Superseded 2026-10-29 (#10479)` markers: PA-1, PA-2, PA-3, PA-4 TLS lines, PA-13 (g)(14), Cross-Cutting block. No signed text is rewritten |
| `knowledge-base/legal/data-processing-agreement-template.md` | the two "Encryption in transit" drafts |
| `knowledge-base/operations/domains.md` | SSL Mode row: app-host caveat |
| `scripts/encryption-posture-ledger.json` | new connection row for the Cloudflare-to-origin hop; Inngest row points to it |

## Decisions

- The ruled Section 11 text keeps the existing private-network and job-scheduler sentence unchanged
  (including "self-hosted Inngest event store"). That phrase predates and now sits beside the 2026-10-27
  Section 4.13 correction (the store is a Supabase Postgres project); flagged to the owner/CLO, not changed here.
- DPD 8.1(c) keeps the existing job-scheduler sentence between the ruled sentences and the ruled status line.
- The 2026-11-19 hard stop appears only in the internal register, ledger and operations notes, not in the
  published documents (the ruled published text carries only the 2026-11-12 target).
- The ledger row's `exception` block is the schema's required carrier for `cert_verification: off`; its
  justification states that it is not an accepted risk. `expires_on` 2026-11-12 forces the re-review.
- `api.soleur.ai` is dropped from the DPA template's TLS claim: no read of its SSL mode exists (CTO verification item 5).
- "Corrected 2026-10-29" is the PR date. If the merge slips past it, the owner may want the date moved.
- Register markers use "fires on the merge of PR #N".

## Verification

`check-tc-document-sha.sh`, `legal-doc-consistency` and `legal-doc-shas-guard` vitest, `lint-legal-mirror-drift-baseline.sh`,
`lint-legal-registers.sh`, `lint-legal-scope-block-placement.sh`, `lint-encryption-posture.py` (+ its suite),
`probe-legal-corpus-truth.sh`.

## Not in this PR (owner-gated)

Any Cloudflare mode change, Origin CA deployment, or origin deploy. Merge. #10479 and #10205 stay open.

## Observability

Documentation-only change; no production code or infra is touched. Discoverability test:
`python3 scripts/lint-encryption-posture.py` (no SSH) fails every PR from 2026-11-12 unless the ledger row is renewed or removed.
