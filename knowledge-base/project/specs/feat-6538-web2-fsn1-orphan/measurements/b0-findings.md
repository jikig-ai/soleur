# B0 findings — PR B (retire soleur-web-2)

Measured 2026-07-17 against `main @ 7b46f6291`. Every number below was re-run, not recalled.
Three findings **falsify plan/ADR-118 premises** and are marked ⛔ — B1 must not be written
against the contract as specified.

---

## B0.1 — plan shapes (AC-B1)

Scope reconstructed verbatim from `apply-web-platform-infra.yml:297-391` → **95 `-target` flags**
(`b0-1-pushapply-scope-95-targets.txt`).

| Measurement | Result | vs plan |
|---|---|---|
| Baseline, push-apply scope, web-2 present | `No changes. Your infrastructure matches the configuration.` | clean — no pre-existing drift *in this scope* |
| web-2 removed, push-apply scope | **`Plan: 0 to add, 1 to change, 1 to destroy`** | ✅ **matches** the predicted shape |
| web-2 removed, B3 local-apply scope (6 targets) | **`Plan: 3 to add, 1 to change, 4 to destroy`** | ⛔ **does not match** — see below |

**Push-apply shape holds.** The single destroy is `hcloud_server.web["web-2"]` (server only —
the volume is *not* in scope), the single change is `hcloud_firewall_attachment.web`. This is
exactly the partial-destroy hazard B2 exists to mitigate: server dies, volume strands and bills.

### ⛔ FINDING 1 — the proxy-TLS resources are **absent from state**; ADR-118 measured a fiction

`terraform state list | grep -iE 'proxy|tls'` returns **only `tls_private_key.ci_ssh`**.
`PROXY_TLS_*` is **absent from Doppler `prd`**.

The 6-target plan therefore reads:

```
# doppler_secret.proxy_tls_cert   will be created      <- NOT "updated in-place"
# tls_private_key.proxy_server    will be created      <- the key ADR-118 says never changes
# tls_self_signed_cert.proxy_server will be created    <- NOT a delete+create replace
```

