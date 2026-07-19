---
feature: feat-one-shot-6698-cert-reissue-telemetry
issue: 6698
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-19-fix-gh-pages-cert-reissue-telemetry-and-dns-propagation-gate-plan.md
---

# Tasks — cert-reissue telemetry + DNS-only window validation

Derived from the plan above. Phase 0.1 is **blocking** — it may re-scope
everything downstream.

## Phase 0 — Preconditions (no code)

- [ ] **0.1 BLOCKING — resolve H-W4.** Read-only CF query for AAAA records on
      `soleur.ai` / `www.soleur.ai` via `GET /zones/{id}/dns_records?type=AAAA`
      (Doppler `prd_terraform`, `CF_API_TOKEN_DNS_EDIT` + `CF_ZONE_ID`).
  - [ ] 0.1.1 Record the output verbatim for the PR body (AC1).
  - [ ] 0.1.2 If AAAA records exist → **stop and re-scope**: the root cause is
        zone drift, remedied in Terraform (`apps/web-platform/infra/dns.tf`), and
        ADR-125's toggle-set completeness claim must be amended. Telemetry
        (Phase 1) still ships; the propagation gate becomes secondary.
  - [ ] 0.1.3 If none → H-W4 refuted; proceed to Phases 1–3 as written.
- [ ] **0.2** Verify `Resolver`/`setServers` on the installed Node
      (`node:dns/promises`, else `node:dns`). Pin the verified form.
- [ ] **0.3** Confirm `[transforms.app_container_warn_filter]`'s `level_int >= 40`
      is unchanged on `origin/main`.
- [ ] **0.4** Confirm `git grep -c SOLEUR_CERT_REISSUE` → 0.

## Phase 1 — Telemetry

- [ ] **1.1** Write the failing test first (`cq-write-failing-tests-before`):
      `test/server/cert-reissue-marker.test.ts` asserting pino level ≥ 40 and
      marker shape.
- [ ] **1.2** Create `server/cert-reissue-marker.ts` mirroring
      `server/claude-cost-marker.ts`: dedicated `pino({ base: { component: "cert-reissue" } })`,
      **no** `hooks.logMethod` Sentry mirror, `log.warn({ SOLEUR_CERT_REISSUE: true, ...m }, "cert reissue")`,
      fail-open `try/catch`, and the `‼️ BOUNDARY` no-PII comment carried forward.
- [ ] **1.3** Define the closed `phase` union:
      `preflight | pre-flip-dns | flip-dns-only | cname-put-null | cname-put-set | dns-propagation | poll | restore | terminal`.
- [ ] **1.4** Add `attempt` / `pollIndex` to the marker interface (AC5).
- [ ] **1.5** Wire emits **inside each `step.run` callback** — never in the
      orchestrating body (body-level re-executes ~15× per run). Leave
      `emitTerminal` where it is.
- [ ] **1.6** Emit observed cert state inside the `poll-${i}` callback; do not
      hoist the `getPages()` result to the body.
- [ ] **1.7** Emit the `pre-flip-dns` baseline before the flip (without it,
      propagation-delay is indistinguishable from never-propagated).
- [ ] **1.8** Verify `emitTerminal` / `reportSilentFallback` behavior unchanged
      and the `gh-pages-cert-reissue-failed` alert still keys on `feature`.

## Phase 2 — Probe-only mode + DNS-propagation gate

- [ ] **2.1** Write failing tests for: probe-only makes zero `setPagesCname`
      calls (AC11); restore runs on the `dns_propagation_failed` path (AC9);
      gate step names stable across a simulated replay (AC10).
- [ ] **2.2** Add `probeOnly` to the event payload, **defaulting to probe-only
      for manual fires**. Flip → gate → restore, skipping the cname toggle.
- [ ] **2.3** Add `assertPublicDnsPropagated` to `ReissueDeps`, combining:
      `resolve4` all in `185.199.0.0/16`; `resolve6` → `ENODATA`; post-flip
      ACME HTTP-01 shaped probe returning a GitHub-shaped response.
- [ ] **2.4** Insert the gate as its own `step.run` between `toggle-reissue` and
      the poll loop, with fixed-count `dns-gate-${i}` / `dns-gate-wait-${i}`
      step names over a constant.
