---
title: 'Fresh-Host Provisioning Reachable from `terraform apply` (companion to `hr-fresh-host-provisioning-reachable-from-terraform-apply`)'
date: 2026-05-20
category: engineering
tags: [hr, fresh, host, iac]
companion_rule: hr-fresh-host-provisioning-reachable-from-terraform-apply
related: [hr-tagged-build-workflow-needs-initial-tag-push, hr-all-infrastructure-provisioning-servers]
trigger_issue: 4017
trigger_pr: 4118
type: best-practice
---

# Fresh-Host Provisioning Reachable from `terraform apply` (companion to `hr-fresh-host-provisioning-reachable-from-terraform-apply`)

The hard rule body in `AGENTS.core.md` is trimmed to a one-liner pointing here.

## The rule (canonical short form)

> Every production service in `apps/<app>/infra/` MUST come up on a one-shot `terraform apply` against empty state with zero operator post-apply actions. If install requires a webhook trigger, tag push, or manual click, the install path MUST ALSO be embedded in `cloud-init.yml`'s `runcmd:` block (or an equivalent first-boot bootstrap).

`[skill-enforced: plan Phase 2.8 + iac-plan-write-guard.sh]`

## Why

In PR-F (#3940) Soleur shipped a self-hosted Inngest server. The install path went through a tag-triggered OCI build (`.github/workflows/build-inngest-bootstrap-image.yml` firing on `vinngest-v*` tag push), then a manually-invoked deploy webhook (`POST /deploy inngest <image> <tag>`) that ran `inngest-bootstrap.sh` on the host. This worked for the operator's first manual mint, BUT — `cloud-init` never ran the bootstrap. The cloud-init.yml file knew nothing about Inngest. As a result:

- The currently-running prod VM had Inngest because the operator ran the webhook by hand once.
- A fresh `terraform apply` against an empty Hetzner project (the path a new Soleur user clones-and-deploys would take) produced a half-installed substrate: cloud-init started the web-platform container, but no Inngest server was listening on `:8288`, so every cron registered via the Inngest SDK silently failed to register.
- The downstream blast radius (#4017's cascade, ~2-day silent gap) included missed daily-priorities cron, missed scheduled-follow-through, and a Better Stack heartbeat that flipped down without alerting anyone because the heartbeat itself depended on the never-started service.

The systemic class is: any infra primitive whose install path requires an out-of-band step (webhook click, tag push, dashboard "install" button, `terraform apply` of a sibling root) is a brand-survival liability the moment Soleur acquires a non-operator user. The first user who runs `terraform destroy && terraform apply` to recover from any incident discovers the gap; the gap takes hours-to-days to root-cause; their conclusion is "Soleur's self-hosted X doesn't work."

This rule closes that surface by requiring the install path to ALSO be embedded in cloud-init, so the first boot of any fresh VM produces a complete, functioning substrate without operator action.

## How to apply

At `/plan` Phase 2.8 (the IaC routing gate), for any new service or daemon being added to `apps/<app>/infra/`, the plan MUST answer this question:

> "If `terraform apply` runs against an empty state with no operator on the keyboard, does this service end up running?"

Acceptable answers:

- **Yes, the service is installed and started by cloud-init's `runcmd:` block.** Plan includes the runcmd entry; review verifies it.
- **Yes, the service is a container image started by an existing `docker run` line in cloud-init.** Plan documents the line; review verifies the image tag is pinned.
- **Yes, the service is part of a base Hetzner image / Hetzner Marketplace appliance.** Plan documents the image source.

Unacceptable answers:

- "Yes, after the operator pushes a tag and clicks the deploy webhook." → BLOCK the plan; require cloud-init coverage.
- "Yes, after the operator SSHes in and runs `<script>`." → BLOCK the plan; this also violates `hr-all-infrastructure-provisioning-servers`.
- "Yes, after a follow-up issue tracks the install step." → BLOCK; follow-up issues for fresh-host install are an anti-pattern (the gap stays open for the duration of the follow-up).

## Sibling rules

- `hr-tagged-build-workflow-needs-initial-tag-push` — ensures the OCI image the cloud-init runcmd block tries to pull actually exists. THIS rule ensures the runcmd block actually exists.
- `hr-all-infrastructure-provisioning-servers` — covers the post-merge operator-SSH surface. THIS rule covers the first-boot-fresh-host surface.
- `hr-multi-step-post-merge-bootstrap-script` — when an operator step IS required (genuinely operator-only credentials), bundle into one script. THIS rule says: prefer NO operator step over a bundled one when possible.

## Cross-references

- Trigger issue: [#4017](https://github.com/jikig-ai/soleur/issues/4017) — substrate cascade.
- Originating PR: [#4118](https://github.com/jikig-ai/soleur/issues/4118) — Inngest cloud-init Tier 1 + this rule.
- Tier 2 follow-up: [#4126](https://github.com/jikig-ai/soleur/issues/4126) — weekly disaster-recovery test that operationally enforces this rule by exercising the fresh-apply path.

## Re-evaluation

The rule retires when an automated `terraform destroy && terraform apply` test runs weekly in CI (see #4126) AND has gone ≥90 days with zero "fresh-apply gap" findings. Until then the plan-time gate is the load-bearing enforcement.
