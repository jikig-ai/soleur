---
title: "fix: unblock web-platform deploys - the file-cap'd bwrap (#9767) that a module-load crash was masking (Closes #9871, Ref #9860)"
date: 2026-10-09
slug: fix-deploy-canary-filecap-bwrap-rollback
branch: feat-one-shot-9860-deploy-canary-health-failed
issue: 9871
refs: [9860]
deepened: 2026-10-09
type: bug-fix
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

## Enhancement Summary

**Deepened on:** 2026-10-09
**Agents used:** learnings-researcher, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, soleur:engineering:cto, security-sentinel, architecture-strategist, observability-coverage-reviewer, framework-docs-researcher (bubblewrap source), plus mechanical gates 4.6-4.8 and 4.11-4.12.

### Key improvements

1. Upstream bubblewrap source (v0.8.0 to v0.13.0) confirms no release supports file capabilities for non-root; the capped-copy option is closed and the setuid option is a dead end past 0.11.1 (Fix Options).
2. The "restore v0.332.2" baseline was wrong: the host script, not the image tag, carries the container flags, and prod never ran "no file cap + SYS_ADMIN bounding" (Phase 0.8). The PR now includes the host alignment as an independently revertable Commit B.
3. The intermediate state would have paged Sentry per deploy and FAILed a soak tracker; the outer-wrap canary now skips behind a constant gate with a marker.
4. The `discoverability_test` was liveness-only (passes before the fix); it is now a script that fails before and passes after.
5. Guard regex hardened (path-qualified and flag-variant `setcap`), per-site `--cap-add` rows added, ADR-075 amendment rewritten against the ADR's real headings.

### New considerations discovered

- `--cap-add SYS_ADMIN` activates a `caps:[CAP_SYS_ADMIN]` include rule in the seccomp profile for every container process.
- `bwrap --version` never reaches the capability guard, so a build-time version smoke cannot be the regression guard.
- Setuid-root binaries remain in the image (deferred hardening issue).

## Overview

