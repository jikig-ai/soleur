---
title: "compliance: establish Art. 15/17 reach of the Inngest Postgres run-history store and amend the five PA (f) rows + DPD §2.3(o)"
type: fix
date: 2026-11-02
slug: compliance-inngest-erasure-reach
branch: feat-one-shot-10848-inngest-erasure-reach
issue: 10848
lane: cross-domain
requires_cpo_signoff: true
---

# compliance: establish Art. 15/17 reach of the Inngest Postgres run-history store and amend the five PA (f) rows + DPD §2.3(o)

## Enhancement Summary

**Deepened on:** 2026-11-02
**Sections enhanced:** 4 (Phase 1 ruling brief, Phase 3 amendment phase, new
`## Encryption Posture`, AC9 rule-id correction)
**Research agents used:** none spawnable on this harness — all deepen passes
ran inline sequential (`Reviewed-Coverage: sequential-fallback` disclosure);
the external-source pass ran via direct web search (EDPB CEF erasure report).

### Key Improvements

1. **Binding-ruling brief strengthened:** Phase 1 now enumerates, per
   disposition option, the fact that would disqualify it (EDPB caution +
   unbounded in-flight exclusion + possibly-not-live timer, against "the
   bound discharges erasure"; no user-indexed column + open identifier
   census + unnameable third-party population, against "per-subject
   mechanism required").
2. **Falsified-negatives sweep added to Phase 3:** the determination
   performs the verification the corpus calls not-yet-done, so every
   paraphrase of the undetermined state is swept — not only the clause's
   own vocabulary (PR #10337 class).
3. **Encryption Posture emitted:** the Phase 4.10 trigger fires on the
   conditional new cross-component connection; the section records the
   existing `supabase.inngest` ledger row and the branch-activation
   obligation.

### New Considerations Discovered

- Rule-id citation corrected: AC9 now cites
  `wg-when-deferring-a-capability-create-a` (verified in `AGENTS.rules.md`).
- §4.5 network-outage trigger matched only the literal `SSH` inside the
  git-data erasure mechanism description — no network-connectivity symptom
  is addressed by this plan, so the checklist does not apply (recorded in
  lieu of a `## Hypotheses` section).
- Halt-gate record: 4.6 pass, 4.7 pass (probe `CORPUS-OK`), 4.8 pass
  (no PAT shape), 4.9 skip (no UI surface), 4.10 pass (section added),
  4.11 skip (no guard deliverable — AC greps are verification commands,
  not new controls), 4.12 pass (one live Scope Check, all rows justified),
  4.13 skip (no new autonomous-task surface in the definite diff — the
  Phase 5 conditional branch re-derives it), 4.55 skip (docs-class diff).

## Overview

Issue #10848 is the compliance half of the Inngest run-history finding: the
Postgres half of the self-hosted Inngest store is a dedicated Supabase project
(EU, `soleur-inngest-prd`) whose `events`, `history`, `function_runs` and
`spans` rows can carry founder and third-party identifiers inside event
payloads. The retention half was discharged by merged PR #11311 (a 7-day
status-gated prune delivered as a host timer via `inngest-bootstrap.sh`). What
remains undetermined — and is this issue's entire remaining work — is whether
the Article 17 erasure cascade (`apps/web-platform/server/account-delete.ts`)
and the Article 15 self-serve export
(`apps/web-platform/server/dsar-export-allowlist.ts`) reach this store. Verified
at plan time: neither does — `account-delete.ts` contains no Inngest reference
across its ~30 cascade steps, the DSAR allowlist covers only the app project's
`public` tables, and the web app holds no credential for the Inngest project
(only the Inngest server on the dedicated host connects, via
`INNGEST_POSTGRES_URI` exported by `inngest-bootstrap.sh`). The published
disclosure currently says the 7-day removal "is not account deletion and is
not a response to an access or erasure request" — an honest negative statement
with no recorded determination behind it.

This plan produces the determination: the factual findings are recorded here,
the legal ruling is a prescribed `soleur:legal:clo` consult at work Phase 1
(delivered against the evidence pack below, ruling recorded in
`decision-challenges.md` and a counsel-review audit file). The doc amendments
then record whatever the ruling says — PA-13/21/22/27/31 (f) cells in
`knowledge-base/legal/article-30-register.md`, the `is not account deletion`
clause's every copy in the published corpus (DPD §2.3(o) + §2.3(aa),
privacy-policy, gdpr-policy, three mirrors, `compliance-posture.md`), with the
SHA re-pin and counsel-review attestation the legal-corpus pipeline requires.
If the ruling requires a per-subject reach the store does not have, a
conditional implementation branch (B1–B3 candidates) activates with its own
IaC / ADR / observability deliverables.

## Problem Statement / Motivation

