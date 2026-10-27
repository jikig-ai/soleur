---
title: "chore: wire autonomous start for the date-gated and event-gated code-quality follow-ups"
date: 2026-10-27
slug: autonomous-start-followthroughs
branch: feat-one-shot-autonomous-start-followthroughs
issue: 9730
refs: [9730, 10515, 11177, 10331]
closes: none
type: chore
priority: p3-low
lane: cross-domain
brand_survival_threshold: none
---

## Enhancement Summary

**Deepened on:** 2026-10-27. **Gates run:** 4.4 scheduled-work pattern, 4.6 user-brand, 4.7 observability, 4.8 PAT-shaped, 4.11 guard contract (lint green), 4.12 scope check, 4.13 task design; cited PR numbers and rule IDs verified live. **Agents:** DHH, Kieran and simplicity (plan-review), security-sentinel, spec-flow-analyzer, learnings-researcher, CTO x3.

### Key improvements
1. Dry-run for all three scripts, exact-permission and allowlist-census guard, concurrency block, default-branch-rename-proof job guard, per-job permissions.
2. Third-party text is code-spanned and sanitized end to end; sentinels are exact-last-line printf constants; billing is a `code_quality`-only allowlist that never publishes the org's bill.
3. Billing blips and transient failures retry instead of spending the one-shot; every month from 2026-09 is covered; one slow commit becomes a sentineled `unjudgeable` finding instead of a perma-red.

### New considerations
- A disabled workflow is a documented residual (no dead-man), per CTO S2.
- Fixed a discoverability `expected_output` that the preflight tokenizer would have rejected as prose.

## Overview

Three open trackers wait on a date or an event and today depend on someone remembering to look: #9730 (re-evaluate GitHub Code Quality, due on or after 2026-11-14), #10515 (lint-ratchet user-mode deferrals, due on or after 2027-01-18) and #11177 (brand-hex gate misses a chained add-then-commit; event-gated, P3). This plan gives each an autonomous start: a committed, read-only watcher script per tracker that gathers the data its re-evaluation needs and posts it once as a comment, run weekly by one repo-scoped `*-watch.yml` workflow. All three trackers stay open. Nothing here turns Code Quality on, changes a repository setting, closes, relabels or edits a tracker, or implements the #11177 fix.

The mechanism departs from the brief's literal wording (a `soleur:followthrough` directive on #9730 and #10515): the CTO ruled a dedicated watch workflow instead, because the sweeper comments on every non-0/1 verdict with no dedup and exit 0 closes the issue (see `## Research Reconciliation` and `decision-challenges.md` F2). The brief's intent is kept: autonomous start once the date passes, a data comment on the tracker, trackers left open.

PR body reminder (no closing keyword anywhere, not in the title either): `Ref #9730`, `Ref #10515`, `Ref #11177`, `Ref #10331` (the code-quality epic, closed 2026-10-20, must not be reopened). Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; the PR body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

## Research Insights

**Premise validation (Phase 0.6).** Checked with `gh issue view`: #9730, #10515, #11177 are OPEN; #10331 is CLOSED (2026-10-20), so it is a `Ref` only. #9730's thread shows Code Quality was turned OFF on 2026-10-19 (CTO ruling, ADR-276 amendment) and the billing stop was confirmed on 2026-10-22; the 2026-11-14 item is therefore "re-enable only if (i) a consumer for the findings exists and (ii) the AI-credit spend can be capped by a billing budget on the `code_quality` product", not "keep or switch off". #11177's thread (2026-10-27) records both triggers as not met. Collision pre-check: no open PR names any of the three issues; foreign `test-all.sh` processes belong to other worktrees. Open sibling PR #11154 (orphan-sweeps re-look probe) edits `followthrough-convention.md`, `scripts/test-all.sh`, both `suite-*.tsv` files and `tests/scripts/test-argv-bearer-sweep.sh`; this plan avoids the runbook and the argv-bearer file and plans a union-resolve for the rest. ADR corpus: ADR-033 (Inngest-first scheduling) allows repo-scoped GitHub Actions watchers by precedent (`registration-narrowing-watch.yml`, `codeql-1537-revisit-watch.yml`); the `new-scheduled-cron-prefer-inngest.sh` hook gates only `scheduled-*.yml` file names.

**Scheduled-work pattern check (deepen Phase 4.4).** `git ls-files | grep cron-` shows Inngest cron functions exist, so Inngest is the default substrate (ADR-033). GitHub Actions cron is acceptable here because the work is purely repo-scoped (GitHub API reads, git history, one issue comment), uses only the default token with no app secret, no Sentry integration, and gains nothing from `step.run` replay; the existing `registration-narrowing-watch.yml` and `codeql-1537-revisit-watch.yml` are the in-repo precedents, and the `*-watch.yml` name keeps clear of the filename-gated hook. Mechanism (diff against precedent): same cron-plus-main-guard-plus-sentinel-plus-self-disable shape; differences are three jobs in one file and a shared lib.

**Measured at plan time (read-only spikes).** (1) The gate-reuse mechanism of F4c works: a `git worktree add --no-checkout --detach <parent>`, `git read-tree <commit>` in that worktree's own index, a plain `git commit -m x` JSON payload and `CLAUDE_PROJECT_DIR` at an empty directory returned `allow` for a real recent main commit touching `apps/web-platform/components/*.tsx`, and returned `deny` naming `components/zz-probe.tsx:1 (component #ff00aa; use a design token)` for a synthetic index entry carrying a raw hex colour; the hook ran from the main checkout (the `--no-checkout` worktree holds no hook files), and the gate `unset`s `GIT_INDEX_FILE`, which is why the worktree's own index is used. (2) One GraphQL request with 40 aliased `search(type:ISSUE, first:1){issueCount}` fields (20 days, opened plus merged) returned in about 3 s at cost 1. (3) `gh issue view --json state,createdAt,comments` carries the fields the lib reads. (4) 2026-11-14 is a Saturday (first cron run 2026-11-16) and 2027-01-18 is a Monday.

**Property list (Phase 0.6b).**

- P1. On or after 2026-11-14 a comment with billing (Sep, Oct, Nov-to-date, where readable) and PR volume per day appears on #9730 with no human remembering.
- P2. On or after 2027-01-18 a comment with the data the lint-ratchet re-evaluation needs appears on #10515.
- P3. The two #11177 "re-evaluate when" triggers are tested weekly and the tracker is commented on only when one fires.
- P4. All three trackers stay open; no setting changes; Code Quality is not enabled; nothing is relabelled or edited.
- P5. The keep-off or turn-on ruling is recorded by the CTO agent in a later `soleur:go` session, and the data comment says so.
- P6. Everything is read-only apart from issue comments; fixtures hold no real credential.

