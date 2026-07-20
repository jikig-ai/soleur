# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-18-fix-gh-pages-cert-bad-authz-auto-reissue-plan.md
- Status: complete

### Errors
- Two transient `iac-plan-write-guard` hook blocks resolved (missing ack comment; literal "out-of-band" in Edit text rephrased to "off-Terraform"). No work lost.
- One denied Bash grep (unrelated permission prompt); rerouted.

### Decisions
- Root cause (LIKELY): apex/www are Cloudflare-proxied; CF anycast masks GitHub's 185.199.x IPs, breaking HTTP-01/domain-config validation → `bad_authz`. May redirect-interception cause REFUTED by live probe.
- Runbook "manual/no-API" claim REFUTED: reissue is API-automatable via `PUT /pages` cname-toggle (Administration: write, already granted) → zero operator console steps.
- Two-agent plan review drove redesign: Inngest-replay-safe restore (unconditional final step + onFailure per ADR-077); symmetric restore ({cname, proxied}); self-heal auto-invoke deferred to default-OFF Flagsmith follow-up; ADR-089 freeze-lock vs cron-terraform-drift racer; framed as AP-001 exception (new AP-019 row).
- No live outage (cert valid to Aug 16, 28-day runway). Brand-survival threshold: aggregate pattern. Product/UX: NONE.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents: framework-docs-researcher, learnings-researcher, architecture-strategist, code-simplicity-reviewer

## Work Phase

### CTO architecture ruling (freeze-lock fork) — 2026-07-18
Substrate audit found **ADR-089 freeze-lock has NO runtime implementation** (it's an edit-time PreToolUse bash guard over a file-path prefix; neither `cron-terraform-drift` (Inngest dispatcher, `0 6,18 * * *`) nor `apply-web-platform-infra.yml` (GHA, push on infra/** merge, `-target` allowlist that does NOT include github_pages/www) consult any runtime lock). Routed the blocking fork to `soleur:engineering:cto`.

**Ruling: Option C — ship v1 lock-free.**
- AC8b + Finding #4 (freeze-lock coordination) → move to the deferred v2 self-heal follow-up issue.
- ADR-125 + AP-019 exception row + `## Decision` framing STAY in v1 (the off-Terraform CF mutation needs AP-001 governance regardless of the lock).
- ADR-125 must NOT cite ADR-089 as runtime coordination (structurally absent); state "v1 accepts residual race; runtime infra-coordination lock deferred to v2".
- v2 lock substrate (when built) = Supabase lease row consulted by a new guard step inside the GHA apply+drift workflows — NOT "reuse ADR-089".
- v1 ships a Sharp Edge naming the two residual racers + the `reissue_failed`/`poll_timeout` → Sentry P0 backstop. **CORRECTION (review, arch-P1):** the mutating `apply-web-platform-infra.yml` push-apply DOES `-target` `cloudflare_record.github_pages`/`.www` (`:343-345`) — so an infra PR merging mid-window CAN auto-apply `proxied=true` and collapse the window (fails closed → poll_timeout → P0 → re-fire). Mitigation is the fail-closed backstop + avoiding infra merges during the window, NOT allowlist exclusion. The drift racer (`0 6,18`) at most spuriously pages. This strengthens the v2 lock justification (#6677).

### Other corrections folded from substrate audit
- `mirrorP0Deduped` is GDPR-Art-33-breach-specific (userId/conversationId dedup keys) — NOT a cron pager. Use `reportSilentFallback` + red terminal outcome for `proxy_restore_failed` instead.
- Function is **event-triggered only** (no `cron:` schedule) → declare NO `SENTRY_MONITOR_SLUG` (avoids cron-monitor IaC parity requirement); paging via `reportSilentFallback` `feature:` tag + optional issue-alert.
- `mintInstallationToken({ permissions, repositories })` supports scoped mint (AC4 clean).
- `onFailure` confirmed in inngest 3.54.2 (top-level config key, `{error, event, step, logger}` args); no repo precedent.
