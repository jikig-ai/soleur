# Plan Review — consolidated decision challenges

Plan: `knowledge-base/project/plans/2026-08-09-chore-legal-operator-assisted-scope-sentences-plan.md`
Panel: dhh-rails-reviewer · kieran-rails-reviewer · code-simplicity-reviewer · architecture-strategist · spec-flow-analyzer · cpo (named-panel, advisory)
Date: 2026-08-09

**Heading question (N1), which the plan explicitly deferred to this review: 6-0 KEEP `### 2.1c Operator-Assisted Processing`.** §2 *is* the relationship classification; `### 2.1b` already exists so nothing renumbers (verified at canonical:63 / mirror:72); 20+ prose sites need a citable anchor. Caveat from spec-flow: no markdown-it-anchor plugin is registered in `eleventy.config.js`, so the published `<h3>` carries no `id` — the heading is citable as TEXT but not deep-linkable. The pointer must therefore name the document in words, not rely on a `#` fragment.

---

## MECHANICAL — auto-apply (correctness; one right answer)

### M1. Strike the "§3.1(b)/(d) remain literally true" justification and the AC-8b certification. **[independently verified]**
§3.4 asserts DPD §3.1(b) *"No data is transmitted to Soleur-operated servers"* and (d) *"does not establish network connections to Soleur-controlled endpoints"* are literally true. **They are not.** `plugins/soleur/skills/trigger-cron/scripts/trigger.sh` — shipped inside the Plugin — POSTs to `https://app.soleur.ai/api/internal/trigger-cron` (`ROUTE_URL` at line 15; `curl -X POST` at 144-145). Verified directly, not taken from the agent report.

The *cut* survives: those limbs key on the **infrastructure** limb, which operator-assisted runs genuinely do not engage, so attaching D3's pointer to §3.1(a) alone remains structurally correct (architecture-strategist concurs). What must go is the claim of truth. AC-8b would otherwise have a **Tier-1 CLO attestation affirmatively certify a sentence this same plan calls false twelve pages later** — the frontmatter learning reproducing itself inside the fix for it.

- Reword §3.4 and AC-8b to: "not the limb this configuration breaks; falsified separately and tracked."
- File a distinct issue for the pre-existing `trigger.sh` falsification (`wg-when-an-audit-identifies-pre-existing`). Do NOT fix it here — different claim class, different cause.
- Note for CLO: a defensible narrower form exists (*"no automatic or background egress; all egress is explicitly operator-invoked"*), and firing the script needs a Doppler-held secret no ordinary user has. But the published sentence is unqualified, and "practically unreachable" is not "does not exist."

