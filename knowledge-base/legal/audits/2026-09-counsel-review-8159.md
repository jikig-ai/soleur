---
title: "Counsel review audit — #8159 / PR #8155 (Devin Cloud session parity: three-doc provider-operated disclosure floor, Art. 30 scope-test bracket, compliance-posture row; floor-only ceiling ruled; T&C flag-only)"
type: counsel-review
date: 2026-09-16
issue: 8159
pr: 8155
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-16
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED subject to THREE in-PR text corrections (C1–C3, below) that the lead applies before merge. Eight artifacts in scope: the three canonical/mirror disclosure pairs (docs/legal/{data-protection-disclosure,privacy-policy,gdpr-policy}.md and plugins/soleur/docs/pages/legal/{same}), knowledge-base/legal/article-30-register.md and knowledge-base/legal/compliance-posture.md. The doc edits are scope-paragraph extensions, predicate scoping, a classification-table row and additive Corrected paragraphs — no processing purpose, lawful basis, retention period, sub-processor or data-subject right changes; each changed canonical's added text is byte-identical to its Eleventy mirror's, and LEGAL_DOC_SHAS is repinned for all three (legal-doc suites 43/43). Every load-bearing claim was checked against the shipped bodies and the probe record — cloud-detect.sh's `not-local:<reason>` fail-closed contract and `--banner`, hooks.json's `^(Bash|exec)$` matcher, devin-session-start.sh's sentinel fields, precommit-guard.sh's exit contract, and cloud-probe.md's two arms — not against the plan or ADR-221. Three claims in the PR's own bookkeeping text are wrong or mis-shaped against the documents they describe: the new posture row cites privacy-policy §8 where the naming landed in §6 (and omits §3 and §4.2), the same row says the verifying probe 'is deferred at #8172' when the register bracket this same PR adds records it as run and measured, and the register bracket names 'the SessionStart rule injection' as a plugin-hook TOM cited in the register (none is) while counting two limbs of a test the register itself states has three. Those are C1–C3; all three edit only text this PR inserts. Rulings: the floor-only taxonomy suffices for v1 (every taxonomy-asserting paragraph in the corpus now names the third configuration directly or resolves it through the DPD §2.1c cross-reference, which post-merge enumerates all three); no TC_VERSION amendment is required now — the flag-only posture stands because T&C's scope paragraphs defer the taxonomy to §2.1c and no obligation changes in the provider-operated configuration (if ever amended it is Tier 2 clarifying, PATCH, and it rides the next otherwise-required T&C edit); the 'no Cognition processor row / no DPA' reasoning and the D10 prohibition wording are confirmed. No MUST-NOT limit is breached. No Art. 33 and no Art. 34 duty arises: nothing was destroyed, lost, altered or disclosed; this is a documentation-scoping change and no personal-data event occurred."
blocking_findings: []
required_before_merge_DISCHARGED:
  - "C1 — compliance-posture.md new Completed-Work row: 'provider-operated named at §§2, 4.1, 8 (legal-basis \"What this covers\") and 10' mis-cites the privacy-policy map — the legal-basis 'What this covers' paragraph is §6 (Legal Basis for Processing), not §8 (Your Rights, untouched), and the naming also sits in §3 and §4.2. The same §8-for-§6 error sits in the spec tracker at knowledge-base/project/specs/feat-devin-cloud-session-parity/tasks.md's Phase-5 floor line ('§§3/4.1/4.2/8/10'), and the tracker's register line repeats the two-limb count ('out of scope on both limbs') of a test the register itself states has three. Exact text under §Conditions."
  - "C2 — compliance-posture.md same row: 'the verifying probe is deferred at #8172' is stale and is contradicted by the register bracket this same PR adds — the probe ran 2026-09-15 on two arms and measured zero hook dispatch on any registration surface; only the residual arms defer to #8172. The same clause's '(credential-path `PreToolUse` deny, SessionStart injection)' names a hook that is not a TOM cited in the register. Exact text under §Conditions."
  - "C3 — article-30-register.md appended bracket: 'neither limb holds there either' counts two limbs of an inclusion test the register itself corrects to three ('All three limbs, not two'), and the parenthetical '(for example the credential-path `PreToolUse` deny and the SessionStart rule injection)' presents as cited-TOM examples a SessionStart context emit that appears nowhere in this register and is not a control; the '— locally' gloss also mis-describes where the plugin's hook surface runs. Exact text under §Conditions."
