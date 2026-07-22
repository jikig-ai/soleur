---
feature: feat-one-shot-6698-cert-reissue-telemetry
issue: 6698
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-19-fix-gh-pages-cert-reissue-telemetry-and-dns-propagation-gate-plan.md
deepened: 2026-07-19
---

# Tasks — cert-reissue telemetry + DNS-only window validation

Derived from the deepened plan. **Phase 0.1 is blocking** — it may re-scope
everything downstream.

## Phase 0 — Preconditions (no code)

- [x] **0.1 BLOCKING — resolve H-W4 (AAAA).** Read-only CF query:
      `GET /zones/{id}/dns_records?type=AAAA` via Doppler `prd_terraform`.
      Per RI-1, LE prefers IPv6 and its IPv4 fallback is nearly absent, so a
      proxied AAAA surviving the flip fully explains `bad_authz` at any window.
  - [x] 0.1.1 Record output verbatim for the PR body (AC1).
  - [x] 0.1.2 AAAA present → **stop and re-scope**; root cause is zone drift,
        remedied in `dns.tf`, and it needs a NEW ADR on toggle-set completeness
        (not this plan's ADR-125 amendment).
  - [x] 0.1.3 None → H-W4 refuted; proceed.
- [x] **0.2 RESOLVED** — `Resolver`/`setServers`/`resolve4`/`resolve6` verified
      available on the installed Node (RI-6).
- [x] **0.3** Confirm `app_container_warn_filter`'s `level_int >= 40` unchanged
      on `origin/main` (verified this session; re-check only after a rebase).
- [x] **0.4** `git grep -c SOLEUR_CERT_REISSUE -- apps/ scripts/` → 0.
      **Scope flags mandatory** — unscoped already returns non-zero (this plan
      and tasks.md quote the literal) and would fail-closed for a benign reason.

## Phase 1 — Telemetry

- [x] **1.1** Failing tests first: `test/server/cert-reissue-marker.test.ts`
      asserting pino level ≥ 40 and marker shape.
- [x] **1.2** Create `server/cert-reissue-marker.ts` mirroring
      `server/claude-cost-marker.ts`: dedicated
      `pino({ base: { component: "cert-reissue" } })`, **no** `hooks.logMethod`
      Sentry mirror, `log.warn({ SOLEUR_CERT_REISSUE: true, ...m }, "cert reissue")`,
      fail-open `try/catch`, `‼️ BOUNDARY` no-PII comment carried forward.
- [x] **1.3** **Field-name constraint:** no marker field named `body`, `content`,
      `message`, `userMessage`, `prompt`, `chat_message`, `userInput`,
      `user_input` — deleted by `pii_scrub_drop_userdata` (`vector.toml:246-253`).
- [x] **1.4** Closed `phase` union (10 members): `preflight`, `pre-flip-dns`,
      `flip-dns-only`, `cname-put-null`, `cname-put-set`, `dns-propagation`,
      `poll`, `restore`, `terminal`, `onfailure-restore`.
- [x] **1.5** Thread `runId` + `attempt` from `HandlerArgs` (already declares
      both) through `ReissueHandlerArgs` and `runReissueSteps` — currently
      destructures only `{ step, logger }`. Add `probeOnly` + `pollIndex`.
      **Assert values propagate, not just types.**
- [x] **1.6** New named step `capture-pre-flip-dns` **before** `toggle-reissue`.
      Emitting inside `toggle-reissue` is wrong — a retry would re-read the
      "pre-flip" baseline after the first flip already happened.
- [x] **1.7** Emit inside each `step.run` callback; **never** in the
      orchestrating body (body re-executes ~16× for 15 step pairs).
- [x] **1.8** **`emitTerminal` MUST gain a marker emit.** It currently routes
      benign outcomes through `logger.info` (`:694`), so `issued`/`not_stuck` —
      the success path — stay dark without this. Not optional.
- [x] **1.9** In `poll-${i}`, capture the **entire** `https_certificate` object
      (`state`, `description`, `domains`, `expires_at`) plus
      `protected_domain_state` / `pending_domain_unverified_at`. Per RI-7 this is
      the only in-band signal that could separate H-W2 from H-W3.
- [x] **1.10** `restore` marker emits **twice** — on entry and on outcome,
      including from a rethrowing catch (restoreState is fail-loud).
- [x] **1.11** Emit `onfailure-restore` from **both** branches of
      `cronGhPagesCertReissueOnFailure`'s try/catch.
- [x] **1.12** Leave `reportSilentFallback` / Sentry behavior intact (additive).

## Phase 2 — Probe-only mode + DNS-propagation gate

- [x] **2.1** Failing tests first: probe-only makes zero `reissueViaCnameToggle`
      calls and zero `poll-*` steps; restore runs on `dns_propagation_failed`;
      gate step names stable across a simulated replay.
- [x] **2.2** `probeOnly` read from event payload. **Absent `data` ⇒
      `probeOnly: true`** (safe default); remediation requires explicit
      `{"probeOnly": false}`. Route already forwards `data` as `callerData`
      (`trigger-cron/route.ts:100-108`).
- [x] **2.3** Probe-only **skips the poll loop entirely** — restores as soon as
      the gate returns (~1–2 min), not ~14 min of public TLS degradation for a
      cert it never re-ordered.
- [x] **2.4** Add `probe_only_complete` to `ReissueOutcome` **and**
      `BENIGN_OUTCOMES`. Unreachable when `probeOnly === false`; `issued`
      unreachable when `probeOnly === true`. Add `probeOnly` to `ReissueResult`
      so it reaches `emitTerminal` extra → Sentry → `public.routine_runs`.
- [x] **2.5** Gate shape mirrors the file's gather/check split:
      `gatherDnsPropagation()` dep (raw observations) + exported pure
      `checkDnsPropagated(inputs)` (policy). **Not** a verdict-returning dep.
      Inputs: `resolve4` answers (⊆ 185.199.0.0/16), `resolve6` (`ENODATA`),
      post-flip ACME HTTP-01 probe shape (GitHub vs Cloudflare).
- [x] **2.6** Wire a **real** `gatherDnsPropagation` in `buildLiveDeps` — the
      dead-twin risk (AC8b).
- [x] **2.7** Gate as its own `step.run` between `toggle-reissue` and the poll,
      bounded `step.sleep` loop with fixed-count names `dns-gate-${i}` /
      `dns-gate-wait-${i}` over a constant. Carry an elapsed-time check *inside*
      the loop (count = upper bound, wall-clock = real ceiling).
- [x] **2.8** **Restructure the tail so there is exactly ONE post-toggle return
      site, after `restore-steady-state`**, outcome carried in a local. Highest
      risk edit. Correct invariant: *every post-toggle exit is preceded by a
      restore — either the in-step one at `:404` or the body step at `:449`.*
      **Do NOT add a second body-level restore to the `reissue_failed` path** —
      it is already covered in-step, and a throwing second restore would
      overwrite the diagnostic outcome via `onFailure`.
- [x] **2.9** Add `dns_propagation_failed` (NOT benign). Sweep consumers:
      `BENIGN_OUTCOMES`, `emitTerminal`, `runLogMiddleware`/`routine_runs`,
      tests, Sentry alerts keyed on `outcome`. `tsc --noEmit`; widen every
      `not assignable to never` rail.
- [x] **2.10** Export a **total-window** constant =
      `(MAX_POLLS-1)*POLL_INTERVAL_MS + CNAME_SETTLE_MS + gate budget`, assert
      ≤ 15 min. Gate budget comes **out of** `POLL_MAX_MS`; do not lengthen.
- [x] **2.11** Widen `REISSUE_ALLOWED_STATES` per RI-3: drop undocumented
      `"failed"`, add `errored` + `authorization_revoked`. Own test.
- [x] **2.12** `EXPECTED_TOGGLE_RECORDS` comment: a count cannot protect against
      record *types* never present in `dns.tf`.
- [x] **2.13** Comment the latent double-fire: a throwing in-step
      `restoreState` re-runs the whole toggle unit under `retries: 1`,
      consuming a second LE attempt. Now countable via `cname-put-*` markers.

## Phase 3 — Follow-through sweeper reopen path

- [x] **3.1** Failing cases first in the **existing**
      `scripts/sweep-followthroughs.test.sh`.
- [x] **3.2** Separate closed-issue query, own `--limit`. Pin a single
      `--search 'label:follow-through state:closed closed:>=…'` form and verify
      against the runner's gh. Do not widen the open query.
- [x] **3.3** **Bypass the `earliest` gate for the closed set** (`:178-185`).
      Without this the design misses #6657 — closed 07-18 with
      `earliest=07-25`, it leaves any short recency window before its soak
      elapses. `earliest` guards premature *closing*; a closed issue already
      asserts "verified."
- [x] **3.4** Fetch `stateReason`; exclude `NOT_PLANNED`.
- [x] **3.5** exit 1 → reopen + comment. exit 2 → no action, **no comment**.
      exit 0 on a closed issue → **full no-op incl. comment** (`run_one`
      currently comments unconditionally at `:271-274`). `::error::` on a failed
      `gh issue reopen`.
- [x] **3.6** Stateless reopen bound — prefer counting prior sweeper-reopen
      comments via `gh issue view --json comments`, give up at N.
- [x] **3.7** Skip closures whose latest comment is the sweeper's own PASS block
      (evidence-based, preserves actor-agnosticism, prevents turning every
      follow-through into a permanent daily monitor).
- [x] **3.8** `bash -n scripts/sweep-followthroughs.sh` clean.
- [x] **3.9** Regression fixture in #6657's exact shape (closed COMPLETED,
      future `earliest`, script exits 1) → sweeper reopens (AC14b).
