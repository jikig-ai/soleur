---
title: "fix(infra): cron_egress_firewall remote-exec apply fails on main (diagnose-then-fix)"
issue: 5279
type: bug-fix
classification: infra-ci-diagnosis
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
created: 2026-06-14
branch: feat-one-shot-cron-egress-firewall-5279
---

# fix(infra): `cron_egress_firewall` remote-exec apply fails on main

Bug. Refs #5279. `apply-web-platform-infra.yml` red on the last 3 consecutive `main` commits at `terraform_data.cron_egress_firewall`'s post-apply remote-exec provisioner.

## Enhancement Summary

**Deepened on:** 2026-06-14
**Agents:** network-outage deep-dive (Explore), architecture-strategist, user-impact-reviewer (single-user-incident threshold), git-history-analyzer, learnings-researcher.
**Live verification:** all 4 cited SHAs (`d79e60209`, `13275b956`, `0defb7b7f`, `bc671d4d2`) confirmed on `origin/main`; all 5 cited issue/PR numbers verified (state + title). All 5 KB-learning citations resolve on disk.

### Key Improvements from Deepen Review
1. **Reordered hypotheses -- 4c (service-enable line 813) is now the LEAD, not 4a.** The unit is `Type=oneshot RemainAfterExit=yes`, so bringing it up blocks on and propagates the loader's exit. Line 813 runs BEFORE any `nft` grep (816+), so a loader `die` (the resolver's live-DNS at :134 is the most plausible) gates everything else and matches the ~4s timing better than a grep mismatch.
2. **Widened the protected-invariant list** (user-impact FINDINGS 1-4): added `jump SOLEUR-EGRESS` (816, the ROOT of the enforcement tree -- without it the whole chain is dead code while green) and the `EnableIPv6` guard (828, IPv6 side-channel). Re-pointed the `egress-probe-negative` at a numeric IP so it tests the daddr default-drop, not the DNS-exfil drop. Scoped OUT the `820` presence check as liveness-only, not a containment invariant.
3. **Corrected Phase 0.1(b)'s "read-only" framing** (architecture P1-2): line 813 re-runs the loader (flush+repopulate -- mutating-but-idempotent). Two-pass repro: read-only assertions first; mutating service-enable under operator ack only if those pass.
4. **Phase 2.1 sentinel + Phase 0 trace now cover line 813**, not just `grep -q` assertions.

### New Considerations Discovered
- The `egress-probe-negative` against `example.com` can pass for the WRONG reason (DNS dropped, not daddr-dropped) -- a vacuous brand-survival proxy unless re-pointed at a numeric target.
- `TF_LOG=DEBUG/TRACE` does NOT capture remote-exec inline script stdout (only provider handshake) -- direct on-host `bash -x` repro is the canonical capture technique for Phase 0.

## Overview

The `apply-web-platform-infra.yml` SSH apply step (the token-gated `terraform apply` over the CF Tunnel bridge, workflow lines 497-531) fails at `terraform_data.cron_egress_firewall`. The **second** `remote-exec` provisioner -- the post-apply assertion block at `apps/web-platform/infra/server.tf:802-844` -- exits with status 1 roughly **4 seconds after the SSH connection is established**. The `file` provisioners (script delivery) all succeed. Terraform suppresses the inline `remote-exec` stdout, so the exact failing command is invisible in the Actions log.

**This is a diagnose-then-fix plan, not a known-fix plan.** The single biggest blocker is *observability*: we cannot currently see which of the ~15 assertions in the block exits 1. Phase 0 makes the failing command visible; Phase 1 fixes whatever it reveals; Phase 2 hardens the block so a future failure is never blind again. The plan is structured so the fix in Phase 1 is conditional on Phase 0's finding, with the most-likely branches pre-analysed.

No code is written during planning. This plan does not pre-commit to a single root cause -- it pre-commits to the *order* of investigation (L3->L7 per the network-outage checklist) and pre-stages the fix for each plausible finding. The fix lands via the EXISTING `apply-web-platform-infra.yml` Terraform apply on merge -- no new infrastructure and no new operator provisioning step is introduced (see `## Infrastructure (IaC)`).

## Premise Validation

