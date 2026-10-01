---
title: "A bwrap spawned by docker exec must not arm PDEATHSIG - the deploy probe was SIGKILLing itself"
date: 2026-10-01
category: bug-fixes
tags: [bwrap, docker-exec, pdeathsig, deploy-gate, canary, ci-deploy, 8016]
issue: 8016
---

# A bwrap spawned by `docker exec` must not arm PDEATHSIG

## Symptom

The blocking bwrap probe in `apps/web-platform/infra/ci-deploy.sh` rolled production deploys back at
random with `reason=canary_sandbox_failed` (#8016). Once the self-report from PR #8026 landed, every
rollback named the same shape: `rc=137` (SIGKILL), `ms` 73-120, `cstate=running`, `err_chars=0`,
`bwrap_err="<empty>"` - 19 of 19 rows in 14 days. 7-day rate 16 rollbacks against 127 passing probes
(11.2%); the sandbox itself was healthy (the faithful SDK canary kept reporting `pass`).

## Cause

The probe argv carried `--die-with-parent`, which makes bwrap arm `PR_SET_PDEATHSIG(SIGKILL)` as its
first act. A process started by `docker exec` is spawned by runc, which exits a few milliseconds
later. When the arming lands before that exit, the kernel delivers SIGKILL to the new process: no
work done (empty stderr), container untouched (`running`), and the failing `ms` equals the passing
`ms` (about 100 ms of exec round-trip). It is a spawn-timing race, not a sandbox failure. The
`PR_SET_PDEATHSIG` "parent" is the thread that created the process (prctl(2)); upstream calls the
flag "a massive footgun" (containers/bubblewrap#692) and golang/go#9263 is the same family.

## Measurements (Docker 29.7 / runc, `--init`, bwrap 0.8, seccomp+AppArmor unconfined, SYS_ADMIN)

| Arm | Result |
|---|---|
| Probe argv WITH `--die-with-parent`, 2500 execs (planning) | 75 nonzero, all rc=137 (3.0%) |
| Same, 1500 execs (work-time re-run) | 10 nonzero (0.7%) - the rate moves with host load |
| Argv WITHOUT the flag, 2500 + 5000 execs (planning) | 0 / 7500 |
| Argv WITHOUT the flag, 1500 execs (work-time re-run) | 0 / 1500 |
| `setpriv --pdeathsig SIGKILL true`, no bwrap, 2500 execs | 120 nonzero (4.8%) - mechanism is independent of bwrap |
| Same, arming delayed 200 ms | 0 / 2500 - a timing race at process start |
| `sh -c 'exec bwrap --die-with-parent ...'` wrapper | 17 / 2500 (0.7%) - narrows, does not close |
| Gate still bites: same argv, no SYS_ADMIN, default seccomp | rc=1 "No permissions to create new namespace" |

## Fix

Removed `--die-with-parent` from the probe in `ci-deploy.sh` and from the one sibling `docker exec`
bwrap site, `audit-bwrap-uid.sh` (same latent false `CLONE_NEWUSER rejected`). Everything the sweeper
and tests anchor on is unchanged: `canary_sandbox_failed`, the `DEPLOY_ROLLBACK` / `SANDBOX_PROBE_OK`
line shapes, the `|| BWRAP_RC=$?` capture. The flag only bought cleanup of a lingering bwrap if the
`docker exec` client died; the child is `true`.

## The rule

Arming PDEATHSIG is unsafe when the arming process's parent is a SHORT-LIVED spawner, which is what
the runc `docker exec` path is. Never put `--die-with-parent` (or `setpriv --pdeathsig`) on a one-shot
probe run through `docker exec`. A long-lived node parent that blocks in `spawnSync`/`spawn` (the
faithful canary, `c4-render.ts`) is safe, which is why those never flaked. This is the opposite
direction of the #4932 revert, which concerned ADDING flags that diverge from the SDK argv.

Pinned by `ci-deploy.test.sh` Guard 2 (the argv the script actually sent, recorded by the mock docker,
keeps `--unshare-pid --dev /dev --bind / /` and omits the flag) and Guard 1 (a statement scan over
every non-test `*.sh` under `apps/web-platform/infra/`), and by `audit-bwrap-uid.test.sh` for the
sibling site.

## Repro loop

```bash
C=probe; docker run -d --name $C --init --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
  --cap-add SYS_ADMIN <image-with-bwrap> sleep 3600
loop() { n=$1; shift; bad=0; for i in $(seq 1 "$n"); do docker exec $C "$@" >/dev/null 2>&1 || bad=$((bad+1)); done; echo "n=$n nonzero=$bad"; }
loop 2500 bwrap --new-session --die-with-parent --dev /dev --unshare-pid --bind / / -- true   # a few percent rc=137
loop 2500 bwrap --new-session --dev /dev --unshare-pid --bind / / -- true                     # 0
```

## Session errors / process notes

- The planning-phase research claim "docker exec is not threaded, no PDEATHSIG parent race possible"
  was false as measured; the bwrap-free `setpriv` control is what refuted it. Measure a platform's
  spawn semantics before asserting them.
- A rollback line that names a SHAPE (signalled child, nothing printed, container alive) did not name a
  cause; the cause came from reproducing the shape locally and bisecting the argv.
- Reading guide for the fields and a recurrence note live in
  `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`.