The 7-day bound is a storage-limitation control (Art. 5(1)(e)); it is not, and
the merged retention PR explicitly declined to be, an erasure or access
mechanism. Article 17 asks: when a founder deletes their account, do residual
Inngest rows that identify them get erased without undue delay? Article 15
asks: does the DSAR bundle disclose what this store holds about the subject?
Both are undetermined: the cascade never reaches the store, the export never
reads it, and no user-indexed path exists on it — `events.event_user` is
Inngest's top-level user field but the repo's own senders leave it sparse and
put identifiers inside `data` payloads at event-name-varying keys
(`founderId`, `userId`, plus third-party `sender`/`subject`/`recipients` for
inbound-mail events), so per-subject reach cannot even be bounded by a column
predicate. The issue's user-impact is a single-subject incident class: a
retained, unindexed history of event payloads that may identify one user with
no established erasure path.

## Proposed Solution

1. **Factual determination (recorded in this plan — done at plan time):**
   account-delete does not reach the store; the DSAR export does not read it;
   no app-side credential or user-indexed column path exists; the 7-day bound
   deletes all eight user-bearing tables' finished-run rows ≤7 days after run
   end, except events referenced by still-unfinished runs; the six protected
   tables (`apps`, `functions`, `worker_connections`, `migrations`,
   `goose_db_version`, `queue_snapshot_chunks`) are not pruned; the timer may
   not yet be enabled on the live host (delivered at host birth, behind the
   `apply_target=inngest-host-replace` acknowledgement).
2. **Legal ruling (work Phase 1, `soleur:legal:clo` consult):** whether
   Art. 17 requires a per-subject erasure mechanism on this store or whether
   the combination {documented no-reach + bounded residue + named residual
   edges} is the compliant posture; same question for Art. 15 and the
   self-serve bundle. The evidence pack below is the ruling input; the EDPB's
   2025 coordinated-enforcement finding that relying on automatic retention
   periods for erasure requests drew supervisory concern is included so the
   "the bound discharges it" position is not assumed uncontroversial.
3. **Doc amendments (the always-deliverable):** every copy of the clause
   "this removal is not account deletion and is not a response to an access or
   erasure request" is extended by the recorded determination — what the reach
   answer is, whose ruling produced it, and the named residuals (in-flight
   exclusion, host-may-not-yet-be-pruning, involuntary third-party subjects,
   `event_user` cannot bound the affected set).
4. **Conditional implementation (ruling-gated):** only if the CLO ruling
   requires a reach that does not exist — candidates B1–B3 below, chosen by
   the ruling, never assumed.

## Technical Considerations

- **Where identifiers actually live.** `event_user` is by-name user-capable
  but the repo's senders (Stripe route, GitHub route, resend-inbound route,
  dashboard send route) put the founder id inside `data` — e.g.
  `data.founderId` (GitHub route), `data.userId` (Stripe-derived), and inbound
  mail puts `sender`/`subject`/`recipients` (third-party PII — involuntary
  subjects who hold no account and whose erasure cannot be keyed on a founder
  id anyway). Per `measurements.md` (#9927): "an empty or sparse `event_user`
  can neither define nor bound the affected set."
- **The bound's residue shape.** `inngest-trace-retention.sql` deletes from
  `spans`, `traces`, `event_batches`, `trace_runs` (status-gated on
  `trace_runs.status IN (50,300,400,500,600)` + `ended_at < now-7d`), and
  `history`, `function_runs`, `function_finishes` (via `function_finishes`
  anchor), plus `events` (age + `NOT EXISTS` unfinished run reference). A
  subject's rows therefore survive at most (longest in-flight run) + 7 days;
  an event referenced by a run that never reaches a terminal status persists
  indefinitely — the named residual edge the ruling must address.
- **Two subject populations.** Founder-keyed identifiers AND involuntary
  third-party subjects (inbound senders/recipients, GitHub handles inside
  payloads). Any per-subject mechanism keyed on a founder id structurally
  cannot name the second population; the bound is the only control that serves
  them. The ruling brief must not let "per-user erasure" silently mean
  "per-founder erasure."
- **Candidate implementation branches (ruling selects, never assumed):**
  - **B1 — host-side erasure job.** Extend the existing
    `inngest-trace-retention` pipeline with a per-subject erasure manifest.
    Blocker to resolve: no app→host data channel exists other than the Inngest
    event API; a manifest needs a new edge (a table the host job reads, fed by
    the app via a new credential, or a Doppler-delivered list). New
    cross-component connection → ADR + C4 + Encryption-Posture deliverables.
  - **B2 — app-side direct purge.** A second Supabase client in the web app
    holding a scoped key for `soleur-inngest-prd`, a new `account-delete`
    cascade step issuing `DELETE … WHERE data->>'founderId' = :uid` (plus a
    key census per event name — the open-enumeration class). New credential
    edge; heavy; enumeration-fragile.
  - **B3 — upstream minimisation.** Stop writing founder identifiers into
    event payloads (precedent: the GitHub route already dropped `founderId` at
    schema v=3, consumer re-derives). Shrinks the store's personal-data
    footprint going forward; does not reach already-stored rows or
    third-party subjects — at most a complement to B1/B2, not a substitute.
  - **B4 — documented no-reach.** The ruling finds no per-subject mechanism
    required; the amendments below ARE the deliverable.
- **NFR:** none outside the legal-corpus gates and (branch-gated) the host
  deploy path.

## Research Insights

- **Premise Validation (Phase 0.6):** #10848 OPEN (target); #9927 OPEN
  (context); #5150 CLOSED (stale-SQLite premise, superseded by the measured
  Postgres finding); #7779, #8528 OPEN (Redis AOF siblings — complementary,
  out of scope); PR #11311 MERGED 2026-10-28 (the 7-day bound — its body
  records "Issue #10848 stays open" and "this removal is not account deletion
  and is not a response to an access or erasure request"); PR #10652 MERGED
  (the C1 measurement). #10849 CLOSED via PR #11283 (the §2.3(o)
  "no external sub-processor" correction — its file set is this plan's
  amendment-footprint precedent). All cited artifacts verified present on this
  branch: `inngest-trace-retention.{sh,sql,sqlite.sql}`,
  `inngest-trace-retention-probe.sh`, `account-delete.ts`,
  `dsar-export-allowlist.ts`, `article-30-register.md`, the three legal docs +
  mirrors. Collision precheck: PR #11846 is this pipeline's own draft —
  expected, not a foreign duplicate (foreign=none).
