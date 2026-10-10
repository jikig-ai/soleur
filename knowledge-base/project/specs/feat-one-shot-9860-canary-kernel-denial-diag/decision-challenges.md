# Decision challenges (headless plan run, #9860)

## 1. The asked `kdeny` row will probably name nothing (User-Challenge)

- Brief direction: "Add a bounded host-side read of the kernel denial line (audit/dmesg ...) as a new DIAG row".
- Evidence: a local docker repro (node:22-slim digest, bubblewrap 0.8.0, uid 1001, repo seccomp profile) shows the exact `Can't mount proc on /newroot/proc: Operation not permitted` under docker's default masked /proc and rc=0 with `--security-opt systempaths=unconfined`. That failure is the kernel refusing a fresh procfs inside a user namespace: a bare EPERM with no audit or dmesg line. The seccomp profile allows `mount` unconditionally and defaults to silent ERRNO, and the AppArmor profile allows `mount,`. The script also runs as `deploy`, which likely cannot read the kernel stream.
- Default taken: the asked row ships as specified (self-reporting ladder, so "unreadable" and "readable, nothing there" are distinguishable).
- Added (inferred scope, challengeable): an in-container `sdk_noproc` row (the SDK probe argv without `--proc /proc`). Cut it if the operator wants strictly the asked row; the cost of cutting is a likely second production deploy cycle.

## 2. Two plan-review seats suggested one rung, not two (Taste)

- DHH and the simplicity seat suggested dropping the `dmesg` rung (the deploy user that cannot read `journalctl -k` probably cannot read `dmesg` either). The operator's brief names "audit/dmesg", so both rungs stay; they share one classifier and one mock. Cheap to cut at work time if the operator agrees.

## 3. #9860 may be a code-shaped regression with user impact, not a host regression (Taste)

- The issue body says "host posture regression". Timeline evidence: the shim that requires a fresh `--proc /proc` (#9768, 2026-10-09T01:31Z; gated by #9803 at 04:04Z) preceded the first faithful `sandbox_broken` (04:52:18Z). `failIfUnavailable: true` plus an availability check that only runs `bwrap --version` means a failing sandbox is silent at startup. If production agent sessions replay the same argv they may be failing for real users. Plan Phase 0 adds a read-only Sentry check before anything ships; the operator may want it now, independent of this PR, and a correction comment on #9860.

## 4. Prod-equivalent repro and a throwaway-container A/B (Taste, not in this PR)

- CTO review suggested (a) a CI or workflow_dispatch job on an ubuntu-24.04 runner that replays the shipped image with the exact docker flags, loaded AppArmor profile and real SDK argv through the shim, as a permanent regression gate for the "dev host is not the shipped posture" class (the second time this class bit), and (b) a diagnostic-only second `docker run --rm` with `systempaths=unconfined` in the failure arm to turn H6 into a direct measurement. Both add machinery beyond the asked scope (a new workflow, or a container lifecycle inside the deploy script) and are left as follow-up candidates for the operator to prioritise.
