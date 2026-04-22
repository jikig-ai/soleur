---
date: 2026-04-22
source: Lighthouse 13.1.0 (headless Chrome, `--no-sandbox`)
target: production `https://soleur.ai/` and `/blog/billion-dollar-solo-founder-stack/`
purpose: evidence for #2809 decision gate (LCP measure-first, fix-maybe)
---

# Lighthouse LCP evidence — 2026-04-22

Measurement for #2809 decision gate. Median-of-3 Lighthouse runs per URL against production (Cloudflare edge + HTTP/2 + brotli).

## Raw per-run metrics

### Home (`https://soleur.ai/`)

| Run | LCP (ms) | FCP (ms) | CLS | Speed Index (ms) | TBT (ms) | Perf score |
|---|---|---|---|---|---|---|
| 1 | 3095 | 2940 | 0.008 | 3057 | 30 | 0.88 |
| 2 | 2543 | 2151 | 0.009 | 2151 | 24 | 0.95 |
| 3 | 2681 | 2501 | 0.009 | 3170 | 33 | 0.92 |
| **Median** | **2681** | **2501** | **0.009** | **3057** | **30** | **0.92** |

### Blog (`https://soleur.ai/blog/billion-dollar-solo-founder-stack/`)

| Run | LCP (ms) | FCP (ms) | CLS | Speed Index (ms) | TBT (ms) | Perf score |
|---|---|---|---|---|---|---|
| 1 | 2748 | 2472 | 0.003 | 2500 | 58 | 0.93 |
| 2 | 2724 | 2473 | 0.003 | 2473 | 81 | 0.93 |
| 3 | 2737 | 2372 | 0.003 | 2372 | 248 | 0.88 |
| **Median** | **2737** | **2473** | **0.003** | **2473** | **81** | **0.93** |

## Decision gate analysis

Plan Phase 4 gate: "If LCP ≤ 2500 ms on BOTH pages → close-without-fix. If > 2500 ms on either → Phase 4b."

- Home median: **2681 ms** (181 ms over threshold)
- Blog median: **2737 ms** (237 ms over threshold)

Both over threshold — gate says proceed to Phase 4b (critical-CSS inline + onload-swap stylesheet load).

## Challenge (per AGENTS.md `cm-challenge-reasoning-instead-of`)

- **Variance exceeds the gap.** Home run-to-run spread is 552 ms (2543 → 3095); median distance to the 2500 ms target is only 181 ms. Blog spread is 25 ms but TBT variance is 4× (58 → 248). A single post-fix Lighthouse run would not reliably prove the fix landed.
- **CSS complexity.** `plugins/soleur/docs/css/style.css` is 1753 lines and serves two structurally different above-the-fold templates (home hero vs. blog post header + author card). A proper critical-CSS extraction needs DevTools Coverage or `penthouse`, plus visual-regression review across both page types.
- **FOUC risk.** The onload-swap pattern without well-curated critical CSS causes full-page flash on first render. Acceptable per CSP (`style-src 'self' 'unsafe-inline'`), but requires explicit verification in a dedicated PR.
- **Classification.** Both medians fall in web.dev's "Needs improvement" band (2500–4000 ms), not "Poor" (>4000 ms). CLS is excellent (<0.01). Perf score is 0.88–0.95.

**Decision:** Close #2809 as "measured — borderline over threshold; remediation tracked in #2831". Phase 4b scoped to its own PR with proper extraction tooling and 3-run before/after medians.

## Reproduction

Full Lighthouse JSON reports (500KB each × 6) not committed to git history. To reproduce:

```bash
mkdir -p artifacts
for i in 1 2 3; do
  npx --yes lighthouse https://soleur.ai/ \
    --only-categories=performance \
    --output=json \
    --output-path=./artifacts/lh-home-${i}.json \
    --chrome-flags="--headless --no-sandbox" \
    --quiet
  npx --yes lighthouse https://soleur.ai/blog/billion-dollar-solo-founder-stack/ \
    --only-categories=performance \
    --output=json \
    --output-path=./artifacts/lh-blog-${i}.json \
    --chrome-flags="--headless --no-sandbox" \
    --quiet
done
jq -s 'map(.audits["largest-contentful-paint"].numericValue) | sort | .[1]' artifacts/lh-home-*.json
jq -s 'map(.audits["largest-contentful-paint"].numericValue) | sort | .[1]' artifacts/lh-blog-*.json
```
