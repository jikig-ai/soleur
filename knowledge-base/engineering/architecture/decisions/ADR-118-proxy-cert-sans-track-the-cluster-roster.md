---
title: A shared cert's SANs are the cluster roster — re-mint on membership change, never pin
status: accepted
date: 2026-07-17
amends: ADR-068
supersedes: none
issue: 6538
---

# ADR-118: Proxy cert SANs track the cluster roster

## Context

`apps/web-platform/infra/proxy-tls.tf` mints the host↔host session-router proxy's TLS
material. Both SAN inputs derive from the web-host cluster roster, and both are
`RequiresReplace`:

```hcl
ip_addresses = [for h in values(var.web_hosts) : h.private_ip]
dns_names    = concat(keys(var.web_hosts), ["localhost"])
```

PR B (#6538) removes the `"web-2"` key from `var.web_hosts` to retire an fsn1 orphan.
That replaces the cert and rotates `PROXY_TLS_CERT` in Doppler `prd` — the value the
proxying client pins as `ca:` with `rejectUnauthorized: true`.

**The file contains no `web-2` literal.** PR B's reference sweep, AC-B4, and the
push-apply-scope measurement are all token-based, so all three are structurally blind to
it. The coupling is by *derivation*, not by mention. It fires at neither merge nor the
targeted apply — it is latent, surfacing only on the next untargeted plan.

### What was verified, and what turned out to be false

The plan's §Open Decision framed this as a live-origin blast-radius problem. It is not.

**The proxy path is dark — three independent locks, any one sufficient:**

| Lock | Evidence |
|---|---|
| Feature flag | `ws-handler.ts` gates the only call site on `isGitDataStoreEnabled()`; `workspace-resolver.ts` = `process.env.GIT_DATA_STORE_ENABLED === "true"`, unset in prod |
| Host roster | `session-router.ts` — `SOLEUR_HOST_ROSTER` unset → empty roster → routes resolve `owner-unresolved`, **never** `proxy` |
| Listener bind | `index.ts` — `SOLEUR_PROXY_BIND` unset → `createProxyServer` fail-closes → returns `null`, no listener |

No Terraform provisions any of those three vars. No load balancer resource exists in any
root. `dns.tf` pins `app.soleur.ai` to `hcloud_server.web["web-1"]` as a singleton; the
for_each round-robin is deferred prose, not code. `session-proxy.ts` states it directly:
*"INERT until 3.D: at a single host every route resolves `local`, so proxyClientToOwner is
never called and the owner's proxy listener has no peers."*

**Three corrections to the plan's own text, recorded so they are not re-derived:**

1. **The "TLS handshake failure across the proxy path" risk is vacuous.** The TLS server
   cert and the pinned client CA are the *same PEM read from the same env var on the same
   host*. A stale-but-consistent host verifies against itself. Vintage skew requires two
   hosts with different container-start times — exactly what the destroy removes. The risk
   as stated cannot occur, and §User-Brand Impact repeats it.
2. **Only `PROXY_TLS_CERT` rotates — not `PROXY_TLS_KEY`.** `doppler_secret.proxy_tls_key`
   reads `tls_private_key.proxy_server.private_key_pem`, and that resource has zero
   dependency on `var.web_hosts`, so it is never replaced. Same key, new cert. This is not
   a key-hygiene event in either direction.
3. **The drift alarm is real.** `cron-terraform-drift.ts` fires `{ cron: "0 6,18 * * *" }`
   and `scheduled-terraform-drift.yml` runs `terraform plan -detailed-exitcode` with no
   `-target`. On exit 2 it files one issue, then comments "Drift still present" every 12h
   forever, plus two emails/day to ops. No allow-list can silence a known-benign diff.

**Empirically measured** against the pinned `hashicorp/tls 4.3.0`, reproducing the real
state SANs (`ip_addresses ["10.0.1.10","10.0.1.11"]`, `dns_names ["web-1","web-2","localhost"]`):

| Config | `terraform plan` |
|---|---|
| SANs hardcoded to current values, web-2 dropped | `No changes.` — a true no-op |
| SANs derived (status quo), web-2 dropped | `must be replaced` → `1 to add, 0 to change, 1 to destroy` |
| SANs hardcoded but **reordered** | `must be replaced` — the attributes are order-sensitive `ListAttribute`s |

So both options work mechanically. The decision is not about risk; it is about which
invariant survives.

## Decision

**Bring the cert and `doppler_secret.proxy_tls_cert` into PR B's scope. Rotate
deliberately, now, inside the supervised operator-local apply.**

`proxy-tls.tf` is **unchanged** — a zero-line diff. The for-expressions already compute the
right answer; this decision just lets them.

### Why

**The repo already ruled on this, and a test enforces it.**
`plugins/soleur/test/terraform-target-parity.test.ts` carries the written rationale for
exempting these addresses from CI targeting:

> the host↔host proxy TLS keypair/cert + their prd doppler_secrets belong to
> the web-host cluster (SANs = web host private IPs) and ride the same
> cluster apply

That is not a comment — it is the justification for an exemption the test enforces. It
asserts the cert's lifecycle **is** the cluster's lifecycle. PR B's operator-local apply
*is* that cluster apply, and the first one since the cert was minted. Option 1 is not scope
creep; it is the first discharge of a promise the repo already made.

Pinning the SANs would **falsify that rationale in place**: `SANs = web host private IPs`
becomes false, `belong to the web-host cluster` becomes false, and the exemption survives
with a lying justification that nothing updates.

**The shared-cert deviation is the whole reason this decision exists — and it cuts toward
re-minting.** ADR-068 specified *"a long-lived self-signed server cert per host"*.
`proxy-tls.tf` deliberately deviates to a **single shared** cert whose SANs cover every
host, because web-1's frozen cloud-init (`ignore_changes = [user_data]`) cannot deliver
per-host Doppler selection. Under the per-host design, retiring web-2 would simply drop
web-2's cert — no churn, no decision. The shared design *deliberately couples cert identity
to cluster membership*. Pinning freezes a shared cert so it stops tracking the cluster it is
shared by, severing the one invariant the deviation was built around.

**Cost is monotonically increasing in time.** Today the rotation is provably free: the path
is dark, there is one host, the cert is unconsumed. After the 3.D cutover it is not (two
hosts, live proxy, coordinated restarts). Accepting the drift *guarantees* the rotation
happens anyway — someone eventually clears the 12h alarm with a full apply — but at an
unknown later date, possibly past 3.D, at strictly higher cost. Rotate at the global
minimum. That minimum is now.

**This does not violate ADR-068's "no rotation cron."** That clause rejects *time-based,
scheduled* rotation of a multi-year cert. It says nothing about re-minting when the SAN set
legitimately changes — and `RequiresReplace` on `ip_addresses`/`dns_names` makes that
re-mint the explicit design. Event-driven re-mint on cluster-membership change is the design
working, not a deviation from it.

### What this decision explicitly does NOT rest on

**The dangling SAN is cosmetic, not a vulnerability.** Stated plainly so no reader mistakes
this for a security fix. A SAN is a *name assertion*, not a credential. Presenting the cert
requires `PROXY_TLS_KEY`, which lives in Doppler `prd` and reaches only our hosts. An
attacker on `10.0.1.11` without the key cannot use a stale SAN for anything; an attacker
*with* the key owns the trust domain regardless of SANs. The confused-deputy path is gated
by `SOLEUR_HOST_ROSTER`, which won't list a destroyed host. Net security delta between
rotating and not rotating is approximately zero. **The deciding axis is
correctness-at-cutover, not security.**

## Rejected alternatives

**Option 2 — accept and document the drift. Rejected: dominated on every axis.** It pays a
permanent 12h alarm plus two emails/day *and* still ends in the same rotation, later and
unbounded. Alarm fatigue on the detector that guards prod is itself the harm: it trains the
operator to ignore exit-2.

**Option 3 — pin the SANs to a static list. Rejected: it converts a loud alarm into a silent
break.** Its steelman is real — it is a proven no-op, it leaves the 5-address gate and the
measured shape untouched, and it avoids touching prod TLS material during a prod-destroy PR.
It fails anyway:

- **It moves the failure to the worst possible moment.** At the 3.D cutover a new `web-3` in
  `var.web_hosts` gets **no SAN**. The pinned cert doesn't change. The client pins the CA,
  dials web-3's private IP, and TLS verification fails at SAN-mismatch — on the live path, at
  the exact moment the feature goes live.
- **It blinds the only sensor that would catch that.** A static pin doesn't drift when a host
  is added: state == config, so the drift detector stays green. Option 1's derivation would
  have added the SAN automatically.
- **The gate objection is a category error.** `web2_retire_allow` membership is exact-equality
  via `IN(.address; web2_retire_allow[])` — the same mechanism the existing `web2_allow`
  recreate set uses, whose header warns against substring matching for precisely this reason.
  Adding two cert addresses cannot admit
  `hcloud_volume.workspaces["web-1"]`; they are exact strings in a disjoint resource-type
  space. The allow-list is a set of exact addresses, not a risk budget.
- **It has the larger source diff.** Option 1 changes zero lines of `proxy-tls.tf`; Option 3
  requires hardcoding `10.0.1.10`/`10.0.1.11` into prod TLS material inside a destroy PR.
- **The pin is reorder-fragile.** `ip_addresses` is a `RequiresReplace` ListAttribute
  (measured above). `values(var.web_hosts)` is map-key-ordered and stable by construction; a
  hand-maintained list forces a spurious replacement on a cosmetic edit.
- **3.D is not speculative.** It is *why this PR exists*: a host born in fsn1 can never join
  `web_spread`, so web-2 must be destroyed and re-born to reach active-active. Option 3 plants
  a silent failure directly in the path of the work that motivates the PR.

## Consequences

### PR B must

- **`-target` list 5 → 6** — add `-target=doppler_secret.proxy_tls_cert`. One target
  suffices: `-target` is transitive **on dependencies**, so it pulls in
  `tls_self_signed_cert.proxy_server` → `tls_private_key.proxy_server`. Do **not** add
  `-target=doppler_secret.proxy_tls_key`; it is not in the plan, and adding it invites the
  false belief that the key rotates.
- **`web2_retire_allow` 5 → 7** — the `-target` list and the allow-list are different lists;
  the allow-list must name everything that *appears* in the plan:
  `tls_self_signed_cert.proxy_server` (replace: delete+create) and
  `doppler_secret.proxy_tls_cert` (update-in-place).
- **Two new counters**, mirroring the existing `firewall_attachment_ok` pattern:
  `cert_replaced` (`<= 1`, delete+create only — the plan's idempotent-retry shape) and
  `doppler_cert_ok` (exactly one `update`, **never `delete`** — a delete strips
  `PROXY_TLS_CERT` from Doppler `prd`; harmless while dark, but it must fail closed).
- **Assert a deliberate omission:** `tls_private_key.proxy_server` must **NOT** be in
  `web2_retire_allow`. It should never plan a change; if it ever does, that is a key rotation
  and `web2_out_of_scope_changes` must halt. Add a synthesized fixture (key change present →
  FAIL), per `cq-test-fixtures-synthesized-only`.
- **Re-measure, do not encode.** The push-apply-scope measurement
  (`0 to add, 1 to change, 1 to destroy`) is **unchanged** — the cert is unreachable from that
  scope, since `-target` is transitive on dependencies, not dependents, and nothing in the
  push-apply list depends on the cert. The **B3 local-apply shape does change**, and a cert
  replace is `1 to add, 0 to change, 1 to destroy`, so the destroy count increments. AC-B1
  already mandates empirical re-measurement at B0; that mandate governs. Encoding a predicted
  number here would repeat the v1 P0 miss that the 5th address already cost once.
- **Add a derivation sweep to B0.** `proxy-tls.tf` has zero `web-2` literals, so the token
  grep cannot see it. Add `git grep -n 'var\.web_hosts' apps/web-platform/infra` as a second
  sweep and diff AC-B4 against that hit-set too.

`host_creates` is **not** tripped: the tripwire is type-scoped to `hcloud_server`/
`hcloud_volume`, so the cert's create does not fire the mirrored wedge.

### The transferable lesson

**A token grep is structurally blind to derived coupling.** The sweep enumerated *mentions*
and missed *dependents*. This is `hr-write-boundary-sentinel-sweep-all-write-sites` in its
read-side form: when a variable is a fleet-wide coupling, the reference sweep must enumerate
what *derives from* it, not what *names* it.

### Relationship to #6574

The same defect class, mirrored:

- **#6574:** `hcloud_firewall_attachment.web` is **in** the push-apply graph while the header
  claims it is excluded. *In the graph, claimed out.*
- **proxy-tls:** the cert is **out** of every apply path while the parity test's rationale
  claims it *"ride[s] the same cluster apply"* — but there is no cluster-apply job. The
  "cluster apply" is an operator ritual, not automation. *Out of the graph, claimed in.*

Both reduce to: **`var.web_hosts` is a fleet-wide coupling that the `-target` boundary does
not model.** #6574's own framing — *"real as a target, and a fiction as a boundary"* —
applies verbatim. No blocking dependency (#6574's candidate fix doesn't touch the cert, and
it is out of scope for PR B). This decision makes the parity test's claim true for the first
time; a sibling issue tracks the fact that its exclusion rationale names an apply path that
exists only as a human habit.

### 3.D

Option 1 is the precondition that makes 3.D safe by default. With the derivation intact, the
cutover PR adds its host to `var.web_hosts` and the SANs follow automatically — the cert
replacement appears in that PR's own plan, under its own review, with the proxy still gated
by `isGitDataStoreEnabled()`. Under a pin, 3.D's author must *remember* to hand-edit a
hardcoded IP list in a file whose name doesn't mention hosts, with no gate, no drift signal,
and no test to catch the omission.
