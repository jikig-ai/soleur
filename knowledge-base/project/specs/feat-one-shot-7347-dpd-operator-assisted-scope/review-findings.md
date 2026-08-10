# Review findings — PR #7372

Panel: security-sentinel · code-quality-analyst · legal-compliance-auditor · pattern-recognition-specialist
(4-agent focused slice; deviation rationale in the review invocation — prose-dominated diff, plan already reviewed by 6 agents.)

**Status: BLOCKED. Do not mark ready.** Three P1s, all confirmed by re-derivation against the records rather than accepted from the agent report.

---

## The single root cause

The scope predicate was written from the **credential** limb alone. The determination's test is a
**three-limb disjunction**, verified verbatim at
`knowledge-base/legal/audits/2026-08-06-alpha-tester-controller-processor-determination.md` §2
("The machine / key / **purpose** test, and the three postures"):

| Posture | Machine | API key | Purpose served | Jikigai's role |
|---|---|---|---|---|
| A | Tester's | Tester's | Tester's | Neither |
| B | Jikigai's (or Jikigai credential) | Jikigai's | Tester's | **PROCESSOR** |
| **C** | **Either** | **Either** | **Jikigai's own** | **CONTROLLER** |

> "Posture C is entered the moment Jikigai reads tester content for a purpose Jikigai chose, however
> small that purpose is."

The shipped §2.1c says: *"The determining question is not whose machine executes the session but
**whose credential funds it**."* That is a one-limb credential test. It cannot see Posture C.

**This is the failure mode the change was built to avoid, reproduced inside the fix for it.** The
plan's own mandatory-read learning
(`2026-08-06-my-correction-overshot-into-a-new-wrong-claim-in-a-compliance-artifact.md`) records that
a correction inherits none of the original claim's scrutiny. The 30(1) register even warns that the
*previous* framing failed because "a surface list cannot see a Jikigai-keyed run on a non-Jikigai
machine" — and the correction commits the mirror-image error.

## What falls through the gap: PA-35, verified

`knowledge-base/legal/article-30-register.md` — **Processing Activity 35 — Ongoing collaborator-access
observation of an alpha tester's private repository (#7331, #1442)**:

