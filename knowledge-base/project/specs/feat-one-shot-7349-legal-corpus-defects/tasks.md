# Tasks — legal-corpus defects (#7349)

Derived from `knowledge-base/project/plans/2026-08-10-legal-corpus-defects-7349-plan.md`.
Lane: `cross-domain`. Threshold: `single-user incident` (CPO sign-off required).

**Standing rule for every phase:** a write-time gate firing is signal to satisfy it. No arm
toggle, no `BODY_EQUIVALENCE_DOCS` removal, no `--base` widening, no baseline regeneration used
to launder a failure. The only legitimate baseline write is Phase 6's refresh, which *lowers*
frozen drift.

## Phase 0 — Preconditions (no edits)

- [ ] 0.1 Run all three gates on the clean tree; record exit codes.
      `bash scripts/lint-legal-scope-block-placement.sh --base origin/main`
      `bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main`
      `bash apps/web-platform/scripts/check-tc-document-sha.sh`
- [ ] 0.2 `sha256sum docs/legal/*.md` — record as the before-picture for every SHA refresh.
- [ ] 0.3 Re-derive the DPD §2.3 item sets with the plan's `extract()` command. Expect canonical 29,
      mirror 23, missing `(p)(w)(x)(y)(z)(ad)`.
- [ ] 0.4 Re-derive the dangling `2.3(x)` set per surface. Expect canonical 0; mirror `(ad)`×1,
      `(p)`×2, `(w)`×3, `(x)`×3, `(y)`×1.
- [ ] 0.5 Re-measure per-pair drift for all nine pairs. Expect total 220. **Also classify the
      CHARACTER of the deferred set, not just the counts (CPO C3)** — `privacy-policy` (58) is
      marked "substantive" with no description; CLAs and `cookie-policy` are unclassified. If
      `privacy-policy` carries an under-disclosure of the same class as `gdpr-policy`'s Art. 6(1)
      bullets, the scope split changes and must change before Phase 3.
- [ ] 0.6 **If any number disagrees with the plan, STOP and correct the plan before editing.**
      The plan's numbers are claims, not permissions.
- [ ] 0.7 **The six CLO rulings are MADE and recorded in the plan's Domain Review** — SOC 2
      position, PA-30 disposition, AUP §4.6 wording, DPD port scope, E1–E9 directions, and the
      Tier 1 / `2.5.0` classification, each with drafted replacement wording. Read them before
      editing; do not re-derive or re-author legal wording the CLO already settled.
- [ ] 0.8 **Three first-draft claims are FALSE — do not "fix" them:** E2's T&C↔DPD forum conflict
      (the DPD has no forum clause), E8's dangling AUP→T&C cross-reference (all resolve), and
      E8's mandatory-vs-optional side letter (two distinct instruments). Confirm each measurement
      yourself before touching those clauses.
- [ ] 0.9 CLO **merge sign-off is NOT yet granted** — it must be written against the actual diff at
      `knowledge-base/legal/audits/2026-08-counsel-review-7349.md`. That is a Phase 5 deliverable
      (5.13), not a precondition.

## Phase 1 — Guards that cannot fire (A1–A4)

- [ ] 1.1 **RED:** write a test that plants a signed row in `knowledge-base/legal/tenant-dpa-register.md`
      and asserts the guard fires; and a second arm asserting it does NOT fire once removed.
      Both arms required — a guard that always fires passes a one-arm test.
