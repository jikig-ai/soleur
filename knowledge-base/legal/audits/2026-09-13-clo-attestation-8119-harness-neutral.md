---
title: "Counsel review audit — PR #8119 (harness-neutral plugin copy; TC_VERSION 2.5.1)"
type: counsel-review
date: 2026-09-13
issue: 8064
pr: 8119
status: SIGNED-OFF (CLO-agent-reviewed, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-13
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED — condition met; re-attested at 8216d6276 (Codex/Devin parenthetical inventory) and again at 12ee4c610 (cookie/disclaimer identity + Privacy §5.1 generic other-CLI sentence). F1 remains discharged (GDPR §2.2 scoped). 12ee4c610 lifts cookie/disclaimer Claude-exclusivity for identity language only: both surfaces now use the same supported-CLI parenthetical; cookie §3.1 still says the plugin does not use cookies; disclaimer liability/warranty text and Last Updated line are unchanged. Privacy §5.1 (canonical + Eleventy) adds 'When you use another supported CLI, plugin-local inference is sent to that CLI's provider under your own credentials. That provider is not a Jikigai processor.' — no named Devin/Cognition or Codex/OpenAI path, no processor-table row. SHA pins match. TC_VERSION stays 2.5.1. No grok --trust. No Art. 33 / Art. 34 duty arises."
condition_discharged_at: 2026-09-13
condition_discharged_by: "Applied in-PR at 959bc2f26 before merge; GDPR §2.2 canonical and Eleventy now match the Privacy Policy §5.1 Claude Code scoping, plus a Grok analogue that states the user's own CLI relationship and the processor denial."
blocking_findings: []
required_before_merge: []
required_before_merge_DISCHARGED:
  - "F1 (mandatory) — GDPR Policy §2.2 first bullet (canonical + Eleventy) still asserted that running the Soleur plugin sends requests to Anthropic's Claude API. After this PR's Plugin-definition expansion that statement was false of Grok Build. Scoped to 'When you use Claude Code:' and a Grok analogue added; LEGAL_DOC_SHAS[\"gdpr-policy\"] re-pinned. Evidence: docs/legal/gdpr-policy.md §2.2 first bullet; plugins/soleur/docs/pages/legal/gdpr-policy.md the same bullet; apps/web-platform/lib/legal/legal-doc-shas.ts gdpr-policy pin d82f2f84d62ed3fd465ee7f1c27ad5dd9c9fb13c465d2945a95967f980cdf19d equals sha256sum of the canonical."
recommended_before_merge_APPLIED:
  - "O1 — GDPR Policy §4.2 table row 'Prompts, code context | Anthropic (via Claude API)' qualified 'when used with Claude Code' on both surfaces."
  - "O2 — Privacy Policy §5.1 generic other-CLI sentence landed at 12ee4c610 (canonical + Eleventy): 'When you use another supported CLI, plugin-local inference is sent to that CLI's provider under your own credentials. That provider is not a Jikigai processor.' Does not name Cognition or OpenAI."
  - "O3 — knowledge-base/legal/compliance-posture.md Acceptable Use Policy Last Updated cell 2026-08-11 → 2026-09-13."
optional_precision_notes:
  - "O4 (optional, non-blocking) — Disclaimer Last Updated remains 11 August 2026; only the identity sentence moved. Liability/warranty text is the August 11 substance; the identity alignment is the same clarifying class as the five lockstep docs. Cookie Policy has no body Last-Updated line by design (NO_BODY_LAST_UPDATED)."
attests:
  - docs/legal/terms-and-conditions.md
  - docs/legal/privacy-policy.md
  - docs/legal/data-protection-disclosure.md
  - docs/legal/gdpr-policy.md
  - docs/legal/acceptable-use-policy.md
  - docs/legal/cookie-policy.md (identity sentences + §3.1 no-cookies claim only)
  - docs/legal/disclaimer.md (identity sentence only; liability/warranty not re-opened)
  - plugins/soleur/docs/pages/legal/terms-and-conditions.md
  - plugins/soleur/docs/pages/legal/privacy-policy.md
  - plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  - plugins/soleur/docs/pages/legal/gdpr-policy.md
  - plugins/soleur/docs/pages/legal/acceptable-use-policy.md
  - plugins/soleur/docs/pages/legal/cookie-policy.md
  - plugins/soleur/docs/pages/legal/disclaimer.md
  - apps/web-platform/lib/legal/tc-version.ts
  - apps/web-platform/lib/legal/legal-doc-shas.ts
  - knowledge-base/legal/compliance-posture.md (T&C row 2.5.1 / 2026-09-13; AUP Last Updated 2026-09-13; Completed-Compliance-Work row for this PR)
art_33_triggered: false
art_34_triggered: false
art_33_limb_applied: "Art. 33(1) is not engaged. Art. 33 is conditioned on a personal data breach within Art. 4(12) — a breach of security leading to accidental or unlawful destruction, loss, alteration, unauthorised disclosure of, or unauthorised access to personal data. This PR is a description change of the Plugin (harness-neutral copy). It introduces no new processing purpose, no new category of personal data, no new recipient, and no new sub-processor. No such event occurred in this work. Art. 34 is not reached. No clock started; nothing fell due. No breach-register row is owed."
carve_outs:
  - "NOT ATTESTED — the engineering design of Grok Build plugin fidelity (Phases 1–5 of #8064). This review attests only whether the legal prose describes the Plugin as the code and the live CLI actually behave."
  - "NOT ATTESTED — ACP #6547 (xAI as a Jikigai processor / sub-processor). Parked. This PR correctly does not unpark it."
  - "NOT ATTESTED — a named Devin/Cognition or Codex/OpenAI inference path. Still unmeasured and still unnamed. Privacy §5.1's generic other-CLI sentence is attested as a class claim (user credentials; not a Jikigai processor), not as a measured description of Devin's cloud fetcher or Codex's provider."
  - "NOT ATTESTED — cookie categories, Docs-Site/Web-Platform cookie tables, or Disclaimer §§3.1–3.2 liability/warranty. 12ee4c610 is identity language only."
  - "NOT ATTESTED — pre-existing #7465 canonical↔mirror Last-Updated drift on privacy / DPD / GDPR. This PR correctly left those Last Updated lines untouched and used an Amended: September 13, 2026 line instead."
  - "NOT PROMOTED — external counsel review. This is the v1 internal sign-off under the Soleur-as-tenant-zero posture."
re_evaluation_triggers:
  - "ACP #6547 unparks, or any path is added on which Jikigai holds an xAI credential or intermediates xAI traffic — xAI then becomes a Jikigai processor / sub-processor and this PR's denial sentences become false."
  - "A Devin/Cognition or Codex/OpenAI inference path is measured (or Jikigai holds a Cognition/OpenAI credential / intermediates that traffic) — the parenthetical inventory then under-describes a live data path and a disclosure, not an invented one, is owed."
  - "Live `grok --help` grows a `--trust` (or equivalent) flag — none exists on CLI 1.0.29; inventing one was a locked non-goal."
  - "Cookie Policy or Disclaimer is expanded beyond identity language (cookie categories, a claim that the plugin uses cookies, or a change to Disclaimer liability/warranty)."
  - "First arms-length (non-Jikigai-affiliate) Grok Build, Codex, or Devin CLI user of the Plugin — v1 attestation rests on Soleur-as-tenant-zero."
  - "Any data subject outside the EEA/UK, or in a regulated industry."
related:
  - knowledge-base/legal/tc-version-bump-policy.md
  - knowledge-base/legal/compliance-posture.md
  - apps/web-platform/lib/legal/tc-version.ts
  - apps/web-platform/lib/legal/legal-doc-shas.ts
  - docs/legal/terms-and-conditions.md
  - docs/legal/privacy-policy.md
  - docs/legal/data-protection-disclosure.md
  - docs/legal/gdpr-policy.md
  - docs/legal/acceptable-use-policy.md
  - plugins/soleur/lib/harness.ts
---

> **DRAFT — This document was generated by AI and requires professional legal review before use. It does not constitute legal advice.**

# Counsel review — PR #8119

**Authority.** Soleur v1 CLO-attestation, ship Phase 5.5 Counsel-Review CLO-Attestation Gate, brand-survival threshold `single-user incident`. This is the internal sign-off performed by the CLO agent, not by the non-lawyer operator. The operator retains an optional veto. External counsel re-review is reserved for the frontmatter `re_evaluation_triggers`.

**Method.** Attested against the working-tree prose, not the PR description. Known drift class: legal prose hallucinated against the code (PR #4353 / #4558); gates measure agreement, not truth (#7349). First pass HEAD `fd8131a05` (BLOCKED on F1). Re-review HEAD `959bc2f26` (DISCHARGED). Parenthetical inventory expansion HEAD `8216d6276`. Cookie/disclaimer identity + Privacy §5.1 generic sentence HEAD `12ee4c610`. Live CLI checked: `grok` 1.0.29.

## Inventory

| Surface | In this PR? | Finding |
|---|---|---|
| `docs/legal/terms-and-conditions.md` + Eleventy | yes | Plugin definition harness-neutral; Last Updated 13 September 2026; PATCH summary in the date line |
| `docs/legal/privacy-policy.md` + Eleventy | yes | Definition + §3 + §4.1 + §5.1 lead; Last Updated **not** touched; **Amended:** 13 September 2026 on both surfaces |
| `docs/legal/data-protection-disclosure.md` + Eleventy | yes | Provider blurb + §1.6 Plugin definition; Last Updated **not** touched; **Amended:** 13 September 2026 on both surfaces |
| `docs/legal/gdpr-policy.md` + Eleventy | yes | Intro definition + Amended line. **§2.2 first bullet scoped — F1 discharged at 959bc2f26.** §4.2 table qualified (O1) |
| `docs/legal/acceptable-use-policy.md` + Eleventy | yes | Intro + Anthropic/Claude third-party bullet names Grok/xAI with a denial; Last Updated 13 September 2026 |
| `docs/legal/cookie-policy.md` + Eleventy | yes (`12ee4c610`) | Identity parenthetical now harness-neutral on both surfaces. §3.1 still: plugin **does not use cookies** |
| `docs/legal/disclaimer.md` + Eleventy | yes (`12ee4c610`) | Identity sentence now harness-neutral. Liability/warranty and Last Updated 11 August 2026 untouched |
| `LEGAL_DOC_SHAS` + `TC_DOCUMENT_SHA` | yes | Pins match `sha256sum` of the five edited canonicals after `8216d6276`; cookie + disclaimer pins unchanged |
| `TC_VERSION` 2.5.0 → 2.5.1 | yes | Seed scripts (`seed-dev-users.sh`, `seed-live-verify-user.sh`, `seed-qa-user.sh`) match |
| `compliance-posture.md` T&C + AUP rows | yes | T&C 2.5.1 / 2026-09-13; AUP Last Updated 2026-09-13 (O3 discharged) |
| `article-30-register.md` | **no** | Correct: no new processing activity |

SHA pins re-hashed on this tree (`12ee4c610`) and equal the literals:

- T&C `TC_DOCUMENT_SHA` = `8d33c47b143b6690dcd581799baacaf1b4c1c084a356fb0d5383a9c661984007` (unchanged this commit)
- privacy-policy = `3019f5d5ca91cd0e2ccf5570468142148e1f1f6fac218200125cbd2c962d5251`
- data-protection-disclosure = `cf2a1acba67b75cff75289108b66c12dc1ab5d051d47e202911977e83c5b9663` (unchanged this commit)
- gdpr-policy = `8a879987bd18d8f49b3f94cec9b7058201f6ad82fd0eb700dfee525a1b0da397` (unchanged this commit)
- acceptable-use-policy = `bc2c38315b6669a1186151cdbffe8b39ca3223903da89a7db0f2c2a9b382eb92` (unchanged this commit)
- cookie-policy = `ff889cbc7937d207374781dca15894292d1f6eaf63c66e6b6f1575f653c4e3c5`
- disclaimer = `8b9373e78afa1aa67126b901e60d040167116bf423d262449e6c4cc6096f09c2`

Local gates on this HEAD: `check-tc-document-sha.sh` exit 0 (includes `BODY_EQUIVALENCE_DOCS` for T&C, AUP, disclaimer).

## §1 — Implementation-detail claims, checked against the files

The Plugin **is** a locally installed plugin for the four harnesses `plugins/soleur/lib/harness.ts` already names: `Harness = "claude" | "grok" | "codex" | "devin"`. Grok markers are `GROK_HOME` / `GROK_AGENT` / `GROK_DEFAULT_MODEL` / `GROK_SUBAGENTS`. CONTRIBUTING.md and `knowledge-base/engineering/grok-onboarding.md` describe the same in-repo plugin loading locally via `.grok/config.toml`. Plugin-local Grok traffic is a user-CLI relationship, not Jikigai intermediating xAI. Codex and Devin are inventoried as supported CLIs only; their inference paths are unmeasured and are **not** described.

Locked constraints, re-verified on `12ee4c610`:

- Cookie-policy and disclaimer identity exclusivity is **lifted** (operator lock update). `git grep 'Claude Code plugin'` over those four files: none. Cookie §3.1 still: the plugin **does not use cookies**. Disclaimer liability/warranty (the August 11 §3.1 / §3.2 substance) was not in the diff. `check-tc-document-sha.sh` exit 0 (disclaimer is in `BODY_EQUIVALENCE_DOCS`).
- `git grep xAI docs/legal/` returns denial sentences, the Privacy Policy §5.1 lead, the AUP Anthropic/Claude bullet, and the new GDPR §2.2 Grok analogue. No processor-table row names xAI (`git grep` of table rows in DPD and GDPR: zero xAI hits). DPD §4.2 processor table is unchanged (Anthropic PBC remains a Jikigai processor for Jikigai-keyed jobs; the "Direct customer of Anthropic" inference row is the user's own relationship).
- `git grep 'grok --trust'` over `docs/legal/` and Eleventy legal pages: none. Live `grok --help` on CLI 1.0.29 has no `--trust` flag.
- T&C and AUP normalised bodies still match (SHA-guard body-equivalence step exit 0). Privacy / DPD / GDPR `**Last Updated:**` lines were not edited (pre-existing #7465 drift). `**Amended:** September 13, 2026` is present on both surfaces of those three. T&C and AUP Last Updated lines are 13 September 2026 on both surfaces (T&C Eleventy hero included).

## §2 — F1 — GDPR §2.2, re-verified discharged

First-pass defect: GDPR intro said the Plugin includes Grok Build, while §2.2 first bullet still said, unqualified, that running the plugin sends requests to Anthropic's Claude API. True of Claude Code, false of Grok Build. Same class as #7349 (half-applied replacement) and as the #7100 split already recorded in the next bullet of that section.

Re-read on `959bc2f26` against Privacy Policy §5.1, not against the commit message.

Privacy Policy §5.1 (canonical and Eleventy, unchanged since `fd8131a05`):

> The Soleur Plugin is designed to work with the AI provider of the CLI you run it in (Anthropic through Claude Code; xAI through Grok Build). When you use Claude Code:

then the Anthropic own-key / no-intermediation bullets.

GDPR Policy §2.2 first bullet (canonical and Eleventy, now identical):

> **Anthropic (Claude API) — locally-installed Soleur plugin:** When you use Claude Code: when you run the Soleur **plugin** on your own machine and invoke its agents and skills, requests are sent to Anthropic's Claude API using **your own** API key. Anthropic acts as an independent data controller or processor under its own terms and privacy policy. For that path, Soleur does not intermediate, intercept, or store any data exchanged between you and Anthropic. When you use Grok Build, plugin-local inference is sent to xAI under your own CLI credentials; xAI is not a Jikigai processor.

The Anthropic claim is now scoped. The Grok sentence states the user's own CLI relationship and the processor denial; it does not add xAI to any processor table. `LEGAL_DOC_SHAS["gdpr-policy"]` equals `sha256sum docs/legal/gdpr-policy.md`. F1 is discharged.

O1 (recommended) also landed: GDPR §4.2 table row is now `Anthropic (via Claude API), when used with Claude Code` on both surfaces.

O2 landed at `12ee4c610` as a generic other-CLI sentence rather than a Grok-specific bullet list. See §2c.

## §2b — Parenthetical inventory expansion (`8216d6276`) — attested, not a new F1

Operator lock: inventory the shipped harnesses in the parenthetical; do **not** invent a Cognition data path (Devin CLI has `devin auth login` and a cloud-side fetcher; unmeasured).

Verified against the files, not the commit message:

- Every Plugin-definition parenthetical on the five canonicals and five Eleventy mirrors now reads `including Claude Code, Grok Build, Codex, and Devin CLI`. That list is the `Harness` union in `plugins/soleur/lib/harness.ts`. Adding examples of an already-stated "supported AI coding CLIs" class is Tier 2 clarifying; `TC_VERSION` correctly stays `2.5.1` on this unmerged PR. `TC_BUMP_METADATA.substantiveChange` was updated in lockstep with the parenthetical.
- GDPR §2.2 first bullet is **unchanged** in substance from F1: Claude Code → Anthropic under the user's key; Grok Build → xAI under the user's CLI credentials; `xAI is not a Jikigai processor`. No Codex/OpenAI sentence. No Devin/Cognition sentence.
- Privacy Policy §5.1 lead is **unchanged**: `Anthropic through Claude Code; xAI through Grok Build` then `When you use Claude Code:`. It does not add an OpenAI or Cognition mapping. Under the operator lock that is the correct direction: under-describing an unmeasured path, not hallucinating one.
- AUP Anthropic/Claude bullet still names only Anthropic (Claude Code) and xAI (Grok Build), with the processor denial. No OpenAI/Cognition terms sentence.
- `git grep` of table rows in DPD and GDPR: zero hits for xAI, Cognition, OpenAI, Codex, or Devin. Denial sentences remain; no processor-table row was added.
- `git grep 'grok --trust'` over `docs/legal/` and Eleventy legal pages: none.

This is not a recurrence of F1. F1 was an **unqualified false statement** (the Plugin as redefined still "sends requests to Anthropic"). After F1 the Anthropic claim is scoped. Naming two further shipped CLIs in an `including` list, without describing unmeasured inference, does not make the scoped Anthropic sentence false.

## §2c — Cookie/disclaimer identity + Privacy §5.1 generic sentence (`12ee4c610`)

Operator lock update: cookie/disclaimer exclusivity lifted for **identity language only**. Still no `grok --trust`. Still no Cognition/OpenAI as Jikigai processors. `TC_VERSION` stays 2.5.1.

Verified against the files:

- Cookie Policy intro and §3.1 (canonical + Eleventy) now use the supported-CLI parenthetical / "locally installed plugin for supported AI coding CLIs". §3.1 still: **does not use cookies**; does not set, read, or transmit cookies of any kind. Consistency test retargeted to that no-cookies claim.
- Disclaimer identity sentence (canonical + Eleventy) now uses the same parenthetical. `git show 12ee4c610 -- docs/legal/disclaimer.md` is that one sentence plus the Eleventy twin. Sections 3.1 / 3.2 liability-and-cap text and the **Last Updated:** 11 August 2026 line are untouched.
- Privacy Policy §5.1, after the Claude Code bullets, now reads: "When you use another supported CLI, plugin-local inference is sent to that CLI's provider under your own credentials. That provider is not a Jikigai processor." Parallel on the Eleventy mirror. `git grep -iE 'Cognition|OpenAI' docs/legal/` : none. No processor-table row. The sentence is a class claim (user credentials; not Jikigai as processor), the same shape as the Grok analogue, without naming the unmeasured providers. "Plugin-local inference" here means inference **from** the locally installed plugin, as already used in GDPR §2.2 for Grok, not on-device model execution.
- `git grep 'grok --trust'` over `docs/legal/` and Eleventy legal pages: none.
- SHA pins for cookie-policy, disclaimer, and privacy-policy equal `sha256sum` of the canonicals. T&C SHA unchanged; `TC_VERSION` still `2.5.1`. Clarifying identity/example language on an unmerged PATCH PR; a further bump is not owed.

## §3 — TC_VERSION classification

`knowledge-base/legal/tc-version-bump-policy.md`:

- Tier 1 material: new purpose, new lawful basis, new sub-processor, new disclaimer, new restriction on permitted use, etc.
- Tier 2 clarifying: re-wording to make a previously-implicit point explicit; adding examples of an existing rule. PATCH bump.
- If unsure, treat as clarifying. Over-bumping is recoverable.

This change re-describes an already-shipping locally-installed plugin. It adds no processing purpose, no Jikigai-held xAI credential, no sub-processor, no new disclaimer-of-warranty. AUP's new "when you use Grok Build, comply with xAI's terms" is the existing "comply with all third-party services" rule named for a second CLI. That is Tier 2 clarifying. PATCH `2.5.0 → 2.5.1` is the right limb. `TC_BUMP_METADATA.lastUpdated` = "September 13, 2026" and the T&C Last Updated line summarise the same delta. Re-acceptance is the intended consequence.

It is **not** cosmetic (Tier 3): the user's understanding of what "the Plugin" is shifts. Leaving `TC_VERSION` un-bumped would have been the under-bump.

No Article 30 amendment is owed. Plugin-local Grok traffic is the user's own xAI relationship; Jikigai is neither controller nor processor of that path (DPD §2.1c first row still holds: "Plugin-local — User's machine, User's credentials, User's purposes | Neither Controller nor Processor").

## §4 — Art. 33 / Art. 34

Confirmed. See `art_33_limb_applied`. Description change of the Plugin; no new processing; no security event. Nothing notifiable.

## §5 — Disposition

**DISCHARGED. Condition met.** F1, O1 and O3 landed at `959bc2f26`. The `8216d6276` parenthetical expansion is attested inventory of shipped harnesses. `12ee4c610` attests cookie/disclaimer identity alignment (no-cookies claim and liability text preserved) and Privacy §5.1's generic other-CLI sentence (O2 applied; no named Cognition/OpenAI path). No further `TC_VERSION` bump. O4 (Disclaimer date line) does not block merge.
