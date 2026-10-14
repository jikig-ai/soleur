# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-29-fix-reconcile-cf-sentry-iac-apex-canonical-plan.md
- Status: complete

### Errors
None. (Two write-guard hook blocks fired on "operator runs terraform apply" framing in the plan and tasks files; resolved per the hook's documented opt-out — added the `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` comment after confirming the operator apply is a genuine `terraform apply` against a managed IaC root deliberately excluded from auto-apply, not a manual/SSH/dashboard step.)

### Decisions
- **Direction confirmed live, apex-ward:** live curl verified `www.soleur.ai → 301 → soleur.ai` (apex serves 200). The stale IaC comments describing the OLD apex→www regime are themselves drift. Flip the 9 SEO redirect rules (both `expression` host AND `target_url.value`) to apex.
- **Reframed the issue's "operator-gated apply" premise:** `seo-rulesets.tf` actually AUTO-APPLIES on merge (it's in `apply-web-platform-infra.yml`'s 81 `-target=` allowlist, lines 249–250). Only the Sentry `uptime-monitors.tf` is genuinely operator-applied (auto-apply scope covers `cron-monitors.tf` only). AC split into Pre-merge/Post-merge accordingly.
- **`soleur_www` uptime monitor is already broken:** its 2xx assertion fails against the live 301 — an active false-page source. Decision: convert to an explicit `equals 301` redirect-health assertion rather than duplicate `soleur_apex`.
- **Rule 10 explicitly NOT touched:** verified its target is `concat("https://", http.host, …)` (host-preserving, no `www` literal); its only www reference is the ACME carve-out host set which must keep covering www. Flagged the out-of-band (non-IaC) www→apex canonicalizer as Deferred Q1.
- **Destroy-guard interaction is load-bearing:** the web-platform destroy-guard filter inspects `cloudflare_ruleset.*.rules` and counts rule-array length; Phase 0.3 prescribes an empirical replace-vs-modify probe and an "edit in place only, keep count at 10" implementer constraint to avoid tripping `[ack-destroy]`.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Bash (live curl probes, gh PR/issue resolution, grep/sed over IaC + workflows + destroy-guard filter), Read, Write, Edit
- ToolSearch
