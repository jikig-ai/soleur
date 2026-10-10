---
title: "fix: canary DIAG bundle gains a bounded kernel-denial row and a no-proc control probe (diagnostics for #9860)"
type: fix
date: 2026-10-10
slug: canary-diag-kernel-denial-and-proc-mask-rows
branch: feat-one-shot-9860-canary-kernel-denial-diag
issue: 9860
refs: [9860, 9871, 9884]
lane: cross-domain
---

# fix: canary DIAG bundle gains a bounded kernel-denial row and a no-proc control probe

Ref #9860. This PR is diagnostics only. It does NOT fix the sandbox failure and must never say `Closes`
(the issue stays open until the cause is named AND the fix or its separate issue exists).

Spec lacks a valid `lane:` - defaulted to cross-domain (fail-closed, TR2).

## Overview

PR #9884 (merged 2026-10-10, `6a86bad36e`, v0.335.13) made a failed canary sandbox emit a bounded 14-row
`SOLEUR_CANARY_SANDBOX_DIAG` bundle. The first real bundle (trigger=faithful) narrowed #9860 to one row:
`sdk_probe rc=1 bwrap: Can't mount proc on /newroot/proc: Operation not permitted`, with the image, file caps,
exec, the legacy probe, the userns sysctls and the container posture all ruled out. This PR adds two rows to the
same bundle:

1. `kdeny` (host side, asked): one bounded, credential-scrubbed read of the host kernel's denial lines (journal
   kernel stream first, `dmesg` second) that reports which rung could read at all, how many lines it saw, how many
   were denials and how many were a procfs-mount denial. "Could not read" and "read it, nothing there" are
   different states and the row names which one it is. Expected outcome, stated up front: the deploy user probably
   cannot read the kernel stream (`noaccess`), and the leading cause leaves no kernel line even when it can.
2. `sdk_noproc` (in-container, inferred - see Scope Check): the SDK probe argv with `--proc /proc` removed. Paired
   with `sdk_probe` it isolates the `--proc` mount as the failing operation on the REAL host kernel in the same
   event, and it tests the shape of the candidate fix (a procfs-free argv) directly. This replaces an earlier
   draft's `procmask` row, which could not discriminate (mount points under `/proc` exist in every docker
   container).

About 30 lines of shell, one runbook table, and the test rows. No Terraform, workflow or Dockerfile change.

**Operator-visible note (independent of this PR).** The evidence below says #9860 is probably not a host regression
but a code-shaped one that may be breaking agent Bash sessions for real users since 2026-10-09T04:52Z. Phase 0 runs
the read-only check that confirms or refutes that, before anything ships.

## Research Reconciliation: brief vs. measured reality

