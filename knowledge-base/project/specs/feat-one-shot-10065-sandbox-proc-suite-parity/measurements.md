---
issue: 10065
branch: feat-one-shot-10065-sandbox-proc-suite-parity
measured: 2026-10-12
---

# Phase 0 measurements (sandbox masked-/proc suite parity)

Environment: local docker 29.7.2, the suite's own image recipe (Dockerfile base `node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d`
plus Debian `bubblewrap procps jq openssh-client`, uid 1001), image id `sha256:e098ecd744e3f1090c2f09983277c1415e201cb3e78e46f2e51b193207e090e0`,
`bubblewrap 0.8.0`, docker default masks, `apparmor=unconfined` (the local override: the docker-mask delta is measured, the AppArmor profile is NOT; CI
proves that half), the committed `seccomp-bwrap.json`. The unmodified suite is 10 passed, 0 failed, rc 0 on the branch base.

| # | Measure | Outcome |
|---|---|---|
| M1 | `node /app/scripts/sandbox-canary.mjs --replay-outer` in the masked suite container | `{"verdict":"sandbox_broken","reason":"wrong_elevation_userns","arm":"outer-wrap"}`. The suite image carries plain Debian bubblewrap, never builds the `runner` stage, and has no elevated (file-cap or setuid) bwrap; the outer table is built for the elevated prod binary, so the replay cannot pass here for a reason unrelated to /proc. This is the same verdict the production report-only canary logs (the soak tracked by #9797). The treatment `--replay` through the shim passes in the same container (`reason ok`, sdkVersion 0.3.284). |
| M2 | C4-shaped argv (`buildLikeC4SandboxArgv` shape: fd 9 on the committed `.bpf`, fd 3 status, `--seccomp 9`, `--json-status-fd 3`) through `/usr/bin/bwrap` under the masks | Pass: payload sentinel printed, `bwrap_rc=0`, status fd `{ "exit-code": 0 }`. The C4 argv carries no /proc token, so it is mask-safe today. |
| M3 | umount availability; drop versus cover | `umount` and `mount` exist in the image. Mount stack: with the recursive `--ro-bind / /` and no tail bind or `--proc`, the sandbox `/proc` is the container procfs plus its mask submounts (`/proc/bus`, `/proc/fs`, `/proc/irq`, `/proc/sys`, 8 pid dirs listed); with `--tmpfs /proc` over it, `/proc` lists no pid dir. Every attempt to `umount2("/proc")` from inside the sandbox returned EPERM in all four arms (drop and cover; no cap flags and `--cap-add CAP_SYS_ADMIN`; the committed seccomp profile and `seccomp=unconfined`): unprivileged bwrap always drops its capabilities after setup and `--cap-add` is only honoured for a privileged bwrap. So no positive control exists in the unprivileged suite image, drop and cover are behaviorally identical here, and an "umount refused under the vendor caps" arm would be unattributable. Decision: no behavioral cover-vs-drop arm and no umount arm; the recorder arm (M4) is the only discriminator. |
| M4 | recorder as `SOLEUR_BWRAP_REAL` under the shim | Works. For `--unshare-user --unshare-pid --ro-bind / / --tmpfs /proc --dev /dev --bind /proc /proc -- true` the recorded argv is `--add-seccomp-fd 10 --unshare-user --unshare-pid --ro-bind / / --tmpfs /proc --dev /dev -- true`: the tail bind is dropped, the shim adds `--add-seccomp-fd N`, and the argv is written NUL-separated by a script that then execs `/usr/bin/bwrap`. |
| M5 | `docker exec -u 1001` PATH | `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`; `command -v bwrap` is `/usr/local/bin/bwrap` (the mounted shim). `sh` is dash, so `type -a` is not available there; use `bash -c`. |

## What follows from M3 (ADR-075 and the shim header)

The shim header (the "dropping the token removes the mount object entirely" sentence) and ADR-075 describe a cover as leaving a live host-procfs mount
object beneath the tmpfs that "an inner process holding CAP_SYS_ADMIN could umount". With the vendor argv's recursive `--ro-bind / /` the container's
procfs sits beneath `--tmpfs /proc` after a drop as well (M3, first rows). The two differ only for a process holding CAP_SYS_ADMIN in its mount
namespace, which the production sandbox never grants (the vendor argv carries `--cap-drop ALL`, pinned by the vendored-tail guard). This PR corrects the
ADR-075 prose and the shim header comment accordingly; no shim code line changes. The guard property is therefore stated as "no argv-requested procfs
mount at /proc" (the shim's contract), not "no procfs mount object exists".

## Hook-sandbox reachability note (D2)

The CLI platform binary has a second builder (the hook sandbox, `/run/claude-hook/apply-seccomp`, fresh `--proc /proc`, no `--ro-bind / /`). It exists only
in the CLI binary, the agent runner spawns the SDK binary with `settingSources: []`, and the shim drops its `--proc`. It is pinned by count in the
vendored-tail guard and is not claimed to be unreachable in general.

## Residual (D4): `--env-file` content versus the shim's override variables

`overlay_github_app_key` (ci-deploy.sh) refuses PATH, LD_*, NODE_*, GIT_*, BASH_*, SSL_*, *_PROXY and similar names in the prd env, but its class list
does not include `SOLEUR_BWRAP_REAL` or `SOLEUR_BWRAP_SECCOMP_BPF`, both of which the shim honours. The prd env is operator-controlled Doppler, the closed-world
tuple check does not read `--env-file` content, and nothing in this diff edits a deploy path, so this is recorded as a stated residual and not closed here.

## Branches taken (AC9)

- M1: branch (b). The outer-wrap replay under the masks cannot be asserted in the unprivileged suite image (`wrong_elevation_userns`, unrelated to /proc),
  and a weaker assertion would pass for the wrong reason. The static pins (constants, literal census, outer fixture pin that already exists) ship; the
  missing runtime replay is tracked by the issue linked from the PR body.
- M2: branch (a). The C4 argv replay runs under the masks in the docker suite with a pass assertion.
