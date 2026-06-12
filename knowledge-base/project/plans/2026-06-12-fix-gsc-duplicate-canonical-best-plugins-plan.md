---
title: 'Fix GSC "Duplicate, Google chose different canonical than user" — best-claude-code-plugins-2026'
type: fix
date: 2026-06-12
branch: feat-one-shot-gsc-duplicate-canonical-best-plugins
lane: single-domain
status: ready
brand_survival_threshold: none
classification: seo-diagnostic / no-code-change-required
---

# 🐛 Fix GSC "Duplicate, Google chose different canonical than user" for `/blog/best-claude-code-plugins-2026/`

## Enhancement Summary

**Deepened on:** 2026-06-12

**Deepen-plan gates run (all PASS):**

- **4.6 User-Brand Impact halt** — section present; threshold `none` with non-empty reason; the sole candidate edit (`plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`) does NOT match the sensitive-path regex (`plugins/*/skills/`, not `apps/web-platform/{server,supabase,...}` / infra / secret-workflow), so no scope-out bullet is required.
- **4.7 Observability gate** — section present; the only code-class edit is a CI lint gate, so the relevant liveness signals are *named, not added* (`sentry_uptime_monitor.soleur_www` for the 301; `validate-seo.sh` in `deploy-docs` CI for sitemap/canonical regressions).
- **4.8 PAT-shaped variable halt** — no PAT-shaped TF vars / env vars / literal tokens. Pass.
- **4.9 UI-wireframe halt** — no UI-surface files (CI shell script + docs only). Pass.
- **4.4 Precedent-diff gate** — N/A: no SQL `SECURITY DEFINER`/atomic-write/lock/RPC/pool pattern; the optional Phase 2 gate mirrors the *existing* sitemap-host gate in the same file (precedent cited inline).
- **4.5 Network-outage deep-dive** — N/A: the only network tokens (`301`, `curl`) are the *verified evidence*, not unresolved connectivity symptoms (no SSH/handshake/timeout/5xx failure being diagnosed).

**Verify-the-negative pass (4.45) — all CONFIRMED against installed code:**

- Plan claim "`validate-seo.sh` canonical check is presence-only (no host assertion)" → **CONFIRMED** (`grep -q 'rel="canonical"'` at the per-page check; no host comparison). This is the legitimate Phase 2 gap.
- Plan claim "`social-distribute` links out, does not republish full text" → **CONFIRMED** (no republication directive in `SKILL.md`).
- Live evidence re-confirmed at deepen time (drift guard): `www → 301 → apex`, `apex → 200`. PR #4729 still `MERGED`.

**Key finding (carried from plan):** Both brief premises were falsified by live production — `base.njk` renders the **apex** canonical (not www), and there is **no external full-text copy**. The reported GSC class is the benign `www→apex` consolidation. **No required code change**; outcome is operator VALIDATE-FIX + wait, with an optional `validate-seo.sh` canonical-host hardening gate. No section warranted speculative research-deepening — the conclusion is grounded in live HTTP evidence + the `2026-06-01-gsc-page-with-redirect-is-historical-memory` precedent.

## Summary

GSC reports **"Duplicate, Google chose different canonical than user"** for
`https://www.soleur.ai/blog/best-claude-code-plugins-2026/` (first detected
2026-06-06, **1 affected page**).

**Verified conclusion: this is benign, expected behavior — there is NO repo code
bug to fix.** The reported URL is the **`www` variant**, which 301-redirects to
the apex canonical (`https://soleur.ai/...`). Google followed the redirect,
landed on the apex page, read its correct self-referential canonical, and
**correctly consolidated the `www` URL onto the apex** — which is exactly what
the site's `www→apex` canonicalizer contract (#4584) intends. "Google chose a
different canonical than user" here means: the *inspected/discovered* URL was the
`www` variant, and Google's chosen canonical is the apex — the page's own
declared canonical. This is Google working **correctly**.

The correct action is **operator-side**: click **VALIDATE FIX** in GSC for this
report and wait. The report is only 6 days old (Google routinely takes 2-4 weeks
to reconcile a freshly-discovered redirecting variant). No deploy is required.

