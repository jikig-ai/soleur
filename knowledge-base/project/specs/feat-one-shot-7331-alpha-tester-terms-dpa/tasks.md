# Tasks — feat-one-shot-7331-alpha-tester-terms-dpa

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
Mirrors the ack in the plan and spec. No task here provisions infrastructure: each writes markdown
under knowledge-base/, edits an operations runbook, or files a GitHub issue. The two human-performed
steps recorded (a counterparty countersignature, a law-firm review) are counterparty and
professional-services acts, unautomatable by nature rather than omission.
-->

Plan: `knowledge-base/project/plans/2026-08-06-legal-alpha-tester-terms-and-processor-posture-plan.md`
Spec: `knowledge-base/project/specs/feat-one-shot-7331-alpha-tester-terms-dpa/spec.md`
Issue: #7331 · Lane: cross-domain · Threshold: single-user incident

**Standing constraint on every task:** no third-party personal data in any committed file. The tester
is `Skouer` / `https://github.com/2my8r9ry2t-wq/Skouer` — company name and repository URL only, never
a person's name or email. Committed third-party PII is an Art. 17 erasure impossibility.

**Anchor every edit on headings and quoted content, never bare line numbers**
(`cq-cite-content-anchor-not-line-number`).

## Phase 0 — Preconditions (must run first)

> **0.1 and 0.6 were BLOCKING and are now RESOLVED** — the operator answered both on 2026-08-06 and
> the answers **invert the plan's primary branch**. They are recorded below as established fact, not
> as open questions. The plan body's `### Phase 0 — Preconditions` section carries the same seven
> ordinals (0.1, 0.6, 0.2–0.5, 0.7); the two files had drifted (the plan was missing 0.1 entirely and
> its ordinals were shifted by one) and are now reconciled. **Phases 1 and 2 were reconciled in the
> same pass** — `tasks.md` ordinals now match the plan's, so a plan-side reference like R10's
> "Phase 2.4" resolves to the same task in both files.

- [x] 0.1 **RESOLVED 2026-08-06 — the answer inverts the plan.** The 2026-08-06 guided-onboarding
      session ran on the **operator's machine** under **JIKIGAI's Anthropic API key**, against tester
      content, at the tester's request. That is a verbatim instance of **Posture B trigger 2**. So
      Posture B has **already fired, retroactively**, and the Art. 28(3) instrument the plan requires
      *before* such a run did not exist. This is a materialised gap, not a contingency. Anthropic is
      **Jikigai's** sub-processor for that egress, not the tester's.
- [x] 0.6 **RESOLVED 2026-08-06 — UC-1 Option 2 (retain and paper).** The operator keeps collaborator
      access and papers it. **Phase 2 executes** (it is no longer conditional). Posture C is live and
      ongoing. See `decision-challenges.md` §UC-1 Resolution.
- [x] 0.2 Re-run the `plugins/soleur/` outbound-host and telemetry scan; record commands and output
      verbatim for the determination to cite. **Scope note (new):** this scan establishes what the
      *plugin* does on the *tester's* machine. It says nothing about the 0.1 configuration, where the
      operator ran the plugin himself under a Jikigai key — do not let a clean scan be cited as
      evidence about that run.
- [x] 0.3 Re-derive the next free Art. 30 ordinal against `origin/main`
      (`grep -n "^## Processing Activity" knowledge-base/legal/article-30-register.md | tail -3`).
      Two records are now needed, not one — see Phase 2. Reserve consecutive ordinals.
- [x] 0.4 Note that **#736 is CLOSED** (title: *"legal: update Terms & Conditions for web platform
      cloud services"*), while `compliance-posture.md` still records it as `OPEN` under the subject
      "T&C blanket statement contradictions". The row is stale on both status and subject — the T&C
      contradictions found here are **untracked**, so file them fresh rather than assuming prior art.
