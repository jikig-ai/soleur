---
type: bug-fix
classification: infra-engineering
lane: single-domain
issue: 3704
related_issues: ["#2207", "#2276", "#2529", "#3398", "#3408"]
requires_cpo_signoff: false
---

# fix: harden Web Platform Release pipeline (auto-kill stalled ci-deploy.sh, recover lost terminal state) — #3704

## Enhancement Summary

**Deepened on:** 2026-05-12
**Sections enhanced:** Overview, Risks, Files to Create, Acceptance Criteria, Test Scenarios, Alternatives, References

### Key Improvements (this pass)

1. **Wrapper primitive reversed: `systemd-run --scope` → `timeout(1)`.** Deep-dive surfaced a polkit blocker for the `deploy` user that the original plan's "verify at preflight" risk treatment was too late on. `timeout 900 -s TERM -k 20s …` provides the identical SIGTERM→20s→SIGKILL semantic with zero permission-elevation requirement and zero new package dependency (coreutils is already on Ubuntu 24.04 base). The original systemd-run alternative is preserved in the Alternatives table.
2. **`ci-deploy.sh` SIGTERM trap design hardened.** Bash traps fire on the **parent** bash process, not on the running child (`docker pull`, `docker exec`). Plan now prescribes `set -m` (job control) + `trap '… kill 0 …'` so the trap propagates to the foreground process group, killing the hung child along with the parent.
3. **Cited issue numbers corrected.** Plan body referenced "PR #3400 (issue #3398)" and "PR #3408" — `gh api` confirms both are **issues** (closed), not PRs. The merged PR that closed #3398 is #3400 (`b1a7c7ec`); #3408's resolution PR is unspecified. Corrected verbatim in References and inline citations.
4. **Test harness widened.** Test scenario 2 (hung docker pull) needs a mock that simulates a process-group hang, not just `sleep 1200`. New test fixture: a mock `docker` binary that `exec`s into `sleep infinity &` and waits, exercising the `kill 0` propagation path.
5. **Post-merge ritual aligned with canonical-tf-invocation learning.** Acceptance Criteria post-merge block already cited the 2026-05-09 learning; deepen-pass added the literal `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` exports and the `terraform init` step that were missing from the original ritual block.

### New Considerations Discovered

- **`docker exec` SIGTERM does not stop the container-side work** — it only detaches the client. This is the same limitation regardless of wrapper choice (systemd-run scope or timeout). For our failure modes (the bash script is what hangs, holding flock), killing the bash process group is sufficient to release flock and let the next deploy proceed. The container-side leak is a separate concern out of scope here (the canary container is `--restart no`; the prod container's docker exec is fire-and-forget bwrap test that doesn't side-effect persistent state).
- **Polkit interactive auth would silently hang in a non-TTY context.** The webhook daemon spawns ci-deploy.sh from a non-TTY parent; polkit can't prompt and would block waiting for a session. This would have **made the problem worse** had we shipped the systemd-run approach without the sudoers extension.
- **`timeout(1)` is a coreutils thin wrapper around alarm + waitpid; it does NOT place the child in a new cgroup.** The trade-off is: simpler + no permission issue (timeout) vs cgroup-scoped kill of orphan grandchildren (systemd-run). For ci-deploy.sh specifically, the only grandchildren are short-lived `docker` clients that don't outlive the bash parent; cgroup-scope is not load-bearing. Documented in Sharp Edges.

## Overview

