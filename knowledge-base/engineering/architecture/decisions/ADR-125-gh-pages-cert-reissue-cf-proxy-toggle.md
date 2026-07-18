---
title: "Event-triggered GitHub Pages cert remediation: replay-safe CF-proxy toggle + App-token reissue, as a narrow AP-001 exception"
status: accepted
date: 2026-07-18
issue: 6657
supersedes: null
---

# ADR-125: event-triggered GitHub Pages cert `bad_authz` remediation via a transient CF-proxy toggle

## Context

The `soleur.ai` GitHub Pages custom-domain TLS certificate periodically wedges in the ACME
state `bad_authz` ("The ACME authorization is in a bad state. We need to start over."). The
cert covers `soleur.ai` + `www.soleur.ai`; when it hard-expires, Cloudflare (Full SSL, origin =
GitHub Pages) returns **526** to every visitor — the exact 2026-05-18 public-brand outage. The
daily `cron-gh-pages-cert-state` poll files an `action-required` issue (#6657) but performs no
remediation; the referenced #3976 runbook marked the reissue step `type: manual`
(`manual_because: "GH Pages Settings UI is not API-equivalent for cert-reissue trigger"`).

Two facts refute the manual framing and shape the design:

1. **The reissue trigger IS API-reproducible.** The console "remove custom domain → re-add"
   gesture is `PUT /repos/{owner}/{repo}/pages` (`cname:null` → re-set), which needs
   `Administration: write` — a permission the Soleur GitHub App already grants. Verified live
   2026-07-18: the App manifest declares `administration: write`.
2. **The likely root cause is the Cloudflare proxy.** The apex A-records + www CNAME are
   `proxied=true` (orange-cloud), so GitHub/Let's Encrypt's domain-config / HTTP-01 validation
   sees CF anycast IPs (`188.114.x`) instead of GitHub's `185.199.x` origins and the
   authorization never completes. The 2026-05-18 postmortem documents this exact blocker; the
   recovery is a transient DNS-only window (`proxied=false`) during re-issuance.

GitHub exposes only the terminal string `bad_authz` — the internal LE reason is unobservable — so
the remediation is **empirical**: perform the "start over" while presenting a DNS-only apex+www,
then observe whether the state progresses to `issued`. Soleur operators are non-technical
(`hr-weigh-every-decision-against-target-user-impact`), so the remediation must be fully scripted
with zero console steps.

A runtime process that `PATCH`es live Cloudflare DNS is an **off-Terraform live-infra mutation** —
exactly what AP-001 / ADR-019 govern. The design must not claim "compliant because no `.tf`
drift"; it must register an explicit, narrow, sanctioned exception.

## Decision

Ship an **event-triggered Inngest routine** `cron-gh-pages-cert-reissue` (v1 = manual-trigger
only, via `POST /api/internal/trigger-cron`; `retries: 1`; fn+account concurrency = 1) that:

1. **Preflight (fail-loud, zero-write on abort):** re-reads `GET /pages`; proceeds **only** if
   `state ∈ {bad_authz, failed}` (an allowlist — toggling a healthy in-flight order can
   *manufacture* a new `bad_authz`); verifies auto-fixable preconditions (ACME carve-out 404,
   `always_use_https=off`, CAA permissive, `_github-pages-challenge` TXT present).
2. **Toggle + reissue (ONE `step.run`):** flips the 4 apex A-records + www CNAME to
   `proxied=false` via a **distinct DNS-edit-only Cloudflare token** (`CF_API_TOKEN_DNS_EDIT`);
   aborts→restores on any partial toggle; then `PUT /pages cname:null` → settle → re-set, using a
   **least-privilege App token** (`generateInstallationToken({ permissions: { administration:
   "write" }, repositories: ["soleur"] })`).
3. **Poll (`step.sleep`):** `GET /pages` up to ~15 min for `state ∈ {approved, issued}`.
4. **Restore:** an **unconditional final `step.run`** re-asserts the declared steady state
   (`proxied=true`, `cname=soleur.ai` — symmetric on both fields), **plus an `onFailure`
   lifecycle handler** that idempotently restores on any throw / retry-exhaustion.

This is registered as a **narrow AP-001 exception (new AP-019 row)** — transient, self-reverting,
single-attempt, human-gated — NOT compliance-by-no-drift. It references **ADR-077** (routine
replay-safety contract) for the step structure and **ADR-033** (Inngest cron substrate), which it
extends with a write-to-live-infra capability.

The restore MUST be a final step + `onFailure` handler, **not a JS `try…finally`**: `step.sleep`
suspends via a control-flow throw that runs `finally` prematurely at the first poll pass, restoring
the proxy before the cert validates and collapsing the DNS-only window (then the memoized toggle-off
step never re-runs → silent timeout).

**v1 accepts a documented residual drift race** (see Consequences); the drift/apply freeze-lock
coordination and self-heal auto-invoke are **deferred to v2** (#6677).

## Alternatives Considered

- **Leave #3976's reissue step manual (operator uncheck/recheck).** Rejected: non-technical
  operators; violates `hr-exhaust-all-automated-options-before` + the never-defer feedback. The
  "must be manual" claim is refuted — the trigger is API-reproducible with a grant the App has.
- **DNS-only reissue WITHOUT the proxy toggle (cname toggle only).** Rejected as sole path: the
  primary hypothesis predicts re-fail while proxied; the postmortem shows the domain-config check
  needs GitHub's origin IPs visible.
- **Persist `proxied=false` in `dns.tf`.** Rejected: permanently drops CF WAF/DDoS + origin-IP
  hiding — a standing security regression. The toggle must be transient and self-reverting.
- **A GitHub Actions workflow (mint App JWT in CI, run the script).** Rejected as primary:
  duplicates the App-token minting already available in the Inngest runtime; the Inngest function +
  `trigger-cron` gives a console-free scripted path with better observability.
- **`-target`ed Terraform apply for the toggle instead of the CF API.** Rejected: fights the same
  drift/apply race, slower, and the records are not in the apply `-target` allowlist.
- **JS `try…finally` restore.** Rejected (blocking, replay-unsafe): `step.sleep` runs `finally`
  prematurely at the first poll → window collapses (ADR-077). Replaced by a final step + `onFailure`.
- **Reuse "ADR-089 freeze-lock" for drift/apply coordination.** Rejected: ADR-089 is an
  **edit-time PreToolUse path-prefix guard** over a gitignored `.claude/.freeze-lock` file — it
  locks editing tool calls, not DB rows or infra resources, and is unreadable from the Inngest/GHA
  runtimes. Citing it would encode a structurally absent dependency. A real runtime lock (Supabase
  lease row consulted by guard steps inside the GHA apply + drift workflows) is deferred to v2, where
  unattended firing makes it load-bearing (CTO ruling 2026-07-18).
- **Ship self-heal auto-invoke in v1.** Deferred (#6677): autonomous live-infra mutation from a
  03:00 cron is over-reach and needs a cross-invocation cooldown store (Inngest is stateless). v1's
  human-gated manual trigger satisfies "scripted, no console" without it.

## Consequences

- **Positive:** #6657-class incidents are remediated by a scripted, self-restoring routine with
  zero console steps; the least-privilege scoped App token + DNS-edit-only CF token bound leak
  blast radius; every terminal outcome emits one discriminating Sentry event.
- **Residual race (v1, accepted):** during the ~5–15 min DNS-only window, live `proxied=false`
  diverges from Terraform-declared `proxied=true`. The mutating racer
  (`apply-web-platform-infra.yml` push-apply) **cannot** touch these records — they are not in its
  `-target` allowlist. The drift racer (`cron-terraform-drift`, `0 6,18 * * *`) degrades to at most
  a spurious `infra-drift` **page** (~2% window-overlap odds, no auto-apply). Any early
  `proxied=true` surfaces immediately as `poll_timeout`/`reissue_failed` → Sentry P0 → operator
  re-fires. Documented as a Sharp Edge; the runtime coordination lock is deferred to v2 (#6677),
  where unattended firing removes the operator-in-the-loop backstop.
- **Blast radius during the window:** CF WAF/DDoS + origin-IP hiding are absent on apex+www.
  Acceptable because the still-valid cert keeps traffic serving, the window is bounded, and the
  final step + `onFailure` guarantee return to the protected steady state; a failed restore pages
  P0 (`proxy_restore_failed`).
- **New IaC:** a distinct `cloudflare_api_token` (Zone.DNS:Edit on the soleur.ai zone) published to
  Doppler `prd` as `CF_API_TOKEN_DNS_EDIT`.