An **optional, low-cost CI regression-hardening** is identified (assert the
per-page canonical *href host* equals the apex, not just that the tag exists) —
see Phase 2. It is not required to resolve the reported issue and may be deferred.

---

## Research Reconciliation — Brief Premise vs. Verified Reality

The one-shot brief carried a pre-supplied diagnosis. Per the pre-research premise
gate, every cited premise was verified against live production and the codebase.
**Both load-bearing premises were falsified.**

| Brief premise | Verified reality | Source |
|---|---|---|
| "`base.njk:7` renders the canonical as `https://www.soleur.ai/...` — so the on-site tag is NOT the bug." | `base.njk:7` renders `{{ site.url }}{{ page.url }}` where `site.url = "https://soleur.ai"` (**apex, no www**). Live apex page canonical = `https://soleur.ai/blog/best-claude-code-plugins-2026/`. The tag is correct, but it points to **apex**, not www. | `plugins/soleur/docs/_data/site.json:3`; `plugins/soleur/docs/_includes/base.njk:7`; live `curl` |
| "Root cause is almost certainly an external syndicated copy lacking rel=canonical back to soleur.ai (see `distribution-content/best-claude-code-plugins-2026.md`)." | The distribution-content file is **outbound social promotion only** — Discord/X/IndieHackers/Reddit/HN/LinkedIn/Bluesky blurbs, every one carrying a **UTM-tagged link back to soleur.ai**. The `social-distribute` skill links out; it does **not** republish full text on dev.to/Medium/Hashnode. A web search for the article's exact framing surfaced only **independent competing listicles** (Firecrawl, Composio, TurboDocx, Medium authors) — no full-text copy of Soleur's article. No external duplicate-with-missing-canonical-back exists. | `knowledge-base/marketing/distribution-content/best-claude-code-plugins-2026.md`; `plugins/soleur/skills/social-distribute/SKILL.md:102-109`; WebSearch |
| (Implicit) the duplicate signal needs a remediation. | The duplicate signal is the `www→apex` 301 consolidation — the canonical-host contract working as designed (#4573 flipped www→apex; #4584 codified it via GitHub Pages CNAME + Terraform DNS drift-guard). | `apps/web-platform/infra/dns.tf:248-268`; live `curl` |

**Premise Validation note:** Brief cited `base.njk:7` (verified — renders apex, not
www as claimed), `distribution-content/best-claude-code-plugins-2026.md` (verified
— social blurbs, not republication), and PR #4729 / `feat-one-shot-gsc-sitemap-redirect-leak`
as the out-of-scope benign redirect class (verified — `gh pr view 4729` = MERGED
2026-06-01, "harden docs sitemap against redirecting-URL leaks"). The mechanism
("external syndicated copy") sits in the *rejected-hypothesis* space once the live
301 + apex self-canonical are observed. Reframed from *fix* to *no-code-change +
operator VALIDATE-FIX + optional CI hardening*, consistent with the brief's stated
"a 'no repo code change' outcome is acceptable."

---

## Live Production Evidence (load-bearing — re-verifiable)

```text
$ curl -sI https://www.soleur.ai/blog/best-claude-code-plugins-2026/
HTTP/2 301
location: https://soleur.ai/blog/best-claude-code-plugins-2026/   # www → apex (per #4584)
server: cloudflare

$ curl -sI https://soleur.ai/blog/best-claude-code-plugins-2026/
HTTP/2 200                                                        # apex serves the page

$ curl -s https://soleur.ai/blog/best-claude-code-plugins-2026/ | grep -oiE '<link rel="canonical"[^>]*>|<meta property="og:url"[^>]*>'
<link rel="canonical" href="https://soleur.ai/blog/best-claude-code-plugins-2026/">   # self-referential, apex
<meta property="og:url" content="https://soleur.ai/blog/best-claude-code-plugins-2026/">
```

- www variant → **301 → apex** (Cloudflare edge fronting GitHub Pages; the 301
  itself is GitHub-Pages/Fastly-owned per `dns.tf:251-268`).
- apex → **200**, self-canonical = apex (correct).
- `og:url` = apex (matches canonical — no conflicting signal).
- Canonical tag **renders in production** (count = 1 in live HTML) — this
  refutes the stale `2026-03-25-seo-audit.md` "canonical not rendering" finding,
  which described a since-fixed build state.

---

## User-Brand Impact

**If this lands broken, the user experiences:** Nothing changes for the user —
this plan ships no code. If the (false) "external syndicated copy" theory had been
chased and `site.url` were "corrected" to `www`, **every page on the docs site**
would suddenly emit a canonical that 301-redirects, regressing the #4573 apex flip
and inducing the exact "Google chose different canonical" signal site-wide. This
plan's primary value is **not making that change.**

**If this leaks, the user's data is exposed via:** N/A — no data surface; this is a
public marketing-site SEO diagnostic.

**Brand-survival threshold:** `none` — single non-canonical-variant GSC report on a
correctly-301'd URL; no user data, no revenue path, no auth surface. Reason for
`none` on a non-sensitive path: the diff (if any) touches only
`plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` (a CI gate) and docs —
no schema/auth/API/migration surface.

---

## Acceptance Criteria

### Pre-merge (PR) — only if the optional Phase 2 hardening is folded in

- [ ] **AC1 (no false fix):** `git diff origin/main -- plugins/soleur/docs/_data/site.json`
  returns empty — `site.url` remains `https://soleur.ai` (apex). The plan does
  **not** change the canonical host.
- [ ] **AC2 (no chasing):** No new code targets an "external syndicated copy"
  (no dev.to/Medium/Hashnode canonical-back artifacts created) — confirmed by the
  reconciliation table above; nothing to verify in code.
- [ ] **AC3 (optional hardening, if folded in):** `validate-seo.sh` asserts the
  per-page `<link rel="canonical">` **href host** equals the apex
  (`https://soleur.ai`), failing if a page emits a `www.` or other-host canonical.
  Verify: run `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh <built _site>`
  on a fixture whose canonical href is `https://www.soleur.ai/...` and confirm it
  **fails**; on the apex fixture confirm it **passes**.
- [ ] **AC4 (no regression):** `validate-seo.sh` still passes on the real built
  `_site/` (apex canonical everywhere). Run the Eleventy build then the script:
  `cd plugins/soleur/docs && npx @11ty/eleventy && bash ../skills/seo-aeo/scripts/validate-seo.sh _site`.
- [ ] **AC5 (out-of-scope confirmed clean):** `grep -E '(\.html$|/pages/)'` over
  `_site/sitemap.xml` returns zero (the PR #4729 "Page with redirect" hardening is
  intact — confirm no regression, per brief out-of-scope instruction).

### Post-merge (operator) — the actual resolution path

- [ ] **AC6 (VALIDATE FIX):** In Google Search Console → Pages → "Duplicate, Google
  chose different canonical than user", open the report for
  `https://www.soleur.ai/blog/best-claude-code-plugins-2026/` and click **VALIDATE
  FIX**. (Automation note below.) `Ref` the issue, do not auto-close at merge.
- [ ] **AC7 (wait + re-check):** After ~2-4 weeks, re-inspect the URL via GSC URL
  Inspection. Expected end state: the **www** URL is classified as "Alternate page
  with proper canonical tag" (or drops out), and the **apex** URL is indexed as
  canonical. If it is, close the tracking issue; if the apex itself is flagged,
  re-open with the new evidence (would indicate a genuine new regression).

> **Automation feasibility (AC6):** GSC's "Validate Fix" button has **no public
> API** (the Search Console API exposes Inspection + Sitemaps + Search Analytics,
> but not coverage-issue validation triggers). It is also CAPTCHA/SSO-gated behind
> the operator's Google account. → Genuinely operator-only.
> `Automation: not feasible because the GSC coverage "Validate Fix" action has no
> API and sits behind Google account SSO.` This is one of the two sanctioned
> operator-only categories (interactive third-party-portal action).

---

## Implementation Phases

### Phase 0 — Preconditions (verification only, no edits)

1. Re-run the three `curl` commands above; confirm www→301→apex, apex→200,
   apex self-canonical. (Already verified at plan time 2026-06-12; re-verify at
   /work time in case of DNS/edge drift.)
2. Confirm `site.url == "https://soleur.ai"` in `_data/site.json` (apex).
3. Confirm `feat-one-shot-gsc-sitemap-redirect-leak` / PR #4729 hardening intact:
   `validate-seo.sh` still contains the redirect-stub gate (line ~76) and the
   canonical-host gate (line ~81+).

### Phase 1 — Outcome decision (no code)

**This is the load-bearing phase.** Conclude: the reported GSC class is the benign
`www→apex` consolidation; the on-site signals are all correct; there is no external
full-text copy. **Resolution = operator VALIDATE FIX + wait (AC6/AC7).** Record this
conclusion in the spec and the tracking issue.

### Phase 2 — OPTIONAL CI regression-hardening (fold-in OR defer)

**Gap:** `validate-seo.sh:141` asserts only that `rel="canonical"` is *present* on
each page — it does **not** assert the canonical **href host** is the apex. A
future change that regressed `site.url` to `www` (re-introducing the exact
"Google chose different canonical" failure this report is about, site-wide) would
**pass** the current per-page gate. The sitemap gate (line ~81) already guards
`<loc>` host single-ness; this extends the same invariant to the per-page
`<link rel="canonical">` href.

**Change (single file):** `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`

```bash
# After the existing presence check (~line 141), add a host-value assertion.
# Extract the canonical href host; fail if it is not the apex.
CANON_HREF=$(grep -oiE '<link[^>]+rel="canonical"[^>]*>' "$f" \
  | grep -oiE 'href="https?://[^/"]+' | sed -E 's|.*href="https?://||' | head -1)
EXPECTED_HOST="soleur.ai"   # apex per #4573/#4584; mirror of _data/site.json site.url host
if [[ -n "$CANON_HREF" && "$CANON_HREF" != "$EXPECTED_HOST" ]]; then
  fail "$page canonical host is '$CANON_HREF' (expected apex '$EXPECTED_HOST') — would induce GSC 'Google chose different canonical'"
else
  pass "$page canonical host is apex ($EXPECTED_HOST)"
fi
```

- **Fold-in criterion:** if the implementer judges the ~10-line gate cheap and
  the apex-canonical invariant worth a CI guard (it directly prevents the class
  this report is about), add it with AC3/AC4 and `Closes #<tracking>`.
- **Defer criterion:** if scope discipline is preferred (the reported issue needs
  no code), file the gate as its own tracking issue (re-eval after this GSC report
  validates green) and ship **zero code** — a pure operator-action PR with `Ref`.
- **DO NOT** hardcode the host in two drifting places without a note: the comment
  must state `mirror of _data/site.json site.url host`. (If a future host flip is
  ever wanted, both move together — same coupling the existing host gates carry.)

### Phase 3 — Tracking + ship

1. Create/update a GitHub tracking issue: "GSC Duplicate-canonical (www variant)
   — best-claude-code-plugins-2026 — VALIDATE FIX + wait". Body: the
   reconciliation table, the live evidence, AC6/AC7. Label per `gh label list`
   (verify labels exist before citing — likely `seo` does NOT exist; use
   `domain/marketing` or `chore` + `priority/p3-low`, confirm at issue-create time).
2. PR body uses **`Ref #N`** (NOT `Closes #N`) — the actual resolution is the
   post-merge operator VALIDATE FIX, not the merge. (`wg-use-closes-n-in-pr-body`
   ops-remediation corollary.) Close the issue post-validation in AC7.
3. If Phase 2 is deferred → the PR is docs/spec-only (this plan + tasks + tracking
   issue). If folded in → PR also carries the `validate-seo.sh` gate.

---

## Out of Scope (confirmed, no action)

- **"Page with redirect" CSV (24 URLs)** — already-triaged benign 3xx class,
  hardened in merged **PR #4729** (`feat-one-shot-gsc-sitemap-redirect-leak`).
  Confirmed `gh pr view 4729` = MERGED. AC5 confirms the sitemap still emits zero
  redirecting locs (no regression). **No new action.**
- **External syndication / dev.to / Medium / Hashnode canonical-back** — does not
  exist; `social-distribute` links out with UTM, no republication. Nothing to do.
- **Changing `site.url` to www** — would be the *wrong* fix and regress #4573.
  Explicitly forbidden (AC1).
- **The "best Claude Code plugins 2026" SEO content-gap** (competing listicles
  outrank on the head term) — a separate marketing/content opportunity flagged in
  prior audits, **not** a canonical bug. Out of scope here; the campaign-calendar /
  growth-strategist owns it.

---

## Hypotheses (considered and dispositioned)

| Hypothesis | Disposition | Evidence |
|---|---|---|
| On-site self-canonical points to www (renders a redirecting canonical) | **Rejected** | `site.url = apex`; live canonical = apex |
| External full-text syndicated copy missing canonical-back | **Rejected** | social-distribute links out (UTM); web search found only independent competing listicles |
| Self-duplication via full-content RSS/atom or `?utm=` URL variants indexed separately | **Rejected** | feed references `/blog/feed.xml`; UTM links carry no full HTML body; canonical consolidates query variants to apex |
| **www variant 301→apex; Google consolidated www onto apex self-canonical (benign)** | **ACCEPTED** | live 301 + apex 200 + apex self-canonical; matches #4584 contract; matches `2026-06-01-gsc-page-with-redirect-is-historical-memory` learning |

---

## Research Insights

- **Prior precedent (decisive):** `knowledge-base/project/learnings/2026-06-01-gsc-page-with-redirect-is-historical-memory-verify-against-build.md`
  — GSC URL lists are Google's *historical memory* of old www/`.html`/`?ref=`
  variants that correctly 301 to apex; **never chase a GSC URL list as a bug list.**
  This is the canonical learning for this entire class.
- **Canonical-host direction settled:** `2026-05-29-canonical-constant-flip-must-grep-consumers-that-assert-old-value.md`
  (PR #4573 flipped www→apex) + `2026-05-29-infra-codify-www-apex-canonicalizer-plan.md`
  (#4584 — the 301 is GitHub-Pages/Fastly-owned via repo `CNAME = "soleur.ai"`;
  DNS substrate Terraform-managed in `dns.tf`, drift-detected by
  `scheduled-terraform-drift.yml`). Apex is canonical **by design**.
- **Existing CI gates (relevant, passing):** `validate-seo.sh` already has
  (a) a redirect-stub gate (sitemap emits no `.html`//`pages/` locs) and (b) a
  canonical-host gate (single `<loc>` host == robots.txt Sitemap host). The
  per-page canonical-tag check (`:141`) is **presence-only** — the optional Phase 2
  gap.
- **Stale audit refuted:** `marketing/audits/soleur-ai/2026-03-25-seo-audit.md`
  claimed canonical/OG tags "not rendering in production" — live `curl` shows
  canonical count = 1; that finding described a since-fixed build state.
- **Competing SERP (not duplicates):** web search for the article framing returns
  Firecrawl, Composio, TurboDocx, Substack, and Medium-author listicles — all
  *independent* articles competing on the head term, none a copy of Soleur's post.
  ([Composio](https://composio.dev/content/top-claude-code-plugins),
  [Firecrawl](https://www.firecrawl.dev/blog/best-claude-code-plugins),
  [TurboDocx](https://www.turbodocx.com/blog/best-claude-code-skills-plugins-mcp-servers).)
- **`validate-seo.sh` host pin coupling:** the proposed `EXPECTED_HOST="soleur.ai"`
  mirrors `_data/site.json` `site.url` host — a deliberate second-site pin, same
  pattern the sitemap/robots host gate already uses.

---

## Domain Review

**Domains relevant:** Marketing (SEO) — advisory.

### Marketing (SEO)

**Status:** reviewed (inline — single-domain `seo-diagnostic` lane; the entire plan
*is* the SEO assessment, corroborated by `seo-aeo` skill artifacts and prior audits).
**Assessment:** The reported GSC class is the benign `www→apex` consolidation, not a
content-duplication or missing-canonical defect. On-site signals (self-canonical,
og:url, JSON-LD WebPage url, atom feed, unique seoTitle/description) are all correct
and apex-pointing. No content rewrite, no canonical-back artifact, no host change is
warranted. The only sanctioned action is operator VALIDATE-FIX + wait. The optional
`validate-seo.sh` host-value gate is pure regression-hardening that prevents a future
host-flip regression from silently re-introducing this exact class site-wide.

### Product/UX Gate

**Tier:** none — no UI surface. No `## Files to Create`/`## Files to Edit` path
matches a UI-surface glob (only a CI shell script + docs). Skipped.

---

## Infrastructure (IaC)

**None.** This plan introduces no server, service, cron, secret, DNS record, or
vendor account. The `www→apex` 301 and DNS substrate are **already** Terraform-managed
(`apps/web-platform/infra/dns.tf`, #4584) and drift-detected; this plan reads that
state for verification only and changes nothing in `infra/`. The optional Phase 2
edit is a CI shell-script gate, not infrastructure. Skip.

---

## Observability

Not applicable as a 5-field schema: this plan ships at most a CI lint gate
(`validate-seo.sh`) and docs — no `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`,
or `plugins/*/scripts/` runtime surface, and no new infrastructure. The relevant
"liveness signal" for the underlying invariant already exists and is **named, not
added**:

- **www→apex 301 drift:** `sentry_uptime_monitor.soleur_www`
  (`apps/web-platform/infra/sentry/uptime-monitors.tf`) — alerts if the 301 breaks.
- **Sitemap host/redirect-stub regressions:** `validate-seo.sh` in CI
  (`deploy-docs` workflow) — fails the build on a multi-host sitemap or redirecting loc.
- **Optional Phase 2 gate:** the per-page canonical-host assertion would join the
  same CI gate (`discoverability_test`: run `validate-seo.sh _site` locally — **no
  ssh** — and observe pass/fail in CI logs).

Per the gate's skip conditions (pure-CI-lint + docs, no new code/infra runtime
surface), a full observability schema is not required.

---

## Files to Edit

- `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` — **OPTIONAL** (Phase 2):
  add per-page canonical-href host assertion. Fold-in or defer per Phase 2 criteria.
  If deferred, this list is **empty** and the PR is docs/spec-only.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-gsc-duplicate-canonical-best-plugins/tasks.md`
  (this plan's task breakdown).
- (Plan file itself, already created.)

## Open Code-Review Overlap

None — no open `code-review`-labelled issue touches `validate-seo.sh` (the only
candidate file). Recorded so the next planner sees the check ran.

---

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This plan's threshold = `none`, with a non-empty reason — filled.)
- **Do not "fix" `site.url` to www.** It reads like the obvious fix for "www URL
  flagged" but is the inverse of the correct direction (#4573 flipped *to* apex).
  AC1 guards this.
- The Phase 2 `EXPECTED_HOST="soleur.ai"` is a **second pin** of the canonical host
  (mirrors `_data/site.json`). If a host flip is ever wanted, both must move
  together — the comment must say so, matching the existing sitemap/robots gate
  coupling.
- **GSC "Validate Fix" is genuinely operator-only** (no API, SSO/CAPTCHA-gated).
  This is the rare sanctioned operator step — do not invent an automation for it,
  but DO bake the `gh pr ready`/`gh pr merge`/`gh issue close` steps that *are*
  automatable into ship, not the operator checklist.
- Before citing any GitHub label in the tracking issue, run
  `gh label list --limit 200 | grep -E "^<label>\b"` — `seo` likely does not exist;
  fall back to `domain/marketing` / `chore` / `priority/p3-low`.
