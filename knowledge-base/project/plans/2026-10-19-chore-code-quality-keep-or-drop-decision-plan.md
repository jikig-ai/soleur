---
title: "chore(quality): decide whether per-PR GitHub Code Quality stays on (slice 4 of #10331)"
type: chore
date: 2026-10-19
slug: code-quality-keep-or-drop-decision
branch: feat-one-shot-10331-code-quality-decision
issue: 10331
closes: 10331
priority: p2
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: single-domain
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# chore(quality): decide whether per-PR GitHub Code Quality stays on (slice 4 of #10331)

## Enhancement Summary

**Deepened on:** 2026-10-19
**Sections enhanced:** 3 (premise corrections, gates, verification)
**Research agents used:** soleur:engineering:cto (two rulings), soleur:operations:coo, code-simplicity-reviewer, spec-flow-analyzer; deepen gates 4.6 to 4.12 run mechanically (full agent fan-out skipped: documentation-and-settings change with no code, no Rails, no UI, no infra)

### Key Improvements
1. The billing API showed the real Code Quality charge is a metered AI-credit line ($254.96 over 2026-09-22 to 2026-10-19), not $10 per committer; the CTO re-ruled from keep to off.
2. Plan-review and spec-flow hardened the disable sequence: positive proof of the off state, code-scanning state captured before and compared after, #10381 settled only after the disable is verified, org-level lock handled by detaching the repository.
3. The ledger Amount is a measured 28-day sum instead of a nine-day partial month.

