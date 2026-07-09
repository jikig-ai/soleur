# Decision Challenges — feat-one-shot-router-cache-staletimes-tab-switch

Surfaced during plan + plan-review (headless one-shot). `ship` Phase 6 renders these
into the PR body and files an `action-required` issue for operator visibility.

## 1. Dropped `static: 180` from the operator's suggested config (Taste)

The fix brief suggested `experimental.staleTimes = { dynamic: 30, static: 180 }`
and delegated tuning ("tune in the plan"). Both simplification reviewers
(DHH + code-simplicity) and the architecture reviewer independently flagged
`static: 180` as unmotivated and mildly counterproductive: the reported bug is
caused solely by `staleTimes.dynamic = 0`; `static` already defaults to a
non-zero window (300 s in Next 15), and lowering it to 180 adds revalidation
churn on prefetched routes for no described benefit. **Plan ships
`{ dynamic: 30 }` only.** Reversible one-line change if a static-route problem
later appears. Operator: flag if you specifically wanted the `static` override.

## 2. Isolation surface is larger than "one config line + GAP C" (User-Challenge / scope)

The 5-agent plan-review (single-user-incident threshold) established that a
non-zero `staleTimes.dynamic` makes the client Router Cache retain per-principal
server-rendered RSC across **soft** navigations, and middleware does not re-run on
cache hits. The default OTP sign-in and the in-session 401/revocation bounces are
all **soft** navigations, so the perf change opens a real cross-principal window
that requires converting several soft navs to hard navs (GAP C/D/E/F) plus a
bfcache defense (GAP G) to stay safe at this threshold. The perf win (no skeleton
flash on tab switch) is operator-requested and each mitigation is a one-line,
well-precedented hard-nav (mirrors `org-switcher-container.tsx:131`), so the plan
keeps the feature and expands the isolation deliverables rather than dropping it.
Operator/CPO: confirm the expanded isolation scope is acceptable, or descope the
perf change. CPO sign-off is already required (`requires_cpo_signoff: true`);
deepen-plan will add `security-sentinel` + `data-integrity-guardian`.
