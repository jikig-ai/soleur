---
date: 2026-06-08
topic: shortform-feature-tweets
lane: cross-domain
brand_survival_threshold: single-user incident
status: complete
---

# Short-Form Feature Tweets — Brainstorm

## What We're Building

A new `soleur:feature-tweet` skill that turns a feature **just shipped to production**
(a merged PR) into a short-form X/Twitter post — single tweet or a 2–3 tweet thread —
without requiring a long-form blog post first. The skill writes a **draft**
`distribution-content/<date>-<slug>.md` file that the existing `content-publisher.sh`
cron pipeline already knows how to publish, so no new publishing path is built.

`/soleur:postmerge` invokes the skill **after its production-health check passes**, so we
only ever draft a tweet about a feature that actually deployed and is verified live. The
skill is also runnable standalone (`/soleur:feature-tweet #<pr>`) as a catch-up escape hatch.

This closes a precise gap: today the only route to social is `social-distribute`, which has a
**blog post as a hard prerequisite**. `changelog` already analyzes merged PRs and classifies
user-facing features by label, but emits only an internal Discord changelog. Neither produces
a blog-less, short-form X post tied to a single shipped feature.

## Why This Approach

- **Reuse over rebuild.** A short-form tweet is just a `distribution-content` file with a
  `## X/Twitter Thread` section of 1–3 tweets. The cron publisher, the `extract_tweets`
  parser (single-tweet already works), the Liquid-marker lint gate, and the campaign calendar
  all consume that format verbatim. The only net-new code is the *generator* + a shared
  merged-PR detection helper.
- **postmerge trigger = "shipped to production" literally.** Gating on the prod-health check
  means we never tweet a feature that didn't actually deploy (the operator's own framing and
  the CTO's recommendation). `ship` is too early (pre-deploy); per-merge auto-trigger is too noisy.
- **Thin standalone skill, not an overload.** Keeping generation in its own
  `feature-tweet` skill (vs. extending `changelog` or inlining into `postmerge`) keeps the
  brand-critical exclusion/sanitization logic single-responsibility, independently testable,
  and reusable as a manual escape hatch.
- **Draft-gate = existing proven pattern.** `status: draft` → operator sets `publish_date`
  and flips to `scheduled` → cron publishes. No straight-through auto-post.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Pipeline | Reuse `distribution-content/*.md` + `content-publisher.sh` | Publisher is source-agnostic; single-tweet file already works (extract_tweets END-emit) |
