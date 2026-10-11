---
title: Agent sandbox shim — fix H6 (fresh procfs refused under docker's masked /proc)
status: draft
owner: engineering
issue: 10032
parent: 9860
brainstorm: knowledge-base/project/brainstorms/2026-10-11-sandbox-proc-shim-h6-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
created: 2026-10-11
---

# Spec: Agent sandbox shim H6 fix

Ref #9860. Closes #10032 only when the faithful canary passes on the deployed image; #9860 stays open until then.

## Problem Statement

Every agent Bash sandbox spawn fails closed in production while the app reports healthy. The shim
(`apps/web-platform/infra/bwrap-shim/bwrap`) splices a mandatory fresh `--proc /proc` to mask host procfs from
tenants (the cross-tenant control from ADR-075/272). Docker's default masked `/proc` refuses that mount
(`bwrap: Can't mount proc on /newroot/proc: Operation not permitted`). The faithful canary is report-only,
so deploys ship the failing image; failed spawns are not reliably logged, so tenant impact is unobservable.

## Goals

- **G1.** The faithful canary (`sdk_probe` and `proc_mask`) passes on the deployed image.
- **G2.** The cross-tenant `/proc` mask stays in force: a sibling pid's `/proc/<pid>/environ` is not readable from a sandbox.
- **G3.** This failure class cannot ship green again: a CI job runs real bwrap under the prod security-opts with docker's default masks.
- **G4.** Failed Bash bwrap spawns become observable in Sentry.
- **G5.** The ADR-075 addendum and the stale comments tell the truth about the mechanism.

## Non-Goals

- Procfs-free argv or rewriting the vendor command string.
- Container topology rework (#9773).
- Least-privilege kernel-stream read for the deploy user and `oom_journal_tail` (separate follow-up issue).
- #9886 (release tag/image provenance) and the flaky cron-egress probe rows.

## Functional Requirements

- **FR1.** Add `--security-opt systempaths=unconfined` to the prod, canary and first-boot `docker run` sites
  (`ci-deploy.sh` canary and prod, `cloud-init.yml`), with a parity pin so the three cannot drift.
- **FR2.** A CI job runs real bwrap with the shim argv in a container started with the same security-opts,
  proving: fresh `--proc` mounts; the pid namespace is the sandbox's own; sibling `environ` is absent. Show the job goes red without the flag.
- **FR3.** Classify a bwrap failure signature on Bash `tool_result` errors (not only session-start exits)
  and mirror it to Sentry (`feature:agent-sandbox`), reachable without the `>2 users/hour` alert threshold.
- **FR4.** Correct the stale `enableWeakerNestedSandbox` comments in `server/agent-runner-sandbox-config.ts`
  (the flag emits `--bind /proc /proc`; it does not skip `--proc`).
- **FR5.** ADR-075 addendum: supersedes the "widening, not a fix" position; bounds the mask-absent interval
  (from about 2026-10-09T04:52Z); states the container-wide scope and AppArmor compensation; does not claim the residual closed.
- **FR6.** CLO attestation under `knowledge-base/legal/audits/` and a new Art. 32 TOM cell; named input to the owed #9723-window Art. 33(5) assessment.

## Technical Requirements

- **TR1.** Validate on the real image (bubblewrap 0.8.0, loaded `soleur-bwrap` AppArmor profile), not only local bwrap 0.12.0 with AppArmor unconfined.
- **TR2.** If the faithful canary still fails after the flag, treat H7 (AppArmor) as live and stop; do not widen further.
- **TR3.** Resolve the vendored gate `enableWeakerNestedSandbox:Gd()&&u5()?!1:...` before relying on the flag state in prod.
- **TR4.** Fixtures use bwrap's real stderr channel and docker's real masked-path behavior (see learnings 2026-10-11 and 2026-10-10 on fixtures that cannot fail).
- **TR5.** Tests and mutation batteries run in an allocated sandbox (`scripts/soleur-sandbox.sh`); assertion floors measured on the live tree.
- **TR6.** Any production write (merge, deploy dispatch, Doppler write) needs explicit operator go-ahead.
