# Decision challenges — feat-one-shot-gsc-404-cdn-cgi-email-protection

Recorded headless during plan review (6-agent panel, 2026-07-20). Per ADR-084 these were
**not** auto-applied — each argues the operator's stated direction should change, so they
are surfaced for a decision. `/ship` renders this into the PR body and files an
`action-required` issue.

---

## UC-1 — Adopt Option C (host-scoped Configuration Rule) instead of robots.txt?

**Raised by:** architecture-strategist (P1), independently supported by the risk analysis.

**The operator's stated direction (the default):** the brief asked to decide between
(a) disabling Cloudflare Email Obfuscation via Terraform and (b) adding
`Disallow: /cdn-cgi/` to robots.txt. The plan chose (b).

**The challenge:** there is a third option the brief did not name. A `cloudflare_ruleset`
in the `http_config_settings` phase can disable `email_obfuscation` scoped by
`http.host in {"soleur.ai" "www.soleur.ai"}` — turning it off **only** for the marketing
site, leaving `app.soleur.ai` and every other host untouched.

**Why it might be better than the chosen option:**

- It **defeats the main objection to Option A** (zone-wide blast radius) while keeping
  obfuscation everywhere it actually matters.
- It **removes the 30 `/cdn-cgi/` hrefs from the link graph entirely**, which is a
  strictly stronger fix than hiding them from crawlers. robots.txt leaves the links in
  place and blocks crawling — which is the textbook precondition for Google's
  "Indexed, though blocked by robots.txt" bucket, a trap **this repo has already hit
  once** with `app.soleur.ai`.
- It is Terraform-native (satisfies AP-001 rather than sidestepping it), and the repo
  already has 5 `cloudflare_ruleset` resources to pattern-match against.

**Why the plan still chose robots.txt:** proportionality. Option C is a new production
infra resource on an auto-applying path, to fix a 404 that Google states does not harm
ranking. It also loses the anti-spam friction on `ops@`/`legal@` for the marketing pages,
and it forgoes the vendor's own documented best practice.

**Current disposition:** Option B ships; Option C is the **defined escalation** if GSC
re-validation surfaces the "Indexed, though blocked" migration (AC11 → Risks row 1).

**Decision needed:** ship Option B as planned and hold C in reserve *(the plan's default)*,
or adopt Option C up front?

---

## UC-2 — Fold the CTA fallback rendering fix into this PR?

**Raised by:** cmo (High) and architecture-strategist (P1), independently.

**The operator's stated direction (the default):** the brief scoped this work to the GSC
404 validation. The plan keeps `plugins/soleur/docs/pages/*.njk` untouched.

**The challenge:** Cloudflare's obfuscation is currently breaking a user-visible element,
independent of any SEO concern. `plugins/soleur/docs/pages/getting-started.njk:22` ships a
deliberate graceful-degradation fallback:

```html
<span class="hero-meta-fallback">(or email <code>ops@jikigai.com</code>)</span>
```

which renders live as **`[email protected]`**. The one element whose job is to show a
copyable address instead shows a string that is not an address — a recognisable
broken-Cloudflare artifact, on a page selling engineering competence, to an audience of
technical builders. `plugins/soleur/docs/pages/pricing.njk:275` (`mailto:hello@soleur.ai`)
has the same issue.

**Severity is bounded:** the hero's primary CTA (`Join the waitlist`) and secondary CTA
(`Run the self-hosted version today`) are unaffected. Only the tertiary `hero-meta` line is.

**Recommended fix if adopted:** wrap in `<!--email_off-->` **and** write the address in a
non-harvestable human form (`ops at jikigai dot com`). Do **not** merely `<!--email_off-->`
the plaintext — that publishes a harvestable address and reintroduces the exact exposure
Option A was rejected for.

**Cost of deferring:** a visibly broken artifact stays on the highest-intent page for
another cycle. **Cost of folding in:** scope the operator did not request, in a PR whose
whole argument is proportionality.

**Current disposition:** deferred, with `/work` filing a tracking issue carrying this
analysis (plan §Deferred).

**Decision needed:** keep deferred with a tracking issue *(the plan's default)*, or fold
the one-line fix into this PR?

---

## Also noted (not a challenge — advisory, already applied)

- **"Security control" framing corrected.** Cloudflare's `data-cfemail` is a single-byte
  XOR whose key is the first hex byte — publicly documented, trivially reversed. The plan
  now argues from "cheap free friction worth keeping" rather than "a security control",
  so the decision cannot be reopened by a reviewer who knows the XOR trick. *(cmo)*
- **Stronger arguments for keeping obfuscation surfaced and folded in:**
  `legal@jikigai.com` is the GDPR/DSAR and automated-decision contestation channel
  (statutory response windows), and `ops@jikigai.com` is simultaneously the founder inbox
  and the founding-cohort conversion channel. *(cmo)*
- **Follow-up worth filing separately:** the "Book intro" CTA fires a `mailto:` with no
  booking link anywhere in the docs (no Cal.com/Calendly found). A booking link would
  likely out-convert it — a conversion-design question independent of Cloudflare. *(cmo)*
