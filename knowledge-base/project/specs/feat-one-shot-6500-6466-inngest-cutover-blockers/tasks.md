# Tasks — ADR-100 Inngest cutover code blockers

Plan: `knowledge-base/project/plans/2026-07-19-fix-inngest-cutover-code-blockers-plan.md`
**Revision 2 (post-deepen).** PR-B was redesigned; the original fail-closed NIC
gate is **withdrawn as unsafe** (plan §CF-5). Read the plan's *Deepen-Review
Critical Findings* before starting — four items are boot- or security-fatal.

Two PRs, independent (different hosts, different apply paths).

---

## Phase 0 — Measure before coding (PR-A gate, blocking)

- [ ] 0.1 `hcloud firewall describe` on the registry firewall. **Note:** both firewalls are public-interface-only deny-all; intra-`10.0.1.0/24` is unfiltered, so "allowed" here proves nothing about enrollment. Do NOT read L3-permitted as A0-passed.
- [ ] 0.2 Confirm the inngest host holds a private NIC and routes to `10.0.1.30` (Better Stack `net-health` marker, `nic=` field).
- [ ] 0.3 Measure zot `/v2/` for the inngest identity against the **pinned image** — record the literal HTTP status. Never derive it from `accessControl` config.
- [ ] 0.4 Probe whether zot resolves `soleur-inngest-bootstrap` at the target tag (`manifest_resolves` shape).
- [ ] 0.5 **CF-1 probe:** determine whether adding `ZOT_*` to `soleur-inngest/prd` trips the boot isolation exact-set-equality check. Near-certain first-boot brick if unhandled.
- [ ] 0.6 **CF-2 probe:** confirm no `cosign verify` exists on this path, and decide digest-pin vs cosign **before** A2 is written.
- [ ] 0.7 **GATE.** If zot cannot serve `10.0.1.40`: do NOT write an unreachable primary arm. Split A4/A5/A6 into PR-A′ (zero zot dependency), file the enrollment issue, post A0 results to #6500. The stop branch is stable — the soak keeps vetoing 5.3.

## Phase 1 — PR-A: inngest host (Closes #6500, Ref #6617)

### 1.1 Sentry stage emitter (A1)
- [ ] 1.1.1 Add the emitter named **literally `soleur-boot-emit`** (CF-7 — the soak greps `^\s*soleur-boot-emit `; a rename breaks 5.3 authorization).
- [ ] 1.1.2 DSN via the **existing `var.sentry_dsn`** through `inngest-host.tf`'s existing `templatefile()` map. **No new `doppler_secret`** (CF-10 — the file warns it would clobber on first create, and it would trip CF-1).
- [ ] 1.1.3 **Copy the `soleur-boot-emit` closed-vocabulary shape, NOT the two-argument phone-home shape.** No free-form field. This is what keeps the Sentry channel leak-proof; `inngest-redact.sh` is not in Sentry's path.
- [ ] 1.1.4 Keep `inngest-boot-phone-home.sh` intact — additive, not a replacement.

### 1.2 Zot-primary pull with GHCR fallback (A2) — GATED ON 0.6
- [ ] 1.2.1 **Blocking:** digest-pin `IREF` (`@sha256:`) or add a real `cosign verify` before `docker create`. Do not ship the zot arm without it (CF-2).
- [ ] 1.2.2 Correct the false `cosign-verify` comment in the same PR.
- [ ] 1.2.3 Write the failing test first: `inngest-host.test.sh` asserts a zot arm. RED.
- [ ] 1.2.4 Write the zot ref **directly into `IREF=` referencing `$ZURL`** so `^\s*IREF=.*\$ZURL` matches. Do NOT copy the web `ZIREF=`-then-`IREF="$ZIREF"` shape — it fails the soak forever (CF-7).
- [ ] 1.2.5 Atomic GHCR fallback; pull stays fail-closed after both arms.
- [ ] 1.2.6 Emit `inngest_zot` (info) / `inngest_ghcr_fallback` (warning).

### 1.3 CI ownership + isolation triple (A3)
- [ ] 1.3.1 `inngest-host.test.sh` asserts: zot arm, GHCR fallback, fail-closed pull, Sentry emit, digest/cosign gate, pin-consistency.
- [ ] 1.3.2 **CF-1:** if any `ZOT_*` lands in `soleur-inngest/prd`, move the isolation regex, the `-lt N` floor, and the "N dark / N+1 live" comment together; pin the admitted-name set by exact value in a test.
- [ ] 1.3.3 Add any new zot credential file to `inngest-redact.sh`'s explicit enumeration — do not rely on the `{40,}` length backstop (the token is exactly 40 chars).
- [ ] 1.3.4 Prefer a scoped third htpasswd identity over duplicating the fleet `ZOT_PULL_TOKEN` value.