optional_precision_notes:
  - "O1 — The pre-existing Posture-A sentence this bracket extends reads 'Neither limb holds: Jikigai determines no purpose and no Jikigai credential is involved' — the same two-limb shorthand C3 removes from the new text, on main since the 2026-08-06 re-key. Harmless where it sits (on the user's own machine the infrastructure limb patently fails too) and outside this PR's added text, so not conditioned; supersede or leave at the next register edit."
  - "O2 — Two under-enumerations remain in DPD, both one-clause fixes at the next canonical edit and neither false: (i) §4.1's self-scoping sentence plus 'Operator-assisted sessions are the exception' is the one taxonomy-adjacent paragraph in the three changed documents that does not name provider-operated — asymmetric with privacy-policy §4.2, which gained the third-exception paragraph, but §4.1's 'no Plugin-level Sub-processors' claim holds a fortiori in the provider-operated configuration; (ii) §2.3's closing pointer — 'Operator-assisted processing and Jikigai-purpose access are described in Section 2.1c' — now under-enumerates §2.1c's three contents. Not conditioned: neither asserts exhaustiveness and neither misleads about a Jikigai role."
  - "O3 — Corpus residual under the floor-only ruling: AUP §§2/5.1/6.1 and Disclaimer §4.1 keep unqualified 'operates locally' predicates, and T&C §§4.1/4.2/8.1 keep two-configuration scope paragraphs. On the merge of PR #8155, which adds `.devin/config.json` `requiredPlugins` and so makes the provider-operated session a configuration Jikigai itself ships, those predicates become descriptively incomplete — but each is either quarantined by a scope paragraph that defers the taxonomy to DPD §2.1c (T&C) or allocates no Jikigai role (AUP/Disclaimer). Fold the third-configuration naming into each document's next otherwise-required edit; no sweep is warranted now."
  - "O4 — The web-app probe arm's built-in `run_subagent` surface does not rehabilitate the agent roster the disclosures treat as absent: Soleur's `agents/**` are plugin-defined and unavailable on either arm, so the sequential-fallback disclosure stands unchanged. Recorded so a future reader does not mistake the DRS/web-app divergence for a crack in the 'no plugin subagents' claim."
attests:
  - "docs/legal/data-protection-disclosure.md and plugins/soleur/docs/pages/legal/data-protection-disclosure.md — the #8159 additions ONLY (Corrected paragraph; §2.1/§2.1(c)/§3.1(a) plugin-local scoping; §2.1c provider-operated naming + fifth classification row; the ten extended scope paragraphs)"
  - "docs/legal/privacy-policy.md and plugins/soleur/docs/pages/legal/privacy-policy.md — the #8159 additions ONLY (Corrected paragraph; §§2/3/4.1/4.2/6/10 provider-operated naming; §4.2 third-exception paragraph; §11 premise rewording)"
  - "docs/legal/gdpr-policy.md and plugins/soleur/docs/pages/legal/gdpr-policy.md — the #8159 additions ONLY (Corrected paragraph; all seven scope paragraphs + the §8.1 wrapped variant extended; §2.1/§7.1 predicates scoped)"
  - "knowledge-base/legal/article-30-register.md — the appended scope-test bracket ONLY (provider-operated out of scope; control-coverage-not-scope statement; two-arm probe record; D10 in-scope prohibition)"
  - "knowledge-base/legal/compliance-posture.md — the new Completed-Work row ONLY (subject to C1 and C2)"
