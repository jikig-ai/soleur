---
title: "legal: correct the published 'no external sub-processor' statement for the Inngest run-history store (data-protection-disclosure 2.3(o))"
type: chore
date: 2026-10-27
slug: legal-inngest-subprocessor-correction
branch: feat-one-shot-10849-inngest-dpd-subprocessor
issue: 10849
closes: 10849
lane: single-domain
domain: legal
priority: p2-medium
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# legal: correct the published 'no external sub-processor' statement for the Inngest run-history store (data-protection-disclosure 2.3(o))

## Overview

A CLO ruling dated 2026-10-22 (recorded in `knowledge-base/legal/audits/2026-10-counsel-review-9927.md`, Artifact 4) found that the published sentence in `docs/legal/data-protection-disclosure.md` §2.3(o) — "self-hosted Inngest OSS on Hetzner, eu-central, no external sub-processor" — mis-describes a recipient (GDPR Arts. 13(1)(e), 5(1)(a)). The Inngest server's run-history and event records live in a **dedicated Supabase Postgres project** (`soleur-inngest-prd`, ref `pigsfuxruiopinouvjwy`, eu-west-1, Ireland), so Supabase Inc is a recipient. Supabase is already a listed processor (§4.2, DPA signed 2026-03-19), so the EU and no-transfer conclusions stand; the defect is the false "no external sub-processor" claim. This plan implements the CLO's prescribed correction verbatim where the ruling dictates text, and applies the same recipient description to the three imprecise sibling sentences the ruling names, on **both** the canonical corpus (`docs/legal/`) and the published Eleventy mirror (`plugins/soleur/docs/pages/legal/`), with SHA re-pin and a counsel-review attestation.

## Problem Statement / Motivation

