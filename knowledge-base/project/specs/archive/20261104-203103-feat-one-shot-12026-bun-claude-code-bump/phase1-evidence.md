# Phase 1 evidence (scratch install, no committed pin moved)

Measured 2026-11-04 (UTC) in a detached scratch worktree at the branch merge-base `d1303cb464`, `/var/tmp/proof-12026`, installed with `npx npm@11 install --ignore-scripts` then `npx npm@11 ci --ignore-scripts` (both rc 0). The lockfile delta is 73 insertions / 73 deletions and touches only `@anthropic-ai/claude-code*` and `@anthropic-ai/claude-agent-sdk*` entries.

## Binary identity (what was loaded)

| Package | Installed version | sha256 | Embedded Bun (`strings <bin> \| grep -m1 -E '^Bun v[0-9]+\.[0-9]+\.[0-9]+'`) |
|---|---|---|---|
| `claude-agent-sdk-linux-x64` | 0.3.311 | `86dc1fcc69498159eaf15f446613e847010f9036bfbbdffd4c49350be8489ada` | `Bun v1.4.4 (Linux x64)` |
| `claude-code-linux-x64` | 2.1.311 | `86dc1fcc69498159eaf15f446613e847010f9036bfbbdffd4c49350be8489ada` | `Bun v1.4.4 (Linux x64)` |

The issue's own probe (`grep -m1 '^Bun v'`) matches the bare string-pool fragment `Bun v`, so it cannot report a version in either the old or the new binary.

## RED baseline (tests unchanged, scratch tree): 12 failed / 173 passed / 1 skipped

`sandbox-vendored-argv-tail` (tail, census, helper selection, bridge, fixture for the SDK package; tail, bridge, fixture for claude-code; lock row), `sandbox-startup-classifier` (SDK census), `broker-mechanism-spike` (declared/installed SDK version), `claude-cli-pin-knows-models` (package.json/Dockerfile agreement, expected: Dockerfile not yet moved). `agent-auth-cli-contract` passed unchanged.

## Real-SDK runtime proof set (`C4_BWRAP_REQUIRED=1`, so an unusable sandbox fails instead of skipping)

| Suite | Result |
|---|---|
| `sandbox-credential-deny-runtime` (P2) | pass (control sees the decoy; production config does not) |
| `sandbox-wrapped-command-runtime`: production-config hosted Bash (control + treatment) | pass |
| `sandbox-wrapped-command-runtime`: AF_UNIX-deny variant (4 rows incl. floor) (P4) | pass |
| `sandbox-wrapped-command-runtime`: G2 per-tenant CLI temp | 2 reds, one cause (below), reviewed |
| `sandbox-proc-mask-runtime` live spawn (P3) | 1 red: `TAIL_DRIFT` vs the stale fixture, expected (below) |
| `infra/sandbox-masked-proc-docker.test.sh` (docker 29.9.2, `SOLEUR_SANDBOX_DOCKER_APPARMOR=unconfined`) | 54 passed, 0 failed |

Docker arm scope: the mounted `/app` was the scratch tree, so the SDK under test was 0.3.311. The AppArmor half is not discharged locally (no sudo, override printed `APPARMOR_OVERRIDE`); CI `infra-validation` on the pushed head is the stand-in for that half, as the plan states.

### Red 1: live spawn tail

The live spawn tail ends `--dev /dev --unshare-pid --unshare-user <CAP_SEGMENT> --bind /proc /proc --unsetenv SRT_ALLOW_NESTED_USERNS`. The committed fixture ends at the bind. The change is an environment unset after the masked-`/proc` bind (hardening direction); the mask is unchanged. Resolved by regenerating the fixture through the capture script.

### Red 2: G2 reviewed-pin list

B can read one CLI state file outside the reviewed pin: `.claude/plugins/store/cc-plugin-agents-md_builtin-<hash>.json`, 92 bytes: `{"usage-rows-queued": "<uuid> claude-md-or-agents-md ok"}`. Content reviewed (dumped from both tenant runs): a UUID and a feature label (corrected in review 2026-11-04: from the bundle the value is `<CLI session id> <instructionFiles setting> <kind>`, HOME-wide, last writer wins; the session id is already readable in `sessions/<pid>.json`, see the ADR-075 addendum). No credential, prompt or tool output. With `plugins/store` added to the marker-scan directories, the scan found no tenant secret or content marker in it. This meets none of the relocation triggers recorded in the test (a readable file holding a credential, prompt or tool output; a demonstrated peer-key use; a visible messagingSocketPath). Resolution: add the normalized name to `OPTIONAL_HOME_STATE`, add `plugins/store` to the scanned directories, and record the file in the ADR-075 addendum list.

## F4: allowAllUnixSockets is still honoured under our production config

The wrapped-command TREATMENT row passes: with `buildAgentSandboxConfig` (`allowAllUnixSockets: true`; `server/agent-runner-sandbox-config.ts` sets none of the managed-policy modes `required`/`egress`) the command runs without the `apply-seccomp` wrapper; the CONTROL row (knob off, helper present) reproduces `apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted`. The new binary's setting list that a managed policy can drop is `network.allowAllUnixSockets` among `Za`, gated on `qa=["required","egress"]`; our config reaches neither.

## Classifier (1.7): runtime order of the helper, `LD_PRELOAD` interposer

The helper is now the `claude` binary itself, entered by `argv0=apply-seccomp` through `/proc/self/fd/3` (usage `apply-seccomp <command> [args...]`). Interposer (`/var/tmp/interpose-12026/i.c`, libc `prctl`/`mount`/`unshare`/`fork`/`execvp`/`waitpid`/`open`) around `bwrap ... -- bash -c 'exec -a apply-seccomp <claude> /usr/bin/true'`, runtime order:

1. outer process: `unshare(NEWPID|NEWNS)` attempt, `prctl(PR_SET_DUMPABLE)`, `unshare(NEWUSER)`, opens `setgroups`/`uid_map`/`gid_map`, `unshare(NEWPID|NEWNS)` after userns, `prctl(PR_SET_DUMPABLE,0)`, `fork` (init);
2. outer process after the fork: `prctl(PR_SET_NO_NEW_PRIVS)` and `prctl(PR_SET_SECCOMP)` on itself (the new `, stub` steps), then `waitpid`;
3. init: `prctl(PR_SET_DUMPABLE)`, `mount(MS_PRIVATE)`, `mount(/proc)`, open of `/proc/sys/user/max_user_namespaces` (the new warning), `prctl(PR_CAP_AMBIENT_CLEAR_ALL)`, `fork(worker)`, `waitpid`;
4. worker: `prctl(PR_SET_NO_NEW_PRIVS)`, `prctl(PR_SET_SECCOMP)` twice (the second is the new `, namespaces` filter), `execvp` of the command.

Decision: `prctl(PR_SET_NO_NEW_PRIVS, stub)`, `prctl(PR_SET_SECCOMP, stub)` and `prctl(PR_SET_SECCOMP, namespaces)` all run before `execvp` of the tenant command: add to `HELPER_STEPS_PRE_COMMAND`. `could not set user.max_user_namespaces (%s); ...` is a non-fatal warning with no `: <errno>` suffix, so `BASH_APPLY_SECCOMP_LINE` can never match it: add to `HELPER_NON_STEP_LINES` (alongside `observe sendmsg failed`). Pool census: 21 strings (19 steps + 2 non-step lines), previously 17 (16 + 1).
