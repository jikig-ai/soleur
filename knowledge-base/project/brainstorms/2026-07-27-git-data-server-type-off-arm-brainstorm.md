---
date: 2026-07-27
issue: 6570
pr: 6974
branch: feat-git-data-server-type-6570
lane: cross-domain
brand_survival_threshold: single-user incident
status: complete
tags: [infra, hetzner, terraform, adr-068, adr-143, active-active, server-type]
---

# git-data must move off the unorderable `cax11` ARM pin

## What We're Building

`soleur-git-data` — the bare-repo store that ADR-068 Phase-3 concurrent serving depends on —
is declared in `apps/web-platform/infra/git-data.tf:120` on `var.git_data_server_type`, whose
default is `cax11` (ARM64/Ampere). The entire Hetzner `cax` line is orderable in **0 of 3** EU
datacenters, so the host cannot be born on its declared type. It never has been.

This brainstorm decides the replacement type and how the host's architecture is selected, and
records the decision as an ADR-143 sibling. It does **not** build the host — the birth is a
separate gated `workflow_dispatch`.

## Premise Corrections

Issue #6570 was filed 2026-07-16. Three of its stated constraints were falsified by live
probes run at brainstorm time (2026-07-26T22:07Z). Recorded here so no downstream artifact
re-imports them.