- [ ] 1.2 **RED:** write a test asserting the guard reaches a non-empty input, distinguishable from
      an empty-input run. (Per #7387: detection ≠ reachability.)
- [ ] 1.3 **GREEN:** reconcile the guard predicate and the status vocabulary to one form. Decide
      which form is canonical; do not make the grep match the prose by accident.
- [ ] 1.4 Fix the same `status: `-prefixed form in the register's prose.
- [ ] 1.5 **RED:** test that `tenant-provisioning.md`'s gate does not report the populated-state
      verdict against the current empty register.
- [ ] 1.6 **GREEN:** make the gate fail closed on the empty register. Do not reuse `grep -c '^|'`
      — it counts the table header, the separator, and the `| _(none yet)_ |` placeholder, which
      is why the current gate reads 3 on an empty set.
- [ ] 1.7 Reconcile `aborted-provisioning` with `aborted-provisioning-at-step-N`.
- [ ] 1.8 Correct `apps/web-platform/scripts/seed-live-verify-user.sh` `TC_VERSION` to the canonical
      value, **then** add it to `SEED_SCRIPTS` in `check-tc-document-sha.sh`. Order matters —
      adding it while drifted turns a required check red.
- [ ] 1.9 Add a `MIN_ASSERTIONS` floor to each guard suite, derived from a green run of the
      **current** suite. A floor, never an equality.

## Phase 2 — Stale records and register shape (B1–B4)

- [ ] 2.1 **The no-commitment position governs** (CLO ruling 1). The DPA template's **§10.3 stays
      unchanged** — it is the operative clause. Replace the 90-day form at the other three sites
      (the DPA commitments table, the DPA's "commitment in §10.3" reference, and
      `knowledge-base/legal/compliance-posture.md`) with an evaluation-plus-12-month-status-update
      form. The alpha-tester annex already agrees — leave it. Rationale: a summary table cannot
      create an obligation the operative clause negates; `security-sentinel` already forced this
      recast away from date-certain on §12.2(b) contract-formation grounds; and #4330 is CLOSED so
      it cannot make anything live.
- [ ] 2.2 Replace the struck-through `#736` row in `compliance-posture.md` with a row naming the
      T&C enumeration artifact by path.
- [ ] 2.3 Add a version column to `compliance-posture.md`'s document inventory and populate it;
      refresh the stale Last-Updated values (T&C, AUP, Cookie Policy, Disclaimer, both CLAs).
- [ ] 2.4 Correct `knowledge-base/product/roadmap.md` row 4.1 to **"In progress — 1 of 10"**
      (verified: #1439 OPEN, tester #1 onboarded 2026-08-06, mix 1 CC / 0 non-CC against a
      `≥3 of 10 non-CC` requirement).
- [ ] 2.4b **CPO C4** — either sync the `## Current State` milestone counts to the live API
      (Phase 4: 89/206; Post-MVP: 1003/1549 — the roadmap says 710/1283, a 293-issue drift) or
      leave the section's date untouched. Never refresh the date over stale counts.
- [ ] 2.5 🔴 **RE-CHARACTERISE PA-30 IN PLACE — the re-home is overruled (CLO ruling 2).** Amend
      its role sentence in `knowledge-base/legal/article-30-register.md`: Jikigai is controller
      today because it is the only store owner; the roles flip on the first arms-length store
      owner, at which point an Art. 28(3) instrument is owed before processing.
      **Do NOT move the record.** Art. 30(2) requires naming a controller other than the
      processor; it carries no purposes/data-subject/personal-data/retention/DSAR limbs, so a
      re-home silently drops six of PA-30's limbs and gate 2 passes it. And
      `apps/web-platform/supabase/migrations/126_beta_crm.sql` cites PA-30 twice in a migration
      **already applied to production** — its body cannot be edited, only superseded.
- [ ] 2.6 Add a `P-2` **reservation stub** to `knowledge-base/legal/article-30-2-register.md`
      §Register maintenance, recording it as reserved for the first arms-length store owner.
- [ ] 2.7 Sweep every PA-30 referrer (the role sentence changed even though the location did not):
      `article-30-register.md` (the record, PA-32's lawful-basis cell, Register-Maintenance item
      9); `legitimate-interest-assessments/2026-07-07-beta-crm-lia.md` ×3 — including
      *"full list in PA-30 §(g)"*; `.../2026-07-31-claude-eval-fleet-and-ci-lia.md` ×3;
      `compliance-posture.md` ×3; `server/tool-tiers.ts`, `server/dsar-export-allowlist.ts`,
      `server/dsar-export.ts`; `migrations/126_beta_crm.sql`; DPD §2.3(ad) + mirror;
      `gdpr-policy.md` §3.13 + mirror. **Carve out** `audits/2026-07-counsel-review-6165.md` and
      `-6172.md` — point-in-time counsel records.

## Phase 3 — Published DPD under-disclosure (C2, C3)

Direction: canonical → mirror, verbatim, unless the CLO ruled otherwise for a given item.
Making the surfaces identical removes the drift-line pair and passes gate 2 as a reduction.
Never rewrite a drifting line into a third form on one side.

- [ ] 3.1 Port §2.3 items `(p) (w) (x) (y) (z) (ad)` into the mirror.
- [ ] 3.2 Port the two §4.2 sub-processor rows (LinkedIn Ireland, Microsoft Ireland).
- [ ] 3.3 Port the two Chapter V transfer bullets and the Art. 17 carve-out.
- [ ] 3.4 Port the four Art. 17 erasure-cascade limbs.
- [ ] 3.5 Restore §5.3 to the canonical text, **including** the `/dashboard/settings/privacy`
      self-serve export route (Art. 15/20 fulfilment path).
- [ ] 3.6 Restore the truncated §2.3(i) and the §2.3 roll-call entry for `(p)`.
- [ ] 3.6a 🔴 **§2.3(ad) must NOT be ported verbatim.** Task 2.5 changed its controller/processor
      characterisation. Restate the role sentence first, then publish — otherwise the notice tells
      users the "operator" is controller of a store whose only owner is Jikigai.
- [ ] 3.6b 🔴 **READ every scope block adjacent to an insertion point.** The DPD has a hard-wrapped
      scope block whose referent is *"The paragraph above"*. Inserting a restored §2.3 item above
      it silently re-points the referent at different text, and **both gates are blind** — the
      block's own line never changes. Verify by reading, not by gate. (AC39)
- [ ] 3.6c Re-verify each of `(p)(w)(x)(y)(z)(ad)` against the live implementation before
      publishing — especially `(z)` workspace-logo upload and `(w)` delegated-credential routing
      (`BYOK_DELEGATIONS_ENABLED`). A port is textually a copy but legally a first publication,
      and AC34 does not reach it. (AC40)
- [ ] 3.7 Re-run the dangling-cross-reference check; expect zero on **both** surfaces.
- [ ] 3.8 Re-run gate 2; expect a strict reduction, never `CONTENT CHANGED`.

## Phase 3b — GDPR Policy lawful-basis carve-back (CPO C3)

- [ ] 3b.1 Port the canonical-only Art. 6(1) lawful-basis bullets into the published
      `gdpr-policy` mirror as a **lockstep two-surface** addition (same technique as 2.7).
- [ ] 3b.2 Do NOT attempt the remaining ~60 `gdpr-policy` drift lines, and do NOT add the document
      to `BODY_EQUIVALENCE_DOCS`. Both belong to the successor issue — including the hard-wrapped
      scope block that trips gate 1 arm (c).

## Phase 4 — Published AUP under-disclosure (C1), disclaimer, and the 404 (C4)

- [ ] 4.1 Apply the CLO's §4.6 rulings. The consent-only clause is the one where neither surface is
      right — the published text drops "or another lawful basis under applicable law", narrowing
      the user's position below the statutory floor. New text, both surfaces.
- [ ] 4.2 Restore the canonical cross-reference to §4.2 rather than the mirror's paraphrase.
- [ ] 4.3 Land the CLO's decision on the mirror-only share-link-revocation sentence and the
      canonical-only workspace-logo paragraph: each on both surfaces or neither.
- [ ] 4.4 Reconcile the changelog abridgement (port the fuller canonical changelog to the mirror;
      both substantive disclosures already survive in the section bodies, but AC19 forces
      convergence).
- [ ] 4.4a 🔴 **Execute E9 HERE, not in Phase 5.** The AUP mirror renders `{{ stats.agents }}`
      through Eleventy and the canonical cannot, so the two surfaces can never reach zero
      normalised drift while any count sits in that sentence. **E9 is a precondition of AC19, and
      AC19 is a precondition of the Phase 6 `BODY_EQUIVALENCE_DOCS` activation.** Left in Phase 5
      the ordering deadlocks and turns a required check red. Use soft floors (AC37).
- [ ] 4.5 Resync `disclaimer` (2 cosmetic drift lines — one autolinked email address).
- [ ] 4.5a 🔴 **CLO E1b/E1c** — correct `disclaimer.md` §3.2's false "provided free of charge"
      premise (the Web Platform sells Stripe subscriptions per T&C §5) and delete §3.1's
      unqualified **direct-damages** exclusion, leaving direct damages subject to the §3.2 cap.
      An unqualified direct-damages exclusion against an EU consumer risks the whole limitation
      clause under Directive 93/13 Annex 1(b). (AC41)
- [ ] 4.6 Point `apps/web-platform/lib/messages/trust-tier-copy.ts` at the served URL. No
      `/docs/legal/` path may remain in user-facing copy.
- [ ] 4.7 Refresh `LEGAL_DOC_SHAS` for every canonical changed in Phases 3–4.

## Phase 5 — T&C contradictions (E1–E9) and the version bump

Sequenced last: it depends on the counterparty documents being settled. The T&C mirror is at
**zero** drift, so every edit must be exactly lockstep or gate 2 fails immediately.

- [ ] 5.1 Write the enumeration artifact under `knowledge-base/legal/` recording all nine
      contradictions **and** the six ambiguities, each with both sides quoted by content anchor and
      the resolution taken. This is the durable record the `#736` row falsely appeared to be.
- [ ] 5.2 Fix E1 (liability cap) **with** `docs/legal/disclaimer.md` in the same commit. The T&C
      governs — it is the instrument with an acceptance record; the Disclaimer has none.
- [ ] 5.3 🔴 **E2 is half not real.** Measured: the DPD has **no** governing-law and **no** forum
      clause; T&C §15 and `disclaimer.md` §8 both say France / Paris and **agree**. Do not "fix" a
      forum conflict. **Fix only the surviving half:** §16.1 is a bare entire-agreement clause with
      no order of precedence, so E1's genuine conflict has no resolution rule. Add a precedence
      paragraph to §16.1.
- [ ] 5.4 Fix E3 (unscoped plugin-local absolutes, T&C §§4.1/4.2/8.1) using the CLO's drafted scope
      blocks. **Gate-1 constraint:** the negative delimiter must sit on the SAME LINE as the scope
      assertion, and the declared referent must be no larger than the genuinely plugin-local text.
- [ ] 5.5 Fix E4 (missing Anthropic + four processors in §8.1b).
- [ ] 5.6 🔴 **E5's direction was backwards.** T&C §3b.1 *agrees* with the DPD (both make the
      Workspace Owner controller) and `compliance-posture.md` already adjudicated it as "no
      contradiction" — editing `gdpr-policy.md` would fix the wrong document. **The real
      contradiction is intra-T&C:** §3b.1's "**all** personal data" vs §3b.2's Arts. 15–22 rights
      **against Jikigai** (rights that run against a controller). Narrow §3b.1 to workspace
      content and workspace-activity records, and keep Jikigai controller of Co-Member account
      data, subscription records, and Art. 5(2) audit logs.
