# Tasks — ADR-100 Inngest cutover code blockers

Plan: `knowledge-base/project/plans/2026-07-19-fix-inngest-cutover-code-blockers-plan.md`
**Revision 2 (post-deepen).** PR-B was redesigned; the original fail-closed NIC
gate is **withdrawn as unsafe** (plan §CF-5). Read the plan's *Deepen-Review
Critical Findings* before starting — four items are boot- or security-fatal.

Two PRs, independent (different hosts, different apply paths).

---

## Phase 0 — Measure before coding (PR-A gate, blocking) — **RUN 2026-07-19, verdict STOP/SPLIT**

- [x] 0.1 `hcloud firewall describe` — MEASURED. Both `soleur-registry` (11266630) and `soleur-inngest` (11269127) carry **zero rules**; `soleur-inngest` is applied to **zero servers** and the inngest host has no cloud firewall attached (on-host nftables is its ingress control). Hetzner cloud firewalls filter the **public interface only**, so intra-`10.0.1.0/24` is unfiltered *by construction*, not by an allow decision. **Not** read as A0-passed.
- [x] 0.2 Private NIC — MEASURED (`nic=[10.0.1.40,]` in the Better Stack `net-health` marker, 2026-07-16 19:51:07; corroborated by hcloud API `private_net → 10.0.1.40`). Route to `10.0.1.30` is **INFERRED** from shared-subnet membership only — the marker probes `priv8288` (its own port); no signal shows `.40` originating to `.30`.
- [x] 0.3 zot `/v2/` for the inngest identity — **CANNOT DETERMINE, and not inferred.** Two stated blockers: (a) the identity does not exist — `soleur-inngest/prd` holds zero `ZOT_*`, and zot's htpasswd has exactly `zot-pull`/`zot-push` (`zot-registry.tf:84-85`); (b) no non-SSH origination path from `.40`. Confirmed empirically: Better Stack `--since 72h --grep 10.0.1.40` returned only the two net-health rows — **the inngest host has never contacted zot.** Measured on zot's own side: anonymous `/v2/` → `401`; authenticated `tags/list` → `200` at 13:29:55Z and 13:35:00Z today.
- [x] 0.4 Tag resolution — MEASURED on the **write side** (a read probe needs private-net origin per `zot-entry-gate.sh:48-53`). GHA run `29620217899` (2026-07-17T23:18:53Z) pushed `127.0.0.1:5000/jikig-ai/soleur-inngest-bootstrap:v1.1.23`. Read-resolves-today is INFERRED (hourly `gc`/`deleteUntagged`; a tagged manifest should survive).
- [x] 0.5 **CF-1 — CONFIRMED against live data, at zero headroom.** Check at `cloud-init-inngest.yml:290-293` is exact-set-equality (`n_total -ne n_inngest`), not a prefix filter. Live: `n_total=5, n_inngest=5` — passing **exactly at the `-lt 5` floor**; `INNGEST_HEARTBEAT_URL` absent, confirming the documented "5 dark" state. Any added `ZOT_*` → `6 ≠ 5` → `FATAL: boot credential not isolated` → `exit 1` → the `/run/soleur-inngest-doppler.ok` sentinel never drops → bootstrap aborts at `:339`. **The singleton scheduler never boots.** The check keys on the NAME, so value rotation is safe; name addition is fatal. The constant lives in three places that must move together: `:291` regex, `:292` floor, `:274`/`:277` comments.
- [x] 0.6 **CF-2 — CONFIRMED.** `grep -n cosign cloud-init-inngest.yml` → exactly one hit, `:236`, **a comment, and it is false**. The real path is `IREF=…:v1.1.23` (mutable tag) → `docker pull` → `docker create`/`cp` → `bash …/inngest-bootstrap.sh` **as root** (`:341-402`), with zero signature checks. Independently corroborated: `build-inngest-bootstrap-image.yml:225-226` states the image is **"NOT cosign-signed (no id-token perm) — no sign step."** → **Decision: digest-pin (`@sha256:`), NOT cosign.** Real cosign is not implementable here — gating boot on a signature that has never been produced converts CF-2 from "unverified pull" into "guaranteed boot-brick". Signing is a separate PR that must land *before* any verify.
- [x] 0.7 **GATE → STOP/SPLIT.** The question is "can zot serve `10.0.1.40`?" The answer is not *no* but **unproven, where the proof requires work that is itself boot-fatal** — and the plan is explicit that unproven takes the same branch. Compounding: CF-8 (`inngest-host.tf` has **no** `lifecycle.ignore_changes=[user_data]`) means every `cloud-init-inngest.yml` edit force-replaces the sole scheduler, executed by *any* later `terraform apply` including one from an unrelated PR. Stacking an unreachable primary arm + a boot-fatal credential change + an unverified root-executed pull on that host is exactly the compound risk this gate exists to stop. Against the plan's `single-user incident` threshold, the failure mode is the user's scheduler going silently dark.