- **Property List (Phase 0.6b):** P1 recorded determination of Art. 17 reach;
  P2 recorded determination of Art. 15 reach; P3 every copy of the clause
  amended to state the determination; P4 conditional implementation path if
  the ruling requires reach.
- **Cut List (Phase 0.6b):** none — the ask names no mechanism; it asks for
  determinations and amendments. The only candidate mechanism (a per-subject
  purge) is held behind the ruling rather than researched now — designing B1/
  B2 before the CLO says whether they are needed would build machinery that
  may buy nothing.
- **Established findings (verified this session):**
  - `apps/web-platform/server/account-delete.ts`: zero `inngest` matches;
    cascade steps enumerated (abort-DSAR, abort, workspace, storage, ~20
    anonymise RPCs, git-data SSH erasure, auth delete) — none reach the store.
  - `apps/web-platform/server/dsar-export-allowlist.ts`: `DSAR_TABLE_ALLOWLIST`
    covers only app-DB `public` tables; exclusion list exists with documented
    rationales (`statutory_repin_send`, egress rollup precedent).
  - `git grep -n 'inngest' apps/web-platform/server apps/web-platform/app
    apps/web-platform/lib`: no Postgres-credential surface for the Inngest
    project; `INNGEST_POSTGRES_URI` is exported only on the host by
    `inngest-bootstrap.sh`.
  - Clause census: `is not account deletion and is not a response` occurs at
    `article-30-register.md` ×6 (PA-13, PA-21, PA-22, PA-27 ×2, PA-31),
    `data-protection-disclosure.md` ×2 (§2.3(o), §2.3(aa)),
    `gdpr-policy.md` ×1, `privacy-policy.md` ×1, `compliance-posture.md` ×1,
    ADR-030 ×1 (decision-record addendum — left as the dated record, see
    Files to Edit notes), mirrors ×4; plus the plan-archive copy (not edited).
  - PA-14 (f) carries the sibling clause minus the "not account deletion"
    tail — inferred sweep item (the #7695 lesson: an unswept sibling cell
    silently contradicts the correction).
  - Retention job delivery: `inngest-bootstrap.sh` installs
    `inngest-trace-retention.timer` at host birth when staged files are
    present; live enablement is behind `apply_target=inngest-host-replace` —
    the conditional "host not yet replaced is not yet pruning" clause stays
    true until a post-merge replace is verified (T1a of the #5150 decision
    record: not authorized by that change).
  - Prior CLO rulings on record (5150 pipeline, 2026-10-27): the 7-day clause
    "is not Art. 15 or Art. 17 reach" — the bound is not the reach answer;
    this issue is exactly the reach question it deferred.
- **Institutional learnings applied:**
  `2026-10-27-legal-correction-notes-quote-the-phrase-they-remove.md`
  (absence greps strip `*(…)*` note spans with paren-depth tracking; section
  cites can be one level off — grep quoted strings); the #7695
  sibling-cell sweep lesson; `plan-globs-must-be-verified-against-repo-structure`;
  the 10849 plan as the amendment-pipeline shape precedent.
- **External research (Phase 1.6 — data-privacy topic → researched):**
  EDPB Coordinated Enforcement Framework report on the right to erasure
  (2025) — half of responding SAs flagged controllers relying on automatic
  deletion/retention periods not specific to erasure requests (in the backup
  context); the one-month response window (Art. 12(3)) bounds "without undue
  delay". Fed to the ruling brief, not to the docs.
- **Community discovery:** skip — no uncovered stack (TypeScript/bash/SQL/
  legal docs all covered). **Functional overlap:** no new component proposed;
  existing machinery (`soleur:legal:clo`, `soleur:gdpr-gate`, legal-corpus
  gate suite) covers the ask — community search not applicable, recorded in
  lieu of spawn.
- **Related issues/PRs:** #11311 (merged bound), #10652 (merged measurement),
  #8528 / #7779 (Redis AOF siblings — explicitly out of scope), #10849 /
  PR #11283 (merged §2.3(o) correction — footprint precedent), ADR-030 /
  ADR-105 / ADR-282 (substrate + store records).
