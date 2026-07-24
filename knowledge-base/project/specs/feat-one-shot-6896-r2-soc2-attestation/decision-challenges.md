# Decision Challenges — feat-one-shot-6896-r2-soc2-attestation

Rendered into the PR body + filed as an `action-required` issue by `/soleur:ship`.

## Challenge 1 — scope: 3 R2 rows (B2, chosen) vs. all 7 provider rows (B1)

**Operator's stated direction:** the parent pipeline scoped the deliverable to "THREE R2 rows" and
"close #6896".

**What the plan found:** the `tracked #6896` placeholder is on **7** ledger rows, not 3 — the 3 R2 rows
plus 4 non-R2 provider rows (`supabase.prd`, `supabase.inngest`, `doppler.secrets`, `betterstack.logs`).
The repo's own audit doc (`encryption-posture-audit-2026-07-23.md:74`) *defines* #6896 as
"provider-managed attestations" covering all 7.

**Decision (default = B2, operator's direction honored):** formalize only the 3 R2 rows (per #6896's
issue **body**, which names exactly those surfaces); re-point the 4 non-R2 rows + audit-doc lines 43–45 &
74 to a **new P3 tracking issue** so #6896 closes with no false-resolved state. The all-7 audit-doc stamp
is treated as doc drift and corrected.

**Alternative not taken (B1):** formalize all 7 provider rows in this PR and close #6896 per the
audit-doc's all-7 definition (lower churn, fully consistent end-state, but silently widens a P3 issue to
4 rows the operator did not name).

**Advisor (fable) verdict:** B2 is correct — issues close against their **body**, not a doc's
over-grouping; B2's re-pointing *is* the correction of that drift. Reframe the PR as "body-scoped close +
audit-doc mis-grouping fix" so no reviewer relitigates B1.

**Operator action:** confirm B2, or direct B1 (do all 7 now), or strict-R2 with a different tracker for
the 4 non-R2 rows.

## Challenge 2 — `live_verification` end-state (not "available")

**Considered:** setting the 3 R2 rows' `live_verification` to `"available"` (literal "clear the
placeholder").

**Decision:** keep `unavailable:<reworded reason>`. In this ledger `available` means a **live probe
exists**; a named, NDA-gated SOC 2 report is an *attestation citation*, not a live verification. Advisor
flagged `available` as an overclaim a SOC 2-literate reviewer/auditor would catch. Reason text drops the
`#6896`/`pending` framing.

**Operator action:** none expected; recorded for transparency.
