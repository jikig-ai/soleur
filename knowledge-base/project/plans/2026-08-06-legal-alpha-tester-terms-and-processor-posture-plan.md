---
title: "Alpha-tester terms + controller/processor posture for tester-owned repository data"
type: plan
issue: "#7331"
branch: feat-one-shot-7331-alpha-tester-terms-dpa
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: plan
date: 2026-08-06
predecessor_issue: "#7329"
predecessor_pr: 7328
milestone: "Phase 4: Validate + Scale"
related:
  - knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md
  - knowledge-base/legal/data-processing-agreement-template.md
  - knowledge-base/legal/tenant-dpa-register.md
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/legal/compliance-posture.md
  - knowledge-base/legal/statutory-response-catalog.md
  - knowledge-base/legal/recommended-tools.md
  - knowledge-base/legal/tc-version-bump-policy.md
  - knowledge-base/legal/data-processing-agreements/anthropic.md
  - knowledge-base/legal/legitimate-interest-assessments/2026-07-07-beta-crm-lia.md
  - knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md
  - knowledge-base/product/validation/2026-08-06-alpha-onboarding-motion-start.md
  - knowledge-base/project/specs/feat-alpha-onboarding-motion/spec.md
---

# Plan — Alpha-tester terms + controller/processor posture for tester-owned repository data

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
Phase 2.8 reviewed. This plan provisions no infrastructure: every task writes markdown under
knowledge-base/, edits an operations runbook, or files a GitHub issue. There is no server, service,
cron, vendor account, DNS record, TLS cert, secret, or firewall rule in scope, so there is no
Terraform representation to route through. The human-performed steps it records — another legal
person deciding whether to countersign, and a law firm reviewing a contract — are counterparty and
professional-services acts, not provisioning; they are unautomatable by their nature rather than by
omission, and are justified inline at AC12/AC13.
-->

## Enhancement Summary

**Deepened on:** 2026-08-06. **Review depth:** `soleur:legal:clo` (determination),
`soleur:legal:legal-compliance-auditor` (12 Critical / 15 High / 8 Med-Low), `soleur:operations:coo`,
`soleur:product:cpo`, `soleur:marketing:cmo`, a strong-model advisor consult (ADR-083), and the
escalated 5-agent plan-review panel.

**Key changes the review produced — the plan shrank by roughly half:**

1. **The `if processor` branch was cut entirely.** The determination proves its antecedent false, so
   the DPA, execution register, Art. 30(2) register, signature probe and deferred issue all went with
   it — five artifacts downstream of a branch that does not fire.
2. **Two correctness bugs were caught in the cut material.** The follow-through probe's PASS
   condition was **vacuous at merge** (no rows → exit 0 → tracker closes with nothing signed), and its
   `exit 2` mitigation **does not exist** — the sweeper comments on TRANSIENT too, so a pending
   signature would have posted ~60 public comments about a named counterparty's contract status.
3. **The two named C4 tests never read the committed artifact**; the real gate byte-diffs a tracked
   render the plan never regenerated. The C4 edit was cut as a duplicate edge anyway.
4. **Tier 1 was made unconditional.** Scoping it to "testers who don't need Tier 2" left tester #1 —
   the only one who exists — with nothing agreed, silently failing the issue's first criterion.
5. **Fabricated clause citations fixed.** "§298" and "§112" were line numbers; the T&Cs have sections
   1–17. A drafted instrument citing them would have cited clauses that do not exist.
6. **Phase 0.1 is now BLOCKING** on establishing whose Anthropic key ran the 2026-08-06 session —
   the premise the whole determination rests on, and one no repo evidence currently settles.

**Gates run:** 4.5 network-outage (no trigger), 4.6 user-brand impact (PASS), 4.7 observability
(pure-docs skip), 4.8 PAT-shaped variable (clean), 4.9 UI wireframe (no UI surface),
4.10 encryption posture (no store), 4.55 downtime (no serving-surface change).

**Citation sweep:** 6 AGENTS rule IDs all active; all `knowledge-base/` paths resolve; 7 ADRs exist;
11 issue/PR numbers resolve — one correction: **#736 is CLOSED**, not open as `compliance-posture.md`
claims.

---

**Standing constraint on every task below:** no third-party personal data in any committed file.
The tester is `Skouer` / `https://github.com/2my8r9ry2t-wq/Skouer` — company name and repository URL
only, never a person's name or email. Git history is permanent, so committed third-party PII is an
Art. 17 erasure impossibility (`alpha-tester-onboarding.md`, §"the PII boundary").

## Overview

Issue #7331 asks for **(a)** alpha-tester terms and **(b)** a determination of whether Jikigai is a
GDPR Art. 28 processor of personal data in a tester's own repository — with a DPA, registers, an
Article 30 record and a runbook gate following **if** the answer is yes.

**The answer is no, and it is already published.** `docs/legal/data-protection-disclosure.md:61` —
identical in both mirrors — states: *"Therefore, Soleur is neither a Controller nor a Processor with
respect to the data processed locally through the Plugin."* The tester runs the self-hosted CLI on
their own machine under their own Anthropic key; Art. 4(8) requires processing *on behalf of* the
controller and Jikigai performs none. A scan of `plugins/soleur/` found no phone-home path, so the
published claim is true as of this worktree. Where the personal data physically lives (Clever Cloud
vs. git) is a **red herring** — it changes the tester's risk profile, not Jikigai's role.

**So the `if processor` branch does not fire, and this plan does not build it.** What it builds is
much smaller, because research surfaced a different and genuinely live exposure the issue does not
mention:

> The operator **already holds GitHub collaborator access to the private Skouer repository** and
> reads its `knowledge-base/` git tree to measure knowledge-base growth for #1442
> (`2026-08-06-alpha-onboarding-motion-start.md:83`; runbook §"Measurability caveat"). That is
> Jikigai reading a private third party's repository **for Jikigai's own research purpose**. Under
> Art. 4(7) that makes Jikigai a **controller** — Art. 28(10) confirms a processor who determines
> purposes becomes one. It is happening today, it has **no lawful basis recorded**, and **a DPA is
> the wrong instrument for it.** PA-32 (community observation) does not cover it: PA-32 is scoped to
> *public* activity and this repository is private.

Three postures, one mechanical test a non-lawyer can apply — **whose machine, whose API key, whose
purpose?**

| Posture | Condition | Role | Instrument |
|---|---|---|---|
| **A** | All three the tester's | **Neither** | None. Record the negative determination. |
| **B** | Tester content reaches a Jikigai machine, credential or account | **Processor** | Art. 28(3) instrument **before** the run |
| **C** | Jikigai reads tester content for **Soleur's own** purpose | **Controller** | LIA + Art. 6 basis + Art. 14 notice |

Posture A is the default for repo data. **Posture C is live and unpapered — it is the only actual
violation in scope, and closing it is this plan's P0.**

**The four Posture B triggers**, enumerated here so the runbook and the determination quote one list
rather than each inventing its own:

1. **The tester connects their repository to the hosted platform.** No judgment required — it is
   automatic, and the validation record states this migration is the plan. See the PA-17 caveat below.
2. **The operator runs Soleur agents against tester code or data on the operator's own machine under
   a Jikigai Anthropic key**, at the tester's request (guided onboarding, a debugging session).
3. **The tester sends Jikigai a repository copy, database dump, fixture, `.env`, or DB credential** by
   any channel.
4. **Jikigai holds any credential to a tester system** (Clever Cloud, their Postgres, a deploy token).