- **CLAUDE.md / constitution conventions:** plan filename + frontmatter
  format; batch-edit assert-the-needle rule; legal-doc amendment house style
  (correction notes quote the superseded phrase; Last Updated chains demote
  one step).

## Research Reconciliation — Spec vs. Codebase

| Spec / brief claim | Reality at plan time | Plan response |
|---|---|---|
| Issue title: "no deletion bound" | Bound exists since PR #11311 merge (2026-10-28) | Scope narrows to the compliance half; title staleness noted, not re-titled |
| "one column capable of holding a user reference (events.event_user, by name)" | True by name; senders put ids in `data` payloads — sparse top-level field cannot bound the affected set (measurements.md) | Evidence pack carries both facts; ruling brief warns against column-predicate bounding |
| "the deletion bound it needed now exists" (pipeline brief) | True in code; live enablement behind `inngest-host-replace` ack — possibly not pruning yet | Evidence pack includes a verify-live step; the conditional disclosure clause persists |
| "amend PA-13, PA-21, PA-22, PA-27 and PA-31 (f) and the section 2.3(o) text" | Clause actually lives in 6 register cells (PA-27 twice), PA-14 (f) sibling, 4 published surfaces ×2 (canonical+mirror), posture note, ADR-030 | Sweep enumerated by grep, not by the issue's list; PA-14 + §2.3(aa) + posture + mirrors are inferred items with the sweep-lesson justification |

## Files to Edit

- `knowledge-base/legal/article-30-register.md` — the (f) Retention cells of
  PA-13, PA-21, PA-22, PA-27 (two cells), PA-31: append the recorded
  determination per ruling; PA-14 (f) sibling append (inferred — identical
  store, sweep lesson); each append is a dated marker naming the ruling, not a
  silent rewrite (house pattern).
- `docs/legal/data-protection-disclosure.md` — §2.3(o) and §2.3(aa) clause
  extensions + `Last Updated` chain.
- `docs/legal/privacy-policy.md` — the recipients-bullet clause + `Last
  Updated` chain.
- `docs/legal/gdpr-policy.md` — the corresponding clause + `Last Updated`
  chain.
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — identical
  edits + hero `Last Updated`.
- `plugins/soleur/docs/pages/legal/privacy-policy.md` — identical edits + hero.
- `plugins/soleur/docs/pages/legal/gdpr-policy.md` — identical edits + hero.
- `apps/web-platform/lib/legal/legal-doc-shas.ts` — re-pin the three docs'
  SHA-256 entries in the same commit.
- `knowledge-base/legal/compliance-posture.md` — close out / update the
  #10848 open item (the 2026-10-22 comment block naming this issue).
- *Not edited, deliberately:* `knowledge-base/engineering/architecture/decisions/ADR-030-*.md`
  — its clause copy is a dated decision-record addendum; the register and
  published docs carry the current determination. Rationale: an ADR addendum
  records what was true and decided at its date.
- *Conditional (ruling-gated, only under branch B1/B2/B3):* implementation
  artifacts the ruling selects — prescribed inside Phase 5, not enumerated as
  committed paths here (the ruling determines which, if any, exist).

## Files to Create

- `knowledge-base/legal/audits/2026-11-counsel-review-10848.md` — the
  counsel-review attestation artifact (house shape: `type: counsel-review`,
  `disposition`, `re_evaluation_triggers`, per-artifact verdict table).
- `knowledge-base/project/specs/feat-one-shot-10848-inngest-erasure-reach/tasks.md`,
  `session-state.md`, `decision-challenges.md` — pipeline artifacts.

## User-Brand Impact

- **If this lands broken, the user experiences:** a founder who deleted their
  account is told, by the published disclosure and our own register, a
  reach answer that was never determined — or worse, told erasure reached a
  store it provably does not; the artifact is the published DPD §2.3(o)
  sentence and the account-deletion confirmation.
- **If this leaks, the user's data is exposed via:** residual Inngest
  event/history payloads carrying `founderId`/`userId`/`sender`/`subject`
  surviving an account deletion on a store no erasure path reaches — and, if
  the host has not yet been replaced, surviving even the 7-day bound.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the harm is per-subject — one user's
  un-erased or undisclosed history is the incident class the issue names;
  it is not an aggregate-pattern control (the bound already covers the bulk).

## Observability

The definite deliverable is docs-class (legal docs, register, posture note,
SHA constants, audit artifact). The conditional implementation branch
re-derives this section per ruling at Phase 5 (a host-side or app-side
mechanism gets the full 5-field block before it is written). For the docs
deliverable the discoverable signal is the legal-corpus gate suite:

