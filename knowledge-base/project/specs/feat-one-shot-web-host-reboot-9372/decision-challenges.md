# Decision challenges: web-host-reboot workflow (#9372, Ref only)

Headless plan run, 2026-10-07. Each item is a Taste or User-Challenge finding from the six-reviewer plan review. The plan keeps the direction the brief stated; the owner may reverse any item. Nothing here was applied silently.

## 1. Keep the `observe` job (User-Challenge)

- Reviewers (DHH, code-simplicity, CTO devex lens) proposed one job: reboot, one single-read grade, a summary, and local re-grading afterwards.
- The brief says the workflow itself polls Better Stack and reports PASS/FAIL/NOT YET. The plan keeps two jobs so the poll holds no Tier-B credential and does not hold the `web-1-swap` mutex for about 45 minutes.
- Default: keep (the stated direction). Reversal cost: delete one job, two cross-job outputs, the `observe` structural rows (about 70 test lines) and Guard 4 row 4.

## 2. Keep the `host` input and the explicit allow-list (User-Challenge)

- DHH proposed dropping the `host` input and the allow-list refusal because the script already pins `soleur-web-2` by constant.
- The brief says "allow only web-2 initially via an explicit allowlist", so the plan keeps it, with a test row that the script, the workflow options and the suite agree.
- Default: keep.

## 3. Credential-free `validate` job ahead of the gate (adopted after the deepen pass)

- Raised as a taste option at plan review (a typo spends an approval). The deepen-pass security review made it a P1: `run-name` is rendered from raw inputs at queue time and an approver reads it, so a hostile or prompt-injected dispatch could shape the approval prompt.
- Adopted: a no-secrets `validate` job, `reboot` depends on it, and `reason` is kept out of the title. The job list is now three. Reversal cost: delete one job and Guard 4 rows 4 and 10.

## 4. Keep the C4 and ADR records (Taste)

- The CTO devex lens suggested skipping the C4 edge-prose edits and the regeneration, and keeping only a two-line ADR addendum, because the capability retires within weeks.
- The plan keeps two half-sentence edge edits and a short ADR-263 addendum (plus a one-line ADR-241 entry), because `wg-architecture-decision-is-a-plan-deliverable` and the C4 completeness mandate treat a new Tier-B consumer as a recorded change, and the retirement row removes them.
- Default: keep, minimal.

## 5. Keep `credentials_required` in the discoverability test (Taste)

- The CTO devex lens suggested omitting `credentials_required` to avoid the `BASELINE_DECLARED_PROBES` collision with sibling PRs.
- Omitting it would make preflight Check 10 execute a probe that cannot read Better Stack without credentials, verifying nothing about the property. Siblings (#9372's own plans) declared it.
- Default: declare it and bump the baseline in the same PR.

## 6. Mutation-battery volume (Taste)

- DHH asked for about 8 to 10 mutation rows in total; the plan keeps 28 across four guards (Guard 1: 9, Guard 2: 6, Guard 3: 3, Guard 4: 10), after trimming 29 and then adding four security rows (pinned actions, no `inputs` in `run:`, the allow-lists, `needs: validate`).
- Every row corresponds to a property in the Property List; the REORDER and second-write-site rows are the ones DHH also kept.
- Default: keep at 28; the owner may cut Guard 2 rows 3 and 6 and Guard 4 rows 3 and 6 first.

## 7. A `PASS (row presence only)` label (Taste, applied)

- CLO suggested not using the word PASS at all; the brief asks for PASS/FAIL/NOT YET. Applied as `PASS (row presence only)` with the fixed footer. Recorded here because it softens a requested word.

## 8. The journald `workspaces-luks-reopen` row as same-run evidence (Taste, not adopted)

- The identifier breakdown measured on 2026-10-07 shows that this host writes a `workspaces-luks-reopen` journald row at the start of each boot (observed on two of the four boots in the last 30 h). Reporting only its presence on the new boot would give same-run evidence about the boot path, minutes after the request, instead of waiting for the daily probe.
- Not adopted: the brief names the probe row as the evidence, the row's own text states what the volume did (which the claim denylist forbids echoing), and the follow-through grades the soak from the probe rows.
- Option for the owner: add a presence-only line (`unit row on the new boot: yes or no`) and exempt that identifier from the denylist.

## 9. Denylist scope (Taste, security side adopted)

- The CTO devex lens wanted the static claim scan limited to emitted-output strings to avoid false positives. The security review showed a print-statement scope is bypassable (heredocs, `jq -n`, strings built in variables).
- Adopted: the static scan covers all non-comment text of the three files (only the footer constant is exempt) and error wording avoids the denylisted words. Reversal: narrow the scan and accept the bypass classes.

## 10. Approval independence (follow-up filed, no change here)

- Measured 2026-10-07: the environment's only reviewer is the owner's own login, and `prevent_self_review` is `false`. The agent's `gh` identity is that login, so the platform does not separate dispatching from approving; `hr-menu-option-ack-not-prod-write-auth` does, by rule.
- A `.tf` change (`prevent_self_review` plus a distinct agent identity) is out of scope for this PR; a follow-up issue is filed in Phase 7.
