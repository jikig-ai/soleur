---
title: Human-in-the-loop infra steps are an automation bug, not a runbook step
date: 2026-07-04
category: workflow-patterns
tags: [workflow-patterns, ci-sentinel, actor-imperative-cooccurrence, no-ssh, hr-no-ssh-fallback-in-runbooks, autonomous-orchestration, 5933]
---

# Learning: Human-in-the-loop infra steps are an automation bug, not a runbook step

## Problem

ADR-068's multi-host GA line was designed with **human-in-the-loop ops steps**: an
operator maintenance-window `terraform apply`, a private-net remote-shell verify,
and a "book a window / decide before the window" human decision. These were
carried in the multi-host blue-green plan and the moved-block-wedge-cutover
runbook as if they were legitimate runbook steps.

They are not. **Soleur users are non-technical and act only through the web app /
CI.** A step that says "the operator SSHs in and runs `terraform apply`" is an
automation bug — there is no human who can (or should) run it. The existing hard
rules (`hr-exhaust-all-automated-options-before`,
`hr-fresh-host-provisioning-reachable-from-terraform-apply`,
`hr-no-ssh-fallback-in-runbooks`) already said "don't", but they had no
enforcement teeth for the *docs* class: a plan or runbook could still prescribe a
human infra step and pass CI.

## Solution

Two moves, in order (the lint is the producer, the docs are its consumers):

1. **Autonomous orchestration substrate.** The apply runs through a
   `workflow_dispatch` path on the existing R2-concurrency-serialized workflow
   (never operator-local), fans out the deploy host-side over the private net, and
   verifies the result off-host with no SSH (the terraform apply's own
   created-resources output + the serving host's deploy-status `reason`). The one
   irreducibly human touch is a **menu acknowledgement** (`gh workflow run … -f
   apply_target=warm-standby`), not an authored prod-write.

2. **An actor+imperative CO-OCCURRENCE lint that fails the class**
   (`scripts/lint-infra-no-human-steps.py`, wired into `ci.yml` + `lefthook.yml`,
   tagged `[hook-enforced:]` on `hr-no-ssh-fallback-in-runbooks`). It flags a line
   only when a **human-actor** token (`operator`, `you`, `SSH into`, `by hand`,
   `manually`, …) AND an **infra-imperative** token (`terraform/tofu apply`,
   `reboot`, `attach the volume`, `verify … private … IP`, `-target … apply`)
   co-occur. It honors `<!-- lint-infra-ignore -->` regions (so the
   de-manualization plan and the retained *deferred-orchestrator* prose don't
   red-line themselves), ignores fenced/backtick code, carves out `## Resolved` /
   `Last-resort diagnosis` sections and `**/archive/**`, and runs in changed-files
   mode to grandfather pre-existing docs.

## Key Insight

A **bare-token denylist cannot separate "a *human* runs `terraform apply`" (a bug)
from "the *orchestrator* runs `terraform apply`" (the fix).** The unit of the
violation is not the infra verb — it is the *pairing of a human actor with an
infra imperative*. Denylisting `terraform apply` outright would red-line the very
plan that removes the human step, plus every legitimate description of the
autonomous path. Modeling the co-occurrence is what makes the gate precise enough
to leave on.

Two supporting insights:

- **Prose is not the enforcement; the lint is.** `AGENTS.core.md` sat at
  22976/23000 bytes (24 B headroom). A net-new hard rule could not land. The right
  move was to strengthen `hr-no-ssh-fallback-in-runbooks` *in place* (add the class
  clause + the `[hook-enforced:]` tag, fund it by tightening the existing prose)
  and let the CI lint carry the teeth. Guidance text is a reminder; the gate is
  the contract.

- **Grandfather with changed-files mode, not by weakening the rule.** A full scan
  of the corpus surfaces ~60 pre-existing human-step lines across ~33 legacy docs.
  Fixing them all in this PR would be unbounded scope; deleting the rule to make CI
  green would be worse. Changed-files mode (diff vs merge base + new untracked
  docs) fails only what a PR *touches*, so the class stops growing immediately and
  the backlog drains as docs are edited for other reasons.

## Tags

- category: workflow-patterns
- related-rules: hr-no-ssh-fallback-in-runbooks, hr-exhaust-all-automated-options-before, hr-fresh-host-provisioning-reachable-from-terraform-apply
- related-learnings: 2026-05-15-ci-sentinel-paren-safety (paren-safe sentinels), 2026-03-21-lefthook-gobwas-glob-double-star (dual-glob)
- refs: #5933
