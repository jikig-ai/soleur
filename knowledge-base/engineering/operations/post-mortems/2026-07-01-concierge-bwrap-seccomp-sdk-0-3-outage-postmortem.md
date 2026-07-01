---
title: "Concierge Bash sandbox down for all tenants — claude-agent-sdk 0.2.85→0.3.197 split-unshare blocked by the container seccomp profile"
date: 2026-07-01
incident_pr: 5874
incident_window: "2026-07-01T13:20Z (#5849 deploy) → 2026-07-01 (fix shipping in #5874)"
recovery_at: "pending — closes when a real Bash command succeeds in a fresh /soleur:go post-deploy (PR #5874 restoration gate)"
suspected_change: "#5849 (feat(sonnet-5): migrate toolchain, deployed ~13:20Z) bumped @anthropic-ai/claude-agent-sdk 0.2.85→0.3.197 / claude-code 2.1.163→2.1.197, re-validating nothing about the bwrap sandbox"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - operator-reported (Concierge /soleur:go debug stream: every Bash call, incl. `echo test`, failed)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

The hosted Concierge `/soleur:go` agent (app.soleur.ai) could not run **any** Bash tool call for **any** tenant: every invocation — even `echo test` — failed at bwrap sandbox startup with `apply-seccomp: unshare(CLONE_NEWPID|CLONE_NEWNS) after userns: Operation not permitted`. The agent was fully stranded (no git, build, or file operations possible). No customer data was exposed; this is a pure availability outage.

## Status

resolved — root cause identified and fixed in PR #5874; restoration is gated on a post-deploy real-Bash verification (see Action Items).

## Symptom

`apply-seccomp: unshare(CLONE_NEWPID|CLONE_NEWNS) after userns: Operation not permitted` on every sandboxed Bash call. Distinct from the earlier #5733/#5848/#5864 lineage (those were about what the agent could *read inside* a working sandbox); this was bwrap **failing to start at all**.

## Incident Timeline

- **Start time (detected):** ~2026-07-01T13:20Z — #5849 (sonnet-5 toolchain migration) deployed, bumping the agent SDK 0.2.85→0.3.197.
- The strand changed character from the prior read-strand ("not a git repository") to a bwrap-won't-start seccomp EPERM; persisted through the #5864 deploy (14:35Z), which was unrelated.
- **Detection:** operator pasted the stranded `/soleur:go` debug stream ("Still stranded").
- **Diagnosis (no-SSH):** ruled out the 2026-06-04 userns-sysctl-drift class (`BWRAP_USERNS_SYSCTL_CHECK: ok` at 14:48Z); confirmed via `git show` that #5849 bumped the SDK; read the container seccomp profile rules to prove the mechanism.
- **Fix authored + reviewed:** PR #5874 (5-agent review, bit-math verified).
- **Recovery:** pending post-deploy verification.

## Root Cause

The container seccomp profile `apps/web-platform/infra/seccomp-bwrap.json` only allowed `unshare` when the `CLONE_NEWUSER` bit was set (the #1557 rule). The **0.2.85** SDK's sandbox combined all namespaces into one `unshare(CLONE_NEWUSER|CLONE_NEWNS|CLONE_NEWPID)`, so `CLONE_NEWUSER` was always present → allowed. **0.3.197 splits** it into `unshare(CLONE_NEWUSER)` then `unshare(CLONE_NEWPID|CLONE_NEWNS)` (= `0x20020000`, no `CLONE_NEWUSER` bit) → no rule matched → fell through to `defaultAction: SCMP_ACT_ERRNO` → EPERM → sandbox never started. #5849 bumped the SDK across a 0.2→0.3 boundary while re-validating nothing about the bwrap sandbox, and the deploy canary only exercised `bwrap --unshare-pid` (never the real split-unshare), so it shipped green.

## Resolution

PR #5874: two additive `SCMP_ACT_ALLOW` rules for `unshare` of a new mount (`CLONE_NEWNS`) and new pid (`CLONE_NEWPID`) namespace, each AND-requiring `CLONE_NEWUSER` unset (matches only the post-userns namespace unshare; cannot smuggle a userns) and `CAP_SYS_ADMIN`-excluded like the existing rule. Purely additive — no isolation regression. Also wired `docker_seccomp_config` into the merge auto-apply so the profile reaches the host over the CF tunnel (it was never in `deploy_pipeline_fix`'s `depends_on`, so profile changes silently never reached prod).

## Action Items & Follow-ups

| Issue | Item | Owner |
| --- | --- | --- |
| #5875 | Harden the agent sandbox against SDK-bump breakage: faithful split-unshare canary (dark-launched non-blocking first), Sentry-alertable sandbox-start-failure observability (this outage produced zero server-side signal), an SDK-bump-requires-canary guard, and profile-change→redeploy automation. | agent |

## Lessons

- A minor-version SDK bump (0.2→0.3) changed the sandbox's syscall sequence; **any `claude-agent-sdk`/`claude-code` bump must re-validate the bwrap sandbox against the real invocation**, not a synthetic `--unshare-pid` probe.
- The outage was invisible server-side (zero Sentry/Better Stack signal) — the agent-sandbox Bash-tool surface needs a structured, alertable sandbox-start-failure event (tracked in #5875).
- The seccomp profile reaches prod via a Terraform resource (`docker_seccomp_config`) that was not in the merge auto-apply, so profile edits silently never deployed — now wired (#5874).
