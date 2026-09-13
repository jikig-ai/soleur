---
title: "Counsel review audit — PR #8119 (harness-neutral plugin copy; TC_VERSION 2.5.1)"
type: counsel-review
date: 2026-09-13
issue: 8064
pr: 8119
status: BLOCKED (CLO-agent-reviewed, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-13
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "BLOCKED — one mandatory correction (F1) before merge. This PR redefines the Plugin as a locally installed plugin for supported AI coding CLIs (including Claude Code and Grok Build) in five canonicals plus Eleventy mirrors, and the Privacy Policy §5.1 lead was correctly scoped with 'When you use Claude Code:'. GDPR Policy §2.2 was not. Its first Anthropic bullet still states, unqualified, that when you run the Soleur plugin, requests are sent to Anthropic's Claude API. That sentence is now false of the Plugin as this PR defines it: live Grok Build CLI 1.0.29 sends plugin-local inference to xAI under the user's own CLI relationship. Same defect class as #7349 (half-applied replacement; gates measure agreement, not truth) and as the #7100 split already recorded in the next bullet of the same section. Cookie-policy and disclaimer were not expanded. xAI is not a processor-table row. No grok --trust. PATCH 2.5.1 is the right limb. No Art. 33 / Art. 34 duty arises."
blocking_findings:
  - "F1 (mandatory) — GDPR Policy §2.2 first bullet (canonical + Eleventy) still asserts that running the Soleur plugin sends requests to Anthropic's Claude API. After this PR's Plugin-definition expansion that statement is false of Grok Build. Scope it the way Privacy Policy §5.1 was scoped in this same PR ('When you use Claude Code:'). Do not add xAI as a Jikigai processor. Re-pin LEGAL_DOC_SHAS[\"gdpr-policy\"] and lockstep the Eleventy mirror."
required_before_merge:
  - "F1 — `docs/legal/gdpr-policy.md` §2.2 bullet 'Anthropic (Claude API) — locally-installed Soleur plugin' and `plugins/soleur/docs/pages/legal/gdpr-policy.md` the same bullet. Qualify the 'requests are sent to Anthropic's Claude API' sentence to Claude Code (privacy-policy.md §5.1 pattern). Re-pin `apps/web-platform/lib/legal/legal-doc-shas.ts` `LEGAL_DOC_SHAS[\"gdpr-policy\"]`. Do not invent `grok --trust`. Do not add an xAI processor-table row."
optional_precision_notes:
  - "O1 (recommended, non-blocking once F1 lands) — GDPR Policy §4.2 table row 'Prompts, code context | Anthropic (via Claude API) | Powering AI agent responses (user authenticates with own credentials)' is Anthropic-headed and is not an exclusive claim, but after the intro expansion a Grok reader can take it as the plugin-local AI-inference row. Qualify 'when used with Claude Code' or add a parallel xAI/Grok row as the user's own CLI relationship (NOT a Jikigai processor / sub-processor row). Same two files as F1; SHA re-pin is already owed by F1."
  - "O2 (optional) — Privacy Policy §5.1 names xAI through Grok Build in the lead sentence, then spells the 'your own API key / Soleur does not intermediate' bullets only under 'When you use Claude Code:'. A matching 'When you use Grok Build:' analogue would state the locked constraint in operative body rather than only in the Amended banner. Not a false statement as written."
  - "O3 (optional) — `knowledge-base/legal/compliance-posture.md` Legal Documents table updated the T&C row to 2.5.1 / 2026-09-13 but left Acceptable Use Policy Last Updated at 2026-08-11 after this PR moved AUP to 2026-09-13. Inventory housekeeping, not a published-notice defect. File `last_updated` frontmatter is still 2026-09-09."
attests:
  - "NOT ATTESTED as a mergeable corpus — F1 blocks. The inventory, SHA pins, cookie/disclaimer carve-out, xAI-not-a-processor constraint, grok --trust absence, TC_VERSION PATCH classification, T&C/AUP body-equivalence, privacy/DPD/GDPR Last-Updated non-touch, and Art. 33/34 negative are recorded below as findings, not as a SIGNED-OFF."
art_33_triggered: false
art_34_triggered: false
art_33_limb_applied: "Art. 33(1) is not engaged. Art. 33 is conditioned on a personal data breach within Art. 4(12) — a breach of security leading to accidental or unlawful destruction, loss, alteration, unauthorised disclosure of, or unauthorised access to personal data. This PR is a description change of the Plugin (harness-neutral copy). It introduces no new processing purpose, no new category of personal data, no new recipient, and no new sub-processor. No such event occurred in this work. Art. 34 is not reached. No clock started; nothing fell due. No breach-register row is owed."
carve_outs:
  - "NOT ATTESTED — the engineering design of Grok Build plugin fidelity (Phases 1–5 of #8064). This review attests only whether the legal prose describes the Plugin as the code and the live CLI actually behave."
  - "NOT ATTESTED — ACP #6547 (xAI as a Jikigai processor / sub-processor). Parked. This PR correctly does not unpark it."
  - "NOT ATTESTED — cookie-policy.md and disclaimer.md remaining Claude Code exclusive. That was a locked constraint; they were not edited; the exclusivity is recorded, not re-justified."
  - "NOT ATTESTED — pre-existing #7465 canonical↔mirror Last-Updated drift on privacy / DPD / GDPR. This PR correctly left those Last Updated lines untouched and used an Amended: September 13, 2026 line instead."
  - "NOT PROMOTED — external counsel review. This is the v1 internal review under the Soleur-as-tenant-zero posture. Status is BLOCKED, not SIGNED-OFF."
re_evaluation_triggers:
  - "F1 lands — re-review the scoped GDPR §2.2 sentence (and Eleventy + SHA pin) against the same Claude Code / Grok Build split Privacy Policy §5.1 already uses."
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

**Method.** Attested against the working-tree prose, not the PR description. Known drift class: legal prose hallucinated against the code (PR #4353 / #4558); gates measure agreement, not truth (#7349). HEAD `fd8131a05`. Live CLI checked: `grok` 1.0.29.

## Inventory

| Surface | In this PR? | Finding |
|---|---|---|
| `docs/legal/terms-and-conditions.md` + Eleventy | yes | Plugin definition harness-neutral; Last Updated 13 September 2026; PATCH summary in the date line |
| `docs/legal/privacy-policy.md` + Eleventy | yes | Definition + §3 + §4.1 + §5.1 lead; Last Updated **not** touched; **Amended:** 13 September 2026 on both surfaces |
| `docs/legal/data-protection-disclosure.md` + Eleventy | yes | Provider blurb + §1.6 Plugin definition; Last Updated **not** touched; **Amended:** 13 September 2026 on both surfaces |
| `docs/legal/gdpr-policy.md` + Eleventy | yes | Intro definition + Amended line. **§2.2 first bullet not scoped — F1** |
| `docs/legal/acceptable-use-policy.md` + Eleventy | yes | Intro + Anthropic/Claude third-party bullet names Grok/xAI with a denial; Last Updated 13 September 2026 |
| `docs/legal/cookie-policy.md` + Eleventy | **no** | Still "Claude Code plugin". Constraint honoured |
| `docs/legal/disclaimer.md` + Eleventy | **no** | Still "Claude Code plugin". Constraint honoured |
| `LEGAL_DOC_SHAS` + `TC_DOCUMENT_SHA` | yes | Pins match `sha256sum` of the five edited canonicals; cookie + disclaimer pins unchanged |
| `TC_VERSION` 2.5.0 → 2.5.1 | yes | Seed scripts (`seed-dev-users.sh`, `seed-live-verify-user.sh`, `seed-qa-user.sh`) match |
| `compliance-posture.md` T&C row | yes | 2.5.1 / 2026-09-13. AUP row still 2026-08-11 (O3) |
| `article-30-register.md` | **no** | Correct: no new processing activity |

SHA pins re-hashed on this tree and equal the literals:

- T&C `TC_DOCUMENT_SHA` = `a66b7fa8e9bd2687ee17a151262eb81c4a50393c74a9f4376b2b626343be0144`
- privacy-policy = `94ddb5b21a1c13db5c9e3a70c3d815e8f40cdbb62bca61810e2878f80c7125ab`
- data-protection-disclosure = `0afd109330be097e034d4f0ab9ffed305b1f6467f4d7f749933d10f9559e14f4`
- gdpr-policy = `4cbed7d90843b17520433077f3654eacd9bf7f5cf18d865220aa2f81ed71904f`
- acceptable-use-policy = `896a401ab93b2f40f997a8187bf515633db2a68af592e7c258be31f9eccf7725`

Local gates on this HEAD: `check-tc-document-sha.sh` exit 0 (includes `BODY_EQUIVALENCE_DOCS` for T&C, AUP, disclaimer); `lint-legal-mirror-drift-baseline.sh --base origin/main` exit 0; `lint-legal-scope-block-placement.sh --base origin/main` exit 0; `legal-doc-consistency.test.ts` + `legal-doc-shas-guard.test.ts` 43/43.

## §1 — Implementation-detail claims, checked against the files

The Plugin **is** a locally installed plugin for Grok Build as well as Claude Code. `plugins/soleur/lib/harness.ts` maps Soleur workflow invocations onto Claude Code, Grok Build, Codex, or Devin CLI; Grok markers are `GROK_HOME` / `GROK_AGENT` / `GROK_DEFAULT_MODEL` / `GROK_SUBAGENTS`. CONTRIBUTING.md and `knowledge-base/engineering/grok-onboarding.md` describe the same in-repo plugin loading locally via `.grok/config.toml`. That is a user-CLI relationship, not Jikigai intermediating xAI.

Locked constraints, verified:

- Cookie-policy and disclaimer were not in the diff. Both still contain "Claude Code plugin" on canonical and mirror.
- `git grep xAI docs/legal/` returns denial sentences and the Privacy Policy §5.1 lead only. No processor-table row names xAI. DPD §4.2 processor table is unchanged (Anthropic PBC remains a Jikigai processor for Jikigai-keyed jobs; the "Direct customer of Anthropic" inference row is the user's own relationship).
- `git grep 'grok --trust'` over `docs/legal/` and Eleventy legal pages: none. Live `grok --help` on CLI 1.0.29 has no `--trust` flag.
- T&C and AUP normalised bodies still match (SHA-guard body-equivalence step exit 0). Privacy / DPD / GDPR `**Last Updated:**` lines were not edited (pre-existing #7465 drift). `**Amended:** September 13, 2026` is present on both surfaces of those three. T&C and AUP Last Updated lines are 13 September 2026 on both surfaces (T&C Eleventy hero included).

## §2 — F1 — GDPR §2.2 half-applied replacement (blocking)

This PR's GDPR intro now says Soleur is "a locally installed plugin for supported AI coding CLIs (including Claude Code and Grok Build)".

The next edited-document section that describes what the Plugin *does* with an AI provider was not updated. GDPR Policy §2.2, first bullet, still reads:

> **Anthropic (Claude API) — locally-installed Soleur plugin:** When you run the Soleur **plugin** on your own machine and invoke its agents and skills, requests are sent to Anthropic's Claude API using **your own** API key.

That sentence is true of Claude Code and **false of Grok Build**. The Eleventy mirror carries the identical sentence (gates green, truth not measured). The next bullet in the same section is the #7100 split that already records the cost of an unqualified "the plugin sends to Anthropic under your key" claim: it was "accurate for the locally-installed plugin and **affirmatively false**" of Jikigai-operated processing. This PR recreates that shape on the other axis — harness, not credential-holder.

Privacy Policy §5.1 in **this same PR** did the correct thing: it named the dual CLI relationship ("Anthropic through Claude Code; xAI through Grok Build") and then scoped the Anthropic bullets with "When you use Claude Code:". GDPR did not. The GDPR Policy is the document the house CLO instructions flag as the one most often missed when the three privacy/GDPR surfaces move together.

Required repair (parent applies; this review does not silently edit legal prose, because a GDPR body edit is a three-file lockstep — canonical, Eleventy, SHA pin — not a one-line patch):

1. Qualify the §2.2 sentence to Claude Code, matching Privacy Policy §5.1.
2. Do **not** add xAI as a Jikigai processor or sub-processor.
3. A Grok analogue, if added, must state the user's own CLI relationship and "Soleur does not intermediate", the way the Anthropic plugin-local bullet already does.
4. Lockstep `plugins/soleur/docs/pages/legal/gdpr-policy.md`.
5. Re-pin `LEGAL_DOC_SHAS["gdpr-policy"]`.

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

**BLOCKED on F1.** O1–O3 do not independently block. Do not merge until F1 is applied and this review is re-run against the scoped GDPR §2.2 sentence.