```yaml
liveness_signal:
  what: legal-corpus probe asserting disclosed-vs-actual posture of the three published docs and their mirrors
  cadence: on-demand at ship time (preflight Check 10) + on every legal-doc change via the gate suite
  alert_target: CI failure on the PR
  configured_in: scripts/probe-legal-corpus-truth.sh, apps/web-platform/test/legal-doc-consistency.test.ts
error_reporting:
  destination: CI job output on the draft PR
  fail_loud: probe exits non-zero with CORPUS-FALSE naming the failing surface
failure_modes:
  - mode: mirror drift (canonical edited, mirror not)
    detection: lint-legal-mirror-drift-baseline.sh reports a drift pair at a touched position
    alert_route: CI failure on the PR
  - mode: clause left unamended in a sibling cell/surface (the #7695 sweep class)
    detection: clause-census grep in AC3 returns non-zero on any surface
    alert_route: CI failure on the PR
logs:
  where: GitHub Actions job log
  retention: repo run-retention default
discoverability_test:
  command: bash scripts/probe-legal-corpus-truth.sh
  expected_output: CORPUS-OK
```

## Encryption Posture

The definite diff introduces no persistent store and no new cross-component
connection. The dedicated Postgres store under discussion —
`supabase.inngest` — is already a first-class row in
`scripts/encryption-posture-ledger.json` (verified `git grep`); this plan
changes what is RECORDED about the store's erasure/access reach, not its
encryption surface, so no ledger row changes.

```yaml
at_rest:
  - store: supabase.inngest
    mechanism: provider-managed:Supabase disk encryption at rest (existing ledger row — unchanged by this diff)
    evidence: scripts/encryption-posture-ledger.json row "supabase.inngest"
    defends_against: physical disk exfiltration of the Supabase-managed volume
    does_not_defend: a leaked project credential; an authenticated query path — this plan's subject is reach (who can select/delete), not at-rest cipher
    disclosed_as: dedicated Supabase Postgres project, eu-west-1 (Ireland) — DPD §2.3(o), §4.2 row
    live_verification: provider attestation — unchanged
in_transit:
  - connection: none added by the definite diff (docs/register/audit only)
    tls: n/a — no new connection
    cert_verification: n/a
    does_not_defend: n/a
    disclosed_as: n/a
```

**Conditional (ruling-gated):** if Phase 5 activates branch B1 or B2, the new
edge it creates (app→Inngest-Postgres credential, or a host-read manifest
channel) is a new cross-component connection and the full `at_rest` /
`in_transit` block is emitted for it BEFORE its first code diff, per plan
Phase 2.11 — flagged here so the branch cannot activate silently under this
section.

## GDPR Gate (Phase 2.7 record)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Invoked at plan time — the plan is itself a regulated-data-surface
determination and its conditional branch may add `.sql`/infra paths. No
`Critical` findings (no Art. 9 column-name matches). The Art. 17 / Art. 15 /
Art. 5(1)(e) items are this plan's subject, not findings against it; the gate
re-fires at `soleur:work` Phase 2 exit against whatever diff the ruling
branch produces (a new `.sql` or credential edge would hit
`GDPR-Art-17-caller` / `GDPR-Chapter-V` patterns — flagged here so the branch
prescribes the check rather than discovering it).

## Domain Review

**Domains relevant:** Legal

### Legal