- [ ] 5.7 Fix E6 (processor status asserted in present tense) **with** the DPD.
- [ ] 5.8 Fix E7 (share links described as processor capacity).
- [ ] 5.9 🔴 **E8 — fix ONE limb, not three.** (a) The "dangling AUP §5.6 cross-reference" does
      **not exist**: every T&C section referenced anywhere in the corpus resolves (measured).
      (b) "Mandatory vs optional" is **two different instruments** — AUP §5.6 mandates the
      *Delegation Consent Side Letter*, explicitly "distinct from the workspace co-member Side
      Letter in Section 5.5", which §3b.4 makes optional. Both correct. **Do not touch either.**
      (c) **REAL:** BYOK joint vs sole controllership — cured by the 5.6 redraft plus an Art. 26
      joint-controller paragraph in §3b.1, which also cures a *substantively* dangling reference
      (AUP §5.6 points at §3b for delegation, and §3b currently says nothing about it).
- [ ] 5.10 Fix E9 across the T&C and Privacy Policy (the **AUP** half already landed at 4.4a as an
      AC19 precondition). Measured today: **68** agent files, **95** skills, **9** domains vs
      "45 / 45 / five". **Remove the counts; do not restate them.** Soft floors per AC37 — the
      live site renders exact counts from the filesystem, so an exact count in a versioned legal
      instrument is stale by construction and buys a Tier-2 bump every release.