- [x] 0.5 Confirm `docs/legal/data-processing-agreement.md` still does not exist. *(Verified absent
      2026-08-06.)* It stays absent: restoring the Tier 2 instrument does **not** publish anything,
      and therefore does **not** fire the #4330 chain — see the closing paragraph of the plan's
      `## Overview`.
- [x] 0.7 **NEW, and the one remaining factual gate.** Establish what the 2026-08-06 session actually
      touched: did any **personal data** enter the operator's machine or egress to Anthropic under the
      Jikigai key, or was it confined to the tester's own code and configuration? Art. 28 bites only
      on personal data, so this scopes the entire retroactive remediation. Sources the operator can
      reconstruct from: his own shell/session history for that date, the tester's repo tree as it
      stood then, and whether the venture database (founders, investors) was opened at all. **If it
      cannot be reconstructed, record that** — and treat the presence of personal data as assumed for
      remediation purposes, since the repository is known to contain it. Do not resolve this by
      asserting a convenient answer.

## Phase 1 — The determination (blocks everything)

- [x] 1.1 Invoke `soleur:legal:clo` to author
      `knowledge-base/legal/audits/<date>-alpha-tester-controller-processor-determination.md` in the
      `2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md` format.
- [x] 1.1a Content: three postures; the *whose machine / whose key / whose purpose* test; the four
      Posture B triggers verbatim from the plan; the Posture C finding; Phase 0.2 evidence; why the
      beta-CRM LIA does not cover this; the role-collision note (Jikigai already processes Skouer's
      own data via PA-30).
- [x] 1.1b Cite ADR-093, ADR-099, ADR-119, ADR-075, ADR-102. Scope every non-receipt sentence to the
      CLI surface **in the sentence itself**.
- [x] 1.2 Retitle and rewrite that section as **"A crossing trigger HAS fired"**: the
      Art. 30(2)(a)–(d) limbs (now pointing at the real record from 2.5, not standing in for it), the
      record that the "before processing begins" rule was **not** met on 2026-08-06, the PA-17
      amendment obligation and its #4558 re-evaluation trigger, and the **substrate-readiness
      precondition** (ADR-119 plaintext ext4; ADR-075 bwrap-only isolation with an accepted
      undetectable residual). Keep the prospective guidance for triggers 1, 3 and 4, which have not
      fired.
- [x] 1.3 Carry the **scope formulation verbatim** from the plan's Overview — what DPD §2.1 still
      covers, what it does not, and the **limb (d)** finding. State it once, precisely; let the rest
      of the document cite it. This is the sentence most likely to be misquoted in either direction.
- [x] 1.4 Record the **dual-purpose analysis**: processor for the tester-instructed limb, controller
      for the dogfooding limb, Art. 28(10) scoped *"in respect of that processing"* — the excess, not
      the instructed part. Carry **both residual uncertainties unresolved**: (a) the two purposes were
      served by one indivisible set of operations, and a regulator could hold that inextricability
      makes it controllership for the whole run; (b) if the dogfooding observations concerned only
      workflow mechanics, that limb may barely be personal-data processing — but the operator
      *consulted* output containing it, and consultation is processing.
- [x] 1.5 **Correct the Art. 28(4) analysis.** The plan's prior claim ("`anthropic.md` does not
      discharge Art. 28(4)") was **overruled** — it conflated Jikigai's internal memo with Anthropic's
      actual DPA, which auto-incorporates via Commercial Terms §C and carries Art. 28(3) terms, DPF,
      SCCs M2+3, IDTA. **Art. 28(4) is inchoate, not breached: there is no tester contract to mirror
      downward.** The live defects are **Art. 28(2)** (no sub-processor authorisation, no notice), the
      absent instrument, and the 30-day retention now attaching to tester content. Two caveats:
      confirm the account is on **Commercial** (not Consumer) Terms, and note Art. 28(4)'s "fully
      liable" limb attaches to Jikigai regardless.
- [x] 1.6 Canonical marking verbatim as a blockquote, opening and closing; frontmatter
      `status: draft-requires-counsel-review`.
