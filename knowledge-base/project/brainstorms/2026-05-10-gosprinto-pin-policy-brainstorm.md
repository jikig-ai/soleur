---
date: 2026-05-10
topic: content-vendoring-pin-policy
issue: 3517
pr: 3521
branch: feat-gosprinto-pin-policy
related_artifacts:
  - knowledge-base/project/brainstorms/2026-05-09-gdpr-gate-skill-brainstorm.md
  - knowledge-base/project/specs/feat-compliance-skills-eval/spec.md
  - plugins/soleur/skills/gdpr-gate/NOTICE
  - knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md
  - https://github.com/jikig-ai/soleur/issues/3517
  - https://github.com/jikig-ai/soleur/pull/3521
user_brand_critical: true
---

# Brainstorm: Content-Vendoring Pin Policy (gosprinto/compliance-skills follow-up)

## What We're Building

A **general content-vendoring pin policy** governing any upstream content lifted under permissive license into the repo, with `gosprinto/compliance-skills` (the 5 reference files in `plugins/soleur/skills/gdpr-gate/`) as the first concrete instance and template for future lifts.

The policy ships as four coordinated artifacts:

1. **Doc:** `knowledge-base/engineering/policies/content-vendoring.md` — the general policy + a registry table (gosprinto is row 1).
2. **Drift workflow:** `.github/workflows/scheduled-content-vendor-drift.yml` — weekly cron (`0 9 * * MON`), blob-SHA diff per registry entry, severity-classified labels, auto-PR via `git merge-file --diff3` for security-relevant drift.
3. **Pre-commit gate:** lefthook `vendor-pin-integrity` stanza — fails if NOTICE blob SHAs disagree with actual lifted file SHAs (prevents silent local edits).
4. **Runtime staleness check:** in `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` — reads NOTICE `last-verified` date; >30 days → prepends `⚠ Rules N days stale — advisory only` banner; >90 days → also writes a `compliance/critical` row to `compliance-posture.md`.

## User-Brand Impact

