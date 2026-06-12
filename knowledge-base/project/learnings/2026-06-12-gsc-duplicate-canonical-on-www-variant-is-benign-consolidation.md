# Learning: GSC "Duplicate, Google chose different canonical than user" on a www variant is the benign www→apex consolidation

## Problem

Google Search Console flagged **"Duplicate, Google chose different canonical than
user"** for `https://www.soleur.ai/blog/best-claude-code-plugins-2026/` (1 page,
first detected 2026-06-06). The operator forwarded it alongside a separate
"Page with redirect" coverage CSV.

The instinct (encoded in the one-shot dispatch brief) was to treat it as an
on-site canonical bug OR an external-syndication-without-canonical-back bug. Both
hypotheses were **wrong**.

## Solution

**Diagnose with live `curl` before touching code.** Three commands settle it:

```bash
curl -sI  https://www.soleur.ai/blog/best-claude-code-plugins-2026/   # → 301, location: https://soleur.ai/...
curl -sI  https://soleur.ai/blog/best-claude-code-plugins-2026/       # → 200
curl -s   https://soleur.ai/blog/best-claude-code-plugins-2026/ | grep -oiE '<link rel="canonical"[^>]*>'
#   → <link rel="canonical" href="https://soleur.ai/blog/best-claude-code-plugins-2026/">   (apex, self-referential)
```

The flagged URL is the **www variant**, which 301-redirects to the **apex**
canonical (per the #4573 apex flip + #4584 canonicalizer contract). Google
followed the redirect, read the apex page's correct self-canonical, and
**correctly consolidated www onto apex**. "Google chose a different canonical than
user" here means: the *inspected* URL was www, and Google's chosen canonical is
apex — the page's own declared canonical. **Google is working correctly. There is
no code bug.**

**Resolution is operator-side, not a deploy:** click **VALIDATE FIX** in GSC and
wait ~2–4 weeks (the report was only 6 days old). GSC's Validate Fix has no public
API and is SSO/CAPTCHA-gated — a genuinely operator-only step.

**`site.url` must stay apex (`https://soleur.ai`).** "Fixing" it to www reads like
the obvious patch for "www URL flagged" but is the *inverse* of the correct
direction and would make every page emit a redirecting canonical site-wide.

**Optional CI hardening shipped:** `validate-seo.sh` now asserts each page's
`<link rel="canonical">` absolute-host equals the sitemap's single `<loc>` host
(derived, not a second literal pin). This is the per-page sibling of the existing
sitemap host-axis gate. It catches a *page-template* regression emitting a
redirecting/other-host canonical; a *uniform* `site.url`→www flip stays covered by
`sentry_uptime_monitor.soleur_www` (the live 301 monitor).

## Key Insight

A GSC coverage report URL is **Google's historical/variant memory, not a bug
list** — the same lesson as
[[2026-06-01-gsc-page-with-redirect-is-historical-memory-verify-against-build]].
When the flagged URL is a *non-canonical variant that correctly 3xx-redirects*
(www, apex-vs-www, `.html`, `?ref=`), the "duplicate / redirect / chosen-different-
canonical" class is **benign by construction**. Verify against live HTTP + the
built `_site/` before writing any fix; the correct action is usually VALIDATE-FIX +
wait, with at most a regression-hardening CI gate.

## Session Errors

1. **Dispatch brief carried two confident-but-wrong diagnostic premises** (`base.njk`
   renders www; root cause is external syndication). — **Recovery:** deepen-plan's
   premise-validation gate falsified both against live production before planning.
   — **Prevention:** already-covered; a dispatch brief's "diagnosis already done"
   block is a *hypothesis to verify*, never fact. The premise gate is the safety
   net and worked. (Recurring class, no new rule needed.)
2. **First `validate-seo.sh` gate omitted the `|| true` pipefail guard (P1, caught by
   security-sentinel, reproduced EXIT=1).** Under `set -euo pipefail` an unguarded
   `var=$(grep ... | grep ... | sed ...)` aborts the whole script when the inner
   grep matches nothing (relative/missing canonical), silently dropping all
   downstream per-page checks. — **Recovery:** wrap the extraction in `|| true`,
   mirroring the 4 existing in-file precedents (lines ~64/80/96/205). —
   **Prevention:** when adding a grep-pipeline command-substitution to a
   `set -euo pipefail` script, mirror the file's existing `|| true` idiom in the
   same edit; add a test that exercises the no-match input (here: a relative-only
   canonical that must skip without aborting).
3. **First gate used `head -1`, checking only the first canonical tag (P2, caught by
   pattern-recognition).** A page with two canonical tags (apex + a rogue www) — the
   exact GSC duplicate-canonical mode — would have passed. — **Recovery:** check
   EVERY extracted host via `grep -vxF` and fail on any mismatch. —
   **Prevention:** when a gate exists to catch "a wrong X is present," verify ALL
   X, not just the first; add a multi-occurrence fixture.

## Tags
category: seo
module: plugins/soleur/skills/seo-aeo
related: [[2026-06-01-gsc-page-with-redirect-is-historical-memory-verify-against-build]]
