---
title: 'Tagged-Build Workflows Need an Initial Tag Push (companion to `hr-tagged-build-workflow-needs-initial-tag-push`)'
date: 2026-05-20
category: engineering
tags: [hr, tagged, build, workflow, needs, initial, tag, push, why, how]
back_link: knowledge-base/project/learnings/2026-05-18-plan-baked-in-operator-ssh-violated-iac-rule.md
companion_rule: hr-tagged-build-workflow-needs-initial-tag-push
related: [hr-all-infrastructure-provisioning-servers, hr-fresh-host-provisioning-reachable-from-terraform-apply]
trigger_pr: 3973
type: best-practice
---

# Tagged-Build Workflows Need an Initial Tag Push (companion to `hr-tagged-build-workflow-needs-initial-tag-push`)

The hard rule body in `AGENTS.core.md` is trimmed to a one-liner pointing at this file.

## The rule (canonical short form)

> Any PR adding a GHA workflow gated on `on.push.tags` MUST push the initial `vX.0.0` tag in the same PR (or via a sibling workflow firing on merge to main). Tag-triggered build with no initial tag is dead code — the OCI image never exists; deploys fail silently.

## Why

In PR-A #3973 (PR-F substrate IaC layer), a workflow `.github/workflows/build-inngest-bootstrap-image.yml` shipped with `on: push: tags: ['vinngest-v*']`. The workflow was technically correct, but no `vinngest-v1.0.0` tag had ever been pushed — so the OCI image at `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0` did not exist. Every subsequent piece of infra that referenced the image (deploy webhook, cloud-init runcmd in #4118) failed to find it. The failure was silent at merge time and only surfaced when the operator triggered the deploy webhook days later and got a `manifest unknown` error from GHCR.

The systemic class is "build trigger gated on a state nobody created." Tag-push workflows, scheduled workflows that depend on a state machine (e.g., a labeled issue existing), and merge-to-main workflows that depend on a sibling label being applied first all share this shape. They look fine in `gh workflow list` (status: active), they pass any plan-time linter (the YAML is valid), and they fail loudly only at runtime when something downstream tries to pull the artifact they were supposed to produce.

## How to apply

At `/plan` Phase 2, when the plan adds **any** GHA workflow with `on.push.tags` or `on: workflow_dispatch` that produces a versioned artifact, the plan's Phase 7 (ship) section MUST list "push initial `vX.0.0` tag" as an explicit ship step — NOT as a "follow-through" or post-merge operator action. Two acceptable shapes:

1. **Same-PR shape (preferred).** The PR's ship phase pushes the initial tag from the merger's local shell (`git tag vX.0.0 && git push origin vX.0.0`) immediately after the squash-merge lands on main. Document the exact tag value in the plan.
2. **Sibling-workflow shape.** A separate `.github/workflows/bootstrap-initial-tag.yml` triggered `on: pull_request.types: [closed]` pushes the initial tag automatically when the parent PR merges. Used when multiple consumers need the tag and human-driven timing is fragile.

A "follow-through issue" (file a tracker, do it later) is NOT acceptable. The whole point of the rule is that the artifact-build path must be exercised at-merge or never.

## Cross-references

- Trigger PR: [#3973](https://github.com/jikig-ai/soleur/pull/3973) — PR-F IaC bootstrap layer.
- Sibling rule: `hr-all-infrastructure-provisioning-servers` — covers the post-merge operator step constraint that motivated this rule's same-PR preference.
- Sibling rule: `hr-fresh-host-provisioning-reachable-from-terraform-apply` (added in #4118) — closes the other half of the dead-code surface (image-exists vs install-fires-at-provision).
- Companion learning (precursor): `knowledge-base/project/learnings/2026-05-18-plan-baked-in-operator-ssh-violated-iac-rule.md` — the original framing of "IaC means IaC; no manual operator clicks in the install path" that this rule extends to the workflow-trigger surface.

## Re-evaluation

This rule retires when the project's `release-please`-style automation (or equivalent) becomes the canonical way to push first tags, making the manual ship step mechanical. Until then the explicit Phase 7 declaration is what makes the gap visible at plan review.
