# fix: ADR-100 Inngest dedicated-host cutover — remaining code blockers

---
type: bug-fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issues: [6500, 6441, 6617]
adrs: [ADR-096, ADR-100, ADR-114, ADR-115, ADR-117]
created: 2026-07-19
revision: 2 (post-deepen — PR-B redesigned; see Deepen-Review Critical Findings)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Enhancement Summary

**Deepened:** 2026-07-19 · **Revision 2**
**Agents:** architecture-strategist, security-sentinel, observability-coverage-reviewer,
spec-flow-analyzer, repo-research-analyst, learnings-researcher
**Gates fired:** 4.5 (network-outage), 4.55 (downtime/cutover — section was **missing**), 4.6, 4.7, 4.8, 4.9

### What the deepen pass changed

Revision 1 passed every plan-time gate and would have caused an outage. Two of
its own design decisions were fatal, and a third made the work undeliverable:

1. **PR-B was redesigned end-to-end.** The `|| exit 1` NIC gate would have
   **bricked a fresh web-1** — `runcmd` is one shell, so the abort takes
   cloudflared, the webhook, and every monitor with it, permanently. Revision 1
   would have converted today's *partial, in-band-fixable* degradation into total
   unrecoverable loss: strictly worse than shipping nothing (CF-5).
2. **B3 reversed ADR-115**, an ADR the plan had not read. The web host
   deliberately never self-reboots because that powers off the sole live origin
   (CF-6). B3 is deleted.
3. **A4/A5/A6 had no delivery path.** `vector.toml` and `inngest-bootstrap.sh`
   are OCI-baked, so a host-replace re-pulls the same pinned image and gets the
   old files. Three post-merge ACs were structurally unsatisfiable (CF-3).
4. **The plan's secret placement would have bricked the inngest host** — the boot
   isolation check is exact set equality, so adding any name FATALs the bootstrap
   (CF-1).
5. **There is no cosign on this path**, and revision 1 asserted there was —
   inheriting a false comment rather than grepping. Adding a plain-HTTP zot arm to
   an unverified root-executed payload is a security regression (CF-2).
6. **3 of 4 Vector tags could never match** their units (CF-4).
7. **The `ignore_changes` risk claim was inverted** for the inngest host (CF-8).
8. **The soak greps anchored literals** the mirrored web pattern does not satisfy —
   faithfully copying the reference would have failed the gate forever (CF-7).

### Honest assessment

The recurring failure was **inheriting claims instead of verifying them** —
from a code comment (CF-2), from a sibling host (CF-6), from an ADR's headline
without its amendments, and from the brief itself. Revision 1's own Sharp Edges
section warned about exactly this class and then committed it four times.

The premise-validation work in revision 1 was sound and is retained: three
briefed premises were wrong and all three corrections still hold.

## Overview

Three prerequisite code blockers stand between today's state and a safe ADR-100
cutover. This plan ships them as **two PRs**, split on *which host must be
replaced for the change to take effect* — the only split axis that avoids paying
for two `inngest-host-replace` cycles.

| PR | Issue | Surface | Takes effect via |
|----|-------|---------|------------------|
| **PR-A** | #6500 + #6617 (a, c) | `cloud-init-inngest.yml`, `vector.toml`, `inngest-host.tf` | `inngest-host-replace` |
| **PR-B** | #6441 (**not** #6466 — see Reconciliation) | `cloud-init.yml`, `soleur-host-bootstrap.sh` | fresh web-host boot |

**This plan does NOT execute the cutover.** `cutover-inngest.yml` remains a
separately-gated `workflow_dispatch`. No change to `INNGEST_BASE_URL`; no touch
to the dark Inngest tables; the 2.4 app-repoint draft PR stays held until
`op=arm`.

## Premise Validation

Checked before any research was dispatched (plan Phase 0.6).

| Cited reference | Probe | Result |
|---|---|---|
| #6500 OPEN | `gh issue view 6500` | ✅ OPEN, `priority/p1-high` |
| #6466 OPEN | `gh issue view 6466` | ✅ OPEN, `priority/p1-high`, `deferred-scope-out` |
| #6617 OPEN | `gh issue view 6617` | ✅ OPEN, `priority/p1-high` |
| #6122 OPEN | `gh issue view 6122` | ✅ OPEN (zot migration parent) |
| `cloud-init-inngest.yml` bare `IREF` | `grep -n IREF` | ✅ present — `IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.23` |
| zot absent on inngest host | `grep -in 'zot\|ZIREF\|ZURL'` | ✅ **0 hits** — confirmed no zot path |
| `cloud-init.yml` `ZIREF` pattern | `grep -n ZIREF` | ✅ present |
| ADR-114 NIC-wait prescription | read ADR-114 §I1 | ✅ present — **but attributed to #6441, not #6466** |
| `cloudflared service install` ungated by NIC | read `cloud-init.yml` runcmd | ✅ gated only by `web_tunnel_connector`; no NIC wait |
| Vector Source 4 tag allowlist | read `vector.toml` `[sources.host_scripts_journald]` | ✅ 17 tags; the 4 named tags absent |

