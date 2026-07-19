# Tasks — ADR-100 Inngest cutover code blockers

Plan: `knowledge-base/project/plans/2026-07-19-fix-inngest-cutover-code-blockers-plan.md`

Two PRs. PR-A and PR-B are independent (different hosts, different apply paths)
and may proceed in parallel.

---

## Phase 0 — Measure before coding (PR-A gate, blocking)

- [ ] 0.1 `hcloud firewall describe` on the registry firewall; diff against `10.0.1.40`. Record literal output.
- [ ] 0.2 Confirm the inngest host holds a private NIC and routes to `10.0.1.30` (Better Stack `net-health` marker, `nic=` field).
- [ ] 0.3 Measure zot `/v2/` response for the inngest identity against the **pinned image** — record the literal HTTP status. Do NOT derive it from `accessControl` config.
- [ ] 0.4 Probe whether zot resolves `soleur-inngest-bootstrap:v1.1.23` (`manifest_resolves` shape).
- [ ] 0.5 Confirm `soleur-inngest/prd` holds (or can hold) `ZOT_*` credentials + a Sentry DSN.
- [ ] 0.6 **GATE:** if 0.1–0.5 show the host cannot reach/authenticate to zot, STOP and re-scope. Surface as a scope expansion, do not absorb.

## Phase 1 — PR-A: inngest host (Closes #6500, Ref #6617)

### 1.1 Sentry stage emitter (A1)
- [ ] 1.1.1 Add `soleur-boot-emit`-equivalent to `cloud-init-inngest.yml`; DSN from isolated `soleur-inngest/prd`.
- [ ] 1.1.2 Add DSN `templatefile()` var to `inngest-host.tf` (declared as a `doppler_secret` resource, never hand-written).
- [ ] 1.1.3 Keep `inngest-boot-phone-home.sh` intact — additive, not a replacement.
- [ ] 1.1.4 Verify nothing credential-bearing is tailed into the emit (phone-home bypasses Vector's PII scrub).

### 1.2 Zot-primary pull with GHCR fallback (A2)
- [ ] 1.2.1 Write the failing test first: `inngest-host.test.sh` asserts a zot arm exists. RED.
- [ ] 1.2.2 Replace the bare `IREF=` with the ADR-096 three-tier gate (`/v2/` probe → zot → atomic GHCR fallback).
- [ ] 1.2.3 Move image ref, docker auth, and cosign target together (ADR-096 Edge A/B).
- [ ] 1.2.4 Confirm the pull stays fail-closed after both arms are exhausted.
- [ ] 1.2.5 Emit `inngest_zot` (info) / `inngest_ghcr_fallback` (warning) on the pull path.

### 1.3 CI ownership (A3) — the root-cause fix
- [ ] 1.3.1 Add `inngest-host.test.sh` assertions: zot arm, GHCR fallback, fail-closed pull, Sentry emit.
- [ ] 1.3.2 Add a pin-consistency assertion coupling the pin to the tag the drift-guard derives.
- [ ] 1.3.3 Verify test count strictly increases.

### 1.4 Positive liveness marker (A4, #6617a)
- [ ] 1.4.1 Add `inngest-server-probe.{service,timer}` to `inngest-bootstrap.sh`, probing `http://127.0.0.1:8288/health`.
- [ ] 1.4.2 Set `SyslogIdentifier=inngest-server-probe` explicitly (#6536 trap).
- [ ] 1.4.3 Emit the `SOLEUR_*` marker **unconditionally before** health classification (ADR-117 positive-control rule).
- [ ] 1.4.4 If the unit runs Doppler as root, set `Environment=HOME=/root`.

### 1.5 Vector allowlist + delivery (A5, #6617c)
- [ ] 1.5.1 Add `inngest-server-probe`, `inngest-redis`, `inngest-nftables`, `inngest-boot-phone-home` to Source 4.
- [ ] 1.5.2 Add exact-value assertions to `journald-config.test.sh`.
- [ ] 1.5.3 Name the delivery path in the PR body — a repo edit alone never reaches the running host.

### 1.6 Quiet the dark heartbeat arm (A6, #6617b re-scoped)
- [ ] 1.6.1 Change the dark arm to once-per-boot + on-transition.
- [ ] 1.6.2 Confirm the diff writes **no** heartbeat URL value anywhere.

## Phase 2 — PR-B: web host NIC-wait (Ref #6441, Ref #6466)

- [ ] 2.1 Add a `nic <ip> <stage>` verb to `soleur-wait-ready` (bounded poll, fail-closed, named timeout constant + rationale).
- [ ] 2.2 Write the failing render test first: NIC-wait precedes `cloudflared service install`. RED.
- [ ] 2.3 Insert `soleur-wait-ready nic 10.0.1.10 private_nic_ready || exit 1` before the cloudflared install, inside the existing `web_tunnel_connector` block.
- [ ] 2.4 Mirror the registry host's bounded-reboot converger for the NIC-down-at-boot case. Do NOT write a new converger.
- [ ] 2.5 Assert ordering by line-number comparison (`private-nic-guard.test.sh` idiom).
- [ ] 2.6 Assert that with `web_tunnel_connector=false` neither line renders.
- [ ] 2.7 Amend ADR-114 §I1 — replace the "Not shipped in #6416" sentence with a record of this PR.

## Phase 3 — Verification

- [ ] 3.1 `bash apps/web-platform/infra/inngest-host.test.sh` exits 0.
- [ ] 3.2 `bash apps/web-platform/infra/journald-config.test.sh` exits 0.
- [ ] 3.3 `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` exits 0.
- [ ] 3.4 Full infra suite green.
- [ ] 3.5 Paste Phase 0 probe results verbatim into the PR-A body.
- [ ] 3.6 PR-A: `Closes #6500`, `Ref #6617`. PR-B: `Ref #6441`, `Ref #6466` (never `Closes` — the fix is latent until a host replace).

## Phase 4 — Post-merge (gated dispatch, API-verified)

- [ ] 4.1 Dispatch `inngest-host-replace` using the existing 5-target allow-set.
- [ ] 4.2 Confirm the fresh boot emits `inngest_zot` or `inngest_ghcr_fallback` to Sentry (API query).
- [ ] 4.3 `scripts/betterstack-query.sh --grep SOLEUR_INNGEST_SERVER_PROBE` returns ≥ 1 row in 5 minutes.
- [ ] 4.4 Confirm `inngest-heartbeat` channel volume drops from the ~1,414/24 h baseline.
- [ ] 4.5 Confirm `zot-soak-6122.sh` C1 arm no longer names #6500 as OPEN.