- **Artifact:** `plugins/soleur/skills/gdpr-gate` advisory output rendered into agent context (weave-don't-append).
- **Vector:** stale rules ship as authoritative narrative claims (e.g., "no Art. 9 fields detected") on a regulated-data PR where fresh-upstream rules would have flagged a finding. The operator merges on a false-clean signal.
- **Threshold:** `single-user incident`. A 0-finding output on a regulated PR where upstream-current would flag 1 IS a single-user incident; the gate's weave shape makes the staleness signal load-bearing for operator trust.
- **Why the staleness gate is load-bearing:** the cron + auto-PR is the convenience layer; it can fail silently (workflow disabled, GH outage, PR queued during a busy week, maintainer on PTO). The runtime check is the safety net that fails loudly on the actual invocation. Same philosophy as `cq-silent-fallback-must-mirror-to-sentry`.

## Why This Approach

**Build now, ship the lot** (selected over CPO's "phase to Phase 4 exit" and the compromise option):

- CTO's argument carried: ~10-min implementation cost makes phasing pointless. The founder is also an operator running gdpr-gate today.
- CLO's freeze-default-with-severity-trigger and CTO's `git merge-file --diff3` collapse into the same auto-PR pipeline.
- CPO's staleness gate (the runtime banner + 30/90-day escalation) was the highest-leverage idea neither CLO nor CTO surfaced; it's what protects users at scale and was kept.
- Repo-research's recommendation to write the policy **content-vendoring-general** (not gosprinto-specific) was kept: this NOTICE is the first content-vendor pin in the repo, and the second case will land cheaper if the doc is general.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Default = freeze on `7b58d68`; re-vendor only on severity-flagged upstream drift | CLO: freeze has zero new MIT obligation. Re-vendor is the trigger, not the default. |
| 2 | Severity classifier (regex over upstream `git diff`) | CTO: `+` to `fields.md` table rows; lines containing `[CRITICAL]`, `MUST`, `Art. \d+`, `§\s*\d+`; new files under `references/layers/` → security-relevant → 14-day SLA + auto-PR. Everything else → `vendor/pin-drift` batched, quarterly review. |
| 3 | Three labels: `vendor/pin-drift`, `vendor/license-changed`, `vendor/upstream-archived` | Repo-research precedent from `scheduled-github-app-drift-guard.yml` 3-label split. License-changed co-labels `compliance/critical`; archived opens a fork-or-drop ADR issue. |
| 4 | Detection: GitHub Actions weekly cron (`0 9 * * MON`), blob-SHA compare via `gh api` | CTO: cheapest reliable mechanism with audit trail. Modeled on `scheduled-skill-freshness.yml` (`CAP_PER_RUN`, idempotent issue search, `notify-ops-email`). |
| 5 | Re-vendor uses `git merge-file --diff3`; CI fails if `<<<<<<<` markers remain | CTO: line-based, content-agnostic. Markdown table cells (Art. 9 row insertions) surface as conflicts, don't corrupt. |
| 6 | Pre-vendor diff scan rejects upstream changes that introduce telemetry, vendor links, hosted-service references rendered to user output, or third-party-domain URLs | CLO: load-bearing. Re-vendoring does not change Sprinto's non-sub-processor status only if this gate holds on every pull. |
| 7 | Pre-commit lefthook gate: blob SHA of each registry-listed lifted file must match NOTICE | Repo-research: missing today. Prevents silent local edits to lifted bytes without re-pin/re-stating attribution. |
| 8 | Runtime staleness check in `gdpr-gate.sh` | CPO novel: 30d → advisory-only banner; 90d → `compliance/critical` row escalation. Failsafe when the cron pipeline fails. |
| 9 | Policy is content-vendoring-general, instantiated via a registry table; gosprinto is row 1 | Repo-research: this NOTICE is the first content-vendor pin; second case will land cheaper if doc is general. Plugin-level NOTICE pattern (`plugins/soleur/NOTICE`) is ideas-only, doesn't pin — different shape, kept distinct. |
| 10 | Compliance-posture integration: new "Vendored Code Provenance" section in `knowledge-base/legal/compliance-posture.md` (sibling to "Vendor DPA Status", not merged into it) | Repo-research: DPA Status is for service vendors (Hetzner, Supabase, Stripe). Conflating service-vendor and content-vendor breaks the operator-ack contract documented at lines 39-50. |
| 11 | NOTICE gets YAML frontmatter (`last-verified`, registry pointer) | Required for the runtime staleness check to read the date in <50ms; frontmatter is the cheap parse target. |
| 12 | No new agent, no new MCP server | CTO + CPO: existing tools (`gh`, GH Actions, `git merge-file`, lefthook) cover the surface. |

## Open Questions

- **Q1 (plan):** Does the runtime staleness banner attach to gdpr-gate output unconditionally, or only when the gate finds 0 issues on a regulated-data PR? (CPO framing suggests the 0-finding case is most dangerous; tagging only that case is a smaller behavior change.) Defer to plan.
- **Q2 (plan):** Should the policy doc live under `knowledge-base/engineering/policies/` (this brainstorm's choice) or `knowledge-base/legal/` (closer to compliance-posture)? Repo-research suggests engineering since the obligations are technical (drift detection, 3-way merge). Legal owns the cross-link, not the artifact.
- **Q3 (plan):** What's the right trigger for retiring a registry entry? E.g., if upstream archives the repo and we fork-permanently, the entry stays? Becomes a separate row? Decide at first occurrence, not now.
- **Q4 (work):** The NOTICE-vs-actual SHA gate needs to compute git blob SHA (not file content SHA). Use `git hash-object` per file. Trivial, but plan should call out the distinction so the lefthook stanza doesn't silently use `sha256sum` and produce a different value.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support
**User-brand-critical override:** CPO + CLO + CTO spawned in parallel (mandatory).

### Legal (CLO)

**Summary:** MIT requires only the copyright notice + permission paragraph; freezing on `7b58d68` carries zero new obligation. Silent incorporation of upstream patches without bumping the NOTICE SHA is the actual breach risk (attribution to bytes that no longer match shipped). Pre-vendor diff scan rejecting telemetry / vendor links / hosted-service references is load-bearing — it's what keeps Sprinto a non-sub-processor under any policy option. Holding out a "GDPR gate" while running known-stale rules is a GDPR Art. 5(2) accountability breach, not a missed advisory.

### Engineering (CTO)

**Summary:** Weekly GH Actions cron with `gh api` blob-SHA compare is the cheapest reliable detection (~10 min implementation). `git merge-file --diff3` works on markdown for the 3-way merge against EU extensions; CI grep for `<<<<<<<` gates the auto-PR. Severity classifier as regex over the upstream diff. Worth an ADR (`/soleur:architecture create`) since this sets the content-vendoring template.

### Product (CPO)

**Summary:** The policy doc itself is meta-process and doesn't need single-user incident shipping; the **freshness SLO does**. The gdpr-gate's weave-don't-append output makes 0-finding outputs on stale rules into single-user incidents. Recommends a runtime staleness gate (advisory-only mode if rules exceed SLO) — load-bearing protection independent of the cron. Initially recommended phasing to Phase 4 exit; user chose build-now after weighing CTO's low-cost argument. Staleness gate kept as the highest-leverage retained idea.

## Capability Gaps

None. All tools required (gh, GH Actions, `git merge-file --diff3`, `git hash-object`, lefthook, bash) exist in the toolchain. All workflow patterns precedent-set in repo:

- `.github/workflows/scheduled-skill-freshness.yml` — monthly cron + `CAP_PER_RUN` + idempotent issue search + bot-PR + notify-ops-email (strongest template; verified at line range; cron schedule and label severity will be adapted, structure kept).
- `.github/workflows/scheduled-github-app-drift-guard.yml` — 3-label severity-split precedent (verified lines 1-80).
- `.github/workflows/pr-auto-close-scanner.yml` — auto-PR creation pattern.
- `lefthook.yml:94-119` — existing `gdpr-gate-advisory` stanza (template for adding `vendor-pin-integrity` sibling stanza).
- `knowledge-base/legal/compliance-posture.md:39-50` — existing operator-ack contract for the Active Compliance Items table; the drift workflow plugs in here, not into the Vendor DPA Status table (that's service vendors).
