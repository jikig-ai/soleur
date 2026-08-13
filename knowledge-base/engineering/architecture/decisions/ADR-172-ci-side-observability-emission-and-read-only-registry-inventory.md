# ADR-172 — CI may emit to the observability warehouse, and may measure the registry's read surface

- **Status:** adopting
- **Date:** 2026-08-06
- **Issue:** #7278
- **Extends:**
  [ADR-166 — a CI message may only name a cause the job measured](ADR-166-a-ci-message-may-only-name-a-cause-the-job-measured.md)
  (the readback rule below is ADR-166 applied to the job's *own* telemetry: an emitter's exit
  code is not a measurement of the warehouse),
  [ADR-096 — migrate the container registry from GHCR to self-hosted zot](ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md)
  (amended below with the consequence this measurement exposes)
- **Related:**
  [ADR-169 — what authorizes destroying the sole pull path](ADR-169-what-authorizes-destroying-the-sole-pull-path.md)
  (its *"no predicate that observes production zot"* clause is addressed, not ignored — see
  *Why ADR-169's no-predicate clause does not reach this*), #7247, #7287, #6929, #7309, #7277
- **Supersedes:** nothing. The ADR ordinal `169` claimed PROVISIONALLY by the superseded
  2026-08-04 restart-lever plan is **dead** — 169 is taken.
- **Enforced by:** `tests/scripts/test-zot-inventory.sh` (verb confinement, egress confinement,
  masking, marker field allow-list, the `ZOT_PUSH_*`-unset entry assertion),
  `tests/scripts/test-zot-inventory-assert-marker.sh` (the readback gate),
  `apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh` (dispatch-only), all
  registered in `scripts/test-all.sh`.

## Context

The registry host has no in-place execution path. `hcloud_server.registry` is cloud-init-only
(ADR-096), so every host-side capability — tightening zot's keep-set, re-running `resize2fs`,
adding per-path disk telemetry, restarting the daemon under operator control — waits for a
provisioning event. And while the LUKS recut is unfired (#7287) there is no safe provisioning event: a replace opens
`/dev/mapper/registry` against a still-plaintext ext4 volume and takes the `refusing-non-luks-device`
arm, which darks the sole pull path permanently. #7287 records the recut as vetoed while #7278 is
open. That is the deadlock, and it is why #7278 asked for "a lever".

Against that, the question the incident actually needs answered is a **measurement**, not an
action. `SOLEUR_ZOT_DISK` reports `pcent=100` on a 59 GB filesystem with `resize_ok=true` and no
slack, but it carries **no per-path breakdown**, so nothing in the estate can say whether that
59 GB is policy-kept blobs or something else. The keep-set arithmetic points nearer ~25 GB than
59 GB. Nobody has measured it.

### What was measured before writing this (2026-08-06, self-pulled)

| Probe | Result |
|---|---|
| `GET /v2/` over the existing `registry.soleur.ai` CF-Access ingress, read-only pull creds | **200** — the origin answers |
| `GET /v2/_catalog` | **200**, exactly **2** repositories |
| zot `accessControl` in `cloud-init-registry.yml` | pull user `["read"]`; push user `["read","create","update"]` — **no user holds `delete`** |
| Better Stack Logs ingest POST from a workstation | **HTTP 202**; **POST → queryable = 17 s** |
| Any prior GitHub Actions POST to Better Stack ingest | **none, ever** — this PR is the first |
| `BETTERSTACK_LOGS_TOKEN` in `soleur/prd` | **present**, reachable via `secrets.DOPPLER_TOKEN_PRD` |
| `sha256-*` referrer tags visible in `tags/list` | **0** in both repos — but the referrers API answers **200** with a sigstore bundle of **~876 bytes** |

Two directions fall out of that table, and they are the whole decision:

- **The read surface is reachable.** A read-only inventory needs no host change, no new ingress,
  no new credential and no Terraform.
- **The write surface is not.** Under deny-by-default `accessControl` a
  `DELETE /v2/<name>/manifests/<digest>` is refused regardless of what the pinned zot build
  implements, so the build-capability question is moot and must not be asserted either way
  (`hr-verify-repo-capability-claim-before-assert`). Granting `delete` means editing
  `/etc/zot/config.json`, which is cloud-init-written — straight back into the deadlock.

A prototype sweep run from a workstation returned `manifest_referenced_bytes` = **14.78 GB**
against ~56 GB used, with **12 manifest errors** — i.e. `enumeration_complete=false`. Under this
ADR's own rule that licenses **no** conclusion. It is recorded here only as the reason the lever
must emit completeness as a first-class field rather than a bare total.

## Decision

### 1. GitHub Actions may emit `SOLEUR_*` markers to the Better Stack Logs ingest, not only query it

Two C4 anchors currently assert that CI's relationship with the Logs warehouse is read-only
(`github -> betterstack` — *"ALSO reads the heartbeats API read-only"*; the `betterstack` element
— *"a Logs warehouse … that CI polls read-only"*). Both become false with this change and are
corrected in the same PR.

The constraint that comes with the capability: **a CI POST bypasses Vector's VRL scrub.** Every
host-side emitter reaches source 2457081 through a Vector agent that redacts; a direct
`curl` from a runner does not. So a CI-emitted marker must be **PII-free by construction** — the
`SOLEUR_ZOT_INVENTORY` line carries byte counts, object counts, our own OCI repo names and our own
digests, nothing else — and that construction is asserted by a strict field allow-list test derived
from the construction site rather than hand-copied.

### 2. A CI-emitted marker is trusted only AFTER readback

The emitter's exit code is **not** evidence that the line landed. A run is green only when the
job has read its own marker back out of the warehouse by `run_id` **and** with
`enumeration_complete=true`. This is ADR-166's rule turned on the job's own telemetry: the job may
claim the marker was ingested only if it measured the ingestion.

Two mechanical consequences, both from measurement rather than taste:

- The poll budget is a multiple of the **measured 17 s** POST→queryable latency; below that floor
  a non-observation is `unknown`, never a verdict.
- The readback needs a **positive control**. `SOLEUR_ZOT_DISK` lands on the same source every
  5 minutes, so a 15-minute window holds ~3 control rows. Zero control rows means
  `channel_dark`, never `marker_absent` — an unanswered query is not an absence.

### 3. The registry's read surface is instrumentable; its write surface is not, and this ADR does not pretend otherwise

`inventory` is delivered. `restart`, `push-config` and `reclaim` are **blocked on a provisioning
event** and are recorded as blocked rather than dropped, with the measured reason for each. This
matters because the blocked set is what a future reader will otherwise re-derive under incident
pressure, and re-deriving it costs a live probe against a crash-looping origin.

### 4. `skip-docker-login` exists to avoid a fail-closed abort — privilege reduction is secondary

`.github/actions/cf-tunnel-registry-bridge/action.yml` ends with `docker login 127.0.0.1:5000`
using `ZOT_PUSH_*`. `scripts/registry-pull-path-health.sh`'s header records that the bridge
*"exits 1 on a failed listener bind **and on a failed docker login**"*. With `zot_restarts`
climbing at roughly 4.8/min, the most likely outcome of dispatching the inventory *without* the
skip is that **the composite aborts and the measurement never runs** — the lever defeated by an
unrelated gate during precisely the condition it exists to measure. That is the primary reason.
The privilege reduction (§5) is the secondary one, and it is weaker than the first draft claimed.

The input **fails closed**. The gate condition is exactly `inputs.skip-docker-login != 'true'`,
never `== 'false'`: an inverted test lets a typo'd or empty value silently strip credentials from
every existing push caller. The composite additionally normalizes and rejects
(`case "${SKIP:-false}" in true|false) ;; *) exit 1 ;; esac`), because GitHub Actions does **not**
fail on an *undeclared* input key — `skip_docker_login: true` with an underscore would otherwise
yield a push-credentialed job with no error anywhere.

### 5. The privilege guarantee is NON-MATERIALIZATION, not non-possession

This is stated precisely because the first draft of the plan overclaimed it, and the overclaim was
headed into this ADR.

The inventory job holds `secrets.DOPPLER_TOKEN_PRD`, which is scoped to the whole `soleur/prd`
**root config**. Doppler service tokens are **config-scoped, not secret-scoped**, so there is no
variant that reads `ZOT_PULL_TOKEN` without also being able to read `ZOT_PUSH_TOKEN` — the job
**could** read the push credential in one command, and `apply-web-platform-infra.yml`'s
`registry_store_restore` job does exactly that with the same token.

What this design buys is therefore **non-materialization**: with `skip-docker-login: true` the job
does not decode `ZOT_PUSH_*` into its environment and does not leave a docker session
authenticated against the sole pull path. It does **not** buy non-possession, and saying so would
be false.

The narrow claim is made self-enforcing rather than asserted: `scripts/zot-inventory.sh` checks at
entry that `ZOT_PUSH_USER` and `ZOT_PUSH_TOKEN` are unset/empty and exits non-zero if either is
populated. That catches a mis-keyed `skip-docker-login` regardless of what any workflow YAML says
— the "measure something the failure state cannot produce" discipline applied to this ADR's own
privilege claim.

Narrowing further would need a new isolated Doppler config, i.e. a new `doppler_project` /
`doppler_secret`, i.e. Terraform — rejected for the reason in *Alternatives Considered*.

### 6. `BETTERSTACK_LOGS_TOKEN` in `soleur/prd` is NOT Terraform-declared, and must not be made so as a reflex

Every `doppler_secret` carrying that name mirrors it into an **isolated** project
(`soleur-registry/prd`, `soleur-inngest/prd`). Its presence in the `soleur/prd` root is
out-of-band; this session **measured** it present there, which is the only reason the design has
zero-Terraform and zero-new-secrets.

The trap: if that value is later found absent or rotated, the reflexive fix — declaring a
`doppler_secret` for it in `soleur/prd` — **is a `.tf` change**, and any `.tf` change today has no
scoped apply path (see *Alternatives Considered*). The correct response is to re-read it
out-of-band or to re-scope, never to mint the Terraform resource.

A related fail-open is recorded because it nearly killed this design:
`doppler secrets --only-names` renders a **box-drawing table**, so `grep -cE '^NAME$'` matches
nothing and every key reads ABSENT. Use `--only-names --json | jq -r 'keys[]'` and assert a
non-zero key count as a positive control before believing any absence.

### 7. Why ADR-169's no-predicate clause does not reach this

`scripts/registry-pull-path-health.sh` carries the header
*"THERE IS DELIBERATELY NO PREDICATE THAT OBSERVES PRODUCTION ZOT. READ THIS BEFORE ADDING ONE."*,
and ADR-169 records the ruling behind it: a draft "A5" live write probe against production zot was
removed because its only distinctive abort arm fires on a divergence the recut itself repairs. A
plan that supersedes a predecessor and carries ten refutations should not leave the eleventh
unaddressed, so it is addressed here.

**That objection is to undecidable classification inside an AUTHORIZATION GATE.** A5 sat in the D10
gate; a gate converts an observation into permission, so an observation whose failure mode is
indistinguishable from the condition being recovered turns into a refusal to recover. The
inventory lever is **a measurement, and a measurement is not a gate**:

- It authorizes nothing. No dispatch, no destroy, no apply and no merge is conditioned on its
  output. It cannot refuse anything to anyone.
- Its ambiguous case is explicitly *not* a verdict: an incomplete sweep emits
  `enumeration_complete=false` and licenses no conclusion, where a gate would have had to choose
  between allow and deny.
- It is manually dispatched and read-only. A5's hazard was blocking a recovery; the worst case
  here is a run that produces no number.

So the D10 gate keeps its no-predicate property unchanged, and this lever does not become one.

### 8. Amendment to ADR-096

ADR-096's cloud-init-only posture for the registry host has a consequence worth stating plainly,
because it is what this whole ADR routes around: **every host-side capability waits for a
provisioning event, and while the LUKS recut is unfired (#7287) there is no safe provisioning event.** The practical
corollary is that the *read-only* surface is currently the only instrumentable one — so read-only
instrumentation is not a lesser version of the work, it is the entire near side of the deadlock.

> **Superseded 2026-08-11 (#7440), by ADR-184 §6 — the premise above no longer holds.** The body of
> this section is left exactly as written because it was true when written and is the reason this
> ADR took the shape it did; the correction is appended rather than substituted.
>
> **The recut has fired.** The live `SOLEUR_ZOT_DISK` heartbeat reads `pcent=8` — down from 100
> across 2026-08-04 → 2026-08-10 — on boot `bc135d5b-d509-41c4-8129-9181421e845c`, with
> `resize_ok=true` and `zot_restarts=0`. A safe provisioning event therefore EXISTS: the step-6
> `registry-host-replace` of the zot-pin ordered path.
>
> So the corollary — that the read-only surface is *the only* instrumentable one — is retired.
> ADR-184 ships a host-side container-log shipper into `cloud-init-registry.yml` that rides that
> replace. What remains true is the *first* clause: a host-side capability still waits for a
> provisioning event, and merging one applies nothing.
>
> **§3's write-surface finding is undisturbed.** ADR-184 changes no `accessControl` and grants no
> `delete`; it reads the journal the container already writes. The deadlock this ADR routed around
> was about the registry's *write* surface, and that half has not moved.

> **[Appended 2026-08-12 (#7455) — the "rides that replace" clause above is RETRACTED.]** Delivery
> did NOT ride the step-6 `registry-host-replace`: that replace had already fired atomically inside
> `registry_luks_recut` on 2026-08-10T22:08Z, ~45h BEFORE the shipper merged (2026-08-12T19:38Z), so
> the shipper sat inert on a host born before it existed. A dedicated `registry_host_replace` job
> (run 31639782781) delivered it 2026-08-12T20:54:12Z, and the first warehouse readback at
> 21:03:51Z flipped ADR-184 `adopting → accepted`. The boot cited above (`bc135d5b-…`) is superseded
> by `93c52405-5fd2-462d-8051-fa68b8ab327f`. Everything else in this block stands — including that a
> host-side capability still waits for a provisioning event and that merging one applies nothing.

## Alternatives Considered

| Alternative | Verdict | Reason |
|---|---|---|
| Mint a new `registry_inventory` CF Access service token scoped to CI | **Rejected** | A new CF Access token plus its Doppler secrets have **no scoped apply path**. None of the registry dispatch targets would create them, so landing them requires an **untargeted** apply — and an untargeted plan today carries the **pending `-/+ hcloud_server.registry` REPLACE already in state** into the unfired-recut fatal (#7287). That reasoning applies to *any* new `.tf` resource, which is why it also rejects a new isolated Doppler config in §5. **The rationale an earlier draft gave was mechanically false and is retracted:** it claimed `-target` transitivity would pull the new token into the three registry gates and brick the recut. `-target` closes over **dependencies**, not dependents, so a CI-only token never enters those graphs. The in-repo counterexample is decisive — `cloudflare_zero_trust_access_service_token.registry_push` and its two `doppler_secret`s are **not** in `hcloud_server.registry`'s `depends_on`, which is exactly four entries. Do not re-derive the retracted version. |
| Inline the `cloudflared access tcp` bridge in the new workflow | Rejected | Duplicates the SHA-pinned cloudflared install into a fifth site. The composite's own SHA-RECOMPUTE DISCIPLINE section exists because that pin drifts. |
| Use the composite as-is and accept the push-credentialed `docker login` | Rejected | Grants a read-only lever write capability on the sole pull path, and — the stronger objection per §4 — makes the run abortable by a login failure during exactly the crash-loop it exists to measure. |
| A **restart** lever (the superseded 2026-08-04 scope) | Rejected | Refuted by measurement: `--restart unless-stopped` has already restarted zot **15,640** times into the same 100 %-full volume. Restarting into a full disk restarts into the same wall. Its host-side delivery additionally needs a replace, which is the unfired-recut fatal (#7287). |
| Reclaim via `DELETE /v2/<name>/manifests/<digest>` over the existing ingress | Rejected | **No zot user holds `delete`** (measured). Deny-by-default refuses it whatever the build supports. |
| Force a GC pass over HTTP | Rejected | No endpoint exists — `/v2/_zot/gc`, `/v2/_catalog/gc`, `/_zot/gc`, `/v2/_zot/ext/gc` all 404, and the pinned build's `BinaryType` excludes mgmt/scrub/search. |
| Print the number to the job log and skip the Better Stack round-trip | Rejected | The lever must be observable **from telemetry**, not from its own exit code. The job log is kept as an additional durable home for the figure and is **never** the pass condition. |
| `crane` as the enumerator | Rejected | It collapses every failure to exit 1, so the verdict taxonomy would have to be recovered from stderr prose instead of `curl -w '%{http_code}'`; it moves egress into a second binary, which falsifies the egress-confinement test; and it adds a sixth SHA pin site. `curl` + `jq` hand-rolls the `Link` loop, which is also what lets an unfollowed `Link` header be **detected** rather than silently ignored. |

## Consequences

**Good**

- The unmeasured question — is the 59 GB actually policy-kept blobs? — becomes answerable with
  zero host change, zero Terraform, zero new credentials and no #6929 exposure.
- CI gains a general capability: any future workflow can emit a `SOLEUR_*` marker and have it land
  in the same warehouse the estate already queries, under a stated PII rule and a stated
  readback rule.
- The privilege claim in this ADR is machine-checked at script entry rather than asserted in prose.

**Bad / accepted**

- `delta_gb` is an **upper bound on unreferenced bytes**, never a measurement of them. Two named
  candidates — zot's dedupe cache DB and orphaned `.uploads/` staging — have different remedies,
  and this lever distinguishes neither. **No cause is asserted from it.**
- `pcent` is `used/(used+avail)` and excludes ext4's root reserve, so `fs_size_gb × pcent/100`
  overstates used bytes by roughly **2.95 GB on 59 GB**. A `delta_gb` under ~3 GB is **not
  distinguishable from zero**.
- Referrers are real and invisible to `tags/list`, so referrer coverage stays a first-class input
  to `enumeration_complete`. Their magnitude, however, is negligible: **~876 bytes** each. The
  feared ~80 % undercount does not hold.
- Runner egress to `s2457081.eu-fsn-3.betterstackdata.com` is **unproven pre-merge** — the 202 was
  measured from a workstation, not from a runner against the region pin. It is handled by emitting
  `reason=ingest_rejected_http_<code>` from the POST's own status rather than by assuming success,
  and it is what keeps this ADR at `adopting`.
- The `soleur/prd` copy of `BETTERSTACK_LOGS_TOKEN` is out-of-band. That is a real fragility; §6
  states the fallback constraint so the fragility cannot be "fixed" into a Terraform change.

**Recorded config drift, not fixed here.** `cloud-init-registry.yml` asserts that cosign here uses
tag-based signatures *"not Subject-field OCI referrers"*. The measurement shows the opposite: the
`sha256-<digest>.sig` tag **404s** and a Subject-field referrer **exists**. So the keep-set's
`sha256-.*`×50 rule currently protects tags that do not exist, while `deleteReferrers=false`
protects the referrers that do. Fixing it is a host config change, i.e. blocked. Recorded so it is
not re-derived.

## Status flip condition

`adopting → accepted` when a real dispatch produces an **observed** `SOLEUR_ZOT_INVENTORY` line
with `enumeration_complete=true` and a numeric `delta_gb`. That is enrolled as a follow-through,
not remembered: **#7339**, driven by `scripts/followthroughs/zot-inventory-marker-7278.sh`.

The blocked-action set in §3 is enrolled too — **#7340**, driven by
`scripts/followthroughs/registry-luks-blocker-6929.sh`, which closes the day #6929 does. Both
trackers are **dedicated issues**: #7278 is closed by this PR and the sweeper lists `--state open`
(so a probe hosted there would never run), and #7247 is a live P1 that will close and take any
tracker on it with it.
