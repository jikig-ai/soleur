---
date: 2026-05-10
category: best-practices
problem_type: brainstorm_process
component: brainstorm
severity: medium
tags: [brainstorm-process, learnings-researcher, vendor-pin, freshness-pattern, runtime-vs-cron, content-vendoring, agent-research-quality]
related_artifacts:
  - knowledge-base/project/brainstorms/2026-05-10-gosprinto-pin-policy-brainstorm.md
  - knowledge-base/project/specs/feat-gosprinto-pin-policy/spec.md
  - knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md
  - https://github.com/jikig-ai/soleur/issues/3517
  - https://github.com/jikig-ai/soleur/pull/3521
synced_to: [brainstorm, learnings-researcher]
---

# Content-Vendoring Pin Policy — Three Process Insights from the Brainstorm

## Problem

The brainstorm for issue #3517 (vendor-pin policy follow-up to the gosprinto/compliance-skills lift) surfaced three distinct process insights that compound future work. Capturing them together because they share the same session and reinforce each other.

1. The **load-bearing layer** when a cron-driven freshness obligation exists is the runtime check, not the cron itself.
2. The **learnings-researcher agent** can return false-negatives on existing learning files; the brainstorm skill has no sanity-check anchor today.
3. The **"look for the second future case"** framing during repo research prevented writing a gosprinto-specific policy that would have needed rewriting on the second lift.

## Solution

### Insight 1: Cron + runtime check — the runtime is load-bearing

When a workflow promises a freshness SLO ("rules updated within N days of upstream change"), the temptation is to ship a cron + auto-PR pipeline and call it done. CPO surfaced what neither CTO nor CLO had: the cron can fail silently — workflow disabled, GitHub Actions outage, PR queued during a busy week, maintainer on PTO. The operator-visible failure is the gate emitting authoritative narrative claims based on stale rules. The **runtime check** (read NOTICE `last-verified` date on every invocation; degrade to advisory-only banner past threshold) is the layer that fails loudly during the actual invocation.

Same philosophy as `cq-silent-fallback-must-mirror-to-sentry`: never let a degraded condition pass silently. Generalizes to any cron-driven freshness obligation (rule sets, vendor SHAs, license caches, geo-IP DBs, certificate revocation lists).

**Pattern (for future use):**

- Cron = convenience layer. Runs in the happy path.
- Runtime check = safety net. Runs every invocation, fails loud when convenience layer fell behind.
- The two layers don't depend on each other — that's the point.

### Insight 2: Learnings-researcher false negatives need a sanity-check anchor

