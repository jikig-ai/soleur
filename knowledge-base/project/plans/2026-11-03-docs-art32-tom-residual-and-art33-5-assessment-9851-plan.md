---
title: "legal: Art. 32 TOM residual entry + Art. 33(5) assessment of the #9723 window"
date: 2026-11-03
slug: art32-tom-residual-and-art33-5-assessment-9851
branch: feat-one-shot-9851-art32-tom-art33-5-assessment
issue: 9851
type: docs
priority: p2
domain: legal
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: false
---

# legal: Art. 32 TOM residual entry + Art. 33(5) assessment of the #9723 window

Draft PR 11966. References: Ref #9851, Ref #9601. Parent epic for the Stage 0 legal record: #9842.

## Overview

Two entries in two world-readable legal registers, both written in the named-gap form already used for the ADR-272 entry (reviewed in the 2026-10 counsel review of #9601):

1. **Art. 32 TOM bullet** in `knowledge-base/legal/article-30-register.md`, section "Cross-Cutting Technical & Organisational Measures (Art. 32)", naming the shared-heap, shared-procfs and shared-network residuals of hosted agent sessions. It is a technical-measure bullet, not an Art. 30 processing activity. An additive dated Superseded marker under the existing arm-F bullet removes the sentences that the latest ADR state falsifies.
2. **Art. 33(5) row** in `knowledge-base/legal/breach-register.md` (Index of determinations) assessing the window in which the `/proc` deny in the sandbox configuration was declared but not realized in the assembled sandbox command. Outcome class (CLO, D2): REACHABILITY-ONLY, PROVISIONAL, evidentiary limbs inconclusive, Art. 33 No, Art. 34 No.

No code, flag, environment, public page or production system is touched. Both entries describe only what exists on 2026-11-03.

## Standing Constraints (operator, not steps of this PR)

These bind the work. None is an action this PR takes, and none is delegable (the epic has no Standing Delegation).

- Creating or flipping any feature flag (broker, approval queue, egress-audit collection) and creating or changing any environment stay with the operator. This PR neither performs, requests nor prepares them.
- The egress-audit enablement issue is not worked, not referenced and not closed. Its number never appears in the diff (plan, tasks, spec, registers, decision-challenges), commit messages, the PR body or any comment; every artifact calls it "the egress-audit enablement issue". The number already sits in older text of the Art. 30 register, so the check (AC2) reads added lines only.
- No production write that needs approval is made. Production state that cannot be read by read-only means is recorded `unverified: <missing source>` (the live `AGENT_OUTER_WRAP` value is one).
- Legal-wording sign-off at flag-on stays with the operator; the CLO agent prepares and reviews only.
- The CTO agent rules every technical fork; the operator is asked no technical question. Rulings are rows with Class `technical` in `knowledge-base/project/specs/feat-one-shot-9851-art32-tom-art33-5-assessment/decision-challenges.md`.
- No public security claim is made ahead of a measured control; wording describes only what exists today.
- `docs/legal/**`, `plugins/soleur/docs/**`, toggle copy, `apps/**`, `scripts/**` and `.github/**` are out of scope and unchanged. The repository is public, so everything under `knowledge-base/` is already world-readable; "register" does not mean "unpublished".
- `ci/main-broken` issue #11669 is not touched.

## Research Reconciliation — Spec vs. Codebase

| Brief or issue claim | Reality (live read 2026-11-03) | Plan response |
|---|---|---|
| Epic is #9601 | The issue body says "Part of epic #9842 (Stage 0 legal record)"; #9601 is the security-hardening epic and also open. Both open. | Reference both: `Ref #9851`, `Ref #9601`; the epic #9842 is cited in prose only. |
| "the #9723 window (`/proc/<pid>/environ` readable after the deny was dead code)" | #9723 is CLOSED (2026-10-09T01:58:31Z). The inner-tier mask later changed shape twice (ADR-075 addenda 2026-10-11 #10032, nested 2026-10-12 #10065, which supersedes "no procfs is mounted"). Environ readability is not established either way: the repo's own measurements conflict (dev-host real-SDK run versus hand-built bubblewrap runs), none in the production image. | The row says reachability, not readability; cites the corrected #10065 form; states the conflict by pointer. |
| "wording describes only what exists today" | The existing arm-F bullet says "#9723 stays open", "status: adopting", a file-capability mechanism (reverted by #9874, ADR-075 addendum 2026-10-09) and "sibling PIDs and environ remain visible" (now true only for the file-tool tier). | Additive dated Superseded marker covering five statements (D12). |
| Window start = "the deny was dead code" | The deny entry is declared from 2026-03-29 (#1282); the sandbox was enabled in production by #1559 (merge 2026-04-05T22:01:06Z); the defective argv shape is repo-evidenced from the in-image fixture capture merged 2026-07-03 (#5928); earlier presence not established. | Event cell: conservative upper bound, labeled; evidence date separately (D5). |
| Ledger row I10 "No entry exists" | True at the ledger's pinned commit; false after this PR merges. The ledger is outside the diff. | PR body notes a ledger re-pin is owed; nothing becomes claimable by the entry's existence. |
| "no arms-length user" (2026-10-09 ruling) | The 2026-10-28 determination holds the account classification open (to 2026-11-04). | The row does not assert it (D17). |

## Research Insights

**Premise Validation (Phase 0.6).** Checked with `gh`/`git`: #9851 OPEN, #9601 OPEN, #9842 OPEN, #9723 CLOSED by PR 9768; #9860 CLOSED (2026-10-12), #9614 CLOSED (2026-10-07), #9773 and #9543 OPEN; PRs 9768 (merged 2026-10-09T01:58:29Z), 10039 (2026-10-11T18:29:11Z), 9874 (2026-10-09T17:13:40Z), 1559 (2026-04-05T22:01:06Z), 5928 (2026-07-03T09:39:47Z), 9709 (2026-10-07T21:50:59Z) merged. Collision pre-check: the only open change naming #9851 is this branch's own draft PR 11966; three foreign `test-all.sh` processes belong to unrelated worktrees. The proposed mechanism (named-gap bullet, index row) matches the existing register conventions; no ADR rejects it.

**Property List (Phase 0.6b).** P1: the shared-heap, shared-procfs and shared-network residuals are named, with their exit, in the Art. 32 list. P2: the #9723 window has an Art. 33(5) record saying what is established and what is not. P3: a legal reviewer's sign-off is recorded and survives archival. P4: no sentence claims more than the repository's latest records support.

**Cut List.** (a) New `audits/` determination or counsel-review file: barred by the diff scope; would need a `NOT_TRANSCRIBED` waiver edit in `scripts/lint-legal-registers.sh`; P3 is served by the CLO Review Record section instead (D8). (b) New ADR or C4 change: no decision is made. (c) New Art. 30 processing activity: the issue says it is not one. (d) Edit to `compliance-posture.md` or the ledger: out of the diff; the stale pointer is named in the CLO record and the ledger re-pin in the PR body. (e) The indirect instrument over retained session records (limb E1): processes conversation content, needs the controller's authorisation (D18), so it is named, not run. (f) Any issue filing: net issue flow is 0. Mechanisms already on main that cover properties: the ADR-272 bullet and the 2026-10-31 breach row are the two forms to copy.

**Institutional learnings applied.** Verify every register citation against the register (`2026-06-04-art-30-pa-citation-must-be-grep-validated-against-register`); remove `PROVISIONAL` only on measured evidence and change the cell itself (`2026-09-14-closing-a-limb-by-decision-is-not-closing-it-clean-...`); a determination must name the host and the discriminating query, not the default state (`2026-10-28-a-determination-memo-inherited-a-serving-claim-...`); a locator pasted into several cells must be checked per cell (`2026-09-18-my-supersession-pointer-named-the-wrong-bracket`); review the correction prose as hard as the defect; check that spec paths really moved after ship archival (`2026-10-13-gh-pr-merge-shipped-live-kb-artifacts-...`); aggregated security findings in a public repo are an attacker roadmap (`2026-02-16-inline-only-output-for-security-agents`); `markdownlint --fix` corrupts table cells, so run it read-only.

**Local research.** Repo research and the learnings search ran inline and as a read-only agent; no external research (no library, API or new technology; high-risk topic is covered by the CLO and CTO rulings below). Community-discovery and functional-overlap checks skipped: no stack gap, documentation-only diff.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` bodies were searched for both register paths; no match.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add the shared-heap / shared-procfs / shared-network residual as an Art. 32 TOM bullet in knowledge-base/legal/article-30-register.md, section Cross-Cutting TOMs (Art. 32), in the named-gap form of the ADR-272 / counsel-review-9601 pattern (not an Art. 30 processing activity)" | Phase 1; Files to Edit 1 | mapped |
| 2 | "Art. 33(5) assessment of the #9723 window (/proc/<pid>/environ readable after the deny was dead code): was there a personal-data exposure? Record the outcome in breach-register form either way." | Phase 2; Files to Edit 2 | mapped |
| 3 | "Both entries merged, legal reviewer sign-off recorded, wording describes only what exists today." | Phase 4 (CLO Review Record); AC5, AC9, AC10 | mapped |
| 4 | "One PR through the full pipeline (plan, work, review panel, QA, compound, ship), then merge via the queue." | Phases 3 to 6; Ship Notes | mapped |
| 5 | "Write them in the plan as a section named \"Standing Constraints (operator, not steps of this PR)\"" | Standing Constraints | mapped |
| 6 | "BEFORE drafting, spawn soleur:legal:clo and soleur:engineering:cto" | Research Insights; decision-challenges.md D1 to D18 | mapped |
| 7 | "(d) whether the PR may close #9851 (default: reference #9851 and #9601 only" | D10; AC8 | mapped |
| 8 | "(e) whether the diff touches regulated-data surfaces beyond register text, deciding whether soleur:gdpr-gate runs (record the ruling either way)" | Gate Dispositions; D9 | mapped |
| 9 | "(f) where the CLO review record lives" | D8; Phase 4 | mapped |
| 10 | "The CLO review is MANDATORY before merge; ... Brand-survival threshold `single-user incident`" | User-Brand Impact; Phase 4; Phase 5 | mapped |
| 11 | "CMO and CPO are NOT consulted unless a public page enters the diff." | Domain Review; D16 | mapped |
| 12 | "Do not edit docs/legal, plugins/soleur/docs, toggle copy, apps, scripts or .github" | AC1; AC6 | mapped |
| 13 | "Net issue flow must be 0 filed (no gh issue create) unless a mandated filing exists. Do not touch ci/main-broken #11669." | AC7 | mapped |
| 14 | "Use `Ref #9851` and `Ref #9601` in any PR text ... never put a close keyword next to an issue reference." | AC8 | mapped |
| 15 | "Cite a source's LATEST state" | Phase 0 verification; AC9 claim trace | mapped |
| 16 | "Give every new rule or criterion a pass criterion and a runnable location." | Acceptance Criteria (each carries both) | mapped |
| 17 | "the withheld-digits grep, lint-legal-registers pass, markdownlint pass, CLO review recorded, no public surface edited, and issue flow 0" | AC2, AC3, AC4, AC5, AC6, AC7 | mapped |
| 18 | "the PR body will say preflight Check 4 (Doppler) was skipped" | Ship Notes; AC8 | mapped |
| 19 | "record each ruling as a row with Class \"technical\" in the plan's decision-challenges file" | Files to Create 4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Edit 1 (Art. 30 register) | "add the shared-heap / shared-procfs / shared-network residual as an Art. 32 TOM bullet" | asked |
| Superseded marker under the arm-F bullet (Phase 1) | "wording describes only what exists today" | asked (ask 3) |
| Files to Edit 2 (breach register) | "Record the outcome in breach-register form either way" | asked |
| `related:` frontmatter addition (Phase 2) | — | inferred — justification: the CLO ruling (D3, CLO item g) asks the register to list the canonical record for traceability; the lint ignores the key so it is cost-free and removable |
| Files to Create 1 to 5 (plan, tasks, spec, decision-challenges, session-state) | "this feature's own plan/spec files under knowledge-base/project/plans and knowledge-base/project/specs/feat-*" | asked |
| CLO Review Record section | "legal reviewer sign-off recorded" | asked |
| Verification Commands | "Give every new rule or criterion a pass criterion and a runnable location." | asked |
| PR-body displaced-path sentence | "The CLO review is MANDATORY before merge" | asked (D8) |

### Split Assessment

- Subsystems touched: 2 — `knowledge-base/legal`, `knowledge-base/project`
- Planned files: 2 edited + 5 created | Estimated changed lines: about 40 added register lines (long table and bullet lines) plus plan files
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** a register that tells a data subject or a supervisory authority that a cross-tenant credential channel was "closed" or that "no personal data was exposed" when the repository can establish neither, or an Art. 32 list that reads as an in-force tenant-isolation control when only a conditionally measured mask and named residuals exist.
- **If this leaks, the user's data is exposed via:** a restated defect narrative in a world-readable file (the repository is public) that gives a reader a map of which process-level channels a prompt-injected agent session could probe, or an identifier, host name, credential name or count that points at a person or workspace.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one tenant's credential or content reached by another tenant, and one mis-worded sentence relied on by a regulator or a user, is enough to damage trust; aggregate-pattern would understate a public-repo statement (CTO and CLO concurring, D16).
- **CPO waiver (D16):** `requires_cpo_signoff` is false because no public page or UI is in the diff and product placement belongs to a publishing PR; CMO and CPO are not consulted.
- **Review path:** the standard panel and `soleur:engineering:review:user-impact-reviewer` run first (report-only), then a fresh CLO review on the FINAL diff (mandatory) last.

## Domain Review

**Domains relevant:** legal, engineering

### Legal (CLO)

**Status:** reviewed (plan-time ruling, 2026-11-03, draft v1 internal CLO attestation)
**Assessment:** conclusion class REACHABILITY-ONLY, PROVISIONAL; row not exclusion; tier (i) only; narrative one sentence plus pointers; the TOM bullet carries status `open residual`; the CLO Review Record lives in decision-challenges.md; PR text uses Ref lines only. Details: D2 to D4, D6, D10, D11, D17, D18.

### Engineering (CTO)

**Status:** reviewed (plan-time rulings, 2026-11-03)
**Assessment:** window dating, canonical-source cell, ship-gate handling, ptrace wording, claim-to-source pairs, marker scope, withheld-number check: D5, D7 to D9, D12 to D16. One finding was routed to the lead outside the repository (D13).

**Product/UX tier:** NONE. The mechanical UI-surface override does not fire (no path under `components/`, `app/` or `pages`); no wireframe (`wg-ui-feature-requires-pen-wireframe` not applicable). **Not consulted, by instruction:** CMO, CPO. **Brainstorm-recommended specialists:** none.

## Gate Dispositions

Documentation-only diff: observability, IaC, encryption posture, Guard Contract (the plan ships checks, not a guard), Task Design, soak enrollment, ADR/C4 (no architectural decision is made; no actor, system, store or access relationship is added), wireframe, founder check (headless) and skill-description budget are skipped for that reason. `soleur:gdpr-gate` is considered and skipped (D9, CLO and CTO): neither register matches the regulated-surface globs and the gate's Critical-finding path would write `compliance-posture.md` and file an issue, both out of scope; the plan trigger "single-user incident declared" was considered and answered by the mandatory CLO review. The skip flips to a gate run if a migration, auth path, API route or `.sql` file enters the diff (AC6 pass criterion).

## Files to Edit

1. `knowledge-base/legal/article-30-register.md` — (a) one new bullet in "Cross-Cutting Technical & Organisational Measures (Art. 32)" after the arm-F bullet and its 2026-10-31 pointer comment, before "Audit logging"; (b) one Superseded blockquote directly under the arm-F bullet.
2. `knowledge-base/legal/breach-register.md` — (a) one row appended to "Index of determinations" after the 2026-10-31 row; (b) one line added to the `related:` frontmatter list. The "Excluded records" count, all existing rows and all prose are untouched.

## Files to Create

1. `knowledge-base/project/plans/2026-11-03-docs-art32-tom-residual-and-art33-5-assessment-9851-plan.md` (this file).
2. `knowledge-base/project/specs/feat-one-shot-9851-art32-tom-art33-5-assessment/spec.md` (specification and claim-to-source table).
3. `knowledge-base/project/specs/feat-one-shot-9851-art32-tom-art33-5-assessment/tasks.md`.
4. `knowledge-base/project/specs/feat-one-shot-9851-art32-tom-art33-5-assessment/decision-challenges.md` (header `| Item | Class | Ruling |`, rows D1 to D18, CLO Review Record section).
5. `knowledge-base/project/specs/feat-one-shot-9851-art32-tom-art33-5-assessment/session-state.md` (pipeline-written run record).

## Implementation Phases (work phase)

**Phase 0 — Re-verify at the pinned commit.** Run the Verification Commands below; record each output line in `session-state.md`. Any fact that moved (an issue state, a merge timestamp, a later ADR addendum) is cited in its LATEST state. Read the end of ADR-075 for addenda newer than 2026-10-31.

**Phase 1 — Art. 32 TOM bullet and Superseded marker** (`article-30-register.md`). Pass criterion: AC9, AC10. Specification (from D11, D13, D14; draft in the register's own register of prose, not in a new voice):
- *Status word and title:* "open residual", naming shared heap, shared procfs and shared network of hosted agent sessions; exit event: the per-tenant executor (#9773, epic #9842); ledger rows I6 and I7 cited as not-shipped.
- *In force, and how far measured:* the inner Bash sandbox's `/proc` is an empty tmpfs with the container procfs beneath it (ADR-075 addenda 2026-10-11 #10032 and nested 2026-10-12 #10065); it rests on three conditions (unelevated bubblewrap, `--cap-drop ALL` in the vendored tail, unchanged run-tuple posture) pinned in CI; measurement sources are CI, dev host and the report-only faithful canary (verdict pass read 2026-10-12, post-mortem "Recovery verification"; say `proc_mask` was in that verdict only if the canary script confirms it, D14). Ledger: no row measures this mask as a claim; do not borrow I1 or I2 for it.
- *Not measured:* production-image behaviour beyond the canary; the hook against the real CLI (ledger I3); the live `AGENT_OUTER_WRAP` value (ledger I5, `unverified`).
- *Not covered, recorded rather than implied:* shared in-process heap; shared procfs on the file-tool tier (barrier named: the pre-tool hook, scope per ledger I3; no kernel control asserted, D13); shared container loopback and cross-use of a sibling session's delegated-egress proxy; abstract unix sockets (ledger I4, dark); shared HOME state by pointer to the breach-register 2026-10-31 row; IPC; the server process's own cross-tenant filesystem access.
- *Reliability limit:* regression detection is CI plus a report-only canary; no paging; no instrument exists for a read of a sibling process environment.
- *No-public-claim sentence:* "This entry makes no public claim; public wording is governed by the ledger's Publication Criterion" plus an as-of date. Do NOT write "no public legal document makes a claim" unless AC9(f)'s grep over the canonical legal documents and mirrors is run and its result is cited (the ledger's premise correction says isolation statements exist on public surfaces).
- *Cross-reference:* one clause pointing at the breach-register 2026-11-03 row; no assessment text in the bullet.
- *Superseded marker:* two-space-indented `  > **Superseded 2026-11-03 (#9851)**` lines directly under the arm-F bullet (the TLS bullet's form, so the blockquote stays inside the list item) and ABOVE the 2026-10-31 pointer comment, firing on the merge of PR 11966, covering exactly S1 "#9723 stays open", S2 "status: adopting", S3 the file-capability mechanism with the bounding-set claim, S4 sibling PIDs and environ "remain visible", S5 the "NOT yet measured in the production image" status line (D12), each with a pointer to the later record; no existing character edited. The ADR-272 bullet's "#9614 pending" sentence is left alone by CTO ruling T6 (the ledger records the non-reconciliation; the new bullet does not repeat it).
- *Must not say:* isolated, secure, tenant isolation (outside the quoted existing ceiling), closed, fixed, resolved, no exposure, not a breach; nothing in the past tense about this pull request; no "RCS" followed by a capitalised word (a consistency test reads that token); do not delete the Better Stack source strings other tests read.

**Phase 2 — Art. 33(5) row** (`breach-register.md`). Pass criterion: AC3, AC9. Nine cells, no pipe, appended after the 2026-10-31 row:
1. *Date:* 2026-11-03.
2. *Event:* tier (i) only. One defect sentence with a pointer ("a `/proc` deny declared in the sandbox configuration was not realized in the assembled sandbox command; realized by a later change and re-shaped again, see ADR-075 addenda 2026-10-08, 2026-10-11, 2026-10-12 and ADR-272 Note 2026-10-08"); the window wording of D5 verbatim in shape (conservative bound labeled, evidence date, approximate end, pointer clause for the fail-closed interval); "no read observed" stated as "none sought or instrumented".
3. *PA(s) touched:* "Hosted agent session processing (the per-session isolation entry); PA mapping is not re-derived in the record" (the 2026-10-31 row's form). Capacity: mixed, not re-derived.
4. *Awareness anchor:* 2026-10-07T19:14Z, the filing of the audit finding; anchors the vulnerability, not a breach; no monitor surfaced it.
5. *Determination:* REACHABILITY-ONLY, PROVISIONAL, draft v1 internal CLO attestation, not external counsel advice. Limb 1 conceded; limb 2 not established; reachability alone does not start the Art. 33 clock (standing rule, cited by the 2026-10-31 and 2026-09-30 rows). Names the conflicting measurements by pointer (ADR-272 Measurements versus the hand-built runs recorded in the Phase-0 measurements, which the ADR itself marks "not measured inside the production container image"), the reachable class (concurrent same-uid processes in the container, including a prompt-injected agent session; the server process is in the class and is not asserted readable), the cohort statement of D17, no notification made. Flip conditions: evidence of an actual read; a measurement of readable environ in the production image during the window; limb E1 finding procfs reads; use of a held credential by a non-holder; an arms-length user found in the window; on a flip, rotation of every secret the server process held (2026-09-24 row precedent), a FRESH 72h from awareness, Art. 34 re-run not inherited, Art. 33(2) processor notice without the risk threshold where Jikigai is processor, external counsel. Says the determination is recorded in this row and the canonical source carries the facts and remedy only. Also states: the CLO review record is identified by pull request 11966 and the branch slug (no path, no timestamp); data subjects and records are not quantified (no instrument); the data reachable is, at a generic level, credentials and session identifiers of the session's user held in a process environment, as the ADRs already say; precautionary rotation was considered and is not required on present evidence (becomes required on a flip); re-review at the next quarterly register review and when the account classification (E4) closes; why the assessment post-dates the anchor (owed under the epic's Stage 0 legal record, named as owed in the 2026-10-09 ruling).
6. *Art. 33 engaged?* "No — on the facts established to date; re-opens with a FRESH 72h from awareness of ..." (2026-10-31 form).
7. *Art. 34 engaged?* "No — assessed on its own facts".
8. *Evidentiary limbs inconclusive?* "Yes." E1 indirect instrument over retained session records unrun (needs the controller's authorisation, D18); E2 no instrument exists for a read of a sibling environ; E3 no production-image measurement during the window; E4 account classification open (2026-10-28 determination, to 2026-11-04).
9. *Canonical source:* `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md` and nothing else in the cell (D7).
- *Frontmatter:* add the same ADR path to `related:`, last in the list (inferred, removable).
- *Must not appear in the row:* argv tokens, bubblewrap versions, credential or variable names beyond those the ADRs already carry, host names, process or workspace identifiers, counts of accounts, query output, the leak-grep patterns of AC9(d), and the unresolved-marker words the lint rejects outside backticks (TBD, TODO, XXX, FIXME).

**Phase 3 — Checks.** Run AC1 to AC4, AC6, AC9, AC10, AC11 (all commands below), fix, re-run.

**Phase 4 — Review panel (first).** `soleur:review` with `soleur:engineering:review:user-impact-reviewer` (threshold single-user incident) plus the standard panel; security-sentinel scoped to disclosure content; findings are applied before the CLO review of Phase 5.

**Phase 5 — CLO review (last, on the final diff).** Spawn a fresh `soleur:legal:clo` (no row or bullet prepared by it) with the final diff and this plan's wording lists; tell it to write nothing under `knowledge-base/legal/audits/` (a file there would match the determination pattern and fail the register lint without a waiver); it returns a verdict per artifact. Append `## CLO Review Record` to decision-challenges.md: reviewer context, the patch id of the two-register diff and the two blob hashes as read, verdict, conditions applied, the stale compliance-posture pointer, and the privately routed finding (named as "routed", no content). Any later register edit invalidates the record and re-runs this phase (D8).

**Phase 6 — QA, compound, ship** per the pipeline; see Ship Notes.

## Verification Commands

Run from the repo root after `git fetch origin main`. These are record commands (their output is written to session-state.md and compared with the cited sources); the pass criteria are the Acceptance Criteria that follow.

```bash
git log --format='%h %ad %s' --date=iso-strict -S'enableWeakerNestedSandbox' -- apps/web-platform/server
git log --format='%h %ad %s' --date=iso-strict -S'"/proc"' -- apps/web-platform/server/agent-runner-sandbox-config.ts
git show 5b32babc70:apps/web-platform/infra/sandbox-canary-argv.json | grep -c '/proc'
for n in 9723 9860 9614 9773 9842 9543; do gh issue view $n --json state,closedAt; done
for p in 9768 10039 9874 1559 5928 9709; do gh pr view $p --json mergedAt; done
grep -n 'Addendum — 2026-1' knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md
grep -c proc_mask apps/web-platform/scripts/sandbox-canary.mjs
bash scripts/lint-legal-registers.sh
bash scripts/markdown-lint.sh knowledge-base/legal/article-30-register.md knowledge-base/legal/breach-register.md
(cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts)
bash scripts/check-pa-22.sh; bash scripts/lint-art30-reverification.sh; bash scripts/check-tom4-rls-posture.sh
bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch
```

## Acceptance Criteria

<!-- Patterns are built so this plan never contains the withheld number. Run after `git fetch origin main`. -->

- [ ] **AC1 — diff scope.** `git diff --name-only origin/main...HEAD | grep -vcE '^(knowledge-base/legal/(article-30-register|breach-register)\.md|knowledge-base/project/plans/(archive/[0-9]{8}-[0-9]{6}-)?2026-11-03-docs-art32-tom-residual-and-art33-5-assessment-9851-plan\.md|knowledge-base/project/specs/(archive/[0-9]{8}-[0-9]{6}-)?feat-one-shot-9851-art32-tom-art33-5-assessment/[^/]+|knowledge-base/project/learnings/([a-z-]+/)?[^/]+\.md)$'` prints `0` (a count, so a non-compiling pattern prints nothing); `git diff --name-only origin/main...HEAD | grep -c 'knowledge-base/project/learnings/'` prints 0 or 1. The generated `knowledge-base/INDEX.md` stays out of the diff (untracked). **Negative control (prints 4):** `printf '%s\n' docs/legal/privacy-policy.md apps/web-platform/x.ts knowledge-base/legal/compliance-posture.md knowledge-base/legal/audits/x.md | grep -vcE '<the same pattern>'`.
- [ ] **AC2 — withheld number.** Derive and test without printing: `N=$(gh issue list --state open --search 'in:title "action-required: enable egress audit collection"' --json number,title -q '[.[]|select(.title|startswith("action-required: enable egress audit collection"))]|if length==1 then .[0].number else empty end'); [ -n "$N" ] || echo CANNOT-DERIVE`, then `git diff -U0 origin/main...HEAD | grep -E '^\+' | grep -v '^+++' | grep -c -w -- "$N"` prints 0; `git log origin/main..HEAD --format=%B | grep -c -w -- "$N"` prints 0; `gh pr view 11966 --json title,body,comments -q '.title, .body, (.comments[].body)' | grep -c -w -- "$N"` prints 0. Never echo `$N`; never grep whole files (older register text carries it); `-U0` is required (context lines could carry it). Archive directory names are `YYYYMMDD-HHMMSS`, so a digit run inside a timestamp does not match `-w`; if any hit appears, triage it as a coincidence in a SHA or URL before regenerating the artifact. **Negative control (prints 1):** `printf '%s\n' "$N" | grep -c -w -- "$N"` (run once, output only the count).
- [ ] **AC3 — row shape and lint.** `bash scripts/lint-legal-registers.sh` exits 0 and its `rows=` count equals the `origin/main` count (`git show origin/main:knowledge-base/legal/breach-register.md | awk -F'|' '/^\| 20[0-9][0-9]-/{n++} END{print n}'`) plus 1; `awk -F'|' '/^\| 2026-11-03 /{print NF}' knowledge-base/legal/breach-register.md` prints exactly one line, `11` (9 cells, no pipe inside); the row's last cell is exactly one backticked path that resolves (`git cat-file -e origin/main:<path>` after trimming); `git diff --numstat origin/main...HEAD -- knowledge-base/legal/breach-register.md | awk '{print $2}'` prints 0 (no deleted line). **Negative control:** a copy of the row with an extra pipe prints `12`.
- [ ] **AC4 — markdownlint.** `bash scripts/markdown-lint.sh knowledge-base/legal/article-30-register.md knowledge-base/legal/breach-register.md` reports the two registers clean (not "nothing to lint"); run read-only, never `--fix`. The plan and spec files sit under `knowledge-base/project/`, which `.markdownlintignore` excludes, so the script reports them out of scope; the pass criterion for those files is a manual read for MD022/MD032 (blank line around headings and lists) and no hard tabs: `grep -c $'\t' <file>` prints 0 for each.
- [ ] **AC5 — CLO review recorded.** decision-challenges.md contains `## CLO Review Record` with verdict `DISCHARGED`, reviewer context "fresh", and a recorded patch id equal to `git diff origin/main...HEAD -- knowledge-base/legal/article-30-register.md knowledge-base/legal/breach-register.md | git patch-id --stable | cut -d' ' -f1` of the final tree (stable across rebases onto a moved main; the two blob hashes are recorded beside it for reference); `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0 (header exactly `| Item | Class | Ruling |`, every technical row starts `Ruled by CTO agent, <date>:` or `Ruled by CLO agent, <date>:`). **Negative control:** change one register byte; the patch-id comparison fails.
- [ ] **AC6 — no public surface or code edited.** `git diff --name-only origin/main...HEAD | grep -cE '^(docs/|plugins/|apps/|scripts/|\.github/|knowledge-base/legal/audits/)'` prints 0; `git diff --name-only origin/main...HEAD | grep -cE '\.sql$|/migrations/|/auth|app/api/'` prints 0 (the gdpr-gate skip stays valid). **Negative control (prints 3):** `printf '%s\n' docs/legal/x.md apps/a/migrations/1.sql scripts/x.sh | grep -cE '<the first pattern>'` after substituting the pattern.
- [ ] **AC7 — issue flow 0.** `bash plugins/soleur/skills/ship/scripts/net-issue-flow.sh 11966` exits 0 with FILED 0; no `gh issue create`, comment, edit, label or close appears in the work-phase tool log (the lead reviews it); `gh issue view 9851 --json state -q .state` prints `OPEN` after merge unless the lead closes it by hand under D10; #11669 untouched.
- [ ] **AC8 — PR hygiene.** `gh pr view 11966 --json body,title -q '.body, .title' | grep -ciE '(close[sd]?|fix(e[sd])?|resolve[sd]?) +#'` prints 0; the body contains `Ref #9851` and `Ref #9601`; the body states that preflight Check 4 (Doppler) was skipped (`gh pr view 11966 --json body -q .body | grep -c 'preflight Check 4'` prints 1); the body carries the displaced-path sentence of Ship Notes; the body names the stale ledger row I10 re-pin; no bracketed pending-review marker (the literal the ship gate greps) is added to any legal file (`git diff -U0 origin/main...HEAD -- knowledge-base/legal | grep -E '^\+' | grep -c '\[DRAFT'` prints 0).
- [ ] **AC9 — wording and claim trace.** (a) New bullet exists once: `grep -n -E 'Per-session filesystem isolation for hosted agent sessions|Superseded 2026-11-03 \(#9851\)|2026-10-31: #10455|open residual|^- \*\*Audit logging' knowledge-base/legal/article-30-register.md` lists, in this line order, the arm-F bullet, the Superseded marker, the 2026-10-31 comment, the new bullet, Audit logging. (b) The bullet contains `open residual`, the words `Not measured`, `Not covered` and an as-of date `2026-11-03`; the row's cell 5 contains `REACHABILITY-ONLY` and `PROVISIONAL`; cells 6 and 7 begin `No`; cell 8 begins `Yes`. (c) Forbidden phrases over added legal lines: `git diff -U0 origin/main...HEAD -- knowledge-base/legal | grep -E '^\+' | grep -niE 'no exposure|no personal data|not a breach|tenant isolation|secure|fixed|resolved|closed'` prints only lines that quote the existing ceiling sentence or the word "closed" in "fail-closed" or "closed" inside the Superseded marker's quotation of an old sentence; every hit is justified in the CLO record. (d) Leak grep: `git diff -U0 origin/main...HEAD -- knowledge-base/legal | grep -E '^\+' | grep -nE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}|/workspaces/|web-[12]|--bind /proc|bwrap [0-9]|bubblewrap [0-9]|GIT_INSTALLATION_TOKEN|GH_TOKEN|ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN'` prints nothing. (e) Every dated fact (issue state, merge timestamp) in the two entries equals the live `gh`/`git` output of Phase 0 (spot-check list recorded in session-state.md) and the claim-to-source table in spec.md has a resolving anchor for each claim the diff adds; the ADR anchors are checked by `grep -n` for the addendum heading. (f) If the bullet says anything about public documents: `grep -rliE 'procfs|/proc|sandbox|tenant isolation' docs/legal plugins/soleur/docs/pages/legal` output is recorded and the sentence is scoped to it; otherwise the bullet carries only "this entry makes no public claim". **Negative control:** a scratch copy with the phrase "no exposure" makes (c) print a hit.
- [ ] **AC10 — Superseded marker and additive diff.** `git diff --numstat origin/main...HEAD -- knowledge-base/legal/article-30-register.md | awk '{print $2}'` prints 0 (no deleted line, so no existing character is edited); the marker begins `  > **Superseded 2026-11-03 (#9851)**` (two-space indent), sits directly under the arm-F bullet and above the 2026-10-31 comment, and names S1 to S5 as listed in Phase 1. **Negative control:** a scratch copy of the register with one character of the arm-F bullet changed prints a non-zero deleted-line count.
- [ ] **AC11 — related tests green.** `(cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts)` exits 0; `bash scripts/check-pa-22.sh`, `bash scripts/lint-art30-reverification.sh` and `bash scripts/check-tom4-rls-posture.sh` exit 0; `python3 scripts/lint-infra-no-human-steps.py <plan> <spec files>` exits 0.
- [ ] **AC12 — review panel run.** `soleur:engineering:review:user-impact-reviewer` and the standard panel ran on the pushed branch before the final CLO pass (recorded in session-state.md with finding counts); no P1 open.

## Test Scenarios

1. **Window dates drift.** If `gh pr view 9768 --json mergedAt` or the ADR-075 addenda differ from the Phase 0 record, the row cites the live value and AC9(e) is re-run.
2. **Row breaks the table.** A literal pipe in the row makes AC3's `awk` print 12; fix the cell.
3. **Marker rewrites history.** Any `-` line in the Art. 30 diff makes AC10 print more than 1.
4. **Over-claim.** "no exposure" or "tenant isolation" in an added line makes AC9(c) print a hit; reviewers treat any unexplained hit as P1.
5. **Disclosure.** Any pattern of AC9(d) in an added line is P1 (public repository).
6. **Withheld number.** An added line, commit or PR text containing it makes AC2 print above 0; amend before push, since history cannot be unpublished once pushed.

## Ship Notes (for the lead)

- PR body: `Ref #9851`, `Ref #9601`; no close keyword; "preflight Check 4 (Doppler) was skipped"; the post-archive plan path FIRST, bare (no backticks; the gate takes the first `knowledge-base/project/(plans|specs)/` match and needs the file to exist, so write it after ship's archival step; a spec path must not come first because it carries no threshold frontmatter) so the ship counsel-review gate fires (D8), and this sentence with the audits path in backticks (the body check strips only backticked spans): "Diff scope displaced the canonical counsel-review audit (`knowledge-base/legal/audits/2026-11-counsel-review-9851.md`): this change is limited to the two registers, so the CLO review is recorded in this feature's decision-challenges.md under CLO Review Record, and the ship counsel-review gate is run against that record; the audit file was not created."; a line that the ledger's row I10 is stale after merge and a re-pin is owed (the entry's existence makes nothing claimable); decision-challenges.md rows render through ship.
- The ship counsel-review gate is satisfied only by a CLO review on the FINAL committed diff (D8). Do not add draft markers.
- Ship archives the spec and plan directories under a timestamp prefix. No register cell cites them. Pre-compute the `YYYYMMDD-HHMMSS` stamp with `date`; if the digits could collide with the withheld number, re-run the archive before committing (AC2).
- Merge via the queue only after AC1 to AC12 pass at the final head; after merge, `bash scripts/lint-legal-registers.sh` on `main` is green, then the lead may close #9851 by hand (D10).
- Findings For The Lead: one finding routed outside the repository (D13) and reported in the planning session summary; a ledger re-pin; the stale pointer in `compliance-posture.md`.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it.
- The register lint reads the second-to-last cell of each dated row; a trailing pipe or extra cell breaks it silently into a different column count (AC3 checks `NF`).
- `git diff` without `-U0` can show context lines carrying the withheld number from older register text (AC2).
- A Superseded marker is a locator pasted into a cell-adjacent place: check the "directly under the arm-F bullet" claim by reading the rendered position, not by assuming (learning 2026-09-18).
- Cite sections and addendum headings, never line numbers; cite the LATEST addendum when two disagree (the #10065 nested addendum overrides the #10032 "no procfs mounted" sentence).
- Do not use `--fix` with markdownlint on these files; it corrupts table cells.
- The CTO and CLO rows in decision-challenges.md contain no literal pipe; keep it that way when editing.