- [x] **3.10** Reopen #6657 (decision made in plan, not deferred).
- [x] **3.11** Verify live against the **failing** input, not just the passing one.

## Phase 4 — ADR-125 + C4

- [x] **4.1** Amend ADR-125 — all four edits: `## Decision` step 3 (poll budget
      shortened), the new gate step + corrected total-window budget, the
      `REISSUE_ALLOWED_STATES` widening, and `## Consequences` for probe-only
      (pays the window cost while by design not remediating).
- [x] **4.2** Correct the "only suspension point" claim in **both** ADR-125 and
      the file docstring (`:17-19`) — the gate adds `dns-gate-wait-*` sleeps.
- [x] **4.3** Read all three `diagrams/{model.c4,views.c4,spec.c4}` in full.
      Enumerate external actors/systems: Let's Encrypt/ACME, GitHub Pages,
      Cloudflare DNS, public resolvers 1.1.1.1/8.8.8.8, Better Stack. Add any
      missing element + `#external` + edges + `view … include`.
- [x] **4.4** Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 5 — Verification & exit

- [x] **5.1** Full suite green. Use the package's real runner:
      `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`;
      typecheck `./node_modules/.bin/tsc --noEmit` (**not** `npm run -w`).
- [ ] **5.2** Walk AC1–AC18b, record evidence.
- [ ] **5.3** PR body uses `Ref #6698`; scan the **whole body** for any
      `<closing-keyword> #<n>` adjacency in prose (GitHub matches it anywhere).
