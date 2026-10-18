# Tasks: verified closeout for the heartbeat-URL argv item (Ref #9757)

Plan: `knowledge-base/project/plans/2026-10-18-fix-heartbeat-url-off-argv-9757-plan.md`
Branch: `feat-one-shot-9757-heartbeat-url-off-argv` | Draft PR: #10504 | Umbrella: #9757 (stays open)

No code is edited. Commit with explicit pathspecs only. Never print a heartbeat URL, token or digest.

## Phase 1: Verify (read-only)

- 1.1 Create `closeout-evidence.md` in this spec directory.
- 1.2 Run `bash tests/scripts/test-argv-bearer-sweep.sh` (about 3.5 minutes) only if any `apps/web-platform/infra/*.sh` file drifted from main since plan time; otherwise cite the plan-time result (823 passed, 0 failed). Record "6 converted of 16 derived heartbeat scripts".
- 1.3 For each of `inngest-bootstrap.sh`, `web-git-data-probe.sh`, `luks-monitor.sh`: record the content anchor of the transport line and its guard function from `git show origin/main:<path>` (no line numbers).
- 1.4 Resolve a successful `apply-web-platform-infra.yml` push run whose head contains PR #10086's merge commit (`git merge-base --is-ancestor 64046de076 <run-head>`); record its conclusion and whether per-resource re-delivery is readable (else write "run succeeded; per-resource re-delivery not read").
  - 1.4.1 Optional: read `soleur-git-data-prd` with the read-scope form in the plan (stdout to a scratch file, keep `status=` and `paused=`, scan for the URL shape). Never cite it as delivery. `status=down` is a finding for #10093, not a blocker.
- 1.5 Cite from `uptime-alerts.tf` and `workspaces-luks.tf` that the luks monitor is paused (`ignore_changes = [paused]`) and delivery is operator-applied. Claim no luks delivery or liveness.
- 1.6 If 1.2 fails: stop the closeout and switch to a real fix PR for whatever failed.

## Phase 2: Review and CI

- 2.1 Run markdownlint on the plan, `tasks.md` and `closeout-evidence.md`; run `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- 2.2 Scan every file, the PR body draft and each comment draft: `grep -rnE 'betterstack\.com/api/v1/heartbeat/[A-Za-z0-9]'` (plain grep -r) and any 20-or-more-character alphanumeric token in the evidence file. Both must print nothing.
- 2.3 Verify the diff scope: `git diff --name-only origin/main...HEAD | grep -vE '^knowledge-base/project/(plans/2026-10-18-fix-heartbeat-url-off-argv-9757-plan\.md|specs/feat-one-shot-9757-heartbeat-url-off-argv/)'` prints nothing (allow `plugins/soleur/knowledge-base/INDEX.md` if ship regenerates it).
- 2.4 Commit with pathspecs: the plan, `tasks.md`, `decision-challenges.md`, `closeout-evidence.md`.

## Phase 3: Ship PR #10504, then stop

- 3.1 Retitle PR #10504 `docs(infra): verified closeout for heartbeat-URL argv item (Ref #9757)`; body opens with "this PR changes no code: the requested conversion is already on main (PRs #10086, #10356)", then the evidence summary, the decision record, "Ref #9757", and that no `apps/web-platform/infra/**` file changes. No closing keyword for #9757, #10093 or #10363.
- 3.2 Resolve review findings; wait for CI green; mark ready.
- 3.3 Stop. Ask the operator to approve the merge of PR #10504 by name, restating that the tick is a one-way signal scoped to "transport (argv)". Only on a Yes record a delegation naming it with `delegation-verify.sh render` (the epic's old-format delegation verifies invalid and is not used).

## Phase 4: After the merge (executing session, GitHub writes only)

- 4.1 Umbrella #9757: new comment with the Phase 1 results, the corrected rationale, "Ref #9757" wording, evidence cited by PR number.
- 4.2 Umbrella #9757 body: capture `updatedAt` and a body backup to a scratch file; replace only the "Heartbeat-URL path secrets" line (tick, scoped label, drop the stale "rides S4/S5" note); diff shows exactly one line changed; re-read right before writing and abort if the body changed; `gh issue edit 9757 --body-file`. Do not close the issue.
- 4.3 #10093: read first; if still no luks-delivery residual, post a new comment: "luks-monitor.sh transport is on main but unverified on any host; delivery is via the operator-applied workspaces-luks.tf root (runbook `workspaces-luks-cutover-6604.md`); the monitor is paused until cutover. Verify at the cutover unpause." Do not close #10093.