### New Considerations Discovered
- The #10381 premise "PR2 merged" was imprecise: the handler PR (#10375) merged 2026-10-15 and a restructure (#10503) on 2026-10-18; the stale-scan test uses both.
- The setting goes live before merge; the PR must merge straight after, and the re-evaluation has no machine trigger (carried by #9730, the ledger cell and the ADR).

## Overview

Final slice of the code-quality arc. Slices 1 to 3 are merged: the two findings that looked like bugs were
triaged (false positives), the shipped plugin-script handlers were fixed, and shrink-only ratchets (ADR-290)
now gate the high-volume rules with both baselines empty. This slice decides the last open question: does the
per-PR GitHub Code Quality scan (ADR-276 S5 cost lever, owner CTO) stay on? The CTO agent rules it, not the
operator. The slice then records the decision three ways: an expense-ledger row, a dated ADR-276 addendum, and a
re-evaluation date (2026-11-14) that both can be found from.

**The CTO ruled twice, and the second ruling is the one that stands.** The first ruling (keep, with a re-evaluation)
rested on the brief's "$10 per active committer per month" framing. Reading the org billing API at plan time
(read-only `GET orgs/jikig-ai/settings/billing/usage`) showed the real charge is a metered product `code_quality`,
SKU "Code Quality AI Credits": $0.41 in August, $94.31 for 2026-09-22 to 30 (the first billing day was 2026-09-22), and
$160.65 for 2026-10-01 to 19 (about $254 a month at that pace). Gross equals net, so these are charges, and no
per-committer SKU appears at all. Re-ruled with that evidence, the CTO tripped its own flip criterion (cost above
$50 a month whatever the signal) and ruled **turn it OFF, after one bounded step that settles #10381**. The rulings
and rationale are rows in `knowledge-base/project/specs/feat-one-shot-10331-code-quality-decision/decision-challenges.md`.

**How it is enabled (verified, answers the brief's question):** it is a repository settings toggle in the GitHub UI
(the repository's Security and quality settings, Code quality page), surfacing as the dynamic workflow `CodeQL - Code Quality`
(`dynamic/github-code-quality/codeql`, workflow id 343194280, state `active`). There is **no in-repo file** that
enables it: no workflow file, and `infra/github` Terraform manages only three rulesets and the marketplace repo,
none of the `jikig-ai/soleur` security settings. Probes of `repos/jikig-ai/soleur/{code-quality,code_quality}`
returned 404, so no REST endpoint exists for the toggle. The disable is therefore **a repo settings change, applied
by the agent through Playwright MCP in this PR's work phase (not an operator step)**, and the PR must say so.

## Research Insights

### Premise Validation (Phase 0.6)

- `#10331` is OPEN (the PR closes it). `#9730` (S5 tracker) OPEN, `#10381` OPEN (verification that a post-PR2 Code
  Quality scan cleared `py/empty-except`; it needs one scan read), `#10583` OPEN (not touched here).
- ADR-276 exists with `status: adopting`; S5 row reads "not started"; Decision 6 states Code Quality and code
  scanning are separate switches and ADR-270 covers only code scanning. ADR corpus grep for the mechanism
  ("disable Code Quality") finds no rejected alternative; ADR-290 only records that Code Quality motivated the ratchets.
- The audit file exists and carries the 4.4% figure (141.1 of 3,234.6 job-min, 2026-10-14 10:00-12:00Z).
  A fresh census today timed out twice against the Actions API (flaky `gh api --paginate`), so 4.4% stays the only
  current-window share; the work phase may retry once, it is not load-bearing.
- **Brief premise corrected:** "$10 per active committer per month" is not what is billed. `orgs/jikig-ai/settings/billing/usage`
  shows only the AI-credit meter. The committer-count product endpoint accepts `code_security` and `secret_protection`
  (both zero committers) and rejects `code_quality`, so the committer charge, if any, is not visible through the API.
- Billing is not new on 2026-10-14: the meter started 2026-09-22. The audit's "re-enabled on 2026-10-14" is the
  operator's re-toggle for the assessment; the spend predates it.
- Repo is PUBLIC, so standard runner minutes are not dollar-billed (Actions Linux lines carry `netAmount` 0): the 4.4% is
  queue pressure on the 60-job account pool, not money. The money is the AI-credit meter.

### Property List and Cut List (Phase 0.6b)

Properties the ask requires: (P1) a ruled keep/drop decision with a recorded rationale; (P2) the spend is on the
ledger; (P3) a re-evaluation date findable from both ledger and ADR; (P4) the ADR records the decision append-only;
(P5) if off, the feature is actually off and the PR states operator-setting vs in-repo.

Cut List (mechanisms considered, none added):

- New tracker issue for the re-evaluation -> P3 -> already covered by `#9730` (S5 tracker, stays open) plus a pointer comment; CTO ruled no new issue.
- `estimate verify_by` marker on the ledger row -> P3 -> the marker means "unverified estimate"; the row is a measured, retired figure, so a marker would mislabel it (CTO ruled none). The date lives in the Notes cell, the ADR addendum and the `#9730` comment.
- New follow-through probe script for "no more charges" -> P5 -> a one-shot read of the billing API in the postmerge step covers it; a probe would need an org-billing token wired into the sweeper for a single check.
- Editing `.github/scripts/cancel-superseded-pr-runs.sh` (it still matches `dynamic/github-code-quality/`) -> none -> harmless when the workflow stops appearing; CTO ruled do not touch.
- Terraform for the toggle -> P5 -> no provider/REST surface found and `jikig-ai/soleur` settings are not Terraform-managed (see Infrastructure section).
- Editing `knowledge-base/finance/cost-model.md` -> P2 -> a retired row carries no forward burn; the COO's "add a row" advice assumed an active charge. The model is separately overdue for review; not this PR.

### Institutional notes

- `scripts/expenses-verify-by-check.sh` already exits 1 on 22 expired estimate markers (Hetzner, Resend, jikigai.com, cron-ux-audit). Pre-existing, out of scope; this PR must not add an anomaly (exit 2).
- Retired ledger rows keep their last amount and a date in the Renewal Date column (see Hermes and inngest-volume rows).
- ADR-276 is append-only by convention: dated `## Amendment` sections, earlier text never edited, "superseded" is stated by subject in the new section.

## Open Code-Review Overlap

None (no open `code-review` issue names `knowledge-base/operations/expenses.md` or ADR-276).

## Implementation Phases

Order matters: the snapshot and the #10381 read come before the disable (the scan history is the evidence), and the
ledger/ADR text is written after the disable so it states what happened, not what was intended.

### Phase 1 - Snapshot and #10381 read (Playwright MCP, read-only)

1. Open the repository's Code Quality alert list for `main` (the Standard findings view; the REST API does not return these). If the browser session is unauthenticated, see Risks.
2. Record: total open findings, per-rule counts and severities (the same 22-rule table as the audit), the `py/empty-except` count for the five files #10381 names (`playwright-mcp-redact-proxy.py`, `scan-ancestor-signal-helpers.py`, `founder-check.py`, `resolve-debt.py`, `security_reminder_hook.py`), and the scan's commit SHA against the current `main` head. Do not trigger a new scan. **Empty or stale view:** if the list is empty, stale (the scan SHA predates the last handler change to those files: #10375 merged 2026-10-15 and the restructure #10503 merged 2026-10-18; verify with `git log --oneline -- <the five files>`) or shows no `py/empty-except` data, the verdict for #10381 is "unverifiable, feature disabled", never "verified".
3. Capture the code-scanning state before touching anything: `gh api repos/jikig-ai/soleur/code-scanning/default-setup` (languages, query suite, schedule, state) and the last three `PR #N` code-scanning runs, so the Phase 2 comparison is against recorded values and not just the word `configured`.
4. Append the snapshot to `knowledge-base/engineering/audits/2026-10-14-github-code-quality-baseline.md` as a new dated section ("Final snapshot before disable, 2026-10-19"). Earlier sections stay untouched.

### Phase 2 - Disable (Playwright MCP, repository settings)

1. Open the repository's Code quality settings page and turn the feature off. GitHub may ask for sudo-mode re-authentication on a settings change; that and a login or 2FA prompt are the named handoff points (see Risks). If the page is locked by an organization-level code security configuration, detach `jikig-ai/soleur` from that configuration rather than editing it for every attached repository; if only an org-wide edit is possible, list the affected repositories first and note that such a configuration can bundle code scanning (so re-check it after).
2. If the page shows an AI-credits or autofix-only toggle, note it in the audit section; do not use it in place of the full disable (CTO ruling).
3. Positive proof: reload the settings page and assert it reads off; capture the page text into the PR description evidence (store under the spec dir only if small).
4. Verify from the API: `gh api repos/jikig-ai/soleur/actions/workflows/343194280 --jq '{state,updated_at}'` (record the exact post-disable value: it may read `disabled_*` or return 404, which is also a pass; `active` is a fail). Then push a trivial commit to this PR's branch and read `gh api 'repos/jikig-ai/soleur/actions/runs?event=dynamic&per_page=30'` for that head after the code-scanning `PR #N` run for it has appeared: no `Code Quality: PR #N` run exists for the same head while the code-scanning one does. `gh api repos/jikig-ai/soleur/code-scanning/default-setup` still equals the Phase 1 capture (languages, query suite, schedule, state).
5. Only after step 4 passes, settle #10381 with `gh issue close 10381 --comment <snapshot and verdict>` (verified, or "unverifiable, feature disabled"). Do not write a close keyword next to an issue number anywhere in prose or commit messages; the `gh issue close` command is the only closer.
6. The setting is live from this point, before merge: the PR body says so, and the PR is merged straight after (an abandoned PR would leave it off with no ledger row or ADR; the rollback is the same toggle).

### Phase 3 - Ledger row (deliverable 1)

Add to the Recurring table of `knowledge-base/operations/expenses.md`, next to the GitHub Team row, and set frontmatter `last_updated: 2026-10-19`:

`| GitHub Code Quality (jikig-ai/soleur) | GitHub | dev-tools | 254.96 | retired | 2026-10-19 | <Notes> |`

Amount: the measured sum of the `code_quality` meter over its whole billing life, 2026-09-22 to 2026-10-19 (28 days, so close to one month; $94.31 in September plus $160.65 for 2026-10-01 to 19). Re-read the meter and recompute at write time (the 2026-10-19 item may still grow), and keep the figure measured, not extrapolated. This replaces the CTO's "September full month" figure, which assumed a complete month: the meter only started on 2026-09-22, so $94.31 alone would understate the draw (mechanical correction, recorded in decision-challenges.md).

Notes (no pipes, no `estimate` marker, one row, kept short): metered `code_quality` product, SKU "Code Quality AI Credits", source `GET orgs/jikig-ai/settings/billing/usage` read 2026-10-19; the brief's "$10 per active committer per month" did not appear as a line item; RETIRED 2026-10-19 by settings change per the ADR-276 amendment (CTO ruling); billing is expected to stop with the toggle, to be confirmed against the meter; **Re-evaluation by 2026-11-14** (re-enable only if a consumer for the findings exists and the AI-credit spend can be capped); nothing fires on that date by itself, the dated anchors are this cell, the ADR-276 amendment and a comment on #9730. Tracker: #9730. Detail (daily range, 4.4% job-minute share, committer endpoint behavior) lives in the ADR amendment.

Run `bash scripts/expenses-verify-by-check.sh` before and after: the anomaly count stays 0 and the EXPIRED count does not rise above the pre-change 22.

### Phase 4 - ADR-276 addendum (deliverable 3)

Append at the end of `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` (no edit to any earlier line, including the S5 row and the Stage status list):

`## Amendment 2026-10-19 (S5 Code Quality decision, #9730; Ref #10331)` with: the decision (Code Quality turned off; code scanning untouched and still advisory per ADR-270); `Ruled by CTO agent, 2026-10-19 (revised): ...` carrying the rationale and the first ruling it supersedes, by subject; the measured evidence (billing figures with their source and the daily range 2.21 to 18.61, the 4.4% job-minute share, the committer-count endpoint accepting `code_security` and `secret_protection` but rejecting `code_quality`, ratchet coverage, no consumer of the findings); what remains uncovered (CodeQL type-inference rules: trivial-conditional, useless-assignment, superfluous-arguments, overwritten-property, regex rules) and that this is the accepted residual; the mechanism (repository settings change, no in-repo file, rollback one toggle); the re-evaluation by 2026-11-14 with its conditions, pointing at the ledger row; and "S5 stays open for the CodeQL query-suite and runner-supply levers (#9730)". Do not append a line to the Stage status list (S5 is not done) and do not change `status:`.

### Phase 5 - Pointer comment and wrap-up

1. `gh issue comment 9730` with a three-line pointer: decision, ledger row, ADR amendment, re-evaluation 2026-11-14. (`#9730` stays open.)
2. PR body carries, as a standalone line, the issue-closing line for #10331 exactly as the brief spells it, plus: "Disabled by repo setting applied by the agent via browser automation; no in-repo change; rollback is one toggle". No close keyword next to any other issue number.
3. `plugins/soleur/skills/work/SKILL.md` is not touched (byte ceiling).

## Files to Edit

- `knowledge-base/operations/expenses.md` (new Recurring row; `last_updated`)
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` (append amendment only)
- `knowledge-base/engineering/audits/2026-10-14-github-code-quality-baseline.md` (append a dated snapshot and disable section)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10331-code-quality-decision/decision-challenges.md` (exists)
- `knowledge-base/project/specs/feat-one-shot-10331-code-quality-decision/tasks.md`

External, not files: the repository's Code Quality setting (off), `#10381` (settled with the snapshot), `#9730` (pointer comment).

## Domain Review

**Domains relevant:** Engineering (CTO ruling above), Operations

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled twice (decision-challenges.md). Keep rested on the wrong cost premise; off, with the #10381 bounded step first, stands.

### Operations

**Status:** reviewed
**Assessment:** COO (read-only): book a measured figure not an average, category `dev-tools`, renewal date `-` or an anchor date, no mandatory cost-model refresh (the +$10 shift is under the 10% rule; with a retired row there is none). COO assumed the $10-per-committer charge and a keep; the billing evidence supersedes the amount but not the row shape. Risk noted: the verify-by gate is already red on 22 stale Hetzner/Resend markers, which this PR neither fixes nor worsens.

Finance (CFO) is covered by the COO assessment above for a single ledger row; no budget-planning change.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-276 with a dated append-only addendum (Phase 4). The decision is a lever outcome inside an existing ADR (S5), not a new substrate or boundary, so no new ADR.

### C4 views

No C4 impact, checked by reading all three files (`model.c4`, `views.c4`, `spec.c4`): (a) external human actors: none added or changed; (b) external systems: GitHub is already modeled as the `github` system ("Source control, CI/CD, issue tracking"), Code Quality is a settings feature of that same system, and neither CodeQL nor Code Quality appears as an element or edge today, so turning a feature off changes no edge; (c) containers or data stores: none; (d) actor-to-surface access relationships: none. `bash plugins/soleur/test/c4-count-parity.test.sh` was run at plan time: 13 passed, 0 failed. Re-run in the work phase after the edits.

### Sequencing

None: the ADR addendum describes the state this PR creates.

## Infrastructure (IaC)

### Terraform changes

None. Routing check per `hr-all-infrastructure-provisioning-servers`: this is the disable of a SaaS feature setting, not provisioning. `infra/github` manages three rulesets and the marketplace repo; `jikig-ai/soleur` repository security settings (secret scanning, push protection, code scanning default setup, Code Quality) are not Terraform-managed, and no REST endpoint for the Code Quality toggle exists (404 on probes). So the automatable path is browser automation (`hr-exhaust-all-automated-options-before`), not an operator checklist. The unrelated ruleset `Code Quality Copilot review for default branch` (id 19474295, enforcement `disabled`, not Terraform-managed) is a separate Copilot-review ruleset and is left as is.

### Apply path

Browser automation of one settings toggle, in the work phase, before merge (live before the PR merges; see Phase 2 step 6). Blast radius: Code Quality PR and main-push scans stop. No required check depends on it (`git grep` of `scripts/required-checks.txt` and the ruleset-ci-required file for Code Quality finds nothing); the code-scanning `CodeQL` contexts and the post-merge alert gate (ADR-270) are separate and keep running.

### Host fan-out

N/A (no SSH provisioners, no hosts).

### Distinctness / drift safeguards

The state is not Terraform-held, so no drift gate applies; the ledger row and the ADR addendum are the record. Evidence of the live state is the workflow API read in Phase 2.

### Vendor-tier reality check

The meter, not a tier, is the cost driver; re-enable requires a way to cap it (unverified whether GitHub offers a budget on `code_quality`; checked at the re-evaluation, not now).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The change is a repository setting plus ledger and decision text; the only visible effect is that PRs no longer get a Code Quality check run.
- **If this leaks, the user's workflow is exposed via:** nothing; no credential, token or user data is read or written. The billing API read uses the operator's existing `gh` session and prints no secret.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none` because the change removes a non-required advisory scan and records a decision; code scanning (security) stays on, so no security control is weakened. Not `aggregate pattern`: no user-facing behavior changes.

## Observability

Skipped by the Phase 2.9 rule: the diff edits only knowledge-base documents (no code-class file under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`) and introduces no infrastructure surface. The live state is nevertheless checkable without SSH: `gh api repos/jikig-ai/soleur/actions/runs?event=dynamic` and `gh api orgs/jikig-ai/settings/billing/usage` (Phase 2 step 4 and the postmerge step).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Decide whether per-PR GitHub Code Quality stays on" [brief] | CTO rulings (decision-challenges.md), Phase 2 | mapped |
| 2 | "The CTO agent (soleur:engineering:cto) rules this, not the operator" [brief] | two CTO spawns recorded as rows | mapped |
| 3 | "add a $10 per active committer per month entry for GitHub Code Quality to knowledge-base/operations/expenses.md" [brief] | Phase 3 (row booked at the measured figure; the $10 framing is corrected in its Notes) | mapped |
| 4 | "set a re-evaluation by 2026-11-14 (record it where the expense and the ADR can both be found)" [brief] | Phase 3 Notes cell, Phase 4 addendum, Phase 5 comment on #9730 | mapped |
| 5 | "record the decision in ADR-276 as a dated addendum (append-only; do not edit prior text)" [brief] | Phase 4 | mapped |
| 6 | "If the CTO rules to turn Code Quality off, make the change that actually disables it" [brief] | Phase 2 | mapped |
| 7 | "state in the PR whether the disable is a repo setting an operator must apply or an in-repo change" [brief] | Phase 5 PR body; Overview | mapped |
| 8 | "as a standalone line in the PR body" (the issue-closing line for #10331, written exactly as the brief gives it) [brief] | Phase 5 | mapped |
| 9 | "do not add bytes to plugins/soleur/skills/work/SKILL.md" [brief] | Phase 5 item 3; not in Files to Edit | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 snapshot and #10381 close | — | inferred - justification: the CTO's revised sequencing ruling requires the existing scan history and #10381's one needed read before the feature is switched off, since a disabled feature leaves #10381 unverifiable |
| Audit file append | — | inferred - justification: the CTO ruled the rule-by-rule counts be saved as the last baseline; the alert list is UI-only and disappears from view once disabled |
| Pointer comment on #9730 | "record it where the expense and the ADR can both be found" | asked |
| Phase 2, ledger, ADR | asks 3 to 6 | asked |

### Split Assessment

- Subsystems touched: 1 (knowledge-base)
- Planned files: 3 edited plus 2 created | Estimated changed lines: about 120
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [x] `knowledge-base/operations/expenses.md` has one new row for GitHub Code Quality, status `retired`, with Amount equal to the measured meter sum recomputed at write time (254.96 at plan time), the source, and the phrase `Re-evaluation by 2026-11-14`; `last_updated` is 2026-10-19; the row has no `estimate` marker and no pipe inside the Notes cell.
- [x] `bash scripts/expenses-verify-by-check.sh` reports `anomalies=0` and `expired=22` (unchanged from before this PR).
- [x] ADR-276 diff is append-only: `git diff origin/main -- <ADR-276 file>` shows only added lines (zero `-` lines other than the diff header), and the new heading is `## Amendment 2026-10-19 (S5 Code Quality decision, #9730; Ref #10331)`; `status:` and the Stage status list are unchanged.
- [x] The ADR addendum and the ledger Notes both contain `2026-11-14` (grep both files).
- [x] Code Quality is actually off: the settings page reads off after a reload, workflow 343194280 is no longer `active` (or 404), a head pushed after the disable has a `PR #N` code-scanning run and no `Code Quality: PR #N` run, and `default-setup` equals the Phase 1 capture.
- [x] The audit file has the appended snapshot section (rule table, total, scan SHA and the five-file `py/empty-except` count, or the explicit empty-view note) and #10381 is settled with that snapshot only after the disable was verified.
- [x] PR body contains the standalone issue-closing line for #10331 exactly as the brief spells it, states the disable is a repository setting applied by the agent (no in-repo change, no operator step), and contains no other close keyword followed by an issue number.
- [x] `git diff origin/main --stat` lists only the three edited files, the two spec files and this plan; `plugins/soleur/skills/work/SKILL.md` is not in it.
- [x] `bash plugins/soleur/test/c4-count-parity.test.sh` still passes.

## Test Scenarios

Verification is the Acceptance Criteria above plus two repeatable commands: the append-only check
`git diff origin/main -- 'knowledge-base/engineering/architecture/decisions/ADR-276*' | grep -c '^-[^-]'` (expect 0) and
`bash scripts/expenses-verify-by-check.sh` (expect `anomalies=0`, `expired=22`). The billing re-read
(`gh api 'orgs/jikig-ai/settings/billing/usage?year=2026&month=10'` shows no `code_quality` item dated after the disable) is
repeated at the postmerge step and at the 2026-11-14 re-evaluation, because the meter posts a day late.

## Postmerge Verification (soleur:postmerge)

1. Workflow 343194280 state and `default-setup` are as recorded; a fresh `PR #N` run exists and no `Code Quality: PR #N` run does.
2. `code_quality` billing items dated after the disable: none (re-read the next day if the meter has not posted).
3. On `main`: the ledger row is present, `scripts/expenses-verify-by-check.sh` still reports `anomalies=0` and `expired=22`, and the ADR-276 diff against the pre-merge `main` is append-only.
4. #10331 and #10381 are closed, #9730 is open and carries the pointer comment, and Code Quality has not been re-enabled by anyone.

## Risks

- **Browser session may be unauthenticated or hit a 2FA/CAPTCHA gate.** Per `hr-never-label-any-step-as-manual-without`, exhaust automation first (the Playwright profile may hold a GitHub session). If a login/2FA gate is the only blocker, automate up to it, hand that single interaction to the operator, and do not mark Phase 2 done or write the ledger row `retired` until the disabled state is verified from the API. The PR must not claim a disable it has not verified.
- **Org-level override.** A code security configuration at the organization level may lock the repo toggle; detach this repository from it rather than editing it for the whole organization (see Phase 2 step 1).
- **Re-evaluation rot.** The PR finishes #10331, and #9730 could be closed before 2026-11-14 once the other S5 levers land. If so, the closing comment on #9730 must carry the 2026-11-14 re-evaluation forward to its successor; the ledger cell and the ADR amendment keep the date meanwhile.
- **Disabling could touch code scanning.** The Phase 2 step 4 check on `default-setup` and on `PR #N` runs is the guard; if code scanning stops, re-enable immediately (security control).
- **History loss on disable** (whether findings survive a re-enable is unverified, so "rollback is one toggle" means the setting, not the history): the Phase 1 snapshot is the mitigation.
- **Residual accepted:** the CodeQL type-inference rules have no deterministic substitute; ADR amendment names them. A consumer for them is the re-enable condition, not a task here.

## References

- Audit: `knowledge-base/engineering/audits/2026-10-14-github-code-quality-baseline.md`
- ADR-276 (S5, Decision 6), ADR-270 (code scanning advisory), ADR-290 (ratchets)
- Trackers: #10331 (this PR is the one that finishes it), #9730 (S5), #10381 (verification), #10583 (not touched)
- Ledger gate: `scripts/expenses-verify-by-check.sh`; billing source: `GET /orgs/jikig-ai/settings/billing/usage`
