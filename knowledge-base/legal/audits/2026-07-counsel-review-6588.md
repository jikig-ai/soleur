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
status: "SIGNED-OFF WITH ACCEPTED RESIDUAL (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-07-24
signed_off_by: "clo agent (Soleur legal domain leader) — reviewing authority for v1 per the agent-native company model; review performed 2026-07-24T22:43Z (00:43 CEST on 2026-07-25 local), same session as the PR; dated 2026-07-24 to match the PR, the corrections banner, and the sibling spec artifacts. External counsel re-review reserved for the re-evaluation triggers below."
tier_classification: "Tier 1 (material) per `knowledge-base/legal/tc-version-bump-policy.md` — retraction of published Article 32 TOM claims plus re-scoping of a surviving one. NO `TC_VERSION` bump: that constant governs `docs/legal/terms-and-conditions.md` exclusively (`apps/web-platform/lib/legal/tc-version.ts:14,17,26-27`); the three documents amended here are notice/disclosure documents with no re-acceptance gate."
brand_survival_threshold: single-user incident
accepted_residual: "The re-scoped LUKS clause ships while a full un-wiped plaintext copy of every workspace remains on the superseded pre-cutover volume `hcloud_volume.workspaces` (`format = \"ext4\"`, `apps/web-platform/infra/server.tf`), retained attached-unmounted as the ADR-119 rollback backstop. Users are not told. CLO block B1 recommended an accompanying retained-plaintext disclosure sentence; the operator reaffirmed the UC-3 hold on 2026-07-24 and B1 was OVERRIDDEN. Tracking issue: #6808 (escalated by this PR to priority/p1-high + type/security). Ledgered internally as `plaintext-exception` (`tracking_issue: \"#6897\"`, `expires_on: 2026-10-22` — an INTERNAL commitment, never published) and named in the Article 30 register PA-1(g) and PA-2(g)."
re_evaluation_triggers: "(1) **#6808 clears** — `WORKSPACES_LUKS_HEARTBEAT_URL` wired, the ADR-119 soak clock starts, and the Phase-5 plaintext wipe of `hcloud_volume.workspaces` completes: at that point the accepted residual is cured by reality and this audit's disposition upgrades from SIGNED-OFF-WITH-RESIDUAL to unqualified. (2) **First arms-length data subject** — if #3723 (or any other path) onboards a non-Soleur user while #6808 is open, the bounding fact that carries this residual (zero arms-length data subjects) is gone: the residual becomes p0, the hold MUST be re-raised, and the published wording must be qualified before onboarding, not after. (3) **Any regression of the LUKS mount** — `workspaces-luks-verify` reporting anything other than `device_type=crypto_LUKS` on `/dev/mapper/workspaces`, or an escrow/header failure, falsifies the one Article 32 claim this PR retains and makes the retained clause itself an over-claim (the #6812 silent-revert failure mode is documented on this exact surface). (4) **Any future edit that would add the held disclosure sentence** — the Path-2 wording preserved in the plan §3b must be reviewed against the then-current infrastructure before publication, and must anchor on **Art. 12(1) + 5(1)(a)**, not Art. 13(3). (5) Standard inherited triggers: an EEA-out transfer, a regulated-industry data subject, or any change of Hetzner locative away from `hel1` only."
---

# Counsel review audit — #6588 (Article 32 TOM retraction + LUKS re-scope)

> **STATUS: DISCHARGED WITH ONE ACCEPTED, OPERATOR-OVERRIDDEN RESIDUAL — reviewed and
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
