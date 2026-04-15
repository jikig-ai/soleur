---
title: Collapsible Navs + Recurring UX-Review Agent Loop
date: 2026-04-15
topic: collapsible-navs-ux-review
status: decided
related_issues: [2341, 2342, 2343, 2344]
---

# Brainstorm: Collapsible Navs + Recurring UX-Review Agent Loop

## What We're Building

Two tightly coupled capabilities, sequenced as B → A.

**B. `soleur:ux-audit` skill (new)** — a recurring agent loop that navigates the live web-platform UI as a logged-in bot user (and as an anonymous visitor), captures structured findings with screenshots, and files them as GitHub issues. Built first because it validates the loop with a known-good calibration case before we trust it on unknowns.

**A. Collapsible sidebars (3 surfaces)** — main app nav (`apps/web-platform/app/(dashboard)/layout.tsx`), Knowledge Base file-tree (`apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx`), and Team Settings (`apps/web-platform/components/settings/settings-shell.tsx`). Shipped as the first proof-of-loop artifact once B's first run surfaces it as a finding.

## Why This Approach

The motivating observation is that some Soleur users — solo founders without a designer (the Phase 4 ICP) — are not skilled at spotting UX gaps themselves. The repo already has a documented coverage gap (`knowledge-base/project/learnings/2026-02-17-ux-review-gap-visual-polish-vs-information-architecture.md`): `ux-design-lead` produces `.pen` wireframes but has zero capability for auditing existing HTML. So B fills a known roster gap rather than duplicating existing tooling.

Building B before A validates calibration: if B's first run does not surface the collapsible-navs pain point as a top-5 finding, the agent's judgment is miscalibrated and we fix that before trusting it on less-obvious UX issues. A also becomes the concrete first artifact for the CMO blog post ("We gave our UX reviewer a cron job") and for the "Built by agents, in public" marketing framing.

Event-driven triggering on UI-path PR merges (with monthly cron as a safety net) ties audit cost (~$3–$12/run) to real UI churn rather than paying for audits in quiet weeks.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope split | Two features, sequenced B → A | CPO: B's first run calibrates against A as known-good; CMO: strongest agent-native narrative |
| Agent surface | New `soleur:ux-audit` skill + reuse `ux-design-lead` agent in new "audit screenshots" mode | Matches competitive-intelligence skill/agent split; keeps Pencil workflow pure |
| Execution surface | GitHub Actions scheduled workflow (via `soleur:schedule` skill) | Proven pattern; no new infra surface |
| Cadence | Event-driven on `apps/web-platform/app/**` and `components/**` PR merges to main, plus monthly cron `0 9 1 * *` as safety net | CTO: ties cost to churn, avoids redundant quiet-week audits |
| Auth | Dedicated bot Supabase account `ux-audit-bot@jikigai.com` seeded with representative fixtures; creds in Doppler `prd` | Empty-state audits misleading on Vercel preview; fixture-seeded bot reflects real user view |
| Logged-out coverage | Audit landing, signup, pricing unauthenticated too | CTO flagged these as highest-churn surfaces |
| Dedup | Two-layer: (1) `gh issue list --label ux-audit --search <route>`, (2) SHA256 hash of `{route}\|{element-selector}\|{issue-category}` stored as hidden HTML comment in issue body | Pattern from CodeQL alert triage learning; embedding similarity overkill |
| Per-run cap | 5 issues per run | Forces prioritization; lowest-severity cut if findings > 5 |
| Global cap | 20 open `ux-audit` issues | Skill refuses to file when cap reached; forces human triage before more findings enter |
| Default milestone | `Post-MVP / Later` | Human founder promotes to active milestone — no auto-promotion |
| Labels | `agent:ux-design-lead` + `ux-audit` + `domain/product` | Distinguishes agent-authored issues; matches public-narrative framing; routes to CPO per existing taxonomy |
| Governance | Exclude `ux-audit` issues from auto-fix/auto-triage workflows | Breaks the file-triage-prioritize self-loop |
| Screenshot storage | Attach directly to issue body via GitHub API | No new R2/Cloudflare Images surface |
| Failure notification | `.github/actions/notify-ops-email` on `if: failure()` | Per `hr-github-actions-workflow-notifications` — no Discord for ops |
| Public framing | Lightweight link from marketing site to the agent-filed-issues GitHub search | CMO: "Built by agents, in public" — issue tracker IS the log |
| Launch content | Blog post "We gave our UX reviewer a cron job" with collapsible-navs as the opening artifact | CMO content opportunity |
| Collapsible-nav persistence | `localStorage` per sidebar via SSR-safe `useSyncExternalStore` | Matches PaymentWarningBanner pattern already in layout.tsx |
| Collapsible-nav shortcut | `Cmd/Ctrl+B` global, reused across all three sidebars | No framework exists yet — introduce minimal keydown listener |
| Mobile treatment | Reuse existing mobile drawer for main nav; add drawer pattern to KB + Settings where missing | KB currently has class-swap, not a drawer |

