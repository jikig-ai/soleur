---
title: "fix(compound-promote): proposer refusals - line cap and skill-conflict guard"
type: fix
date: 2026-10-26
slug: fix-compound-promote-proposer-refusal-line-cap-and-skill-guard
branch: feat-one-shot-10552-proposer-refusal-line-cap-and-skill-guard
issue: 10552
ref: 10552
priority: p2
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

# fix(compound-promote): proposer refusals - line cap and skill-conflict guard

`Ref #10552` only. Never `Closes`: #10552 stays open until a scheduled run actually opens a draft PR. The PR body
must say the effect is **unmeasured until #10552 clears** and must not claim these fixes will open a PR.

## Enhancement Summary

**Deepened on:** 2026-10-26
**Sections enhanced:** Proposed Solution (Defect B), Guard Contract (Guard 2), Observability, Acceptance Criteria, Dependencies & Risks, Research Insights
**Passes run:** halts 4.6 (User-Brand Impact, scope-out present), 4.7 (Observability schema), 4.8 (no PAT shapes), 4.9/4.10/4.13 (not triggered: no UI, store or new autonomous surface), 4.11 (`lint-guard-contract.py` green, assembly is structural), 4.12 (one unfenced `## Scope Check`); architecture-strategist, security-sentinel and observability-coverage-reviewer reviews; live verification of cited PR/issue states and of the Octokit typings.

### Key Improvements

1. The skill-conflict scan is now **lazy** (first drafted skill cluster only) and records **only the kept clusters' exact target paths**: no wasted ~40 requests on clusters refused earlier, a bounded memoized output, and no attacker-controlled file names stored or logged.
2. Lookups use `Object.hasOwn` (the scan result crosses an Inngest JSON round-trip), the first PR wins, and the log carries an integer PR number only.
3. Observability block now cites layers (pino -> Vector -> Better Stack, pino -> Sentry), states the conflict arm is deliberately non-paging, and uses the literal `PASS` for the probe.

### New Considerations Discovered

- The handler-level constraints from the census: no new `async (): Promise<ClusterOutcome> => {` opener, no new `TARGET_ALLOW_RE.test(` call inside the handler; both are why the helpers are module-level.
- The SKILL.md payload room grows to 20 lines x 1000 characters; bounded by the 20-line cap and the human-gated draft PR (accepted, see Dependencies & Risks).

## Overview

The 2026-10-26 09:46Z manual `input:"patterns"` run (Better Stack outcome row, run_id
`01M5VSNSD7TMT85MHSYDXC94YG`: `clusters_proposed=2`, `clusters_opened=0`) refused both clusters in
`apps/web-platform/server/inngest/functions/cron-compound-promote.ts`:

- **Defect A, `edit-invalid` (cause `too-long`).** The validator caps a model-written line at 500 characters
  (`EDIT_LINE_MAX_CHARS`), but the corpus the model imitates already holds 26 rule lines over 500 (longest 597)
  and the corpus lint (`scripts/lint-agents-rule-budget.py`, `PER_RULE_CAP = 600` UTF-8 bytes) accepts up to
  600. A model that copies the house style overshoots and the whole cluster is refused with no retry.
- **Defect B, `skill-conflict-guard`.** The guard refuses every `plugins/soleur/skills/` target whenever its
  search finds any open PR, then posts the proposed diff as a comment on the first hit. The hit was Dependabot
  PR #10812 (a `pillow` bump under `gemini-imagegen`), unrelated to the cluster's file, and the comment landed
  on it at 2026-10-26T09:47:40Z.

Both are server-side defects in code that sits after the model call. This plan fixes both, with tests and the
runbook, ADR and compliance-record text that describe the changed behaviour.

## Research Reconciliation - Spec vs. Codebase

| Brief / code claim | Reality (verified) | Plan response |
|---|---|---|
| The guard searches `"plugins/soleur/skills" in:files` and so matches PRs that touch skill files | `in:files` is not a qualifier of `GET /search/issues`. Run live with and without it, the query returns the identical 13 results, ranked on title/body text. #10812 matched because its **title** contains `/plugins/soleur/skills/gemini-imagegen`. The guard has never tested file overlap | The fix is not "narrow the search". Replace it with a real file-list check (list open PRs, read each PR's changed files) |
| `AGENTS.rules.md` has 26 of 137 lines over 500 chars, max 597 | 137 is the file's total line count; the 26 are all `- ` rule lines (of 99). Max 597. Confirmed | Cap the AGENTS target at 600 |
| `PER_RULE_CAP` is 600 UTF-8 bytes while the validator counts chars | The lint measures `len(line.encode())` on the `- ` line (newline excluded, prefix included). A line that passes `PRINTABLE_ASCII_RE` is pure ASCII, so `l.length` (UTF-16 units) equals its byte length. Same basis | Keep the charset check and say why in a comment; pin it with a test row |
| The same cap fits `SKILL.md` targets | No lint caps SKILL.md lines. Measured over the 104 `plugins/soleur/skills/*/SKILL.md`: **1071 lines exceed 600**, max 9461 (`review` 262, `work` 216) | Separate SKILL cap of 1000 (CTO ruling A-3) |
| The guard "posts a diff comment on that unrelated PR" | True (09:47:40Z). The compliance record treats that comment as an ungated publication surface (DPIA memo, `compliance-posture.md` rows 170-171) and #10676's re-evaluation trigger lists "first posted skill-conflict comment" | Remove the comment (CTO ruling B-3); update the compliance record (CLO ruling) |
| Fail-closed on a search/API failure | Today a failed request throws out of the `apply-and-pr-*` step (no try/catch), so the run errors and no PR opens | Keep: API errors still propagate. Add a distinct refusal for "could not finish enumerating" |

## Research Insights