- [ ] 5.11 Mirror every T&C edit exactly.
- [ ] 5.12 **Tier 1 → `TC_VERSION` 2.4.0 → 2.5.0 (MINOR)** per CLO ruling 6. MAJOR is reserved for
      changes expected to cause abandonment ("new license restriction, new jurisdiction") —
      neither occurs, and every substantive change is neutral-to-favourable to the user. Update in
      lockstep — `TC_DOCUMENT_SHA`, all four `TC_BUMP_METADATA` fields, the canonical Last-Updated
      line, the mirror's Last-Updated line, **all three** seed scripts, and the
      `compliance-posture.md` version row.
- [ ] 5.13 Record the tier and its reasoning in the PR body. **CLO sign-off gates merge and must
      be written against the actual diff** at `knowledge-base/legal/audits/2026-08-counsel-review-7349.md`,
      with a per-artifact verdict and a DISCHARGED/BLOCKED disposition. Flag **E6**
      (T&C-as-Art.-28(3)-instrument) in that audit's frontmatter as the strongest external-counsel
      re-review candidate.
- [ ] 5.14 **M1 (CPO C2)** — reset the alpha-tester roster's `Terms` column and re-send the
      corrected paragraph to every tester at `agreed` or `sent-awaiting-reply`; add that as a
      standing step in `knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md`.
      The bump cannot reach a self-hosted CLI tester, so without this the cohort gets no notice.
