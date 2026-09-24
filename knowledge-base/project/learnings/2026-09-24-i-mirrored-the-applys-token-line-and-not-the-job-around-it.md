---
title: "I mirrored the apply's token line and not the job around it"
date: 2026-09-24
category: integration-issues
module: scheduled-terraform-drift
tags: [terraform, github-actions, credentials, drift-detection, review, mutation-testing, precedent]
issue: 6612
pr: 8679
---

# I mirrored the apply's token line and not the job around it

## Problem

#6612 asked for a Sentry leg in `scheduled-terraform-drift.yml`: plan the
`apps/web-platform/infra/sentry` root full-root with `-detailed-exitcode`, authenticated
"the way `apply-sentry-infra.yml` does". The plan read the apply's binding line
(`SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_IAC_AUTH_TOKEN }}`), copied it, and added an
`env -u DOPPLER_TOKEN … -u TF_LOG_PROVIDER` wrapper to keep Doppler and debug logging away
from the third-party provider. The drift issue it filed told the operator to reconcile by
dispatching the apply. The suite was green, and the author's 12-mutant battery killed every
mutant.

A 9-seat review found two structural gaps and a test suite that pinned the wrong thing:

- **The environment.** A deny-list names what the author was thinking about. The job's
  `infra-credentials` step exports through `$GITHUB_ENV`: `HCLOUD_TOKEN` today, and after
  ADR-241's Tier-B cutover every key of the privileged project as plain names AND `TF_VAR_*`.
  A `TF_VAR_sentry_org` would choose the host the bearer token is sent to (`base_url` is built
  from it). `TF_CLI_ARGS_plan=-refresh=false` would turn the drift detector into a constant
  exit 0. None of those names were on the list.
- **The remediation.** A manual dispatch of the apply passes the same gates as a merge. For an
  object deleted in Sentry's UI the plan shows a create, and the apply's create gate refuses
  any create no recent diff explains. For a destroy, the gate reads `[ack-destroy]` from
  `head_commit.message`, which a dispatch does not have. The apply's own failure issue already
  said "Do NOT `workflow_dispatch`". The plan had verified only that the `reason` input exists.
- **The tests** pinned flag PRESENCE and line SUBSTRINGS. `-refresh=false`, `--target=`, a YAML
  comment carrying the gate text next to an ungated binding, `cond && '' || secret` (which
  always yields the secret), deleted `MATRIX_DIR` bindings, and a `row()` that ignored its
  check's status all survived.

## Solution

- terraform runs under `env -i PATH HOME AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY SENTRY_AUTH_TOKEN`.
  The root's variables have defaults, so nothing else is needed. The suite asserts the EXACT set
  of environment names terraform receives, against a decoy environment carrying every name above.
- The drift issue routes by plan content: dispatch for in-place updates only; a PR for a
  UI-deleted object; a re-run of the failed push apply, or a PR carrying `[ack-destroy]`, for a
  destroy.
- The suite asserts exact argv, parsed step-env values (not line substrings), a `row()` dispatch
  self-test, and an exact row-ID ledger instead of a slack floor. 17 workflow mutants and 4
  dispatch mutants killed; the pre-review workflow reds 7 rows.
- A redaction for `body = "…"` (uptime request bodies are not `sensitive` in provider 0.15.7).

## Key Insight

A precedent is its whole job, not the line you copied. "Authenticate the way X does" is a claim
about everything X's process receives, and "reconcile by dispatching X" is a claim about every
gate X runs. Both were read off one line each. When the thing receiving the environment is
third-party code, the only list that stays correct as other steps grow is an allowlist.

Two corollaries from the same PR:

- An exit criterion is only real if something can count it. The ADR's "3 vendor errors in 30 days"
  was unmeasurable (the shared check-in is overwritten by sibling legs within minutes; the job
  stays green on exit 1). It now names the annotation query.
- A latent test defect surfaces on whichever branch first satisfies its hidden precondition:
  `test-all-affected` row t compared a forced-diff run against a count taken from the REAL
  branch diff, so it reddened #8654 (the first infra-touching branch after #8665). Fixed in
  #8677, where review found row p had the same defect.

## Session Errors

