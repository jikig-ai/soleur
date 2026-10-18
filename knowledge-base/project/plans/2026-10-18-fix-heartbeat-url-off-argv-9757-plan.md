---
title: "fix: heartbeat-URL path secrets off argv: verified closeout (umbrella 9757)"
type: fix
date: 2026-10-18
slug: heartbeat-url-off-argv-9757
branch: feat-one-shot-9757-heartbeat-url-off-argv
issue: 9757
closes: none
lane: cross-domain
brand_survival_threshold: none
---

# fix: heartbeat-URL path secrets off argv: verified closeout (Ref #9757)

## Overview

Spec lacks valid lane: defaulted to cross-domain (fail-closed); no spec.md exists for this one-shot branch.

The brief asked for the "Heartbeat-URL path secrets" item of umbrella #9757 to be implemented: move the
Better Stack heartbeat URL (its path is the credential) off curl's argument list in
`apps/web-platform/infra/inngest-bootstrap.sh`, `web-git-data-probe.sh` and `luks-monitor.sh`, by sending it
as a `url = "..."` line on curl's stdin config behind a shape guard.

**That work is already on main.** Premise validation (below) found all three transport lines merged and
guarded by the S6-HB stage of `tests/scripts/test-argv-bearer-sweep.sh` with an empty allowlist. The
umbrella item is still unticked only because its last status note carried a reason that is stale as to code.
So the deliverable of this branch is a **verified closeout with no code change**: carry the evidence in a
knowledge-base-only PR that triggers no infrastructure apply, and, after that PR merges, tick the item
scoped to "transport (argv)" and name the one unverified delivery (luks) as an explicit residual on #10093.

Ruled by CTO agent, 2026-10-18: option A (knowledge-base-only closeout); the evidence bar, sequencing and
umbrella-edit guard below are also CTO rulings, recorded in
`knowledge-base/project/specs/feat-one-shot-9757-heartbeat-url-off-argv/decision-challenges.md`.

**The operator sees a documentation-only PR where the brief said "Implement the next fix PR".** The PR body
must open with that fact and the reason (the fix is already merged), and ask for merge approval naming
PR #10504.

## Research Reconciliation: Spec vs. Codebase

| Brief / umbrella claim | Reality on origin/main (840dc667fc) | Plan response |
|---|---|---|
| `inngest-bootstrap.sh` still puts the heartbeat URL on curl argv | Converted by PR #10356 (merged 2026-10-15): the heartbeat heredoc body ends in a `printf 'url = "%s"\n' "$INNGEST_HEARTBEAT_URL" \| /usr/bin/curl --disable --noproxy '*' -gfsS --max-time 10 --config -` line, behind a negated allow-class shape guard. #10120 closed 2026-10-18 | No edit; cite the PR and the content anchor |
| `web-git-data-probe.sh` still on argv | Converted by PR #10086 (merged 2026-10-12): `_hb_url_ok` guard and `_hb_curl()` with a process-substitution stdin config | No edit |
| `luks-monitor.sh` still on argv | Converted by PR #10086: `hb_url_ok` guard, three-attempt loop with `--config - < <(printf 'url = "%s"\n' "$hb_url")` | No edit; delivery caveat recorded as a residual |
| Umbrella note (2026-10-18): the item "stays unticked: it also names web-git-data-probe.sh and luks-monitor.sh" | Stale as to code. Both are converted; S6-HB lists both in the derived population with exactly one guarded stdin line each | Correct the rationale in the post-merge evidence comment |
| "Same production-apply constraint, rides S4/S5" | True only for a future infra edit. This PR edits none: the apply path filter is `apps/web-platform/infra/**` and the release filter is `apps/web-platform/**` plus `plugins/soleur/**`; neither matches `knowledge-base/**` | KB-only PR, no apply |

## Research Insights

