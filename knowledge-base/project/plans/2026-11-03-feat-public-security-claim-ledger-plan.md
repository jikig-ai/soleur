---
title: "feat: internal public-security-claim ledger (item of #9601, issue #9603)"
type: feat
date: 2026-11-03
slug: public-security-claim-ledger
branch: feat-one-shot-9603-public-security-claim-ledger
issue: 9603
refs: [9603, 9601]
closes: none
priority: p3-low
domain: legal
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: false
---

# feat: internal public-security-claim ledger (#9603)

## Enhancement Summary

**Deepened on:** 2026-11-03 (after the five-seat plan-review panel and 20 CTO rulings).
**Method:** the deepen halts and quality checks were run mechanically against this documentation-only plan; the broad agent fan-out was not repeated because the plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer) and the plan-time CLO and CTO consults had already covered every section, and a second fan-out would only re-read the same ADRs.

**Halts and checks (all pass):** User-Brand Impact present with threshold `single-user incident` (4.6); Observability skipped, pure-docs (4.7); no PAT-shaped variable (4.8); no UI surface, no wireframe needed (4.9); no store or connection (4.10); no guard deliverable (4.11); exactly one unfenced `## Scope Check`, a `Recommendation:` line, zero `unmapped` cells, no BLOCKED marker (4.12); no new autonomous task (4.13). Every cited ADR file (14), issue and PR was re-resolved live with `gh` and `git`; the one cited rule id (`wg-ui-feature-requires-pen-wireframe`) is an active rule. AC1 was run against synthetic archived and live paths (clean copy prints 0, forbidden copy prints 5, the branch diff prints 0), and AC2's pattern and negative control print 0 and 1.

### Key improvements folded in from review
1. Status model hardened: flag tags `[residual]` and `[prod-unmeasured]`, owning-ADR `accepted` requirement, host class, measured-commit SHA with decay check, weakest-mapped-row rule (D17 to D19).
2. Findings given a closed type and a disposition with an `escalate` stop, plus neutral wording rules (D20).
3. Acceptance criteria made runnable and non-vacuous: count-based negated greps, concrete column-extraction commands, census-based Part 2 check, split AC6a and AC6b, and an ordering that puts the fresh CLO review last.
4. Candidate rows corrected against the ADR corpus (ADR-075 later addenda, ADR-052 scope, ADR-305 legacy-runner scope, ADR-277 re-filed under approval).

### New considerations discovered
- The ship counsel-review gate stays quiet only because the PR body carries no plan path; any plan link in the body makes it fire (Findings For The Lead item 1).
- Archive timestamps starting 01, 11 or 21 followed by 12:37 can contain the withheld digit string.
- ADR-272 cannot pass the Publication Criterion until its own status text reads `accepted`, which is outside this PR.

## Overview

Issue #9603 asks for a public security/control page once hosted-agent controls are measured. The CTO ruled a narrower scope for this PR (2026-11-03): one internal ledger file, `knowledge-base/legal/public-security-claim-ledger.md`, recording per claim topic across isolation, egress and human approval which control would measure it, its status and its evidence; a check of what public surfaces already say; and the criterion any future public sentence must meet. No page, no gate script, no public-surface edit and no issue traffic ships here. The CLO agent prepares the ledger at work time; this plan fixes its structure, its candidate row set (verified at plan time, re-verified at work time), its checks and its review path. Rulings: `knowledge-base/project/specs/feat-one-shot-9603-public-security-claim-ledger/decision-challenges.md` (D1 to D20). The PR carries `Ref #9603` and `Ref #9601` only; #9603 stays open and unticked in the #9601 checklist.

## Standing Constraints (operator, not steps of this PR)

These bind the work. None is an action this PR takes, and none is delegable (the epic has no Standing Delegation).

- Creating or flipping any feature flag (broker, approval queue, egress-audit collection) and creating or changing any environment are out of scope and are not performed, requested or prepared by this PR.
- The egress-audit enablement issue is not worked, not referenced and not closed. Its number never appears in the diff (plan, tasks, spec, ledger, decision-challenges), the PR body or any comment; every artifact calls it "the egress-audit enablement issue".
- No production write that needs approval is made. Live flag states are read only by read-only means; a state that cannot be fully read is recorded `unverified: <missing source>`.
- Legal-wording sign-off at flag-on stays with the human principal; the CLO agent only prepares material and reviews it.
- No public security claim is made ahead of a measured control.
- `docs/legal/**`, `plugins/soleur/docs/**` and in-app toggle copy stay unchanged.
- The repository is public, so everything under `knowledge-base/` is already world-readable; "unpublished" does not mean "under knowledge-base", which is why no draft page sentence is written anywhere.

## Research Reconciliation — Spec vs. Codebase