1. **(forwarded, plan) The infra write guard blocked the first plan write** on the phrase "Sentry UI". Recovery: reworded. **Prevention:** write "Sentry's web UI" / "hand edit" in plans that describe out-of-band edits.
2. **(forwarded, plan) The deepen PAT check false-matched `var.sentry_auth_token` in prose.** Recovery: reworded. **Prevention:** none needed; the check is conservative by design.
3. **(forwarded, plan) The test-design reviewer returned no findings text twice at deepen.** Recovery: disclosed as a coverage gap; the review panel's test-design seat then found 11 survivors. **Prevention:** treat a silent seat as absent coverage and re-run it at review, as happened here.
4. **(forwarded, plan) The primary working directory switched mid-planning to another worktree.** Recovery: absolute paths. **Prevention:** brief planning subagents with absolute worktree paths (done).
5. **(forwarded, plan) A verification sweep called `decision-challenges.md` missing** after resolving a shortened path. Recovery: cited the full path. **Prevention:** cite repo-relative full paths in plans.
6. **My edit script doubled a quote (`RUN_URL=""${…}"`) in the email step.** Recovery: the suite's extracted-step run died with a syntax error (rc 2) and pointed at it. **Prevention:** after any scripted workflow edit, extract each touched `run:` block with `yaml.safe_load` and run `bash -n` on it before running suites.
7. **The first "doppler was invoked" check grepped bare `DOPPLER` and matched its own `DOPPLER_TOKEN=UNSET` flag line.** Recovery: anchored on the stub's record prefixes. **Prevention:** a stub's log lines need prefixes no other record shares; grep the prefix, anchored.
8. **A stray `git stash list` in a compound Bash call got the whole call blocked by the stash hook.** Recovery: re-ran without it. **Prevention:** never put a stash subcommand in a worktree command, even a read-only one.
9. **`gh issue create` for #8681 was refused twice** — first for naming no user-visible consequence, then because the `--body-file` path was a `$F` variable the gate cannot read. Recovery: a `Mandated-By:` line and a literal absolute path. **Prevention:** write the body file in one call and run `gh issue create --body-file <absolute path>` alone in the next.
10. **On the RED run, the real-terraform rows fell through to the operator's real `doppler` binary** via the pre-change `doppler run` path. Recovery: a doppler stub on those rows' PATH. **Prevention:** a suite that runs a real tool must stub every OTHER credentialed binary the step could reach, including on the code path the change is removing.
11. **The `env -u` deny-list missed `$GITHUB_ENV` exports and `TF_CLI_ARGS*`.** Recovery: `env -i` allowlist plus an exact env-name-set assertion. **Prevention:** routed to `plan-sharp-edges.md` (below).
12. **The remediation was never checked against the apply's gates.** Recovery: routed by plan content. **Prevention:** routed to `plan-sharp-edges.md` (below).
13. **The suite pinned presence and substrings; 11 mutants survived.** Recovery: exact argv, exact env set, parsed values, dispatch self-test, row ledger. **Prevention:** already documented in `review/SKILL.md` (prefix pins, substring anchors, dispatch axis); the review panel is the control that caught it.
14. **A post-merge Monitor keyed on "every run for the merge SHA" never settled**, because issue-event workflows keep attaching to `main`'s tip SHA. Recovery: stopped it and watched the named workflows by run id. **Prevention:** post-merge watches select runs by workflow file (`actions/workflows/<file>/runs?head_sha=`), never by the SHA alone.
15. **#8654's CI went red on `test-all-affected` row t**, a latent harness defect from #8665 triggered by the first infra-touching branch. Recovery: a separate PR (#8677), reviewed, merged, then #8654 synced. **Prevention:** a test comparing a forced-input run to an enumerated count must enumerate under the same forced input (now how `runnable_n` works).
16. **`BASELINE_DECLARED_PROBES` conflicted with a sibling that took 22→23 concurrently.** Recovery: 24, keeping both justifications; G1 verified the real count. **Prevention:** none beyond syncing early; a shared ratchet will conflict by design.
17. **Auto-merge was blocked by the prose close-keyword hook on "close #4781" in a Model Dissents bullet.** Recovery: reworded. **Prevention:** already hook-enforced; write "settle issue #N" in prose.
18. **Two ADR claims were written unmeasured** ("ADR-241 relies on the `[ERROR]` email"; "the sentry leg finishes first"). Recovery: read ADR-241 R1 (it relies on the workflow's drift detection) and restated the timing from measured plan durations. **Prevention:** already the compound inventory's inherited-framing rule; the review panel caught both.
