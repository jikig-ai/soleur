# Decision challenges — feat-one-shot-gsc-404-cdn-cgi-email-protection

Recorded headless during plan review (6-agent panel) and deepen-plan, 2026-07-20. Per
ADR-084 these were **not** silently auto-applied. `/ship` renders this into the PR body and
files an `action-required` issue.

---

## RESOLVED at deepen-plan — UC-1: Option C adopted (plan reversed)

**Status: no longer an open question — the plan changed.** Recorded because the reversal is
significant and the operator should know it happened.

The plan-review panel challenged the choice of `Disallow: /cdn-cgi/` (Option B) and argued
for a host-scoped Cloudflare Configuration Rule (Option C). Deepen-plan research settled it
**against Option B** on three independent grounds:

1. **Google explicitly advises against it for this exact case**, verbatim: *"Don't create
   fake content, redirect to your homepage, or use robots.txt to block 404s — all of these
   things make it harder for us to recognize your site's structure."*
   ([support.google.com/webmasters/answer/2445990](https://support.google.com/webmasters/answer/2445990))
   Cloudflare's `Disallow: /cdn-cgi/` recommendation is generic hygiene for sites with no
   GSC 404 report on that path; Google's guidance is specific to the situation we have.
2. **robots.txt cannot de-index, and we supply the indexing precondition.** Google: *"A page
   that's disallowed in robots.txt can still be indexed if linked to from other sites"*, and
   *"it is not a mechanism for keeping a web page out of Google."* There are **30 internal
   links from indexed pages** to the target. Option B would have removed the 404 signal that
   retires the URL while leaving the links that keep it discoverable.
3. **The repo already learned this**, six weeks ago, on this same zone:
   `knowledge-base/project/learnings/2026-06-14-gsc-indexed-though-blocked-by-robots-is-a-real-misconfig-not-benign.md`
   documents `app.soleur.ai/` becoming indexed *because* a robots.txt `Disallow` stopped
   Googlebot reading the `noindex`. The v1 plan had not applied this learning.

**Outcome:** the plan now disables Email Obfuscation for `soleur.ai` + `www.soleur.ai` only,
via a `cloudflare_ruleset` in the `http_config_settings` phase — removing the 30 hrefs at
source. This is option (a) exactly as the brief framed it (*"disabling Cloudflare Email
Obfuscation for the zone/marketing pages via Terraform"*), scoped to the marketing pages.

**What the operator is accepting by this change:** the marketing pages' contact addresses
(`ops@jikigai.com`, `hello@soleur.ai`, `legal@jikigai.com`) become plaintext and therefore
harvestable. Assessment: what is lost is **cheap friction, not a security control** —
Cloudflare's `data-cfemail` is a single-byte XOR with the key in the first byte, decoded by
off-the-shelf scrapers for over a decade. Plaintext contact addresses on legal pages are
near-universal practice. If spam volume on the DSAR channel (`legal@`) or the founder inbox
(`ops@`) becomes material, the escalation is a contact form or an alias — **not** re-enabling
obfuscation, which would reintroduce this bug.

**Scope change worth flagging:** this moved the work from a 1-line static-file edit to a new
Terraform resource on the auto-applying infra path. Larger, but correct.

---

## RESOLVED as a side effect — UC-2: CTA fallback rendering defect

**Status: fixed by the reversal; no separate decision needed.**

Two reviewers independently flagged that `plugins/soleur/docs/pages/getting-started.njk:22`
ships a deliberate graceful-degradation fallback:

```html
<span class="hero-meta-fallback">(or email <code>ops@jikigai.com</code>)</span>
```

which renders live as literal **`[email protected]`** — the one element whose job is to show
a copyable address instead shows a string that is not an address. The founding-cohort CTA
href is also a 404 for any visitor without JS. Same for `mailto:hello@soleur.ai` at
`pricing.njk:275`.

Under the original Option B this needed a deliberate `.njk` fix (and was being deferred).
Under Option C it **repairs itself** — with obfuscation off on the marketing hosts,
Cloudflare stops rewriting and both the CTA href and the plaintext fallback render
correctly, with no source edit. AC10 asserts this.

Severity was bounded throughout: the hero's primary CTA (`Join the waitlist`) and secondary
CTA (`Run the self-hosted version today`) were never affected — only the tertiary
`hero-meta` line.

---

## Still open — advisory follow-ups

- **"Book intro" CTA is a `mailto:`, not a booking link.** No Cal.com/Calendly exists
  anywhere in the docs. A booking link would likely out-convert a mailto for the
  10-slot founding cohort. Conversion-design question, independent of Cloudflare —
  worth a tracked issue. *(cmo)*
- **28-day GSC re-check** is filed as a follow-up issue (tasks.md 4.1). GSC exposes no API
  for coverage-validation state, so the re-check is human. Note the AC9 occurrence census
  **is** automatable and would make a good followthrough probe if this recurs.

## Also noted (advisory, already folded into the plan)

- **"Security control" framing corrected** to "cheap friction", so the decision cannot be
  reopened by a reviewer who knows the XOR trick. *(cmo)*
- **Stronger arguments surfaced and folded in:** `legal@jikigai.com` is the GDPR/DSAR and
  automated-decision contestation channel (statutory response windows); `ops@jikigai.com` is
  simultaneously the founder inbox and the founding-cohort conversion channel. *(cmo)*
- **Phase 4 cut** (unanimous, 5 agents): a proposed `scripts/followthroughs/` probe for
  `api.soleur.ai` would have **auto-closed #3379 on its first sweep**, because the sweeper
  closes issues on exit 0 and the probe's asserted condition is already true today.
  Follow-through probes are trigger detectors, not regression detectors. *(kieran,
  architecture-strategist, dhh, code-simplicity, spec-flow)*
- **`validate-seo.sh` left untouched:** it is a distributed plugin skill referenced by
  `.openhands/skills/seo-aeo-analyst/SKILL.md` and two Inngest cron prompts; a
  Cloudflare-specific hard FAIL would break consumer sites, and would have turned the green
  21-test `validate-seo.test.ts` suite red via its shared default fixture. *(spec-flow,
  kieran, code-simplicity)*