- [x] 1.7 **Write the determination whichever way the verdict falls.** It is now doing more work, not
      less: a negative finding on any limb still has to be recorded, because the alternative is
      re-litigating all of this at tester #3.

## Phase 2 — Close Posture C and record Posture B **(executes — UC-1 Option 2 chosen 2026-08-06)**

- [x] 2.00 **Marking applies to every artifact in this phase:** canonical marking verbatim as an
      opening and closing blockquote + frontmatter `status: draft-requires-counsel-review`, on the LIA
      (2.1) and on the **new** `article-30-2-register.md` (2.5). PA-34 (2.2) and PA-35 (2.3) inherit the 30(1)
      register's existing marking; the new file has none to inherit. Asserted by **AC17**.
- [x] 2.0 The LIA's Art. 6(1)(f) **necessity** limb must state that a less intrusive means exists and
      was considered and declined — a tester-supplied `git log --stat` buys the same single metric.
      Option 2 was chosen on measurement fidelity, not because Option 1 was unavailable. An LIA that
      omits the rejected alternative fails the balancing test it claims to perform.
- [x] 2.1 LIA at `knowledge-base/legal/legitimate-interest-assessments/<date>-alpha-tester-repo-observation-lia.md`,
      modelled on `2026-07-07-beta-crm-lia.md`.
- [x] 2.2 Add **PA-34** to `article-30-register.md` in the existing `| Art. 30(1) limb | Entry |`
      shape, Jikigai as controller — the **dogfooding limb of the 2026-08-06 guided session**. Reuse
      the register's existing RCS token verbatim (`legal-doc-consistency.test.ts` asserts a single RCS
      token across four sites).
- [x] 2.3 Add **PA-35** — the **ongoing #1442 collaborator-access observation**. A separate activity
      from PA-34: continuous rather than session-bound. Collapsing the two would leave the live
      activity described by a record whose scope is a single past event.
- [x] 2.4 **Rewrite** `article-30-register.md` §0's in-scope predicate. It currently excludes *"the
      locally-installed Soleur Claude Code plugin … it processes no personal data **on Jikigai
      infrastructure** and Jikigai is not a controller for it"* — **both conjuncts are now false**. Do
      **not** append one more surface: that is what was done for #7100 and it left the defect in
      place. Re-key on **who determines purposes, or whose credentials effect the processing,
      regardless of host.** This is the #7100 defect's **third** occurrence.
- [x] 2.5a **Check `legal-doc-consistency.test.ts` BEFORE writing 2.5.** It loads an **explicit site
      list** naming `article-30-register.md` by path, so the new file will not fail CI — and will not
      be guarded either. If the 30(2) register carries an `RCS <City>` token, enrol it in that list;
      if it carries none, record that as deliberate.
- [x] 2.5 Create **`knowledge-base/legal/article-30-2-register.md`** — the Art. 30(2) **processor**
      record for the instructed limb of the 2026-08-06 session. **Separate file, not a "Part B"**: the
      limb sets differ (no purposes, no data-subject categories, no retention), the 30(1) file is
      titled and scoped to controller capacity, and one file meaning two things is the ambiguity
      #7100 punished. Cross-link from §0 and from the determination. **Art. 30(5) is not relied on** —
      *"not occasional"* is read narrowly and operator-assisted onboarding is designed to repeat.
- [x] 2.6 Art. 14 notice line claiming Art. 14(5)(b) disproportionate effort **in writing**. Note the
      adjacency: same Art. 14-to-unreachable-third-parties shape as **#7120**, whose clock expired.
      Do not create a second one silently.

## Phase 3 — Tier 1 alpha notice (all testers, including #1)

- [~] 3.1 **Deliverable exists; prescribed agent NOT used.** The Tier 1 substance was drafted
      inline rather than via `legal-document-generator`. Recorded as a deviation rather than
      marked done — the paragraph is in the runbook and meets 3.3-3.5, but the plan named an
      agent and it did not run.
      (not `/soleur:legal-generate`, whose Phase 0/1 use `AskUserQuestion` and hang headless).