Every web-platform deploy since the tenant filesystem isolation merge (#9767, 2026-10-09T11:38Z)
rolls back at the pre-swap canary in `apps/web-platform/infra/ci-deploy.sh`; production still
serves `87b26df8e4` (v0.332.2) and is healthy. Phase 0 (read-only, no SSH, executed at plan time,
outputs recorded below) shows **two causes in sequence, the second invisible until the first was
fixed**:

1. **v0.332.3, v0.332.4, v0.332.5, v0.333.0** - `reason=canary_health_failed`: the canary container
   crashes at module load (`fileURLToPath(undefined)`, the `import.meta.url` bug fixed by #9838).
   The brief says v0.332.4, v0.332.5 and v0.333.0 were built after that fix. They were not: their
   commits predate it (Phase 0.1), and Better Stack shows the identical stack for each.
2. **v0.333.1, the first tag containing #9838** - `reason=canary_sandbox_failed`: the container is
   healthy now and the **blocking legacy bwrap probe** dies in ~90 ms with
   `bwrap: Unexpected capabilities but not setuid, old file caps config?`. Cause: #9767 added
   `RUN setcap cap_sys_admin,cap_setuid,cap_setgid+ep /usr/bin/bwrap` to the Dockerfile; the app
   runs as uid 1001; bubblewrap 0.8.0 (Debian bookworm, `node:22-slim`) refuses to run for a
   non-root caller that acquires capabilities from a file cap rather than setuid. This is the
   leading hypothesis (H1, also the operator's relayed hypothesis and #9871's) and it is confirmed
   by four independent observations (Phase 0.2-0.5). It breaks every plain bwrap exec in the image:
   the deploy probe, the faithful canary replay and real agent sandbox calls.

The #9860 ledger entry (`sandbox_broken / bwrap_operation_not_permitted`) is **not** what fails any
deploy, and it is **not caused by the file cap either**: Better Stack shows the same faithful verdict
on the v0.332.1 and v0.332.2 deploys, whose legacy probe PASSED (`SANDBOX_PROBE_OK`) before the cap
existed. It is stale only because no deploy has cleared the health gate since 12:09Z, so the faithful
canary has not run. #9860 (host posture, userns EPERM class) is untouched by this plan: **Closes
#9871, Ref #9860**.

Chosen fix (Option O1, conditional on the Phase 0 signature): delete the file cap so `/usr/bin/bwrap`
is plain again, replace the `{bwrap}`-only audit with an empty-set audit, remove the now-pointless
`--cap-add SYS_ADMIN` grants and keep the report-only outer-wrap canary quiet while the arm is withdrawn
(so the container flags return to exactly what v0.332.2 ran), repin the tests that pinned the broken
posture, amend ADR-075, document how to localize a canary failure, and verify with a real deploy that
reaches the served sha. The dedicated-capped-copy alternative in #9871 was measured and is closed by the
upstream bubblewrap source (Fix Options). The image change (Commit A) unblocks alone; the host-script change
(Commit B) is in the same PR because review showed the unblock otherwise deploys a container posture prod
never ran (Phase 0.8) and leaves a Sentry page per deploy.

## Research Reconciliation - Brief vs. Codebase/Production

| Brief / relayed claim | Reality (evidence in Phase 0) | Plan response |
|---|---|---|
| v0.332.4, v0.332.5, v0.333.0 "built after" #9838 still fail, so a second cause may exist | Built from `b7fa93724a`, `460ee5813c`, `d7dee46bb0`, all before `ceb1c6c1ba` (#9838). `git merge-base --is-ancestor` is false for all three. `gh run view` `headSha` on `workflow_run` runs is main HEAD at trigger time, not the tag's commit - the source of the misreading | Tag-to-commit map is Phase 0.1; the fix targets v0.333.1's failure |
| A second cause exists | Confirmed, visible only on v0.333.1 (`canary_sandbox_failed`) | Fix Options below |
| #9860: faithful `sandbox_broken` is a non-blocking host-posture regression, maybe what fails the deploy | Non-blocking is true (`run_faithful_sandbox_canary \|\| true`). It does not fail any deploy and pre-dates the cap (v0.332.1/.2 logged it with the legacy probe green). Its ledger is stale: `checked_at` 12:09:17Z in all four failed states | Do not touch the faithful canary or host posture; Ref #9860 |
| #9871: "dedicated capped copy for the outer wrap" fixes it | The unblock half is right (`/usr/bin/bwrap` must be plain). The copy does not work for uid 1001 either (local run C: same `Unexpected capabilities`), so it would ship a SYS_ADMIN carrier that cannot run | Recorded in Fix Options and `decision-challenges.md`; O1 chosen, copy left to the re-spike |
| Spike "WORKS" for arm F (tenant-isolation plan Phase 0 table) | Reproduces as FAIL for uid 1001 in the same base image; the plan's own S0.7(d) ("inner canary argv byte-identical under file-cap bwrap") was never run as the prod user, and pre-merge gates replace bwrap with an in-process shim (`sandbox-canary-capture-gate`), so the real binary is first exercised at deploy | ADR-075 amendment; deferral issue for a pre-merge real-bwrap-as-uid-1001 probe |
| v0.332.2's posture is the baseline the fix restores | The HOST `ci-deploy.sh` is delivered by `apply-deploy-pipeline-fix.yml`, not by the image tag: run 37928426862 delivered #9767's version (sha256 `fda3b3ed...`, 4 `--cap-add SYS_ADMIN` literals) at 12:11:34Z, after the v0.332.1 and v0.332.2 deploys (the latter completed 12:09:30Z). Those two probes therefore ran WITHOUT SYS_ADMIN in the bounding set; the image-only fix would run "no file cap + SYS_ADMIN bounding", which prod has never run | Commit B removes the grants so the posture is exactly v0.332.2's |
| Production healthy on v0.332.2 | `curl https://app.soleur.ai/health` -> `"version":"0.332.2","build_sha":"87b26df8e4..."` | Baseline for the served-sha criterion |

## Phase 0 - Evidence (read-only, no SSH). Executed at plan time; `soleur:work` re-runs it first

All commands are read-only; secrets stay in Doppler (`doppler run`), never printed. Better Stack rows can
carry container-tail text: filter before pasting anything into a PR body.

**Step 0 (before any edit).** `gh pr list --search "linked:issue #9871" --state all` -> `[]` (no PR yet).
Open PRs touching the same files: `#9809` (touches `Dockerfile`, `ci-deploy.sh`, `ci-deploy.test.sh`,
`sandbox-canary-soak.test.sh` in other hunks: a probe-script COPY line, ledger sections 7b/7c). Re-check
at work time and rebase over whichever merges first; a locked sibling worktree `fix-5863-bwrap-elevation`
exists with no PR and no changes beyond main.

### 0.1 Tag -> commit map and the #9838 ancestry check

```bash
for t in v0.332.2 v0.332.3 v0.332.4 v0.332.5 v0.333.0 v0.333.1; do echo -n "$t "; git rev-parse --short "web-$t^{commit}"; done
for t in v0.332.4 v0.332.5 v0.333.0 v0.333.1; do echo -n "$t contains ceb1c6c1ba(#9838)? "; git merge-base --is-ancestor ceb1c6c1ba web-$t && echo yes || echo no; done
for t in web-v0.332.2 web-v0.333.1; do echo -n "$t Dockerfile setcap RUN lines: "; git show $t:apps/web-platform/Dockerfile | grep -c '^RUN setcap'; done
```

```text
v0.332.2 87b26df8e4   v0.332.3 5e75548373 (#9767)   v0.332.4 b7fa93724a   v0.332.5 460ee5813c   v0.333.0 d7dee46bb0   v0.333.1 ceb1c6c1ba (#9838)
v0.332.4 contains #9838? no    v0.332.5 contains #9838? no    v0.333.0 contains #9838? no    v0.333.1 contains #9838? yes
web-v0.332.2 Dockerfile setcap RUN lines: 0        web-v0.333.1 Dockerfile setcap RUN lines: 1
```

### 0.2 Deploy job annotations (the `reason`) and which probe layer each reason names

```bash
gh api repos/jikig-ai/soleur/check-runs/<deploy-job-id>/annotations --jq '.[]|select(.annotation_level=="failure")|.message'
```

```text
run 37944106317 (job 113871631662): ci-deploy.sh exited 1 (reason=canary_health_failed, tag=v0.332.5)
run 37944479470 (job 113877595849): ci-deploy.sh exited 1 (reason=canary_health_failed, tag=v0.332.4)
run 37947145374 (job 113882587889): ci-deploy.sh exited 1 (reason=canary_health_failed, tag=v0.333.0)
run 37948901530 (job 113887502008): ci-deploy.sh exited 1 (reason=canary_sandbox_failed, tag=v0.333.1)   <- new reason
```

In `ci-deploy.sh`, `canary_health_failed` is only the in-loop `/health != 200` reason (the login,
dashboard and layer-3 arms were never reached); `canary_sandbox_failed` is written only by the
**blocking legacy bwrap probe** after the health gate passed. The reason alone localizes the sub-check.
`/hooks/deploy-status` (same payload `cat-deploy-state.sh` serves) carries no sub-check detail.

### 0.3 deploy-status payload (log of run 37947145374, step `Verify deploy script completion`)

```text
"tag":"v0.333.0","reason":"canary_health_failed","exit_code":1,"start_ts":1791558677,"end_ts":1791558765   (88 s)
"sandbox_canary":{"verdict":"sandbox_broken","reason":"bwrap_operation_not_permitted","checked_at":1791547757 (2026-10-09T12:09:17Z),"consecutive_pass":0}
"outer_wrap_canary":{"verdict":"unknown","checked_at":0}
```

Neither canary ran in any failed deploy (`write_sandbox_canary_state` overwrites the ledger on every run
and resets `consecutive_pass` on `sandbox_broken`, so a frozen `checked_at` means no run, not a writer bug).

### 0.4 Better Stack (`ci-deploy` / `webhook` journald; the rollback arm pipes `docker logs --tail 30` through `logger`)

```bash
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since '<start>' --until '<end>' \
  --grep ERR_INVALID_ARG_TYPE --grep DEPLOY_ROLLBACK --grep SANDBOX_PROBE_OK --grep 'Faithful sandbox canary' --limit 80 \
  | jq -r '.raw|fromjson|"\(.SYSLOG_IDENTIFIER // "-") \(.message // "")"'
```

```text
v0.332.3 / v0.332.5 / v0.332.4 / v0.333.0 windows: TypeError [ERR_INVALID_ARG_TYPE]: The "path" argument must be of type string or an instance of URL. Received undefined
    at fileURLToPath (node:internal/url:1605:11) ... at Object.<anonymous> (/app/dist/server/index.cjs:105083:75)   (identical stack, four deploys)
v0.333.1 (15:21Z)  ci-deploy  DEPLOY_ROLLBACK: bwrap sandbox non-functional in ...:v0.333.1 rc=1 ms=90 cstate=running err_chars=68 bwrap_err="bwrap: Unexpected capabilities but not setuid, old file caps config?"
v0.332.1 (~11:30Z)  ci-deploy  SANDBOX_PROBE_OK: bwrap sandbox verified in ...:v0.332.1 rc=0 ms=83     webhook  Faithful sandbox canary (non-blocking): verdict=sandbox_broken reason=bwrap_operation_not_permitted
v0.332.2 (~11:53Z)  ci-deploy  SANDBOX_PROBE_OK: bwrap sandbox verified in ...:v0.332.2 rc=0 ms=75     webhook  Faithful sandbox canary (non-blocking): verdict=sandbox_broken reason=bwrap_operation_not_permitted
```

`cstate=running`, `rc=1` and an explicit bwrap message rule out the #8016 PDEATHSIG race (rc=137, empty
stderr) and the #9860 userns-EPERM class (`Operation not permitted`) as the cause of v0.333.1's failure.

### 0.5 Local reproduction in the deploy base image (local Docker only, no prod contact)

Image: `node:22-slim@sha256:4f77a690...`, `apt-get install bubblewrap libcap2-bin` (bubblewrap 0.8.0),
callers run as uid 1001 via `setpriv --reuid=1001 --bounding-set=...`.

```text
no file cap, bounding +sys_admin:                      bwrap: pivot_root: Operation not permitted   rc=1   (plain docker lacks the prod apparmor/seccomp allowances: a different, posture-dependent error)
A  file cap, bounding WITHOUT sys_admin (no cap-add):   setpriv: failed to execute bwrap: Operation not permitted   rc=126   (exec denied - the caller's container lacks --cap-add)
B  file cap, bounding WITH sys_admin,setuid,setgid:     bwrap --version -> bubblewrap 0.8.0 rc=0 (--version never reaches the guard); any real argv:
                                                         bwrap: Unexpected capabilities but not setuid, old file caps config?   rc=1   (legacy probe argv AND outer-wrap-shaped argv)
C  separate capped copy /usr/local/bin/bwrap-outer:     capped copy: Unexpected capabilities but not setuid ...  rc=1   |   plain /usr/bin/bwrap: pivot_root EPERM (plain docker) rc=1
```

Local runs cannot show the post-fix probe PASSES (the prod `soleur-bwrap` apparmor profile is needed):
only the real deploy proves that. Note row B: a `bwrap --version` smoke at image build time passes on
the broken image, so it cannot be the regression guard.

### 0.6 Sentry (WEB-PLATFORM-AN) and production baseline

```text
status=unresolved first=2026-10-09T04:52:18Z last=2026-10-09T12:09:17Z count=5      (scripts/sentry-issue.sh WEB-PLATFORM-AN)
{"status":"ok","version":"0.332.2","build_sha":"87b26df8e4dee5765d82bf130b73900dd9e869ab",...}      (curl -s https://app.soleur.ai/health)
```

### 0.7 H1 (file cap) - what would falsify it, and the stop rule

H1 is falsified by any one of: (a) `web-v0.333.1`'s Dockerfile carrying no `setcap` (observed: 1 line, v0.332.2: 0);
(b) the legacy probe also failing on a cap-free image (v0.332.1/.2 passed, rc=0); (c) the local no-cap
repro printing `Unexpected capabilities` (it prints `pivot_root` instead); (d) after the fix deploys, the
probe still failing with the same string. (a)-(c) did not falsify it. **Stop rule:** at work time, if the
newest failed deploy's `reason`/`bwrap_err` differs from the v0.333.1 signature, stop and re-plan - a
`canary_health_failed` with a new stack is an app-level cause; a `bwrap_err` containing `Operation not
permitted`, `clone` or `userns` is #9860's host-posture class; neither is fixed in the Dockerfile.

### 0.8 Which host script each probe ran under (the baseline is not the image tag)

```bash
gh run list --workflow apply-deploy-pipeline-fix.yml --limit 6 --json databaseId,createdAt,conclusion,headSha
git show 87b26df8e4:apps/web-platform/infra/ci-deploy.sh | sha256sum
git show ceb1c6c1ba:apps/web-platform/infra/ci-deploy.sh | sha256sum
```

```text
apply-deploy-pipeline-fix run 37928426862  2026-10-09T12:11:34Z  success  headSha 5e75548373 (#9767)   <- the host got --cap-add here
v0.332.1 probe (~11:30Z) and v0.332.2 probe (~11:52Z): both BEFORE that apply -> ran with no SYS_ADMIN in the bounding set
sha256 at 87b26df8e4: 7c5c8f37...  (zero --cap-add SYS_ADMIN)      sha256 at ceb1c6c1ba: fda3b3ed...  (== deploy-status ci_deploy_sha256 on the v0.332.3 and v0.333.0 states)
```

The `--cap-add` grants also activate the `caps:[CAP_SYS_ADMIN]` include rule in
`apps/web-platform/infra/seccomp-bwrap.json` for every process in the container (security review), so
"inert once the file cap is gone" is false: it widens seccomp and the bounding set (setuid-root `su`,
`mount`, `newgrp` and others in `node:22-slim` would receive SYS_ADMIN). That is why Commit B removes them.

## Fix Options (trade-offs against the tenant-isolation goal, ADR-075)

The tenant-isolation feature's goal is per-session filesystem isolation for both agent tool tiers. Today
it is dark (`AGENT_OUTER_WRAP != 1`), so no isolation is *delivered* by the cap; the cap only breaks bwrap.

**Upstream facts (verified against bubblewrap source at tags v0.8.0 through v0.13.0, `bubblewrap.c`
`acquire_privs()` and `main()`, plus `NEWS.md`):** the error comes from the `else if (real_uid != 0 &&
has_caps ())` branch, reached only when real uid equals effective uid (not setuid); `has_caps()` is true
for ANY permitted capability bit; `acquire_privs()` runs before `parse_args()`; `bwrap --version` exits
earlier and never reaches it. No release in that range supports file capabilities for a non-root caller
(the v0.8.0 source comment calls setcap "which we don't support anymore"). Setuid mode works in v0.8.0
through v0.11.1, is a default-off build option from v0.11.2 (CVE-2026-41163 fix), and is removed in
v0.12.0; upstream's stated direction is unprivileged user namespaces. Debian bookworm ships 0.8.0-2+deb12u1
(whether its package installs the binary setuid is unverified). Citations: raw.githubusercontent.com
`containers/bubblewrap/<tag>/bubblewrap.c`, `NEWS.md` on `main`.

| Option | Unblocks deploy | Outer wrap works for uid 1001 | Cost / risk |
|---|---|---|---|
| **O1 (chosen): drop the file cap; `/usr/bin/bwrap` plain** | Yes (bwrap returns to the unprivileged path the v0.332.1/.2 probes passed on) | No - stays dark; arm F needs a re-spike | Smallest change; reduces privilege; isolation delivery waits on a measured mechanism. Not byte-identical to v0.332.2 until the `--cap-add SYS_ADMIN` grants are also removed (Phase 2B) |
| O2 (#9871): cap-free `/usr/bin/bwrap` + capped copy `/usr/local/libexec/bwrap-outer`, pin `agent-outer-wrap.ts` and founder scripts to it | Yes | **No** - run C, and upstream never supports file caps for non-root | Ships a SYS_ADMIN carrier that cannot run, plus a path change across code, scripts, fixture, audit and tests; false assurance the feature is wired |
| O3: setuid-root copy for the outer wrap | Yes (inner path untouched) | Unmeasured; works on bubblewrap <= 0.11.1 only | New setuid-root binary reachable by uid 1001 and every sandbox child; a dead end on any bubblewrap upgrade (setuid removed in 0.12.0): security review and an in-image uid-1001 measurement required; re-spike |
| O4: tolerate/skip the legacy probe failure | Yes | n/a | Ships a build whose every agent Bash call fails; the probe is the gate. Rejected |
| O5: run the outer wrap as a root helper (real uid 0) | Unmeasured | Unmeasured | Re-architecture of the spawn path; re-spike |
| O6: unprivileged userns outer wrap (upstream's direction) | Yes | Blocked today | ADR-075's own spike found fresh `--proc` EPERM under Docker masked paths and the nested-userns conflict with the inner sandbox; needs the container-posture topology work (#9773) |

O1 is the only option that needs no new measurement to justify. O2 is closed by the upstream source; O3,
O5 and O6 are the re-spike's candidate set. The constraint measured here and confirmed upstream: **a
non-root caller holding any capability is refused, so a mechanism must run bwrap with real uid 0, use
setuid-root (bubblewrap <= 0.11.1), or use unprivileged user namespaces.** The re-spike is a
security-reviewed issue measured as uid 1001 in the actual image under the prod apparmor/seccomp profile
(Phase 4 deferral (a)); it is not part of this unblock.

## Research Insights

**Premise validation.** #9860 open (`meta/machinery`), #9871 open P0, neither has a closing PR; #9767
merged, #9838 merged 13:31Z (confined to `server/agent-outer-wrap.ts` + its test), #5863 and #9723 closed,
#9773 open. ADR-075's "Adopted: file-capability bwrap" is the mechanism being reversed (amended, not
re-litigated: its spike table is what omitted uid 1001). `git diff 87b26df8e4..ceb1c6c1ba -- Dockerfile
infra/` shows the posture-relevant hunks are exactly: `libcap2-bin` install, the `setcap` RUN, the
end-of-runner `getcap` audit, `--cap-add SYS_ADMIN` x3 sites, and the outer-wrap fixture COPY lines (the
rest is unrelated Inngest/Sentry infra).

**Property list.**

- P1: a release built from `main` reaches canary pass and promotes; production serves the new `build_sha`.
- P2: the agent sandbox (`bwrap` as uid 1001, via the PATH shim) is no worse in the new image than in v0.332.2.
- P3: the failing canary sub-check is identifiable without SSH from the run annotation plus one documented Better Stack query.
- P4: an image whose bwrap carries file capabilities cannot reach `main` unnoticed.
- P6: the container flags and canary noise match the withdrawn posture (no `SYS_ADMIN` grant without a consumer; no per-deploy page for an arm that is not provisioned).
- P5: #9860's acceptance (host posture) is tracked honestly - open, Ref only.

**Cut list.**

- Relax/skip the legacy probe (O4) -> P1 only, violates P2. Cut.
- Per-error reason codes in deploy-state -> P3 already met by the `DEPLOY_ROLLBACK ... bwrap_err=` Better Stack line (0.4). Cut; runbook paragraph instead.
- Capped copy (O2), setuid copy (O3), root helper (O5) -> P1 is met by O1 alone; the others need measurement. Deferred to the re-spike issue.
- A getcap-gated outer-wrap canary skip (a `docker exec` whose failure would silently disable the canary) -> replaced by a constant gate with a marker (Phase 2B.3).
- A setuid/setgid strip of the image's setuid-root binaries -> a real hardening gap (security review) but unrelated to this incident and unmeasured against the image's tooling; deferred (Phase 4.5(d)).
- Fixture directory of full-copy mutated scripts and a 6-row mutation matrix -> over-built (plan review); replaced by derive-at-test-time mutants (Guard Contract).
- A build-time `bwrap --version` smoke -> passes on the broken image (0.5 row B). Cut.
- Any change to the faithful canary, host userns sysctl or apparmor profile -> that is #9860.

**Learnings applied** (none covers file caps on bwrap, a tag-vs-commit misread, or one canary rollback masking a second - the learning is a Phase 3 deliverable):
`knowledge-base/project/learnings/bug-fixes/2026-10-01-docker-exec-pdeathsig-race-sigkills-bwrap-probe.md` (same probe and rollback reason; rc=137 vs rc=1 discriminates);
`knowledge-base/project/learnings/security-issues/bwrap-shared-seccomp-filter-fd-hygiene-20261006.md` (a probe must be able to fail for the right reason);
`knowledge-base/project/learnings/2026-07-03-faithful-canary-capture-must-run-in-the-deploy-base-image.md` (capture/replay uid and image must equal prod: this is the uid-1001 gap);
`knowledge-base/project/learnings/2026-07-18-image-baked-and-latent-is-a-claim-verify-a-published-tag-exists.md` (verify which commit a tag carries);
`knowledge-base/project/learnings/best-practices/2026-07-07-deploy-status-tag-reader-resolve-running-version-from-health.md` (deploy-status `.tag` is the last attempt; use `/health` `build_sha`);
`knowledge-base/project/learnings/2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md` (the host-posture class = #9860);
`knowledge-base/engineering/operations/runbooks/canary-probe-set.md` (read before touching the probe set).

**Open Code-Review Overlap.** None (open `code-review` issues queried for `Dockerfile`, `ci-deploy.sh`, `cloud-init.yml`, `agent-outer-wrap.ts`, `agent-outer-wrap.test.ts`, `sandbox-canary.mjs`: no match).

## User-Brand Impact

- **If this lands broken, the user experiences:** a deploy pipeline that stays stuck (no shipped fix, including security fixes, reaches production), or - if the wrong fix is chosen (probe relaxed, or the file-cap'd bwrap forced through) - every agent Bash/sandbox call failing in every user's session.
- **If this leaks, the user's workflow/data is exposed via:** a fix that weakens the legacy probe so a broken or absent sandbox ships, or that adds a runnable privileged binary (O3) without review. The chosen option removes a privilege grant and keeps the blocking probe intact.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** a stuck pipeline and a failed sandbox hit all tenants equally rather than one tenant's data, and the fix restores a posture that served production for months (v0.332.2) instead of creating a new exposure; `single-user incident` would apply to O3/O4, which are excluded.

## Implementation Phases (Closes #9871, Ref #9860)

One PR, two commits, ordered so each is independently revertable: **Commit A** is the image unblock
(Phases 1, 2A, 3, 4); **Commit B** aligns the host-side deploy script with the image (Phase 2B). A alone
unblocks the deploy; B removes the posture delta and the alert noise A would otherwise leave
(architecture review). The two merge-triggered flows race (Web Platform Release builds and deploys the
image; `apply-deploy-pipeline-fix.yml` delivers `ci-deploy.sh`), and both orders must pass: new image on
the old host script (SYS_ADMIN still in the bounding set, no file cap) and new image on the new host
script (exactly the v0.332.2 container flags). If B regresses, revert B alone; the image fix stands.

Test-first (`cq-write-failing-tests-before`): the pins that encode the broken posture are repinned first
(RED against the current tree), then the changes (GREEN).

### Phase 1 - Repin the tests (RED)

1.1 `apps/web-platform/infra/sandbox-canary-soak.test.sh` section 8 currently asserts the broken posture
(`grep -q 'setcap cap_sys_admin,cap_setuid,cap_setgid+ep /usr/bin/bwrap'`, `grep -q 'getcap -r /'`,
`--cap-add SYS_ADMIN` >= 2 sites in `ci-deploy.sh`, and in `cloud-init.yml`), under a header comment that
still says "the image sets the file caps". Rewrite the header and invert all four asserts. New asserts, all
run through the harness `assert` (same shell, `eval`):

- no `setcap` command in the Dockerfile after stripping comment lines and joining `\` continuations:
  `sed -e ':a;/\\$/N;s/\\\n//;ta' "$DOCKERFILE" | grep -vE '^[[:space:]]*#' | grep -Ec '(^|[^[:alnum:]_.-])setcap[[:space:]]+(-[a-qs-z]|[^-])'` must print `0` (`setcap -r` and comments allowed; verified at plan time: prints 1 on the broken tree and on a continuation-line mutant, 0 on the v0.332.2 Dockerfile and on a comment/`setcap -r` fixture);
- the Dockerfile audit is an explicit emptiness test: `getcap -r /` is present AND is followed by `[ -z "$all" ]`, and no `|| true` follows the `getcap` on that line (structural: reject `getcap -r /[^;]*||`);
- no `--cap-add` and no `--privileged` on any non-comment line of `ci-deploy.sh` or `cloud-init.yml` (per file, per line: `grep -vE '^[[:space:]]*#' "$f" | grep -Ec -e '--cap-add' -e '--privileged'` prints `0`; the rewritten comments must not need the literal, or the grep strips comments first).

Implement as a function `check_no_filecap <dockerfile> <ci-deploy> <cloud-init>` returning non-zero on any
missing or empty input. Run the suite: RED on the current tree.

1.2 `apps/web-platform/infra/ci-deploy.test.sh`: add the outer-wrap canary skip case (Phase 2B). The
generic docker mock returns rc 0 with empty stdout for `exec`, so no new mock arm is needed for a constant
gate; assert the skip marker is logged and the outer ledger is absent (see 2B.3).

### Phase 2A - Image posture (Commit A; GREEN for the deploy)

2A.1 `apps/web-platform/Dockerfile`: delete the `RUN setcap cap_sys_admin,cap_setuid,cap_setgid+ep
/usr/bin/bwrap` line and rewrite its comment (cite this plan: file-cap bwrap non-viable for uid 1001 under
bubblewrap 0.8.0; ADR-075). Keep `libcap2-bin` (the audit uses `getcap`). Replace the end-of-runner
`{bwrap}`-only audit with an empty-set audit, still AFTER every install layer:
`RUN set -e; all="$(getcap -r / 2>/dev/null)"; [ -z "$all" ] || { echo "FATAL: unexpected file-cap binary: $all" >&2; exit 1; }`.
`getcap -r /` exits 0 on empty output and on unreadable paths (and `2>/dev/null` hides them by design),
so the explicit emptiness test is the only fail-closed mechanism; `/proc` and `/sys` hold no file caps and
are an accepted blind spot. Baseline safety: the v0.333.1 build passed an audit that already required zero
file-cap'd binaries besides bwrap, so the empty set holds for the current layer set.

### Phase 2B - Host alignment (Commit B; delivered by `deploy_pipeline_fix`)

2B.1 `apps/web-platform/infra/ci-deploy.sh`: remove `--cap-add SYS_ADMIN \` from the canary `docker run`
(~line 3875) and the production `docker run` (~line 4215); rewrite the two `#5863 arm F` comment blocks
(~3861, ~4201) to say the posture is withdrawn (no literal `--cap-add` needed in the prose).
`apps/web-platform/infra/cloud-init.yml` (~785-796): same for the first-boot `docker run`. The container
flags then match v0.332.2 exactly (`git show web-v0.332.2:apps/web-platform/infra/ci-deploy.sh` carries
zero `--cap-add SYS_ADMIN`; v0.333.1 carries four literals, two of them `docker run` flags). `cloud-init.yml` is
ignored for web-1 (`ignore_changes = [user_data]`) and shapes fresh hosts only; the auto-apply plan must
show no `hcloud_server` replacement (AC).
2B.2 Delivery: `ci-deploy.sh` reaches the host through the existing gated `terraform_data.deploy_pipeline_fix`
auto-apply (`apply-deploy-pipeline-fix.yml`; the PR merge is the authorization; no manual prod write).
2B.3 `run_outer_wrap_canary` in `ci-deploy.sh`: keep the `OUTER_LEDGER_ALIAS` early return first, then
skip while arm F is withdrawn, gated by a single constant (`OUTER_WRAP_CANARY_ENABLED="${OUTER_WRAP_CANARY_ENABLED:-0}"`),
logging `logger -t "$LOG_TAG" "OUTER_WRAP_CANARY_SKIPPED reason=arm_f_withdrawn"`. No `docker exec`, so no
new failure mode; re-arming is a one-word change in the re-spike PR. Why it is in this PR: against a plain
bwrap the `--replay-outer` classifier returns `sandbox_broken` (`wrong_elevation_userns` or EPERM), and
`run_canary_replay` calls `sandbox_canary_sentry_event` on every `sandbox_broken` (Sentry op
`sandbox-canary-outer-wrap`, every deploy), while `scripts/followthroughs/tenant-outer-wrap-soak-5863.sh`
exits 1 (FAIL) on that verdict and the sweeper reopens a closed tracker. A skipped canary writes no ledger
row, which the soak script reads as not-yet-measured. Test: `ci-deploy.test.sh` asserts the marker line and
the absent `SANDBOX_OUTER_WRAP_CANARY_STATE_FILE`; the faithful canary path is unchanged.
2B.4 Comment-only sweep of the stale file-cap statements (no behaviour change):
`apps/web-platform/scripts/sandbox-canary.mjs` (~737, ~1115, ~1185, ~1198),
`apps/web-platform/server/agent-outer-wrap.ts` (~21, ~139, ~652, ~744),
`apps/web-platform/scripts/tenant-isolation-inner-probe.sh` (~97-107) and the soak script's failure
message. `test/agent-outer-wrap.test.ts` (`BWRAP_HAS_CAPS`) and `scripts/agent-outer-wrap-debug.sh` degrade
gracefully without the cap and are not edited. Do not flip `AGENT_OUTER_WRAP`.

### Phase 3 - Docs, ADR, learning

3.1 ADR-075 amendment, written as a new dated addendum (the ADR's top-level `status: accepted` stays; it
has no `## Alternatives Considered` heading - its section is `## Rejected / deferred alternatives`, and the
spike table lives in the tenant-isolation plan, not the ADR). The addendum supersedes three named passages
of the 2026-10-08 addendum: the "**Adopted:** ... file-capability `bwrap` ... `--cap-add SYS_ADMIN`"
paragraph; the "What this delivers" paragraph (isolation is not delivered); the "Privilege-hygiene notes"
line about a `{bwrap}`-only `getcap -r /` audit (now an empty set). Flip that addendum's
`**Status: adopting**` marker to withdrawn-pending-re-spike. Add one row to `## Rejected / deferred
alternatives` for file-cap bwrap with the measured failure (`Unexpected capabilities but not setuid`,
bubblewrap 0.8.0, uid 1001, 2026-10-09) and the upstream fact that no release supports it. About 15 lines.
3.2 `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`: one paragraph "Which sub-check
failed", a generic no-SSH recipe that does not grep a known cause string (it would miss a new crash
class): (1) read `start_ts`/`end_ts` from the deploy-status JSON in the release run log (step `Verify deploy
script completion`); (2) `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since
<start> --until <end> --limit 200` with no cause grep; (3) decode with `jq -r '.raw|fromjson'` and keep rows
with `SYSLOG_IDENTIFIER == "ci-deploy"` (issue and PR bodies that quote these markers also ship through the
shipper), reading the rows that precede the `DEPLOY_ROLLBACK` line; (4) branch on `reason`:
`canary_health_failed` -> the canary container's `docker logs --tail 30` rows; `canary_sandbox_failed` ->
the `bwrap_err=` field. State the hot window (about 40 minutes) plus S3 archive, that no `ssh` or `docker
exec` appears in the path, and that container-tail rows are not redacted and must be filtered before being
pasted anywhere shared. Cross-reference the existing "Blocking bwrap sandbox probe" section instead of
duplicating it.
3.3 Learning via `soleur:compound` (topic only; date chosen at write time):
`knowledge-base/project/learnings/bug-fixes/<topic>.md` - a first-failure fix hides the second; map a tag
to its commit before concluding a fix failed (`git rev-parse web-v<ver>^{commit}`, never `headSha`); a
privilege spike must run as the prod uid; `bwrap --version` does not reach the privilege guard; upstream
bubblewrap does not support file caps for non-root.

### Phase 4 - Verification, issue disposition, deferrals

4.1 Pre-merge: `bash apps/web-platform/infra/sandbox-canary-soak.test.sh` and
`bash apps/web-platform/infra/ci-deploy.test.sh` 0 failed; `bash scripts/lint-orphan-test-suites.sh`;
`plugins/soleur/test/c4-count-parity.test.sh`; the `sandbox-canary-capture-gate` CI job (the Dockerfile
matches the `capture_trigger` regex in `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh`) green or its
ack satisfied; Phase 0.5 local repro re-run with the setcap step removed prints `pivot_root`, never
`Unexpected capabilities` (a negative-direction check only - the pass is proven by 4.3).
4.2 Merge triggers the repo's gated flows only (Web Platform Release build + deploy webhook, and
`apply-deploy-pipeline-fix.yml`); no SSH, no manual host edit. A workflow rerun is allowed only for a
transient failure of a gated workflow.
4.3 Verify with Monitor (bounded, an until-loop, not a backgrounded poll) on a 20-minute budget from the
release run's start (a healthy deploy job takes about 80 s - runs 37924139130 and 37926518883 - plus
build and queue time). Evidence, each from a command that returns it: the deploy job for the merge's
tag concludes `success` (`gh run view <id> --json jobs`); the release run log's `Verify deploy script
completion` step prints `ci-deploy.sh completed successfully for v<ver>` (this replaces a signed
`/hooks/deploy-status` call, which needs credentials; deploy-status `.tag` is the last attempt only);
`bash scripts/verify-served-sha-filecap-free.sh` prints `SERVED_SHA_FILECAP_FREE` (it reads `/health`
`build_sha`, requires it to be the removal commit or a descendant, and requires zero `setcap` lines in that
sha's Dockerfile); Better Stack, decoded and filtered on `SYSLOG_IDENTIFIER == "ci-deploy"`, shows the row
`SANDBOX_PROBE_OK ... :v<ver> rc=0` containing the merge tag (the positive proof - "no `DEPLOY_ROLLBACK`" is
weak evidence because the shipper can be silent). If the deploy fails, read its `reason` + `bwrap_err` and
apply the Phase 0.7 stop rule; do not edit the probe. If Commit A deployed on the old host script and
`bwrap_err` is `Operation not permitted`, suspect the bounding-set delta first (confirm Commit B's
`ci-deploy.sh` reached the host: deploy-status `ci_deploy_sha256` equals the repo file's sha256), then
#9860's host posture.
4.4 #9860 disposition: after 4.3 the faithful canary runs again and overwrites the ledger. Comment the new
ledger verdict on #9860. Expect `sandbox_broken` again (it pre-dates the cap, Phase 0.4): then #9860's
host-posture investigation (apparmor `soleur-bwrap` drift, `kernel.apparmor_restrict_unprivileged_userns`,
`kernel.user.max_*`) is its remaining scope and it stays open. If it is `pass`, closure still waits on
#9860's own acceptance. The soak ledger needs no repair: `consecutive_pass` resets on `sandbox_broken` by
design. PR body: `Closes #9871`, `Ref #9860`.
4.5 Deferral issues (each with re-evaluation criteria and a milestone from
`knowledge-base/product/roadmap.md`; verify labels exist before using them): (a) re-spike arm F's privilege
mechanism as uid 1001 in the real image under the prod apparmor/seccomp profile (O3/O5/O6 candidates,
the upstream constraint above), Ref #9773; (b) pre-merge in-image real-bwrap-as-uid-1001 probe (the capture
gate uses a shim, so real bwrap is first exercised at deploy); (c) run the bwrap probe report-only when the
health gate fails, so both causes surface in one deploy (this incident's second cause stayed hidden because
the sandbox probe never runs once health fails); (d) harden the image's setuid-root binaries (strip the
setuid/setgid bits that the app does not need, set `no-new-privileges` on the `docker run` lines) after a
measurement against the image's tooling (priority: P2; unrelated to this incident).

