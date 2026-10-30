---
title: "Counsel review audit — #9927 / PR #10652 (Inngest LUKS items 6, 8b, C1: Article 30 register PA-13/21/22/27/31 markers and compliance-posture entry)"
type: counsel-review
date: 2026-10-22
issue: 9927
pr: 10652
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-10-22
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED, subject to two wording-only in-PR conditions (C1, C2). Every count, date, evidence class and 'NOT measured' limb in the added text matches measurements.md and the runbook; no negative claim, no published-document edit, no [DRAFT] marker. The one published inaccuracy (DPD 2.3(o)) pre-dates the PR and is tracked in #10849."
conditions:
  - "C1 — compliance-posture.md 2026-10-22 comment: 'CLO ruling 2026-10-22: acceptable under Art. 32(1)(b)-(d) / 5(1)(b), no stop condition' merges two rulings. The Art. 32 / 5(1)(b) ruling on the probe is dated 2026-10-20 (decision-challenges.md); the 2026-10-22 ruling is the recording ruling ('may ship, no stop condition'). Reword to name both dates."
  - "C2 — article-30-register.md PA-13 (e): the new Superseded marker says the Postgres half holds run-history and event records but not where. (e) is the transfer limb and still opens 'No transfer'. Add one clause: dedicated Supabase project, EU (eu-west-1 per inngest-server.md), Supabase an already-listed processor (DPD section 4.2), so the no-transfer conclusion stands."
non_blocking:
  - "N1 — #10849 body attributes eu-west-1 to ADR-105; ADR-105 names the project ref, not the region (the register marker at PA-27 (f) has this right; the region is in inngest-server.md). Correct the issue text before the 2.3(o) rewrite; the issue itself says to verify against the sources."
  - "N2 — the sibling pointers quote 'Postgres holds config and history' / 'localhost-bound' as one alternation; PA-27 (d) and PA-31 (d)/(f) carry only the second phrase. Accurate as an either-or; no edit needed."
open_follow_ups: ["#10848 (Art. 5(1)(e) storage limitation and Art. 17 / Art. 15 reach of the Postgres history; filed, OPEN)", "#10849 (DPD 2.3(o), mirror, plus privacy-policy 5.9 and gdpr-policy imprecision; filed, OPEN, target 14 days)"]
re_evaluation_triggers: "Round 2 of C1 (any row-level count, min-timestamp read or payload read) OR first arms-length user OR EEA-out data subject OR regulated-industry user OR a finding that the Postgres history is reachable from the app's account-delete / DSAR path."
---

# Counsel review audit — #9927 (Inngest Postgres history: register markers and posture entry)

v1 internal counsel-review attestation for PR #10652, a `single-user incident` PR that amends `knowledge-base/legal/article-30-register.md` and `knowledge-base/legal/compliance-posture.md`. Authority: CLO agent (Soleur-as-tenant-zero v1); operator veto retained; external counsel reserved for the frontmatter triggers. Output is draft material, not legal advice.

**Method.** Each added sentence was checked against `measurements.md` (C1 section), the runbook `inngest-luks-cutover-6894.md` ("After a total loss" and its Superseded blocks), the ADR-282 addendum of 2026-10-22, `decision-challenges.md` (CLO rulings of 2026-10-20 and 2026-10-22), `inngest-server.md` (region) and the live state of #10848/#10849. `git diff origin/main...HEAD` shows no change under `docs/legal/`, `plugins/soleur/docs/pages/legal/` or `legal-doc-shas.ts`, and zero added `[DRAFT` markers.

## Artifact 1 — Article 30 register (PA-13 (e)/(f); PA-21/22/27/31 pointers)

