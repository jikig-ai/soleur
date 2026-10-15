# Learning: a census that stubs the host verb cannot see the env the step forgot to pass — and four siblings from the wipe-body review

## Problem

PR #10294 built the body of the plaintext-volume wipe (`mode=wipe|wipe_finish|wipe_check` on `git-data-cutover.yml`, issue #10138). It passed a 368-assertion census, a 97-mutant battery and 13 local suites. A 13-seat review panel then found a P1 in the first minute: the post-detach host read (W10) ran under `exec env -i <allow-list>` **without `WEB_HOST_SSH`**, the variable the CF bridge exports through `$GITHUB_ENV` and `access_gate` requires. Every real `wipe` would have detached the volume and then refused at W10 with `web_host_ssh_unset`, mailing "store not serving, do not finish" about a healthy store. Three seats reproduced it independently (observability, security, quality). The census could not see it because its simulator replaced `git-data-cutover.sh` with a stub that always answers.

Four siblings came out of the same review, each a verification-code defect rather than a feature defect:

1. A host verb that exits 5 for both a store **verdict** and `probe_failed` ("could not read") cannot be told apart by an exit-code test. The first fix (`rc == 5`) was too coarse; the second (a free `grep` for ` verdict=probe_failed` over the verb's stdout) was forgeable, because the verb relays remote stderr on stdout.
2. Census shims that answer a fixed OK (a `gh` shim, a boot stub that always says ok) cannot test refusals: five one-line deletions of the `wipe_finish` evidence steps' `exit 5` left the suite at 69/69.
3. A helper wrote `phase=detached` from an identity **read**, so a refused `wipe_finish` notified the very command it had just refused.
4. Notification placeholders written as `<the volume id you typed>` are swallowed as HTML tags by the email and as markdown inline HTML by the issue, so the recovery command read `-f volume_id= -f origin_run=`.

## Solution

- **Env contract row, derived from the script**: for every `exec env -i` step that runs `git-data-cutover.sh`, derive the env names `access_gate` / `mode_wipe_assert` read and require the step to pass each, plus an **executed** row that runs the step's real `bash -c` body under the exact allow-list against the real script with only `ssh` shimmed. Mutant: drop `WEB_HOST_SSH` -> RED on the census, the executed row and a simulator run.
- **Verdict vs unanswered read**: set the refusal only when the verb exits 5 **and** its own emitter line is not `probe_failed`, matched with an anchor (`grep -qE "^\[git-data-cutover\] STORE probe=[a-z-]+ verdict=probe_failed" "$out"` on a captured file, never a pipe, never a free substring). An unanswered read leaves `phase=detached`, which already notifies `VOLUME_DETACHED` with the finish command; the finish repeats the same read before any delete. A single retry of the read-only check (never on a store verdict) closes the transport-flake case.
- **Negative scenarios**: the simulator's stubs must be able to return the BAD answer (wrong branch, event `push`, gate `failure`, null `createdAt`, rollback run after the stamp, boot verdict not ok, detach/attach/detach history) and each scenario must refuse **at its own step** with DETACH=0 and DELETE=0, with a one-line mutant per `exit`.
- **Markers belong to the step that made the call**: `identity` writes no phase; `detach` writes `detached` only after its confirm read.
- **Placeholders are plain words** (`VOLUME_ID`, `ORIGIN_RUN_ID`), the id is filled only from a digit-validated 1-12 character input, and a row asserts no angle bracket appears in any recovery command.

## Key Insight

A census that stubs the thing which distinguishes good from bad input measures the workflow's shape, not its behaviour. For a destructive pipeline the check that matters is "run the real step body under the real allow-list against the real script, with the world shimmed at the process boundary (ssh, curl, gh), and drive the BAD answer through every gate". Everything else (step order, `if:` strings, token containment) is necessary and was green throughout while the wipe could not have completed.

Review mechanics worth keeping: 13 report-only seats plus a simplicity pass found 3 P1 and ~25 P2 in verification code; a verification pass over only the **fix delta** (2 seats) still found 2 more P3 in the fixes (the forgeable grep, a missing page-2 attach in the action history). A second-reviewer gate on the proposed scope-outs moved 3 of 5 items back to inline fixes because they sat in code the PR introduced; only the three pre-existing items were filed (#10343).

## Session Errors

1. **W10 env allow-list missing `WEB_HOST_SSH`** — Recovery: added to the allow-list, sourced the volume id from the verdict record, added an env-contract row + executed row — **Prevention:** for any `exec env -i` step that runs a script, derive the script's env reads and assert them; execute the step body under the exact allow-list.
2. **Refusal rule keyed on `rc == 5` alone, then on a free substring of stdout** — Recovery: capture stdout to a file and match the verb's emitter line anchored at line start — **Prevention:** never test an exit code that two different meanings share; match the emitter line anchored, on a captured file.
3. **Backtick in a comment inside the notify body** (`WF-notify-plain` red) — Recovery: reworded — **Prevention:** none beyond the existing row (covered).
4. **Fan-out left two registered censuses red** (`flag-precheck` G1-census, root-token census), found only by review — Recovery: restated both over the three-job shape — **Prevention:** after a fan-out with disjoint file ownership, run the registered suites that grep the changed workflow before the first review; route-to-definition proposal (not applied here, different subsystem): add this to the `soleur:work` fan-out guidance.
5. **Angle-bracket placeholders in the notify recovery command** — Recovery: plain-word placeholders, digit-validated fill, pinned by a row — **Prevention:** render every notification body through an HTML parser in a test.
6. **Hook blocks and cwd drift**: `pgrep -f` self-match; `gh issue create` needed a consequence label (`meta/machinery`); the follow-through-script hook reads the shell cwd, which had reset to the main checkout between calls — Recovery: `cd` into the worktree in its own call before the `gh issue create` call — **Prevention:** run path-relative gh/hook commands from the worktree and verify `pwd`.
7. **A 4 KB `PROMOTED_FILES` line printed by a `git diff`** flooded context — Recovery: none needed — **Prevention:** cut long lines with `cut -c1-N` before printing guard files.
8. **Transient network failures (EAI_AGAIN) killed two verification seats; a session restart killed two fix agents** — Recovery: resumed each by id with a short "continue" message; no work was lost because edits were already in the worktree — **Prevention:** resume, do not respawn; check `git status` for partial edits first.
9. **`gh issue view --comments --json` used together** (flags are mutually exclusive) — Recovery: dropped one — **Prevention:** none (one-off).
10. **Shard-manifest regeneration swept in two unrelated suite rows** — Recovery: dropped them — **Prevention:** read the manifest diff for rows the change did not add.

## Tags
category: integration-issues
module: git-data-cutover