### Gate outcome — PR-A becomes PR-A′ (operator-confirmed 2026-07-19)

**A2 (zot-primary arm) and A1/A3 (its CI + Sentry-stage authorization) are WITHDRAWN from this PR.** `#6500` stays OPEN and is reframed: it is not a pin swap, it is **an enrollment task with a boot-brick precondition**. The A0 evidence gets posted to it.

Ships in PR-A′ (zero zot dependency): **A4, A5, A6**, the unconditional CF-3 image rebuild, and the free CF-2 win — digest-pin `IREF` on the **existing GHCR arm** + correct the false comment at `:236`.

Not a degradation: the soak (`zot-soak-6122.sh:416`) keeps vetoing 5.3 on its two anchored predicates (`^\s*IREF=.*\$ZURL`, `^\s*soleur-boot-emit `) with `FAIL(blocker-closed-but-condition-unmet)`. That veto is the **correct** state — the 7th GHCR-served path is still open in the code and the soak says so. The ordering that matters is against the PAT revoke, which has not happened.

## Phase 1 — PR-A′: inngest host (Ref #6500, Ref #6617)

> **`Ref`, not `Closes`.** The Phase 0 gate returned STOP/SPLIT and the zot arm is WITHDRAWN (see "Gate outcome" above), so `#6500` stays OPEN. Auto-closing it here would hand the `zot-soak-6122.sh:395-416` CLOSED branch a false authorization for the irreversible ADR-096 §5.3 PAT revoke.

### 1.1 Sentry stage emitter (A1)
- [ ] 1.1.1 Add the emitter named **literally `soleur-boot-emit`** (CF-7 — the soak greps `^\s*soleur-boot-emit `; a rename breaks 5.3 authorization).
- [ ] 1.1.2 DSN via the **existing `var.sentry_dsn`** through `inngest-host.tf`'s existing `templatefile()` map. **No new `doppler_secret`** (CF-10 — the file warns it would clobber on first create, and it would trip CF-1).
- [ ] 1.1.3 **Copy the `soleur-boot-emit` closed-vocabulary shape, NOT the two-argument phone-home shape.** No free-form field. This is what keeps the Sentry channel leak-proof; `inngest-redact.sh` is not in Sentry's path.
- [ ] 1.1.4 Keep `inngest-boot-phone-home.sh` intact — additive, not a replacement.

### 1.2 Zot-primary pull with GHCR fallback (A2) — GATED ON 0.6

**WITHDRAWN from PR-A′ per the Phase 0 STOP/SPLIT verdict** (zot has never served a pull to `.40`, and the enrollment it needs is boot-fatal per CF-1). 1.2.1 and 1.2.2 were the two items with **zero** zot dependency, so they shipped in PR-A′ against the existing GHCR arm; 1.2.3–1.2.6 stay withdrawn with the arm.