Checked at plan time against live evidence (not the issue body's prose):

- **Issue #5279 is OPEN** (`gh issue view 5279 --json state` -> `OPEN`), not closed-by-PR. Premise current.
- **CI ground truth pulled** (`gh run list --workflow=apply-web-platform-infra.yml`): the last 3 runs (27496891449/#5268, 27445232131/#5247, 27444304829/#5244) are `failure`; `feat(inngest): restore 7 Tier-2 crons` (27442636875) is `success`. **Also discovered:** #5089's OWN first apply run (27280628140, 2026-06-10 13:43) was `failure` -- i.e., the resource has been red since its introduction, never reliably green except one manual re-run (27291111717, 2026-06-10 16:41).
- **The "green" intervening commits did not touch `apps/web-platform/infra/**`** -- the workflow only fires on that path (workflow lines 67-75). So those green runs never re-ran the provisioner; `triggers_replace.config_hash` was unchanged -> no-op. The first re-fire after the egress files changed (#5244) went red. **Correction to the issue's framing:** the resource is not "newly broken since 2026-06-12" -- it has been broken since #5089 (2026-06-10) and the egress-CIDR commits merely re-fired the latent failure.
- **Failing surface confirmed from the live log** (run 27496891449): `Error: remote-exec provisioner error ... on server.tf line 802 ... error executing "/tmp/terraform_*.sh": Process exited with status 1`. Line 802 is the *second* remote-exec (the assertion block), not the first (the `mkdir`/`nft install` block at line 749).
- **The CF Access `ci_ssh` token suspicion is PARTIALLY FALSIFIED by the log.** The "CF Tunnel SSH bridge (gated)" step completed without the `cloudflared TCP forward did not open ... CF Access ci_ssh token may be expired/missing` error firing; the provisioner reached "Connected!" and ran the `file` provisioners successfully. A token-expiry failure would have aborted the bridge step *before* terraform ran. The `cloudflared TCP forward` warning the issue cites from the #5247 run is a separate concern (verify in Phase 0.2, but it is not the cause of the assertion-block exit-1).

## Research Reconciliation -- Issue Claims vs. Live Evidence

| Issue claim | Live evidence | Plan response |
|---|---|---|
| "pre-existing since 2026-06-12" | Red since #5089 (2026-06-10); #5089's own apply run 27280628140 failed | Treat as introduced-broken in #5089, not a 06-12 regression. Investigate the assertion block as it shipped in #5089. |
| "File provisioners succeed; remote-exec exits 1 shortly after connecting" | Confirmed -- error is at server.tf:802 (the 2nd remote-exec), ~4s after "Connected!" | Focus on the assertion block; the script-delivery `file` provisioners are out of scope. |
| "Suspected: expired/missing CF Access `ci_ssh` token" | Bridge step completed; "Connected!" reached; no token-expiry error in the failing run's log | Token is NOT the cause of run 27496891449. Phase 0.2 still confirms token freshness as L3 due-diligence, but it is not the lead hypothesis. |
| "Suspected: container egress probes" | Plausible but timing (4s vs `--max-time 20`) argues the failure is an *earlier* `set -e` assertion, before the probe block | Probe is a secondary hypothesis; the early `nft`/`systemctl`/`docker` assertions are the lead. Phase 0 settles it. |
| "Display-format-agnostic fix (#5247) did not fully resolve it" | #5247 changed only the CIDR grep (line 827); the apply stayed red | The CIDR grep is one of ~15 assertions; #5247 fixed one without seeing the others (because output is suppressed). Phase 0 un-suppression is what #5247 lacked. |

## User-Brand Impact

**If this lands broken, the user experiences:** the container egress firewall (`SOLEUR-EGRESS` nftables chain + DOCKER-USER jump) may be *installed but unverified* on each infra apply -- OR, in the worst sub-case, the `set -e` assertion failing *before* the service-enable line (server.tf:813) runs would leave the firewall **not enabled at all**, so a compromised cron (one of the 4 `spawn("bash")` crons that bypass the #5018 PreToolUse hook, ADR-033 I7) could dial an arbitrary host for data exfiltration with no containment. The apply going red also blocks *every* subsequent infra change to the web-platform root behind a failing required-check, so unrelated DNS/Doppler/Cloudflare changes cannot land green.

**If this leaks, the user's data/workflow is exposed via:** an uncontained container egress path -- a prompt-injected or compromised cron exfiltrating operator session data, Supabase rows, or BYOK credentials to an attacker-controlled host, because the default-drop rule the firewall is supposed to enforce was never asserted live (the exact failure mode the `egress-probe-negative` assertion exists to catch).

**Brand-survival threshold:** single-user incident. One operator's container-egress containment silently failing open is a single-user data-exfiltration exposure. CPO sign-off required at plan time; `user-impact-reviewer` invoked at review time.

## Hypotheses (L3 -> L7, network-outage checklist -- `hr-ssh-diagnosis-verify-firewall`)

The remote-exec runs over an SSH bridge, so the network-outage checklist fires. Unverified lower layers are listed FIRST, in L3->L7 order, before any service-layer hypothesis. **The failing run's log already verifies L3-bridge and L7-SSH-handshake as healthy** (bridge opened, "Connected!" reached, file provisioners ran) -- so the residual hypotheses sit at the *post-connection assertion* layer, which is L7-application. The lower-layer checks below are recorded as verified-from-log with the artifact, per the checklist's opt-out discipline (artifact-backed, not "obvious").

1. **L3 -- CF Tunnel SSH bridge / `ci_ssh` token.** *Verified healthy from log* (run 27496891449): the "CF Tunnel SSH bridge (gated)" step did not emit the `cloudflared TCP forward did not open on 127.0.0.1:2222 ... CF Access ci_ssh token may be expired/missing` error; `cloudflared --version` printed; the provisioner reached "Connected!". **Artifact:** bridge step completed, `terraform_data.cron_egress_firewall (remote-exec): Connected!` at 11:09:09Z, error at 11:09:13Z. Phase 0.2 re-confirms token freshness in Doppler `prd_terraform` as due-diligence, but the bridge is not the cause of this run's failure. *(Opt-out justification for not running `hcloud firewall describe`: the bridge bypasses the :22 firewall allowlist entirely via the tunnel -- the runner egress IP is deliberately NOT in `var.admin_ips`; the firewall path is not on this provisioner's connection route.)*
2. **L3 -- DNS / routing to the host.** *Verified healthy from log*: `terraform output -raw server_ip` resolved (the bridge scoped its NAT redirect to it) and SSH connected. No DNS/routing hypothesis applies -- the packet reached sshd.
3. **L7 -- SSH handshake / sshd.** *Verified healthy from log*: `Connected!` printed; `file` provisioners (scp over the same connection) succeeded. sshd accepted the session.
4. **L7 -- APPLICATION (the assertion block, server.tf:802-844) -- LEAD HYPOTHESIS.** One of the `set -e`-guarded commands in the block exits non-zero. **Output is suppressed, so the specific command is unknown -- Phase 0 makes it visible.** Pre-staged sub-hypotheses, reordered after deepen-plan review found the **service-enable line (server.tf:813) is the GATING command**, not an `nft` grep:
   - **4c (LEAD -- the gating command, most dangerous).** The service-enable line (server.tf:813, which brings up `cron-egress-firewall.service`) exits non-zero. **Mechanism (confirmed by reading `cron-egress-firewall.service`):** the unit is `Type=oneshot RemainAfterExit=yes TimeoutStartSec=300`, so bringing it up **blocks on the oneshot and propagates the loader's exit code**. The loader (`cron-egress-nftables.sh`) has 6 fast `die` paths (`nft` absent :37, bridge iface absent :38, `EnableIPv6 != false` :45, invalid-CIDR reject-whole-file :90, and -- most plausibly -- `cron-egress-resolve.sh` live-DNS resolution failure :134). A loader `die` is fast (matches the ~4s timing) and means the firewall is **not enabled at all**. Critically, line 813 runs BEFORE any `nft list | grep` assertion (816+), so if 813 dies, 4a/4b/4d/4e are all unreachable this run. The service ExecStart runs the loader under `doppler run` (env-file `-/etc/default/inngest-server`) -- a Doppler-CLI/token hiccup at apply time is a distinct `die`-adjacent path (the resolver needs SENTRY_*/SUPABASE_* env to resolve dynamic hosts; absent env forces additive-only but a hard resolve failure still `die`s). **This is the lead because the ~4s timing the issue cites points harder at a loader `die` than at a render-format grep mismatch.**
   - **4a (secondary).** An `nft list ... | grep -q '<literal>'` assertion (lines 816-827) fails because the live nftables render differs from the grepped literal -- the exact class #5247 hit once on the CIDR set (line 827). Other literals (`jump SOLEUR-EGRESS`, `egress-blocked`, `egress-dns-exfil`, `dport 8288 accept`, `cidr allowlist`) were NOT given the display-agnostic treatment #5247 applied to line 827. **Reachable only if 4c's line 813 already succeeded** (these run after the service is enabled).
   - **4b.** `docker network inspect bridge -f '{{.EnableIPv6}}' | grep -qx false` (line 828) fails because the bridge reports `true`/`unknown` (IPv6 enabled, or docker not queryable at apply time). *Fast-failing; reachable only post-813.*
   - **4d (secondary).** The container `egress-probe-positive` (`docker exec ... curl api.github.com`) or `egress-probe-negative` (`curl example.com` must FAIL) at line 838 fails. *Slower (`--max-time 20`/`8`) -> less consistent with 4s timing; if the container is absent the `else` branch warns-and-skips (does not fail). Note: the negative probe can pass for the WRONG reason -- example.com unreachable because DNS resolution was dropped (port-53 to non-pinned resolver) rather than because the daddr default-drop fired; see Phase 1 4d and Sharp Edges.*
   - **4e.** `curl -s --max-time 10 https://api.github.com` host-egress spot-check (line 841) fails -- host egress to GitHub blocked. *Up to 10s -> least consistent with 4s timing.*
   - **4f.** The timer-active check (line 829) reports `cron-egress-resolve.timer` inactive. Lower-probability (an enabled timer arms immediately; `OnBootSec=2min` in `cron-egress-resolve.timer` governs first *trigger*, not active-state), but confirm in Phase 0 rather than assume. If it races, prefer the durable enabled-state check over the active-state check for the timer specifically.

## Implementation Phases

### Phase 0 -- Make the failing command visible (BLOCKING; no fix until this completes)

The fix cannot be chosen until we see which command exits 1. This phase un-suppresses the remote-exec output and captures the exact failing line, WITHOUT shipping debug instrumentation to `main` permanently.

**0.1 -- Reproduce with output un-suppressed.**
- The SSH apply re-runs the provisioner because the resource is currently `tainted` (the log shows `is tainted, so must be replaced`).
- To capture the failing command WITHOUT a merge, two automatable options, in order of preference:
  - **(a)** Trigger a `workflow_dispatch` run with a *temporary* instrumented variant of the block on a NON-default test branch -- **rejected**: `workflow_dispatch` against a feature branch runs the workflow file from that branch but the apply still hits prod state; acceptable only if `-target`-scoped to `cron_egress_firewall` and `[ack-destroy]`-free. Lower-risk than it sounds because the resource is a pure on-host re-provision (no `when=destroy`), but still a prod write.
  - **(b) PREFERRED -- diagnostic reproduction from the operator session.** Connect to the host over the operator's existing admin-IP path (the operator egress IP is in `var.admin_ips`, so the direct path works without the CF bridge) and run the assertion commands (copied verbatim from server.tf:810-842) under shell trace (`bash -x`) so every command and its exit status streams to the operator terminal. The first non-zero command IS the culprit. **The trace MUST include the service-enable line (server.tf:813), not just the read-only grep/curl assertions** -- per deepen-plan review (P1-1), 813 is the GATING command and the most likely failure (4c); tracing only the read-only assertions would skip it. **Framing correction (deepen-plan P1-2):** this is NOT fully read-only -- line 813 re-runs the loader, which flush+repopulates the SOLEUR-EGRESS chain and re-resolves the allowlist. That is idempotent-by-design but IS a state mutation, and if the loader is currently `die`-ing at resolve, re-running it could leave the firewall in the fail-open-bootstrap state (drop rules absent) for that window. Run two passes: first trace ONLY the read-only assertions (816-842, skipping 811-814) to test 4a/4b/4d/4e; only if those all pass, run the mutating service-enable line under operator ack to test 4c. Capture `journalctl -u cron-egress-firewall.service` for the loader's `die` message either way.
- **Record the exact failing command and its stderr** into the spec's session-state and the plan's Research Reconciliation before proceeding to Phase 1.

**0.2 -- Confirm `ci_ssh` token freshness (L3 due-diligence, parallel to 0.1).**
- `doppler secrets get CI_SSH_ACCESS_TOKEN_ID --plain -p soleur -c prd_terraform` and `CI_SSH_ACCESS_TOKEN_SECRET` -- confirm both present and non-empty (read-only).
- Cross-check the CF Access service-token expiry: the `cloudflare_notification_policy.service_token_expiry` resource exists (workflow line 290) -- confirm via the Cloudflare MCP whether the `ci_ssh` service token is within its validity window. If expired, that is a SEPARATE issue (the bridge would fail entirely, which it did not in run 27496891449) -- file it, do not fold into this fix.

**0.3 -- Verify sibling provisioners pass (scope confirmation).**
- The 7 SSH-provisioned siblings (`disk_monitor_install`, `resource_monitor_install`, `fail2ban_tuning`, `journald_persistent`, `docker_seccomp_config`, `apparmor_bwrap_profile`, `orphan_reaper_install`) use the SAME post-apply assertion pattern (server.tf has 16 `grep -q`/check-active/`nft list` assertions total) and the SAME bridge. They are GREEN in run 27496891449's SSH apply step (only `cron_egress_firewall` errored). This confirms the failure is specific to the egress assertions/probes, not the bridge or the generic pattern. Record this as the scope boundary: **do not touch the siblings.**

**Phase 0 exit gate:** the exact failing command is named in the plan/spec with its stderr. Phase 1 does not begin until then.

### Phase 1 -- Fix the identified failing assertion (branch on Phase 0 finding)

Apply the minimal fix for whatever Phase 0 reveals. Pre-staged responses per sub-hypothesis (ordered lead-first):

- **If 4c (loader/service-enable failure -- LEAD, most dangerous):** Phase 0's shell trace + `journalctl -u cron-egress-firewall.service` will show the loader's `die` message. The loader (`cron-egress-nftables.sh`) can `die` on: `nft`/bridge-interface absence (:37-38), `EnableIPv6` (:45), CIDR-validator rejection (:90, #5268), or `cron-egress-resolve.sh` resolution failure (:134, DNS). Fix the specific `die` cause. If it is a CIDR-validator false-reject of a committed line, re-check the 4 committed ranges against `is_valid_ipv4_cidr` (they passed the #5268 drift-guard 133/0, so unlikely but verifiable). If it is a resolve failure at apply time, consider whether the apply-time host/container DNS view differs from steady-state (the resolver unions host + container views; at apply time the container may be absent). The firewall correctly fails-open-on-bootstrap by design when the container is down -- but the assertion block should then LOUDLY skip (like the 838 probe block), never silently green. **Do NOT** make the apply pass by making the service-enable non-fatal -- a firewall that fails to enable must keep the apply red.
- **If 4a (nft literal-grep format mismatch):** apply the same display-agnostic treatment #5247 gave line 827 to the specific failing literal. For chain-rule greps (`jump SOLEUR-EGRESS`, `egress-blocked`, etc.), the literal is in the rule *comment* and is version-stable -- but verify against the live `nft list chain` output captured in Phase 0 (the comment may render with surrounding quotes/escapes that defeat `grep -q '<bare>'`). Prefer matching a structural token that nft cannot reformat (a comment substring that spans no punctuation boundary -- see Sharp Edges on paren-safety). **Do NOT** weaken an assertion to the point it passes vacuously -- see the protected-invariant list below.
- **If 4b (`EnableIPv6` check):** determine from Phase 0 whether the bridge genuinely has IPv6 enabled (a real containment gap -> fix the bridge config, do NOT relax the assertion) or whether `docker network inspect` is failing at apply time (e.g. docker not ready). If gating the check on docker availability, the else-branch MUST `exit 1` LOUDLY (like the 838 probe block), **never a silent pass** -- a docker-unavailable apply that cannot prove IPv6 is off must stay red (deepen-plan user-impact FINDING 3: a silent skip reopens the v6 exfil side-channel).
- **If 4d (container probe):** re-evaluate against the live `soleur_egress_allow_cidr` interval set captured in Phase 0. If the container IS running and the positive probe fails, the allowlist is missing a host the container needs (the #5089 learning found 10 hosts beyond the cron set -- Resend, Buttondown, Cloudflare validators, browser push, canary). If the negative probe fails (example.com reachable), the ruleset is inert -- a real containment bug. **Probe-target correction (deepen-plan user-impact FINDING 2):** the negative probe currently uses `example.com`, which is dropped at the DNS layer (port-53 to a non-pinned resolver, rules 146-149) -- so the probe can pass for the WRONG reason (DNS dropped, not daddr-dropped). Re-point the negative probe at a NUMERIC non-allowlisted IP (no DNS needed) so it exercises the daddr default-drop path directly. Either way, fix the firewall, not the assertion.
- **If 4e (host-egress spot-check):** unlikely given timing; if it fires, host egress to api.github.com is blocked -- investigate the host firewall (out of this resource's scope; the comment at line 839 says host OUTPUT is never filtered by DOCKER-USER, so a host-egress failure points elsewhere).
- **If 4f (timer-active race):** prefer the durable enabled-state check over the timing-sensitive active-state check for `cron-egress-resolve.timer`.

**Protected-invariant list (deepen-plan user-impact FINDINGS 1-4 -- do NOT relax any of these to green the apply):**
- **`jump SOLEUR-EGRESS` in DOCKER-USER (server.tf:816)** -- the ROOT of the enforcement tree. Without the jump, container traffic never enters the chain and EVERY downstream rule (default-drop, DNS-exfil drop, allowlist) is dead code while still asserting green. This is MORE load-bearing than the default-drop itself. Assert the rule is *reachable*, not merely present in a comment.
- **default-drop `egress-blocked` (server.tf:817)** -- the terminal drop.
- **`EnableIPv6=false` guard (server.tf:828)** -- closes the IPv6 side-channel (the chain is IPv4-only `table ip`). A vacuous relaxation (e.g. `grep -q false` instead of `grep -qx false`, or a silent docker-unavailable skip) silently reopens v6 egress.
- **`egress-probe-negative` (server.tf:838)** -- but ONLY load-bearing once re-pointed at a numeric target (FINDING 2 above); as-written against `example.com` it is a DNS-path proxy.
- **NOT load-bearing -- scope out explicitly:** the `soleur_egress_allow | grep -qE '[0-9.]+'` presence check (server.tf:820) is presence-only (any IP-shaped match passes); it does NOT reject an inert/over-broad/stale set. Document it as a liveness check, NOT a containment invariant, so a future editor does not mistake its green for proof of correct allowlist contents.

**Test before fix (RED/GREEN, `cq-write-failing-tests-before`):** `apps/web-platform/infra/cron-egress-firewall.test.sh` already exists (133/0 green, extended in #5268). Add a behavioral predicate test that reproduces the Phase 0 failing condition (e.g. an `nft list` fixture in the live render format that the *old* grep fails and the *new* grep passes), so the fix is regression-locked. The test must FAIL against the current assertion and PASS after the fix.

### Phase 2 -- Harden observability so a future failure is never blind (always runs)

The root structural problem #5247 hit: terraform suppresses inline `remote-exec` stdout, so a one-line format mismatch took 3 PRs to chase because nobody could see which command failed. Close that permanently.

- **2.1 -- Make the assertion block self-reporting under `set -e`.** Replace the bare `set -e` + sequential assertions with assertions that echo a unique sentinel on failure BEFORE exiting, so terraform's *captured-on-error* output names the failing check even with stdout suppressed. Pattern (per the 2026-06-10 learning, the `if cmd; then ...; else echo 'X FAILED'; exit 1; fi` form already used for the probe block at line 838): wrap each assertion as `<cmd> || { echo 'ASSERT-FAILED: <name>'; exit 1; }`. **Cover the service-enable line (server.tf:813) too**, not only the `grep -q` assertions (deepen-plan review: 813 is the LEAD failure 4c, and a sentinel there names a loader `die` directly) -- e.g. wrap the service-enable so a non-zero exit emits `ASSERT-FAILED: cron-egress-firewall-enable` and surfaces the loader's `journalctl` tail. On failure, terraform surfaces the last output lines including the sentinel. This is the cheapest no-SSH observability win and directly satisfies `hr-observability-as-plan-quality-gate` / `hr-no-ssh-fallback-in-runbooks`.
- **2.2 -- Mirror an apply-time assertion failure to Sentry.** The resolver script already posts Sentry events (`cron-egress-resolve` slug). The apply-time provisioner has no such mirror -- a red apply is only visible in GitHub Actions, not in the operator's no-SSH observability plane. Confirm whether `apply-web-platform-infra.yml` failures already route to Slack/Sentry; if not, add a minimal apply-failure mirror. Keep this minimal -- the primary win is 2.1.
- **2.3 -- Document the un-suppression technique** in the cron-egress runbook (`knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md` referenced by the resolver) so the next operator reproduces in minutes, not 3 PRs.

## Files to Edit

- `apps/web-platform/infra/server.tf` -- the `cron_egress_firewall` post-apply remote-exec block (lines 802-844); the specific assertion identified in Phase 0, plus the Phase 2.1 sentinel wrappers.
- `apps/web-platform/infra/cron-egress-nftables.sh` -- only if Phase 0 reveals a loader `die` (sub-hypothesis 4c).
- `apps/web-platform/infra/cron-egress-allowlist-cidr.txt` -- only if 4c/4d reveals a missing/invalid range.
- `apps/web-platform/infra/cron-egress-firewall.test.sh` -- regression test (AC2/AC3/AC4).
- `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md` (or sibling runbook) -- Phase 2.3 un-suppression technique.

## Files to Create

- None expected. If Phase 0 needs a throwaway instrumented variant (option 0.1a), it lives on a non-default branch and is NOT committed to main.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` and searched bodies for `server.tf`, `cron-egress-nftables.sh`, `cron-egress-resolve.sh`, `apply-web-platform-infra.yml`. **None** matched the files this plan edits. (Recorded so the next planner sees the check ran.)

## Domain Review

**Domains relevant:** Engineering (infra/CI), Product (brand-survival threshold).

### Engineering (infra)

**Status:** reviewed (CTO/platform lens applied inline during planning)
**Assessment:** Diagnosis-first infra-CI bug. The fix surface is a single terraform_data resource's post-apply assertion block plus its loader scripts. No new infrastructure is introduced (Phase 2.8 IaC gate: skip -- pure edit to an already-provisioned surface). The architectural risk is *vacuous-assertion relaxation*: weakening a load-bearing containment check to make the apply pass green. The plan explicitly forbids this (Phase 1 "assert the invariant, not a proxy"). Sibling provisioners are out of scope (verified green in Phase 0.3).

### Product/UX Gate

**Tier:** none
**Decision:** N/A -- no user-facing surface. No file under `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` is touched. Mechanical UI-surface override did not fire.
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

The brand-survival threshold (`single-user incident`) is product-relevant for sign-off (`requires_cpo_signoff: true`) but the change has no UI. CPO sign-off is on the *technical approach to a containment-affecting fix*, not on any page design.

## Infrastructure (IaC)

Skip -- this plan introduces NO new infrastructure. It edits the post-apply assertion block of an EXISTING `terraform_data` resource and its already-shipped loader scripts. No new server, service, cron, secret, vendor, DNS record, or firewall *resource* is added. The apply path is the existing `apply-web-platform-infra.yml` SSH apply over the CF Tunnel bridge (`hr-all-infrastructure-provisioning-servers` already satisfied -- the PR merge re-fires the provisioner; the resource is currently `tainted` so it replaces on next apply). The fix lands green via the existing workflow on merge; no operator provisioning step is introduced. The diagnostic reproduction in Phase 0.1(b) is a read-only on-host trace over the operator's existing admin-IP path (capturing which suppressed assertion exits 1), not provisioning. The service-state checks referenced in Phase 1 are the existing server.tf assertion lines under analysis, not new manual steps.

## Observability

```yaml
liveness_signal:
  what: "terraform_data.cron_egress_firewall apply result (green/red) in apply-web-platform-infra.yml"
  cadence: "every merge to main touching apps/web-platform/infra/** (+ 12h scheduled-terraform-drift backstop)"
  alert_target: "GitHub Actions run status; Phase 2.2 adds Sentry mirror for apply-time assertion failure"
  configured_in: ".github/workflows/apply-web-platform-infra.yml + apps/web-platform/infra/server.tf:802-844"
error_reporting:
  destination: "Phase 2.1 sentinel echo surfaces the failing assertion name in the (otherwise-suppressed) terraform remote-exec error output; Phase 2.2 mirrors to Sentry (slug-aligned with cron-egress-resolve)"
  fail_loud: true
failure_modes:
  - mode: "an nft/service/docker/probe assertion exits 1 at apply time"
    detection: "Phase 2.1 sentinel 'ASSERT-FAILED: <name>' in terraform error output"
    alert_route: "GitHub Actions red check (required) + Phase 2.2 Sentry event"
  - mode: "firewall installed but unverified (assert fails before/without enabling the service)"
    detection: "service enabled/active assertion in the block; resolver self-heal Sentry event (enforcement_missing) at runtime"
    alert_route: "apply red + cron-egress-resolve Sentry event"
  - mode: "container egress probe fails (allowlist gap or inert ruleset)"
    detection: "egress-probe-positive/negative assertions (server.tf:838); runtime egress-blocked Sentry events"
    alert_route: "apply red + cron-egress-blocked runbook"
logs:
  where: "GitHub Actions run log (apply step); host journald for the loader/resolver; Sentry for runtime drops"
  retention: "Actions default; journald bounded+persistent (#4792); Sentry default"
discoverability_test:
  command: "gh run list --workflow=apply-web-platform-infra.yml --limit 1 --json conclusion --jq '.[0].conclusion'"
  expected_output: "success (after fix lands and the apply re-fires on merge)"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (Phase 0 gate).** The exact failing assertion command and its stderr are recorded in the plan/spec -- captured via the un-suppressed (shell-trace / un-suppressed remote-exec) reproduction in Phase 0.1. The PR body names which sub-hypothesis (4a-4e) was the actual cause.
- [ ] **AC2 (regression test).** `apps/web-platform/infra/cron-egress-firewall.test.sh` gains a behavioral predicate that FAILS against the pre-fix assertion and PASSES after the fix, reproducing the Phase 0 condition (e.g. a live-render `nft list` fixture). Full suite green (`bash apps/web-platform/infra/cron-egress-firewall.test.sh` -> N passed, 0 failed) + `bash -n` + `shellcheck` clean on any edited `.sh`.
- [ ] **AC3 (fix is non-vacuous; protected-invariant set).** The fixed assertion still rejects the broken state it guards: a test fixture representing the *absent/inert* condition still makes the assertion exit 1 (the fix changed the literal/format match, NOT the invariant). The protected set is `{ server.tf:816 jump SOLEUR-EGRESS, 817 default-drop, 828 EnableIPv6 guard, 838 egress-probe-negative (re-pointed at a numeric non-allowlisted IP) }` -- each has a negative fixture proving it still fails on the broken state. The `820` presence check is explicitly documented as liveness-only, NOT a containment invariant.
- [ ] **AC4 (observability -- Phase 2.1).** Every assertion in server.tf:810-842 **including the service-enable line (813)** emits a unique `ASSERT-FAILED: <name>` sentinel before `exit 1`, verified by a test that runs the block with one assertion forced-false and greps the captured output for the sentinel.
- [ ] **AC5 (sibling scope boundary).** No change to the 7 SSH-provisioned sibling `terraform_data` resources. `git diff --name-only` touches only `server.tf` (the cron_egress block), `cron-egress-*.sh`/`.txt` as needed, the test, and the runbook.
- [ ] **AC6 (CPO sign-off).** CPO has signed off on the technical approach at plan time (threshold = single-user incident). Recorded in PR.
- [ ] **AC7 (PR body uses `Ref #5279`, not `Closes`).** Because the fix's *proof* is the green apply that fires post-merge, the issue closes in the post-merge step after the apply lands green -- not at merge. (`wg-use-closes-n-in-pr-body-not-title-to`, ops-remediation variant.)

### Post-merge (operator/automated)

- [ ] **AC8.** On merge to main (touches `apps/web-platform/infra/**`), `apply-web-platform-infra.yml` fires and the SSH apply step completes GREEN at `terraform_data.cron_egress_firewall`. Verify: `gh run list --workflow=apply-web-platform-infra.yml --limit 1 --json conclusion --jq '.[0].conclusion'` -> `success`. **Automatable** -- no operator SSH.
- [ ] **AC9.** After the green apply, the firewall is verified live (read-only): the DOCKER-USER jump rule and the cron-egress-firewall service are confirmed active. **Automatable** over the existing bridge / operator path.
- [ ] **AC10.** `gh issue close 5279` after AC8 passes (the apply landing green is the proof the issue is resolved).

## Test Scenarios

- Loader/assert fixture: an `nft list set ip filter soleur_egress_allow_cidr` rendering in BOTH the `/20` prefix form and the expanded-range form passes the (display-agnostic) CIDR assertion (regression-locks #5247's class for the specific failing literal).
- Forced-false assertion: running the block with one assertion's input absent makes the block exit 1 AND emits the matching `ASSERT-FAILED: <name>` sentinel (Phase 2.1).
- Non-vacuous negative: an inert ruleset fixture (no default-drop rule) still fails the relevant assertion (AC3).
- The 4 committed CIDR ranges (`140.82.112.0/20`, `185.199.108.0/22`, `192.30.252.0/22`, `143.55.64.0/20`) all pass `is_valid_ipv4_cidr` (re-confirm #5268 invariant unbroken by any loader edit).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Section is filled above.)
- **Do NOT relax a containment assertion to green the apply.** The `egress-probe-negative` (example.com must be UNREACHABLE) and the default-drop `grep -q 'egress-blocked'` are load-bearing brand-survival checks. Weakening them to pass is exactly the proxy-vs-invariant trap -- at single-user-incident threshold a green check over a broken firewall is worse than a red one.
- **Drift-runbook canonical TF invocation** (if Phase 0/local reproduction touches terraform): export raw `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` from Doppler `prd_terraform` (R2 backend creds -- must be raw, `tf-var` mangles them), `terraform init -input=false`, then `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform <plan|apply>`. Without `--name-transformer tf-var`, plan errors with ~13 `No value for required variable`.
- **nft grep paren-safety:** when matching a rule comment, audit punctuation between words -- `grep -q 'cidr allowlist'` matches the bare phrase, but if nft renders the comment quoted/parenthesised the bare match can fail. Pick a phrase spanning no punctuation boundary in the live render captured in Phase 0.
- **A timer-active check is timing-sensitive** -- a timer can be enabled-but-not-yet-active at apply time (first tick pending). If Phase 0 shows the timer assertion racing, prefer the durable enabled-state check over the active-state check for the timer specifically.
- **The resource is currently `tainted`** (the failing apply taints it). The next apply REPLACES it (destroy+recreate, pure on-host re-provision, no `when=destroy`). This means the fix is proven by the post-merge apply, and a local `terraform apply -replace=` is the manual reproduction path.
- **Issue framing correction:** the resource has been red since #5089 (2026-06-10), not since 2026-06-12. The green intervening runs never re-ran the provisioner (path filter). Do not assume an egress-CIDR commit "introduced" the failure -- #5089's assertion block did.

## References

- Issue: #5279
- Failing run: 27496891449 (`gh run view 27496891449 --log`) -- error at `server.tf:802`
- Introducing PR: #5089 (`d79e60209`, 2026-06-10); its own apply run 27280628140 also failed
- Prior fix attempts: #5244 (`13275b956`), #5247 (`0defb7b7f`), #5268 (`bc671d4d2`)
- Resource: `apps/web-platform/infra/server.tf:719-845`
- Loader: `apps/web-platform/infra/cron-egress-nftables.sh`
- Resolver: `apps/web-platform/infra/cron-egress-resolve.sh`
- Test: `apps/web-platform/infra/cron-egress-firewall.test.sh`
- Workflow: `.github/workflows/apply-web-platform-infra.yml` (SSH apply: lines 497-531)
- Bridge: `.github/actions/cf-tunnel-ssh-bridge/action.yml`
- Learning (DIRECT): `knowledge-base/project/learnings/2026-06-10-terraform-remote-exec-gating-and-container-scoped-egress-allowlist.md`
- Learning: `knowledge-base/project/learnings/security-issues/2026-06-14-nft-injection-via-unvalidated-config-reject-whole-file.md`
- Learning: `knowledge-base/project/learnings/2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`
- Learning: `knowledge-base/project/learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md`
- Checklist: `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md` (`hr-ssh-diagnosis-verify-firewall`)
