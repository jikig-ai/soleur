---
title: "Counsel review audit — #10849 (DPD 2.3(o) 'no external sub-processor' correction; sibling-sentence rewrites in (aa), privacy-policy 4.13, gdpr-policy 3.10, and the 4.2 Supabase row)"
type: counsel-review
date: 2026-10-27
issue: 10849
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-10-27
signed_off_by: "CLO agent function run inline (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED. Every added claim was verified against inngest.tf, inngest-bootstrap.sh, inngest-server.md, ADR-105 and the controlling ruling (2026-10-counsel-review-9927.md). Canonical and mirror carry byte-identical corrections at every touched position; SHA pins regenerated; no new transfer, purpose or processor is asserted."
non_blocking:
  - "N1 — `docs/legal/data-protection-disclosure.md` 2.3(o) still says 'Sub-processors: none new (Inngest remains self-hosted; ...)' and its retention paragraph names the THREE stores including the dedicated Supabase Postgres project. Accurate as written (Supabase is an existing listed processor; the Inngest server software is self-hosted); the retention paragraph was the correction's corroboration, not a defect. No edit."
  - "N2 — `docs/legal/privacy-policy.md` (encryption-in-transit bullet) and `docs/legal/gdpr-policy.md` still describe the job scheduler itself as 'self-hosted Inngest' — true of the server process; only the record-holding claim was falsified. No edit."
  - "N3 — Internal KB prose (runbooks, earlier audits) that loosely says 'self-hosted Inngest store' is outside this correction's published-doc scope; earlier audits are append-only records."
open_follow_ups: ["#10848 (Art. 5(1)(e) storage limitation and Art. 17 / Art. 15 reach of the Postgres history — separate tracked issue)", "#5150 (no-automatic-deletion retention bound — already disclosed as persisting until store maintenance)"]
re_evaluation_triggers: "First arms-length user OR EEA-out data subject OR regulated-industry user OR a substrate change (new store, region move, provider change) for the Inngest run-history/event records OR a finding that the Redis AOF or SQLite fail-safe copies carry different recipients."
---

# Counsel review audit — #10849 (DPD 2.3(o) recipient correction)

v1 internal counsel-review attestation for the published-docs correction ordered by the 2026-10-22 CLO ruling (`knowledge-base/legal/audits/2026-10-counsel-review-9927.md`, Artifact 4). Authority: CLO agent function (Soleur-as-tenant-zero v1); operator veto retained; external counsel reserved for the frontmatter triggers. Output is draft material, not legal advice.

**Method.** Each added sentence was checked claim-by-claim against `apps/web-platform/infra/inngest.tf` (project `soleur-inngest-prd`, ref `pigsfuxruiopinouvjwy`, region eu-west-1 — code comment), `apps/web-platform/infra/inngest-bootstrap.sh` (`INNGEST_POSTGRES_URI` via doppler env; `INNGEST_REDIS_URI` for `127.0.0.1:6379`; `unset INNGEST_POSTGRES_URI` SQLite fail-safe arm), `knowledge-base/engineering/operations/runbooks/inngest-server.md` ("events live in Supabase Postgres and the queue/run-state lives in Redis"; pooler host `aws-0-eu-west-1`), ADR-105 (names the project, not the region), and the ruling audit. Canonical↔mirror identity at every touched position was diff-verified; `LEGAL_DOC_SHAS` re-pinned; the five legal-corpus gates run green.

## Artifact 1 — data-protection-disclosure.md 2.3(o) (canonical + mirror)

| Claim added | Checked against | Verdict |
|---|---|---|
| "self-hosted Inngest OSS on Hetzner, eu-central" | inngest.tf / runbook (dedicated Hetzner host) | TRUE |
| "its queue and run state are held in a Redis store on that host" | inngest-bootstrap.sh `INNGEST_REDIS_URI` → `127.0.0.1:6379`; runbook "the armed-event queue lives in Redis" | TRUE |
| "its run-history and event records are held in a dedicated Supabase Postgres project in eu-west-1 (Ireland)" | inngest.tf comment (project, ref, region); runbook pooler host `aws-0-eu-west-1`; §2.3(o) retention paragraph naming the dedicated Supabase Postgres project | TRUE |
| "operated by Supabase Inc, a processor already listed in Section 4.2" | §4.2 Supabase row; DPA signed 2026-03-19 (Section 6) | TRUE |
| "no processor outside Section 4.2 is involved" | §4.2 table read in full; Hetzner also listed there | TRUE |
| Correction note: "an earlier version stated 'no external sub-processor'" | pre-edit text | TRUE |