**Status:** reviewed (inline — no subagent spawn surface on this harness;
the CLO ruling itself is prescribed as a work-Phase-1 consult, not improvised
here)
**Assessment:** This plan IS a legal-domain change: it produces a recorded
determination on Arts. 15/17 reach of a personal-data-bearing store and
amends the published disclosure + Article 30 register accordingly. The
domain-leader contribution that matters — the ruling — is explicitly a
work-phase deliverable (`soleur:legal:clo` with the evidence pack,
"do NOT use AskUserQuestion"), because the ruling must be rendered against
facts assembled into a fixed record, not paraphrased from plan prose.
Domain sweep of the other 7 domains: Engineering — conditional only (branch
B1/B2 touch code/infra if the ruling requires reach); Product — no UI-surface
file in Files to Edit/Create (legal-doc pages are static published text, not
interactive surfaces; mechanical override does not fire); Marketing, Sales,
Finance, Operations, Support — none.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "determine the retention need and bound" | — | descoped — justification: delivered by merged PR #11311 (7-day status-gated bound, recorded in the plan body verbatim: "Issue #10848 stays open") |
| 2 | "decide pruning" | — | descoped — justification: decided and implemented by merged PR #11311 (pipelines A/B/C); live enablement behind `apply_target=inngest-host-replace`, tracked there, not re-decided here |
| 3 | "determine erasure and access reach" | FR-1 (evidence pack + recorded facts) / Phase 1 (CLO ruling) / FR-2 (conditional branch) | mapped |
| 4 | "then amend PA-13, PA-21, PA-22, PA-27 and PA-31 (f)" | Phase 3 register sweep — 6 clause cells (PA-27 ×2) + PA-14 inferred sibling | mapped |
| 5 | "and the section 2.3(o) text" | Phase 4 — DPD §2.3(o) + every sibling copy (§2.3(aa), privacy, gdpr, mirrors, posture) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| CLO ruling consult (Phase 1) | "determine erasure and access reach" | asked |
| Factual evidence pack (Phase 0/FR-1) | "determine erasure and access reach" | asked |
| Register (f) cell amendments | "then amend PA-13, PA-21, PA-22, PA-27 and PA-31 (f)" | asked |
| §2.3(o) amendment | "and the section 2.3(o) text" | asked |
| PA-14 (f) + §2.3(aa) + privacy + gdpr + mirrors + posture sweep | — | inferred — justification: the clause the ask names has six register copies and four published copies on two surfaces each; a partial sweep reproduces the #7695 retraction-without-sweep defect — identical wording must carry the same determination everywhere it appears |
| SHA re-pin (`legal-doc-shas.ts`) | — | inferred — justification: `check-tc-document-sha.sh` + `legal-doc-shas-guard.test.ts` gate the three edited docs; the edit cannot merge without the pin (enforcement contract) |
| Last Updated chains (canonical + hero) | — | inferred — justification: legal-doc amendment house form — every published change moves both Last Updated shapes, and the amendment note is the mechanism by which the change is honest |
| Counsel-review audit file | — | inferred — justification: the legal-corpus pipeline's attestation pass (10849 precedent, `lint-legal-registers.sh` producer pattern) — a CLO-authored determination needs its recorded audit |
| compliance-posture #10848 item update | — | inferred — justification: the issue is a named open item there; landing the determination without updating the tracker leaves it open (the deferral-tracking contract) |
| Conditional implementation branch (B1–B3) | "determine erasure and access reach" | asked — the reach ask cannot be discharged by disclosure alone if the ruling finds a mechanism is required |
| Live-pruning verification step | — | inferred — justification: the bound the determination relies on may not be enabled on the live host (T1a of the #5150 record); a ruling rendered on an unverified premise is spec fiction (Phase 1.7 reconciliation contract) |

### Split Assessment

- Subsystems touched: 3 — `docs/`, `plugins/soleur/docs/`, `knowledge-base/`
  (+ `apps/web-platform/lib/` one constants file)
- Planned files: 10 definite + 4 pipeline artifacts | Estimated changed lines: ~200
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (the conditional branch, if activated, is its own
  follow-through by ruling — it cannot merge inside a docs PR it may never need)

## Implementation Phases

### Phase 0 — Re-verify premises (work Phase 0.5)

`git fetch origin main`; re-grep the clause census (sibling legal PRs land
weekly — the amendment chain re-anchors targets); re-run the collision
re-probe over the planned paths. Verify whether a post-2026-10-28
`inngest-host-replace` dispatch has run (the timer-enablement premise):
`gh run list --workflow apply-web-platform-infra.yml` filtered to the target —
a post-merge replace flips "host not yet replaced is not yet pruning" to
pruning, which the ruling brief and the final clause text must reflect. If no
evidence either way is obtainable, the conditional clause stays.

### Phase 1 — CLO ruling (the determination)

Spawn `soleur:legal:clo` (on this harness: `run_subagent` profile
`subagent_explore`, agent definition
`plugins/soleur/agents/legal/clo.md`) with the evidence pack — the findings
table above, the residual edges (in-flight exclusion, not-yet-pruning, the
two subject populations, `event_user` cannot bound the set), the EDPB
caution, and the explicit instruction "do NOT use AskUserQuestion". The brief
MUST enumerate, for each disposition option, the fact that would disqualify
it — for "the bound discharges erasure": the EDPB concern about
retention-substituted erasure, the unbounded in-flight exclusion, and the
possibly-not-yet-live timer; for "a per-subject mechanism is required": the
absence of any user-indexed column, the open-ended identifier census inside
payloads, and that no founder-keyed predicate can name the involuntary
third-party population the bound already serves (per the binding-ruling
brief rule — a brief is a filter, and disqualifying facts are what it must
not filter out). Required
output: answers to (a) Art. 17 — does the bound + documented no-reach
discharge erasure, or is a per-subject mechanism required and which of
B1–B4; (b) Art. 15 — does the self-serve bundle require the store's rows or
a documented exclusion; (c) the exact clause text each surface should carry.
Record `Ruled by CLO agent, <date>: <decision> - <rationale>` in
`knowledge-base/project/specs/<branch>/decision-challenges.md` and the
counsel-review audit file. **If the ruling requires reach (branch ≠ B4), the
implementation sub-plan gains its own IaC / ADR / observability /
encryption-posture deliverables before any code is written** — per plan
Phases 2.8–2.11, not improvised.

### Phase 2 — Register (f) cell amendments

Per ruling text, append a dated marker to the six clause-bearing cells
(PA-13, PA-21, PA-22, PA-27 ×2, PA-31) and the PA-14 (f) sibling — the
determination, the ruling citation, the named residuals. House pattern:
append `**Added <date> (#10848):** …` / in-cell marker; never silently rewrite
the clause the marker supersedes.

### Phase 3 — Published-doc amendments (canonical + mirror, byte-identical)

Per ruling text, extend the clause at: DPD §2.3(o), DPD §2.3(aa),
privacy-policy recipients bullet, gdpr-policy corresponding bullet — on both
surfaces each (8 positions), then `Last Updated` chains on all three docs
(canonical `**Last Updated:**` + mirror hero `<p>…Last Updated…</p>`), with
the house-form amendment note ("This corrects/extends a statement, not what
is processed: … no new purpose, sub-processor or international transfer").
**Falsified-negatives sweep (same phase):** the determination performs the
verification the corpus currently calls not-yet-done — grep the legal corpus
for paraphrases of the undetermined state (`not established`, `undetermined`,
`no established`, `not a response to an access or erasure`, `reach`) and
sweep every hit that the ruling falsifies, not only the clause's own
vocabulary (the PR #10337 class: a flip that sweeps only the flip's words
leaves the differently-worded negative claim standing).

### Phase 4 — Posture item + SHA re-pin

Update the `compliance-posture.md` 2026-10-22 comment block's #10848 item to
the determined state. `sha256sum` the three edited canonical docs →
`apps/web-platform/lib/legal/legal-doc-shas.ts`, same commit.

### Phase 5 — Conditional implementation (ruling-gated)

Only under a non-B4 ruling. The chosen branch's artifacts are named by the
ruling, not pre-enumerated here; before any code, the branch emits the
deliverables plan Phases 2.8–2.12 require for its shape (Terraform root
changes / ADR + C4 / 5-field observability block / encryption posture for any
new credential edge or cross-component connection / task-design gate if a new
job or timer is created). The erasure predicate's identifier census (per
event name → payload key) is derived from `git grep` of every `inngest.send`
call site — the open-enumeration class, so the predicate is constructed from
the sender census and tested against every site, never assumed
(`#8076`-class: the population is whoever the mechanism reaches, not a nearby
inventory).

### Phase 6 — Gate suite + counsel-review attestation

Run all five legal-corpus gates (`lint-legal-scope-block-placement.sh --base
origin/main`, `lint-legal-mirror-drift-baseline.sh --base origin/main`,
`apps/web-platform/scripts/check-tc-document-sha.sh`,
`apps/web-platform/test/legal-doc-consistency.test.ts` +
`legal-doc-shas-guard.test.ts`, `probe-legal-corpus-truth.sh`) plus the
affected-suites runner. Produce
`knowledge-base/legal/audits/2026-11-counsel-review-10848.md` in the house
shape — every added claim cross-checked against a repo source
(`inngest-bootstrap.sh`, `inngest-trace-retention.sql`,
`account-delete.ts`, `dsar-export-allowlist.ts`, the measurements record, the
CLO ruling); `disposition: DISCHARGED` or the PR halts on the named blocker.

## Acceptance Criteria

- [ ] AC1: `decision-challenges.md` (or the counsel-review audit) carries a
  `Ruled by CLO agent, <date>` row answering both the Art. 17 and Art. 15
  reach questions for the dedicated Postgres store — a determination, not a
  restatement of the bound.
- [ ] AC2: Every register cell that carried the clause before the diff (the
  6 cells found by `git grep -n 'is not account deletion and is not a
  response' knowledge-base/legal/article-30-register.md` run at Phase 0) now
  carries the determination text per ruling, and PA-14 (f) carries the same
  determination appended.
- [ ] AC3: On all four published surfaces (DPD, privacy, gdpr × canonical +
  mirror): every occurrence of `is not account deletion and is not a
  response to an access or erasure request` outside `*(…)*` note spans is
  followed by or replaced with the determined reach text per ruling; a
  paren-depth-aware sweep finds no copy left stating the undetermined form
  as current fact.
- [ ] AC4: Canonical-vs-mirror diff at every touched position is
  byte-identical; `Last Updated` moved on all three docs (canonical body
  line + mirror hero `<p>`) with the house-form note.
- [ ] AC5: `LEGAL_DOC_SHAS` entries for the three docs equal `sha256sum` of
  the edited canonical files; `check-tc-document-sha.sh` exits 0.
- [ ] AC6: All five legal-corpus gates pass (named in Phase 6).
- [ ] AC7: `knowledge-base/legal/audits/2026-11-counsel-review-10848.md`
  exists with `disposition: DISCHARGED` or the PR halts on the named
  blocker; every added claim cites a repo source.
- [ ] AC8: `compliance-posture.md` no longer names #10848 as an open
  reach question (closed-out or updated to the determined state per ruling).
- [ ] AC9: If the ruling selected branch ≠ B4, the implementation
  sub-plan's gate deliverables (IaC / ADR + C4 / observability / encryption
  posture) exist before its first code diff, AND either land in this PR
  with their own ACs or are tracked as a `wg-when-deferring-a-capability-create-a` issue with the
  ruling's re-evaluation criteria — recorded either way.
