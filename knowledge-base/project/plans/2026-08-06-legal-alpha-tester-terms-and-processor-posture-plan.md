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
revised: 2026-08-06
revision_reason: "Blocking preconditions 0.1 and 0.6 answered; both Posture B (fired retroactively 2026-08-06) and Posture C (live) now apply. Central verdict inverted — see '## Revision' at the top of the body."
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

## Revision — 2026-08-06: the two blocking preconditions were answered, and they invert the verdict

**Read this before the Enhancement Summary below, which describes the superseded shape of the plan.**

Phase 0.1 and 0.6 were BLOCKING. The operator answered both:

1. **The 2026-08-06 guided-onboarding session ran on the operator's machine under JIKIGAI's Anthropic
   API key**, against tester content, at the tester's request. That is a verbatim instance of
   **Posture B trigger 2** as this plan already enumerated it. Posture B therefore **fired
   retroactively**, and the Art. 28(3) instrument this plan requires *before* such a run did not
   exist. A materialised gap, not a contingency.
2. **UC-1 Option 2: the operator retains collaborator access and papers it.** **Posture C is live**
   and Phase 2 **executes**.

**Both postures now apply simultaneously**, and the validation record shows they were not merely
concurrent but *co-occurring in the same run*: the operator ran that session *"with a second purpose
of dogfooding the onboarding experience itself in order to improve it for testers 2–10"*
(`2026-08-06-alpha-onboarding-motion-start.md`, §"Protocol deviation"). One indivisible set of
operations served the tester's instruction **and** Jikigai's own purpose.

**What changed, in one line each** — each is worked through in the section it affects:

| Was | Now |
|---|---|
| *"The answer is no, and it is already published."* | The published sentence is **narrower than the alpha configuration**, not a general answer. See the rewritten Overview. |
| *"the `if processor` branch does not fire, and this plan does not build it"* | It fired on 2026-08-06. The branch is **partially restored**, scoped to operator-assisted runs. |
| No Art. 30(2) record — *"a 30(2) record documents processing carried out, and none is"* | Processing **was** carried out. The stated reason is gone; a 30(2) record is restored in a **separate file**. |
| *"Escalate only if Tier 2 is actually drafted and sent"* | Counsel review is no longer hypothetical — but the recommendation is still **do not spend yet**, for reasons re-derived honestly at `## Escalation guidance`. |
| Anthropic is the *tester's* processor | Under a Jikigai key Anthropic is **Jikigai's** sub-processor for that egress. |
| Phase 2 *(skipped under Option 1)* | Phase 2 **executes**. |
| No retroactive remediation in scope | **In scope, and specified** — see `## Retroactive remediation`. |

**One correction the operator's answers did not force, caught while re-deriving:** the CMO-prescribed
Tier 1 lead — *"it runs on your machine, on your key — I can't see your repo"* — is now **false in
both halves for tester #1** and is withdrawn. See Phase 3.

**Revision method.** `soleur:legal:clo` re-adjudicated the determination against seven scoped
questions; `soleur:legal:legal-compliance-auditor` ran the cross-document consistency pass. The CLO
**overruled two positions this plan previously held** (DPD limb (d); the Art. 28(4) claim) and both
corrections are carried below rather than smoothed over. Guarded throughout against the failure mode
in `2026-08-06-my-correction-overshot-into-a-new-wrong-claim-in-a-compliance-artifact.md` —
*"a correction inherits none of the original claim's scrutiny"* — which is why the Overview states
what the published position **does** still cover as carefully as what it does not.

---

## Enhancement Summary

**Superseded in part by the Revision above** — items 1 and 6 in particular. Retained because the
research behind items 2–5 is unaffected and the record of what the review produced is worth keeping.

**Deepened on:** 2026-08-06. **Review depth:** `soleur:legal:clo` (determination),
`soleur:legal:legal-compliance-auditor` (12 Critical / 15 High / 8 Med-Low), `soleur:operations:coo`,
`soleur:product:cpo`, `soleur:marketing:cmo`, a strong-model advisor consult (ADR-083), and the
escalated 5-agent plan-review panel.

**Key changes the review produced — the plan shrank by roughly half:**

