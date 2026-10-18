# Tasks: verified closeout for the heartbeat-URL argv item (Ref #9757)

Plan: `knowledge-base/project/plans/2026-10-18-fix-heartbeat-url-off-argv-9757-plan.md`
Branch: `feat-one-shot-9757-heartbeat-url-off-argv` | Draft PR: #10504 | Umbrella: #9757 (stays open)

No code is edited. Commit with explicit pathspecs only. Never print a heartbeat URL, token or digest.

## Phase 1: Verify (read-only)

- [x] 1.1 Create `closeout-evidence.md` in this spec directory.
- [x] 1.2 Run `bash tests/scripts/test-argv-bearer-sweep.sh` (about 3.5 minutes) only if any `apps/web-platform/infra/*.sh` file drifted from main since plan time; otherwise cite the plan-time result (823 passed, 0 failed). Record "16 derived, 6 manifest-pinned".
- [x] 1.3 For each of `inngest-bootstrap.sh`, `web-git-data-probe.sh`, `luks-monitor.sh`: record the content anchor of the transport line and its guard function from `git show origin/main:<path>` (no line numbers).
- [x] 1.4 Resolve a successful `apply-web-platform-infra.yml` push run whose head contains PR #10086's merge commit (`git merge-base --is-ancestor 64046de076 <run-head>`); record its conclusion and whether per-resource re-delivery is readable (else write "run succeeded; per-resource re-delivery not read"). Plan-time reading: run 38303163269 (head 64046de076, success) replaced `terraform_data.git_data_probe_install` with its `file` and `remote-exec` provisioners; re-confirm on the merged tree and record the resource name and outcome only.
  - 1.5 Cite that the luks monitor is paused (`ignore_changes = [paused]`, `uptime-alerts.tf`), that its installer `terraform_data.luks_monitor_install` is in the auto-applied target list, and that only the monitor and its URL secret are operator-applied. Claim no luks delivery or liveness.
- [x] 1.6 If 1.2 fails: stop the closeout and switch to a real fix PR for whatever failed.

## Phase 2: Review and CI

- [x] 2.1 Run markdownlint on the plan, `tasks.md` and `closeout-evidence.md`; run `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [x] 2.2 Scan every file, the PR body draft and each comment draft: `grep -rnE 'betterstack\.com/api/v1/heartbeat/[A-Za-z0-9]'` (plain grep -r) and any 20-or-more-character alphanumeric token in the evidence file. Both must print nothing.
- [x] 2.3 Verify the diff scope: `git diff --name-only origin/main...HEAD | grep -vE '^knowledge-base/project/(plans/2026-10-18-fix-heartbeat-url-off-argv-9757-plan\.md|specs/feat-one-shot-9757-heartbeat-url-off-argv/)'` prints nothing (no `plugins/` path: a `plugins/soleur/**` change such as a regenerated INDEX.md would fire the web release and version bump, so it must be absent or called out in the PR body).
- [x] 2.4 Commit with pathspecs: the plan, `tasks.md`, `decision-challenges.md`, `closeout-evidence.md`, `session-state.md`.

## Phase 3: Ship PR #10504, then stop

- [ ] 3.1 Retitle PR #10504 `docs(infra): verified closeout for heartbeat-URL argv item (Ref #9757)`; body opens with "this PR changes no code: the requested conversion is already on main (PRs #10086, #10356)", then the evidence summary, the decision record, "Ref #9757", and that no `apps/web-platform/infra/**` file changes. No closing keyword for #9757, #10093 or #10363.
- [ ] 3.2 Resolve review findings; wait for CI green; mark ready.
- [ ] 3.3 Stop. Ask the operator to approve the merge of PR #10504 by name, restating that the tick is a one-way signal scoped to "transport (argv)". Only on a Yes record a delegation naming it with `delegation-verify.sh render` (the epic's old-format delegation verifies invalid and is not used).

## Phase 4: After the merge (executing session, GitHub writes only)

- [ ] 4.0 Preconditions: `gh pr view 10504 --json state` reads MERGED; the three scripts are unchanged on main since 2026-10-15 (`git log origin/main -- <three paths>` empty past that date) and S6-HB is still green on main; run the secret scan from 2.2 over every comment draft.
- [ ] 4.1 Umbrella #9757 body: capture `updatedAt` and a body backup to a scratch file; replace only the "Heartbeat-URL path secrets" line (tick, scoped label "transport (argv): done" plus "live hosts web-2 and the inngest host keep the argv scripts until re-delivery, #10093 residual 1", drop the stale "rides S4/S5" note); diff shows exactly one line changed; re-read right before writing and abort if the body changed; `gh issue edit 9757 --body-file`. Do not close the issue.
- [ ] 4.2 Umbrella #9757: new comment with the Phase 1 results, the corrected rationale, "Ref #9757" wording, evidence cited by PR number. Posted only after 4.1 succeeded; skip if an equivalent comment already exists.
- [ ] 4.3 #10093: read first; if still no luks-delivery residual, post a new comment: "luks-monitor.sh transport is on main but unverified on any host; its installer is auto-applied but re-delivery was not read, and its heartbeat monitor (operator-applied, paused until cutover) cannot show delivery. Verify at the cutover unpause." Do not close #10093.
- [ ] 4.4 Read back: the umbrella body differs from the backup by exactly one line, #9757 and #10093 are still OPEN.
