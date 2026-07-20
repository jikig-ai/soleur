# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-20-fix-gsc-404-cdn-cgi-email-protection-plan.md
- Status: complete

### Errors
None. Two self-corrections during planning, both folded into the plan's Sharp Edges:
- An `&&`-chained verification silently truncated on a zero-match `grep` (trap already recorded in this repo's learnings).
- `grep -c` undercounted occurrences on minified HTML (reported 1 where there were 2).

### Decisions
- **Root cause verified live, not assumed.** Cloudflare Email Obfuscation rewrites `mailto:`
  hrefs and plaintext addresses into `/cdn-cgi/l/email-protection` — 30 occurrences site-wide
  (privacy-policy alone accounts for 20). Confirmed edge-injected: zero `cdn-cgi` strings in
  committed source.
- **Remedy reversed at deepen-plan from robots.txt `Disallow` (Option B) to a host-scoped
  Cloudflare Configuration Rule (Option C)** — `http_config_settings` / `set_config` /
  `email_obfuscation = false`, scoped to `soleur.ai` + `www.soleur.ai`. Three independent
  grounds: (1) Google explicitly advises against using robots.txt to block 404s; (2) robots.txt
  cannot de-index and 30 internal links supply the indexing precondition; (3) the repo already
  learned this on this same zone six weeks ago
  (`2026-06-14-gsc-indexed-though-blocked-by-robots-is-a-real-misconfig-not-benign.md`).
  Provider feasibility verified against the pinned version (4.52.7).
- **`api.soleur.ai`: assessed, no change.** Both proposed remedies are structurally inert on a
  DNS-only CNAME; a dormant rule already exists and 3 tests already assert it.
- **`/pages/legal/terms-of-service.html`: deliberately untouched** — already 301s correctly.
  Stale GSC history, not a live defect.
- **Two review findings dissolved scope rather than adding it:** the gate was kept out of
  `validate-seo.sh` (distributed plugin skill; shared fixture would have turned 21 green tests
  red), and the CTA `[email protected]` rendering defect now repairs itself under the new
  remedy with no source edit.
- **Phase 4 cut (unanimous, 5 agents):** a proposed `scripts/followthroughs/` probe for
  `api.soleur.ai` would have auto-closed its tracker issue on the first sweep, because the
  sweeper closes on exit 0 and the asserted condition is already true today.

### Operator tradeoff recorded
Disabling obfuscation makes marketing-page contact addresses (`ops@jikigai.com`,
`hello@soleur.ai`, `legal@jikigai.com`) plaintext and harvestable. Assessed as cheap friction
rather than a security control (`data-cfemail` is a single-byte XOR). Escalation if spam
becomes material is a contact form or alias — not re-enabling obfuscation, which would
reintroduce this bug. Full record in `decision-challenges.md`.

### Components Invoked
`soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`; agents: `best-practices-researcher`
x2, `repo-research-analyst`, `learnings-researcher`, `dhh-rails-reviewer`,
`kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`,
`spec-flow-analyzer`, `cmo`, `general-purpose` (verify-the-negative sweep).