- **(b) Purposes** — "Measuring alpha-programme knowledge-base growth for **Jikigai's own validation
  metrics** (#1442), by reading the git history of the `knowledge-base/` tree in an alpha tester's
  **private** repository under operator collaborator access"
- **(e) Transfers** — "**None for the observation itself**" (no Jikigai credential is involved)
- **Status** — "**Live and ongoing** as of 2026-08-06. Unlike PA-34 this is not a closed past event,
  which is why the determination classes closing it as the **higher-priority remediation**."

Tester's machine, tester's key, Jikigai's purpose, no request from the tester, happening now.

---

## P1-1 — `privacy-policy.md` §4.2 re-affirms a claim that is false for the live counterparty

The section now ends: *"We do not do this by default. **Unless you ask us for an operator-assisted
session** and agree that written agreement first, **everything above stands exactly as written**."*
"Everything above" is *"All of this data remains on your machine. We have no access to it."*

The carve-out is gated on a conjunction — *you asked* AND *our machine or our API key*. **PA-35
satisfies neither conjunct**, yet reads the exact two categories the exception paragraph names
(`knowledge-base/` tree, git history), which are also exactly what PA-35(c) records.

Determination §11 C5 named this section specifically: *"§4.1 was the sentence this determination
originally analysed; **§4.2 is the one that actually breaks**."* C5's §4.2 bullet is therefore only
**partially** discharged — the carve-out added addresses operator-assisted sessions, while the case
C5 cited is collaborator-access observation.

**Fix.** A second, independent exception keyed on **repository access**, not credential. Then delete
or narrow "everything above stands exactly as written."

## P1-2 — `data-protection-disclosure.md` §2.1c collapses the three-limb test to one

Restate the determining question as a disjunction — whose machine, whose credential, **or whose
purpose** — and add a fourth table row for Jikigai-purpose observation under the User's own machine
and key. Without it the §2.1c table's controller row is gated by a definition that excludes the only
live controller activity.

## P1-3 — "only under a written instrument … before the session begins" is unbacked, in three documents

Sites: disclosure §2.1c(c); gdpr-policy §2.2 third bullet; privacy-policy §4.2. All present-tense
statements of standing practice. The records contradict them:

- `article-30-2-register.md` — "**The Art. 28(3) instrument required *before* this processing did not
  exist when it occurred.** … Anyone reading this record later should not infer from its existence
  that the timing obligation was met."
- annex Recital (D) — "An Operator-Assisted Run took place on 6 August 2026 … **before any written
  instrument was in place**. Article 28(3) requires that contract to precede the processing. **It did
  not.**"
- annex Schedule A — "**Execution status: NOT EXECUTED.** No signature has been sought."

One operator-assisted session has ever occurred and it ran without an instrument; the only candidate
instrument is unexecuted. The definite article in "**That** instrument … governs" compounds it by
implying an in-force document.

**Fix.** Forward-looking form, no definite article: *"Jikigai will not carry out operator-assisted
processing without first agreeing a written Article 28(3) instrument with the User. Where such an
instrument is agreed, it — not this Disclosure — addresses …"*

---

## P1-4 / P1-5 — the pointer was applied by template to sections that are not plugin-local

The template sentence says "**This section** describes plugin-local processing", and was pasted into
sections that demonstrably describe more:

- **`data-protection-disclosure.md` §4.2 "Service Processors"** — the Article 28 processor register
  (GitHub Pages, Plausible, Buttondown, Supabase, Stripe, Hetzner, Cloudflare). Its own opening line
  is *"For processing activities where Jikigai acts as Controller …"*. The pointer tells a reader the
  sub-processor table is plugin-local. **Remove entirely** — the section has nothing to disclaim.
  Contrast §4.1 directly above, which got a correctly-scoped bespoke paragraph; that is the form.
- **`acceptable-use-policy.md` §2 "Scope"** — enumerates the Web Platform explicitly, and the
  preceding sentence already distinguishes Plugin from Web Platform. In an AUP the Scope section is
  what every enforcement section hangs off; narrowing it is materially worse than the same error
  elsewhere.

## P2 — `gdpr-policy.md` §2.1 contradicts itself within one section

The pointer says the section "does not describe operator-assisted processing … and must not be read
as covering it"; two paragraphs later the newly-added clause describes operator-assisted sessions as
controller limb (d). Both halves are new in this PR, so the contradiction is self-inflicted. Scope the
note to "the two paragraphs above", not the section.

## P2 — "This section" over-reach at the plugin/Web-Platform boundary (7 sites)

AUP §5.1, §5.3, §6.1; gdpr-policy §6, §9; privacy-policy §6, §10. Correctly positioned, wrongly
scoped. One-word fix: "the paragraph above" — the phrasing already used correctly at disclosure §4.1.
AUP §6.1 is sharpest (the sentence above describes Web Platform server-side monitoring).

## P2 — three list-splitting insertions (6 sites incl. mirrors)

Disclosure §3.1 (between bullets (a) and (b)), §10.1 (between (b) and (c)), gdpr-policy §7.1 (between
bullets 1 and 2). Indented two spaces mid-enumeration, so GFM attaches the paragraph to the
**preceding list item only** and converts the list to loose — a section-scoped sentence renders as a
rider on one bullet, plus a visible layout change. Move flush-left, after the list closes.

## P3 — smaller items

- Disclosure §9.1 "Audit Rights" carries the breach-notification sentence copy-pasted verbatim from
  §7.1. Split: §7.1 keeps breach, §9.1 keeps audit.
- Disclosure preamble pointer says "This section" with no enclosing section; read at document level it
  asserts the whole Disclosure is plugin-local, which §2.1b and §2.1c contradict.
- privacy-policy §2 restates the sentence immediately above it and lowercases the defined term
  **Policy**.
- Repetition: the ~70-word block fires 25× per surface. Consider stating it once per document near
  the top, with a one-clause reminder elsewhere.
- **P1-6 (self-inflicted, cheap):** plan §0 A11 and `decision-challenges.md` M11 both flag P-1(a)'s
  sector/nationality descriptor as quasi-identifying under
  `hr-third-party-content-grep-on-undertaking` — and then reproduce the string verbatim in a **public**
  repo (`gh repo view --json isPrivate` → `false`). Flagging is not fixing. Paraphrase both.

---

## What held

Worth recording, because it is the part the change was actually designed around and it worked:

- **Zero SLA / price / retention / transfer-mechanism terms shipped.** Token counts for
  `DPF | SCCs | IDTA | 30-day | business days | 24 hours | no charge` are byte-identical between
  `origin/main` and HEAD across all five published docs. Every occurrence in the diff is pre-existing
  changelog text carried through unchanged. Condition **C6** respected — no transfer mechanism named.
- The plan's own draft of "own machine and key **at no charge**" was correctly dropped.
- Anthropic PBC's name and address match annex §5.1 verbatim.
- Disclosure §3.1(b)/(d) and gdpr-policy §7.1 bullet 2 survive verbatim, unqualified, and are not
  asserted true — the #7375 boundary held exactly as intended.
- Mirror sync is exact: normalised drift sets are character-for-character identical at `origin/main`
  and at HEAD for all five pairs, so every edit landed on both surfaces and the pre-existing #7349
  drift was neither fixed nor worsened.
- Dates consistent across all 15 locations; all ten body lines grew by exactly 240 characters with
  prior text preserved verbatim as `Previous:`.
- All five `LEGAL_DOC_SHAS` literals match; both gates green (consistency 13/13, SHA guard exit 0).
- No third-party repository filenames, directory listings, or file contents in the published docs —
  the prior-incident shape did not recur.

---

# Round 2 — legal-compliance-auditor + pattern-recognition-specialist

Four-agent convergence. Adds three findings that are worse than anything in round 1, all in strings
**I authored** or amendments **I recorded as binding and did not verify landed**.

## P1-7 — privacy-policy §2: my own replacement string mints a FALSE closed exception list

The string I wrote to fix the controller-identity site reads: *"For the processing described in this
policy Jikigai is the data controller. **The one exception** is an operator-assisted session…"*

At least three other configurations described **in that same policy** are not sole-controller:
- §4.10 / §5.12 LinkedIn Page Insights — "the Page admin and LinkedIn Ireland are **joint controllers**"
- §4.7 beta-tester / prospect CRM — gdpr-policy §3.13 and DPD §2.3(ad) both say "**the Web Platform
  user is the controller** and Jikigai is the processor"
- §4.11 workspace co-members — DPD §2.1b(a): "the **Workspace Owner is the controller**"

The pre-existing sentence was merely imprecise. My replacement upgraded it to an **affirmative
exhaustive-exception claim**, which is strictly worse — the exact failure mode of the learning this
plan cites in its own frontmatter. Fix: "One such configuration is…", pointing at §4.7/§4.10/§4.11.

## P1-8 — §2.1c(d) "removes Jikigai from the processing chain entirely" is falsified two bullets above

My §2.1c(d) says a User may require their own machine and credentials, "which removes Jikigai from the
processing chain **entirely**." But §2.1c(b), in the same section, says Jikigai observes how Soleur
performs in order to improve the product — and determination §2 Posture C is **Machine: Either · Key:
Either · Purpose: Jikigai's own → CONTROLLER**. The credential switch removes the Art. 28 **processor**
limb; it does not remove the Art. 4(7) **controller** limb. Delete "entirely" and say which limb goes.

## P1-9 — two amendments I recorded as BINDING were never implemented, and my verification did not check

- **A8 / decision-challenges M8 bullet 4** — DPD §4.2 preamble's closed section list *"where Jikigai
  acts as Controller (see Sections 2.1b and 2.3)"* needed 2.1c. Not applied; the generic Scope block
  was dropped underneath it instead, which created P1-4.
- **A6** — gdpr-policy §10's *"The register documents eleven processing activities"* was to be
  de-numeralised **or** deferred. Neither happened; it was silently dropped.
- **DPD §2.3 opener** — *"Soleur's data processing activities are limited to:"* (a)–(ad) is a closed
  list that now omits operator-assisted processing. The identical fix WAS applied one document over
  (gdpr §2.1 gained "(d)" plus "That list is not exhaustive"), so the pattern was understood and not
  carried across. Highest-value miss of the three.

**Process gap worth naming.** My post-implementation verification checked every *prohibition*
(don't touch T&C, don't assert §3.1(b)/(d), don't change "eleven", no PR refs, don't fix #7349 drift)
and passed 6/6. It checked **no obligation** — nothing asserted that each binding amendment actually
landed. A prohibition sweep cannot detect an omission. Any future amendment list needs a
positive per-item grep, not just a negative one.

## P1-10 — new Art. 6(1)(f) controller limb with no balancing test and no register entry

§2.1c(b) and the gdpr §2.2 bullet both assert reliance on legitimate interests for product-learning.
Every other 6(1)(f) reliance in this corpus cites an LIA path or a named balancing test; gdpr §3
enumerates §3.1–§3.13 and this limb got no entry, no LIA citation, and no Art. 30 addition. This one
needs a CLO decision, not an edit.

## Also raised (not previously captured)

- **Retention sections were not swept** — privacy §7 (*"You control its retention and deletion
  entirely"*) and gdpr §8.1 (*"Soleur does not impose any retention period"*) both contradict PA-34(f)'s
  30-day Anthropic window. Separable from C6: the **qualitative** fact (content is retained for a
  period the User does not control) is true on either Terms; only the number is C6-contingent.
- **Art. 14 third-party subjects** — PA-34(c) names company officers in fixture data; PA-35 names the
  tester's personnel and commit authors. All ten documents speak only to "the User". PA-35(g)(3) lists
  an Art. 14(5)(b) notice as a TOM, and the LIA discharges the publicity limb via two knowledge-base
  files. This PR edited the actual public transparency layer and left it silent.
- **Annex/notice asymmetry** — annex §5.2 states DPF + SCCs Modules 2&3 + UK IDTA flatly to a signing
  counterparty while the notice withholds them pending C6. The caution is applied to the audience that
  cannot act on it and withheld from the one that will contractually rely on it. One call, not two.
- **Precedent properties (ii) and (iv) dropped** — privacy §5.1's shape has four properties; the 36
  blocks carry affirmative-scope-first and cross-reference, but never **quote the non-travelling
  sentence inline** and never carry a **dated at-the-site parenthetical**. The inline quote was the
  precedent's load-bearing feature: it is what tells a reader *which* sentence stopped travelling.

## What the panel confirmed as correct

- Every one of the 36 blocks names the operator-assisted limb explicitly; none leans on the
  "automated jobs" framing. The escape the register recorded twice is **closed**.
- Both pointer registers byte-identical within themselves; the DPD self-reference localisation is
  applied exactly where intended and nowhere else.
- Zero SLA / price / retention / transfer-mechanism terms shipped; C6 respected.
- §4.1 is the one site that got the shape right — it scopes "the paragraph above", keeps the existing
  sentence verbatim, and adds the labelled exception. That is the form every other site needed.