| Brief / issue claim | Reality (command that produced it) | Plan response |
|---|---|---|
| "Remaining candidates: docker's masked /proc handling, or the seccomp filter" | The seccomp filter cannot be what singles out procfs. `jq` over `apps/web-platform/infra/seccomp-bwrap.json`: `mount`, `umount`, `umount2`, `pivot_root` are `SCMP_ACT_ALLOW` with `args: null` (unconditional); `clone`/`unshare` allow `CLONE_NEWUSER` via masked-equal rules. `mount(2)` takes the filesystem type through a pointer argument, which seccomp cannot inspect, and `direct_probe` (same filter, bind and devtmpfs mounts, implicit userns) passes. | Seccomp is demoted to "ruled out statically unless a new syscall appears". Because the profile's default action is ERRNO (silent), a seccomp refusal would also leave no kernel line, so `kdeny` hits=0 does not exonerate it; the static reading does. |
| "The `sdk_probe` line has no healthy baseline, so it is strong evidence, not proof" | A local docker repro supplies the missing contrast. `canary-repro:latest` (node:22-slim digest from the Dockerfile, bubblewrap 0.8.0, uid 1001, the repo seccomp profile): `bwrap --unshare-user --unshare-pid --proc /proc --dev /dev --bind / / -- true` under docker's DEFAULT masked `/proc` prints `bwrap: Can't mount proc on /newroot/proc: Operation not permitted`, rc=1; the identical command with `--security-opt systempaths=unconfined` is rc=0. `/proc/self/mountinfo` in the default container lists `/proc/bus /proc/fs /proc/irq /proc/sys /proc/sysrq-trigger /proc/acpi /proc/asound /proc/interrupts /proc/kcore /proc/keys /proc/scsi /proc/timer_list`. The dev host kernel (7.2.5, no AppArmor) is not prod's (6.8.0-90, AppArmor), so this corroborates the mechanism, it does not replace the prod read. | Leading hypothesis H6. `sdk_noproc` is the prod-kernel measurement: `sdk_noproc rc=0` with `sdk_probe rc=1` on the real host isolates the `--proc` mount. The mechanism is the kernel's rule that a fresh procfs is refused inside a user namespace when the mount namespace has anything mounted under `/proc`; it fails with a bare EPERM and writes no log line. |
| "#9860: host posture regression, not a code regression" (issue body, "since 04:52Z") | `git log` timestamps: #9768 (tenant `/proc` tail mask in `infra/bwrap-shim/bwrap`, which splices `--proc /proc` over the SDK's tail `--bind /proc /proc`) merged 2026-10-09T01:31Z; its first deploy was rolled back on exactly this error (learning `bwrap-args-payload-outer-resume-proc-mask-20261009.md`, "v0.330.10 rollback"); #9803 (gate the splice to argv that expose procfs) merged 04:04Z; Sentry WEB-PLATFORM-AN firstSeen 04:52:18Z is the first successful deploy after that, i.e. the first faithful canary to replay a real SDK argv through the new shim. The repo's own comment says it plainly: `enableWeakerNestedSandbox` exists because "Docker containers cannot mount proc inside user namespaces" (#1557, learning `bwrap-sandbox-three-layer-docker-fix-20260405.md`). `agent-runner-sandbox-config.ts` sets `failIfUnavailable: true`, and the SDK's availability check is `bwrap --version`, which the shim passes through, so the app starts healthy while every agent Bash spawn fails closed. | The "host regression" premise is stale-or-unproven. H6 is code-shaped and sits in a different subsystem (agent sandbox shim, ADR-075/ADR-272), which is why Phase 6 plans a separate issue rather than a fix here. Phase 0 reads whether users are affected. |
| "Add a bounded host-side read of the kernel denial line (audit/dmesg)" | The reader is `ci-deploy.sh`, which runs as `deploy` under `webhook.service` (`User=deploy`, cloud-init `users: groups: docker`, sudoers carry only fixed-argv grants, none for kernel logs). `/var/log/audit/audit.log` is root-only; `journalctl -k` needs `systemd-journal` or `adm`; `dmesg` needs `CAP_SYSLOG` when `kernel.dmesg_restrict=1` (the Ubuntu 24.04 default; NOT measured on this host). `cat-deploy-state.sh` already runs `journalctl -k ... 2>/dev/null` as the same user and its output has never been verified non-empty. | The row is a self-reporting ladder (journal, then dmesg, then `none`) that names why a rung failed. The audit-log rung is cut. If both rungs report `noaccess`, a least-privilege access change is a separate follow-up with its own plan and approval gate (Phase 6), not a privilege grant added to this PR. |
| "The AppArmor profile allows `mount,` broadly" | Verified: `apparmor-soleur-bwrap.profile` has `mount,`, `umount,`, `pivot_root,` and only `deny` rules on `@{PROC}/sys/kernel/...`, `sysrq-trigger`, `kcore`. An AppArmor mount denial would print `apparmor="DENIED" operation="mount" ... profile="soleur-bwrap" ... fstype="proc"`. | H7 stays open; `kdeny`'s `mproc` count (operation=mount AND fstype=proc) is the number that would prove it. The production container still serves during the canary and shares the profile name, so a bare profile match is noise by design and is NOT used as the hit test. |
| Observed in the first bundle: `kernel` / `hostsec` rows | Read from Better Stack (`betterstack-query.sh --since 48h --grep SOLEUR_CANARY_SANDBOX_DIAG`): `kernel=6.8.0-90-generic docker=29.3.0`; `hostsec` shows `apparmor=soleur-bwrap seccomp={'defaultAction':'SCMP_ACT_ERRNO` and no `systempaths=` entry, so the container runs with docker's default masked `/proc`. | Recorded as run context; the second fact is static support for H6 (a `systempaths=unconfined` override would appear in `hostsec`). |

## Research Insights

- Files: `apps/web-platform/infra/ci-deploy.sh` (the `# CANARY_DIAG_BEGIN` .. `# CANARY_DIAG_END` region,
  `_cred_err_tail`, `_canary_diag_emit`, `emit_canary_sandbox_diag`, two call sites), `ci-deploy.test.sh`
  (D1-D9 block, `create_docker_mock`, `create_base_mocks`, floor 568), the runbook
  `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` ("Canary sandbox DIAG bundle" and the H1-H5
  table), `apps/web-platform/infra/bwrap-shim/bwrap`, `seccomp-bwrap.json`, `apparmor-soleur-bwrap.profile`,
  `cloud-init.yml` (webhook unit, sudoers), `server/agent-runner-sandbox-config.ts`.
- Learnings applied: `2026-04-05 bwrap-sandbox-three-layer-docker-fix` (masked `/proc` blocks proc mounts inside
  user namespaces; the SDK flag exists to skip `--proc`), `2026-10-09 bwrap-args-payload-outer-resume-proc-mask`
  (the shim now REQUIRES a fresh procfs, and "dev-host is not the shipped-image toolchain"),
  `2026-06-04 cron-silence-was-bwrap-userns-drift` (never gate a deploy on a synthetic probe validated only
  against a mock; read the specific root-cause value; dark-launch anything new).
- Better Stack read (read-only, Doppler `prd_terraform`): the first bundle rows, quoted above.
- Prior art for the test shape: the #9871 plan `2026-10-09-fix-canary-sandbox-failure-self-diagnosis-plan.md`
  (NOT archived: moving it would drop the discoverability baseline of 53) and its Review Round 1 Amendments.
- Plan review (4 seats: DHH, Kieran, code-simplicity, CTO devex) changed this plan: `procmask` replaced by
  `sdk_noproc`; the `name` key and the path-elision machinery removed (a closed enum with no path field cannot leak
  a tenant path, instead of mitigating it); the `noaccess` classifier anchored on journalctl/dmesg's own hint lines
  (a broad `denied` regex would have classed the very AppArmor line the row exists to catch as `noaccess`);
  newest-lines-first reads; 14 new rows cut to 9; two guards merged into one.

### Premise Validation

Checked: #9860 is open (`gh issue view 9860`); #9886 open (out of scope). Cited paths exist on `origin/main`
(`git cat-file -e origin/main:apps/web-platform/infra/ci-deploy.sh`). Stale: the "host regression" premise and the
"seccomp is a live candidate" premise (table above). ADR corpus: the mechanism (a journald marker, free text last,
scrubbed by `_cred_err_tail`) is the ADR-115 trusted-region convention already in use; no ADR rejects it. The
kernel-log read itself (a non-root script reading the kernel stream) is not covered by any ADR; a grep of
`knowledge-base/engineering/architecture/decisions/` for `dmesg`/`journalctl -k` hit only ADR-163 (unrelated).

### Property List and Cut List (Phase 0.6b)

Properties: (P1) the next failed canary deploy states, in Better Stack, whether the host kernel logged a denial
for the mount and, if the kernel log was unreadable, says so; (P2) the same event isolates the `--proc` mount as
the failing operation on the real kernel, so one production cycle can decide H6; (P3) neither row can change the
rollback, the exit code, the state file or the teardown order, and both are time- and size-bounded; (P4) no
credential-shaped string and no tenant file name egresses; (P5) the Guard-2 probe-argv pin and every #9871 row stay
green and unedited except where the section list itself changes.

Cut List: (a) an `audit.log`/`ausearch` rung - cut: root-only, `deploy` has no grant, and audit records are printed
into the kernel stream the journal rung already reads; (b) a throwaway `docker run --cap-add SYSLOG ... dmesg` rung
- cut: a new root-equivalent container lifecycle inside a deploy script for a line the leading hypothesis says does
not exist; (c) a sudoers grant or group change to make the kernel stream readable - cut from this PR: a host IaC
change with its own apply and gate (Phase 6); (d) running the sdk argv under `systempaths=unconfined` from the
deploy script as a diagnostic A/B - cut here, surfaced as a decision challenge (it adds a container lifecycle to
the deploy script); (e) strace/`perf` in the container - cut: not in the image; (f) a new test file - cut:
`ci-deploy.test.sh` already owns the docker/logger mocks and runs in `infra-validation.yml`; (g) the `name` key,
tenant-path elision, a `procmask` row and a second guard - cut after plan review (see Research Insights).

## Hypotheses (what the new rows must discriminate in one event)

Extends the runbook's H1-H5 (H1, H2, H4, H5 are already excluded by the first bundle).

| # | Hypothesis | Rows that decide it |
|---|---|---|
| H3 | Exec works; the failure is mount creation (the #9860 shape) | established: `direct_version rc=0`, `sdk_probe` fails with `Can't mount proc` |
| H6 | docker's masked `/proc` makes the kernel refuse a fresh procfs inside the user namespace (silent EPERM, no log line). Became fatal when #9768's shim started requiring `--proc /proc` on every SDK argv | `sdk_noproc rc=0` AND `sdk_probe rc=1` (the `--proc` mount is the failing operation) AND `hostsec` carries no `systempaths=` entry AND `kdeny` `mproc=0` (a readable stream with no procfs-mount denial; unreadable is weaker). Corroborated by the local repro |
| H7 | The `soleur-bwrap` AppArmor profile denies the mount | `kdeny` `mproc>=1` with `operation='mount'` and `fstype='proc'` in the fields |
| H8 | Seccomp denies an unlisted syscall (a newer bwrap/glibc path) | not decidable from the kernel stream (default-ERRNO is silent unless the profile logs, then `type=1326` raises `hits`); the static profile reading is the evidence |

"Kernel stream unreadable" is a state of the `kdeny` row, not a hypothesis: `src=none j=noaccess d=noaccess` says
H6/H7 are undecided by the kernel log and `sdk_noproc` plus `hostsec` plus the local repro carry the diagnosis.

## Design

### `kdeny` (host side, in `emit_canary_sandbox_diag`, after `kernel`, before `done`)

One new function `_canary_kdeny_read`, inside the `CANARY_DIAG_BEGIN..END` region (so the existing census covers it),
printing exactly one line:

```text
src=<journal|dmesg|none> j=<ok|noaccess|absent|timeout|error> d=<same|skip> total=<n> hits=<n> mproc=<n> <fields>
```

Ladder. Each rung is `timeout -k 1 3 <cmd> 2>&1 | head -c 65536` inside a command substitution that exits with
`${PIPESTATUS[0]}` (the pattern the exec read already uses). Both rungs select the NEWEST lines, because
`head -c` on an oldest-first stream keeps the oldest 64 KiB and drops the denial that happened seconds ago:

1. `journalctl -k -n 400 --since=-5min --no-pager -o cat`.
2. Only when rung 1 is not `ok` OR returned zero real lines: `dmesg | tail -n 400` (the `tail` sits before `head -c`).
3. Neither usable: `src=none`.

Classification works on the output AFTER removing journalctl/dmesg's own hint lines, matched by anchored patterns
(`^Hint: You are currently not seeing messages`, `^No journal files were opened due to insufficient permissions`,
`^dmesg: read kernel buffer failed:`, `^Failed to ... (Permission denied|Operation not permitted)`). `total` and
`hits` are computed on the remaining REAL lines. A rung is `noaccess` only when a hint matched AND zero real lines
remain; it is never overridden by the words `denied`/`permission` appearing inside real kernel lines (an AppArmor
line carries `apparmor="DENIED"` and `denied_mask=`, and a broad regex would class the readable stream that holds
the very denial as `noaccess`). Status by exit code: 127 -> `absent`; 124/137 -> `timeout`; 141 (SIGPIPE from
`head -c` closing the pipe) -> `ok`; other non-zero with no real lines and no hint -> `error`; else `ok`.

Counts are produced with `awk ... END{print n+0}`, never `grep -c` under `pipefail` (a zero count exits 1, which is
exactly the readable-nothing-there state). `total`, `hits` and `mproc` are capped at 9999. `hits` counts real lines
matching `apparmor="DENIED"|type=1400|type=1326`. `mproc` counts hits that also carry `operation="mount"` and
`fstype="proc"`. The bare profile name `soleur-bwrap` and `comm="bwrap"` are NOT hit tests: the production container
shares the profile and its tenant sandboxes generate unrelated denials.

`fields` is built from the LAST mount-class hit if any, else the last hit, through a closed key allowlist in
diagnostic-value order: `operation profile fstype error info requested_mask denied_mask syscall`, values rendered
quote-folded by the scrubber, capped at 130 bytes. There is no `name` key and no `comm` key, so no file path and no
tenant-settable string can reach the row by construction. Worst-case prefix
`src=journal j=timeout d=timeout total=9999 hits=9999 mproc=9999 ` is 61 characters; 61 + 130 = 191 <= 200, so
`_cred_err_tail`'s 200-character tail never eats the status head (pinned by a boundary row).

It is emitted ONLY through `_canary_diag_emit "$trigger" kdeny "$(_canary_kdeny_read)"`, the single logger
chokepoint, so it is scrubbed by `_cred_err_tail` like every other row. `kdeny` is NOT in the in-container section
allowlist, so a container cannot forge it (it becomes `section=raw`), exactly like `host`, `hostsec`, `kernel`,
`done`. No `sudo`, no read of `/var/log/*`, no `-f`/`--follow`, no `dmesg -w`. The function declares every variable
`local`, ends in `return 0`, and runs in a command-substitution subshell, so it cannot alter the deploy's globals.

Budget: two rungs at 3 s each add at most 6 s to the existing worst case, on both triggers; an unreadable stream
returns in milliseconds. `SOLEUR-DEBT:` marker above the function: remove or demote `kdeny` once #9860's cause is
named (upgrade trigger: the issue closing), so `harvest-debt` surfaces it.

### `sdk_noproc` (in-container)

One line appended after `sdk_probe` in `CANARY_DIAG_SCRIPT`, same shape as its neighbours:
`/usr/bin/bwrap --unshare-user --unshare-pid --dev /dev --bind / / -- true` under `timeout 5`, reporting `rc=` and
the first line, i.e. `sdk_probe` with `--proc /proc` removed. It is added to the in-container allowlist regex, so
the in-container bundle is eleven sections and the closing row reads `lines=11`. The runbook's "fourteen rows"
becomes sixteen and "ten in-container" becomes eleven.

### Placement and order

In-container: `id proc lsm files caps prov direct_version direct_probe sdk_probe sdk_noproc kernel_ns`, then
`host hostsec kernel kdeny done`. `done` stays last and keeps its meaning. Both triggers carry both rows; the call
sites, their `|| true` and their ordering relative to `DEPLOY_ROLLBACK`, the Sentry page and `docker stop` are not
touched.

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` - add `_canary_kdeny_read` (with its `SOLEUR-DEBT:` marker) and the `kdeny`
  emit line inside the `CANARY_DIAG_BEGIN..END` region; add the `sdk_noproc` line to `CANARY_DIAG_SCRIPT`; add
  `sdk_noproc` to the section allowlist regex. The probe statement, `BWRAP_RC` capture, `DEPLOY_ROLLBACK` line and
  teardown order stay byte-identical.
- `apps/web-platform/infra/ci-deploy.test.sh` - new `create_mock_kernlog` (one mock installed under both
  `journalctl` and `dmesg`, switching on `basename $0`) called from `create_base_mocks`; mock default diag body
  gains an `sdk_noproc` row; new rows D10a-h and D11; existing rows updated for the new section list (same row
  count): D1c, D1i (`lines=11`), D3c2 (`-le 20` becomes `-le 21`: 16 in-container + 5 emitter rows), D3c3, D4g
  (a forged `kdeny forged=1` first word must become `raw`), D6a, D9a/b, plus the description strings and comments
  that still say "ten" or list `host, hostsec, kernel, done` (grep `ten in-container`, `ten pinned`,
  `kernel, done`, `benign ten-section`); `D_SECTIONS` gains `sdk_noproc`; raise `CI_DEPLOY_ASSERT_FLOOR` 568 to the
  measured count (expected 577) with a dated comment in the changelog block.
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` - section table gains `sdk_noproc` and
  `kdeny` rows; "fourteen rows" becomes sixteen, "ten in-container" becomes eleven, `lines=10` becomes `lines=11`,
  "`lines` > 10" becomes "> 11"; H-table gains H6-H8; the `sdk_probe` row records the measured local contrast; a
  short "Reading `kdeny`" note (what `j=`/`d=` mean, why `mproc=0` with `j=ok` is evidence and not proof, printk
  ratelimiting and silent ERRNO caveats). No SSH step.
- `plugins/soleur/test/preflight-discoverability-test.test.ts` - `BASELINE_DECLARED_PROBES` 53 to 54 with the
  PLACEMENT / TRUTH / NO SUBSTITUTE comment (this plan is the 54th declaring plan; re-measure with
  `bun test preflight-discoverability-test.test.ts -t "G1 the number"` on the branch with only the plan added, not
  assumed). A known tax of declaring `credentials_required` for a Better Stack probe, and a merge-conflict hotspot
  with any concurrent plan that also declares it.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9860-canary-kernel-denial-diag/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9860-canary-kernel-denial-diag/decision-challenges.md`

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open --json number,title,body --limit 200` filtered with
`jq --arg path` for `ci-deploy.sh`, `ci-deploy.test.sh` and `canary-probe-set.md`: zero matches, this session.
Re-run at work time and record.)

## Implementation Phases

### Phase 0 - user impact first, then sandbox and baselines

1. Read-only user-impact check (no deploy needed, GET only): Sentry events with `feature=agent-sandbox` /
   "sandbox required but unavailable" since 2026-10-09T04:52Z via `scripts/sentry-issue.sh` (token from Doppler,
   never printed; verify the exact tag/feature names first), and whether agent Bash tool calls succeed after the
   v0.334.1 deploy. Record the result in the PR body. If sessions are failing, #9860 is a user-facing incident: the
   ship step posts a correction on #9860 ("code-shaped, #9768 interacting with docker's default posture, not a host
   regression"), the follow-up issue is filed at single-user threshold, and the operator is told before merge.
2. Allocate ONE scratch copy for every mutation row and every full-suite run, per
   `plugins/soleur/skills/work/references/work-scratch-sandboxes.md`:
   `ROOT=$(git rev-parse --show-toplevel); SBX=$(bash "$ROOT/scripts/soleur-sandbox.sh" new canary-kdeny) && [ -d "$SBX" ] || exit 2`.
   Run suites and mutants with `bash "$ROOT/scripts/soleur-sandbox.sh" run-isolated "$SBX" -- bash <suite>`, restore the
   pristine file before each mutant, and `rm "$SBX"` before the seat returns (also on failure). On `ALLOC-FAILED`
   stop; never mutate the live tree and never fall back to `/tmp`.
3. Baselines in the sandbox: `bash apps/web-platform/infra/ci-deploy.test.sh` (568/568 expected),
   `python3 scripts/lint-shell-capture-exit.py`, `bash scripts/lint-orphan-test-suites.sh`.
4. Local corroboration (read-only, any docker host; recommended gate): re-run the two-line masked-`/proc` repro with
   the exact `docker run` flags from `ci-deploy.sh`, adding the `soleur-bwrap` AppArmor profile if the host can load
   it, plus the `sdk_noproc` argv (expected rc=0 in the default container). Record in the PR body.

### Phase 1 - tests first (cq-write-failing-tests-before)

In `ci-deploy.test.sh`, all RED before any `ci-deploy.sh` edit:

1. `create_mock_kernlog <dir>`: one script installed as `journalctl` and `dmesg`. Knobs `MOCK_KLOG_OUT`,
   `MOCK_KLOG_RC`, `MOCK_KLOG_SLEEP` (via `/bin/sleep`, the PATH `sleep` is a no-op) per command name, recorder
   `MOCK_KLOG_LOG` (one line per invocation, argv included); the mock ignores argv and answers from env. Default:
   readable, a few synthesized benign kernel lines, no denial. rc 127 models "absent". The 4 MB case is generated
   through `OUT`. Fixtures are synthesized (cq-test-fixtures-synthesized-only); credential shapes are built by
   concatenation so no contiguous secret-shaped literal exists in the file.
2. The default mock diag body gains `sdk_noproc rc=0 `; `D_SECTIONS` gains `sdk_noproc`.
3. Update, in place (same row count), the existing rows and strings listed under Files to Edit.
4. New rows (expected +9):
   - D10a `kdeny` is emitted once per bundle, after `kernel` and before `done`, matches `DIAG_LINE_RE`, begins `src=`;
     the `MOCK_KLOG_LOG` recorder is non-empty (the mocks, not the runner's real `journalctl`/`dmesg`, ran: no
     vacuous pass, no host-dependent result).
   - D10b a REALISTIC synthesized AppArmor mount denial (`apparmor="DENIED" operation="mount" class="mount"
     info="failed flags match" error=-13 profile="soleur-bwrap" name="/newroot/proc/" pid=... comm="bwrap"
     fstype="proc" srcname="proc" flags="rw, nosuid" denied_mask="r"`) in a readable stream: `j=ok` (NOT
     `noaccess`: the line contains `denied`), `hits=1 mproc=1`, fields carry `operation='mount'`,
     `profile='soleur-bwrap'`, `fstype='proc'`, and carry no `name`, no `comm`, no `pid`, no timestamp.
   - D10c the ladder states in one table-driven row: readable with zero hits (`j=ok hits=0 mproc=0 total>0`);
     journal hint-only then dmesg answers (`src=dmesg j=noaccess d=ok`); journal readable but empty then dmesg
     answers; both hint-only (`src=none j=noaccess d=noaccess`); both rc 127 (`absent`); an unrelated
     `profile="soleur-bwrap"` denial for a non-mount operation (`hits=1 mproc=0`). Each state asserts the deploy
     verdict is unchanged.
   - D10d both rungs hang (`MOCK_KLOG_SLEEP=60`): each cut at 3 s plus kill-after, `j=timeout d=timeout`, via
     `diag_inert` (exit code, state reason, rollback line, teardown order unchanged, wall time bounded; the
     two-rung worst case is checked against `diag_inert`'s 20 s bound, not assumed).
   - D10e a 4 MB benign stream followed by ONE denial at the very end: the row stays bounded and the denial still
     counts in `hits` (newest-lines-first), via `diag_inert`.
   - D10f credential shapes (`dp.st.`, `sk_live_`, JWT, built by concatenation) placed in a field value of a
     denial line: absent from the logger capture AND the deploy stdout, `REDACTED` present, with the unarmed
     control.
   - D10g census (positive control first, a fixture region containing `sudo journalctl` must be flagged): every
     kernel read is `timeout -k 1 3 journalctl|dmesg`, the journal rung carries `-n 400`, the dmesg rung has
     `tail -n` before `head -c`, there is no `sudo`, `/var/log`, `audit.log`, `-f`, `--follow`, `-w`, `-W`, and
     `kdeny` is emitted from exactly one `_canary_diag_emit` call. Extends the existing region-census idiom.
   - D10h boundary: `total=9999 hits=9999 mproc=9999`, `j=timeout d=timeout` and a 130-byte field string together
     still show the full `src=` head after `_cred_err_tail`.
   - D11 the REAL container script's `sdk_noproc` line carries `--unshare-user --unshare-pid` and no `--proc`
     (extends D9d's extraction), while `sdk_probe` still carries `--proc /proc`.
5. Raise `CI_DEPLOY_ASSERT_FLOOR` to the measured count with a dated changelog line (a floor left below the count
   is pure slack).

### Phase 2 - implementation in `ci-deploy.sh`

Add `_canary_kdeny_read` and the `kdeny` emit line, the `sdk_noproc` script line and the allowlist entry exactly as
Design states. Run the suite in the sandbox until green, then `shellcheck` if available,
`python3 scripts/lint-shell-capture-exit.py`, and the grep-q-pipe guard by hand (its pre-commit wiring is out of
scope, running it is not): new test code uses the file's `has_f`/`has_e` helpers, never `producer | grep -q`.

### Phase 3 - runbook and ratchet

Runbook edits listed above (anchors by heading, not line number). Bump `BASELINE_DECLARED_PROBES`; run
`cd plugins/soleur/test && bun test preflight-discoverability-test.test.ts` (a `LEFTHOOK_EXCLUDE=bun-test` commit
skips this suite, so run it before pushing).

### Phase 4 - mutation battery and verification (sandbox only)

Run every row of the Guard Contract matrix below against the sandbox copy, one mutant at a time from the pristine
backup, and record each row's killing assertion in the PR body. `python3 scripts/lint-guard-contract.py <this plan>`
and `python3 scripts/lint-infra-no-human-steps.py` on this plan. Confirm `git diff origin/main --
apps/web-platform/infra/ci-deploy.sh` shows the probe statement, `BWRAP_RC` capture, `DEPLOY_ROLLBACK` line and
teardown order byte-identical, and `ci-deploy.test.sh` shows no deleted line inside the #8016 Scenario 1-4 or
Guard 1/2 blocks.

### Phase 5 - ship pipeline and OPERATOR GATES (the parent runs review, QA, compound, ship, postmerge)

Preflight Check 6 (brand-survival self-review) is read-only; it fires because `apps/web-platform/infra/` matches the
sensitive-path regex, and the `## User-Brand Impact` section below carries the required bullets. It runs at ship, in
the live tree, against the PR body plus this plan.

| Gate | Action it guards | Authorization required |
|---|---|---|
| G1 | `gh pr merge`: merging delivers `ci-deploy.sh` to the production host (push-triggered `apply-deploy-pipeline-fix.yml`) and triggers a production release deploy | the operator's explicit go-ahead for THIS merge, stated in the session; a menu acknowledgement is not authorization (`hr-menu-option-ack-not-prod-write-auth`) |
| G2 | any `workflow_dispatch` of `apply-deploy-pipeline-fix.yml` (the #8167 eviction remedy) | explicit per-command go-ahead naming the dispatch |
| G3 | any re-run of the release workflow's failed deploy job to force a bundle (runbook: "Re-run failed jobs") | explicit per-command go-ahead |
| G4 | any Doppler WRITE | none is planned; reads only (`doppler run -p soleur -c prd_terraform -- ...` for Better Stack) and no secret value is ever printed |

PR body: `Ref #9860`, never `Closes`. Do not archive the #9871 plan or spec.

### Phase 6 - post-deploy: read the bundle and name the root cause (documented follow-up, NOT part of this PR's code)

Time-box: if no bundle exists 3 days after G1's merge (every web-platform merge triggers a release deploy, and the
faithful canary has failed on every deploy since 2026-10-09), take gate G3 or the decision-challenge repro path
instead of waiting. Owner of the outcome: the operator (the availability-versus-isolation call below is a business
decision, not a diagnostic one).

1. Parity first (read-only): `bash scripts/check-deploy-script-parity.sh --bs-only`. The release deploy that carries
   this merge can still run the previous host script; a bundle without `kdeny` on that deploy means "script not yet
   delivered", not "diagnostic failed" (runbook, "Reading absence").
2. Arm a watch with the Monitor tool (never `sleep` in the foreground; `hr-monitor-not-run-in-background-for-polling`):
   an until-loop over
   `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 2h --limit 200 --grep SOLEUR_CANARY_SANDBOX_DIAG | jq -r '.raw | fromjson? | select(.SYSLOG_IDENTIFIER=="ci-deploy") | .message'`
   that exits when a `section=kdeny` row appears.
3. Decide, then act:

| Evidence in the one event | Conclusion | Action |
|---|---|---|
| `kdeny mproc>=1` (`operation='mount'`, `fstype='proc'`) | H7: the AppArmor profile denies the mount | fix `apparmor-soleur-bwrap.profile` (same host-infra subsystem as this PR): new plan, host-file delivery, gate G1 again |
| `sdk_noproc rc=0`, `sdk_probe rc=1`, no `systempaths=` in `hostsec`, `kdeny` `mproc=0` or unreadable | H6: the shim's required fresh procfs cannot mount under docker's default masked `/proc` | DIFFERENT subsystem (agent sandbox shim, ADR-075/272, container posture): open a separate issue with the local repro commands and this bundle; threshold from the Phase 0 user-impact read |
| none of the above (`sdk_noproc` also fails, or H8 signs) | an unmodelled cause | keep #9860 open, widen the bundle in a new plan |

4. Guardrails for the H6 issue, so the fix is not made here by reflex: the `/proc` mask is the cross-tenant control
   from #9723 (host procfs would expose `/proc/<pid>/environ`). Today the product fails CLOSED (broken agent
   sandboxes, no leak); reverting the splice restores availability and re-opens #9723. Candidate fixes are
   `--security-opt systempaths=unconfined` (container-wide: it widens `/proc` for every tenant in the single
   web-platform container, so the SCOPE of the widening needs review, not only the action), a mask that does not
   need a fresh procfs under a masked parent, or a procfs-free argv path (`sdk_noproc` is the first measurement of
   that class). Each needs CTO and CLO review and an ADR-075 addendum; none weakens the mask without it.
5. If the kernel stream was `noaccess` and is still needed: least-privilege read access for the deploy user (the
   `systemd-journal` group, which is already docker-group and therefore root-equivalent, or a fixed-argv sudoers
   entry modelled on the existing `Cmnd_Alias` grants) is a host IaC change with its own plan, apply and gate.

## Observability

```yaml
liveness_signal:
  what: "journald marker SOLEUR_CANARY_SANDBOX_DIAG, now sixteen rows per bundle: section=id|proc|lsm|files|caps|prov|direct_version|direct_probe|sdk_probe|sdk_noproc|kernel_ns, then host|hostsec|kernel|kdeny|done, on every canary sandbox failure; SANDBOX_PROBE_OK on every pass"
  cadence: "per failed deploy (diag) / per deploy (OK marker)"
  alert_target: "Better Stack log query via scripts/betterstack-query.sh; the deploy job already fails the release run (legacy trigger) and the faithful verdict already pages Sentry (op=sandbox-canary)"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (emit_canary_sandbox_diag, _canary_kdeny_read); shipping path apps/web-platform/infra/vector.toml allowlists SYSLOG_IDENTIFIER ci-deploy"
error_reporting:
  destination: "Better Stack (journald tag ci-deploy via Vector); no new Sentry event, the existing rollback arm and sandbox-canary page are unchanged"
  fail_loud: "the kdeny row states its own failure (j=/d= noaccess|absent|timeout|error), so an unreadable kernel stream is a visible row, never a missing one; the closing done row still reports exec_rc/lines/capped/bytes"
failure_modes:
  - mode: "masked /proc refuses a fresh procfs in the user namespace (H6)"
    detection: "section=sdk_noproc rc=0 with section=sdk_probe Can't mount proc and section=hostsec without systempaths= (all in the same event); section=kdeny mproc=0"
    alert_route: "layer 3 (Vector journald to Better Stack); read with betterstack-query.sh"
  - mode: "AppArmor profile denies the mount (H7)"
    detection: "section=kdeny mproc>=1 with operation='mount' and fstype='proc'"
    alert_route: "layer 3"
  - mode: "the host kernel stream cannot be read by the deploy user"
    detection: "section=kdeny src=none j=noaccess d=noaccess"
    alert_route: "layer 3"
  - mode: "the kernel read hangs, floods or fails"
    detection: "timeout -k 1 3 per rung, newest-400-lines and head -c 65536 bound it; D10d/e pin that rollback, state, exit code and teardown order are unchanged; the row reports j=timeout/d=timeout"
    alert_route: "layer 3 (absence query: DEPLOY_ROLLBACK present, SOLEUR_CANARY_SANDBOX_DIAG absent, per the runbook's Reading absence table)"
  - mode: "a credential or a tenant file name reaches the marker"
    detection: "D10f (credential shapes) and D10b (no name/comm/pid in the fields) in CI before merge; _cred_err_tail at runtime; the closed key allowlist has no path-valued key"
    alert_route: "CI failure of infra-validation.yml"
logs:
  where: "journald SYSLOG_IDENTIFIER=ci-deploy on the host, shipped to Better Stack"
  retention: "Better Stack source retention (hot window about 40 minutes plus archive arm; query without --no-archive)"
discoverability_test:
  command: "bash scripts/betterstack-query.sh --since 24h --grep SOLEUR_CANARY_SANDBOX_DIAG --limit 20"
  expected_output: "section=kdeny"
  credentials_required: "BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD from Doppler soleur/prd_terraform (run under doppler run -p soleur -c prd_terraform --) - Better Stack log rows are readable only through the ClickHouse query connection; no unauthenticated probe can show that the marker egressed"
```

Layer cite (hr-observability-layer-citation): every failure mode is layer 3 (Vector journald to Better Stack).
Layer 6 (synchronous webhook response) is unavailable: the deploy is asynchronous and `deploy-status`'s `reason` is a
closed enum consumed elsewhere, so a cause reaching only layer 3 is an accepted, stated limit. Affected-surface
rule (blind execution surface, 2.9.2): `sdk_noproc` is emitted FROM the container, `kdeny` from the host, and one
event's fields (`sdk_noproc`, `sdk_probe`, `direct_probe`, `hostsec`, `kdeny`) discriminate H6, H7 and H8 together.

## Infrastructure (IaC)

No new infrastructure. `ci-deploy.sh` ships through the existing `terraform_data.deploy_pipeline_fix`.

### Terraform changes
None.

### Apply path
Existing: `apply-deploy-pipeline-fix.yml` on push to main (path-filtered on `ci-deploy.sh`), HTTPS via the Cloudflare
Tunnel to `/hooks/infra-config`, no SSH. Downtime: none (script swap between invocations). A merge delivers the
file to production, so it sits behind gate G1; a dispatch re-run is gate G2.

### Distinctness / drift safeguards
`scripts/check-deploy-script-parity.sh` is the drift check; Phase 6 step 1 uses it.

### Vendor-tier reality check
Not applicable (no vendor resource).

## Guard Contract

### Guard 1 - the new rows are inert to the rollback, bounded, classify honestly and cannot egress a path or a credential

**Property.** Reading the kernel stream, failing to read it, hanging or flooding either rung, or a container
printing a forged `kdeny`-shaped line cannot change the rollback line, the exit code, the state file, or the order
`DEPLOY_ROLLBACK`, bundle, `docker stop`, and `kernel kdeny done`; each rung is time- and size-bounded; a readable
stream that contains a denial is never reported as unreadable; and no path-valued or credential-shaped string
reaches journald through `kdeny` or `sdk_noproc`.

**Assembly.** Every path by which the new code can run, alter control flow or write a line: (1) `_canary_kdeny_read`
and its two external commands (`journalctl`, `dmesg`) plus its classifier and field extractor, (2) the `kdeny` emit
line, (3) the `sdk_noproc` line in `CANARY_DIAG_SCRIPT` and its allowlist entry in `emit_canary_sandbox_diag`,
(4) both existing call sites of `emit_canary_sandbox_diag` (legacy rollback arm, faithful `sandbox_broken`), (5) the
section order, (6) the sinks (the journald line and the deploy script's stdout, which the webhook re-logs). The
chokepoint for control flow is `emit_canary_sandbox_diag`; the chokepoint for the line is `_canary_diag_emit`. The
census quantifies over every `journalctl`/`dmesg` mention in the region, not the two known call lines, and the
section-order row asserts the whole ordered list (set identity), not a count.

**Mutation matrix.**

| # | Edit (must drive the suite RED) | Row that catches it |
|---|---|---|
| 1 | Delete the `kdeny` emit line (the guard's own dispatch) | D10a (row absent) and D1c (ordered section list) |
| 2 | Move the `kdeny` emit after `done` (REORDER, not delete) | D1c ordered list and D10a placement |
| 3 | Drop `timeout -k 1 3` from either rung and keep the hang mock | D10d (wall time and verdict) |
| 4 | Drop `head -c 65536`, or drop `-n 400`/`tail -n` so the OLDEST lines are kept | D10e (4 MB then a final denial must still count) |
| 5 | Broaden the `noaccess` test back to `denied\|permission` over the whole output | D10b (the realistic denial must read `j=ok`) |
| 6 | Add a `name` or `comm` key to the field allowlist, or emit the raw line | D10b (no name/comm/pid/timestamp in the fields) |
| 7 | Add a third rung (`audit.log`/`kern.log` read, unbounded) or `sudo` to a rung (second member after a compliant first) | D10g census |
| 8 | Bypass `_canary_diag_emit` with a direct `logger` call, or drop `_cred_err_tail` | D10g/D5c (single logger call) and D10f |
| 9 | Put `kdeny` or `sdk_noproc`-forgery into the wrong allowlist (add `kdeny` to the in-container regex) | D4g (forged `kdeny forged=1` must become `raw`) |
| 10 | Lengthen the status prefix or the fields cap so the 200-char tail eats `src=` | D10h boundary |
| 11 | Re-add `--proc /proc` to the `sdk_noproc` line (it would then duplicate `sdk_probe` and decide nothing) | D11 |

**Harness rows.** (a) Make the kernel mock record nothing: D10a's recorder assertion must go RED (no vacuous pass).
(b) Drive the census with a fixture region containing `sudo journalctl`: D10g's positive control must flag it.
Must-PASS inputs that are not the canonical: a denial line with an unknown extra key and a quoted value containing a
space must still produce a shaped row (the allowlist drops the extras instead of failing); a readable stream with
zero real lines plus a hint must read `noaccess` while a readable stream with real lines and no hint must read `ok`.

**Anchor.** The ordered section list in D1c is the stored value; it is compared by set identity AND order, so a
substitution that keeps the count (rename one section) fails. The floor 568 to N is paired with that identity and
raised in the SAME edit that adds the rows. A weakening would have to edit the #8016 Scenario/Guard blocks, which
Phase 4 asserts byte-identical in the diff. Fixtures are synthesized (cq-test-fixtures-synthesized-only) and
`_cred_err_tail` keeps its own pre-existing rows; this guard proves routing and the closed allowlist, not the
sanitiser's integrity.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Read the #9860 comment thread (gh issue view 9860 --comments) and knowledge-base/engineering/operations/runbooks/canary-probe-set.md (the H1-H5 table)." [brief] | Research Reconciliation, Hypotheses | mapped |
| 2 | "Add a bounded host-side read of the kernel denial line (audit/dmesg, with timeout and head -c, scrubbed via _cred_err_tail) as a new DIAG row in apps/web-platform/infra/ci-deploy.sh." [brief] | Design: `kdeny`; Phase 2 | mapped |
| 3 | "Add D-rows to ci-deploy.test.sh and raise CI_DEPLOY_ASSERT_FLOOR from 568." [brief] | Phase 1 rows D10-D11, floor | mapped |
| 4 | "Ship through the pipeline: review, QA, compound, ship, postmerge (the parent runs these; you only plan)." [brief] | Phase 5 | mapped |
| 5 | "After deploy, read the next real bundle with scripts/betterstack-query.sh and name the root cause. Then fix it, or open a separate issue if it is a different subsystem (post-deploy step; plan it as a documented follow-up phase, not part of this PR's code)." [brief] | Phase 6 | mapped |
| 6 | "The operator must give an explicit go-ahead before ANY production write ... The plan must mark that as an operator gate." [brief] | Phase 5 gate table G1-G4 | mapped |
| 7 | "Doppler reads only. Never print secret values." [brief] | Phase 5 G4, Phase 0 step 1, Phase 6 step 2 | mapped |
| 8 | "Use the Monitor tool for polling, never sleep." [brief] | Phase 6 step 2 | mapped |
| 9 | "Run Check 6 and the tests in an allocated sandbox per the repo's mutation-battery conventions." [brief] | Phase 0 step 2, Phase 4 (mutation rows and suites in an allocated sandbox); preflight Check 6 noted in Phase 5 | mapped (see Sharp Edges: the brief's "Check 6" is read as the Guard mutation battery plus preflight Check 6) |
| 10 | "Do not archive the plan/spec of the prior PR (moving the plan would break the discoverability baseline of 53)." [brief] | Research Insights, Phase 5 | mapped |
| 11 | "PR body must use `Ref #9860`, never `Closes`." [brief] | Acceptance Criteria | mapped |
| 12 | "Out of scope, separate follow-ups (do not start): the release tag/image provenance fix (#9886), flaky cron-egress-ghcr-probe.test.sh clock-boundary rows (untracked), wiring lint-shell-capture-exit and grep-q-pipe-guard into pre-commit for staged *.test.sh." [brief] | Non-Goals | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit `ci-deploy.sh` (`_canary_kdeny_read`, emit line) | "Add a bounded host-side read of the kernel denial line" | asked |
| Edit `ci-deploy.test.sh` (mocks, D10 rows, floor) | "Add D-rows to ci-deploy.test.sh and raise CI_DEPLOY_ASSERT_FLOOR from 568." | asked |
| Edit `canary-probe-set.md` (rows, H6-H8) | "(the H1-H5 table)" | inferred - justification: a new DIAG row that the runbook's decode table does not describe is undiscoverable; the runbook is the decode surface the #9860 comment points readers to |
| Edit `preflight-discoverability-test.test.ts` (53 to 54) | "Do not archive the plan/spec of the prior PR (moving the plan would break the discoverability baseline of 53)." | inferred - justification: this plan declares `credentials_required` (the Observability schema's optional field for a Better Stack probe), which moves a repo-global ratchet by one; the suite goes red otherwise |
| `sdk_noproc` in-container row | - | inferred - justification: the local repro and the repo's own learnings say the leading cause (masked `/proc`) writes no kernel line, so the asked `kdeny` row alone would likely name nothing and cost another production deploy cycle; the row is one line in an existing script, decided by the same event, and tests the shape of the candidate fix. Surfaced as a decision challenge |
| `kdeny` counts `hits`/`mproc`, closed-key fields, classifier on hint lines | "scrubbed via _cred_err_tail" | inferred - justification: a bare profile match would count the production container's unrelated denials as H7 evidence, and a broad classifier would report the readable denial stream as unreadable; the closed key set (no `name`/`comm`) keeps tenant file names out of Better Stack by construction |
| `create_mock_kernlog` (hermetic mocks) | "Add D-rows to ci-deploy.test.sh" | inferred - justification: the suite does not mock `journalctl`/`dmesg` today, so without mocks the new rows would run the runner's real binaries and be host-dependent |
| `SOLEUR-DEBT:` removal trigger on `kdeny` | - | inferred - justification: a one-incident diagnostic with no retirement trigger becomes permanent machinery (CTO review) |
| `tasks.md` | - | inferred - justification: the work phase derives its task list from it |
| `decision-challenges.md` | - | inferred - justification: the headless plan contract persists Taste/User-Challenge items there for ship to render |
| Phase 0 user-impact read; Phase 6 time-box, owner, availability-versus-isolation framing | "plan it as a documented follow-up phase, not part of this PR's code" | inferred - justification: the leading hypothesis means a user-facing incident may already exist; the read is GET-only and sets the urgency of everything else |

### Split Assessment

- Subsystems touched: 3 - apps/web-platform, knowledge-base, plugins/soleur
- Planned files: 4 edited + 2 created | Estimated changed lines: 230
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash apps/web-platform/infra/ci-deploy.test.sh` passes in the allocated sandbox with the raised floor (the measured count; expected 577), every assertion counted.
- [ ] The #8016 Scenario 1-4 and Guard 1/2 blocks, and the probe statement, `BWRAP_RC` capture, `DEPLOY_ROLLBACK` line and teardown order in `ci-deploy.sh`, are byte-identical in `git diff origin/main` (the diff only adds the two rows and updates the existing section-list rows and strings).
- [ ] Every row of the Guard Contract matrix was driven in the sandbox and went RED with the named killing assertion (recorded in the PR body); `python3 scripts/lint-guard-contract.py` on this plan passes.
- [ ] `python3 scripts/lint-shell-capture-exit.py`, `bash scripts/lint-orphan-test-suites.sh` and `cd plugins/soleur/test && bun test preflight-discoverability-test.test.ts` pass with `BASELINE_DECLARED_PROBES` at the re-measured count (54 expected).
- [ ] The runbook documents `sdk_noproc`, `kdeny`, H6-H8 and the sixteen-row / eleven-in-container bundle, with no SSH step (`hr-no-ssh-fallback-in-runbooks`).
- [ ] The Phase 0 user-impact read and the local repro result are recorded in the PR body.
- [ ] The plan and spec of PR #9884 are untouched (`git diff origin/main --name-status` shows no rename or delete under `knowledge-base/project/plans/` or `specs/`).
- [ ] PR body says `Ref #9860`, never `Closes`.

### Post-merge (automatable; each production-touching step sits behind its gate)

- [ ] Gate G1 granted explicitly before `gh pr merge`.
- [ ] `bash scripts/check-deploy-script-parity.sh --bs-only` reports parity for the merge's `ci-deploy.sh` (read-only); on drift the remedy is gate G2.
- [ ] After the next canary sandbox failure, `bash scripts/betterstack-query.sh --since 24h --grep SOLEUR_CANARY_SANDBOX_DIAG` returns a `section=kdeny` and a `section=sdk_noproc` row (credentials as declared above), and the Phase 6 table names the cause or states which datum is missing.
- [ ] Phase 6 outcome recorded on #9860 (the cause, the follow-up issue number, or the fix PR), and the issue left open until then.

## Non-Goals

- The release tag/image provenance fix (tracked: #9886).
- The flaky `cron-egress-ghcr-probe.test.sh` clock-boundary rows (untracked per the brief; file at ship if the operator wants it tracked).
- Wiring `lint-shell-capture-exit` and `grep-q-pipe-guard` into pre-commit for staged `*.test.sh` (untracked per the brief).
- Any change to the sandbox, the shim, the seccomp or AppArmor profile, the Dockerfile, the `docker run` flags, sudoers or the cloud-init `users` block. Those belong to the Phase 6 outcome and are separate PRs.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. This one is filled (aggregate pattern).
- The brief's "Check 6" is ambiguous. This plan runs the Guard mutation battery and the suite in an allocated sandbox and notes that preflight Check 6 (brand-survival, read-only) runs at ship; if the brief meant something else, reconcile before work starts.
- `diag_inert` asserts wall time `< 20 s`. Two 3 s rungs plus the existing bounded calls fit; do not raise the bound to make a slow mock pass.
- `CANARY_DIAG_SCRIPT` is a single-quoted shell variable: no single quote may appear in the new `sdk_noproc` line. D9 executes the real script under `sh` and `bash`, which is what catches a quoting slip. D9's extraction stops at the first line ending in `'`, so the closing quote must stay on the last script line.
- The existing census bans bare `env`, `export`, `declare`, `set` and `printenv` outside two literal names inside the region; the new function and its comments must not trip it (comments are exempt only on whole-line comments).
- `_cred_err_tail` keeps the LAST 200 characters. The `kdeny` prefix (61 characters worst case) plus the 130-byte fields cap is sized to fit; any longer prefix silently eats the discriminating head. D10h pins it.
- `journalctl -k` as an unprivileged user usually exits 0 with a hint and no lines; classify on the hint lines, never on bare words inside real kernel lines, and never use `grep -c` under `pipefail` for the counts.
- `head -c` closing the pipe makes `PIPESTATUS[0]` 141, which is truncation, not an error.
- Do not "fix" H6 in this PR by touching the proc mask or the docker flags: it is the cross-tenant control from #9723, and the fix needs CTO and CLO review.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - infrastructure/tooling change. (Engineering-only; no UI surface. GDPR gate
considered and not invoked: the rows carry kernel and namespace facts, and the one personal-data risk, a tenant
file name inside a denial line, is closed by construction: the closed key allowlist has no path-valued key, pinned
by D10b. No new persistent store or connection, so the Encryption Posture gate is skipped. No architectural
decision is made or changed, so no ADR or C4 deliverable: the marker follows the existing ADR-115 trusted-region
convention. The Phase 6 H6 fix WOULD be an architectural decision (container posture versus the cross-tenant `/proc`
mask) and is planned there with CTO and CLO review and an ADR-075 addendum, not here. CTO devex review of this plan
ran during plan-review and its findings are applied above.)

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing; production keeps serving and the rollback
  arm still tears down the canary and exits 1 exactly as today. The only regression possible is a slower or
  mis-ordered rollback if a new row misbehaves, which D10d/e and the existing D3 rows pin.
- **If this leaks, the user's workflow/data is exposed via:** the `kdeny` read of the host kernel stream, which can
  contain denial lines about the production container's tenant sandboxes and egresses to Better Stack unscrubbed by
  Vector. Mitigation by construction: a closed key allowlist with no `name`/`comm`/`pid` key, `_cred_err_tail`
  through the single emitter, and rows D10b/D10f.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** aggregate, not single-user: the change touches no user data path and
  cannot affect a user session; the exposure is bounded by construction and by test. The underlying #9860 bug is
  different: if the Phase 0 read shows agent sessions failing for real users, the follow-up issue is re-thresholded
  to `single-user incident` there.
