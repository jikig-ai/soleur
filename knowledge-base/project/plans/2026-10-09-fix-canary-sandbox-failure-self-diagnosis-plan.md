---
title: "fix: canary_sandbox_failed rollback arm self-reports why bwrap failed (diagnostics for #9871)"
type: fix
date: 2026-10-09
slug: canary-sandbox-failure-self-diagnosis
branch: feat-one-shot-9871-canary-failure-diagnostics
issue: 9871
refs: [9871, 9860]
lane: cross-domain
---

# fix: canary_sandbox_failed rollback arm self-reports why bwrap failed

## Enhancement Summary

**Deepened on:** 2026-10-09
**Sections enhanced:** Research Reconciliation, Design, Observability, Scope Check, Files to Edit
**Research agents used:** none spawned (planning subagent context; every claim below was verified inline with read-only `gh`, `git`, `grep` and Better Stack queries, command shown per claim)

### Key Improvements
1. Layer 2 is substantially EXPLAINED, not unexplained: image `v0.334.0` was built from 48d5144cf4 (pre-#9874 Dockerfile, contains `RUN setcap ...`), while its git tag points at d7dfd05aac. See Research Reconciliation.
2. The cap-free image `v0.334.1` was never deployed: `skip_reason=ci_not_green` (push CI 37964762522 red in `test-scripts (5/8)`).
3. Secondary question answered with run-level evidence and mapped to the already-open #8167.
4. Bundle gained a `prov` section (BUILD_SHA / BUILD_VERSION) so a stale or mis-tagged image is identifiable in one event; runbook update added to scope.

### New Considerations Discovered
- Tag/image provenance can diverge when two merges land inside one release duration (follow-up candidate).
- The release workflow computes the next version from tags at run time and publishes with `targetCommitish: main`, so a tag can name a commit whose image was built from an earlier push SHA.


Ref #9871, Ref #9860. This PR is diagnostics only. It does NOT fix the deploy and must never say `Closes`.

## Overview

Every web-platform deploy since the tenant-isolation change dies in `ci-deploy.sh`'s blocking legacy probe
(`docker exec soleur-web-platform-canary bwrap --new-session --dev /dev --unshare-pid --bind / / -- true`).
The failure arm records only the first 200 characters of the probe's stderr, so the cause cannot be read from
Better Stack. This plan adds a bounded, read-only, sanitised diagnostic bundle in that arm, emitted as
`SOLEUR_CANARY_SANDBOX_DIAG` journald markers before `docker stop`, so the next failed deploy names its own
cause with no SSH. About 60 lines of shell plus tests.

## Research Reconciliation: brief vs. measured reality

The pipeline brief called Layer 2 (rc=126, `line 424: /usr/bin/bwrap: Operation not permitted`) UNEXPLAINED and
"contradicting the clean build-time audit". Read-only research this session explains most of it. The
diagnostic bundle must still ship, because the explanation is circumstantial until the host says so itself.

| Brief claim | Reality (command that produced it) | Plan response |
|---|---|---|
| "v0.334.0 image should be cap-free (PR #9874 merged, tags web-v0.334.0 / v0.334.1 both point at d7dfd05aac)" | The git TAG points at d7dfd05aac but the IMAGE `v0.334.0` was built by push-run 37964351357 from commit **48d5144cf4**, the commit BEFORE #9874. `gh run view 37964351357 --log` contains `#15 [runner 2/28] RUN setcap cap_sys_admin,cap_setuid,cap_setgid+ep /usr/bin/bwrap` and the OLD audit step `bwrap_caps=... [ -n "$bwrap_caps" ]`. `reusable-release.yml` checks out the pushed SHA, computes `next` from tags at run time (`Bumping 0.333.4 -> 0.334.0`), and the Release is created with `targetCommitish: main`, which resolved to d7dfd05aac. Push-run 37964763207 (checkout d7dfd05aac, cap-free Dockerfile) took `Latest tag: web-v0.334.0 ... Bumping 0.334.0 -> 0.334.1`. | The v0.334.0 image DOES carry file caps. Both observed errors follow: with the OLD host script (`--cap-add SYS_ADMIN`) bwrap runs and dies with "Unexpected capabilities but not setuid"; with the NEW host script (no cap-add) the bounding set lacks SYS_ADMIN, so execve of a file with `cap_sys_admin+ep` returns EPERM, which is the rc=126 at shim line 424. Better Stack timeline (`betterstack-query.sh --grep "bwrap sandbox non-functional"`): v0.334.0 rc=1 "Unexpected capabilities" at 2026-10-09 17:47:33, then v0.334.0 rc=126 EPERM at 18:55:48. Hypothesis H1 below becomes the leading one, still unproven. |
| "the deploy arm for v0.334.0 was re-run, so v0.334.0 is what must be fixed" | Deploy arm 37968251364 resolved `version=0.334.0 tag=web-v0.334.0 sha=48d5144cf4`. The deploy for d7dfd05aac (the cap-free build, v0.334.1) is run 37968576721, whose resolve-target printed `deploy skipped [skip_reason=ci_not_green] - upstream CI concluded 'failure'`. The push CI run 37964762522 on d7dfd05aac failed in `test-scripts (5/8)`. No deploy of v0.334.1 has ever been attempted. | OUT OF SCOPE for this PR but it is the fastest unblock and is surfaced in the pipeline return summary: v0.334.1 was never deployed. Follow-up evidence in Secondary Findings. |
| "the seccomp profile and AppArmor profile are unchanged and permissive" | `git log -- apparmor-soleur-bwrap.profile seccomp-bwrap.json` last touched 2026-07-01 and 2026-04-06. | Kernel/LSM drift stays a live alternative (#9860 `bwrap_operation_not_permitted` since 04:52Z predates the cap change; Better Stack also shows `Can't mount proc on /newroot/proc: Operation not permitted` at 02:26 and 03:02 on v0.330.10 / v0.331.0). The bundle must discriminate it from H1 in ONE event. |

## Research Insights

**Premise Validation (carried from Phase 0.6).** #9871 and #9860 open; `ci-deploy.sh` probe, failure arm,
`_cred_err_tail` and the shim's final `exec "$REAL"` exist on origin/main; the "image is cap-free" premise was stale.

**Verified-in-session facts (commands):**
- `scripts/betterstack-query.sh --since 36h --grep "bwrap sandbox non-functional"` timeline: v0.330.10 02:26 and
  v0.331.0 03:02 `Can't mount proc on /newroot/proc: Operation not permitted` (rc=1); v0.333.1-v0.333.4 and
  v0.334.0 (17:47:33) `Unexpected capabilities but not setuid` (rc=1); v0.334.0 18:55:48 rc=126 EPERM at shim line 424.
- `gh run view 37964351357 --log | grep -E 'RUN setcap|bwrap_caps'`: the v0.334.0 image build ran the setcap layer.
- `gh run view 37964351357` / `37964763207` log: `Bumping 0.333.4 -> 0.334.0` and `Bumping 0.334.0 -> 0.334.1`.
- `gh release view web-v0.334.0`: `targetCommitish: main`; `git rev-list -n1 web-v0.334.0` = d7dfd05aac.
- `gh run view 37968251364` resolve-target: `version=0.334.0 tag=web-v0.334.0 sha=48d5144cf4...`;
  `gh run view 37968576721` resolve-target: `skip_reason=ci_not_green`.
- `gh run list --workflow apply-deploy-pipeline-fix.yml`: 37964350917 and 37964762496 cancelled with zero jobs;
  the same-push `Apply web-platform infra` runs succeeded; both workflows declare
  `concurrency.group: terraform-apply-web-platform-host` with `cancel-in-progress: false`.
- `apps/web-platform/Dockerfile`: `ENV BUILD_VERSION` / `ENV BUILD_SHA` exist (lines near 206-217), `libcap2-bin`
  is installed in the runner stage, final `getcap -r /` audit is fail-closed.
- `apps/web-platform/infra/vector.toml`: `ci-deploy` is in `host_scripts_journald`; Vector slices messages at
  10000 chars (each DIAG line is far below it).
- Mock constraint: the `bwrap-fail` docker mock arm fails any `exec` whose argv contains `bwrap`; the diag script
  contains that substring, so its mock arm must precede it.

**Mechanism notes from the kernel side (explains why H1 yields rc=126 not rc=1):** when the executed file has
file capabilities with the effective bit and the resulting permitted set cannot hold them (the container
bounding set lacks CAP_SYS_ADMIN after `--cap-add SYS_ADMIN` was removed), execve fails with EPERM before bwrap
starts; with `--cap-add SYS_ADMIN` present bwrap starts and its own `has_caps()` check prints
"Unexpected capabilities but not setuid". The bundle's `caps` + `direct_version` sections test exactly this split.

**Edge cases handled in the design:** an empty `getcap` output renders `<empty>` (distinct from "section missing");
a section over 200 chars is split rather than head-truncated; the diag never runs when the container is gone
(`docker exec` failure is itself captured as a `raw` line); `canary_infra_error` is deliberately not diagnosed.

**Not adopted:** a host-side `docker inspect --type image` read of the image Config.Env (would work, but the
existing in-container `printenv BUILD_SHA BUILD_VERSION` with two literal names is simpler and census-guarded).

## Hypotheses (what the bundle must discriminate in a single event)

| # | Hypothesis | Field that decides it |
|---|---|---|
| H1 | Image still has `cap_sys_admin+ep` on `/usr/bin/bwrap` (stale or mis-built image) and the bounding set lacks SYS_ADMIN, so execve is EPERM | `caps` section non-empty for `/usr/bin/bwrap`; `prov` BUILD_SHA is 48d5144cf4 (not the tag's commit); `direct_version` rc=126 (exec fails even for `--version`) |
| H2 | Exec is denied by LSM (AppArmor) or by seccomp, independent of file caps | `caps` empty AND `direct_version` rc=126 AND `proc` shows `Seccomp=2` / `lsm` shows the profile name and mode |
| H3 | Exec works, namespace/mount creation is denied (the 02:26/03:02 `Can't mount proc` shape, #9860) | `direct_version` rc=0 AND `direct_probe` rc!=0 with the stderr first line; `kernel` shows `apparmor_restrict_unprivileged_userns` / `max_user_namespaces` |
| H4 | The shim, not bwrap, is the culprit | `direct_probe` (shim bypassed) rc=0 while the PATH probe failed |
| H5 | Container posture drift (cap-add/cap-drop/SecurityOpt/Privileged differ from `docker run` in this script) | `host` section |

## Premise Validation

Checked: #9871 and #9860 are open (`gh issue view`). Cited paths exist on `origin/main`: `ci-deploy.sh` probe at
the `docker exec soleur-web-platform-canary bwrap --new-session ...` statement, failure arm
`canary_sandbox_failed`, `_cred_err_tail`, `bwrap-shim/bwrap` final `exec "$REAL" --add-seccomp-fd`. Stale/changed:
the "image is cap-free" premise (table above). ADR corpus: the mechanism (a logger marker with free text last)
is the ADR-115 trusted-region convention already used by the sibling `DEPLOY_ROLLBACK: bwrap` line, not a new
mechanism; no ADR rejects it.

## Property List and Cut List (Phase 0.6b)

Properties: (P1) the next failed canary deploy states, in Better Stack, which of H1-H5 holds; (P2) producing that
statement can never change the rollback, its exit code, its state file, or its ordering relative to teardown;
(P3) no credential-shaped string egresses via the new markers; (P4) the Guard-2 probe-argv pin stays exact.

Cut List: (a) a new `scripts/` collector or `workflow_dispatch` diagnostic job - cut: needs host reach we do not
have, the existing failure arm already runs on the host against the live container; (b) a new deploy-status
JSON field - cut: `reason` is a closed enum consumed elsewhere, journald marker buys P1 alone; (c) strace/`perf`
inside the container - cut: not in the image, would need a mutable container; (d) a separate test file - cut:
`ci-deploy.test.sh` already runs in `infra-validation.yml` and owns the docker/logger mocks, so no `test-all.sh`
registration is needed (verified: `scripts/test-all.sh` states "ci-deploy.test.sh runs in infra-validation.yml").

## User-Brand Impact

- **If this lands broken, the user experiences:** production keeps serving the previous web-platform version (the
  rollback arm still tears down the canary and exits 1 exactly as today); the only regression possible is a
  slower or mis-ordered rollback if the diagnostic misbehaves, which the isolation tests below pin.
- **If this leaks, the user's workflow/credentials are exposed via:** the diagnostic runs `docker exec` inside the
  canary, whose `Config.Env` holds the production secret set (`--env-file`), and its output egresses to Better
  Stack unscrubbed by Vector. A careless `env`, `printenv`, `/proc/*/environ` read or `docker inspect` of
  `.Config.Env` would ship secrets off-box. Mitigation: an allowlisted fixed command set, `printenv` only with
  two literal names, every value through `_cred_err_tail`, plus a source census test.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** aggregate, not single-user: the change touches no user data path and
  cannot affect a user session; the exposure is an operator-credential egress that the sanitiser, the census
  test and the fixed command set bound, and a single-user tier would add review ceremony for a read-only probe
  that mirrors an existing one.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open --json number,title,body` filtered with `jq --arg`
for `apps/web-platform/infra/ci-deploy.sh`, `ci-deploy.test.sh`: re-run at work time; record the result.)

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` - add `emit_canary_sandbox_diag` and `_canary_diag_emit` (placed after
  `_cred_err_tail`, which they use); call it from the `canary_sandbox_failed` arm AFTER the `DEPLOY_ROLLBACK`
  logger line and BEFORE `docker stop`; call it from `run_canary_replay` when the verdict is `sandbox_broken`
  (once per deploy via `CANARY_DIAG_EMITTED`).
- `apps/web-platform/infra/ci-deploy.test.sh` - docker mock gains a diag arm and a sequence log; logger mock
  gains `MOCK_LOGGER_FAIL`; new rows; raise `CI_DEPLOY_ASSERT_FLOOR`.
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` - new subsection under "Blocking bwrap
  sandbox probe - reading its self-report" (heading anchor, not line number) that lists the section names, the
  H1-H5 decision table and the query; `deploy-status-debugging.md`'s `canary_sandbox_failed` row already points at
  that anchor, so no edit there.
- `plugins/soleur/test/preflight-discoverability-test.test.ts` - bump `BASELINE_DECLARED_PROBES` 51 -> 52 with the
  PLACEMENT / TRUTH / NO SUBSTITUTE comment its failure text asks for. This plan's `credentials_required` is the
  52nd declaring plan; measured in this session: `bun test preflight-discoverability-test.test.ts -t "G1 the number"`
  FAILS on the branch with only the plan added (expected 51). NO SUBSTITUTE: Better Stack log rows are readable
  only through the ClickHouse connection, so no unauthenticated read can show that the marker egressed. A
  `LEFTHOOK_EXCLUDE=bun-test` commit skips this suite, so run it before pushing.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9871-canary-failure-diagnostics/tasks.md`

No Terraform, workflow or Dockerfile change (the runbook edit is documentation only). `ci-deploy.sh` is delivered by the existing
`terraform_data.deploy_pipeline_fix` via `apply-deploy-pipeline-fix.yml` (see Infrastructure below).

## Design

### The bundle (one `docker exec`, one host-side set of reads)

Defined as a single-quoted shell-script variable `CANARY_DIAG_SCRIPT` (POSIX `sh`; node:22-slim `sh` is dash)
that prints `<section> <key=value ...>` lines. Executed as
`timeout "$CANARY_DIAG_TIMEOUT" docker exec soleur-web-platform-canary /bin/sh -c "$CANARY_DIAG_SCRIPT" soleur-canary-diag`.
The trailing literal `soleur-canary-diag` is `$0` inside the script and is the token the test mock keys on.
It runs as the image's `USER soleur` (uid 1001), the same user and caps the failing probe had.

In-container sections (every command read-only, each wrapped in `timeout 5`, each `2>&1`, each line ends in
`|| true` semantics so one failure never hides the next):

| section | content |
|---|---|
| `id` | `id` (uid/gid only) |
| `proc` | `/proc/self/status` lines `CapInh CapPrm CapEff CapBnd CapAmb NoNewPrivs Seccomp`, whitespace-squeezed |
| `lsm` | `/proc/self/attr/current` (AppArmor profile + mode) |
| `files` | `stat -c '%a %U:%G %s %n'` and `readlink -f` for `/usr/bin/bwrap` and `/usr/local/bin/bwrap`; `command -v bwrap` |
| `caps` | `getcap /usr/bin/bwrap /usr/local/bin/bwrap` (empty means none), plus `getcap -r /usr/bin /usr/local/bin /usr/lib` count and first two (libcap2-bin is installed in the runner stage) |
| `prov` | `printenv BUILD_SHA BUILD_VERSION` (two literal names, never bare `printenv`/`env`) - image provenance |
| `direct_version` | `/usr/bin/bwrap --version`, rc, first line (shim bypassed; exec-level test) |
| `direct_probe` | the Guard-2 probe argv run against `/usr/bin/bwrap` directly under `timeout 5`, rc, first stderr line (shim bypassed; namespace-level test) |
| `kernel_ns` | `/proc/sys/kernel/apparmor_restrict_unprivileged_userns`, `/proc/sys/kernel/unprivileged_userns_clone`, `/proc/sys/user/max_user_namespaces` as seen from the container |

Host-side sections (no exec):

| section | content |
|---|---|
| `host` | `docker inspect -f 'capadd={{.HostConfig.CapAdd}} capdrop={{.HostConfig.CapDrop}} secopt={{.HostConfig.SecurityOpt}} priv={{.HostConfig.Privileged}} aa={{.AppArmorProfile}} img={{.Image}}' soleur-web-platform-canary` (never `.Config.Env`) |
| `kernel` | `uname -r`, `docker version --format '{{.Server.Version}}'`, host `cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns` |

### Emission

`_canary_diag_emit <section> <raw>`: `val="$(_cred_err_tail "$raw")"`, then
`logger -t "$LOG_TAG" "SOLEUR_CANARY_SANDBOX_DIAG: image=$IMAGE:$TAG trigger=$trigger section=$section val=\"${val:-<empty>}\"" || true`.
Free text (`val`) is LAST and quote-bounded (ADR-115 trusted region; the existing `bwrap_err="..."$` anchor
convention). `_cred_err_tail` keeps the last 200 characters, so each section is built to fit in 200; a section that
does not is split by the in-container script into `name`, `name2`. The output of the docker exec is read with
`head -c 8192`, at most 16 lines, and a line whose first token is not `[a-z_0-9]{1,16}` is emitted as section `raw`.

`emit_canary_sandbox_diag <trigger>` (trigger = `legacy` or `faithful`) is invoked ONLY as
`emit_canary_sandbox_diag legacy || true`. Inside it: `set +e` is not used; instead every external command is in
an `if`/`||` context and the whole body is bounded by the exec `timeout` (default 25 s, `CANARY_DIAG_TIMEOUT`
overridable for tests, validated numeric). It must return 0 and must not touch `BWRAP_RC`, `BWRAP_ERR`,
`CANARY_HEALTHY`, the state file or any global other than `CANARY_DIAG_EMITTED`.

### Faithful-canary path: decided YES

`run_canary_replay` already classifies `sandbox_broken` (the #9860 verdict, recorded since 04:52Z with no cause
beyond `bwrap_operation_not_permitted`). One call, `[[ "$verdict" == "sandbox_broken" ]] && emit_canary_sandbox_diag faithful || true`,
placed right after the verdict is computed and before any teardown, with a `CANARY_DIAG_EMITTED` guard so a deploy
where both fire emits once (the legacy arm sets the guard). It never gates: the legacy arm still alone decides
rollback. `canary_infra_error` is not diagnosed (the #4941 false-rollback guard classes it as infra, and the
bundle would exec into a container that may not exist).

## Implementation Phases

### Phase 1 - tests first (cq-write-failing-tests-before)

In `ci-deploy.test.sh`:
1. Docker mock: BEFORE the Guard-2 recorder hook, an arm for any `exec` whose argv contains `soleur-canary-diag`:
   append `diag` to `MOCK_CANARY_SEQ_LOG`, record the argv line to `MOCK_CANARY_DIAG_LOG`, optionally
   `/bin/sleep "$MOCK_CANARY_DIAG_SLEEP"`, print `MOCK_CANARY_DIAG_OUT` (a default benign multi-section body),
   exit `${MOCK_CANARY_DIAG_RC-0}`, and `exit` BEFORE the existing `bwrap`-substring arms so Guard 2's
   "exactly one bwrap exec" count is unchanged. `docker stop`/`rm` append `stop`/`rm` to the same sequence log.
2. Logger mock: `MOCK_LOGGER_FAIL=1` makes it exit 1 after capturing.
3. New rows (all drive `run_deploy` in `bwrap-fail` mode unless noted):
   - D1 rc!=0: exactly one diag exec recorded; >= 8 `SOLEUR_CANARY_SANDBOX_DIAG` lines; every line matches
     `section=[a-z_0-9]+ val="[^"]*"$`; the first DIAG line is after the `DEPLOY_ROLLBACK` line in the logger
     capture; in the sequence log `diag` precedes `stop` and `rm`.
   - D2 rc==0 (reuse the pass-with-chatter scenario and a plain pass): zero diag execs, zero DIAG lines, zero
     entries in the sequence log.
   - D3 inertness, one row per failure of the diag itself (diag exec rc=1; diag sleeps past `CANARY_DIAG_TIMEOUT=1`;
     diag prints 4 MB; `MOCK_LOGGER_FAIL=1`): the script still exits 1, the state file still says
     `reason=canary_sandbox_failed exit_code=1`, `docker stop` and `rm` still ran, and the `DEPLOY_ROLLBACK` line
     is byte-identical to the baseline run's.
   - D4 credential shapes: `MOCK_CANARY_DIAG_OUT` carries `dp.st.prd.<fixture>`, `sk_live_<fixture>`, `ghp_<fixture>`,
     `eyJ<a>.<b>.<c>` and a doubled-quote injection; the logger capture and the deploy stdout contain none of the
     raw fixtures and contain `REDACTED`; every DIAG line still matches the last-field anchor. One fixture
     straddles the 8192-byte read cut (a `dp.st.prd.` token split across it): redaction runs per line AFTER the
     cut, so a straddling shape must still never leave a usable credential (assert no 12+ char tail of the fixture
     survives). Sinks asserted: the logger capture AND the deploy stdout/stderr, because the existing
     `bwrap_err` precedent shows stdout egresses through the webhook leg.
   - D5 source census over `CANARY_DIAG_SCRIPT` and both functions: no bare `env`, no `printenv` that is not
     followed by the two literal names, no `environ`, no `export -p`, no `.Config.Env`, no `--die-with-parent`,
     no `set` at command position; every `logger -t ... SOLEUR_CANARY_SANDBOX_DIAG` goes through
     `_canary_diag_emit`; both call sites end in `|| true`.
   - D6 faithful path: a `sandbox_broken` verdict from the replay mock emits the bundle once with
     `trigger=faithful`; a deploy where legacy already emitted does not emit twice; an `ok` verdict emits none;
     `canary_infra_error` emits none.
   - D7 Guard 2 and Guard 1 rows run unmodified and stay green (the diag exec is not recorded in
     `MOCK_DOCKER_ARGV_LOG`).
   - D8 instrument control: a helper that asserts "DIAG line count >= N" is driven with an unmatchable pattern
     and must report failure (the #8016 positive-control shape), and the diag log is required non-empty before
     any D1 field check runs (no vacuous pass).
4. Raise `CI_DEPLOY_ASSERT_FLOOR` (522) in the same edit by the measured number of added rows, with a dated
   comment line in the existing changelog block.

### Phase 2 - implementation in `ci-deploy.sh`

Add `CANARY_DIAG_SCRIPT`, `_canary_diag_emit`, `emit_canary_sandbox_diag` after `_cred_err_tail`; insert the two
call sites. No change to the probe argv, `BWRAP_RC` capture, `DEPLOY_ROLLBACK` line, `final_write_state`, or
teardown order. Run `bash apps/web-platform/infra/ci-deploy.test.sh`, `shellcheck` if available, and the
repo's shell-capture lint (`python3 scripts/lint-shell-capture-exit.py`, baseline file alongside). Add the runbook subsection
in the same commit.

### Phase 3 - verify the delivery path (no SSH)

After merge, `apply-deploy-pipeline-fix.yml` delivers the script. Verify with
`bash scripts/check-deploy-script-parity.sh --status-only` (it compares the repo hash to the live
`ci_deploy_sha256`). If the push run was cancelled (see Secondary Findings), re-dispatch it; that is a prod
write, so it needs the operator's explicit go for this specific dispatch, not a menu acknowledgement.

## Observability

```yaml
liveness_signal:
  what: "journald marker SOLEUR_CANARY_SANDBOX_DIAG (one line per section, section=proc|lsm|files|caps|prov|direct_version|direct_probe|kernel_ns|host|kernel) on every canary sandbox failure; SANDBOX_PROBE_OK on every pass"
  cadence: "per failed deploy (diag) / per deploy (OK marker)"
  alert_target: "Better Stack log query via scripts/betterstack-query.sh; the deploy job already fails the release run and files its failure issue"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (emit_canary_sandbox_diag); shipping path apps/web-platform/infra/vector.toml allowlists SYSLOG_IDENTIFIER ci-deploy"
error_reporting:
  destination: "Better Stack (journald tag ci-deploy via Vector); no Sentry event, the rollback arm already records final_write_state 1 canary_sandbox_failed"
  fail_loud: "DEPLOY_ROLLBACK: bwrap sandbox non-functional (existing) followed by SOLEUR_CANARY_SANDBOX_DIAG lines; a diag that itself fails leaves the rollback line intact and, if logger is down, the existing printf fallback keeps the record on the webhook leg"
failure_modes:
  - mode: "image carries file caps on /usr/bin/bwrap (stale or mis-built image) - H1"
    detection: "section=caps non-empty and section=prov BUILD_SHA differs from the release tag's commit"
    alert_route: "layer 3 (Vector journald to Better Stack); read with betterstack-query.sh"
  - mode: "exec denied by AppArmor or seccomp - H2"
    detection: "section=lsm profile and mode, section=proc Seccomp, section=direct_version rc=126 with empty caps"
    alert_route: "layer 3"
  - mode: "namespace or mount creation denied, kernel posture drift - H3 / #9860"
    detection: "section=direct_version rc=0 and section=direct_probe rc!=0; section=kernel_ns and section=kernel values"
    alert_route: "layer 3; also the faithful-canary sandbox_broken verdict now carries the same bundle (trigger=faithful)"
  - mode: "the diagnostic itself hangs, floods or fails"
    detection: "the exec timeout (25 s) bounds it; D3 tests pin that rollback, state and exit code are unchanged; a missing DIAG block after a DEPLOY_ROLLBACK line is itself the signal"
    alert_route: "layer 3 (absence query: DEPLOY_ROLLBACK present, SOLEUR_CANARY_SANDBOX_DIAG absent for the same image tag)"
  - mode: "credential-shaped string reaches the marker"
    detection: "D4 and D5 in CI before merge; _cred_err_tail at runtime"
    alert_route: "CI failure of infra-validation.yml"
logs:
  where: "journald SYSLOG_IDENTIFIER=ci-deploy on the host, shipped to Better Stack (the surface #9871's evidence was read from)"
  retention: "Better Stack source retention (hot window about 40 minutes plus archive arm; query without --no-archive)"
discoverability_test:
  command: "bash scripts/betterstack-query.sh --since 24h --grep SOLEUR_CANARY_SANDBOX_DIAG --limit 20"
  expected_output: "section=proc"
  credentials_required: "BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD from Doppler soleur/prd_terraform (run under doppler run -p soleur -c prd_terraform --) - Better Stack log rows are readable only through the ClickHouse query connection; no unauthenticated probe can show that the marker egressed"
```

Layer cite (hr-observability-layer-citation): every failure mode above is layer 3 (Vector journald to Better
Stack). Layer 6 (synchronous webhook response) is not available: the deploy is asynchronous (the caller polls
`deploy-status`, whose `reason` is a closed enum consumed by other tooling), so a fatal cause reaching only layer 3
is an accepted, stated limit rather than an omission. Affected-surface rule (blind execution surface): the
probe signals are emitted FROM the container (`docker exec` in-container reads), and one event's structured
sections discriminate H1-H5 together (see Hypotheses).

## Infrastructure (IaC)

No new infrastructure. `ci-deploy.sh` ships through the existing `terraform_data.deploy_pipeline_fix`.
### Apply path
Existing: `apply-deploy-pipeline-fix.yml` on push to main (path-filtered on `ci-deploy.sh`), HTTPS via the CF
Tunnel to `/hooks/infra-config`, no SSH. Downtime: none (script swap between invocations).
### Distinctness / drift safeguards
`scripts/check-deploy-script-parity.sh` is the drift check; Phase 3 uses it.
### Vendor-tier reality check
Not applicable (no vendor resource).

## Guard Contract

### Guard 1 - the diagnostic is inert to the rollback

**Property.** Running, failing, hanging or flooding the diagnostic cannot change the rollback line, the exit
code, the state file, or the order of `DEPLOY_ROLLBACK` before diag before `docker stop`; and it never runs when
the probe passed.

**Assembly.** Every path by which diagnostic code can execute or alter control flow: (1) the legacy
`canary_sandbox_failed` arm call site, (2) the `run_canary_replay` faithful call site, (3) the
`emit_canary_sandbox_diag` body (its external commands: `docker exec`, `docker inspect`, `docker version`,
`uname`, `cat /proc/sys/...`, `logger`), (4) the globals it may touch (`CANARY_DIAG_EMITTED` only). The chokepoint
is the single function `emit_canary_sandbox_diag`; the census test quantifies over every call to it in
`ci-deploy.sh`, not the two known sites.

**Mutation matrix.**

| # | Edit (must drive the suite RED) | Row that catches it |
|---|---|---|
| 1 | Drop `|| true` at a call site and make the diag exec exit non-zero | D3 (exit code / state) |
| 2 | Move the call after `docker stop` / `docker rm` (REORDER, not delete) | D1 sequence-log order |
| 3 | Move the call before the `DEPLOY_ROLLBACK` logger line | D1 logger-capture order |
| 4 | Call the diag unconditionally (outside `BWRAP_RC != 0`) | D2 (zero diag on pass) |
| 5 | Delete the call entirely (the guard's own dispatch) | D1 (>= 8 lines, diag log non-empty) |
| 6 | Add a third call site that is not behind `|| true` or not behind the once-per-deploy guard (second member after a compliant first) | D5 census and D6 once-only |
| 7 | Let the diag assign `BWRAP_RC` or `CANARY_HEALTHY` | D3 (state/exit unchanged) |

**Harness rows.** (a) Make the mock's diag arm record nothing: D1 must go RED, not pass vacuously. (b) Drive the
D1 field helper with an unmatchable pattern: it must report failure (D8). Must-PASS inputs that are not the
canonical: a diag body with only two sections and one empty `val` (`<empty>`), and a diag exec that returns rc 1
after printing three lines - both must still pass D1's structural checks, proving the guard does not demand the
canonical full body.

**Anchor.** The inertness claim is compared against the existing #8016 rows (Scenarios 1-4 and Guard 2), which
this change does not edit; a weakening would have to touch those lines and shows in the diff. AC below makes
that a diff-scope check (`git diff origin/main` shows zero deleted lines inside them).

### Guard 2 - no credential-shaped value egresses through the marker

**Property.** No value from the canary's environment, and no credential-shaped string in any diagnostic output,
reaches journald via `SOLEUR_CANARY_SANDBOX_DIAG`.

**Assembly.** The whole event, not one field: its contributors are `$IMAGE:$TAG` (registry ref, non-secret),
`trigger` (a literal), `section` (validated `[a-z_0-9]{1,16}` else `raw`) and `val` (sanitised); sinks are the
journald line and the deploy script's own stdout (webhook `-verbose` re-logs it). Every producer and every sink: the in-container script's commands (anything that can print
`Config.Env`: `env`, `printenv`, `set`, `export -p`, `/proc/*/environ`, `ps e`), the host-side `docker inspect`
template, `_canary_diag_emit`'s sanitiser call, and every `logger` statement carrying the marker. Chokepoint:
`_canary_diag_emit`; the census asserts there is no second path.

**Mutation matrix.**

| # | Edit (must drive the suite RED) | Row |
|---|---|---|
| 1 | Add bare `env` or `printenv` to the script | D5 census |
| 2 | Read `/proc/self/environ` or `ps e` | D5 census |
| 3 | Remove `_cred_err_tail` from `_canary_diag_emit` | D4 |
| 4 | Put `val` in the middle of the line (free text not last) | D1/D4 last-field anchor |
| 5 | Add a section that calls `logger` directly (second path, after a compliant first) | D5 census (every marker logger via `_canary_diag_emit`) |
| 6 | Add `{{.Config.Env}}` to the inspect template | D5 census |

**Harness rows.** Edit the census regex to match nothing: D5 must go RED via its positive control (a fixture
script containing `env` must be flagged). Must-PASS: a script using `printenv BUILD_SHA BUILD_VERSION` with
trailing text, and a `val` containing `sk_live`-lookalike prose that is not credential-shaped, must pass.

**Anchor.** The fixtures are synthesized (cq-test-fixtures-synthesized-only), and `_cred_err_tail` is covered by
its own pre-existing rows; the guard proves routing through it, not the sanitiser's integrity.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "run a bounded (timeout), read-only, sanitised diagnostic bundle against the still-running canary container" [brief] | Design: The bundle; Phase 2 | mapped |
| 2 | "BEFORE `docker stop`" [brief] | Phase 2 call site after the DEPLOY_ROLLBACK line; Guard 1 rows 2-3 | mapped |
| 3 | "emit it as a greppable `logger -t \"$LOG_TAG\"` marker (e.g. SOLEUR_CANARY_SANDBOX_DIAG)" [brief] | Design: Emission | mapped |
| 4 | "never able to alter the rollback or its exit code (`\|\| true`, set -e safe" [brief] | Guard 1; test rows D3 | mapped |
| 5 | "reuse the existing `_cred_err_tail`-style sanitiser and keep free text LAST on the line" [brief] | Design: Emission; Guard 2; test rows D1/D4 | mapped |
| 6 | "Also decide whether the same bundle belongs on the faithful-canary path." [brief] | Design: Faithful-canary path (decided YES); test row D6 | mapped |
| 7 | "the Guard-2 probe-argv pin must keep passing; add a case proving the diag bundle runs on rc!=0, never on rc==0, never changes the exit code, and cannot leak a credential-shaped string" [brief] | Phase 1 rows D1-D5, D7 | mapped |
| 8 | "registration in test-all" [brief] | Cut List (d) | descoped - justification: no new test file is created; ci-deploy.test.sh already runs in infra-validation.yml (scripts/test-all.sh says so), so there is nothing to register |
| 9 | "the Observability section (how the next failed deploy self-reports to Better Stack with no SSH)" [brief] | ## Observability | mapped |
| 10 | "why were the push-triggered apply-deploy-pipeline-fix.yml runs ... cancelled with zero jobs started" [brief] | Secondary Findings 1 | mapped |
| 11 | "The PR will `Ref #9871` and `Ref #9860` ... never `Closes`" [brief] | Acceptance Criteria (PR body) | mapped |
| 12 | "Follow the planning skills' own gates (Observability, User-Brand Impact with the `aggregate pattern` threshold, Guard Contract, infra-steps lint)" [brief] | ## Observability, ## User-Brand Impact, ## Guard Contract, lint runs recorded in Phase 2 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit `apps/web-platform/infra/ci-deploy.sh` (functions + two call sites) | asks 1-6 | asked |
| Edit `apps/web-platform/infra/ci-deploy.test.sh` (mock arms, rows, floor) | ask 7 | asked |
| `prov` section (BUILD_SHA / BUILD_VERSION from the image) | - | inferred - justification: research found the v0.334.0 image was built from the pre-fix commit; without this field the next event cannot tell a stale image from a kernel/LSM cause (hypothesis H1 vs H2/H3) |
| `CANARY_DIAG_TIMEOUT` test override | - | inferred - justification: the D3 hang row needs a bounded wait; a fixed 25 s would make the suite slow or flaky |
| `MOCK_LOGGER_FAIL` knob | ask 4 | asked |
| Create `knowledge-base/project/specs/feat-one-shot-9871-canary-failure-diagnostics/tasks.md` | - | inferred - justification: the plan skill's work contract derives tasks.md from the plan and the work phase executes against it |
| Edit `canary-probe-set.md` (reading the DIAG bundle) | ask 9 | asked |
| Edit `preflight-discoverability-test.test.ts` (ratchet 51 -> 52) | ask 12 | asked - the Observability gate the brief names makes this plan declare `credentials_required`, which moves that repo-global count |
| Secondary Findings 2-3 (v0.334.1 never deployed; tag/image mismatch) | ask 10 | asked |
| Research Reconciliation table | "verify the load-bearing parts yourself with read-only commands, do not just trust this" [brief] | asked |

### Split Assessment

- Subsystems touched: 3 - apps/web-platform, knowledge-base, plugins/soleur
- Planned files: 5 | Estimated changed lines: 420
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [x] `bash apps/web-platform/infra/ci-deploy.test.sh` passes with the raised floor; Guard 2 (`assert_bwrap_probe_argv`) and Guard 1 pass unmodified.
- [x] `git diff origin/main -- apps/web-platform/infra/ci-deploy.test.sh` shows no deleted line inside the #8016 Scenarios 1-4 or Guard 1/2 blocks.
- [x] `git diff origin/main -- apps/web-platform/infra/ci-deploy.sh` leaves the probe statement, `BWRAP_RC` capture, `DEPLOY_ROLLBACK` line and teardown order byte-identical (the diff only adds functions and two guarded calls).
- [x] `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-09-fix-canary-sandbox-failure-self-diagnosis-plan.md` passes.
- [x] `cd plugins/soleur/test && bun test preflight-discoverability-test.test.ts` passes with `BASELINE_DECLARED_PROBES` at 53 (main was already 52 from #9826 when this branch merged it in; this plan is the 53rd declaring plan).
- [x] orphan-suite census is unaffected (no new suite file is added; run `bash scripts/lint-orphan-test-suites.sh`).
- [ ] PR body says `Ref #9871` and `Ref #9860`, never `Closes`.

### Post-merge (automatable)

- [ ] `bash scripts/check-deploy-script-parity.sh --status-only` reports parity for the merge's `ci-deploy.sh`.
- [ ] After the next canary sandbox failure, `bash scripts/betterstack-query.sh --since 24h --grep SOLEUR_CANARY_SANDBOX_DIAG` returns the section lines (credentials as declared above), and the sections decide H1-H5 per the table.

## Secondary Findings (investigated, NOT fixed here)

1. **Why both push runs of Apply deploy-pipeline-fix were cancelled with zero jobs: already tracked as open #8167
   (P1).** Evidence: `apply-deploy-pipeline-fix.yml` and `apply-web-platform-infra.yml` (also `web2-luks-rebirth.yml`)
   share `concurrency.group: terraform-apply-web-platform-host` with `cancel-in-progress: false`. GitHub keeps one
   RUNNING and one PENDING run per group and cancels an older pending run when a newer one queues. Run list for
   2026-10-09: push 48d5144cf4 at 17:10:14 started both "Apply web-platform infra" (ran, success 17:14:15) and
   "Apply deploy-pipeline-fix" (pending); push d7dfd05aac at 17:13:42 queued its own pair, which evicted the pending
   48d5 run (cancelled 17:13:44) and then evicted its own sibling the same way (cancelled 17:13:44, zero jobs).
   Only the infra workflow's pair survived. The host kept the stale `ci-deploy.sh` until the operator-authorised
   `workflow_dispatch` run 37976212395 at 18:51. Systemic: yes. Any two merges within the infra run's duration
   whose changes touch both workflows' path filters reproduce it, and nothing re-triggers a path-filtered push
   run, so the host stays stale until the next matching merge or a dispatch. Action: no new issue; add this
   2026-10-09 recurrence (run ids 37964350917, 37964762496, and the survivor sequence) as a comment on #8167 and
   consider raising its priority because it now sits on the P0 deploy path. (Do not file; comment at ship.)
2. **v0.334.1 was never deployed** (see Research Reconciliation): its deploy was skipped as `ci_not_green`
   because push CI 37964762522 failed in `test-scripts (5/8)`; the cause of that test failure was not identified
   in this session. This is the fastest route to unblock production and needs the operator: re-run or fix the red
   shard on `main`, then re-run the deploy arm for d7dfd05aac. File a follow-up issue at ship if the failure is a
   real regression: "push CI red on d7dfd05aac (test-scripts 5/8) silently gated the only cap-free image".
3. **Tag/image provenance mismatch**: when two merges land within one release duration, `web-vX` is created at the
   branch tip (`targetCommitish: main`) while the image is built from the push SHA, so a tag can name a commit
   whose image was built from an earlier one. Follow-up issue candidate: have the release assert
   `git rev-parse web-vX == github.sha` (or tag `github.sha` explicitly). The new `prov` section would have
   shown this immediately.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder text fails `deepen-plan` Phase 4.6; this one is filled (aggregate pattern).
- The diag `docker exec` runs inside a container whose environment is the production secret set. The census test (D5) is the guard on this; do not weaken it to make a new command fit.
- `_cred_err_tail` keeps the LAST 200 chars. A section longer than 200 loses its head, so sections are built short and the important fields are placed last.
- The mock's `bwrap-fail` arm fails any `exec` whose argv contains the substring `bwrap`; the diag script contains that word, so the diag arm MUST precede it and the Guard-2 recorder.
- `timeout` on the host and `timeout` in the container are different binaries; both must exist (coreutils on both; verified `timeout` is already used on the host at several sites and node:22-slim ships coreutils).
- Do not add `--die-with-parent` or `--pdeathsig` to any docker-exec bwrap statement, including the diag's direct probe (Guard 1, #8016).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - infrastructure/tooling change. (Engineering-only; no UI surface, no
regulated-data surface: the markers carry kernel, capability and image-provenance facts, no personal data, so the
GDPR gate does not fire. No new persistent store or connection, so the Encryption Posture gate is skipped.
No architectural decision is made or changed, so no ADR or C4 deliverable: the marker follows the existing
ADR-115 trusted-region convention.)