## Open Questions

1. **Route manifest.** A shared `apps/web-platform/src/routes.manifest.ts` (or equivalent) listing what pages exist, their auth level, and their fixture prerequisites would serve both `soleur:ux-audit` and future QA skills. Build it as part of B, or defer? Currently flagged as a capability gap.
2. **Bot fixture content.** What representative state does the bot account need (how many KB entries, which upload types, how many team members)? Needs a short spec before the first run.
3. **First-run calibration criterion.** If collapsible-navs is NOT in the first run's top-5 findings, what's the remediation — re-prompt tweaks, rubric adjustment, or rollback? Define "the agent is calibrated" before running.
4. **Retry prevention.** If the founder closes an agent-filed issue as "wontfix", does the dedup hash prevent re-filing forever, or does it expire? Closed-wontfix ≠ closed-shipped.
5. **Screenshot scale + redaction.** What's the default screenshot scale (keep at 1x for vision-token economy? upscale for detail?) and do we need any PII redaction in logged-in captures (even for a bot account)?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** High user value for A (every user on ~1280px laptops); medium for B (value depends entirely on signal quality). Phase 3 fits cleanly; materially de-risks Phase 4's 2-week unassisted usage trigger. Recommendation adopted: sequence B → A, cap 5/run, close rate > 60% as acceptance signal.

### Marketing (CMO)

**Summary:** B is the most credible concrete artifact the product has produced for the agent-native positioning — a falsifiable proof point, not a demo. Recommendation adopted: public issues, `agent:ux-design-lead` label, lightweight marketing-site link, launch blog post with collapsible-navs as opening artifact.

### Engineering (CTO)

**Summary:** A is low-risk (1–2 days). B has real architecture decisions: new skill (not extend), event-driven + monthly cron (not weekly), fixture-seeded bot account, hash-based dedup, 20-issue global cap, exclude from auto-fix/auto-triage. Identified two capability gaps (route manifest, new skill) now tracked below.

### Operations (COO)

**Summary:** GitHub Actions scheduled workflow, Doppler `prd` for bot creds, ~$3–$12/run = ~$15/month max, attach screenshots to issues (no new storage surface), email-on-failure per `hr-github-actions-workflow-notifications`.

## Capability Gaps

| Gap | Domain | Why needed |
|---|---|---|
| No skill for "navigate authenticated app routes and capture structured UX findings" — `soleur:qa` is merge-gated, `soleur:test-browser` captures but doesn't audit | Product | Direct blocker for B. Addressed by creating `soleur:ux-audit` in this feature. |
| No shared route manifest for `apps/web-platform` listing pages, auth level, fixture prerequisites | Engineering | Both `soleur:ux-audit` and future QA skills need it. Open Question #1 — decide in-scope or deferred during planning. |
| No pattern for hiding agent-authored issues from auto-fix/auto-triage workflows | Product | Governance-loop prevention. Will need a one-line `--exclude-label ux-audit` addition to existing triage/fix skills. |

## Next Steps

1. Create GitHub issues: one for B (primary, this feature), one for A (blocked by B), one for each deferred capability gap.
2. Spec B via `skill: soleur:plan` — it owns the critical path.
3. First-run calibration criterion (Open Question #3) decided in the plan, not left to implementation.
