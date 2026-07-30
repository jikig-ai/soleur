---
title: "fix(dev): bind the local Supabase stack to loopback instead of 0.0.0.0"
date: 2026-07-30
type: fix
branch: feat-one-shot-supabase-bind-loopback
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: "conditional — C1..C6 folded into this revision (see §Domain Review)"
labels: [type/security, domain/engineering, priority/p1-high]
plan_revision: v2 (post 7-agent review)
---

# fix(dev): bind the local Supabase stack to loopback instead of 0.0.0.0

> Spec lacks valid `lane:` (no `spec.md` on this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Step 0 — Immediate mitigation, before anything else

**Run `supabase stop` right now. Do not wait for this plan.**

The exposure is live and has been for **three weeks** (`supabase_db_web-platform` uptime, measured).
Stopping the stack closes 100% of it in seconds at zero cost, because **nothing depends on it**:
normal local development runs against the *hosted* dev project
(`apps/web-platform/README.md` §"Running locally"), and CI starts its own disposable stack. Three
weeks of idling is itself the evidence that nothing needs it running.

Record the stop timestamp in the PR body as the exposure-close time. Everything below makes the
*next* start safe — it is no longer a race, which is what lets this plan keep its RED-before-GREEN
ordering instead of rushing the fix. **Restart the stack only for the brief attended windows that
capture RED evidence (Phase 0.1, Phase 1.3), and Phase 0 must exit with the machine safe.**

## Overview

The local Supabase CLI stack for `apps/web-platform` publishes every service port on **all**
interfaces, exposing an unauthenticated database admin UI and four other unauthenticated services
to every device on whatever network the laptop joins.

**Measured baseline (this host, 2026-07-30).** Every published port answers a TCP connect on the
LAN IPv4, on both globally routable IPv6 addresses, *and* on loopback:

| Port | Service | `127.0.0.1` | LAN IPv4 `192.168.1.142` | Global IPv6 `2a01:e0a:…:4f92` |
|---|---|---|---|---|
| 54321 | Kong API gateway | OPEN | **OPEN** | **OPEN** |
| 54322 | Postgres | OPEN | **OPEN** | **OPEN** |
| 54323 | Studio (unauthenticated DB admin UI) | OPEN | **OPEN** | **OPEN** |
| 54324 | Inbucket (mail catcher) | OPEN | **OPEN** | **OPEN** |
| 54327 | Analytics / Logflare | OPEN | **OPEN** | **OPEN** |

`ss -tlnp` shows `0.0.0.0:5432{1,2,3,4,7}` and `[::]:5432{1,2,3,4,7}`. **This table is not
exhaustive** — see §Port coverage for the transient shadow DB (54320), the disabled pooler (54329),
the edge-runtime inspector (8083), and the **link-local IPv6** address `fe80::…%wlp0s20f3`, which
is reachable by exactly the modelled on-link attacker and which a `scope global` probe never sees.

This is Docker's default publish behaviour via `supabase start`, not an attacker artifact. It is
the last open item from the 2026-07 laptop-compromise remediation. **No production change.**

### The three controls, honestly labelled

An earlier revision called a point-of-use guard "the security boundary". That was wrong, and the
error was load-bearing — it was the stated reason for tolerating fragility elsewhere. A guard that
stops a *test harness* does nothing to close a socket a stranger is connecting to. Corrected:

1. **Layer 1 — the wrapper + a loopback-bound Docker network. The only boundary.** It is what
   actually stops the ports being published on non-loopback addresses.
2. **Layer 2 — reusing the CLI's own network name.** Not a boundary; it makes Layer 1 hold when
   someone types bare `supabase start`. Free, because `--network-id <the CLI's own name>` is a
   no-op against the CLI default — no probe apparatus, no fallback branch.
3. **Layer 3 — an always-on detector.** `assert` wired into the existing SessionStart hook, so an
   exposed stack surfaces **without anyone running anything special**. This answers "what tells the
   founder their running stack is exposed?" — previously nothing did, because the only signal fired
   on the path an exposed developer is by definition not on.

**Cut from the previous revision:** a fail-closed binding guard inside the RLS-fuzz harness. It was
not a boundary, it would have added a hard `docker` binary + socket dependency to a *required merge
gate* (breaking the supported `RLS_FUZZ_CI_DB_HOST` path, which has no Supabase containers at all),
and it would have turned `local-dsn-guard.ts` — a deliberately pure, IO-free validator with a test
asserting it performs no resolution — into a subprocess-spawning module. Five of seven reviewers
converged on removing it.

**The durable asset is the gate, not the wrapper.** The gate reads **Docker's** state, so it
survives a CLI rewrite, a v3 default change, and a pin bump unchanged. The wrapper and Layer 2 are
version-coupled (§Limits #8). That asymmetry is why this plan stays small.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Codebase reality | Plan response |
|---|---|---|
| "The local Supabase **dev stack**" — implies the primary local development database. | It is **not**. `apps/web-platform/README.md` §"Running locally" prescribes `doppler run -p soleur -c dev -- npm run dev` against the **hosted dev** project. The local CLI stack is solely the **ADR-111 RLS/authz-fuzz substrate**. | Enables §Step 0: the stack can simply be stopped, because no workflow depends on it. |
| "Do not break … any test that assumes these ports." | Every consumer already targets **loopback**: `rls-authz-fuzz.yml` sets both DSNs to `postgres://postgres:postgres@127.0.0.1:54322/postgres`; the six `test/rls-fuzz/*.integration.test.ts` default to the same; `scripts/rls-parity-check.ts` likewise. | Compatible by construction. **Correction:** the earlier claim "the harness could never have used a LAN address" was false — `local-dsn-guard.ts` reads `RLS_FUZZ_CI_DB_HOST` with no shape constraint, so an explicit override *can* allow one. Accurate: no committed consumer uses a LAN address, and the allowlist rejects one absent that override. |
| "Check whether other Supabase projects in the repo have the same exposure." | `git ls-files \| grep -c 'supabase/config\.toml'` → **1**. No `docker-compose*.y{a,}ml` for local dev. | No sibling to fix. **Correction:** an earlier draft claimed the gate covered "a future second project" while pinning its filter to `label=…project=web-platform`. Fixed: filter on label **key presence**, making the claim true. |
| "verify before assuming" that no `config.toml` bind key exists. | **Verified absent**, six ways. See §Mechanism. | Adopted the vendor-documented mechanism; limits stated per the brief. |
| Implicit: this is laptop-only. | `rls-authz-fuzz.yml` runs `supabase start` on a GitHub runner with the same pinned CLI 2.84.2. | Wired through the same wrapper. **Precise about what CI detects:** it starts a *fresh* stack, so it verifies the **mechanism** against the pinned CLI and the runner's Docker. It cannot see the founder's laptop — that is Layer 3's job. |
| Implicit: `supabase start` is how these ports get published. | **False, and the most important finding of the review.** All 11 containers carry `RestartPolicy: unless-stopped` and `docker` is `enabled` at boot (measured). **dockerd republishes these ports on every boot and every daemon restart, with no wrapper involvement.** | On this host the wrapper is the *minority* publish path. Probe P2 verifies the binding survives a daemon restart; promoted to AC5. |

## Premise Validation

The brief cites no issue or PR by reference, so there is no stale-blocker risk. Cited artifacts
verified present: `config.toml` (396 lines, read in full), all five container names, and the
exposure itself — reproduced, and found **broader** than claimed (IPv6 global *and* link-local).
No open GitHub issue tracks this exposure.

**Own-capability claims** (`hr-verify-repo-capability-claim-before-assert`): "the CLI offers no bind
knob" rests on six independent artifacts, not memory (§Mechanism).

**Mechanism vs. the ADR corpus.** Grepped the decisions dir for the mechanism's keywords. **ADR-111**
is the only hit governing this substrate; it pins CLI 2.84.2, names the canonical loopback DSN, and
sets the precedent for a local-only `config.toml` knob (`[db.migrations] enabled = false`). It is
**silent on bind address** — neither decided nor rejected. No rejected-alternative collision.

## Hypotheses

The brief contains `firewall`, tripping the network-outage gate
(`plugins/soleur/skills/plan/references/plan-network-outage-checklist.md`,
`hr-ssh-diagnosis-verify-firewall`). Applied inverted — the symptom is over-reachability — but the
L3→L7 ordering stands: establish which layer admits the packet before fixing higher.

1. **L3 — host packet filter.** **Verified: none in play.** No ufw/nftables/firewalld ruleset for
   these ports; **no `/etc/docker/daemon.json` exists** (measured); the repo's only firewall
   artifacts (`apps/web-platform/infra/firewall-9000-deny.test.sh`, `cloud-init-*.yml`) govern
   Hetzner production hosts. Docker's `DOCKER` DNAT chain is traversed *before* `INPUT`, so a naive
   host deny would not have applied anyway. **Nothing at L3 was ever expected to block this.**
2. **L3/L4 — the DNAT + socket bind. The actual layer.** **Verified as the cause.** Docker
   publishes with no `HostIP`, so bindings inherit the network's default host-binding IP.
   `docker network inspect supabase_network_web-platform --format '{{json .Options}}'` → `{}`, so
   Docker falls back to the daemon default (`docker network inspect bridge` shows
   `"com.docker.network.bridge.host_binding_ipv4":"0.0.0.0"`). **This is the layer the fix targets.**
3. **L7 — service authentication.** **Verified: no help.** Studio ships no auth in local mode; the
   CLI's own banner states "Studio, pgMeta (/pg/\*), and analytics have no authentication".
   Postgres uses the published default `postgres:postgres`. **No L7 fix exists.**

**Opt-outs with artifacts.** *DNS/routing*: probes used literal IPs from `ip -o addr show`, so no
resolver participates. *TLS/proxy*: `[api.tls] enabled = false`; plaintext listeners, no CDN.
*Service journal*: the question is not whether packets arrived (handshakes completed) but whether
they should have been able to.

## Mechanism — why `config.toml` cannot do this, and what can

### No bind-address knob exists (six independent confirmations)

1. **Official config reference** (<https://supabase.com/docs/guides/local-development/cli/config>,
   the URL in `config.toml`'s own header) documents **no** `bind_address`/`listen_address`/`host`/
   `host_ip` at any level — only `port` keys, plus `realtime.ip_version`, which selects IPv4-vs-IPv6
   **protocol**, not a bind address.
2. **The repo's config**, read in full. Every section carries `port` and no listener host key.
   *Precision (review correction):* there are **three** `127.0.0.1` strings — `[studio] api_url`,
   `[auth] site_url`, `[auth] additional_redirect_urls` — all **client-side URLs**. And a literal
   grep does find one `host` key: `# host = "smtp.sendgrid.net"` (commented, `[auth.email.smtp]`),
   an **outbound SMTP relay**, not a listener bind. The conclusion holds; stating it absolutely
   did not.
3. **The installed binary's help.** `supabase start --help` (v2.84.2) lists only `-x/--exclude`,
   `-h/--help`, `--ignore-health-check`. The relevant global flag is
   `--network-id string  use the specified docker network instead of a generated one`.
   *(Verified unchanged at v2.110.0 — `cmd/start.go` is byte-identical between the two tags; the
   only flag added since is `--preview`.)*
4. **CLI source.** At the pinned tag v2.84.2, `internal/utils/docker.go` never sets `HostIP` on port
   bindings, so Docker's default always applies; `--network-id` is honoured via
   `hostConfig.NetworkMode`; and `DockerNetworkCreateIfNotExists` **silently reuses** a pre-existing
   network (`if errdefs.IsConflict(err) … { return nil }`). **Path caveat:** the repo became a
   monorepo after 2.84.2, so that path 404s at v2.110.0 — the equivalent is
   `apps/cli-go/internal/db/start/start.go:121`, still
   `PortBindings: nat.PortMap{"5432/tcp": []nat.PortBinding{{HostPort: hostPort}}}` with no
   `HostIP`. A repo-wide code search for `HostIP` at v2.110.0 returns **zero** hits. The behaviour
   is unchanged; only the paths moved.
5. **Upgrading would not help — checked, not assumed.** The pin is 26 minor versions behind, so
   "just upgrade" is the obvious rebuttal. The releases API was queried for the 100 most recent
   releases (`v2.108.0-beta.38` … `v2.111.0-beta.14`, well past 2.110.0) and filtered for
   `bind|host_binding|127\.0\.0\.1|loopback|listen address|network-id`. **One match, unrelated** —
   `v2.111.0-beta.9`, "pg-delta selinux bind mount".
6. **Upstream already built it, and it was rejected on policy.** This is the strongest citation and
   it makes the workaround **permanent rather than provisional**. PR
   [supabase/cli#4613 "feat/bind to local"](https://github.com/supabase/cli/pull/4613) (opened
   2025-12-12, *"Proposal to bind CLI services to local IPs (while being configurable)"*) was
   **closed unmerged** on 2025-12-23. Maintainer `@sweatybridge`:
   > "If you mean whether we are only binding to localhost by default, the decision is no. It was
   > done for convenience of testing local mobile apps. […] And it would be a breaking change to
   > revert this for existing users."
   > "I believe we should lean on **docker network** because it's more robust than adding our own
   > custom networking config."

   **The maintainer's prescribed alternative is exactly this plan's Layer 1.** There is no upstream
   contribution left to attempt and no CLI upgrade to chase.
   *(Note: [#1977](https://github.com/supabase/cli/issues/1977) was closed as a **duplicate** of
   [#1397](https://github.com/supabase/cli/issues/1397) — say "closed as duplicate", not "closed".)*

**Decoy to name explicitly:** `SUPABASE_SERVICES_HOSTNAME` (added after 2.84.2,
`apps/cli-go/internal/utils/misc.go` `GetHostname()`) reads like a bind knob and will be found by
anyone grepping newer source. It is **dial-side only** — it changes which host the CLI *connects to*
for health checks in dev-container/sibling-Docker setups. It does not affect what containers bind
to. ADR-153 records this so a future session does not "simplify" the wrapper away.

### The vendor-documented remedy

Supabase's Local Development guide (§Quickstart):

> "If your local development machine is connected to an untrusted public network, you should create
> a separate Docker network and bind to 127.0.0.1 before starting the local development stack." …
> "You should never expose your local development stack publicly."

```sh
docker network create -o 'com.docker.network.bridge.host_binding_ipv4=127.0.0.1' local-network
npx supabase start --network-id local-network
```

<!-- verified: 2026-07-30 source: https://supabase.com/docs/guides/local-development -->
*(Live page re-fetched during review: 2 occurrences of `host_binding_ipv4`, the quoted sentence, and
the `--network-id` command. A GitHub code-search returning zero hits for the docs repo is a
search-index artifact, not a discrepancy.)*

### Measured, not assumed

Sources disagree on whether this IPv4-named option leaves the IPv6 `[::]` wildcard in place. Since
that decides whether the mechanism is a complete or a half fix, it was **measured** — throwaway
network and container, created, observed, destroyed:

```text
$ docker network inspect probe-loopback-net --format '{{json .Options}}'
{"com.docker.network.bridge.host_binding_ipv4":"127.0.0.1"}
$ docker ps --format '{{.Ports}}'
127.0.0.1:65432->1234/tcp
$ ss -tlnp | grep 65432
LISTEN 0 4096  127.0.0.1:65432  0.0.0.0:*
```

**A single loopback socket — no `0.0.0.0`, and decisively no `[::]`.** Docker Engine 29.4.3,
rootful. Probe P1 re-measures against the *real* stack rather than trusting this.

### Network identity and the label trap

The wrapper uses the CLI's own network name, **derived from `config.toml`** (`project_id =
"web-platform"`, verified equal to the live container label `com.supabase.cli.project=web-platform`)
— never a hardcoded string repeated in three places.

**The CLI already labels that network.** Measured: `supabase_network_web-platform` carries
`com.supabase.cli.project=web-platform` *and* `com.docker.compose.project=web-platform`.
`supabase stop` → `DockerRemoveAll` → `NetworksPrune` filtered on that label, so a **labelled**
network is destroyed on stop and silently recreated wildcard-bound on the next start. The wrapper's
ensure-condition is therefore **not** "does the option exist" but all three of:

- `Options["com.docker.network.bridge.host_binding_ipv4"] == "127.0.0.1"` (**value equality** — a
  network carrying `0.0.0.0` or a LAN IP passes a presence check and fails open), **and**
- the `com.supabase.cli.project` label is **absent** (else the next `supabase stop` prunes it),
  **and**
- `Driver == "bridge"` (this is a bridge-driver option; any other driver ignores it silently).

Any of the three failing ⇒ recreate. **If `docker network rm` or `docker network create` fails, the
wrapper aborts — it never falls through to `supabase start` on a surviving wildcard network.**

## Port coverage — the fix vs. the verification

Different questions; an earlier draft conflated them.

**The fix is structurally complete.** The network option applies to every container on that
network, including ones that do not exist yet. Enumeration is irrelevant to it.

**The verification is not.** Against `config.toml`:

| Service | Port | Status |
|---|---|---|
| `db.shadow_port` | 54320 | **Gap — transient.** Started by `db diff`/`db lint`/`db reset`, torn down immediately. A point-in-time gate can **never** observe it. Layers 1–2 protect it; nothing verifies it. This is why the wrapper is a general passthrough. Stated in §Limits #4. |
| `db.pooler.port` | 54329 | `enabled = false`. If enabled → persistent → covered by dynamic enumeration. |
| `edge_runtime.inspector_port` | 8083 | Not published today (verified). Published under `functions serve --inspect`. **A `5432[0-9]` regex would miss it** — hence the dynamic port set. |
| `inbucket` smtp/pop3 | 54325/54326 | Commented out; persistent if enabled → covered. |
| `storage.s3_protocol`, `realtime` | — | No host port (verified unpublished; routed via Kong). Not gaps. |

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|---|---|---|
| **A. `config.toml` bind key** | **Impossible** | No such key — six confirmations. The option the brief asked us to verify rather than assume; verified absent. |
| **A2. Upgrade the CLI hoping a knob was added** | **Verified not a fix** | 100 most recent releases contain no bind feature, and PR #4613 shows the maintainers **decided against** the localhost default. Also carries ADR-111 parity risk (the pin is deliberate). |
| **A3. Contribute the flag upstream** | **Already tried, rejected** | PR #4613 closed unmerged 2025-12-23 on stated policy; the maintainer prescribed the docker-network approach instead. Nothing to attempt. |
| **B. Loopback-bound Docker network + `--network-id`** | **CHOSEN** | Vendor-documented **and maintainer-prescribed**; unprivileged; per-project; measured to eliminate `0.0.0.0` **and** `[::]`; repo-owned; CI-verifiable. |
| **C. Docker daemon `{"ip":"127.0.0.1"}`** | **Deferred as a COMPLEMENT, not rejected as an alternative** | *Rationale corrected after review:* the earlier claim that it "would silently break every other container the developer intends to expose" is **empirically false here** — no non-Supabase container publishes anything except Dropbox (`0.0.0.0:17500`), no `/etc/docker/daemon.json` exists (greenfield, no merge surface), and an explicit `-p 0.0.0.0:X:Y` still overrides the default, so breakage is a **loud** connection-refused with a one-flag remedy. C is the fail-safe-**default** posture and is immune to every fail-open path B has. Excluded from *this* PR only because it is root-level host configuration deserving its own cycle and IaC review — not because it is worse. Deferral raised to `priority/p2-medium`. |
| **D. `DOCKER-USER` packet-filter rules** | Rejected as primary | Does not fix the binding; sockets stay wildcard and exposure returns on any rule flush or a machine without the rules. Requires root. Folded into the deferral with C. |
| **E. `supabase start -x studio,inbucket,logflare,vector`** | Complementary note | Reduces surface (Studio is the worst offender) but leaves **Postgres 54322 — the highest-value target — still exposed**. Recorded in the ADR as an available lever. |

## Architecture Decision (ADR/C4)

### ADR — a standalone **ADR-153**, not an ADR-111 amendment

*This reverses the previous revision on review.* The earlier rationale ("ADR-111 owns this
substrate"; "a thin ADR would fragment the contract"; "no ordinal claimed ⇒ no collision risk") does
not survive scrutiny — and the third was bookkeeping convenience dressed as an architectural reason,
now **struck**. Reasons for a standalone record:

- **Different subject.** ADR-111 is a *test methodology* (reproducing an authenticated request at
  the DB layer, why `db reset` is incompatible, the parity contract). This is a *host security
  posture*.
- **Different revisit triggers** (Docker engine behaviour, CLI networking policy — none touch
  ADR-111's contract) and **different lifetime**: if the fuzz harness were retired tomorrow, this
  decision would still bind anyone who types `supabase start`.
- **Terse ADRs are the sanctioned shape.** `principles-register.md` §Notes AP-011: "Default is
  terse (3 sections)". Precedents: ADR-129, ADR-132, ADR-147.
- ADR-111 is `Status: adopting` and already carries four layered sub-decisions plus an ADR-112
  amendment. "Can I `docker system prune`?" must be findable by someone debugging Docker, not RLS.

**ADR-153 content:** the mechanism and its six-way justification, including **PR #4613's rejection
and the maintainer's docker-network prescription** (the reason this workaround is permanent, not
provisional); the three-control structure and **which one is the boundary**; the value-equality +
label-absence + bridge-driver ensure-condition; the `NetworkSettings.Ports`-not-
`HostConfig.PortBindings` rule; the `unless-stopped` republish path; the `SUPABASE_SERVICES_HOSTNAME`
decoy; the measured dual-stack result; §Limits; alternatives C/D/E. **Plus a re-evaluation trigger:**
*if the CLI pin ever moves to a v3 line, re-check whether the localhost default landed — and if it
did, delete the wrapper and Layer 2 and keep only the gate.*

Ordinal is **provisional** (ADR-152 is highest today); `/ship` re-verifies against `origin/main`
before merge. Add a one-line `Related: ADR-153` cross-reference to ADR-111.

### C4 views

**No C4 impact**, established by reading all three model files
(`diagrams/{model.c4,views.c4,spec.c4}`), not by keyword grep:

- **External human actors:** the four modelled actors are `founder`, `emailSender`, `betaContact`,
  `contributor`. No new role — the developer running the stack is already `founder`/`contributor`.
- **External systems/vendors:** none added. Local Docker Engine and the Supabase CLI are developer
  tooling, not deployed platform components.
- **Containers/data stores:** the modelled `supabase = database "Supabase PostgreSQL"` is the
  **hosted** project (HTTPS/PostgreSQL edges from `webapp`, `api`, `engine`, `claude`, `auth`,
  `inngest`, `coordinator`) — untouched. The local CLI stack is an unmodelled ephemeral substrate.
- **Access relationships:** none of the modelled edges change.

The three views scope the model to the deployed platform; no element description is falsified.

## Limits of the chosen mechanism

Required by the brief ("document the chosen alternative and its limits").

1. **Host-scoped, not repo-enforced.** The network lives on the developer's machine; a fresh
   machine or a deleted network reverts the default until the wrapper runs. Layer 3 makes that loud.
2. **`docker system prune` / `docker network prune` removes the network**, and the next bare
   `supabase start` recreates it wildcard-bound. CI cannot catch this (CI runs the wrapper path);
   Layer 3 is the control that does.
3. **Validated only on rootful Linux Docker Engine 29.4.3.**
   `com.docker.network.bridge.host_binding_ipv4` is a **bridge-driver** option; Docker Desktop
   forwards via a VM proxy and rootless Docker via rootlesskit's port driver — **neither is the
   bridge driver**, so the mechanism may not apply. The founder and CI runners are rootful Linux; a
   contributor on macOS may see a red assert, and the README says so.
4. **The transient shadow DB (54320) cannot be verified** by a point-in-time gate — it exists only
   during `db diff`/`db lint`/`db reset`. It is *protected* by Layers 1–2 (which is why the wrapper
   is a general passthrough), never *verified*.
5. **IPv4-named option.** Measurement shows it also suppresses `[::]` on 29.4.3, but that is engine
   behaviour, not a contract — which is why the IPv6 assertion stays in CI permanently.
6. **Does not harden other Docker containers.** Deferred with C/D.
7. **Not a substitute for keeping real data out of the local stack** — synthesized fixtures only
   (`cq-test-fixtures-synthesized-only`), verified true today (§User-Brand Impact).
8. **The wrapper is version-coupled to a CLI that is mid-rewrite; the gate is not.** The repo became
   a monorepo after 2.84.2 and a **new TypeScript CLI at `apps/cli/` now serves `start`/`stop`/
   `status`**. It reproduces the same publishing behaviour today (`formatPortBindingFlag` emits
   `${hostPort}:${containerPort}` with no host IP), so nothing is broken — but **whether the TS path
   honours `--network-id` is unverified, and that flag is Layer 1's entire foundation.** Verify it
   before ever bumping the pin (tracked in §Deferred). The gate reads Docker's own state and
   survives all of this unchanged.

## User-Brand Impact

*Rewritten per CPO condition C2, because the previous version rested severity on a mechanism that
measurement shows is unavailable.*

**If this lands broken, the user experiences:** `npm run db:start` fails, and the RLS/authz-fuzz
merge gate goes red on every PR touching `supabase/migrations/**` — blocking the founder's merges
on a hardening change meant to be invisible. **The worse failure is the quiet one:** a green `PASS`
printed over a still-exposed stack. Today the founder *knows* the stack is exposed and treats it as
an open item; a false green retires that vigilance and converts an acknowledged risk into an
unacknowledged one — strictly worse than the status quo. Every anti-vacuity rule in §Acceptance
Criteria exists for this failure mode.

**If this leaks, the user is exposed via:** five **unauthenticated network services** — Studio (a
full DB admin UI), Kong, Logflare, Inbucket, and Postgres — running for three weeks on the one
laptop that holds the founder's Doppler session, GitHub App credentials, production SSH access, and
every repo checkout, offered to every device on every café, hotel, and conference network the
machine joined. Any pre-auth defect in any of those five is a direct path onto the machine that
*is* the company.

**What the measurements say — and do not say** (CPO condition C3):

- The database held **420 `auth.users`, all `@example.test`/`e.test`/`ex.test`**, and the `public`
  schema had **zero rows**. **No real user data was exposed. No rotation, no breach notification,
  and no GDPR obligation is triggered by this finding.** This upgrades §Limits #7 and the GDPR skip
  from assertion to verified fact.
- The reachable `postgres` role is **not** a superuser (PG 17.6; `SET ROLE supabase_admin` →
  permission denied). The SQL→OS pivot the previous revision implied is **measurably unavailable**;
  severity rests on pre-auth *service* surface, not on the database.
- **`log_connections=off` and no logging collector**, so three weeks of connections to `:54322`
  left **no record**. We cannot prove it was not accessed. This changes no remediation — there was
  nothing worth taking — but the founder should hear it said rather than infer that "no evidence"
  means "no access".

**Brand-survival threshold:** `single-user incident` — **affirmed, and specifically not lowered.**
The measurements above hand a future reviewer an easy downgrade argument (fake data, no superuser).
That argument is wrong: the asset at risk is not the database, it is the laptop. One founder, one
machine, no second copy of the operation.

## Observability

```yaml
liveness_signal:
  what: "supabase-local.sh assert exit code — 0 iff every published port on every container
         carrying the com.supabase.cli.project label resolves to a loopback HostIp"
  cadence: "(a) every SessionStart via the existing hook — the always-on detector, independent of
            whether anyone runs the wrapper or the fuzz suite; (b) every wrapper start;
            (c) every rls-authz-fuzz CI run"
  alert_target: "SessionStart hook output for the founder; GitHub Actions job failure in CI.
                 No new alerting substrate."
  configured_in: ".claude/hooks/ (SessionStart) + .github/workflows/rls-authz-fuzz.yml"

error_reporting:
  destination: "stderr + non-zero exit, with THREE distinguishable conditions so a reader can tell
                a security regression from an environment problem:
                  EXPOSED       — a published port binds a non-loopback address (security finding)
                  NO_CONTAINERS — zero project containers found (inconclusive, NOT a pass)
                  DOCKER_ERROR  — docker unreachable/unparseable (inconclusive, NOT a pass)"
  fail_loud: true

failure_modes:
  - mode: "Vacuous PASS — zero containers or zero published ports satisfy a universally-quantified
           assertion trivially (the gate having the very false-green shape it exists to catch)"
    detection: "hard-fail on an empty enumeration; always print
                'enumerated N containers / M published ports' and 'probed K non-loopback addresses'"
    alert_route: "NO_CONTAINERS exit condition"
  - mode: "dockerd republishes the stack on boot/daemon-restart with no wrapper involvement
           (all containers are restart: unless-stopped — the DOMINANT publish path on this host)"
    detection: "Phase 0 probe P2 verifies bindings survive a daemon restart; Layer 3 catches drift
                at the next session"
    alert_route: "probe P2 failure blocks the design; thereafter the SessionStart detector"
  - mode: "Network exists with the WRONG host_binding_ipv4 value, or carries the CLI project label
           (so the next `supabase stop` prunes it), or has a non-bridge driver"
    detection: "wrapper ensure-condition tests value equality AND label absence AND driver —
                never key presence"
    alert_route: "wrapper recreates; aborts (never falls through) if rm/create fails"
  - mode: "A new or transient port appears (pooler 54329, inspector 8083)"
    detection: "port set derived dynamically from NetworkSettings.Ports — never a 5432[0-9] regex"
    alert_route: "EXPOSED naming the new port. Transient shadow DB 54320 is a stated limit."
  - mode: "A future Docker restores the IPv6 [::] wildcard despite host_binding_ipv4"
    detection: "assert checks for a '::' HostIp entry and probes every non-loopback address
                including link-local"
    alert_route: "EXPOSED naming the address"

logs:
  where: "GitHub Actions job log (CI); stderr (local). No new persistent sink — developer tooling."
  retention: "GitHub Actions default (90 days)"

discoverability_test:
  command: "bash apps/web-platform/scripts/supabase-local.sh assert --verbose"
  expected_output: "'enumerated N containers / M published ports', a per-port table showing
                    bind=127.0.0.1, 'probed K non-loopback addresses' with every one REFUSED, and
                    'PASS: M/M published ports are loopback-only'; exit 0."
```

No remote-shell step appears anywhere in the verification path (`hr-no-ssh-fallback-in-runbooks`).

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — mandated by the threshold).

### Product (CPO) — sign-off

**Status:** reviewed. **Verdict: SIGN OFF WITH CONDITIONS**, all six folded into this revision:
C1 → §Step 0 (stop the stack now, record the timestamp); C2 → §User-Brand Impact rewritten to lead
with the real vector and drop the unavailable SQL pivot; C3 → measured stack contents recorded;
C4 → Layer 2 pre-authorised for removal without further deliberation if probe P3 is anything but a
clean pass; C5 → deferral tracking fixed (§Deferred); C6 → README "stop the stack when not in use".

CPO explicitly ruled **do not re-order the phases** — RED-before-GREEN is what makes the gate
trustworthy — and instead **decouple the mitigation from the fix**, which is what §Step 0 does.

### Engineering (CTO / architecture)

**Status:** reviewed by a 7-agent panel; findings folded throughout. Principal reversals: the
point-of-use guard cut entirely; the layer labels corrected; the ADR moved to a standalone record;
alternative C reclassified from rejected-alternative to deferred-complement on corrected evidence;
and the discovery that upstream already rejected the in-CLI fix on policy, which makes this
workaround permanent and its minimal shape correct.

### Product/UX Gate

**Tier:** none. No user-facing surface; the mechanical UI-surface scan finds no
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in the Files lists. CPO
involvement here is threshold-driven sign-off, not UX review.

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

Phase 2.8 detection fires on `firewall` in the brief. This plan provisions **nothing the rule
governs**: no server, host, vendor account, DNS record, TLS cert, secret, packet-filter rule,
monitoring webhook, systemd unit, or cron job; no `.tf`, `cloud-init*.yml`, or `docker-compose*.yml`
is touched; no remote-shell step, no Doppler secret write, no vendor-dashboard step in any phase.

The only created object is a **Docker network on the developer's own workstation**, made by an
idempotent, repo-committed, unprivileged script — developer tooling, in the same class as
`apps/web-platform/scripts/run-migrations.sh`.

*Corrected after review:* the previous revision argued this scoping was "load-bearing to the
design". Choosing a weaker control partly to stay outside a process rule's scope is an inversion.
**The scoping is right on its own merits** — unprivileged, per-project, repo-owned, reversible —
and stands on those. Alternative C (daemon config) is deferred because it is root-level host
configuration deserving its own cycle, not because a rule forbids it.

**Terraform changes:** none. **Apply path:** N/A. **Distinctness:** `dev`/`prd` unaffected —
neither hosted project is touched. **Vendor tier:** N/A.

## Encryption Posture

**Skipped — detection does not fire.** No persistent store and no new cross-component connection;
no Files entry matches `\.tf$`, `supabase/migrations/.*\.sql$`, `cloud-init.*\.ya?ml$`, or
`docker-compose.*\.ya?ml$`. For the record the change is a strict **in-transit improvement**: it
removes plaintext Postgres and plaintext HTTP listeners from every non-loopback interface.

## GDPR / Compliance Gate

**Skipped, with reasoning recorded and now evidenced.** The canonical regex does not match (no
schema, migration, auth flow, API route, or `.sql`). None of the four expansion triggers fire.
**Verified rather than asserted:** the exposed database contained 420 synthetic `@*.test` users and
an empty `public` schema — no personal data was exposed, so no Art. 33/34 notification duty and no
Art. 30 register change arises. The unauditable-access caveat is recorded in §User-Brand Impact.

## Open Code-Review Overlap

- **#3364** — "review: add postgres-role ownership guard to run-migrations.sh (PR #3355 follow-up)".
  Matched on the `apps/web-platform/scripts/` prefix only. **Disposition: acknowledge** — different
  concern, different file (`run-migrations.sh`, untouched here), needs its own cycle.

No open code-review issue references `rls-authz-fuzz.yml`, `supabase/config.toml`,
`apps/web-platform/package.json`, ADR-111, or the rls-fuzz test dir.

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/scripts/supabase-local.sh` | **One script, two jobs.** Default: a **general passthrough** — `exec supabase --network-id "$NET" "$@"` with the flag **before** `"$@"` so `--` passthrough subcommands still work — covering `start`/`stop`/`status` *and* `db diff`/`db reset`/`db lint`/`migration`/`gen types`. Ensures the network first (value equality + label absence + bridge driver; abort on rm/create failure; pin the subnet on recreate to avoid a VPN/corporate-route collision). Subcommand `assert`: the verification gate. `#!/usr/bin/env bash`, `set -euo pipefail`, `--help`. Declares its `docker`/`jq` dependencies explicitly. |
| `apps/web-platform/scripts/supabase-local.test.sh` | Unit test using the repo's established **PATH-shimmed fake binary** convention (`postgrest-reload-schema.test.sh` shims `curl`; `run-migrations-schema-probe.test.sh` shims `psql`) — here a fake `docker`/`ss` returning different payloads keyed on `--format`. **Must pass with no Docker and no stack**, because `scripts/test-all.sh:560` globs `apps/web-platform/scripts/*.test.sh` and runs it on every full-suite run. |

## Files to Edit

| Path | Change |
|---|---|
| `.claude/hooks/` (SessionStart) | **Layer 3.** Run `supabase-local.sh assert` when a project stack is running; print a loud warning if EXPOSED. Silent when no stack is up. Never blocks the session. |
| `.github/workflows/rls-authz-fuzz.yml` | Start via the wrapper; add an `Assert loopback-only binding` step after `Start local Supabase stack` and before the bootstrap step. **Add both new script paths to the `paths:` filter** — today neither is covered, so a PR editing them runs nothing. |
| `apps/web-platform/package.json` | `db:start`, `db:stop`, `db:status`, `db:assert-loopback`, plus a `db:cli` passthrough. |
| `apps/web-platform/README.md` | New "Local Supabase stack (RLS-fuzz substrate)" section: what it is for; the wrapper as the only documented path **including `db diff`/`db reset`/`migration`**; **stop it when not in use** (C6); the rootful-Linux-only caveat; synthesized-fixtures-only; pointer to ADR-153. |
| `knowledge-base/engineering/architecture/decisions/ADR-153-*.md` | New terse ADR (see §Architecture Decision). |
| `knowledge-base/engineering/architecture/decisions/ADR-111-runtime-authz-rls-fuzz-harness.md` | One-line `Related: ADR-153` cross-reference only. |
| `apps/web-platform/supabase/config.toml` | Comment only, at the port declarations: bind address is not configurable here; see the wrapper + ADR-153. |

No SKILL.md `description:` edit and no `AGENTS.md` rule ⇒ neither budget gate applies.

## Implementation Phases

### Phase 0 — Probe the premises before building on them

Each probe has a **pre-declared** outcome so the decision is mechanical, not a judgement made under
sunk cost. **Scoped operations only — never an unscoped `docker network prune` on the founder's
machine** (it would delete unrelated projects' networks). **Phase 0 must exit with the stack stopped
or loopback-bound** (`trap`); if the session aborts mid-phase, the machine is left safe.

| # | Probe | Pre-declared outcome |
|---|---|---|
| **P1** | Does the option hold on the **real stack**? Recreate the network with it, start, read `NetworkSettings.Ports`. | Must show `127.0.0.1` and **no** `::`. Failure ⇒ **the mechanism is wrong**; halt, file an `action-required` issue naming CPO as decision owner, and re-enter planning. Do **not** silently fall back to a root-level design that `requires_cpo_signoff` has not covered. |
| **P2** | **Does the binding survive a daemon restart?** With the fix in place, `systemctl restart docker`, then re-read `NetworkSettings.Ports`. | Must remain loopback-only. **This is the dominant publish path** (`unless-stopped` + docker enabled at boot). Failure ⇒ the fix does not survive a reboot and the design changes. |
| **P3** | Does a **bare `supabase start`** reuse the pre-existing same-name network, and does it re-apply the CLI project label? | Reuses **and** leaves it unlabelled ⇒ Layer 2 works. Anything else ⇒ **drop Layer 2, no further deliberation** (CPO C4); Layers 1 and 3 unaffected. |

Also: confirm the CLI is `2.84.2` (matching the CI pin); confirm `package.json` has no `db:*`
collision. **Registration is already solved** — `scripts/test-all.sh:560` globs
`apps/web-platform/scripts/*.test.sh`, so the new suite needs zero wiring. *(The previous revision
cited a non-existent `scripts/run-registered-suites.sh` and issue #7076; the real infra runner is
`apps/web-platform/infra/run-registered-suites.sh`, which covers only `infra/` and is irrelevant.)*

### Phase 1 — RED: the gate, proven to fail

1.1 Write `supabase-local.sh assert`. Enumerate containers by label **key presence**
    (`--filter label=com.supabase.cli.project`) so a second project is genuinely covered; read
    **`NetworkSettings.Ports`**; treat `published` as a **non-null, non-empty** binding array
    (6 of 11 containers return `"8080/tcp": null`); derive the port set dynamically; probe with
    bash `/dev/tcp` (guaranteed present, unlike `nc`); include **link-local** IPv6; emit the three
    distinct exit conditions and the enumeration counts.
1.2 Write `supabase-local.test.sh` with fixtures for: wildcard IPv4, wildcard `::`, loopback-good,
    **null port entries**, **zero containers**, docker-unreachable, and a case proving the gate
    detects a wildcard state that `HostConfig.PortBindings` reports **identically** to the fixed
    state (the proxy trap).
1.3 Run the gate against the exposed stack in a short attended window. It MUST fail. Capture as RED
    evidence, then leave the machine safe.

### Phase 2 — GREEN: the wrapper

2.1 Write the ensure/passthrough logic per §Mechanism (value equality, label absence, bridge driver,
    abort-on-failure, pinned subnet, flag before `"$@"`).
2.2 Migrate the live stack via the wrapper. Re-run the gate — MUST pass.

### Phase 3 — Wire the safe path

3.1 SessionStart hook (Layer 3). 3.2 `package.json`. 3.3 CI workflow **+ `paths:` filter**.
3.4 README. 3.5 `config.toml` comment.

### Phase 4 — ADR-153 (+ ADR-111 `Related:` line)

### Phase 5 — Verification

5.1 All ACs, captured. 5.2 `bun run test:rls-fuzz` green (**not** bare `vitest` — it is not on
PATH; the package script is the verified invocation). 5.3 `cd apps/web-platform &&
./node_modules/.bin/tsc --noEmit` (**not** `npm run -w …` — the root declares no `workspaces`).
5.4 `bash scripts/test-all.sh` to confirm the new `*.test.sh` passes with no Docker present.

## Acceptance Criteria

### Pre-merge (PR)

**AC1 — the gate is proven to go red.** `supabase-local.test.sh` passes and includes failing cases
for wildcard IPv4, wildcard `::`, **zero containers**, **null port entries**, and the
`HostConfig.PortBindings` proxy trap. A gate never seen to fail is not a gate.

**AC2 — no wildcard binding remains, from the correct source, dual-stack.** For every container
carrying the `com.supabase.cli.project` label and every **non-null, non-empty** entry in
`NetworkSettings.Ports`: **no** entry has `HostIp` of `0.0.0.0` or `::`, and every entry is
`127.0.0.1`. *(Over the dynamically-derived port set — deliberately **not** a `5432[0-9]` regex,
which would miss 8083 and anything outside the decade. The previous revision's `docker ps` arm is
deleted: 6 of 11 containers publish nothing, so "every container shows `127.0.0.1:`" was
unsatisfiable even when fixed.)*

**AC3 — negative reachability, live probe, non-vacuous.** For every published port and **every**
non-loopback address on the host — the LAN IPv4, both global IPv6 addresses, **and the link-local
IPv6** — a TCP connect is REFUSED. Output must state `probed K non-loopback addresses`, so `K=0` is
visibly inconclusive rather than falsely green. The laptop run (K≥4) is the brief's required
evidence.

**AC4 — positive reachability and health preserved.** Every published port answers on `127.0.0.1`;
`supabase status` healthy; `psql "postgres://postgres:postgres@127.0.0.1:54322/postgres" -c
'select 1'` returns a row.

**AC5 — the binding survives a daemon restart** (probe P2 promoted, because `unless-stopped` makes
dockerd the dominant publisher): after `systemctl restart docker`, AC2 still holds **without**
running the wrapper.

**AC6 — the ensure-condition is not presence-only.** Starting from each of (a) `Options: {}`,
(b) `host_binding_ipv4=0.0.0.0`, (c) a network carrying `com.supabase.cli.project`, the wrapper
recreates and reaches AC2; and a forced `docker network rm` failure makes it **abort**, never
proceed to `supabase start`.

**AC7 — Layer 3 fires without anyone opting in.** With a wildcard-bound stack running, a new
session prints a loud EXPOSED warning naming the remediation command verbatim
(`bash apps/web-platform/scripts/supabase-local.sh start`). With a loopback-bound stack, silent.
With no stack, silent.

**AC8 — functional regression suite green.** `bun run test:rls-fuzz` passes against the
loopback-bound stack, and `bash scripts/test-all.sh` passes with the stack stopped.

**AC9 — CI wiring is real and self-guarding.** `rls-authz-fuzz.yml` contains no bare
`run: supabase start`; the assert step sits after `Start local Supabase stack` and before
`Bootstrap migration-tracking table (content_sha shim)`; and the `paths:` filter includes both new
scripts. Verified by parsing the YAML and comparing step indices — **not** an awk range:

```bash
python3 -c "import yaml;s=[x.get('name') for x in yaml.safe_load(open('.github/workflows/rls-authz-fuzz.yml'))['jobs']['rls-fuzz']['steps']];i=s.index;assert i('Start local Supabase stack')<i('Assert loopback-only binding')<i('Bootstrap migration-tracking table (content_sha shim)')"
```

**AC10 — the CLI limitation is stated with citations** *(operator-requested by the brief)*. The PR
body states that CLI 2.84.2 **and the latest 2.110.0+** offer no `config.toml` bind-address control,
citing the official config reference, `supabase start --help`, the CLI source, the releases-API
sweep, **and PR #4613's rejection with the maintainer's docker-network prescription** — and
documents the chosen alternative and its limits (§Limits). It also records
`git ls-files | grep -c 'supabase/config\.toml'` → `1` as evidence for the brief's "fix
consistently" requirement, and the §Step 0 exposure-close timestamp.

### Post-merge (operator)

**None.** Every step is automated in-session or by CI.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | Gate vs wildcard IPv4 / wildcard `::` | non-zero, `EXPOSED`, port + address named |
| T2 | Gate vs loopback-bound stack | exit 0, `PASS: M/M` with enumeration counts |
| T3 | Gate with **zero containers** | non-zero, `NO_CONTAINERS` — never a pass |
| T4 | Gate with **null** port entries on 6 containers | those containers skipped as unpublished; no throw, no red |
| T5 | Gate with docker unreachable | non-zero, `DOCKER_ERROR`, distinguishable from `EXPOSED` |
| T6 | Gate where loopback does NOT answer | non-zero — the gate is not one-sided |
| T7 | Gate vs a state `HostConfig.PortBindings` reports identically to the fixed state | non-zero — proves the correct data source |
| T8 | Wrapper: no network / `Options:{}` / wrong value / labelled / non-bridge driver | recreates in all five, reaches AC2 |
| T9 | Wrapper: `docker network rm` fails | aborts before `supabase start` |
| T10 | Wrapper passthrough: `db diff`, `db reset`, `migration new`, `gen types --local` | all land on the loopback network |
| T11 | `systemctl restart docker` with the fix in place | bindings still loopback-only (AC5) |
| T12 | Bare `supabase start` after the network exists | loopback preserved — **iff probe P3 passed**; otherwise Layer 2 is absent by design and this is dropped |
| T13 | SessionStart hook: exposed / clean / no stack | warns / silent / silent |
| T14 | `scripts/test-all.sh` on a machine with no Docker | new suite passes (fixtures only) |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **A green gate over a still-exposed stack** — the worst outcome, since it retires the founder's existing vigilance | Every anti-vacuity rule: fail-closed on zero containers/ports, printed enumeration counts, dynamic port set, correct data source, three distinct exit conditions, and unit tests proving each red path (AC1). |
| The binding does not survive a daemon restart, so the reboot path silently republishes wildcard | Probe P2 in Phase 0, promoted to AC5. Failure changes the design before any code depends on it. |
| A correctly-optioned but **labelled** network passes a naive check, then `supabase stop` prunes it | Ensure-condition tests label **absence** as well as option **value** (AC6). The CLI creates it labelled, so this is the default state, not an edge case. |
| CI's Docker engine still creates the `[::]` entry, turning a merge gate permanently red | The PR self-tests (the `paths:` filter includes the workflow). Pre-declared branch: if CI's engine differs, scope AC2's `::` clause to engines where the bridge driver owns publishing and record the divergence in §Limits #3 — do not weaken the laptop assertion. |
| Docker Desktop / colima / rootless contributors get an unexplained red | Stated in §Limits #3 and the README; the mechanism is a bridge-driver option and those engines publish via a different driver. |
| Recreating the network collides with a VPN/corporate route (172.17–172.31) | Pin the subnet on recreate; verify reachability after. |
| **The CLI is mid-rewrite (TS CLI at `apps/cli/`) and `--network-id` support there is unverified** — Layer 1's foundation | §Limits #8; tracked as a deferral to verify **before** any pin bump. The gate is engine-level and survives regardless, which is why it is the durable asset. |
| Layer 2 costs more than it protects | It is now free (a no-op flag against the CLI's own name) and pre-authorised for removal on any P3 result other than a clean pass (CPO C4). No probe apparatus, no fallback branch. |
| Transient shadow DB (54320) is unverifiable | §Limits #4; the wrapper's general passthrough keeps `db diff`/`db lint` on the safe network, which is what protects it. |
| Doc drift: bare `supabase start` remains in historical learnings and specs | Deliberately not rewritten — learnings are point-in-time records. The README and ADR-153 are the current-truth surfaces. |

## Deferred

Per `wg-when-deferring-a-capability-create-a`, each gets a tracking issue in this cycle.

1. **Host-wide Docker publish hardening — daemon `{"ip":"127.0.0.1"}` (alt. C) plus optional
   `DOCKER-USER` rules (alt. D).** Every other container the founder runs still defaults to
   `0.0.0.0` on a roaming, credential-bearing laptop. **`priority/p2-medium`** *(raised from p3 —
   p3 contradicted the declared threshold, and the original rejection rationale was empirically
   false: no competing published containers, no existing `daemon.json`, and explicit `-p 0.0.0.0:`
   still overrides so breakage is loud and one-flag-fixable)*. **Proactive trigger:** re-evaluate at
   the next planned untrusted-network trip, or by **2026-09-30**, whichever is sooner — not "when
   another exposure is found", which waits for a second incident to justify preventing it.
   Milestone: `Post-MVP / Later`. Labels: `type/security`, `domain/engineering`,
   `priority/p2-medium`.
2. **Verify the TypeScript CLI honours `--network-id` before any pin bump.** Layer 1 depends
   entirely on that flag, and `apps/cli/` now serves `start`/`stop`/`status`. **Trigger:** any PR
   that moves the `supabase/setup-cli` pin off 2.84.2 — a mechanical, greppable trigger.
   Milestone: `Post-MVP / Later`. Labels: `type/chore`, `domain/engineering`, `priority/p2-medium`.
3. **Reduce the started service set (`-x studio,inbucket,logflare,vector`).** **Owner:** whoever
   next touches ADR-111's substrate contract. **Trigger:** the next ADR-111 substrate change, or
   **2026-09-30**. Milestone: `Post-MVP / Later`. Labels: `type/chore`, `domain/engineering`,
   `priority/p3-low`.

All labels and the milestone verified to exist (`gh label list`, `gh api …/milestones`).

## Sharp Edges

- **An empty enumeration satisfies a universally-quantified assertion.** "For every published
  port…" is trivially true over zero ports. The gate built to catch a false green had exactly the
  false-green shape it was meant to detect. Always print the counts.
- **Do not read `HostConfig.PortBindings`.** It reports the *requested* binding — `HostIp: ""` both
  before and after this fix, because the fix operates via the network default, not a per-container
  request. A gate built on it can never go red and never go green. Use `NetworkSettings.Ports`.
- **`ss` and `NetworkSettings.Ports` are not independent evidence** — both derive from Docker's
  publishing path. Only the live TCP connect is independent. Do not present them as corroboration.
- **The CLI creates the network already labelled.** So "does the option exist" is the wrong
  ensure-condition; it must also require the `com.supabase.cli.project` label to be **absent**, or
  the next `supabase stop` prunes the network and the next start silently reverts to wildcard.
- **`restart: unless-stopped` means dockerd, not the wrapper, is the dominant publisher.** These
  ports come back on every boot and daemon restart with nobody typing anything.
- **`ip -o addr show scope global` excludes link-local IPv6.** `fe80::…%iface` is reachable by
  exactly the modelled on-link attacker, so a `scope global` probe understates the exposure.
- **`SUPABASE_SERVICES_HOSTNAME` is not a bind knob.** Added after 2.84.2, it is dial-side only
  (which host the CLI connects to for health checks). It reads like the answer and is not.
- **Never run an unscoped `docker network prune` on the founder's machine** to test a hypothesis —
  it deletes unrelated projects' networks. Scope every removal by name.
- **A guard that blocks with an opaque message is a dead end.** Every failure path must name the
  exact remediation command.
- **`vitest` is not on PATH** — use `bun run test:rls-fuzz`. **Typecheck** is `cd apps/web-platform
  && ./node_modules/.bin/tsc --noEmit`; `npm run -w …` aborts (`No workspaces found`).
- **`scripts/test-all.sh:560` globs `apps/web-platform/scripts/*.test.sh`**, so the new suite is
  registered automatically — and therefore must pass with **no Docker and no stack**.
- **Put the `--network-id` flag before `"$@"`**, or it breaks any subcommand using `--` passthrough.
