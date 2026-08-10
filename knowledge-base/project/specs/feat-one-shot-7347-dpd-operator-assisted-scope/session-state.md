# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-09-chore-legal-operator-assisted-scope-sentences-plan.md`
- Status: recovered from partial-artifact (planning subagent stalled at the deepen-plan halt gates; the plan body and all deepened sections were already on disk). Continued from `soleur:plan-review` rather than re-running `soleur:plan`.

### Errors

- Planning subagent `Plan + deepen for #7347` terminated on a stream watchdog: no progress for 600s, last emitted line `Running the mandatory deepen-plan halt gates.` No `## Session Summary` was returned, so the Session Summary contract was not satisfied.
- Recovery per one-shot fallback step 1: on-disk artifact check found the plan (62 KB) in the **worktree** (not the bare-root mirror), carrying frontmatter, Overview (§1), Acceptance Criteria (§11), Implementation Phases (§8), and all deepen-plan sections (§12 GDPR gate, §13 ADR/C4, §14 observability, §15 encryption, §16 IaC, §17 hypotheses, §18 user-brand impact, §19 domain review). Judged complete; only the Session Summary emission failed.
- `tasks.md` was NOT written by the subagent. Not treated as blocking — §8 of the plan carries the phase breakdown.
- Scope verification note: the subagent's sweep was NOT taken on trust. Its headline claim (29 sites, not the 4 that condition C5 names) is re-verified during `/work` Phase 0 preconditions before any edit lands.

### Decisions

- **Verified C5 site list is 29, not 4.** Condition C5 names four sites across three files; the plan's claim-indexed sweep of `docs/legal/{data-protection-disclosure,privacy-policy,gdpr-policy}.md` found 29 carrying the claim class (DPD 12, PP 8, GDPR 9). Indexed by **claim**, not by file, per the repo learning that records that defect shipping three times previously.
- **Shape per file:** exactly ONE new heading in the whole change — `N1` = DPD `### 2.1c Operator-Assisted Processing`, slotted between §2.1b and §2.2 so nothing renumbers. All other 28 edits are prose inside existing sections. Collapsed to 11 verifiable strings: 5 substantive blocks + 1 verbatim-reused pointer sentence + 4 fixed limb clauses (DSAR / transfer / breach-audit / retention).
- **Mirror handling — the decisive finding.** `eleventy.config.js` sets `INPUT = "plugins/soleur/docs"`, so `docs/legal/**` is not in the Eleventy input tree, not in `deploy-docs.yml`'s path filter, and read by no Next.js route. `docs/legal/*.md` is the canonical source of record and is published NOWHERE; the mirror at `plugins/soleur/docs/pages/legal/` IS the publicly-readable document. Therefore the substantive prose must land in the mirror regardless of the heading question — `legal-doc-consistency.test.ts` compares heading sequence only (`##`/`###`), never prose bodies, so editing only the canonical would leave the flat denials standing on the live pages with the suite green. This is the undershoot failure mode in a form no CI gate detects.
- **`TC_VERSION` bump NOT engaged; SHA refresh IS mandatory.** `TC_VERSION` governs `terms-and-conditions.md` only, which this change does not touch. Per `tc-version-bump-policy.md` §"Non-T&C legal docs" these three are notice/disclosure documents: no middleware reads a version constant, no WORM acceptance ledger exists, so the re-acceptance mechanic cannot fire and no existing user is forced to re-accept. Empirically confirmed against the three most recent legal-prose commits, none of which touched `tc-version.ts`. The unconditional obligation instead is refreshing `LEGAL_DOC_SHAS[...]` in `legal-doc-shas.ts` in the same PR, enforced by `tc-document-sha-guard` — a required check with NO path filter.
- **Tier 1 (material)** per the policy's own dispositive example ("new sub-processor disclosed in the running text"): edit D5 discloses Anthropic PBC in the DPD's running text. Tier 1 ⇒ **CLO sign-off is the gating signal for merge.**
- **Over-retraction guard is explicit.** DPD §3.1(b) *"No data is transmitted to Soleur-operated servers"* and (d) *"does not establish network connections to Soleur-controlled endpoints"* remain literally true — the operator-assisted egress goes to Anthropic, not to a Jikigai server. The correct key is the register's **credential limb**, not its infrastructure limb, so the pointer attaches to §3.1(a) only. AC-8b asserts (b) and (d) survive verbatim and unqualified. Correcting them would be the documented failure mode: a new false claim introduced inside a correction.
- **Both existing in-repo precedents are insufficient to copy verbatim.** GDPR §2.2 bullet 2 and PP §5.1 scope the Jikigai-keyed path to Jikigai's *"own automated jobs"*; an operator-driven interactive run on a workstation is not an automated job, so verbatim reuse would miss operator-assisted runs again — the exact escape the register's re-key note records happening twice. Every block must name an operator-assisted / guided-onboarding limb explicitly.
- **Deferred, tracked not silent:** `terms-and-conditions.md`, `acceptable-use-policy.md`, `disclaimer.md` scope sentences — editing the T&C engages `TC_VERSION`, forcing every existing user to re-accept and closing live WebSocket sessions. That is a deliberate operator decision, not something to ride in on a chore PR. One tracking issue to be filed in Phase 5.3.

### Open questions for CLO (Q1-Q7, gating merge per Tier 1)

Q1 register-limb traceability · Q2 standing-position vs incident narration · Q3 `Ref #7347` vs plain-English annotation convention · Q4 do not assert the Anthropic transfer mechanism/retention window while determination C6 is open · Q5 whether executing the annex is a "first executed DPA" for the SOC 2 trigger (condition set, not this PR) · Q6 include the GDPR §10 stale "eleven processing activities" fix (register now holds 35) · Q7 whether to correct `article-30-register.md` §0's imprecise §4.1-vs-§4.2 citation.

### Components Invoked

- `soleur:plan` (via isolated planning subagent)
- `soleur:deepen-plan` (via same subagent; stalled at its halt gates after writing output)
- `soleur:plan-review` (parent session, recovery path)