does_not_attest:
  - "docs/legal/terms-and-conditions.md and its mirror — deliberately untouched; the flag-only posture is ruled acceptable (§Rulings R2)"
  - "docs/legal/{acceptable-use-policy,disclaimer,cookie-policy}.md — untouched residuals; see O3"
  - "plugins/soleur/scripts/cloud-detect.sh, plugins/soleur/hooks/{devin-session-start.sh,hooks.json}, plugins/soleur/scripts/precommit-guard.sh, the .claude/.openhands guardrails, and knowledge-base/project/specs/feat-devin-cloud-session-parity/cloud-probe.md — engineering evidence every legal claim was checked against; attested as evidence, not as legal records"
  - "knowledge-base/project/specs/feat-devin-cloud-session-parity/tasks.md — spec tracker; the C1 sibling fix is conditioned there but the file is not an attested artifact"
art_33_triggered: false
art_34_triggered: false
re_evaluation_triggers: "Any Jikigai-held credential or Jikigai purpose ever reaching a provider-operated session — the D10 prohibition bars it until Cognition is a contracted Jikigai processor under Art. 28(3) with the required transfer mechanism, and the named vendor row becomes due at that point; a change in Cognition's processor/DPA posture fires the same review. #8172's residual probe arms contradicting the zero-hook-dispatch measurement. #8160 landing an upstream hook surface in cloud sessions — control coverage expands and every 'hooks absent' sentence re-runs. #8205's per-hook review of the `.claude/settings.json` `Bash` matcher class. The next T&C body edit folds the third-configuration naming per R2/O3. #7465's mirror-drift remediation unfreezing the Last Updated lines. Standing external-counsel triggers unchanged."
---

# Counsel review audit — #8159 / PR #8155 (provider-operated session disclosure floor)

This file is the load-bearing evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on
PR #8155 (spec threshold `single-user incident`). The legal surface in the PR is the three-doc
disclosure floor, the Article 30 scope-test bracket, and the compliance-posture row. The CLO agent
is the v1 attestation authority; the operator holds an optional veto.

## Scope and limit check

- **Attested set.** Eight files: the three `docs/legal/` canonicals and their Eleventy mirrors,
  `article-30-register.md`, `compliance-posture.md`. `terms-and-conditions.md` is deliberately
  untouched and is ruled on, not attested (R2).
- **Notice docs, not contracts.** The three changed canonicals carry no version constant and no
  acceptance ledger; the `LEGAL_DOC_SHAS` repin ×3 is the unconditional SHA-refresh contract of
  `tc-version-bump-policy.md` §Non-T&C legal docs, satisfied in-PR.
