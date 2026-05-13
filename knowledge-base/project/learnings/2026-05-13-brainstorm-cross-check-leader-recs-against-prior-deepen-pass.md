---
date: 2026-05-13
category: process
related_issues: ["#3712", "#3704", "#2207", "#3706", "#3723"]
related_skills:
  - soleur:brainstorm
  - soleur:plan
  - soleur:deepen-plan
tags: [brainstorm, multi-agent, decision-archaeology, bundle-disposition]
---

# Cross-check leader recommendations against prior deepen-pass decisions before accepting them

## Problem

During the 2026-05-13 unified-ci-deploy-stall-hardening brainstorm, the CTO subagent recommended shipping `systemd-run --scope --property=TimeoutSec=600` in `hooks.json.tmpl` as a belt-and-suspenders second layer on top of `ci-deploy-wrapper.sh` (the `timeout(1)` primitive shipped 24h earlier in PR #3706). The recommendation included a detailed gap table showing what `systemd-run --scope` catches that the bash TERM trap doesn't (cgroup-kill of orphan grandchildren, bash-segfault recovery, OOM-killer scenarios).

In parallel, the repo-research-analyst subagent surfaced that the **#3706 deepen-pass had explicitly rejected `systemd-run --scope`** for documented reasons (plan §49-59, §190): `webhook.service` runs as `User=deploy` (unprivileged); `systemd-run --system` requires polkit, which cannot prompt in a non-TTY context and would *block indefinitely — making the original stall worse*. The deepen-pass had instead chosen `timeout(1)` for identical SIGTERM→SIGKILL semantic with zero permission elevation.

The CTO subagent's prompt did NOT include the plan path as required reading. It assessed from the issue bodies + adjacent code only. The recommendation was internally coherent but contradicted a settled architectural decision in a plan it had not read.

## Solution

When spawning domain-leader subagents during brainstorm Phase 0.5, **always include the path to any in-flight or recently-merged plan/spec for the same problem space in the leader's read-list**, not just the issue bodies.

Concretely, for this session:

- Leader prompts MUST include `knowledge-base/project/plans/<latest>-<topic>-plan.md` when an adjacent merged PR is referenced in the feature description.
- Repo-research-analyst MUST be spawned in parallel with leaders (it was, and that's what caught the conflict).
- The brainstorm parent MUST reconcile leader recommendations against repo-research findings before presenting approach options to the operator. **Repo-research is load-bearing as the deepen-pass-decision-archaeologist** when leaders aren't briefed on the prior plan.

The reconciliation that actually fired in this session:
1. CTO recommended `systemd-run --scope` second layer.
2. Repo-research independently surfaced the deepen-pass §49-59 systemd-run rejection.
3. Brainstorm parent verified by reading `webhook.service` (`User=deploy`) and the plan §49-59 directly.
4. Recommendation rejected at brainstorm time, not at plan time (which would have been more expensive — plan-time pivot back to brainstorm).

## Key Insight

Domain leaders reason strategically from the description + adjacent code and may prescribe substrates that were already considered and rejected in a recent deepen-pass. The cost of catching this at brainstorm Phase 0.5 (one extra grep / file read by the orchestrator) is trivial; the cost of catching it at plan time or PR review is days.

This is a specialization of the existing brainstorm-skill heuristic ("Cross-checking leader infra/substrate claims against repo-research"). The general rule is: **leader recommendations are hypotheses, not authority. Repo-research and prior plans are the load-bearing verification.** When a leader prescribes a specific substrate, primitive, or design (named function, named flag, named systemd primitive), the orchestrator MUST verify against the most recent plan/spec for the same problem before weaving the recommendation into the synthesis.

## Bundle Disposition Pattern

A second pattern this session demonstrated cleanly:

When the brainstorm scope spans 3+ related open issues sharing one failure mode, **do NOT create a new umbrella issue**. The brainstorm document + spec.md ARE the bundle's single source of truth. Append a "Bundled scoping" section to each referenced issue's body (via `gh issue edit --body-file -`, not a comment) linking:

- The brainstorm path on the feature branch
- The spec.md path on the feature branch
- Any new artifacts created by the bundle (e.g., compliance learning)
- The feature branch name
- The draft PR number
- Any follow-up issues spawned (deferred scope-outs)
- A per-issue disposition table

The body-append (vs. comment) is correct because downstream tooling — `gh issue list --search`, the Rule Metrics aggregator, the postmerge / drain-labeled-backlog skills — reads issue bodies as authoritative state. A comment ages out of view; the body is canonical.

This pattern is already documented in the brainstorm skill's Phase 3.6 step 1 ("Multiple OPEN issues (bundle)"), but the body-vs-comment rationale wasn't explicit. Adding it here as durable reference.

## Session Errors

1. **`git rev-parse --show-toplevel` failed from bare-repo root.**
   Recovery: switched to explicit `$PWD`-relative paths (`./plugins/soleur/skills/...`) for script invocation, and re-emitted telemetry from inside the worktree after `cd`.
   **Prevention:** brainstorm Phase 0.1 telemetry emit (`source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh"`) assumes a worktree. From a bare root, this command exits 128. The brainstorm Phase 0 branch-safety check already creates the worktree before Phase 0.1 fires in *most* cases, but defense-in-depth: emit telemetry only after the `cd .worktrees/feat-<name>` step.

2. **`gh issue create --label "type/feat"` rejected — actual label is `type/feature`.**
   Recovery: ran `gh label list | grep "^type/"`, corrected to `type/feature`, re-issued.
   **Prevention:** `gh label list` verification is already required by `/soleur:go` Step 2 for `drain-labeled-backlog`. The same verification should apply to ANY `gh issue create --label` call across all skills. Worth a one-line addition to the brainstorm skill's Phase 3.6 step 2 ("verify each `--label` value against `gh label list` before issue create").

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-13-unified-ci-deploy-stall-hardening-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-unified-ci-deploy-stall-hardening/spec.md`
- Compliance learning (cross-product): `knowledge-base/project/learnings/compliance/2026-05-13-pipeline-reliability-as-gdpr-art32-control.md`
- #3706 plan (the deepen-pass that rejected systemd-run): `knowledge-base/project/plans/2026-05-12-fix-harden-web-platform-release-pipeline-3704-plan.md`
- Issues bundled: #3712, #3704, #2207
- Follow-up: #3723 (Hetzner self-hosted runner)
