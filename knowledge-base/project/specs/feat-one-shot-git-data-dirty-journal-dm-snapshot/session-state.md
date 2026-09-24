# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-24-fix-git-data-plaintext-dirty-journal-dm-snapshot-plan.md
- Status: complete (second planning subagent; the first crashed on a session limit after writing only the skeleton — recovered via the branch-frontmatter selector)
- Plan artifact: recovered (selector=branch)

### Errors
None (one plan-edit script aborted on a stale anchor before writing and was re-run).

### Decisions
- #8710 ships as a separate PR; hard precondition before the plan_only replace dispatch.
- Pipeline stops before four production dispatches (rung-2 rehearsal, plan_only replace, real replace, strict git-data-cutover dry run); none authorised by the plan.
- blockdev --setro stays on for the host's lifetime; one mechanism (dm snapshot, COW in /dev/shm), no clean-journal side path.
- Plan review cut ~10 mechanisms; new failure word is reason=snapshot only.
- Rehearsal evidence PASSes only on plaintext_volume=present with plaintext_journal=dirty on both boots.

### Components Invoked
soleur:plan, soleur:gdpr-gate, soleur:plan-review (dhh, kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, cpo), soleur:deepen-plan (security-sentinel, data-integrity-guardian, test-design-reviewer, verify-the-negative sweep), repo-research-analyst x2, learnings-researcher, cto, Plan agent.

## Work Phase
- Status: implementation complete; AC4 (loopback SUT arms on the CI kernel) pending the infra-validation run on e80bf4d3d5.

### Measurements (each from the run/command named)
- AC0: infra-validation run 35986930424, deploy-script-tests, "Run git-data plaintext snapshot loopback evidence": N0 + M1 11 passed, 0 failed (floor projection 11 confirmed). The same job went red on an unrelated self-test (run-registered-suites T2e KNOWN_UNDERIVED), fixed in 23caa494a9.
- Stub harness: 279/279 on the new bootstrap; 98 failures when pointed at the pre-change bootstrap (RED proven).
- Rehearsal suite: 116/116; the 12 new rows all RED against the pre-change workflow/tf.
- Capture suite 158/158; plan-shape 25/25 (3 script mutants); emit 73/73; poll 185/185; census 85/85.
- git-data-userdata-budget.sh: stored 24176 B / 32768 B cap (headroom 8592 B), was 22284 B.
- AC4b: `git diff f2aa5b1bee..HEAD` over cloud-init-git-data.yml shows only the dmsetup package and the GIT_DATA_PLAINTEXT_VOLUME_ID move; modules/git-data-userdata/ unchanged.

### Deviations from the plan (each deliberate)
- Block-device test is `stat -L -c %F` rather than `[ -b ]`, so the non-root harness can drive it (PATH stub) without a new env seam.
- The harness reaches /dev/shm, /dev/mapper/ and /sys/ by absolute-path rewrite of the extracted unit (the runuser precedent) instead of shadowing mktemp.
- A second `Invalid` check right after the mount, so a COW overflow reads reason=snapshot before any superblock read; arm D accepts snapshot|mount as planned.
- `RUNG2_REPLACE_BOOT=PASS` is appended only on PASS (a FAIL exits 1 and appends nothing), mirroring the reboot arm; the upload gate makes a FAIL non-releasable either way.
- The committed git-data-rung2-boot-evidence.env is DELETED in this PR: the runbook's two-PR sequence requires the payload PR to delete voided evidence (the plan's "out of this PR" meant regenerating it).
- The teardown job carries no `environment:`: the environment has required reviewers, and a second approval would leave a paid host running. It uses only the repo-level DOPPLER_TOKEN.
- The seed pins its rendered ingest URL to git-data's own source literal and its host label by anchored ERE (credential-refusal lint); Doppler prd_terraform has no BETTERSTACK_INGEST_URL override, so the default renders.
- run-registered-suites KNOWN_UNDERIVED gains the loopback suite (same #7076 shape as its two siblings).
- GDPR gate at work exit: cumulative diff matches no canonical-regex path; skipped per the skill.
