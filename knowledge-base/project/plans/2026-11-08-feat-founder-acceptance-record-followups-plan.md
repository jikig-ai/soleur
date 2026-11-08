---
title: "feat: founder acceptance record follow-ups (published retention wording, CPO deck sign-off, pin tripwire, parked hold check, credential-free aggregate check, Inbox entry)"
date: 2026-11-08
slug: founder-acceptance-record-followups
branch: feat-one-shot-founder-acceptance-followups-12365
issue: 12365
type: feat
priority: p3-low
domain: legal, engineering, product
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
closes: [12396, 12429]
refs: [12197, 12011, 12365, 12366, 12080]
---

## Overview

One pull request (the operator asked for one) that finishes the follow-ups left by the founder-acceptance-record work (Ref #12197, #12011). The record is live: the `approval-queue` flag is ON for role-prd, `FLAG_APPROVAL_QUEUE=1` is mirrored in Doppler prd, and the founder's acceptance of text hash `10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287` reads back as `accepted`, `row_ok: true`. The six items:

1. **#12365** the published Privacy Policy 4.17, GDPR Policy 3.19 and Data Protection Disclosure 2.3(aj), 5.3(a), 10.3(l) still say "no period confirmed (proposal: life plus 5, max 10)" and that nothing is recorded. Bring them to the committed text.
2. **CPO deck sign-off** set `signOff.cpo` (the CPO ruled; `PROVISIONAL` stays true).
3. **#12366** terms wording for a first-ever text, the "a few minutes" vs 10 minutes code wording, and the base-SHA pin guard (kept deferred behind a mechanical tripwire).
4. **#12396** server-side enforcement of the `parked` label as a required-check member step (no ruleset change).
5. **#12429** a credential-free pre-flag aggregate check (a `service_role` RPC plus a bearer-gated sibling route).
6. **Navigation** a founder-visible Inbox row that leads to `/dashboard/approvals/legal`.

Hard constraints carried through every phase: `founder-acceptance-record.md` bytes do not change (a changed byte is a new hash and the founder is asked again; nothing here edits it); the service key has no grant on `legal_acceptance` and `DATABASE_URL` stays reserved by the runbook, so decisions are read only through `GET /api/internal/legal-acceptance/<key>?hash=<hash>` with the verify bearer, projected to `status` and `row_ok`; `approval-queue` is not touched (any flip needs an exact-command go from the operator, `hr-menu-option-ack-not-prod-write-auth`); outcomes are recorded as comments on #12197 stating what was measured and what was not.

## Research Insights

### Premise Validation (Phase 0.6)

Checked: #12365, #12366, #12396, #12429, #12197, #12011 all OPEN with no closing PR. PR #12342 (the parked hold and the founder acceptance record) is MERGED (2026-11-08T18:21:47Z), so the hook and the `parked` triage tier are on `origin/main`. `origin/main` tops out at migration 185; the CTO checked 80 open PRs and none adds 186 or 187. Collision pre-check: the only open change naming #12365 is this branch's own draft PR #12438; #12366, #12396 and #12429 are unnamed by any PR. The cited paths all exist on `origin/main`: the text, the CLO ruling, `legal-acceptance-copy.ts`, the verify route, migrations 184/185, `infra/github/ruleset-ci-required.tf`. One premise was STALE and drives item 1: the CLO's own ruling L7 (2026-11-08) said to leave the trio unchanged because the flag was off, the only data subject was the operator and a public "5 years" would precede the deletion step. The flag is now on, a record exists and the trio's "nothing is recorded" preface is now false; the CLO re-ruled (Decision Classes below). One premise in the brief is partly wrong: it asks to "drop PROVISIONAL" after the CPO signs; the CPO and the standing CLO ruling D rule that the constant must stay true.

ADR corpus check of the proposed mechanisms: ADR-032 (required checks; umbrella contexts, always-run aggregators) governs #12396 and already contains the umbrella pattern, so a member step is the existing mechanism, not a new one; ADR-319 (legal acceptance record) governs #12429 and its amendments are append-only. Neither lists the proposed mechanism as a rejected alternative.

### Property List and Cut List (Phase 0.6b)

Properties the asks buy:

- P1 A reader of the published documents is not told a retention period or a processing status that contradicts the committed text.
- P2 The card deck carries a recorded product sign-off and says nothing false about code validity or about a first-ever terms text.
- P3 A changed byte of a published text cannot ship unnoticed once there is more than one text.
- P4 A PR carrying `parked` cannot be merged by any identity that is subject to the required checks, and an unreadable label state fails closed.
- P5 The pre-flag question "does any row exist for this key under a hash other than the registry hash?" can be answered with the verify bearer alone.
- P6 The founder can find the legal-text card from the Inbox after the first visit.

Cut List (mechanism, property, what already covers it):

- A shared `parked-check` helper called from 8 merge sites (#12396 item 2) cut: P4 is bought by the required check; `admin-merge-ready.sh` already grades every required context, so a parked PR is red there with no edit (CTO R1).
- A new top-level required context `parked-hold` cut: needs a Terraform ruleset apply, canonical-JSON and `required-checks.txt` edits, and a bot synthetic, for no gain over a member step of an existing umbrella (CTO R1).
- A `labeled`/`unlabeled` trigger added to `ci.yml` cut: it would re-run the whole suite on every label event and `cancel-in-progress` would cancel in-flight runs; `secret-scan.yml` already lists both types (CTO R1).
- A mode flag on the existing verify route for counts cut: the route's contract is "exactly four keys, one configured founder" and `hold-gate-eval.sh` asserts it (CTO R2).
- A small-cell floor on the counts cut: it would hide the n=0 / n=1 answer, which is the question (CTO R2).
- A sidebar nav item cut: `NAV_ITEMS` is shared with the command palette, `g` sequences, overlay and tour, and the founder check is server-only (CPO).
- A `hold-gate-eval.sh` gate kind for counts cut: no consumer yet (CTO R2).
- Building the registry base-SHA guard now cut: only one text exists; replaced by a tripwire that makes the second text author build it (CTO R3).

### Institutional learnings applied

- Editing `docs/legal/*.md` needs the mirror, the `LEGAL_DOC_SHAS` pin and the Last Updated chain in one PR; only the full `test-all.sh` gate catches orphaned guards (`2026-05-29-legal-doc-triple-lockstep-and-rpc-grants-invoker-before-definer.md`). The mirror carries its own `**Last Updated:**` line (`2026-11-02-mirror-legal-doc-carries-its-own-last-updated-chain.md`). `legal-doc-consistency.test.ts` enforces heading-sequence parity (`2026-06-15-two-legal-mirror-gates-and-always-build-mcp-registered-list-desync.md`): no heading changes in the trio.
- A SECURITY DEFINER RPC bypasses the RESTRICTIVE jti-deny RLS policy: re-assert `is_jti_denied_from_jwt()` after the `auth.uid()` check where the function is reachable by a user token (`security-issues/2026-07-09-...`). The counts RPC is `service_role`-only and refuses any caller with `auth.uid()` set, which is the 185 pattern; the work phase confirms the jti predicate is not needed for a function no user token can execute.
- Every definer function needs the full 3-role REVOKE or the rpc-grants lint's lazy regex mis-attributes it (`2026-05-29-...`); Supabase default privileges defeat `REVOKE FROM PUBLIC` alone (`2026-05-06` / `2026-07-10` learnings): 186 revokes from `PUBLIC, anon, authenticated, service_role` then grants `service_role`.
- Migration number collision mid-pipeline (`workflow-patterns/2026-06-30-migration-number-collision-mid-pipeline.md`): re-check the next free number against `origin/main` at work time and again at ship.
- Merge-queue adoption (`best-practices/2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md`): job-level `if: pull_request` skips on `merge_group` and stalls the queue; diff bases branch on `merge_group`; an empty base must hard-fail, never fall through to exit 0. Required-check anchors must cover the verified surface (`2026-06-29-required-check-anchors-...`).
- `2026-11-08-a-hold-that-lives-only-in-the-pr-it-protects-holds-nothing-...`: draft is the only hold that works in every checkout; a shell-text matcher needs allow rows as well as deny rows.
- `2026-09-25-a-proof-by-absence-close-on-a-flag-gated-surface-proves-nothing.md`: the pre-flag count is measured, not inferred from "no signal".
- `2026-10-29-hitl-approval-queue-the-fixes-were-the-defective-part-and-six-ci-guards-no-local-suite-selects.md`: run the repo-global lints (ESLint on changed files, feature-map coverage, service-role allowlist, sweep completeness) before the first push.

### Code facts the plan rests on (cited by name)

- `LEGAL_COPY.dialog.codeBody` and `LEGAL_COPY.dialog.verifyError.wrong_code` in `apps/web-platform/lib/legal-acceptance-copy.ts` say "a few minutes"; `supabase/templates/magic-link.html` says "This code expires in 10 minutes" and "Enter this code to sign in to your Soleur account"; `supabase/scripts/configure-auth.sh` sets `mailer_otp_exp: 600`; `supabase/config.toml` has `otp_expiry = 3600` for local dev only. Nothing pins "10 minutes" today.
- `LEGAL_KIND_COPY.terms` carries "the updated" in `pendingTitle`, `acceptedTitle`, `declinedTitle`, `answerDetail`.
- `registry-pins.test.ts`: `PUBLISHED` append-only, `checkPins()`; one text, one pin row.
- `GET /api/internal/legal-acceptance/[key]` (`route.ts`): config, bearer (`readNamedBearerSecret`, `bearerMatches`), shapes, registry, `verifyAcceptance`, `ackState`; answers four keys for the one configured founder; `PUBLIC_PATHS` holds the prefix `/api/internal/legal-acceptance`; `verify-route-census.test.ts` walks the directory recursively.
- Migrations 184/185 pattern: `SECURITY DEFINER`, `SET search_path = public, pg_temp`, `auth.uid() IS NOT NULL` raises 42501, shape predicates raise 22023, `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role`, `GRANT EXECUTE ... TO service_role`, a `verify/NNN_*.sql`, a `.down.sql`, a static migration test.
- `isLegalSurfaceEnabled(userId)` in `server/legal-acceptance/surface.ts`: founder match first (no flag read for a non-founder), then the flag with `workspaceId: null`.
- The CI Required ruleset is Terraform (`infra/github/ruleset-ci-required.tf`); required contexts are three umbrellas (`guards-ruleset` in `ci.yml`, `quality-guards`, `secret-guards` in `secret-scan.yml`); `ci.yml` triggers on `opened, synchronize, reopened, ready_for_review`; `secret-scan.yml` also lists `labeled`, `unlabeled`; bypass actors OrganizationAdmin and Admin role in `pull_request` mode.
- The C4 model already has `webapp -> legalAcceptanceStore` (service_role RPCs) and `founder -> legalAcceptanceStore` (owner-level query, runbook) in `model.c4`; the element description names migrations 184 and 185.

## Research Reconciliation: Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "set signOff.cpo and drop PROVISIONAL" after the CPO signs | The CPO ruled `PROVISIONAL` must stay true (human lawyer review owed, flag global, first-real-row and non-Jikigai-founder conditions open); the standing CLO ruling D and the attestation status say the same | Set `signOff.cpo` only; keep `PROVISIONAL: true`; reword the header comment and test title; recorded as a deviation from the brief in `decision-challenges.md` |
| #12396 "required check or ruleset" | A new required context needs a Terraform ruleset apply; a member step of an existing umbrella needs none | `parked-hold` member step in `secret-guards` (CTO R1); no production-mutating step |
| #12396 item 2 "shared parked-check helper at 8 merge sites" | The required check binds auto-merge, the queue and all non-bypass identities; `admin-merge-ready.sh` grades every required context | No helper (Cut List); wording changes in `drain-prs/SKILL.md` and the hook header only |
| #12429 "RPC or endpoint" | Both are needed: the service key cannot call a table, and the caller is a shell with the bearer | RPC `legal_acceptance_hash_counts` plus sibling route `[key]/counts` (CTO R2) |
| #12365 "update the retention wording" | The preface ("written ahead ... nothing is recorded"), the status-check sentence and the monitoring event field list are also false or inconsistent now | The CLO rulings cover all of them (Phase 1) |
| #12366 item 3 "add a base-SHA guard when a second text is added" | One text exists; the trigger has not fired | Keep deferred, add a mechanical tripwire test (CTO R3); the issue stays open for item 3 |
| "decide with the CPO whether Inbox gets an entry" | Neither #12429 nor #12396 covers navigation | CPO ruled an Inbox row; it ships as its own commit with `Ref #12197`, no new issue |
| Doc claims "no menu entry reaches /dashboard/approvals/legal" | Confirmed: `inbox-severity.ts` maps `approval_required` to `/dashboard/approvals/${approvalId}` (UUID only); nothing links to `/legal` | Phase 4 |

## Decision Classes (summary; the table of record is `decision-challenges.md`)

All technical forks were delegated and ruled on 2026-11-08: CLO (wording, preface, draft markers, code validity, terms wording, TC_VERSION), CPO (sign-off, PROVISIONAL, navigation), CTO R1 to R4 (parked hold, counts shape, pin tripwire, Inbox mechanism). Operator-only items: none are open. The production-mutating steps in this PR are the standard release pipeline (migration 186 applied before deploy, additive function only); no ruleset apply, no flag change, no Doppler write.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (two-stage `--json` then `jq --arg`) against 18 planned source, workflow, document and test paths on 2026-11-08: `None`. The Inbox consumer sweep may add paths; the work phase re-runs the query on the final list and records Fold in / Acknowledge / Defer per hit.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "#12365: update the published Privacy Policy, GDPR Policy and Data Protection Disclosure so their retention wording matches the committed text" [brief] | Phase 1 | mapped |
| 2 | "Run the legal-doc consistency and drift tests (legal-doc-consistency, legal-doc-shas-guard) and keep the docs/ and plugin mirrors in step." [brief] | Phase 1 tasks 1.4 to 1.6, AC1 to AC4 | mapped |
| 3 | "Invoke the CPO agent to review the deck and record its ruling as \"Ruled by CPO agent, <date>\"; only then set signOff.cpo and drop PROVISIONAL, with the matching test updates." [brief] | Phase 5 (sign-off set; PROVISIONAL drop descoped by CPO ruling) | mapped (partly descoped, justification: CPO and CLO ruling D rule the constant stays true while a human lawyer review is owed) |
| 4 | "#12366: the terms-wording and base-SHA pin follow-ups; read the issue and do what it lists." [brief] | Phase 2 (items 1 and 2 done; item 3 tripwire) | mapped |
| 5 | "#12396: server-side enforcement of the `parked` label ... Design it as a required check or ruleset, not another text matcher; ask the CTO agent for the shape first." [brief] | Phase 6 | mapped |
| 6 | "#12429: a credential-free pre-flag aggregate check (verify-token-gated SECURITY DEFINER RPC or endpoint returning count(*) and counts by text_hash for a key, no founder_id, no note, no row data)" [brief] | Phase 3 | mapped |
| 7 | "run the plan, GDPR gate and review panel properly" [brief] | `## GDPR / Compliance Gate`, Plan Review, review-time panel in the Acceptance Criteria | mapped |
| 8 | "Navigation: ... Decide with the CPO agent whether a founder-visible entry belongs in Inbox; fold it into #12396 or #12429 rather than opening a new issue" [brief] | Phase 4 | mapped (folded as its own commit under `Ref #12197`, justification: neither issue covers navigation, CPO ruling) |
| 9 | "Merge through the merge queue only after the PR-attached CI is green; archive the plan and spec inside the PR before merging ... Verify the served build sha on https://app.soleur.ai/health after each deploy." [brief] | Phase 7 | mapped |
| 10 | "Record outcomes as comments on #12197, stating what was measured and what was not." [brief] | Phase 7 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Retention edits in the three documents and mirrors | "update the published Privacy Policy, GDPR Policy and Data Protection Disclosure" | asked |
| Replace the false "written ahead" preface and status-check sentence | "so their retention wording matches the committed text" | inferred, justification: leaving "nothing is recorded" beside a 5-year retention statement makes the same section contradict itself (CLO ruling 2) |
| Fix the monitoring event field list (drop "text fingerprint") | "matches the committed text" | inferred, justification: the committed text says the monitoring copies do not hold the fingerprint; the published sentence says they do (CLO ruling 1, L2 inconsistency) |
| GDPR 8.4 pointer paragraph and PP Section 7 line | "update the published Privacy Policy, GDPR Policy ..." | inferred, justification: both state account data is deleted on request or give the old proposal; they would contradict 3.19 and 4.17 |
| `legal-doc-shas.ts` re-pin and mirrors | "keep the docs/ and plugin mirrors in step" | asked |
| `signOff.cpo` and test edits | "only then set signOff.cpo" | asked |
| `codeBody` / `wrong_code` wording | "#12366: ... read the issue and do what it lists" | asked |
| First-ever terms wording incl. `noBody` and `declinedBody` ("The current terms stay in place") | "do what it lists" | inferred, justification: same defect class as "the updated" (false for a first-ever text), CLO ruling 7 |
| Tripwire `needsBaseGuard` in `registry-pins.test.ts` and a README sentence | "the terms-wording and base-SHA pin follow-ups" | asked (item 3 kept deferred, tripwire added so the deferral cannot rot) |
| `parked-hold` member step, `scripts/ci-parked-hold.sh`, self-test | "server-side enforcement of the `parked` label" | asked |
| Delete `parked-merge-hold-enforcement-12342.sh`, reword `drain-prs/SKILL.md` and the hook header | "the local hook and triage tier are a best-effort guardrail only" | inferred, justification: the probe re-evaluates the server-side route this PR ships, and the best-effort wording would be false after it lands |
| Migration 186, RPC, `[key]/counts` route, helper script, runbook and ADR-319 edits | "credential-free pre-flag aggregate check" | asked |
| `STORE_FAILED_STAGES` gains `counts`; alert-op contract test | "credential-free pre-flag aggregate check" | inferred, justification: the sentry op-contract test fails otherwise (CTO R2) |
| Inbox `kind: "legal"` row and its consumer sweep | "Decide with the CPO agent whether a founder-visible entry belongs in Inbox" | asked (CPO ruled yes, CTO R4 shaped it) |
| ADR-032 and ADR-319 amendments, C4 edge text | "run the plan, GDPR gate and review panel properly" | inferred, justification: `wg-architecture-decision-is-a-plan-deliverable` requires the ADR/C4 update in the same plan |
| New issue for the item-5 hook-cost measurement plus the admin-bypass residual | "Design it as a required check or ruleset" | inferred, justification: CTO R1 rules item 5 is measure-first and the admin bypass is a stated residual; net issue flow is -1 (closes #12396 and #12429, files 1) |

### Split Assessment

- Subsystems touched: 7 (`apps/web-platform`, `docs`, `plugins`, `scripts`, `.github`, `knowledge-base`, `.claude`).
- Planned files: about 60 (about 25 source and workflow, about 20 test, 6 legal documents, remaining records). Estimated changed lines: about 1900.
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR, by explicit operator direction ("Work these items in one PR"); the thresholds are all exceeded, so the seams are: (a) legal trio, (b) deck + tripwire, (c) counts RPC/route, (d) Inbox row then CPO sign-off, (e) parked-hold. The plan orders them as separate commits for review and bisect, and the CPO sign-off commit follows the Inbox commit. Rollback is whole-PR (the merge queue squashes): reverting restores the old trio together with its `LEGAL_DOC_SHAS` pins and mirrors in one atomic revert, and migration 186's down file removes only the function.

## User-Brand Impact

- **If this lands broken, the user experiences:** the founder opens the Inbox and gets a row that leads to a 404 (gate dropped), or a card that says the code lasts a different time than the email, or the published policies promise a retention the text does not.
- **If this leaks, the user's data is exposed via:** the new counts RPC or route returning more than `{total, by_hash}` (a founder id, a choice, a timestamp or the note), or the new Inbox read selecting `requested_edit` (the Request changes note) into an API payload; or a service-role path becoming reachable by a user token.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the table has one data subject today, the operator, but it is a regulated legal-consent record on a `service_role` boundary and a public retention commitment; one leaked note or one wrong published commitment is a single-user incident, not an aggregate pattern.

`requires_cpo_signoff: true`: the CPO has reviewed the deck and the navigation (Phase 2.5 below); `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Architecture Decision (ADR/C4)

### ADR

- Amend **ADR-319** (append-only, "Amendment 2026-11-08 (#12429)"): the counts RPC/route as the credential-free pre-flag read; the verify bearer now also grants aggregate reads (a scope widening of one token, not a new credential); the runbook's owner-SQL pre-flag step is replaced; the endpoint reveals only `{key, registry_hash, total, by_hash, ok_to_flag}`; no small-cell floor and why.
- Amend **ADR-032** (one line, "Amendment 2026-11-08 (#12396)"): `parked-hold` is a member step of `secret-guards`, hosted there because `secret-scan.yml` already triggers on `labeled`/`unlabeled`; it binds auto-merge, the queue and non-bypass identities and does not bind a bypass actor running `gh pr merge --admin` (stated residual; `admin-merge-ready.sh` is the shipped gate for that path); a `parked` label applied by an Actions actor with `GITHUB_TOKEN` fires no `labeled` run, so a parked bot PR keeps its fabricated-green `secret-guards` until its `merge_group` run; each queue entry is judged by its own `merge_group` build (queue `ALLGREEN`, `max_entries_to_merge = 3`), so a label added to a lower entry after its build is not seen; the hook-cost number (Phase 6.7).
- Both are tasks in Phase 3 and Phase 6, not follow-up issues.

### C4 views

Read all three files (`model.c4`, `views.c4`, `spec.c4`) at work time and cite what was checked. Already seen at plan time: the actor `founder` and the system `legalAcceptanceStore` exist; `webapp -> legalAcceptanceStore` already carries "reads the record through service_role RPCs" (the counts RPC is one more service_role read on the same edge; the edit is to the `legalAcceptanceStore` element sentence that says the agent can read "four fields about ONE decision", which the counts route falsifies, plus the migration list in its description; prefer "service_role RPCs, list in ADR-319" over naming each migration so the next migration needs no C4 edit); `founder -> legalAcceptanceStore` describes the owner-level query for note reads (unchanged, the note read stays owner-only; the pre-flag read leaves that edge). External actors/systems: none new (GitHub Actions and the operator are modeled; no new vendor). After the edit regenerate `model.likec4.json`, run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (the `secret-guards` member count may be embedded in edge prose).

### Sequencing

The ADR amendments describe the shipped state and land in the same PR as the code.

## Implementation Phases

Order: 0 pre-flight, 1 legal trio, 2 deck wording + tripwire, 3 counts, 4 Inbox row, 5 CPO sign-off (strictly after 4), 6 parked-hold, 7 records and release. Each phase is a separate commit group; tests are written first for each (`cq-write-failing-tests-before`).

### Phase 0 Pre-flight

- 0.1 `git fetch origin main`; confirm the next free migration is 186 (`ls apps/web-platform/supabase/migrations | tail -3` on `origin/main`); re-check at ship.
- 0.2 Confirm `texts/founder-acceptance-record.md` sha256 is `10d283e0...a287` before and after every phase (AC17).
- 0.3 Re-run the code-review overlap query on the final file list.
- 0.4 Verify the live code lifetime read-only (Supabase auth config via the management API with the existing read path, or `configure-auth.sh` is the repo statement of intent): "about 10 minutes" is a claim about the live project, so record what was measured. If the live value is not readable by the agent, state that the claim rests on `configure-auth.sh` and `magic-link.html` and add the pinned test (Phase 2).

### Phase 1 Published trio (#12365), wording ruled by the CLO agent

Source of truth: the committed text and `knowledge-base/legal/audits/2026-11-07-clo-ruling-founder-acceptance-record-12197.md`. The CLO ruling text (2026-11-08) is persisted verbatim in `knowledge-base/project/specs/feat-one-shot-founder-acceptance-followups-12365/clo-wording-rulings.md` (decision rows C1 to C7); work applies the OLD to NEW strings exactly (each OLD must match once before and each NEW once after).

- 1.1 Block R (retention, new wording) in PP 4.17 Retention, GDPR 3.19 Retention, DPD 2.3(aj) Retention: "5 years from the date of the decision, and then we delete the record. ... longer only while a legal claim, a complaint or an official inquiry about the record is open ... We have not yet built the step that deletes a record ... we will build it before any record reaches that age, and until then records are kept as they are ... Copies in database backups may last for a further period we have not measured. Records of code requests are not covered by the 5 years ... monitoring copies ... 90 days Sentry and Better Stack ... own servers limited by disk space."
- 1.2 Other edits: PP Section 7 deletion bullet (the "No retention period is confirmed ..." line); PP 4.17 and GDPR 3.19 "The note" bullet (kept for as long as the decision record is kept; cannot be removed on its own); GDPR 8.4 pointer paragraph; DPD 5.3(a) ("which now exists for the Jikigai operator's account") and 10.3(l) (period, hold clause, deletion step not yet built).
- 1.3 Falsehood fixes: replace the italic "written ahead of the processing" preface in all three with the dated status paragraph (keep its `[DRAFT ...]` marker); replace the "not switched on at the date of this amendment (November 6, 2026)" status-check sentence; fix the PP "Why" bullet and the GDPR Purposes (iv) sentence; remove ", text fingerprint," from the monitoring-event field list and add the Better Stack log-line clause in all three "Who can see it" passages after grepping `reportLegalOp` call sites for the fields each event carries. CLO ruled: no day is stated ("in November 2026"); if the operator has the switch-on date it may replace that phrase.
- 1.4 `**Amended:** November 8, 2026` entry (CLO wording, with the trailing "Ref #12011, #12365." and the "(#12365)" in the Superseded marker dropped: public legal-document annotations carry no issue numbers, `2026-05-12-public-legal-doc-annotations-no-pr-numbers.md`; the CLO is told in the PR body) added after the November 6 entry in each of the three documents (and their mirrors), plus the `> **Superseded November 8, 2026 (#12365) ...**` marker under the November 6 entry. DRAFT markers stay byte-identical; the new Amended entry carries one. Do NOT touch the `**Last Updated:**` line (CLO; the November 6 entry is the precedent). No heading changes. No TC_VERSION bump, no re-acceptance (TC_VERSION applies to the Terms only).
- 1.5 Mirrors: `plugins/soleur/docs/pages/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` get the same body edits; sync the mirror's whole `**Last Updated:**` chain and hero only if the canonical chain moved (it does not).
- 1.6 Recompute `sha256sum docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` into `LEGAL_DOC_SHAS` in `apps/web-platform/lib/legal/legal-doc-shas.ts`.
- 1.7 Add a small test (`apps/web-platform/test/legal-acceptance/published-retention.test.ts`) asserting that each of the three canonical documents and the committed text contain `5 years from the date of the decision` and the "not yet built" statement, and that none of the three contains `life of the legal text plus 5` (AC1 is otherwise a grep). Post-merge: confirm the Eleventy site serves the new text (7.4). Then run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts test/legal-doc-shas-guard.test.ts`, `bash apps/web-platform/scripts/check-tc-document-sha.sh`, `bash scripts/lint-legal-mirror-drift-baseline.sh`, the markdown lint (`scripts/markdown-lint.sh`) on the six files, and the full `test-all.sh` gate (orphaned guards only surface there).
- 1.8 Append-only records: a dated addendum in the CLO ruling file ("Review round 2, 2026-11-08": L7 superseded by the operator's #12365 instruction and the changed facts; the six wording rulings), a `> Superseded` marker on the L7 row, and a pointer from the compliance-posture row if it names the old proposal (`grep -n "life of the legal text plus 5" knowledge-base/legal/ -r`). The DSAR lockstep gate does not fire (the legal-acceptance paths are not on its list), so `compliance-posture.md` is edited only where it states the old proposal.
- 1.9 #12365 stays OPEN, narrowed: edit its body to say the wording is done and the remaining acceptance criterion is the human-lawyer review of the final-form trio before the first non-Jikigai founder (this keeps the legal-risk tracker without a new issue). PR body uses `Ref #12365`, not `Closes`. Recorded as a taste row for ship to surface.

### Phase 2 Deck wording (#12366 items 1 and 2) and the pin tripwire (item 3)

- 2.1 Tests first in `apps/web-platform/test/legal-acceptance/legal-copy.test.ts` (byte pins, `TERMS_PRESUMING`, `FORBIDDEN_CLAIMS` walker).
- 2.2 `legal-acceptance-copy.ts` (CLO ruling 6): `dialog.codeBody` becomes "The code works for about 10 minutes. The email may say the code is for signing in: use it here. Nothing is recorded until your code is checked."; `verifyError.wrong_code` "Codes only work for about 10 minutes."; `sendError.locked` ("wait a few minutes") and `codeHint` stay. Change the card, not the shared sign-in template (a production auth-config PATCH).
- 2.3 Two assertions inside `legal-copy.test.ts` (a repo-intent pin, not proof of the live lifetime) reading `apps/web-platform/supabase/templates/magic-link.html` for `expires in 10 minutes` and `apps/web-platform/supabase/scripts/configure-auth.sh` for `"mailer_otp_exp": 600`; the test comment states that editing the shared template now breaks the card pin on purpose.
- 2.4 `LEGAL_KIND_COPY.terms` (CLO ruling 7): drop "updated" from `pendingTitle`, `acceptedTitle`, `declinedTitle`, `answerDetail`; `noBody` "Nothing changes. Nothing is accepted. Final once recorded."; `declinedBody` "Nothing changed. Nothing was accepted. This answer is final: ..."; the other fields stay. The acknowledgement kind is untouched, so the founder's card for the committed text is byte-identical in behavior.
- 2.5 Tripwire (CTO R3): in `registry-pins.test.ts` add a pure `needsBaseGuard(served, guardExists)`; it fails when two or more texts are served and `scripts/check-registry-pin-base.sh` is absent, and its failure message carries the guard shape (member of `guards-ruleset`, `git merge-base origin/main HEAD`, `MERGE_GROUP_BASE_SHA` fallback, hard-fail on an unresolvable base, compare `git show <base>:<file>` sha256, require changed `version` plus a retained old pin row plus a new row). Rows: one text, no guard passes; two texts, no guard fails; two texts with the guard passes. One sentence in `texts/README.md` points at the tripwire; the mutation rows go in the #12366 comment.
- 2.6 #12366 stays open for item 3 only; comment on it with the tripwire and the shape.

### Phase 3 Credential-free aggregate check (#12429), GDPR gate, migration, sensitive path

- 3.1 Migration `186_legal_acceptance_hash_counts.sql` and `.down.sql` (plain `DROP FUNCTION IF EXISTS`, hot-rollback safe). `public.legal_acceptance_hash_counts(p_key text) RETURNS jsonb`, `STABLE`, `SECURITY DEFINER`, `SET search_path = public, pg_temp`; `auth.uid() IS NOT NULL` raises 42501; key fails `^[a-z0-9][a-z0-9-]{0,62}$` raises 22023; `FROM ONLY public.legal_acceptance WHERE key = p_key GROUP BY text_hash`; selects no `founder_id`, `choice`, `created_at` or `requested_edit`; returns `{total, by_hash:[{text_hash,count}]}` ordered by `text_hash`, `{total:0, by_hash:[]}` when empty; `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role`; `GRANT EXECUTE ... TO service_role`; a `COMMENT ON FUNCTION`. Add `supabase/verify/186_legal_acceptance_hash_counts.sql`. Re-check 186 is free at ship.
- 3.2 `server/legal-acceptance/service.ts`: `hashCounts(client, {key})` with a strict parser mirroring `verifyAcceptance` (closed keys, 64-hex hash, integer counts >= 1, sum equals `total`; violation is a `bad_payload` error mapped to 502).
- 3.3 Route `app/api/internal/legal-acceptance/[key]/counts/route.ts` (HTTP-only exports, `export const dynamic = "force-dynamic"`): `readNamedBearerSecret` then `bearerMatches` first; 503 token unset or malformed (no founder-id config needed); 400 malformed key; 404 key not in the registry (`getLegalText`); RPC failure 503 via `storeFailed("counts")`; payload `{key, registry_hash, total, by_hash, ok_to_flag}` where `ok_to_flag` is true iff every `by_hash.text_hash` equals `registry_hash` (vacuously true at `total` 0); `Cache-Control: no-store`. Add `"counts"` to `STORE_FAILED_STAGES` in `server/approval/ops.ts`.
- 3.4 Helper `scripts/legal-acceptance-counts.sh <key>` (operator tooling with a production URL stays out of the plugin tree that ships to customers; it sources `plugins/soleur/scripts/lib/bearer-fetch.sh` for `bc_read_token` and `bc_get`; verify the source path resolves from `scripts/`), refuses under `set -x`, prints `ok_to_flag=<bool> total=<n> measured=production-table-only` and no row data. Any failure (401, 404, 502, 503, unreadable token) exits non-zero and prints no `ok_to_flag=` line. The token is the same `LEGAL_ACCEPTANCE_VERIFY_TOKEN` the verify read uses (source documented in the runbook; no new credential, but the bearer now also grants aggregate reads, stated in the ADR-319 amendment). `ok_to_flag` is advisory: it does not authorize a flip (`hr-menu-option-ack-not-prod-write-auth`).
- 3.5 Docs: replace the owner-SQL pre-flag step in `knowledge-base/engineering/operations/runbooks/legal-acceptance-note-read.md` and in the CLO ruling's "Pre-flag check, addition (L8)" paragraph (marker, append-only) with the helper call; ADR-319 amendment; C4 text per the section above; Art. 30 / LIA wording for the aggregate read goes to the CLO (the RPC reads no personal data per row and returns counts without an identifier; the GDPR gate output below is advisory).
- 3.6 Tests first: `migration-186-legal-acceptance-hash-counts.test.ts` (static, modelled on the 185 test); a DB-backed row in `test/server/legal-acceptance.tenant-isolation.test.ts` (service_role succeeds; authenticated gets 42501; two hashes across two founders counted correctly); `counts-route.test.ts` (401, 400, 404, token-only 503, RPC error 503, malformed payload 502, `ok_to_flag` matrix, closed response key set, `Cache-Control: no-store`); extend `test/sentry-legal-acceptance-alert-op-contract.test.ts`; the census, `cross-layer-limits.test.ts` and `routes.test.ts` run unchanged. Repo-global lints before first push: `lint-migration-api-grants.sh`, `migration-rpc-grants.test.ts`, `table-grants.ts` parity (no new table, so no entry), `rls-fuzz` coverage (service-only function is outside the gate).
- 3.7 Apply path: `web-platform-release.yml` runs `resolve-target, migrate, verify-migrations, deploy`, so 186 lands before the code. If the RPC is missing the route returns 503 with one Sentry event, never a 500.
- 3.8 Post-deploy (Phase 7): read the served sha at `https://app.soleur.ai/health`, then run the helper for `founder-acceptance-record` and record `ok_to_flag` and `total` as measured. The count measures only the production table for that key; it does not measure database backups, the Sentry `accepted` count or dev/preview.

### Phase 4 Inbox entry (CPO ruling, CTO R4 mechanism)

- 4.0 Wireframe (`wg-ui-feature-requires-pen-wireframe`; run after the 4.5 fallback evaluation and before any component code): the mechanical UI-surface override makes this BLOCKING tier (it edits `components/inbox/*.tsx`). The CPO ruled it reuses committed frames: "06 Inbox - approval rows (action_required) + nav badge" in `knowledge-base/product/design/approvals/approval-request.pen` (carries the row and the FYI state) and "Waiting for you list" in `founder-approval-cards.pen` (the destination). This plan run may write only under plans/specs, which is a stated hard limit of the planning phase, not a skip: `soleur:product:design:ux-design-lead` is invoked as the first work task to add one variance frame to `approval-request.pen` (legal title, no expiry chip when `validUntil` is absent, FYI state after answering, no checkbox) and commit the `.pen` and its export before any component code. It is not skippable. AC16 fails unless a non-empty variance frame exists in `approval-request.pen`; phases 4.1 onward depend on AC16, not on "specialist ran". The frame also draws the keyboard and a11y rows (spacer in place of the checkbox, focus order, mobile layout).
- 4.1 Tests first (CTO R4 (f)): `test/legal-acceptance/inbox-rows.test.ts` (each of the following is a MUTANT that must go RED: gate dropped; pending rendered as `info`; answered rendered as `action_required`; read failure throws instead of omitting; undeclared key included; archived view includes rows; `requested_edit`, hash or timestamp in the payload. Pinned behaviours: legal rows are absent from the archived view; on a read failure the other items return 200 and the legal rows are omitted (no degraded hint: Sentry is the signal and the card page stays reachable by URL; accepted limitation); `Date.parse(version)` is safe because a test pins that every registry `version` is an ISO date), `inbox-severity.test.ts`, `inbox-surface.test.tsx` / `inbox-surface-cache.test.tsx`, `inbox-nav-badge.test.tsx`, `inbox-bulk-archive-handler.test.ts` (`kind:"legal"` gives 400), `inbox-tools.test.ts` (agent output has no legal rows), `inbox-no-service-client.test.ts` (extend the grep), an `/api/inbox` route test (legal failure still 200 and calls `reportLegalOp`), a `cross-layer-limits.test.ts` row pinning the client key regex to `KEY_RE`.
- 4.2 `server/legal-acceptance/inbox-rows.ts`: called only for the active view and only after `isLegalSurfaceEnabled(user.id)`; a read selecting only `key, text_hash, choice` (never `requested_edit`), its own narrow parse, `deriveLegalCardState` with `cardHash == currentHash`; omits undeclared kinds; only `pending` is `action_required`, every other state including `expired` is `info`; sort time `Date.parse(version)`; `pinned` false; wrapped in its own try/catch that omits the legal rows and calls `reportLegalOp("pageReadFailed", err, {userId, extra:{read:"legal_acceptance_inbox"}})`.
- 4.3 Union widening with the three-pattern sweep (`const _exhaustive: never`, `\.kind === "`, `\?\.kind === "`): `lib/inbox-severity.ts` (`MergedInboxItem` gains `{kind:"legal", id:key, severity, pinned:false, outstanding, legal:{key,label,version,state}}`; `sortTime`, `toMerged*`, `mergeAndRank(inboxRows, emailRows, legalRows = [])`), `lib/inbox-archive-eligibility.ts` (guard `isArchiveCandidate`), `hooks/use-row-selection.ts` (prune effect and `toggleSection`), `components/inbox/inbox-surface.tsx` (`Row`, `SelectableRow`, `SelectAllStrip`, archived tab), new `components/inbox/legal-inbox-row.tsx` (no checkbox, a width spacer; navigates to `/dashboard/approvals/legal/<key>`, never calls `/api/inbox/[id]/state`), `components/dashboard/inbox-nav-badge.tsx` (`hasUnreadFyi` becomes a `switch` with `: never`; `legal` returns false), `lib/legal-acceptance-wire.ts` (client-safe key regex), `app/api/inbox/route.ts`. `server/inbox-tools.ts` keeps the two-argument call; `server/inbox-bulk-archive-handler.ts` unchanged. Row copy comes only from existing deck strings (`pendingTitle`, `pending.badge`, `openUntil`, the kind's accepted, declined, changes-requested and expired titles): no new wording, so no new CLO pin.
- 4.4 SWR refresh is an acceptance criterion (AC9): after a recorded decision the row turns FYI and the nav dot clears without a reload; if the cache does not refresh, call `mutate(swrKeys.inbox(...))` on a recorded decision, with a test row. The badge reads the same shared SWR key as the Inbox Active tab (`inbox-nav-badge.tsx`). Row-state transitions each get a test row: pending (NEEDS YOU); accepted / declined / changes_requested (FYI); replaced (the key's current hash changed: the row returns to NEEDS YOU for the new version and links to it); expired (FYI, no prompt; the card explains); flag off or founder change while a stale row is cached (click lands on the 404, the row disappears on the next fetch; accepted). Answered rows stay as permanent FYI rows, the way frame 06 shows resolved approvals; a decay rule (hide after N days) is not ruled: the CPO is asked at the Phase 5 review, and until then it is an accepted limitation recorded in 5.3. Keyboard: a focused legal row ignores archive and select-all shortcuts (no-op, never the 400 path), with a test.
- 4.5 Fallback trigger (CTO), evaluated at the end of 4.1 (tests written, `rg` sweep done) and BEFORE the 4.0 variance frame is commissioned so no frame is sunk: if the sweep finds a consumer outside the list above, or more than one existing inbox test needs rewriting rather than extending, fall back to a plain link in the inbox page header under the same gate (about 3 files) and the sign-off names the fallback.
- 4.6 The new route is `GET /api/inbox` derived data only; no migration, no new table.

### Phase 5 CPO sign-off (strictly after Phase 4)

- 5.0 The CPO agent reviews the committed variance frame export (the 2026-11-08 deck ruling was not a pixel-level review and predates the frame) and rules on the answered-row decay question; if it declines to attest the frame, "wireframe variances" is dropped from the string below.
- 5.1 `LEGAL_COPY.signOff.cpo` becomes exactly `Ruled by CPO agent, 2026-11-08: card deck wording, states and wireframe variances for the founder-acceptance-record text; entry point ruled separately` (the sign-off must name the shipped surface; AC6 asserts the string that names the shipped entry point, so if the fallback was taken the string names the header link).
- 5.2 `PROVISIONAL` stays `true`. Reword the header comment ("the CPO has not signed off") and the test title/comment ("CPO sign-off outstanding") to "CPO signed 2026-11-08; human lawyer review owed". `legal-copy.test.ts` pins `signOff` to `{ cpo: "<string>", clo: "<unchanged>" }` and `PROVISIONAL` to `true`, and adds an assertion that the cpo string passes `FORBIDDEN_CLAIMS` (the deck walker now collects it).
- 5.3 Recorded accepted limitations (CPO), not blockers: "your team" means Jikigai only for the operator and needs a CLO-ruled rewrite before a non-Jikigai solo founder; a Request-changes note is saved but nothing reads or replies to it (roadmap gap before non-operator founders); answers are final until the team ships a new version.

### Phase 6 `parked` hold as a required-check member step (#12396)

- 6.1 Tests first: `scripts/ci-parked-hold.test.sh` with a stubbed `gh`.
- 6.2 `scripts/ci-parked-hold.sh`: reads labels LIVE with `gh api repos/$REPO/pulls/$PR --jq '[.labels[].name]'` using `GH_TOKEN=github.token` (never `github.event.pull_request.labels`: `rename-guard` and `allowlist-diff` read the payload and a re-run reuses a stale payload); on `merge_group` takes the PR number from `github.event.merge_group.head_ref` with `^refs/heads/gh-readonly-queue/main/pr-([0-9]+)-[0-9a-f]{40}$` (the `mg_arm` regex in `scripts/ci-oracle-review.sh`); checks only the named PR; label names compared case-insensitively; fails closed on a non-200 after ONE bounded retry (2 attempts, 2 s apart, so one transient API 5xx does not block the queue), unparseable JSON, a missing PR or a non-matching ref; emits `::error::PR #N carries parked. Remove the label (maintainers) or keep the PR a draft`; re-reads the group-membership semantics in `mg_arm` of `scripts/ci-oracle-review.sh` (parity-pinned to `scripts/merge-queue-cla-verify.sh`) at work time and either reuses its enumeration or documents that each entry is judged by its own `merge_group` build.
- 6.3 `.github/workflows/secret-scan.yml`: member step ids `parked-hold` and `parked-hold-selftest` in the `secret-guards` job, each with the step-level condition `!cancelled() && (github.event_name == 'pull_request' || github.event_name == 'merge_group')` exactly as `waiver-discipline` has it (an unconditional `!cancelled()` would run on `push` and `schedule`, where there is no PR, and fail closed on main's scans; no JOB-level event `if:`), each listed in its own `member` line of the `aggregate` step with scope `pull_request,merge_group` (`scripts/lint-umbrella-aggregate.sh` check (a) requires every `- id:` in exactly one `member()` call; the lint is always run). The job already holds `pull-requests: write`, which covers the live label read. `.github/CODEOWNERS` gains `@deruelle` rows for `scripts/ci-parked-hold.sh`, `scripts/ci-parked-hold.test.sh` and `scripts/lib/umbrella-member.sh` (they are the evaluator; only the workflow file is covered today). `secret-scan.yml` already lists `labeled` and `unlabeled`; a new run on the same head SHA supersedes (latest check-run per name wins); a label added after enqueue is not seen (residual; mitigation is dequeue per `merge-queue-dequeue.md`).
- 6.4 `scripts/required-checks.txt` (comments only): record the member and its disposition: not content-scoped; the bot synthetic for `secret-guards` is unchanged; unreachable at synthesis because the composite action's `labels` input is caller-fixed (sweep the callers with `grep -rn "bot-pr-with-synthetic-checks" .github`); a later human label fires a real `labeled` run which supersedes the synthetic (`unverified` for a `GITHUB_TOKEN`-created PR; flip evidence: a human-labeled bot PR showing no new `secret-guards` run means reproduce the live read in the action's Phase-4 ceiling). `scripts/lint-umbrella-aggregate.sh` is run (and edited only if it pins the member list).
- 6.5 Before deleting `scripts/followthroughs/parked-merge-hold-enforcement-12342.sh`, `rg` for other references (sweep list, tests, the `parked-green-synthesis-11362` sibling, any census test). Reword the "best-effort" text in `plugins/soleur/skills/drain-prs/SKILL.md` and the header of `.claude/hooks/ship-operator-step-gate.sh` to point at the check; the hook stays as defence in depth. Delete `scripts/followthroughs/parked-merge-hold-enforcement-12342.sh`; closing #12396 ends its sweep (the directive is in the issue body). ADR-032 amendment line.
- 6.6 What "server-side enforced" means, stated honestly in the ADR, the skill text and the PR body: the check binds auto-merge, the merge queue and any non-bypass identity (including Actions tokens and the `schedule` skill's `gh pr merge --squash --auto`); it does not stop an admin-credentialed session running `gh pr merge --admin` (the ruleset's bypass actors OrganizationAdmin and Admin role in `pull_request` mode); `admin-merge-ready.sh` grades every required context and a parked PR has `secret-guards` red or pending, so it exits non-zero with no change. Draft status stays the first hold (`gh pr ready` flips it with no check; the check covers parked-and-ready).
- 6.7 Item 5 (per-statement hook cost): measure it in this PR (minutes of work): the hook with a PATH-stubbed `gh` on 1, 10 and 100 statements; record the three numbers in the #12396 closing comment. Act, as a separate issue, only if the 100-statement run adds more than 200 ms. The admin-bypass residual lives in the ADR-032 amendment, so no issue is filed for it. Expected new issues: 0 (net issue flow -2 with #12396 and #12429 closed); if the number exceeds 200 ms, 1 (labels `meta/machinery`, milestone per `roadmap.md`).

### Phase 7 Records and release

- 7.1 Archive the plan and spec inside the PR before merging (`wg-kb-artifacts-archived-in-pr`, `bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`).
- 7.2 PR body: `Closes #12396`, `Closes #12429`, `Ref #12365`, `Ref #12366`, `Ref #12197`, `Ref #12011`; list the CPO/CLO/CTO rulings (`Ruled by ... 2026-11-08`), the deviation from the brief (PROVISIONAL stays true), the admin-bypass residual, and that a human lawyer review is a separate owed item. CLA-signed author check before merge (`wg-cla-signed-author-before-merge`). Draft PR #12438 is un-drafted only when CI is green.
- 7.3 Merge through the merge queue only after the PR-attached CI is green. After each deploy, verify the served build sha at `https://app.soleur.ai/health` equals the merge commit (`curl -s https://app.soleur.ai/health | jq`). Release pipeline: `migrate` applies 186 before the deploy; a failed migrate leaves the old code serving.
- 7.4 Post-merge measurements, each recorded with what was and was not measured: (a) `/health` sha; (b) the counts helper output for `founder-acceptance-record`; (c) the verify endpoint read for hash `10d283e0...` still `accepted`, `row_ok: true`, projected to `status` and `row_ok` only; (d) the Inbox row visible for the founder and absent for a non-founder (a test-user session in Playwright, or the route test if no second account exists; state which); (e) the `parked-hold` check red on a throwaway labeled draft PR and green after unlabel (the live merge_group path is not exercised until a real queue entry; state it). `approval-queue` is not read or flipped by this PR.
- 7.5 Comments on #12197 (one per outcome) with measured/not-measured lines; comment on #12366 (items 1 and 2 done, item 3 tripwire); narrow #12365; file a new issue only if the 6.7 measurement exceeds 200 ms.
- 7.6 Roadmap hygiene at ship (`wg-every-feature-listed-in-a-roadmap-phase`): the Inbox entry has no roadmap row (nearest is CP2 #4672, the generic approval queue); add the milestone and a roadmap row via the ship step. The PR body labels the first-ever-terms wording (Phase 2.4) as hygiene that no current user sees, so the CPO sign-off does not appear to cover it.

## Files to Edit

Legal and records: `docs/legal/privacy-policy.md`, `docs/legal/gdpr-policy.md`, `docs/legal/data-protection-disclosure.md`, `plugins/soleur/docs/pages/legal/privacy-policy.md`, `plugins/soleur/docs/pages/legal/gdpr-policy.md`, `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`, `apps/web-platform/lib/legal/legal-doc-shas.ts`, `knowledge-base/legal/audits/2026-11-07-clo-ruling-founder-acceptance-record-12197.md`, `knowledge-base/legal/compliance-posture.md` (only if it states the old proposal), `knowledge-base/engineering/operations/runbooks/legal-acceptance-note-read.md`, `knowledge-base/engineering/architecture/decisions/ADR-319-legal-acceptance-record.md`, `knowledge-base/engineering/architecture/decisions/ADR-032-*.md` (verify the exact filename), `knowledge-base/engineering/architecture/diagrams/model.c4`, `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated).

Deck and registry: `apps/web-platform/lib/legal-acceptance-copy.ts`, `apps/web-platform/test/legal-acceptance/legal-copy.test.ts`, `apps/web-platform/test/legal-acceptance/registry-pins.test.ts`, `apps/web-platform/server/legal-acceptance/texts/README.md`.

Counts: `apps/web-platform/server/legal-acceptance/service.ts`, `apps/web-platform/server/approval/ops.ts`, `apps/web-platform/test/sentry-legal-acceptance-alert-op-contract.test.ts`, `apps/web-platform/test/server/legal-acceptance.tenant-isolation.test.ts`, `apps/web-platform/lib/routes.ts` (comment block on the `[key]` segment only), `.github/CODEOWNERS`, `knowledge-base/project/specs/feat-one-shot-founder-acceptance-followups-12365/` records.

Inbox: `apps/web-platform/app/api/inbox/route.ts`, `apps/web-platform/lib/inbox-severity.ts`, `apps/web-platform/lib/inbox-archive-eligibility.ts`, `apps/web-platform/hooks/use-row-selection.ts`, `apps/web-platform/components/inbox/inbox-surface.tsx`, `apps/web-platform/components/dashboard/inbox-nav-badge.tsx`, `apps/web-platform/lib/legal-acceptance-wire.ts`, `knowledge-base/product/design/approvals/approval-request.pen` (+ export), the existing inbox tests named in 4.1.

Parked hold: `.github/workflows/secret-scan.yml`, `scripts/required-checks.txt`, `scripts/lint-umbrella-aggregate.sh` (only if it pins members), `plugins/soleur/skills/drain-prs/SKILL.md`, `.claude/hooks/ship-operator-step-gate.sh` (header comment only), `scripts/followthroughs/parked-merge-hold-enforcement-12342.sh` (delete).

Glob verification: every path above that is not a new file was confirmed to exist on `origin/main` at plan time except those marked "verify"; the work phase runs `git ls-files | grep -E '<path>'` for each marked path before editing (`hr-when-a-plan-specifies-relative-paths-e-g`).

## Files to Create

`apps/web-platform/supabase/migrations/186_legal_acceptance_hash_counts.sql`, `...186_legal_acceptance_hash_counts.down.sql`, `apps/web-platform/supabase/verify/186_legal_acceptance_hash_counts.sql`, `apps/web-platform/app/api/internal/legal-acceptance/[key]/counts/route.ts`, `apps/web-platform/server/legal-acceptance/inbox-rows.ts`, `apps/web-platform/components/inbox/legal-inbox-row.tsx`, `scripts/legal-acceptance-counts.sh`, `scripts/legal-acceptance-counts.test.sh` (stubbed `curl`: refuses under `set -x`, prints only `ok_to_flag`, `total`, `measured`; non-zero exit and no `ok_to_flag=` on any failure), `scripts/ci-parked-hold.sh`, `scripts/ci-parked-hold.test.sh`, tests: `apps/web-platform/test/legal-acceptance/migration-186-legal-acceptance-hash-counts.test.ts`, `.../counts-route.test.ts`, `.../inbox-rows.test.ts`.

## GDPR / Compliance Gate

Invoked `soleur:gdpr-gate` at plan time against this plan (regulated-data surfaces: migration, API route, `.sql`, legal documents, `legal_acceptance`). The result is appended below as `### Gate result` and is advisory only; any Critical finding is acknowledged by the operator before work (see Decision Classes). The CLO (Domain Review) covers the lawful-basis and Art. 13 content of the published wording; Art. 30 PA-40 gets a one-line addendum for the aggregate read (counts, no identifiers) in Phase 3.5.

### Gate result

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Advisory, plan-phase, run inline against the plan text (schema and prose only; no row values read). No `Critical` finding: no new column, so no Art. 9 column-name match. Nothing was written to `compliance-posture.md` and no issue was filed in this phase.

| check_id | Severity | Location | Result |
|---|---|---|---|
| `GDPR-Art-9` | none | migration 186, Inbox read | No new column. The Request-changes note (`requested_edit`) is the one free-text field that could carry special-category data; the RPC and the Inbox read are specified to never select it (Guard 2 mutation row 4; Inbox test "requested_edit in payload"). Existing exposure of the note is unchanged and stays owner-only (runbook). |
| `GDPR-Art-6` | Suggestion | migration 186 | No new column or table, so no `-- LAWFUL_BASIS` annotation is owed. Add one `COMMENT ON FUNCTION` line naming the same LIA / PA-40 basis (Art. 6(1)(f)) so the function is traceable. |
| `GDPR-Art-5e` | Important (pre-existing, tracked) | published trio, `legal_acceptance` | The 5-year period is now published, but the deletion step is not built (#12080). The trio states this openly ("not yet built; will be built before any record reaches that age"); the dated deadline is 2031-11-07. No new PII table in this PR. |
| `GDPR-Art-17` / `GDPR-Art-17-caller` | none | migration 186 | No new FK to `users`, no `anonymise_*` RPC. |
| `GDPR-Chapter-V` | none | whole plan | No new vendor, SDK or env var; the route reuses the existing Supabase service client (eu-west-1). |
| Art. 13 / 13(2)(a) transparency (layer LC) | Suggestion, addressed | published trio | The trio's old "proposal, up to 10 years" overstated the retention; Phase 1 replaces it with the numeric period and the hold clause (CLO ruling). Human-lawyer review of the final form remains owed (#12365 kept open). |
| Art. 30 | Suggestion | PA-40 | One-line addendum for the aggregate read (counts by hash, no identifier, `service_role` only). |
| Art. 32 | Suggestion, addressed | counts route | Bearer-gated, bearer checked before any lookup, `Cache-Control: no-store`, closed response key set, strict parser. With one data subject today a count of 1 is linkable by the bearer holder, who already learns "accepted" from the verify endpoint; no small-cell floor (CTO T5). The CLO is asked for the Art. 30 wording only. |
| Art. 25 / data minimisation | Suggestion, addressed | Inbox rows | The row carries `{key, label, version, state}` only: no hash, no note, no time. |

Scan-completion line the gate would print: path scan covered the migration, the API routes and the published documents named in `## Files to Edit` and `## Files to Create`; the counts are re-derived at work time from `git diff --name-only` against the canonical regex.

## Domain Review

**Domains relevant:** Legal, Product, Engineering

### Legal

**Status:** reviewed
**Assessment:** Ruled by CLO agent, 2026-11-08 (v1 internal position standing in for counsel on the operator's instruction of 2026-11-07; a human lawyer review is a separate owed item). L7 of 2026-11-08 is superseded: its premises (flag off, nothing recorded) no longer hold, and the published "proposal, up to 10 years" overstates the committed 5 years, which is worse than silence under Art. 13(2)(a). The public 5-year commitment stays honest because every retention statement carries "not yet built; we will build it before any record reaches that age"; #12080 must ship before 2031-11-07. Rulings: retention block R in all three documents; italic preface and status-check sentence replaced with a dated status paragraph (no day stated); DRAFT markers stay; no TC_VERSION bump or re-acceptance; new `Amended: November 8, 2026` entry and a Superseded marker under the November 6 entry; do not touch `Last Updated`; card wording "about 10 minutes" (change the card, not the shared template); terms kind drops "updated" and fixes `noBody` and `declinedBody`.

### Product

**Status:** reviewed (see Product/UX Gate)
**Assessment:** Ruled by CPO agent, 2026-11-08: deck signed off (wording matches the CLO table and the pin table; every error path ends in a stated next step; no blocking defects); `PROVISIONAL` stays true; the founder-visible entry is an Inbox row, not a sidebar item or banner, gated on `isLegalSurfaceEnabled`, composed only from existing deck strings; the sign-off commit must follow the Inbox commit.

### Engineering

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-11-08: R1 `parked-hold` member step in `secret-guards` (no Terraform); R2 RPC plus sibling counts route, migration 186; R3 keep the pin guard deferred behind a tripwire; R4 Inbox row derived in the `GET /api/inbox` handler (about 9 source files and 7 to 8 test files). Full text in `decision-challenges.md`.

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override: the plan edits `components/inbox/*.tsx` and adds `legal-inbox-row.tsx`)
**Decision:** reviewed (partial)
**Agents invoked:** soleur:product:cpo, soleur:product:spec-flow-analyzer (run with the plan review, see Plan Review below)
**Skipped specialists:** none. `soleur:product:design:ux-design-lead` is scheduled as the first task of Phase 4 (task 4.0) because the planning phase may write only under `plans/` and `specs/`; it is not skipped and not deferrable.
**Pencil available:** to be confirmed at task 4.0 (`bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --auto`); hard-block only if auth or Node < 22.19.0 is genuinely unsatisfiable.

#### Findings

The CPO found no new blocking-tier frame needed beyond a variance on committed frames 06 (Inbox approval rows) and "Waiting for you list"; a banner or a nav item would need a new frame, which is another reason to choose the row. Variances to draw: legal title, no expiry chip without `validUntil`, FYI after answering, no checkbox (the synthetic id has no inbox row to update; follows the unresolved-approval guard in frame 06 note 3).

## Infrastructure (IaC)

No new infrastructure: no server, service, secret, vendor, DNS or firewall change; no Terraform change (the ruleset is deliberately untouched, CTO R1). The migration is applied by the existing release pipeline.

## Observability

```yaml
liveness_signal:
  what: the counts route answers 401 to an unauthenticated GET (reachable and bearer-gated) and the parked-hold member reports in every secret-guards run
  cadence: per request for the route; per pull_request, merge_group and label event for the member
  alert_target: Sentry (legal-acceptance alert rules in apps/web-platform/infra/sentry) for the route; the failing required check for the member
  configured_in: apps/web-platform/app/api/internal/legal-acceptance/[key]/counts/route.ts (reportLegalOp storeFailed stage counts); .github/workflows/secret-scan.yml (member step parked-hold)
error_reporting:
  destination: Sentry via reportLegalOp("storeFailed", err, {tags:{stage:"counts"}}); Inbox read failures via reportLegalOp("pageReadFailed", ..., {extra:{read:"legal_acceptance_inbox"}})
  fail_loud: the counts route answers 503 (RPC failed or missing) or 502 (undocumented payload shape), never a partial 200; the parked-hold step exits non-zero with ::error::PR #N carries parked or ::error:: on an unreadable label state
failure_modes:
  - mode: migration 186 not applied when the new route is served
    detection: the route returns 503 and one storeFailed stage=counts event; verify-migrations fails the release before deploy
    alert_route: Sentry legal-acceptance alert rule; the release workflow run
  - mode: the counts payload gains an unexpected field or a count that does not sum to total
    detection: the strict parser throws bad_payload, the route answers 502 and emits storeFailed
    alert_route: Sentry
  - mode: the Inbox legal read fails
    detection: the other inbox items still return 200 and one pageReadFailed event with read=legal_acceptance_inbox is emitted
    alert_route: Sentry
  - mode: a label added after a PR is enqueued is not seen by the queue
    detection: none by design (stated residual); the operator dequeues per merge-queue-dequeue.md
    alert_route: documented in ADR-032 amendment and the PR body
  - mode: GitHub API unreadable inside parked-hold
    detection: the step fails closed and annotates the run
    alert_route: the failing required check
logs:
  where: Sentry events and the pino line written by reportLegalOp (copied to Better Stack); Actions run logs for the member step
  retention: Sentry and Better Stack 90 days as stated in the Privacy Policy; Actions logs per repository settings
discoverability_test:
  command: bash scripts/ci-parked-hold.test.sh
  expected_output: parked-hold selftest ok
```

(The counts route probe `curl -s -o /dev/null -w '%{http_code}' https://app.soleur.ai/api/internal/legal-acceptance/founder-acceptance-record/counts` printing `401` is the post-deploy check in Phase 7.4; it is not the declared preflight command because it returns 404 before this PR is deployed. The self-test script must print exactly the final line `parked-hold selftest ok` and finish inside the 15-second preflight cap with a stubbed `gh`.)

## Encryption Posture

No persistent store and no new cross-component connection is introduced: migration 186 adds a function over the existing `public.legal_acceptance` table (whose posture is unchanged and is not re-stated here), and the new route calls Supabase over the same `createServiceClient()` connection the verify route already uses. The posture schema therefore applies to no row:

```yaml
at_rest:          none introduced; the only store read is the existing legal_acceptance table, unchanged by this plan (function-only migration)
in_transit:       no new connection; route to Supabase uses the existing service client (cert_verification on); caller to route is the existing app.soleur.ai TLS edge
exception:        none
```

## Guard Contract

### Guard 1 — parked-hold member step

**Property.** A PR that carries `parked` at evaluation time cannot satisfy `secret-guards` on `pull_request` or `merge_group`, and an unreadable label state also fails.

**Assembly.** The events {opened, synchronize, reopened, labeled, unlabeled, merge_group} on `secret-scan.yml`; the label read path (live API, never the payload); the member's presence in the `aggregate` step with scope `pull_request,merge_group`; the job permissions; the queue-ref parse; the absence of any job-level `if:`; the step-level event condition; the queue-entry semantics (each entry is judged by its own `merge_group` build). The workflow-shape assertions (rows 5 to 8) live in `scripts/ci-parked-hold.test.sh`. Chokepoint: `scripts/ci-parked-hold.sh` is the only evaluator; the workflow step and the self-test both call it.

**Mutation matrix.**

| # | Edit | Must drive RED |
|---|------|----------------|
| 1 | Make the label match case-sensitive so `Parked` passes | self-test row "mixed-case label" |
| 2 | Treat an API failure as not parked | self-test row "gh exits non-zero" |
| 3 | Let an unparseable `head_ref` pass | self-test row "ref does not match" |
| 4 | Read payload labels instead of the live read (fixture: payload empty, API has `parked`) | self-test row "payload vs live" |
| 5 | Remove `unlabeled` from `on.pull_request.types` | workflow-shape assertion |
| 6 | Drop the member from the `aggregate` step | workflow-shape assertion |
| 7 | Add a `pull_request`-only job-level `if:` | workflow-shape assertion |
| 8 | Drop the step-level `pull_request`/`merge_group` event condition (the step then runs on `push`/`schedule`) | workflow-shape assertion plus a self-test `push`-event fixture row (no PR: the step condition skips it and it must never fail main's scans) |
| 9 | Empty the self-test's call list so it reports "0 checked" and exits 0 | the self-test's own anti-vacuity floor (a minimum row count) |
| 10 | Remove the bounded retry (one transient 5xx then blocks) or make it unbounded | self-test row "one 5xx then 200 passes; persistent 5xx fails" |

**Harness rows.** One edit to the suite that must drive it RED: delete the stubbed `gh` failure arm (the suite then no longer exercises fail-closed; the floor on row count reds). One must-PASS input that is not the canonical: a PR with labels `[Parked-not, enhancement]` (a near-miss name) passes.

**Anchor.** The check compares live API state to the string `parked`; what outside the commit must move for a weakening to pass: a ruleset change (Terraform, operator-authorized apply) removing `secret-guards`, or a bypass actor merging with `--admin`. A PR cannot weaken the check and merge itself, only because review does: a PR that removes the member is judged by its own weakened workflow file, which is the stated limit of any in-repo check. The control is CODEOWNERS review of `.github/workflows/secret-scan.yml`, `scripts/ci-parked-hold.sh`, `scripts/ci-parked-hold.test.sh` and `scripts/lib/umbrella-member.sh` (rows added in 6.3), not the check itself.

### Guard 2 — counts RPC privacy boundary

**Property.** `legal_acceptance_hash_counts` reveals only a key's total and per-hash counts: no founder id, choice, timestamp or note, and no caller except `service_role` can execute it.

**Assembly.** The function body's select list; the REVOKE/GRANT pair; the `auth.uid()` guard; the route's closed response key set; the strict parser; every consumer of the RPC (one: the route).

**Mutation matrix.**

| # | Edit | Must drive RED |
|---|------|----------------|
| 1 | Drop the REVOKE from `anon`/`authenticated` | migration-186 static test |
| 2 | GRANT EXECUTE to `authenticated` | migration-186 static test and the tenant-isolation row (42501 expected) |
| 3 | Drop the `auth.uid()` guard | migration-186 static test |
| 4 | Add `founder_id` or `choice` to the select/aggregate output | migration-186 static test; parser closed-key test |
| 5 | Unpin `search_path` | migration-186 static test; rpc-grants lint |
| 6 | Add a second hash for a second founder, only the first is counted | tenant-isolation row (two founders, two hashes) |
| 7 | Route returns an extra key | `counts-route.test.ts` closed key set |

**Harness rows.** Edit to the suite: remove the 42501 expectation (the suite must red on the missing negative case through its must-fail floor). Must-PASS non-canonical input: a key with zero rows returns `{total:0, by_hash:[]}`.

**Anchor.** The counts are compared to the registry hash computed in the route from the committed file; what must move to weaken: the grant (a migration, reviewed) or the registry file (a new hash, caught by `registry-pins.test.ts`).

## Acceptance Criteria

### Functional

- [ ] AC1 The three published documents and their mirrors contain the block R retention wording, the dated status paragraph, the corrected monitoring sentence and the November 8, 2026 `Amended:` entry; no heading changed; `**Last Updated:**` untouched; DRAFT markers retained. `grep -c "life of the legal text plus 5" docs/legal/*.md plugins/soleur/docs/pages/legal/*.md` prints 0 for every file.
- [ ] AC2 `legal-doc-consistency.test.ts`, `legal-doc-shas-guard.test.ts`, `check-tc-document-sha.sh`, `lint-legal-mirror-drift-baseline.sh` and the full `test-all.sh` pass; `LEGAL_DOC_SHAS` holds the three recomputed shas (`sha256sum` equals the literal for each).
- [ ] AC3 No TC_VERSION change (`git diff origin/main -- apps/web-platform/lib/legal/tc-version.ts` is empty).
- [ ] AC4 `legal-copy.test.ts` pins `codeBody` and `wrong_code` ("about 10 minutes"), the terms-kind wording without "updated", and a drift test fails if `magic-link.html` stops saying `expires in 10 minutes` or `configure-auth.sh` stops setting `"mailer_otp_exp": 600`.
- [ ] AC5 `registry-pins.test.ts` contains `needsBaseGuard` with the three rows; `texts/README.md` points at it.
- [ ] AC6 `signOff.cpo` equals the ruled string that names the shipped entry point (5.1) and `PROVISIONAL` is `true`; the Phase 5 commit follows the Phase 4 commit in `git log`.
- [ ] AC7 Migration 186 and its down file apply cleanly to a scratch database; `verify/186_*.sql` reports `bad = 0`; the static migration test and the tenant-isolation row pass; `lint-migration-api-grants.sh` and `migration-rpc-grants.test.ts` pass.
- [ ] AC8 `GET /api/internal/legal-acceptance/founder-acceptance-record/counts` returns the closed payload `{key, registry_hash, total, by_hash, ok_to_flag}` with the bearer, 401 without, 404 for an unknown key, 503/502 on RPC failure; `verify-route-census.test.ts` passes unchanged.
- [ ] AC9 (states and refresh) The Inbox shows a NEEDS YOU row for a pending legal text and an FYI row once answered, only for the configured founder with the flag on; a non-founder gets no row and no `legal_acceptance` read; a legal read failure returns the other items with 200; the row has no checkbox, no archive, no state call; the nav badge counts a pending row and not an answered one; after a recorded decision the row turns FYI and the dot clears without a reload; a replaced version returns the row to NEEDS YOU; legal rows are absent from the archived view; a focused legal row ignores archive and select-all shortcuts.
- [ ] AC10 `parked-hold` is a member of `secret-guards`; a PR labeled `parked` fails it on `pull_request` and (fixture) `merge_group`; unlabeling re-evaluates; the self-test prints `parked-hold selftest ok`; the follow-through probe is deleted; no file under `infra/github/` changed.
- [ ] AC11 The founder's verify read is unchanged: hash `10d283e0...a287` still reads `accepted`, `row_ok: true` after deploy (projected to `status` and `row_ok`).
- [ ] AC16 A non-empty variance frame for the legal-text Inbox row exists in `knowledge-base/product/design/approvals/approval-request.pen` (with its export) and is committed before any Phase 4 component code; the CPO reviewed it before the sign-off commit (5.0).
- [ ] AC12 `founder-acceptance-record.md` sha256 is still `10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287` (`sha256sum apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md`).

### Non-Functional / Process (pre-merge)

- [ ] AC13 Nothing in the diff touches `approval-queue`, Flagsmith or Doppler (`git diff origin/main --stat | grep -i -E "flag|doppler"` shows only files named in this plan).
- [ ] AC14 Review panel at the `single-user incident` threshold ran (security-sentinel, data-integrity-guardian, user-impact-reviewer, gdpr-gate, architecture-strategist, test-design-reviewer, observability-coverage-reviewer) and every P1/P2 finding is resolved or tracked.
- [ ] AC15 Plan and spec archived inside the PR; PR body carries `Closes #12396`, `Closes #12429`, `Ref #12365`, `Ref #12366`, `Ref #12197`; #12365 narrowed; #12366 commented.

### Post-merge verification (cannot gate the pre-merge definition of done)

- [ ] AC17 `/health` serves the merge sha after each deploy; the counts helper output and the verify read are recorded on #12197 with what was measured and what was not; the Inbox row and the `parked-hold` live check are recorded per 7.4 (with the unexercised `merge_group` path stated); the Eleventy site serves the new trio text.

## Test Scenarios

- Published trio: a reader compares each retention sentence in PP 4.17, GDPR 3.19, DPD 2.3(aj) to the committed text's "How long it is kept" and finds the same period, hold clause and "not yet built" statement.
- Code lifetime: the card says "about 10 minutes"; the email says "expires in 10 minutes"; editing either breaks a test.
- First-ever terms text: the terms card never says "updated" and never says "the current terms stay in place".
- Counts: zero rows for a key returns `total 0, ok_to_flag true`; one row under the registry hash returns `ok_to_flag true`; one row under another hash returns `ok_to_flag false`; a user token calling the RPC gets 42501; the response never contains `founder_id`.
- Inbox: founder with flag on and a pending text sees a NEEDS YOU row and a badge count of 1; after Yes the row is FYI and the dot clears; a non-founder sees nothing; the archived tab shows no legal row; bulk-archive with `kind:"legal"` is rejected with 400.
- Parked: a PR labeled `parked` is red; `Parked` (case) is red; unlabel turns it green; the GitHub API returning 500 is red; a malformed queue ref is red.

## Dependencies & Risks

- R1 Public commitment with no control behind it (CLO residual): mitigated by "not yet built; will be built before any record reaches that age" in every statement; #12080 must ship before 2031-11-07. Tracked on #12080.
- R2 Published trio claims "since the approval queue was switched on for the Jikigai operator in November 2026" without a date; if the operator has the date, replace the phrase (CLO).
- R3 The live code lifetime may differ from `configure-auth.sh` (config drift); Phase 0.4 measures it or states it is unmeasured.
- R4 Migration number 186 can be claimed by a sibling PR; re-check at work and at ship.
- R5 The Inbox consumer sweep may exceed the CTO list; the plain-link fallback is the pre-agreed exit.
- R6 `parked-hold` hosted in `secret-guards` is a semantic misfit (recorded in `required-checks.txt`); a label added after enqueue is not seen; an admin `--admin` merge is not bound. All three are stated, not hidden.
- R7 Bot-PR synthetic behavior for a later human label is unverified; flip evidence is defined in 6.4.
- R8 Production mutation: only the standard release pipeline applies 186 (additive function). No ruleset apply, no flag flip, no Doppler write; nothing needs an operator go beyond merge.
- R9 Human-lawyer review of the final-form trio remains owed before any non-Jikigai founder; #12365 stays open as that tracker.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled here; do not blank it.
- Each OLD string in the CLO ruling must match exactly once before and each NEW once after; a mirror body that differs by a space fails `legal-doc-consistency`. Apply to the canonical, copy to the mirror, then diff the bodies.
- `gh --jq` does not forward `--arg`; use two-stage `gh ... --json` then `jq --arg` in any helper.
- The counts RPC must not select `requested_edit`; the Inbox read must not either (`LEGAL_ROW_COLUMNS` includes it; do not reuse it).
- The route is under `PUBLIC_PATHS` prefix `/api/internal/legal-acceptance`; the bearer check must be the first thing after config (census test).
- Do not run the counts helper or the verify read from an agent session with `DATABASE_URL`; the bearer is the only credential used.
- The plan file and spec dir are archived in this PR; keep the `decision-challenges.md` table of record.
- No `spec.md` exists for this one-shot branch, so `lane:` is `cross-domain` (fail-closed default, TR2).

## References

- Issues: #12365, #12366, #12396, #12429, #12197, #12011, #12080, #12344; PR #12342 (merged), draft PR #12438.
- `knowledge-base/legal/audits/2026-11-07-clo-ruling-founder-acceptance-record-12197.md`; `apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md`; ADR-319, ADR-032.
- Rulings of record: `knowledge-base/project/specs/feat-one-shot-founder-acceptance-followups-12365/decision-challenges.md`.
