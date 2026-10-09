---
title: "fix: unblock web-platform deploys - the file-cap'd bwrap (#9767) that a module-load crash was masking (Closes #9871, Ref #9860)"
date: 2026-10-09
slug: fix-deploy-canary-filecap-bwrap-rollback
branch: feat-one-shot-9860-deploy-canary-health-failed
issue: 9871
refs: [9860]
type: bug-fix
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

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
is plain again, replace the `{bwrap}`-only audit with an empty-set audit, repin the test that pinned
the broken posture, amend ADR-075, document how to localize a canary failure, and verify with a real
deploy that reaches the served sha. The dedicated-capped-copy alternative in #9871 was measured and
does not make the outer wrap work (Fix Options); the follow-up PR that removes the now-pointless
`--cap-add SYS_ADMIN` grants is split out of the unblock.

## Research Reconciliation - Brief vs. Codebase/Production

| Brief / relayed claim | Reality (evidence in Phase 0) | Plan response |
|---|---|---|
| v0.332.4, v0.332.5, v0.333.0 "built after" #9838 still fail, so a second cause may exist | Built from `b7fa93724a`, `460ee5813c`, `d7dee46bb0`, all before `ceb1c6c1ba` (#9838). `git merge-base --is-ancestor` is false for all three. `gh run view` `headSha` on `workflow_run` runs is main HEAD at trigger time, not the tag's commit - the source of the misreading | Tag-to-commit map is Phase 0.1; the fix targets v0.333.1's failure |
| A second cause exists | Confirmed, visible only on v0.333.1 (`canary_sandbox_failed`) | Fix Options below |
| #9860: faithful `sandbox_broken` is a non-blocking host-posture regression, maybe what fails the deploy | Non-blocking is true (`run_faithful_sandbox_canary \|\| true`). It does not fail any deploy and pre-dates the cap (v0.332.1/.2 logged it with the legacy probe green). Its ledger is stale: `checked_at` 12:09:17Z in all four failed states | Do not touch the faithful canary or host posture; Ref #9860 |
| #9871: "dedicated capped copy for the outer wrap" fixes it | The unblock half is right (`/usr/bin/bwrap` must be plain). The copy does not work for uid 1001 either (local run C: same `Unexpected capabilities`), so it would ship a SYS_ADMIN carrier that cannot run | Recorded in Fix Options and `decision-challenges.md`; O1 chosen, copy left to the re-spike |
| Spike "WORKS" for arm F (tenant-isolation plan Phase 0 table) | Reproduces as FAIL for uid 1001 in the same base image; the plan's own S0.7(d) ("inner canary argv byte-identical under file-cap bwrap") was never run as the prod user, and pre-merge gates replace bwrap with an in-process shim (`sandbox-canary-capture-gate`), so the real binary is first exercised at deploy | ADR-075 amendment; deferral issue for a pre-merge real-bwrap-as-uid-1001 probe |
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

## Fix Options (trade-offs against the tenant-isolation goal, ADR-075)

The tenant-isolation feature's goal is per-session filesystem isolation for both agent tool tiers. Today
it is dark (`AGENT_OUTER_WRAP != 1`), so no isolation is *delivered* by the cap; the cap only breaks bwrap.