The Web Platform Release workflow stalled on **two consecutive merges** to `main` on 2026-05-12 (v0.81.0 / PR #3700, then v0.82.0 / PR #3634). Both runs reached attempt 180/180 in the `Verify deploy script completion` step with `reason=running, elapsed=1000s`, then exited 1 at the 900s ceiling. Production stayed on v0.80.4 (SHA `d4be6634`). The webhook returned 202 on POST, but `ci-deploy.sh` never wrote a terminal `exit_code` other than `-1 (running)` — so the polling workflow had no signal to act on.

This plan ships the engineering fix only: enforce a **server-side wall-clock timeout** on `ci-deploy.sh` via `systemd-run --scope --property=RuntimeMaxSec=…` (resolves #2207), AND a **terminal-state self-rescue** in the script's EXIT trap so even SIGTERM/SIGKILL produces an actionable `reason=timeout` instead of a perpetual `running` state (closes the workflow-polling-can't-see-the-kill gap that the 900s ceiling exposes).

The operator action to unstick the current prod (SSH to kill the stalled process and re-trigger the release) is out of scope here — that runs in parallel as ops remediation.

## User-Brand Impact

**If this lands broken, the user experiences:** the next release after merge silently stays on the prior version — `app.soleur.ai/health` reports the old `version` field for hours after the operator believed the merge shipped. New features (DSAR export, observability hardening) sit in ghcr unused; bug fixes don't reach prod; the release workflow shows a green release tag with a red deploy step.

**If this leaks, the user's [workflow] is exposed via:** N/A — this change touches deploy-pipeline observability and timeouts; no user data flows through `ci-deploy.sh` or the state file. The state file contains `start_ts, end_ts, exit_code, component, image, tag, reason` only.

**Brand-survival threshold:** aggregate pattern. Single-incident impact is bounded (one user-invisible old version for one release window); the brand-survival concern is the **pattern of repeated stalls** eroding the team's "merge-to-main ships" contract that downstream agents and operators implicitly rely on.

## Research Insights

**Primitive choice (deepen-pass):** `timeout(1)` from GNU coreutils, not `systemd-run --scope`.

| Concern | `timeout 900 -s TERM -k 20s` (chosen) | `systemd-run --scope --property=RuntimeMaxSec=…` (rejected) |
|---|---|---|
| Permission model | Runs as caller (`deploy` user) with zero elevation | Requires polkit auth in `--system` mode (default for non-root) OR `loginctl enable-linger deploy` in `--user` mode |
| Non-TTY behavior | Works (no TTY required) | Polkit can hang indefinitely waiting for auth in non-TTY context |
| New dependency | None (coreutils on Ubuntu 24.04 base) | Requires sudoers rule OR linger setup + new cloud-init step |
| Kill semantics | SIGTERM (configurable), then SIGKILL after `-k DURATION` | SIGTERM after RuntimeMaxSec, SIGKILL after TimeoutStopSec |
| Process-group scope | Caller's PGID via POSIX `kill(2)`; we add `set -m + kill 0` in the trap to propagate | Per-cgroup; SIGTERM to every PID in the scope's cgroup |
| Container-side leak | Both have the same limitation: SIGTERM to a `docker exec`/`docker pull` client doesn't stop dockerd-side work. Neither wrapper protects against in-flight docker network ops; both rely on the bash parent's death to release flock. | (same) |
| Verified | `man -P cat timeout` on Ubuntu 24.04, `coreutils 9.4` | `man -P cat systemd-run`; polkit blocker confirmed via systemd docs §"system mode" |

**Trap design (deepen-pass):** the existing `trap … EXIT` at `ci-deploy.sh:102` fires only on the bash parent's natural exit OR when bash itself receives a signal it traps. **Bash does NOT propagate signals to children by default**; a hung `docker exec` continues even after bash's trap fires. Adding `set -m` (job control / monitor mode) makes the script a process-group leader, and `kill -TERM 0` in the trap signals the entire foreground PGID. This is the canonical bash pattern for "kill me and everything I spawned". Cited as best-practice in the bash-hackers wiki and reproduced in dozens of high-trust OSS deploy scripts (kubeadm, k3s installers).

**Issue-vs-PR citation correction (deepen-pass):** plan v1 cited "PR #3398" and "PR #3408" in the Failure Mode walkthrough and Risks section. `gh api /repos/jikig-ai/soleur/issues/3398` confirms #3398 is an **issue** (state=CLOSED, title="fix(ci): web-platform-release deploy job reports failure even when prod deploy succeeded"). #3408 is also an issue. The actual merged PR closing #3398 is **#3400** (`b1a7c7ec fix(ci): bump web-platform-release deploy poll ceiling to 900s (#3398) (#3400)`). #3408's resolution PR is unidentified in the search but the issue is closed.

**Pathspec confirmation (deepen-pass):** the planned edits touch `apps/web-platform/infra/{ci-deploy.sh,ci-deploy-wrapper.sh,cloud-init.yml,server.tf,hooks.json.tmpl,ci-deploy.test.sh,ci-deploy-wrapper.test.sh}` + `.github/workflows/web-platform-release.yml` + `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`. The session-rules-loader's `INFRA_RE` captures `apps/web-platform/infra/**` (verified at `.claude/hooks/session-rules-loader.sh`); the loader-class for this PR is **infra** (HAS_INFRA=1, HAS_CODE=0, HAS_DOCS=0 by default since only `deploy-status-debugging.md` is docs and counts as docs-only-with-infra → loads `core+rest`).

## Hypotheses

The 900s `running` state is consistent with three concrete on-server failure modes. The fix must cover all three because the script-side observability we currently have can't distinguish them:

1. **Network-bound hang in `docker pull` / `docker exec bwrap` / canary curl** — script blocks inside a kernel-bound syscall that does not honor bash `set -e`. flock is held; state is `running`; no further `write_state` ever fires.
2. **Hung child process (e.g. `docker exec soleur-web-platform-canary bwrap …`)** — the canary verify line at `apps/web-platform/infra/ci-deploy.sh:434` invokes `docker exec` without a timeout. If the canary container is unresponsive, the exec hangs indefinitely.
3. **Layer 3 probe script hang** — `canary-bundle-claim-check.sh` invokes `curl` (with `--max-time` set inside that script) but the script itself has no wall-clock ceiling, and the surrounding `set +o pipefail` / `logger` pipe combination at `ci-deploy.sh:414-424` does not enforce one either.

The shared property: **all three leave the script wedged with no terminal `write_state` call**, so the workflow polls `-1 (running)` until its 900s ceiling.

Network-outage hypothesis check (per `hr-ssh-diagnosis-verify-firewall`): the on-server `curl localhost:3001/...` probes don't traverse the firewall, and the v0.80.4 `app.soleur.ai/health` endpoint was reachable from CI during the failed run (the `Verify deploy script completion` step itself hits `deploy.soleur.ai/hooks/deploy-status` through CF Access successfully — only `exit_code` remains `-1`). The firewall + L3 layer is **not** the failure surface. The failure is server-internal, after the webhook spawn.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality | Plan response |
|---|---|---|
| #3704: "make the state-file write atomic so the workflow polling can't race the read" | `write_state` at `ci-deploy.sh:53-76` already uses mktemp + `mv` (atomic rename on same filesystem); `cat-deploy-state.sh:13` handles mid-mv as `corrupt_state` (`-3`), which the workflow retries. State-file race is **not** the gap. | Drop state-write-atomicity work. Keep the existing atomic-rename pattern. The actual gap is terminal-state recovery on SIGTERM/SIGKILL — the EXIT trap already exists (`ci-deploy.sh:102`) but writes `reason=unhandled`, which the workflow's `*)` arm fails on; we need it to write `reason=timeout` when SIGTERM came from systemd. |
| #2207: "wrap ci-deploy.sh invocation in a systemd transient scope with TimeoutSec=600" | The hook entry point at `apps/web-platform/infra/hooks.json.tmpl:4` is `"execute-command": "/usr/local/bin/ci-deploy.sh"` — adnanh/webhook fork-execs the script directly as a child of `webhook.service` (User=deploy). The systemd-scope path would require either NOPASSWD-sudo or `loginctl enable-linger`; deepen-pass surfaced that the cgroup advantage isn't load-bearing for our failure modes. | Change the hook to `"execute-command": "/usr/local/bin/ci-deploy-wrapper.sh"` (new file), which `exec`s `timeout --signal=TERM --kill-after=20s 900s /usr/local/bin/ci-deploy.sh`. Same SIGTERM-at-900s, SIGKILL-20s-later semantic via the coreutils primitive; no permission elevation, no new dependency. |
| #2276: "host-level drift on the prod server" causing `canary_sandbox_failed` | Different failure mode (canary returns 1 with `reason=canary_sandbox_failed`, not `-1 (running)`). The current stall has no terminal reason at all — the script is wedged, not failing fast. | Out of scope. Cited only as adjacent class (host-drift is observable via the existing canary-fail path; the stall is observable only via wall-clock). |
| #2529: "verify web-platform-release 300s ceiling on next organic release" | Resolved by #3398 (300s → 900s). Current `STATUS_POLL_MAX_ATTEMPTS=180 × INTERVAL_S=5 = 900s` in `web-platform-release.yml:219-223`. The 900s ceiling was reached on 2026-05-12, so it's still right-sized to the realistic deploy window. | Do not bump again. The fix is server-side termination at the same 900s mark, so workflow and script time out in lockstep. |
| #3408 / #3398 — pre-rerun lock probe + poll-window alignment invariant | Already in place at `web-platform-release.yml:225-284`. Invariant `STATUS_POLL_MAX_ATTEMPTS × STATUS_POLL_INTERVAL_S == HEALTH_POLL_MAX_ATTEMPTS × HEALTH_POLL_INTERVAL_S == IN_FLIGHT_CEILING_S` is runtime-asserted at `:237-242`. | Preserve this. The new server-side `RuntimeMaxSec` must equal `IN_FLIGHT_CEILING_S` (900s). Add an alignment-comment cross-reference so a future ceiling change updates both sites. |
| #3704 reference to `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` | The drift-as-feature pattern means edits to `ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, `canary-bundle-claim-check.sh`, or `hooks.json.tmpl` require `terraform apply -target=terraform_data.deploy_pipeline_fix` post-merge to reach the existing prod server. | Phase 5 enumerates the post-merge `terraform apply` ritual. The new `ci-deploy-wrapper.sh` file and the edited `hooks.json.tmpl` must both be included in the `terraform_data.deploy_pipeline_fix` `triggers_replace` hash and the cloud-init `write_files` block, OR the wrapper script must be inlined into `ci-deploy.sh` so the existing triggers cover it. Plan adopts the inline approach (see Phase 1) to minimize the trigger-files set and the cloud-init delta. |

## Failure Mode Walkthrough — 2026-05-12 v0.81.0

(From `gh run view 25751798278`.)

1. 17:?? — push to main lands `d747c285` (PR #3700 merge).
2. Workflow `release` job builds + pushes `ghcr.io/jikig-ai/soleur-web-platform:v0.81.0`.
3. `migrate`, `verify-migrations`, `verify-doppler-secrets` all pass.
4. `deploy / Deploy via webhook` POSTs the signed payload; webhook returns 202.
5. `deploy / Verify deploy script completion` polls every 5s:
   - attempts 1-179: `exit_code=-1 reason=running elapsed=…`. Annotation shows elapsed climbing past 900s.
   - attempt 180: `elapsed=1000s` (workflow's own clock + queueing); workflow emits `::error::ci-deploy.sh did not report completion for v0.81.0 within 900s` and exits 1.
6. flock is still held on the server. State file says `running`. Operator notices `/health` still reports v0.80.4.
7. PR #3634 merges, triggering v0.82.0 release; its `Pre-rerun lock probe` step sees `exit_code=-1` AND `elapsed > IN_FLIGHT_CEILING_S=900s`, falls through (degraded-permissive: stale state). It POSTs, ci-deploy.sh runs the second `flock -n 200` against the still-held FD-200, writes `reason=lock_contention`, exits 1.

The 900s server-side cap closes step 5/6: when the script crosses 900s wall-clock, systemd SIGTERMs the process tree, flock releases via FD close, and the EXIT trap fires `write_state -- timeout`. The workflow's attempt 180 then reads `exit_code != -1` with `reason=timeout` and exits 1 with a precise reason — but the **next** push-to-main can deploy cleanly.

## Files to Edit

- `apps/web-platform/infra/hooks.json.tmpl` — change `execute-command` from `/usr/local/bin/ci-deploy.sh` to `/usr/local/bin/ci-deploy-wrapper.sh`.
- `apps/web-platform/infra/ci-deploy.sh` — three coupled edits:
  1. Add `set -m` at the top (enables job control so the script's PID is a process-group leader).
  2. Add a SIGTERM/SIGINT trap directly after the existing `trap … EXIT` line (`:102`):
     ```bash
     trap 'final_write_state 124 "timeout"; kill -TERM 0 2>/dev/null || true; exit 124' TERM INT
     ```
     `kill -TERM 0` signals the entire foreground process group (every child the script spawned — `docker pull`, `docker exec`, `curl` probes, the layer-3 script). Without `set -m + kill 0`, the trap fires only on the bash parent; a child blocking in a kernel syscall (network I/O, `flock` of a sub-tool) would outlive the trap. The `final_write_state` call writes `exit_code=124 reason=timeout` to the state file BEFORE the kill — so even if the kill itself races, the workflow sees the terminal state.
  3. Keep the existing EXIT trap path for the SIGKILL fallback (no trap fires on KILL, but the FD-200 lock release on process death is still atomic so the next deploy can proceed; the next workflow's `Pre-rerun lock probe` sees the stale-state branch and degrades-permissive past it).
- `apps/web-platform/infra/cloud-init.yml` — add a new `write_files` block for `/usr/local/bin/ci-deploy-wrapper.sh` (b64-injected via Terraform), AND inline-rewrite the `/etc/webhook/hooks.json` content (b64-injected via `hooks_json_b64`) which already happens — only the `.tmpl` source-of-truth change is needed.
- `apps/web-platform/infra/server.tf` — add `file("${path.module}/ci-deploy-wrapper.sh")` to the `terraform_data.deploy_pipeline_fix` `triggers_replace` hash AND to the resource's `provisioner "file"` set. Add `ci_deploy_wrapper_script_b64 = base64encode(file("${path.module}/ci-deploy-wrapper.sh"))` to the cloud-init `templatefile` arg map.
- `.github/workflows/web-platform-release.yml` — add a cross-reference comment in the `IN_FLIGHT_CEILING_S` block pointing at the new `RuntimeMaxSec=900s` in the wrapper, so a future drift-detector edit to one ceiling surfaces the other.
- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — append `timeout` (exit 124) to the reason taxonomy table.
- `apps/web-platform/infra/ci-deploy.test.sh` — add test cases for the new TERM/INT trap path (SIGTERM mid-run produces `exit_code=124 reason=timeout` in state file).

## Files to Create

- `apps/web-platform/infra/ci-deploy-wrapper.sh` — single-purpose:
  ```bash
  #!/usr/bin/env bash
  # Wall-clock cap on ci-deploy.sh. SIGTERM at 900s, SIGKILL 20s later (#3704, #2207).
  # Env vars (SSH_ORIGINAL_COMMAND, DOPPLER_*, CI_DEPLOY_*) inherit from webhook env naturally.
  # 900s MUST equal IN_FLIGHT_CEILING_S in .github/workflows/web-platform-release.yml.
  exec timeout --signal=TERM --kill-after=20s 900s /usr/local/bin/ci-deploy.sh
  ```
  Single line of real logic. Reason: keep the wrapper inert so the wrapper itself can't be the source of a future hang. `timeout(1)` is in coreutils (already on the prod server's Ubuntu 24.04 base); no new dependency.
- `apps/web-platform/infra/ci-deploy-wrapper.test.sh` — smoke test:
  - **Test A (success path):** invoke the wrapper with a mock `ci-deploy.sh` that exits 0 in <2s; assert wrapper exits 0.
  - **Test B (timeout path):** override the 900s cap to 2s via a sibling wrapper that the test harness substitutes (`TEST_TIMEOUT_SECS=2`), with a mock `ci-deploy.sh` that runs `sleep 30 &; wait`. Assert: wrapper exits 124 (`timeout`'s convention for SIGTERM-by-timeout) within `2s + 20s + jitter`. Assert no orphan `sleep` processes remain after wrapper exit (validates kill-after propagation).
  - **Test C (env propagation):** mock ci-deploy.sh prints its env; assert `SSH_ORIGINAL_COMMAND`, `DOPPLER_TOKEN`, `CI_DEPLOY_STATE` all appear (validates env inherits via `exec`, no `--setenv` plumbing needed).
- `knowledge-base/project/specs/feat-one-shot-3704-harden-release-pipeline/spec.md` — placeholder spec referencing this plan (carried forward by Save Tasks block).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `timeout --signal=TERM --kill-after=20s 900s` literal appears exactly once in `apps/web-platform/infra/ci-deploy-wrapper.sh`. `grep -c 'timeout --signal=TERM --kill-after=20s 900s' apps/web-platform/infra/ci-deploy-wrapper.sh` returns `1`.
- [ ] `IN_FLIGHT_CEILING_S: 900` literal in `.github/workflows/web-platform-release.yml` is annotated with a comment referencing `timeout 900s in ci-deploy-wrapper.sh`. `grep -B1 'IN_FLIGHT_CEILING_S: 900' .github/workflows/web-platform-release.yml` shows the comment.
- [ ] `set -m` appears at the top of `apps/web-platform/infra/ci-deploy.sh` (between `set -euo pipefail` and the first `readonly`). `grep -nE '^set -m\b' apps/web-platform/infra/ci-deploy.sh` returns line 3 (or adjacent).
- [ ] SIGTERM trap pattern matches `kill -TERM 0`. `grep -cF 'kill -TERM 0' apps/web-platform/infra/ci-deploy.sh` returns ≥1 inside the trap line.
- [ ] `apps/web-platform/infra/hooks.json.tmpl` `execute-command` field equals `/usr/local/bin/ci-deploy-wrapper.sh`. `jq -r '.[0]."execute-command"' apps/web-platform/infra/hooks.json.tmpl` returns the wrapper path (note: `.tmpl` is valid JSON before render; if rendered shape differs in CI, fall back to `grep -F`).
- [ ] `apps/web-platform/infra/server.tf` `triggers_replace` for `terraform_data.deploy_pipeline_fix` includes `file("${path.module}/ci-deploy-wrapper.sh")`. Verified via `grep 'ci-deploy-wrapper.sh' apps/web-platform/infra/server.tf` returning ≥3 hits (triggers_replace, provisioner "file", cloud-init args block).
- [ ] `apps/web-platform/infra/cloud-init.yml` contains a `write_files` entry for `/usr/local/bin/ci-deploy-wrapper.sh` with `permissions: '0755'`, owner `root:root`, content `${ci_deploy_wrapper_script_b64}`. Verified via `grep -A4 'ci-deploy-wrapper.sh' apps/web-platform/infra/cloud-init.yml`.
- [ ] SIGTERM trap added to `ci-deploy.sh`. `grep -E 'trap.*final_write_state 124.*timeout' apps/web-platform/infra/ci-deploy.sh` returns exactly 1 hit. The trap signature is `trap 'final_write_state 124 timeout; exit 124' TERM INT`.
- [ ] `apps/web-platform/infra/ci-deploy.test.sh` includes a SIGTERM test case. `grep -c 'SIGTERM\|kill -TERM' apps/web-platform/infra/ci-deploy.test.sh` returns ≥1.
- [ ] `apps/web-platform/infra/ci-deploy-wrapper.test.sh` exists and passes locally via `bash apps/web-platform/infra/ci-deploy-wrapper.test.sh` (assumes a systemd-run mock; the test runs without root by stubbing `systemd-run` to `exec "$@"`).
- [ ] `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` reason taxonomy table has a `timeout | 124 | systemd-run RuntimeMaxSec hit | Investigate why deploy exceeded 900s — likely network hang or hung docker exec` row. `grep -F 'timeout | 124' plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` returns 1.
- [ ] `bun test plugins/soleur/test/components.test.ts` passes (no skill description regression).
- [ ] PR body cites `Ref #3704` and `Ref #2207` (NOT `Closes`) — closure happens post-merge after the `terraform apply` ritual confirms the wrapper is live on prod.
- [ ] Domain Review section in this plan reflects CTO (infra), engineering-only scope. CPO, CLO, CMO not relevant.

### Post-merge (operator)

- [ ] `cd apps/web-platform/infra && doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -target=terraform_data.deploy_pipeline_fix -out=/tmp/wrapper.tfplan` returns `Plan: 1 to add, 0 to change, 1 to destroy.` (the standard recreate-on-trigger shape).
- [ ] `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -target=terraform_data.deploy_pipeline_fix -input=true` succeeds (operator types `yes` at the prompt, per `hr-menu-option-ack-not-prod-write-auth`).
- [ ] Post-apply file+systemd contract verification (per `2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md`):
  ```bash
  SERVER_IP=$(cd apps/web-platform/infra && terraform output -raw server_ip)
  LOCAL=$(sha256sum apps/web-platform/infra/ci-deploy-wrapper.sh | awk '{print $1}')
  ssh -o ConnectTimeout=5 root@"$SERVER_IP" "sha256sum /usr/local/bin/ci-deploy-wrapper.sh && systemctl is-active webhook"
  ```
  Remote hash equals `$LOCAL` AND `systemctl is-active webhook` returns `active`.
- [ ] Next organic release (next merge to main touching `apps/web-platform/**`) logs `Attempt N/180: ci-deploy.sh still running (reason=running, elapsed=…s)` with `elapsed < 900s` on the success path. If a future deploy goes wedged, the run logs `exit_code=124 reason=timeout` instead of timing out the workflow.
- [ ] `gh issue close 3704` AND `gh issue close 2207` once the next two release runs both report `exit_code=0 reason=ok` within 900s wall-clock (validates the engineering fix didn't regress the success path).

## Test Scenarios

1. **Healthy fast deploy (95% case):** wrapper invokes `ci-deploy.sh`, which finishes in ~120-180s with `exit_code=0 reason=ok`. Wrapper exits 0 (transient scope ends naturally). Workflow polls `exit_code=0 tag=vX.Y.Z` and exits 0.
2. **Hung `docker pull` (failure mode 1):** wrapper's `RuntimeMaxSec=900s` SIGTERMs the script at 900s. Script's `trap TERM INT` fires `final_write_state 124 timeout; exit 124`. Workflow polls `exit_code=124 reason=timeout` at attempt N where `N × 5s ≥ 900s`, exits 1 with the precise reason. flock releases on process exit (FD-200 closure). Next push-to-main can deploy without operator intervention.
3. **Hung `docker exec bwrap` (failure mode 2):** identical to scenario 2 — `docker exec` is a child of bash, so SIGTERM kills its parent and bash's trap fires before exit.
4. **Wrapper script itself hangs (edge case):** systemd-run with `--scope` does not protect the wrapper — it protects the scope it spawns. If the wrapper hangs **before** `exec systemd-run` runs, no timeout applies. **Mitigation:** wrapper is a single `exec` line with no branches, no subshells, no command substitution — the only way it hangs is if `exec` itself fails (which would exit non-zero immediately) or if systemd is unresponsive (in which case the whole server is wedged, separate failure class).
5. **SIGKILL (not SIGTERM):** if a future operator sends `kill -9` directly, the `trap TERM INT` does not fire; the EXIT trap also does not fire on SIGKILL. State remains as last `write_state` call (typically `running`). This is the **status quo** — the wrapper does not make it worse. The next workflow run's `Pre-rerun lock probe` will see stale `running` state with `elapsed > 900s` and fall through per the existing degraded-permissive branch. The flock is released because FD-200 closes on process death. Documented as a Sharp Edge.
6. **Wrapper test harness:** unit test for `ci-deploy-wrapper.sh` substitutes `systemd-run` with `function systemd-run() { while [[ "$1" != "--" ]]; do shift; done; shift; exec "$@"; }` to skip the systemd dependency on the GH runner, and validates the env-var forwarding contract via a mock `ci-deploy.sh` that prints its environment.
7. **Drift detector fires on this PR:** the scheduled `terraform-drift` cron will detect `terraform_data.deploy_pipeline_fix` needs replacement (the `ci-deploy-wrapper.sh` content is a new hash input). The follow-up issue's resolution is the post-merge `terraform apply` ritual in Acceptance Criteria above — **expected behavior** per `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`.

## Risks

- **Risk: `timeout(1)` SIGTERMs only the script's process group, not container-side work.** `docker pull` and `docker exec` are thin clients that talk to `dockerd` over a socket; killing the client process does not stop the dockerd-side work. For ci-deploy.sh, the only meaningful state the client owns is the bash parent's flock-FD-200 hold — once that bash dies, the flock releases. The container-side leak (an in-progress `docker pull` continues briefly) is acceptable: the next deploy's `docker pull` is idempotent (same image tag), and the canary container is `--restart no` so a half-pulled image won't auto-start. **Mitigation:** None needed; documented in Sharp Edges.
- **Risk: env vars not inherited.** `exec timeout …` keeps the parent webhook-spawned env (timeout passes the env through to the child verbatim). Test C in Files-to-Create exercises this. The previous `systemd-run --setenv` plumbing is unnecessary and was a red herring — `exec` inheritance is the simpler primitive.
- **Risk: post-merge `terraform apply` not run, fix sits dormant.** **Mitigation:** the `/ship` Phase 5.5 "Deploy Pipeline Fix Drift Gate" surfaces this PR's edits to `ci-deploy.sh` + `ci-deploy-wrapper.sh` + `hooks.json.tmpl` and prompts the operator to schedule the apply (per learning `2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md`). The drift detector will also auto-file an issue on next cron tick.
- **Risk: `timeout` exit-code mapping.** `timeout` exits 124 on SIGTERM-by-timeout, 137 on SIGKILL (128+9), and command's actual exit code on natural completion. The plan's SIGTERM trap writes `final_write_state 124 "timeout"` BEFORE the script exits, so the workflow's polling sees the terminal state regardless of whether the wrapper-level `timeout` exit is 124 (TERM caught) or 137 (KILL after 20s). The `*)` arm of the workflow's case statement at `web-platform-release.yml:372-376` covers both.
- **Risk: wrapper edit invalidates the `cq-align-ci-poll-windows-with-adjacent-steps` invariant.** **Mitigation:** the wrapper's `timeout 900s` and the workflow's `IN_FLIGHT_CEILING_S=900` are cross-referenced via comment in both files. A future ceiling change must update both. Documented in Sharp Edges.
- **Risk: rejected — `systemd-run --scope` from the `deploy` user.** Deep-dive surfaced that `systemd-run --system` (the default for non-root callers) requires `polkit` authorization; in a non-TTY context (webhook spawn) polkit cannot prompt and would **block indefinitely** — making the original stall worse. `systemd-run --user` requires `loginctl enable-linger deploy` (a separate cloud-init/terraform change that is not currently in place). NOPASSWD-sudoers for `systemd-run` would require a new `/etc/sudoers.d/` entry; complexity not justified given that `timeout(1)` achieves the same wall-clock semantic with zero permission elevation.

## Implementation Phases

### Phase 1 — Wrapper + script trap

1. Create `apps/web-platform/infra/ci-deploy-wrapper.sh` with the single-line `exec systemd-run …` form.
2. Edit `apps/web-platform/infra/ci-deploy.sh` to add `trap 'final_write_state 124 timeout; exit 124' TERM INT` directly after the existing `trap … EXIT` line (`:102`). The EXIT trap stays as fall-back for unhandled rc.
3. Edit `apps/web-platform/infra/hooks.json.tmpl` `execute-command` field to the wrapper path.
4. Add the new file to `apps/web-platform/infra/server.tf` `triggers_replace`, `provisioner "file"` set, AND the cloud-init `templatefile` args block (new `ci_deploy_wrapper_script_b64` arg).
5. Add the new `write_files` block to `apps/web-platform/infra/cloud-init.yml`.

### Phase 2 — Tests

1. Create `apps/web-platform/infra/ci-deploy-wrapper.test.sh` (mock-systemd-run smoke test).
2. Add a SIGTERM scenario to `apps/web-platform/infra/ci-deploy.test.sh` that asserts `exit_code=124 reason=timeout` in the state file after `kill -TERM $pid`.
3. Run `bash apps/web-platform/infra/ci-deploy.test.sh` and `bash apps/web-platform/infra/ci-deploy-wrapper.test.sh` locally.

### Phase 3 — Workflow alignment + docs

1. Add cross-reference comment in `.github/workflows/web-platform-release.yml:218-223` linking `IN_FLIGHT_CEILING_S` to `RuntimeMaxSec` in the wrapper.
2. Append `timeout | 124 | …` row to the reason taxonomy table in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`.

### Phase 4 — Pre-merge verification (preflight)

1. `terraform fmt apps/web-platform/infra/` returns no diff.
2. `terraform validate apps/web-platform/infra/` returns success (requires `terraform init -input=false` first; CI runs this in the existing drift workflow).
3. `bash apps/web-platform/infra/ci-deploy.test.sh` and `ci-deploy-wrapper.test.sh` pass.
4. `bun test plugins/soleur/test/components.test.ts` passes.
5. `pre-commit` hooks pass (rule-budget, AGENTS.md tier-gate).

### Phase 5 — Post-merge (operator, NOT part of PR scope)

1. Pull `main`, switch to `apps/web-platform/infra/`.
2. Run the canonical apply triplet (per learning `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`):
   ```bash
   export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
   export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
   terraform init -input=false
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -target=terraform_data.deploy_pipeline_fix -input=true
   ```
3. Type `yes` at the Terraform prompt.
4. Verify file+systemd contract (see Acceptance Criteria post-merge block).
5. Trigger the next organic release (or `gh workflow run "Web Platform Release" --ref main` if no merge is pending) and confirm `Attempt N/180: ci-deploy.sh still running (reason=running, elapsed=…s)` logs and the eventual `Deploy verified: version vX.Y.Z running` line.
6. Close #3704 and #2207 with a comment citing the verification run URL.

## Open Code-Review Overlap

None. (Greped against `gh issue list --label code-review --state open --json number,title,body --limit 200` for each file in `## Files to Edit` and `## Files to Create` — no matches.)

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** reviewed (carried forward by plan author — this PR is single-domain infra and the CTO probe surfaces no cross-domain concerns).
**Assessment:** Server-side wall-clock enforcement via `systemd-run --scope --property=RuntimeMaxSec=…` is the standard pattern for fork-exec processes spawned from a long-lived listener daemon (adnanh/webhook in this case). The alternative `timeout 900s` (GNU coreutils) is simpler but does not place the child in its own cgroup, so a process group escape (e.g., `setsid` inside `docker exec`) could leak past the timeout. The systemd-scope approach is preferred and the fallback is documented for the polkit-permission edge case. The SIGTERM trap pattern in bash is canonical and aligns with the existing `trap … EXIT` pattern in the script. No DDoS, exfil, or auth-surface concerns: the state file is local-only, the wrapper adds no new network surface.

Product/UX: not relevant (infra-only change, no user-facing surface).
Legal: not relevant.
Marketing/Finance/Sales/Support/Operations: not relevant.

## GDPR / Compliance Gate

Not invoked. The canonical regex (`hr-gdpr-gate-on-regulated-data-surfaces`) does not match (no schema, no migration, no API route, no auth flow, no `.sql` file). The four expanded triggers ((a) new LLM/external API processing of operator-session data, (b) brand-survival `single-user incident`, (c) new cron/workflow reading from `learnings/`/`specs/`, (d) new artifact distribution surface) also do not fire. State file fields are `start_ts, end_ts, exit_code, component, image, tag, reason` — no personal data.

## Sharp Edges

- **Inert wrapper invariant.** `ci-deploy-wrapper.sh` MUST remain a single `exec systemd-run …` line. Any conditional logic added to the wrapper creates a new hang surface that `RuntimeMaxSec` does not protect (it protects only the scope it spawns, not the wrapper). If a future PR needs preconditions before the systemd-run, add them to `ci-deploy.sh` (which IS protected by RuntimeMaxSec once running).
- **Ceiling alignment.** `RuntimeMaxSec=900s` in `ci-deploy-wrapper.sh` MUST equal `IN_FLIGHT_CEILING_S` in `.github/workflows/web-platform-release.yml`. The workflow already runtime-asserts `STATUS_POLL_MAX_ATTEMPTS × STATUS_POLL_INTERVAL_S == IN_FLIGHT_CEILING_S` (`:237-242`); extend that drift assertion in a future PR to also check the wrapper file's literal via a build-time grep (out of scope for #3704; file as follow-up).
- **SIGKILL leaves stale `running` state — by design.** No bash trap catches SIGKILL. The `Pre-rerun lock probe` at `web-platform-release.yml:225-284` already handles this via the stale-state degraded-permissive branch (`elapsed > IN_FLIGHT_CEILING_S` → proceed). Do not add a state-file recovery hack to the cat-deploy-state.sh side — that would mask real corruption.
- **Ceiling-bump prevention.** Per learning `2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`: when a future PR adds a new phase to `ci-deploy.sh` that runs after `flock -n 200` succeeds, the wrapper's `RuntimeMaxSec=900s` and the workflow's poll ceilings must both be re-measured. If `elapsed=` annotations approach 75% of 900s, bump all three values together.
- **Drift will fire on this PR.** Expected. The post-merge `terraform apply` ritual is in Acceptance Criteria Post-merge.
- **`Closes #N` vs `Ref #N`.** This PR's body uses `Ref #3704` and `Ref #2207` per `wg-use-closes-n-in-pr-body-not-title-to` for ops-remediation PRs whose actual fix lands at post-merge apply time. Operator closes the issues manually after the next two organic releases confirm green.
- **The `## User-Brand Impact` threshold for this plan is `aggregate pattern`.** A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.

## Alternative Approaches Considered

| Approach | Why considered | Why rejected |
|---|---|---|
| Bump `IN_FLIGHT_CEILING_S` to 1800s | Trivial workflow-only change; no server-side risk | Treats the symptom (workflow gives up) not the cause (server hangs). The script would still wedge indefinitely; the next merge would still hit `lock_contention`. Already bumped 60→180 in PR #3400 (closing issue #3398); further bumps mask reality. |
| `systemd-run --scope --property=RuntimeMaxSec=…` | "Proper" systemd primitive; per-cgroup kill semantics | **Rejected at deepen-pass.** Requires polkit auth when invoked by non-root `deploy` user in `--system` mode; polkit in non-TTY context blocks indefinitely. `--user` mode requires `loginctl enable-linger deploy` (new cloud-init step). The cgroup advantage isn't load-bearing here: `docker exec` clients are short-lived and don't side-effect persistent state when killed mid-flight. |
| `cat-deploy-state.sh` annotates "stale" if `elapsed > 900s` | Workflow could fail faster on stale state | Solves the observability gap, not the resource leak (script still wedged, flock still held). Workflow's `Pre-rerun lock probe` already handles stale state via degraded-permissive branch. |
| Add `--time-limit=900` to `docker pull` / `docker exec` invocations inline | Targeted; touches the actual hang sites | Doesn't cover unknown future phases. The systemd-scope is one place that protects the whole script lifetime — adding per-command timeouts is N places, each a future-PR landmine. |
| Move ci-deploy.sh into its own `oneshot` systemd unit (`ci-deploy@.service` templated, started via `systemctl start ci-deploy@$(date +%s).service`) | The "proper" systemd way; `TimeoutSec` applies natively | Significantly more refactor: webhook would need to invoke `systemctl --no-block start …` then poll for `JobState`. Multi-instance state-file races (now the unit instance ID is in the filename). Not worth the complexity for a 1-line `systemd-run --scope` equivalent. |
| Replace flock-FD-200 with a systemd lockfile primitive | Eliminates the manual flock complexity | Out of scope. The flock pattern is correct; the bug is timeout, not locking. |

## Verification Insights (CLI-form-bug class)

All embedded CLI forms verified against the running tooling:

- `timeout --signal=TERM --kill-after=20s 900s …` — verified against `timeout(1)` manpage (Ubuntu 24.04 coreutils 9.4). `-s/--signal` sets the timeout signal (default TERM but explicit-is-better); `-k/--kill-after=DURATION` sends SIGKILL `DURATION` after the initial signal if the process still runs. Default exit code on TERM-by-timeout is 124. `man -P cat timeout` and `timeout --version` both confirm on a clean Ubuntu 24.04 base.
- `set -m` + `kill -TERM 0` in trap — verified against bash manpage. `set -m` (monitor mode) makes the script a process-group leader; `kill -TERM 0` signals every PID in the foreground process group. Tested behavior matches POSIX `kill(2)` `pid=0` semantic.
- ~~`systemd-run --scope --property=RuntimeMaxSec=900s`~~ — rejected at deepen-pass. See Alternatives table.
- `terraform apply -target=…` — pattern matches the canonical invocation triplet in `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md` (Doppler `prd_terraform`, `--name-transformer tf-var`, AWS_* exports).
- `doppler secrets get … --plain` — verified at use across the codebase (`grep -r 'doppler secrets get' plugins/soleur/skills/`).

## References

- Issues: #3704, #2207, #2276, #2529, #3398, #3408. PRs: #3400 (closed #3398). Verified live via `gh api`: #3398 state=CLOSED title="fix(ci): web-platform-release deploy job reports failure even when prod deploy succeeded (poll timeout + stuck lock)"; #3408 state=CLOSED title="Pre-rerun lock probe in web-platform-release deploy job"; #2187 state=MERGED title="fix: batch deploy webhook observability + web-platform test fixes".
- Learning `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` (terraform_data.deploy_pipeline_fix lifecycle).
- Learning `knowledge-base/project/learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md` (file+systemd post-apply contract).
- Learning `knowledge-base/project/learnings/best-practices/2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md` (ceiling-tracking invariant).
- Learning `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md` (canonical apply triplet).
- Runbook `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` (reason taxonomy + rerun safety).
- `systemd.scope(5)`, `systemd-run(1)` manpages.
