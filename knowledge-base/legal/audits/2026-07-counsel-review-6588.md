---
title: "Counsel review audit — #6588 (retraction of three never-achievable Article 32 TOM claims; re-scoping of the surviving LUKS encryption-at-rest claim onto the live single-host topology)"
type: counsel-review
date: 2026-07-24
issue: 6588
pr: 6938
plan: knowledge-base/project/plans/2026-07-24-fix-6588-legal-clause-retraction-plan.md
decision_record: knowledge-base/project/specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md
site_dispositions: knowledge-base/project/specs/feat-one-shot-6588-legal-clause-retraction/site-dispositions.md
adr: knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md
status: "SIGNED-OFF WITH ACCEPTED RESIDUAL — final. Re-attested against HEAD c9747f0aa; pre-merge condition E-1 DISCHARGED 2026-08-02 by `workspaces-luks-verify` run 30749271370 (verified independently, §A3). All five A–E defects are CURED. The DC-1 retained-plaintext residual is carried forward unamended and is ACCEPTED, not cured. CLEAR TO MERGE."
ship_gate_disposition: "DISCHARGED — the ship Phase 5.5 Counsel-Review CLO-Attestation gate is satisfied. No outstanding pre-merge condition."
superseded_by: "§Amendment No. 3 — E-1 discharge and final disposition, 2026-08-02 (supersedes §Amendment No. 2 → §Amendment No. 1 → the 2026-07-24 review)"
signed_off_at: 2026-08-02
signed_off_at_withdrawn: 2026-07-24
amended_at: 2026-08-02
pre_merge_condition: "E-1 — DISCHARGED 2026-08-02. Satisfied by Door 1: `workspaces-luks-verify` run 30749271370 (2026-08-02T13:07:46Z, workflow_dispatch on main @ b5871b9f6d, conclusion success) — `device_type=crypto_LUKS`, `mount_source=/dev/mapper/workspaces`, escrow ok, header readable, `workspace_count=8 expected=8`, `/health=200`, readyz ready=true. Verified independently against the GitHub API and the raw run log, not from a report. See §A3.1."
claim_decay_trigger: "ANNOTATED 2026-08-03 (#6808 schedule PR): the PREMISE of this trigger — `workspaces-luks-verify` being workflow_dispatch-only, with no automatic verification of any kind — RETIRES ON MERGE of that PR, which adds a daily `schedule: 41 4 * * *` plus a three-class alarm and a Sentry Crons monitor for the schedule itself. The TRIGGER ITSELF IS NOT RETIRED and its threshold is unchanged: if no successful run lands within any trailing 30-day window while the published present-tense clause stands, the clause MUST still be re-tensed to a dated past verification (Amendment No. 2, Door 2) or withdrawn. What changes is only that the window is now defended by a standing control rather than by operator memory, and that a failure is now self-reporting: a failing run files a `ci/luks-verify` issue, and a run that never fires is caught by the Sentry monitor. Evidence query: `gh run list --workflow=workspaces-luks-verify.yml --event=schedule --limit 40 --json databaseId,conclusion,createdAt`. See §A3.4."
amended_by: "clo agent (Soleur legal domain leader) — Amendment No. 1 re-attested HEAD 25e5de36e on 2026-08-02 after the 2026-08-01 rebase (DC-2) materially reversed the PR's own position; Amendment No. 2 re-attested HEAD c9747f0aa the same day after the A–E rulings were applied. Evidence recomputed from the working tree, hashed against `main`, and pulled live from the GitHub API at each pass; nothing carried over on trust from any earlier pass."
signed_off_by: "WITHDRAWN. The 2026-07-24 attribution is preserved below for the record: 'clo agent (Soleur legal domain leader) — reviewing authority for v1 per the agent-native company model; review performed 2026-07-24T22:43Z (00:43 CEST on 2026-07-25 local), same session as the PR; dated 2026-07-24 to match the PR, the corrections banner, and the sibling spec artifacts. External counsel re-review reserved for the re-evaluation triggers below.' That review is superseded, not deleted — see §Amendment No. 1 for what it got wrong and why."
tier_classification: "Tier 1 (material) per `knowledge-base/legal/tc-version-bump-policy.md` — retraction of published Article 32 TOM claims plus re-scoping of a surviving one. NO `TC_VERSION` bump: that constant governs `docs/legal/terms-and-conditions.md` exclusively (`apps/web-platform/lib/legal/tc-version.ts:14,17,26-27`); the three documents amended here are notice/disclosure documents with no re-acceptance gate."
brand_survival_threshold: single-user incident
accepted_residual: "The re-scoped LUKS clause ships while a full un-wiped plaintext copy of every workspace remains on the superseded pre-cutover volume `hcloud_volume.workspaces` (`format = \"ext4\"`, `apps/web-platform/infra/server.tf`), retained attached-unmounted as the ADR-119 rollback backstop. Users are not told. CLO block B1 recommended an accompanying retained-plaintext disclosure sentence; the operator reaffirmed the UC-3 hold on 2026-07-24 and B1 was OVERRIDDEN. Tracking issue: #6808 (escalated by this PR to priority/p1-high + type/security). Ledgered internally as `plaintext-exception` (`tracking_issue: \"#6897\"`, `expires_on: 2026-10-22` — an INTERNAL commitment, never published) and named in the Article 30 register PA-1(g) and PA-2(g)."
re_evaluation_triggers: "(1) **#6808 clears** — `WORKSPACES_LUKS_HEARTBEAT_URL` wired, the ADR-119 soak clock starts, and the Phase-5 plaintext wipe of `hcloud_volume.workspaces` completes: at that point the accepted residual is cured by reality and this audit's disposition upgrades from SIGNED-OFF-WITH-RESIDUAL to unqualified. (2) **First arms-length data subject** — if #3723 (or any other path) onboards a non-Soleur user while #6808 is open, the bounding fact that carries this residual (zero arms-length data subjects) is gone: the residual becomes p0, the hold MUST be re-raised, and the published wording must be qualified before onboarding, not after. (3) **Any regression of the LUKS mount** — `workspaces-luks-verify` reporting anything other than `device_type=crypto_LUKS` on `/dev/mapper/workspaces`, or an escrow/header failure, falsifies the one Article 32 claim this PR retains and makes the retained clause itself an over-claim (the #6812 silent-revert failure mode is documented on this exact surface). (4) **Any future edit that would add the held disclosure sentence** — the Path-2 wording preserved in the plan §3b must be reviewed against the then-current infrastructure before publication, and must anchor on **Art. 12(1) + 5(1)(a)**, not Art. 13(3). (5) Standard inherited triggers: an EEA-out transfer, a regulated-industry data subject, or any change of Hetzner locative away from `hel1` only."
---

# Counsel review audit — #6588 (Article 32 TOM retraction + LUKS re-scope)

> ## 📍 CURRENT DISPOSITION — read this first
>
> **The controlling section of this document is `§Amendment No. 3` (at the end).**
>
> **Disposition: SIGNED-OFF WITH ACCEPTED RESIDUAL. The ship Phase 5.5 Counsel-Review
> CLO-Attestation gate is DISCHARGED. Clear to merge. No outstanding pre-merge condition.**
>
> The accepted residual is the DC-1 retained-plaintext volume — **accepted and undisclosed, not
> cured**. See `§A3.5`.
>
> Everything before `§Amendment No. 3` is superseded history, preserved deliberately. Read order:
> this notice → `§Amendment No. 3` → the rest only if you need to know how the position got here.

---

> ## ⛔ WITHDRAWAL NOTICE (2026-08-02) — superseded by Amendment No. 2, retained as record
>
> **The 2026-07-24 sign-off recorded in this document is WITHDRAWN as of 2026-08-02.**
> *(At the time this notice was written the disposition was BLOCKED. The five defects it refers
> to were subsequently cured and verified — see `§Amendment No. 2`. This notice is retained
> unamended because the withdrawal itself stands: the 2026-07-24 review is not reinstated.)*
>
> The review below was performed against the branch **before** the 2026-08-01 rebase onto
> `main` (60 commits) and before the 2026-08-01/02 register and attestation fix commits. That
> rebase **materially reversed this PR's own position** (DC-2: the git-data register items were
> re-scoped to `DRAFTED / NOT-YET-ACTIVE` instead of deleted, because #6570 closed and the host
> became orderable), and `main` published a **newer banner head** (#7100, July 31) while this
> branch sat. **The attestation was never re-run.** Five of its rows are false against
> HEAD `25e5de36e` — including three SHA digests that match no file and no commit on this
> branch, a banner structure this PR does not produce, and an issue state that flipped.
>
> Everything between this notice and `§Amendment No. 1` is **preserved verbatim as the record of
> what was attested on 2026-07-24**. It is *not* a current statement of the legal position and
> must not be cited as one. Read `§Amendment No. 1` at the end of this file for the
> re-attestation against HEAD, the corrected rows, the re-graded block B2, and the four
> merge-blocking defects.
>
> This preservation-plus-amendment shape is deliberate and is the same standard this PR applies
> to the `Previous: July 2, 2026` banner entry: **a corrections regime that rewrites what it
> previously said is not a corrections regime.** An attestation that quietly edits its own false
> rows out of existence is worth less than one that shows them.

---

> **STATUS [SUPERSEDED 2026-08-02 — see the Withdrawal Notice above]: DISCHARGED WITH ONE ACCEPTED, OPERATOR-OVERRIDDEN RESIDUAL — reviewed and
> attested by the `clo` agent on 2026-07-24.**
> The `clo` agent (Soleur legal domain leader) is the reviewing authority for the v1
> Soleur-as-tenant-zero posture — this is an agent-native company; legal review is a
> CLO-agent function, not a task for the non-lawyer operator. The operator retains an
> optional veto; **external** counsel re-review is reserved for the frontmatter
> re-evaluation triggers. The agent cross-checked **every** implementation-detail claim
> in the six published files and the four internal registers against the actual
> infrastructure and CI evidence — `git diff origin/main`, `apps/web-platform/infra/server.tf`,
> `scripts/encryption-posture-ledger.json`, the live `workspaces-luks-verify` run
> **30130277489**, and the live state of issues #6808 / #6897 / #3723 / #6570 / #6538 —
> and **discharges the gate**, subject to the residual recorded in §B1 below, which is
> **accepted, not cured**.

This audit is the load-bearing evidence for the ship-time Counsel-Review CLO-Attestation
gate (ship Phase 5.5) on **PR #6938** (issue **#6588**, `feat-one-shot-6588-legal-clause-retraction`,
the **legal half**). The PR's legal grain is unusual and worth naming precisely: it does not
*add* a disclosure. It **retracts three published Article 32 technical-and-organisational
measures that were never realised in the live platform**, and **re-scopes a fourth off a
premise that has since died**. Retraction is the rarer and more delicate operation — a
badly-executed one makes the remaining claim *stronger* rather than weaker, which is exactly
the defect the 2026-07-16 attempt introduced (recorded at
`knowledge-base/project/specs/feat-6538-web2-fsn1-orphan/decision-challenges.md` DC-1).

