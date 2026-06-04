---
title: "Cron silent-producer root cause was bwrap userns drift, not turn budget — and a gating health-check shipped unvalidated then blocked all deploys"
date: 2026-06-04
tags: [incident, cron, inngest, bwrap, sandbox, observability, terraform, live-evidence, deploy-gate, regression]
related_issues: ["#4927", "#4928"]
related_sentry: ["4d67bdc8e3564efdb6afb5d8ff23527c"]
related_prs: ["#4932", "#4941"]
---

# Cron silence was bwrap userns drift, not turn budget

## What happened

Three scheduled Inngest cron producers went silent (community-monitor, content-generator, roadmap-review). The pre-written plan hypothesised **turn-budget exhaustion** and prescribed raising `--max-turns` 50→80 / 40→80. The live Sentry `extra` payloads refuted that:

- **community-monitor 06-04 (exit 0):** degraded report — `bwrap` (the Claude Code Bash sandbox) could not mount `/proc` via an unprivileged user namespace (`Operation not permitted`). **Every** Bash tool call failed; claude wrote a best-effort digest, exited 0, and never reached `gh issue create`.
- **content-generator 06-04 (exit 1):** `"Reached max turns (50)"` — but captured **while bash was broken**, i.e. claude burned turns retrying failed Bash. Contaminated evidence; does NOT prove a real budget shortfall.
- **community-monitor 06-03 (exit 1):** `"Credit balance is too low"` (Anthropic billing) — a separate transient.

Real root cause: the host sysctl `kernel.apparmor_restrict_unprivileged_userns=0` (required for bwrap's userns + `/proc` mount) had drifted back to `1` and nothing re-asserted it.

## The fix (#4932) and the regression it caused (#4941)

**The real fix — drift-proof provisioning (#4932, kept, verified).** The sysctl was set by a `terraform_data` provisioner keyed ONLY on `sha256(seccomp-bwrap.json)` — identical on a replaced VM (the fresh-host trap, `hr-fresh-host-provisioning-reachable-from-terraform-apply`) — and a bare `sysctl -w` lost on reboot. Fix: key the trigger on `{ seccomp hash, server_id }` and assert via a boot-persistent oneshot systemd unit (`bwrap-userns-sysctl.service`). The post-merge `terraform apply` recovered the host; a manual `community-monitor` trigger then produced a healthy digest issue (#4943) — verified recovery.

**The regression — a gating health-check shipped unvalidated (#4932 → reverted in #4941).** `ci-deploy.sh` already ran a bwrap probe that *gated* the deploy (rollback on failure) but tested only `--unshare-pid --bind / /`, never the cron's `--unshare-user`/`--proc /proc` path — a real coverage gap. The attempted fix added `--unshare-user --proc /proc` to that *gating* probe. It was **validated only against the test mock (which always succeeds)**, never against a real host, and the synthetic invocation did not match what claude's sandbox actually does: it **failed on a healthy host** (the apply asserted the sysctl at 14:30:31, the probe still failed at 14:38:43) and **rolled back every web-platform deploy**. Reverted in #4941; the userns/proc coverage was re-added as a **non-blocking** sysctl-value check (reads `kernel.apparmor_restrict_unprivileged_userns`, zero false-positive risk) — detection without the power to block deploys.

## Key insights (reusable)

- **A plan's root-cause hypothesis is a hypothesis. Pull the live evidence before coding.** The `--max-turns` bump would have been a false fix: it cannot help when bwrap can't run bash, and #4927/#4928 would not have recovered. Sentry event `extra` (`exitCode`/`stdoutTail`/`stderrTail`, threaded by the output-aware heartbeat) was the authoritative source — read it via the org-issues API with `SENTRY_ISSUE_RW_TOKEN`, no SSH.
- **Evidence captured while a dependency is broken is contaminated.** "Reached max turns (50)" looked like a budget problem but was a symptom of broken bash. Don't pattern-match a symptom to the nearest prior fix (community-monitor's 50→80 bump).
- **A health-check that diverges from production reality is worse than none — in BOTH directions.** The old gating probe passed while crons were broken (didn't test userns); the "improved" one failed while the host was healthy (tested a synthetic userns invocation the real sandbox doesn't use). Same root flaw: the probe and the reality diverged.
- **Never ship a deploy-*gating* check validated only against a mock.** The test asserted the probe's command *shape* (flags present) against an always-succeeding mock — it confirmed nothing about the probe's *outcome* on a real host. For a check whose correctness depends on real kernel/container behavior, mock-green is not coverage; the change is runtime-unvalidated until observed on the real target.
- **Dark-launch deploy gates.** A new/changed check that can block or roll back a deploy must ship **non-blocking (log-only) first**, be observed passing on ≥1 real deploy, then be promoted to gating. Never validate a gate change with the same deploy it gates. When the safer non-blocking form already exists, do not "upgrade" it to gating without that observation — exactly the step skipped here.
- **Prefer reading the root-cause value over a synthetic capability probe.** The drift was `kernel.apparmor_restrict_unprivileged_userns` flipping to 1. A non-blocking read of that exact sysctl is unambiguous and false-positive-free; a synthetic `bwrap … -- true` with guessed flags is not. Detect the specific thing that drifted.
- **Don't bundle speculative detection into a verified recovery.** The evidence demanded the sysctl fix; it did NOT demand the canary-probe change. Bundling the unvalidated enhancement into the recovery PR coupled a safe change to a risky one. Ship recovery alone → verify → detection as its own change with its own validation.
- **One-time `terraform_data` provisioners gated on a file hash silently skip on host replacement.** Fold the server id into the trigger so a fresh VM re-runs them; assert reboot-critical kernel state via an enabled systemd unit, not a one-shot `sysctl -w`.

See [[2026-06-01-output-aware-cron-heartbeat-and-live-evidence-refutes-plan-hypothesis]] — same "live evidence refutes plan" pattern, prior occurrence.
