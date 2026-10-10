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

## Work-phase deviations (2026-10-10)

- **Hit test narrowed (Mechanical).** The plan counted `apparmor="DENIED"|type=1400|type=1326` as hits. Audit type 1400 also carries complain-mode `ALLOWED`/`AUDIT` records, which are not refusals, so a bare `type=1400` would inflate `hits`. The shipped test is `apparmor="DENIED"|type=1326`, with a fixture that proves an ALLOWED record does not count (mutation 17 kills the regression).
- **Newest-first reads use `tac` (Mechanical).** The plan's `head -c` on an oldest-first stream would keep the oldest 64 KiB of 400 audit lines (about 350 bytes each, so about 140 KB) and drop the denial that happened seconds ago. Both rungs now reverse before `head -c`; mutations 4d/4e kill removing it.
- **Mutation-battery result:** 31 mutants (27 SUT, 1 duplicate-axis, 3 harness), 29 killed outright; 20 (no fixture reached the 9999 cap) and H-b (census control tripped two rules at once) survived, were fixed with fixtures and re-killed; H-c (the mock's own `-k -n 400` argv check) is equivalent by redundancy, because D10g pins `journalctl -k -n 400` textually and kills mutation 4b on its own. The mock check stays as the "fake exits 64 on a missing flag" defense.

## Review dispositions (2026-10-11, 13-seat panel)

- **Declined: cut `kdeny` to ~30 lines and ~10 test rows (code-simplicity seat, P2 proportionality).** The operator asked for "a bounded host-side read of the kernel denial line ... scrubbed via _cred_err_tail". The six-state ladder, the anchored hit test and the closed key set exist because "could not read" and "read it, nothing there" are different facts and because tenant text must not egress; each arm is pinned by a mutation-proven row (29/31 killed outright, 2 fixed and re-killed, 1 equivalent by redundancy), and a rewrite would discard that proof and spend a second production deploy cycle on an unmeasured shape. The dead rc-141 branch is deleted. If the first bundle shows `src=none`, `kdeny` has bought one row and the Phase 6 follow-up should delete it (the SOLEUR-DEBT marker names that trigger).
- **Applied (cluster A):** the H6/H7 decision rules now state that `mproc` is host-wide, that `src=dmesg` is not time-bound, that `j=ok` means readable text only, the EPERM (bwrap) vs EACCES (AppArmor `error=-13`) tie-breaker, auditd routing and window saturation; H6 is presumed tenant-impacting until a live read says otherwise.
- **Applied (B, C, D, E):** `ok` requires rc 0; hits are anchored to a real audit record; `fstype` is limited to a short token; the header contract names the kernel reads; `--since`, `-o cat` and the key list are pinned (code literal == runbook literal); the exec cap default is 30 s (five `timeout 5` probes sum to 25 s).
- **Follow-up for the H6 issue, not this PR:** `apps/web-platform/server/agent-runner-sandbox-config.ts` (the `enableWeakerNestedSandbox` comment) still says the flag skips `--proc /proc` and that this is safe; since the shim re-adds `--proc /proc` (#9768) that comment is false. Also `cat-deploy-state.sh` runs the same unprivileged `journalctl -k` for `oom_journal_tail` and may be silently empty.