**Premise Validation (Phase 0.6).** Cited by reference: umbrella #9757 (open), the inngest heartbeat PR
(#10356, merged 2026-10-15T19:05Z), PR #10086 (merged 2026-10-12, merge commit 64046de076), PR #10322
(registry, merged), draft PR #10504 (this branch). Checked with `gh issue view`, `gh pr view` and `git grep`
on origin/main. Held: the umbrella is open and the item is unticked. Stale: the premise that the three scripts
are unconverted. The ADR-corpus check (`knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md`, sections
"Addendum — 2026-10-12 (#9757 residue)" and "2026-10-15 follow-ups — PR C") shows the conversion is the
recorded decision, and ten residuals are tracked on #10093.

**Property List (Phase 0.6b).**

1. P1: No heartbeat curl in `apps/web-platform/infra/*.sh` carries its URL on argv (observable: S6-HB reports zero violations, allowlist length 0).
2. P2: Each of the three named scripts judges the URL shape before any request and sends it only on the stdin config (observable: one `url = "%s"` line per script, behind the guard).
3. P3: The umbrella item's state matches P1 and P2 and says what is and is not verified (observable: the checklist line ticked with a scoped label, plus an evidence comment).
4. P4: The luks delivery gap is visible to the next engineer (observable: a residual comment on #10093 with a named verification trigger).

**Cut List.**

- Convert the three scripts again, or add a fourth guard copy: buys no property (P1, P2 already hold, enforced by S6-HB); covered by PR #10086 and PR #10356.
- Rate-limit `web-git-data-probe.sh`'s refusal marker and unset-URL WARN (#10093 residuals 3 and 8): hygiene, not an argv exposure; would fire the production push-apply plus six ratchet bumps; already tracked on #10093.
- A new live-evidence verifier for the git-data and luks monitors: out of scope for a closeout.
- A repeat transport-line `git grep` cross-check (cut at plan review): S6-HB already asserts one guarded stdin line per script and is the authoritative scanner.

**Institutional learnings applied** (`knowledge-base/project/learnings/`):

- `2026-10-13-a-sibling-session-shipped-the-same-fix-while-i-planned-and-review-found-it-three-hours-later.md` and `2026-05-31-inngest-v1-loopback-gated-and-halt-on-stale-premise.md`: re-verify the premise against main before planning a fix; halt on a stale premise.
- `2026-10-15-a-new-nonpaging-marker-moved-a-pin-in-a-suite-the-affected-gate-never-selects.md`: a marker or emit-site edit moves `BASELINE_PASSES` in a suite the affected gate never selects (relevant only to a future code PR).
- `2026-10-16-i-rescoped-a-pr-and-its-post-merge-probe-still-waited-for-a-boot-the-pr-no-longer-caused.md`: anchor a post-merge probe on the real delivery event; here that is why a monitor read is never delivery evidence.

**Evidence gathered at plan time** (read-only, no secret printed):

- Full `bash tests/scripts/test-argv-bearer-sweep.sh` on this tree (origin/main plus the branch-init commit): `823 passed, 0 failed`, every S6-HB row `[ok]` (6 converted scripts in the derived heartbeat population: the three named plus `web-zot-consumer-probe.sh`, `inngest-consumer-probe.sh` and `web-private-nic-guard.sh`; allowlist ceiling 0; guard-copy parity across 4 bash copies). Wall time about 3.5 minutes.
- Delivery paths: `web-git-data-probe.sh` is delivered to web-1 by the `server.tf` terraform_data install on the push-apply. `luks-monitor.sh` is delivered by `workspaces-luks.tf`, an operator-applied root. The `soleur-workspaces-luks-prd` monitor (`uptime-alerts.tf`) is `paused = true` with `ignore_changes = [paused]`, period 86400, grace 3600, and has a second pusher (`workspaces-luks-verify.yml`), so an "up" read on it would not prove this script is on any host.
- The git-data monitor is `soleur-git-data-prd` (`git-data.tf`, period 60, grace 180).

## Open Code-Review Overlap

None. The plan edits no source file; the only files touched are under `knowledge-base/project/{plans,specs}/` and GitHub issue comments.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Move the heartbeat URL (whose path is the secret) off argv in apps/web-platform/infra/inngest-bootstrap.sh, apps/web-platform/infra/web-git-data-probe.sh and apps/web-platform/infra/luks-monitor.sh" [brief] | Phase 1 (evidence that it is done on main) | mapped: satisfied by PRs #10086 and #10356, nothing left to edit |
| 2 | "by passing it as `url = \"...\"` on curl's stdin config behind a shape guard, following the pattern the inngest heartbeat PR" [brief] | Phase 1 (a): S6-HB asserts the guarded stdin line per script | mapped |
| 3 | "the unticked \"Heartbeat-URL path secrets\" checklist item" [brief] | Phase 4 (tick scoped to transport, after merge) | mapped |
| 4 | "the umbrella stays OPEN; reference it as \"Ref #9757\", never \"Closes\"" [brief] | Phase 3 (PR body wording) and Phase 4 (no close) | mapped |
| 5 | "Ship through review and CI to a merge-ready PR. After the PR exists, stop and ask the operator to approve its merge naming the PR" [brief] | Phase 3 | mapped |
| 6 | "never print secrets; no -auto-approve for Terraform; production writes need the operator's per-command go-ahead" [brief] | Phase 1 token handling; no Terraform and no production write anywhere in this plan | mapped |
| 7 | "Note the neighbouring ratchets (boundary-prefix census, grep-q pipe guard, infra tool-census tests, plugin-root anchoring, SKILL.md byte ceilings) that infra shell changes trip, and plan for them." [brief] | Ratchet table below: this PR trips none; the table records why | mapped |
| 8 | "Implement the next fix PR" [brief] | Overview: the fix is already merged; the PR is the verified closeout | descoped (infra edit) - justification: editing `apps/web-platform/infra/**` again would fire the production push-apply for no security gain; Ruled by CTO agent, 2026-10-18 |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1: re-verify S6-HB and the apply-run delivery evidence | "Move the heartbeat URL (whose path is the secret) off argv" (asks 1-2) | asked |
| Phase 1 (c): apply-run conclusion for the PR #10086 merge | - | inferred - justification: the CTO evidence bar requires delivery evidence for the one script the push-apply delivers; without it the tick would claim more than the evidence supports |
| Phase 4: umbrella tick and evidence comment | "the unticked \"Heartbeat-URL path secrets\" checklist item" (ask 3) | asked |
| Phase 4: #10093 luks residual comment | - | inferred - justification: the luks monitor is paused and operator-applied, so the tick must not imply luks delivery; the residual keeps the gap visible |
| Phase 3: KB-only PR with plan, tasks, decision record, evidence file | "Ship through review and CI to a merge-ready PR" (ask 5) | asked |
| Files to Create: `closeout-evidence.md` | "Ship through review and CI to a merge-ready PR" (ask 5) | inferred - justification: the evidence must live in the PR so a reviewer can re-check it without the session; the post-merge issue comments cite it by PR number |

### Split Assessment

- Subsystems touched: 1 - `knowledge-base`
- Planned files: 4 | Estimated changed lines: 300
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

**If this lands broken, the user experiences:** nothing. The PR changes no runtime file. The worst case is a wrongly ticked umbrella item that overstates what is verified, which the scoped label ("transport (argv)") and the named luks residual prevent.

**If this leaks, the user's data is exposed via:** no new vector. No heartbeat URL, token or digest is written into any artifact, PR body or comment; the evidence records only booleans, counts, content anchors and monitor names. A heartbeat URL is a path-bearing credential, so a pasted URL would be the leak; the acceptance criteria scan every outgoing text for it.

**Brand-survival threshold:** none

threshold: none, reason: the diff touches only knowledge-base planning artifacts and GitHub issue comments, no runtime, credential or schema path.

## Implementation Phases

### Phase 1 - Verify (read-only; no secret printed)

Create `knowledge-base/project/specs/feat-one-shot-9757-heartbeat-url-off-argv/closeout-evidence.md` and fill it from these reads. The file records results only: pass/fail, counts, content anchors (a quoted fragment of the transport line, never a line number), monitor names, and `status=`/`paused=` fields. Never the heartbeat URL, the Better Stack token, or any digest.

- (a) S6-HB. Run `bash tests/scripts/test-argv-bearer-sweep.sh` on a tree equal to origin/main for the files named; record the final summary line and say "6 converted of 16 derived heartbeat scripts" so the file matches the test output. Pass: `0 failed` and every `S6-HB` row `[ok]`. The plan-time run (823 passed, 0 failed) is cited; re-run only if the branch has drifted from main for any file in the `apps/web-platform/infra/*.sh` set. This is the authoritative scanner for the argv property and for the one-guarded-stdin-line-per-script property; no separate grep is prescribed.
- (b) Anchors on main. Record, per script, the content anchor of its transport line and its guard function (`_hb_url_ok` / `hb_url_ok` / the negated allow-class `case` in the inngest heartbeat body), read from `git show origin/main:<path>`.
- (c) Delivery of `web-git-data-probe.sh`. Resolve a successful `apply-web-platform-infra.yml` push run whose head SHA contains PR #10086's merge commit (`64046de076`; check with `git merge-base --is-ancestor`), via `gh run list`; no secret involved. Say whether the run log or a run summary readable without a secret shows the `server.tf` terraform_data install ran. A green run with no diff does not prove re-delivery, so if per-resource re-delivery is unreadable, write "run succeeded; per-resource re-delivery not read" and never "delivered".
- (c2) Optional, informational: the `soleur-git-data-prd` monitor state, using the read-scope form the cutover runbook documents (`knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`; only the monitor name is substituted: the runbook's example targets `soleur-git-data-host-prd`): `doppler run --only-secrets BETTERSTACK_API_TOKEN_READONLY -p soleur -c prd_terraform -- env -u SHELLOPTS -u BASH_ENV -u BASHOPTS bash --noprofile --norc -c 'BS_TOKEN="$BETTERSTACK_API_TOKEN_READONLY" exec bash apps/web-platform/infra/arm-heartbeats.sh --status soleur-git-data-prd'`. Redirect stdout to a scratch file, keep only the `status=` and `paused=` fields, scan the scratch file for the heartbeat URL shape before anything is pasted, and never `set -x`. `--status` never issues a PATCH. `status=up` proves only that some probe is beating; it is never cited as delivery. A `status=down` is a finding filed on #10093 and does not block the transport tick. If Doppler or Better Stack is unreadable, record "not read" and why.
- (d) Luks. Cite from `uptime-alerts.tf` and `workspaces-luks.tf` that the monitor is `paused = true` with `ignore_changes = [paused]` and that delivery of `luks-monitor.sh` is through the operator-applied `workspaces-luks.tf` root. Claim no luks delivery or liveness.

If (a) fails on a fresh read, stop the closeout and switch to a real fix PR for whatever failed (CTO fallback).

### Phase 2 - Review and CI on the knowledge-base-only PR

Commit with explicit pathspecs only (never `git add -A` or `git add .`): the plan, `tasks.md`, `decision-challenges.md`, `closeout-evidence.md`. Run markdownlint on the plan and `tasks.md`, and the repo's changed-files lint for human-run infra steps, before the commit.

### Phase 3 - Ship: PR #10504 to merge-ready, then stop

Update draft PR #10504: title `docs(infra): verified closeout for heartbeat-URL argv item (Ref #9757)`; body opens with "this PR changes no code: the requested conversion is already on main (PRs #10086, #10356)", the evidence summary, the decision record, "Ref #9757", and a line that no `apps/web-platform/infra/**` file changes (so no push-apply and no web release fire). No closing keyword for #9757, #10093 or #10363. After review and CI are green, mark ready and **stop**: ask the operator to approve the merge of PR #10504 by name. Only on a Yes record a delegation naming it with `delegation-verify.sh render`; the epic's existing delegation is in the old format and verifies invalid, so it is not used.

### Phase 4 - After the merge: record on GitHub (non-production writes, by the executing session)

Runs only after PR #10504 merges, so a rejected PR leaves the umbrella untouched. Evidence is cited by PR number (`#10504`), not by a path in an unmerged branch. `gh issue comment` and `gh issue edit` are not production infrastructure writes; no secret in any body.

1. Umbrella #9757, new comment: the Phase 1 (a)-(d) results, the corrected rationale ("web-git-data-probe.sh and luks-monitor.sh are converted, PR #10086"), "Ref #9757" wording, and that the tick covers the **transport (argv)** scope while residuals stay open on #10093.
2. Umbrella #9757 body: tick only the "Heartbeat-URL path secrets" line and append the scoped label `(transport (argv): done, PRs #10086 and #10356; residuals on #10093)`; decide deliberately what happens to the line's existing note ("Same production-apply constraint, rides S4/S5"): replace it with the scoped label so the line does not contradict the tick. Edit guard: capture `updatedAt` and a backup of the body to a scratch file, build the new body by replacing that one line, diff before/after (exactly one line differs), re-read the issue immediately before writing and abort without writing if `updatedAt` or the body changed, then `gh issue edit 9757 --body-file`. Do not close the issue.
3. #10093, new comment (never an edit of an old one): "luks-monitor.sh transport is on main but unverified on any host; delivery is via the operator-applied workspaces-luks.tf root (runbook: `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`); the monitor is paused until cutover. Verify at the cutover unpause." Read #10093 first: its 2026-10-15 residual list has no luks-delivery item at plan time; comment only if that still holds.

## Files to Edit

None. No source, test, workflow, ADR, Terraform or script file is edited.

## Files to Create

- `knowledge-base/project/plans/2026-10-18-fix-heartbeat-url-off-argv-9757-plan.md` (this plan)
- `knowledge-base/project/specs/feat-one-shot-9757-heartbeat-url-off-argv/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9757-heartbeat-url-off-argv/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-9757-heartbeat-url-off-argv/closeout-evidence.md` (written in Phase 1)

## Ratchets and gates (planned for, none tripped)

The brief asked to plan for the ratchets that infra shell changes trip. This PR edits no infra shell file, so each is left untouched on purpose (CTO ruling: touch none). For a future code PR on these scripts, the bumps are:

| Ratchet | Where | Tripped here? | If a future code PR edits these scripts |
|---|---|---|---|
| Heartbeat argv scan (S6-HB), allowlist ceiling 0, guard-copy parity across 4 bash copies | `tests/scripts/test-argv-bearer-sweep.sh` (`EXPECTED_TESTS=823`) | No | Keep the allowlist empty; edit all guard copies byte-identically |
| Non-paging marker pin, per-script suite floors, promoted-file floor | `betterstack-send-failed-alert-mutation.test.sh` (`BASELINE_PASSES=79`, not selected by `--affected`), `luks-monitor.test.sh` (`EXPECTED_PASSES=155`), `scripts/guard-vacuity-floor.test.sh` `PROMOTED_FILES` | No | A new `SOLEUR_*` emit site moves the pin; re-measure floors |
| GuardA byte-identity row, push-apply and release triggers | `cloud-init-inngest-bootstrap.test.sh`; `apply-web-platform-infra.yml` paths `apps/web-platform/infra/**` | No (KB-only diff) | Editing `inngest-bootstrap.sh` turns GuardA red until the tag mint and pin-bump PR (ADR-232); any infra edit fires the production apply and needs the operator's per-command go-ahead |
| grep-q pipe guard, infra tool census, boundary-prefix census, plugin-root anchoring, SKILL.md byte ceilings | `.claude/hooks/grep-q-pipe-guard.test.sh`; infra and plugin suites | No | Not reached by a knowledge-base-only diff; re-check any census that lists a tool the edited script uses |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git diff --name-only origin/main...HEAD | grep -vE '^knowledge-base/project/(plans/2026-10-18-fix-heartbeat-url-off-argv-9757-plan\.md|specs/feat-one-shot-9757-heartbeat-url-off-argv/)'` prints nothing, except the pipeline-written `plugins/soleur/knowledge-base/INDEX.md` if the ship step regenerates it (merge-base form, so a sibling merge to main cannot redden it); in particular no `apps/`, `tests/`, `scripts/`, `.github/` path.
- [ ] `closeout-evidence.md` records: the S6-HB result (`0 failed`, "6 converted of 16 derived"), a content anchor and guard per script, the apply-run conclusion with the per-resource re-delivery statement, the optional monitor reading or "not read", and the luks paused/operator-applied citation.
- [ ] No outgoing text contains a heartbeat URL, token or digest. Scan the files, the PR body draft and every comment draft with `grep -rnE 'betterstack\.com/api/v1/heartbeat/[A-Za-z0-9]'` (plain `grep -r`, not `git grep`, because the spec files are untracked until the commit) plus a scan for any 20-or-more-character alphanumeric token in `closeout-evidence.md`; both return nothing.
- [ ] PR #10504 body uses "Ref #9757" and contains no `Closes`, `Fixes` or `Resolves` keyword for #9757, #10093 or #10363.
- [ ] CI is green on the PR head; review findings resolved.

### Post-merge (recorded by the executing session, not operator steps)

- [ ] Umbrella #9757 has the evidence comment and exactly one body line changed (the heartbeat item, scoped label), and the issue is still OPEN.
- [ ] #10093 has the new luks residual comment (or the plan-time read is recorded as superseded) and is still OPEN.

## Test Scenarios

- Given the S6-HB stage on a tree equal to main, when it runs, then every S6-HB row is `[ok]` and the summary reads `0 failed`.
- Given a mutation that puts the URL back on argv in any converted script, when S6-HB runs, then it is RED (already pinned by the suite's mutation rows; this plan adds none).
- Given the apply run's per-resource re-delivery cannot be read, when Phase 1 (c) completes, then the evidence says "run succeeded; per-resource re-delivery not read".
- Given `soleur-git-data-prd` reads `status=down`, when Phase 1 (c2) completes, then the finding is filed on #10093 and the transport tick still proceeds.
- Given Doppler is unreadable in the session, when Phase 1 (c2) completes, then the evidence says "not read".
- Given the umbrella body changed between the read and the write, when Phase 4 step 2 runs, then it aborts without writing.
- Given the umbrella body edit, when the before/after diff is taken, then exactly one line differs.

## Domain Review

**Domains relevant:** engineering (CTO) only

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled (2026-10-18) option A, KB-only closeout; rejected the residual-fix and verifier options as out of scope; set the evidence bar, then revised it after plan review (apply-run conclusion is the delivery evidence, the monitor read is informational, the tick and comments move after merge, the umbrella edit is guarded). No product, marketing, legal, finance or support surface: no user-facing change, no regulated data, no new infrastructure.

## Observability

Skipped: the diff touches no code-class path (`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`) and introduces no infrastructure surface. The existing liveness signal for these scripts is unchanged (Better Stack heartbeats, S6-HB in CI).

## Plan Review Revisions (2026-10-18)

Panel: DHH, Kieran, code-simplicity (threshold none, so no escalation); the CTO was already the ruling authority, so no separate devex seat.

- Applied (mechanical): sequencing (tick and comments after merge, evidence cited by PR number); umbrella-edit guard and the existing-note decision; secret-scan AC uses plain `grep -r` and covers the PR body and comment drafts; diff-scope AC now has a failing condition and the real INDEX path; "6 converted of 16 derived"; Split Assessment file count corrected (4); ADR sections cited by their real headings; luks residual names the cutover runbook; transport-line cross-check grep cut (S6-HB is authoritative); line-number citations replaced by content anchors in the evidence file; existing-residual read before the #10093 comment.
- Applied (CTO-ruled technical): bar (c) is the apply-run conclusion, the monitor read is optional and never delivery evidence, `status=down` does not block the transport tick.
- Surfaced, not applied (taste): fold `closeout-evidence.md`, `tasks.md` and `decision-challenges.md` into the plan (kept: the brief requires the decision record, the pipeline consumes `tasks.md`, and the evidence file lets a reviewer re-check without the session); collapse the ratchet table further (kept in four rows because ask 7 names them); the tick is a one-way signal an owner may read as "done" while residuals remain (mitigated by the scoped label; restated in the merge-approval ask).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`; this one declares `none` with a reason because the diff is knowledge-base only.
- Do not put the heartbeat URL, the Better Stack token or a digest into the evidence file, a comment, or the PR body; a path-bearing URL pasted as "proof" is the exposure this item exists to prevent.
- The umbrella body edit must change exactly one line; a read-modify-write that reflows the checklist would silently rewrite other items. Diff, and re-read for concurrent edits, before posting.
- Do not use a closing keyword for #9757, #10093 or #10363 anywhere in the PR; closure of #10093 and the umbrella is evidenced work later.
- Never cite a monitor "up" read as delivery evidence: `soleur-git-data-prd` only shows some probe is beating, and the luks monitor is paused with a second pusher.
- Stale-premise lesson: re-read main before acting on a brief that names files as unconverted; the umbrella text lags merged work.