`proxy-tls.tf` is *"contract before consumer"* config (header: "this material ships in 3.A so the
proxy server/client in 3.B can load it") that **was never applied**. Consequences:

- ADR-118's "cert **replace** = delete+create" is impossible — there is nothing to delete.
- `doppler_cert_ok` ("exactly one `update`, **never** `delete`") ⇒ the real plan emits a
  **create** ⇒ **the gate halts on the true plan**.
- "`tls_private_key.proxy_server` must never plan a change; if it does that's a key rotation →
  halt" ⇒ the real plan **creates** it ⇒ **the gate halts**. The zero-`var.web_hosts`-dependency
  claim is *true* (block is 4 lines, no interpolation) but does not imply "no diff" when the
  resource is absent from state.
- B6.2's `-target=doppler_secret.proxy_tls_cert` would **birth** the private key + cert + one
  Doppler secret into `prd` on the supervised apply — scope far beyond "retire web-2".
  Worse: `doppler_secret.proxy_tls_key` is deliberately **not** targeted, so the apply would
  write `PROXY_TLS_CERT` to `prd` **with no matching `PROXY_TLS_KEY`** — a broken half-state.

The B-GATE adjudicated Option 1 vs Option 3 for a resource that does not exist. Removing web-2
has **zero** effect on live TLS material. ADR-118's "empirically measured against the real state
SANs" cannot be true — there are no state SANs.

**The drift rationale is also already spent:** ADR-118 argues the un-rotated cert leaves latent
drift for `scheduled-terraform-drift.yml`. That drift **already exists and is already filed** —
**#6580 "infra: drift detected in web-platform"** is OPEN, and **#6443** records that this
detector "always alarms" (drowned, not blind). The destroy neither creates nor worsens it.

---

## B0.2 — token sweep (AC-B4 baseline)

`b0-2-token-sweep.txt` — **383 hits / 57 files**.

⛔ **FINDING 2 — the plan's recorded baseline never existed.** tasks.md B0.2 records
*"311 hits / 45 files"* (measured 2026-07-16). That figure matches **no commit on main**:

| ref | hits / files |
|---|---|
| 2026-07-16 EOD `33a56a253` | 383 / 57 |
| 2026-07-15 `a9016a997` | 322 / 48 |
| 2026-07-14 `339535852` | 312 / 43 |
| 2026-07-13 `44969b4df` | 309 / 43 |

45 files is not a value this sweep ever returned. AC-B4 diffing against 311/45 would have
diffed against a fabricated baseline. **Use 383/57 @ `7b46f6291`.**

---

## B0.2b — derivation sweep

`git grep -ln 'var\.web_hosts' apps/web-platform/infra` → **exactly 9 files**, matching the
recorded set. Audit of all nine:

- **Class A (ForceNew-on-membership-change): exactly one** — `proxy-tls.tf`
  (`ip_addresses`/`dns_names` are order-sensitive RequiresReplace lists). **Moot per Finding 1.**
  `tls_private_key.proxy_server` confirmed zero-dependency (verbatim: `algorithm = "ECDSA"`,
  `ecdsa_curve = "P256"`, nothing else).
- `server.tf` — no class A. The `placement_group_id` ternary reads `var.web_hosts["web-1"]`
  (retained) and is inside `ignore_changes`. Destroys `hcloud_volume.workspaces["web-2"]`
  **with its data** — intended.
- `web-hosts-eu-pin.tftest.hcl` — **leave its `web-2` literal alone**; it is a synthesized
  mixed-EU negative fixture, not a roster reference.
- `dns.tf`, `network.tf`, `placement-group.tf`, `variables.tf` — prose/comments only.

### ⛔ FINDING 3 — B3.4's landmine is under-scoped

The plan names **three** workflow literals + one `-lt 2` floor. Measured, the roster literal
`10.0.1.10,10.0.1.11` has **four** workflow copies plus an unguarded infra copy, and a
**second CI-registered test** fails:

| site | plan says | reality |
|---|---|---|
| `apply-web-platform-infra.yml:710`, `:974` | ✅ named | confirmed |
| `web-platform-release.yml:563` | ✅ named | confirmed — live tagged-release deploy fan-out |
| `cutover-inngest.yml:106` (`CUTOVER_HOSTS`) | ❌ **not named** | asserted against `variables.tf` by `cutover-inngest-workflow.test.sh:188-199` |
| `apps/web-platform/infra/inngest-host.tf:40` | ❌ **not named** | `web_host_private_ips` → rendered into the Inngest host's nftables `ip saddr` allowlist. **No test guards it.** Leaving `.11` is a standing grant to a recycled Hetzner private IP |
| `web-hosts-fanout-parity.test.sh` `-lt 2` | ✅ named | confirmed (CI: `infra-validation.yml:445`) |
| `cutover-inngest-workflow.test.sh` | ❌ **not named** | **CI-registered at `infra-validation.yml:523`** — also red-CIs on B3 |
| `scripts/deploy-status-fanout-verify.sh:86` | ❌ **not named** | hard `if [[ "$ROSTER_COUNT" -ne 2 ]]; then … exit 1`. This script exists *solely* to verify web-2; patching `-ne 2`→`-ne 1` leaves a verify that proves nothing. It should retire with web-2, together with its two consumer jobs |

---

## B0.3 — no apply in flight ✅

`gh run list --workflow=apply-web-platform-infra.yml` — zero non-`completed` runs. Last:
`2026-07-17T11:37:56Z completed/success`. Re-confirm immediately before any apply
(`use_lockfile = false` — no state lock).

## B0.4 — `web-1-swap` concurrency group ✅

Not joined. Moot under local-apply (no job exists).

---

## ⛔ FINDING 4 — open question 3: **web-2 IS a live Cloudflare Tunnel connector**

Pulled from Cloudflare's control plane (the vantage-independent instrument per
`scripts/tunnel-connector-census.sh` / #6425). Tunnel `soleur-web-platform` = `6410c1ec…`:

```
live connectors: 2                              <- the #6425 invariant (entries with >=1 live conn)
connector a281fb1b: origin_ip 135.181.45.178    = soleur-web-platform (web-1)
connector 8c57fcd5: origin_ip 178.105.153.255   = soleur-web-2         <- LIVE, 4 QUIC conns
                    2a01:4f8:c015:c251::1       = soleur-web-2 (v6)
```

web-1's connector holds conns in `ams15`, `ams07`, `hel01`×2. Both connectors are live and
Cloudflare selects **per edge colo** (colo-sticky). **web-2 is currently eligible to serve
production `app.soleur.ai` traffic.**

This contradicts config: `server.tf:195` reads `web_tunnel_connector = each.key == "web-1"`.
The likely mechanism is `ignore_changes = [user_data]` (server.tf:255) — web-2 still runs the
cloud-init it was born with (`run_at 2026-07-07`), so the config change never reached the host.
This is precisely the ADR-114/#6425 two-connector ambiguity that caused 16h of false
`inngest_down` P1s on 2026-07-15.

**Implications:**

1. The framing "idle fsn1 **orphan**" is false. web-2 is a live origin for some edge colos.
   The destroy removes a **serving** connector, not a dormant host.
2. It falsifies the stated basis for leaving `terms-and-conditions.md` untouched
   (tasks.md A6.4: *"web-2 never served the Web Platform"*). The T&C **conclusion** may still be
   right, but **not for that reason** — re-derive it, do not inherit it.
3. B6.8's verification (`app.soleur.ai` probe → 200) **cannot detect** the failure mode it
   matters for: a single probe from one vantage hits one colo. Per the census script's own
   warning, "10/10 identical reads from one vantage prove nothing at all." B6.8 needs the
   **connector census** (expect 2 → 1), not a response probe.
4. Destroying a live connector mid-flight drops in-flight requests on colos currently pinned to
   it until Cloudflare reconverges. Whether that needs a drain step is an **operator decision**,
   not an inference — it is not addressed anywhere in the plan.

---

## Verdict

B0.1 (push-apply shape), B0.2b (9 files), B0.3 and B0.4 hold. **B0.2's baseline, ADR-118's
proxy-TLS premise, B3.4's scope, and the "orphan" framing do not.** B1 as specified would build
a gate that halts on the true plan; B6.2's `-target` list would write a keyless `PROXY_TLS_CERT`
into `prd`. Both need a decision before B1 starts.