### 1.4 Positive liveness marker (A4, #6617a)
- [ ] 1.4.1 Add `inngest-server-probe.{service,timer}` probing `http://127.0.0.1:8288/health`.
- [ ] 1.4.2 Set `SyslogIdentifier=inngest-server-probe` explicitly (#6536).
- [ ] 1.4.3 Emit **unconditionally before** classification (ADR-117).
- [ ] 1.4.4 **Carry discriminating fields in one event:** `http_code` (incl. `000`), `vector_active`, `redis_active`, `uptime_s`, `boot_id`, image sha. A boolean marker reproduces #6617 one layer up.
- [ ] 1.4.5 If the unit runs Doppler as root, set `Environment=HOME=/root`.

### 1.5 Vector allowlist (A5, #6617c)
- [ ] 1.5.1 Set `SyslogIdentifier=inngest-redis` on `inngest-redis.service` (currently tagged `doppler`).
- [ ] 1.5.2 Set `SyslogIdentifier=inngest-nftables` on the nftables unit (currently tagged `inngest-nftables.sh`).
- [ ] 1.5.3 Add `inngest-server-probe`, `inngest-redis`, `inngest-nftables` to Source 4. **Do NOT add `inngest-boot-phone-home`** — it never calls `logger` and has no journald channel (CF-4).
- [ ] 1.5.4 Assert each tag by exact value in `journald-config.test.sh`, and cross-check the literal appears in **both** the unit file and `vector.toml`.
- [ ] 1.5.5 **CF-3, unconditional:** rebuild the bootstrap image, push the tag, bump the `IREF` pin off `v1.1.23`. Without this, 1.4/1.5/1.6 are undeliverable.

### 1.6 Rate-limit the dark heartbeat arm (A6, #6617b)
- [ ] 1.6.1 Change to a **low periodic cadence (hourly)** — NOT transition-only, which eliminates the positive control (CF-9).
- [ ] 1.6.2 Confirm the diff writes **no** heartbeat URL value anywhere.

### 1.7 Apply routing + ADR (A7)
- [ ] 1.7.1 Route the replace through the maintenance-window `apply_target=inngest-host` dispatch; state it in the PR body (CF-8 — this host has NO `ignore_changes`).
- [ ] 1.7.2 Update ADR-096 §5.3's enumeration to register the new inngest pull site + emit names.

## Phase 2 — PR-B: web host NIC precondition (Ref #6441, Ref #6466)

**Redesigned. The original `soleur-wait-ready nic … || exit 1` is withdrawn.**

- [ ] 2.1 Gate cloudflared activation on NIC readiness via a **systemd precondition** (`ExecStartPre` poll or an ordered oneshot) so a late attach *delays* registration.
- [ ] 2.2 **Never** add `exit 1` to `runcmd` — it is one shell; an abort there kills cloudflared, webhook, and every monitor, permanently (CF-5).
- [ ] 2.3 Emit `private_nic_ready` (info) and `private_nic_timeout` (warning) via `soleur-boot-emit` — available here because the web host runs `soleur-host-bootstrap.sh`.
- [ ] 2.4 **Do NOT add reboot/converge behavior** — ADR-115 normative blocker; a web-host reboot powers off the sole live origin (CF-6).
- [ ] 2.5 Test: with `web_tunnel_connector=false` nothing renders; with `true` the precondition governs activation.
- [ ] 2.6 **Regression guard:** assert zero added `exit 1` lines in `cloud-init.yml`.
- [ ] 2.7 Add a **new consolidating ADR-114 §I1 amendment note**. Do NOT edit the preserved "Not shipped in #6416" sentence.

## Phase 3 — Verification

- [ ] 3.1 `bash apps/web-platform/infra/inngest-host.test.sh` exits 0.
- [ ] 3.2 `bash apps/web-platform/infra/journald-config.test.sh` exits 0.
- [ ] 3.3 `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` exits 0.
- [ ] 3.4 Full infra suite green.
- [ ] 3.5 Paste Phase 0 probe results verbatim into the PR-A body, including the literal zot status. A `401`/`403` blocks merge.
- [ ] 3.6 PR-A: `Closes #6500`, `Ref #6617`. PR-B: `Ref #6441`, `Ref #6466` (never `Closes`).

## Phase 4 — Post-merge (gated dispatch, API-verified)

- [ ] 4.1 Dispatch the replace via the maintenance-window `apply_target=inngest-host` path.
- [ ] 4.2 Confirm the fresh boot emits **`inngest_zot`** (not "zot or fallback" — a fallback boot increments the soak's fallback counter and resets it to FAIL).
- [ ] 4.3 `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep SOLEUR_INNGEST_SERVER_PROBE` returns ≥ 1 row.
- [ ] 4.4 `inngest-heartbeat` channel rows `< 50` over a 24 h window starting **≥ the replace timestamp**.
- [ ] 4.5 `zot-soak-6122.sh` passes **both** arms — the `#6500`-CLOSED check AND the two anchored code greps.

## Known unresolved (do not silently absorb)

- [ ] **Post-5.3 break-glass.** ADR-096 5.3 deletes the GHCR fallback branch, leaving the singleton with exactly one registry and no recovery if zot is down at boot. This plan does not solve it. 5.3 must not proceed until a break-glass exists.
- [ ] **First-run risk.** The replace is both the delivery mechanism and the first execution of the new boot code. Consider GHCR-primary/zot-secondary first, flipping preference on a second replace.