**No new processing activity, no new lawful basis, no new data subject, no new
recipient / sub-processor, no new Chapter V transfer, no change to retention or to
data-subject rights.** There are no `[DRAFT — pending CLO/counsel review]` markers to clear.

## What the PR actually does (cross-checked against the diff and the infrastructure)

### The three retracted claims, and the evidence each is unachievable

| # | Retracted claim (as published) | Why it is retracted, not merely corrected | Evidence pulled |
|---|---|---|---|
| **(a)** | *"traffic between the hosts is **encrypted in transit with TLS**"* | There is **no cross-host traffic** for it to protect. The second web host (web-2, `fsn1`) was retired **2026-07-17** (#6538, now **CLOSED**); it never served user traffic and never stored user data. | #6538 state pulled live: `CLOSED`. Retracted at `privacy-policy.md:298`, `gdpr-policy.md:44`, `data-protection-disclosure.md:189`, `:276`, `privacy-policy.md:519`. |
| **(b)** | *"membership re-verified when a session is served across hosts"* | **No load balancer exists** and `app.soleur.ai` is pinned to a single host, so no session is ever served across hosts. The measure describes a boundary that has no traffic crossing it. | Web-2 sat at LB weight 0 per ADR-068 §(c) (recorded in the Art. 30 vendor row); locative now `hel1` only across `var.location` / `web_hosts`. |
| **(c)** | *"a dedicated per-workspace git-data host"* / *"a dedicated host for per-workspace git data"* | The host was **never provisioned and cannot be**: CAX11 is orderable in **0 of 3 EU DCs** (live Hetzner API, 2026-07-16). | **#6570 OPEN**, pulled live — *"git-data is pinned to cax11 — orderable in 0 of 3 EU DCs, so it can never be born"*. |

Claim (c) is the most serious of the three: it was published in the **DPD Section 4.2
processor table** and in the **gdpr-policy Section 2.2 sub-processor entry** — the
Art. 13(1)(e) / Art. 30(1)(d) recipient-disclosure grade — naming infrastructure that has
never existed. Claim (a) is second: it is an affirmative Art. 32(1)(a) statement about a
transport channel. Removing all three **whole** (rather than trimming the multi-host head
and leaving the dependent clauses dangling) is the correct operation, and the diff performs it.

### The one retained claim, and its live verification

**LUKS encryption at rest is retained and re-scoped.** The published sentence no longer hangs
on the dead *"Where the Web Platform spans more than one Hetzner host in the EU region"*
conditional; it now stands on the live single-host topology:

- `privacy-policy.md:519` — *"Stored workspace git data sits on a **LUKS-encrypted volume
  (encryption at rest)** on the Hetzner host in the EU region that serves the Web Platform"*
- `gdpr-policy.md:44` / `data-protection-disclosure.md:189`, `:276` — same, re-anchored to
  *"that host"* / *"the serving host"*.

Verified live, not asserted from code: **`workspaces-luks-verify` run 30130277489**
(2026-07-24T22:13:06Z, conclusion `success`) — `device_type=crypto_LUKS`,
`mount_source=/dev/mapper/workspaces`, escrow ok, header readable,
`workspace_count=8 expected=8`. The re-assert (rather than a citation of the day-old
certification run 30040444418) is methodologically right on this surface: run 29782780158
held `crypto_LUKS` for ~27 minutes before a dead-man timer silently reverted it (#6812), so a
stale green is the *documented* failure mode here. I record this as the correct standard of
evidence for a retained Art. 32 claim and would have flagged a code-only assertion.

### Two sites correctly received *no* LUKS claim

`privacy-policy.md:489` and `gdpr-policy.md:318` publish no encryption claim today; the diff
retracts the multi-host premise and the web-2 reference at both **without adding one**. Adding
an encryption claim inside a retraction PR would be the inverse defect. Confirmed absent.

### Banner (Article 12(1) transparency of the correction itself)

- A **new July 24, 2026 head** is prepended, naming all three retracted measures with the
  reason each is unachievable, the web-2 retirement date, the LUKS retention-and-re-scope, and
  the standing EU-only / one-account / one-AVV finding. Byte-identical across all six files
  (head length **1426** in each; canonical == mirror verified).
- The **July 16, 2026 entry is demoted** to `Previous:` intact.
- The historical **`Previous: July 2, 2026`** entry — the one that first published the now-retracted
  measures — is **annotated additively at its END**, never amended in place. I verified the July-2
  segment survives as a **byte-identical contiguous substring** in all six files: **818** chars
  (privacy-policy ×2), **823** (DPD ×2), **827** (gdpr-policy ×2). The 450-char annotation is
  identical canonical-vs-mirror and states in terms that *"the July 2, 2026 entry text above is
  preserved verbatim as the record of what was published."*

This is the right shape. A corrections regime that rewrites what it previously said is not a
corrections regime; the reader must be able to see both the claim and its withdrawal.

### Residual mentions of the retracted terms — checked, all benign

I swept all six files for `TLS` / `encrypted in transit` / `re-verified` / `git-data host` /
`web-2` / `fsn1` **outside** the preserved July-2 segment. Every hit is inside either the new
July-24 retraction head or the retraction annotation — i.e. **describing the retraction**, never
asserting the measure. The two live `TLS` hits that remain in body prose
(`privacy-policy.md` §11 *"All communication with the Web Platform is protected by TLS"*;
`data-protection-disclosure.md:316` limb (c) *"TLS for data in transit"*) are **user↔platform**
transport claims, which are true and unaffected — they are not the retracted host↔host claim.
`web-2` and `fsn1` now appear **only** on the banner line in all six files (verified by line
number), never in a current-state section.

## Per-artifact verdict

| Artifact | Claim(s) cross-checked | Verdict |
|---|---|---|
| `docs/legal/privacy-policy.md` (banner; §Hetzner `:298`; §Transfers `:489`; §11 Security `:519`) | (a)(b)(c) retracted at every site carrying them; multi-host premise dropped at `:298`/`:489`/`:519`; LUKS retained and re-anchored to the Helsinki host at `:298`/`:519` with the `hel1` antecedent present at `:297`; per-workspace access-control retained (true of the live platform); no LUKS claim added at `:489` | **CONFIRMED** — accurate to the live topology; no surviving sentence asserts infrastructure that does not exist. |
| `docs/legal/gdpr-policy.md` (banner; §2.2 `:44`; §Transfers `:318`) | The word-order variant *"a dedicated host for per-workspace git data"* correctly caught and retracted at `:44` (a DPD-tuned find-and-replace would have missed it); the italic retrospective carrying an anchor token also dropped; `Ref #6538` → `Ref #6588`, date → July 24 2026; no LUKS claim added at `:318` | **CONFIRMED**. |
| `docs/legal/data-protection-disclosure.md` (banner; §4.2 processor table `:189`; §Transfers `:276`; §(e) limb `:318`) | Highest-grade site. The Processing-Activity cell drops (a)(b)(c) + web-2 and the never-built per-workspace git-data *fetch-authorization* claim; the Data-Processed cell keeps LUKS re-anchored to the serving host; limb (e) corrected from *"Helsinki, Finland and Falkenstein, Germany"* → Helsinki only | **CONFIRMED** — this is the Art. 13(1)(e)/30(1)(d)-grade cell and it is now true. Limb (e) carried **none** of the union-anchor tokens and was found by separate measurement, not by the Phase-1 grep; catching it matters because a stale two-DC transfer locative is a Chapter V-adjacent misstatement. |
| `plugins/soleur/docs/pages/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` (Eleventy mirrors) | Every substantive replaced line is **byte-identical** to its canonical counterpart (verified by exact string match, 3/3 substantive lines per file); July-24 head and retraction annotation identical; the Eleventy `<p>Effective … | Last Updated July 24, 2026</p>` subtitle updated in each | **CONFIRMED** — mirrored in lockstep. Mirror banners legitimately carry a truncated `Previous:` history and are edited in place, which is the established convention and changes no heading sequence, so `legal-doc-consistency.test.ts` is unaffected. |
| `knowledge-base/legal/article-30-register.md` — PA-1 (d)/(e)/(g), PA-2 (d)/(e)/(g), PA-8 (e), Vendor/Sub-Processor Mapping row | Recipients narrowed to a single `hel1` host; transfer cells drop the `fsn1` second host and the never-provisioned CAX11 with `#6570 OPEN` cited; TOM cells (g) replace the git-data-volume LUKS item with the **live workspaces-volume** item (ADR-119, mapper `hcloud_volume.workspaces_luks`, run 30130277489) and **delete** register items 14/15 and 18/19 (the host↔host TLS proxy and the membership-gated fetch authorization) as never realised; the vendor row retires the `fsn1` locative to the audit trail | **CONFIRMED, and this is the block-B2 cure.** The internal register no longer over-claims relative to the public documents. I note approvingly that **PA-2's own (d) and (e) were not in the plan's enumeration** and were found by re-running the union anchor over the whole file — a partial register correction shipped alongside a public retraction would have been the worse outcome of the two. |
| `knowledge-base/legal/compliance-posture.md` (Hetzner DPA scope row, `:80`) | Data-location narrowed to `hel1` only; both the retired standby and the **never-ordered CAX11** removed from DPA scope, with the CAX11 removal correctly characterised as *"a demonstrability defect, not a coverage gap"*; no re-sign, no sub-processor change, no third-country-transfer change; `fsn1` preserved in-cell as audit trail; Better Stack `eu-fsn-3` correctly flagged as a distinct, unaffected processor | **CONFIRMED.** The re-sign analysis is right: the AVV is host-count- and EU-DC-agnostic and `hel1` is under the same account. |
| `knowledge-base/engineering/architecture/nfr-register.md` (`:522`, Compute row) | `Not Implemented` → `Implemented / LUKS (cryptsetup)`, citing ADR-119, the 2026-07-23 cutover certification and the 2026-07-24 re-assert — **and naming the retained plaintext volume as a ledgered `plaintext-exception` (#6897) pending a soak blocked on #6808** | **CONFIRMED.** Note the internal record states the residual plainly. That is the correct internal posture and it is what discharges Art. 5(2) here; it is also precisely the asymmetry §B1 is about. |
| `apps/web-platform/lib/legal/legal-doc-shas.ts` | Three SHA pins re-computed | **CONFIRMED — recomputed independently.** `sha256sum` of each amended canonical file matches its pin byte-for-byte (`data-protection-disclosure` `e6b00414…`, `gdpr-policy` `dabb5105…`, `privacy-policy` `85373780…`). `tc-document-sha-guard` will pass; `terms-and-conditions.md` is untouched. |
| `scripts/encryption-posture-ledger.json` (two `disclosed_as` citations) | `docs/legal/privacy-policy.md:519` → `…:Encrypted, access-controlled workspace storage`; `docs/legal/data-protection-disclosure.md:316` → `…:TLS for data in transit` | **CONFIRMED — both anchors resolve** (each string occurs exactly once in its target file). This satisfies `cq-cite-content-anchor-not-line-number` and, more to the point, survives the next legal-doc edit that shifts line numbers. |
| `knowledge-base/project/specs/feat-6538-web2-fsn1-orphan/decision-challenges.md` DC-1 | Marked **RESOLVED 2026-07-24**, with §Resolution recording (1) certified encryption, (2) whole-family retraction + re-scope, (3) **that its own 7-day reopen trigger (2026-07-23) lapsed by one day**, and (4) what is expressly *not* resolved — the plaintext residual | **CONFIRMED, and the lapse disclosure is the right call.** The entry does not argue the trigger away; it states that the trigger was written against a date, fired by its own terms, and that the substantive risk it guarded (an *unscheduled* window) did not materialise. Recording a fired trigger rather than eliding it is what makes the next one credible. |
| `knowledge-base/project/specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md` DC-1 | The B1 acceptance record: the #6918 UC-3 hold; the revisit-trigger analysis as put; the operator's reaffirmation; the CLO's contrary recommendation preserved unamended; the accepted residual with #6808 named | **CONFIRMED.** My plan-time reasoning is reproduced accurately and is **not softened** — including the point that Arts. 13/14 are not the source of the duty, that Art. 32(1) is substantive not publicational, that Art. 5(2) is discharged internally, and that what decided it was the #6588 over-claim standard anchored on **Art. 12(1) + 5(1)(a)**. |

## The four plan-time CLO blocks

| Block | Plan-time position | Status in this PR |
|---|---|---|
| **B1** — no re-scoped clause (d) without an accompanying retained-plaintext disclosure sentence | Blocking | **OVERRIDDEN by operator decision, 2026-07-24. Residual accepted and tracked on #6808.** See §B1 below. |
| **B2** — no public retraction without the Article 30 register + `compliance-posture.md:80` corrections in the *same* PR | Blocking | **CURED.** Register PA-1/PA-2/PA-8 + vendor row, DPA scope row, and the NFR register all corrected in this diff. |
| **B3** — no in-place edit of the `Previous: July 2, 2026` wording; annotate only | Blocking | **CURED.** July-2 segment byte-identical (818/823/827) in all six files; annotation appended at the end. |
| **B4** — no published wipe date while #6808 is open | Blocking | **STANDS and trivially satisfied** — nothing about the plaintext volume is published at all, so no date can be published about it. Satisfied by the same absence that constitutes B1's residual. |

## §B1 — recommended, overridden, residually accepted

**This section exists because an attestation that silently omits its own overridden block is
worthless.** I record it as an accepted exception, not as a re-ruling. My position below is
**unamended**: I do not retract it, I do not soften it, and I do not represent it as satisfied.

### What I recommended

**No re-scoped clause (d) should ship without an accompanying retained-plaintext disclosure
sentence.** The re-scoped sentence — *"stored workspace git data sits on a LUKS-encrypted
volume"* — reads to any ordinary user as a statement about **their data**, not about **one
volume**. Meanwhile a full, un-wiped plaintext copy of every workspace remains on
`hcloud_volume.workspaces` (`format = "ext4"`, `apps/web-platform/infra/server.tf`),
retained attached-unmounted as the ADR-119 rollback backstop. That copy defeats **precisely the
threat the sentence advertises**, and Soleur has the admission in writing in its own ledger:

> `does_not_defend: "a seized/snapshot disk exposes any workspace data still resident on this volume."`

My reasoning, for the record:

- **Arts. 13/14 are not the source of the duty.** TOMs are not an enumerated limb of the
  information obligations, and a transient storage-media state is operational detail outside them.
- **Art. 32(1) is substantive, not publicational.** It obliges appropriate measures; it creates
  no disclosure duty of its own.
- **Art. 5(2) is discharged internally** — by the `plaintext-exception` ledger row and by the
  Article 30 register entries at PA-1(g) and PA-2(g), both of which state the residual plainly.
- **What decided it is the #6588 over-claim standard itself**, anchored on **Art. 12(1)
  (transparent, intelligible information) + Art. 5(1)(a) (fairness and transparency)**. #6588
  exists because a published Article 32 claim outran the infrastructure. A PR whose entire
  purpose is to close that gap should not leave a narrower instance of the same gap open. The
  correct citation is **Art. 12(1) + 5(1)(a)**, **not** Art. 13(3) — noted so that whoever writes
  the deferred wording does not propagate a loose anchor.

### What was decided

The question was re-raised on **2026-07-24** with the revisit-trigger analysis. The UC-3 hold
(PR #6918) carries its own revisit condition — *"if the teardown slips materially, revisit
Path 2"* — and **that trigger has fired**:

- **#6808 is OPEN** — `WORKSPACES_LUKS_HEARTBEAT_URL` is unwired, so `luks-monitor.sh` runs,
  succeeds, and pushes nothing.
- `workspaces-luks-soak-6604.sh` gates on a heartbeat **present** with rows spanning **≥ 7 days**.
  With the URL unwired, **the ADR-119 soak clock has not started**.
- No soak ⇒ no Phase-5 wipe ⇒ the residual stays live. Earliest possible cure is
  **"#6808 fix + 7 days"**, with **no committed date** for either leg.

Presented with that, the **operator reaffirmed the hold**, choosing **Path 1 (cure the reality —
wipe the volume)** over **Path 2 (qualify the published wording)**, and directed that the blocker
be escalated instead. The operator did not decline the finding.

**Disposition: B1 is OVERRIDDEN. The residual is accepted, not cured.**

### The residual, stated without euphemism

The re-scoped LUKS clause ships while a full un-wiped plaintext copy of every workspace remains
on a seizable disk. Its plain reading is broader than the infrastructure earns, **and users are
not told**. This is an **accepted, undisclosed residual** — accepted, not unnoticed.

### What bounds it today

- **Zero arms-length data subjects.** #3723 is **OPEN** (verified live); the volume holds the
  operator's own dogfooding workspaces. **No data subject has yet been misled.** This is the
  fact the whole acceptance rests on, and it is the fact most likely to change.
- **The residual is ledgered** — `scripts/encryption-posture-ledger.json`,
  `hcloud_volume.workspaces`, `mechanism: plaintext-exception`, `tracking_issue: "#6897"`,
  `expires_on: 2026-10-22`. That expiry is an **INTERNAL commitment and is never published**;
  it must not be read as a public undertaking to any data subject.
- **Named in the Article 30 register** at PA-1(g) and PA-2(g), and in the NFR register — so the
  internal record is accurate even though the public record is silent.
- **#6808 was escalated by this PR** to `priority/p1-high` + `type/security` (verified live on
  the issue), with a comment dated 2026-07-24T22:36Z recording that it now gates a **live
  published over-claim** rather than only a monitoring gap. I concur with `p1-high` over
  `p0-critical`: *"drop everything"* is the opposite of the decision taken and is not earned on
  today's facts, while *"degraded functionality, no workaround"* is exact for a soak clock that
  cannot start.
- **`Ref #6897`, never `Closes #6897`** — closing it would orphan the live ledger
  `tracking_issue: "#6897"` rows and the `model.c4` references, leaving live exceptions pointing
  at a closed issue.

### Escalation trigger, recorded now so it is not re-derived later

**If #3723 (or any other route) onboards a first arms-length user while #6808 is still open,
this becomes p0, the hold must be re-raised, and the published wording must be qualified
*before* that user is onboarded.** The bounding fact disappears at the moment of onboarding,
not at the moment anyone notices.

## Non-blocking observations

- **A. Plural "Hetzner data centres" locative persists at four non-amended sites** —
  `privacy-policy.md:297`, `gdpr-policy.md:98`, `gdpr-policy.md:388`,
  `data-protection-disclosure.md:316` limb (c). These remain **accurate** (Hetzner operates
  multiple EU data centres; each of these sentences then names Helsinki explicitly as where
  workspace data sits) and none asserts a multi-host Soleur topology, so there is **no
  over-claim and no failing gate**. Flagged only as a tidiness item for the next legal-doc pass;
  fixing it in this PR would have expanded the diff beyond the retraction without improving
  accuracy.
- **B. The DPD Section 4.2 processor table is the highest-grade disclosure surface in this
  family and should lead future correction sweeps.** This PR ordered it correctly. Recorded so
  the ordering is not re-derived: the recipient table outranks the TOM prose, because a false
  recipient entry is an Art. 30(1)(d) defect, not merely an Art. 32 one.
- **C. Eleventy-mirror banner history remains legitimately truncated** relative to canonical
  (fewer `Previous:` entries). Pre-existing and conventional; body equivalence is enforced by
  `check-tc-document-sha` for `terms-and-conditions` only, and the substantive lines here are
  byte-identical. No action.

## Overall disposition

**DISCHARGED WITH ONE ACCEPTED RESIDUAL — proceed to ship.** I reach this conclusion on the
merits, not by deference.

The PR does the harder and rarer thing correctly: it removes three published Article 32 claims
**as a whole family** across all six published surfaces, rather than trimming a head and leaving
dependent clauses to make the survivor read stronger — which is the specific defect that made
#6588 necessary. Each retraction is evidenced against infrastructure that cannot support the
claim (#6538 CLOSED; no load balancer, single-host DNS pin; #6570 OPEN with CAX11 orderable in
0 of 3 EU DCs). The one surviving claim is re-scoped onto a topology that exists and is verified
**live on the day of the PR**, with a deliberate re-assert rather than a stale green. The
historical record is annotated additively and preserved byte-identically, which is what makes a
corrections banner worth reading. The internal registers are corrected **in the same PR**, so the
internal record never over-claims relative to the public one — and the register sweep went beyond
the plan's own enumeration to catch PA-2(d)/(e). Blocks **B2, B3 and B4 are satisfied**.
**No surviving published sentence misstates the infrastructure.**

**The residual, stated exactly:** the re-scoped LUKS encryption-at-rest clause ships while a
full un-wiped plaintext copy of every workspace remains on `hcloud_volume.workspaces`,
attached-unmounted, un-wiped, and **undisclosed to users**. I recommended an accompanying
disclosure sentence (block **B1**); the operator reaffirmed the hold and B1 was **overridden**.
I have not withdrawn that recommendation. It is carried here as an **accepted exception**,
tracked on **#6808**, bounded by the fact that there are **zero arms-length data subjects today**
(#3723 OPEN), ledgered internally as a `plaintext-exception` (#6897, `expires_on: 2026-10-22`,
never published), and named in the Article 30 register. The acceptance is survivable **only**
while that bounding fact holds; the escalation trigger above is the condition on which it stops
being survivable.

Tier classification for `tc-version-bump-policy.md`: **Tier 1 (material)**. **No `TC_VERSION`
bump** — that constant governs `docs/legal/terms-and-conditions.md` exclusively, and the three
documents amended here are notice/disclosure documents with no re-acceptance gate.

All output in this PR and in this audit remains **draft material requiring professional legal
review**. This attestation is the **v1 internal CLO-agent sign-off** under the
Soleur-as-tenant-zero posture — the operator retains an optional veto, and **external** counsel
re-review is reserved for the frontmatter re-evaluation triggers, the first of which
(#6808 clearing / the plaintext wipe completing) is the one that retires this audit's residual.

*(End of the 2026-07-24 review, preserved verbatim. It is superseded from here.)*

---
---

# Amendment No. 1 — re-attestation against HEAD `25e5de36e`

**Date:** 2026-08-02
**Amending authority:** `clo` agent (Soleur legal domain leader), v1 counsel-review attestation
authority per the Soleur-as-tenant-zero posture.
**Effect on the 2026-07-24 sign-off:** **WITHDRAWN.**
**Disposition of the ship Phase 5.5 Counsel-Review CLO-Attestation gate: BLOCKED.**

## A1.1 — Why this amendment exists

The 2026-07-24 attestation certified a diff that was not shipped. Two things happened after it
was written and neither triggered a re-review:

1. **The 2026-08-01 rebase onto `main`** (60 commits) carried DC-2, which reversed the PR's own
   position on the git-data Article 32 items — from *delete as never realised* to *retain as
   `DRAFTED / NOT-YET-ACTIVE`* — because #6570 closed and the host was repinned `cax11` →
   `cpx22`. Block **B2** had been graded `CURED` **on the deletion**.
2. **`main` published a newer banner head** (#7100, July 31, 2026) while this branch sat, so this
   PR's own entry is demoted to `Previous:` and the head it was attested as prepending does not
   exist.

An attestation is load-bearing evidence for a gate. Once the thing it describes changes, it stops
being evidence and starts being a false record — and a false counsel-review record is a worse
artifact than none, because the gate reads as discharged. That is the defect this amendment
closes.

## A1.2 — The false rows, corrected

Each row below was re-verified independently at HEAD `25e5de36e` on 2026-08-02. Methods are in
§A1.9.

| # | What the 2026-07-24 audit asserted | What is true at HEAD | Correction |
|---|---|---|---|
| **1** | Per-artifact verdict on `apps/web-platform/lib/legal/legal-doc-shas.ts`: *"CONFIRMED — recomputed independently … matches its pin byte-for-byte (`data-protection-disclosure` `e6b00414…`, `gdpr-policy` `dabb5105…`, `privacy-policy` `85373780…`)"* | The pins at HEAD are `data-protection-disclosure` **`656f7a59…`**, `gdpr-policy` **`10bceac9…`**, `privacy-policy` **`44d7aaaa…`**. The three quoted prefixes match **no file and no commit on this branch**. | The *conclusion* is true at HEAD — I recomputed `sha256sum` over the three canonical files and all three match their pins byte-for-byte — but the *evidence quoted for it was not*. The quoted digests are **struck**. `docs/legal/terms-and-conditions.md` is untouched (`f3640a38…`), so `tc-document-sha-guard` passes and no `TC_VERSION` bump is engaged. **This recomputation expires the moment any of rulings A–E lands**: every one of them edits all three canonical files, so all three pins must be regenerated and this row re-verified before the next sign-off. |
| **2** | *"A **new July 24, 2026 head** is prepended … Byte-identical across all six files (head length **1426** in each)"* and *"The **July 16, 2026 entry is demoted** to `Previous:` intact."* | The published head is **July 31, 2026 (Ref #7100)**. This PR's #6588 entry sits at **`Previous: July 24, 2026`**. The July-16 entry was demoted by #7100, not by this PR. | The audit's Article 12(1) analysis — *"the reader must be able to see both the claim and its withdrawal"* — was performed on a banner structure **this PR does not produce**. Re-analysed at **ruling E**, where it fails. The byte-identity finding survives: I re-verified the #6588 entry and the `workspaces-luks-verify` clause are byte-identical across all six files. |
| **3** | Block **B2 CURED**, on the ground that the register *"**delete**[s] register items 14/15 and 18/19 (the host↔host TLS proxy and the membership-gated fetch authorization) **as never realised**"* | Items **(14)/(15)/(16)** in PA-1(g) and **(18)/(19)/(20)** in PA-2(g) are **retained** as `DRAFTED / NOT-YET-ACTIVE`, each expressly stating *"asserts NO present-tense measure"*, with a dated 2026-08-01 correction note in each TOM cell. | The graded fact is gone. **B2 is re-graded on the merits in §A1.3** — partly cured, partly re-opened. |
| **4** | *"**#6570 OPEN**, pulled live — 'git-data is pinned to cax11 — orderable in 0 of 3 EU DCs, **so it can never be born**'"*, cited as the evidence that retraction limb (c) describes the impossible | **#6570 is CLOSED** (verified live 2026-08-02). The host was repinned `cax11` → `cpx22` and is orderable. | The impossibility premise is **withdrawn**. `soleur-git-data` is **unprovisioned**, not unprovisionable — verified absent from the live Hetzner account 2026-08-01 (4 servers: `soleur-web-platform`, `soleur-web-2`, `soleur-registry`, `soleur-inngest`). Retraction of limb (c) as a *present-tense* claim remains correct; retraction of it as a claim that *could never* be true does not. Consequence at **ruling D**. |
| **5** | Per-artifact verdict on `knowledge-base/legal/compliance-posture.md`: *"Data-location narrowed to `hel1` only; both the retired standby and the **never-ordered CAX11** removed from DPA scope"* | Neither happened. The Hetzner row's **Data Region** cell still reads **`hel1 (Finland) + fsn1 (Germany)`**, and the git-data host is **retained in DPA scope** as CPX22 with a *"DECLARED in IaC but NOT YET PROVISIONED"* qualifier added 2026-08-01. | The audit conflated two different rows in two different files: the **Art. 30 register's** Vendor/Sub-Processor row *did* narrow to `hel1` only; the **compliance-posture** DPA row did not. Verdict re-issued as **PARTIALLY CONFIRMED**: the not-yet-provisioned qualifier is the right treatment and is correct on the facts; the Data Region column is now an internal inconsistency (register says `hel1`, posture says `hel1 + fsn1`). Non-blocking — it over-states rather than under-states the footprint, both DCs are EU under one AVV, and it is an internal record. Logged at §A1.8. |

## A1.3 — Block B2, re-graded on the merits

B2 was: *no public retraction without the Article 30 register + `compliance-posture.md` corrections
in the **same** PR.* Its purpose was to stop the **internal record over-claiming relative to the
public one**. The DC-2 reversal changed the fact it was graded on, so it is re-graded here, on
the retain-as-`DRAFTED` disposition, on its merits.

### (i) The retain-as-DRAFTED disposition is correct. I endorse it.

The DC-2 reversal was the right call and I would have reached it independently:

- **A `DRAFTED / NOT-YET-ACTIVE` item that says "asserts NO present-tense measure" over-claims
  nothing.** B2 was aimed at over-claiming. This disposition does not over-claim; it timestamps.
- **Deleting would have been *under*-claiming** — the mirror-image defect and the same class.
  Article 30(1)(g) asks for a general description of the technical and organisational measures;
  a designed measure recorded as not-in-force, with its activation condition named, is a more
  accurate record than silence. Deletion also destroys the Article 13(3) advance-notice value the
  register is relying on for the whole #5274 Phase-3 plane.
- **It converges on the house remedy.** #6982 had already applied exactly this treatment to the
  sibling items (13)/(17) on `main`. Inventing a second remedy for the same situation, in the same
  register, would have made the register harder to read than the problem it solved.
- **The premise for deletion is factually dead** (row 4 above). "Never realised" is not a true
  statement about `soleur-git-data`; "not yet realised" is.

### (ii) But B2 is **re-opened in the direction the reversal created**

B2 required the internal and public records to **agree**. DC-2 moved the register and **did not
move the public documents**. Two disagreements now exist, and both run in the worse direction —
the published text is **stronger** than the Article 30 register:

**(a) The retraction banner still says "never".** Register items (14)-(16)/(18)-(20) say the
measures are designed and not yet in force. The published July-24 banner entry says they
*"describe infrastructure that does not exist and, for two of them, **never did**"*, and the
July-2 retraction annotation says they *"were **never realised** in the live platform"*. The
statutory register and the published correction now assert contradictory things about the same
three measures. Cure: **ruling D**.

**(b) The per-workspace git-data authorization is asserted publicly and disclaimed internally.**
Register (15)/(19): *"Per-workspace membership-gated git-data fetch authorization — DRAFTED /
NOT-YET-ACTIVE … asserts NO present-tense measure."* Published, in the present tense, at
`docs/legal/privacy-policy.md:318`, `:549` and `docs/legal/gdpr-policy.md:45` plus three mirrors.
The code agrees with the register, not with the documents: `fetchFromGitData` returns at
`apps/web-platform/server/git-data-client.ts:197` on `!isGitDataStoreEnabled()` **before**
reaching `authorizeGitDataAccess(...)` at `:201`; the write path has the identical shape at
`git-data-replication.ts:335-338`; and the flag is `process.env.GIT_DATA_STORE_ENABLED === "true"`
(`workspace-resolver.ts:56-58`), default false. Cure: **ruling B**.

### (iii) B2 verdict

**B2 — CURED as to the register's own internal accuracy; RE-OPENED as to public/internal
agreement.** The re-opened half is **merge-blocking**, and it is blocking for exactly B2's
original reason: this PR exists because a published Article 32 claim outran the infrastructure,
and it would ship two more instances of that.

## A1.4 — What survives the amendment unamended

Re-verified at HEAD, still good:

- **The claim-family analysis and the whole-family removal method** for (a)/(b)/(c). This remains
  the substantive strength of the PR and the reason the 2026-07-16 defect is not repeated.
- **B3 — CURED.** The `Previous: July 2, 2026` entry body is unchanged; only an appended
  annotation is new. Note for ruling D: **that annotation has itself never been published** (this
  branch never merged; `main` published July 31 from #7100), so editing the *annotation* text
  before it ships is not an in-place edit of the historical record and does not engage B3. The
  July-2 entry body must still not be touched.
- **B4 — STANDS, trivially satisfied.** Nothing about the plaintext volume is published, so no
  wipe date can be.
- **§B1 and the accepted residual — carried forward unamended.** The operator's DC-1 hold is
  **not reopened** by this amendment. It is reaffirmed, twice, and it is not mine to reverse. But
  see §A1.5: the residual it bounds is now **larger** than the 2026-07-24 record describes, for a
  reason the 2026-07-24 review did not analyse.
- **Tier 1 (material), no `TC_VERSION` bump.** Unchanged and correct.
- **Re-evaluation trigger (5)** ("any change of Hetzner locative away from `hel1` only") has
  **not** fired: the second web host re-added 2026-07-27 (#6919 / ADR-143) is in `hel1`.

## A1.5 — The residual grew, and the 2026-07-24 review recorded the growth as a narrowing

This is the most consequential finding in the amendment, so it is stated separately from the
false-row table.

The 2026-07-24 audit characterised the LUKS clause change as a **re-scope onto the live
topology** — a narrowing — and its §B1 residual was framed as *"the plain reading is broader than
the infrastructure earns."* Measured against the diff, the change is a **strengthening**:

- **Before:** *"**Where the Web Platform spans more than one Hetzner host in the EU region**,
  stored workspace git data sits on a LUKS-encrypted volume…"* — a conditional whose antecedent
  was false, and which therefore **asserted nothing**.
- **After** (`docs/legal/privacy-policy.md:549`): *"Stored workspace git data sits on a
  LUKS-encrypted volume (encryption at rest) on the Hetzner host in the EU region that serves the
  Web Platform"* — **universal and unhedged**, and expressly located on the serving host.

Meanwhile `hcloud_volume.workspaces` (`format = "ext4"`, resource `hcloud_volume.workspaces` in
`apps/web-platform/infra/server.tf`) is created `for_each = var.web_hosts` and attached by
`hcloud_volume_attachment.workspaces` to `hcloud_server.web[each.key]` — so the un-wiped plaintext
copy is attached to **the very host the new sentence names**. The new locative does not distance
the claim from the residual; it points at it.

Two consequences the 2026-07-24 review did not draw:

1. **The PR removed a scoping antecedent, making the sentence strictly stronger in the exact
   dimension #6588 is about.** DC-1 asked the operator *"may we add a disclosure?"* and was
   answered no, twice. It never asked *"may we strengthen the claim?"* — and the strengthening is
   what shipped.
2. **`scripts/encryption-posture-ledger.json` records that store as
   `"disclosed_as": "not-publicly-claimed"`.** The published universal is broad enough to be read
   as a claim covering data resident on it, so the ledger's own assertion is not true of the
   published text as it stands. The ledger is machine-linted and fails closed on unresolvable
   anchors (`scripts/lint-encryption-posture.py`, `resolve_disclosed_as`, test cases TS-17/TS-18)
   — but no linter can catch prose that is broader than the store it names.

Cure: **ruling C** — a referent narrowing that discloses nothing, adds no sentence, states no fact
about any other volume, and restores the ledger's own `not-publicly-claimed` assertion to truth.
**It does not breach the DC-1 hold** and it is not a re-litigation of it; the analysis is in the
ruling.

## A1.6 — Fresh defect, not present in the 2026-07-24 review

The published evidence citation for the one retained Article 32 claim is **falsifiable by one
command**, and its tense is unsupported. All six files carry, byte-identically:

> *"it is verified live (`workspaces-luks-verify`, device_type crypto_LUKS on /dev/mapper/workspaces)"*

- **Falsifiable.** `apps/web-platform/infra/luks-monitor.sh` derives `real_dev` from
  `cryptsetup status` and runs `blkid -s TYPE -o value "$real_dev"` on that **backing** device.
  `/dev/mapper/workspaces` is the **decrypted** device; `blkid` on it returns `ext4`. Both internal
  artifacts state this correctly as two fields (`device_type=crypto_LUKS`,
  `mount_source=/dev/mapper/workspaces`); the published prose compressed them into one false
  compound. A reader who checks — and a corrections banner invites checking — reaches the opposite
  of the intended conclusion about the only Article 32 claim this PR retains.
- **Tense unsupported.** The latest `workspaces-luks-verify` run is **30130277489,
  2026-07-24T22:13:06Z** — **nine days** before merge. On this exact surface the documented failure
  mode (#6812) is a **silent revert within ~27 minutes**, and the continuous monitor that would
  catch one is confirmed non-reporting: **#6808 is OPEN** (verified live 2026-08-02),
  `WORKSPACES_LUKS_HEARTBEAT_URL` unwired, so `luks-monitor.sh` runs, succeeds and pushes nothing.
  The 2026-07-24 review itself set the standard — *"a stale green is the documented failure mode
  here"* and *"I would have flagged a code-only assertion"* — and a nine-day-old green is a stale
  green by that standard.

Cure: **ruling A**, plus the merge-day gate in §A1.7.

## A1.7 — Revised disposition

**BLOCKED. Not signed off. Do not treat the ship Phase 5.5 Counsel-Review CLO-Attestation gate as
discharged.**

Four merge-blocking defects, each with exact replacement wording issued to the operator in the
same review:

| Ref | Defect | Why blocking |
|---|---|---|
| **A** | Falsifiable + stale-tense evidence citation for the retained Article 32 claim, in all six published files | A corrections notice whose own evidence citation is disprovable by one command destroys the credibility of the correction. Compounded by nine-day-old evidence with the monitor down (#6808). |
| **B** | Present-tense per-workspace git-data authorization published in three documents that this PR's own Article 30 register marks `DRAFTED / NOT-YET-ACTIVE`, and that the code does not execute | Published record stronger than the statutory register — the #6588 defect class exactly. Also an unresolved three-way disagreement among the published documents (the DPD dropped the claim; two others kept it). |
| **C** | Removal of the scoping antecedent converted an inoperative conditional into a universal encryption-at-rest claim, on the same host that carries the un-wiped plaintext copy | A **net-new** over-claim of the #6588 class, introduced by #6588's own PR, never put to the operator. |
| **D** | Banner and July-2 annotation still say "never" where the register now says "not yet"; banner limb (i) mis-names its own subject; the web-2 retirement sentence is stale | Direct public/internal contradiction on a statutory record. Half of B2's cure has been undone by the reversal that came after the sign-off. |

Plus **E** (banner head date / change-signal), which I rule untenable — see the ruling.

**Merge-day gate, required in addition to the wording fixes:** re-run `workspaces-luks-verify`
and record the fresh run ID **on the day the PR merges**. This is not belt-and-braces; it is the
evidentiary standard the 2026-07-24 review itself set for this surface, and #6808 being open means
nothing else is watching.

**Re-attestation required** once A–E land. It must, at minimum: recompute the three SHA pins
(row 1 above expires on those edits), re-verify canonical/mirror byte-identity at every changed
site, re-verify the banner head date against the actual merge date, and confirm no ledger
`disclosed_as` anchor was orphaned by the bullet-label change in ruling C
(`scripts/lint-encryption-posture.py` fails closed on an unresolvable anchor — TS-18).

## A1.8 — Non-blocking internal-record items opened by this amendment

- **`knowledge-base/legal/compliance-posture.md`, Hetzner row, Data Region column** reads
  `hel1 (Finland) + fsn1 (Germany)` while the Article 30 register's Vendor/Sub-Processor row now
  reads `hel1` only. The Notes cell legitimately retains `fsn1` as audit trail; the **Data Region
  column** is the machine-read field and over-states the live Hetzner compute footprint. P2 —
  over-, not under-statement, both DCs EU under one AVV, internal record only.
- **`scripts/encryption-posture-ledger.json`**, store `hcloud_volume.workspaces`, `evidence`
  field still cites `apps/web-platform/infra/server.tf:1569`. At HEAD line 1569 is an unrelated
  sysctl comment; the resource is `resource "hcloud_volume" "workspaces"` (line 1779). Stale
  line-number citation — violates `cq-cite-content-anchor-not-line-number`, the same rule this PR
  applied to the two `disclosed_as` fields but did not apply to `evidence`. P2.
- **`plugins/soleur/docs/pages/legal/*.md` Eleventy subtitles** (`<p>Effective … | Last Updated
  July 31, 2026</p>`) must move in lockstep with whatever ruling E produces. Mechanical, but it is
  a third surface beyond canonical and mirror body text and is easy to miss.

## A1.9 — Method

Everything in this amendment was pulled at HEAD `25e5de36e` on 2026-08-02. Nothing was carried
over on trust from the 2026-07-24 pass.

- **SHA pins:** `sha256sum` over the three amended canonical files plus
  `docs/legal/terms-and-conditions.md`, compared against
  `apps/web-platform/lib/legal/legal-doc-shas.ts`.
- **Issue states:** `gh issue view` for #6570, #6808, #3723, #6538, #6897, #7100, #7119.
- **Banner structure:** direct extraction of the head and the `Previous:` chain from all six
  published files, plus a byte-identity comparison of the #6588 entry and the
  `workspaces-luks-verify` clause across canonical and mirror.
- **Register:** items (13)-(17) in PA-1(g) and (17)-(21) in PA-2(g) extracted in full from
  `knowledge-base/legal/article-30-register.md`, plus the diff of that file against `main`.
- **Code:** `apps/web-platform/server/git-data-client.ts` (`:79` `authorizeGitDataAccess`, `:197`
  the flag early-return, `:201` the authz call), `git-data-replication.ts:335-338`,
  `workspace-resolver.ts:56-58` (flag default) and the live `workspace_members` /
  `is_workspace_member` gates at `workspace-resolver.ts:124-193`, `:394-415`, `:755-793`.
- **Infrastructure:** `apps/web-platform/infra/server.tf` (`hcloud_volume.workspaces` and
  `hcloud_volume_attachment.workspaces`), `apps/web-platform/infra/luks-monitor.sh:150-172`.
- **Evidence freshness:** `gh run list` for `workspaces-luks-verify`.
- **Ledger:** `scripts/encryption-posture-ledger.json` plaintext-exception entries and
  `scripts/lint-encryption-posture.py` `resolve_disclosed_as`.

## A1.10 — Standing of this amendment

This amendment is the **v1 internal CLO-agent attestation** under the Soleur-as-tenant-zero
posture. It is a **BLOCKED** disposition, not a sign-off, and it is issued on the merits rather
than deferred to the operator — the operator is a non-lawyer founder and this review is a CLO
function. The operator retains an optional veto. **External** counsel re-review remains reserved
for the frontmatter re-evaluation triggers.

All output in this PR and in this audit remains **draft material requiring professional legal
review**.

*(End of Amendment No. 1. Its BLOCKED disposition is discharged by Amendment No. 2 below. It is
preserved unamended: the defects it found were real, and an audit trail that deletes its own
findings once they are fixed cannot be used to show that they were ever fixed.)*

---
---

# Amendment No. 2 — re-attestation against HEAD `c9747f0aa`, and lifting of the block

**Date:** 2026-08-02
**Amending authority:** `clo` agent (Soleur legal domain leader), v1 counsel-review attestation
authority under the Soleur-as-tenant-zero posture.
**Effect on Amendment No. 1:** its **BLOCKED** disposition is **DISCHARGED**. Its withdrawal of
the 2026-07-24 sign-off **stands** — that review is not reinstated.
**Disposition: SIGNED-OFF WITH ACCEPTED RESIDUAL, subject to one pre-merge evidentiary
condition (E-1, §A2.6).**

## A2.1 — Standard of verification applied

Amendment No. 1 exists because the 2026-07-24 attestation certified a summary rather than a tree.
This amendment therefore verifies **the tree**, not the change report it was handed. Every
assertion below was recomputed at HEAD `c9747f0aa` from the working copy, hashed where a hash was
available, and pulled live from the GitHub API where the fact was remote. Where a claim could be
checked against `main` rather than against a description, it was.

## A2.2 — Per-ruling verdicts

| Ruling | Verification performed | Verdict |
|---|---|---|
| **A** — falsifiable evidence citation | The impossible compound `device_type crypto_LUKS on /dev/mapper/workspaces` returns **0 occurrences across all six** files. The replacement — *"verified live by the `workspaces-luks-verify` check, which confirms that the device backing the `/dev/mapper/workspaces` mount is a `crypto_LUKS` container"* — is present exactly once in each of the six, byte-identically. This is now consistent with `luks-monitor.sh:159-165`, which resolves `real_dev` from `cryptsetup status` and runs `blkid` on the **backing** device. The claim is no longer disprovable by inspection. | **CURED** as to content. Tense condition E-1 remains — §A2.6. |
| **B** — present-tense authz the register disclaims | `access-controlled per workspace`: **0 across all six**. The three body sites carry my exact replacement wording and are **byte-identical canonical↔mirror** (pp `318/317`, pp `549/530`, gdpr `45/54`). The published documents no longer assert a control that `git-data-client.ts:197` short-circuits before reaching. **The DPD, privacy policy and GDPR policy now agree**, which they did not at HEAD `25e5de36e`. | **CURED.** |
| **C** — universal claim vs narrowed referent | The narrowed referent is applied at **all five** sites (pp:318, pp:549, gdpr:45, dpd:189, dpd:276) plus mirrors, each byte-identical to its counterpart. No sentence about the retained plaintext volume was added anywhere — I checked the diff for additions, not just for the presence of my wording. `scripts/encryption-posture-ledger.json` still records `hcloud_volume.workspaces` as `"disclosed_as": "not-publicly-claimed"`, and that assertion is **now true of the published text**, which it was not before. | **CURED. The DC-1 hold is intact and was not circumvented.** |
| **D** — "never" vs the register's "not yet" | `never realised` and `for two of them, never did`: **0 across all six**. The head now retracts **four** measures *"as statements about the platform as it runs today"*, states *"retracted as statements about today, not abandoned as plans … recorded internally as designed and not yet in force"*, names limb (i) correctly as the **web-host ↔ git-data-host** proxy (matching register items (14)/(18)), adds the July-27 `hel1` standby, and re-dates the July-2 annotation to August 2. | **CURED.** |
| **E** — banner head date / change-signal | Head is `**Last Updated:** August 2, 2026 (Ref #6588`, byte-identical across all six at **2468 characters**. Exactly **one** #6588 entry per file — no duplicate left in the `Previous:` chain. Chain reads **August 2 → July 31 (#7100, verbatim) → July 16 → July 5 → July 2 → June 30**. The three Eleventy mirror subtitles read `Last Updated August 2, 2026`. The `#7119` live-status sentence is present. `July 24, 2026` as a current-state marker: **0 remaining** — the in-body markers at pp:318 and gdpr:45 both moved to August 2. | **CURED.** A returning data subject now receives a change signal. |

## A2.3 — Block B2: fully cured

Amendment No. 1 re-graded B2 as *cured as to the register, re-opened as to public/internal
agreement*. Both re-opened limbs are closed at HEAD:

- **(a) The "never" contradiction is gone.** The published head and the Article 30 register now
  make the same statement about the same three measures: designed, recorded, not yet in force.
- **(b) The authorization asymmetry is gone.** No published document now asserts a measure that
  register items (15)/(19) disclaim.

**B2 — CURED.** B3 and B4 continue to stand (see §A2.4). **All four plan-time CLO blocks are now
either cured (B2, B3, B4) or recorded as an accepted operator override (B1).**

## A2.4 — B3 re-verified cryptographically, not by inspection

The 2026-07-24 review asserted B3 satisfied by measuring the July-2 segment's length. That is a
weaker test than it sounds — a compensating edit preserves length. I hashed the segment against
`main` instead:

| Document | `main` July-2 segment | HEAD July-2 body (pre-annotation) | |
|---|---|---|---|
| `privacy-policy.md` | `00af6c6c25221149…`, 818 ch | `00af6c6c25221149…`, 818 ch | **identical** |
| `gdpr-policy.md` | `5ef046eec512d08e…`, 827 ch | `5ef046eec512d08e…`, 827 ch | **identical** |
| `data-protection-disclosure.md` | `6164442cc9e1628c…`, 823 ch | `6164442cc9e1628c…`, 823 ch | **identical** |

**B3 — CURED, on a hash rather than a length.** Only the appended annotation differs, and it is
byte-identical across all six surfaces.

**Ruling on the surviving `authorized per workspace` occurrences.** They remain **only** inside
the preserved `Previous: July 2, 2026 (Ref #5274)` entry. **That is correct and they must not be
touched.** That entry is the record of what was published; the July-2 annotation — which this PR
amended precisely to name that fourth measure — is what retracts it. Editing the historical entry
to remove a claim Soleur actually made would breach B3 and would convert the corrections banner
into the thing it exists to prevent: a record that silently agrees with the present. **The
coordinator was right not to touch it.**

## A2.5 — Mechanical gates, run rather than reported

| Gate | Result |
|---|---|
| `sha256sum` × 3 canonical vs `LEGAL_DOC_SHAS` | `data-protection-disclosure` `7d40e3a1…`, `gdpr-policy` `1e85dce4…`, `privacy-policy` `cc4fee45…` — **all three match byte-for-byte** |
| `terms-and-conditions.md` | `f3640a38…`, **unchanged** — no `TC_VERSION` bump engaged; Tier 1 (material) classification unchanged |
| `apps/web-platform/scripts/check-tc-document-sha.sh` | **rc=0** |
| `scripts/lint-encryption-posture.py` | **PASS** — 16 stores, 3 connections, 0 unledgered, **0 failing checks**, rc=0 |
| Ledger anchor after the (B) re-label | `docs/legal/privacy-policy.md:Encrypted workspace storage` — resolves; the TS-18 fail-closed path is not triggered |
| `legal-doc-consistency.test.ts` + `legal-doc-shas-guard.test.ts` | **19/19 passed** |

## A2.6 — Condition E-1: the one thing still outstanding, and how to discharge it

**The published head asserts, in the present tense, that the LUKS mount "is verified live."** The
newest `workspaces-luks-verify` evidence is still run **30130277489, 2026-07-24T22:13:06Z** — nine
days old at merge — and **#6808 remains OPEN** (`priority/p1-high`, `type/security`, verified live
2026-08-02), so `WORKSPACES_LUKS_HEARTBEAT_URL` is unwired and the continuous monitor runs,
succeeds and pushes nothing. On this exact surface the documented failure mode (#6812) is a
**silent revert within ~27 minutes**.

I wrote the word *"confirms"* into that sentence in ruling A. I will not attest a present-tense
verification claim on evidence I know to be stale with the monitor confirmed silent — that is
precisely the failure the withdrawn 2026-07-24 review committed after setting the standard itself.

**Two doors. Either discharges E-1; both are legally sound.**

- **Door 1 (preferred) — dispatch a fresh `workspaces-luks-verify` run on merge day** and record
  the run ID in this section. Minutes of work, requires operator authorization for the
  `workflow_dispatch`, keeps the stronger claim, and touches no files. **If it fails, do not
  merge** — merging would publish a fresh false Article 32 claim, the #6588 defect exactly.
- **Door 2 (fallback, if dispatch is unavailable or declined) — date the evidence instead of
  present-tensing it.** Replace, in all six files:
  *"and it is verified live by the `workspaces-luks-verify` check, which confirms that the device
  backing the `/dev/mapper/workspaces` mount is a `crypto_LUKS` container"*
  with
  *"and it was verified by the `workspaces-luks-verify` check on July 24, 2026, which confirmed
  that the device backing the `/dev/mapper/workspaces` mount was a `crypto_LUKS` container"*.
  This converts an unsupported present-tense claim into a supported dated one. It is **not free**:
  it re-touches all six files and requires re-pinning all three SHAs and re-running §A2.5.

**What is not acceptable is merging as-is with the present-tense claim on nine-day-old evidence.**
Weighed honestly against the cost of delay: the currently-published text on `main` is the *worse*
record — it carries the un-retracted over-claims this PR removes — so delay has a real cost to
data subjects and I do not treat E-1 as a reason to sit on the merge. That is why E-1 is scoped to
minutes and has a no-authorization fallback, rather than being an open-ended hold.

## A2.7 — Canonical/mirror banner divergence: out of scope, but track it

Measured at HEAD: canonical banners carry **13** `Previous:` entries, mirrors **10**; the
canonical-only entries are **May 25, 2026** and **May 22, 2026**, and the mirrors condense several
older BYOK/DSAR/workspace-member entries. Delta is **9,369 / 7,360 / 6,578** characters for
privacy-policy / gdpr-policy / DPD respectively.

**Out of scope for #6588 — confirmed, and the coordinator was right to leave it.** It predates
this PR by roughly two months, this PR touched none of it, and the *current* head plus every
substantive body sentence is byte-identical across both surfaces (verified above). Repairing it
inside a retraction PR would mean rewriting thousands of characters of historical published
banner text — the operation B3 exists to forbid — for no gain in the accuracy of the retraction.

**It does warrant its own tracked issue, and an incidental remark inside a disclosure is not a
tracking mechanism.** Two published surfaces carrying different correction histories is an
**Article 12(1) accessibility** question in its own right: a reader on the docs site sees a
shorter record of corrections than a reader of the repository, and the gap widens with every
correction. Recommended: **P2**, `domain/legal` + `type/compliance`, scoped to deciding whether
the mirror is intended as a *full* record or a *deliberately condensed* one — and if condensed,
publishing a link from the mirror banner to the canonical full history. That link is the actual
Art. 12(1) fix and is cheap; back-filling 9 kB of history into the mirror probably is not the
right answer.

## A2.8 — The residual, carried forward unamended

**§B1 is unchanged and is not reopened by this amendment.** A full un-wiped plaintext copy of
every workspace remains on `hcloud_volume.workspaces` (`format = "ext4"`, attached via
`hcloud_volume_attachment.workspaces` to `hcloud_server.web[each.key]`), retained as the ADR-119
rollback backstop, **and users are not told**. The CLO recommendation to disclose was
**OVERRIDDEN by the operator** on 2026-07-24 and reaffirmed; it is an **accepted, undisclosed
residual**, tracked on **#6808**, ledgered as `plaintext-exception` (#6897, `expires_on:
2026-10-22`, internal only), and named in the Article 30 register at PA-1(g) and PA-2(g).

Ruling C **narrowed the published referent so the residual is no longer aggravated by the
published wording**, which is what Amendment No. 1 required. It did **not** cure the residual, and
nothing here should be read as doing so. What bounds it is unchanged: **zero arms-length data
subjects** (#3723 OPEN, verified 2026-08-02). **The escalation trigger stands: if any route
onboards a first arms-length user while #6808 is open, this becomes p0, the hold must be
re-raised, and the published wording must be qualified *before* that user is onboarded, not
after.**

The frontmatter re-evaluation triggers are unchanged and remain live. Trigger (5) has **not**
fired — the second host added 2026-07-27 is in `hel1`.

## A2.9 — Non-blocking items still open

Both were logged in §A1.8 and are **not** cured at HEAD. Neither blocks merge; both should be
picked up with the #6897 legal-doc reconcile:

- **`knowledge-base/legal/compliance-posture.md`**, Hetzner row, **Data Region** column reads
  `hel1 (Finland) + fsn1 (Germany)` while the Article 30 register's vendor row reads `hel1` only.
  Over-statement of the live compute footprint in an internal record; both DCs EU, one AVV. **P2.**
- **`scripts/encryption-posture-ledger.json`**, store `hcloud_volume.workspaces`, `evidence` field
  still cites `apps/web-platform/infra/server.tf:1569`; the resource is at line **1779** and 1569
  is an unrelated sysctl comment. Violates `cq-cite-content-anchor-not-line-number` — the same rule
  this PR applied to `disclosed_as` but not to `evidence`. **P2.**

## A2.10 — Disposition

**SIGNED-OFF WITH ACCEPTED RESIDUAL — subject to pre-merge condition E-1 (§A2.6).**

I reach this on the merits, not by deference and not by relief that the corrections landed. The
diff at HEAD `c9747f0aa` does the hard thing correctly: it retracts four published Article 32
measures as a whole family across six surfaces, it re-scopes the one surviving measure onto a
referent narrow enough that the internal ledger's own `not-publicly-claimed` assertion is true of
the published text, it stops the published record from being stronger than the statutory register
in either direction, it preserves the historical entries byte-identically while annotating them
additively, and it gives a returning data subject an honest change signal on the day the change is
published. **No surviving published sentence misstates the infrastructure**, and — unlike the
state Amendment No. 1 found — no published sentence is stronger than the Article 30 register.

Two things this sign-off does **not** say. It does not say the retained-plaintext residual is
cured; it is accepted, undisclosed, and bounded only by the absence of arms-length data subjects.
And it does not say the merge may proceed today unconditionally: **E-1 must be discharged first**,
by either door.

Re-attestation is required only if the diff changes again. If Door 2 is taken, §A2.5 must be
re-run in full — the three SHA pins expire on that edit.

This is the **v1 internal CLO-agent sign-off** under the Soleur-as-tenant-zero posture. The
operator retains an optional veto. **External** counsel re-review remains reserved for the
frontmatter re-evaluation triggers. All output in this PR and in this audit remains **draft
material requiring professional legal review**.

*(End of Amendment No. 2. Its condition E-1 is discharged by Amendment No. 3 below.)*

---
---

# Amendment No. 3 — E-1 discharged; final disposition

**Date:** 2026-08-02
**Amending authority:** `clo` agent (Soleur legal domain leader), v1 counsel-review attestation
authority under the Soleur-as-tenant-zero posture.
**Effect:** condition **E-1 is DISCHARGED**. This audit's disposition is **final**.

## A3.1 — E-1 discharged, verified rather than accepted

Door 1 was taken. The operator authorised the dispatch and the run landed. I verified it against
the GitHub API and the raw run log rather than from the report I was handed — the whole reason
Amendments 1 and 2 exist is that a prior attestation certified a summary.

**Run 30749271370** — `workflow_dispatch`, branch `main` @ `b5871b9f6d`, created
**2026-08-02T13:07:46Z**, completed `13:08:24Z`, conclusion **`success`**. Confirmed to be the
**newest** run of `workspaces-luks-verify.yml`, ahead of 30130277489 (2026-07-24).

Extracted from the run log verbatim, not quoted from the change report:

```
[luks-monitor] OK: /mnt/data is LUKS-backed (device_type=crypto_LUKS mount_source=/dev/mapper/workspaces escrow=ok header=readable)
[luks-monitor] SOLEUR_WORKSPACES_READYZ ready=true writable=true populated=true workspace_count=8 expected=8 capacity=use=6%,mount=rw
[luks-monitor] WARN: WORKSPACES_LUKS_HEARTBEAT_URL absent — heartbeat not pushed (operator wires it at cutover)
app /health=200
workspaces-luks re-assert PASSED (blkid=crypto_LUKS, mapper mount, escrow ok, /health 200, readyz ready=true, workspace inventory >= baseline).
```

Two integrity checks I ran that were not asked for, because a matching log excerpt is not the
same as a sound measurement:

1. **The probe that ran is the probe this PR reviewed.** The run was dispatched on `main`, not on
   the feature branch. That is *correct* — the probe measures the live host, not the branch — but
   it is only equivalent if the branch has not modified the probe. `git diff main...HEAD` over
   `apps/web-platform/infra/luks-monitor.sh` and `.github/workflows/workspaces-luks-verify.yml`
   is **empty**. The measurement is therefore valid for this branch.
2. **The green is non-vacuous, and I confirmed the mechanism rather than the claim.**
   `workspace_count=8 expected=8` means the fail-closed inventory comparison had a real operand
   on both sides; the workflow's own `seed_workspace_count` documentation warns that a missing
   baseline leaves that comparison with nothing to compare, which is not what happened. The run
   was dispatched with `SEED_WORKSPACE_COUNT` empty, i.e. the read-only path — the workflow header
   documents this step as read-only and device-opening-free.

**The evidence matches ruling A exactly, and this is the point of ruling A:** the log reports
`device_type=crypto_LUKS` and `mount_source=/dev/mapper/workspaces` as **two separate fields**.
`device_type` is measured by `blkid` on the *backing* device resolved from `cryptsetup status`;
`/dev/mapper/workspaces` is the *decrypted mount source*. The withdrawn banner collapsed these
into one compound that was false of either device read alone. The published wording now mirrors
the instrument.

**E-1 is DISCHARGED.** The published present-tense clause is supported by same-day evidence.

## A3.2 — The run corroborated the reasoning that required it

`[luks-monitor] WARN: WORKSPACES_LUKS_HEARTBEAT_URL absent — heartbeat not pushed` confirms
**#6808 is live from inside the probe itself**. This is worth recording as a methodological point,
not just a fact: the merge-day gate was required on the argument that between dispatches nothing
is watching and a #6812-class silent revert would go unpaged. The run did not merely satisfy the
gate — it independently re-evidenced the premise that made the gate necessary. Had this been
waived as ceremony, the waiver would have rested on the assumption the run itself disproves.

## A3.3 — Ruling C is retrospectively validated on grounds I had not identified

Recording this because it strengthens a ruling by an argument I did not make at the time, and
because the next person to revisit ruling C should see it.

The NFR-027 register entry records, alongside the run: *"**Scope is web-1 only:** web-2's
workspaces volume is knowingly left plaintext-but-empty pre-flip — a recorded, gate-enforced
deviation from #6588's 'every `var.web_hosts` member' AC, tracked **#6931**."* This follows from
the Terraform: `hcloud_volume.workspaces` is created `for_each = var.web_hosts` with
`format = "ext4"`, while `workspaces_luks` covers **web-1 only**.

The pre-ruling wording — *"Stored workspace git data sits on a LUKS-encrypted volume … on the
Hetzner host in the EU region that serves the Web Platform"* — would have been false as to
**web-2's** plaintext volume as well, a **second** over-claim independent of the DC-1 retained
backstop, and one I did not identify when issuing ruling C. The narrowed referent
(*"the volume from which … workspace git data is served"*) excludes it correctly and for the right
reason: web-2 sits at serving-weight 0 and serves no workspace git data. **Ruling C was necessary
on two independent grounds, not one.**

## A3.4 — On strengthening #6808: no, and here is the better fix

**Do not escalate #6808 beyond `priority/p1-high` + `type/security`. Keep it where this PR put
it.** Three reasons:

- **Today produced no new fact.** The dead heartbeat is *why* #6808 exists. The run corroborated
  it; it did not discover it. Re-triaging on re-confirmation of a known fact makes priority a
  record of how recently something was looked at rather than of how bad it is.
- **`p0-critical` means "drop everything,"** which contradicts the disposition I am signing in the
  same document. A label that contradicts its own attestation degrades the label system for every
  future reader.
- **The bounding fact is unchanged** — zero arms-length data subjects (#3723 OPEN, verified).

**But the existing escalation is not sufficient either, for a reason today's run exposed.**
`workspaces-luks-verify.yml` is **`workflow_dispatch`-only** — its own header says so, and all
four runs in its history are manual dispatches. So while #6808 is open there is **no automatic
verification of any kind**: the heartbeat is the only continuous control and it is dead. Before
this PR that was an internal operations gap. It is now the thing standing behind a **published,
present-tense** Article 32 verification claim. The gap changed in **kind**, not in degree — and a
priority label is the wrong instrument for a change in kind.

**Recommended instead — a compensating control, not a label bump:**

1. **Add a `schedule:` trigger to `workspaces-luks-verify.yml` while #6808 is open.** Cheap,
   automatic, and — unlike the heartbeat — it needs no operator secret-wiring, which is precisely
   what #6808 is blocked on. This bounds the decay of the published claim without depending on the
   thing that is broken. File as a sub-task of #6808 or a linked **P2**.
   > **DISCHARGED 2026-08-03 (#6808 schedule PR).** Implemented as a daily `schedule: 41 4 * * *`.
   > The recommendation asked only for the trigger; what shipped deliberately went further, because a
   > cron without a working alarm is strictly worse than the dispatch-only state it replaces — it also
   > makes people believe the surface is monitored. So the schedule lands together with a three-class
   > alarm (`drift` / `readiness` / `unavailable`, the first being this audit's re-evaluation trigger
   > (3)), an ops-email page for the first two, and a Sentry Crons monitor covering the mode the
   > in-run alarm structurally cannot see: the run that never fires at all.
2. **#6808 should not be closeable until either the heartbeat is wired *or* the schedule
   exists.** Record that on the issue, so closing the narrow secret-wiring task cannot silently
   retire the broader guarantee.
   > **CORRECTED 2026-08-03 (#6808 schedule PR). Read the disjunction as a CONJUNCTION.** As
   > drafted, "either ... or" was harmless while neither limb existed. Now that the schedule limb is
   > satisfied it would license closing #6808 with the heartbeat still dead — retiring the broader
   > guarantee by exactly the mechanism this recommendation was written to prevent, and inverting its
   > own stated intent. The two limbs are not substitutes: the schedule is a DAILY SAMPLE taken from
   > outside the host, while `WORKSPACES_LUKS_HEARTBEAT_URL` is a CONTINUOUS signal emitted by the
   > host itself, and this audit's own §A3.4 preamble calls the heartbeat "the only continuous
   > control". A daily sample leaves an up-to-24-hour blind window that no schedule cadence closes in
   > principle. **#6808 therefore remains OPEN.** The PR that added the schedule uses `Ref #6808`,
   > never `Closes`, and satisfies only the "schedule exists" half of the recorded closure condition.
3. **Correct the #6808 comment.** The 2026-07-24 comment says it gates *"a live published
   over-claim."* Ruling C removed that over-claim, so the framing is now obsolete and overstated.
   What #6808 gates today is the **continued truth of a published present-tense verification
   claim** — accurate, still serious, and materially different. Leaving the stale framing invites
   a future reader to conclude the issue was mis-triaged and quietly downgrade it.

**New re-evaluation trigger, recorded now so it is not re-derived: claim decay.** While #6808 is
open, if no successful `workspaces-luks-verify` run lands within any **trailing 30-day window**
while the published *"is verified live"* clause stands, the clause **must** be re-tensed to a
dated past verification (Amendment No. 2, Door 2) or withdrawn. A present-tense verification claim
with nothing verifying it decays into exactly the defect class #6588 exists to close, and it
decays silently — which is the property that makes it dangerous.

## A3.5 — The residual, carried forward unchanged and unsoftened

**Nothing in this amendment cures the DC-1 residual, and nothing in the merge-day green touches
it.** A full un-wiped plaintext copy of every workspace remains on `hcloud_volume.workspaces`,
attached, un-wiped, and **undisclosed to users**. The CLO recommendation to disclose was
**OVERRIDDEN by the operator** and reaffirmed; it stands as an **accepted, undisclosed residual**,
tracked on **#6808**, ledgered as `plaintext-exception` (#6897, `expires_on: 2026-10-22`, internal
only), and named in the Article 30 register at PA-1(g) and PA-2(g).

Ruling C stopped the published wording from **aggravating** the residual. That is all it did.

**What bounds it is unchanged: zero arms-length data subjects (#3723 OPEN).** The escalation
trigger stands in full — **if any route onboards a first arms-length user while #6808 is open,
this becomes p0, the hold must be re-raised, and the published wording must be qualified *before*
that user is onboarded, not after.** The bounding fact disappears at the moment of onboarding, not
at the moment anyone notices.

Separately tracked and not part of this residual: **#6931** (web-2's plaintext-but-empty volume),
now correctly outside the published claim per §A3.3.

## A3.6 — Final disposition

**SIGNED-OFF WITH ACCEPTED RESIDUAL.**

**The ship Phase 5.5 Counsel-Review CLO-Attestation gate is DISCHARGED. There is no outstanding
pre-merge condition. Clear to merge.**

For `/soleur:ship` and any downstream gate, unambiguously:

- **Gate status:** DISCHARGED.
- **Blocking items:** none.
- **Accepted residual:** one — the DC-1 retained plaintext volume, accepted and undisclosed, not
  cured, tracked #6808 / #6897, bounded by zero arms-length data subjects.
- **Follow-ups, none merge-blocking:** the `schedule:` compensating control and the #6808 comment
  correction (§A3.4); the canonical/mirror banner divergence issue (§A2.7); the two P2
  internal-record items (§A2.9); #6931 (§A3.3).

I reach this on the merits. Across three passes this audit went from certifying a diff that was
never shipped, to blocking on five defects, to signing a diff I verified line by line against the
tree, the infrastructure, the register, the code, and a same-day live probe. **No surviving
published sentence misstates the infrastructure, and no published sentence is stronger than the
Article 30 register in either direction.** That is the standard #6588 was opened to restore, and
it is met.

This remains the **v1 internal CLO-agent sign-off** under the Soleur-as-tenant-zero posture. The
operator retains an optional veto. **External** counsel re-review remains reserved for the
frontmatter re-evaluation triggers — unchanged, live, and now joined by the claim-decay trigger
in §A3.4. All output in this PR and in this audit remains **draft material requiring professional
legal review**.