| Trigger | `/soleur:postmerge`, gated on prod-health check passing | Only tweet verified-live features; matches "shipped to production" framing |
| Generator location | New thin `soleur:feature-tweet` skill | Single-responsibility, testable, manual escape hatch; postmerge calls it |
| PR detection | Extract `changelog`'s inline `gh pr` logic into shared `scripts/lib/recent-merged-prs.sh` | No shared helper exists today; prevents time-window/label drift between skills |
| Tweet-worthiness | `changelog`'s existing label classifier: `type/feature` + `user-facing` | Don't invent a new selector; reuse classification |
| Voice source | `brand-guide.md` `## Voice` + `## Channel Notes > ### X` (inline-validated) | Single voice spec; no separate brand-voice reviewer (per 2026-02-12 learning) |
| Brand-guide update | Extend `### X` channel notes with ship-tweet voice: lead build-in-public peers, hook buyers with a concrete benefit | Operator-requested; keeps one source of truth |
| Approval gate | `status: draft` until operator flips to `scheduled` | Existing proven gate; no auto-post |
| Tweet format | Canonical **numbered** authoring (`2/`, `3/`); single tweet = hook only | Prevents silent 5→1 thread collapse (#2496) |
| Visual design | N/A — no UI surface (produces markdown content files) | Phase 3.55 trigger boundary not met |

## User-Brand Impact

- **Artifact:** auto-generated public tweets about every production ship.
- **Vector:** (1) premature/amplified disclosure of a security fix before patch-adoption windows
  close; (2) leaking unannounced / internal / dark-launched work tipping competitors;
  (3) off-brand or inaccurate copy; (4) silent no-op missing the engagement window.
- **Threshold:** `single-user incident` — one bad public tweet is a brand event.
- **Mandatory guardrails (CLO verdict — all required):**
  1. **Fail-closed label/path exclusion.** Deny `security`, `type/security`, `infra`,
     `internal`, `dark-launch`/flagged labels + path globs (auth, migrations, secrets, CI/infra).
     **Unlabeled or ambiguous PRs default to excluded.**
  2. **Human approval gate.** Nothing reaches the publish queue without the operator flipping
     `status: draft → scheduled`. Approval-fatigue is why the exclusion floor must shrink the
     set *before* drafts are seen.
  3. **Content sanitization.** User-facing benefit only — no implementation/diff detail, no
     contributor PII / author attribution, no customer names (explicit customer-name/NDA scan
     the label filter cannot catch).
  4. **Draft-only posture** (recommended) clears X/LinkedIn automated-posting ToS exposure;
     auto-publish would require the official paid X API tier and professional review first.

## Open Questions

- **Default channels for ship tweets:** `x` only, or `x, bluesky`? LinkedIn personal-profile
  automation is ToS-restricted (CLO); Bluesky/Discord are low-risk. Lean `x, bluesky`; decide at plan time.
- **Count-assertion test:** add a test asserting "author N tweets → publisher posts N" to harden
  against the silent-thread-collapse regression class (#2496) — recommended in-scope.
- **Liquid/markdownlint hazards:** hashtag corruption (`# tag`) and Liquid-marker leaks are known;
  reuse the `<!-- markdownlint-disable-next-line MD018 -->` pragma and run `lint-distribution-content.sh`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Product, Legal. (Operations, Sales, Finance, Support — not relevant.)

### Marketing (CMO)

**Summary:** Right lever — the real gap is *cadence*, and ship events are a free, authentic posting
trigger that decouples social from blog-writing. Reuse the `changelog` classifier and the existing
publisher; the net-new piece is a generator, not a pipeline. Ship-tweet voice = present-tense,
first-person build-in-public, concrete benefit. Mandatory human-approval gate given brand-critical tag.

### Product (CPO)

**Summary:** Integration gap, not greenfield. Smallest valuable product = a thin generator emitting
the existing `distribution-content` format, draft-gated, operator/batch cadence — not auto-hooked on
every merge. Reuse `changelog`'s user-facing label classifier as the selector. One net-new adapter,
not a parallel skill.

### Engineering (CTO)

**Summary:** Cheapest correct path is reuse (LOW risk) — publisher is source-agnostic and a single-tweet
file already works via `extract_tweets` END-emit. No shared merged-PR helper exists (changelog's `gh`
logic is prose-only); extract one to prevent drift. Trigger on `postmerge` gated on the health check.
Emit canonical numbered format. Risk: unreviewed auto-tweets on the brand-critical surface — require
the label filter + draft status.

### Legal (CLO)

**Summary:** SHIPPABLE only with guardrails 1+2+4 mandatory (3 recommended). "Merged to prod" ≠ "safe to
announce" — a tweet *amplifies* a security-fix diff to a non-watching audience and collapses
patch-adoption windows. Fail-closed exclusion floor + human approval ceiling + benefit-only sanitization
(no PII/customer names) are all required; draft-only is the cleanest ToS posture. Not legal advice —
exclusion deny-list + any auto-publish posture need professional review before shipping under the tag.

## Capability Gaps

- **Merged-PR → short-form distribution-content generator — MISSING.** Evidence:
  `ls plugins/soleur/skills/ | grep -iE "tweet|short"` → none; `social-distribute` SKILL.md:35
  makes blog-post path a **hard** prereq; `changelog` outputs Discord-only. This is the one net-new skill.
- **Shared merged-PR detection helper — MISSING.** Evidence:
  `find plugins/soleur scripts -name "*.sh" | xargs grep -lE "gh pr list .*merged|gh search prs"` → none;
  `changelog/SKILL.md:26` only says "use gh cli". Extract `scripts/lib/recent-merged-prs.sh`.
- **postmerge → content hook — MISSING** (but `ship` has a CMO Content-Opportunity Gate at
  `ship/SKILL.md:478` as prior art). Evidence: no `social|distribution|announce` match in `postmerge`.

## Related Learnings (constraints carried into the plan)

- `2026-04-17-extract-tweets-numbered-format.md` — emit canonical numbered format; add count-assertion.
- `2026-04-17-distribution-content-liquid-marker-leak.md` — render/strip Liquid before publish; lint gate.
- `2026-03-11-multi-platform-publisher-error-propagation.md` — return non-zero on real failures.
- `2026-03-20-stale-content-publisher-duplicate-warnings.md` — idempotent status transitions.
- `2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md` — `allowed_mentions:{parse:[]}` if Discord channel included.
- `2026-03-24-agent-hallucinated-author-name-from-org-context.md` — read `site.author.name`, never infer.
- `2026-02-12-brand-guide-contract-and-inline-validation.md` — inline-validate vs brand guide; no separate reviewer.
- `2026-03-06-blog-citation-verification-before-publish.md` — "no naked numbers"; verify or omit stats.
- `2026-03-13-platform-integration-scope-calibration.md` — keep day-one scope to generation + existing publish path.