Verified as seeded (no correction): image scan advisory (ADR-281 adopting, non-gating); credential broker not shipped (ADR-311 adopting, measurement only; #9543 open); per-session containers and Landlock `proposed` (ADR-315, ADR-316; #9602 open); #9851 open; untrusted-content and approval-queue flags default OFF in code (`FLAG_APPROVAL_QUEUE=0` in `.env.example`; flags `untrusted-content-classify`, `untrusted-content-wrap`, `approval-queue`).

| Claim (issue #9603 body, CTO brief seed list) | Reality at origin/main (f05eaab78f) | Plan response |
|---|---|---|
| Issue: the Art. 30 register, Privacy Policy and DPD "carry no agent-isolation claim today". | Stale. `knowledge-base/legal/article-30-register.md` carries qualified TOM entries for ADR-272 key withholding and ADR-075 arm F; `docs/legal/acceptable-use-policy.md` section 5.8, `gdpr-policy.md` section 3.16 and `privacy-policy.md` carry egress statements; `web-egress-toggle.tsx` carries a credential statement; a 2026-03-29 blog post carries credential-isolation statements. | Ledger section 7 corrects the premise; Part 2 maps each statement. |
| Issue: revisit when "the egress audit log (#9545) exists". | #9545 closed; PR #11115 merged and an ancestor of origin/main; the epic #9601 body (state 2026-10-28) says deployed, collection OFF for external organisations; code default OFF. | Row `dark`; live prd state `unverified` unless fully read. |
| Issue: "page (or section)". | CTO ruling: ledger only. | No page, no draft sentences. |
| Seed: owner-key withholding (ADR-272) `measured`. | ADR-272 status is `adopting` (acceptance gated on a production-image canary). Measured on a dev host with decoy values and in CI with real bubblewrap; covers the Anthropic auth variables only. The ADR text still says the canary is pending although #9614 is closed. | D7, D17, D18: `measured`, scope in descriptor, tags `[residual]` and `[prod-unmeasured]`, host class `dev-host`/`CI-runner`; fails C1 until the ADR text says `accepted`. |
| Seed: cross-tenant isolation via the outer wrap `dark`. | Correct for arm F (`AGENT_OUTER_WRAP` must equal "1"; ADR-075 addendum 2026-10-08 (#5863): `adopting`, "claim held until production measurement, per #9603 discipline"). ADR-075 base read isolation is `accepted` but later addenda record residuals: shared-HOME CLI state readable by a sibling (2026-10-31), file tools contained only by a PreToolUse hook outside bwrap, AF_UNIX denial not enforced in the inner sandbox (2026-10-16) with a flag-gated second filter (2026-10-19). | Split: base read isolation scoped to Bash tool filesystem reads (`measured`, tags); file-tool hook row; outer wrap `dark`; AF_UNIX flag-gated filter row (CLO classifies from the addenda); residuals by pointer only. |
| Seed: plugin destructive-command guard (ADR-277) `measured`. | ADR-277 `accepted` with open CPO3-R2/R3 items and a non-coverage list; scope is the plugin on customer machines; hook OFF in hosted sessions; hosted ask path unmeasured. | Row in the A series, scope in descriptor, host class `CI-runner`; a hosted-session statement may not map to it alone (D19). |
| Seed: the gated-tier mechanism (ADR-305, PR #11304). | ADR-305 `accepted`; closes the pre-approval in the legacy runner; `apps/web-platform/test/build-allowed-tools-census.test.ts` is a static invariant; the ADR names a real-SDK probe as instrument. | D11: cite by ID only, no dates, no defect wording, pointer "see the existing CLO determination (PR #11443)"; descriptor says "legacy runner only"; CLO re-verifies which artifact is the instrument. |
| Seed: egress default-off for hosted sessions. | ADR-052 covers the cron population inside the platform container, not hosted sessions; ADR-278 is `accepted`, ships dark, toggle default off. | Split E1a (default-off outbound; instrument the CLO finds, else `advisory`) and E1b (opt-in gateway, `dark`); gateway-monitoring statement folded into E1b evidence. |
| Brief: CLO review record. | The ship counsel-review gate names `knowledge-base/legal/audits/<YYYY-MM>-counsel-review-<issue>.md`, outside the allowed list. The register lint demands a citation only for determination-shaped text (Art. 4(12) or Art. 33), so the allowed-path list is the stronger reason. | D16: record in `decision-challenges.md`; Findings For The Lead item 1. |

## Research Insights

**Premise Validation (Phase 0.6).** `gh` checks: #9603 open (p3-low, `type/feature`, `domain/marketing`, milestone Post-MVP / Later), #9601, #2004, #9851, #9773, #9543, #9602 open; #5863, #5862, #9545, #9614 closed; PR #11115 merged and an ancestor of origin/main. `collision-precheck.sh 9603` reported only this branch's draft PR #11948. Every cited path was confirmed with `git cat-file -e origin/main:<path>` (reviewer re-check: all evidence and inventory paths exist; one inventory path is corrected below). ADR corpus check for the mechanism: no ADR rejects a claim ledger; ADR-281 Decision 4 is the precedent and is cited, not amended.

**Property List.** P-A: per topic, a reader sees whether a control exists, is measured, is off, or is not built. P-B: every `measured` status is backed by evidence one command resolves. P-C: every statement already public on isolation, egress or approval is mapped and classified; findings reach the CLO. P-D: a future public sentence has an explicit runnable pass criterion and named non-passing statuses. P-E: the ledger cannot be read as a Jikigai statement about product security. P-F: the stale premise and the #2004 overlap are settled in writing with a re-evaluation trigger.

**Cut List.** Draft page body; publication-gate script or CI check; any edit to `docs/legal`, Art. 30, `compliance-posture.md`, Privacy Policy, DPD; new ADR or C4 change; filing issues for findings; a seventh status word (CTO D13 redefines `advisory`); a separate Test Scenarios section (the ACs are the tests).

**Institutional learnings applied** (`knowledge-base/project/learnings/`): `2026-09-27-a-status-flip-sweep-must-include-the-legal-registers-that-state-the-mechanism.md` (sweep `knowledge-base/legal/` as well as `docs/`); `workflow-patterns/2026-10-23-committing-generated-npm-payload-tripped-four-repo-wide-scanners-and-cmo-gate-missed-dark-launch-claim-flip.md` (the criterion gates the claim flip, not only the build); `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md` and `2026-09-20-the-ops-only-green-verdict-claimed-a-fact-the-gate-never-measured.md` (not-run, skipped, blind, dark are distinct; a `measured` cell cites the instrument, not a step verdict); `workflow-patterns/2026-10-27-legal-correction-notes-quote-the-phrase-they-remove.md` (Part 2 cites anchors, never quotes).

**Plan-time verified evidence matrix (candidate rows; the work phase re-verifies every cell and cites each source's LATEST state).** In the ledger, ADRs are cited as backticked full paths under `knowledge-base/engineering/architecture/decisions/` and each `measured` cell quotes the owning ADR's status word verbatim. Tokens: backticked repo paths, `gh:pr/<n>`, `gh:issue/<n>`, `unverified: <what>`. Residuals are cited by pointer, never restated; the 2026-10 gated-tier window and the past weakness named in ADR-075's 2026-10-08 (#9723) addendum are cited by number and date only, with no narrative.

| Row | Topic descriptor (not a sentence) | Candidate status | Evidence candidates | Tags and open items |
|---|---|---|---|---|
| I1 | Anthropic auth variables absent from sandboxed Bash in interactive hosted sessions (these variables only) | measured, flag yes | ADR-272 (`adopting`); `apps/web-platform/test/sandbox-credential-deny-runtime.test.ts`, `sandbox-credential-deny-argv.test.ts`, `agent-sandbox-credential-deny.test.ts`; `gh:pr/9599` | host class dev-host and CI-runner; `[residual]` ADR-272 "Not covered" text; `[prod-unmeasured]` no production-image canary cited though `gh:issue/9614` is closed; ADR text lag; no runtime tripwire |
| I2 | Tenant filesystem read isolation for the Bash tool (ADR-075 base) | measured, flag yes | ADR-075 (`accepted`); positive deny instruments (CLO finds: `agent-sandbox-tenant-deny.test.ts`, `helpers/sandbox-isolation-fixtures.ts` or equivalents, re-check); `sandbox-wrapped-command-runtime.test.ts` pins residuals | host class CI-runner; `[residual]` ADR-075 addendum 2026-10-31 and the breach-register provisional row; proxy-socket note in that test header; production flag state of the outer wrap unverified |
| I3 | Tenant file-tool containment (Read, Grep, Glob, LS, Notebook) by the PreToolUse hook | advisory unless a hook test is cited | ADR-075 addendum 2026-10-31; hook test CLO searches | sub-case unmeasured unless found |
| I4 | AF_UNIX denial for no-egress sessions (second filter behind a runtime flag) | CLO classifies (dark if flag off, else advisory) | ADR-075 addenda 2026-10-16, 2026-10-19 | live flag state unverified |
| I5 | Per-session mount-namespace outer wrap (arm F) | dark | `apps/web-platform/server/agent-outer-wrap.ts`; ADR-075 addenda 2026-10-08 (#5863), 2026-10-09; `gh:issue/5863` closed, `gh:issue/9773` open | live prd state unverified |
| I6 | Per-session ephemeral containers and active Landlock ruleset | not-shipped | ADR-315, ADR-316 (`proposed`); `gh:issue/9602` | none |
| I7 | Credential broker for entitled sessions | not-shipped | ADR-311 (`adopting`; no broker); `gh:issue/9543` | none |
| I8 | Runtime image vulnerability scan | advisory (non-gating), never claimable | ADR-281; `scripts/image-cve-public-claim-guard.test.sh`; `gh:issue/9826` | none |
| I9 | Untrusted-content classification and wrap | dark | ADR-287; `gh:pr/10192`; flags in `apps/web-platform/lib/feature-flags/server.ts` | live prd state unverified; `gh:issue/4671` open |
| I10 | Art. 32 TOM residual entry for shared heap, procfs and network | not-shipped | `gh:issue/9851` open | none |
| E1a | Hosted sessions: outbound network off by default | CLO decides (measured only with a cited instrument, else advisory) | ADR-278, instrument the CLO finds | ADR-052 only if the CLO confirms it applies to hosted sessions; fleet-divergence and flag-gated items `unverified` |
| E1b | Opt-in HTTPS gateway for agent web access (includes the gateway-monitoring statement: a stale Better Stack incident `gh:issue/11047` still open) | dark | ADR-278 (`accepted`, ships dark); `apps/web-platform/components/settings/web-egress-toggle.tsx` | toggle default off; monitoring statement advisory (unmeasured) |
| E2 | Workspace egress audit log read path (collection off for external workspaces) | dark, flag yes | `gh:pr/11115`; `apps/web-platform/server/egress-audit-read.ts`; `knowledge-base/legal/audits/2026-10-counsel-review-9545.md`; ADR-288; epic `gh:issue/9601` body | live `egress-audit-collection` state unverified; deployed state from the epic body only |
| A1 | Structured approval queue | dark | ADR-309; `gh:pr/11289`; `FLAG_APPROVAL_QUEUE=0` in `apps/web-platform/.env.example`; `knowledge-base/legal/audits/2026-10-counsel-review-4672.md` | flag not created per epic body; live state unverified |
| A2 | Gated-tier platform tools not pre-approved by the SDK allow list (legacy runner only) | measured only if the instrument is confirmed, flag yes, "see the existing CLO determination (PR #11443)" | ADR-305 (`accepted`); `gh:pr/11304`; `apps/web-platform/test/build-allowed-tools-census.test.ts` | host class CI-runner; production observation not cited; ADR-309 durable path changes behavior when the queue flag is on |
| A3 | Hosted Bash must-ask lane for destroy-family commands | advisory (unmeasured), flag yes | ADR-284 (`adopting`); `gh:issue/9776`, `gh:issue/10111` | lane lines in production sinks NOT OBSERVED; no member approval observed; soak not recorded |
| A4 | Per-action-class scope grants and approval tiers | CLO decides (measured only with a cited test) | `apps/web-platform/lib/messages/trust-tier-copy.ts`; scope-grants page | tier-enforcement tests searched at work time |
| A5 | Plugin destructive-command guard on customer machines (hook off in hosted sessions) | measured, flag yes | ADR-277 (`accepted`); `plugins/soleur/test/destructive-command-guard-hook.test.sh`; `plugins/soleur/hooks/destructive-command-guard.sh`; `gh:pr/9653` | host class CI-runner; `[residual]` ADR-277 non-coverage list; `[prod-unmeasured]` hosted ask path |
| A6 | Default state of autonomous Bash execution in hosted sessions | CLO classifies from ADR-284 (records the default) | ADR-284; `apps/web-platform/components/settings/bash-autonomous-toggle.tsx` | verify default value and where it is stated |

**Public-surface inventory at plan time (origin/main f05eaab78f; work-phase P0 regenerates a frozen file list).** Zero-hit: `docs/legal/cookie-policy.md`, `docs/legal/individual-cla.md`; pages `about.njk`, `blog.njk`, `changelog.njk`, `claude-code-plugins.njk`, `community.njk`, `legal.njk`, `skills.njk` (under `plugins/soleur/docs/pages/`). Relevant: `docs/legal/{acceptable-use-policy,terms-and-conditions,data-protection-disclosure,gdpr-policy,privacy-policy,disclaimer}.md` and their nine mirrors under `plugins/soleur/docs/pages/legal/`; `plugins/soleur/docs/index.njk` (FAQ), `pages/{agentic-engineering,glossary,vision,compare-soleur-vs-devin}.njk`, `pages/known-external-tools.md`; blog posts led by `2026-03-29-credential-helper-isolation-sandboxed-environments.md`, `2026-03-31-soleur-vs-paperclip.md`, `2026-04-21-soleur-vs-devin.md`; in-app files `web-egress-toggle.tsx`, `egress-audit-view.tsx`, `bash-autonomous-toggle.tsx`, scope-grants page, `autonomous-disclosure-banner.tsx`, `auto-run-chip.tsx`, `interactive-prompt-card.tsx`, `debug-stream-panel.tsx`, `runtime-explainer-banner.tsx`, `today-card.tsx`, `lib/messages/trust-tier-copy.ts`, `lib/approval-copy.ts`, approval card and landing components; registers public by repository visibility: `article-30-register.md`, `article-30-2-register.md`, the `breach-register.md` provisional row, ADR status lines. Pages with broad-term hits to classify (likely out of topic, each needs a recorded reason): `ai-agents-for-solo-founders.njk`, `company-as-a-service.njk`, `ai-cmo.njk`, `ai-cto.njk`, `compare-soleur-vs-cursor.njk`, `solo-founder-ai-stack.njk`, `pricing.njk`, `getting-started.njk`, `agents.njk`, `goal-primitive.md`, `docs/legal/corporate-cla.md`.

## Open Code-Review Overlap

None. No existing file is edited; a query of open `code-review` issues for the ledger path returned no match.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "ONE new file `knowledge-base/legal/public-security-claim-ledger.md` (flat in knowledge-base/legal/, NOT under audits/" | Files to Create 1; AC1 | mapped |
| 2 | "It opens with a banner: internal working ledger, not a statement by Jikigai about product security." | Ledger Spec 1; AC3 | mapped |
| 3 | "Part 1, topic rows: each row is a claim TOPIC DESCRIPTOR (never a marketing-grade sentence)" | Ledger Spec 3, 4; AC3, AC5 | mapped |
| 4 | "Closed status vocabulary: measured, published-measured, published-unverified, dark, not-shipped, advisory." | Ledger Spec 2; AC3 | mapped |
| 5 | "Every measured or published-measured row needs an evidence path that `git cat-file -e origin/main:<path>` resolves, or a PR or issue number verified with `gh`" | P1; AC3 | mapped |
| 6 | "advisory/dark/not-shipped rows listed under an explicit \"not yet claimable\" heading" | Ledger Spec 4; AC3 | mapped |
| 7 | "Part 2, published-statements check: every isolation, egress or approval statement ALREADY on a public surface" | P3; AC4 | mapped |
| 8 | "Correct the issue's stale premise (that the Art. 30 register and public docs carry no isolation claim) inside the ledger." | Ledger Spec 7; AC4 | mapped |
| 9 | "Record a decision (not a new surface) on overlap with #2004" | Ledger Spec 8; AC5 | mapped |
| 10 | "Document a Publication Criterion" with "a pass criterion and a runnable location" | Ledger Spec 6; AC5 | mapped |
| 11 | "Record a re-evaluation trigger" | Ledger Spec 9; AC5 | mapped |
| 12 | "Keep not-run, skipped and blind as distinct states" | Ledger Spec 2(b) | mapped |
| 13 | "write them in the plan as a section named \"Standing Constraints (operator, not steps of this PR)\"" | Standing Constraints | mapped |
| 14 | "record each as a Class technical row in decision-challenges.md" | Files to Create 5 | mapped |
| 15 | "The plan MUST carry a `## User-Brand Impact` section" | User-Brand Impact | mapped |
| 16 | "CLO review MANDATORY before merge" and "Run user-impact-reviewer plus the standard panel." | P6; AC6b | mapped |
| 17 | "PR keywords: `Ref #9603` and `Ref #9601` ONLY, never a closing keyword." | AC6a, AC7 | mapped |
| 18 | "AC1 `git diff --name-only origin/main...HEAD` shows only allowed paths (keep a negative control)" | AC1 | mapped |
| 19 | "AC2" the withheld digits "appear nowhere in diff or PR body" (number withheld by constraint) | AC2 | mapped |
| 20 | "mark those gates not-applicable with the reason" (observability, GDPR, UI) | Gate Dispositions | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Create 1 (ledger) | asks 1 to 12 | asked |
| Files to Create 2 to 5 (plan, tasks, spec, decision-challenges) | "this feature's own plan, tasks, spec and decision-challenges files" | asked |
| P1 re-verification of every seed row | "VERIFY each against origin/main, do not trust this list" | asked |
| P3 parallel surface sweeps | "spawn soleur:legal:clo for the rows and the Part 2 sweep" | asked |
| Reviewer one-liners inside the ledger | "Give the criterion a pass criterion and a runnable location (e.g. the exact commands a reviewer runs)" | asked |
| `## CLO Review Record` location | "CLO review recorded before merge" | asked; location is CTO ruling D16 |
| Part 1B pointers; Part 2 `kind` column; flag tags; host class; weakest-row rule; Finding type and Disposition | asks 6 and 7 | inferred — justification: CTO rulings D10, D14, D17 to D20 (each closes a way a wrong row or an unreviewed public statement could license a claim) |

### Split Assessment

- Subsystems touched: 1 — `knowledge-base`
- Planned files: 5 | Estimated changed lines: about 650
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** a ledger row marked `measured` for a control that is off, partial or unproven, which a later author reads as licence for a public sentence ("your data is isolated from other tenants", "agents cannot reach your keys") that a user then relies on when deciding what data to put in a workspace.
- **If this leaks, the user's data is exposed via:** a public reading of the world-readable ledger as a Jikigai statement (an over-strong row works as a representation to users and prospects), or a row that restates a recorded residual in new detail and widens an exposure existing records describe only by pointer.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one user acting on a wrong "measured" row is enough to damage trust and create deceptive-implication exposure, so the tier is single-user incident, not aggregate pattern.
- **CPO waiver (CTO ruling D9):** `requires_cpo_signoff` is `false` because no public page or UI is in the diff and the product-placement question is deferred to the publishing PR, which must flip the key to `true` and run the CPO pass.
- **Review path:** the CLO agent prepares the ledger; the standard panel and `soleur:engineering:review:user-impact-reviewer` run first (report-only), then a fresh CLO review (mandatory) last; CMO and CPO are not consulted.

## Domain Review

**Domains relevant:** legal

### Legal (CLO)

**Status:** reviewed (plan-time assessment, 2026-11-03; read-only)
**Assessment:** The repository is public, so the banner must say the ledger is an internal claimability register and not a product statement, each status word is defined in a legend, `measured` carries object, host class, date and scope (never a bare adjective), and rows prefer "no public statement is authorised until the criterion" over "the product does not do X". The shared-HOME residual may be named once, by pointer. The Art. 30 register entries are public by repository visibility, not by publication; the 2026-10-06 counsel review (`knowledge-base/legal/audits/2026-10-counsel-review-9601.md`) calling the register "not a published surface" is true of audience and false of access, recorded in Part 2 with a caveat line; the audit is append-only and is not edited. The end-of-work review attests: closed-vocabulary statuses with instrument and date; no row reads as a claim, warranty or guarantee; Part 2 complete across every statement category; unmeasurable statements mapped to Part 1B rows; Art. 30 classification as above; premise correction accurate; #2004 decision and trigger present; citations by section or anchor; no `docs/legal` or Art. 30 file edited; and a decision on whether per-statement finding detail is committed before disposition (CTO D20 left this legal call to the CLO).

**Product/UX tier:** NONE. The mechanical UI-surface override does not fire (no path under `components/`, `app/` or `pages` is created or edited); no wireframe (`wg-ui-feature-requires-pen-wireframe` not applicable). **Not consulted, by CTO ruling:** CMO, CPO. **Brainstorm-recommended specialists:** none.

## Gate Dispositions

Documentation-only diff: observability, IaC, encryption posture, Guard Contract, Task Design, soak enrollment, ADR/C4 (no architectural decision is made; the ledger supersedes no ADR and adds no actor, system, store or access relationship), wireframe, founder check (headless) and skill-description budget are not applicable. `soleur:gdpr-gate` is considered and skipped (CTO D15): no schema, auth, API, PII processing or processor in the diff, and its Critical-finding path would write `compliance-posture.md` and file an issue, both forbidden; the legal lens is the plan-time CLO assessment plus the mandatory review; the skip flips to a gate run if the diff gains such a surface.

## Files to Create

1. `knowledge-base/legal/public-security-claim-ledger.md` (written in the work phase).
2. `knowledge-base/project/plans/2026-11-03-feat-public-security-claim-ledger-plan.md` (this file).
3. `knowledge-base/project/specs/feat-one-shot-9603-public-security-claim-ledger/tasks.md`.
4. `knowledge-base/project/specs/feat-one-shot-9603-public-security-claim-ledger/spec.md`.
5. `knowledge-base/project/specs/feat-one-shot-9603-public-security-claim-ledger/decision-challenges.md` (D1 to D20; at the end of work a `## CLO Review Record`).

A learnings file under `knowledge-base/project/learnings/` only if compound produces one (at most one). **Files to Edit:** none; in particular none of `docs/legal/**`, `plugins/soleur/docs/**`, `apps/**`, `.github/**`, `scripts/**`, any `.tf`, flag or Doppler configuration, `compliance-posture.md`, `article-30-register.md`. The ledger is flat in `knowledge-base/legal/`, is not in `REGISTER_FILES` of `scripts/lint-legal-registers.sh` (Art. 30, Art. 30-2, breach register, compliance posture, CCLA register) and is outside its `audits/**` walk.

## Ledger Specification (structure the work phase writes)

One Markdown file; section order and table shape are fixed so the ACs can check them. Table cells never contain `|`; status cells are bare words (no backticks); paths in cells are backticked; the ledger uses no Markdown links (backticked paths only, so the KB link walker has nothing to resolve).

1. **Banner (first lines).** "Internal working ledger. Not a statement by Jikigai about product security, not a warranty, not a published security claim. A status here gates what may be said elsewhere; it is not a representation to anyone." It also states validity only as of the recorded origin/main commit and that evidence must be re-resolved before any reliance.
2. **Legend.** (a) Statuses, with the namespace split: Part 1 rows take `measured`, `dark`, `not-shipped`, `advisory`; Part 2 rows take `published-measured`, `published-unverified`. `measured` = measured within the descriptor's scope by a named instrument, host class and date, with the result. `dark` = flag-off or not enabled for anyone (on for internal or test only is `dark` with the segment named; on for any external organisation is not `dark`; an upward flip needs a cited artifact, never a flag read alone). `not-shipped` = no code, or only a recorded ADR or an unwritten entry. `advisory` = exists or runs but no measurement of the control as a control is cited (sub-case `non-gating` or `unmeasured`, named in the evidence cell); never claimable; leaves `advisory` only through a cited measurement at a path that exists (D13). `published-measured` = the public statement's mapped rows are all `measured`, its scope is no wider than theirs, and it states every `[residual]` tag; otherwise `published-unverified`; for a `disclosure` it means only that the evidence supports the disclosed limit and is not a security claim (D8, D14). (b) Measurement states `not-run`, `skipped` and `blind` are distinct; none is `measured`; a platform step conclusion is not a measurement; a `measured` cell cites the measurement artifact (run identity and required fields), not the step verdict. (c) Flag column: exactly `yes` or `no`, empty or unparseable means `yes`, legend line "yes = do not claim" beside each header; every `yes` row carries `[residual: <pointer>]` and or `[prod-unmeasured: <what>]` in its evidence cell; a `no` row carrying either tag counts as `yes` (D17). (d) Every `measured` evidence cell carries the owning ADR status word quoted verbatim, `host class: CI-runner | dev-host | production-image` (missing or unrecognised means `CI-runner`), the measured-commit SHA and the instrumented path list (an empty list fails; `git cat-file -e <sha>` must succeed) (D18). (e) Evidence tokens as in the matrix.
3. **Part 1A — Rows with a measured basis.** `| ID | Topic | Control that would measure it | Status | Evidence | Not yet claimable |`. IDs `I<n>`, `E<n>`, `A<n>`. Scope sits in the descriptor; tags in the evidence cell; Part 2 cross-references `(P2-n)` in the evidence cell.
4. **Part 1B — Not yet claimable.** Same columns for every `dark`, `not-shipped` and `advisory` row. Every flag-`yes` Part 1A row also gets a pointer as a bullet outside the tables: `- <ID>: <one clause>`. Live prd flag states not fully read are marked `unverified: <missing source>` here (a full read means Flagsmith, code default and Doppler prd all read; run `list.sh` with output redirected to a scratchpad file, extract only the four flag names and states, never paste raw output, bounded by a timeout).
5. **Part 2 — Published-statements check.** `| ID | Surface and anchor | Topic descriptor | Kind | Maps to | Status | Finding |`. IDs `P2-<n>`. `Kind` is `assurance`, `disclosure` or `register-entry`. `Maps to` is one or more Part 1 ids; the status is the weakest mapped row's (order weakest to strongest: not-shipped, dark, advisory, measured); a hosted-session statement must map to a hosted-scope row (a plugin-scoped row alone yields `published-unverified`); a statement with no row is `published-unverified` and the Part 1 row is added in the same PR (D19). Statements are cited by file and section anchor, never quoted. `Finding` holds `F<n>` or `-`. Under `### Findings for the CLO`, each finding has `Finding type` (scope wider than row | residual not stated | maps to non-measured row | register entry stronger than row | disclosure contradicted by evidence | no mapped row), `Disposition` (`escalate` | `CLO-owned` | `accepted-by-CLO`), `Disposed by`, `Disposition date`; no finding is edited in this PR and none files an issue (D20). Mirrors under `plugins/soleur/docs/pages/legal/` are recorded as `mirror of` notes with one lockstep result line (confirmed, or divergences listed). The section lists the recorded sweep commands, every zero-hit surface and every reviewed-out-of-topic hit with its reason (for example blog statements about git worktrees).
6. **Publication Criterion.** A sentence may enter any public surface only if all hold. C1: every mapped Part 1 row is `measured`, its owning ADR status is `accepted`, no `[prod-unmeasured]` tag, the host class is no narrower than the sentence's scope (a statement about hosted production behavior needs `production-image`), the sentence states every `[residual]` tag, and its scope is no wider than the row's. C2: evidence resolves and has not decayed (`git diff <measured-commit>..origin/main --stat -- <instrumented paths>` prints nothing at the publishing PR's base). C3: the CLO signed the wording, with operator sign-off at flag-on. C4: the Art. 30 TOM entry, DPD and Privacy Policy edits, with their mirrors and the legal-doc sha file, ship in the SAME PR. C5: the publishing PR adds its own claim guard (precedent only: `scripts/image-cve-public-claim-guard.test.sh`, ADR-281 Decision 4; exit 0 shows nothing about a non-image claim). C6: `advisory`, `dark`, `not-shipped` and `published-unverified` never pass; `not-run`, `skipped`, `blind` never count as `measured`; a `published-measured` disclosure never clears a claim. The text states which statuses apply to Part 1 rows and which to Part 2 rows. **Pass criterion:** every item answers yes with the printed output stated. **Runnable location:** reviewer one-liners listed in the ledger (aid, not an automated gate; automation belongs to the publishing PR): `git cat-file -e origin/main:<path>` exits 0; `gh pr view <n> --json state --jq .state` prints `MERGED`; `gh issue view <n> --json state --jq .state` prints the cited state; for C4, `git diff --name-only origin/main...HEAD | grep -cE '^(docs/legal/(data-protection-disclosure|privacy-policy)\.md|plugins/soleur/docs/pages/legal/(data-protection-disclosure|privacy-policy)\.md|knowledge-base/legal/article-30-register\.md|apps/web-platform/lib/legal/legal-doc-shas\.ts)$'` prints 6 (three canonical edits, two mirrors, one sha file; the Art. 30 register edit counts once). The publishing PR also flips `requires_cpo_signoff` to `true` and consults CMO and CPO. Per `knowledge-base/legal/audits/2026-10-counsel-review-9601.md` condition C3, before any credential-isolation claim the claim is limited to the entry's text and canonical, mirror and sha file move together.
7. **Correction of the issue's premise** (short; statements listed by file and section; the Art. 30 register is public by repository visibility).
8. **Decision: overlap with #2004.** #9603 is a public trust page; #2004 (open; authenticated in-app work visualization) shares at most a fact source (this ledger's evidence rows). No surface is created by this record; placement (docs site versus in-app) is deferred to the publishing PR, with CMO and CPO consulted then.
9. **Re-evaluation trigger.** Revisit when at least one row in each of isolation, egress and human approval is `measured` for external workspaces AND the operator and the CLO have signed the wording.
10. **Method (written last).** The pinned origin/main SHA, the exact commands run, and `ls knowledge-base/engineering/architecture/decisions/ADR-<n>-*.md` for every cited ADR.

Wording rules (checked by AC5, attested by the CLO): topic descriptors and the control column are noun phrases of at most 20 words; no first or second person; a control column never reads as a roadmap commitment in `dark`, `advisory` or `not-shipped` rows; past tense only for what has shipped; the ledger never restates the 2026-10 gated-tier window (no dates, no word for the past defect, no issue number), never contains the withheld digits, and contains no candidate public sentence. The ledger, the PR body and the CLO record never use the finding-ban words listed in AC5.

## Implementation Phases (work phase)

Every sub-agent and reviewer prompt starts with this preamble: "Read-only. No Write or Edit. No `gh issue create`, comment, edit or label. No flag skill other than the read-only `list.sh` read. Return text only; refer to the egress-audit enablement issue only by that description." After each sub-agent returns, the lead runs `git status --porcelain` and `git diff --name-only`, removes anything unexpected, and greps the returned text with the AC2 pattern before pasting anything into a file. On a scratchpad EDQUOT, results are returned inline in chunks; nothing falls back to a path under the worktree or `knowledge-base/`, and no file is deleted to make room.

**P0 Setup.** `git fetch origin main`; record `SHA=$(git rev-parse origin/main)`; all reads use `git show "$SHA":<path>` or `git grep ... "$SHA"`. Generate the frozen sweep file list (`git ls-tree` plus the category greps) into the scratchpad as the AC4 input, with each category owned by exactly one worker (A: `docs/legal` canonical files; B: `plugins/soleur/docs/**`, README files, `llms.txt`, CHANGELOG and distribution drafts; C: `apps/web-platform` in-app copy and user-facing error strings, flag names and descriptions, the world-readable registers). Re-fetch at P5; if the SHA moved, re-run the evidence checks and note it in Method.

**P1 Row verification (`soleur:legal:clo`).** Re-verify every matrix cell (`git show`, `git cat-file -e`, `gh pr view`, `gh issue view`), reading each source's LATEST state (append-only addenda, superseded sentences, struck-through issue items). Return a diff table (row, seed status, verified status, reason, evidence); each flip is recorded by the lead as a technical row in `decision-challenges.md`. Decide E1a, A4, A6, I3, I4 and confirm the A2 instrument. Attempt the four flag reads under the Part 1B rule; never create or flip a flag.

**P2 Part 1 and legend.** The lead writes ledger sections 1 to 4, then hands the frozen Part 1 id list and descriptors to the workers.

**P3 Part 2 sweep (three workers in parallel, text returned).** Each worker returns rows plus a trailer `ROWS=<n> FILES=<n> ZERO_HIT=<n> OOT=<n> END`; a return without the trailer or with a file-count mismatch is re-dispatched once, then split; a missing slice makes the sweep incomplete and forces a BLOCKED review. Workers may return `UNMAPPED` statements; the lead adds a Part 1 row (CLO classifies the status) and re-runs the AC3 shape checks. The lead merges, then triages each finding to a Disposition; an `escalate` finding (a live in-app or docs-site assurance, or any finding the CLO judges to need an edit) stops the work and is returned to the lead with file and section, for CTO routing; an unresolved `escalate` blocks marking the PR ready.

**P4 Decisions and Method.** The lead writes sections 5 (merge), 6 to 9, then 10 last.

**P5 Verification.** Run AC1 to AC5 and AC6a.

**P6 Reviews.** The standard review panel and `soleur:engineering:review:user-impact-reviewer` run first in report-only mode (findings return as text; no issues, no `todos/` files). Then a fresh CLO invocation (given only the final ledger and the checklist in the Domain Review section, not the worker outputs) reviews last. The CLO Review Record is appended to `decision-challenges.md` as prose or a list (not a table headed with the Decision Classes columns), append-only, carrying reviewer context (fresh), the ledger blob hash (`git hash-object`), the pinned SHA, verdict, and conditions. Verdicts: DISCHARGED; DISCHARGED-WITH-CONDITIONS (not mergeable until conditions are applied and re-attested); BLOCKED (PR stays draft; apply conditions and re-review, at most two cycles; a condition that needs a public edit or a new issue stops the work and returns to the lead). **P6.5:** after any ledger or ruling-file edit, re-run AC1 to AC5 and AC6a, and re-attest if the blob hash changed. Run `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` right after writing the record and require exit 0 (verified at plan time that a prose `## CLO Review Record` section passes; a table headed `Item | Class | Ruling` whose technical row lacks the "Ruled by CTO agent, <date>:" prefix fails).

**P7 Ship notes for the lead.** PR body: `Ref #9603`, `Ref #9601`, and finding COUNTS per Finding type plus the ledger path (D20); no closing keyword; no plan or spec path (a plan path in the body makes the ship counsel-review gate fire; if it must appear, the CTO widens the allowed paths by exactly the one audits file the gate names, with a register citation). Re-check the body after ship folds `decision-challenges.md` into it and again after Phase 6.45 archival (AC1, AC2, AC6a, the technical-ruling gate against archived paths). The lead's final message to the human principal lists every finding, since no issue is filed.

## Acceptance Criteria

<!-- Commands run from the repo root after `git fetch origin main`. Patterns are built so this plan never contains the withheld digit string. -->

- [ ] **AC1 — diff scope.** `git diff --name-only origin/main...HEAD | grep -vcE '^(knowledge-base/legal/public-security-claim-ledger\.md|knowledge-base/project/plans/(archive/[0-9-]+-)?[0-9-]*feat-public-security-claim-ledger-plan\.md|knowledge-base/project/specs/(archive/[0-9-]+-)?feat-one-shot-9603-public-security-claim-ledger/[^/]+|knowledge-base/project/learnings/([a-z-]+/)?[^/]+\.md)$'` prints `0` (a count, so a pattern that fails to compile prints nothing). `git diff --name-only origin/main...HEAD | grep -c 'knowledge-base/project/learnings/'` prints 0 or 1. The generated `knowledge-base/INDEX.md` cache is untracked and stays out of the diff. **Negative control (prints 5):** `printf '%s\n' docs/legal/privacy-policy.md apps/web-platform/x.ts scripts/x.sh knowledge-base/legal/article-30-register.md knowledge-base/legal/compliance-posture.md | grep -vcE '<the same pattern>'`.
- [ ] **AC2 — withheld digits.** `git diff origin/main...HEAD | grep -cE '1{2}237'` prints 0; `git log origin/main..HEAD --format=%B | grep -cE '1{2}237'` prints 0; `gh pr view 11948 --json body,comments --jq '.body, (.comments[].body)' | grep -cE '1{2}237'` prints 0 (bot-comment hits are triaged for coincidental digits in run URLs and SHAs). **Negative control (prints 1):** `printf '11%s\n' 237 | grep -cE '1{2}237'`. If a generated token trips it, regenerate the token.
- [ ] **AC3 — ledger shape.** Run on the ledger (`L`) with scratchpad scripts, each with a negative control on a mutated copy: (a) `head -12 L | grep -ci 'internal working ledger'` prints 1 or more. (b) Column count: every row line starting `| [IEA][0-9]+ ` has 6 cells, every `| P2-[0-9]+ ` row has 7 (`awk -F'|' '{print NF-2}'`). (c) Part 1 statuses: `awk -F'|' '/^\| [IEA][0-9]+ /{gsub(/^ +| +$/,"",$5); print $5}' L | grep -vxcE 'measured|dark|not-shipped|advisory'` prints 0; Part 2 statuses: `awk -F'|' '/^\| P2-[0-9]+ /{gsub(/^ +| +$/,"",$7); print $7}' L | grep -vxcE 'published-measured|published-unverified'` prints 0; each extraction yields more than 0 rows (anti-vacuity). (d) Flag cells: `awk -F'|' '/^\| [IEA][0-9]+ /{gsub(/^ +| +$/,"",$7); print $7}' L | grep -vxcE 'yes|no'` prints 0; every `yes` row's evidence cell contains `[residual:` or `[prod-unmeasured:`; every `measured` evidence cell contains `host class:`, an owning-ADR status quote and a measured-commit SHA with a non-empty path list. (e) Evidence resolves: `awk -F'|' '/^\| [IEA][0-9]+ /&&$5~/^ *measured *$/{print $6}' L | grep -oE '`[^`]+`' | tr -d '`' | while read -r t; do case $t in gh:pr/*) gh pr view "${t#gh:pr/}" --json state >/dev/null || echo "MISSING $t";; gh:issue/*) gh issue view "${t#gh:issue/}" --json state >/dev/null || echo "MISSING $t";; unverified:*) ;; */*) git cat-file -e "origin/main:$t" 2>/dev/null || echo "MISSING $t";; esac; done` prints nothing; every cited ADR is a backticked full path. (f) Every `dark`, `not-shipped` and `advisory` row sits after the Part 1B heading, and every flag-`yes` Part 1A row has a bullet pointer `- <ID>:` there. **Negative controls:** a copy with one status replaced by `shipped`, one evidence path altered, one `yes` flag cell emptied, makes (c), (e), (d) respectively print a violation.
- [ ] **AC4 — Part 2 census.** Re-run the recorded sweep command set over the P0 frozen file list; every hit file has at least one Part 2 row or sits in the reviewed-out-of-topic list with a reason (the unclassified bucket is empty): `for f in $(cat <frozen list>); do grep -qF "$f" L || echo UNMAPPED "$f"; done | wc -l` prints `0`. Zero-hit surfaces are listed; the nine legal mirrors have one lockstep result line; every `Maps to` id exists in Part 1; every `F<n>` pointer has a finding entry with all four fields and a closed `Finding type`; the two Art. 30 TOM entries and the acceptable-use-policy section 5.8 statement are Part 2 rows. Anti-vacuity: the frozen list has at least as many files as the plan-time inventory names; a copy with one covered file's rows removed makes the loop print that file.
- [ ] **AC5 — criterion, decisions, wording.** The ledger contains the criterion (C1 to C6 with pass criterion and one-liners with expected output), the #2004 decision, the trigger, the premise correction, the measurement-state legend. Over data rows (`grep -E '^\| ([IEA][0-9]+|P2-[0-9]+) '`): `grep -ciE '\b(we|our|you|your|secure|safe|guarantee|guaranteed|prevents|cannot|never|zero|compliant|certified|audited)\b'` prints 0. Over the whole ledger, the PR body and the CLO record: `grep -ciE '\b(false|misleading|overclaim|overclaims|inaccurate|unsupported)\b'` prints 0; over the ledger `grep -ciE 'bypass|exposure window|2026-04-06|11303'` prints 0, `grep -c '\]('` prints 0 (no Markdown links), and no table cell contains a pipe (AC3 column counts). No candidate public sentence appears (CLO attests).
- [ ] **AC6a — lints and PR hygiene (run in P5, again at ship).** `bash scripts/lint-legal-registers.sh` exits 0; `git add knowledge-base/legal/public-security-claim-ledger.md && bash scripts/markdown-lint.sh knowledge-base/legal/public-security-claim-ledger.md` reports the file clean (not "nothing to lint"); `bash scripts/check-adr-ordinals.sh` exits 0; `python3 scripts/lint-infra-no-human-steps.py <plan> <spec files>` exits 0. PR body: `gh pr view 11948 --json body --jq .body | grep -ciE '(close[sd]?|fix(e[sd])?|resolve[sd]?) #[0-9]+'` prints 0; `grep -cE 'knowledge-base/project/(plans|specs)/'` prints 0.
- [ ] **AC6b — reviews (run in P6).** The CLO Review Record exists, verdict DISCHARGED, reviewer context fresh, recorded blob hash equals `git hash-object` of the final ledger, recorded SHA is a valid commit; `soleur:engineering:review:user-impact-reviewer` ran at threshold single-user incident; the standard panel ran; plan and spec are archived by ship.
- [ ] **AC7 — no side effects.** Snapshot before and after: `gh issue view 9603 --json state,labels,milestone` equals the recorded snapshot (OPEN; `priority/p3-low`, `type/feature`, `domain/marketing`; Post-MVP / Later); `gh issue view 9601 --json body --jq .body | grep -c '\[ \] #9603'` prints 1 (the line exists first); no `gh issue create`, close, comment or edit, no `flag-create` or `flag-set-role` skill call appears in the work phase tool log (the lead reviews it); run before arming merge and after merge.

## Findings For The Lead

1. **CLO review record location (D16).** The ship counsel-review gate names `knowledge-base/legal/audits/<YYYY-MM>-counsel-review-9603.md`. It was deliberately not used: it is outside the allowed paths (the register lint would also demand a citation, but only for determination-shaped text). The record lives in `decision-challenges.md`. The gate reads the plan path from the PR body, so it does not fire while the body carries only the Ref lines and counts.
2. **Escalation.** An `escalate` finding stops the work and returns to the lead for CTO routing (wording to the CLO, mechanism truth to the CTO); no public-surface edit is made here.
3. **Finding detail.** Whether per-statement finding detail is committed to a public file before disposition is a legal call left to the CLO review (D20); the default in the PR body is counts only.
4. **Part 2 scale.** About 14 canonical legal and in-app files plus mirrors, pages, blog and registers; the three-worker split with a trailer check keeps each slice bounded.

## Sharp Edges

- The archive step names directories `YYYYMMDD-HHMMSS`; the withheld five-digit string can only appear when the time starts 01, 11 or 21 followed by 12:37 with no separators. Pre-compute the timestamp with `date`; if it matches, sleep and re-run the archive before committing; if already committed, `git mv` to a fresh timestamp, commit and push.
- A plan whose `## User-Brand Impact` is empty or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it.
- Do not write the bracketed draft marker the ship counsel-review gate greps for, in the ledger or this plan.
- Do not quote public statements in Part 2: a quoted phrase defeats later absence greps and may carry the withheld digits (the Art. 30 register amendment text does).
- Status cells hold exactly one bare vocabulary word; qualifiers go in the topic or evidence cell, or AC3(c) fails. Pointers for Part 1B are bullets, not table rows.
- Cite sections and addendum dates, not line numbers.
- Only the read-only flag list is allowed; `flag-create` and `flag-set-role` are out of bounds.