**Cut list (Phase 0.6b).**

| Mechanism | Property | What already covers it or why cut |
|---|---|---|
| `soleur:followthrough` directive for #9730/#10515 | P1, P2 | Buys the date gate, but the sweeper comments on every rc 2/3/5 daily with no dedup and rc 0 closes; `registration-narrowing-watch.yml` already buys notify-once. Cut by CTO ruling F2. |
| Sweeper invokes a skill or agent | P5 | No such mechanism on `origin/main` (grepped `scheduled-followthrough-sweeper.yml` and `scripts/sweep-followthroughs.sh`: the launcher only `execve`s a committed script). P5 is met by the comment text. F1. |
| New org-billing App or PAT secret | P1 | A standing privilege for a P3 tracker; hr-github-app-auth-not-pat. Cut, F3: try the Actions token, degrade to PR volume plus exact commands. |
| Copying the gate's colour regexes into the watcher | P3 | The gate itself is runnable; run it against each commit instead (F4c). |
| Editing `followthrough-convention.md` | none | Conflicts with #11154; the shape is documented in the workflow and script headers (F6). |
| Regenerating the TSV `generated-at` headers | none | Hand-insert rows alphabetically (F6); the header is a conflict magnet with #11154. |

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| Add the followthrough directive to #9730 and #10515, scripts under `scripts/followthroughs/` | Sweeper posts the probe's stdout on every non-0/1 verdict daily, with no dedup; exit 0 closes the issue; the convention itself routes notify-only shapes to a dedicated workflow | One `*-watch.yml`, scripts under `scripts/` (`watch-*.sh`), no directive (F2). Reversible: a directive can be added later. |
| The script "pulls billing for Sep, Oct and Nov-to-date" | `GET orgs/jikig-ai/settings/billing/usage` works with the operator's local auth; no billing credential exists among repo secrets; the Actions token has no organization-administration scope | Try the Actions token; 401/403/404 means "not readable from CI", post PR volume plus per-month commands for the ruling session; measure the real status with a post-merge dry-run dispatch (F3). |
| "keep-off or turn-on ruling" | Code Quality has been OFF since 2026-10-19; the 2026-11-14 test is "consumer exists AND spend can be capped" | Data comment states the criteria and the current OFF state; ruling stays with the CTO agent in the next `soleur:go` session. |
| #11177 trigger: "a second hook other than git-commit-secret-scan.sh sourcing commit-index-sim.sh" | The issue says "a third hook"; the brand-hex gate adopting the lib is the planned fix, so the brief's wording would fire on the fix itself | Exclude both `git-commit-secret-scan.sh` and `brand-hex-commit-gate.sh` (F4b). |
| Sweeper can invoke the CTO agent? | No | Data only (F1). |

## Problem Statement / Motivation

