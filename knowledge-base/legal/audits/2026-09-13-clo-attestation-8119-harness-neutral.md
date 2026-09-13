---
title: "Counsel review audit — PR #8119 (harness-neutral plugin copy; TC_VERSION 2.5.1)"
type: counsel-review
date: 2026-09-13
issue: 8064
pr: 8119
status: SIGNED-OFF (CLO-agent-reviewed, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-13
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED — condition met. One artifact-class in scope (five canonical legal docs + Eleventy mirrors + SHA pins + TC_VERSION 2.5.1). The single mandatory correction (F1) has LANDED at 959bc2f26: GDPR Policy §2.2 first bullet (canonical + Eleventy) now starts 'When you use Claude Code:' and adds the Grok Build analogue ('plugin-local inference is sent to xAI under your own CLI credentials; xAI is not a Jikigai processor'). LEGAL_DOC_SHAS[\"gdpr-policy\"] re-pinned to the live sha256. O1 (GDPR §4.2 table 'when used with Claude Code') and O3 (compliance-posture AUP Last Updated 2026-09-13) landed in the same commit. Re-verified against Privacy Policy §5.1 and against the files, not the PR description. Cookie-policy and disclaimer still Claude-exclusive. No xAI processor-table row. No grok --trust. PATCH 2.5.1 is the right limb. No Art. 33 / Art. 34 duty arises."
condition_discharged_at: 2026-09-13
condition_discharged_by: "Applied in-PR at 959bc2f26 before merge; GDPR §2.2 canonical and Eleventy now match the Privacy Policy §5.1 Claude Code scoping, plus a Grok analogue that states the user's own CLI relationship and the processor denial."
blocking_findings: []
required_before_merge: []
required_before_merge_DISCHARGED:
  - "F1 (mandatory) — GDPR Policy §2.2 first bullet (canonical + Eleventy) still asserted that running the Soleur plugin sends requests to Anthropic's Claude API. After this PR's Plugin-definition expansion that statement was false of Grok Build. Scoped to 'When you use Claude Code:' and a Grok analogue added; LEGAL_DOC_SHAS[\"gdpr-policy\"] re-pinned. Evidence: docs/legal/gdpr-policy.md §2.2 first bullet; plugins/soleur/docs/pages/legal/gdpr-policy.md the same bullet; apps/web-platform/lib/legal/legal-doc-shas.ts gdpr-policy pin d82f2f84d62ed3fd465ee7f1c27ad5dd9c9fb13c465d2945a95967f980cdf19d equals sha256sum of the canonical."
recommended_before_merge_APPLIED:
  - "O1 — GDPR Policy §4.2 table row 'Prompts, code context | Anthropic (via Claude API)' qualified 'when used with Claude Code' on both surfaces."
  - "O3 — knowledge-base/legal/compliance-posture.md Acceptable Use Policy Last Updated cell 2026-08-11 → 2026-09-13."
optional_precision_notes:
  - "O2 (optional, non-blocking) — Privacy Policy §5.1 names xAI through Grok Build in the lead sentence, then spells the 'your own API key / Soleur does not intermediate' bullets only under 'When you use Claude Code:'. GDPR §2.2 now carries the Grok analogue in operative body. Privacy is not false as written; a matching 'When you use Grok Build:' bullet list would be belt-and-braces only."
attests:
  - docs/legal/terms-and-conditions.md
  - docs/legal/privacy-policy.md
  - docs/legal/data-protection-disclosure.md
  - docs/legal/gdpr-policy.md
  - docs/legal/acceptable-use-policy.md
  - plugins/soleur/docs/pages/legal/terms-and-conditions.md
  - plugins/soleur/docs/pages/legal/privacy-policy.md
  - plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  - plugins/soleur/docs/pages/legal/gdpr-policy.md
  - plugins/soleur/docs/pages/legal/acceptable-use-policy.md
  - apps/web-platform/lib/legal/tc-version.ts
  - apps/web-platform/lib/legal/legal-doc-shas.ts
  - knowledge-base/legal/compliance-posture.md (T&C row 2.5.1 / 2026-09-13; AUP Last Updated 2026-09-13; Completed-Compliance-Work row for this PR)
art_33_triggered: false
art_34_triggered: false
art_33_limb_applied: "Art. 33(1) is not engaged. Art. 33 is conditioned on a personal data breach within Art. 4(12) — a breach of security leading to accidental or unlawful destruction, loss, alteration, unauthorised disclosure of, or unauthorised access to personal data. This PR is a description change of the Plugin (harness-neutral copy). It introduces no new processing purpose, no new category of personal data, no new recipient, and no new sub-processor. No such event occurred in this work. Art. 34 is not reached. No clock started; nothing fell due. No breach-register row is owed."
carve_outs:
  - "NOT ATTESTED — the engineering design of Grok Build plugin fidelity (Phases 1–5 of #8064). This review attests only whether the legal prose describes the Plugin as the code and the live CLI actually behave."
  - "NOT ATTESTED — ACP #6547 (xAI as a Jikigai processor / sub-processor). Parked. This PR correctly does not unpark it."
  - "NOT ATTESTED — cookie-policy.md and disclaimer.md remaining Claude Code exclusive. That was a locked constraint; they were not edited; the exclusivity is recorded, not re-justified."
  - "NOT ATTESTED — pre-existing #7465 canonical↔mirror Last-Updated drift on privacy / DPD / GDPR. This PR correctly left those Last Updated lines untouched and used an Amended: September 13, 2026 line instead."
  - "NOT PROMOTED — external counsel review. This is the v1 internal sign-off under the Soleur-as-tenant-zero posture."
re_evaluation_triggers:
  - "ACP #6547 unparks, or any path is added on which Jikigai holds an xAI credential or intermediates xAI traffic — xAI then becomes a Jikigai processor / sub-processor and this PR's denial sentences become false."
  - "Live `grok --help` grows a `--trust` (or equivalent) flag — none exists on CLI 1.0.29; inventing one was a locked non-goal."
  - "Cookie Policy or Disclaimer is expanded off Claude Code exclusivity."
  - "First arms-length (non-Jikigai-affiliate) Grok Build user of the Plugin — v1 attestation rests on Soleur-as-tenant-zero."
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

**Method.** Attested against the working-tree prose, not the PR description. Known drift class: legal prose hallucinated against the code (PR #4353 / #4558); gates measure agreement, not truth (#7349). First pass HEAD `fd8131a05` (BLOCKED on F1). Re-review HEAD `959bc2f26`. Live CLI checked: `grok` 1.0.29.

## Inventory

| Surface | In this PR? | Finding |
|---|---|---|
| `docs/legal/terms-and-conditions.md` + Eleventy | yes | Plugin definition harness-neutral; Last Updated 13 September 2026; PATCH summary in the date line |
| `docs/legal/privacy-policy.md` + Eleventy | yes | Definition + §3 + §4.1 + §5.1 lead; Last Updated **not** touched; **Amended:** 13 September 2026 on both surfaces |
| `docs/legal/data-protection-disclosure.md` + Eleventy | yes | Provider blurb + §1.6 Plugin definition; Last Updated **not** touched; **Amended:** 13 September 2026 on both surfaces |
| `docs/legal/gdpr-policy.md` + Eleventy | yes | Intro definition + Amended line. **§2.2 first bullet scoped — F1 discharged at 959bc2f26.** §4.2 table qualified (O1) |
| `docs/legal/acceptable-use-policy.md` + Eleventy | yes | Intro + Anthropic/Claude third-party bullet names Grok/xAI with a denial; Last Updated 13 September 2026 |
| `docs/legal/cookie-policy.md` + Eleventy | **no** | Still "Claude Code plugin". Constraint honoured (not in `fd8131a05` or `959bc2f26`) |
| `docs/legal/disclaimer.md` + Eleventy | **no** | Still "Claude Code plugin". Constraint honoured |
| `LEGAL_DOC_SHAS` + `TC_DOCUMENT_SHA` | yes | Pins match `sha256sum` of the five edited canonicals; cookie + disclaimer pins unchanged; gdpr-policy re-pinned on F1 |
| `TC_VERSION` 2.5.0 → 2.5.1 | yes | Seed scripts (`seed-dev-users.sh`, `seed-live-verify-user.sh`, `seed-qa-user.sh`) match |
| `compliance-posture.md` T&C + AUP rows | yes | T&C 2.5.1 / 2026-09-13; AUP Last Updated 2026-09-13 (O3 discharged) |
| `article-30-register.md` | **no** | Correct: no new processing activity |

SHA pins re-hashed on this tree and equal the literals:

- T&C `TC_DOCUMENT_SHA` = `a66b7fa8e9bd2687ee17a151262eb81c4a50393c74a9f4376b2b626343be0144`
- privacy-policy = `94ddb5b21a1c13db5c9e3a70c3d815e8f40cdbb62bca61810e2878f80c7125ab`
- data-protection-disclosure = `0afd109330be097e034d4f0ab9ffed305b1f6467f4d7f749933d10f9559e14f4`
- gdpr-policy = `d82f2f84d62ed3fd465ee7f1c27ad5dd9c9fb13c465d2945a95967f980cdf19d`
- acceptable-use-policy = `896a401ab93b2f40f997a8187bf515633db2a68af592e7c258be31f9eccf7725`

Local gates on this HEAD: `check-tc-document-sha.sh` exit 0 (includes `BODY_EQUIVALENCE_DOCS` for T&C, AUP, disclaimer).

## §1 — Implementation-detail claims, checked against the files

The Plugin **is** a locally installed plugin for Grok Build as well as Claude Code. `plugins/soleur/lib/harness.ts` maps Soleur workflow invocations onto Claude Code, Grok Build, Codex, or Devin CLI; Grok markers are `GROK_HOME` / `GROK_AGENT` / `GROK_DEFAULT_MODEL` / `GROK_SUBAGENTS`. CONTRIBUTING.md and `knowledge-base/engineering/grok-onboarding.md` describe the same in-repo plugin loading locally via `.grok/config.toml`. That is a user-CLI relationship, not Jikigai intermediating xAI.

Locked constraints, re-verified on `959bc2f26`:

- Cookie-policy and disclaimer were not in either commit of this PR. Both still contain "Claude Code plugin" on canonical and mirror.
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

O2 remains optional: Privacy §5.1 still names xAI in the lead and does not spell a Grok bullet list. Not a false statement.

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

**DISCHARGED. Condition met.** F1, O1 and O3 landed at `959bc2f26`. O2 is recorded as optional precision and does not block merge.