**Premise validation (Phase 0.6).** #10552 is OPEN. PR #10812 is OPEN, author `app/dependabot`, one file
(`plugins/soleur/skills/gemini-imagegen/requirements.txt`). Every cited symbol exists on this branch
(`EDIT_LINE_MAX_CHARS` line 962, `newLinesCause` 1131, prompt line 1356, guard 2204-2222,
`skillConflictDiffBody` 1403). The brief's mechanism ("narrow the search to the same file") would not work as
described, because the search qualifier does not exist; this is the one stale premise and it reshapes Defect B
from "tighten a query" to "replace the check". ADR corpus: ADR-092 (additive-only boundary) states the 500-char
cap as a compensating control and is corrected in place; ADR-300 lists the comment behaviour as an accepted
residual and is updated; neither rejected the file-list mechanism.

**Property list (Phase 0.6b).**

1. A cluster's inserted `AGENTS.rules.md` lines are refused for length only when the corpus lint would also reject them.
2. A SKILL.md edit is not refused for a line length the existing skill corpus routinely exceeds.
3. A skill-targeting cluster is refused for conflict only when an open PR changes that cluster's own target file.
4. The guard never reports "no conflict" when it could not finish looking.
5. No model-derived text is posted into an unrelated public PR.
6. The cap constant cannot drift from the lint constant without a red test.

**Cut list.** (a) A one-shot retry on `too-long`: buys property 1 only by spending a second model call; the cap
alignment already buys it. Cut. (b) An in-guard comment on the same-file PR: property 5 forbids it; the refusal
row plus a warn log carrying the PR number already make the conflict discoverable. Cut. (c) Skipping every bot
author: would drop the App's own earlier draft PRs, which are real conflicts. Only `dependabot[bot]` is skipped,
and only to save API calls. (d) Review cuts adopted: the live-corpus longest-line test (the lint already gates the
corpus), the `editLineMax` helper (inlined), the separate ADR-092 amendment section (in-place edit), the `model.c4`
edit (no falsified statement), and the "must stay ahead of the length check" claim (an ASCII-only line has chars
equal to bytes in any order; the check order only changes the reported cause).

**Institutional learnings applied.**

- `2026-10-20-a-threshold-that-lives-only-in-a-prompt-is-a-request-not-a-constraint.md`: a number the model is only asked to respect needs a server check and a pinned constant; a new refusal reason must reach the probe class sets and the test floor (`MIN_CASES`).
- `2026-10-25-a-decoded-value-scan-ran-before-the-shape-check-...md`: octokit call sites keep literal route templates; no pass-through adapter with `route as never`.
- `2026-06-11-cross-file-drift-guards-extract-every-operand-by-shape.md`: extract the Python operand by shape with an exactly-one count check and integer validation; never hard-code the literal. The Python file also contains `{PER_RULE_CAP}` in f-strings, so the extractor is anchored (`^PER_RULE_CAP\s*=\s*(\d+)\s*(#.*)?$`, multiline).
- `2026-03-24-gh-api-paginate-concatenated-arrays.md` and the 300-file `gh pr diff` cap: use the paginated `pulls/{n}/files` route, and test pagination (a single-page test does not).
- `2026-09-24-an-empty-api-search-is-not-evidence-of-absence-...md`: an empty or truncated answer is not a verdict, which is the basis for the "unverifiable" arm.
- `2026-04-18-agents-md-byte-budget-and-why-compression.md`: measure bytes, not chars, for the 600 cap.

**Technical rulings.** Nine forks were ruled by the CTO agent and recorded in
`knowledge-base/project/specs/feat-one-shot-10552-proposer-refusal-line-cap-and-skill-guard/decision-challenges.md`
(rows A-1..A-3, B-1..B-4). The CLO agent reviewed the publication-surface removal (rows L-1, L-2, C-1; see Domain Review).

**Plan-review round (2026-10-26).** Three reviewers (no P0). Mechanical findings applied: nullable `pr.user`,
fake-octokit records `(route, params)`, stale comment near `RENDER_HAZARD_RE`, property wording for the Dependabot
skip, anchored extractor, probe header prose, "raised to the new measured total", one-Sentry-event-per-run note.
The one technical fork (page bounds and total request budget) went to the CTO as ruling B-4 and replaced the
bounds of B-1. Not adopted: a shared Octokit mock helper across the two handler suites (the hoisted `vi.mock`
factories are per-file by construction) and trimming the Scope Check tables (required by the skill).

### Deepen-pass verification (2026-10-26)

- **Octokit typings, resolved in the installed `@octokit/openapi-types` 27.0.0** (`apps/web-platform/node_modules/@octokit/openapi-types/types.d.ts`): `pull-request-simple.user` is `components["schemas"]["nullable-simple-user"]` (line 18856), so `pr.user` can be null; the files `diff-entry` has `previous_filename?: string` (line 23129), so a rename is detectable. `cron-bug-fixer.ts` (`listOpenBotFixIssueNumbers`, line ~227) is the precedent for `octokit: Octokit` plus `as { data: ... }` on the two literal routes.
- **Cited states, resolved live:** #10552 OPEN, #10676 OPEN (`compliance: re-run the empirical DPIA limbs at the first loop-opened draft PR (#2720)`), PR #10812 OPEN (Dependabot, one file), PR #11157 OPEN (this branch's draft PR). No AGENTS rule ids are cited in this plan; no GitHub label is prescribed.
- **Precedent-diff (Phase 4.4):** the pagination-with-bound plus `Array.isArray` guard is novel to this function; the nearest precedent (`cron-bug-fixer.ts` ~364) is single-page and unbounded, so the bounded loop has no sibling to copy and is covered by the table-driven tests rather than by precedent.
- **Verify-the-negative sweep:** "no other caller of `skillConflictDiffBody`" (grep: only the cron file and its test), "`PII_REGEX` has other uses" (lines ~1759, ~1807 per review), "`skill-conflict-guard-comment-posted` appears nowhere else" (grep: only the cron file). All confirmed.
- **Security review (no P0):** the 600/1000 caps leave `CREDENTIAL_RE` / `AGENTS_ID_TOKEN_RE` worst cases at roughly 1e6 steps on 1000 characters (trivial); the installation token is minted without a `permissions` map, so removing the comment POST changes no scope (an unscoped token being wider than needed is a pre-existing observation, not part of this fix).