- [~] 3.2 **Deliverable meets the constraints; prescribed agent NOT used.** Paste-block is 90
      words, first-person, no occurrence of "Plugin", withdrawn lead blocked — but rendered
      inline rather than via `soleur:marketing:copywriter`. Same deviation as 3.1.
      merged into the existing "One note on record-keeping" paragraph. No defined terms, no section
      numbers, no "shall", and **never the word "Plugin"**.
      **The prescribed lead is withdrawn.** It read: *"it runs on your machine, on your key — I can't
      see your repo."* Under the Phase 0.1 and 0.6 answers **both halves are false for tester #1** —
      the 2026-08-06 session ran on the operator's machine on Jikigai's key, and the operator holds
      collaborator access and can see the repo. Shipping that sentence would put an affirmatively
      false statement in writing to the counterparty, about the exact subject in dispute, in the one
      document meant to fix the problem. The CMO constraint it came from (*lead with what Soleur
      owes*) still holds — but what Soleur owes is now **candour about access**, not a reassurance of
      no-access. Lead instead with what is true and reassuring: the tool runs locally and Jikigai
      operates no server that reaches their code; where Jikigai *does* have access it is access the
      tester granted, for a stated purpose, revocable at a word.
      **Verify before drafting:** `docs/legal/privacy-policy.md` §4.1 carries *"We do not have access
      to your files, your code, or your usage patterns."* It is scoped by its own closing sentence
      (*"This section applies to the Plugin only"*) — §4.1 has four bullets **including** that
      sentence, and one of the other three is about local storage rather than transmission, so lean on
      the closing-sentence scoping rather than a bullet count. It is not falsified by collaborator
      access, which is not a Plugin capability. But it is the sentence a tester will quote back. Tier 1 must not contradict it and
      must not repeat it as though it were a promise about Jikigai's conduct generally.
- [x] 3.3 Content: Terms link; confidentiality owed by Jikigai over the private repo; end-of-alpha
      disposition; no fee, no obligation, stop anytime; redact third-party personal data before
      sending logs, with Jikigai's undertaking to delete unredacted material on notice.
- [x] 3.4 Ask for a one-line reply as assent evidence.
- [x] 3.5 Physically fence the paste-block from the DRAFT marking so the banner cannot be copied into
      a welcome email. Applies to the Phase 3B instrument too — it is the artifact most likely to be
      copied wholesale.
- [x] 3.6 **Draft the retroactive-remediation message — SEPARATE from Tier 1.** ~5 sentences, plain
      language, no defined terms, **no apology theatre**. Two facts: their content transited Jikigai's
      Anthropic account under a **30-day retention window** (~2026-09-05 expiry for the 2026-08-06
      session), and the session **also served Jikigai's own improvement purpose**. It rides alongside
      Tier 1 to tester #1, never inside it — a ≤90-word warm welcome would either blow its budget or
      bury the disclosure. **Gate on 0.7:** assert nothing about personal data that 0.7 did not
      establish.

## Phase 3B — Tier 2 Art. 28(3) instrument (RESTORED, re-scoped)

- [x] 3B.1 Draft `knowledge-base/legal/<date>-alpha-tester-processing-annex.md` covering
      **operator-run sessions against tester content under a Jikigai credential — and nothing else.**
      **Not** a DPA for repo data at rest on the tester's machine: that relationship still does not
      exist, and an instrument asserting it would contradict a published position that remains true.
- [x] 3B.2 **Name Anthropic as an authorised sub-processor** (Art. 28(2)); **effective forward**; with
      a **recital acknowledging the 2026-08-06 session**. State in the instrument that ratification
      evidences good faith and **does not cure retroactively**. Do **not** backdate it.
