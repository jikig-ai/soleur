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

- [ ] 0.1 **BLOCKING.** Establish the actual configuration of the 2026-08-06 session: whose machine
      ran the agents, **whose Anthropic key** paid for them, and whether operator collaborator access
      is held right now and since when. The validation record says the operator ran onboarding
      personally and names no key. If the key was Jikigai's, the primary branch changes — Posture B
      applies and Anthropic becomes a Jikigai sub-processor.
- [ ] 0.2 Re-run the `plugins/soleur/` outbound-host and telemetry scan; record commands and output
      verbatim for the determination to cite.
- [ ] 0.3 Re-derive the next free Art. 30 ordinal against `origin/main`
      (`grep -n "^## Processing Activity" knowledge-base/legal/article-30-register.md | tail -3`).
- [ ] 0.4 Note that **#736 is CLOSED** (title: *"legal: update Terms & Conditions for web platform
      cloud services"*), while `compliance-posture.md` still records it as `OPEN` under the subject
      "T&C blanket statement contradictions". The row is stale on both status and subject — the T&C
      contradictions found here are **untracked**, so file them fresh rather than assuming prior art.
- [ ] 0.5 Confirm `docs/legal/data-processing-agreement.md` still does not exist.
- [ ] 0.6 Surface the UC-1 open decision from `decision-challenges.md`. Phase 2 is **skipped** under
      Option 1 (revoke access) and **executed** under Option 2 (retain and paper).

## Phase 1 — The determination (blocks everything)

- [ ] 1.1 Invoke `soleur:legal:clo` to author
      `knowledge-base/legal/audits/<date>-alpha-tester-controller-processor-determination.md` in the
      `2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md` format.
- [ ] 1.2 Content: three postures; the *whose machine / whose key / whose purpose* test; the four
      Posture B triggers verbatim from the plan; the Posture C finding; Phase 0.2 evidence; why the
      beta-CRM LIA does not cover this; the role-collision note (Jikigai already processes Skouer's
      own data via PA-30).
- [ ] 1.3 Cite ADR-093, ADR-099, ADR-119, ADR-075, ADR-102. Scope every non-receipt sentence to the
      CLI surface **in the sentence itself**.
- [ ] 1.4 Add the **"If a crossing trigger fires"** section: the Art. 30(2)(a)–(d) limbs, the PA-17
      amendment obligation and its #4558 re-evaluation trigger, and the **substrate-readiness
      precondition** (ADR-119 plaintext ext4; ADR-075 bwrap-only isolation with an accepted
      undetectable residual).
- [ ] 1.5 Canonical marking verbatim as a blockquote, opening and closing; frontmatter
      `status: draft-requires-counsel-review`.

## Phase 2 — Close Posture C *(skipped under UC-1 Option 1)*

- [ ] 2.1 LIA at `knowledge-base/legal/legitimate-interest-assessments/<date>-alpha-tester-repo-observation-lia.md`,
      modelled on `2026-07-07-beta-crm-lia.md`.
- [ ] 2.2 Add **PA-34** to `article-30-register.md` in the existing `| Art. 30(1) limb | Entry |`
      shape, Jikigai as controller. Reuse the register's existing RCS token verbatim
      (`legal-doc-consistency.test.ts` asserts a single RCS token across four sites).
- [ ] 2.3 Amend `article-30-register.md`'s in-scope surface list so PA-34 is reachable by a
      membership predicate — otherwise it repeats the #7100 defect the same line documents.
- [ ] 2.4 Art. 14 notice line claiming Art. 14(5)(b) disproportionate effort **in writing**.

## Phase 3 — Tier 1 alpha notice (all testers, including #1)

- [ ] 3.1 Draft the substance via the `legal-document-generator` agent invoked **directly via Task**
      (not `/soleur:legal-generate`, whose Phase 0/1 use `AskUserQuestion` and hang headless).