- [ ] AC10: The diff touches only files enumerated in `## Files to Edit` /
  `## Files to Create` (incl. spec-dir + audit artifacts) unless the ruling
  activated Phase 5, in which case the activation itself names the added
  paths.
- [ ] AC11: The conditional "host not yet replaced is not yet pruning"
  clause reflects the Phase-0 live verification — removed only if a
  post-2026-10-28 `inngest-host-replace` is evidenced; otherwise retained.

## Test Scenarios

- Given the edited corpus, when a paren-depth-aware strip of `*(…)*` spans
  runs over `docs/legal/*.md`, `plugins/soleur/docs/pages/legal/*.md` and
  `article-30-register.md`, then zero occurrences of the undetermined clause
  form remain asserted as current (`unit`).
- Given the register, when `git grep -c 'is not account deletion and is not
  a response' knowledge-base/legal/article-30-register.md` is compared to
  its Phase-0 value, then each previously-clause-bearing cell also matches
  the ruling's determination marker (`unit`).
- Given the SHA re-pin, when `bash
  apps/web-platform/scripts/check-tc-document-sha.sh` runs, then exit 0
  (`integration`).
- Given the six doc surfaces, when each edited sentence is diffed
  canonical-vs-mirror, then byte-identical (`unit`).
- Given the probe, when `bash scripts/probe-legal-corpus-truth.sh` runs on
  the finished tree, then exit 0 with `CORPUS-OK` (`integration`).