- [x] 3B.3 Draft from the template's genuinely good parts only — **§7.2 verbatim** (2-business-day ack
      / 10-business-day SLA) and **§10 (audit)** near-verbatim. **Never Schedule 4's 17 TOMs** (they
      describe RLS/Supabase/WORM/R2 — the #6588 defect), and never the Schedule 2 BYOK row unamended
      (it would tell the tester "Anthropic is YOUR sub-processor", false in Posture B).
- [x] 3B.4 Canonical draft marking + `status: draft-requires-counsel-review`. **It does not go to the
      tester until AC13's counsel review.** Drafted now, sent later — that ordering is the point.
- [x] 3B.5 **No register row anywhere.** #4330 item iv: not `tenant-dpa-register.md`;
      `customer-dpa-register.md` is created **on counter-signature**, not pre-emptively.

## Phase 4 — Runbook

- [x] 4.1 Retitle Step 2 to cover the terms; inline the Tier 1 paragraph into the existing welcome
      template so the operator copies from the runbook, never from the legal file. **No renumbering.**
- [x] 4.2 Replace the "Known gap" section with the operating rule: the machine/key/purpose one-liner
      and the four Posture B triggers, **with trigger 2 marked FIRED (2026-08-06)**.
- [x] 4.2b **Behavioural control, as a hard gate:** *do not run Soleur agents against tester content
      under a Jikigai Anthropic key until the Art. 28(3) instrument is counsel-reviewed and
      countersigned.* Use the tester's own key, or do not run it. This closes Posture B forward and is
      what makes deferring the counsel spend legitimate rather than negligent. Asserted by **AC14**.
- [x] 4.2c **Collaborator access — state the rule with its exception.** The runbook can no longer say
      *"do not accept collaborator access"* as the house rule, because the house is not following it.
      State the standing rule (**prefer non-personal aggregates — commit and file counts — or a
      tester-supplied `git log --stat`; do not take repository-content access for metrics**), then
      record the **tester #1 exception** and where it is papered (LIA + PA-35). A rule the runbook
      violates in its only worked example teaches the exception, not the rule.
- [x] 4.2d Record that when a future tester makes an instrument unavoidable, that is when the single
      counsel review is bought — once, reusable across all ten testers.
- [x] 4.3 Add a `Terms` column to the recruitment tally (`agreed` / `not-required`), updated at Step 1.
- [x] 4.4 Add the offboarding line: at alpha end, access revoked, clones and retained feedback
      artifacts deleted, written confirmation within 30 days.
- [x] 4.5 Fill tester #1's tally row and record that Tier 1 is sent retroactively, **plus the 3.6
      remediation message** — specific to tester #1, and **not** a template step for testers 2–10,
      who will not need one under 4.2b.
- [x] 4.6 Correct the **Measurability caveat** table: the *"requires collaborator access"* cell is the
      live Posture C activity and must cross-reference PA-35 and the LIA, rather than reading as a
      neutral implementation note.

## Phase 5 — Records

- [x] 5.1 Add a `#7331` row to `compliance-posture.md` Active Items.
- [ ] 5.2 Rewrite the statutory catalog's fifth requester class as the *neither-controller-nor-processor*
      response — **not** an Art. 28(3)(e) duty, which the determination forecloses. Add it inside the
      existing step-3 **prose paragraph** (it is not a bullet list). Add **no new anchor**; keep all
      five H2 headings byte-identical (`statutory-rules.ts` deep-links four of them).
- [x] 5.3 Action the fired Anthropic re-evaluation trigger (`anthropic.md`, §"Re-evaluate when"):
      record the Zero-Retention status or why it remains unsigned, and the 30-day retention effect —
      **now reaching tester content**, with the **~2026-09-05** expiry for the 2026-08-06 session. Add
      the operator-assisted surface to `register_activity_refs` and "Activities in scope". **Confirm
      the Jikigai Anthropic account is on Commercial Terms** — §C does not auto-incorporate on
      Consumer ToS, and the whole Art. 28(4) analysis rests on it. **Signing the Zero-Retention
      amendment is the cheapest remediation step available** and removes the retention limb outright.