- [ ] 3.2 Render the paste-block via `soleur:marketing:copywriter`: ≤90 words, first-person singular,
      merged into the existing "One note on record-keeping" paragraph, leading with what Soleur owes
      ("it runs on your machine, on your key — I can't see your repo"). No defined terms, no section
      numbers, no "shall", and **never the word "Plugin"**.
- [ ] 3.3 Content: Terms link; confidentiality owed by Jikigai over the private repo; end-of-alpha
      disposition; no fee, no obligation, stop anytime; redact third-party personal data before
      sending logs, with Jikigai's undertaking to delete unredacted material on notice.
- [ ] 3.4 Ask for a one-line reply as assent evidence.
- [ ] 3.5 Physically fence the paste-block from the DRAFT marking so the banner cannot be copied into
      a welcome email.

## Phase 4 — Runbook

- [ ] 4.1 Retitle Step 2 to cover the terms; inline the Tier 1 paragraph into the existing welcome
      template so the operator copies from the runbook, never from the legal file. **No renumbering.**
- [ ] 4.2 Replace the "Known gap" section with the operating rule: the machine/key/purpose one-liner,
      the four Posture B triggers, and — under Option 1 — do not accept collaborator access.
- [ ] 4.3 Add a `Terms` column to the recruitment tally (`agreed` / `not-required`), updated at Step 1.
- [ ] 4.4 Add the offboarding line: at alpha end, access revoked, clones and retained feedback
      artifacts deleted, written confirmation within 30 days.
- [ ] 4.5 Fill tester #1's tally row and record that Tier 1 is sent retroactively.

## Phase 5 — Records

- [ ] 5.1 Add a `#7331` row to `compliance-posture.md` Active Items.
- [ ] 5.2 Rewrite the statutory catalog's fifth requester class as the *neither-controller-nor-processor*
      response — **not** an Art. 28(3)(e) duty, which the determination forecloses. Add it inside the
      existing step-3 **prose paragraph** (it is not a bullet list). Add **no new anchor**; keep all
      five H2 headings byte-identical (`statutory-rules.ts` deep-links four of them).
- [ ] 5.3 Action the fired Anthropic re-evaluation trigger (`anthropic.md`, §"Re-evaluate when"):
      record the Zero-Retention status or why it remains unsigned, and the 30-day retention effect.
- [ ] 5.4 Add roadmap row **4.12**.
- [ ] 5.5 Update the validation record's "Known gap" to resolved.
- [ ] 5.6 Add a Terms link to `plugins/soleur/README.md`.

## Phase 6 — Filings and hygiene

- [ ] 6.1 File the dated issue for tester #1 assent (and counsel review if Tier 2 ever proceeds) —
      due date **in the title**, no `follow-through` label, no probe.
- [ ] 6.2 File the pre-existing defects as a batch: `tenant-provisioning.md` pipe-count gate;
      `tenant-dpa-register.md` guard that can never fire; `tenant-offboarding.md` broken path and
      missing alpha-tester exit path; DPA template §10.3 SOC 2 contradiction; AUP mirror divergence;
      DPD mirror missing §2.3(ad) with a dangling cross-reference; PA-30 recorded in the wrong shape;
      stale `compliance-posture.md` T&C row; roadmap 4.1 status contradiction. Check #736 first.
- [ ] 6.3 `INDEX.md`: edit the `## legal` section surgically and `git checkout` the rest.

## Phase 7 — Verification

- [ ] 7.1 Run `/soleur:gdpr-gate` against the plan and the shipped artifacts.
- [ ] 7.2 Verify AC1–AC11 from the plan. AC2 (no personal data) is the only irreversible one — run it
      over the full `git diff origin/main --name-only` set, not one file.
- [ ] 7.3 Confirm the ship Phase 5.5 CLO-attestation gate actually fires (it matches a literal
      `[DRAFT — pending CLO/counsel review` marker the house marking does not carry; the
      `single-user incident` threshold is what should carry it).
- [ ] 7.4 Emit the resume prompt (`wg-end-of-work-emit-resume-prompt`).
