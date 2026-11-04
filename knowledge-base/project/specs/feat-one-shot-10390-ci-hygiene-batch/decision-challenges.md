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
| `webhook.service` + `vector.service` disposition under the #10078 calibration (condition-skip vs. keep designed-loud) | technical | Ruled by CTO agent, 2026-11-04: keep designed-loud (comment + negative pin), no `ConditionPathExists=` for either unit - `/etc/default/webhook-deploy` is written unconditionally (cloud-init.yml:441) before both units' first starts (:604, end-of-cloud-init), so absence is always a real fault already covered by the on_err fatal trap; `Type=simple` persistent services never re-evaluate a skipped condition, converting a transient fault into a permanently dead deploy channel/log shipper with no self-heal and weaker detection; B5.3 pins the crash-loop as the designed signal. Dissent: weak, vector only — a dead vector cannot ship its own crash-loop rows, so its detection advantage is nil (ingest-side darkness is the signal either way); ruling holds because Restart=on-failure self-heals on file appearance and a skip does not. |
| New admission environment name `release-publish` | taste | Ruled by CTO agent, 2026-11-04: `release-publish` - matches the established domain-action environment naming convention (infra-privileged, inngest-config-signing); no collision; admission-only property carried by .tf header + DP-11 F8 guard as conventions require. Dissent: weak — `release-admission` is arguably more honest about the admission-only, secrets-free design and an acceptable substitute; weighed below convention consistency. |
| Marker-lint `lint-gh-dedupe-shape.py` included in scope (the issue asks only to normalize/document) | technical | Ruled by CTO agent, 2026-11-04: include the ratchet (`scripts/lint-gh-dedupe-shape.py` + `.test.sh` + suite registration) alongside the normalization - no existing lint covers the class (errexit-capture and argv-arg verified disjoint); census measured 76 hits across **19** workflow files (plan said 18; `scheduled-rehearsal-skip-monitor.yml` is the extra — classify it too), so the class already re-grew once past #9612's enumeration and ADR-166 documents docs-only enforcement failing. |
| Split vs. single PR (plan thresholds crossed: ~34 files, ~900 lines) | technical | Ruled by CTO agent, 2026-11-04: single PR #12064 with three per-workstream commits - workstream file sets verified disjoint at file level (apply-web-platform-infra.yml is NOT in the dedupe census; web-platform-release.yml is B-only), no ordering dependency; batch convention established (#11559/#11824/#11994); issue-boundary seam remains available if review or a regression forces it. Dissent: weak — single PR's revert unit is coarser; mitigated by per-workstream commits enabling partial `git revert <commit>`. |