Three premises **did not hold as stated**. They are reconciled below.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Codebase reality | Plan response |
|---|---|---|
| "#6466 (P1, GA blocker) — NIC-wait before `cloudflared service install`" | #6466's body is about **host-addressability** (fan-out `/hooks/deploy-status`, per-host infra-config targeting, host-scoped SSH, web-2 promotion runbook). It contains **no** NIC-wait item. ADR-114 §I1 states the gate verbatim and says: *"It is candidate (b) under I2 below, tracked in **#6441**."* #6441 is OPEN. | **Re-attribute.** PR-B ships the NIC-wait against **#6441**, and comments on #6466 to record the split. The *work* is real and unshipped — only the issue number was wrong. #6466 stays open for its own (larger) addressability scope. |
| "Provision the heartbeat URL for the dedicated host so `inngest-heartbeat` stops emitting `url_present=no`" | The `url_present=no` line is the **deliberate dark-arm**, rendered by `inngest-bootstrap.sh` only when `DOPPLER_PROJECT` is the dark project. `INNGEST_HEARTBEAT_URL` is provisioned **by `op=arm` (G4)** in `cutover-inngest.yml`, and `op=rollback` **removes** it — explicitly so a dark host never becomes *"a SECOND pusher on the shared Better Stack heartbeat monitor"* (#6552). | **Reject the prescribed remedy; keep the goal.** Provisioning the URL pre-`op=arm` would (a) bypass the cutover FSM gate, (b) create the exact dual-pusher state #6552 exists to prevent, and (c) contradict this brief's own "nothing before `op=arm`" constraint. The quota waste is real, so PR-A instead makes the dark arm **quiet**: log once per boot + on transition, not every 60 s. Same row reduction, no arming side-effect. |
| "mirror [the ZIREF pattern] onto the inngest host path" | `cloud-init.yml`'s inngest block is gated by `web_colocate_inngest`, whose `default = false` (`variables.tf`). The ZIREF reference pattern therefore lives in a path that **has never executed in production**. | **Use as shape, not as proof.** PR-A adopts the three-tier ADR-096 gate shape but treats it as new code: it gets its own tests and its own measured zot-resolution probe. Do not assume the pattern is battle-tested. |

Two further gaps the brief did not name, both load-bearing:

- **Sentry emit does not exist on the dedicated host.** `grep -i sentry cloud-init-inngest.yml` → **0 hits**. The host reports only to Better Stack via `inngest-boot-phone-home.sh`. `soleur-boot-emit` (the Sentry emitter) is defined in `soleur-host-bootstrap.sh`, which the inngest host **does not run**. #6500's acceptance criterion 2 ("reports on the Sentry `stage:` schema") is therefore a **port**, not a call-site addition — it needs a DSN staged into the isolated `soleur-inngest/prd` project.
- **The inngest host is not an enumerated zot client.** `grep 10.0.1.40` across `zot-registry.tf` + `cloud-init-registry.yml` → **0 hits**. Whether zot's `accessControl` and the registry host's firewall admit `10.0.1.40`, and whether `soleur-inngest/prd` even holds `ZOT_*` credentials, is **unverified**. Phase A0 measures this before any code is written.

## Deepen-Review Critical Findings (must resolve before A2 ships)

Four findings from the deepen pass materially change PR-A. Two are **boot- or
security-fatal and were caused by the plan's own stated design** — recorded here
rather than quietly patched, because each is a class the plan should have caught
at write time.

### CF-1 (CRITICAL, boot-brick) — the plan's secret placement would stop the host booting

`cloud-init-inngest.yml` runs a fail-closed isolation self-check asserting
**exact set equality**, not a prefix filter:

```sh
n_inngest="$(printf '%s\n' "$names" | grep -Ec '^(INNGEST_(SIGNING_KEY|EVENT_KEY|REDIS_PASSWORD|POSTGRES_URI|HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN)$' || true)"
if [ "$n_total" -ne "$n_inngest" ] || [ "$n_inngest" -lt 5 ]; then
```

The original §Infrastructure said to source the Sentry DSN and the `ZOT_*`
credential from `soleur-inngest/prd`. The moment those land, `n_total > n_inngest`
→ `FATAL: boot credential not isolated` → the `/run/soleur-inngest-doppler.ok`
sentinel is never dropped → the bootstrap block aborts. **The singleton never
boots.** The check counts what the *token can see*, so no delivery mechanism
(`templatefile()` vs `doppler run`) dodges it.

The constant is encoded in **three places that must move together**: the regex,
the `-lt 5` cardinality floor, and the "5 dark / 6 live" comment above it.

**Resolution:** A3 gains an AC asserting all three move in the same PR, plus an
`inngest-host.test.sh` case pinning the admitted-name set by exact value. This
is not optional cleanup — it is the difference between a working host and a brick.

### CF-2 (CRITICAL, security) — there is no cosign verification on this path, and the plan repeated a false comment

`grep cosign apps/web-platform/infra/cloud-init-inngest.yml` returns **exactly one
hit, and it is a comment** claiming *"the cold-boot soleur-inngest-bootstrap OCI
pull + cosign-verify authenticates…"*. `cosign verify` exists only in
`ci-deploy.sh` (the app-deploy path) and `cloud-init-registry.yml`. The inngest
bootstrap path is:

1. `IREF=…:v1.1.23` — a **mutable tag**, not a digest
2. `docker pull` / `docker create` / `docker cp`
3. `bash "$EXTRACT_DIR/inngest-bootstrap.sh"` — **executed as root**

No signature check anywhere. Today the only integrity control is GHCR's TLS +
authn. **The zot arm as originally specified would replace that with plain HTTP
on the private net** — after which anything that can answer at `10.0.1.30:5000`,
or spoof it on `10.0.1.0/24`, serves a root shell script to the singleton
scheduler.

This plan's original A2 asserted *"image ref, docker auth, and cosign target move
together."* **That was false, and it was false because this plan inherited the
comment's claim instead of grepping the path** — precisely the failure mode its
own Sharp Edges section warns about ("a false comment shipped the bug, then the
plan, guard, ADR and tests each restated it"). The plan restated it.

**Resolution — A2 is now gated.** Before the zot arm may ship, one of:

- **(a)** pin `IREF` by `@sha256:` digest against a repo constant, and assert the
  resolved digest matches; or
- **(b)** add a real `cosign verify` step before `docker create`.

A0's reachability gate is **not** a substitute — the blocking gate is
*verification*, not *reachability*. And the false comment at `:236` must be
corrected in the same PR, per the corpus-honesty standard this plan applies to
ADR-114.

Note the same hole exists on the web precedent (`cloud-init.yml` pulls
`$ZURL/…:v1.1.23` unverified). That is a pre-existing gap, not this PR's to fix —
but it is why "mirror the web pattern" was never a safety argument.

### CF-3 (P0) — `vector.toml` is OCI-baked, so neither named delivery path works

`vector.toml` is baked into the bootstrap image (`Dockerfile:205`) and reaches
the host via `docker cp soleur-inngest-bootstrap-extract:/vector.toml` in
`cloud-init-inngest.yml`. A replaced host **re-pulls the same pinned
`v1.1.23`** and therefore gets the **old** `vector.toml`.

This is the mechanism behind the drift the brief flagged. A5's two candidate
delivery paths (host-replace, or `-target`ed reload) **neither of them delivers a
baked file.** A5 now requires: rebuild the bootstrap image, bump `IREF`, and push
the tag **in the same PR** (`hr-tagged-build-workflow-needs-initial-tag-push`),
then replace. The conditional "if PR-A bumps the image" line is promoted to an
unconditional requirement.

### CF-4 (P1) — three of the four new Vector tags can never match

Source 4 is an **exact-value** `SYSLOG_IDENTIFIER` match. Verified against the units:

| Tag | Reality | Verdict |
|---|---|---|
| `inngest-server-probe` | new unit, sets `SyslogIdentifier=` explicitly | ✅ matches |
| `inngest-redis` | unit sets **no** `SyslogIdentifier`; `ExecStart=/usr/bin/doppler …` → journald tags it **`doppler`** | ❌ never matches |
| `inngest-nftables` | unit sets **no** `SyslogIdentifier`; `ExecStart=/usr/local/bin/inngest-nftables.sh` → tagged **`inngest-nftables.sh`** (with `.sh`) | ❌ never matches |
| `inngest-boot-phone-home` | **never calls `logger`** — it is a pure `curl` POST to the Better Stack HTTP ingest; emits **zero** journald lines | ❌ no channel exists |

The brief's item 3c is therefore correct in intent but incomplete as a
prescription: adding the tags alone is a no-op. A5 must **also** set
`SyslogIdentifier=inngest-redis` and `SyslogIdentifier=inngest-nftables` on those
two pre-existing units, and **drop `inngest-boot-phone-home` from the allowlist**
(or add a `logger -t` mirror alongside its POST — but it already ships to Better
Stack directly, so the tag buys nothing).

The plan's own Sharp Edge said "every **new** unit sets it explicitly" — which
structurally does not cover these three **pre-existing** units. AC5 as originally
written (repo grep + exact-value assert) **passes on all three broken tags**.

### CF-5 (CRITICAL, PR-B bricks the host) — `runcmd` is ONE shell, so `|| exit 1` aborts everything downstream

`cloud-init.yml` states it verbatim: **`set +e # H3 (#6090): scope set -e — runcmd is ONE /bin/sh; leak = silent abort (plan).`**

The original B2 inserted `soleur-wait-ready nic 10.0.1.10 … || exit 1` immediately
before `cloudflared service install`. That `exit 1` does not skip one step — it
**terminates the entire remaining runcmd**: the cloudflared install, the webhook
binary install and its unit-enable step, the port-9000 readiness gate, the
disk/resource/container monitors, and the container egress firewall. And
`runcmd` is **once-per-instance** — a reboot does not re-run it. So even if the
NIC converges at minute 11, the host never installs cloudflared.

**The original design made things strictly worse.** Compare honestly:

| | Today (no gate) | Original B2 (`\|\| exit 1`) |
|---|---|---|
| NIC down at boot | connector installs and works; `deploy.` + `ssh.` **up**; only the `registry.` route (`10.0.1.30:5000`) is broken | **nothing installs**; `deploy.` + `ssh.` + webhook + monitors all dark, permanently, no in-band recovery |

Today's failure is a *partial, diagnosable, in-band-fixable* degradation. The
original B2 converted it into total unrecoverable loss — the exact outcome this
plan's own User-Brand Impact section names as the thing to avoid. `server.tf`
already documents this failure mode as the reason the connector gate exists.

**PR-B is redesigned.** See the rewritten phase below.

### CF-6 (CRITICAL, ADR-115 reversal) — the web host deliberately never self-reboots, and the plan missed the ADR

`web-private-nic-guard.sh` states the divergence explicitly:

> It DIVERGES from the registry guard in ONE deliberate way: **it NEVER reboots.**
> ADR-115's two normative reboot-blockers earn the registry ONE host's self-reboot
> authority; on a web host a reboot would power-off the SOLE live origin, so the
> web variant is **detect + emit + alarm ONLY.**

The original B3 said *"mirror the registry host's converger … do not write a fresh
converger."* That **reverses ADR-115's normative blocker** — and the plan's
Architecture Decision section simultaneously claimed *"None reverses or extends a
recorded Decision."* That claim was false, and **ADR-115 was absent from the
plan's ADR set entirely.** It is now added.

The sibling the plan was looking for already exists (`web-private-nic-guard.sh`)
— it deliberately lacks exactly the half the plan wanted to port. **B3 is deleted.**

### CF-7 (P0) — the soak greps anchored literals the mirrored web pattern does not satisfy

`zot-soak-6122.sh` gates on two anchored predicates, with a comment that
anticipates precisely the weak form this plan originally proposed:

```sh
if ! grep -qE '^[[:space:]]*IREF=.*\$ZURL' "$INNGEST_CI" || ! grep -qE '^[[:space:]]*soleur-boot-emit ' "$INNGEST_CI"; then
```

> *"A comment line begins with `#`, so it can never produce `^\s*IREF=` or
> `^\s*soleur-boot-emit `. Narrowing is not anchoring."*

Two consequences:

- **The web reference pattern does not match.** `cloud-init.yml` writes
  `ZIREF="$ZURL/…"` then `IREF="$ZIREF"` — that never produces
  `^\s*IREF=.*\$ZURL`. Mirroring the web shape *faithfully* makes the soak fail
  forever with `FAIL(blocker-closed-but-condition-unmet)`.
- **A1 must emit via the literal `soleur-boot-emit `**, not a "`soleur-boot-emit`-
  *equivalent*". Any rename breaks 5.3 authorization.

A2 must therefore write the zot ref **directly into `IREF=`** referencing `$ZURL`,
and A1 must name the emitter exactly. AC1/AC3 are rewritten to the soak's own
predicates so the gate and the plan cannot drift on what "fixed" means.

### CF-8 (P1) — the inngest host has NO `ignore_changes`; the plan's risk claim was inverted

The plan's Risks and Distinctness sections claimed *"`ignore_changes = [user_data]`
on **both** host resources: config changes are latent, not live."* `inngest-host.tf`
says the opposite, verbatim:

> Deliberately **NO** `lifecycle.ignore_changes=[user_data]`. … CONSEQUENCE
> (ADR-100): this host is the SOLE scheduler, so **every cloud-init edit
> force-replaces it** → a cron-outage window — **gate all cloud-init edits to the
> maintenance-window `apply_target=inngest-host` dispatch.**

So PR-A's `cloud-init-inngest.yml` edits are **not latent**. Merging PR-A arms a
pending force-replace of the sole scheduler that *any* subsequent `terraform
apply` — including one from an unrelated PR — will execute, outside a maintenance
window, with the untested zot arm on the boot path.

**The required control is the maintenance-window `apply_target=inngest-host`
dispatch gate**, which the plan never mentioned. It is now a named PR-A
requirement. (The claim remains true for the *web* host, which does carry
`ignore_changes` — so PR-B is genuinely latent.)

### CF-9 (P1) — A6 as written eliminates the positive control rather than rate-limiting it

The plan's own Sharp Edge says: *"Emit unconditionally, before classification,
**rate-limited** (ADR-117 / #6537)."* A6 said "once per boot + on transition" —
that is **elimination, not rate-limiting**. Post-A6 a dead heartbeat pusher and a
healthy quiet one become indistinguishable, which is the exact shape ADR-117
describes as *"goes silent exactly when someone ships a probe."*

**Resolution:** rate-limit to a low periodic cadence (hourly), not transition-only.
That still takes ~1,414 rows/24 h down to ~24 rows/24 h — satisfying the quota
goal — while preserving the positive control.

### CF-10 (P2) — the Sentry DSN needs no new Doppler resource, and routing it through one is what triggered CF-1

`variables.tf` already defines `var.sentry_dsn`, sourced from `prd_terraform`,
described as *"Semi-public (already in the client bundle)"*, and already baked
into web cloud-init. `inngest-host.tf` already bakes `ghcr_read_user`/
`ghcr_read_token` through the identical `templatefile()` path — and warns that a
`doppler_secret` here *"would clobber the real value on first create"*.

**Resolution:** pass `var.sentry_dsn` into the existing `templatefile()` map. One
line, established precedent, no new Doppler resource — **and because the value
never enters the `soleur-inngest` project, it does not trip CF-1's isolation
check at all.** Only the `ZOT_*` credentials remain a CF-1 concern.

## Blocking Dependency — zot has never served a pull (#6497)

Surfaced at deepen time, and it reframes what PR-A can honestly claim.

**#6497 (OPEN, P1) establishes that zot has served zero pulls in 90 days** — zero
`registry:zot` *and* zero `registry:ghcr-fallback` Sentry issues. Its framing is
blunt: *"Nothing degraded — the capability never existed."* The root cause was
`/etc/zot/htpasswd` being baked exactly once at boot with **no Terraform data
edge** from `random_password` to the host, so the bake went stale invisibly.

That issue names **three conditions** required for zot to actually serve a pull:

| # | Condition | Tracked by | State |
|---|---|---|---|
| 1 | zot login works | **#6497** | **OPEN** — `replace_triggered_by` has landed (3 hits in `zot-registry.tf`), but the issue stays open on a soak whose `earliest` gate is only now eligible |
| 2 | zot holds the tag | #6416 | CLOSED |
| 3 | the host reaches zot on the private net | #6415 / ADR-115 | CLOSED |

**What this means for PR-A — stated plainly so nobody misreads the result:**

- The zot arm is **correct code that will probably fall back to GHCR on its first
  boot.** That is not a bug in this PR. An implementer who sees
  `inngest_ghcr_fallback` and starts debugging their own diff will burn a day.
- **Closing #6500 does not make the inngest host zot-served.** It makes the host
  *capable* of being zot-served, and it unblocks the soak's C1 blocker arm. Those
  are different claims, and only the second is this plan's to make.
- Condition 3 for *this specific host* is unverified — the inngest host appears
  in no zot client configuration. A0 is what settles it.

**This does not block merging PR-A, and PR-A should not wait for #6497.** The
ordering that matters is against the **PAT revoke**, not against zot working: a
host with a zot arm and a working GHCR fallback is strictly safer than today's
GHCR-only pin, whether or not zot serves. The plan's fail-closed-after-both-arms
posture is what makes that true.

**AC amendment:** AC17 must accept **either** `inngest_zot` **or**
`inngest_ghcr_fallback` as a pass — asserting `inngest_zot` specifically would
make PR-A's acceptance depend on an unrelated open P1.

## Hypotheses

`hr-ssh-diagnosis-verify-firewall` fires (brief matches `SSH`, `unreachable`,
`firewall`, `timeout`). This plan *prevents* an outage rather than diagnosing
one, but the L3→L7 discipline still binds the Phase A0 probe order: **no
service-layer hypothesis may be investigated before L3 is measured.**

| Layer | Question | Verification (Phase A0, before code) |
|---|---|---|
| **L3 — firewall** | Does the firewall admit `10.0.1.40 → 10.0.1.30:5000`? | `hcloud firewall describe` on the registry firewall; diff against `10.0.1.40`. Artifact pasted into the PR body. |
| **L3 — routing** | Does the inngest host hold a private NIC and route to `10.0.1.30`? | Better Stack `net-health` marker — `inngest-boot-phone-home.sh net-health` already emits `nic=`. |
| **L4/L7 — registry auth** | Does `/v2/` answer, and with what status for the inngest identity? | **Measured, not derived** — run the pinned zot digest with the repo's exact `accessControl`, or probe the live private endpoint. Record the literal status. |
| **L7 — mirror content** | Does zot actually carry `soleur-inngest-bootstrap:v1.1.23`? | `manifest_resolves` probe (the shape `zot-entry-gate.sh` uses). #6500 itself warns this is *expected*, not *established*. |

### Network-Outage Deep-Dive (gate 4.5)

Layer-by-layer verification status. Every layer is **explicitly not-yet-verified
with a named command** — none is assumed. The L3 layers are measured *first*, per
`hr-ssh-diagnosis-verify-firewall`; no service-layer hypothesis may be
investigated ahead of them.

| Layer | Status | Artifact required before code |
|---|---|---|
| **L3 firewall allow-list** | ❏ not verified | `hcloud firewall describe` output for the registry firewall, diffed against `10.0.1.40`. |
| **L3 DNS / routing** | ❏ not verified | Private-net reachability `10.0.1.40 → 10.0.1.30`; `nic=` field from the existing `net-health` phone-home marker. No public DNS is involved — both hosts are private-net-only. |
| **L7 TLS / proxy** | ⊘ **not applicable, deliberately** | zot serves **plain HTTP** on the private net (ADR-096). There is no TLS layer to verify; integrity rests on cosign digest-pinning plus `insecure-registries` + `--allow-insecure-registry`. Recording this as N/A rather than silently skipping it: *"no TLS error"* must never be read as *"TLS verified"* on this path. |
| **L7 application** | ❏ not verified | zot `/v2/` literal status for the inngest identity, and `manifest_resolves` for `soleur-inngest-bootstrap:v1.1.23`. |

The web-host side (PR-B) inverts the usual order: the failure being prevented is
*L3 not yet existing* (the private NIC) at the moment an L7 service (cloudflared)
registers. The gate is therefore correctly placed at L3, not at the service layer
— which is the same L3-before-L7 discipline this checklist encodes.

**Sharp edge, binding on Phase A0:** per the #6497 learning, a hypothesis about
a vendored service's HTTP behavior must be **measured against the pinned image**,
never read off its config. No phase of PR-A may branch on an assumed zot status
code. If A0 shows the inngest host cannot reach or authenticate to zot, PR-A's
scope changes from "add a zot path" to "add a zot path **and** enroll the host as
a zot client" — and that enrollment is the larger half.

## User-Brand Impact

**If this lands broken, the user experiences:** a scheduler outage. A botched
NIC-wait can leave a fresh web-1 with no cloudflared connector — `deploy.` and
`ssh.` both dark, unrecoverable in-band (there is no SSH fallback). A botched
zot path can leave the singleton inngest host unable to boot, so every scheduled
reminder, digest, and cron the user depends on silently stops firing.

**If this leaks, the user's data is exposed via:** the GHCR PAT and the zot
credential are both baked into `user_data` at render time. A widened bake — or a
Sentry/Better Stack emit that tails a log containing them — puts registry
credentials into an observability sink with a different retention and access
boundary than Doppler.

**Brand-survival threshold:** `single-user incident`.

One user losing their scheduler is a brand event, not a metric. `requires_cpo_signoff: true`
is set accordingly; `user-impact-reviewer` runs at review time.

## Implementation Phases

### PR-A — inngest host: zot path, Sentry stage emit, self-reporting liveness

Ref #6500. Ref #6617.

> **`Ref`, not `Closes`** — superseded by the Phase 0 STOP/SPLIT gate. PR-A shipped as PR-A′ with the zot arm withdrawn, so `#6500` stays OPEN; auto-closing it would give `zot-soak-6122.sh` a false CLOSED authorization for the irreversible ADR-096 §5.3 PAT revoke.

**A0 — Measure before coding (no code in this phase).**
Run the Hypotheses probes above. Record each literal result in the PR body.

**Two probes the original A0 was missing:**

- **The isolation-allowlist collision (CF-1).** Check whether adding `ZOT_*` to
  `soleur-inngest/prd` trips the exact-set-equality check. This is a near-certain
  first-boot brick on the very replace PR-A depends on, and nothing else in A0
  would surface it.
- **Verification status (CF-2).** Confirm there is no `cosign verify` on this path
  (there is not) and decide digest-pin vs cosign before A2 is written.

**Note the L3 probe is vacuous on its own.** Both firewalls are zero-rule
deny-all on the **public** interface only; intra-`10.0.1.0/24` traffic is
unfiltered by design. So `hcloud firewall describe` will return "allowed" and
that result carries **no information about enrollment** — the only access control
on zot is the user-scoped htpasswd `accessControl` block. A0 must not read
*L3-permitted* as *A0-passed*. (The corollary is the real security statement: any
compromised host on the private net already has network reach to the registry,
which is exactly what makes CF-2 load-bearing rather than theoretical.)

**Gate — and what the stop branch concretely does.** If zot cannot serve
`10.0.1.40`:

1. **Do not** write a fallback whose primary arm can never succeed.
2. **Split the PR rather than blocking it.** A4/A5/A6 (probe unit, Vector tags,
   heartbeat rate-limit) have **no dependency on zot whatsoever**. Ship them as
   PR-A′ — they carry their own value and their own replace. Only A1/A2 wait.
3. **File the enrollment work** as a new issue (zot client enrollment for
   `10.0.1.40`: `accessControl` entry + scoped identity), link it from #6500, and
   post the A0 results to #6500 so the soak's blocker arm keeps vetoing 5.3.
4. **The stop branch is stable, not a stalemate:** with #6500 open the soak
   refuses to authorize 5.3, so the PAT stays live and the host stays bootable.
   That is the safe direction — but say so explicitly rather than leaving it
   implied.

**A1 — Port the Sentry stage emitter to the dedicated host.**
Add the emitter to `cloud-init-inngest.yml`, named **literally `soleur-boot-emit`**
(CF-7: the soak greps `^\s*soleur-boot-emit ` — an "equivalent" with a different
name breaks 5.3 authorization). DSN via **`var.sentry_dsn` through the existing
`templatefile()` map** (CF-10) — not a new `doppler_secret`, which would both
duplicate an existing variable and trip CF-1's isolation check.

Keep `inngest-boot-phone-home.sh` — this is *additive*; Better Stack stays the
boot-stage channel, Sentry becomes the channel `zot-soak-6122.sh` can query. Emit
on the pull path: `inngest_zot` (info) / `inngest_ghcr_fallback` (warning).

**Copy the `soleur-boot-emit` shape, NOT the phone-home shape.** This is the
security-critical detail. `soleur-boot-emit`'s payload is closed-vocabulary by
construction — fixed tags (`stage`, `host_id`, `region`), **no free-form field**.
That property is exactly what makes the Sentry channel leak-proof. The inngest
host's existing phone-home takes a free-form `detail` argument and callers pass
redacted log tails to it. An implementer working inside `cloud-init-inngest.yml`
— where *every* emit call takes two arguments — will reach for the two-argument
shape by reflex, and credential-bearing pull tails will begin flowing to Sentry,
a sink with different retention and **no `inngest-redact.sh` anywhere in its
path**. The emitter must accept no free-form argument, and an AC must assert it.

**A2 — Zot-primary pull with GHCR fallback. GATED ON CF-2.**
Replace the bare `IREF=` with the ADR-096 three-tier gate: `/v2/` probe → zot pull
→ atomic fallback to GHCR. Image ref and docker auth move together (ADR-096
Edge A/B: `insecure-registries` + `--allow-insecure-registry`). The pull stays
**fail-closed** after both arms are exhausted — the fallback widens the inputs, it
does not soften the gate.

**Verification must land first (CF-2).** There is no cosign on this path today
and the ref is a mutable tag. Shipping a plain-HTTP zot arm onto an unverified
root-executed payload is a net security *regression*, so A2 does not merge until
either the digest pin or a real `cosign verify` is in place. Correct the false
`cosign-verify` comment in the same PR.

**`insecure-registries` is host-wide and permanent** — it downgrades the docker
daemon's trust for that endpoint for *every* future pull on the singleton, not
just the boot pull. Scoped to an exact `host:port` it is the right shape, but it
is only acceptable paired with CF-2's verification. Ship neither without the other.

**A3 — Give the file a CI owner.**
`cloud-init-inngest-bootstrap.test.sh` reads `cloud-init.yml` despite its name;
`inngest-host.test.sh` has zero `ghcr`/`IREF`/`zot` assertions. Add assertions to
`inngest-host.test.sh` covering: zot arm present, GHCR fallback present, pull
fail-closed, Sentry emit present, and the pin matching the tag the drift-guard
derives. **This is what stops the pin silently drifting again** — it is the root
cause #6500 names, not a nice-to-have.

**A4 — Positive liveness marker (#6617a), with discriminating fields.**
Add `inngest-server-probe.{service,timer}` to `inngest-bootstrap.sh`: probe
`http://127.0.0.1:8288/health`, emit via `logger -t inngest-server-probe`, and set
`SyslogIdentifier=inngest-server-probe` explicitly (#6536). Emit
**unconditionally before classification** (#6537/ADR-117). If the unit runs
Doppler as root, set `Environment=HOME=/root`.

**A boolean marker reproduces #6617 one layer up.** "Zero rows" is produced
identically by: inngest-server dead · Vector dead · host down · Better Stack
ingest/egress dead · timer not enabled · **the tag being dropped by the allowlist
(CF-3/CF-4)**. On day one the *most likely* cause of zero rows is the probe's own
undelivered channel — so an undifferentiated marker would be untrustworthy
exactly when first consulted. The marker must therefore carry, in **one** event:
literal `http_code` (**including `000`** — connect-refused vs timeout),
`vector_active`, `redis_active`, `uptime_s`, `boot_id`, and the image/config sha
it booted from. Then `http_code=000 vector_active=active` reads *server dead*,
while total silence reads *shipper or host dead* — two states, two signatures.

**A5 — Vector allowlist (#6617c): fix the units, then rebuild the image.**
Two corrections from CF-3 and CF-4 change this phase substantially.

1. **Set `SyslogIdentifier=` on the two pre-existing units** —
   `SyslogIdentifier=inngest-redis` and `SyslogIdentifier=inngest-nftables`.
   Without this the tags match nothing (they are currently tagged `doppler` and
   `inngest-nftables.sh` respectively).
2. **Drop `inngest-boot-phone-home` from the allowlist** — it never calls
   `logger`; it is a pure `curl` POST and has no journald channel at all. It
   already ships to Better Stack directly, so the tag buys nothing.
3. Add `inngest-server-probe` + the two corrected tags to
   `[sources.host_scripts_journald].include_matches.SYSLOG_IDENTIFIER`.
4. **Rebuild the bootstrap image, bump `IREF`, and push the tag — in this PR.**
   `vector.toml` and `inngest-bootstrap.sh` are **baked into the OCI image**
   (`Dockerfile`) and `docker cp`'d out of the pinned ref at boot. A host-replace
   re-pulls the *same* `v1.1.23` and gets the *old* files. Neither of the
   originally-named delivery paths works. This is unconditional, not a
   contingency (`hr-tagged-build-workflow-needs-initial-tag-push`).

Without step 4, A4/A5/A6 are **undeliverable by construction** and their
post-merge ACs are unsatisfiable.

**A6 — Rate-limit the dark heartbeat arm (#6617b, re-scoped; see CF-9).**
Change the dark arm from an unconditional 60 s `logger` line to a **low periodic
cadence (hourly)** — *not* once-per-boot-and-transition, which would eliminate
the positive control rather than rate-limit it (ADR-117). ~1,414 rows/24 h →
~24 rows/24 h, which meets the quota goal while keeping a dead pusher
distinguishable from a healthy quiet one. **This PR writes no heartbeat URL value
anywhere** — that is `op=arm`'s job (see Reconciliation).

**A7 — Gate the apply to the maintenance window (CF-8).**
`inngest-host.tf` carries **no** `ignore_changes = [user_data]`, so merging PR-A
arms a pending force-replace of the sole scheduler that any subsequent
`terraform apply` will execute. Route the apply through the maintenance-window
`apply_target=inngest-host` dispatch the file mandates, and say so in the PR body.

### PR-B — web host: defer cloudflared registration until the NIC is up

Ref #6441. Ref #6466 (records the scope split). **Redesigned post-deepen — see
CF-5 and CF-6. The original fail-closed inline gate is withdrawn as unsafe.**

The invariant is ADR-114 §I1: *a host MUST NOT serve as a tunnel connector unless
it can serve every ingress rule — concretely, its private NIC is up.* The
redesign enforces that invariant **without** an in-band abort and **without** a
reboot, which are the two things CF-5 and CF-6 rule out.

**Design principle: defer, don't abort.** A slow NIC should *delay* connector
registration, not terminate the boot. Deferral preserves the recovery channel;
abortion destroys it. This is the whole difference between the original design
and this one.

**B1 — Make cloudflared's activation depend on NIC readiness.**
Rather than blocking `runcmd`, express the precondition where systemd can retry
it: a NIC-readiness condition on the cloudflared unit (an `ExecStartPre` poll, or
a small oneshot the unit is ordered `After=`), so a late attach delays
registration and systemd converges on its own. Everything downstream of the
install line in `runcmd` continues to execute regardless — webhook, monitors, and
the egress firewall all still land, so the host stays reachable and diagnosable.

**Explicitly NOT:** `soleur-wait-ready nic … || exit 1` in `runcmd`. `runcmd` is
one shell (CF-5); an abort there is unrecoverable and strictly worse than today.

**B2 — Emit the state, positively, on both arms.**
The web host **does** run `soleur-host-bootstrap.sh`, so `soleur-boot-emit` (the
Sentry `stage:` emitter) is available here — unlike the inngest host. Emit
`private_nic_ready` (info) on success **and** `private_nic_timeout` (warning) on
the deferral branch, so a NIC that never converges produces a *row*, not a
silence. This is the layer citation the original plan's fourth failure mode was
missing.

**B3 — (deleted).** The original "mirror the registry converger" step reversed
ADR-115's normative reboot blocker. The web-host guard
(`web-private-nic-guard.sh`) already exists and is deliberately detect-and-emit
only, because a reboot here powers off the sole live origin. **If a web-host
converge is genuinely wanted, that is an ADR-115 amendment and a CPO decision —
not an implementation detail smuggled into a bug-fix PR.**

**B4 — Test the render and the ordering.**
Assert that with `web_tunnel_connector=true` the NIC precondition governs
cloudflared activation, and with `false` neither renders. **Also assert the
negative:** no `exit 1` is introduced into the `runcmd` path — a regression guard
for CF-5, which is the failure this PR exists to avoid rather than cause.

**B5 — Reconcile ADR-114's I1 status honestly.**
I1 carries three inconsistent status statements today: the original *"Not shipped
in #6416"*, a 2026-07-15 amendment declaring I1 **enforced** via the
single-connector gate, and a 2026-07-17 amendment saying it is **inert on the
running fleet**. Do **not** edit the original sentence — it sits inside preserved
*"text as originally written"* and editing it corrupts the record the amendment
convention exists to protect. Add a **new consolidating amendment note** that
reconciles all three and records what this PR ships (the distinct runtime NIC
gate, as opposed to the already-shipped single-connector gate).

## Files to Edit

**PR-A**
- `apps/web-platform/infra/cloud-init-inngest.yml` — Sentry emitter (A1), zot gate (A2)
- `apps/web-platform/infra/inngest-bootstrap.sh` — probe units (A4), dark-arm quieting (A6)
- `apps/web-platform/infra/vector.toml` — 4 tags (A5)
- `apps/web-platform/infra/inngest-host.tf` — DSN/`ZOT_*` template vars (A1/A2)
- `apps/web-platform/infra/inngest-host.test.sh` — CI ownership (A3)
- `apps/web-platform/infra/journald-config.test.sh` — Source 4 tag assertions (A5)

**PR-B**
- `apps/web-platform/infra/cloud-init.yml` — NIC-wait before cloudflared (B2)
- `apps/web-platform/infra/soleur-host-bootstrap.sh` — `nic` verb (B1)
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — render+ordering tests (B4)

**Files to Create:** none. Every change extends an existing surface.

## Infrastructure (IaC)

### Terraform changes

**Corrected post-deepen (CF-1, CF-4, CF-10).** The original design here was the
direct cause of the boot-brick in CF-1.

- **Sentry DSN:** pass the **existing `var.sentry_dsn`** into `inngest-host.tf`'s
  existing `templatefile()` map — the same path that already carries
  `ghcr_read_user`/`ghcr_read_token`. **No new `doppler_secret`** (the file warns
  one *"would clobber the real value on first create"*), and because the value
  never enters the `soleur-inngest` project it does not touch the isolation check.
- **`ZOT_*` credentials:** these *do* interact with CF-1. If they land in
  `soleur-inngest/prd`, the boot isolation self-check's **exact set equality**
  fails and the host will not boot. Whichever delivery is chosen, the isolation
  triple — the regex, the `-lt 5` floor, and the "5 dark / 6 live" comment —
  **must move in the same PR**, with a test pinning the admitted-name set.
- **Prefer a scoped third identity over duplicating the fleet credential.**
  `ZOT_PULL_TOKEN` currently lives in `soleur/prd` and is read by web hosts.
  Copying that *value* into the inngest project makes the inngest boot token a
  path to a credential that reads every image in the shared registry, including
  the web app image. Doppler *inheritance* is unchanged — but inheritance is the
  wrong invariant; the threat is **value duplication**. Minting a third htpasswd
  identity (a new `random_password` plus one `accessControl` policy entry) costs
  one line and converts a shared-secret widening into a scoped, independently
  revocable enrollment.
- **Redaction:** `inngest-redact.sh` builds its scrub list from an **explicit
  enumeration** of credential files. A new zot env file is **not** in that list.
  The only backstop is a `{40,}` length pattern, and `random_password.zot_pull`
  is **exactly 40 chars** — it matches by one character of margin, and any length
  decrement or surrounding punctuation silently drops it below threshold. Add the
  zot env file to the enumeration explicitly; do not rely on the backstop.

No new Terraform root; no new provider.

**If A0 shows the inngest host is not an authorized zot client**, this section
grows an `accessControl` entry enrolling the new identity. That is a scope
expansion to be surfaced, not absorbed silently.

### Apply path
**(c) taint + `-replace`** — `inngest-host-replace`, the existing 5-target guarded
dispatch (server + NIC + firewall + volume attachment + volume). Blast radius:
the singleton inngest host. **Zero prod impact today** because the host is dark —
this is precisely why the work must land *before* the cutover, not after.

Per `2026-07-07-immutable-redeploy.md`: `-target` walks **upstream, not
downstream**. The replace must `-target` the dependent attachments explicitly, or
the new host comes up off the private net and/or public-exposed before the
firewall re-attaches. The existing 5-target allow-set already encodes this — use
it; do not hand-roll a narrower target list.

PR-B needs no apply: `cloud-init.yml` governs *future* fresh web hosts. The
running fleet carries `ignore_changes = [user_data]`, so the gate is inert until
web-1 is next recreated — which is exactly the cutover's resume path.

### Distinctness / drift safeguards
- `soleur-inngest/prd` ≠ `soleur/prd` — asserted by the boot isolation self-check, which is **exact set equality** and therefore fail-closed on *any* added name (CF-1).
- **`ignore_changes` is asymmetric — the original plan had this backwards (CF-8).**
  - **web host:** carries `ignore_changes = [user_data]` → PR-B is genuinely **latent** until a recreate.
  - **inngest host:** carries **NO** `ignore_changes` → PR-A's cloud-init edits arm an **immediate pending force-replace** of the sole scheduler, executable by any later apply. Route through the maintenance-window `apply_target=inngest-host` dispatch (A7).
- Tag↔pin coupling (`hr-tagged-build-workflow-needs-initial-tag-push`): PR-A **must** rebuild the bootstrap image, push the tag, and bump the pin — unconditionally, because `vector.toml` and `inngest-bootstrap.sh` are OCI-baked (CF-3).
- **Repo file ≠ shipped file.** `vector.toml` and `inngest-bootstrap.sh` reach the host only via the image. No AC may assert a running-host effect from a repo grep alone.

### Vendor-tier reality check
No new vendor resource. `betteruptime_heartbeat.inngest_prd` already exists and
is `paused = true`; this plan does **not** unpause it and does **not** add a
heartbeat.

## Downtime & Cutover

Gate 4.55 fired (infra replace class: `-replace` on `hcloud_server.inngest`;
PR-B's gate is consumed by a web-1 recreate). Zero-downtime is the default and
both PRs achieve it — but for **different reasons**, and one of them is
temporal, which is the whole argument for landing this work now.

### PR-A — zero downtime, because the host is dark

The offline-inducing operation is `inngest-host-replace` (`terraform apply
-replace` over the 5-target allow-set). The affected surface is the singleton
`hcloud_server.inngest`.

**Today this costs nothing.** The host runs against a non-prod (dark) Postgres
backend; no user-facing scheduling depends on it. The replace is a cold boot of
a machine nobody is talking to.

**After the cutover the same operation is a full scheduler outage** — ADR-100
makes this host a *singleton* and defers the HA failover pair to #6185. There is
no rolling or blue-green path for a singleton by construction.

So the zero-downtime path here is **sequencing, not mechanism**: do the replace
while the host is dark. This is not a nice-to-have — it inverts to a
`single-user incident` if deferred past `op=arm`. Any suggestion to "ship this
after the cutover" should be read as converting a free operation into an outage.

**Per-stage verification / rollback:** the FSM (`INNGEST_CUTOVER_FLIP`) is
untouched by this plan and the poll timer ships enabled for the host's whole
life, so `op=rollback` remains reachable throughout. The durable Redis AOF
volume survives the replace by omission from the destroy set.

### PR-B — zero downtime, because nothing applies

`cloud-init.yml` governs **future fresh hosts only**. The running fleet carries
`ignore_changes = [user_data]`, so merging PR-B changes nothing about the
running web-1. No apply, no restart, no window.

### The web-1 recreate is a real outage — and it is not this plan's to schedule

Stating it plainly, because the retirement changed the picture: **web-2 was
retired 2026-07-17 (#6538), so web-1 is the sole web host.** The blue-green
mechanism itself — *"blue-green host replacement via add/drain/remove"* — is
#6459, still OPEN and marked *ADR needed*, and it is gated on git-data (#6570).
There is therefore **no blue-green partner and no blue-green mechanism today** —
a web-1 recreate is a total platform outage window, not a drain-and-cut-over.

This is worth stating precisely because it is the strongest argument for PR-B:
the one recovery mechanism that would make a bad recreate survivable does not
exist yet, so the in-band recovery path is the only one there is.

This plan does **not** schedule that recreate; the cutover does. What PR-B
changes is the *shape of the failure* inside that window:

| | Without the NIC-wait | With the NIC-wait |
|---|---|---|
| NIC converges normally | brief outage, host returns | brief outage, host returns |
| NIC converges late | cloudflared registers pre-convergence → connector cannot serve private-net ingress → `deploy.` and `ssh.` both dark → **unrecoverable in-band** | boot blocks, converger reboots, host returns |
| NIC never converges | silent half-broken connector | fail-closed: host does not become a connector, and says so via the stage marker |

The NIC-wait does not shorten the window. It removes the branch where the
window **never ends**. On a single-host fleet with no SSH fallback, that is the
difference between an outage and an incident.

**Residual accepted:** the bounded-window timeout means a pathologically slow
attach still fails closed rather than serving degraded. That is the correct
trade at this threshold — a host that cannot serve every ingress rule must not
be a connector (ADR-114 I1).

## Observability

```yaml
liveness_signal:
  what: SOLEUR_* marker from inngest-server-probe (HTTP 200 on 127.0.0.1:8288/health)
  cadence: hourly (OnBootSec=90s, OnUnitActiveSec=1h) systemd timer
    # NOT 60s. Source 4 applies no PRIORITY filter, so every fire ships a row;
    # per-minute would cost ~1,440 rows/day against the ~25k/day Better Stack
    # quota — the exact cost #6617b removes from the heartbeat in this same
    # change. Every query window below is sized against this hourly period.
  alert_target: Better Stack Logs source 2457081 (absence-of-marker is queryable)
  configured_in: inngest-bootstrap.sh (unit) + vector.toml Source 4 (allowlist)

error_reporting:
  destination: Sentry (stage: schema, new on this host) + Better Stack (existing phone-home)
  fail_loud: true — the OCI pull stays fail-closed after both registry arms

failure_modes:
  - mode: zot unreachable / unauthorized at boot
    detection: Sentry stage:inngest_ghcr_fallback (warning)
    alert_route: zot-soak-6122.sh denominator; sentry_issue_alert.zot_mirror_fallback_rate
  - mode: both registries fail
    detection: Sentry stage-fatal + Better Stack oci-pull-rc-<n> + absent boot markers
    alert_route: host never reaches bootstrap-done; marker absence localizes the stage
  - mode: inngest-server dead but host up
    detection: inngest-server-probe marker with http_code=000 AND vector_active=active
      (a POSITIVE signature, not an absence — absence alone cannot distinguish this
      from a dead shipper or a dead host)
    alert_route: Better Stack Logs, inngest-server-probe channel
  - mode: shipper or host dead
    detection: total absence of the inngest-server-probe marker across a window
      longer than the 1h timer period (>=3h; see discoverability_test)
    detection_latency: ~2h worst case. A death immediately after a fire is
      invisible for the remaining ~1h of that period, and absence is only
      conclusive once a >=2h window has elapsed with no row. This is the
      accepted cost of the hourly cadence — a 60s probe would detect in
      minutes but at ~1,440 rows/day against a ~25k/day quota. For a dark,
      not-yet-cut-over host this trade is correct; revisit it at G4 when the
      scheduler carries live traffic.
    alert_route: Better Stack Logs absence-detection; see the alerting gap below
  - mode: fresh web host defers cloudflared indefinitely (NIC never converges)
    detection: soleur-boot-emit private_nic_timeout (warning) — a POSITIVE row on the
      deferral branch, emitted from soleur-host-bootstrap.sh which the web host runs
    alert_route: Sentry stage: schema (the same layer the web host's other boot
      stages already use)

logs:
  where: Better Stack Logs source 2457081 via Vector Source 4 (journald)
  retention: per existing Better Stack plan

discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 3h --grep SOLEUR_INNGEST_SERVER_PROBE
  expected_output: >=2 rows in a 3h window on a healthy host; zero rows is now a
    POSITIVE down-signal rather than an ambiguous silence
    # The window MUST exceed the 1h period. At --since 1h a healthy host run 40
    # min after the last fire returns zero rows, and the down-signal reading
    # above would declare a live scheduler dead. 3h spans >=2 fires even with
    # AccuracySec=1min skew at both edges, so >=2 rows is the healthy floor.
```

**The gap this closes.** Vector Source 1 ships only `PRIORITY 0-4`, so a healthy
inngest-server is *structurally silent*. Absence-of-WARN was the only liveness
signal — which is why #6617's question stayed unanswerable for days. A5's three
tags are the same class: `inngest-redis`, `inngest-nftables`, and the new
`inngest-server-probe` emit at `PRIORITY 5-6` and match **no** source today, so
their zero-row state carries no information at all. (`inngest-boot-phone-home`
is **not** among them and is deliberately absent from Source 4's allowlist — it
never calls `logger`, so it emits zero journald lines to allowlist; see the
table at "never calls `logger`" above and `journald-config.test.sh`, which
asserts that absence.)

**Alerting gap — stated, not papered over.** Everything above is *queryable*;
almost none of it *fires*. `alert_target` is a Better Stack Logs source, and a
query is not an alert — nobody is notified. Worse, a `systemd` timer on a
deny-all-public host **cannot detect its own host being down**; the probe's
silence is exactly the signal it is least able to send.

This plan deliberately does **not** unpause `betteruptime_heartbeat.inngest_prd`
(that is `op=arm`'s job), so it adds no firing alert either. The honest position:
**PR-A converts an unanswerable question into an answerable one, not into a
monitored one.** Absence-alerting for the dedicated host needs an *external*
observer — a Better Stack log-absence rule, or an off-host scheduled query that
opens an issue — and that is **deferred with a tracking issue**, not silently
assumed. Do not read AC27 (a one-shot query at merge time) as ongoing monitoring.

**Live-state caveat:** `inngest.tf` sets `paused = true` but also carries
`lifecycle { ignore_changes = [paused] }`, so the repo config is **not
authoritative** for live pause state (ADR-117's arming pattern unpauses via a
one-time API PATCH). Any claim about whether the monitor is currently live must
come from an API read, not from the `.tf` file — per
`hr-no-dashboard-eyeball-pull-data-yourself`. This cuts *toward* the plan's
heartbeat rejection: if the monitor is already live, the dual-pusher harm is
immediate rather than deferred.

**Known drift (in scope to state, out of scope to fix):** the deployed OCI image
predates the current repo `vector.toml`, so running behavior does not match repo
config — a `PRIORITY=6` row arrived despite Source 1's documented `0-4` filter.
No AC in this plan may treat the repo file as evidence of running-host behavior.

### Soak follow-through enrollment
PR-A's zot arm feeds `zot-soak-6122.sh`, whose C1 blocker arm reads #6500's state
via `gh`. Closing #6500 is what unblocks that arm — **do not remove the arm to
make the gate pass** (#6500's own instruction). No new soak script; this plan
extends an existing soak's denominator.

## Architecture Decision (ADR/C4)

### ADR
**No new ADR** — but the original claim here (*"None reverses or extends a
recorded Decision"*) **was false** and is corrected. The plan had omitted ADR-115
entirely, and its original B3 reversed that ADR's normative reboot blocker
(CF-6). ADR-115 is now in the plan's ADR set and B3 is deleted.

The remaining changes do *implement* recorded decisions: ADR-096 (three-tier zot
gate), ADR-114 §I1 (the NIC precondition), ADR-100 / ADR-117 (dedicated-host
observability and positive controls).

**Two amendments are required, both in-scope:**

- **ADR-114 §I1 — a NEW consolidating note, not an edit.** I1 carries three
  inconsistent status statements (original *"Not shipped in #6416"*; a 2026-07-15
  amendment declaring it **enforced** via the single-connector gate; a 2026-07-17
  amendment calling it **inert on the running fleet**). The original sentence sits
  inside preserved *"text as originally written"* — editing it corrupts the record
  the amendment convention protects. Add a consolidating note instead.
  **Also correct the framing:** PR-B is not "shipping I1" (candidate (b) already
  shipped in #6425). It ships the *distinct runtime NIC gate*. That reframing
  matters — it removes "the ADR demands this" as a justification for accepting a
  large blast radius, which is precisely how the original B2/B3 got waved through.
- **ADR-096 §5.3 enumeration** — register the new inngest pull site and its emit
  names (AC15). 5.3 is irreversible and its enumeration is the checklist it
  validates against.

### C4 views
**No C4 impact.** Enumeration checked against all three model files
(`model.c4`, `views.c4`, `spec.c4`):

- **External human actors:** none added.
- **External systems:** zot registry, GHCR, Sentry, Better Stack, Cloudflare
  Tunnel — all already modeled (`zot` 22 refs, `ghcr` 9, `sentry` 14,
  `betterstack` 15, `tunnel` 14 in `model.c4`), all already `include`d in
  `views.c4`.
- **Containers / data stores:** none added. The inngest host and registry host
  are modeled.
- **Actor↔surface access relationships:** unchanged. The inngest host already
  has a modeled pull edge; this plan changes *which registry it prefers*, not
  *who may reach what*.

The one thing that would change this: if A0 forces enrolling `10.0.1.40` as a new
zot client, that **is** a new relationship edge and the `.c4` edit becomes an
in-scope task.

## Domain Review

**Domains relevant:** Engineering.

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure-only change across two immutable hosts. The
dominant risks are sequencing (an unbootable singleton with no rollback if
ADR-096 5.3 lands first) and latency-of-effect (`ignore_changes = [user_data]`
makes every change latent until a replace). Both are addressed structurally: the
CI-ownership phase (A3) prevents recurrence of the ungoverned-pin root cause, and
the apply-path section names the delivery step for every latent change. Product,
Legal, Finance, Marketing, Sales, Support, Operations: not relevant — no
user-facing surface, no new vendor, no new recurring cost, no regulated-data
surface.

**Product/UX Gate:** skipped — mechanical UI-surface scan over `Files to Edit`
matched zero paths under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`.
Tier NONE.

## GDPR / Compliance Gate

Not invoked. No regulated-data surface: no schema, no migration, no auth flow, no
API route, no `.sql`. Triggers (a)–(d) do not fire — no LLM processing of
operator data, no new cron reading `knowledge-base/`, no new artifact
distribution surface. The `single-user incident` threshold (trigger b) is
declared, so this is recorded rather than skipped silently: the threshold is set
by *availability* blast-radius, not by personal-data processing.

One adjacent note carried from User-Brand Impact: registry credentials are baked
into `user_data`. PR-A must not widen that bake, and must not tail credential-
bearing logs into Sentry — `inngest-boot-phone-home.sh` already documents that
its POST bypasses Vector's PII scrub, so anything it ships must be pre-scrubbed.

## Open Code-Review Overlap

**None.** Queried all 61 open `code-review` issues; zero bodies reference
`cloud-init-inngest.yml`, `cloud-init.yml`, `vector.toml`, `inngest-bootstrap.sh`,
or `inngest-host.tf`.

## Acceptance Criteria

Rewritten post-deepen. Several originals asserted a **proxy** rather than the
invariant, and AC17 admitted the failure state as a pass.

### Pre-merge (PR-A)

1. **The soak's own predicate passes:** `grep -qE '^[[:space:]]*IREF=.*\$ZURL' apps/web-platform/infra/cloud-init-inngest.yml`. (Replaces the original bare-word grep, which the soak's author explicitly documented as defeatable by a comment line — *"narrowing is not anchoring"*.)
2. The zot arm is followed by a GHCR fallback and the pull remains fail-closed after both — asserted by an `inngest-host.test.sh` case.
3. **The soak's second predicate passes:** `grep -qE '^[[:space:]]*soleur-boot-emit ' apps/web-platform/infra/cloud-init-inngest.yml`, emitting `inngest_zot` / `inngest_ghcr_fallback`.
4. **CF-2 verification gate:** `IREF` is digest-pinned (`@sha256:`) **or** a `cosign verify` step precedes `docker create`. The false `cosign-verify` comment is corrected in the same PR.
5. **CF-1 isolation triple:** if any `ZOT_*` name is added to `soleur-inngest/prd`, the check's regex, its `-lt N` floor, and the "N dark / N+1 live" comment all move together; `inngest-host.test.sh` pins the admitted-name set by exact value.
6. **A1 emitter is closed-vocabulary:** its JSON body carries only fixed tags and accepts **no** free-form argument (asserted by grep on the emitter body). Guards against the phone-home shape leaking redacted tails into Sentry.
7. `inngest-redact.sh`'s enumeration includes any new zot credential file — not relying on the `{40,}` length backstop.
8. Vector Source 4 contains `inngest-server-probe`, `inngest-redis`, `inngest-nftables`; **`inngest-boot-phone-home` is absent** (CF-4 — it has no journald channel). `journald-config.test.sh` asserts each by exact value.
9. `inngest-redis.service` and the `inngest-nftables` unit each set `SyslogIdentifier=` matching their Source-4 tag **byte-for-byte** (Vector's `include_matches` is exact equality). One AC asserts the literal appears in **both** files.
10. `inngest-server-probe.{service,timer}` render with explicit `SyslogIdentifier=`, emit **unconditionally before** classification, and the marker carries the discriminating fields (`http_code` incl. `000`, `vector_active`, `redis_active`, `uptime_s`, `boot_id`, image sha).
11. **CF-3 delivery:** the bootstrap image is rebuilt, the tag pushed, and the `IREF` pin bumped off `v1.1.23` in this PR. `grep -c 'v1.1.23' cloud-init-inngest.yml` == 0.
12. The dark heartbeat arm emits on a rate-limited periodic cadence (not transition-only), and the diff contains **no write of a heartbeat URL value** (expected count 0).
13. A0's probe results are pasted verbatim in the PR body, **including the literal zot HTTP status**, and a `403`/`401` status blocks merge rather than being recorded and passed over. — **The paste applies to PR-A′; the merge block does not.** A0 measured anonymous `/v2/` → `401`, and that result is what drove the gate to withdraw the zot arm. Blocking PR-A′ — which has zero zot dependency — on the finding that justified narrowing it to zero zot dependency is circular. The `401` blocks the **A2 arm**, which is exactly what happened.
14. `inngest-host.test.sh` and `journald-config.test.sh` both exit 0.
15. **ADR-096's 5.3 enumeration is updated** to register the new inngest pull site and its emit names — 5.3 is irreversible and its checklist is *"the claim 5.3 checks against"*, so a new fallback branch it does not know about is a silent gap. — **N/A in PR-A′ because there is no new site or name to register.** This AC presupposed the A2 zot-primary arm, which the Phase 0 gate withdrew. PR-A′ digest-pins the *existing* single GHCR arm rather than adding a branch, and adds no emit name (`grep -c 'soleur-boot-emit\|inngest_zot\|inngest_ghcr_fallback' apps/web-platform/infra/cloud-init-inngest.yml` == 0). Registering non-existent sites would corrupt the very checklist 5.3 validates against. Retained, not deleted: this AC becomes live again with the A2 arm.
16. PR body uses `Ref #6500` — **not `Closes`**, because the Phase 0 gate returned STOP/SPLIT and withdrew the zot arm, so `#6500` stays OPEN (closing it is the irreversible ADR-096 §5.3 authorization act) — plus `Ref #6617`, and states the maintenance-window `apply_target=inngest-host` routing (CF-8).

### Pre-merge (PR-B)

17. Cloudflared activation is gated on NIC readiness **via a systemd precondition**, not via `runcmd`.
18. **Regression guard for CF-5:** the diff introduces **no** `exit 1` into the `runcmd` path (`git diff` on `cloud-init.yml` shows zero added `exit 1` lines). This is the AC that prevents this PR from causing the outage it exists to prevent.
19. `soleur-boot-emit` fires `private_nic_ready` on success **and** `private_nic_timeout` on the deferral branch — the failure has a row, not a silence.
20. With `web_tunnel_connector=false`, no NIC gate and no cloudflared install render.
21. **ADR-114 gains a new consolidating I1 amendment note** reconciling the three inconsistent status statements. The original *"Not shipped in #6416"* sentence is **left untouched** (it is preserved historical text).
22. No reboot/converge behavior is added to the web host (ADR-115 normative blocker).
23. `cloud-init-inngest-bootstrap.test.sh` exits 0.
24. PR body uses `Ref #6441` and `Ref #6466` — **not `Closes`** (latent until a web-1 recreate).

### Post-merge (gated dispatch — all API-verified)

25. Replace dispatched **through the maintenance-window `apply_target=inngest-host` path**, not a bare apply.
26. **The fresh boot emits `inngest_zot`** — narrowed from the original "zot **or** ghcr_fallback", which would have admitted a pass in a state that *increments the soak's fallback counter and resets the soak to FAIL*. A `ghcr_fallback` boot is an expected outcome given #6497, but it is **not** an acceptance pass; record it and keep #6500's zot arm unproven.
27. `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 3h --grep SOLEUR_INNGEST_SERVER_PROBE` returns ≥ 2 rows. **Window must exceed the timer period** — the probe fires hourly (`OnUnitActiveSec=1h`), so a `--since 1h` window is a coin flip in both directions and a healthy host would read as dead. **Verified form** — `--grep` is repeatable/OR-combined; the Doppler wrapper is required (a bare invocation has no credentials).
28. **Deterministic replacement for "drops materially":** `inngest-heartbeat` channel rows `< 50` over a full 24 h window whose start is **≥ the replace timestamp** (so old-host and new-host rows are not mixed in one window).
29. `zot-soak-6122.sh` passes **both** arms — the `#6500`-CLOSED check **and** the two anchored code greps. The original AC checked only the first.

**Automation:** all post-merge ACs are API-readable (`gh workflow run`,
`betterstack-query.sh`, Sentry API). Per `hr-no-dashboard-eyeball-pull-data-yourself`
each carries a deterministic verdict rule — including AC28, which the original
("materially") did not.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Sequencing:** ADR-096 5.3 revokes the GHCR PAT before PR-A merges → the singleton is unbootable with no rollback (5.3–5.5 are irreversible). | This plan is the 5.3 blocker. #6462 already wires the soak to refuse while #6500 is OPEN. Do not weaken that arm. |
| **A0 shows zot cannot serve `10.0.1.40`.** | Explicit stop-and-re-scope gate. A fallback whose primary arm can never succeed is worse than no fallback — it looks fixed and is not. |
| **Baked config:** `vector.toml`/`inngest-bootstrap.sh` reach the host only via the OCI image, so repo edits alone are inert (CF-3). | A5 step 4 makes the image rebuild + tag push + pin bump unconditional. AC11 asserts the pin moved off `v1.1.23`. |
| **Un-gated force-replace (CF-8):** PR-A's cloud-init edits arm a pending replace of the sole scheduler that any later apply executes, outside a maintenance window. | A7 routes through the `apply_target=inngest-host` dispatch; AC16 requires the PR body to state it. |
| **Post-5.3 there is no fallback at all.** ADR-096 5.3 *deletes* the GHCR pull-site branch. After that the singleton scheduler has exactly one registry. A zot outage at the next boot = unbootable host, and the soak proves only historical service, never next-boot availability. | **This plan does not resolve it, and says so.** Flagged as the highest-consequence unaddressed state: 5.3 must not proceed until a break-glass path for the singleton exists. Raised here so it is not discovered during an irreversible step. |
| **First execution of new boot code is on the production singleton** — the replace is simultaneously the delivery mechanism and the first run; rollback is another replace onto the same `user_data`. | Prefer landing GHCR-primary/zot-secondary first and flipping preference on a second replace, or render and exercise the pull block against a disposable host before dispatching. |
| **`-target` walks upstream only** → replaced host lands off the private net or public-exposed. | Use the existing 5-target allow-set; do not hand-roll. |
| **Fresh Hetzner host boots with private NIC down** → B2's wait times out on an attached-but-unconverged host. | B3 mirrors the registry host's bounded-reboot converger rather than writing a new one. |
| **PR-B is latent on the running fleet** → a "fixed" claim that is inert. | AC16 uses `Ref`, not `Closes`. #6441 closes when a fresh web-1 has actually booted through the gate. |
| **The ZIREF reference pattern has never run in production** (`web_colocate_inngest` default false). | Treated as new code with its own tests; not assumed correct by precedent. |
| **Credential widening** into Sentry/Better Stack via a log tail. | Pre-scrub anything the phone-home ships (it bypasses Vector's PII scrub by design). |

## Alternatives Considered

| Option | Verdict |
|---|---|
| **One PR for all three items** | **Rejected.** PR-B touches a different host with a different apply path; bundling couples a web-host boot change to an inngest-host replace for no benefit. |
| **Three PRs (one per issue)** | **Rejected.** #6500 and #6617(a,c) both land on `cloud-init-inngest.yml`/`vector.toml` and both take effect via the *same* `inngest-host-replace`. Splitting them buys a second replace cycle and nothing else. |
| **Provision the heartbeat URL now** (as briefed) | **Rejected** — bypasses the `op=arm` gate and creates the dual-pusher state #6552 exists to prevent. Re-scoped to quieting the dark arm. |
| **Extend `zot-soak-6122.sh` to query Better Stack** instead of porting Sentry to the host | **Rejected** — #6500's acceptance names the Sentry `stage:` schema explicitly, and the soak's other six paths already report there. Two schemas for one verdict is the worse shape. |
| **Attribute the NIC-wait to #6466** (as briefed) | **Rejected** — ADR-114 tracks it under #6441. Filing against #6466 would close an issue whose actual scope (host-addressability) remains untouched. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or contains placeholder text fails `deepen-plan` Phase 4.6.
- **Do not derive zot's HTTP behavior from its `accessControl` config.** Measure it against the pinned image (#6497). A policy-less user gets `Login Succeeded`, not `403` — a plan branching on an assumed status code builds an unreachable arm and tests that assert a string that cannot exist.
- **`grep` on the repo proves the file, not the host.** Both hosts carry `ignore_changes = [user_data]` and boot from pinned OCI images that predate `main`. "Baked and latent" is a claim about an artifact that may not exist — verify tag recency and content-carrier before trusting it.
- **An unset `SyslogIdentifier=` is the #6536 trap.** systemd tags the unit with the ExecStart basename (`doppler`, `bash`, `curl`), which matches no Vector source — the channel is silently dark. Every new unit in this plan sets it explicitly.
- A positive-control marker gated on the health it reports vanishes exactly when it is needed. Emit unconditionally, before classification, rate-limited (ADR-117 / #6537).