- [ ] 5.15 **M2 (CPO C2)** — write `TC_BUMP_METADATA.substantiveChange` in plain outcome language.
      It renders verbatim into the Art. 13(3) banner on `/accept-terms`; no clause names, no
      jargon. Consistency is AC24; comprehensibility is AC36.

## Phase 6 — Coverage, ratchet, successor tracking (D1, D2)

- [ ] 6.1 Add the non-tenant alpha-tester case to `tenant-offboarding.md` — prefer a cross-link to
      the runbook that owns the procedure over a duplicate (a second copy is the mirror-divergence
      defect class, reintroduced in the runbooks), but state the case explicitly so it does not
      read as uncovered.
- [ ] 6.2 Sweep the 7 live `engineering/ops/` files enumerated in plan §D2. **Carve out** the
      `2026-06-03-path-rename-sweep-exclude-own-migration-artifacts.md` learning, plans, specs and
      archives.
- [ ] 6.3 Add `acceptable-use-policy`, `data-protection-disclosure` and `disclaimer` to
      `BODY_EQUIVALENCE_DOCS` — **after** each reports zero drift, never before.
- [ ] 6.4 Refresh the gate-2 baseline; assert total frozen drift is strictly below 220.
- [ ] 6.5 File the successor issue for the deferred set (`gdpr-policy` **remaining ~60 after the
      Phase 3b carve-back**, `privacy-policy` 58, `corporate-cla` 12, `individual-cla` 7,
      `cookie-policy` 4) with the measured table, **each document's character classification**,
      a note that `gdpr-policy` is partially remediated here, and the 2026-09-30 target.
- [ ] 6.6 Re-point gate 2's header and runtime output from `#7349` to the successor issue, and
      update the pinned assertion in `scripts/lint-legal-mirror-drift-baseline.test.sh` **in the
      same commit**.
- [ ] 6.7 Update the shared gate-discoverability block in `plugins/soleur/skills/legal-audit/SKILL.md`,
      `plugins/soleur/skills/legal-generate/SKILL.md` and `plugins/soleur/agents/legal/clo.md`.

## Phase 7 — Verification

- [ ] 7.1 Run every gate by **its own invocation**, not a reconstruction of its input set.
- [ ] 7.2 `bash scripts/test-all.sh`.
- [ ] 7.3 Walk each cross-document contradiction commit and assert both region markers are present
      in that commit's diff. **Do not use `git log -- A B`** — it is a union filter and cannot
      distinguish a paired commit from a one-sided one.
- [ ] 7.4 Read the diff of every gate script and confirm no gate was weakened (AC33).
- [ ] 7.5 Confirm every claim the PR **adds** to a legal document traces to a named source line or
      a CLO ruling in the enumeration artifact (AC34). Absence-greps alone can all pass while an
      added claim is false.