- [x] 1.2.1 **Blocking:** digest-pin `IREF` (`@sha256:`) or add a real `cosign verify` before `docker create`. Do not ship the zot arm without it (CF-2). — **DONE (digest, not cosign):** `IREF=…:v1.1.24@sha256:6cdaa63d1496642e681898a831234b712f75d3b09bd0844bcabec3de74b0a0f8` on the **existing GHCR** arm. Digest cross-checked against three independent sources (`docker buildx imagetools inspect`, the push log of build run `29694156854`, the GitHub packages API) and the tag@digest ref exercised end-to-end (pull/create/inspect) against the published image. cosign remains unimplementable: the image is unsigned by design (`build-inngest-bootstrap-image.yml`: "NOT cosign-signed (no id-token perm)"), so a verify would gate the sole scheduler's boot on an artifact that has never existed.
- [x] 1.2.2 Correct the false `cosign-verify` comment in the same PR. — **DONE.** Corrected in place (recorded, not deleted) at the GHCR-bake comment in `cloud-init-inngest.yml`; `inngest-host.test.sh` item 11 now fails if a signature check is CLAIMED without one being EXECUTED, and requires the corrected prose to name the absence, cite CF-2, and name the digest pin. Both legs mutation-tested against the original sentence.
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
- [x] 1.4.1 Add `inngest-server-probe.{service,timer}` probing `http://127.0.0.1:8288/health`.
- [x] 1.4.2 Set `SyslogIdentifier=inngest-server-probe` explicitly (#6536).
- [x] 1.4.3 Emit **unconditionally before** classification (ADR-117).
- [x] 1.4.4 **Carry discriminating fields in one event:** `http_code` (incl. `000`), `vector_active`, `redis_active`, `uptime_s`, `boot_id`, image sha. A boolean marker reproduces #6617 one layer up.
- [x] 1.4.5 If the unit runs Doppler as root, set `Environment=HOME=/root`. — **N/A by construction, and deliberately so:** the probe needs no secrets, so it wraps no `doppler` (bare `curl` to loopback + `logger`) and inherits neither the `$HOME`-undefined trap nor the `DOPPLER_CONFIG_DIR`/`PrivateTmp` collision that cost #6536 three days. The unit carries a comment requiring `Environment=HOME=/root` if a future edit ever adds `doppler run`.

**A4 delivery notes.** The units are written and armed entirely by `inngest-bootstrap.sh` (OCI-baked, per CF-3) alongside the existing heartbeat units — no operator step, no SSH, reached on a fresh host by the cloud-init bootstrap block. The timer is armed there and the oneshot also fired once immediately, so a fresh replace ships its first marker in seconds rather than at `OnBootSec`. Cadence is **hourly** (`OnBootSec=90s`, `OnUnitActiveSec=1h`): Source 4 applies no PRIORITY filter, so a 60s probe would itself cost ~1,440 rows/day — the very cost 1.6 removes. `image_sha` is sourced from `/etc/default/soleur-inngest-image`, written by `cloud-init-inngest.yml` from the digest-pinned `$IREF` right after the pull.

### 1.5 Vector allowlist (A5, #6617c)
- [x] 1.5.1 Set `SyslogIdentifier=inngest-redis` on `inngest-redis.service` (currently tagged `doppler`).
- [x] 1.5.2 Set `SyslogIdentifier=inngest-nftables` on the nftables unit (currently tagged `inngest-nftables.sh`).
- [x] 1.5.3 Add `inngest-server-probe`, `inngest-redis`, `inngest-nftables` to Source 4. **Do NOT add `inngest-boot-phone-home`** — it never calls `logger` and has no journald channel (CF-4).
- [x] 1.5.4 Assert each tag by exact value in `journald-config.test.sh`, and cross-check the literal appears in **both** the unit file and `vector.toml`.
- [x] 1.5.5 **CF-3, unconditional:** rebuild the bootstrap image, push the tag, bump the `IREF` pin off `v1.1.23`. Without this, 1.4/1.5/1.6 are undeliverable. — **DONE and verified by measurement, not assumption.** Tag `vinngest-v1.1.24` pushed → build run `29694156854` succeeded (the zot mirror step also succeeded, at the same digest). The published image was then pulled and its `/vector.toml` and `/inngest-bootstrap.sh` extracted: they carry this PR's Source 4 tag trio, the `inngest-server-probe` unit and the dark-arm rate limiter. Pin bumped on **both** hosts (`cloud-init-inngest.yml` IREF; `cloud-init.yml` IREF + ZIREF) — the pin-drift guard requires them to agree with the semver-max published tag. `grep -c 'v1.1.23'` == 0 in both.

### 1.6 Rate-limit the dark heartbeat arm (A6, #6617b)
- [x] 1.6.1 Change to a **low periodic cadence (hourly)** — NOT transition-only, which eliminates the positive control (CF-9).
- [x] 1.6.2 Confirm the diff writes **no** heartbeat URL value anywhere. — **Asserted, not merely confirmed:** `inngest.test.sh` fails if any delivered infra artifact assigns `INNGEST_HEARTBEAT_URL` a literal URL, or bakes a Better Stack heartbeat URL. Both anchored on assignment/URL constructs rather than the bare name (the repo is full of prose and `name = "INNGEST_HEARTBEAT_URL"` definitions), and both mutation-tested. Provisioning the URL stays `op=arm`'s job at G4; doing it early is the dual-pusher state #6552 prevents.

**A6 implementation note.** `dark_arm_emit_due()` in the ping script gates only the `logger` call — `exit 0` stays outside it, so #6536's storm fix (an absent URL never reaches `curl`) is untouched. It **fails open**: an unreadable/unwritable stamp emits anyway, degrading to today's row volume rather than to a silently disarmed signal. `inngest-heartbeat.service` gains `RuntimeDirectory=inngest-heartbeat` + `RuntimeDirectoryPreserve=yes`; both are load-bearing (the unit runs `User=deploy` and `/run` is root-owned 0755, and a `Type=oneshot` would otherwise lose the directory — and the stamp — on every fire).

### 1.7 Apply routing + ADR (A7)
- [ ] 1.7.1 Route the replace through the maintenance-window `apply_target=inngest-host` dispatch; state it in the PR body (CF-8 — this host has NO `ignore_changes`).
- [ ] 1.7.2 Update ADR-096 §5.3's enumeration to register the new inngest pull site + emit names. — **N/A in PR-A′: there is nothing to register.** The withdrawn A2 arm was what would have added a second pull site (`ZURL`) and the `inngest_zot` / `inngest_ghcr_fallback` emit names. PR-A′ adds **no** new pull site (the single GHCR arm at `cloud-init-inngest.yml:390` is digest-pinned in place, not added) and **no** new emit name. Verified: `grep -c 'soleur-boot-emit\|inngest_zot\|inngest_ghcr_fallback' apps/web-platform/infra/cloud-init-inngest.yml` == **0**. Editing §5.3 to register sites that do not exist would corrupt the checklist that 5.3's irreversible PAT revoke checks against. **Re-open this task with the A2 arm.**

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
- [ ] 3.5 Paste Phase 0 probe results verbatim into the PR-A body, including the literal zot status. A `401`/`403` blocks merge. — **N/A in PR-A′ as a merge blocker; the paste still applies.** This AC was written for the zot-primary arm, where a `401`/`403` meant the arm PR-A was shipping could not work. Phase 0 MEASURED anonymous `/v2/` → `401`, and that measurement is precisely *why* the gate withdrew the arm. PR-A′ has **zero** zot dependency, so read literally this AC would block its own merge on the finding that justifies it. Post the A0 evidence verbatim to `#6500` and the PR body (that part is unchanged); the `401` blocks the **zot arm**, not PR-A′.
- [ ] 3.6 PR-A′: `Ref #6500`, `Ref #6617` — **`Ref`, never `Closes`**, because the Phase 0 gate withdrew the zot arm and `#6500` stays OPEN (closing it is the ADR-096 §5.3 authorization act). PR-B: `Ref #6441`, `Ref #6466` (never `Closes`).

## Phase 4 — Post-merge (gated dispatch, API-verified)

- [ ] 4.1 Dispatch the replace via the maintenance-window `apply_target=inngest-host` path.
- [ ] 4.2 Confirm the fresh boot emits **`inngest_zot`** (not "zot or fallback" — a fallback boot increments the soak's fallback counter and resets it to FAIL).
- [ ] 4.3 `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep SOLEUR_INNGEST_SERVER_PROBE` returns ≥ 1 row.
- [ ] 4.4 `inngest-heartbeat` channel rows `< 50` over a 24 h window starting **≥ the replace timestamp**.
- [ ] 4.5 `zot-soak-6122.sh` passes **both** arms — the `#6500`-CLOSED check AND the two anchored code greps.

## Known unresolved (do not silently absorb)

- [ ] **Post-5.3 break-glass.** ADR-096 5.3 deletes the GHCR fallback branch, leaving the singleton with exactly one registry and no recovery if zot is down at boot. This plan does not solve it. 5.3 must not proceed until a break-glass exists.
- [ ] **First-run risk.** The replace is both the delivery mechanism and the first execution of the new boot code. Consider GHCR-primary/zot-secondary first, flipping preference on a second replace.