The `learnings-researcher` agent reported that `2026-05-09-evaluating-vendor-branded-claude-code-skills.md` "does not exist in the repo" while writing its conclusions. The file is present (8711 bytes, on main since merge of #3501, in the worktree at `knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md`). Verified by direct `ls -la` and `git log --oneline main -- <path>` showing the merge commit.

Likely cause: the agent's `find` or grep was scoped against a path that didn't reach the file (bare-repo gotcha per `hr-when-in-a-worktree-never-read-from-bare`, OR a wrong base path passed to `find`). The brainstorm proceeded only because I had read the file directly in Phase 1.1 before spawning the agent — without that, the brainstorm would have advanced under a false premise that no prior vendor-evaluation learning existed.

The `2026-04-17-brainstorm-verify-existing-artifacts-and-mount-sites.md` learning warned about a related class (Explore agent reporting "not confirmed to be mounted" on a feature that was mounted). Same root: agent search scope mismatched the actual file location, and the brainstorm-side has no sanity-check anchor to detect it.

### Insight 3: "Look for the second future case" prevented a gosprinto-only doc

The repo-research-analyst correctly identified that the gdpr-gate `NOTICE` is the **first content-vendor pin in the repo** (the plugin-level `plugins/soleur/NOTICE` is ideas-only, no SHA pinning). It then pushed for writing the policy content-vendoring-general — registry-table-driven, not gosprinto-specific.

That framing collapses the cost of the second future lift to "add a registry row," and prevents a gosprinto-specific doc that would have to be rewritten when the next case lands. Same pattern as the spec-vs-component split in `spec-templates`: write the shape once, instantiate per-case.

**Heuristic (for future brainstorms):** when a feature is the first instance of a category, ask "what does the second instance look like?" If the proposed design needs rewriting for the second case, generalize now.

## Key Insights

1. **Cron freshness pipelines need a runtime safety net.** The cron + auto-PR is the convenience layer; the runtime check is what protects users when the cron fails. Architect both layers; do not collapse them.

2. **Learnings-researcher (and Explore-class research agents) can false-negative on existing files.** The brainstorm skill should pass the agent a known-existing learning path as a sanity-check anchor, OR the agent itself should `ls -la` / `test -f` candidate paths before asserting non-existence.

3. **First-instance-of-category triggers a generalization gate.** If the second future case would need rewriting, generalize the design now and instantiate per-case via a registry table or schema.

4. **Domain leaders disagree productively when prompted with a phasing question.** CTO (build-now, low cost) vs CPO (defer to Phase 4 exit, don't promise SLOs you won't honor) was a genuine tension; surfacing it to the user gave them a clean choice rather than a forced consensus. The staleness-gate idea only emerged because CPO was forced to argue against CTO's "ship the lot."

5. **MIT freezing is the lowest-attribution-risk option, not a defensible default.** CLO's framing: silent incorporation of upstream patches without bumping the NOTICE SHA is the actual breach risk, because attribution is to bytes that no longer match shipped. Freezing is not "lazy" — it's the lowest-risk legal posture. The risk lives in (a) re-vendor without SHA bump, (b) operator trust on stale advisory output.

## Session Errors

1. **Learnings-researcher false negative on existing file.** — Recovery: caught via direct Read in Phase 1.1 before agent claim landed. — Prevention: brainstorm Phase 1.1 should pass the agent a known-existing learning path as a sanity-check anchor, OR the learnings-researcher agent should `ls -la` / `test -f` candidate paths before asserting non-existence; same root pattern as `2026-04-17-brainstorm-verify-existing-artifacts-and-mount-sites.md`.

2. **Phase 0.25 roadmap freshness — soft skip without per-spec verification.** — Recovery: none needed; the brainstorm topic was governance-only and didn't depend on roadmap phase-table freshness. — Prevention: brainstorm Phase 0.25 could grow either a "trust last_updated within N days" gate, or an explicit "skip if topic is not roadmap-affecting" exit, so the shortcut is legitimate-by-spec rather than judgment-call.

## Prevention

- **Brainstorm Phase 1.1:** Add a sanity-check anchor to the learnings-researcher prompt — pass at least one known-existing learning path; if the agent reports it absent, re-prompt with absolute paths. Pattern: `Verify <path> exists via 'test -f'; if not, your search scope is wrong — re-scope before reporting findings.`

- **Brainstorm Phase 0.25:** Add an early exit: "If `last_updated` is within 7 days AND the brainstorm topic is in [governance, infra, ops, ci, content-vendoring, internal-tooling], skip the milestone reconciliation." This makes the shortcut legitimate-by-spec.

- **Cron-freshness designs:** Add a checklist item to spec-templates: "Does this design depend on a cron's success? If yes, what runtime check fails loud when the cron fell behind?"

- **First-instance-of-category gate:** When a brainstorm spec proposes a registry-table-shaped artifact (NOTICE, ADR registry, vendor list), add a Sharp Edges item: "If this is the first instance, write the policy general; instantiate per-case via the table."

## Cross-References

- Brainstorm document: `knowledge-base/project/brainstorms/2026-05-10-gosprinto-pin-policy-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-gosprinto-pin-policy/spec.md`
- Tracking issue: #3517
- Draft PR: #3521
- Source PR (the lift): #3501
- Prior brainstorm (where Q3 was deferred): `knowledge-base/project/brainstorms/2026-05-09-gdpr-gate-skill-brainstorm.md`
- Prior learning (vendor-branded skill evaluation): `knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md`
- Related learning (Explore agent false-negative class): `knowledge-base/project/learnings/2026-04-17-brainstorm-verify-existing-artifacts-and-mount-sites.md`
- Hard rule applied: `hr-weigh-every-decision-against-target-user-impact` (set `USER_BRAND_CRITICAL=true` from `pii`/`user data` keyword match)
