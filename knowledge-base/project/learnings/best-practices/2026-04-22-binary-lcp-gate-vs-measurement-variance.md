---
date: 2026-04-22
category: best-practices
tags: [lighthouse, performance, plan-gates, measurement, lcp]
problem_type: planning
related_prs: [2829]
related_issues: [2809, 2831]
---

# Binary plan gates become unreliable when measurement variance exceeds the gate margin

## Problem

The #2809 plan prescribed a binary decision gate: **"if LCP > 2500 ms on either
/ or a blog post → proceed to Phase 4b (critical-CSS inline + onload-swap
stylesheet load)."**

Median-of-3 Lighthouse runs against prod (Cloudflare edge + HTTP/2 + brotli,
headless Chrome with `--no-sandbox`):

- Home (`https://soleur.ai/`): **2681 ms** median (2543 → 3095, spread 552 ms)
- Blog (`https://soleur.ai/blog/billion-dollar-solo-founder-stack/`): **2737 ms**
  median (2723 → 2748, spread 25 ms)

Home variance (552 ms run-to-run spread) exceeded the distance between the
median and the 2500 ms target (181 ms) by ~3×. Both pages were "over
threshold" by 181–237 ms, squarely inside the measurement's own noise band.

The gate text said "proceed to Phase 4b". The honest answer was "we don't
know whether Phase 4b would move the needle enough to distinguish signal
from noise on a single post-fix run."

## Root cause

The plan author picked an absolute-value threshold (web.dev's 2500 ms "Good"
cutoff) without considering the natural variance of the measurement tool.
Lighthouse in headless Chrome against a Cloudflare-fronted prod site has
150–600 ms run-to-run LCP variance at this magnitude — driven by:

- CDN edge cache freshness at the measurement node
- TLS handshake jitter
- V8 JIT warm-up differences
- Network RTT noise

A binary gate with a margin smaller than σ produces flaps, not decisions.

## Solution (applied in PR #2829)

1. Document the measurement evidence in a committed artifact
   (`knowledge-base/marketing/audits/soleur-ai/2026-04-22-lighthouse-lcp-evidence.md`).
2. Challenge the plan's gate per AGENTS.md `cm-challenge-reasoning-instead-of`.
3. File a dedicated follow-up issue (#2831) for Phase 4b with re-evaluation
   criteria that account for variance: "3-run before/after medians, escalate
   if median exceeds 3000 ms or FCP exceeds 2800 ms."
4. Close the #2829 PR with an explicit note that the deferral is tracked and
   the plan's original gate was challenged.

## Key insight

**A binary plan gate needs an error-bar annotation.** When the gate variable
has run-to-run noise comparable to the gate margin, one of the following must
be specified up front:

- **More samples** — e.g., "median of 9 runs" not 3, to tighten the CI
- **Delta-from-baseline** — e.g., "fix must reduce median LCP by ≥ 300 ms" not
  "fix must land LCP ≤ 2500 ms". The delta form cancels systemic CDN /
  measurement-node bias.
- **Tolerance band** — e.g., "≥ 2700 ms triggers fix, 2500–2700 defers to
  tracked follow-up with re-measurement deadline"

Without one of these, the agent executing the plan has to make a judgment
call at measurement time — which defeats the purpose of writing a plan.

## Prevention

**For future performance-gated plans** (LCP, FCP, TTFB, CLS, API P99 latency,
cold-start, bundle size): the plan Phase must specify at least one of the
three above. Reject a plan review that leaves a binary perf gate with no
variance handling.

**For the deepen-plan skill**: add a Phase that, when a Phase prescribes a
numeric gate against an external-measurement variable (Lighthouse, New Relic,
RUM, load-test output), the deepen pass estimates the expected run-to-run
variance from prior measurements (or documented upper bounds for that tool)
and tightens the gate to one of: delta-from-baseline, tolerance-band, or
increased-N median.

## Session errors

- **Plan subagent did not produce `tasks.md` in the specs directory** —
  Recovery: manually created `knowledge-base/project/specs/feat-one-shot-drain-marketing-chores/`
  and wrote `session-state.md` directly. Minor; no blocking impact.
  Prevention: if one-shot step 2 assumes the plan subagent writes `tasks.md` to
  the specs directory, verify the assumption in the one-shot skill Step 2 after
  the subagent returns (existence check on `specs/<branch>/tasks.md`), and
  fall through to creating the directory manually if missing. The current
  one-shot text says "The plan subagent already wrote `tasks.md`" — make that
  conditional.

## References

- PR #2829 — this PR (drain #2807 #2808 #2809)
- Issue #2831 — filed follow-up for the critical-CSS Phase 4b work, with
  variance-aware re-evaluation criteria
- web.dev LCP thresholds — <https://web.dev/lcp/> (2500 ms "Good", 4000 ms "Poor")
- AGENTS.md `cm-challenge-reasoning-instead-of` — rule that authorized the
  challenge of the plan's binary gate