## Proposed Solution

### Defect A - one cap per target, the AGENTS cap pinned to the lint

In `cron-compound-promote.ts`:

- Replace `const EDIT_LINE_MAX_CHARS = 500` with three exports:
  `AGENTS_EDIT_LINE_MAX_CHARS = 600` (the corpus lint's `PER_RULE_CAP`; the comment states the chars-equal-bytes
  argument: `PRINTABLE_ASCII_RE` admits only ASCII, so a line's length in characters is its length in bytes),
  `SKILL_EDIT_LINE_MAX_CHARS = 1000` (comment: no lint governs SKILL.md lines, so this constant has no pin by
  design; revisit only if refusal rows show 1000 being hit) and
  `EDIT_LINE_TARGET_CHARS = 500` (the soft target the prompt states).
- In `newLinesCause` (already receives `targetPath`) the `too-long` arm picks the cap inline:
  `targetPath === "AGENTS.rules.md" ? AGENTS_EDIT_LINE_MAX_CHARS : SKILL_EDIT_LINE_MAX_CHARS`. The prompt builder
  uses the same expression, so the numbers it states are the numbers enforced.
- The prompt line becomes derived text: aim for at most `EDIT_LINE_TARGET_CHARS` characters, never more than the
  target's hard cap, and say a longer line refuses the whole edit. No retry.
- Rewrite the stale comment in `newLinesCause` ("or the skill-conflict comment that quotes the diff"): the
  render-hazard screen stays, because it also protects the draft PR body and the committed text, but the comment
  surface it names no longer exists.

### Defect B - a real same-file check, scanned once per run, no comment

CTO rulings B-1 (match rule), B-2 (fail-closed arms), B-3 (no comment) and B-4 (bounds, shared per-run scan).

- **Scan once per run.** New exported `scanOpenPrSkillPaths({ octokit, owner, repo, targets })` (a module-level
  helper) returns a JSON-serialisable `{ changed: Record<string, number>; incomplete: null | "prs" | "files" | "requests" }`.
  `targets` is the list of the kept skill clusters' `target_path` values; `changed` records ONLY paths that equal
  one of them exactly (as `filename` or `previous_filename`), mapped to the first open PR number that changes
  it (first PR wins: skip a key that already exists via `Object.hasOwn`). That bounds the memoized step output to
  at most one entry per skill cluster (a 1000-file fork PR cannot inflate Inngest run state) and keeps
  attacker-controlled file names out of any stored or logged value. It uses only two literal routes, `GET /repos/{owner}/{repo}/pulls` (state open, 100 per page,
  `SKILL_GUARD_PR_PAGES = 3`) and `GET /repos/{owner}/{repo}/pulls/{pull_number}/files` (100 per page,
  `SKILL_GUARD_FILE_PAGES_PER_PR = 10`), with a run-wide `SKILL_GUARD_FILE_REQUEST_BUDGET = 150` file-list
  requests. The first bound reached is recorded in `incomplete` (`prs`: the last PR page was full; `files`: a PR
  filled its pages; `requests`: the budget ran out) and scanning continues where it still can, so a later match is
  never lost. Skip only author login `dependabot[bot]` (call saving; the exact path match already excludes it) and
  read it as `pr.user?.login` because `user` is null for deleted accounts. Do not skip drafts (the App's own
  promote PRs are drafts) and do not skip large PRs (the list endpoint has no changed-file count). A non-array
  payload (fixed-string error, never the payload) or any request error throws: the step fails, Inngest retries,
  no PR opens (the existing fail-closed behaviour, CTO ruling B-2; a skill-scan failure ends the run exactly as
  the old in-step request failure did, so no new blast radius for `AGENTS.rules.md` clusters). Priority when
  several bounds are hit: the first reached wins, pinned by a test row so the `bound` tag is stable.
- **Where it runs (lazily, once).** A handler-scope `let skillScan` is assigned from
  `step.run("skill-conflict-scan", ...)` just before the apply `step.run`, only when `draft.kind === "drafted"`,
  the cluster's `target_path` starts with `plugins/soleur/skills/` and `skillScan` is still unset. It sits after
  the ledger/dedup/week-cap filtering and the early return, so suppressed, duplicate, sub-quorum and
  draft-refused clusters never trigger it, and an `AGENTS.rules.md`-only run makes no pulls request. The step
  result is memoized, drafts are memoized, so the call is replay-deterministic, both skill clusters share one
  budget, and the assignment happens outside any step callback (census Guard 3 is about mutations inside
  callbacks). The scan step must not copy the `async (): Promise<ClusterOutcome> => {` signature (census
  Guard 3 requires exactly one opener) and must not add a `TARGET_ALLOW_RE.test(` call inside the handler (the
  patterns-handler suite counts exactly two); the prefix gate and all path logic stay in module-level helpers.
- **Verdict per cluster.** A pure exported `skillConflictVerdict(scan, targetPath)` returns
  `{kind:"conflict", pr}` when `Object.hasOwn(changed, targetPath)` (`changed` crosses a JSON round-trip on replay,
  so never use `in`); else `{kind:"unverifiable", bound}` when
  `incomplete` is set; else `{kind:"clear"}`. The apply step (inside the existing
  `target_path.startsWith("plugins/soleur/skills/")` block) maps `conflict` to the existing
  `{kind:"refused", reason:"skill-conflict-guard"}` after a `logger.warn` (`skill-conflict-guard-refused`, fields
  `fn`, `hash`, `pr` (only if `Number.isInteger`), `target`; warn because the Better Stack filter keeps level >= 40;
  never a PR title or file name), and `unverifiable` to
  `{kind:"refused", reason:"skill-conflict-guard-unverifiable"}` after a warn (fields `fn`, `hash`, `bound`) and one
  message-path `reportSilentFallback` (tag `bound`, `extra.cluster_hash`). The warn and the Sentry call run inside
  the memoized apply callback, so they fire on first execution only (matches every existing refusal site);
  `refusals.push` stays outside the callback in `record()`. The old log string `skill-conflict-guard-comment-posted`
  appears nowhere else in the repo (grepped), so renaming it breaks no runbook query. `ClusterOutcome.reason` is already a plain string,
  so `record()` needs no new field.
- **Intended behaviour, stated.** The App's own earlier open draft promote PR that changes the same SKILL.md
  conflicts: the new cluster is refused as `skill-conflict-guard` (CTO confirmed). That is the guard's purpose
  (no two competing drafts on one file); the cluster re-proposes after the earlier draft merges or closes.
- Delete the comment POST, `skillConflictDiffBody` and its two tests (no other caller; grepped). `PII_REGEX`
  stays: it has other uses.

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` - constants, `newLinesCause` cap and stale comment, prompt line, `scanOpenPrSkillPaths`, `skillConflictVerdict`, the lazy `skill-conflict-scan` step + hoisted `skillScan`, the apply-step guard block, delete `skillConflictDiffBody`.
- `apps/web-platform/test/server/inngest/cron-compound-promote-draft-edit.test.ts` - drop the `skillConflictDiffBody` import and describe block; replace the `501`/`500` rows with per-target boundary rows; add the prompt-text assertion and the pin test (with an exported-in-file `extractPerRuleCap` helper used by the pin and by its fixture rows).
- `apps/web-platform/test/server/inngest/cron-compound-promote-draft-handler.test.ts` - route-aware Octokit mock (the current mock answers every route with a search-shaped object, which the new array check rejects); add handler-level guard cases.
- `apps/web-platform/test/server/inngest/cron-compound-promote-patterns-handler.test.ts` - route-aware Octokit mock for the pulls routes (its `SKILL_CLUSTER` reaches the guard).
- `scripts/followthroughs/compound-promote-draft-edit-10552.sh` - add `skill-conflict-guard-unverifiable` to the N-class set (`nset`) AND to the header prose that lists the reasons (lines ~22, 33, 47) so the two do not drift.
- `scripts/followthroughs/compound-promote-draft-edit-10552.test.sh` - add the new reason to the P-6 loop; raise `MIN_CASES` to the new measured total.
- `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md` - rewrite the `skill-conflict-guard` bullet (lines ~171-175); add the `-unverifiable` bullet (states that an open PR with more than 1000 changed files, or more than 150 file-list requests in a run, makes every skill cluster unverifiable until it closes) and the `too-long` cap note; say where the conflicting PR number appears (the Better Stack warn line).
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` - refusal enum list (line ~708): add `skill-conflict-guard-unverifiable`.
- `knowledge-base/engineering/architecture/decisions/ADR-092-additive-only-auto-edit-boundary-and-hard-rule-body-weakening-gate.md` - correct in place the compensating-controls sentence ("500 characters", line ~215): 600 for `AGENTS.rules.md` (pinned to the corpus lint) and 1000 for SKILL.md, 500-character prompt target, with a short dated clause (2026-10-26, #10552). No separate amendment section.
- `knowledge-base/engineering/architecture/decisions/ADR-300-pattern-wiki-and-pr-state-proposal-ledger.md` - the accepted-residual bullet about the skill-conflict comment (line ~91).
- `knowledge-base/legal/audits/2026-10-20-dpia-reeval-compound-promote-2720.md` - CLO scope: edit the line-120 cell (cap now 600, 1000 for SKILL.md), add a `> **Superseded 2026-10-26 (#10552): ...**` marker under each skill-conflict-comment sentence (lines ~93, 157, 184, 197, 288), add a dated `## Addendum 2026-10-26 (#10552)`, add a frontmatter pointer key. Wording is conditioned on the merge ("on the merge of PR #11157 ...") and is not written in the past tense.
- `knowledge-base/legal/compliance-posture.md` - row 170: one dated sentence (residual (b) narrows to the draft PR only; cap moved to 600/1000; nothing new goes to a processor so #10676's processor trigger is not engaged). Row 171's trigger text is unchanged.

## Files to Create

- `apps/web-platform/test/server/inngest/cron-compound-promote-skill-guard.test.ts` - table-driven unit tests of `scanOpenPrSkillPaths` and `skillConflictVerdict` with a fake octokit that records `(route, params)`.
- `knowledge-base/project/specs/feat-one-shot-10552-proposer-refusal-line-cap-and-skill-guard/tasks.md` (Save Tasks step).
- `knowledge-base/project/specs/feat-one-shot-10552-proposer-refusal-line-cap-and-skill-guard/decision-challenges.md` (written).

`apps/web-platform/test/github-url.test.ts` is not edited: it must stay green, which holds because both new
call sites pass a literal `"VERB /route"` first argument.

## Open Code-Review Overlap

None. Queried open `code-review` issues for each planned file path (nine path/basename keys including the
cron file, the runbook, the three test files, ADR-092 and the lint script): zero matches.

## Architecture Decision (ADR/C4)

### ADR

No new ADR. ADR-092 is corrected in place (compensating-controls sentence) and the ADR-300 accepted-residual
bullet is updated; both are Phase 4 tasks, not follow-ups.

### C4 views

All three model files were read (`model.c4`, `views.c4`, `spec.c4`). No C4 impact. Checked and already modelled:
external actor `publicReader` ("a PUBLICATION surface"; the removed comment was an instance, the removal only
narrows it); external system `github` and container `api`; the access relationship is the single edge
`api -> github` (`model.c4` line ~741), whose description covers the cron's read of bot-PR state via search. That
description is not falsified by this change (it never mentioned the guard's listing or the comment write), so no
edit is made. No element, tag, relationship or `view include` changes. `plugins/soleur/test/c4-count-parity.test.sh`
is green on this branch (derived cardinalities do not move).

### Sequencing

Single PR. The ADR and compliance text describe the post-merge state.

## User-Brand Impact

- **If this lands broken, the user experiences:** the weekly compound-promote cron still opens no draft PR, or
  opens one that conflicts with an in-flight edit to the same skill file; the operator sees the same refusal rows
  in Better Stack. No end-user surface changes.
- **If this leaks, the user's data is exposed via:** nothing new. The change removes the one path that published
  model-derived diff text into a public PR with no human gate; the inserted-text screens (printable ASCII, 20-line
  cap, credential shapes, render hazards, rule-id grammar) are unchanged and only the length bound moves.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the cron operates on the operator's own corpus and every PR it opens is
  a draft behind a human merge gate; this PR reduces a publication surface and weakens no screen that guards credentials or personal data.

*Scope-out override:* `threshold: none, reason: the touched server path only narrows an outbound GitHub write and widens a length bound on text that still passes the unchanged credential, charset and render-hazard screens and a human-gated draft PR.`

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_COMPOUND_PROMOTE_OUTCOME marker row per run (refusals[] + refusal_detail[]), shipped to Better Stack"
  cadence: "weekly (Sunday 00:00 UTC) plus manual input:patterns runs"
  alert_target: "follow-through sweeper on #10552 (probe exit 5 after 35 days NOT YET); Sentry issue feed for draft-edit-refused and skill-conflict-guard-unverifiable (feed only, no paging rule claimed)"
  configured_in: "apps/web-platform/server/inngest/functions/cron-compound-promote.ts; scripts/followthroughs/compound-promote-draft-edit-10552.sh"
error_reporting:
  destination: "Sentry via reportSilentFallback (feature cron-compound-promote)"
  fail_loud: "logger.warn lines skill-conflict-guard-refused / skill-conflict-guard-unverifiable (level 40, reaches Better Stack) and a refusals[] entry; API errors fail the scan step (Sentry correlation via the Inngest run error)"
failure_modes:
  - mode: "an open PR changes the cluster's target file"
    detection: "pino warn skill-conflict-guard-refused (fn, hash, pr, target) shipped by Vector to Better Stack, plus a refusals[] entry in the outcome marker; query: scripts/betterstack-query.sh --grep skill-conflict-guard-refused"
    alert_route: "deliberately non-paging: the #10552 probe grades it N-class (NOT YET) and raises ACTION REQUIRED only after 35 days; a stale self-conflicting draft PR can block a file quietly until then"
  - mode: "scan cannot finish (bound prs, files or requests reached, no match)"
    detection: "pino warn skill-conflict-guard-unverifiable (fn, hash, bound) via Vector to Better Stack, mirrored by the pino -> Sentry path (reportSilentFallback message path, op skill-conflict-guard-unverifiable, tag bound), plus a refusals[] entry"
    alert_route: "Sentry issue feed (no paging rule is claimed for this op) and the same Better Stack row"
  - mode: "model line exceeds the new cap"
    detection: "draft-edit-refused with reason edit-invalid and cause too-long (Sentry tags)"
    alert_route: "Sentry issue; N-class in the probe"
logs:
  where: "Better Stack source fed from journald/Vector (logger.warn) and the app pino mirror"
  retention: "Better Stack source retention"
discoverability_test:
  command: "bash scripts/followthroughs/compound-promote-draft-edit-10552.sh"
  expected_output: "PASS"
  # the probe prints PASS to stdout (exit 0); NOT YET (2), FAIL (1), CANNOT ESTABLISH (3) and ACTION REQUIRED (5) go to stderr.
  # credentials_required below makes preflight Check 10 SKIP-DECLARED, so the 15s cap is never exercised.
  credentials_required: "Better Stack query credentials (Doppler soleur/prd_scheduled BETTERSTACK_QUERY_HOST, _USERNAME, _PASSWORD) - the refusal rows exist only in Better Stack, so no unauthenticated probe verifies the same property"
```

## Guard Contract

### Guard 1 - Edit-line cap pinned to the corpus lint

**Property.** The cap the validator enforces on a model-written `AGENTS.rules.md` line equals the corpus lint's
`PER_RULE_CAP`, measured in the same unit, so the validator never accepts a line the lint rejects and never
refuses one the lint accepts.

**Assembly.** The number appears in: the TS constant `AGENTS_EDIT_LINE_MAX_CHARS`; the one `too-long` arm of
`newLinesCause` (the single place a cap is chosen, for both targets, and the prompt builder reads the same
expression); the prompt line built from the same constants; the Python constant `PER_RULE_CAP`; and prose in
ADR-092, the runbook and the DPIA memo (prose is covered by acceptance-criteria greps on code symbols, not by the
pin test). The unit equality (chars == bytes) holds because `PRINTABLE_ASCII_RE` admits only ASCII. The SKILL cap
is deliberately unpinned. Anchor: a single PR can edit both constants, so the pin proves consistency (drift
detection), not integrity; that is the property wanted here.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Set `AGENTS_EDIT_LINE_MAX_CHARS` back to 500 | RED (pin test equality; boundary row: a 600-char rule line is accepted) |
| 2 | Change `PER_RULE_CAP` to 601 in the Python file | RED (pin test) |
| 3 | Rename `PER_RULE_CAP` in the Python file so the extractor finds zero matches | RED (the exactly-one-match assertion fails loudly instead of the pin passing vacuously: dispatch row) |
| 4 | Remove the `PRINTABLE_ASCII_RE` arm | RED (a 301-character line of two-byte characters, 602 bytes, must be refused) |
| 5 | Apply the SKILL cap to the AGENTS target | RED (a 601-char AGENTS rule line is refused; second member after a compliant first) |
| 6 | Hard-code "500" in the prompt text | RED (prompt assertion: the text contains the target's hard cap taken from the constants, per target) |

Harness rows: (H1, suite edit) swap the extractor's regex for one that captures `B_ALWAYS_WARN` (44000): the pin
must go RED because 44000 is not 600. (H2, must-PASS non-canonical) `extractPerRuleCap` run on the fixture string
`PER_RULE_CAP=600  # note` (different spacing, trailing comment) returns 600, and run on a string that only
mentions `{PER_RULE_CAP}` inside an f-string returns no match; the helper is the same function the pin test calls,
so the fixture rows test the real extractor.

### Guard 2 - Skill-conflict guard fires on a same-file change and never reports clear unverified

**Property.** A skill-targeting cluster is refused as `skill-conflict-guard` when some open PR (other than a
Dependabot PR, skipped for call saving) changes the cluster's `target_path` as `filename` or `previous_filename`,
and the guard never yields "clear" when the scan hit a bound and found no match.

**Assembly.** The chokepoints are `scanOpenPrSkillPaths` (one run-wide scan, memoized as one step) and
`skillConflictVerdict` (the only place a verdict is made), reached from the one apply-step block gated on
`target_path.startsWith("plugins/soleur/skills/")`. The scan quantifies over up to 3 pages of 100 open PRs and,
per PR, up to 10 pages of 100 files, under a run-wide 150-request budget. In the assembly: two literal routes, the
author skip, three bounds, three error paths (request error, non-array payload, bound reached), the step-presence
condition (scan runs lazily, only for a drafted skill cluster, once) and the handler's verdict mapping (`conflict` ->
`skill-conflict-guard`, `unverifiable` -> `skill-conflict-guard-unverifiable`, `clear` -> continue).
`AGENTS.rules.md`-only runs must make zero calls to either route. Anchor: the guard compares a live API answer to
the cluster's own path, so no stored value is involved.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert to `GET /search/issues` title/body matching | RED (the fake records `(route, params)`: only the two literal routes with `state:"open"`, `per_page:100` and an incrementing `page` are allowed; the different-file and title-mention cases must be clear) |
| 2 | Drop the `previous_filename` mapping | RED (rename case) |
| 3 | Stop the scan after the first non-skipped PR | RED (a same-file PR listed second, after a compliant different-file first PR, must conflict) |
| 4 | Treat a reached bound as clear (any of `prs`, `files`, `requests`) | RED (one table row per bound must be unverifiable) |
| 5 | Skip every bot author instead of only `dependabot[bot]` | RED (an App-bot PR on the same file must conflict) |
| 6 | Wrap the requests in a try/catch that returns an empty scan | RED (request-error cases must reject) |
| 7 | Guard never invoked (condition prefix mistyped) | RED (handler-level same-file case must end `skill-conflict-guard`; dispatch row) |
| 8 | Re-add a comment POST in the handler | RED (handler cases assert no request whose route starts with `POST`) |
| 9 | Match with `includes` or `startsWith` instead of equality | RED (must-PASS: a PR changing `.../alpha/SKILL.md.orig` is clear) |
| 10 | Read `pr.user.login` without optional chaining | RED (a `user: null` PR row must not throw) |
| 11 | Run the scan once per cluster instead of once per run | RED (handler case with two skill clusters asserts the pulls route is requested once per page, and the file budget is shared) |
| 12 | Record every changed skill path instead of only the clusters' targets | RED (a 1000-file PR scan result holds at most one entry per target) |
| 13 | Look the target up with `in` instead of `Object.hasOwn` | RED (a target named `constructor`-style key is never reported as a conflict after a JSON round-trip of `changed`) |
| 14 | Run the scan eagerly before drafting | RED (a skill cluster refused by quorum/duplicate/draft makes zero pulls requests) |

Harness rows: (H1, suite edit) make the fake octokit answer every files request with a full page forever: the
scan must still terminate and report `files` (the loop bound ends it, not the fake). (H2, must-PASS non-canonical)
a PR set containing the prefix-lookalike path, the live #10812 shape (title mentions the skills directory, file
`requirements.txt`) and a `user: null` PR must scan to `incomplete: null` and yield `clear`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Decide the fix (align cap to the lint's 600 bytes ... or tighter cap + one bounded retry)" | Defect A; ruling A-1 (600 hard cap, 500 soft target, no retry) | mapped |
| 2 | "update the prompt text, the validator, and tests" | Defect A edits and Phase 1 tests | mapped |
| 3 | "Keep the cap derived from / pinned against PER_RULE_CAP ... (a test that reads the lint constant)" | Guard 1; pin test | mapped |
| 4 | "Narrow it so it only fires for an open PR that touches the SAME target file (cluster.target_path), and skip bot/dependabot noise" | Defect B; rulings B-1, B-4 | mapped |
| 5 | "decide whether the comment-on-unrelated-PR side effect should remain at all (route that fork to the CTO agent)" | ruling B-3 (removed) | mapped |
| 6 | "Keep fail-closed behaviour on a search/API failure, keep the egress census test ... green (literal routes only)" | scan error paths; two literal routes | mapped |
| 7 | "add tests for same-file, different-file and dependabot cases" | Phase 2 tests | mapped |
| 8 | "add/adjust ADR or runbook text only where behaviour documented there changes" | runbook, ADR-092, ADR-300, betterstack-log-query | mapped |
| 9 | "The PR body must say effect unmeasured until #10552 clears and must not claim these fixes will open a PR" | Acceptance Criteria (PR body) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Separate SKILL.md cap of 1000 | "mind chars-vs-bytes and the printable-ASCII rule so they coincide" | asked (measurement showed the AGENTS rule does not fit SKILL.md) |
| New `skill-conflict-guard-unverifiable` reason, bounds and per-run scan | "Keep fail-closed behaviour on a search/API failure" | asked (a bounded enumeration needs a non-clear arm) |
| Probe `nset` entry, header prose and `MIN_CASES` | "add/adjust ADR or runbook text only where behaviour documented there changes" | inferred: the probe's closed reason vocabulary documents the refusal set; one new member must be named or it prints `unknown` |
| Compliance-record edits (DPIA memo, posture row 170) | "add/adjust ADR or runbook text only where behaviour documented there changes" | inferred: the CLO ruled the cap sentence and the comment-surface statements become false on merge; a false compliance statement is a defect |

### Split Assessment

- Subsystems touched: 4 - `apps/web-platform`, `scripts/followthroughs`, `knowledge-base/engineering`, `knowledge-base/legal`
- Planned files: 15 | Estimated changed lines: about 650
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The four roots are one behaviour (two refusal paths in one function) plus the text that
  describes it; splitting would leave the compliance record or runbook describing a state the code no longer has.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled all forks (rows A-1..B-4 of `decision-challenges.md`). Key constraints adopted: 600 for the AGENTS cap pinned to `PER_RULE_CAP`, 500 prompt target, no retry; 1000 for SKILL.md after the 1071-line measurement met the CTO's own flip condition; same-file match on `filename`/`previous_filename`; skip only `dependabot[bot]`; one per-run scan with bounds 3 PR pages / 10 file pages / 150 requests and an `unverifiable` refusal; comment removed.

### Legal

**Status:** reviewed
**Assessment:** CLO agent (draft material, internal sign-off only): the DPIA memo's output-screen sentence ("at most 500 characters") and the statements that the skill-conflict comment is posted "with no gate" become false on merge, so the memo gets an in-place edit of the line-120 cell plus dated supersession markers and an addendum, and `compliance-posture.md` row 170 gets one dated sentence; row 171's trigger text stays. The Art. 30 register has no claim to change (re-grep at work time and fix in place if one is found). The #10676 trigger "first posted skill-conflict comment" **fired on 2026-10-26T09:47Z** (comment on PR #10812, no recorded balancing basis); this PR records the fact and does not discharge the trigger. Deleting that comment is not in this PR (decision-challenges row C-1, operator authorization).

No Product/UX surface, no marketing, finance, sales, operations or support implications.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Pre-merge (PR)

- [x] `grep -n "AGENTS_EDIT_LINE_MAX_CHARS = 600" apps/web-platform/server/inngest/functions/cron-compound-promote.ts` returns one line, and the symbol `EDIT_LINE_MAX_CHARS` (without the `AGENTS_`/`SKILL_` prefix) no longer appears under `apps/web-platform`.
- [x] A vitest reads `PER_RULE_CAP` out of `scripts/lint-agents-rule-budget.py` (path resolved from `import.meta.url`, a missing file is a hard failure, anchored exactly-one-match, integer-validated) and asserts equality with `AGENTS_EDIT_LINE_MAX_CHARS`.
- [x] Boundary rows: an AGENTS rule line of exactly 600 characters is accepted, 601 is `edit-invalid`/`too-long`; a SKILL line of 1000 is accepted, 1001 is refused; 20 lines at each cap pass; a 301-character line of two-byte characters is refused as `charset`.
- [x] The prompt sent for an AGENTS target contains the hard cap 600 and for a SKILL target 1000, plus the soft target 500, each taken from the constants.
- [x] `scanOpenPrSkillPaths({..., targets})` + `skillConflictVerdict` (table-driven): clear for a Dependabot #10812-shaped fixture (title mentions the skills directory, file `requirements.txt`) with no files request made for the Dependabot PR; clear for a different-file human PR; conflict for a same-file PR; conflict for a rename whose `previous_filename` matches; conflict for a same-file PR authored by an App bot; conflict for a match on the second files page; a `user: null` PR does not throw; `changed` holds only entries equal to a requested target (a 1000-file PR yields at most one entry per target); the first PR wins for a path changed by two PRs; the first-reached bound is the one reported when several are hit; unverifiable with `bound` `prs`, `files` and `requests` respectively when each bound is reached without a match; a match found after a bound was reached is still a conflict; rejects on a request error and on a non-array payload. The fake records `(route, params)` and the suite asserts the exact route set, `state:"open"`, `per_page:100` and incrementing `page`.
- [x] Handler level: a different-file open PR lets the skill cluster open; a same-file PR yields `skill-conflict-guard` with no `safeCommitAndPr` call, no request whose route starts with `POST`, and no `reportSilentFallback` for the conflict; the unverifiable case yields `skill-conflict-guard-unverifiable` with a Sentry `op` of the same name; two skill clusters share one scan; an `AGENTS.rules.md`-only run, and a skill cluster refused earlier by quorum, duplicate or draft refusal, make no call to either pulls route (the scan is lazy).
- [x] `grep -rn "skillConflictDiffBody\|search/issues" apps/web-platform/server/inngest/functions/cron-compound-promote.ts` returns only the ledger/week-cap search call sites that predate this change (no `in:files`, no `skillConflictDiffBody`).
- [x] `apps/web-platform/test/github-url.test.ts`, `cron-compound-promote-outcome-census.test.ts` (including Guards 1, 1b, 1c, 3, 3b), the three `cron-compound-promote-*` handler/edit suites and `plugins/soleur/test/c4-count-parity.test.sh` are green.
- [x] `bash scripts/followthroughs/compound-promote-draft-edit-10552.test.sh` passes with `MIN_CASES` raised to the new measured total.
- [x] Runbook, `betterstack-log-query.md`, ADR-092 (in place), ADR-300, the DPIA memo and `compliance-posture.md` row 170 carry the text listed under Files to Edit; the ADR-092 sentence names 600, 1000 and the 500 prompt target.
- [x] The patterns-handler suite's "exactly two `TARGET_ALLOW_RE.test(` sites in the handler" test and census Guard 3 (exactly one `async (): Promise<ClusterOutcome> => {` opener) stay green: the scan step does not copy that signature and adds no `TARGET_ALLOW_RE.test(` call.
- [x] `python3 scripts/lint-guard-contract.py` and `python3 scripts/lint-infra-no-human-steps.py` pass on this plan.
- [ ] PR body: `Ref #10552` (not `Closes`), states the effect is **unmeasured until #10552 clears**, does not claim a PR will open, and lists the CTO and CLO rulings. #10552, #10551, #10550, #8443 and #8293 are not commented on or closed.

### Post-merge

- [ ] The cron is not triggered by this work. The next scheduled or manually triggered run is the measurement; the existing #10552 follow-through probe reads it. Until then the effect is unmeasured.
- [ ] Ship-time tracker note (agent action, not part of the diff): a factual note on #10676 that its "first posted skill-conflict comment" trigger fired on 2026-10-26T09:47Z (PR #10812) and that this PR removes the surface; the re-run of the empirical limbs stays with the operator and CLO.

## Test Scenarios

Pyramid layers: unit unless marked.

- Given a 600-character AGENTS rule bullet with a fresh `cq-` id, when `buildAdditiveEditDiff` runs, then it derives a diff; given 601 characters, then `edit-invalid`/`too-long`.
- Given a 1001-character SKILL line, then `too-long`; given 1000, then accepted.
- Given `PER_RULE_CAP` text with unusual spacing, when the extractor runs, then it returns the integer; given no match, two matches, or only an f-string mention, then the test fails loudly.
- Given open PRs `[dependabot #10812 (title mentions skills dir)]`, when the scan runs, then no files request is made for it and the verdict for `plugins/soleur/skills/alpha/SKILL.md` is clear.
- Given 3 full pages of PRs that never match, then `incomplete: "prs"` and an unmatched target is unverifiable `prs`; given a PR with 10 full files pages, then `files`; given more than 150 file-list requests needed, then `requests`; in each case a path already collected still yields conflict.
- Given the handler with a same-file PR, then the cluster ends `skill-conflict-guard`, the marker row carries it, a warn line carries `pr`, and no POST is made (integration, real cloned git repo as in the existing handler suite).
- Regression for the reported run: the #10812-shaped fixture no longer blocks a skill cluster (integration).

## Success Metrics

Not measurable at merge. The measurement is the first run after merge whose marker row shows a skill-targeting
or AGENTS-targeting cluster passing these two gates, read by the #10552 probe. Until then: unmeasured.

## Dependencies & Risks

- **The cap raise does not guarantee a PR.** Other gates (byte budget, shrink floor, quorum, `lint-rule-ids` pointer) are unchanged and may still refuse. State this in the PR body.
- **API cost of the guard.** 44 open PRs today, so about 40 file-list requests once per run (shared by both clusters); the 3x10 page bounds and the 150-request budget cap the worst case, and exhaustion is an `unverifiable` refusal, never a clear. Dependabot PRs are skipped to trim the count. A single open PR with more than 1000 changed files, or a repository with more than about 150 non-Dependabot open PRs, makes every skill cluster `unverifiable` until it clears; the runbook says so.
- **Self-conflict is intended.** The App's own earlier open draft promote PR on the same SKILL.md refuses the new cluster as `skill-conflict-guard` (CTO confirmed); the cluster re-proposes after that draft merges or closes.
- **A new refusal reason touches co-moving artifacts** (probe `nset` and header prose, probe test floor, runbook, Better Stack enum list). All are in Files to Edit; the census (Guard 1b) pins only `edit-*` reasons and is unaffected, verified by running it.
- **The new `skill-conflict-scan` step is inside the census-covered handler.** Guards 1 and 3 (apply-step window, replay safety) must stay green; the step returns a plain JSON object and mutates no handler-scope accumulator.
- **1000 for SKILL.md is a judgment value** (no lint to pin it). Revisit only if refusal rows show it being hit (CTO ruling A-3).
- **Accepted race.** Both skill clusters share one snapshot of the open PRs; a PR opened between the scan and `safeCommitAndPr` is not seen. State this in the runbook. A human-gated draft PR bounds the consequence to a merge conflict a reviewer resolves.
- **Availability limit, accepted.** Any contributor (including a fork) who opens a PR on the same skill file, or one PR with more than 1000 changed files, blocks a skill cluster until it closes. This is fail-closed by design; the runbook says so.
- **SKILL.md payload room.** A skill edit can now carry up to 20 lines x 1000 characters (20k characters); the AGENTS-only id/tag screens do not apply to skills. Bounded by the 20-line cap, the unchanged credential and render-hazard screens and the human-gated draft PR. A total inserted-character cap was considered and not added (it would be a new threshold with no measured need); revisit with the 1000 value if refusal rows show it being hit.
- **Compliance wording must stay conditional on merge** (CLO): do not write the removal in the past tense.

## Implementation Phases

1. **Phase 1 - Defect A (tests first).** Write the failing boundary, prompt and pin tests; add the constants, the inline cap in `newLinesCause`, the prompt text and the comment rewrite. Update the existing 500/501 rows.
2. **Phase 2 - Defect B (tests first).** Write `cron-compound-promote-skill-guard.test.ts` (table-driven) and the handler-level cases, including the route-aware Octokit mocks in the two handler suites; implement `scanOpenPrSkillPaths`, `skillConflictVerdict`, the `skill-conflict-scan` step and the apply-step block; delete `skillConflictDiffBody` and its tests.
3. **Phase 3 - probe and docs that co-move.** Probe `nset` + header prose + test floor; runbook; `betterstack-log-query.md`.
4. **Phase 4 - ADR and compliance record.** ADR-092 in-place correction, ADR-300 bullet, DPIA memo and posture row (conditional wording).
5. **Phase 5 - verification.** Run the listed suites, the two plan lints and the greps; confirm `github-url.test.ts` and the outcome census are green. Do not trigger the cron.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or filler text fails `deepen-plan` Phase 4.6; this plan fills it with threshold `none` plus the scope-out line.
- The existing handler-suite Octokit mocks answer every route with `{data:{total_count,items}}`. The new scan rejects a non-array payload on purpose (fail closed), so those mocks must become route-aware or every skill-cluster handler test errors.
- `pr.user` is null for deleted accounts: read it as `pr.user?.login`, and keep a `user: null` row in the fixtures.
- Octokit call sites pass a literal `"VERB /route"` first argument and cast the result as `{ data: ... }` (precedent: `cron-bug-fixer.ts`); never a route variable, never `as never`.
- The Edit tool rewrites U+2028/U+2029 in `old_string`; the cap tests build non-ASCII lines with `String.fromCharCode`/repeat, not literals.
- Do not add a `Closes` line anywhere, and do not comment on #10552: only `Ref #10552`.
