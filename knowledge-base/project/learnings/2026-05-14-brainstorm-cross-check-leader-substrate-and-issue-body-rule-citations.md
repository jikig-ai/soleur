---
title: Brainstorm — cross-check leader substrate recommendations against infra files AND cross-check issue-body hard-rule citations verbatim
date: 2026-05-14
category: workflow-issues
tags:
  - brainstorm
  - leader-substrate-verification
  - hard-rule-citation-drift
  - issue-body-staleness
  - prior-decision-recovery
  - cf-tunnel-749
issue: 3723
sibling_issue: 3756
brainstorm: knowledge-base/project/brainstorms/2026-05-14-soleur-managed-deploy-substrate-multi-tenant-brainstorm.md
spec: knowledge-base/project/specs/feat-soleur-managed-deploy-substrate-3723/spec.md
status: published
---

# Learning: Brainstorm — cross-check leader substrate recommendations against infra files AND cross-check issue-body hard-rule citations verbatim

## Problem

Two adjacent failure modes surfaced during the #3723 brainstorm — both cheap to prevent at Phase 1.1, expensive if they leak into Phase 2 (approaches) or Phase 3.5 (capture).

### Failure mode 1: leader substrate recommendation contradicts an existing-but-unrecognized prior decision

The triad's CTO recommended Option (c) "Cloudflare Tunnel + extended webhook" over the issue body's proposed Hetzner-runner-on-Soleur-monorepo. The recommendation was load-bearing because it would entirely eliminate the need for a new Terraform root, new VM, and ADMIN_IPS rotation. The recommendation's strength came from a single repo claim: `apps/web-platform/infra/firewall.tf:15` documents prior decision #749 ("CI deploy SSH rule removed — deploys now use webhook via Cloudflare Tunnel"). If the claim is true, the issue body's proposal silently reverses #749. If the claim is false, the recommendation collapses.

The orchestrator must verify the claim before propagating it into Phase 2 approaches. The brainstorm-techniques guidance has a section on this exact pattern ("Cross-checking leader infra/substrate claims against repo-research"), but it can be skipped if the claim isn't surfaced as a quotable string.

### Failure mode 2: issue body cites a hard rule that does not say what the body claims

The original #3723 issue body wrote: "New Terraform root MUST include a destroy runbook per `hr-every-new-terraform-root-must-include-an`." The CTO subagent grepped `AGENTS.core.md:16` and found the actual rule text: "Every new Terraform root must include an **R2 remote backend**." Different requirement. A destroy runbook is good practice per ADR-019, but it is not what the cited rule mandates.

Acceptance criteria, ADR scope, and downstream specs all inherit this citation. If left uncaught, the brainstorm-to-plan pipeline ships an ADR premised on a fictional rule, and the plan's preflight gates check a nonexistent requirement.

## Solution

Two cheap checks at Phase 1.1 (research / context-gathering), before Phase 2 approaches.

### Check 1: Verify infra-file substrate claims with literal grep before they shape Phase 2

When any leader (or the orchestrator's own framing) names a specific substrate with phrasing like "the existing X already handles", "the prior decision Y", "the substrate is already wired", grep the repo for the diagnostic symbol of that substrate AND the issue number cited by the leader. Two-pass: (a) does the named primitive exist? (b) does the cited prior decision actually appear in code or in a learning?

For #3723 specifically:
```bash
grep -n "749\|tunnel.tf\|cloudflared" apps/web-platform/infra/*.tf
sed -n '1,30p' apps/web-platform/infra/firewall.tf  # for the literal comment text
```

If grep returns the cited file + line with the cited prior decision, the claim verifies. If not, the leader's recommendation is making up substrate that doesn't exist; reframe their option as "propose new substrate" rather than "use what's there." Catches false-positive "already wired" claims (2026-05-12 D-DSAR-art15 brainstorm has the parallel learning where a leader claimed Vercel cron was wired and it wasn't).

### Check 2: Verify issue-body hard-rule citations against AGENTS.core.md verbatim

When an issue body cites a hard rule by ID (`hr-*` or `cq-*` or `wg-*`), grep `AGENTS.core.md` (or wherever the body lives — `AGENTS.docs.md` / `AGENTS.rest.md`) for the rule ID and read the actual text. Issue bodies drift: the cited rule may have been edited, retired, or the writer paraphrased and the paraphrase warped the meaning.

```bash
grep -n "hr-every-new-terraform-root-must-include-an" AGENTS.core.md
# OR for the by-section structure used by the index in AGENTS.md:
grep -A2 "hr-every-new-terraform-root-must-include-an" AGENTS.core.md
```

If the actual rule text and the issue body's restatement diverge, capture the divergence in the brainstorm's `## References` section as a "Citation correction" bullet. Do not propagate the body's restatement into the spec.md or the ADR — use the rule's actual text.

## Key Insight

Issue bodies are authored at one point in time and rot in two distinct ways: (a) the *infra they describe drifts* (a prior PR moves the substrate; the body still names the old one), and (b) the *rules they cite drift* (the rule's text was edited, the body's paraphrase is now wrong). The cheap fix for both is the same shape — a 30-second grep before Phase 2 — but the symptoms are different enough that the orchestrator needs two checklist items, not one.

The triad's value isn't only what they recommend; it's also that they're more likely to grep the actual files than the orchestrator under time pressure. Treat any leader recommendation that turns on a specific substrate's existence as a claim to verify, not as a fact to repeat.

## Session Errors

Session error inventory: **none detected** in our own work. The two failure modes documented above were *prevented* by the CTO subagent surfacing them and by the orchestrator running the grep verification at Phase 2 boundary, before any artifact was written. If the verification had been skipped, the brainstorm document and spec.md would have inherited both the substrate misframe and the bad rule citation.

**Prevention:** Add the two checks above as explicit Phase 1.1 substeps in the brainstorm skill if they're not already there. The brainstorm-techniques skill already has the "Cross-checking leader infra/substrate claims against repo-research" pattern (#3 in its verification list); the "issue-body hard-rule citation verification" pattern is adjacent and complementary — both deserve to live next to each other.

## Related

- `knowledge-base/project/learnings/2026-05-12-anticipatory-hook-bypass-and-leader-substrate-cross-check.md` — Parallel pattern for cron-substrate claims (Vercel cron false-wired claim).
- `knowledge-base/project/learnings/2026-05-12-brainstorm-issue-body-option-and-inventory-staleness-pino-userid.md` — Parallel pattern for option enumerations and inventory counts in issue bodies.
- `knowledge-base/project/learnings/2026-05-07-brainstorm-verify-referenced-pr-state-and-leader-infra-claims.md` — Parallel pattern for referenced PR/issue state staleness.
- `knowledge-base/project/learnings/2026-05-11-brainstorm-grep-approach-hook-before-spawning-leaders.md` — Parallel pattern for approach-hook grep before leader spawn.
- `knowledge-base/project/learnings/2026-05-12-brainstorm-defer-decision-issue-body-rule-drift-and-oauth-only-bundling-scope-bound.md` Pattern 1 — Verifying issue-body architectural constraints against the plugin-wide rule corpus.

## Tags

category: workflow-issues
module: brainstorm