1. ~~**The `if processor` branch was cut entirely.** The determination proves its antecedent false, so
   the DPA, execution register, Art. 30(2) register, signature probe and deferred issue all went with
   it — five artifacts downstream of a branch that does not fire.~~
   **⚠ SUPERSEDED 2026-08-06.** The antecedent is **true** — trigger 2 fired. Three of the five are
   restored (instrument, Art. 30(2) record, deferred issue); two stay cut (the register row, the
   probe). Each re-decided on its own merits at
   [What the inversion restores](#what-the-inversion-restores-and-what-stays-cut).
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
6. ~~**Phase 0.1 is now BLOCKING** on establishing whose Anthropic key ran the 2026-08-06 session —
   the premise the whole determination rests on, and one no repo evidence currently settles.~~
   **✓ ANSWERED 2026-08-06: it was Jikigai's key.** Making this blocking is what caught the
   inversion — the plan's single most valuable review outcome, and the reason the wrong verdict never
   shipped. Now resolved at Phase 0.1.

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

**The answer is "no for the configuration the published documents describe, and that is not the
configuration the alpha actually ran in."** Both halves matter, and the plan previously carried only
the first.

**What the published position still covers.** `docs/legal/data-protection-disclosure.md` §2.1 (*"The
Soleur Plugin Is Not a Data Processor"*) — identical in both mirrors — concludes: *"Therefore, Soleur
is neither a Controller nor a Processor with respect to the data processed locally through the
Plugin."* That conclusion **remains true within its stated scope**: Plugin-local processing, on the
User's own machine, under the User's own credentials. Limbs (b) and (c) are intact — the Plugin as
software still collects nothing and the files stayed on a local filesystem. The `plugins/soleur/`
egress scan confirms it as of this worktree. Where the tester's personal data physically lives
(Clever Cloud vs. git) remains a **red herring**: it changes the tester's risk profile, not Jikigai's
role.

**What it does not cover.** It does not reach operator-run, Jikigai-key-funded processing of tester
content. The 2026-08-06 session ran on a different machine under a different key, so it falls
**outside** §2.1's scope rather than contradicting its conclusion — it is governed by a separate role
analysis. The formulation the determination must carry, from the CLO re-adjudication:

> The §2.1 conclusion remains true within its stated scope: Plugin-local processing, on the User's own
> machine, under the User's own credentials. The 2026-08-06 operator-assisted session falls outside
> that scope — different machine, different key — and is therefore governed by a separate role
> analysis rather than contradicting §2.1. Limb (d), however, is phrased as an unconditional statement
> of fact and is inaccurate as a general description once an operator-assisted mode exists. That is a
> documented finding requiring a scoped qualifier at next amendment.

**Do not round this off in either direction — that is the failure mode here.** It is wrong to say the
published sentence is falsified and must be retracted; it is equally wrong to say it is simply "true"
and move on. **Limb (d)** — *"Users authenticate directly with third-party services using their own
API keys and credentials"* — is written as a description of how the product works, not as a
conditional carve-out, and it **was not true of that session**. The conclusion survives because it is
premised on limbs that mostly held; limb (d) is inaccurate as an unconditional statement. That is a
**finding**, recorded here and in the determination, **not an edit this plan makes** — amending
`docs/legal/` is out of scope (see the closing paragraph of this Overview on why the #4330 chain does
not fire, and Phase 6 for the filing).

The same narrowness runs through the sibling documents, and the determination must say so rather than
citing them as though they settled the question: `terms-and-conditions.md` **§4.2 ("Third-Party API
Interactions")** premises itself on *"your own API keys and accounts"*, and `privacy-policy.md` §4.1's
*"We do not have access to your files, your code, or your usage patterns"* is scoped by its own
closing sentence (*"This section applies to the Plugin only"*). §4.1 has **four bullets in total,
including the quoted sentence** — three others, of which one concerns local storage rather than
transmission; the closing-sentence scoping is the load-bearing part of this citation, not a bullet
count. None of them is falsified. All of them are premised on a configuration the alpha departed
from.

**So the `if processor` branch DID fire — on 2026-08-06 — and this plan builds the part of it that
the fired trigger requires.** Not the whole branch: the DPA-for-repo-data the issue imagined still
does not exist, because plugin-local processing on the tester's machine is still not Jikigai
processing. What is restored is scoped to **operator-assisted runs**. See
[Retroactive remediation](#retroactive-remediation) and
[What the inversion restores](#what-the-inversion-restores-and-what-stays-cut).

Research also surfaced a second live exposure the issue does not mention, which the operator has now
elected to paper rather than dissolve:

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

Posture A remains the default for repo data on the tester's own machine. **B and C are both live.**
Posture B **fired on 2026-08-06 and is now closed forward but unremediated backward**; Posture C is
**live, ongoing, and now papered by election** (UC-1 Option 2). Closing both is this plan's P0.

**The two postures co-occurred in a single run, and the plan must not treat them as separable
events.** The validation record states the operator ran that session *"with a second purpose of
dogfooding the onboarding experience itself in order to improve it for testers 2–10."* So one
indivisible set of operations served **(i)** the tester's instruction — Jikigai as **processor** —
and **(ii)** Jikigai's own product-improvement purpose — Jikigai as **controller**. Art. 28(10)
produces limb (ii); it does not swallow limb (i), because its text is scoped *"in respect of that
processing"* — the excess, not the instructed part. A single entity holding both capacities over the
same data for different purposes is orthodox.

> **Residual uncertainty, stated rather than resolved** (CLO): the two purposes were served by one
> indivisible set of operations — no separate copy, no separate inference — and a regulator could
> hold that where a processor's own purpose is inextricable from the instructed one, the safer
> characterisation is **controllership for the whole run**. Secondly, if the dogfooding observations
> concerned only workflow mechanics rather than record content, limb (ii) may barely be personal-data
> processing at all — but the operator *consulted* output containing it, and consultation is
> processing. The determination carries both uncertainties; it does not pick the convenient branch.

**The four Posture B triggers**, enumerated here so the runbook and the determination quote one list
rather than each inventing its own. **Trigger 2 has fired** — it is marked inline rather than in a
footnote, because a trigger list that reads as prospective when one member has already fired is how
this plan got its verdict wrong the first time:

1. **The tester connects their repository to the hosted platform.** No judgment required — it is
   automatic, and the validation record states this migration is the plan. See the PA-17 caveat below.
2. **The operator runs Soleur agents against tester code or data on the operator's own machine under
   a Jikigai Anthropic key**, at the tester's request (guided onboarding, a debugging session).
   > **⚠ FIRED — 2026-08-06, tester #1 (Skouer).** This trigger describes the guided-onboarding
   > session verbatim. The Art. 28(3) instrument it requires *before* the run did not exist. See
   > [Retroactive remediation](#retroactive-remediation). The runbook's own gate was crossed too:
   > its `## Known gap` says *"resolve #7331 **before** Soleur agents operate on their repository in
   > earnest"* — and the validation record's *"Exposure (2) begins at first substantive agent run
   > against their data, not at onboarding"* is falsified for a Jikigai-keyed session, where
   > onboarding **was** the run.
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

**The cheaper way to close Posture C was offered and declined.** The plan carried revocation as an
open decision rather than silently choosing; **the operator chose to retain and paper** (UC-1
Option 2, 2026-08-06). Phase 2 therefore executes. The arithmetic behind the challenge is unchanged
and does not go away because the answer went the other way: the access buys exactly **one metric of
three** (KB growth) on a surface where the other two are unmeasurable anyway, and a tester-supplied
`git log --stat` substitutes for it. **The LIA must carry that fact in its necessity limb** — a less
intrusive means existed, was considered, and was declined for measurement fidelity. An Art. 6(1)(f)
balancing that omits the rejected alternative is not a balancing.

> **The CLO's standing recommendation, recorded because it survives the operator's answer.** It still
> favours revocation over papering, and adds a **middle path this plan did not previously have**:
> re-derive the #1442 metric to **non-personal aggregates** — commit counts, file counts, directory
> growth — rather than reading repository *content*. That removes the activity from Art. 4(1) scope
> almost entirely, costs nothing, keeps the metric, and needs no LIA, no PA record and no Art. 14
> notice. It is the highest-leverage move available here. It is **not** auto-applied — the operator
> has answered UC-1 and this plan executes that answer — but Phase 2 records it as the standing
> de-escalation, and the runbook states it as the rule for testers 2–10 so this does not recur nine
> more times by default.

Nothing is published to `docs/legal/`: doing so fires a six-step chain including *"initiate SOC 2
engagement within 90 days"* (`compliance-posture.md`, #4330 item vi). Committing a one-person company
to SOC 2 to onboard a free alpha tester is the highest-cost error available here.

**Restoring the Tier 2 instrument does NOT fire that chain, and the plan must say so explicitly** —
otherwise "we now need a DPA" gets read as "we now need SOC 2," which is the single most expensive
misreading available. The #4330 chain is keyed to **publishing the customer-facing Web Platform DPA
template to `docs/legal/`**, on one of three named triggers: *"(a) first B2B prospect asks 'Do you
have a DPA?'; (b) first paying customer organization invites employees as Workspace Co-Members…;
(c) first EU customer requests SCCs."* **None has fired.** The instrument restored here is a
different thing: a **bilateral, unpublished, alpha-scoped Art. 28(3) annex** for operator-assisted
sessions, held in `knowledge-base/legal/` and sent by email to one counterparty. It is not the
Web Platform customer DPA and must not be drafted from it wholesale (see the template's clause-level
defects in Reconciliation).

<a id="retroactive-remediation"></a>

## Retroactive remediation — the 2026-08-06 session

Something already happened without the instrument that was supposed to precede it. This section says
what the operator does about it. It is a **deliverable of this plan**, not a contingency.

**It is not a notifiable personal-data breach.** Art. 4(12) requires a *security* failure leading to
unauthorised or accidental disclosure. Here the disclosure was **requested by the tester** and no
security control failed. This is a **lawfulness and documentation failure**, which Art. 33/34 do not
reach. *Residual argument recorded rather than dismissed:* limb (ii) — the dogfooding purpose — was
**not** what the tester asked for, and onward use for the processor's own purpose could be argued
into "unauthorised". The CLO's view is that the argument fails on the security limb; it is flagged,
not asserted away. **Do not use this paragraph to conclude "nothing happened."** It concludes only
that no regulator notification clock is running.

**The five steps, in order:**

1. **Reconstruct the session's scope** (Phase 0.7). Did personal data — founder/investor records from
   Skouer's product database — actually enter the operator's machine or egress to Anthropic, or was
   it confined to repo scaffolding, config and knowledge-base prose? **Likely reconstructible from
   the local Claude Code session transcripts on the operator's machine; check before declaring it
   unknowable.** If genuinely unreconstructible, adopt the **precautionary** assumption that personal
   data was in scope — tester content was the working material. Do not adopt the favourable branch by
   default.
2. **Behavioural control, effective immediately: no further Jikigai-keyed runs against tester
   content** until an instrument exists. This is what closes the exposure forward, it costs nothing,
   and it is what makes deferring the counsel spend legitimate rather than negligent.
3. **Draft the Art. 28(3) instrument** covering operator-assisted mode, **naming Anthropic as an
   authorised sub-processor**, effective **forward**, with a recital acknowledging the 2026-08-06
   session. **Ratification evidences good faith; it does not cure retroactively** — the plan must not
   imply a backdated instrument fixes anything.
4. **Internal note** recording the dual purpose, the egress, and the **~2026-09-05 retention expiry**
   (2026-08-06 + Anthropic's default 30-day window), after which the Anthropic-side copy lapses. The
   date is a fact the operator should have written down, not a deadline to chase.
5. **Sign the Anthropic Zero-Retention amendment, or use the tester's key**, before any further
   session. This actions the fired `anthropic.md` trigger (Phase 5.3) and is the cheapest of the five.

**What the tester must be told, and where.** Candour wins; proportionality governs the *form*. Two
facts a reasonable person would want to know: **their content transited Jikigai's Anthropic account
under a 30-day retention window**, and **the session also served Jikigai's own improvement purpose**.

Neither belongs in the Tier 1 welcome notice. Tier 1 is ≤90 words, warm, first-person, and merged
into an existing paragraph — putting this there would either blow the budget or bury the disclosure
inside a welcome message, which is the worse of the two. **It is a separate, short, plain-language
message: roughly five sentences, no apology theatre, no defined terms.** Tier 1 still goes to tester
#1 unconditionally; this rides alongside it, not inside it. Both are drafted in Phase 3.

<a id="what-the-inversion-restores-and-what-stays-cut"></a>

## What the inversion restores, and what stays cut

The Enhancement Summary recorded that five artifacts were cut as *"downstream of a branch that does
not fire."* The branch fired. Each is re-decided **on its own merits**, not restored as a block —
restoring them wholesale would repeat, in the opposite direction, exactly the error being corrected.

| Artifact | Now | Why |
|---|---|---|
| **Tier 2 bilateral instrument** (Art. 28(3)) | **RESTORED**, re-scoped | Art. 28(3) requires a written contract, and the processing it governs has already happened once and is designed to repeat for testers 2–10. But it is **not** the DPA the issue imagined (repo data at rest): it covers **operator-assisted runs only**. Drafted from scratch against the template's §7.2 and §10, not copied from it. |
| **Art. 30(2) processor record** | **RESTORED** | The stated reason for omitting it — *"a 30(2) record documents processing carried out, and none is"* — is falsified. Processing **was** carried out. Art. 30(5)'s <250-employee derogation is not relied on: *"not occasional"* is read narrowly and operator-assisted onboarding is explicitly designed to repeat, so the derogation is unreliable — and the record costs almost nothing, so the question need not be resolved to make the call. |
| **PA-34 — dogfooding limb of the 2026-08-06 guided session** | **RESTORED** (was the Phase 2 record, now re-scoped) | Art. 30(1) shape, Jikigai as controller. Session-bound. The Posture C collaborator-access record is **PA-35**, not this one. |
| **PA-35 — a third activity the plan did not have** | **NEW** | The CLO separated what this plan conflated: the **#1442 collaborator-access observation is ongoing and not session-bound**, so it is a distinct activity from the dogfooding limb of a single guided session. Two records, two ordinals. Reserve them consecutively at Phase 0.3. |
| **Execution register row** (`tenant-dpa-register.md`) | **STAYS CUT** | Unchanged by the inversion. #4330 item iv forbids a row there and names the successor: `customer-dpa-register.md`, created **on counter-signature**, not pre-emptively. Posture B firing does not reopen a recorded decision about *where a row goes*. AC3 still asserts the diff is empty. |
| **Signature / follow-through probe** | **STAYS CUT** | Every reason is untouched: `follow-through-directive-gate.sh` denies the command, the PASS condition is vacuous at merge, and `exit 2` is not silent (the sweeper comments on TRANSIENT, so ~60 public comments about a named counterparty's contract status). A dated issue with the due date in the **title** remains the mechanism. |
| **Deferred counsel / execution issue** | **RESTORED as an actual filing**, not a conditional one | Phase 6.1. The instrument is being drafted, so the issue tracks a real deliverable rather than a hypothetical one. It still does **not** carry the `follow-through` label. |
| **An empty Art. 30(2) register with an explanatory header** | **STILL REJECTED — but moot** | The original objection (writing the reason not to create a file inside the file) was sound. It no longer applies: the register will not be empty. |

## Research Reconciliation — issue premises vs. repo reality

| Issue premise | Reality on disk | Plan response |
|---|---|---|
| "Nothing binds either direction today." | **False.** `terms-and-conditions.md:20,22`: *"By **installing**, accessing, or using Soleur (**whether the Plugin** or the Web Platform), you agree to be bound."* **§10.2 ("No Guarantee of Availability or Accuracy")** already disclaims SLA, uptime and warranty; the AUP binds "whether locally via the Plugin"; `LICENSE` (BUSL-1.1) binds as a copyright licence. **Cite clause numbers, never line numbers** — the T&Cs have sections 1–17, so a drafted instrument citing "§298" or "§112" would cite clauses that do not exist (`cq-cite-content-anchor-not-line-number`); the supersession duty is **§3b.4**. | The defect is **notice and assent evidence**, not absent terms: `plugins/soleur/README.md:373-375` surfaces only the BSL licence and never links the Terms, so a CLI installer is bound by terms never shown — weak against a French B2B counterparty. Tier 1 carries a Terms link and asks for a one-line reply. |
| "Controller/processor posture … undetermined." | **Published and negative — but for a narrower configuration than the alpha ran in.** DPD §2.1 (*"The Soleur Plugin Is Not a Data Processor"*), limbs (a)–(d), plus §2.2 assigning the **user** controller duties; `gdpr-policy.md`, `privacy-policy.md` §4.1, and `article-30-register.md` §0 concur. Every one of them is premised on the tester's machine and the tester's own key — see T&C **§4.2 ("Third-Party API Interactions")**: *"These interactions occur through your own API keys and accounts."* | The determination **confirms the published position within its scope** and records that the scope does not reach operator-assisted runs. It does **not** reverse it: the five published sentences stay true as written. It adds the finding that DPD **limb (d)** is inaccurate as an *unconditional* statement now an operator-assisted mode exists — filed (Phase 6.2), not edited here. |
| "Jikigai plausibly becomes a processor if agents operate on the repo." | The crux the issue poses — *does an agent touch PII?* — is **the wrong test** and a non-lawyer cannot apply it. Migrations, live-data debugging and dump/fixture files all happen on the tester's machine under the tester's key and cross no boundary. | Replaced by the machine/key/purpose test and four concrete Posture B triggers. |
| *(absent from the issue)* | **Posture C is live**: collaborator access to a private repo, read for Jikigai's own metrics, no lawful basis recorded. | The P0 deliverable — or dissolved outright by declining the access. |
| "DPA … registered in `tenant-dpa-register.md`." | **A recorded decision forbids it and names the successor.** `compliance-posture.md` (#4330 item iv): write the row *"**on counter-signature** (NOT `tenant-dpa-register.md`… either create `customer-dpa-register.md` with a parallel schema, or amend the existing register to be dual-purpose)."* That register also has no Founder UUID for a CLI tester, no "drafted" status, and a §6.1 **30-day clock** that fires on the first `dpa-signed` row. | Write **no row** anywhere now. Record the tester's terms status as one new column on the **existing recruitment tally** in the runbook. `customer-dpa-register.md` is created **on counter-signature**, per #4330 — not pre-emptively. |
| "Article 30 register updated if a new processing activity is confirmed." | Titled **"Article 30(1) Register"**, scoped *"in its capacity as **data controller**"*, 33 activities, **zero Art. 30(2) records**. Art. 30(2) limbs are different and fewer — no purposes, no data-subject categories, no retention. | **Three records now, not one.** **PA-34** (dogfooding limb of the guided session) and **PA-35** (ongoing #1442 collaborator-access observation) in the existing `(a)`–`(g)` controller shape. Plus a **new Art. 30(2) register at `knowledge-base/legal/article-30-2-register.md`** for the processor limb — a separate file, not a "Part B" of the 30(1) register: the field sets differ, the existing file is titled and scoped to controller capacity, and one file meaning two things is the ambiguity #7100 punished. Cross-link it from §0. *(The plan's former reason for creating none — "a 30(2) record documents processing carried out, and none is" — is falsified; processing was carried out.)* |
| *(absent from the issue, and from this plan until the inversion)* | **The register's own membership predicate excludes the activity.** §0's In-scope surfaces paragraph reads: *"The locally-installed Soleur Claude Code plugin is **out of scope** of this register — it processes no personal data **on Jikigai infrastructure** and Jikigai is not a controller for it."* **Both conjuncts are now false**: Jikigai's credentials effected the processing, and Jikigai is controller for the dogfooding limb. The paragraph carries its own post-mortem of this exact defect — the list *"previously named `jikig-ai/soleur` alone, which is why a Jikigai-keyed Anthropic egress in a sibling repository fell outside every membership predicate"* (#7100). | **This is #7100 recurring a third time**, and the fix is not another surface added to a list. Rewrite the predicate to key on **who determines purposes, or whose credentials effect the processing, regardless of host**. Keying on *infrastructure location* is the defect, and each patch that adds one more surface leaves it in place. Phase 2.3. |
| "Anthropic as sub-processor." | **Both chains exist, on different surfaces.** Under the **tester's** key (Posture A) Anthropic is the *tester's* processor — DPD §4.2, `gdpr-policy.md`, DPA template §6.3 / Schedule 2 BYOK row. Under the **Jikigai** key on 2026-08-06 (Posture B) Anthropic is **Jikigai's sub-processor** for that egress. | The instrument must **name Anthropic as an authorised sub-processor** for operator-assisted mode, and must not import the template's BYOK Schedule 2 row unamended — telling the tester *"Anthropic is YOUR sub-processor"* is true in A and **false in B**, and a misstatement in a compliance instrument. The surface determines the sentence; a single flat statement is wrong on one of them whichever way it is written. |

**Further findings:**

- **`anthropic.md`'s own re-evaluation trigger has fired and is unactioned.** §"Re-evaluate when" —
  *"Soleur takes on data subjects beyond the operator (**cohort onboarding**)."* Cohort onboarding
  began 2026-08-06. Frontmatter `zero_retention_amendment: unsigned` means the **30-day Anthropic
  retention window** applies to everything egressing under a Jikigai key — **now including tester
  content**, which is new and is the operative consequence. For the 2026-08-06 session that window
  expires **~2026-09-05**.

- **CORRECTION — this plan's Art. 28(4) claim was wrong, and is replaced.** The plan previously
  asserted that because `anthropic.md` is *"a snapshot memo … not an executed bilateral instrument —
  no flow-down warranty, no audit right, no breach-notification timeline"*, it **"does not discharge
  Art. 28(4)."** The CLO overruled that on re-adjudication, and the reasoning is worth keeping
  because the error is instructive: **it conflated Jikigai's internal memo with Anthropic's actual
  DPA.** Anthropic's DPA auto-incorporates via Commercial Terms §C (effective 2025-02-24) and carries
  Art. 28(3) terms, EU-US DPF, SCCs M2+3, UK IDTA and the Swiss Addendum. Anthropic is bound by that
  instrument regardless of what a file in Jikigai's repo says. Sharper still: **Art. 28(4) requires
  mirroring the controller–processor contract downward — and there is no contract with the tester, so
  there is nothing to mirror. Art. 28(4) is inchoate here, not breached.**

  **The live defects are different and narrower**, and the determination must state these instead:
  **(a) Art. 28(2)** — the tester never authorised, and was never told of, any sub-processor;
  **(b)** there is **no instrument with the tester at all**, which is the root gap that makes (a)
  possible; **(c)** the 30-day retention now attaches to tester content under Jikigai's account.
  Two caveats to carry: the operator must **confirm the Jikigai account is on Commercial Terms** —
  §C does not auto-incorporate on Consumer ToS — and **Art. 28(4)'s "fully liable" limb attaches to
  Jikigai for Anthropic's performance with or without an instrument.**
- **Do not amend the T&Cs.** `tc-version-bump-policy.md:22-27`: a `TC_VERSION` bump *"forces every
  existing user to re-accept the Terms on their next page load"* and closes live WebSocket sessions.
- **Do not reuse `side-letter-template.md`.** `:119` — *"Jikigai is **not a party**"*; `:81` assigns
  IP **to the Owner**, the wrong direction.
- **The determination has a precedent format** —
  `knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md`
  (Verdict / Reasoning / Conditions / disposition). Use `audits/`; do not invent a directory.
- **The DPA template's clause-level defects.** Tier 2 **is** a deliverable of this PR (Phase 3B), so
  these are binding drafting constraints, not contingent guidance: §1.2 `:43` scopes
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

**The failure mode inverted with the verdict.** It was: *a tester handed an instrument presuming
processing that four published documents deny.* That risk has not vanished, but it is no longer the
sharp one, because the processing is real.

**If this lands broken, the user experiences** a supplier that **reassured them in writing about the
precise thing that was not true.** The withdrawn Tier 1 lead — *"it runs on your machine, on your
key — I can't see your repo"* — is false in both halves for tester #1: the 2026-08-06 session ran on
the operator's machine on Jikigai's key, and the operator holds collaborator access and can see the
repo. A tester who is later told the truth, having first been sent that sentence, does not read it as
an imprecision. **A comforting false statement is worse than the gap it was written to close** — and
it would have been sent in the document whose whole purpose was to fix the problem.

The older tension is still there and is now the *other* way round: the tester reads
`privacy-policy.md` §4.1 — *"We do not have access to your files, your code, or your usage
patterns"* — while the operator holds a collaborator seat on their private repository. That sentence
is scoped to the Plugin by its own closing line and is not falsified by collaborator access, which is
not a Plugin capability. But **scoping that a lawyer can defend is not scoping a tester will read.**
Tier 1 must not repeat it as though it were a promise about Jikigai's conduct generally.

**If this leaks, the user's data is exposed via** two live paths, not one: **(i)** the operator's
collaborator access to the tester's private repository, exercised for Jikigai's own metrics — now
papered by election, previously with no lawful basis and still with no confidentiality undertaking
running to the tester until Tier 1 lands; and **(ii)** tester content that **already egressed** to
Anthropic under the Jikigai key and sits in a 30-day retention window to ~2026-09-05. Anything from
that repo surfacing in a Soleur commit, issue, digest or case study is a confidentiality and
trade-secret problem — with a counterparty who shares a coworking space with the founder.

**Brand-survival threshold:** `single-user incident` — **re-confirmed, unchanged, and now carrying
more weight than when it was set.** Re-checked rather than assumed: it was chosen because this is the
brand's first external user and the exposure was *live rather than hypothetical*; the exposure is now
**materialised rather than live** — one instance has already occurred. The threshold does not
escalate, because the affected population is still exactly one identified tester and the value is
already the most protective one this plan can carry. It keeps `requires_cpo_signoff: true` and routes
`user-impact-reviewer` at review. It is also what carries the ship Phase 5.5 CLO-attestation gate
(R11), which matters more now that three brand-new legal artifacts ship instead of one.

## Resolved decision — behavioural vs. documentary control

Surfaced by plan review as a **User-Challenge** (ADR-084). Persisted to
`knowledge-base/project/specs/feat-one-shot-7331-alpha-tester-terms-dpa/decision-challenges.md`.

> **ANSWERED 2026-08-06 — Option 2 (retain and paper).** The operator keeps collaborator access.
> **Phase 2 executes.** Posture C is live and ongoing. The challenge text is preserved below verbatim
> because its arithmetic is still load-bearing on the LIA's necessity limb — a less intrusive means
> existed and was declined — and because the standing de-escalation (revoke, or re-derive #1442 to
> non-personal aggregates) remains available if papering proves burdensome.

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

*(End of preserved challenge text. Option 2 was chosen; Phase 2 executes.)*

## Domain Review

**Domains relevant:** Legal, Operations, Product

**Agents invoked:** `soleur:legal:clo`, `soleur:legal:legal-compliance-auditor`,
`soleur:operations:coo`, `soleur:product:cpo`, `soleur:marketing:cmo`, a scoped strong-model advisor
consult (ADR-083), and the escalated 5-agent plan-review panel. **Skipped specialists:** none.

### Legal

The determination was **not** improvised inline. `soleur:legal:clo` adjudicated it;
`soleur:legal:legal-compliance-auditor` returned 12 Critical / 15 High / 8 Medium-Low cross-document
findings. Load-bearing outputs are in the Overview and Reconciliation above.

**Re-adjudicated 2026-08-06** after the two operator answers, on a scoped 7-question brief. The CLO
**overruled two positions this plan held** — DPD limb (d) is *not* merely narrower but inaccurate as
an unconditional statement, and the Art. 28(4) claim was wrong — and **added one activity the plan
had conflated** (the ongoing #1442 observation is distinct from the dogfooding limb of a single
session; PA-34 **and** PA-35). Both corrections are carried in the text above rather than smoothed
into the existing prose.

**Escalation, blunt:** the determination memo still needs **no** lawyer. It is the `audits/`
CLO-attestation lane, and its harder half is now a *narrower* claim than before — it says what the
published position covers and what it does not, both verifiable from the documents' own text. What
changed is that it no longer *only* restates published positions; it records a materialised gap. That
raises the bar on candour, not on credentials. The **liability cap and confidentiality undertaking**
in the Tier 2 instrument remain the highest-value hour of counsel time in this work — see
`## Escalation guidance` for why that hour is still not bought yet.

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
  not fire** — counsel review is one-time (`recommended-tools.md` §`vendor-msa-review`: *"typical
  cost **$300-800** per contract"* — **USD**, not EUR as this plan previously said) and belongs in the
  One-Time section. It is **one review of the instrument, not one per tester.** Unchanged by the
  inversion: the instrument is now actually drafted, but it is still reviewed **once**, and the review
  is still not bought in this PR (see `## Escalation guidance`).

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
  Tier 2 — a deliverable of this PR — is an **addition**, not a substitution.
- **CMO constraints on the Tier 1 copy** (route it through `soleur:marketing:copywriter`, not the
  legal generator): **≤ 90 words**; merged into the existing "One note on record-keeping" paragraph
  rather than added as a second block; **first-person singular** throughout, matching the Art. 14
  paragraph already there; **never the word "Plugin"** in tester-facing copy; no defined terms, no
  section numbers, no "shall".

- **⚠ The prescribed lead is WITHDRAWN.** It read: *"lead with what Soleur owes — it runs on your
  machine, on your key, I can't see your repo — which is already published and converts the notice
  from paperwork into reassurance."* Under the Phase 0.1 and 0.6 answers **both halves are false for
  tester #1**: the 2026-08-06 session ran on the operator's machine on Jikigai's key, and the
  operator holds collaborator access and can see the repo. Shipping it would put an affirmatively
  false reassurance in writing to the counterparty, about the exact subject in dispute, inside the
  document written to fix the problem. **The constraint it came from survives** — *lead with what
  Soleur owes* — but what Soleur owes is now **candour about access**, not a claim of no-access. Lead
  with what is both true and reassuring: the tool runs locally and Jikigai operates no server that
  reaches their code; where Jikigai *does* have access, it is access the tester granted, for a stated
  purpose, revocable at a word. **This is the single highest-risk sentence in the deliverable set** —
  it is warm, quotable, and was wrong.
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

**Re-derived after the inversion. The recommendation did not change, but the reason did — and the old
reason no longer works.** The old text said *"escalate only if Tier 2 is actually drafted and sent"*
and *"do NOT escalate the determination itself."* The first was conditional on an instrument that is
now being drafted; the condition has been met, so that sentence can no longer carry the decision.

**Bottom line: no counsel spend on the alpha instrument now.** Not because it is hypothetical — it is
not — but because a **free behavioural control closes the exposure that would otherwise force the
spend.** With no further Jikigai-keyed runs against tester content, the 2026-08-06 exposure is closed
forward and the Anthropic-side copy lapses ~2026-09-05. That defers the **spend**, not the
**drafting**: the marked internal draft ships at **$0** and is adequate for one unpaid friendly
tester. **The behavioural control is what makes the deferral legitimate rather than negligent, so it
is a Phase 4 runbook deliverable and an acceptance criterion (AC14), not an intention.**

**Ships as a marked draft, no counsel, $0:** the determination memo; the retroactive-remediation
record and the tester message; PA-34, PA-35 and the LIA; the Art. 30(2) register; the Art. 14 line;
the Tier 1 notice; the runbook operating rule; the statutory-catalog bullet; the tally column.

**Buy counsel at exactly one moment:** before the Tier 2 instrument is **sent to a counterparty** —
covering the **liability cap**, the **confidentiality undertaking**, and French-law assent mechanics
for an unpaid B2B alpha. One review, reusable across all ten testers. AC13 still gates it.

**On price — the plan's own figure was wrong twice, and both corrections matter.**
`recommended-tools.md` §`vendor-msa-review` says **"typical cost $300-800 per contract"** — **USD,
not EUR**; this plan said "EUR 300–800" and cited line numbers rather than the section anchor. And
more substantively: **neither listed SKU is the right product.** §`vendor-msa-review` ($300-800) and
§`ai-vendor-terms` (~$200-400) are both **contract-scan** products; a lawful-basis / Art. 14 / DPIA
question is **data-protection advice**, which neither describes. Before budgeting, the operator must
establish **whether the marketplace offers a data-protection-advice SKU at all, and whether the panel
is GDPR-qualified.** Budget in **EUR with FX and reverse-charge VAT** — these are USD list prices
quoted against a French SARL. Treat $300-800 as a floor for the wrong product, not a quote.

**Budget reality check — re-assessed, and UC-2 survives.** Counsel receives the standard
accountability pack (`statutory-response-catalog.md`, step 3: *"Pull the accountability pack:
Article 30 register…"*), which holds an ~5-months-overdue DPIA (#7121), an expired Art. 14 clock
(#7120), and **a live processing limb with no available lawful basis** (#7119, BLOCKING).

UC-2 argued #7119 outranks *"a **conditional** instrument for an unpaid tester who has not asked for
one."* **That premise is dead — the instrument is not conditional.** So the challenge is re-derived
rather than carried forward, and it **still holds, on different reasoning**: #7119 involves ~80
digests **already published to a public repo** carrying commenter handles and stargazer names, never
deleted, **still running**, plus an expired notice clock and an overdue DPIA. The alpha instrument
moved from *hypothetical* to *small, bounded, and closed forward by the behavioural control* — one
identified counterparty, who requested the processing, whose exposure lapses in a month. **#7119 wins
on scale, publicity, and continuance.** It is not close.

> **The highest-leverage move here costs nothing and is not a legal purchase at all** (CLO): the
> #1442 collaborator-access observation is the one thing still running. **Re-derive it to non-personal
> aggregates** — commit counts, file counts, directory growth — instead of reading repository content.
> That removes it from Art. 4(1) scope almost entirely and keeps the metric. Revocation does the same
> and is also free. The operator has elected to paper instead (UC-1 Option 2), which this plan
> executes; the cheaper options are recorded so the election is a choice rather than a default, and so
> testers 2–10 are not onboarded into the same posture by inertia.

## Open Code-Review Overlap

**None.** All 64 open `code-review`-labelled issues fetched; each planned path searched against their
bodies via standalone `jq --arg`; zero matches.

## Implementation Phases

Tasks anchor on **headings and quoted content, never bare line numbers**
(`cq-cite-content-anchor-not-line-number`).

### Phase 0 — Preconditions

**Reconciled with `tasks.md` on 2026-08-06.** The two files had drifted: this section was missing the
BLOCKING 0.1 entirely and its ordinals were shifted by one against `tasks.md` (plan 0.1 = "re-derive
the Art. 30 ordinal" = tasks 0.3). `tasks.md` was the superset and its numbering is now canonical
here. **0.1 and 0.6 are RESOLVED** and recorded as established fact.

**0.1 — RESOLVED 2026-08-06. BLOCKING, and the answer inverts the plan.** The 2026-08-06
guided-onboarding session ran on the **operator's machine** under **JIKIGAI's Anthropic API key**,
against tester content, at the tester's request — a verbatim instance of **Posture B trigger 2**.
Posture B fired retroactively; the Art. 28(3) instrument required *before* the run did not exist.
Anthropic is **Jikigai's** sub-processor for that egress.

**0.6 — RESOLVED 2026-08-06. UC-1 Option 2 (retain and paper).** The operator keeps collaborator
access. **Phase 2 executes.** Posture C is live and ongoing.

0.2 Re-run the `plugins/soleur/` egress scan; record commands and output for the determination, so it
cites verified fact rather than the privacy policy proving itself. **Scope caveat:** the scan
establishes what the *plugin* does on the *tester's* machine. It is silent on the 0.1 configuration.
Do not let a clean scan be cited as evidence about the operator-run session — that inference is the
one this plan already made wrong once.

0.3 Re-derive the next free Art. 30 ordinal against `origin/main`
(`grep -n "^## Processing Activity" knowledge-base/legal/article-30-register.md | tail -3`).
**Reserve two consecutive ordinals** — PA-34 and PA-35 (see Phase 2). Last occupied: PA-33.

0.4 **#736 is CLOSED** (title: *"legal: update Terms & Conditions for web platform cloud services"*),
while `compliance-posture.md` records it `OPEN` under "T&C blanket statement contradictions" — stale
on both status and subject. The T&C contradictions found here are **untracked**; file them fresh.
*(This item previously read "Read open issue #736", which the deepen sweep had already falsified —
corrected at the same time as the ordinal reconciliation.)*

0.5 Confirm `docs/legal/data-processing-agreement.md` still does not exist. **Verified absent
2026-08-06**, and it stays absent — the restored Tier 2 instrument is not published, so the #4330
chain does not fire.

**0.7 — NEW, and the one remaining factual gate.** Establish what the 2026-08-06 session actually
touched: did **personal data** — founder/investor records from Skouer's product database — enter the
operator's machine or egress to Anthropic under the Jikigai key, or was it confined to repo
scaffolding, config and knowledge-base prose? Art. 28 bites only on personal data, so this scopes the
whole remediation. **Likely reconstructible from the local Claude Code session transcripts on the
operator's machine — check before declaring it unknowable.** If genuinely unreconstructible, record
that and adopt the **precautionary** assumption that personal data was in scope. Do not resolve this
by asserting the convenient answer.

### Phase 1 — The determination (blocks everything)

1.1 Have `soleur:legal:clo` author
`knowledge-base/legal/audits/<YYYY-MM-DD>-alpha-tester-controller-processor-determination.md` in the
`2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md` format: the three postures, the
machine/key/purpose test, the four Posture B triggers, the Posture C finding, the Phase 0.2 evidence,
why the beta-CRM LIA does not cover this, and the role-collision note (Jikigai already processes
Skouer's own data via PA-30).
1.2 Retitle and rewrite what was the **"If a crossing trigger fires"** section as **"A crossing
trigger HAS fired"**. It still names the Art. 30(2)(a)–(d) limbs and states that any bilateral
instrument must be counsel-reviewed before it is sent — but it now points at a **written record that
exists** (Phase 2.5) rather than standing in for one, and it records that the "before processing
begins" rule was **not** met on 2026-08-06. Keep the prospective guidance for triggers 1, 3 and 4,
which have not fired.
1.3 Carry the **scope formulation verbatim** from the Overview — what DPD §2.1 still covers, what it
does not, and the limb (d) finding. This is the sentence most likely to be misquoted in either
direction; the determination should state it once, precisely, and let everything else cite it.
1.4 Record the **dual-purpose analysis** (processor for the instructed limb, controller for the
dogfooding limb, Art. 28(10) scoped to the excess) **and both residual uncertainties** — the
inextricability argument for whole-run controllership, and whether the dogfooding limb touched record
content at all. State them; do not resolve them in the convenient direction.
1.5 Correct the **Art. 28(4)** analysis per Further Findings: Anthropic's own DPA auto-incorporates
and binds; Art. 28(4) is **inchoate, not breached**, because there is no tester contract to mirror;
the live defects are **Art. 28(2)** (no sub-processor authorisation or notice), the absent instrument,
and the 30-day retention. Note the two caveats — confirm **Commercial** (not Consumer) Terms, and
Art. 28(4)'s "fully liable" limb attaches regardless.
1.6 Canonical marking **verbatim, blockquote, opening and closing**; frontmatter
`status: draft-requires-counsel-review`.
1.7 **Written whichever way the verdict falls** — this is now doing more work, not less. The
determination is what stops the negative half being over-read at tester #3 *and* stops the positive
half being over-read into "we are a processor of everyone's repository."

### Phase 2 — Close Posture C and record Posture B **(executes — Option 2 chosen 2026-08-06)**

**Marking applies to every artifact in this phase.** The canonical draft marking **verbatim, as a
blockquote, opening and closing**, plus frontmatter `status: draft-requires-counsel-review` — on the
LIA (2.1) and on the **new** `article-30-2-register.md` (2.5). PA-34 and PA-35 inherit the 30(1)
register's existing marking; the new file has none to inherit and must carry its own. Asserted by
**AC17**.

2.0 The LIA's Art. 6(1)(f) **necessity** limb must state that a **less intrusive means exists and was
declined**: a tester-supplied `git log --stat`, or re-deriving #1442 to non-personal aggregates, buys
the same single metric. Option 2 was chosen on measurement fidelity, not because Option 1 was
unavailable. An LIA that omits the rejected alternative is not performing the balancing it claims to.

2.1 LIA at `knowledge-base/legal/legitimate-interest-assessments/<date>-alpha-tester-repo-observation-lia.md`,
modelled on `2026-07-07-beta-crm-lia.md`: Art. 6(1)(f) three-part balancing for operator
collaborator-access observation of a private tester repository.
2.2 **PA-34** in `article-30-register.md`, existing `| Art. 30(1) limb | Entry |` shape, Jikigai as
**controller** — the **dogfooding limb of the 2026-08-06 guided session**. Append by content anchor,
not file order. Reuse the register's existing RCS token verbatim (R13).
2.3 **PA-35** — the **ongoing #1442 collaborator-access observation**. A separate activity from
PA-34: it is continuous rather than session-bound, and collapsing the two would leave the live
activity described by a record whose scope is a single past event. Same shape, Jikigai as controller,
same RCS token.
2.4 **Rewrite the register's membership predicate**, §0 "In-scope surfaces". Today it excludes *"the
locally-installed Soleur Claude Code plugin … it processes no personal data **on Jikigai
infrastructure** and Jikigai is not a controller for it"* — **both conjuncts are now false**. Do
**not** fix this by appending one more surface to the list: that is what was done for #7100 and it
left the defect in place. Re-key the predicate on **who determines purposes, or whose credentials
effect the processing, regardless of host.** Without this, PA-34 and PA-35 are unreachable by every
membership predicate in the register — the #7100 defect, third occurrence (R10).
2.5 **Art. 30(2) processor record** at a **new** `knowledge-base/legal/article-30-2-register.md`, for
the instructed limb of the 2026-08-06 session. Separate file, not a "Part B" of the 30(1) register:
the limb sets differ (30(2) has no purposes, no data-subject categories, no retention), the existing
file is titled and scoped to controller capacity, and one file meaning two things is the ambiguity
#7100 punished. Cross-link from §0 of the 30(1) register and from the determination.
**Art. 30(5) is not relied on** — *"not occasional"* is read narrowly and operator-assisted
onboarding is designed to repeat for testers 2–10; the record costs almost nothing, so the derogation
question need not be resolved to make the call. **Check before writing:**
`apps/web-platform/test/legal-doc-consistency.test.ts` loads an **explicit site list** (it names
`knowledge-base/legal/article-30-register.md` by path), so a new register is **not** auto-enrolled and
will not fail CI — but it also will not be **guarded**. If the 30(2) register carries an `RCS <City>`
token, add it to that site list, or it becomes an unguarded fourth site — the drift class #4086
closed.
2.6 Art. 14 notice line for involuntary third-party data subjects, **claiming Art. 14(5)(b)
disproportionate effort in writing**, delivered as one more sentence in the welcome message. Note the
adjacency the LIA must acknowledge: this is the same Art. 14-to-unreachable-third-parties shape as
**#7120**, whose clock expired. Do not create a second one silently.

### Phase 3 — Tier 1 alpha notice (all testers, including #1)

3.1 Draft the substance via `legal-document-generator` (invoked **directly via Task** — not
`/soleur:legal-generate`, whose Phase 0/1 use `AskUserQuestion` and would hang the headless pipeline),
then render the paste-block via `soleur:marketing:copywriter` against the CMO constraints above.
3.2 Content: a Terms link; confidentiality owed *by Jikigai* over the private repo; end-of-alpha data
disposition; no fee, no obligation, stop anytime; the collaborator-access purpose and scope stated
plainly (**now unconditional — Option 2 was chosen**); and **redact third-party personal data before
sending logs**, with Jikigai's undertaking to delete unredacted material on notice. **Do not use the
withdrawn lead** (see the CMO constraints above), and do not restate `privacy-policy.md` §4.1's *"We
do not have access to your files, your code"* as though it were a promise about Jikigai's conduct
generally — it is scoped to the Plugin by its own closing sentence, and repeating it here would
re-create the contradiction Tier 1 exists to remove.

3.2b **The retroactive-remediation message — a SEPARATE communication, not a Tier 1 sentence.**
Roughly **five sentences**, plain language, no defined terms, **no apology theatre**. Two facts a
reasonable person would want: **their content transited Jikigai's Anthropic account under a 30-day
retention window** (expiring ~2026-09-05 for the 2026-08-06 session), and **the session also served
Jikigai's own improvement purpose**. Candour wins; proportionality governs the form — this does not
belong inside a ≤90-word warm welcome, where it would either blow the budget or bury the disclosure.
It rides **alongside** Tier 1 to tester #1, not inside it. Gate it on Phase 0.7: what it says about
personal data depends on what the session is found to have touched, and it must not assert more
precision than 0.7 supports.
3.3 Ask for a **one-line reply** as assent evidence — this is what satisfies issue AC1 and closes the
notice/assent gap behind T&C `:22`. Note the tension CMO raised (a reply is a second yes); it is
accepted because Tier 1 arrives *after* the tester has already agreed to take part.
3.4 Fence the paste-block away from the DRAFT markings so the banner cannot be copied into a welcome
email.

### Phase 3B — Tier 2 instrument (RESTORED, and re-scoped)

3B.1 Draft the **Art. 28(3) instrument for operator-assisted mode** at
`knowledge-base/legal/<date>-alpha-tester-processing-annex.md`. **Not** the DPA the issue imagined —
it does not cover repo data at rest on the tester's machine, which is still not Jikigai processing.
It covers **operator-run sessions against tester content under a Jikigai credential**, and nothing
else. Scope creep here re-creates the misstatement the Reconciliation warns about.
3B.2 It must **name Anthropic as an authorised sub-processor** (Art. 28(2)), be **effective forward**,
and carry a **recital acknowledging the 2026-08-06 session**. State in the plan and in the instrument
that **ratification evidences good faith and does not cure retroactively** — a recital is not a
backdate.
3B.3 Draft from scratch against the template's genuinely good parts — **§7.2 verbatim** (2-business-day
ack / 10-business-day SLA) and **§10 (audit)** near-verbatim — and **not** from Schedule 4's 17 TOMs,
which describe RLS/Supabase/WORM/R2 and none of which describes this relationship (R7, the #6588
defect). Do not import the Schedule 2 BYOK row unamended.
3B.4 Canonical draft marking + `status: draft-requires-counsel-review`. **It does not go to the
tester until AC13's counsel review happens.** It is drafted now and sent later; that ordering is the
whole point of the behavioural control.
3B.5 **No register row anywhere.** #4330 item iv governs: not `tenant-dpa-register.md`;
`customer-dpa-register.md` is created **on counter-signature**, not pre-emptively. AC3 asserts it.

### Phase 4 — Runbook

4.1 Retitle Step 2 to cover the terms; inline the Tier 1 paragraph into the existing welcome template
so the operator copies from the runbook, never from the legal file. **No renumbering.**
4.2 Replace the "Known gap" section with the **operating rule**: the machine/key/purpose one-liner and
the four Posture B triggers, **with trigger 2 marked as having fired on 2026-08-06**.
4.2b **The behavioural control, stated as a hard gate:** *do not run Soleur agents against tester
content under a Jikigai Anthropic key until the Art. 28(3) instrument is counsel-reviewed and
countersigned.* Use the tester's own key, or do not run it. This is what closes Posture B forward and
what makes deferring the counsel spend legitimate; it is asserted by **AC14**.
4.2c **Collaborator access — state the rule honestly, including the exception.** The runbook can no
longer carry *"do not accept collaborator access on a tester's repository"* as the house rule, because
the house is not following it. State the standing rule (**prefer non-personal aggregates — commit and
file counts — or a tester-supplied `git log --stat`; do not take repository content access for
metrics**), then record the **tester #1 exception** and where it is papered (LIA + PA-35). A rule the
runbook itself violates in its only worked example teaches the exception, not the rule.
4.2d State that when a future tester makes an instrument unavoidable, that is when the single counsel
review is bought — once, reusable across all ten testers.
4.3 Add a **`Terms`** column to the recruitment tally (`agreed` / `not-required`), updated at Step 1.
4.4 Add the offboarding line: at alpha end, collaborator access revoked, local clones and retained
feedback artifacts deleted, written confirmation within 30 days.
4.5 Record the **tester #1 position** — onboarding began 2026-08-06, so Tier 1 is sent retroactively
and the tally row is filled. **Plus the remediation message (3.2b)**, which is specific to tester #1
and does not become a runbook template step for testers 2–10 — under 4.2b they will not need one.
4.6 Correct the **Measurability caveat** table: the *"requires collaborator access"* cell is the live
Posture C activity, so it must cross-reference PA-35 and the LIA rather than reading as a neutral
implementation note.

### Phase 5 — Records

5.1 `compliance-posture.md`: add a `#7331` Active Items row.
5.2 Rewrite the `statutory-response-catalog.md` DSAR section's **fifth requester class** — not as an
Art. 28(3)(e) forwarding path (this plan's own determination forecloses that duty) but as the honest
response: *Jikigai holds nothing, is neither controller nor processor for it, will not confirm or deny
whether a third party does, and the Art. 12(3) clock is the controller's.* Add it as a bullet under
the existing step 3; **do not add a new anchor** — `:225-228` couples any `catalogAnchor`/`ruleId`
change to `apps/web-platform/lib/email-triage/statutory-rules.ts` in the same PR.
5.3 Action the fired Anthropic trigger (`anthropic.md`, §"Re-evaluate when"): record the
Zero-Retention status or why it remains unsigned, and the 30-day retention consequence — **now
including tester content**, with the ~2026-09-05 expiry for the 2026-08-06 session. Add the
operator-assisted surface to `register_activity_refs` and to the "Activities in scope" list, and
**confirm the Jikigai Anthropic account is on Commercial Terms** — §C does not auto-incorporate on
Consumer ToS, and the whole Art. 28(4) analysis rests on that. **Signing the Zero-Retention
amendment is the cheapest of the five remediation steps** and removes the retention limb outright.
5.4 Roadmap: add row **4.12** (`wg-every-feature-listed-in-a-roadmap-phase`).
5.5 Update the validation record's "Known gap" to resolved.
5.6 Add a Terms link to `plugins/soleur/README.md`.

### Phase 6 — Filings

6.1 File the dated issue for **tester #1 assent and the Tier 2 counsel review** — no longer
conditional, because the instrument is being drafted. **Due date in the title**, no `follow-through`
label, no probe (the hook denies it and the PASS condition is vacuous at merge).
6.2 File the pre-existing defects listed in Research Reconciliation, as a batch, checking #736 first
(it is CLOSED). **Two additions from the inversion:** **(a)** DPD §2.1 **limb (d)** is inaccurate as
an unconditional statement now an operator-assisted mode exists — it needs a scoped qualifier at next
amendment, and the same narrowness affects T&C §4.2 and `privacy-policy.md` §4.1; **(b)** the Art. 30
register's §0 membership predicate keys on infrastructure location, which is the #7100 defect
recurring — filed even though Phase 2.4 fixes the instance, because the *class* fix (audit every
membership predicate in the corpus for host-keying) is larger than this PR.
6.3 File the **#1442 metric re-derivation** as a deferred issue: replace repository-content reading
with non-personal aggregates (commit/file/directory counts), which would remove PA-35 from Art. 4(1)
scope almost entirely. Recorded as the standing de-escalation, not actioned here — the operator has
elected Option 2 and this plan executes it (`wg-when-deferring-a-capability-create-a`).

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — The determination exists under `knowledge-base/legal/audits/`, states the three postures
  with Art. 4(7)/4(8)/28 reasoning, gives the machine/key/purpose test, enumerates the four Posture B
  triggers **with trigger 2 marked FIRED (2026-08-06)**, cites the Phase 0.2 empirical evidence with
  its scope caveat, and carries the **"A crossing trigger HAS fired"** section naming the
  Art. 30(2)(a)–(d) limbs. Present **whichever way the verdict falls**.
- **AC1b** — The determination carries, in this order and without softening either: the **scope
  formulation** (what DPD §2.1 still covers, what it does not, and that limb (d) is inaccurate as an
  unconditional statement); the **dual-purpose analysis** with **both** residual uncertainties stated
  unresolved; and the **corrected Art. 28(4)** position (inchoate, not breached; the live defects are
  Art. 28(2), the absent instrument, and the 30-day retention). **Negative check:** the determination
  does **not** contain a sentence asserting that the published DPD position is falsified, retracted,
  or wrong — and does **not** contain one asserting it answers the operator-assisted case. Both
  directions are failure modes; grep the draft for each.
- **AC2** — No personal data in any committed artifact. The tally carries company name only; a grep
  for an `@`-bearing address across the changed `knowledge-base/` files returns nothing but
  `legal@jikigai.com`. *(The only irreversible risk in this PR.)*
- **AC3** — `git diff origin/main --name-only` adds **no file under `docs/legal/`**, and
  `git diff origin/main -- knowledge-base/legal/tenant-dpa-register.md` is **empty**. One assertion
  guards both the #4330 SOC 2 chain and the §6.1 30-day clock.
- **AC4** — `git diff origin/main -- apps/web-platform/lib/legal/tc-version.ts` is **empty** — the
  T&Cs were not amended, so no global re-acceptance is forced.
- **AC5** — *(unconditional — Option 2 was chosen)* `article-30-register.md` carries **PA-34** (the
  dogfooding limb of the 2026-08-06 session) **and PA-35** (the ongoing #1442 collaborator-access
  observation) in the `| Art. 30(1) limb | Entry |` shape, both recording Jikigai as **controller**,
  both reusing the register's existing RCS token; with a matching LIA on disk whose **necessity limb
  names the declined less-intrusive alternative**, and an Art. 14 line in the welcome template.
- **AC5b** — `knowledge-base/legal/article-30-2-register.md` exists as a **separate file**, records
  the processor limb of the 2026-08-06 session against the Art. 30(2)(a)–(d) limbs, and is
  cross-linked from §0 of the 30(1) register. If it carries an `RCS <City>` token it is enrolled in
  `legal-doc-consistency.test.ts`'s explicit site list; if it carries none, that is recorded as
  deliberate.
- **AC5c** — The 30(1) register's §0 "In-scope surfaces" predicate **no longer keys on infrastructure
  location**. Assert on the rewritten predicate's content, not on the absence of a token: grep that
  the paragraph contains a purpose-or-credentials formulation, and that PA-34 and PA-35 are reachable
  by it. *(A bare-absence grep cannot distinguish a fixed predicate from a deleted one — the AC6/AC10
  defect class from the 2026-08-06 overshoot learning.)*
- **AC6** — The runbook's Step 2 carries the Tier 1 terms inline; the recruitment tally has a `Terms`
  column with tester #1's row filled. **Assert the positive replacement, not substring absence:** the
  `## Known gap` section is *replaced by* the operating rule (the machine/key/purpose one-liner, the
  four Posture B triggers, and the 4.2b behavioural control) and the offboarding line is present — a
  bare `grep -c 'Known gap' == 0` cannot distinguish "replaced" from "deleted", the same defect AC5c
  and AC15 guard against. **Step headings still number 1–6** — no renumber.
- **AC7** — The Tier 1 paste-block is ≤ 90 words, first-person, contains no occurrence of "Plugin",
  and is physically fenced from the DRAFT marking.
- **AC8** — `git diff origin/main -- apps/web-platform/lib/email-triage/statutory-rules.ts` is
  **empty** (no catalog anchor added, so no coupling fires), and the new requester class does **not**
  describe an Art. 28(3)(e) duty.
- **AC1c** — **The Tier 2 instrument exists as a PR artifact** (Phase 3B):
  `knowledge-base/legal/<date>-alpha-tester-processing-annex.md` is present, scoped to
  **operator-assisted runs only**, **names Anthropic as an authorised sub-processor**, is effective
  **forward** with a recital acknowledging the 2026-08-06 session, and carries the canonical draft
  marking. AC13 gates *sending* it; this AC gates its *existence*, which nothing else asserted.
- **AC9b** — **Phase 5.3 is done:** `anthropic.md`'s fired *"Re-evaluate when"* trigger is actioned in
  the file itself — the Zero-Retention status recorded (signed, or why still unsigned), the 30-day
  retention consequence stated, and the **Commercial (not Consumer) Terms** confirmation captured.
  That confirmation is the premise the whole corrected Art. 28(4) analysis rests on, so it cannot be
  left implicit.
- **AC9c** — **Retroactive-remediation step 4 landed:** an internal note records the dual purpose, the
  egress, and the **~2026-09-05 retention expiry** (2026-08-06 + Anthropic's 30-day window). Steps
  1/2/3/5 map to 0.7 / 4.2b / 3B / 5.3; step 4 previously mapped to no task and no AC.
- **AC9** — `compliance-posture.md` has a `#7331` row; `roadmap.md` has row **4.12**; the dated issue
  from Phase 6.1 exists with its due date **in the title** and **without** the `follow-through` label.
- **AC10** — Every `knowledge-base/` path cited in the **shipped artifacts** (not this plan) resolves:
  extract with `grep -ohE 'knowledge-base/[A-Za-z0-9/_.-]+\.md'`, test each with `[[ -f ]]`.
- **AC11** — `/soleur:gdpr-gate` has run; Critical findings are resolved or carry an
  operator-acknowledged `compliance/critical` issue. PR body uses `Closes #7331`.
- **AC14** — The runbook carries the **behavioural control** (4.2b) as a hard gate: no Jikigai-keyed
  runs against tester content until the instrument is countersigned. This is the criterion that makes
  the deferred counsel spend defensible, so it is asserted on the runbook's text, not assumed.
- **AC15** — **The withdrawn lead does not ship.** No Tier 1 artifact, runbook welcome template, or
  remediation message asserts that Jikigai cannot see the tester's repository or that the session ran
  on the tester's key. Assert the **negation form**, not substring absence: every match for
  `your key|your machine|can'?t see|do not have access` across the changed tester-facing text is
  either absent or scoped to the Plugin in the same sentence. *(Per the learning: an absence-grep
  cannot distinguish an assertion from a negation, and this plan legitimately discusses the withdrawn
  sentence — exclude planning artifacts from the check's own scope.)*
- **AC16** — The Phase 3.2b remediation message exists, is **separate** from the Tier 1 paste-block,
  and states the Anthropic transit and the dual purpose. It asserts nothing about personal data that
  Phase 0.7 did not establish.
- **AC17** — **Every new legal artifact carries the canonical marking.** Enumerate the files this PR
  adds under `knowledge-base/legal/` and assert each has the marking verbatim as an opening and
  closing blockquote **and** frontmatter `status: draft-requires-counsel-review`: the determination,
  the LIA, `article-30-2-register.md`, and the Tier 2 processing annex. The new 30(2) register is the
  one most likely to be missed — it is a register rather than a memo, and the register it sits beside
  already carries the marking, so the omission would not look like one. **Counterpart check:** no
  marking appears inside any block intended for a counterparty (Tier 1 paste-block, remediation
  message) — the marking is a corpus-internal control (AC7 covers Tier 1; extend it to 3.2b).

### Post-merge (operator / counterparty)

- **AC12** — Tester #1 replies confirming the Tier 1 terms.
  `Automation: not feasible because` the missing input is **another person's assent**, which no tooling
  can supply. This is not one of the canonical operator-only categories (a)–(d) in
  `2026-05-15-operator-only-step-canonical-list.md`, but it satisfies that learning's controlling
  principle — *"the boundary is possession … not availability of tooling."* Everything either side of
  it is automated: the notice is drafted and inlined into the runbook template, and the tally column is
  ready for the status. Tracked by the Phase 6.1 dated issue.
- **AC13** — *(Tier 2 is now drafted in this PR; this gates it being **sent**)* one-time counsel
  review of the liability cap and confidentiality undertaking before it reaches any tester. The
  instrument ships to `knowledge-base/` as a marked draft at $0; AC14's behavioural control is what
  holds the line until this is bought. Before budgeting, establish whether the marketplace offers a
  **data-protection-advice** SKU — the two SKUs in `recommended-tools.md` are contract-scan products
  and the listed **USD** figures are not a quote for this work.
  `Automation: not feasible because` this is the purchase of a professional legal opinion — a
  commercial engagement, not a browser workflow, so no `playwright-attempt` line applies.

## Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Posture C ships unaddressed** — the operator keeps reading a private third-party repo for Jikigai's own metrics with no lawful basis. No longer *the only* violation in scope, and no longer optional. | Phase 0.6 is RESOLVED (Option 2); Phase 2 executes unconditionally; AC5 asserts PA-34 + PA-35 + the LIA. A DPA would not have cured it (Art. 28(10)). Standing de-escalation recorded at Phase 6.3. |
| R1b | **Posture B recurs** — a second Jikigai-keyed session runs before the instrument exists, converting a one-off gap into a pattern, which is what defeats the Art. 30(5) "occasional" reading and the good-faith framing together. | The Phase 4.2b behavioural control, asserted by **AC14**. This is the single load-bearing mitigation in the plan: every argument for deferring the counsel spend depends on it holding. |
| R2 | A row in `tenant-dpa-register.md` starts the §6.1 30-day clock and invalidates its empty baseline; a file under `docs/legal/` fires the #4330 chain including **SOC 2 within 90 days**. | Neither happens. AC3 asserts both by diff. |
| R3 | **The correction overshoots** — the determination is written as though the published position were falsified, contradicting five published sentences across two documents and both mirrors that remain true within their scope. The exact failure documented in `2026-08-06-my-correction-overshot-into-a-new-wrong-claim-in-a-compliance-artifact.md`: *"a correction inherits none of the original claim's scrutiny."* | The determination **confirms §2.1 within its scope** and records the limb (d) finding separately. **AC1b's negative check greps for overshoot in both directions.** The published sentences are not amended here; the finding is filed (6.2a). |
| R3b | **The correction undershoots** — "it's all still published and fine" is carried forward and the materialised gap is minimised into a footnote. Symmetric to R3 and likelier, because it requires changing less. | Trigger 2 is marked **FIRED** inline in the trigger list rather than in a footnote; `## Retroactive remediation` is a top-level section with five numbered steps; AC1/AC1b/AC16 assert them. |
| R4 | Amending the T&Cs forces **every existing user** to re-accept and closes live WebSocket sessions. | Tier 1 incorporates by reference. AC4 asserts `tc-version.ts` is untouched. |
| R5 | The DRAFT banner reaches a tester inside the welcome email. | Paste-block fenced from the marking; the runbook shows the final text so the operator never copies from the legal file. AC7 checks it. |
| R6 | **Tier 1 scoped to exclude tester #1**, leaving issue AC1 unmet — Skouer qualifies for Tier 2, so a Tier-1-only-for-others design covers nobody who exists. | Tier 1 is unconditional; Tier 2 is an addition, never a substitution. AC6 requires tester #1's tally row filled. |
| R7 | **Tier 2 is a deliverable of this PR (Phase 3B)**, so this risk is live, not hypothetical: copying Schedule 4's TOMs would publish Art. 32 measures describing infrastructure that does not serve this relationship — the defect the repo publicly retracted in #6588, this time inside an executed instrument. | The template's clause-level defects are enumerated in Reconciliation so the drafter starts from them. Counsel review is AC13. |
| R8 | The PA-34 / PA-35 ordinals collide with a sibling PR. | **Two** consecutive ordinals re-derived at Phase 0.3 and anchored on the heading form, not a bare token. |
| R9 | **A tester-facing document ships without counsel review because Tier 2 felt cheap to draft.** Sharper now: Tier 2 **is** a deliverable of this PR, so the artifact will exist, marked draft, one copy-paste away from an email. | AC13 gates **sending**, AC14 gates the activity the instrument covers, and 3B.4 requires the canonical draft marking. The Phase 3 fencing rule (paste-blocks physically separated from markings) applies to the instrument too — it is the artifact most likely to be copied wholesale. |
| R10 | **PA-34 repeats the #7100 defect.** `article-30-register.md` §0 *"In-scope surfaces"* enumerates the register's in-scope surfaces (Web Platform, docs site, `jikig-ai/soleur`, `jikig-ai/operator-digest`) and carries its own post-mortem: the list *"previously named `jikig-ai/soleur` alone, which is why a Jikigai-keyed Anthropic egress in a sibling repository fell outside every membership predicate."* Feedback artifacts arriving by operator email, Discord, or an encrypted drive fall outside all four — **and so does an operator-run, Jikigai-keyed session, because the same paragraph excludes the locally-installed plugin on an "on Jikigai infrastructure" test whose both conjuncts are now false.** | **Phase 2.4** rewrites the predicate to key on **purposes or credentials, regardless of host** — not another surface appended to the list, which is what was done for #7100 and left the defect in place. **AC5c** asserts the rewritten predicate's content. This is the defect's **third** occurrence; 6.2(b) files the corpus-wide class fix. |
| R11 | **The ship Phase 5.5 CLO-attestation gate silently skips.** It fires on `legal_touch` AND (`sui_threshold` OR `draft_marker`), where the draft-marker grep is the literal `^\+.*\[DRAFT — pending CLO/counsel review` — which the corpus's house marking does **not** match. | This plan declares `brand_survival_threshold: single-user incident`, so `sui_threshold` carries it. Pin that deliberately at ship rather than relying on the marker arm, and confirm the gate actually fired on three brand-new legal artifacts. |
| R12 | **Staging any `knowledge-base/**/*.md` re-runs `scripts/generate-kb-index.sh` and force-stages `INDEX.md`**, which is badly stale (`INDEX.md:4` says 3773 files against a live ~7436) — bundling thousands of lines of unrelated drift into a legal PR. | Apply the recorded remedy (`2026-06-04-kb-index-regen-bundles-stale-drift-prefer-surgical-edit.md`): edit the `## legal` section surgically and `git checkout` the rest of `INDEX.md`. |
| R13 | `legal-doc-consistency.test.ts` loads `article-30-register.md` as an RCS-jurisdiction site and asserts `tokens.size === 1`. A PA-34 controller-identification limb naming any registry other than the existing one reds CI. | Reuse the register's existing RCS token verbatim in PA-34. |
| R14 | **The withdrawn Tier 1 lead ships anyway** — *"it runs on your machine, on your key — I can't see your repo"* is warm, quotable, already drafted into two artifacts, and false in both halves for tester #1. It is exactly the sentence a copywriter agent would keep. | Withdrawn explicitly and with reasons in the CMO constraints, in Phase 3.2, and in `tasks.md` 3.2 — three places, because deleting it in one leaves it in the others. **AC15** asserts the **negation form**, not substring absence, and excludes planning artifacts from its own scope. |
| R15 | **The #4330 SOC 2 chain is fired by misreading "we now need a DPA."** The highest-cost error available, and the inversion makes it newly reachable. | The Overview states the chain's three actual triggers verbatim and that none has fired; 3B.1 scopes the instrument to operator-assisted mode; 3B.5 forbids any register row; **AC3** asserts by diff that nothing lands under `docs/legal/` and `tenant-dpa-register.md` is untouched. |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| ~~**Build the `if processor` branch** — DPA, execution register, Art. 30(2) register, signature probe, deferred issue.~~ **SUPERSEDED 2026-08-06.** | ~~The plan's own determination proves the antecedent false.~~ **The antecedent is true — trigger 2 fired on 2026-08-06.** The branch is **partially restored**, artifact by artifact, at [What the inversion restores](#what-the-inversion-restores-and-what-stays-cut). Restoring it *as a block* is rejected for the same reason cutting it as a block was wrong: the five artifacts have different justifications, and two (the `tenant-dpa-register.md` row, the signature probe) stay cut on grounds the inversion does not touch. |
| **Build the whole `if processor` branch as the issue framed it** — a DPA covering personal data in the tester's repository. | Still wrong, and the distinction is the point. Plugin-local processing on the tester's machine under the tester's key is still **not** Jikigai processing. An instrument covering it would assert a relationship that does not exist and contradict a published position that remains true. The restored instrument covers **operator-assisted runs only**. |
| **A springing annex, signed now, dormant until a trigger.** | Rejected on inverted reasoning, and worth recording because the *conclusion* survived while the *reason* did not. Previously: it springs immediately and buys nothing. Now: **there is nothing left to spring** — the trigger has fired and the processing has occurred, so what is needed is an instrument **effective forward with a recital acknowledging the past run** (3B.2), not a contingent one. A springing instrument would also misdescribe the timeline in its own operative clause. |
| **Backdate the instrument to 2026-08-05 so the session is covered.** | It would be false, and it would be false in a document whose entire value is that a regulator can rely on it. Art. 28(3) is not satisfied by a contract that did not exist when the processing happened. **Ratification evidences good faith; it does not cure retroactively** — which is why 3B.2 uses a recital and says so out loud. |
| **Enroll a follow-through probe to chase the countersignature.** | The runbook already ruled on this exact shape — *"the work here is a conversation, which has no exit-code probe"* — and `follow-through-directive-gate.sh` denies it. The PASS condition ("no row pending") is also **vacuous at merge**, when no row exists: it would close the tracker with nothing signed. |
| **A new `alpha-tester-agreement-register.md`.** | Would be the repo's **fourth** register; the existing two hold zero rows between them after three months and both grew guards that assert vacuously. #4330(iv) already names the successor (`customer-dpa-register.md`) and says create it **on counter-signature**. A column on the existing tally is the whole requirement. |
| ~~**An empty Art. 30(2) register with an explanatory header.**~~ **MOOT 2026-08-06.** | The original objection was sound — writing the reason not to create a file *inside* the file is the tell — but its premise is gone: **processing was carried out**, so the register will not be empty. Phase 2.5 creates it as a real record in a **separate file**. |
| **A "Part B" for Art. 30(2) inside the existing 30(1) register.** | The limb sets differ (30(2) has no purposes, no data-subject categories, no retention), and the file is titled and scoped *"in its capacity as **data controller**"* throughout. One file meaning two things is the exact ambiguity #7100 punished. Separate file, cross-linked from §0. |
| **Add one more surface to the register's in-scope list**, as was done for #7100. | It would make PA-34/PA-35 reachable and leave the defect intact for the fourth occurrence. The predicate keys on *infrastructure location*; the fix is to re-key it on **purposes or credentials** (Phase 2.4). |
| **Renumber the runbook to insert a new Step 2.** | Step 2 already *is* the welcome message, and the Known-gap text's "between Steps 1 and 2" is satisfied by the top of Step 2. Renumbering rots four internal self-references for no gain. |
| **Add a C4 feedback-channel edge.** | Duplicates `betaContact -> founder` between the same two elements, distinguished only by label. PA-34 records the flow authoritatively. |
| **Amend the T&Cs to carry alpha terms.** | A Tier 1 change bumps `TC_VERSION`, forcing every existing user to re-accept and closing live sessions. |
| **Reuse `side-letter-template.md`.** | *"Jikigai is not a party"*; and it assigns IP to the Owner. Reusing it means gutting it. |
| **Procure an e-signature service.** | Art. 28(9) is met by a countersigned PDF by email; R2 `cla-evidence` (WORM, 10-year, $0.00) already exists. |
| **Absorb the pre-existing defects into this diff.** | `wg-when-an-audit-identifies-pre-existing` says file them. One consistent policy — all filed at Phase 6.2, none absorbed. |
