---
title: "Counsel review audit — #10848 (Art. 15/17 reach of the dedicated Inngest Postgres run-history store determined; clause sweep across the register, three published docs + mirrors, and the posture item)"
type: counsel-review
date: 2026-11-02
issue: 10848
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-11-02
signed_off_by: "CLO agent function run via run_subagent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED, conditioned on the tracked follow-up #11856 (absolute age ceiling closing the never-terminal-run indefinite limb) — filed, not publication-blocking. Every added claim was verified against account-delete.ts, dsar-export-allowlist.ts, inngest-bootstrap.sh, inngest-trace-retention.sql, the Better Stack journal of inngest-trace-retention.service (2026-11-02), and the CLO ruling of the same date. Canonical and mirror carry byte-identical amendments at every touched position; SHA pins regenerated; no new transfer, purpose or processor is asserted."
non_blocking:
  - "N1 — ADR-030 carries one copy of the superseded clause inside a dated decision-record addendum; left unedited deliberately — the ADR records what was true and decided at its date; the register and published docs carry the current determination."
  - "N2 — The Redis AOF half (#8528, #7779) is a separate open sibling question, named as such in the amended text rather than resolved here."
  - "N3 — Three post-live retention runs exited `reason=batch_cap`; nightly progress continues but some tables can starve. Disclosed in the amended surfaces and tracked in #11856's residual note."
open_follow_ups: ["#11856 (absolute age ceiling on run-history tables — closes the never-terminal-run indefinite limb)", "#8528 (Art. 17 reach of the Inngest Redis AOF — sibling store)", "#7779 (Redis AOF sibling)"]
re_evaluation_triggers: "First arms-length user OR EEA-out data subject OR regulated-industry user OR an Inngest schema change adding an indexed owner column OR a subject request naming this store OR persistent batch_cap starvation preventing progress OR a substrate change (new store, region move, provider change) for the Inngest run-history/event records."
---

# Counsel review audit — #10848 (Art. 15/17 reach of the Inngest Postgres store)

v1 internal counsel-review attestation for the determination ordered by issue #10848 and rendered by CLO ruling 2026-11-02 (recorded in `knowledge-base/project/specs/feat-one-shot-10848-inngest-erasure-reach/decision-challenges.md`). Authority: CLO agent function (Soleur-as-tenant-zero v1); operator veto retained; external counsel reserved for the frontmatter triggers. Output is draft material, not legal advice.