### M2. Limb clauses must state the INSTRUMENT, never a unilateral promise. **[highest severity]**
Breach (24h, annex §8.1), audit (annual, 30 days' notice, annex §9.1) and DSAR service levels (2/10 business days, annex §6.2), plus N1's *"own machine and key at no charge"* (annex §5.4), are carried **only** by the alpha-tester annex — unexecuted, counsel-review-pending, agreed with one counterparty. `article-30-2-register.md` P-1 has no DSAR/breach/audit limb **by construction** (its own §"Why this is a separate file"); PA-34(h) carries only a controller-limb manual route marked *"No completeness guarantee."*

Publishing them converts a draft bilateral annex into a **universal unilateral public undertaking**. The plan reaches exactly this conclusion for annex §5.2/§5.3 in §7.3 and then fails to carry it to §5.4/§6/§8/§9.

- Every limb clause takes the form *"the written instrument agreed before such a session addresses X"* — never *"Jikigai will do X"*.
- No numeric SLA, no price term, no retention figure in published text.
- **AC-10 must assert the FORM, not merely the trace.**

### M3. The pointer must name its target document.
spec-flow: the cross-document chain does not resolve. A bare "Section 2.1c" reads as a LOCAL reference in `gdpr-policy.md` (which has its own `## 2` / `### 2.1` / `### 2.2`) and in `privacy-policy.md`, where it resolves to nothing. AC-2 only counts the pointer and AC-3 only requires it name an operator-assisted limb — **no AC requires it to identify which document holds the canonical definition.**
- Pointer names the document in words: "…described in the Data Protection Disclosure, Section 2.1c."
- Add an AC asserting cross-document resolution.

### M4. Two pointer registers, not one verbatim string.
DPD/GDPR are third-person legal ("the User", "Jikigai"); `privacy-policy.md` is second-person ("your machine", "we have no access"). One verbatim string is wrong-voiced at ~8 P sites and AC-2's exact-count grep passes anyway. Budget **two** variants (formal + plain-English).

### M5. Link form differs by surface — a verbatim port breaks one of them.
Canonical uses `privacy-policy.md`; the mirror uses `/legal/privacy-policy/` (verified at DPD mirror line 237). Phase 3.1 and AC-4 demand a **verbatim** port, so any doc-link either 404s on the published page or breaks canonical convention. Absent from §7.4. Specify a per-surface link transform; exclude link text from the verbatim-port assertion.

### M6. G10 — do NOT change "eleven" to "35".
`gdpr-policy.md:412` reads *"The register documents eleven processing activities:"* followed by an enumerated list of **exactly 11 items**. Changing the numeral leaves it contradicting the list directly beneath — a newly false published sentence manufactured inside an accuracy correction. Publishing the other 24 would narrate the incident, which §7.2 forbids. **De-numeralise ("the activities described below") or defer.** Convergent finding: architecture-strategist F1 + cpo.

### M7. Q3 settled — no PR refs in published legal text.
`knowledge-base/project/learnings/2026-05-12-public-legal-doc-annotations-no-pr-numbers.md` explicitly forbids perpetuating the style: *"reset to the canonical style — do not perpetuate."* The plan's symmetry argument misreads it — the learning's symmetry claim is entry-level (canonical vs mirror), not chain-level across history. Plain-English + `§N.M`. Note the plan's §3.3 quote of the precedent **elides `ref #7100`**, hiding that the precedent itself embeds a ref in body prose; property (iv) restates as "dated parenthetical, **date only, no ref**."

### M8. Missed sites — add four.
- **DPD preamble (CRITICAL):** before §1 — *"Because Soleur is not a data processor (see Section 2), this is not a Data Processing Agreement under Article 28"*. First substantive sentence, document-wide, cites the very section §2.1c contradicts. Absent from the 12 DPD sites and from AC-8's protected set.
- **`privacy-policy.md` §2 "Who We Are" (CRITICAL):** *"Jikigai is the data controller for the processing activities described in this Policy."* P3 says processor, two headings below.
- **`gdpr-policy.md` §2.1 ¶3:** closed three-item list *"Jikigai acts as a data controller for: (a)…(b)…(c)"* — operator-assisted adds a fourth limb. G1 covers ¶1-2 only.
- **DPD §4.2 preamble:** closed section list *"where Jikigai acts as Controller (see Sections 2.1b and 2.3)"* goes stale.

### M9. Cuts and narrowings (simplicity panel).
Cut **D4** (§3.2 preamble — subordinate clause, D3 lands six lines above), **P1** (PP §3 — P2/P3 carry it within a screenful), **P8** (PP §11 — infrastructure limb; see M1, out of scope here), **G9** (GDPR §9 — already conditionally scoped, same family as the deferred AUP §5.3). **Narrow G7** to bullets 1 and 4 (bullet 2 is the infrastructure limb) and give it an explicit attachment guard like D3's. **Fold D6 into D5** (both in §4, 35 lines apart). **Drop the retention limb clause** — the pointer already cures it (P6, G8). Justify limb clauses only where the text denies a legal DUTY (D7, D9, D10, G5) or denies a TRANSFER (D8, P7, G6).

### M10. AC-8 is unsatisfiable as written.
P2/P4 are *widenings* and G10 a correction, so `git diff | grep '^-'` will not yield only banner lines. It would be silently relaxed at implementation, taking the non-retraction guard with it. Specify widenings as pure appends, or scope AC-8's grep.

### M11. AC-12 misses a derived identifier.
P-1(a) describes the counterparty as *"a French venture-exploration database business"* — quasi-identifying with one alpha tester. Add sector/nationality descriptors to the redaction sweep (`hr-third-party-content-grep-on-undertaking`).

### M12. Fix the mechanism, keep the conclusion.
The nine date locations are correct, but the hero regex misses the body line because of the `:` in `**Last Updated:**`, not because it matches "first occurrence." Likewise the mirror sentinel trips via `test.each(DOCS)` → `loadMirror` ENOENT, not `expect(DOCS)` (which uses `arrayContaining`). Operational conclusions stand; the stated reasons are wrong and would mislead the next reader.

### M13. Ceremony collapse.
§13 (C4), §14, §15, §16, §17, §18, §19 are not load-bearing for a prose change — collapse each to a one-line "N/A — prose-only". Keep §3.1/3.3/3.4, §4, §5.2/5.3, §6, §11.

### M14. Positioning — lead with the default case.
Pointer opens with the reassurance, then the qualification: *"this section applies to you unless you asked for an operator-assisted session…"*. Otherwise 20+ caveats each opening on the exception read as hedging and make the common case harder to determine (spec-flow gap 5: only the P3 draft carries the default-negative; no AC requires it).

### M15. Discharge record must not read as a remedy.
The `compliance-posture.md` C5-discharge row must state plainly: **C5 discharged; C2/C3 remain open; C5 is a notice fix, not a remedy for the live tester.** Otherwise the condition set reads majority-complete while the two conditions that actually protect the tester stay open.

---

## USER-CHALLENGE — surfaced, never auto-applied

### U1. Activate the body-equivalence guard for the three docs? (architecture F3)
`check-tc-document-sha.sh:177-180` has `BODY_EQUIVALENCE_DOCS=("terms-and-conditions")` plus a **committed note** saying the guard infrastructure is ready for `data-protection-disclosure` *"once the mirror is re-synced"*, and `legal-doc-shas-guard.test.ts:97` already proves detection. Opting all three in would make AC-4 machine-enforced instead of a manual region diff.
**Why not auto-applied:** it requires first resolving a **pre-existing canonical↔mirror drift (#4455)** that this PR would otherwise layer on top of blind, and it adds a required check that can block the PR. That is scope expansion on a time-sensitive fix.

### U2. Fold AUP + Disclaimer in, or keep them deferred? (dhh F4 vs plan §3.5)
The plan defers T&C, AUP and Disclaimer together. The T&C deferral is well-argued and uncontested — editing it engages `TC_VERSION`, forcing **every existing user to re-accept** and closing live WebSocket sessions. But AUP and Disclaimer are deferred by *adjacency*, not by mechanism: §5.3 itself proves no version constant reads them, and both already have mirrors and `LEGAL_DOC_SHAS` entries. AUP §5.3 *"You are the data controller"* is the same wrong-for-this-tester claim as PP §4.2. Cost to fold in: ~5 pointers, 2 mirrors, 2 SHAs — machinery already running.
**Why not auto-applied:** expands an explicitly time-sensitive change beyond the operator's stated target.

### U3. Re-evaluation trigger for the deferred set. (cpo)
Plan keys deferral re-evaluation to determination **C9** (before tester #2). cpo notes *"before the next operator-assisted run"* and *"before tester #2"* are different events and **the first comes sooner**. Recommend the trigger become the earlier of the two.

---

## Carried to CLO (Tier 1 sign-off gates merge)

- **Q2 (highest reader impact):** forward tense. A present-tense *"only under a written instrument"* reads as a claim about the live tester's own past session, which was **not** so covered.
- **Q4:** do not assert the Anthropic transfer mechanism or retention window as settled while determination **C6** is open — including where annex §5.2 states it flatly. C6 is already tracked at `knowledge-base/legal/data-processing-agreements/anthropic.md` item 4; it is a one-email operator action with days of lead time and it gates what §2.1c can ever say.
- **Q1 / Q5 / Q7:** no reader impact; answer for the record.
- **Q6:** superseded by M6 (de-numeralise or defer).

---

## Resolutions — 2026-08-09

All M1-M15 accepted and folded into the plan as binding amendments A1-A14 (plan §0). The three
user-challenge items were put to the operator:

- **U2 → A15. Fold AUP + Disclaimer in; defer `terms-and-conditions.md` only.** The T&C deferral keeps
  a real mechanism; AUP/Disclaimer had only adjacency.
- **U1 → A17. Measured, then deferred by the rule the operator set.** Drift after the script's own
  normalisation: gdpr-policy 63 lines, privacy-policy 58, DPD 56, AUP 18, disclaimer 2, T&C 0.
  Substantive → sync this PR's own edits to both surfaces, file guard activation as a follow-up, do
  not add any doc to `BODY_EQUIVALENCE_DOCS` here (it would fail on drift this PR did not cause).
- **U3 → A16. Trigger tightened** to the next operator-assisted run or C9, whichever is earlier.

**Finding that emerged from the U1 measurement, and its disposition (A18).** The published DPD mirror
is missing **six** §2.3 processing-activity disclosures — (p), (w), (x), (y), (z), (ad) — where #7349
recorded only (ad). Since the mirror is the sole published surface, those activities are undisclosed
to data subjects: an Art. 13/14 gap affecting all web-platform users, broader in population than the
single-tester gap this PR closes. The AUP divergence is likewise substantive, including a published
clause **stricter than the canonical record** (the "another lawful basis" alternative is dropped).
Operator decision: keep it in #7349 rather than pulling it into a time-sensitive PR; #7349's premise
corrected on-issue the same day so its planning starts from the verified scope.

**Correction to M5, found while measuring.** `collapse()` in `check-tc-document-sha.sh` already
normalises both link forms to sentinels (`(privacy-policy.md)` and `(/legal/privacy-policy/)` both →
`(LINK_PRIVACY)`). So the per-surface link difference is a real authoring constraint but does **not**
trip the guard. M5's action stands (use the per-surface form, exclude link text from any verbatim-port
assertion); its stated risk was overstated.
