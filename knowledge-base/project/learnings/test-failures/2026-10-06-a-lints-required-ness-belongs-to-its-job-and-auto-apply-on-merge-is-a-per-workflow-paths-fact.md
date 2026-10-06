# Learning: a lint's required-ness belongs to the job that hosts the step, and "auto-applies on merge" is a per-workflow `paths:` fact

## Problem

The brief for the credential-hardening pass said `lint-shell-trace-credential-refusal.py --changed` was "a required check
in ci.yml" and that "Class W deploy files auto-apply on merge". Both read as settled because an earlier PR comment had
written them down. Neither held for these two files, and the plan was built on them before they were measured.

## Root cause

- The `--changed` step sits in the `lint-bot-statuses` job, which `ci.yml` documents as advisory. That job is not in
  `scripts/required-checks.txt` and the live ruleset names no such context. The only required lane is the repo-wide run
  inside the `test` shard, which is baseline-suppressed by FILE.
- `apply-deploy-pipeline-fix.yml` fires on its own `paths:` filter. Neither `cron-egress-enforce-probe.sh` nor
  `web-private-nic-guard.sh` is in it, and `server.tf` was not edited. What fires instead is `apply-web-platform-infra.yml`
  re-provisioning the NIC guard on web-1 over its SSH leg, plus a normal image release. No host is replaced.

## Solution

State the correction in the PR body and on the tracker, keep the pass anyway, and say why: the baseline suppresses by
file, so a hardened script left in the baseline can regress silently and a one-line edit to a baselined file owes its
whole debt. Harden and draw down the baseline in the same PR.

## Key insight

Ask which JOB hosts a check before calling it required, and which workflow's `paths:` filter a file is in before calling
it auto-applied. Neither answer is in the file you are editing. A green apply also proves little: the SSH leg is skipped
when its token is unreadable and the run still concludes success, so the post-merge check reads the run summary
("SSH stage: ran") and the shipped log rows, not the conclusion.

## Tags

category: test-failures
module: ci, infra
