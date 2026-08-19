# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-17-fix-sentry-audit-rules-api-deprecation-plan.md`
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope verified: `git diff f5f51c84b..HEAD --name-only` → plans/ + specs/ only. Plan-only mandate held.

### Errors

Reported by the planning subagent, and independently checked where the claim reversed the parent's brief:

- **Fabricated attribution (self-reported).** The subagent described findings as coming from a `cto` review before any CTO review had returned, then verified those findings against the repo afterwards. It corrected this in-session. The underlying facts were real; the attribution was not. Treated here as a reason to verify its reversals rather than accept them.
- **`cto` review agent never returned.** Its lens — bash-as-substrate, tripwire maintenance cost, build-vs-buy for deprecation tracking — is genuinely unexamined. This bears directly on the plan's decision to BUILD a proactive deprecation tripwire, so it is carried into the review step rather than closed here.
- **The parent brief's "both branches → `workflows/`" was WRONG** — corrected by the plan, and independently re-verified live before accepting:
  - `projects/{org}/{proj}/rules/` → `x-sentry-replacement-endpoint: /api/0/organizations/{org}/workflows/`
  - `organizations/{org}/alert-rules/` → `x-sentry-replacement-endpoint: /api/0/organizations/{org}/detectors/`

  The mapping is per-endpoint. Following the brief would have mis-mapped metric alerts onto the issue-alert replacement.
- Subagent's own falsified premises, caught by its review panel: the "orphan test suite" premise (registration is by glob, an explicit `run_suite` line would have double-registered and reddened the required `test` check); the initial `curl_retry` prescription (adding `-w '%{http_code}'` inside the wrapper collides with Gates 2/3, which pass their own `-w`, corrupting healthy 200 bodies); "the four gates are unchanged" (Gates 1–3 call `curl_retry`, Gate 4 consumes `gate1_body`, so the wrapper rewrite IS in their blast radius); "manifest has no live consumer" (`infra/sentry/README.md` extracts it, T7 tests the coupling).

### Decisions

- Endpoint mapping is per-endpoint, taken from Sentry's own response headers. Both replacements are org-scoped, so the `fetch_rules()` project-vs-org branch dissolves entirely.
- **No brownout-sized retry.** The brownout window is a Sentry-owned runtime option and the assumed `0 */2 * * *` schedule is not supported by the failure timestamps. Decisive argument: a retry long enough to swallow a brownout 410 necessarily also masks a post-sunset 410 — the permanent case this gate exists to catch. Replaced with status-aware, idempotency-aware classification plus a proactive deprecation tripwire.
- Cursor-following is mandatory for `detectors/`/`monitors/`; `detectors/` grows 1:1 with monitors, so fail-on-truncation would deadlock the deploy path through ordinary growth. Link-header targets are never followed as given — Sentry's Link headers are absolute, and an `<@attacker.tld/…>` form makes curl treat the prefix as userinfo (credential-exfiltration vector).
- **Orphan detection was already broken before the deprecation.** `monitor.slug` matches 0 rows and 0/55 slugs appear in the payload, so Class A has flagged every monitor since day one. Remapped to a count plus the invariant `class_a_count == cron_detector_count`, with a fail-closed extraction guard.
- Recommends AGAINST making the gate a required check; the honest sequencing is a hermetic/live split first.

### Components Invoked

- Skills: `soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`
- Agents: `repo-research-analyst`, `learnings-researcher`, `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, `cto` (spawned, NO RESULT)
- Cost: ~520k subagent tokens, 106 tool calls, ~53 min wall-clock.

## Carried Into Review

1. The unexamined `cto` lens on build-vs-buy for the deprecation tripwire — the plan chose BUILD without that challenge.
2. Scope breadth: the plan grew beyond the endpoint fix to include pagination, Link-header SSRF hardening, a deprecation tripwire, and an orphan-detection remap. Each is individually justified; the aggregate deserves a simplicity pass.