- [x] 5.3b **Retroactive-remediation step 4 — the internal note.** Record the dual purpose of the
      2026-08-06 session, the egress under the Jikigai key, and the **~2026-09-05 retention expiry**
      (2026-08-06 + Anthropic's default 30-day window), after which the Anthropic-side copy lapses. A
      fact to write down, not a deadline to chase. Asserted by **AC9c** — this step previously mapped
      to no task and no AC.
- [x] 5.4 Add roadmap row **4.12**.
- [x] 5.5 Update the validation record's "Known gap" to resolved.
- [x] 5.6 Add a Terms link to `plugins/soleur/README.md`.

## Phase 6 — Filings and hygiene

- [x] 6.1 File the dated issue for tester #1 assent **and the Tier 2 counsel review** — no longer
      conditional, since the instrument is drafted in this PR. Due date **in the title**, no
      `follow-through` label, no probe.
- [x] 6.2 File the pre-existing defects as a batch: `tenant-provisioning.md` pipe-count gate;
      `tenant-dpa-register.md` guard that can never fire; `tenant-offboarding.md` broken path and
      missing alpha-tester exit path; DPA template §10.3 SOC 2 contradiction; AUP mirror divergence;
      DPD mirror missing §2.3(ad) with a dangling cross-reference; PA-30 recorded in the wrong shape;
      stale `compliance-posture.md` T&C row; roadmap 4.1 status contradiction. Check #736 first
      (it is CLOSED). **Two additions from the inversion:** (a) DPD §2.1 **limb (d)** is inaccurate as
      an unconditional statement now an operator-assisted mode exists, and the same narrowness affects
      T&C §4.2 and `privacy-policy.md` §4.1 — each needs a scoped qualifier at next amendment;
      (b) the Art. 30 register's §0 predicate keys on infrastructure location — the corpus-wide class
      fix (audit **every** membership predicate for host-keying) is larger than this PR.
- [x] 6.3 File the **#1442 metric re-derivation** as a deferred issue: replace repository-content
      reading with non-personal aggregates (commit/file/directory counts), which would take PA-35 out
      of Art. 4(1) scope almost entirely. The standing de-escalation — recorded, not actioned, because
      the operator elected Option 2 (`wg-when-deferring-a-capability-create-a`).
- [ ] 6.4 `INDEX.md`: edit the `## legal` section surgically and `git checkout` the rest.

## Phase 7 — Verification

- [ ] 7.1 Run `/soleur:gdpr-gate` against the plan and the shipped artifacts.
- [ ] 7.2 Verify **AC1–AC16** from the plan (the revision added AC1b, AC5b, AC5c, AC14, AC15, AC16).
      AC2 (no personal data) is the only irreversible one — run it over the full
      `git diff origin/main --name-only` set, not one file.
- [ ] 7.2b **AC15 explicitly, because it is the easiest to skip.** The withdrawn Tier 1 lead must not
      ship. Assert the **negation form**, not substring absence: every match for
      `your key|your machine|can'?t see|do not have access` in changed **tester-facing** text is
      either absent or scoped to the Plugin in the same sentence. **Exclude the planning artifacts** —
      this plan, spec and tasks file all quote the withdrawn sentence in order to withdraw it, and a
      naive grep matches its own prohibition (the documented AC10 defect class).
- [ ] 7.2c **AC1b's two-directional check.** Grep the determination for sentences asserting the
      published DPD position is *falsified/retracted/wrong*, **and** for sentences asserting it
      *answers* the operator-assisted case. Both are failure modes; a pass requires neither.
- [ ] 7.3 Confirm the ship Phase 5.5 CLO-attestation gate actually fires (it matches a literal
      `[DRAFT — pending CLO/counsel review` marker the house marking does not carry; the
      `single-user incident` threshold is what should carry it).
- [ ] 7.4 Emit the resume prompt (`wg-end-of-work-emit-resume-prompt`).
