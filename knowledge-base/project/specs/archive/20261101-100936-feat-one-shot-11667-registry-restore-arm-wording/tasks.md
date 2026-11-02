---
plan: knowledge-base/project/plans/2026-11-01-chore-registry-restore-arm-wording-plan.md
issue: 11667
branch: feat-one-shot-11667-registry-restore-arm-wording
lane: cross-domain
---

# Tasks: registry restore arm wording (Ref #11667)

## Phase 1 — Edit the workflow

- 1.1 Read lines 3630-3640 of `.github/workflows/apply-web-platform-infra.yml`.
- 1.2 Edit the exit-3 arm (line 3637): replace `the rebuilt registry did not accept the write and the tunnel did not converge within the backoff. The store is EMPTY.` with `the registry did not accept or serve a request within the backoff. The store is EMPTY or only partly refilled.` (keep the trailing `Verify the registry host is serving, then re-run this job.`).
- 1.3 Edit the exit-4 arm (line 3638): replace `Do not deploy; re-run this job and read the per-entry lines above.` with `Do not deploy. NOT retryable: read the per-entry lines above.`
- 1.4 Touch no other line, comment or whitespace; keep the line count unchanged.

## Phase 2 — Edit the runbook

- 2.1 Read line 507 of `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`.
- 2.2 Replace `Re-run the job and read the per-entry lines; a repeat means` with `NOT retryable; read the per-entry lines; a repeat means`; keep the "do not deploy" sentence.

## Phase 3 — Verify locally

- 3.1 Run plan ACs 1-5 (size equals origin/main minus 12 and under 490000; numstat `2 2` and `1 1`; new literals once, old literals zero; row-4 anchored grep); `wc -l` unchanged.
- 3.2 After committing, run AC6: no path under `scripts/`, `tests/`, `plugins/`, `apps/`.
- 3.3 Run `cd plugins/soleur && bun test test/workflow-file-size.test.ts` and `bash tests/scripts/test-registry-d10-workflow-wiring.sh` (expect `91 passed, 0 failed`); report any budget hit as such.

## Phase 4 — Ship

- 4.1 Re-run the open code-review overlap query for both edited paths.
- 4.2 Run `bash plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh` before any push.
- 4.3 Commit message: no `[skip-web-platform-apply]`, no `[ack-destroy]`.
- 4.4 PR body for #11787: `Ref #11667`, the parent-tracker Ref line from the brief, the -12 byte delta; no close/fix/resolve wording; run the AC8 grep.
- 4.5 Comment on #11667 listing by string: `The store is EMPTY and this job cannot refill it` (~line 3592), exit-78 arm `the store is still EMPTY` (~line 3643), `### The store is EMPTY` summary (~line 3475), plus the two planner-added runbook strings.
- 4.6 `gh pr merge 11787 --squash --auto` (one merge command per Bash call, no `--delete-branch`, no admin merge); report a multi-hour queue stall.
- 4.7 Do not touch issues 11312, 11379, 10924.

## Phase 5 — Post-merge verification

- 5.1 `gh run list --workflow apply-web-platform-infra.yml --limit 1`; wait with the watch mechanism.
- 5.2 Apply job: pre-apply entrypoint gate and `terraform apply` green, no-change plan.
- 5.3 `git show origin/main:.github/workflows/apply-web-platform-infra.yml | wc -c` is the pre-merge main size minus 12 (about 489192).
