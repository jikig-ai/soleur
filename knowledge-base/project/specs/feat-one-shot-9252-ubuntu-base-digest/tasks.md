# Tasks: bump the git-data rehearsal ubuntu:24.04 pin (#9252, ubuntu part only)

Plan: knowledge-base/project/plans/2026-10-08-chore-bump-ubuntu-base-digest-git-data-rehearsal-plan.md

## Phase 1: Re-resolve and measure (no edits)

- 1.1 `docker buildx imagetools inspect ubuntu:24.04` -> record the index digest (MediaType must be `image.index.v1+json`); today `sha256:534baea6...eb55`.
- 1.2 In `ubuntu:24.04@sha256:<NEW>`: run `mke2fs -V`, `dpkg -s e2fsprogs`, plain / `-O project` / `-O casefold` mkfs + `dumpe2fs -h`; compare to the OLD image.
- 1.3 Branch: identical -> allowlist unchanged; novel feature -> one-line classified row with kernel-source rationale; any `module-dep` -> STOP and report on #9252.

## Phase 2: Edit

- 2.1 `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`: `UBUNTU_BASE` literal (one line, column 0) + stanza comment (dated pair, re-measure note).
- 2.2 `apps/web-platform/infra/git-data-ownership.test.sh`: `UBUNTU_BASE` literal.
- 2.3 `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`: `UBUNTU_BASE` literal (Tier B).
- 2.4 Do NOT edit `git-data-birth-fs-fingerprint.txt`, zot files, `cloud-init-registry.yml`, or `.github/workflows/*`.

## Phase 3: Verify locally

- 3.1 Run the rehearsal suite and the ownership suite, capturing the exit code (no bare `| tail`).
- 3.2 Check AC-1 and AC-2 greps; `git diff origin/main --name-only` against AC-3 fences.

## Phase 4: PR (draft #9783)

- 4.1 Body: digest move, measurement table, R1 outcome, sibling bumps, `Ref #9252` (never Closes), Generated-with-Claude-Code line last.
- 4.2 Wait for green CI; re-run AC-1 after the last CI rerun; mark ready. Merge stays with the operator. No `[ack-destroy]`, no apply workflows.