- **`Last Updated` freeze honored.** No `Last Updated` line is touched on any changed doc; the
  canonical↔mirror drift on that line is frozen by `lint-legal-mirror-drift-baseline.sh` (#7465),
  and each doc instead carries an additive `Corrected September 14, 2026 (#8159)` paragraph per the
  #7786 convention.
- **Mirror lockstep.** For each of the three pairs, the changed content is byte-identical between
  canonical and mirror; `legal-doc-consistency.test.ts` + `legal-doc-shas-guard.test.ts` run 43/43
  from `apps/web-platform`.
- **No Art. 33/34 surface.** Nothing was destroyed, lost, altered, disclosed or accessed; this is a
  documentation-scoping change over a probe that processed no personal data (env-var names, hook
  dispatch absence, plugin lock metadata only — cloud-probe.md §Method).

## Drift table

| # | Claim added | Checked against (file / anchor) | Verdict |
|---|---|---|---|
| D1 | DPD §2.1c names the provider-operated session; its classification table gains a fifth row ("Neither Controller nor Processor — no limb is Jikigai's; the provider's own terms govern the machine") | `data-protection-disclosure.md` §2.1c fifth table row + "three things" preamble; register's three-limb inclusion test | **Holds** |
| D2 | Every taxonomy-asserting paragraph in the three docs names the third configuration | Enumeration: DPD — all ten `**Scope.**` paragraphs extended (document intro + §§2.1, 2.2, 3.1, 4.3, 5.1, 6.1, 7.1, 9.1, 10.1); privacy — naming at §§2, 3, 4.1, 4.2, 6, 10 plus the §4.2 third-exception paragraph; GDPR — all seven `**Scope.**` paragraphs + the §8.1 wrapped variant | **Holds** (one sibling left unnamed → O2) |
| D3 | "No limb is Jikigai's" for a provider-operated session | Register test limbs 1–3: no Jikigai purpose, no Jikigai-held credential, no Jikigai-operated infrastructure or Jikigai account; cloud-probe.md credential determination (Devin account and billing personal; no Jikigai-issued key reachable) | **Holds** |
| D4 | Register bracket: the probe ran two arms and measured zero hook dispatch on any registration surface | `cloud-probe.md`: web-app arm `4c574cf0fa594527bb3f9650c05b74a7`, DRS sandbox arm `b9cf2c02cc8f49debdbc49ed72cdf2b5`, both 2026-09-15; "no hook dispatch on any surface" is a cross-arm agreement | **Holds** |
| D5 | No Cognition processor row; named vendor entry probe-conditional | Register §"Sub-processors" mapping carries no Cognition row; reasoning sound — in the provider-operated configuration Cognition is the *user's* vendor under the user's own account, and Jikigai owes no Art. 28(3) instrument for processing it neither controls nor effects | **Holds** |
| D6 | D10 prohibition: a Jikigai-credentialed or Jikigai-purpose provider-operated session carrying user personal data is prohibited until the provider is a contracted Jikigai processor (Art. 28(3) + transfer mechanism/SCCs) | Brainstorm D10 (2026-09-14) prohibits the Jikigai-credentialed shape; the register/posture widening to Jikigai-purpose is a faithful generalization — limb 1 fires on the same test | **Holds** |
| D7 | Posture row: "provider-operated named at §§2, 4.1, 8 (legal-basis 'What this covers') and 10" | Privacy-policy section map: naming sits at §§2, 3, 4.1, 4.2, 6 and 10; §8 is "Your Rights" and is untouched; the legal-basis "What this covers" is §6 | **FALSE → C1** (§8-for-§6; §§3 and 4.2 omitted) |
| D8 | Posture row: "the verifying probe is deferred at #8172" | `cloud-probe.md` (ran 2026-09-15, two arms) and the register bracket this same PR adds ("verified, not asserted"); #8172 carries only residual arms | **FALSE/stale → C2** |
| D9 | Register bracket: "plugin-hook TOMs cited in this register (for example … the SessionStart rule injection) … — locally"; "neither limb holds there either" | `grep -n SessionStart article-30-register.md` → the only occurrence is inside this bracket; the cited plugin-hook TOM is the PA-8 §(g) credential-path `PreToolUse` deny in `plugins/soleur/hooks/hooks.json`; the inclusion test states "All three limbs, not two"; a Jikigai machine running the full plugin in an operator-assisted session runs the hook surface — "locally" is not the discriminator | **FALSE-shaped → C3** |
| D10 | Mirror lockstep + repins | Normalized canonical/mirror diff identical ×3; `npx vitest run test/legal-doc-consistency.test.ts test/legal-doc-shas-guard.test.ts` from `apps/web-platform` → 43/43; `lint-legal-mirror-drift-baseline.sh` within baseline | **Holds** |
| D11 | `Last Updated` lines untouched; additive Corrected paragraphs instead | `git diff main...HEAD` touches no `Last Updated` line; #7465 freeze honored | **Holds** |
| D12 | Honest-degradation machinery the disclosures rest on: no plugin subagents and no hook dispatch in cloud; sequential fallback; secrets/production acknowledgement or hard-defer; commit-on-main refusal independent of hooks | `cloud-detect.sh` emits `local` or `not-local:<reason>` (`sentinel-absent`, `no-devin-env`, `malformed`, `foreign-host`, `non-plugin-source`, `conflicting-evidence`) and `--banner` names the absent surfaces; `hooks.json` matcher `^(Bash\|exec)$`; `devin-session-start.sh` writes `{host,ts,hook_source}` and preserves a plugin-sourced sentinel; `precommit-guard.sh` exits 0/1/2 per shell segment; probe: `ask_user_question` absent, `message_user` blocks | **Holds** |
| D13 | T&C deliberately untouched; its scope paragraphs name only two configurations | `terms-and-conditions.md` §§4.1/4.2/8.1 scope paragraphs each defer the taxonomy to "the Data Protection Disclosure Section 2.1c"; `TC_DOCUMENT_SHA` unchanged; no T&C diff | **Holds** — and is the ground for R2 |

## Findings

- **F1 (C1).** A section mis-citation in the posture row. "§8 (legal-basis 'What this covers')" is
  wrong on the document's own heading map — §8 is "Your Rights"; the legal-basis "What this covers"
  paragraph sits in §6 — and the enumeration omits §3 and §4.2 where the naming also landed. The
  privacy policy's own Corrected paragraph enumerates the scoped predicates accurately ("Sections 3,
  4.1, 4.2 and 11"), so this is a bookkeeping-row defect, not a document defect — the #7349 class of
  a record asserting about a document what the document does not contain. The spec tracker's
  Phase-5 floor line carries the same §8-for-§6 and is fixed with it.
- **F2 (C2).** A stale deferral that contradicts the PR's own register text. The row says "the
  verifying probe is deferred at #8172"; the register bracket added in the same PR records the probe
  as run — two arms, zero hook dispatch, "verified, not asserted" — and defers only residual arms to
  #8172. One PR must not contain a posture row and a register bracket asserting opposite states of
  the same measurement.
- **F3 (C3).** Three mis-shapings in one register sentence. "Neither limb holds there either" counts
  two limbs where the register's own correction paragraph states three ("All three limbs, not two")
  — and for this configuration the limb that must be named is the infrastructure limb, the very one
  the shorthand omits. "The SessionStart rule injection" is presented as a plugin-hook TOM cited in
  this register; no such TOM exists here (the register's plugin-hook citation is the PA-8 §(g)
  credential-path `PreToolUse` deny in `plugins/soleur/hooks/hooks.json`), and `devin-session-start.sh`
  is a context emit, not a control — naming it as a TOM would imply a protection the surface does not
  carry. The "— locally" gloss mis-describes the discriminator: the hook TOMs execute wherever a
  session loads the plugin's hook surface, which includes a Jikigai machine under an operator-assisted
  session, not only user-local machines.
- **F4.** No other document must change for the floor to be honest. The three canonicals' scope
  paragraphs now name all three configurations everywhere the taxonomy is asserted (D2), the
  register's inclusion test already reaches the right answer (D3), and the prohibition that bounds
  the dangerous configuration is recorded twice, consistently (D6). What remains is enumeration
  accuracy in the bookkeeping — C1–C3 — and the residual corpus flagged under O3.

## Rulings

- **R1 — Ceiling (tasks.md open item, closed here).** Floor-only suffices for v1. Every paragraph in
  the corpus that asserts the plugin-local/operator-assisted taxonomy now either names the
  provider-operated configuration itself (the three changed docs) or expressly defers the taxonomy
  to DPD §2.1c, which post-merge enumerates all three (T&C §§4.1/4.2/8.1). The residual unqualified
  "operates locally" predicates in AUP and Disclaimer allocate no Jikigai role and mislead no reader
  about a Jikigai obligation; a corpus-wide sweep would force notice-doc repins and a T&C
  re-acceptance for a clarification that changes no obligation — disproportionate to the residual.
  The tasks.md ceiling item is **closed by this ruling**: the third-configuration naming folds into
  each residual document's next otherwise-required edit (O3).
- **R2 — TC_VERSION.** No amendment required now; the flag-only posture is acceptable. T&C §§4.1,
  4.2 and 8.1 are scoping provisions that correctly bound their own paragraphs and hand the taxonomy
  to "the Data Protection Disclosure Section 2.1c" — which is precisely the section this PR extends.
  The load-bearing substantive claim ("does not collect, transmit, or store your data on remote
  infrastructure controlled by us") remains true in the provider-operated configuration: Jikigai's
  servers stay out of the chain. No user obligation shifts, so a reader following the cross-reference
  reaches the correct three-configuration enumeration. If the naming is ever folded into the T&C
  body, the change is **Tier 2 clarifying → PATCH** under `tc-version-bump-policy.md` (re-wording a
  provision to make an already-implicit scope explicit); it should ride the next otherwise-required
  T&C edit rather than force a standalone re-acceptance.
- **R3 — No Cognition processor row / no DPA: confirmed.** In the provider-operated configuration
  Cognition contracts with the *user* under the user's own account and credentials; Jikigai is
  neither controller nor processor for that processing and so owes no Art. 28(3) instrument. A named
  Cognition vendor entry is correctly probe-conditional: it becomes due only if a Jikigai limb ever
  attaches — which is the prohibited configuration under D10, not a processing shape to pre-register.
- **R4 — D10 prohibition wording: confirmed.** The brainstorm's D10 bars a Jikigai-credentialed
  cloud session carrying user personal data until Cognition is a contracted Jikigai processor
  (Art. 28(3) + SCCs). The register and posture row widen the trigger to "Jikigai-held credential or
  Jikigai purpose"; that is a faithful generalization, not a drift — a Jikigai-purpose session fires
  limb 1 of the same inclusion test and carries the same disclosure obligation to an uncontracted
  third-party machine.
- **R5 — SC5 disposition.** DISCHARGED subject to C1–C3 applied before merge. The corrections are
  confined to bookkeeping text this PR inserts; the published-facing disclosure text itself (the
  three canonicals and mirrors) verifies clean and needs no further edit for v1.

## Conditions

All three edit only text that this PR inserts; none touches a `Last Updated` line, a canonical
scope paragraph, or any pre-existing register sentence.

**C1 — `knowledge-base/legal/compliance-posture.md` new row, and the sibling in
`knowledge-base/project/specs/feat-devin-cloud-session-parity/tasks.md`.**

In the posture row, replace:

> privacy-policy §§3, 4.1, 4.2 predicates scoped; third-exception paragraph added to §4.2; provider-operated named at §§2, 4.1, 8 (legal-basis "What this covers") and 10.

with:

> privacy-policy §§3, 4.1 and 4.2 predicates scoped (§11's local-machine premise reworded to a no-transmission claim that holds in every configuration); provider-operated named at §§2, 3, 4.1, 4.2 (the §4.2 third-exception paragraph), 6 (the legal-basis "What this covers") and 10.

In tasks.md's Phase-5 floor line, replace:

> privacy-policy §§3/4.1/4.2/8/10 scoped + third-exception paragraph

with:

> privacy-policy §§2/3/4.1/4.2/6/10 scoped + §4.2 third-exception paragraph + §11 premise reworded

and in the same file's register line, replace:

> (provider-operated out of scope on both limbs;

with:

> (provider-operated out of scope on all three limbs;

**C2 — `knowledge-base/legal/compliance-posture.md` same row.** Replace:

> appended-bracket amendment records that plugin-hook TOMs (credential-path `PreToolUse` deny, SessionStart injection) do not execute on provider-operated machines — control coverage, not scope, is what changes — and that the verifying probe is deferred at #8172.

with:

> appended-bracket amendment records that the plugin-hook TOM cited in the register (the credential-path `PreToolUse` deny at PA-8 §(g), registered in `plugins/soleur/hooks/hooks.json`) does not execute on provider-operated machines — control coverage, not scope, is what changes — verified, not asserted, by the two-arm probe (`cloud-probe.md`, measured 2026-09-15: zero hook dispatch on any registration surface on both the DRS-sandbox and user-facing web-app arms); the residual arms defer to #8172.

**C3 — `knowledge-base/legal/article-30-register.md` appended bracket.** Replace:

> **[Added 2026-09-14 (#8159).] The same conclusion holds for a provider-operated session** — the Plugin running on a third party's machine (for example a Devin Cloud session on a Cognition-managed VM) under the user's own credentials for the user's own purposes: neither limb holds there either, so Jikigai is neither controller nor processor for it, and the provider's own terms govern the machine (DPD §2.1c fifth row). What changes on that surface is **control coverage, not scope**: plugin-hook TOMs cited in this register (for example the credential-path `PreToolUse` deny and the SessionStart rule injection) execute only where the plugin's hook surfaces run — locally — so they protect only the configurations where they run, and no provider-operated session should be described as carrying them.

with:

> **[Added 2026-09-14 (#8159); probe clause measured 2026-09-15.] The same conclusion holds for a provider-operated session** — the Plugin running on a third party's machine (for example a Devin Cloud session on a Cognition-managed VM) under the user's own credentials for the user's own purposes: no limb of the test holds there either — no Jikigai-determined purpose, no Jikigai-held credential or account, and no Jikigai-operated infrastructure — so Jikigai is neither controller nor processor for it, and the provider's own terms govern the machine (DPD §2.1c fifth row). What changes on that surface is **control coverage, not scope**: the plugin-hook TOM cited in this register — the credential-path `PreToolUse` deny at PA-8 §(g), registered in `plugins/soleur/hooks/hooks.json` — executes only on a machine whose session loads the plugin's hook surface, so it protects the configurations where that surface runs (plugin-local, and an operator-assisted session that installs the full plugin), and no provider-operated session should be described as carrying it.

No other text change is required. O1–O4 are non-blocking.

## Verification commands (re-runnable from the worktree)

- `diff <(sed -e 's/Last Updated.*//' docs/legal/data-protection-disclosure.md) <(sed -e 's/Last Updated.*//' plugins/soleur/docs/pages/legal/data-protection-disclosure.md)` — and the same pair for `privacy-policy.md` and `gdpr-policy.md` → identical normalized bodies (D10).
- `cd apps/web-platform && npx vitest run test/legal-doc-consistency.test.ts test/legal-doc-shas-guard.test.ts` → 43/43 (D10).
- `bash scripts/lint-legal-mirror-drift-baseline.sh` → within the #7465 baseline (D10/D11).
- `git diff main...HEAD -- docs/legal/ | grep -c 'Last Updated'` → 0 changed `Last Updated` lines (D11).
- `grep -n 'provider-operated' docs/legal/privacy-policy.md` → §§2, 3, 4.1, 4.2, 6, 10; nothing in §8 (D7/C1).
- `grep -n 'SessionStart' knowledge-base/legal/article-30-register.md` → the only occurrence is inside the new bracket; the cited plugin-hook TOM is the PA-8 §(g) `PreToolUse` deny in `plugins/soleur/hooks/hooks.json` (D9/C3).
- `grep -n 'All three limbs' knowledge-base/legal/article-30-register.md` → the register's own three-limb correction paragraph (D9/C3).
- `grep -n 'matcher' plugins/soleur/hooks/hooks.json` → `^(Bash|exec)$` on the credential-path `PreToolUse` entry (D12).
- `grep -n 'zero hook dispatch\|4c574cf0\|b9cf2c02' knowledge-base/project/specs/feat-devin-cloud-session-parity/cloud-probe.md` → two arms, zero hook dispatch on every registration surface (D4/D8).
- `grep -n 'requiredPlugins' .devin/config.json` → the merge-time fact that makes O3's residual descriptive (conditional-tense basis).
- `gh issue view 8159 --json state` → OPEN; `gh pr view 8155 --json state` → OPEN (WIP); `gh issue view 8172 --json state` → OPEN; `gh issue view 7465 --json state` → OPEN; `gh issue view 8160 --json state` → OPEN.

## Lead application record (2026-09-16)

- **C1–C3** were applied verbatim by the lead: the compliance-posture row's privacy-policy
  section map and probe clause corrected (C1, C2); the same §-map and the "both limbs" →
  "all three limbs" fix applied to `tasks.md` (C1's sibling edits); the Art. 30 register
  bracket rewritten with the three-limb enumeration, the PA-8 §(g)-registered TOM
  identified by name, and the probe clause re-dated (C3). All edits touch only text this
  PR inserts.
- **Side effects of this audit (applied by the CLO, not attested text):** the audit file itself is
  waived as not-a-determination in `scripts/lint-legal-registers.sh` `NOT_TRANSCRIBED` and in the
  `breach-register.md` waiver table, following the #8043/#8189 precedent; the breach-register waiver
  count sentence is restated to eighteen rows (it read "sixteen" against a table that already held
  seventeen); the tasks.md ceiling checkbox is marked resolved by R1; `knowledge-base/INDEX.md` is
  regenerated by `scripts/generate-kb-index.sh` so the auto-generated index lists this audit.