## Success Metrics

- The issue's open question — "whether account-delete or the DSAR export
  reaches this store is not established" — has a recorded, ruled answer in
  the register, the published corpus, and the posture tracker.
- Zero unamended copies of the undetermined clause on any published or
  register surface.
- All five legal-corpus gates green; counsel-review audit discharged.

## Dependencies & Risks

- **Ruling-dependent branch risk:** if the CLO requires a per-subject
  mechanism, this PR's doc work still lands but the implementation is a
  gated follow-through (AC9) — the plan deliberately does not pre-build
  machinery the ruling may never need (Phase 0.6b).
- **Premise risk — live pruning:** the determination's posture partially
  rests on the 7-day bound; if the host has not been replaced, residual
  lifetime is unbounded in practice — the Phase-0 verification + retained
  conditional clause carry this.
- **Enumeration risk:** the identifier census inside payloads is open-ended;
  any Phase-5 predicate is derived from a full `inngest.send` call-site
  census, tested per site.
- **Sibling-drift risk:** legal docs are amended weekly — Phase 0 re-anchors
  every target; a merge race on Last Updated chains is expected and handled
  by re-reading at edit time.
- **Scope boundary:** the Redis AOF half (#8528, #7779) is explicitly out of
  scope — the amendments name it as the open sibling rather than resolving
  it.

## Sharp Edges

- Absence greps MUST strip `*(…)*` note spans with paren-depth tracking —
  correction notes quote the superseded clause verbatim, and nested parens
  like "eu-west-1 (Ireland)" defeat naive sed-strips
  (`2026-10-27-legal-correction-notes-quote-the-phrase-they-remove.md`).
- Section cites drift one level off — grep the quoted clause, not the cited
  section number (same learning: the "§5.9" sentence lived in §4.13's
  bullet).
- The mirror is the published surface — every edit lands byte-identical on
  both; `Last Updated` has two shapes (canonical body + mirror hero).
- PA-27 carries the clause TWICE and PA-14 carries the sibling form — a
  five-row mental model misses both; sweep by grep, not by the issue's list.
- The clause's conditional tail ("a host that has not yet been replaced … is
  not yet pruning") must survive whatever text replaces the reach claim —
  deleting it silently upgrades the disclosure to a claim that may be false.
- `soleur:work` re-reads each target line at edit time; sibling legal merges
  re-anchor the chains.
- A CLO-authored determination is recorded as a ruling, then implemented —
  doc text says what the ruling says, never what sounds compliant.
- `requires_cpo_signoff: true` is declared per the single-user-incident
  threshold; the headless pipeline records it for ship Phase 6 rather than
  pausing.
- The subagent-free harness ran the review panel inline sequential —
  `Reviewed-Coverage: sequential-fallback` disclosure applies at review
  trailer time; no independent panel is claimed.

## Context

- Issue: #10848 (OPEN — the compliance half; retention half delivered by
  merged PR #11311).
- Controlling records: `knowledge-base/project/specs/archive/20261027-160344-feat-one-shot-5150-inngest-trace-retention/decision-challenges.md`
  (CTO T1 + CLO T2 rulings — the bound "is not Art. 15 or Art. 17 reach"),
  `knowledge-base/project/specs/archive/20261022-221258-feat-one-shot-9927-inngest-luks-items-6-8b-c1/measurements.md`
  (the C1 measurement), `knowledge-base/legal/audits/2026-10-counsel-review-9927.md`
  (probe legality + recording rulings).
- Amendment-pipeline precedent: archived plan
  `20261027-111547-2026-10-27-legal-inngest-subprocessor-correction-plan.md`
  (PR #11283 / #10849).
- Siblings out of scope: #8528 (Redis AOF Art. 17), #7779 (AOF retention),
  #9927 (LUKS residuals).

## References

- #10848 (work target); #5150 / PR #11311 (the bound); #9927 / PR #10652
  (the measurement); #10849 / PR #11283 (the footprint precedent); ADR-030,
  ADR-105, ADR-282 (substrate records); EDPB CEF report on the right to
  erasure (2025) — external, cited in the ruling brief only.