- `docs/legal/data-protection-disclosure.md` §2.3(o) asserts "no external sub-processor" while its own retention paragraph two paragraphs later names "a dedicated Supabase Postgres project" as one of the three Inngest stores — an internally contradictory, published mis-description of a recipient.
- `docs/legal/data-protection-disclosure.md` §2.3(aa) repeats the defect: "persist in the self-hosted, operator-managed Inngest event store … a PII surface, **not a third-party recipient**" — Supabase Inc IS a recipient of those records.
- `docs/legal/privacy-policy.md` §4.13 (the issue cites §5.9; the sentence actually lives in §4.13's Sub-processors bullet — §5.9 is the Resend section it cross-references) says the same values "persist in a self-hosted, operator-managed event store on EU infrastructure".
- `docs/legal/gdpr-policy.md` (PA-27 recipients bullet) says recipient addresses "persist in the self-hosted Inngest event store".
- §4.2's Supabase row lists no run-history/event data category — the published processor table understates what Supabase holds.

## Proposed Solution

Apply the CLO's proposed §2.3(o) replacement verbatim (verified claim-by-claim against `apps/web-platform/infra/inngest.tf`, `inngest-bootstrap.sh`, `inngest-server.md`, ADR-105 — see Research Insights), plus house-style `*(corrected <date>, ref #10849: …)*` notes at each corrected sentence, updated `Last Updated` chains on all three documents, identical edits on canonical and mirror, and `legal-doc-shas.ts` re-pin. The exact before/after strings are specified in Implementation Phases; every added claim traces to a named repo source.

## Technical Considerations

- **Mirror drift ratchet** (`scripts/lint-legal-mirror-drift-baseline.sh`): drift at HEAD must be a subsequence of drift at merge base; in-place edits of already-drifting lines and new drift content fail. Verified at planning time: **none of the six target lines is in the current drift set** (canonical and mirror agree on every one), so byte-identical edits on both surfaces leave the drift sequence unchanged. Baseline at `origin/main` (`2e9874c`): 80 drift lines, gate green.
- **Correction-note quoting trap**: the prescribed `*(corrected … stated 'no external sub-processor')*` note QUOTES the superseded phrase. Any absence-grep AC must first strip `*(corrected …)*`/`*(Corrected …)*` spans (the `probe_legal_corpus_truth.py` pattern) or it false-fires on its own audit trail.
- **Last-Updated two-shape trap** (sharp-edge): the canonical body line is `**Last Updated:** October 27, 2026` (colon + bold) while the mirror ALSO carries a hero line `<p>Effective February 20, 2026 | Last Updated October 27, 2026</p>` (no colon, stripped by `normalize_plugin` so it is drift-invisible but user-visible). Both must move; AC greps must tolerate `Last Updated[: *]+` punctuation.
- **SHA re-pin**: `apps/web-platform/lib/legal/legal-doc-shas.ts` holds `LEGAL_DOC_SHAS["<doc>"] = sha256(raw bytes)`; `check-tc-document-sha.sh` fails CI on a stale pin. Re-pin all three edited canonical docs.
- **NFR impacts**: none — published-docs accuracy only; no runtime code, no migration, no infra.

## Research Insights

**Premise validation (Phase 0.6) — every cited claim verified against source before drafting:**

| Claim | Source checked | Result |
|---|---|---|
| §2.3(o) says "no external sub-processor" | `docs/legal/data-protection-disclosure.md` §2.3(o) opening parenthetical | TRUE at line 193 |
| Run-history/events live in a dedicated Supabase Postgres project | `inngest-server.md` ("events live in Supabase Postgres and the queue/run-state lives in Redis"; `--postgres-uri` = configuration and history persistence) + `inngest-bootstrap.sh` (`INNGEST_POSTGRES_URI` via doppler env; SQLite only as `REDIS_READY=0` fail-safe) | TRUE |
| Project is eu-west-1 (Ireland) | `apps/web-platform/infra/inngest.tf` comment: "project: soleur-inngest-prd ref: pigsfuxruiopinouvjwy region: eu-west-1"; runbook pooler host `aws-0-eu-west-1.pooler.supabase.com` | TRUE (region source is the runbook/TF, NOT ADR-105 — CLO audit N1) |
| ADR-105 names the project | `ADR-105-*.md`: "dedicated durable-backend Supabase project (soleur-inngest-prd, ref pigsfuxruiopinouvjwy)" — no region | TRUE |
| Queue and run state held in Redis on that host | `inngest-bootstrap.sh`: `INNGEST_REDIS_URI="redis://…@127.0.0.1:6379"` constructed from password; AOF on attached LUKS volume | TRUE |
| Supabase already a listed §4.2 processor, DPA 2026-03-19 | DPD §4.2 Supabase row + §6 transfer-safeguard line "DPA signed 2026-03-19 via PandaDoc" | TRUE |
| SQLite is a third store (degraded fail-safe) | §2.3(o) retention paragraph + `inngest-bootstrap.sh` `unset INNGEST_POSTGRES_URI` fail-safe arm | TRUE — the CLO's replacement names only the two durable stores; the SQLite fail-safe remains disclosed in the retention paragraph, unchanged |

**Property List (Phase 0.6b):** (1) §2.3(o) no longer asserts "no external sub-processor" as a claim; (2) every published surface describing the Inngest event/run-history store names Supabase Inc as the record holder's operator; (3) §4.2's Supabase row covers the run-history/event category; (4) each correction carries the house audit-trail note + bumped Last Updated; (5) all five legal CI gates stay green.

**Cut List:** none — the ask names no new mechanism; every property is bought by the doc edits + re-pin the issue prescribes.

**Institutional learnings applied:** `plan-sharp-edges.md` — the Last-Updated hero/body punctuation split; absence-grep vs. legitimate-occurrence trap; every-added-claim-traces-to-source AC requirement; diff-scope ACs must include pipeline-written files.

**Collision checks:** `gh pr list linked:issue #10849 --state all` → none; `#10849 in:body` merged → only #10652 (the C1 measurement PR that *recorded* the finding — cited predecessor, different scope); `#10849 in:body` open → none; open-issue dup search → none identical (#9073/#9074 are adjacent, different questions); worktree noun grep → no sibling.

**Related records:** the Art. 30 register PA-13 (e)/(f) and PA-27 (d)/(f) markers were already corrected by #9927/PR #10652 (Superseded markers in `article-30-register.md`) — **out of scope**, already accurate. `knowledge-base/legal/audits/2026-10-counsel-review-9927.md` is the controlling ruling; its N1 notes the issue's ADR-105 region attribution was wrong (runbook is the region source — verified, used above).

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality on disk | Plan response |
|---|---|---|
| "privacy-policy.md section 5.9 ('self-hosted, operator-managed event store on EU infrastructure')" | The sentence lives in **§4.13**'s Sub-processors bullet (§5.9 is the Resend processor section the bullet cross-references); §5.9 contains no such sentence | Edit §4.13 where the sentence actually is; cite the discrepancy in the plan and PR body |
| "(o) … 'no external sub-processor' … Verify each claim against ADR-105 and `apps/web-platform/infra`" | Verified — all hold; region is additionally pinned by `inngest.tf` + runbook (ADR-105 has no region, per the CLO's own N1) | Draft from sources, not from the ruling's wording alone |
| "disclosure (aa) repeating the phrasing" | Confirmed — (aa) carries "self-hosted, operator-managed Inngest event store" AND "a PII surface, not a third-party recipient" | Correct both limbs |

## Open Code-Review Overlap

None — 98 open `code-review` issues scanned; zero bodies name any of the seven planned file paths or `knowledge-base/legal/audits`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a data subject (including an *involuntary* one — a sender to `ops@soleur.ai` or a person mentioned in such mail) reads the published Data Protection Disclosure at `soleur.ai/legal/data-protection-disclosure/` and is told the store holding their subject line, address and recipient addresses has "no external sub-processor" — a published Art. 13(1)(e)/5(1)(a) inaccuracy they can cite against Jikigai.
- **If this leaks, the user's data is exposed via:** the already-published false claim itself — the exposure vector is the public page; shipping the correction removes it.
- **Brand-survival threshold:** `single-user incident` — a published legal mis-statement about where one person's data rests is exactly the per-subject harm class.
- **Threshold decision (challengeable):** chosen over `aggregate pattern` because the mis-description harms each individual reader/data-subject on its own — no aggregation needed — and it routes the ship-time Counsel-Review CLO-Attestation Gate the issue requires.

CPO sign-off required at plan time before `soleur:work` begins. Headless pipeline note: recorded here for `soleur:ship` Phase 6 rendering; `soleur:engineering:review:user-impact-reviewer` runs at review time per the review skill's conditional-agent block.

## Scope Check

### Ask Mapping

| # | User ask (verbatim, issue #10849) | Plan item | Status |
|---|-----------------------------------|-----------|--------|
| 1 | "a published sentence in `docs/legal/data-protection-disclosure.md` section 2.3(o) (and its mirror `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`) says 'self-hosted Inngest OSS on Hetzner, eu-central, no external sub-processor'" | Phase 1 edit (DPD §2.3(o), canonical + mirror) | mapped |
| 2 | "`privacy-policy.md` section 5.9 ('self-hosted, operator-managed event store on EU infrastructure')" | Phase 2 edit (privacy-policy §4.13 — actual sentence location; §5.9 verified clean) | mapped |
| 3 | "`gdpr-policy.md` ('persist in the self-hosted Inngest event store')" | Phase 3 edit (gdpr-policy recipients bullet, canonical + mirror) | mapped |
| 4 | "Section 4.2's Supabase row lists no run-history or event data category" | Phase 4 edit (DPD §4.2 Supabase row, canonical + mirror) | mapped |
| 5 | "`data-protection-disclosure.md` (aa) repeats the 'self-hosted, operator-managed' phrasing" | Phase 5 edit (DPD §2.3(aa), canonical + mirror) | mapped |
| 6 | "Proposed 2.3(o) replacement: '(self-hosted Inngest OSS on Hetzner, eu-central; its queue and run state are held in a Redis store on that host, and its run-history and event records are held in a dedicated Supabase Postgres project in eu-west-1 (Ireland), operated by Supabase Inc, a processor already listed in Section 4.2; no processor outside Section 4.2 is involved;'" | Phase 1 — applied verbatim | mapped |
| 7 | "the house-style '(corrected <date>, ref #N: an earlier version stated 'no external sub-processor')' note and an updated `Last Updated`" | Phase 6 — correction notes per site + Last Updated chain on all three docs + mirror hero lines | mapped |
| 8 | "Verify each claim against ADR-105 and `apps/web-platform/infra` before drafting; do not hand-write it from this ruling" | Research Insights verification table (done at plan time) + work-phase re-verify | mapped |
| 9 | "Needs the docs/legal CI gates, mirrors, SHA re-pin and a counsel-review attestation pass" | Phase 7 (SHA re-pin) + Phase 8 (gate suite) + Phase 9 (CLO-attestation audit artifact) | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|-------------------|---------|
| `docs/legal/data-protection-disclosure.md` | ask 1, 4, 5 | asked |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | ask 1 ("and its mirror") | asked |
| `docs/legal/privacy-policy.md` + mirror | ask 2 | asked |
| `docs/legal/gdpr-policy.md` + mirror | ask 3 | asked |
| `apps/web-platform/lib/legal/legal-doc-shas.ts` | ask 9 ("SHA re-pin") | asked |
| `knowledge-base/legal/audits/2026-10-counsel-review-10849.md` (create) | ask 9 ("counsel-review attestation pass") | asked |
| `knowledge-base/project/specs/feat-one-shot-10849-inngest-dpd-subprocessor/{tasks,session-state,decision-challenges}.md` | — | inferred — pipeline artifacts the one-shot contract writes (session-state, tasks) plus the ADR-084 decision-challenge ledger |
| `scripts/lint-legal-registers.sh` waiver row (conditional) | — | inferred — only if the new audit file trips the Art. 33 producer-pattern check; the gate's own mechanism for non-determination audits |

### Split Assessment

- Subsystems touched: 3 — `docs/`, `plugins/soleur/docs/`, `apps/web-platform/lib/` (+ `knowledge-base/` artifacts)
- Planned files: 8 edited + 1 created (+ ≤3 spec-dir artifacts)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — none met (est. ~40 changed lines of prose + 3 SHA strings)
- Recommendation: single PR

## Domain Review

**Domains relevant:** Legal

### Legal

**Status:** reviewed
**Assessment:** This IS a legal-surface change authored under a recorded CLO ruling (2026-10-22, `audits/2026-10-counsel-review-9927.md`). The ruling supplies the §2.3(o) replacement verbatim; the sibling-sentence rewrites are new drafting and are routed back through the CLO-attestation pass (Phase 9) rather than shipped unreviewed. Product/UX: NONE — no user-facing UI file in Files to Edit (mechanical scan: all targets are `*.md` legal docs + one `*.ts` constants map). Engineering/Ops/Finance/Marketing/Sales/Support/Product: no cross-domain implication — the substrate is unchanged; only its description is corrected.

## Implementation Phases

### Phase 0 — Re-verify sources (work Phase 0.5)

Re-`git fetch origin main` and re-run the collision re-probe over the eight touched paths (`gh pr list --state open --json number,files` intersect planned files). Re-read each target line on the CURRENT tree — sibling legal PRs land weekly.

### Phase 1 — DPD §2.3(o) parenthetical (canonical + mirror)

Replace, byte-identically in `docs/legal/data-protection-disclosure.md` and `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`:

`self-hosted Inngest OSS on Hetzner, eu-central, no external sub-processor` → `self-hosted Inngest OSS on Hetzner, eu-central; its queue and run state are held in a Redis store on that host, and its run-history and event records are held in a dedicated Supabase Postgres project in eu-west-1 (Ireland), operated by Supabase Inc, a processor already listed in Section 4.2; no processor outside Section 4.2 is involved *(corrected October 27, 2026, ref #10849: an earlier version stated 'no external sub-processor')*`

(The remainder of the parenthetical — the read-surface/ingest-port clause and its September correction trail — is untouched.)

### Phase 2 — privacy-policy §4.13 (canonical + mirror)

Replace `additionally persist in a self-hosted, operator-managed event store on EU infrastructure (the same self-hosted Inngest store described in the Data Protection Disclosure, Section 2.3(o))` → `additionally persist in the Inngest run-history and event store held in a dedicated Supabase Postgres project in eu-west-1 (Ireland), operated by Supabase Inc — a processor already listed in this Section and in the Data Protection Disclosure, Section 4.2 (the same Inngest store described in the Data Protection Disclosure, Section 2.3(o)) *(corrected October 27, 2026, ref #10849: an earlier version described the store as 'a self-hosted, operator-managed event store on EU infrastructure'; its records are held in a Supabase Postgres project operated by Supabase Inc)*`

### Phase 3 — gdpr-policy recipients bullet (canonical + mirror)

Replace `persist in the self-hosted Inngest event store alongside subject and sender` → `persist in the Inngest run-history and event store held in a dedicated Supabase Postgres project in eu-west-1 (Ireland), operated by Supabase Inc — a processor already listed in this policy's processor mapping — alongside subject and sender *(corrected October 27, 2026, ref #10849: an earlier version described the store as 'the self-hosted Inngest event store'; its records are held in a Supabase Postgres project operated by Supabase Inc)*`

### Phase 4 — DPD §4.2 Supabase row (canonical + mirror)

In the `**Web Platform Processors:**` table, extend the Supabase row's Processing-Activity cell `Web Platform auth + database` → `Web Platform auth + database; Inngest run-history and event records (dedicated project, eu-west-1, Ireland)` and its Data-Processed cell to append `, Inngest run-history and event records (Sections 2.3(o) and 2.3(aa))`.

### Phase 5 — DPD §2.3(aa) (canonical + mirror)

Replace `persist in the self-hosted, operator-managed Inngest event store (the same self-hosted Inngest store described in Section 2.3(o); the self-hosted Inngest server performs no automatic deletion of stored events, so this copy persists until operator-side store maintenance; a PII surface, not a third-party recipient)` → `persist in the Inngest run-history and event store held in a dedicated Supabase Postgres project in eu-west-1 (Ireland), operated by Supabase Inc — a processor already listed in Section 4.2 and in this entry's sub-processor list (the same Inngest store described in Section 2.3(o); the Inngest server performs no automatic deletion of stored events, so this copy persists until operator-side store maintenance) *(corrected October 27, 2026, ref #10849: an earlier version described this store as 'self-hosted, operator-managed' and 'a PII surface, not a third-party recipient'; its records are held in a Supabase Postgres project operated by Supabase Inc, already named in this entry's sub-processor list)*`

### Phase 6 — Last Updated chains (all three docs, canonical + mirror + hero)

On each of the three documents: rewrite `**Last Updated:** October 26, 2026 *(…)*` → `**Last Updated:** October 27, 2026 *(<one-sentence note naming the corrected sections, in the established house form "This corrects a statement, not what is processed: … no new purpose, sub-processor or international transfer beyond the processor named")* Previous: October 26, 2026 *(…)*` (the existing note chain demotes one step, verbatim). On each mirror also bump the hero `<p>Effective … | Last Updated October 26, 2026</p>` → `October 27, 2026`.

### Phase 7 — SHA re-pin

`sha256sum docs/legal/{data-protection-disclosure,privacy-policy,gdpr-policy}.md` → update the three entries in `apps/web-platform/lib/legal/legal-doc-shas.ts` in the same commit.

### Phase 8 — Gate suite (before commit → ship)

Run all five legal-corpus gates locally: `lint-legal-scope-block-placement.sh --base origin/main`, `lint-legal-mirror-drift-baseline.sh --base origin/main`, `apps/web-platform/scripts/check-tc-document-sha.sh`, `apps/web-platform/test/legal-doc-consistency.test.ts` + `legal-doc-shas-guard.test.ts`, `probe-legal-corpus-truth.sh`. Then the affected-suites runner.

### Phase 9 — Counsel-review attestation (CLO function, run inline on this harness)

Produce `knowledge-base/legal/audits/2026-10-counsel-review-10849.md` in the established house shape (frontmatter `type: counsel-review`, `status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)`, `disposition`, `re_evaluation_triggers`; per-artifact verdict table). Method per `agents/legal/clo.md`: each added sentence cross-checked against `inngest-server.md`, `inngest.tf`, `inngest-bootstrap.sh`, ADR-105 and the CLO ruling; confirm no new `[DRAFT` marker; confirm mirror/canonical lockstep; DISCHARGED or BLOCKED disposition. Emit the one-line `COUNSEL-REVIEW: …` veto notice. If the audit file trips `lint-legal-registers.sh`'s producer pattern, add its waiver row in the same commit.

## Files to Edit

- `docs/legal/data-protection-disclosure.md` — §2.3(o), §2.3(aa), §4.2 Supabase row, Last Updated
- `docs/legal/privacy-policy.md` — §4.13 bullet, Last Updated
- `docs/legal/gdpr-policy.md` — recipients bullet, Last Updated
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — identical four edits + hero date
- `plugins/soleur/docs/pages/legal/privacy-policy.md` — identical two edits + hero date
- `plugins/soleur/docs/pages/legal/gdpr-policy.md` — identical two edits + hero date
- `apps/web-platform/lib/legal/legal-doc-shas.ts` — three SHA strings
- `scripts/lint-legal-registers.sh` — CONDITIONAL: one waiver row, only if Phase 9's audit trips the Art. 33 producer pattern

## Files to Create

- `knowledge-base/legal/audits/2026-10-counsel-review-10849.md` — the attestation artifact
- `knowledge-base/project/specs/feat-one-shot-10849-inngest-dpd-subprocessor/tasks.md`, `session-state.md`, `decision-challenges.md` — pipeline artifacts

## Acceptance Criteria

- [ ] AC1: After stripping `*(corrected …)*`/`*(Corrected …)*` spans, `grep -c 'no external sub-processor'` on `docs/legal/data-protection-disclosure.md` AND its mirror is 0.
- [ ] AC2: §2.3(o) on BOTH surfaces contains the CLO-prescribed clause verbatim: `dedicated Supabase Postgres project in eu-west-1 (Ireland), operated by Supabase Inc, a processor already listed in Section 4.2`.
- [ ] AC3: After stripping correction-note spans, `grep -c 'self-hosted, operator-managed'` on all six legal surfaces is 0; `grep -c 'a PII surface, not a third-party recipient'` on both DPD surfaces is 0; `grep -c 'self-hosted Inngest event store'` on both gdpr-policy surfaces is 0.
- [ ] AC4: §4.2's Supabase row names the run-history/event category on BOTH surfaces; the row's other cells are otherwise unchanged.
- [ ] AC5: Each of the three docs' canonical Last Updated body line opens `**Last Updated:** October 27, 2026` and demotes October 26 to `Previous:`; each mirror's hero `<p>` reads `Last Updated October 27, 2026`.
- [ ] AC6: `LEGAL_DOC_SHAS` entries for the three docs equal `sha256sum` of the edited canonical files.
- [ ] AC7: All five legal-corpus gates pass: `lint-legal-scope-block-placement.sh`, `lint-legal-mirror-drift-baseline.sh` (no new drift lines at the touched positions — verified via the gate's report), `check-tc-document-sha.sh`, `legal-doc-consistency.test.ts` + `legal-doc-shas-guard.test.ts`, `probe-legal-corpus-truth.sh`.
- [ ] AC8: `knowledge-base/legal/audits/2026-10-counsel-review-10849.md` exists with `disposition: DISCHARGED` or the PR halts on the named blocker; the audit's every-checked claim cites a repo source.
- [ ] AC9: Every claim the diff ADDS (eu-west-1, Redis on-host, dedicated project, Supabase Inc operator, already-listed-processor) is traceable to a named source line (inngest.tf comment / inngest-bootstrap.sh / inngest-server.md / §4.2 row).
- [ ] AC10: The diff touches only the files enumerated in `## Files to Edit`/`## Files to Create` (including spec-dir + audit artifacts).

## Test Scenarios

- Given the edited tree, when `bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main` runs, then exit 0 and its report shows no drift pair at any touched position. (`integration`)
- Given the SHA re-pin, when `bash apps/web-platform/scripts/check-tc-document-sha.sh` runs, then exit 0. (`integration`)
- Given correction notes quote the superseded phrase, when `sed -E 's/\*\((C|c)orrected[^*]*\)//g' docs/legal/*.md plugins/soleur/docs/pages/legal/*.md | grep -c 'no external sub-processor\|self-hosted, operator-managed'`, then output `0`. (`unit`)
- Given the six surfaces, when each edited sentence is diffed canonical-vs-mirror at the touched positions, then the added text is byte-identical. (`unit`)

## Context

- Issue: #10849 (OPEN, labels: legal, domain/legal, type/chore, priority/p2-medium; target within 14 days of filing)
- Controlling ruling: `knowledge-base/legal/audits/2026-10-counsel-review-9927.md` (Artifact 4 + conditions C1/C2 already applied by #10652)
- Substrate truth: `inngest-server.md`, `apps/web-platform/infra/inngest.tf`, `apps/web-platform/infra/inngest-bootstrap.sh`, `ADR-105-inngest-postgres-footprint-per-pool-cap-and-idle-drain.md`
- Out of scope: Art. 30 register PA-13/PA-27 markers (already corrected by PR #10652); #10848 (Art. 5(1)(e)/17/15 reach of the Postgres history — separate tracked issue); #5150 (no-automatic-deletion retention gap — already disclosed); internal KB prose (runbooks, audits) that loosely says "self-hosted Inngest store" — the issue scopes published docs only; the attestation may note these as non-blocking.

## Sharp Edges

- The mirror is the published surface — a canonical-only edit changes nothing a user sees; every edit lands on both.
- Correction notes QUOTE the superseded phrase — absence greps must strip `*(corrected …)*` spans first.
- Last Updated has TWO shapes (canonical `**Last Updated:**`, mirror hero `<p>…Last Updated…</p>` without colon); both move; the hero line is drift-invisible but user-visible.
- `soleur:work` must re-read each target line at edit time — the amendment chain means a sibling merge re-anchors the Last Updated chain under this plan.
- `requires_cpo_signoff: true` is declared per the single-user-incident threshold; headless pipeline records it for ship Phase 6 rather than pausing.

## References

- #10849 (work target); #9927 / PR #10652 (ruling + register markers, citation only); ADR-105 (citation); #10848, #5150 (adjacent open items, out of scope)
