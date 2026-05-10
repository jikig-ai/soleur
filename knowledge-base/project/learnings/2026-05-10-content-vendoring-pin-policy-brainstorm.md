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

## Plan Session Insights (round 2 — 2026-05-10 plan + 5-agent review)

The plan session for #3517 surfaced five further design-pattern insights worth compounding:

### 6. 5-agent plan-review found load-bearing issues 3-agent review missed

The `soleur:plan-review` skill spec invokes 3 reviewers (DHH / Kieran / code-simplicity). Adding **architecture-strategist** and **spec-flow-analyzer** to the parallel batch caught issues none of the 3 surfaced:

- **Spec-flow-analyzer P1.1:** banner emitted to stderr is invisible to agent runtimes — the entire user-protection thesis collapses if banner doesn't reach stdout.
- **Spec-flow-analyzer P1.2:** drift detection compares blob SHAs without upgrade-vs-downgrade directionality — auto-PR would *downgrade* content on upstream rollback.
- **Architecture-strategist P1:** lefthook glob and NOTICE `lifted-files` are dual sources of truth — a 6th file added to NOTICE without lefthook update escapes commit-time integrity entirely.

**Pattern:** when threshold is `single-user incident` (per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`), plan-review should grow optional architecture-strategist + spec-flow-analyzer slots. The 3-agent baseline catches overengineering and convention drift; the 5-agent panel catches blast-radius and flow gaps.

### 7. Operator-protection signals from CLI tools must emit to stdout, not stderr

Agent runtimes (Claude Code skill harness, MCP servers, the Bash tool's output capture) frequently surface only stdout in the agent's chat context. Stderr is swallowed.

**Pattern:** any CLI tool emitting an operator-protection signal (warning banner, posture-fail line, deprecation notice, staleness alert) MUST emit to **stdout**, not stderr. Reserve stderr for diagnostic noise the agent doesn't need to act on.

The original spec FR6 specified "prepend to all output" without disambiguating; the existing `gdpr-gate.sh` writes everything to stderr (`>&2`); the runtime banner inherited that convention by default. Spec-flow-analyzer caught the regression before merge.

### 8. Sourcing bash helpers under `set -euo pipefail` aborts the caller

`gdpr-gate.sh` sets `set -euo pipefail` (line 18). The original plan proposed `source notice-frontmatter.sh` to load the parser. If the parser uses `set -e` internally (which AGENTS.md/AC3 mandates) and any function fails — missing frontmatter, malformed YAML, parser deleted — the **caller** aborts via inherited `set -e`, violating the gate's always-exit-0 advisory contract.

**Pattern:** subshell exec (`x=$(bash helper.sh subcommand 2>/dev/null || echo "fallback")`) is the safe primitive for non-trivial helpers in `set -e` callers. `source` is for tight, no-fail utility functions (e.g., `incidents.sh`).

### 9. Drift detectors comparing remote vs local versions need directionality

A blob-SHA-comparing drift detector that flags any non-equal pair will auto-PR a *downgrade* when upstream force-pushes / reverts to an earlier commit. The remediation is `git merge-base --is-ancestor <upstream-new> <our-pin>` — exit 0 means upstream is now older, which is rollback, not drift.

**Pattern:** any drift detector comparing remote-current vs locally-pinned versions must distinguish (a) upstream-newer (legitimate drift, auto-PR candidate), (b) upstream-older (rollback, human-review-only), (c) upstream-renamed (404 + redirect resolution), (d) upstream-deleted/archived (fork-or-drop ADR).

### 10. Phase 0.25 roadmap-freshness shortcut held up; reinforces #3525

The brainstorm session soft-skipped Phase 0.25 (roadmap-freshness reconciliation) because the topic was governance-only. The plan session followed suit. No issues surfaced. The deferred edit at #3525 (early-exit clause for non-roadmap-affecting topics) remains the right call.

## Cross-References

- Brainstorm document: `knowledge-base/project/brainstorms/2026-05-10-gosprinto-pin-policy-brainstorm.md`
- Plan: `knowledge-base/project/plans/2026-05-10-feat-content-vendoring-pin-policy-plan.md`
- Tasks: `knowledge-base/project/specs/feat-gosprinto-pin-policy/tasks.md`
- Spec: `knowledge-base/project/specs/feat-gosprinto-pin-policy/spec.md`
- Tracking issue: #3517
- Draft PR: #3521
- Source PR (the lift): #3501
- Scope-out issues filed during plan-review: #3526 (vendor-diff-scan defer), #3527 (ADR defer), #3528 (compliance/critical dilution), #3529 (vendor-pins consolidation)
- Prior brainstorm (where Q3 was deferred): `knowledge-base/project/brainstorms/2026-05-09-gdpr-gate-skill-brainstorm.md`
- Prior learning (vendor-branded skill evaluation): `knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md`
- Related learning (Explore agent false-negative class): `knowledge-base/project/learnings/2026-04-17-brainstorm-verify-existing-artifacts-and-mount-sites.md`
- Hard rule applied: `hr-weigh-every-decision-against-target-user-impact` (set `USER_BRAND_CRITICAL=true` from `pii`/`user data` keyword match)
