---
title: "fix: drop --die-with-parent from the deploy bwrap probe (docker-exec PDEATHSIG race, #8016)"
type: fix
date: 2026-10-01
slug: deploy-bwrap-probe-sigkill-canary-rollback
branch: feat-one-shot-8016-bwrap-probe-rc137
issue: 8016
closes: 8016
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

<!-- lane: spec.md absent for this branch (one-shot path, no brainstorm) - defaulted to cross-domain (fail-closed). -->

## Enhancement Summary

**Deepened on:** 2026-10-01
**Sections enhanced:** Proposed Solution 3, Technical Considerations, Observability, Research Insights, Dependencies & Risks, Phase 1/3/4/5
**Agents used:** security-sentinel, architecture-strategist, observability-coverage-reviewer, test-design-reviewer, best-practices-researcher, a verify-the-negative grep pass; plus the earlier repo-research, learnings-researcher, functional-overlap, CTO and plan-review panel (DHH, Kieran, code-simplicity).

### Key improvements

1. Mechanism now source-backed: PR_SET_PDEATHSIG fires on termination of the parent THREAD (man7), and upstream calls `--die-with-parent` "a massive footgun" (containers/bubblewrap#692, verified live) - our measured race is the documented class, not a novel theory.
2. Test mechanics corrected against the real harness: argv recording is a pre-`case` hook in the mock keyed on any arg containing `bwrap` (the `bwrap-trace`/`bwrap-fail` arms alone are not the only arms and exit early), written to a caller-owned `mktemp -d` log (not `$MOCK_DIR`, which `run_deploy` deletes), one joined line per exec, token match on space-padded whole tokens.
3. Observability honesty: a durable recurrence detector does not exist; deferred with tracking issue #9342 (Better Stack alert modeled on the luks-deadman pair) instead of claiming email is the route.

### New considerations discovered

- The blocking probe never exercised `--unshare-user`, `--unshare-net` or `--ro-bind`; tenant-isolation fidelity rests on the non-blocking faithful canary (ADR-079). Pre-existing; now stated plainly.
- After the fix, a seccomp/AppArmor regression on `prctl` would pass the blocking gate and be caught only by the faithful canary post-deploy (the designed "faithful FAIL + legacy PASS" signal).
- The apply workflow is fail-closed across web-1 and web-2; a web-2 outage delays delivery to both.
- A stale `server.tf` NOTE (#2205) claims `ci-deploy.sh` is also copied into cloud-init `write_files`; no such entry exists (out of scope, noted).

## Overview

The blocking bwrap probe in `apps/web-platform/infra/ci-deploy.sh` (block beginning
`echo "Verifying bwrap sandbox..."`, failure arm `final_write_state 1 "canary_sandbox_failed"`)
rolls back production deploys at random. Since PR #8026 every rollback names itself, and all of
them name the same thing: `rc=137` (SIGKILL), `ms` 73-120, `cstate=running`, `err_chars=0`,
`bwrap_err="<empty>"`.

**Named cause (measured, reproduced, not inferred):** the probe argv carries `--die-with-parent`.
That flag makes bwrap arm `PR_SET_PDEATHSIG(SIGKILL)` as its first act. A process started by
`docker exec` is spawned by runc, which exits a few milliseconds after the exec starts; when the
arming lands before that exit, the kernel delivers the SIGKILL to the freshly started process. The
signal arrives before bwrap does any work, which is why stderr is empty, the container is still
`running`, and the failing `ms` is the same as the passing `ms` (about 100 ms of `docker exec`
round-trip). It is a spawn-timing race, not a sandbox failure.

**Fix:** remove `--die-with-parent` from the blocking probe (and from the one sibling `docker exec`
bwrap site, `audit-bwrap-uid.sh`), pin both in the existing tests, keep the reason string and the
DEPLOY_ROLLBACK line exactly as measured today, and close #8016.

## Problem Statement / Motivation

- Prod impact: 16 rollbacks in the 7 days to 2026-09-30; 7-day rate 16 / (127 OK + 16) = 11.2%
  (prior 7 days: 3 / (102 + 3) = 2.9%). Each rollback leaves `main` ahead of prod until the next
  merge's deploy or a manual rerun, and each fires the release-failure email.
- The gate is firing on a probe artifact while the sandbox it protects is healthy: the non-blocking
  faithful SDK canary (`run_faithful_sandbox_canary`, ADR-079) reports `consecutive_pass` 719+ over
  the same period, because it runs the real SDK argv (which also carries `--die-with-parent`) from a
  node parent, not from a `docker exec`-spawned process.
- The issue's original "stale canary" framing was withdrawn in the 2026-09-10 correction comment
  (two different canaries sharing the word "sandbox"); this plan does not revisit it.

## Research Reconciliation - Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Issue body: a freshness gate treats a stale-but-passing canary as a failure | Withdrawn on the issue itself; no freshness comparison exists; the passing payload block is the non-blocking faithful canary | Ignore; do not touch the payload or the faithful canary |
| Sweeper arm (a): "fix the named cause" - implies rc/ms/cstate name a cause | They name a *shape* (signalled child, nothing printed, container alive), not a cause | Diagnose by measurement: Better Stack distribution + local reproduction (below) |
| `ci-deploy.sh` NOTE block: "The bwrap argv is deliberately untouched" | That guard exists against *adding* `--unshare-user --proc /proc` (#4932, rolled back every deploy). Removing a flag is a different edit and is the fix | Rewrite the NOTE to say what may and may not change, with the measured numbers |
| Repo-research pass: "docker exec is not threaded; no PDEATHSIG parent race possible" | False as measured: `setpriv --pdeathsig SIGKILL true` (no bwrap at all) under `docker exec` dies rc=137 in 4.8% of 2500 runs | Mechanism recorded in Research Insights; claim not carried forward |
| Code comments: "the probe passes ~97.6% of the time" | 7-day pass rate was 88.8%; 14-day 92.2%; the figure is a stale point estimate | Delete the number from the rewritten comment (a dated rate in a code comment is the next stale figure); numbers live in the learning file |
| ADR-079 treats the legacy probe as the gate during dark-launch | It does not specify the probe's argv; no ADR decides `--die-with-parent` for the probe | No ADR change required (see Architecture Decision gate) |

## Research Insights

**Premise Validation.** #8016 is OPEN with no closing PR (`closedByPullRequestsReferences` empty);
draft PR #9336 is this branch. The cited block exists on this branch's `ci-deploy.sh`. The
proposed mechanism (remove a flag) is not in any ADR's rejected-alternatives: ADR-079 keeps the
legacy probe as the blocking gate and never lists its argv; the only prior argv decision is the
#4932 revert (adding `--unshare-user --proc /proc` rolled back every deploy), which constrains
*additions*, not this removal. Stale premise found and carried: the issue's headline contradiction
(already corrected by its author).

**Property List.**

1. P1 - the gate rolls a deploy back only when bwrap cannot create the sandbox inside the canary.
2. P2 - a rollback line names only what was measured (`rc`, `ms`, `cstate`, `err_chars`,
   sanitized `bwrap_err`); the deploy reason stays `canary_sandbox_failed`; no cause is asserted in
   a string the job did not measure.
3. P3 - the probe's verdict does not depend on how fast runc exits after `docker exec` spawns it.
4. P4 - no other `docker exec`-spawned bwrap site in the repo's deploy/audit tooling carries the same
   latent flake.

**Cut List** (mechanism -> property -> what already covers it / why cut):

- Retry-on-rc=137 loop -> would buy P1 by masking -> the cause removal buys it; a retry also hides a
  genuine SIGKILL (OOM at the canary's 1536m cap), which is exactly the signal P2 wants preserved.
- New reason string (for example `canary_sandbox_probe_signalled`) -> P2 -> `final_write_state`
  consumers (`web-platform-release.yml` catch-all, `ci-deploy.test.sh`, the #8016 sweeper) key on
  `canary_sandbox_failed`; the measured fields already ride the DEPLOY_ROLLBACK line, and the cause
  is *unmeasurable* by the job itself, so naming it in the reason would be the exact defect the issue
  title describes.
- `timeout` wrapper around the exec -> none -> no hang was observed (failing `ms` equals passing `ms`).
- `sh -c 'exec bwrap ...'` wrapper that keeps the flag -> P3 -> measured at 0.7% (17/2500): it
  narrows the window, it does not close it.
- Promoting the faithful canary to blocking, or replacing the legacy probe -> out of scope; ADR-079
  gates promotion on a soak.
- New `check-bwrap-exec-argv.sh` census script + its own test suite (plan v1) -> P4 -> cut by plan
  review (DHH, code-simplicity and Kieran all converged): only two live sites exist, both pinned by
  per-site assertions; the census regex also over-matched (`soleur-bwrap` in three `docker run`
  statements) and carried a brittle site-count floor. Replaced by one small assertion in the existing
  `ci-deploy.test.sh` (Proposed Solution 3).
- ADR-079 addendum and a full post-mortem addendum (plan v1) -> none -> the plan's own Architecture
  gate concludes no decision is made; the learning file is the single prose home, the runbook carries
  the reading guide, the post-mortem gets a two-line pointer.
- Committing the Docker reproduction harness as a CI test -> needs docker + bwrap + ~2 minutes; it
  is embedded in the learning file as a runnable loop instead.

**Measured evidence (all numbers pulled during planning).**

| Source | Measurement |
|---|---|
| Better Stack, 14d, `DEPLOY_ROLLBACK: bwrap sandbox non-functional` | 19 rows, 19/19 `rc=137`, `err_chars=0`, `cstate=running`, `bwrap_err="<empty>"`, `ms` 73-119 |
| Better Stack, 7d | 16 rollback rows vs 127 `SANDBOX_PROBE_OK` rows (11.2%); prior week 3 vs 102 (2.9%) |
| Better Stack, passing probes | `ms` mean 94, max 133 - indistinguishable from the failing 73-120 |
| Better Stack timeline, v0.300.2 | canary health/login/dashboard pass, then rollback within the same second; no kernel/OOM line in the window |
| Local Docker 29.7 / runc, `--init`, bwrap 0.8, 2500 execs: probe argv WITH `--die-with-parent` | 75 nonzero, all rc=137 (3.0%) |
| Same, argv WITHOUT the flag | 0 / 2500, then 0 / 5000 on a second run |
| `docker exec c setpriv --pdeathsig SIGKILL true` (no bwrap) | 120 / 2500 rc=137 (4.8%) - mechanism is independent of bwrap |
| Same, arming delayed by 200 ms (`sleep 0.2; exec setpriv ...`) | 0 / 2500 - timing race at process start |
| `sh -c 'exec bwrap --die-with-parent ...'` | 17 / 2500 (0.7%) |
| Gate still bites: same argv, container without SYS_ADMIN / default seccomp | `rc=1`, "No permissions to create new namespace" |

The local rate (3.0%) matches the prod 14-day rate; the local failure signature (137, empty stderr,
container alive) matches all 19 prod rows.

**External sources (verified live during deepen).**
- man7 `prctl(2)` `PR_SET_PDEATHSIG`: the "parent" is the thread that created the process; the signal is
  sent when that thread terminates.
- containers/bubblewrap#692 "--die-with-parent is a massive footgun" (open; title verified via `gh api`).
- golang/go#9263 "Setting Pdeathsig while PID 1 causes all child processes to die on birth" (verified via
  `gh api`) - same family: arming PDEATHSIG interacts with the spawner's thread/process lifetime.
- Upstream mitigation named for bwrap is `--sync-fd` (spawner-held pipe) rather than `--die-with-parent`;
  not adopted here because `docker exec` gives the probe no spawner-held descriptor, and the probe's child
  is `true`, so lifetime coupling buys nothing (analysis, not a cited claim).
- The rule the learning file records is precise, not blanket: arming PDEATHSIG is unsafe when the arming
  process's parent is a short-lived spawner (the runc exec path). The faithful canary and `c4-render.ts`
  arm it from a long-lived node parent that blocks in `spawnSync`/`spawn`, which is why they do not flake.

**Verify-the-negative results.** `die-with-parent` outside `knowledge-base/` and `node_modules` occurs in:
`ci-deploy.sh:3987` and `audit-bwrap-uid.sh:77` (both host-side `docker exec`, the two fix sites),
`server/c4-render.ts:417` (node `spawn` argv inside the app), `scripts/sandbox-canary.mjs:308` (arity set
only), `sandbox-canary-argv.json:9` and `test-fixtures/sandbox-canary/split-unshare-argv.json:11` (captured
data, replayed by node), `plugins/soleur/skills/preflight/SKILL.md:1186` (host-side), and test code under
`apps/web-platform/test/`. Zero hits for `pdeathsig`. No copy of the probe statement exists in
`cloud-init.yml`; no test asserts the old probe argv (Guard 2 is net-new coverage). The three
`soleur-bwrap` `docker run` option sites (`ci-deploy.sh:3814-3815`, `:4139-4140`, `cloud-init.yml:789-790`)
confirm that a bare `\bbwrap\b` match would false-positive.

**Institutional learnings applied.**
`bwrap-deploy-gate-undiagnosable-rollback-postmortem.md` (the capture form `VAR="$(cmd)" || RC=$?`
and the `<empty>` sentinel must survive untouched - they gate the rollback and carry the diagnosis);
`2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md` (never validate a gating check
against a mock alone; this fix's verification is a live-runtime repro, not only the mocked suite);
`2026-07-03-faithful-canary-capture-must-run-in-the-deploy-base-image.md` (the faithful canary, not
the legacy probe, owns SDK-argv fidelity); `2026-07-01-sandbox-observability-gate-signal-timing...`
(run the pre-existing suite immediately after touching a gate).

**Open Code-Review Overlap.** None - no open `code-review` issue references
`ci-deploy.sh`, `ci-deploy.test.sh`, `audit-bwrap-uid.sh` or the #8016 sweeper script.

**Functional overlap / community discovery.** No community artifact covers a docker-exec PDEATHSIG
race; no uncovered stack.

## Proposed Solution

### 1. The probe (the fix)

`apps/web-platform/infra/ci-deploy.sh`, probe statement:

```bash
BWRAP_ERR="$(docker exec soleur-web-platform-canary bwrap --new-session --dev /dev --unshare-pid --bind / / -- true 2>&1)" || BWRAP_RC=$?
```

Everything else in the block is untouched on purpose: the rc-preserving capture form (it GATES the
rollback), `_now_ms` timing, `_cred_err_tail` sanitizer, the `DEPLOY_ROLLBACK` / `SANDBOX_PROBE_OK`
line shapes (the sweeper and `ci-deploy.test.sh` anchor on them), `final_write_state 1
"canary_sandbox_failed"`.

What the probe still proves (P1): bwrap can create a PID namespace, mount a new `/dev`, and
bind-mount `/` under the canary's AppArmor + seccomp profiles. `--new-session` stays (it is a
`setsid`, not a PDEATHSIG arm). What it stops asserting is "prctl(PR_SET_PDEATHSIG) works", which is
trivially true and is still exercised by the faithful canary on the real SDK argv.

What `--die-with-parent` bought here: cleanup of a lingering bwrap if the `docker exec` client
died mid-probe. The child is `true`; it lives about a millisecond.

Comment work in the same hunk: rewrite the `NOTE: a prior change (#4932)` block to state the rule
precisely - additions that diverge from the real SDK argv (`--unshare-user --proc /proc`) rolled
back every deploy; `--die-with-parent` is deliberately absent because of the docker-exec spawn race
(one rule line plus a pointer to the learning file, no numbers). Delete the stale "~97.6%" figure
rather than replacing it.

### 2. Sibling site

`apps/web-platform/infra/audit-bwrap-uid.sh` (the MU1 audit script) execs `docker exec "$CONTAINER"
bwrap --new-session --die-with-parent --unshare-user --unshare-pid --dev /dev --bind / / -- id -u`.
Same spawn path, same latent flake (a false `CLONE_NEWUSER rejected` FAIL). Drop the flag. Its test
mock's `exec` arm only echoes `DOCKER_EXEC_STDOUT` today, so extend it to append the argv to a
`DOCKER_EXEC_ARGV_LOG` file (`printf '%s\n' "$*" >> "${DOCKER_EXEC_ARGV_LOG:-/dev/null}"` - a file, not
stdout, which feeds the PASS message `run_case` asserts on; the `/dev/null` default keeps an unset
variable from failing the mock under `set -e`; pass the path through `run_case`'s `"$@"` env mechanism)
and assert the flag is absent while `--unshare-user --unshare-pid` remain.

### 3. Pin the flag's absence in the existing test (no new script)

Two additions to `apps/web-platform/infra/ci-deploy.test.sh`, nothing new on disk:

- **Traced probe argv (Guard 2).** The `bwrap-trace` mock already echoes `DOCKER_EXEC:$*`, but that
  text reaches the test only after passing through `$(...)`, `_cred_err_tail` (newlines to spaces,
  redaction, last 200 chars), so a longer argv could push a token out of the tail. Record the raw argv
  instead, with these mechanics (each verified against the real harness by the test-design and security
  reviews):
  - Put ONE append in the mock `docker` script BEFORE the `case "$mode"` dispatch (next to the existing
    pre-case `pgrep` block, `ci-deploy.test.sh:385-405`), keyed on any arg matching `*bwrap*`. Recording
    inside the `bwrap-trace`/`bwrap-fail` arms is wrong: other modes (`trace`, `apparmor-trace`,
    `default`) also answer the probe's `docker exec`, and both arms `exit` early (`:887`, `:921`).
  - The log lives in a caller-owned `mktemp -d` (as `:3225` does) and is truncated per scenario - NOT
    under `$MOCK_DIR`, which `run_deploy` deletes on its EXIT trap (`:1292`); a stale log from one scenario
    must not satisfy another's "requires" checks. Export `MOCK_DOCKER_ARGV_LOG` inside the scenario's own
    `$( ... )` subshell, as `:2796`/`:3235` do for `MOCK_DOCKER_MODE`.
  - One line per bwrap exec, argv joined by single spaces (`printf '%s\n' "$*"`); assertions pad the line
    with spaces and match whole tokens (`*" --die-with-parent "*`), so `--unshare-pid-foo` or `--bind / /x`
    cannot satisfy a check, and `--dev /dev` / `--bind / /` are matched as adjacent pairs.
  - Required: `--unshare-pid`, `--dev /dev`, `--bind / /`; forbidden: `--die-with-parent`; an empty or
    missing log is a FAIL. On failure print the missing/forbidden token AND the log contents.
  - Follow the file's accounting convention (`TOTAL=$((TOTAL+1))`, `PASS`/`FAIL`, helper shape of
    `assert_bwrap_canary_*` at `:2790-2840`); raise `CI_DEPLOY_ASSERT_FLOOR` (`TOTAL >= floor`) by the
    number of added rows with a comment; place the new rows before that floor block.
  - `lint-shell-capture-exit.py` scans test files: any capture of `grep` needs `|| true` or an `if`; use
    `grep -cF -- '--die-with-parent'` (the leading `--` is otherwise read as an option).
- **Repo-wide absence check (Guard 1).** One small function `bwrap_exec_flag_violations <file...>` in
  the same test: join backslash continuations, drop full-line comments, and flag any statement that
  contains `docker exec` AND `bwrap` as a command token (`(^|[[:space:];|&(/"'])bwrap([[:space:]"']|$)`,
  which also catches `/usr/bin/bwrap` and quoted forms, while `soleur-bwrap` in the `docker run`
  AppArmor/seccomp options does not match) AND `--die-with-parent` or `--pdeathsig`. Trailing inline
  comments (` # ...`) are stripped before matching. Known blind spots, stated rather than hidden: it scans
  `*.sh` only (a `docker exec ... bwrap` in `.yml`/`.mjs`/workflow files is out of its assembly; none exist
  today), and a flag smuggled through a shell variable is caught only on the ci-deploy path by Guard 2. It runs over every non-test `*.sh` under `apps/web-platform/infra/` (recursive)
  and must return nothing; it is also driven over two inline fixtures (flag on a continuation line;
  `setpriv --pdeathsig` form) that it must flag, so the matcher cannot silently match nothing.

### 4. Reason string / diagnosis fields (unchanged, by decision)

The deploy reason stays `canary_sandbox_failed`; the `DEPLOY_ROLLBACK ... non-functional` text stays
(consumers anchor on it). If a SIGKILL ever recurs after this fix, the same line names it
(`rc=137`, `ms`, `cstate`, `err_chars`) and nothing in the string asserts a cause the job did not
measure. The runbook's `rc` row is updated: the (`rc=137`, `cstate=running`, `err_chars=0`, `ms` equal
to a passing run's) signature is documented as the HISTORICAL PDEATHSIG-race signature; after this fix
any `rc=137` is by definition not that race and is unexplained (an OOM at the 1536m cap also shows
`cstate=running` with empty stderr), with `ms` far from the passing mean as the discriminator.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Remove `--die-with-parent` (chosen) | Removes the cause; 0 / 7500 failures locally; capability coverage unchanged |
| Bounded retry on rc=137 | Rejected: masks a real SIGKILL; treats the symptom |
| `sh -c 'exec bwrap ...'` wrapper | Rejected: measured 0.7%, not 0% |
| New distinct reason string naming the race | Rejected: unmeasurable by the job; breaks consumers' anchors |
| Replace the legacy probe with the faithful canary | Out of scope; soak-gated by ADR-079 |
| Do nothing; keep rerunning failed deploys | Rejected: 11% of deploys, rising |

## Technical Considerations

- **Delivery path.** `ci-deploy.sh` reaches the host through the existing
  `apply-deploy-pipeline-fix.yml` workflow (path trigger on `apps/web-platform/infra/ci-deploy.sh`,
  pushes `/usr/local/bin/ci-deploy.sh` and triggers one graceful redeploy). No new infrastructure,
  no Terraform change, no operator step.
- **Runtime verification beyond mocks.** The mocked suite cannot see a spawn race. Verification is the
  live Docker loop (Phase 4) on the final argv, extracted from the file so it cannot drift.
- **Shell conventions.** Keep `set -e` safety of the existing capture; no new `logger` calls outside
  the `|| printf` fallback pattern; shellcheck clean.
- **Ordering at delivery.** `apply-deploy-pipeline-fix.yml` pushes the script and triggers one
  graceful redeploy; a deploy already in flight when the push lands still runs the old probe and can
  flake once. A failed deploy is recovered by the next merge's deploy or a rerun - no new exposure.
- **Coverage shift, stated.** The blocking probe never exercised `--unshare-user`, `--unshare-net` or
  `--ro-bind` (the real SDK argv does, `sandbox-canary-argv.json:9-14,87-90`); tenant-isolation fidelity
  rests on the non-blocking faithful canary (ADR-079), unchanged by this fix. Dropping the flag also stops
  the blocking gate from exercising `prctl(PR_SET_PDEATHSIG)`; seccomp allows `prctl` unconditionally
  (`seccomp-bwrap.json:265`) and AppArmor has no signal/prctl rule, so a future regression of that call
  would pass the gate and surface only as the faithful canary's designed "faithful FAIL + legacy PASS"
  Sentry signal post-deploy. Neither hole is widened by this change.
- **Delivery is fail-closed across both web hosts.** `apply-deploy-pipeline-fix.yml` must reach web-1 and
  web-2; a web-2 outage delays the fix on both. Phase 5 checks the deploy-script parity/sha evidence for
  both hosts, not only web-1 Better Stack rows. (Out of scope, noted: the `server.tf` #2205 NOTE claims a
  cloud-init `write_files` copy of `ci-deploy.sh` that does not exist.)
- **No new test file.** The changes extend existing suites (`ci-deploy.test.sh`, `audit-bwrap-uid.test.sh`),
  so `suite-shard-legs.tsv` / shard parity is untouched.

## User-Brand Impact

- **If this lands broken, the user experiences:** a deploy that either keeps rolling back at random
  (stale prod, delayed fixes and features, release-failure emails) or, worse, a gate that no longer
  catches a non-functional agent sandbox so a release ships whose workspaces are not isolated.
- **If this leaks, the user's workflow is exposed via:** no new data path; the only exposure vector
  is the second failure above (gate weakened), which the capability assertions in
  `ci-deploy.test.sh` (argv still carries `--unshare-pid`, `--dev /dev`, `--bind / /`) and the
  live broken-sandbox control (`rc=1` without SYS_ADMIN) are written to prevent.
- **Brand-survival threshold:** `aggregate pattern`. The change removes one non-isolating flag; the
  namespace/mount capability checks that protect tenant isolation are untouched and re-proven
  against a deliberately broken sandbox. No per-user data surface is added or widened.

## Architecture Decision (ADR/C4)

No architectural decision is made or changed: no boundary, substrate or resolver moves, and
ADR-079 keeps the legacy probe as the blocking gate (it does not list the probe's argv, so nothing
in it is contradicted - CTO review confirmed). CTO suggested a one-paragraph ADR-079 addendum;
plan review (DHH, code-simplicity) cut it because the plan itself concludes no decision is made, so
the constraint (a bwrap spawned by `docker exec` must not arm PDEATHSIG) lives in the learning file
and the runbook. C4: checked all
three model files for the affected elements - the deploy host and canary container are modeled as
the existing deploy-pipeline/container elements with no flag-level detail, no new actor, system,
data store or relationship appears, and no derived cardinality moves; the count-parity gate
(`plugins/soleur/test/c4-count-parity.test.sh`) is run in Phase 4 as the evidence, not reasoning
about actors. The learning file (not an ADR) records the platform fact.

## Observability

```yaml
liveness_signal:
  what: one `SANDBOX_PROBE_OK` or `DEPLOY_ROLLBACK: bwrap sandbox non-functional` journald line per deploy, tagged ci-deploy, shipped to Better Stack by Vector (existing)
  cadence: per deploy
  alert_target: release-failure email (deploy arm of web-platform-release.yml); the #8016 follow-through sweeper stays as-is but goes inert when the issue closes
  configured_in: apps/web-platform/infra/ci-deploy.sh (probe block) and apps/web-platform/infra/vector.toml (SYSLOG_IDENTIFIER allowlist)

error_reporting:
  destination: Better Stack Logs via logger -t ci-deploy, with the printf fallback to the webhook leg when journald is unavailable
  fail_loud: the DEPLOY_ROLLBACK line with rc, ms, cstate, err_chars and bwrap_err, plus final_write_state reason canary_sandbox_failed surfaced as the release workflow ::error:: line and the failure email

failure_modes:
  - mode: the probe is SIGKILLed again after the flag removal (a different killer, for example OOM at the 1536m canary cap)
    detection: journald to vector to a Better Stack Logs row (rc=137 with cstate and err_chars on the DEPLOY_ROLLBACK line; ms far from the passing mean separates a hang or OOM from the old instant kill), and the workflow run log ::error:: annotation from final_write_state canary_sandbox_failed
    alert_route: release-failure email plus the workflow run log; a human reads the runbook row. No durable log-based alert exists today - deferred with tracking issue #9342 (Better Stack alert modeled on the luks-deadman pair); recurrence does not auto-reopen the tracker once it is closed
  - mode: a PDEATHSIG-arming flag reappears on a docker-exec bwrap statement in infra scripts
    detection: the repo-wide absence check inside ci-deploy.test.sh (Guard 1) plus the per-site argv assertions
    alert_route: red CI on the offending PR
  - mode: the argv edit weakens capability coverage so a non-functional sandbox ships
    detection: ci-deploy.test.sh asserts the recorded probe argv still carries --unshare-pid, --dev /dev, --bind / / (CI-time guard, no runtime layer); post-deploy the non-blocking faithful canary records a sandbox_broken verdict in the deploy status payload and the canary-status workflow
    alert_route: red CI on the PR; the sandbox_canary verdict in the status payload (no routed Sentry rule is claimed here)

logs:
  where: Better Stack Logs (SYSLOG_IDENTIFIER ci-deploy), host journald
  retention: Better Stack hot window plus S3 archive (betterstack-query.sh reads both; 14 days queried during this plan)

discoverability_test:
  command: bash scripts/betterstack-query.sh --since 7d --grep SANDBOX_PROBE_OK | jq -r '.raw | fromjson | select(.SYSLOG_IDENTIFIER == "ci-deploy") | .message'
  expected_output: SANDBOX_PROBE_OK
  credentials_required: Better Stack ClickHouse query credentials, supplied by running the command under doppler run -p soleur -c prd_terraform -- (BETTERSTACK_QUERY_*) - the deploy-time probe line exists only in production logs, so no unauthenticated probe can verify the same property
```

## Guard Contract

### Guard 1 - no PDEATHSIG-arming flag on a docker-exec bwrap statement in infra scripts

**Property.** No statement in the non-test shell scripts under `apps/web-platform/infra/` that spawns
bwrap through `docker exec` arms `PR_SET_PDEATHSIG` (`--die-with-parent`, `--pdeathsig`) on the
process runc spawns.

**Assembly.** Every statement (backslash-continuations joined, full-line comments removed) in every
non-test `*.sh` file, searched recursively under `apps/web-platform/infra/`, that contains `docker exec`
and `bwrap` as a command token. The chokepoint is the statement-level scan over the directory, not a
named file list, so a third site is covered without editing the check. Members today: the ci-deploy.sh
probe and the audit-bwrap-uid.sh statement (flag on a continuation line, which is why the join exists).
Out of assembly by design: host-side bwrap with a long-lived parent (preflight Check 10, ADR-175),
the faithful canary's node-spawned bwrap, and `docker run` statements (their `soleur-bwrap` AppArmor and
seccomp option names are not the command token).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `--die-with-parent` to the ci-deploy.sh probe statement | RED |
| 2 | Inline fixture: flag on a backslash-continuation line of a `docker exec ... bwrap` statement | the function flags it (the join must see it) |
| 3 | Inline fixture: `setpriv --pdeathsig SIGKILL bwrap ...` inside a `docker exec` statement | flagged (equivalent arming form) |
| 4 | Point the function at zero files, or break the command-token regex so nothing matches (own dispatch) | the inline fixtures stop being flagged, so the suite goes RED - an empty matcher cannot pass |
| 5 | Add a second violating statement after a clean first one in the same fixture | both reported (the scan does not stop at the first member) |

**Harness rows.** H1: stub the function to return nothing - rows 2, 3 and 5 (fixtures that MUST be
flagged) go RED. H2: stub it to flag everything - the must-PASS inputs go RED. Must-PASS inputs that
differ from the real tree: a `docker run ... --security-opt apparmor=soleur-bwrap` statement, a
full-line comment mentioning `--die-with-parent`, and a host-side `bwrap --die-with-parent` statement
with no `docker` token.

**Anchor.** No stored value (no floor, no hash): the property is absence, and the positive controls
live in the same test as inline fixtures. The residual is consistency, not integrity: one diff can edit
both the script and this test; the behavioural proof is the live Docker loop recorded in the learning
file.

### Guard 2 - the probe still exercises the sandbox capability

**Property.** The blocking probe's actual `docker exec` argv, as recorded from a real run of the
deploy script, still invokes bwrap with `--unshare-pid`, `--dev /dev` and `--bind / /`, and does not
carry `--die-with-parent`.

**Assembly.** The single `docker exec ... bwrap` call made in the probe block, observed through the
`MOCK_DOCKER_ARGV_LOG` file written by the mock's pre-`case` hook for any mock mode that sees a bwrap
arg (the recorded argv of what the script ran, not a grep of the source and not the sanitized stdout copy), so a
refactor that moves the statement cannot hide it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `--unshare-pid` from the probe | RED |
| 2 | Replace the probe statement with `true` so docker never sees a bwrap exec (own dispatch) | RED (empty argv log is refused) |
| 3 | Re-add `--die-with-parent` after a compliant argv | RED |
| 4 | Remove `--bind / /` while keeping the other two | RED (each token is checked) |

**Harness rows.** H1: stub the assertion helper to always pass - rows 1-4 then go green, proving they
depend on the helper (so an un-stubbed run is what turns them RED). Must-PASS: the same tokens in a
different order.

**Anchor.** None stored; literal tokens in the test.

## Implementation Phases

### Phase 0 - Repro harness (evidence, re-run at work time)

Throwaway; nothing committed. In any image that has `bwrap` and `setpriv`, container started with
`--init --security-opt seccomp=unconfined --security-opt apparmor=unconfined --cap-add SYS_ADMIN`
(local analogue of the soleur-bwrap profiles; the race is independent of them):

```bash
loop() { n=$1; shift; bad=0; for i in $(seq 1 "$n"); do docker exec C "$@" >/dev/null 2>&1 || bad=$((bad+1)); done; echo "n=$n nonzero=$bad"; }
loop 2500 bwrap --new-session --die-with-parent --dev /dev --unshare-pid --bind / / -- true   # expect ~3% rc=137
loop 2500 bwrap --new-session --dev /dev --unshare-pid --bind / / -- true                     # expect 0
loop 2500 setpriv --pdeathsig SIGKILL true                                                    # expect ~5%
```

### Phase 1 - RED (tests first; `cq-write-failing-tests-before`)

1. `ci-deploy.test.sh`: add the pre-`case` `MOCK_DOCKER_ARGV_LOG` append to the mock `docker` (any arg
   matching `*bwrap*`); add the Guard 2 assertion helper (three required tokens, one forbidden, empty-log
   refusal, failure output names the token and prints the log) and the Guard 1 `bwrap_exec_flag_violations` function with its inline fixtures. Fails now
   on the forbidden-token and real-tree checks.
2. `audit-bwrap-uid.test.sh`: mock `exec` arm appends argv to `DOCKER_EXEC_ARGV_LOG`; assert
   `--die-with-parent` absent, `--unshare-user --unshare-pid` present. Fails now.

### Phase 2 - GREEN

1. Edit the probe statement + NOTE/comment block in `ci-deploy.sh` (rule line + pointer, no numbers);
   delete the same stale "97.6% of runs" figure from the comment in `ci-deploy.test.sh` (~line 917).
2. Edit `audit-bwrap-uid.sh`. Phase 1 tests pass.

### Phase 3 - Docs

1. `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`: update the `rc` row
   (the 137 signature is historical; post-fix any `rc=137` is unexplained, discriminate by `ms`), and
   the "Closing #8016" paragraph (closed by the fix; no automatic reopen - recurrence is noticed via
   the release-failure email, the workflow `::error::` annotation and this row; name #9342 as the
   pending durable alert). Triage steps lead with the existing no-SSH probes only (the
   `betterstack-query.sh` query, the `::error::` annotation, the deploy-status webhook body); remediation
   is a redeploy via `apply-deploy-pipeline-fix.yml`, never a host command.
2. `knowledge-base/engineering/operations/post-mortems/bwrap-deploy-gate-undiagnosable-rollback-postmortem.md`:
   a two-line pointer to the learning file under the open-root-cause note.
3. New learning `knowledge-base/project/learnings/bug-fixes/2026-10-01-docker-exec-pdeathsig-race-sigkills-bwrap-probe.md`:
   the single prose home - mechanism (with the man7, bubblewrap#692 and golang#9263 sources), measurement
   table, repro loop, and the precise rule: "arming PDEATHSIG is unsafe when the arming process's parent
   is a short-lived spawner such as the runc `docker exec` path; never put it on a one-shot probe; a
   long-lived node parent that blocks in `spawnSync` is safe".

### Phase 4 - Verification (before PR ready)

- Live loop on the final argv, with the probe argv EXTRACTED from the `ci-deploy.sh` statement (not
  retyped): 5000 execs, expect 0 nonzero; broken-sandbox control (no SYS_ADMIN) expect `rc=1`.
- `bash apps/web-platform/infra/ci-deploy.test.sh` and `audit-bwrap-uid.test.sh` green; shellcheck on
  touched scripts; Guard 2 mutation rows 1-4 applied and confirmed RED, then reverted.
- `python3 scripts/lint-guard-contract.py` on this plan; `bash plugins/soleur/test/c4-count-parity.test.sh`.
- PR body: `Closes #8016`, the measurement tables, the 0 / 5000 result, and a plain statement that this
  REMOVES a flag.

### Phase 5 - Post-merge (informational, not an acceptance criterion)

`apply-deploy-pipeline-fix.yml` pushes the script (to both web hosts, fail-closed) and triggers one
redeploy; confirm the script-sha parity evidence covers web-1 and web-2. Read the runbook's Better
Stack query once after the next several deploys: expect `SANDBOX_PROBE_OK ... rc=0` rows and no new
`rc=137` rollback row. One redeploy cannot discriminate the fix at the old 3-11% failure rate, so this
is a smoke read; the live A/B (0 / 7500 versus 3.0%) is the proof.

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` - probe argv (~line 3987), NOTE block, stale rate comment
- `apps/web-platform/infra/ci-deploy.test.sh` - pre-`case` mock argv log, Guard 1 function + Guard 2 assertions, assert-floor bump, stale 97.6% comment
- `apps/web-platform/infra/audit-bwrap-uid.sh` - drop the flag (lines ~75-80)
- `apps/web-platform/infra/audit-bwrap-uid.test.sh` - argv-recording mock + assertions
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` - rc row + closing paragraph
- `knowledge-base/engineering/operations/post-mortems/bwrap-deploy-gate-undiagnosable-rollback-postmortem.md` - two-line pointer

## Files to Create

- `knowledge-base/project/learnings/bug-fixes/2026-10-01-docker-exec-pdeathsig-race-sigkills-bwrap-probe.md`

Files deliberately not touched: `scripts/followthroughs/bwrap-probe-selfreport-8016.sh` (inert once the
issue closes), `sandbox-canary-argv.json` and `sandbox-canary.mjs` (the faithful canary must keep the
real SDK argv including `--die-with-parent`), `web-platform-release.yml` (reason handling is a
catch-all and unchanged), ADR-079 (no decision changes).

## Acceptance Criteria

- [ ] The probe statement in `ci-deploy.sh` no longer contains `--die-with-parent`; it still contains
  `--new-session --dev /dev --unshare-pid --bind / / -- true` and the `|| BWRAP_RC=$?` capture form.
- [ ] `ci-deploy.test.sh` records the probe's raw argv in both mock modes, asserts the three capability
  tokens and the absent flag, and (verified by mutation) fails when a token is removed or the flag re-added.
- [ ] `audit-bwrap-uid.sh` no longer arms PDEATHSIG; its test asserts the recorded argv.
- [ ] The Guard 1 function returns nothing on the real infra scripts and flags both inline fixtures
  (continuation-line flag; `setpriv --pdeathsig`); it does not match `soleur-bwrap` option names.
- [ ] `DEPLOY_ROLLBACK` / `SANDBOX_PROBE_OK` line shapes and `final_write_state 1 "canary_sandbox_failed"`
  are byte-identical to main (the diff touches none of those lines).
- [ ] Live Docker loop on the extracted final argv: 0 nonzero in 5000 execs; control without SYS_ADMIN returns rc=1.
- [ ] Runbook, post-mortem pointer and learning file written; markdownlint clean.
- [ ] `lint-guard-contract.py` passes on this plan; shellcheck clean; c4-count-parity green.
- [ ] PR body contains `Closes #8016`, the measurement tables, and states that the PR removes a flag
  (the opposite direction of the #4932 revert, which concerned ADDING SDK-divergent flags) while the
  faithful canary keeps owning SDK-argv fidelity.

## Test Scenarios

- Given the deploy script run under the `bwrap-trace` or `bwrap-fail` mock, when the probe fires, then
  the recorded argv carries `--unshare-pid`, `--dev /dev`, `--bind / /` and not `--die-with-parent`.
- Given a statement with the flag on a backslash-continuation line of a `docker exec ... bwrap`
  command, when the Guard 1 function scans it, then it is flagged; a `docker run` statement carrying
  `soleur-bwrap` options is not.
- Given a probe that exits 137 with empty stderr (existing scenario 2), when the deploy runs, then the
  rollback line still renders `rc=137 ... bwrap_err="<empty>"` and the reason is `canary_sandbox_failed`
  (regression: the self-report survives the fix).
- Given a probe that exits 0 with stderr chatter (existing scenario 3), when the deploy runs, then no
  rollback occurs.
- Live runtime (not mocked): 5000 `docker exec` probe runs on the final argv, zero nonzero exits.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO assessed the fix as sound (flag is lifecycle hygiene, not a capability; seccomp
allows prctl; faithful canary still covers the flag). Incorporated: join backslash continuations in
the scan (done), comment drift (done); declined: an ADR-079 addendum (cut in plan review) and a
14-day acceptance read (User-Challenge, see Dependencies & Risks). Product, Marketing, Legal, Sales, Finance, Support and Operations: no
implication - deploy-pipeline tooling change with no user-facing surface, no data processing change
and no spend.

No Product/UX Gate: no UI-surface file in Files to Edit or Create.

## GDPR / Compliance

Gate evaluated: no regulated-data surface (no schema, auth, API route, migration) and none of the
cross-controller triggers (no LLM/external API on session data, no new cron reading learnings, no new
distribution surface). Skipped.

## Infrastructure-as-Code Routing

No new infrastructure. Delivery of the edited script to the host uses the existing
`apply-deploy-pipeline-fix.yml` path; no operator-run host step is introduced.

## Dependencies & Risks

- **Prod differs from the local repro (runc/kernel/Docker version).** Mitigation: signature and rate
  match (3.0% local vs 2.9-11% prod; identical rc/ms/stderr/cstate on 19/19 rows). The prod rate
  swing is consistent with host load changing how fast runc exits relative to the arming (the probe
  runs right after the canary's parallel health probes), not with a second mechanism. Residual: if
  `rc=137` persists after the fix, the line names it and a human reopens the issue; the next suspect list is
  already written down (OOM at the canary cap, a host reaper).
- **Closing on a reproduction rather than a prod soak.** The tracker's own criteria were evidence-based
  closure; the lead directed closure via the PR body once verified. The fix's verification is a
  live-runtime A/B (0 / 7500 vs 3.0%) plus a bwrap-free reproduction and a timing control. Recurrence
  detection after closure is NOT automatic: the sweeper goes inert, so a recurrence is noticed through
  the release-failure email and the runbook row, and a human reopens or files a new issue.
- **Live loop uses unconfined seccomp/AppArmor.** The prod match argument rests on signature and rate,
  not on loading `soleur-bwrap` profiles locally; the race is independent of them (the bwrap-free
  `setpriv` control reproduces it).
- **Weakening the gate.** The flag is not an isolation property; capability tokens are pinned by
  Guard 2 and the faithful canary keeps the SDK-faithful argv.
- **CTO-recommended 14-day acceptance read, not adopted as a gate.** CTO advised a ~14-day
  zero-`rc=137` acceptance read after merge. It is recorded as a User-Challenge in
  `specs/feat-one-shot-8016-bwrap-probe-rc137/decision-challenges.md` because the operator's stated
  direction (close via the PR body once verified) is the default and a soak would require keeping #8016
  open under the sweeper.
- **Recurrence detection gap, deferred with a tracking issue.** No Better Stack alert matches the
  DEPLOY_ROLLBACK line (observability review, P1). Filed as #9342 (Better Stack alert modeled on
  `soleur-workspaces-luks-deadman-fired-prd`, re-evaluate on any post-fix rollback row); not folded in
  because it is a Terraform apply on a different root and the fix removes the cause of the flake.
- **Guard 1 false positives.** A future legitimate docker-exec bwrap statement needing the flag has no
  path except editing the check; accepted - the flag is unsafe on that spawn path by measurement.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or carries filler text fails
  `deepen-plan` Phase 4.6; this one declares `aggregate pattern` with its reason.
- The `|| BWRAP_RC=$?` capture and the `<empty>` sentinel are load-bearing safety properties of the
  gate; any edit near the probe must keep them (reverting to `if !` makes the gate fail open).
- Do not "fix" the recurrence by editing the faithful canary or its fixture: its argv is captured from
  the real SDK and must keep `--die-with-parent`.
- Do not put a failure-rate figure in a code comment: the "~97.6%" it replaces was stale within weeks.
- All production-read commands in this plan are read-only (Better Stack query via the existing
  script); nothing here writes to production.

## References & Research

- Issue #8016 and comments (2026-09-10 correction; 2026-09-19..2026-09-30 recurrences).
- PR #8026 (self-report marker), PR #4932 / #4941 (argv-addition revert), ADR-079.
- `apps/web-platform/infra/ci-deploy.sh` probe block; `ci-deploy.test.sh` scenarios 1-4.
- `knowledge-base/engineering/operations/post-mortems/bwrap-deploy-gate-undiagnosable-rollback-postmortem.md`.
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` (self-report reading guide).