| Option | Unblocks deploy | Outer wrap works for uid 1001 | Cost / risk |
|---|---|---|---|
| **O1 (chosen): drop the file cap; `/usr/bin/bwrap` plain** | Yes (restores the v0.332.2 posture that passed the probe) | No - stays dark; arm F needs a re-spike | Smallest change; reduces privilege; isolation feature delivery waits on a measured mechanism |
| O2 (#9871): cap-free `/usr/bin/bwrap` + capped copy `/usr/local/libexec/bwrap-outer`, pin `agent-outer-wrap.ts` and founder scripts to it | Yes | **No** - run C: the copy hits the same guard for uid 1001 | Ships a SYS_ADMIN carrier that cannot run, plus a path change across code, scripts, fixture, audit and tests; false assurance the feature is wired |
| O3: setuid-root copy for the outer wrap | Yes (inner path untouched) | Unmeasured - bwrap's privileged path is the setuid one | New setuid-root binary reachable by uid 1001 and every sandbox child: security review and an in-image uid-1001 measurement required; belongs to the re-spike |
| O4: tolerate/skip the legacy probe failure | Yes | n/a | Ships a build whose every agent Bash call fails; the probe is the gate. Rejected |
| O5: run the outer wrap as a root helper | Unmeasured | Unmeasured | Re-architecture of the spawn path; re-spike |

O1 is also the only option that needs no new measurement to justify. O2/O3/O5 are the re-spike's
candidate set, with the one constraint measured here: **bubblewrap 0.8.0 refuses a non-root real uid that
holds capabilities, so a mechanism must either run bwrap with real uid 0 or use setuid-root.**
The re-spike is a security-reviewed issue measured as uid 1001 in the actual image under the prod
apparmor/seccomp profile (Phase 4 deferral (a)); it is not part of this unblock.

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
- P5: #9860's acceptance (host posture) is tracked honestly - open, Ref only.

**Cut list.**

- Relax/skip the legacy probe (O4) -> P1 only, violates P2. Cut.
- Per-error reason codes in deploy-state -> P3 already met by the `DEPLOY_ROLLBACK ... bwrap_err=` Better Stack line (0.4). Cut; runbook paragraph instead.
- Capped copy (O2), setuid copy (O3), root helper (O5) -> P1 is met by O1 alone; the others need measurement. Deferred to the re-spike issue.
- `--cap-add SYS_ADMIN` removal and the outer-wrap canary skip -> neither is needed for P1/P2 (the grant is inert without a file cap, and the outer canary is report-only, `|| true`); both touch `ci-deploy.sh`, which rides the separate `deploy_pipeline_fix` delivery path. Split into a follow-up PR (Phase 4 deferral (c)).
- Fixture directory of full-copy mutated scripts, a 6-row mutation matrix, getcap-gated canary logic -> over-built for the unblock (plan review); replaced by derive-at-test-time mutants (Guard Contract).
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

## Implementation Phases (PR 1 - the unblock; Closes #9871, Ref #9860)

Test-first (`cq-write-failing-tests-before`): the pin that encodes the broken posture is repinned first (RED against the current tree), then the Dockerfile changes (GREEN).

### Phase 1 - Repin the test (RED)

1.1 `apps/web-platform/infra/sandbox-canary-soak.test.sh` section 8 currently asserts the broken posture
(`grep -q 'setcap cap_sys_admin,cap_setuid,cap_setgid+ep /usr/bin/bwrap'` and `grep -q 'getcap -r /'`).
Invert only the two Dockerfile asserts (the `--cap-add SYS_ADMIN` asserts stay in this PR; they flip in
PR 2). New asserts, all run through the harness `assert` (same shell, `eval`):

- no `setcap` command in the Dockerfile after stripping comment lines and joining `\` continuations:
  `sed -e ':a;/\\$/N;s/\\\n//;ta' "$DOCKERFILE" | grep -vE '^[[:space:]]*#' | grep -Ec '(^|[;&|[:space:]])setcap[[:space:]]+[^-]'` must print `0` (`setcap -r` and comments allowed; verified at plan time: prints 1 on the broken tree and on a continuation-line mutant, 0 on the v0.332.2 Dockerfile and on a comment/`setcap -r` fixture);
- the Dockerfile audit is an explicit emptiness test: `getcap -r /` is present AND is followed by `[ -z "$all" ]`, and no `|| true` follows the `getcap` on that line (structural: reject `getcap -r /[^;]*||`).
Implement the check as a function `check_no_filecap <dockerfile>` returning non-zero on a missing or empty file.

### Phase 2 - Image posture (GREEN for the deploy)

2.1 `apps/web-platform/Dockerfile`: delete the `RUN setcap cap_sys_admin,cap_setuid,cap_setgid+ep
/usr/bin/bwrap` line and rewrite its comment (cite this plan: file-cap bwrap non-viable for uid 1001 under
bubblewrap 0.8.0; ADR-075). Keep `libcap2-bin` (the audit uses `getcap`). Replace the end-of-runner
`{bwrap}`-only audit with an empty-set audit, still AFTER every install layer:
`RUN set -e; all="$(getcap -r / 2>/dev/null)"; [ -z "$all" ] || { echo "FATAL: unexpected file-cap binary: $all" >&2; exit 1; }`.
`getcap -r /` exits 0 on empty output and on unreadable paths, so the explicit emptiness test is the only
fail-closed mechanism. Baseline safety: the v0.333.1 build passed an audit that already required zero
file-cap'd binaries besides bwrap, so the empty set holds for the current layer set.

Nothing else changes in PR 1: `ci-deploy.sh`, `cloud-init.yml` and `server/agent-outer-wrap.ts` are
untouched, so the unblock does not depend on `deploy_pipeline_fix` host delivery. The existing host
`ci-deploy.sh` keeps `--cap-add SYS_ADMIN`; with no file cap the bounding-set grant is inert for uid 1001
(the pre-#9767 probe passed; run "no file cap" in 0.5 shows the failure moves to the posture-dependent
`pivot_root` that the prod profile permits). The outer-wrap canary (`|| true`, report-only) will report
`sandbox_broken` for the not-provisioned arm until PR 2: truthful, non-blocking, noisy.

### Phase 3 - Docs, ADR, learning

3.1 ADR-075 amendment (about 10 lines, same PR): status line "arm F's file-capability mechanism
withdrawn"; the measured failure (`Unexpected capabilities but not setuid`, bubblewrap 0.8.0, uid 1001,
2026-10-09); one `## Alternatives Considered` row for file-cap bwrap. The mount-namespace-only wrap
design, flag and code remain, dark. The candidate list lives in the re-spike issue, not the ADR.
3.2 `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`: one paragraph "Which sub-check
failed": `reason=canary_health_failed` -> canary container crash, read the `docker logs --tail 30` rows;
`canary_sandbox_failed` -> read the `DEPLOY_ROLLBACK ... bwrap_err=` row; the Phase 0.4 query verbatim.
3.3 Learning via `soleur:compound` (topic only; date chosen at write time):
`knowledge-base/project/learnings/bug-fixes/<topic>.md` - a first-failure fix hides the second; map a tag
to its commit before concluding a fix failed (`git rev-parse web-v<ver>^{commit}`, never run `headSha`);
a privilege spike must run as the prod uid; `bwrap --version` does not reach the privilege guard.

### Phase 4 - Verification, issue disposition, deferrals

4.1 Pre-merge: `bash apps/web-platform/infra/sandbox-canary-soak.test.sh` 0 failed;
`bash scripts/lint-orphan-test-suites.sh` confirms the suite is registered;
`plugins/soleur/test/c4-count-parity.test.sh` green; Phase 0.5 local repro re-run with the setcap step
removed prints `pivot_root`, never `Unexpected capabilities` (a negative-direction check only - the pass
is proven by 4.3).
4.2 Merge triggers the repo's gated flows only (Web Platform Release build + deploy webhook); no SSH, no
manual host edit. A workflow rerun is allowed only for a transient failure of a gated workflow.
4.3 Verify by polling (Monitor, bounded, not a backgrounded loop) with a 15-minute budget from the
release run's start (baseline: a healthy deploy job takes about 80 s - runs 37924139130 and 37926518883 -
plus build and queue time): the deploy job for the merge's tag concludes `success`; deploy-status
`exit_code 0, reason ok, tag v<ver>`; `curl https://app.soleur.ai/health` reports `build_sha` equal to the
merge commit (not `87b26df8e4`); Better Stack shows `SANDBOX_PROBE_OK ... rc=0` for that tag and no
`DEPLOY_ROLLBACK` for it. If the deploy fails: read its `reason` + `bwrap_err` and apply the Phase 0.7
stop rule; do not edit the probe.
4.4 #9860 disposition: after 4.3 the faithful canary runs again and overwrites the ledger. Comment the new
ledger verdict on #9860. Expect `sandbox_broken` again (it pre-dates the cap, Phase 0.4): then #9860's
host-posture investigation (apparmor `soleur-bwrap` drift, `kernel.apparmor_restrict_unprivileged_userns`,
`kernel.user.max_*`) is its remaining scope and it stays open. If it is `pass`, closure still waits on
#9860's own acceptance. The soak ledger needs no repair: `consecutive_pass` resets on `sandbox_broken` by
design. PR body: `Closes #9871`, `Ref #9860`.
4.5 Deferral issues (each with re-evaluation criteria and a milestone from
`knowledge-base/product/roadmap.md`; verify labels exist before using them): (a) re-spike arm F's privilege
mechanism as uid 1001 in the real image under the prod apparmor/seccomp profile (O2/O3/O5 candidates, the
0.5 constraint), Ref #9773; (b) pre-merge in-image real-bwrap-as-uid-1001 probe (the capture gate uses a
shim); (c) **PR 2** follow-up: remove `--cap-add SYS_ADMIN` from `ci-deploy.sh` (canary + prod run) and
`cloud-init.yml`, flip the soak test's cap-add asserts to "absent" (non-comment lines, any
`--cap-add`/`--privileged` spelling), skip the outer-wrap canary while arm F is withdrawn (fix the
swap-reaching mock arms in `ci-deploy.test.sh`), update the stale comments in
`scripts/sandbox-canary.mjs` and `server/agent-outer-wrap.ts`; merge only after PR 1's deploy is verified.