**Trigger 1 carries a recorded obligation this plan must route, not merely name.** PA-17's lawful-basis
cell already states that *where the repository contains personal data of natural persons who are
neither the Owner nor a Co-Member, the balancing is re-opened by the "first third-party-personal-data
repository" re-evaluation trigger recorded in the #4558 counsel-review audit — **before any such repo
is brought into scope**.* A tester's venture database is exactly that repository, so trigger 1 fires
that re-evaluation directly. Note also that PA-17 §(b)(ii) lands the pull at `userData.workspace_path`
(the operator's workspace clone), **not** Hetzner — Hetzner appears in §(e) as the self-hosted Inngest
dispatcher host — and PA-17 expressly records that *"no third-party data subjects are introduced"*.
So trigger 1 does not merely require an instrument: **PA-17 itself would need amending**, and a signed
DPA does not repair an Art. 30(1) record that fails to describe the flow.

**There is a cheaper way to close Posture C than papering it**, and the plan carries it as an open
decision for the operator rather than silently choosing: **decline or revoke the collaborator
access.** It buys exactly one metric of three (KB growth) on a surface where the other two are
unmeasurable anyway, and a tester-supplied `git log --stat` substitutes for it. Declining dissolves
Posture C entirely — no LIA, no Art. 14 notice, no instrument, no counsel spend. See
[Open decision](#open-decision-behavioural-vs-documentary-control).

Nothing is published to `docs/legal/`: doing so fires a six-step chain including *"initiate SOC 2
engagement within 90 days"* (`compliance-posture.md`, #4330). Committing a one-person company to SOC 2
to onboard a free alpha tester is the highest-cost error available here.

## Research Reconciliation — issue premises vs. repo reality

| Issue premise | Reality on disk | Plan response |
|---|---|---|
| "Nothing binds either direction today." | **False.** `terms-and-conditions.md:20,22`: *"By **installing**, accessing, or using Soleur (**whether the Plugin** or the Web Platform), you agree to be bound."* **§10.2 ("No Guarantee of Availability or Accuracy")** already disclaims SLA, uptime and warranty; the AUP binds "whether locally via the Plugin"; `LICENSE` (BUSL-1.1) binds as a copyright licence. **Cite clause numbers, never line numbers** — the T&Cs have sections 1–17, so a drafted instrument citing "§298" or "§112" would cite clauses that do not exist (`cq-cite-content-anchor-not-line-number`); the supersession duty is **§3b.4**. | The defect is **notice and assent evidence**, not absent terms: `plugins/soleur/README.md:373-375` surfaces only the BSL licence and never links the Terms, so a CLI installer is bound by terms never shown — weak against a French B2B counterparty. Tier 1 carries a Terms link and asks for a one-line reply. |
| "Controller/processor posture … undetermined." | **Published and negative.** DPD §2.1 `:47-61` (titled *"The Soleur Plugin Is Not a Data Processor"*), limbs (a)–(d), plus §2.2 `:76-86` assigning the **user** controller duties. `gdpr-policy.md:31`, `privacy-policy.md:37-40`, `article-30-register.md:32,680` concur. | The determination **confirms** the published position and applies it to the alpha question for the first time. Reversing it would contradict five published sentences across two documents and two mirrors. |
| "Jikigai plausibly becomes a processor if agents operate on the repo." | The crux the issue poses — *does an agent touch PII?* — is **the wrong test** and a non-lawyer cannot apply it. Migrations, live-data debugging and dump/fixture files all happen on the tester's machine under the tester's key and cross no boundary. | Replaced by the machine/key/purpose test and four concrete Posture B triggers. |
| *(absent from the issue)* | **Posture C is live**: collaborator access to a private repo, read for Jikigai's own metrics, no lawful basis recorded. | The P0 deliverable — or dissolved outright by declining the access. |
| "DPA … registered in `tenant-dpa-register.md`." | **A recorded decision forbids it and names the successor.** `compliance-posture.md` (#4330 item iv): write the row *"**on counter-signature** (NOT `tenant-dpa-register.md`… either create `customer-dpa-register.md` with a parallel schema, or amend the existing register to be dual-purpose)."* That register also has no Founder UUID for a CLI tester, no "drafted" status, and a §6.1 **30-day clock** that fires on the first `dpa-signed` row. | Write **no row** anywhere now. Record the tester's terms status as one new column on the **existing recruitment tally** in the runbook. `customer-dpa-register.md` is created **on counter-signature**, per #4330 — not pre-emptively. |
| "Article 30 register updated if a new processing activity is confirmed." | Titled **"Article 30(1) Register"**, scoped *"in its capacity as **data controller**"*, 33 activities, **zero Art. 30(2) records**. Art. 30(2) limbs are different and fewer — no purposes, no data-subject categories, no retention. | **PA-34** in the existing `(a)`–`(g)` shape for the **Posture C controller** activity. No Art. 30(2) register is created: a 30(2) record documents processing *carried out*, and none is. The determination's *"If a crossing trigger fires"* section names the 30(2)(a)–(d) limbs instead. |
| "Anthropic as sub-processor." | **No chain on the CLI surface**: Anthropic is the *tester's* processor under the tester's key. DPD `:169`, `gdpr-policy.md:37`, DPA template §6.3 / Schedule 2 BYOK row `:337-343`. | Do not list Anthropic in a Schedule 2 here. Using the template unamended would tell the tester *"Anthropic is YOUR sub-processor"* — true in A, **false in B**, and a misstatement in a compliance instrument. |

**Further findings:**

- **`anthropic.md`'s own re-evaluation trigger has fired and is unactioned.** `:179` — *"Soleur takes
  on data subjects beyond the operator (**cohort onboarding**)."* Cohort onboarding began 2026-08-06.
  Frontmatter `zero_retention_amendment: unsigned` means a **30-day Anthropic retention window**
  applies to everything egressing under a Jikigai key. And `anthropic.md` is a **snapshot memo** of
  auto-incorporated Commercial Terms §C, not an executed bilateral instrument — no flow-down
  warranty, no audit right, no breach-notification timeline — so it does not discharge Art. 28(4).
- **Do not amend the T&Cs.** `tc-version-bump-policy.md:22-27`: a `TC_VERSION` bump *"forces every
  existing user to re-accept the Terms on their next page load"* and closes live WebSocket sessions.
- **Do not reuse `side-letter-template.md`.** `:119` — *"Jikigai is **not a party**"*; `:81` assigns
  IP **to the Owner**, the wrong direction.
- **The determination has a precedent format** —
  `knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md`
  (Verdict / Reasoning / Conditions / disposition). Use `audits/`; do not invent a directory.
- **The DPA template's clause-level defects**, if Tier 2 is ever drafted from it: §1.2 `:43` scopes
  Customer Data to the Web Platform; §5.1 defines instructions as Web-Platform-UI actions;
  **§5.3 + Schedule 4's 17 TOMs describe RLS/Supabase/WORM/R2 and none describes this relationship**
  — the exact defect the repo publicly retracted in #6588 (DPD `:12`); §7.1/§7.3 route DSARs to
  `/dashboard/settings/privacy`, which a CLI tester has no account for (**keep §7.2 verbatim** — its
  2-business-day ack / 10-business-day SLA is good); **§12.1's cap evaluates to EUR 100** for an
  unpaid tester; §10 audit is the best section and is adoptable near-verbatim.

**Pre-existing defects — filed, not absorbed** (`wg-when-an-audit-identifies-pre-existing`, one
consistent policy): `tenant-provisioning.md:47`'s gate passes against an empty register;
`tenant-dpa-register.md:84`'s guard greps `status: dpa-signed` against rows carrying a bare
`dpa-signed`, so it can never fire; `tenant-offboarding.md:217` cites `engineering/ops/`;
`tenant-offboarding.md` records no exit path for a non-tenant alpha tester; DPA template §10.3 says
SOC 2 is *"not a binding commitment"* at `:198` while `:406` says "within 90 days"; the **AUP mirrors
carry materially different user-facing legal text**; the DPD Eleventy mirror lacks §2.3(ad) while
`plugins/soleur/docs/pages/legal/gdpr-policy.md:201` carries a dangling cross-reference to it; PA-30
declares Jikigai a processor but sits in the 30(1) controller shape; `compliance-posture.md:62`'s T&C
row is stale against `TC_VERSION = "2.4.0"`; `roadmap.md:327` marks row 4.1 "Not started" while `:81`
says onboarding is underway.

**And one more, found by the deepen-plan citation sweep:** `compliance-posture.md` records
*"| T&C blanket statement contradictions | #736 | OPEN |"* — but **#736 is CLOSED**, and its actual
title is *"legal: update Terms & Conditions for web platform cloud services."* The row is stale on
both status and subject, so it cannot be relied on as prior art for the T&C contradictions this plan
found. Treat those as **untracked** and file them fresh; add the stale row itself to the batch.

## User-Brand Impact

**If this lands broken, the user experiences:** a tester handed an instrument presuming Jikigai might
process their repository data, who then reads `privacy-policy.md:40` — *"We do not have access to your
files, your code, or your usage patterns"* — and `data-protection-disclosure.md:61`. Their supplier has
told them two contradictory things about whether it can see their code, in writing, in the same week.

**If this leaks, the user's data is exposed via:** the operator's **live collaborator access** to the
tester's private repository, exercised for Jikigai's own metrics with no lawful basis and no
confidentiality undertaking running to the tester. Anything from that repo surfacing in a Soleur
commit, issue, digest or case study is a confidentiality and trade-secret problem — with a
counterparty who shares a coworking space with the founder.

**Brand-survival threshold:** `single-user incident` — CPO concurs. This is the brand's **first
external user** and the exposure is live rather than hypothetical. Sets `requires_cpo_signoff: true`;
routes `user-impact-reviewer` at review.

## Open decision — behavioural vs. documentary control

Surfaced by plan review as a **User-Challenge** (ADR-084): it argues the issue's stated direction
should change, so it is recorded for the operator rather than decided here. Persisted to
`knowledge-base/project/specs/feat-one-shot-7331-alpha-tester-terms-dpa/decision-challenges.md`.

> **The cheapest control here is behavioural, not documentary.** Collaborator access on the tester's
> private repo is what creates Posture C. The runbook's own measurability table shows it buys **one
> metric of three** — knowledge-base growth via git history — on a surface where returns and
> non-engineering agent usage are unmeasurable regardless. Ask the tester to paste a `git log --stat`
> and the metric survives without the access.
>
> **Option 1 (recommended): revoke.** Posture C dissolves. No LIA, no Art. 14 notice, no PA-34, no
> counsel spend. The published determination holds unchanged and no crossing trigger exists.
> **Option 2: retain and paper.** Keep the access for measurement fidelity and ship the LIA + PA-34 +
> Art. 14 line (Phase 2 below).
>
> The plan is written so Phase 2 is skipped under Option 1 and executed under Option 2. Everything
> else is unaffected.

## Domain Review

**Domains relevant:** Legal, Operations, Product

**Agents invoked:** `soleur:legal:clo`, `soleur:legal:legal-compliance-auditor`,
`soleur:operations:coo`, `soleur:product:cpo`, `soleur:marketing:cmo`, a scoped strong-model advisor
consult (ADR-083), and the escalated 5-agent plan-review panel. **Skipped specialists:** none.

### Legal

The determination was **not** improvised inline. `soleur:legal:clo` adjudicated it;
`soleur:legal:legal-compliance-auditor` returned 12 Critical / 15 High / 8 Medium-Low cross-document
findings. Load-bearing outputs are in the Overview and Reconciliation above. Escalation, blunt: the
determination memo needs **no** lawyer — it restates published positions verified against code, and is
the `audits/` CLO-attestation lane. If Tier 2 is ever drafted, its **liability cap and confidentiality
undertaking** are the highest-value hour of counsel time in this work.

### Operations

- **Fold the agreement into the existing Step 2**, do not renumber. Step 2 already *is* the welcome
  message template, and the runbook's Known-gap text says the step *"belongs between Steps 1 and 2"* —
  the top of Step 2 satisfies that literally, with zero renumbering and zero rotted internal
  references.
- **Record terms status on the existing recruitment tally** (`| Tester | Company | Claude Code user? |
  Surface | Onboarded |`), which the operator already updates at Step 1 of every onboarding. One new
  column beats a fourth register: the repo maintains two registers with **zero rows between them**
  after three months, and both grew guards that assert on them vacuously or can never fire.
- **No follow-through probe.** The runbook already ruled on exactly this shape: *"The work here is a
  conversation, which has no exit-code probe. Put the due date in the title instead."* — and
  `.claude/hooks/follow-through-directive-gate.sh` **denies** the `gh issue create` outright without a
  directive. A dated issue is the mechanism.
- **Procure nothing.** Art. 28(9) is satisfied by a countersigned PDF by email; R2 `cla-evidence`
  (WORM, 10-year, **$0.00**) already exists. **`wg-record-recurring-vendor-expense-before-ready` does
  not fire** — counsel review is one-time (EUR 300–800, `recommended-tools.md:33`) and belongs in the
  One-Time section. It is **one review of the instrument, not one per tester.**

### Product/UX Gate

**Tier:** none. The mechanical UI-surface override does not fire — no path in `## Files to Create` or
`## Files to Edit` matches the UI-surface term list or glob superset. No `.pen` wireframe required;
`wg-ui-feature-requires-pen-wireframe` does not apply. **Decision:** reviewed.
**Pencil available:** N/A (no UI surface).

#### Findings

- **Do not front-load a signature.** The binding constraint is ≥3 of 10 non-Claude-Code founders,
  currently **0 of 3**, unrecoverable after tester #8 — the cohort least tolerant of paperwork. It
  also contradicts the runbook's own design: *"It is a message, not a ceremony."*
- **Tier 1 is unconditional — every tester, including tester #1.** Plan review caught that scoping
  Tier 1 to "testers who don't need Tier 2" leaves tester #1 with nothing agreed, failing issue AC1.
  Tier 2, if ever drafted, is an **addition**, not a substitution.
- **CMO constraints on the Tier 1 copy** (route it through `soleur:marketing:copywriter`, not the
  legal generator): **≤ 90 words**; merged into the existing "One note on record-keeping" paragraph
  rather than added as a second block; **first-person singular** throughout, matching the Art. 14
  paragraph already there; **lead with what Soleur owes** — *it runs on your machine, on your key, I
  can't see your repo* — which is already published and converts the notice from paperwork into
  reassurance; **never the word "Plugin"** in tester-facing copy; no defined terms, no section
  numbers, no "shall".
- **The DRAFT banner must not cross to a counterparty.** The marking is a corpus-internal control.
  Any artifact crossing to a third party carries a review attestation instead, or does not cross. The
  Tier 1 file must fence its paste-block away from the markings, and the runbook must show the final
  welcome text with Tier 1 already inlined so the operator never copies from the legal file.

## Architecture Decision (ADR/C4)

All three model files were **read**, not keyword-grepped — grepping the feature's own noun returns
zero and proves nothing, since the elements at issue are named for roles.

### ADR

**No new ADR** — but the "nothing is extended" half of that claim is **false**, and the determination
must carry its architectural anchors. No code, schema, or substrate changes, and the corpus's vessel
for a legal-posture record is a dated file under `knowledge-base/legal/audits/`. No ADR is
*contradicted*, **provided every non-receipt sentence is scoped to the CLI surface in the sentence
itself.** The determination MUST cite:

- **ADR-093** — the plugin/platform trust-boundary ADR of record. Same seam, opposite arrow: it
  protects Soleur *from* the connected repo; this determination protects the repo *from* Soleur.
  Its `:28` (*"the `knowledge-base/` root stays workspace-relative — it is repo content"*) is an
  explicit accepted flow of connected-repo content into agent context **on the hosted surface**, and
  any unscoped non-receipt sentence collides with it.
- **ADR-099** — the only architectural statement that makes the CLI/hosted split real. This is the
  anchor the determination actually needs.
- **ADR-119** and **ADR-075** — see the substrate-readiness risk below.
- **ADR-102** — already classifies the tester as an involuntary Art. 14 subject under PA-30; the
  determination must not silently re-classify them.

**Substrate readiness is part of the Posture B gate, not just paperwork.** If a bilateral instrument
is ever drafted, crossing trigger 1 lands the tester on a substrate where `ADR-119` records
`hcloud_volume.workspaces` holding *"every user's checked-out repository as plain ext4"* (status
`adopting`, not `accepted`), and `ADR-075` records a single multi-tenant container where *"bwrap is
the only filesystem isolation between tenants"*, with an accepted TOCTOU residual that is
*"undetectable (no telemetry fires if it is ever exploited)"*. An instrument springing into effect at
that moment would carry Art. 28(3)(c) / Art. 32 security representations against exactly that. The
crossing gate must therefore have a **substrate precondition**, not only a countersignature — and the
determination must say so rather than implying paperwork is sufficient.

### C4 views

**Enumeration (the mandate's four categories):**

- **External human actors.** `model.c4:22-25` — `betaContact = actor "Beta Tester / Prospect"`,
  *"An involuntary data subject (Art. 14)"*. That is the tester. The founders and investors inside the
  tester's database are a different set of natural persons with the **tester** as controller; under
  Posture A they are **not reached by Soleur**, so their absence is correct — and the determination
  states it, making the absence documented rather than accidental.
- **External systems.** None new. The repository is reached over the modelled `github` edge
  (`model.c4:230`). The tester's product database **must not** be modelled — an edge would assert a
  flow that does not exist and contradict `data-protection-disclosure.md:61`.
- **Containers / data stores.** None. `connectedRepoPlugin` (`model.c4:320`) already models the
  untrusted connected-repo surface.
- **Access relationships.** **None to add.** `betaContact -> founder` (`model.c4:386`) already runs
  between the same two elements for third-party-PII origination; a second parallel arrow distinguished
  only by label adds nothing a reader of PA-34 does not already have. **No C4 edit, and no c4 test run
  in this PR.**

This is a "no C4 impact" conclusion, and per the completeness mandate it cites the enumeration above
rather than asserting it bare.

## Observability

**Skipped — pure-docs plan.** No code-class file under `apps/*/server/`, `apps/*/src/`,
`apps/*/infra/`, or `plugins/*/scripts/`; no new infrastructure surface.

**Phase 2.9.1 soak enrollment does not fire.** The counterparty countersignature is gated on another
person's volition with no wall-clock component, which is not the soak shape — and the runbook plus the
`follow-through-directive-gate.sh` hook both rule it out explicitly. Tracked by a dated issue whose
**title** carries the due date.

## Encryption Posture

**Skipped.** No persistent store, no new cross-component connection, no match against the Phase 2.11
globs.

## GDPR / Compliance Gate (Phase 2.7)

Fires — the subject is regulated-data posture and trigger (b) applies (`single-user incident`).
`/soleur:gdpr-gate` runs against this plan and the drafted artifacts at /work Phase 2 exit.

## Escalation guidance (solo founder)

`recommended-tools.md` has no single threshold sentence; the implicit bar is *a statutory deadline
exists, or the founder has no retained counsel*.

**Ships as a marked draft, no counsel needed:** the determination memo; PA-34 and its LIA; the Art. 14
line; the Tier 1 notice; the runbook step; the statutory-catalog bullet; the tally column.

**Escalate only if Tier 2 is actually drafted and sent** — `#vendor-msa-review`, EUR 300–800 one-time
(`recommended-tools.md:36`: *"you do NOT need an ongoing retainer"*), covering the **liability cap and
the confidentiality undertaking**, and French-law assent mechanics for an unpaid B2B alpha.

**Do NOT escalate the determination itself.** The answer is settled and consistent with four published
documents and verified code.

**Budget reality check.** Counsel receives the standard accountability pack
(`statutory-response-catalog.md:213-216`), which currently holds an ~5-months-overdue DPIA (#7121), an
expired Art. 14 clock (#7120), and **a live processing limb with no available lawful basis** (#7119,
marked BLOCKING). If there is one legal budget, #7119 outranks a conditional instrument for an
unpaid tester who has not asked for one.

## Open Code-Review Overlap

**None.** All 64 open `code-review`-labelled issues fetched; each planned path searched against their
bodies via standalone `jq --arg`; zero matches.

## Implementation Phases

Tasks anchor on **headings and quoted content, never bare line numbers**
(`cq-cite-content-anchor-not-line-number`).

### Phase 0 — Preconditions

0.1 Re-derive the next free Art. 30 ordinal against `origin/main`
(`grep -n "^## Processing Activity" knowledge-base/legal/article-30-register.md | tail -3`).
0.2 Re-run the `plugins/soleur/` egress scan; record commands and output for the determination, so it
cites verified fact rather than the privacy policy proving itself.
0.3 Read open issue **#736** to avoid duplicating it.
0.4 Confirm `docs/legal/data-processing-agreement.md` still does not exist.
0.5 Surface the [Open decision](#open-decision-behavioural-vs-documentary-control) — Phase 2 is
skipped under Option 1.

### Phase 1 — The determination (blocks everything)

1.1 Have `soleur:legal:clo` author
`knowledge-base/legal/audits/<YYYY-MM-DD>-alpha-tester-controller-processor-determination.md` in the
`2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md` format: the three postures, the
machine/key/purpose test, the four Posture B triggers, the Posture C finding, the Phase 0.2 evidence,
why the beta-CRM LIA does not cover this, and the role-collision note (Jikigai already processes
Skouer's own data via PA-30).
1.2 Include an **"If a crossing trigger fires"** section naming the Art. 30(2)(a)–(d) limbs, stating
that the record must be written before processing begins, and that any bilateral instrument must be
counsel-reviewed before it is sent. This replaces an empty Art. 30(2) register.
1.3 Canonical marking **verbatim, blockquote, opening and closing**; frontmatter
`status: draft-requires-counsel-review`.
1.4 **Written whichever way the verdict falls** — the negative determination is what stops this being
re-litigated at tester #3.

### Phase 2 — Close Posture C *(skipped under Option 1)*

2.1 LIA at `knowledge-base/legal/legitimate-interest-assessments/<date>-alpha-tester-repo-observation-lia.md`,
modelled on `2026-07-07-beta-crm-lia.md`: Art. 6(1)(f) three-part balancing for operator
collaborator-access observation of a private tester repository.
2.2 **PA-34** in `article-30-register.md`, existing `| Art. 30(1) limb | Entry |` shape, Jikigai as
**controller**. Append by content anchor, not file order.
2.3 Art. 14 notice line for involuntary third-party data subjects, **claiming Art. 14(5)(b)
disproportionate effort in writing**, delivered as one more sentence in the welcome message.

### Phase 3 — Tier 1 alpha notice (all testers, including #1)

3.1 Draft the substance via `legal-document-generator` (invoked **directly via Task** — not
`/soleur:legal-generate`, whose Phase 0/1 use `AskUserQuestion` and would hang the headless pipeline),
then render the paste-block via `soleur:marketing:copywriter` against the CMO constraints above.
3.2 Content: a Terms link; confidentiality owed *by Jikigai* over the private repo; end-of-alpha data
disposition; no fee, no obligation, stop anytime; the collaborator-access purpose and scope stated
plainly (Option 2 only); and **redact third-party personal data before sending logs**, with Jikigai's
undertaking to delete unredacted material on notice.
3.3 Ask for a **one-line reply** as assent evidence — this is what satisfies issue AC1 and closes the
notice/assent gap behind T&C `:22`. Note the tension CMO raised (a reply is a second yes); it is
accepted because Tier 1 arrives *after* the tester has already agreed to take part.
3.4 Fence the paste-block away from the DRAFT markings so the banner cannot be copied into a welcome
email.

### Phase 4 — Runbook

4.1 Retitle Step 2 to cover the terms; inline the Tier 1 paragraph into the existing welcome template
so the operator copies from the runbook, never from the legal file. **No renumbering.**
4.2 Replace the "Known gap" section with the **operating rule**: the machine/key/purpose one-liner,
the four Posture B triggers, and — under Option 1 — *do not accept collaborator access on a tester's
repository*. State that if a future tester makes it unavoidable, that is when the bilateral instrument
and its single counsel review are bought, once, reusable across all ten testers.
4.3 Add a **`Terms`** column to the recruitment tally (`agreed` / `not-required`), updated at Step 1.
4.4 Add the offboarding line: at alpha end, collaborator access revoked, local clones and retained
feedback artifacts deleted, written confirmation within 30 days.
4.5 Record the **tester #1 position** — onboarding began 2026-08-06, so Tier 1 is sent retroactively
and the tally row is filled.

### Phase 5 — Records

5.1 `compliance-posture.md`: add a `#7331` Active Items row.
5.2 Rewrite the `statutory-response-catalog.md` DSAR section's **fifth requester class** — not as an
Art. 28(3)(e) forwarding path (this plan's own determination forecloses that duty) but as the honest
response: *Jikigai holds nothing, is neither controller nor processor for it, will not confirm or deny
whether a third party does, and the Art. 12(3) clock is the controller's.* Add it as a bullet under
the existing step 3; **do not add a new anchor** — `:225-228` couples any `catalogAnchor`/`ruleId`
change to `apps/web-platform/lib/email-triage/statutory-rules.ts` in the same PR.
5.3 Action the fired Anthropic trigger (`anthropic.md`, §"Re-evaluate when"): record the
Zero-Retention status or why it remains unsigned, and the 30-day retention consequence.
5.4 Roadmap: add row **4.12** (`wg-every-feature-listed-in-a-roadmap-phase`).
5.5 Update the validation record's "Known gap" to resolved.
5.6 Add a Terms link to `plugins/soleur/README.md`.

### Phase 6 — Filings

6.1 File the dated issue for counsel review (if Tier 2 proceeds) and tester #1 assent — **due date in
the title**, no `follow-through` label, no probe.
6.2 File the pre-existing defects listed in Research Reconciliation, as a batch, checking #736 first.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — The determination exists under `knowledge-base/legal/audits/`, states the three postures
  with Art. 4(7)/4(8)/28 reasoning, gives the machine/key/purpose test, enumerates the four Posture B
  triggers, cites the Phase 0.2 empirical evidence, and carries the "If a crossing trigger fires"
  section naming the Art. 30(2)(a)–(d) limbs. Present **whichever way the verdict falls**.
- **AC2** — No personal data in any committed artifact. The tally carries company name only; a grep
  for an `@`-bearing address across the changed `knowledge-base/` files returns nothing but
  `legal@jikigai.com`. *(The only irreversible risk in this PR.)*
- **AC3** — `git diff origin/main --name-only` adds **no file under `docs/legal/`**, and
  `git diff origin/main -- knowledge-base/legal/tenant-dpa-register.md` is **empty**. One assertion
  guards both the #4330 SOC 2 chain and the §6.1 30-day clock.
- **AC4** — `git diff origin/main -- apps/web-platform/lib/legal/tc-version.ts` is **empty** — the
  T&Cs were not amended, so no global re-acceptance is forced.
- **AC5** — *(Option 2 only)* `article-30-register.md` carries a **PA-34** entry in the
  `| Art. 30(1) limb | Entry |` shape recording Jikigai as **controller** of tester-repo observation,
  with a matching LIA on disk and an Art. 14 line in the welcome template. Under Option 1, the
  determination instead records that the access was declined and Posture C does not arise.
- **AC6** — The runbook's Step 2 carries the Tier 1 terms inline; the recruitment tally has a `Terms`
  column with tester #1's row filled; `grep -c 'Known gap'` and `grep -c 'in earnest'` both return
  zero; the operating rule and the offboarding line are present. **Step headings still number 1–6** —
  no renumber.
- **AC7** — The Tier 1 paste-block is ≤ 90 words, first-person, contains no occurrence of "Plugin",
  and is physically fenced from the DRAFT marking.
- **AC8** — `git diff origin/main -- apps/web-platform/lib/email-triage/statutory-rules.ts` is
  **empty** (no catalog anchor added, so no coupling fires), and the new requester class does **not**
  describe an Art. 28(3)(e) duty.
- **AC9** — `compliance-posture.md` has a `#7331` row; `roadmap.md` has row **4.12**; the dated issue
  from Phase 6.1 exists with its due date **in the title** and **without** the `follow-through` label.
- **AC10** — Every `knowledge-base/` path cited in the **shipped artifacts** (not this plan) resolves:
  extract with `grep -ohE 'knowledge-base/[A-Za-z0-9/_.-]+\.md'`, test each with `[[ -f ]]`.
- **AC11** — `/soleur:gdpr-gate` has run; Critical findings are resolved or carry an
  operator-acknowledged `compliance/critical` issue. PR body uses `Closes #7331`.

### Post-merge (operator / counterparty)

- **AC12** — Tester #1 replies confirming the Tier 1 terms.
  `Automation: not feasible because` the missing input is **another person's assent**, which no tooling
  can supply. This is not one of the canonical operator-only categories (a)–(d) in
  `2026-05-15-operator-only-step-canonical-list.md`, but it satisfies that learning's controlling
  principle — *"the boundary is possession … not availability of tooling."* Everything either side of
  it is automated: the notice is drafted and inlined into the runbook template, and the tally column is
  ready for the status. Tracked by the Phase 6.1 dated issue.
- **AC13** — *(only if Tier 2 is ever drafted and sent)* one-time counsel review of the liability cap
  and confidentiality undertaking before it reaches any tester.
  `Automation: not feasible because` this is the purchase of a professional legal opinion — a
  commercial engagement, not a browser workflow, so no `playwright-attempt` line applies.

## Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Posture C ships unaddressed** — the operator keeps reading a private third-party repo for Jikigai's own metrics with no lawful basis. The only actual violation in scope. | Phase 0.5 forces the Option 1 / Option 2 decision; AC5 covers both arms. A DPA would not have cured it (Art. 28(10)). |
| R2 | A row in `tenant-dpa-register.md` starts the §6.1 30-day clock and invalidates its empty baseline; a file under `docs/legal/` fires the #4330 chain including **SOC 2 within 90 days**. | Neither happens. AC3 asserts both by diff. |
| R3 | A processor determination would contradict five published sentences across two documents and both mirrors — the User-Brand Impact failure mode. | The determination confirms rather than reopens. If it reversed, `privacy-policy.md` §4.1 and `article-30-register.md:32,680` must be amended in the same PR. AC1 forces the verdict to be explicit. |
| R4 | Amending the T&Cs forces **every existing user** to re-accept and closes live WebSocket sessions. | Tier 1 incorporates by reference. AC4 asserts `tc-version.ts` is untouched. |
| R5 | The DRAFT banner reaches a tester inside the welcome email. | Paste-block fenced from the marking; the runbook shows the final text so the operator never copies from the legal file. AC7 checks it. |
| R6 | **Tier 1 scoped to exclude tester #1**, leaving issue AC1 unmet — Skouer qualifies for Tier 2, so a Tier-1-only-for-others design covers nobody who exists. | Tier 1 is unconditional; Tier 2 is an addition, never a substitution. AC6 requires tester #1's tally row filled. |
| R7 | If Tier 2 is ever drafted, copying Schedule 4's TOMs would publish Art. 32 measures describing infrastructure that does not serve this relationship — the defect the repo publicly retracted in #6588, this time inside an executed instrument. | The template's clause-level defects are enumerated in Reconciliation so the drafter starts from them. Counsel review is AC13. |
| R8 | The PA-34 ordinal collides with a sibling PR. | Re-derived at Phase 0.1 and anchored on the heading form, not a bare token. |
| R9 | A tester-facing document ships without counsel review because Tier 2 felt cheap to draft. | Tier 2 is **not** a deliverable of this PR. If drafted later, AC13 gates it. |
| R10 | **PA-34 repeats the #7100 defect.** `article-30-register.md:32` enumerates the register's in-scope surfaces (Web Platform, docs site, `jikig-ai/soleur`, `jikig-ai/operator-digest`) and carries its own post-mortem: the list *"previously named `jikig-ai/soleur` alone, which is why a Jikigai-keyed Anthropic egress in a sibling repository fell outside every membership predicate."* Feedback artifacts arriving by operator email, Discord, or an encrypted drive fall outside all four. | Phase 2.2 amends `:32`'s surface list in the same edit that adds PA-34. Without it the new entry is unreachable by every membership predicate in the register. |
| R11 | **The ship Phase 5.5 CLO-attestation gate silently skips.** It fires on `legal_touch` AND (`sui_threshold` OR `draft_marker`), where the draft-marker grep is the literal `^\+.*\[DRAFT — pending CLO/counsel review` — which the corpus's house marking does **not** match. | This plan declares `brand_survival_threshold: single-user incident`, so `sui_threshold` carries it. Pin that deliberately at ship rather than relying on the marker arm, and confirm the gate actually fired on three brand-new legal artifacts. |
| R12 | **Staging any `knowledge-base/**/*.md` re-runs `scripts/generate-kb-index.sh` and force-stages `INDEX.md`**, which is badly stale (`INDEX.md:4` says 3773 files against a live ~7436) — bundling thousands of lines of unrelated drift into a legal PR. | Apply the recorded remedy (`2026-06-04-kb-index-regen-bundles-stale-drift-prefer-surgical-edit.md`): edit the `## legal` section surgically and `git checkout` the rest of `INDEX.md`. |
| R13 | `legal-doc-consistency.test.ts` loads `article-30-register.md` as an RCS-jurisdiction site and asserts `tokens.size === 1`. A PA-34 controller-identification limb naming any registry other than the existing one reds CI. | Reuse the register's existing RCS token verbatim in PA-34. |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **Build the `if processor` branch** — DPA, execution register, Art. 30(2) register, signature probe, deferred issue. | The plan's own determination proves the antecedent false. Five artifacts downstream of a branch that does not fire; plan review cut them as a block. |
| **A springing DPA annex, signed now, dormant until a trigger.** | Both triggers have **already fired** for the only counterparty that exists (collaborator access is live), so it springs immediately and buys nothing. It also hands a tester a document presuming processing that four published documents deny. |
| **Enroll a follow-through probe to chase the countersignature.** | The runbook already ruled on this exact shape — *"the work here is a conversation, which has no exit-code probe"* — and `follow-through-directive-gate.sh` denies it. The PASS condition ("no row pending") is also **vacuous at merge**, when no row exists: it would close the tracker with nothing signed. |
| **A new `alpha-tester-agreement-register.md`.** | Would be the repo's **fourth** register; the existing two hold zero rows between them after three months and both grew guards that assert vacuously. #4330(iv) already names the successor (`customer-dpa-register.md`) and says create it **on counter-signature**. A column on the existing tally is the whole requirement. |
| **An empty Art. 30(2) register with an explanatory header.** | A 30(2) record documents processing *carried out*; none is. Writing the reason not to create the file *inside* the file is the tell. The limbs are named in the determination instead. |
| **Renumber the runbook to insert a new Step 2.** | Step 2 already *is* the welcome message, and the Known-gap text's "between Steps 1 and 2" is satisfied by the top of Step 2. Renumbering rots four internal self-references for no gain. |
| **Add a C4 feedback-channel edge.** | Duplicates `betaContact -> founder` between the same two elements, distinguished only by label. PA-34 records the flow authoritatively. |
| **Amend the T&Cs to carry alpha terms.** | A Tier 1 change bumps `TC_VERSION`, forcing every existing user to re-accept and closing live sessions. |
| **Reuse `side-letter-template.md`.** | *"Jikigai is not a party"*; and it assigns IP to the Owner. Reusing it means gutting it. |
| **Procure an e-signature service.** | Art. 28(9) is met by a countersigned PDF by email; R2 `cla-evidence` (WORM, 10-year, $0.00) already exists. |
| **Absorb the pre-existing defects into this diff.** | `wg-when-an-audit-identifies-pre-existing` says file them. One consistent policy — all filed at Phase 6.2, none absorbed. |