## Files to Edit

- `apps/web-platform/Dockerfile` - drop the bwrap `setcap`; empty-set `getcap -r /` audit; comments.
- `apps/web-platform/infra/sandbox-canary-soak.test.sh` - header + invert four asserts; `check_no_filecap` + derive-at-test-time mutation cases.
- `apps/web-platform/infra/ci-deploy.sh` - drop 2x `--cap-add SYS_ADMIN`; constant-gated outer-wrap canary skip; comments.
- `apps/web-platform/infra/ci-deploy.test.sh` - outer-wrap canary skip case.
- `apps/web-platform/infra/cloud-init.yml` - drop `--cap-add SYS_ADMIN`; comment.
- `apps/web-platform/scripts/sandbox-canary.mjs`, `apps/web-platform/server/agent-outer-wrap.ts`, `apps/web-platform/scripts/tenant-isolation-inner-probe.sh` - comment-only.
- `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md` - dated addendum.
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` - "which sub-check failed" paragraph.

## Files to Create

- `scripts/verify-served-sha-filecap-free.sh` - the `discoverability_test` probe (below); read-only, no credentials, under 15 s.
- `knowledge-base/project/learnings/bug-fixes/<topic>.md` (via compound).
- Tiny hand-written stubs for the harness-pass case live inside the test (heredoc to `$TMP`), named `Dockerfile.pass1` style, not committed fixture trees.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Phase 0 re-run on the newest failed deploy matches the v0.333.1 signature (else Phase 0.7 stop rule); key lines pasted in the PR body, filtered of container-tail text.
- [ ] `sed -e ':a;/\\$/N;s/\\\n//;ta' apps/web-platform/Dockerfile | grep -vE '^[[:space:]]*#' | grep -Ec '(^|[^[:alnum:]_.-])setcap[[:space:]]+(-[a-qs-z]|[^-])'` prints `0` (it prints `1` on `main` today).
- [ ] For each of `apps/web-platform/infra/ci-deploy.sh` and `apps/web-platform/infra/cloud-init.yml`: `grep -vE '^[[:space:]]*#' <file> | grep -Ec -e '--cap-add' -e '--privileged'` prints `0` (single file per invocation; it prints non-zero on `main` today).
- [ ] `bash apps/web-platform/infra/sandbox-canary-soak.test.sh` and `bash apps/web-platform/infra/ci-deploy.test.sh` report 0 failed, and each Guard Contract mutant (derived at test time) makes `check_no_filecap` fail while the pass stubs pass.
- [ ] `bash scripts/lint-orphan-test-suites.sh` exits 0 (suite registered); `plugins/soleur/test/c4-count-parity.test.sh` exits 0; the `sandbox-canary-capture-gate` job is green or its ack satisfied.
- [ ] `git diff --name-only origin/main...HEAD` is a subset of the Files-to-Edit/Create lists plus the pipeline-written `knowledge-base/project/specs/feat-one-shot-9860-deploy-canary-health-failed/*` and `knowledge-base/INDEX.md`.
- [ ] The auto-apply plan for the `ci-deploy.sh`/`cloud-init.yml` change shows no `hcloud_server` replacement; `AGENT_OUTER_WRAP` is not flipped.
- [ ] ADR-075 addendum in the same diff, citing the real section headings; PR body has `Closes #9871` and `Ref #9860` (never `Closes #9860`); deferral issues 4.5 (a)-(c) exist and are linked; open-PR overlap with #9809 re-checked and rebased.

### Post-merge (repo-gated flows, no operator step)

- [ ] The Web Platform Release deploy job for the merge's tag concludes `success` within the 4.3 budget.
- [ ] `bash scripts/verify-served-sha-filecap-free.sh` prints `SERVED_SHA_FILECAP_FREE`.
- [ ] Better Stack (decoded, `SYSLOG_IDENTIFIER == "ci-deploy"`) shows `SANDBOX_PROBE_OK ... :v<ver> rc=0` for the merge tag and `OUTER_WRAP_CANARY_SKIPPED`.
- [ ] deploy-status `ci_deploy_sha256` equals `sha256sum apps/web-platform/infra/ci-deploy.sh` (Commit B delivered).
- [ ] The fresh faithful-canary verdict (new `checked_at` after the deploy start) is commented on #9860.

## Test Scenarios

- Given the post-fix tree, `check_no_filecap` passes; given a copy with `RUN setcap ... /usr/bin/bwrap` re-added, with a different binary's setcap on a `\` continuation line, with the audit's emptiness test replaced by `|| true`, with `--cap-add SYS_ADMIN` re-added at one `docker run` site, or given an empty/missing file, it fails.
- Given a Dockerfile whose only `setcap` mentions are a comment and `setcap -r`, it passes.
- Given `OUTER_WRAP_CANARY_ENABLED` unset, `run_outer_wrap_canary` logs the skip marker, runs no `docker exec`, and writes no outer ledger row; given `OUTER_WRAP_CANARY_ENABLED=1` the replay runs as before.

## Observability

```yaml
liveness_signal:
  what: Web Platform Release deploy job conclusion, /health build_sha, and the SANDBOX_PROBE_OK / DEPLOY_ROLLBACK lines the ci-deploy tag ships to Better Stack
  cadence: per deploy (every push to main that changes the web image)
  alert_target: ops@jikigai.com deploy-failure email (Resend step in the deploy job); Sentry op=sandbox-canary for the faithful verdict
  configured_in: .github/workflows/web-platform-release.yml (Email notification step) and apps/web-platform/infra/ci-deploy.sh (logger -t ci-deploy markers)
error_reporting:
  destination: GitHub run annotation (reason=...) plus Better Stack tag ci-deploy (bwrap_err, canary container tail); Sentry for faithful/outer-wrap verdicts
  fail_loud: true
failure_modes:
  - mode: canary container crashes at load (the ERR_INVALID_ARG_TYPE class)
    detection: layer 3 (Vector host_scripts_journald, SYSLOG_IDENTIFIER ci-deploy) - the rollback arm pipes `docker logs soleur-web-platform-canary --tail 30` to logger; layer 6 (workflow run log) - `::error::ci-deploy.sh exited 1 (reason=canary_health_failed)`
    alert_route: deploy-failure email, then the runbook recipe (3.2)
  - mode: legacy bwrap probe fails for a capability or posture reason
    detection: in-surface probe (a docker exec of bwrap inside the canary container) shipped on layer 3; the DEPLOY_ROLLBACK line carries rc, ms, cstate, err_chars and the sanitized bwrap_err, discriminating file-cap (Unexpected capabilities), userns EPERM (Operation not permitted) and the PDEATHSIG race (rc=137, empty) in one event; layer 6 run log carries reason=canary_sandbox_failed
    alert_route: deploy-failure email; Better Stack tag ci-deploy
  - mode: an image ships a file-cap'd binary or a container grant returns
    detection: workflow run log of the image-build step (the empty-set getcap audit aborts the build) and CI check sandbox-canary-soak.test.sh failing pre-merge
    alert_route: CI failure on the PR; failed image build in the release run
  - mode: outer-wrap canary paging for an arm that is not provisioned
    detection: Sentry monitor op=sandbox-canary-outer-wrap (existing issue alert, routes to ops email) must show zero events after the deploy; the OUTER_WRAP_CANARY_SKIPPED marker on layer 3 proves the skip ran
    alert_route: Sentry issue alert (existing)
  - mode: Commit B's ci-deploy.sh not delivered to the host
    detection: deploy-status ci_deploy_sha256 differs from sha256sum of the repo file; apply-deploy-pipeline-fix workflow run log red
    alert_route: workflow failure notification
logs:
  where: Better Stack (tags ci-deploy, webhook), GitHub Actions run logs (deploy-status JSON in the Verify deploy script completion step)
  retention: Better Stack hot window about 40 minutes plus S3 archive (betterstack-query.sh queries both); Actions per repo default
discoverability_test:
  command: bash scripts/verify-served-sha-filecap-free.sh
  expected_output: SERVED_SHA_FILECAP_FREE
```

The probe script (created in this PR, read-only, no credentials, well under 15 s): reads `build_sha` from
`curl -fsS --max-time 8 https://app.soleur.ai/health`; finds the removal commit with
`git log -1 --format=%H -S'setcap cap_sys_admin' -- apps/web-platform/Dockerfile` (the latest commit
touching that string); requires `git merge-base --is-ancestor <removal> <build_sha>`; requires zero setcap
command lines in `git show <build_sha>:apps/web-platform/Dockerfile` using the Phase 1 pipeline; prints
`SERVED_SHA_FILECAP_FREE` only when all hold. It prints nothing on the pre-fix served sha `87b26df8e4` (not a
descendant of the removal commit), so unlike a bare `/health` liveness check it fails before the fix and
passes after. It needs full git history; on a shallow checkout it prints nothing (fail-closed).

## Guard Contract

### Guard 1 - no file capabilities and no SYS_ADMIN grant without a measured consumer

**Property.** No binary in the runner image carries file capabilities, and neither `ci-deploy.sh` nor
`cloud-init.yml` grants a container capability (`--cap-add`) or `--privileged`; re-introducing any of them
requires editing this guard in the same diff (the review trigger).

**Assembly.** Two chokepoints, both required: the end-of-runner `getcap -r /` empty-set audit RUN in the
Dockerfile (authoritative for xattr file caps, runs in the image, sees any cap-granting layer including a
later package; it does not see setuid/setgid bits or runtime-mounted paths) and `check_no_filecap` in
`sandbox-canary-soak.test.sh` (static, pre-merge; sees the Dockerfile text including `\`-continued RUN lines,
and every non-comment line of the two `docker run` files). The guard does not prove bwrap RUNS as uid 1001
(a setuid or other mechanism would pass it); that gap is deferral 4.5(b).

**Mutation matrix** (mutants derived at test time with `sed`/`printf` from the real files into `$TMP`).

| # | Edit (must drive the guard RED) | Targets |
|---|---|---|
| M1 | Add `RUN setcap cap_sys_admin,cap_setuid,cap_setgid+ep /usr/bin/bwrap` | the property |
| M2 | Add, after a compliant first state, `setcap -q cap_net_raw+ep /usr/bin/ping` on the continuation line of another `RUN`, and a `/usr/sbin/setcap ...` spelling | a second member, another binary, the `\` form, a path-qualified command, a flag other than `-r` |
| M3 | Point `check_no_filecap` at an empty or missing file (each of the three inputs) | the guard's own dispatch: must fail, never "0 checked, exit 0" |
| M4 | Rewrite the audit to `all="$(getcap -r / \|\| true)"`, pipe it into `grep`, or drop the `[ -z "$all" ]` test | the audit's fail-closed property (structural reject) |
| M5 | Re-add `--cap-add SYS_ADMIN` at ONE of the two `ci-deploy.sh` `docker run` sites (the other stays clean), then at the `cloud-init.yml` site | per-site, not a `>= N` floor |
| M6 | Add `--privileged` or `--cap-add=SYS_ADMIN` (equals form) at one site | other spellings of the same grant |

**Harness rows.** H1 (must-PASS, non-canonical): a stub whose only `setcap` mentions are a comment and
`setcap -r /usr/bin/bwrap`, and a `docker run` stub whose only `--cap-add` is inside a comment. H2 (suite
edit): replace the grep in `check_no_filecap` with `true`; M1 must then fail the suite, proving the harness
can go red.

**Anchor.** Nothing stored is compared; the only expected value is the empty set. Weakening needs both the
audit RUN and `check_no_filecap` edited in one reviewed diff.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-075 (Phase 3.1): arm F's file-capability mechanism is withdrawn; not deferred.

### C4 views

No C4 impact. All three of `diagrams/model.c4`, `views.c4`, `spec.c4` were checked: external actors (agent
end user, support user, founder/operator, outside contributor) unchanged; external systems (GHCR/zot,
Doppler, Better Stack, Sentry, Hetzner) unchanged - no emitter edge is added or removed; no container or
data store changes; no actor-to-surface access relationship changes (the outer wrap, never enabled, is not
modeled; `grep -n -i 'bwrap\|capab\|outer' model.c4` shows only unrelated sandbox mentions).
`plugins/soleur/test/c4-count-parity.test.sh` is an acceptance criterion (the cardinality gate).

### Sequencing

The amendment is true as of this PR (the cap is removed in the same diff).

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Two engineering reviewers disagreed on the shape of the PR, and the later evidence settled it.
The CTO and simplicity reviews recommended an image-only unblock (everything touching `ci-deploy.sh`
split out); the architecture and security reviews showed that doing so deploys a container posture prod never
ran (the host script gained `--cap-add` at 12:11:34Z, after the last passing probe), widens seccomp through the
`caps:[CAP_SYS_ADMIN]` rule, and leaves a Sentry page per deploy plus a soak-tracker FAIL that reopens a
closed tracker. Resolution: one PR, two independently revertable commits (A: image; B: host alignment); the
getcap-gated canary skip the CTO flagged as fail-open became a constant gate with a marker. Evidence gaps
closed: the Dockerfile/infra diff between 87b26df8e4 and ceb1c6c1ba was listed; the empty-set audit baseline is
evidenced by the passing v0.333.1 build; 4.3 has a budget, a positive-evidence list and a failure rule.
Product/UX gate: NONE (no `components/**` or `app/**` files). GDPR gate: not triggered. Encryption posture:
not triggered (no store or connection). IaC routing: no new infrastructure; Commit B rides the existing
`deploy_pipeline_fix` auto-apply.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "first establish what actually fails the deploy canary on v0.333.0 without SSH" | Phase 0.1-0.7 | mapped |
| 2 | "whether it is the sandbox canary, the layered canary probe set in ci-deploy.sh, or something else" | Phase 0.2-0.4 | mapped |
| 3 | "then fix the root cause" | Phases 1-3 (O1) | mapped |
| 4 | "verify with a real deploy reaching the served sha" | Phase 4.3 | mapped |
| 5 | "close #9860 only if its own acceptance work is done (otherwise Ref it)" | Phase 4.4 | mapped |
| 6 | "Production writes need explicit authorization" | Phase 4.2 (merge-gated flows only) | mapped |
| 7 | "make this the leading hypothesis in the plan's Phase 0" [relayed] | Phase 0.7 (H1, falsifiers, stop rule) | mapped |
| 8 | "shape the fix options (e.g. a separate capped copy used only by the outer wrap while /usr/bin/bwrap stays plain, vs dropping the file caps) with the trade-offs" [relayed] | Fix Options | mapped |
| 9 | "the PR closes #9871 (the actual deploy blocker) and handles #9860 per its own acceptance" [relayed] | Phase 4.4 / PR body | mapped |
| 10 | "check whether the deploy-time soak verdict refreshes correctly" [relayed] | Phase 0.3, 4.4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 0 evidence | "establish what actually fails the deploy canary on v0.333.0 without SSH" | asked |
| Dockerfile setcap removal and empty-set audit | "fix the root cause" | asked |
| Soak test repin and `check_no_filecap` | "fix the root cause" | inferred - justification: the existing section 8 asserts the broken posture, so CI is red without the repin; the guard keeps the posture from silently returning |
| ADR-075 amendment | -- | inferred - justification: `wg-architecture-decision-is-a-plan-deliverable`; recorded architecture must not contradict the shipped one |
| Commit B: `--cap-add` removal, constant-gated outer canary skip, comment sweep | "fix the root cause" | inferred - justification: the grants' only consumer was the withdrawn file cap and they widen seccomp and the bounding set; the unprovisioned arm's replay pages Sentry every deploy and FAILs a soak tracker; stale comments assert a posture that no longer exists |
| `scripts/verify-served-sha-filecap-free.sh` | "verify with a real deploy reaching the served sha" | asked |
| Runbook paragraph, learning | "first establish what actually fails" | inferred - justification: the discrimination took four lookups; the paragraph makes it one |
| Deferral issues (4.5) | "otherwise Ref it" | inferred - justification: a deferral without a tracking issue is invisible (plan deferral-tracking check) |
| Fix Options table | "shape the fix options" | asked |

### Split Assessment

- Subsystems touched: 3 - `apps/web-platform` (Dockerfile, infra scripts and tests, comments), `scripts` (one probe), `knowledge-base` (ADR, runbook, learning)
- Planned files: 13 edited + 2 created | Estimated changed lines: about 250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR, two commits (A image, B host alignment); under every threshold

## Risks

- **The unblock depends on the prod apparmor/seccomp posture accepting the cap-free probe.** v0.332.1 and v0.332.2 passed it (`SANDBOX_PROBE_OK rc=0`) with that posture, and `seccomp_profile_loaded_matches_host` is true; if the next deploy fails with a different `bwrap_err`, Phase 0.7 routes to #9860's class, not to a probe edit.
- **Named unverified delta, closed by Commit B.** On the old host script the new image would run "no file cap + `SYS_ADMIN` in the bounding set", which prod has never run (Phase 0.8); plain-docker local runs cannot show the prod apparmor outcome. With Commit B delivered first (the apply workflow takes about a minute; the release path needs CI and a build) the posture equals v0.332.2's. The 4.3 failure rule names this delta as the first suspect.
- **Commit B regression risk:** a mistake in `ci-deploy.sh` can create a fourth cause behind the same canary. Mitigation: the edit is two deleted lines plus a guarded early return, covered by `ci-deploy.test.sh`; if it regresses, revert Commit B alone (the image fix stands).
- **Merge-race between releases.** Any deploy triggered before this merge (v0.333.2+ from #9808, plus #9809 if it merges first) rolls back harmlessly (the previous version keeps serving). After merge, confirm the release workflow tags the merge commit (no manual dispatch needed) before polling.
- **#9809 overlap** (other hunks in the same files): rebase risk only; it also adds a report-only deploy probe that may itself use bwrap - re-read it at work time.
- **Setuid-root binaries remain in the image** (`su`, `mount`, `newgrp`, ...; no `no-new-privileges`): pre-existing, not introduced here, and no longer paired with a `SYS_ADMIN` bounding grant after Commit B. Hardening is deferred (4.5(d)).
- `AGENT_OUTER_WRAP=1` is invalid while the arm is withdrawn (bwrap would fail closed at spawn, EPERM); a comment at `outerWrapEnabled` says so (2B.4).
- Line numbers in this plan are orientation; anchors are the quoted strings.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or unfilled fails `deepen-plan` Phase 4.6; this one is filled (`aggregate pattern`).
- `gh run view` `headSha` on `workflow_run` runs is main HEAD at trigger time; map tags with `git rev-parse web-v<ver>^{commit}`.
- Never edit the legacy bwrap probe argv or its rc handling to make a deploy pass: the `VAR="$(cmd)" || RC=$?` capture and the blocking branch are the gate.
- `deploy-status.tag` is the last attempt, not the running version; check `/health` `build_sha`.
- `bwrap --version` passes on a file-cap'd image (it never reaches the guard): it is not a regression probe.
- `grep -c` over several files prints `file:count` and exits 1 on zero; the ACs use single-file pipelines.