## Files to Edit (PR 1)

- `apps/web-platform/Dockerfile` - drop the bwrap `setcap`; empty-set `getcap -r /` audit; comments.
- `apps/web-platform/infra/sandbox-canary-soak.test.sh` - invert the two Dockerfile asserts; `check_no_filecap` + derive-at-test-time mutation cases.
- `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md` - amendment.
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` - "which sub-check failed" paragraph.

## Files to Create

- `knowledge-base/project/learnings/bug-fixes/<topic>.md` (via compound).
- Tiny hand-written stubs for the harness-pass case live inside the test (heredoc to `$TMP`), named `Dockerfile.pass1` style, not committed fixture trees.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Phase 0 re-run on the newest failed deploy matches the v0.333.1 signature (else Phase 0.7 stop rule); key lines pasted in the PR body, filtered of container-tail text.
- [ ] `sed -e ':a;/\\$/N;s/\\\n//;ta' apps/web-platform/Dockerfile | grep -vE '^[[:space:]]*#' | grep -Ec '(^|[;&|[:space:]])setcap[[:space:]]+[^-]'` prints `0` (it prints `1` on `main` today).
- [ ] `bash apps/web-platform/infra/sandbox-canary-soak.test.sh` reports 0 failed, and each Guard Contract mutant (derived at test time) makes `check_no_filecap` fail while the pass stubs pass.
- [ ] `bash scripts/lint-orphan-test-suites.sh` exits 0 (suite registered); `plugins/soleur/test/c4-count-parity.test.sh` exits 0.
- [ ] `git diff --name-only origin/main...HEAD` is a subset of the Files-to-Edit/Create lists plus the pipeline-written `knowledge-base/project/specs/feat-one-shot-9860-deploy-canary-health-failed/*` and `knowledge-base/INDEX.md`; `ci-deploy.sh` and `cloud-init.yml` are absent.
- [ ] ADR-075 amended in the same diff; PR body has `Closes #9871` and `Ref #9860` (never `Closes #9860`); deferral issues 4.5 (a)-(c) exist and are linked; open-PR overlap with #9809 re-checked and rebased.

### Post-merge (repo-gated flows, no operator step)

- [ ] The Web Platform Release deploy job for the merge's tag concludes `success` within the 4.3 budget.
- [ ] `curl -s https://app.soleur.ai/health` shows the merge commit's `build_sha` and `"status":"ok"`.
- [ ] Better Stack shows `SANDBOX_PROBE_OK` for that tag; no `DEPLOY_ROLLBACK` for it.
- [ ] The fresh faithful-canary verdict (new `checked_at` after the deploy start) is commented on #9860.

## Test Scenarios

- Given the post-fix Dockerfile, `check_no_filecap` passes; given a copy with `RUN setcap ... /usr/bin/bwrap` re-added, with a different binary's setcap on a `\` continuation line, with the audit's emptiness test replaced by `|| true`, or given an empty/missing file, it fails.
- Given a Dockerfile whose only `setcap` mentions are a comment and `setcap -r`, it passes.

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
    detection: ci-deploy pipes `docker logs soleur-web-platform-canary --tail 30` to logger on rollback; Better Stack query in Phase 0.4
    alert_route: deploy-failure email, then the runbook paragraph (3.2)
  - mode: legacy bwrap probe fails for a capability or posture reason
    detection: in-surface probe - `docker exec` of bwrap inside the canary container; the DEPLOY_ROLLBACK line carries rc, ms, cstate, err_chars and the sanitized bwrap_err, discriminating file-cap (Unexpected capabilities), userns EPERM (Operation not permitted) and the PDEATHSIG race (rc=137, empty) in one event
    alert_route: deploy-failure email; Better Stack tag ci-deploy
  - mode: an image ships a file-cap'd binary again
    detection: the Dockerfile empty-set getcap audit aborts the build; sandbox-canary-soak.test.sh fails pre-merge
    alert_route: CI failure on the PR; failed image build in the release run
  - mode: outer-wrap canary reports sandbox_broken for the withdrawn arm until PR 2
    detection: Sentry op=sandbox-canary-outer-wrap events after the deploy
    alert_route: Sentry issue alert (existing); closed by PR 2
logs:
  where: Better Stack (tags ci-deploy, webhook), GitHub Actions run logs (deploy-status JSON in the Verify deploy script completion step)
  retention: Better Stack hot window about 40 minutes plus S3 archive (betterstack-query.sh queries both); Actions per repo default
discoverability_test:
  command: curl -s https://app.soleur.ai/health
  expected_output: '"status":"ok"'
```

## Guard Contract

### Guard 1 - no file-capability binary in the image

**Property.** No binary in the runner image carries file capabilities, and re-introducing one requires
editing this guard in the same diff (the review trigger).

**Assembly.** Two chokepoints, both required: the end-of-runner `getcap -r /` empty-set audit RUN in the
Dockerfile (authoritative, runs in the image, sees any cap-granting layer including a later package), and
`check_no_filecap` in `sandbox-canary-soak.test.sh` (static, pre-merge; sees the Dockerfile text, including
`\`-continued RUN lines and comments). Neither sees the other's blind spot. The guard does not prove bwrap
RUNS as uid 1001 (a setuid or other mechanism would pass it); that gap is deferral (b).

**Mutation matrix** (mutants derived at test time with `sed`/`printf` from the real Dockerfile into `$TMP`).

| # | Edit (must drive the guard RED) | Targets |
|---|---|---|
| M1 | Add `RUN setcap cap_sys_admin,cap_setuid,cap_setgid+ep /usr/bin/bwrap` | the property |
| M2 | Add, after a compliant first state, `setcap cap_net_raw+ep /usr/bin/ping` on the continuation line of another `RUN` | a second member, a different binary, the `\` form |
| M3 | Point `check_no_filecap` at an empty or missing file | the guard's own dispatch: must fail, never "0 checked, exit 0" |
| M4 | Rewrite the audit to `all="$(getcap -r / \|\| true)"` or drop the `[ -z "$all" ]` test | the audit's fail-closed property (structural reject) |

**Harness rows.** H1 (must-PASS, non-canonical): a stub whose only `setcap` mentions are a comment and
`setcap -r /usr/bin/bwrap`. H2 (suite edit): replace the grep in `check_no_filecap` with `true`; M1 must
then fail the suite, proving the harness can go red.

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
**Assessment:** The two-cause diagnosis is sound; restructure so the unblock is minimal (adopted: PR 1 is
image-only, `--cap-add` removal and the outer-wrap canary skip are PR 2). The outer-wrap canary skip must
not be keyed on a `getcap` exec whose failure silently disables it (adopted: deferred, and PR 2 will
use the flag/constant gate plus a distinct marker for exec failure). Evidence gaps closed: the Dockerfile
and infra diff between 87b26df8e4 and ceb1c6c1ba was listed (Research Insights); the empty-set audit
baseline is evidenced by the passing v0.333.1 build; 4.3 now has a budget and a failure rule. Product/UX
gate: NONE (no `components/**` or `app/**` files). GDPR gate: not triggered. Encryption posture: not
triggered (no store or connection). IaC routing: no new infrastructure in PR 1; PR 2's `ci-deploy.sh`
edit rides the existing `deploy_pipeline_fix` auto-apply.

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
| Runbook paragraph, learning | "first establish what actually fails" | inferred - justification: the discrimination took four lookups; the paragraph makes it one |
| Deferral issues (4.5) | "otherwise Ref it" | inferred - justification: a deferral without a tracking issue is invisible (plan deferral-tracking check) |
| Fix Options table | "shape the fix options" | asked |

### Split Assessment

- Subsystems touched: 2 - `apps/web-platform` (Dockerfile, one infra test), `knowledge-base` (ADR, runbook, learning)
- Planned files: 4 edited + 1 created | Estimated changed lines: about 120
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR for the unblock; PR 2 (deferral 4.5(c)) is already split out

## Risks

- **The unblock depends on the prod apparmor/seccomp posture accepting the cap-free probe.** v0.332.1 and v0.332.2 passed it (`SANDBOX_PROBE_OK rc=0`) with that posture, and `seccomp_profile_loaded_matches_host` is true; if the next deploy fails with a different `bwrap_err`, Phase 0.7 routes to #9860's class, not to a probe edit.
- **Merge-race between releases.** Any deploy triggered before this merge (v0.333.2+ from #9808, plus #9809 if it merges first) rolls back harmlessly (the previous version keeps serving). After merge, confirm the release workflow tags the merge commit (no manual dispatch needed) before polling.
- **Old host `ci-deploy.sh` still passes `--cap-add SYS_ADMIN`** during PR 1's deploy: harmless for uid 1001 without a file cap (the exec-denied case in 0.5 row A needed the cap-less bounding set and the file cap together), untested end to end until 4.3.
- **#9809 overlap** (other hunks in the same files): rebase risk only; it also adds a report-only deploy probe that may itself use bwrap - re-read it at work time.
- Line numbers in this plan are orientation; anchors are the quoted strings.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or unfilled fails `deepen-plan` Phase 4.6; this one is filled (`aggregate pattern`).
- `gh run view` `headSha` on `workflow_run` runs is main HEAD at trigger time; map tags with `git rev-parse web-v<ver>^{commit}`.
- Never edit the legacy bwrap probe argv or its rc handling to make a deploy pass: the `VAR="$(cmd)" || RC=$?` capture and the blocking branch are the gate.
- `deploy-status.tag` is the last attempt, not the running version; check `/health` `build_sha`.
- `bwrap --version` passes on a file-cap'd image (it never reaches the guard): it is not a regression probe.
- `grep -c` over several files prints `file:count` and exits 1 on zero; the ACs use single-file pipelines.
