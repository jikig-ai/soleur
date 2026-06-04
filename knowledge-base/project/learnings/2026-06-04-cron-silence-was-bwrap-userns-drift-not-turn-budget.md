---
title: "Cron silent-producer root cause was bwrap userns drift, not turn budget — and the canary probe had a coverage gap that hid it"
date: 2026-06-04
tags: [incident, cron, inngest, bwrap, sandbox, observability, terraform, live-evidence]
related_issues: ["#4927", "#4928"]
related_sentry: ["4d67bdc8e3564efdb6afb5d8ff23527c"]
related_prs: ["#4932"]
---

# Cron silence was bwrap userns drift, not turn budget

## What happened

Three scheduled Inngest cron producers went silent (community-monitor, content-generator, roadmap-review). The pre-written plan hypothesised **turn-budget exhaustion** and prescribed raising `--max-turns` 50→80 / 40→80. The live Sentry `extra` payloads refuted that:

- **community-monitor 06-04 (exit 0):** degraded report — `bwrap` (the Claude Code Bash sandbox) could not mount `/proc` via an unprivileged user namespace (`Operation not permitted`). **Every** Bash tool call failed; claude wrote a best-effort digest, exited 0, and never reached `gh issue create`.
- **content-generator 06-04 (exit 1):** `"Reached max turns (50)"` — but captured **while bash was broken**, i.e. claude burned turns retrying failed Bash. Contaminated evidence; does NOT prove a real budget shortfall.
- **community-monitor 06-03 (exit 1):** `"Credit balance is too low"` (Anthropic billing) — a separate transient.

Real root cause: the host sysctl `kernel.apparmor_restrict_unprivileged_userns=0` (required for bwrap's userns + `/proc` mount) had drifted back to `1` and nothing re-asserted it.

## Two mechanisms, both fixed in #4932

1. **Provisioning was not drift-proof.** The sysctl was set by a `terraform_data` provisioner keyed ONLY on `sha256(seccomp-bwrap.json)` — identical on a replaced VM (the fresh-host trap, `hr-fresh-host-provisioning-reachable-from-terraform-apply`) — and a bare `sysctl -w` lost on reboot. Fix: key the trigger on `{ seccomp hash, server_id }` and assert via a boot-persistent oneshot systemd unit (`bwrap-userns-sysctl.service`).
2. **The canary gate had a coverage gap.** `ci-deploy.sh` already ran a bwrap probe that *gated* the deploy — but with `--unshare-pid --bind / /` only, never `--unshare-user`/`--proc /proc`. So it passed even when the userns sysctl had reverted, and the canary swapped a broken host to prod "healthy." Fix: the probe now exercises `--unshare-user --proc /proc` — the exact path the cron sandbox uses — turning a silent ~2-week outage into a deploy-time rollback.

## Key insights (reusable)

- **A plan's root-cause hypothesis is a hypothesis. Pull the live evidence before coding.** The `--max-turns` bump would have been a false fix: it cannot help when bwrap can't run bash, and #4927/#4928 would not have recovered. Sentry event `extra` (`exitCode`/`stdoutTail`/`stderrTail`, threaded by the output-aware heartbeat) was the authoritative source — read it via the org-issues API with `SENTRY_ISSUE_RW_TOKEN`, no SSH.
- **Evidence captured while a dependency is broken is contaminated.** "Reached max turns (50)" looked like a budget problem but was a symptom of broken bash. Don't pattern-match a symptom to the nearest prior fix (community-monitor's 50→80 bump).
- **A gating health-check that doesn't exercise the production-critical path is worse than none** — it manufactures false confidence. The canary bwrap probe must mirror what the real sandbox does (userns + `/proc`), or drift in that exact capability sails through green.
- **One-time `terraform_data` provisioners gated on a file hash silently skip on host replacement.** Fold the server id into the trigger so a fresh VM re-runs them; assert reboot-critical kernel state via an enabled systemd unit, not a one-shot `sysctl -w`.

See [[2026-06-01-output-aware-cron-heartbeat-and-live-evidence-refutes-plan-hypothesis]] — same "live evidence refutes plan" pattern, prior occurrence.