Three tracker comments end with "re-evaluate by DATE" or "re-evaluate when EVENT" and nothing fires on that date or event ("nothing fires on that date by itself" is the ADR-276 amendment's own words for #9730). The consequence is silent rot: the cost lever (a metered AI-credit line that reached $254.96 in 28 days) or the brand gate's known hole stays unexamined until someone happens to look.

## Proposed Solution

One workflow, `.github/workflows/code-quality-followups-watch.yml`, weekly (Mondays 09:17 UTC), three independent jobs, default branch only, `GH_TOKEN=github.token`, `permissions: contents: read, issues: write`. Each job runs one script from `scripts/`. A small shared library holds the pieces all three need.

```text
code-quality-followups-watch.yml
  job reeval-9730   -> scripts/watch-code-quality-reeval-9730.sh   (earliest 2026-11-14)
  job reeval-10515  -> scripts/watch-lint-ratchet-reeval-10515.sh  (earliest 2027-01-18)
  job triggers-11177-> scripts/watch-brand-hex-triggers-11177.sh   (every run)
shared: scripts/lib/watch-notify-once.sh
```

### Shared library `scripts/lib/watch-notify-once.sh` (sourced, never executed)

`wn_notify_once_main <tracker> <earliest> <sentinel-key> <gather_fn>` holds the whole common flow of the two dated scripts (date gate -> OPEN check -> sentinel -> gather callback -> post), so each of scripts 1 and 2 holds only its gather and compose callbacks; script 3 stays separate and shares only the sentinel reader and `wn_post` (CTO round 2, R4). The same lib function is what Guard 2 row 1 mutates, so one edit covers both dated scripts.

- `wn_now` / `wn_reached ISO`: epoch compare with a `WATCH_NOW` test seam; before the date the script prints a `::notice::` and exits 0.
- `wn_read_issue N`: `gh issue view N --json state,createdAt,comments`; sets `WN_STATE`, `WN_JSON`; any failure is rc 3 (post nothing).
- `wn_sentinel_present KEY`: true only for a comment authored by `github-actions` or `github-actions[bot]` whose body contains the sentinel; a human-authored sentinel never suppresses. A jq failure is rc 3, never "absent".
- `wn_post N`: `gh issue comment N --body-file -`; failure is rc 1.
- `wn_sanitize` (renamed from `wn_sanitize_title`; security review S1/S5): EVERY interpolated third-party string (issue titles, logins, file paths, commit subjects, gate deny reasons) is rendered inside a code span with backticks removed, so `@mentions`, `#N` back-references and bare URLs do not notify or autolink; it also drops C0 controls, DEL, U+2028/2029, bidi overrides (U+202A-202E, U+2066-2069) and zero-width characters, neutralises `<`, `>` and `&`, and cuts to 100 characters. Bodies are never pasted.
- `wn_billing_month Y M`: `gh api 'orgs/jikig-ai/settings/billing/usage?year=Y&month=M'` (year and month in the URL, never `-f`/`-F`, so the call stays a GET); runs the single jq aggregate (per-product gross and net, plus the first and last dated `code_quality` line) so scripts 1 and 2 only render its output, and sets `WN_BILL_STATUS` to `ok`, `unreadable:<status>` (401/404/non-rate-limit 403, status = the `HTTP [0-9]{3}` match in gh's stderr) or rc 3 for everything else; only `code_quality` aggregates are kept. The suite's stub emits gh's real stderr shape (`gh: ... (HTTP 403)`).
- Sentinels are full namespaced HTML comments, `<!-- code-quality-followups-watch:<key> -->`, matched with `contains` on the whole string including the closing `-->`; keys are full values (`trigger-2:<40-char sha>`, `trigger-1:v1`), so a short sha or `v10` cannot false-match; a suite row pins a prefix-colliding key. The sentinel is always the exact LAST line of the comment, built only from `printf` constants plus a sha validated `^[0-9a-f]{40}$`, and the suite asserts that no sanitized data string can contain `-->` (security review S2: a title or path echoed into some other bot comment must not be able to forge or pre-spend a sentinel).
- `wn_preflight`: `perl` and `jq` must be present (script 3 needs both for the gate), else rc 3.

### Script 1: `scripts/watch-code-quality-reeval-9730.sh`

Order: xtrace refusal (rc 78) -> earliest gate -> tracker OPEN? -> sentinel present? (`<!-- code-quality-followups-watch:reeval-9730:v1 -->`) -> gather -> compose -> post.

- PR volume per day, 2026-09-01 through today (UTC): `gh api graphql` with aliased `search(type:ISSUE, first:1){issueCount}` fields, opened (`created:DAY`) and merged (`merged:DAY`) per day, in chunks of 20 days (measured: 40 aliases in about 3 s, cost 1) with a short pause between chunks. Every count must be an integer and every day must be present; a secondary-rate-limit or any partial response is rc 3 with nothing posted (retry next week), never a partial result.
- Billing for EVERY month from 2026-09 through the current month (a first post that slips into December still carries November) via `wn_billing_month`: only the `code_quality` product is kept - gross, net, line count, first and last dated line - never other products (a fail-closed allowlist: the org's whole bill is not published on a public issue; security review S4). The product string comes from the ADR-276 prose, so Phase 6 confirms it against the live response; if no `code_quality` line exists the comment says exactly that. Failure classes: 401, 404 and a non-rate-limit 403 mean `unreadable:<status>` (degrade and post); a 5xx, 429, rate-limit 403, network error or unparseable body is rc 3 (retry next Monday - a transient blip must not spend the one-shot with a degraded comment; spec-flow P0). If unreadable: say so, give the three `gh api` commands the ruling session runs with the operator's auth, `::warning::`, continue (exit 0 after posting).
- Comment body: the re-enable criteria quoted from the ADR-276 amendment, the current state (OFF since 2026-10-19), weekly totals and a collapsed per-day list, billing section, and the sentence that no ruling is made here: the next `soleur:go` session has the CTO agent record the keep-off or turn-on ruling from this data and moves the re-evaluation to its successor before closing the tracker. "Nothing was changed" line. Sentinel last.
- `--dry-run` (all three scripts): gather and print the would-be body, skip the earliest gate and the post, never spend a sentinel; a suite scenario per script asserts zero `issue comment` calls. The workflow's `dry_run` dispatch input passes it to all three jobs.

### Script 2: `scripts/watch-lint-ratchet-reeval-10515.sh`

Same order, sentinel `<!-- code-quality-followups-watch:reeval-10515:v1 -->`, earliest 2027-01-18. Data, per CTO ruling F5, window starting 2026-10-19 (PR #10514 merge):

- For each deferred item (six items, with item 4 split into Windows and notebooks as the 2026-10-22 triage comment does, so seven searches), a hardcoded issue/PR search (keywords pointing at that comment), up to 20 hits; item 5 (telemetry) prints a static line "build blocked on `soleur:legal:clo` review" next to its hits, and item 6 searches the single keyword `ever-better` (CTO round 2, R3: a hit on either is a valid flip signal even though building stays blocked); each with number, state, created date, author login, the author's association and an `external` mark when it is not OWNER, MEMBER or a bot. Hits are leads, not verdicts. The tracker itself and #10331 are excluded.
- The sharpened-trigger signals: issues naming `ruff exceeded the total budget` or a ruff timeout from `lint-ratchet.py auto`.
- Code Quality state: the expense-ledger line for "GitHub Code Quality" and the ADR-276 amendment heading, both printed verbatim, not parsed (checked: the ledger row holds amounts, status and dates only - no account ID or invoice number; the suite pins that the printed line matches `^\\| GitHub Code Quality`); `code_quality` billing lines dated after 2026-10-19 only when billing is readable.
- Commits touching `plugins/soleur/scripts/lint-ratchet.py` since 2026-10-19 (`git log --first-parent`, sanitized subjects).
- The sentence that the next `soleur:go` session has the CTO agent apply the flip condition to this data. Search failure: rc 3, nothing posted.

### Script 3: `scripts/watch-brand-hex-triggers-11177.sh`

Runs every Monday; posts only when a trigger fires; never touches the issue otherwise.

- Trigger 1 (a third hook sourcing the simulated index): tracked `.claude/hooks/*.sh` and any existing `plugins/**/hooks/*.sh`, excluding `lib/` and `*.test.sh`, minus `git-commit-secret-scan.sh` and `brand-hex-commit-gate.sh`; a non-comment line naming `commit-index-sim`. Notify once (`trigger-1:v1`).
- Trigger 2 (an off-brand colour reached main): first-parent commits on the default branch, window = since the tracker's `createdAt`, capped at the newest 200 first-parent commits that touch the gate's path classes (CTO round 2, R1: a fixed 9-day cap would slide a commit out after two consecutive exit-3 runs, and notify-once makes re-examination free); when the cap truncates, print `examined=N truncated=1` plus a `::warning::` and exit 0. For each commit, run the real gate in ONE `git worktree add --no-checkout --detach` reused for the whole loop with one cleanup trap (`git worktree remove --force` plus `rm -rf`): per commit `git reset --mixed -q <first-parent>` then `git read-tree <commit>` into that worktree's own index (the gate unsets `GIT_INDEX_FILE`, so an env-var index would be ignored), a plain `git commit -m x` payload on stdin, `CLAUDE_PROJECT_DIR` pointed at an empty directory so no incident ledger is written, the call wrapped in `timeout -k 5 60`. A `deny` is a finding. The sentinel is checked BEFORE judging each commit (`trigger-2:<sha>` and `trigger-2-unjudgeable:<sha>`), so a sentineled commit is never re-run through the gate. For ONE commit, exit 124/137, a non-`allow`/`deny` result or a stderr `WARN` is an "unjudgeable commit" (own sentinel `trigger-2-unjudgeable:<sha>`, commit skipped, loop continues; the comment says "could not be judged by the gate (timeout or unusable output)", never "off-brand colour"); it is never an allow. Systemic failure stays rc 3: preflight (hook file, perl, jq, readable history) before the loop, or the first three judged commits all unjudgeable. A total loop budget of 600 s (job `timeout-minutes: 15` leaves the rest for checkout and the post) truncates like the 200-cap: `examined=N truncated=1 budget=1`, `::warning::`, exit 0; newest-first order can starve the oldest clean commits, a documented residual with no watermark (CTO round 3, S1). The 60 s value is a starting point: Phase 6 measures the real per-commit time and sets the timeout at about 10 times the worst case seen. Fallback only if this proves infeasible at /work: extract `UI_RE`/`EMAIL_RE`/`COLOR_RE` from the hook source with a parity test that fails when they move.
- Notify once per finding (`trigger-2:<sha>`); one comment lists only new findings (summary above 10). The comment states that the route cannot be inferred from main: a chained add-then-commit, a `--no-verify` commit and a human commit look alike, so it is a lead for the ruling session.
- Tracker CLOSED: `::notice::`, exit 0. A tracker that no longer resolves (gh error text "Could not resolve to an issue" or `HTTP 404/410`) is a terminal `::notice::tracker gone, nothing to watch`, exit 0; any other or unrecognised read error stays rc 3 (CTO round 3, S2). `--dry-run`: runs both detectors and prints the would-be comment without posting or spending a sentinel. `--print-state`: local git only, prints `watch=brand-hex-11177 mode=print-state`, the trigger-1 hook list and the trigger-2 candidate-commit count; this is the discoverability probe.

### Exit codes (all three)

0 posted, or any no-op (before the date, tracker not open, already notified, no trigger); 1 comment post failed; 2 usage; 3 cannot establish (a read the verdict depends on failed; nothing posted, so the next run retries); 78 refusing to run under xtrace. A red run is the failure signal: the Actions tab and GitHub's failure email, as for the precedent watcher.

## Technical Considerations

- **No scheduler substrate change.** `*-watch.yml` is the existing repo-scoped, secret-free exception (precedent PR #9660). No Sentry cron monitor, no Inngest registration, no `EXPECTED_CRON_FUNCTIONS` row (the precedent added none).
- **Sentinels live in comments the workflow itself posts**, so HTML-comment sentinels survive (the sweeper's output sanitiser, which neutralises them, is not on this path).
- **Public surface.** The comments land on a public repository's issues: aggregates only for billing (no SKU entitlements, invoices or account identifiers); third-party titles are sanitized; mentions neutralised so a title cannot notify anyone.
- **Test-suite registration** follows the registry rules: explicit `run_suite` lines appended last in the `want_scripts` block (the file notes `scripts/*.test.sh` is not auto-globbed); TSV rows inserted alphabetically at floor weight, headers untouched.
- **gh stub fidelity.** The suites' fake `gh` whitelists real flags only (learning 2026-09-25: a stub that accepts invented flags makes dead code look green).
- **grep-q-pipe-guard.** No `cmd | grep -q` under `pipefail`; use herestrings or `grep -q` on files (`bash .claude/hooks/grep-q-pipe-guard.test.sh` is in the repo-global list).
- **Header notes the workflow carries (spec-flow P2).** A human-deleted or edited bot comment means the next Monday re-posts once (acceptable); a tracker closed then reopened resumes and reads its sentinel correctly; `gh issue view --json comments` returns every page of comments (measured in the convention's Paging note), so a long thread cannot hide a sentinel.
- **Date arithmetic.** `earliest` constants are ISO-8601 `Z` strings validated `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`; epoch values validated `^[1-9][0-9]{0,15}$` before arithmetic (a leading zero is octal in bash).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing; the failure is a missing or duplicated comment on an internal tracker, or a red weekly run.

**If this leaks, the user's data is exposed via:** a public issue comment on the public repository. Mitigations: billing is posted as aggregates only (the operator already posts these figures on the same trackers), third-party titles and logins are public GitHub data re-shown on GitHub and are sanitized, and no secret is read or written (the workflow's token is the default Actions token, `issues: write`).

**Brand-survival threshold:** none. The change touches no path matched by the canonical sensitive-path regex (`code-quality-followups-watch.yml` carries none of the credential/deploy/release words; nothing under `apps/`).

## Observability

```yaml
liveness_signal:
  what: the weekly Monday run of code-quality-followups-watch.yml (three jobs); a no-op is a green run with a ::notice:: line naming why
  cadence: weekly (cron '17 9 * * 1')
  alert_target: a red run -> the Actions tab and GitHub's default failure email (same stance as registration-narrowing-watch.yml); the data/trigger comment itself is the success signal on the tracker
  configured_in: .github/workflows/code-quality-followups-watch.yml
error_reporting:
  destination: GitHub Actions run annotations (::error:: / ::warning::) and the job log
  fail_loud: exit 3 when a read the verdict depends on fails (nothing posted, so the next run retries); exit 1 when the post fails; a billing-unreadable result is a ::warning:: and is stated in the comment
failure_modes:
  - mode: PR-volume or issue-search read fails
    detection: script exits 3 with ::error::
    alert_route: red weekly run
  - mode: comment post fails
    detection: script exits 1 with ::error::; no sentinel written, so the next run retries
    alert_route: red weekly run
  - mode: the brand-hex gate cannot be run or returns malformed output
    detection: script exits 3 (never reads as "no trigger")
    alert_route: red weekly run
  - mode: workflow never runs (cron not registered, or default-branch guard skips every run)
    detection: post-merge `gh workflow list` shows the workflow, and a dry-run dispatch on main completes
    alert_route: the post-merge verification in this plan
logs:
  where: GitHub Actions run logs and the job step summary
  retention: GitHub default (90 days)
discoverability_test:
  command: bash scripts/watch-brand-hex-triggers-11177.sh --print-state
  expected_output: mode=print-state
```

## Task Design

```yaml
tasks:
  - task: code-quality-reeval-9730-watch
    trigger: cron weekly Mondays 09:17 UTC, plus workflow_dispatch (dry_run input); runs on main only
    services: reads GitHub GraphQL search and the org billing usage endpoint; writes one issue comment on #9730
    next: nothing; the next soleur:go session reads the comment and has the CTO agent record the ruling
    human_reentry: stop by deleting the workflow job and script (RETIREMENT block in the workflow header); closing #9730 makes every later run a no-op
    dedupe: bot-authored sentinel comment `code-quality-followups-watch:reeval-9730:v1` checked before any gather (beyond concurrency group); a human-pasted sentinel never suppresses
    source_dedupe: not a ticket source
  - task: lint-ratchet-reeval-10515-watch
    trigger: same workflow, own job; earliest 2027-01-18 constant
    services: reads GitHub GraphQL search, the git history of the checkout, the expense ledger and ADR-276 files; writes one issue comment on #10515
    next: nothing; the ruling session applies the flip condition
    human_reentry: same as above; closing #10515 makes later runs no-ops
    dedupe: bot-authored sentinel comment `code-quality-followups-watch:reeval-10515:v1`
    source_dedupe: not a ticket source
  - task: brand-hex-triggers-11177-watch
    trigger: same workflow, own job, every Monday
    services: reads the checkout's git history and hook files, runs the committed brand-hex gate in a throwaway worktree; writes an issue comment on #11177 only when a trigger fires
    next: nothing; a fired trigger tells the next session to pick up the #11177 scope
    human_reentry: close #11177 or delete the job; the retirement list is in the workflow header
    dedupe: per-finding bot-authored sentinels `trigger-1:v1` and `trigger-2:<sha>`; one comment lists only findings not yet sentineled
    source_dedupe: not a ticket source
```

## Architecture Decision (ADR/C4)

No new architectural decision. The mechanism is the existing repo-scoped watcher pattern (precedent PR #9660, `codeql-1537-revisit-watch.yml`), ADR-033's scheduling-substrate rule is not reversed, and no future engineer reading ADR-033 and the C4 views would be misled. C4 check: no external actor, vendor, data store or access relationship is added (the watchers call the GitHub API the platform already uses, with the default token). Derived cardinalities are the exception to the actor rubric: `plugins/soleur/test/c4-count-parity.test.sh` MUST be run green at /work because a new workflow can move a count that `model.c4` embeds.

## Guard Contract

### Guard 1 — Read-only, notify-only write set

**Property.** None of the three scripts, the shared library or the workflow can close, reopen, edit, label or otherwise mutate a tracker, change a repository setting, or enable Code Quality; the only GitHub write is `gh issue comment` on the script's own tracker.

**Assembly.** Every `gh` invocation in `scripts/lib/watch-notify-once.sh` and the three `scripts/watch-*.sh`, every `run:` step and `permissions:` block in the workflow, and every HTTP verb passed to `gh api`. Chokepoint: reads go through the stubbed `gh` and writes through the single `wn_post`; the suite asserts the recorded argv set, not a list of call sites, and a static census greps all four files for forbidden verbs (`issue close|reopen|edit|delete|lock`, `label`, `pr merge`, `repo edit`, `api -X (POST|PATCH|PUT|DELETE)` and `--method` forms).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `gh issue close "$N"` after the post in script 1 | RED (recorded argv set contains a verb outside {issue view, issue comment, api GET, api graphql}) |
| 2 | Make the stub `gh` log nothing (the recording dispatch is dead) | RED (the suite's call-count floor: at least one recorded read and one recorded comment per posting scenario) |
| 3 | Add `gh issue edit --add-label` to script 3 only, after a compliant script 1 and 2 | RED (census covers all three scripts and the lib, not the first) |
| 4 | Change `permissions:` to add `contents: write` (or `pull-requests: write`) in the workflow | RED (workflow facet asserts the exact permission set) |
| 5 | A `gh api graphql -f query='mutation{...}'` call in script 2 | RED (the stub rejects any GraphQL body containing `mutation`, and the census greps for it) |
| 6 | A non-GraphQL `gh api` call carrying `-f`/`-F`/`--field`/`--raw-field` (flips a GET to a POST) | RED (stub and census both reject the flags) |

**Harness rows.** Drop the forbidden-verb census (delete the loop body) -> the suite must go RED on its own self-test; a must-PASS input that is not the canonical: a script variant that adds a read-only `gh api graphql` query call must stay GREEN. (CTO round 2, R5: keep ONE census, in script 1's suite only, written as an allowlist: every `gh issue` subcommand is `view` or `comment`; every `gh api` call is GET-shaped, with no `-X`/`--method` other than GET, no `-f/-F/--field/--raw-field/--input`, and no `mutation` in a GraphQL body; any `gh` noun other than `issue` and `api` is rejected; it spans the lib, the three scripts and the workflow text, and has a self-test row. The recorded-argv oracle stays in every suite. Retirement note: when script 1 is deleted, move the census to the next surviving suite.)

**Anchor.** The recorded-argv oracle is the stub itself. `permissions:` is an independent anchor only for scopes other than issues: `issues: write` still lets a token close, edit and label issues, so the read-only-on-issues property rests on the argv oracle and the census; GitHub enforces the block for contents, pull-requests and administration whatever the script says.

### Guard 2 — Notify-once with bot-only sentinel

**Property.** For a given tracker and finding key, a second run posts nothing, and a sentinel pasted by a human never suppresses the real notice.

**Assembly.** The single `wn_sentinel_present` reader and the single `wn_post` writer, used by all three scripts; the comment author field is the anchor (a GitHub-side fact a commit cannot forge). Per-finding keys (`trigger-2:<sha>`) are compared as a set, not by count.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the sentinel check in script 1 | RED (second run in the suite posts again) |
| 2 | Accept any author in `wn_sentinel_present` | RED (human-sentinel scenario posts nothing) |
| 3 | Script 3: a bot comment holds `trigger-2:<shaA>`; a new commit `<shaB>` offends | RED if `<shaB>` is not posted (a check that stops at the first sentinel is the defect) |
| 4 | Make the reader treat a jq failure as "absent" | RED (malformed-comments scenario must exit 3, not post) |
| 5 | Dispatch: run script 1 with a stub that returns an empty comment list and `state=OPEN` before the date | RED if it posts (earliest gate precedes everything) |

**Harness rows.** Remove the `wn_post` call: the suite's posting scenarios must go RED (a suite that only asserts "no second post" passes with no first post); must-PASS non-canonical: sentinel from `github-actions[bot]` (REST spelling) suppresses as well as `github-actions`.

**Anchor.** Comment authorship (`github-actions`), set by GitHub, not by the commit.

### Guard 3 — Trigger 1 detector scope

**Property.** Trigger 1 fires if and only if a tracked hook other than `git-commit-secret-scan.sh` and `brand-hex-commit-gate.sh` has a non-comment line naming `commit-index-sim`.

**Assembly.** The tracked hook population: `.claude/hooks/*.sh` and `plugins/**/hooks/*.sh`, minus `lib/` and `*.test.sh`; the comment-stripping applied to every candidate; the two named exclusions. Chokepoint: one `git ls-files` listing plus one filter.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture: add `.claude/hooks/new-hook.sh` with `. "$cis_lib"` where `cis_lib=.../commit-index-sim.sh` | RED if the watcher does not fire |
| 2 | Fixture: the file names the lib only in a whole-line comment | RED if it fires (precision) |
| 3 | Fixture: the brand-hex gate itself sources the lib (the fix landing) | RED if it fires |
| 4 | Fixture: a second extra hook in `plugins/x/hooks/` after a compliant first | RED if only the first is listed |
| 5 | Fixture with zero tracked hooks (listing empty) | RED if exit 0 "clean": exit 3 "cannot establish" |

**Harness rows.** Empty the exclusion list: row 3 must go RED; must-PASS non-canonical: a `.test.sh` naming the lib and a file under `lib/` stay silent.

**Anchor.** The tracked file set at the default branch HEAD, read with `git ls-files`, not the working tree.

### Guard 4 — Trigger 2 detector runs the real gate

**Property.** Every first-parent commit on main inside the window that touches the gate's path classes is judged by the committed brand-hex gate itself, and a `deny` is reported; an unusable gate result is never read as "clean".

**Assembly.** The commit listing (since the tracker's createdAt, newest 200 path-class-touching first-parent commits), the single reused worktree with its per-commit reset and read-tree, and the gate invocation; all go through one `judge_commit` function. The gate output classifier accepts only `allow` or `deny` JSON.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture commit adds `color: "#ff00aa"` in `apps/web-platform/app/x.tsx` | RED if no finding |
| 2 | Fixture commit adds a token reference only (`var(--soleur-x)`) | RED if a finding (precision) |
| 3 | Window dispatch: all fixture commits older than the window | RED if the watcher reports "clean" with 0 commits examined and exits 0 without printing `examined=0` (a vacuous clean) |
| 4 | Two offending commits, the second after a compliant first | RED if only one is reported |
| 5 | Stub the gate to print garbage / the gate prints a stderr `WARN` | RED if exit is not 3 |
| 6 | Email-class file adds an off-palette hex vs a palette hex | RED if off-palette is not flagged or the palette hex is |
| 7 | Skip the per-iteration `reset --mixed` + `read-tree` in the reused worktree; an offending commit is followed by a clean one | RED (stale index state would carry the first verdict into the second) |
| 8 | Gate wrapper returns exit 124 (timeout) or a stderr `WARN` for ONE commit, with later commits clean/offending | RED unless that commit is reported unjudgeable (once, sentineled, never "off-brand"), the loop continues, and the next week's run does not re-run it through the gate |
| 9 | The first three judged commits are all unjudgeable, or preflight finds no `perl` / no hook file | RED unless exit 3 |

**Harness rows.** Remove the worktree `read-tree` step: row 1 must go RED (the gate sees an empty index and allows everything, which is exactly the vacuity to catch); must-PASS non-canonical: a commit touching only files outside the path classes is skipped without running the gate.

**Anchor.** The gate file at HEAD of main is the classifier, so a gate change moves the verdict with it; the suite copies the real gate into its fixture repo, so a gate rewrite that breaks the invocation contract (the `unset GIT_INDEX_FILE`, the JSON shape) reds the suite.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Wire autonomous start for the date-gated and event-gated code-quality follow-ups, using the existing follow-through machinery (scheduled-followthrough-sweeper.yml, the `<!-- soleur:followthrough script=… earliest=… -->` directive, committed scripts under scripts/followthroughs/" [brief] | Workflow + three watch scripts (existing watcher machinery per the convention) | mapped; the directive/`scripts/followthroughs/` vehicle is replaced per CTO F2 |
| 2 | "a committed followthrough script that, once earliest=2026-11-14 passes, pulls billing for Sep, Oct and Nov-to-date plus PR volume per day, and posts that data as a comment on #9730" [brief] | Script 1 | mapped |
| 3 | "Add the followthrough directive to #9730 with earliest=2026-11-14" [brief] | — | descoped — justification: the sweeper would comment daily with no dedup and exit 0 closes the tracker; CTO ruling F2 chose a dedicated watch workflow with the date as a script constant; reversible |
| 4 | "Determine whether the sweeper can invoke a Soleur skill or agent so the CTO agent (soleur:engineering:cto) records the keep-off or turn-on ruling; if it cannot, the script posts data only and the issue states that the next soleur:go session records the ruling." [brief] | Ruling F1 and the data comment's closing paragraph | mapped |
| 5 | "Do not turn Code Quality on or change any repository setting." [brief] | Guard 1; P4 | mapped |
| 6 | "Open issue #10515 (lint ratchet re-evaluation, due on or after 2027-01-18): same pattern, script gathers the data the re-evaluation needs, directive with earliest=2027-01-18." [brief] | Script 2 (directive part descoped as ask 3) | mapped |
| 7 | "a weekly check script that tests the two \"re-evaluate when\" triggers in the issue body ... and comments on the issue only when a trigger fires." [brief] | Script 3 | mapped |
| 8 | "Do not implement the #11177 fix itself." [brief] | Non-goal; Guard 3 row 3 | mapped |
| 9 | "Leave the worktree-reaping tracker alone." [brief] | No file or issue touches it | mapped |
| 10 | "these issues must stay OPEN, so PR body uses `Ref #9730`, ... with no closing keyword" and the `10331` Ref line [brief] | Overview PR-body reminder; ship checklist | mapped |
| 11 | "Scripts must be non-destructive, read-only apart from issue comments, and use no real credentials in fixtures (synthesized shapes built by concatenation)." [brief] | Guard 1; test fixtures | mapped |
| 12 | "Run the repo-global checks a file-selected suite cannot see (...)" [brief] | Acceptance Criteria, pre-merge | mapped |
| 13 | "Run soleur:ship and soleur:postmerge to completion. If the PR is BEHIND with auto-merge armed, wait for the merge queue via Monitor, do not re-sync by hand." [brief] | Phase 6 and post-merge section | mapped |
| 14 | "check for overlap/conflict at plan time and keep your edits to that runbook minimal or avoid it" [brief] | F6: runbook unedited | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/code-quality-followups-watch.yml` | "wire autonomous start" (asks 1, 2, 6, 7) | asked |
| `scripts/watch-code-quality-reeval-9730.sh` + test | "pulls billing for Sep, Oct and Nov-to-date plus PR volume per day" | asked |
| `scripts/watch-lint-ratchet-reeval-10515.sh` + test | "script gathers the data the re-evaluation needs" | asked |
| `scripts/watch-brand-hex-triggers-11177.sh` + test | "a weekly check script that tests the two \"re-evaluate when\" triggers" | asked |
| `scripts/lib/watch-notify-once.sh` | — | inferred — justification: the three scripts share sentinel, issue-read, post, sanitize and billing logic; one reviewed copy instead of three drifting ones (the suites exercise it through all three) |
| `--dry-run` / `dry_run` dispatch input | "Determine whether the sweeper can invoke..." (measure, do not assume) | inferred — justification: the Actions token's billing status is an expectation until measured; the dry-run is the only way to measure it before 2026-11-14 |
| `run_suite` lines and TSV rows | "Run the repo-global checks a file-selected suite cannot see" | asked |
| Post-merge pointer comments on #9730 and #10515 | "the issue states that the next soleur:go session records the ruling" | asked |

### Split Assessment

- Subsystems touched: 3 — `.github/workflows`, `scripts`, `knowledge-base/project/{plans,specs}`
- Planned files: 14 created or edited (12 code and registry files, 2 planning artifacts) | Estimated changed lines: about 1,900 (about 1,300 are the three test suites; the library is exercised through them and has no suite of its own)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the brief asks for one PR; the three watchers share one workflow and one library, so a split would triple the registry-conflict surface with #11154 and leave a library without its consumers; the line count is dominated by mutation-proven test suites (precedent PR #9660: 1,041 insertions in one PR).

## Open Code-Review Overlap

- #7942 (two mutation batteries named `*.mutation.sh` run in no gate) names `scripts/test-all.sh`. Acknowledge: a different concern (unregistered mutation batteries); this plan only appends registered `run_suite` lines. The issue stays open.
- #10462, #10463, #10464, #8800, #8435 name `scripts/followthroughs/` probes. Acknowledge: none of them touches a file this plan edits; no probe is added there.
- No open code-review issue names `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, the brand-hex gate, `commit-index-sim.sh` or the sweeper.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled every technical fork at plan time (`knowledge-base/project/specs/feat-one-shot-autonomous-start-followthroughs/decision-challenges.md`, F1 to F6): dedicated weekly watch workflow instead of the sweeper directive, no new billing credential, trigger semantics and gate-reuse for #11177, data scope for #10515, and the registry-footprint plan against #11154. Finance (CFO) is not relevant: the plan reads billing but books nothing and changes no ledger row; Legal (CLO): no personal data is processed beyond public GitHub logins re-shown on GitHub. No Product/UX surface: no user-facing page or component is created or changed.

## Files to Create

- `.github/workflows/code-quality-followups-watch.yml`
- `scripts/lib/watch-notify-once.sh`
- `scripts/watch-code-quality-reeval-9730.sh`, `scripts/watch-code-quality-reeval-9730.test.sh`
- `scripts/watch-lint-ratchet-reeval-10515.sh`, `scripts/watch-lint-ratchet-reeval-10515.test.sh`
- `scripts/watch-brand-hex-triggers-11177.sh`, `scripts/watch-brand-hex-triggers-11177.test.sh`
- `knowledge-base/project/specs/feat-one-shot-autonomous-start-followthroughs/{decision-challenges.md,tasks.md}` (planning artifacts)

## Files to Edit

- `scripts/test-all.sh` — three `run_suite` lines appended last in the `want_scripts` block (expect a union-resolve if #11154 merges first).
- `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` — three rows each, inserted alphabetically at floor weight (1200 ms) and leg 1, `generated-at` headers untouched.

Deliberately NOT edited: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`, `scripts/sweep-followthroughs.sh`, `.github/workflows/scheduled-followthrough-sweeper.yml`, `tests/scripts/test-argv-bearer-sweep.sh`, `plugins/soleur/skills/work/SKILL.md`, and anything about the worktree-reaping tracker.

## Implementation Phases

Phase 1 — RED tests first (cq-write-failing-tests-before). Write the three suites against the not-yet-existing scripts: stub `gh` whitelisting real flags and logging argv; fixture repo for script 3 that copies the real gate and its libs; synthesized fixtures only (any token-shaped string built by concatenation); instrument self-test and `finish || exit 1` as the last line, as in the precedent suite. Confirm each fails for the right reason.

Phase 2 — `scripts/lib/watch-notify-once.sh`.

Phase 3 — Script 1, then script 2, then script 3 (smallest blast radius first; script 3 last because of the worktree and gate mechanics). After each, its suite goes green.

Phase 4 — The workflow (three jobs, `if: github.ref_name == github.event.repository.default_branch` (a default-branch rename must not turn every run into a green skip), actions pinned by full 40-char SHA exactly as the precedent pins `actions/checkout`, workflow-level `permissions: {}` with the grants on each job (`contents: read`, `issues: write`), `dry_run` passed through `env:` and never interpolated inline in `run:`, `concurrency: group: code-quality-followups-watch, cancel-in-progress: false`, `persist-credentials: false`, `fetch-depth: 1` for job 1 (no history needed) and `fetch-depth: 0` for jobs 2 and 3 (git log, the gate worktrees), `dry_run` dispatch input passed as `--dry-run` to all three jobs, header with purpose, noise rationale, self-disable, RETIREMENT list: workflow, three scripts and suites, lib, the `run_suite` lines, the TSV rows).

Phase 5 — Registry edits (`test-all.sh`, both TSVs); run `scripts-shard-manifest`, totality and runtime-coverage suites.

Phase 6 — Live read-only dry runs from the worktree (script 3's dry run is also the first-run-flood check: whatever it would post for commits already on main is reviewed BEFORE merge, so the first real Monday run does not alarm the tracker with known history; every GraphQL search string hardcodes `repo:jikig-ai/soleur` and built-in keywords only, with no third-party text interpolated into a query): each script with `--dry-run` against real GitHub using the operator's auth (billing readable locally, so the "readable" branch is exercised for real), compare the PR-volume totals to an independent `gh api` count, keep the output out of the repo. Run the repo-global checks (see Acceptance Criteria). Commit, `soleur:review`, `soleur:ship`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `bash scripts/watch-code-quality-reeval-9730.test.sh`, `...10515.test.sh` and `...11177.test.sh` exit 0, each ending in the `finish || exit 1` gate, with the mutation rows of Guards 1 to 4 each shown RED against a mutated copy.
- [ ] AC2: Script 1 posts nothing before 2026-11-14T00:00:00Z, posts once after it, and a second run finds the bot sentinel and posts nothing; billing unreadable (stub 403) still posts PR volume, states the limitation and exits 0; PR-volume failure exits 3 with no post.
- [ ] AC3: Script 2 behaves the same around 2027-01-18T00:00:00Z; third-party titles in the posted body are code-spanned with `@`, `<`, `>`, backtick and `&` neutralised, never a body excerpt.
- [ ] AC4: Script 3 posts nothing when neither trigger fires, posts one comment with only the new findings when one does, never posts for a human-pasted sentinel, treats a CLOSED tracker as a no-op, and exits 3 when the gate output is unusable.
- [ ] AC5: The recorded `gh` argv of every scenario in all three suites is a subset of {`issue view`, `issue comment`, `api` GET/GraphQL}; the static census finds no forbidden verb in the lib, scripts or workflow; `permissions:` is exactly `contents: read` and `issues: write`.
- [ ] AC6: Live dry runs (`--dry-run`, operator auth) for scripts 1 and 2 print a well-formed body; script 1's per-day PR totals equal an independent `gh api` count for the same window; the printed body contains no `@` mention and no closing keyword.
- [ ] AC7: `bash scripts/watch-brand-hex-triggers-11177.sh --print-state` exits 0 and prints `watch=brand-hex-11177 mode=print-state` within 15 s without network.
- [ ] AC8: Repo-global checks green: `bash scripts/check-adr-ordinals.sh`; `bash plugins/soleur/test/boundary-prefix.test.sh`; `python3 -I scripts/ci-pr-affected-replay.py ratchet`; `bash .claude/hooks/grep-q-pipe-guard.test.sh`; `bash scripts/guard-vacuity-floor.test.sh`; `bash plugins/soleur/skills/verification-scaffold/test/manifest.test.sh`; plus `bash plugins/soleur/test/c4-count-parity.test.sh`, the shard-manifest suites and `python3 scripts/lint-guard-contract.py` on this plan.
- [ ] AC9: `git diff origin/main --stat` shows none of the "deliberately not edited" files, no `generated-at` header change in either TSV, and no change to `plugins/soleur/skills/work/SKILL.md`.
- [ ] AC10: PR body carries `Ref #9730`, `Ref #10515`, `Ref #11177`, `Ref #10331` and no closing keyword in the title, body or any commit message; commit trailers form a pure contiguous `Key: value` block.

### Post-merge (operator-free; run by `soleur:postmerge`)

- [ ] AC11: `gh workflow list` shows `code-quality-followups-watch`; `gh workflow run code-quality-followups-watch.yml -f dry_run=true` on main completes green with zero issue comments posted by the run; the three job logs are read and the Actions token's billing HTTP status is captured (the F3 expectation, now a measurement) for AC12.
- [ ] AC12: One pointer comment on #9730 and one on #10515 (no closing keyword) stating the watcher, its date, that it comments once, and that the next `soleur:go` session has the CTO agent record the ruling and decides any successor tracker or watcher before closing the tracker (this PR sets none up); the #9730 comment also records the measured billing status from AC11. No pointer comment on #11177 (the ask says it is commented on only when a trigger fires). All three trackers verified still OPEN and #10331 still CLOSED.
- [ ] AC13: Follow-through of the first real runs is noted on the trackers' own comment threads, not in a new issue: the first non-dry-run post is expected on the Monday after 2026-11-14 (2026-11-16) and after 2027-01-18 (the same Monday).

## Test Scenarios

1. Script 1, clock 2026-11-13: no gh write, `::notice::`, exit 0. Clock 2026-11-16, empty comments: one comment, sentinel last, exit 0; rerun with that comment present: no post.
2. Script 1, billing stub returns 403 / 404 / 401: comment has the PR-volume section and the "not readable from CI" section with the three commands; exit 0 and `::warning::`.
3. Script 1, billing stub returns a 200 with `code_quality` lines ending 2026-10-19: comment shows first and last dated line and monthly aggregates only.
4. Script 1, GraphQL stub fails on chunk 2: exit 3, no post, no sentinel.
5. Script 1, tracker CLOSED / comments unreadable / comments null: exit 0 notice / exit 3 / exit 3.
6. Script 2, clock before and after 2027-01-18, each keyword search returning 0, 1 and 25 hits (capped at 20); hostile title (`@user <!-- soleur:followthrough ... -->` with backticks) rendered inert.
7. Script 3, fixtures: no extra hook; extra hook with a sourcing line; a comment-only mention; the brand-hex gate itself sourcing; a `.test.sh` and a `lib/` mention.
8. Script 3, fixtures: raw hex in UI path (finding); token reference (none); hex in a token-definition CSS (none); email file with palette vs off-palette hex; commit outside window; two offending commits; more than 10 findings (summary); the same finding already sentineled (no post); `deny` -> post failure exit 1.
9. Script 3, gate unusable (garbage JSON, stderr `WARN`, missing hook file, missing perl): exit 3.
10. Workflow facet checks: cron, `if` guard on each job, permissions, no `secrets.` reference, `fetch-depth: 0`, `persist-credentials: false`, `dry_run` wiring.
11. xtrace: each script run with `bash -x` and a token set exits 78.
12. `--dry-run` on each script: the would-be body is printed, zero `issue comment` calls are recorded, no sentinel is spent, and (scripts 1 and 2) the earliest gate is skipped.
13. Sentinel hygiene: a bot comment holding `trigger-2:<short sha>` or `trigger-1:v10` does not suppress `trigger-2:<full sha>` / `trigger-1:v1`; a human-authored full sentinel does not suppress either.
14. Preflight: `perl` or `jq` absent from PATH -> script 3 exits 3. Reused-worktree loop: an offending commit followed by a clean one reports exactly the first; a truncated window (more than 200 commits) prints `examined=200 truncated=1` and exits 0.

## Risks

- **Residual: a disabled or never-run workflow is visible only as a missing or red run.** GitHub disables scheduled workflows after 60 days of repo inactivity and a persistent exit 3 shows only as a red run; the CTO (round 3, S2) rejected a sweeper dead-man (it would recreate the daily noise) and an in-script "cannot establish" notice (it depends on the same failing read); the post-merge check is `gh workflow list` plus the `dry_run` dispatch, and the repo commits daily. Recorded in the workflow header.

- **Actions token cannot read org billing (expected).** Handled by design (F3) and measured post-merge (AC11). If it turns out readable, nothing else changes.
- **Union-resolve with #11154** in `test-all.sh` and both TSVs. Mitigation: rows inserted alphabetically, headers untouched, the conflict is two sides of an additive list; re-run the registry checks after any resolve. Do not re-sync by hand when BEHIND with auto-merge armed: wait for the merge queue via Monitor.
- **Running the real gate per commit** is slower and more intricate than a regex. Mitigation: only commits touching the gate's path classes, newest-200 cap since the tracker's creation, one reused `--no-checkout` worktree, a `timeout -k 5 60` per commit (measured at Phase 6), cleanup trap, job `timeout-minutes: 15`; fallback (regex extraction with a parity test) is pre-ruled.
- **Search-keyword noise for #10515.** Leads only, capped, external-marked; the ruling session judges.
- **Weekly cadence means up to 7 days between the date and the post** (first post 2026-11-16 for #9730, the same day as the date for #10515 because 2027-01-18 is a Monday). Accepted.
- **Workflow-only failure signal is a red run.** Same stance as the precedent; no new alarm.

## References

- Precedent: `.github/workflows/registration-narrowing-watch.yml`, `scripts/watch-registration-narrowing-9564.sh` and `.test.sh` (PR #9660); `codeql-1537-revisit-watch.yml`
- Convention and sweeper: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`, `scripts/sweep-followthroughs.sh`, `.github/workflows/scheduled-followthrough-sweeper.yml`
- ADR-276 amendments (2026-10-19, 2026-10-22), ADR-301 (`commit-index-sim.sh`), ADR-033
- Gate under watch: `.claude/hooks/brand-hex-commit-gate.sh`, `.claude/hooks/git-commit-secret-scan.sh`, `.claude/hooks/lib/commit-index-sim.sh`
- Learnings: 2026-10-07 watcher-suite shape sampling; 2026-09-25 gh stub must mirror real CLI flags; 2026-06-05 prose `closes` keyword auto-closes a tracker; 2026-10-19 vendor-state and billing premise; 2026-10-26 fail-open fallback regex
