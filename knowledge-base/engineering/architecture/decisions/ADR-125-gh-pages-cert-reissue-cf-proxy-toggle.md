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
   `state ∈ {bad_authz, errored, authorization_revoked, failed}` (an allowlist — toggling a healthy
   in-flight order can *manufacture* a new `bad_authz`); verifies auto-fixable preconditions (ACME
   carve-out 404, `always_use_https=off`, CAA permissive, `_github-pages-challenge` TXT present).
   *(Amended #6698: `errored` and `authorization_revoked` are documented terminal failure states
   that the original `{bad_authz, failed}` allowlist silently declined as `not_stuck`, so a cert
   wedged in either was never remediated. `"failed"` is not a documented state and is retained only
   defensively.)*
2. **Toggle + reissue (ONE `step.run`):** flips the 4 apex A-records + www CNAME to
   `proxied=false` via a **distinct DNS-edit-only Cloudflare token** (`CF_API_TOKEN_DNS_EDIT`);
   aborts→restores on any partial toggle; then `PUT /pages cname:null` → settle → re-set, using a
   **least-privilege App token** (`generateInstallationToken({ permissions: { administration:
   "write", pages: "write" }, repositories: ["soleur"] })`). *(Amended: `PUT /pages` requires
   **BOTH** `administration:write` AND `pages:write` — proven empirically on the live installation,
   pages-only → 403, admin-only → 403, both → 204. GitHub's REST docs do not state this.)*
3. **DNS-propagation gate (`step.run` + `step.sleep`, added #6698):** before polling, observe from
   **public resolvers** (1.1.1.1 / 8.8.8.8) whether the flip has propagated — apex A ⊆
   `185.199.0.0/16`, **no AAAA**, and a post-flip ACME probe whose `Server` header is GitHub's
   rather than Cloudflare's.

   **Only a CONFIRMED AAAA aborts.** Gate *exhaustion* does not: Cloudflare's proxied TTL is a
   fixed, non-editable 300 s, so "not propagated yet" is an ordinary observation, and treating it
   as terminal would make the paging `dns_propagation_failed` the **default** outcome of a
   perfectly correct remediation. The gate budget is therefore sized past one full TTL rollover
   (11 attempts × 30 s = 300 s), and on exhaustion the routine proceeds to the poll while emitting
   an `unconfirmed` marker so a later `poll_timeout` is never misread as "DNS was known good".

   A surviving AAAA is different in kind and IS terminal: Let's Encrypt prefers IPv6 and does not
   fall back from a proxied AAAA that answers successfully with the wrong content, so no window
   length can succeed and proceeding would burn a validation attempt on a guaranteed failure. That
   case alone yields the non-benign `dns_propagation_failed`.

   The gate reads **raw** observations (resolver answers, per-leg error codes, `Server` headers);
   the verdict is a pure exported function, mirroring the existing
   `gatherPreconditions` → `checkReissuePreconditions` split. An inconclusive lookup
   (`ETIMEOUT`/`ESERVFAIL`, as distinct from `ENODATA`) is a `retry`, never a pass — collapsing
   "could not ask" into "the answer is empty" would fail open on exactly the state being checked.
4. **Poll (`step.sleep`):** `GET /pages` for `state ∈ {approved, issued}`, capturing the ENTIRE
   `https_certificate` object per tick (`description` is the only in-band field that has ever
   carried Let's Encrypt-side detail). *(Amended #6698: the gate's budget comes **out of** the
   poll's, not on top — see the window budget below, which shortens the cert poll to 9 ticks from
   the original "~15 min".)*
5. **Restore:** an **unconditional final `step.run`** re-asserts the declared steady state
   (`proxied=true`, `cname=soleur.ai` — symmetric on both fields), **plus an `onFailure`
   lifecycle handler** that idempotently restores on any throw / retry-exhaustion. *(Amended #6698:
   the post-toggle tail has exactly **one** return site, after restore, so "no post-toggle exit
   skips restore" holds by construction — `onFailure` does not fire on a clean early `return`.)*

**Total DNS-only window budget (amended #6698).** The public-TLS-outage window is
`poll + CNAME_SETTLE_MS + gate + step IO`, **not** the poll alone — the original ADR budgeted only
the poll, so the real window already overran by the 45 s settle. `TOTAL_DNS_ONLY_WINDOW_MS`
**bounds** that sum at 14.75 min, reserving a nominal `STEP_IO_ALLOWANCE_MS` for the per-step IO
(GitHub calls at `GITHUB_TIMEOUT_MS`, CF/DNS/ACME at `CF_TIMEOUT_MS`) that sleeps alone do not
count. It is a budget, **not a runtime guarantee**: a pathological run where every call hits its
timeout can still overrun, and the real backstop against an unbounded window is that restore runs
on every exit. A wall-clock (`elapsed()`) break in the loops would NOT make it a guarantee — it
would be a replay hazard, since Inngest re-executes the body on every resume and ADR-077 bans
`Date.now()`-derived control flow there.

**Probe-only mode (added #6698).** A probe fire performs the DNS flip, runs the propagation gate,
and restores — **skipping the cname toggle and the poll entirely**, so it consumes no Let's Encrypt
validation attempt. It is the **default** for manual fires; remediation requires an explicit
`{"probeOnly": false}`.

This is registered as a **narrow AP-001 exception (new AP-019 row)** — transient, self-reverting,
single-attempt, human-gated — NOT compliance-by-no-drift. It references **ADR-077** (routine
replay-safety contract) for the step structure and **ADR-033** (Inngest cron substrate), which it
extends with a write-to-live-infra capability.

The restore MUST be a final step + `onFailure` handler, **not a JS `try…finally`**: `step.sleep`
suspends via a control-flow throw that runs `finally` prematurely at the **first suspension**,
restoring the proxy before the cert validates and collapsing the DNS-only window (then the memoized
toggle-off step never re-runs → silent timeout).

*(Correction, #6698: this ADR and the routine's file docstring both previously asserted the poll's
`step.sleep` was "the only suspension point". The propagation gate's `dns-gate-wait-${i}` sleeps
make that literally false. The **reasoning** is unaffected — there is still no `finally`, and the
first suspension is now the gate's rather than the poll's — but both texts were corrected so a
future reader does not trust a claim the code no longer supports.)*

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
  diverges from Terraform-declared `proxied=true`. **Two racers, both fail closed:** (1) the
  mutating `apply-web-platform-infra.yml` push-apply DOES `-target` `cloudflare_record.github_pages`
  + `.www` (`.github/workflows/apply-web-platform-infra.yml:343-345`) and fires on any push to
  `main` touching `infra/**`, so an infra PR merging mid-window would auto-apply `proxied=true` and
  collapse the DNS-only window before the cert validates; (2) the drift racer
  (`cron-terraform-drift`, `0 6,18 * * *`) at most spuriously pages `infra-drift` (no auto-apply).
  Both outcomes are **non-worse than the already-degraded status quo**: an early `proxied=true`
  surfaces immediately as `poll_timeout`/`reissue_failed` → Sentry P0 → operator re-fires (idempotent,
  human-gated). Mitigation for v1 is the fail-closed→P0→re-fire backstop plus avoiding infra merges
  during the ~15-min window (or gating the apply with `[skip-web-platform-apply]`); it is **not**
  `-target`-allowlist exclusion (an earlier draft of this ADR wrongly claimed the records were not
  targeted). This is exactly why the runtime coordination lock is deferred to v2 (#6677), where
  unattended firing removes the operator-in-the-loop backstop and makes a real lock load-bearing.
- **Probe-only pays the window cost without remediating (added #6698).** A probe fire opens the
  same DNS-only window — and therefore the same public-TLS degradation on apex+www — while **by
  design** not attempting the fix. That is a deliberate trade: the alternative is a blind
  remediation fire that consumes a Let's Encrypt validation attempt against limits that are hourly
  and **compounding**, and that cannot distinguish "DNS never propagated" from "window too short"
  from "already rate-limited". Probe-only is materially cheaper than it looks because it skips the
  poll entirely: ~1–2 min of degradation instead of ~15. The residual is that an operator who fires
  twice (probe, then remediation) pays two windows rather than one.
- **Blast radius during the window:** CF WAF/DDoS + origin-IP hiding are absent on apex+www.
  Acceptable because the still-valid cert keeps traffic serving, the window is bounded, and the
  final step + `onFailure` guarantee return to the protected steady state; a failed restore pages
  P0 (`proxy_restore_failed`).
- **New IaC:** a distinct `cloudflare_api_token` (Zone.DNS:Edit on the soleur.ai zone) published to
  Doppler `prd` as `CF_API_TOKEN_DNS_EDIT`.