- [x] **5.4** Enroll the #6698 soak follow-through directive pointing at the
      existing `gh-pages-cert-reissue-6657.sh` probe; label `follow-through`.
- [x] **5.5** File the deferred tracking issues from `## Deferred / Tracking`.

## Phase 6 — Post-merge (automated; no operator step)

- [ ] **6.1** Assert deploy: `curl -s https://app.soleur.ai/health` `build_sha`
      matches the merge commit (restart also clears the `github-app.ts` tokenCache).
- [ ] **6.2** Fire 1 — probe-only (`data.probeOnly: true`).
- [ ] **6.3** Discoverability: `betterstack-query.sh --since 30m --grep
      '"SOLEUR_CERT_REISSUE":true'`, additionally scoped on
      `source_kind":"app_container` and filtered to this fire's `runId`.
      **Probe-only expects 6 phases**, not all 10.
- [ ] **6.4** Apply the AC22 ordered verdict rule (7 branches; every reachable
      observation has one).
- [ ] **6.5** Fire 2 — remediation (`data.probeOnly: false`, **required**), only
      after AC22 branch 7 and a multi-hour LE cooling-off.
- [ ] **6.6** Re-assert steady state after every fire.
- [ ] **6.7** Once `issued`/`approved`: restore `https_enforced: true`.