The corrected sentence replaces a false recipient description (Art. 13(1)(e), 5(1)(a)). The EU and no-transfer conclusions stand: Supabase's row and the §6 transfer-safeguard line already carry eu-west-1 + the signed DPA. **Verdict: accurate.**

## Artifact 2 — data-protection-disclosure.md 2.3(aa) (canonical + mirror)

"self-hosted, operator-managed Inngest event store" and "a PII surface, not a third-party recipient" were both falsified by the Postgres store. The rewrite names the store, its operator and its already-listed status, and drops the "not a third-party recipient" limb — Supabase Inc is the recipient and is already named in the entry's own sub-processor list, so no new recipient is introduced by the correction. **Verdict: accurate.**

## Artifact 3 — privacy-policy.md 4.13 (canonical + mirror)

Same defect, same fix; the bullet already lists "Supabase Inc (EU — stores the triage rows)", so the corrected sentence cross-references "a processor already listed in this Section". Note: the issue cites §5.9; the sentence lives in §4.13's Sub-processors bullet (§5.9 is the Resend section it cross-references) — corrected where the sentence actually is. **Verdict: accurate.**

## Artifact 4 — gdpr-policy.md 3.10 recipients bullet (canonical + mirror)

"persist in the self-hosted Inngest event store" replaced with the store's actual holding arrangement; the recipient mapping already carries Supabase as a processor. **Verdict: accurate.**

## Artifact 5 — data-protection-disclosure.md 4.2 Supabase row (canonical + mirror)

The row's Processing-Activity cell gains "Inngest run-history and event records (dedicated project, eu-west-1, Ireland)"; the Data-Processed cell gains the category naming 2.3(o)/(aa); the Legal-Basis cell adds legitimate interest (Art. 6(1)(f)) for the run-history records — matching (o)'s own dual basis (contract for the feature; legitimate interest for the operational telemetry limb) and (aa)'s 6(1)(f). **Verdict: accurate; the table no longer understates the processor's holding.**

## Artifact 6 — Last Updated chains and house-style notes

All three documents carry the new dated amendment note demoting October 26 to `Previous:`; the mirror hero `<p>` dates match; every corrected sentence carries the `*(corrected October 27, 2026, ref #10849: …)*` note quoting the superseded phrasing (the audit-trail convention already used in these documents). **Verdict: consistent with house style.**

## Artifact 7 — Negative-claim and gate check

After stripping correction/amendment notes, zero bare assertions of "no external sub-processor", "self-hosted, operator-managed" or "not a third-party recipient" remain on any of the six surfaces (measured). `lint-legal-scope-block-placement.sh`, `lint-legal-mirror-drift-baseline.sh` (no new drift; the touched lines were outside the baseline drift set and were edited identically on both surfaces), `check-tc-document-sha.sh`, `legal-doc-consistency.test.ts` + `legal-doc-shas-guard.test.ts` (43 tests), and `probe-legal-corpus-truth.sh` all pass. No `[DRAFT` marker added. No breach event arose — this is an accuracy correction to a published description; nothing was lost, altered, or disclosed to a new recipient. **Verdict: pass.**

## Overall

| Artifact | Verdict |
|---|---|
| DPD 2.3(o) | Accurate (CLO-prescribed text, verified against sources) |
| DPD 2.3(aa) | Accurate |
| privacy-policy 4.13 | Accurate |
| gdpr-policy 3.10 | Accurate |
| DPD 4.2 Supabase row | Accurate |
| Last Updated + notes | House style |
| Gates / negative claims | Pass |

**Disposition: DISCHARGED.** No in-PR conditions. Follow-ups stay open and tracked: #10848 (Art. 5(1)(e)/17/15 reach of the Postgres history), #5150 (no automatic deletion — disclosed), #7465 (pre-existing canonical↔mirror drift remediation, unrelated positions).

*Draft material for internal attestation; not legal advice. External counsel re-review follows the frontmatter triggers.*