| Claim in the diff | Checked against | Verdict |
|---|---|---|
| Dedicated Supabase project, 14 tables | measurements.md "Does the Postgres half hold history?" | TRUE |
| ~937k history / ~182k events / ~1.6M spans, labelled estimated | measurements.md size row (`reltuples` / live-count estimates; the register takes the higher live count, flagged as estimates) | TRUE |
| `events.event_user` named as a user-capable column BY NAME, non-null count NOT measured | candidate-column row and "N rows non-null: NOT measured" | TRUE |
| Oldest row NOT measured | "Oldest row / retention horizon: NOT measured" | TRUE |
| Evidence class: partial | measurements.md "Evidence class: partial" | TRUE |
| Aggregate catalog metadata only, read-only role, pinned project, no row/identifier/payload read | role `supabase_read_only_user`, `read_only=on`, project `pigsfuxruiopinouvjwy`; closing paragraph of the C1 section | TRUE |
| "No automatic deletion" unchanged and not proven by this read | the read measured presence, not deletion behaviour | TRUE; correctly not over-claimed |
| "Not personal-data-bearing" clause stays scoped to PA-13's own events | the clause concerns Stripe email hashing in PA-13; nothing measured contradicts it | TRUE |
| eu-west-1 in the PA-27 (f) marker; ADR-105 names the project, not the region | `inngest-server.md` has the pooler host `aws-0-eu-west-1`; ADR-105 has no region | TRUE (and a more careful source than #10849, see N1) |

**Marker use.** PA-13 (f) takes `Added` (nothing there is falsified); PA-13 (e) and PA-27 (f) take `Superseded` as to the exact falsified phrase ("Postgres holding only config/history"; "operator-managed, self-hosted, localhost-bound"), scoped "for the Postgres half only" with "Redis half unchanged". PA-21 (f), PA-22 (f), PA-27 (d), PA-31 (d)/(f) carry pointer-only Superseded blocks. This is the rule in the CLO sharp edge and matches the 2026-10-22 ruling. The original sentences are retained with the marker under them. **Verdict: accurate; C2 (e-limb location clause).**

## Artifact 2 — compliance-posture.md (2026-10-22 comment, `last_updated`)

Counts, "14 tables", "name-pattern match only, the event body column was not inspected", "non-null count and oldest row NOT measured", "evidence class partial" and "default of all active users stays and is a floor, not a ceiling" all match measurements.md and the runbook. "The probe script was removed from the PR" is true (`scripts/inngest-history-probe*` absent; ADR-282 addendum and runbook say the same). Open items #10848/#10849 exist and are OPEN; "target 14 days" matches #10849. `last_updated` moved to 2026-10-22. **Verdict: accurate except the merged-ruling date (C1).**

## Artifact 3 — Negative claims (check 2)

No added text asserts "no per-user source exists", "no record survives" or "nothing identifies them"; the runbook now forbids saying so. The two pre-existing absolutes ("unknowable from surviving data"; "no per-user list exists") were rewritten into bounded form. The remaining "No per-user list is kept app-side" is scoped to `schedule-reminder` and ADR-282, and is immediately followed by "NOT established". **Verdict: pass.**

## Artifact 4 — Published documents and consistency (checks 3 and 4)

No file under `docs/legal/` or the Eleventy mirror changed; no SHA re-pin was needed. The register text now disagrees with `data-protection-disclosure.md` 2.3(o) ("no external sub-processor") and is imprecise against privacy-policy 5.9, gdpr-policy and DPD (aa). That divergence pre-dates this PR, the register is the more accurate surface, Supabase is already a listed processor (DPD section 4.2) so the EU and no-transfer conclusions stand, and the fix is filed (#10849, which names all four sentences, a proposed replacement, the CI gates and a counsel-review pass). **Verdict: pass; the tracked inaccuracy is not a blocker.** The PR body must state the inaccuracy and link #10849 (ruling condition).

## Artifact 5 — ADR-282 addendum and the 2026-10-22 ruling

The addendum rows (measured: project, tables, estimates, candidate column by name; not measured: non-null count, oldest row, rows tied to lost work, which users) match measurements.md exactly. Ruling conditions are met: `Ref #9927` (no closing keyword) is in the commits seen; the did-not-inspect sentence is in the runbook verbatim; #10848 filed; the 2.3(o) fix is a tracked follow-up, not an in-PR edit.

## Overall

| Artifact | Verdict |
|---|---|
| Register PA-13 (e)/(f), PA-21/22/27/31 markers | Accurate; C2 |
| compliance-posture.md entry | Accurate; C1 |
| Negative-claim check | Pass |
| Published documents / drift from `docs/legal/` | Untouched; one pre-existing gap tracked in #10849 |
| ADR-282 addendum and runbook | Consistent with measurements.md |

**Disposition: DISCHARGED**, with C1 and C2 applied in this PR (wording only; neither changes a figure or a legal conclusion). #10848 and #10849 stay open and are the controlling follow-ups.

*Draft material for internal attestation; not legal advice. External counsel re-review follows the frontmatter triggers.*