- [ ] **2.5** **Restructure the tail of `runReissueSteps`** so
      `restore-steady-state` precedes **all** post-toggle terminal returns. The
      gate must never throw and must fall through to restore on failure.
      *Highest-risk edit in the change.*
- [ ] **2.6** Extend `ReissueOutcome` with `dns_propagation_failed`; sweep every
      consumer (`BENIGN_OUTCOMES` — it is **not** benign, `emitTerminal`, tests,
      Sentry alerts keyed on `outcome`). Run `tsc --noEmit` and widen every
      `not assignable to never` rail.
- [ ] **2.7** Keep the total DNS-only window at **15 min**; budget the gate out
      of `POLL_MAX_MS`. Assert against exported constants (AC13).
- [ ] **2.8** Add the `EXPECTED_TOGGLE_RECORDS` comment: a count cannot protect
      against record *types* never present in `dns.tf`.

## Phase 3 — Follow-through sweeper reopen path

- [ ] **3.1** Locate (or add) the `.test.sh` harness for
      `scripts/sweep-followthroughs.sh`; write failing cases first.
- [ ] **3.2** Add a **separate, recency-bounded** closed-issue query
      (`--state closed --search "closed:>=<date>"`, own `--limit`). Do **not**
      widen the existing `--state open --limit 50` call.
- [ ] **3.3** Fetch `stateReason`; exclude `NOT_PLANNED`.
- [ ] **3.4** Exit 1 → `gh issue reopen` + comment. Exit 2 → no action **and no
      comment**. Exit 0 → leave closed.
- [ ] **3.5** Bound the loop: `soleur:followthrough-nosweep` opt-out marker or a
      reopen cap after N.
- [ ] **3.6** `bash -n scripts/sweep-followthroughs.sh` clean.
- [ ] **3.7** Reopen #6657, or record that #6698 supersedes it as the live tracker.

## Phase 4 — ADR-125 + C4

- [ ] **4.1** Amend ADR-125 `## Decision` (+ `## Consequences`) per the Phase 0.1
      branch taken. Do not write it before 0.1 runs.
- [ ] **4.2** Read all three of `diagrams/{model.c4,views.c4,spec.c4}` in full.
      Enumerate external actors/systems: Let's Encrypt/ACME, GitHub Pages,
      Cloudflare DNS, public resolvers 1.1.1.1/8.8.8.8, Better Stack. Add any
      missing element + `#external` tag + edges + `view … include`.
- [ ] **4.3** Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 5 — Verification & exit

- [ ] **5.1** Full suite green (use the package's real runner —
      `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`; typecheck
      via `./node_modules/.bin/tsc --noEmit`, **not** `npm run -w`).
- [ ] **5.2** Walk every AC1–AC18 and record evidence.
- [ ] **5.3** PR body uses **`Ref #6698`**, never `Closes` (AC18).
- [ ] **5.4** Enroll the #6698 soak follow-through directive pointing at the
      existing `gh-pages-cert-reissue-6657.sh` probe; label `follow-through`.
- [ ] **5.5** File the four deferred tracking issues from the plan's
      `## Deferred / Tracking`.

## Phase 6 — Post-merge (automated; no operator step)

- [ ] **6.1** Deploy lands; container restart clears the `github-app.ts` tokenCache.
- [ ] **6.2** Fire 1 — **probe-only** via `/api/internal/trigger-cron`.
- [ ] **6.3** Discoverability: `betterstack-query.sh --since 30m --grep '"SOLEUR_CERT_REISSUE":true'`
      returns ≥ 1 row per phase (field-isolated grep — never the bare token).
- [ ] **6.4** Apply the AC22 verdict rule to pick the next action.
- [ ] **6.5** Fire 2 — remediation, only after a clean AC22 first branch **and** a
      multi-hour LE cooling-off. Watch `.https_certificate.state` up to ~15 min.
- [ ] **6.6** Re-assert steady state after every fire (apex + www `proxied=true`,
      `cname=soleur.ai`).
- [ ] **6.7** Once `issued`/`approved`: restore `https_enforced: true`.