| Issue claim | Status | Live finding |
|---|---|---|
| `cax` orderable in 0 of 3 EU DCs | **HOLDS** | Re-measured: `nbg1-dc3`, `hel1-dc2`, `fsn1-dc14` all `cax_orderable=0` |
| git-data has never existed | **HOLDS** | `/v1/servers` returns 5 hosts; none is git-data |
| "the account cap is 5 servers" | **FALSE** | Live limit is **10 servers, 5 running** — five free slots |
| "a raise is a Hetzner Console request" | **MOOT** | The raise was already granted in the 2026-07-15 cap-headroom workstream |
| "a slot is freed by retiring web-2 (5/5 → 4/5)" | **STALE** | web-2 was **re-added 2026-07-24** as a fresh cattle standby (ADR-143 D1, #6459). Fleet is back at 5/5 — irrelevant, since the cap is 10. |
| `GET /v1/limits` returns 404 | **HOLDS** | Confirmed HTTP 404. But the *inference* drawn from it — "cap unreadable, assume 5" — is what was wrong. |

The stale `5` is not a harmless error. ADR-143's addendum records that it nearly caused two
wrong decisions: requesting a cap raise that already existed, and retiring `soleur-grok-dogfood`
to "free a slot" — an irreversible `cx33` loss (cheapest orderable 8 GB replacement is `cpx32`,
4.2×) for a slot that was already free six times over. Because `/v1/limits` 404s, **no automated
check can read the cap**, so nothing contradicts a stale value once it enters the repo. Recording
the limits as facts with a decay date belongs to #6460.

**What still holds:** the "root blocker of active-active" framing. ADR-143 shipped the ingress +
host-lifecycle layer, but explicitly keeps `replicas=1` in force and gates *concurrent serving*
on ADR-068 Phase-3 GA (shared git-data). ADR-143:149 names #6570 as the owner of this decision
and deliberately left `var.git_data_server_type` unchanged.

## Why This Approach

**Type — `cpx22` (2c/4g/80GB x86, €19.49/mo net, hel1).**

This is not a novel call; it is the **third** application of an established in-repo pattern.
`soleur-inngest` sits on `cpx22` for the identical reason — the expense ledger records it
provisioned "amd64 (cpx22, ~EUR 19.49/mo) because the cheaper arm64 cax11 (~EUR 5.99/mo) was
EU-wide out of stock at Phase-2 provision time" (#6178, ADR-100). `soleur-web-2` landed on
`cpx22` for the same reason a week ago (#6967, ADR-143 addendum).

Live pricing pulled at decision time (hel1, net/mo):

| type | shape | disk | arch | €/mo | orderable |
|---|---|---|---|---|---|
| `cx23` | 2c/4g | 40 GB | x86 | 5.49 | hel1 only — **flickering** |
| `cax11` (current pin) | 2c/4g | 40 GB | arm | 5.99 | **0 of 3** |
| `cpx12` | 1c/2g | 40 GB | x86 | 11.49 | all 3 |
| `cpx22` | 2c/4g | 80 GB | x86 | 19.49 | all 3 |
| `cpx32` | 4c/8g | 160 GB | x86 | 35.49 | all 3 |

`cpx22` matches the `cax11` pin exactly on cores and RAM (2c/4g) and doubles local disk, so this
is a **price change, not a resize** — +€13.50/mo vs the ARM pin. Both git-data data stores are on
separate volumes (`hcloud_volume.git_data` + `git_data_luks`), so local disk is irrelevant to
capacity either way.

`cx23` was rejected despite being the cheapest and *cheaper than the ARM pin at identical specs*.
It is orderable in hel1 right now but was orderable in **0 of 3** DCs on the repo's probe hours
earlier — it flickers. Picking a type on the strength of a single point-in-time reading is the
exact mechanism that produced this bug, and it would strand git-data in the same grandfathered
class as web-1 (`cx33`), `soleur-grok-dogfood` (`cx33`) and `soleur-registry` (`cx23`) — the
#6460 DR gap, where none of the three can be rebuilt on its current type.

`cpx12` was rejected on headroom: it halves the pinned shape to 1c/2g, `git gc`/`repack` are
spiky on a single vCPU, and a later resize is a reboot-forcing change — which for git-data means
a second birth through the gated dispatch, with LUKS passphrase preservation each time.

**Arch — derive it, don't hardcode it.**

`git-data` is the one dedicated host that hardcodes its architecture. `zot-registry.tf` and
`inngest-host.tf` both derive it (`startswith(var.X, "cax") ? "arm64" : "amd64"`) and select
their downloads + checksums off that local. git-data has **no** such local, and
`cloud-init-git-data.yml:129` hardcodes the `linux_arm64` Doppler CLI build — which is precisely
why ADR-143 notes this "is a real code change, not a var flip".

Deriving keeps the type pin and the binary download structurally coupled so they cannot drift
apart again, and makes an ARM restock a var flip rather than cloud-init surgery. The inngest
ledger row already promises exactly this revert path for its host; git-data should have the same.

The blast radius is small: the Doppler CLI is the **only** arch-coupled artifact in
`cloud-init-git-data.yml` (a single `curl` + its `sha256sum -c`). The per-arch checksum pair
already exists verbatim at `inngest-host.tf:66` (same pinned Doppler version), so it is reused,
not re-derived.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | `var.git_data_server_type` default `cax11` → **`cpx22`** | Only stably-orderable like-for-like (2c/4g). Third instance of the established cax11→cpx22 pattern (inngest #6178, web-2 #6967). +€13.50/mo. |
| D2 | Add `local.git_data_arch` deriving arm64/amd64 from the type prefix | Mirrors `local.registry_arch` / `local.inngest_arch`; couples pin to download so they cannot drift. |
| D3 | Select the Doppler CLI download **and** its checksum off `local.git_data_arch` | The only arch-coupled artifact in the cloud-init. Reuse the per-arch sha256 pair at `inngest-host.tf:66`. |
| D4 | Add a `validation` block rejecting an unrecognized type prefix | Mirrors `inngest_server_type`'s guard: a typo whose arch cannot be inferred fails at plan. |
| D5 | Add `data "hcloud_server_type" "git_data"` | git-data has no plan-time type guard; only zot-registry does. This is the #6508 fix that makes a nonexistent type fail at **plan** instead of after `-replace` has already destroyed the host — #6288's exact disaster, and `git-data-host-replace` is a destroy-first path. |
| D6 | Rewrite the `# cax11 = ARM64 (Ampere); git/sshd are ARM-native` comment | The rationale is voided by the move. Deleting it beats leaving stale justification standing (the #6966 precedent). |
| D7 | Update expense ledger row 19 `CAX11 (git-data)` → `CPX22`, $4.10 → ~$21.05 | `wg-record-recurring-vendor-expense-before-ready`. Status stays `approved-not-billing` — the host is still unborn; billing begins at the gated dispatch. |
| D8 | Record as an **ADR-143 addendum**, not a new ADR | ADR-143:149 already scoped this as its own follow-on and anticipated the shape change; #6966 set the precedent of recording a forced-by-stock repin as an addendum. |
| D9 | **Do not** birth the host in this PR | The birth is a gated `workflow_dispatch` with a live stock re-probe. Stock moves on an hours timescale — orderability at merge time is not orderability at apply time. |

## User-Brand Impact

- **Artifact:** the `soleur-git-data` host declaration (`git-data.tf` + `cloud-init-git-data.yml`)
  and its `git_data_server_type` pin.
- **Vector:** git-data is the store for per-workspace bare repos. A host that boots on the wrong
  architecture, or a `-replace` that destroys before discovering its target type is unorderable,
  strands or loses a user's workspace git history with no rollback — the single-user incident is
  "my project's history is gone", the least recoverable failure this product has.
- **Threshold:** `single-user incident`.

The LUKS-passphrase-preserving-by-omission property of `git-data-host-replace` is load-bearing
here and must survive: D1–D6 keep `random_password.git_data_luks` and
`doppler_secret.git_data_luks_key` out of scope, so the existing `luks_passphrase_touched`
backstop continues to assert it.

## Downstream Chain — what merging this does NOT unblock

The repin is step 1 of a chain. Recorded so no reader mistakes a merged #6570 for a usable
git-data store. Each item verified open at brainstorm time.

| # | Gate | State |
|---|---|---|
| 1 | **#6570 repin** (this work) | The host cannot be *declared* bornable until this lands. |
| 2 | **Birth the host** via gated dispatch | `git-data-host-replace` plans a plain CREATE against a host absent from state. **Verify that path rather than assume it** — the stock preflight would have aborted on `cax11`, so it has never actually run this shape. If it does not fit, an additive birth route may need building, as the web-host birth path did (#6730). |
| 3 | **#6975 heartbeat masking** (filed by this brainstorm) | Precondition of the *birth*, not the repin — see Open Questions. |
| 4 | **#6680** — `git-data-cutover.yml` has no tunnel ingress for `10.0.1.20` | The CF Tunnel SSH bridge reaches only web-1, and the whole cutover runs over that bridge. **Host born is not cutover-runnable.** An unsolved design question, not a mechanical fix. |
| 5 | **Flip `GIT_DATA_STORE_ENABLED`** on both hosts in lockstep | Verified **absent from Doppler `soleur/prd` entirely**; `workspace-resolver.ts:57` gates on `=== "true"`. Flip **only** via `git-data-cutover.sh` — it sits behind drain → delta-rsync → set-identity verify, and a manual Doppler set skips the write-freeze. |

**Even completing all five does not give web-2 traffic.** `lb-weight-gate.sh` Condition B needs
`GIT_DATA_STORE_ENABLED==true` *plus* a `GIT_DATA_LUKS` soak marker, and condition (3) needs
web-2's `/workspaces` LUKS-backed (#6931). Necessary, not sufficient. Serving-weight stays out of
scope here.

Adjacent and deliberately deferred: **#6548** (git_data_prd never unpaused, absent from live
Better Stack) and **#5914** (host-key TOFU on private-net git SSH).

## Open Questions

1. **Should git-data be born with LUKS enabled from the start, skipping the plaintext-first
   cutover entirely?** *(Leaning yes — see below.)*

   Encryption-at-rest is fully built (`git-data-luks.tf`, guest-side LUKS2, ~238-bit passphrase
   from a least-privilege `prd_git_data` Doppler config, rated **conforming** in the
   encryption-posture audit). But it is built as a **cutover**: `hcloud_volume.git_data` is
   plaintext ext4 and is the source; `hcloud_volume.git_data_luks` is the target;
   `git-data-cutover.sh` rsyncs old→fresh under a write-freeze. The plaintext volume is flagged
   under **#6897** pending its DL-2 wipe.

   That design is correct for the scenario it was written for — a Phase-2 host already holding
   live plaintext data. **That scenario never happened.** The host has never been born and
   `GIT_DATA_STORE_ENABLED` is absent from Doppler `prd`, so `replicateToGitData` has never run
   and *neither* volume has ever held a byte of user data. There is nothing to migrate.

   **Why born-on-LUKS looks better:**
   - **No plaintext window ever exists** for user git history — a cleaner GDPR Art. 32 / NFR-027
     posture than migrating *into* encryption, and it moots the #6897 plaintext-volume item for
     this host rather than deferring a wipe.
   - **It is not a `REPO_ROOT` change.** `git-data-cutover.sh:67` reads
     `OLD_ROOT="${OLD_ROOT:-/mnt/git-data}"  # plaintext source AND final LUKS mount` — the LUKS
     volume ends up mounted *at* `/mnt/git-data` post-cutover anyway, so the path is
     device-agnostic. Born-on-LUKS is "mount the LUKS volume at `/mnt/git-data` from cloud-init
     and skip the plaintext volume", leaving `git-data-provision.sh:34` and the
     `core.hooksPath` fence wiring untouched.
   - **It sidesteps #6680.** The cutover runs over the CF Tunnel SSH bridge, which reaches only
     web-1 and not `10.0.1.20` — the blocker in downstream-chain step 4. A birth that needs no
     cutover does not need that ingress to exist first.

   **Cost, stated honestly:** `git-data-cutover.sh` + its two-pass freeze-rsync and set-identity
   verification are already built and tested, and ADR-068's phase structure assumes the
   plaintext-first sequence. Choosing born-on-LUKS is an **ADR-068 amendment**, not a config
   tweak, and it gives up the plaintext volume as a rollback backstop. It also does not remove
   the need for the cutover machinery long-term (rotation is still a full volume cutover per
   `git-data-luks.tf`).

   Belongs to the **birth** (downstream-chain step 2), not this repin. Decide before dispatching.

2. **Does the read-source flip need a one-time backfill for idle workspaces?** Population of
   git-data is **lazy and turn-driven**, not a bulk migration: `replicateToGitData` force-pushes
   all `refs/heads/*` + `refs/tags/*` at *session end* and no-ops at flag-off. There is no
   web-1 → git-data rsync (`git-data-cutover.sh` is entirely git-data-host-local; it SSHes to web
   hosts only to drain them), and `git grep -E 'backfill|seed|bulk.*push'` over
   `git-data-*.ts` returns **zero hits**.

   So a workspace with no session after the flip never populates. That is harmless while
   git-data is a **write-only replica** (the read-source flag defaults to the volume until PR C)
   — the web volume stays the read source, so an empty repo costs nothing.

   It becomes load-bearing at the **read-source flip**, because ADR-068 §(d) concedes GitHub is
   not a complete backstop: *"`syncPush` auto-commits only `knowledge-base/**` and reroutes a
   protected-default push to a `soleur/kb-sync` PR branch, so the agent's real commits never land
   on origin's default branch … a fresh GitHub clone can be strictly behind the user's latest
   tip."* git-data is authoritative for the most-recent per-user worktree tip, and today that tip
   lives **only on web-1's volume**. An unpopulated workspace read through `fetchFromGitData`
   would resolve from a clone that is behind.

   Unresolved: whether PR C needs a one-time backfill, or whether lazy population suffices
   because reads fall back to the volume. Not this PR's scope; flag before the read-source flip.

3. **The git-data heartbeat masks across hosts — filed as #6975.** `web-probe-envwrite.sh:42`
   asserts *"git-data uses ONE shared beat today (single-host; masking moot, C3) → the KEY is
   unsuffixed"*, and line 54 writes `GIT_DATA_HEARTBEAT_URL_KEY=GIT_DATA_HEARTBEAT_URL`. That
   single-host premise is **dead** — `soleur-web-2` is live. Both hosts probe `10.0.1.20:22` and
   ping the same unsuffixed beat, so a healthy web-1 path MASKS a dead web-2→git-data path. This
   is the exact OR-masking `web-probe.tf` designed out of the zot and NIC-guard beats via
   `for_each var.web_hosts`. No open issue tracked it. **Decided: file, do not fold in** — the
   repin is a server-type decision and this is a probe-topology defect. It gates the **birth**
   (step 2 above), not this PR, because with no git-data host both probes currently fail and
   nothing is yet masked.
4. **`terraform_data.git_data_probe_install` (`server.tf:622`) is hardcoded to
   `hcloud_server.web["web-1"]`**, while fresh hosts get the probe baked via
   `cloud-init`/`soleur-host-bootstrap.sh`. web-2 has the probe, but the two hosts receive it by
   different mechanisms — a drift surface. The same resource also hardcodes `web-1` inside the
   zot key suffix. Carried into #6975.
5. **Should the remaining grandfathered hosts get D5's plan-time guard?** web-1 (`cx33`) and
   grok-dogfood (`cx33`) have none; only zot-registry does. Owned by #6460.
6. **Revert-to-ARM trigger.** D2 makes reverting to `cax11` a var flip when Ampere restocks, but
   nothing watches for a restock. #6460's periodic orderability audit is the natural home.
7. **Expense ledger row 16 (`CPX22 (web-2)`) is stale** — it reads `approved-not-billing` with
   "web-2 is NOT provisioned yet", but the host is **live** (Hetzner API 2026-07-26T22:07Z; #6969
   covers its first boot). Adjacent to FR8's ledger edit; flagged, not fixed here.

## Cross-Session Review (2026-07-27)

A parallel session produced an independent plan for the wider git-data enablement. Its findings
were checked rather than adopted. Corroborated and folded in: the type choice (`cpx22`, reached
independently), the #6975 masking defect, the #6680 cutover-ingress gate, the
`GIT_DATA_STORE_ENABLED` absence, the probe-install drift, and `run-registered-suites.sh` as the
authoritative infra gate (TR6).

**Two of its claims did not verify and were not adopted:**

- **"branch `feat-one-shot-6969-web-host-replace` (PR #6973) already edits `variables.tf`,
  `apply-web-platform-infra.yml`, `stock-preflight-gate.sh`, `scheduled-inngest-health.yml`,
  `terraform-target-parity.test.ts`, `test-all.sh`."** `git diff origin/main...origin/feat-one-shot-6969-web-host-replace`
  shows **exactly two files**: a plan doc and a `tasks.md`. None of the claimed files is touched.
  That session was describing its own uncommitted working tree, not pushed state — which also
  makes its "green on all 13 ACs, only needs `/review` → `/ship`" unverifiable, since the
  implementation is not pushed. The conflict is therefore **prospective, not actual**; the
  mitigation (fetch `origin/main` immediately before editing `variables.tf`) is still sound, and
  no sequencing dependency on that branch is warranted.
- **"It CLAIMS ADR-148 — take 149 or higher."** No `ADR-148` reference exists on that branch, and
  the highest ADR on `main` is **ADR-147**. Moot for this work regardless: D8 records an ADR-143
  **addendum**, which allocates no new number.

## Domain Assessments

**Not spawned.** This session ran under a standing operator instruction not to invoke subagents,
so the Phase 0.5 domain-leader fan-out (CPO/CLO/CTO triad) did **not** run. The assessment below
was performed inline by the orchestrator and is recorded honestly as such rather than presented
as leader sign-off.

- **Engineering:** the change is three files (`variables.tf`, `git-data.tf`,
  `cloud-init-git-data.yml`) plus the ledger, with two in-repo precedents to copy verbatim. The
  only genuinely new element is D5's plan-time guard.
- **Finance:** +€13.50/mo net against the voided ARM pin (~+$14.60 at ~1.08 FX). Not yet burn —
  the row stays `approved-not-billing` until the gated birth. The `cx23` alternative would have
  been *cheaper* than the ARM pin but was rejected on stock durability, so the cost increase is
  a deliberate purchase of orderability, not an unavoidable one.
- **Legal:** no new sub-processor; same Hetzner account and DPA. `hel1` keeps EU residency
  (CLO T-1). LUKS-at-rest posture is unchanged by construction.

## Capability Gaps

None. Every mechanism this decision needs already exists in-repo:
`local.registry_arch` / `local.inngest_arch` (evidence: `zot-registry.tf:58`,
`inngest-host.tf:62`), the per-arch Doppler checksum pair (`inngest-host.tf:66`), the plan-time
type guard (`zot-registry.tf:134`), and the stock preflight gate
(`tests/scripts/lib/stock-preflight-gate.sh`, which `git-data-host-replace` already sources).

## Productize Candidate

`fleet-sku-orderability-audit` — three hosts are now grandfathered on unorderable types and
nothing detects "a declared type left the orderable set" until an apply. Already scoped to
**#6460**; not a new candidate, but this brainstorm is the third independent occurrence and
strengthens the case.
