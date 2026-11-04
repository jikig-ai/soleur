---
title: Decision challenges — feat-one-shot-10390-ci-hygiene-batch
date: 2026-11-04
---

# Decision Challenges

Headless pipeline run (one-shot planning subagent — no operator TTY, no
Task-spawn capability). Rulings that would normally go to a CTO/operator
gate are recorded here per technical-ruling-delegation.md and surfaced at
ship time.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| `webhook.service` + `vector.service` disposition under the #10078 calibration (condition-skip vs. keep designed-loud) | technical | pending - assumed: keep designed-loud. `/etc/default/webhook-deploy` is written unconditionally by runcmd (~:441), so absence is a real fault not benign ordering; both units are `Type=simple`/`Restart=on-failure` boot-persistent services where a condition-skip never self-heals and converts transient fault into a permanently dead deploy channel/log shipper; `webhook.service`'s disabled start limit is already pinned deliberate (`infra-config-apply.test.sh` B5.3). Mirrors the `inngest-redis` designed-loud precedent. |
| New admission environment name `release-publish` | taste | pending - assumed: `release-publish`. Reviewer-less, secrets-free, main-only policy; gating reusable-release `release` + bootstrap `build` jobs. |
| Marker-lint `lint-gh-dedupe-shape.py` included in scope (the issue asks only to normalize/document) | technical | pending - assumed: include. #9659 exists because the class re-grew past #9612's enumeration; document-only fixes have no census backstop (ADR-166: docs-only enforcement of a shell-semantics invariant does not work). |
| Split vs. single PR (plan thresholds crossed: ~34 files, ~900 lines) | operator (scope) | pending - assumed: single PR per the one-shot batch convention (#12064), three disjoint per-workstream commits; the recorded seam for a forced split is the issue boundary (#9659 \| #10078 \| #8780). |