**Method.** Each added claim was checked against `apps/web-platform/server/account-delete.ts` (zero `inngest` references across the cascade), `apps/web-platform/server/dsar-export-allowlist.ts` (`DSAR_TABLE_ALLOWLIST` covers only the app project's `public` tables; `routine_runs` exclusion precedent), `apps/web-platform/infra/inngest-bootstrap.sh` (`INNGEST_POSTGRES_URI` exported on the host only — the app holds no credential for `soleur-inngest-prd`), `apps/web-platform/infra/inngest-trace-retention.sql` (in-flight exclusion: `events` deletes only `NOT EXISTS` an unfinished `function_runs` row; `history`/`function_runs`/`function_finishes` anchor on `function_finishes`), the sender call sites (`inngest.send({ id, name, data })` — identifiers inside `data` at event-name-varying keys, `event_user` sparse), and the live journal of `inngest-trace-retention.service` (Better Stack, 2026-11-02: `INNGEST_TRACE_RETENTION_DELETED spans=1557933 traces=656095 event_batches=0 trace_runs=91957 history=863294 function_runs=1727 function_finishes=92326 events=70289`, `OUTCOME=ok` on one pass; three subsequent runs `reason=batch_cap`). Post-merge `inngest-host-replace` dispatches ran 2026-10-29 and 2026-10-30 (runs 40843766999, 41078292714, both success), so the "not yet pruning" premise is falsified and removed.

**Ruling (verbatim).** *Ruled by CLO agent, 2026-11-02: B4 — documented no-reach, conditioned on a tracked bound-tightening follow-up for the one indefinite limb; the self-serve DSAR bundle lawfully excludes this store under a documented rationale — the combination {7-day status-gated bound now live + named residuals + operator-mediated manual request path} is the compliant posture because no per-subject predicate can be constructed on this store and no founder-keyed mechanism can ever name the involuntary third-party population the bound already serves.*

## Artifact 1 — article-30-register.md (f) cells (PA-13, PA-21, PA-22, PA-27 ×2, PA-31) + PA-14 (f) sibling

| Claim added | Checked against | Verdict |
|---|---|---|
| erasure cascade does not reach the store | `account-delete.ts` — zero `inngest` matches | TRUE |
| DSAR export does not reach the store | `dsar-export-allowlist.ts` — app-project `public` only | TRUE |
| `event_user` sparse; identifiers inside `data` payloads | sender call sites (`inngest.send` grep) | TRUE |
| involuntary third-party subjects unnameable by founder-keyed predicate | `sender`/`subject`/`recipients` payload keys, no account | TRUE |
| prune live on replaced host; `OUTCOME=ok`; `batch_cap` residual | Better Stack journal 2026-11-02; replace runs 40843766999/41078292714 | TRUE |
| never-terminal-run indefinite limb; age-ceiling follow-up | `inngest-trace-retention.sql` anchors; #11856 filed | TRUE |
| six never-pruned tables | retention SQL table set | TRUE |

The appended `**Added 2026-11-02 (#10848, CLO ruling …)**` markers record the determination without rewriting the superseded sentences (house pattern). **Verdict: accurate.**

## Artifact 2 — DPD §2.3(o) + §2.3(aa) (canonical + mirror)

The clause tail is replaced per ruling text: the falsified "host not yet replaced … not yet pruning" conditional is dropped (two post-merge replaces evidenced), the live-pruning fact plus the batch-cap residual is recorded, and the determination sentence names no-reach, the unnameable affected set, the never-terminal limb, and the manual named-request path. §2.3(aa) adds the involuntary-subject limb (inbound senders/recipients hold no account; Art. 14(5)(b) disproportionate-effort posture). **Verdict: accurate.**

## Artifact 3 — privacy-policy + gdpr-policy recipients bullets (canonical + mirror)

Subject-facing register of the same determination: no per-subject erasure or export path; the 7-day job now runs on the host; never-terminal-run residual; manual named-request path. GDPR bullet keeps the ADR-269 recipients-routing text untouched. **Verdict: accurate.**

## Artifact 4 — compliance-posture.md

PA-27 Active Items (iv) rewritten in-cell to the determined state; the 2026-10-22 comment's "Open: … #10848" claim superseded inline; new dated 2026-11-02 comment block records the determination. **Verdict: accurate.**

## Artifact 5 — Last Updated chains + SHA pins + amendment notes

Canonical `**Last Updated:**` moved to November 2, 2026 on all three docs with the house-form note ("not a new purpose, sub-processor or international transfer"); mirror hero `<p>` moved identically; `LEGAL_DOC_SHAS` re-pinned to the edited canonical bytes; every amendment note quotes the superseded phrase verbatim (paren-depth-aware absence sweep finds zero residual copies of the undetermined clause asserted as current). **Verdict: house style.**

## Overall

| Artifact | Verdict |
|---|---|
| Register (f) cells + PA-14 sibling | Accurate |
| DPD §2.3(o) / §2.3(aa) | Accurate |
| privacy-policy / gdpr-policy bullets | Accurate |
| compliance-posture item (iv) + comments | Accurate |
| Last Updated + notes + SHA pins | House style |
| Conditional implementation branch | Not activated — ruling is B4; the age-ceiling limb is tracked at #11856 |

**Disposition: DISCHARGED**, conditioned on tracked follow-up #11856 (the ruling's one required limb; filed, not publication-blocking). Follow-ups stay open and tracked: #11856 (age ceiling), #8528 / #7779 (Redis AOF siblings — named, out of scope), #7465 (pre-existing canonical↔mirror drift, unrelated positions).

*Draft material for internal attestation; not legal advice. External counsel re-review follows the frontmatter triggers.*
