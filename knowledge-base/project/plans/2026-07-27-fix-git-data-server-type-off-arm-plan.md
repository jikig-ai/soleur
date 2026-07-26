---
date: 2026-07-27
type: fix
issue: 6570
pr: 6974
branch: feat-git-data-server-type-6570
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-07-27-git-data-server-type-off-arm-brainstorm.md
spec: knowledge-base/project/specs/feat-git-data-server-type-6570/spec.md
---

# fix(6570): git-data server type `cax11` → `cpx22` + dual-arch derivation

## Overview

`apps/web-platform/infra/git-data.tf:120` pins `soleur-git-data` to `var.git_data_server_type`
(default `cax11`, ARM64/Ampere). The entire Hetzner `cax` line is orderable in **0 of 3** EU
datacenters, so the host cannot be born on its declared type — and never has been.

This is an **IaC-only** change: flip the default to `cpx22`, derive the host architecture from the
type prefix instead of hardcoding it, add a plan-time type tripwire, update the expense ledger, and
record an ADR-143 addendum. **No host is born here** (NG1) — the birth remains a gated
`workflow_dispatch`.

Decisions D1–D10 are settled in the brainstorm. This plan implements them; it does not re-derive
them.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| "Tests likely touched: `terraform-target-parity.test.ts`" | It enumerates `terraform_data.*` **SSH-provisioned** resources (`MIN_SSH_PROVISIONED = 10`) and `-target=` allow-lists. A `data "hcloud_server_type"` is neither a `terraform_data` resource nor `-target`-able. | **Scope reduction — not edited.** Removed from Files to Edit. |
| "`cloud-init-user-data-size.test.ts` carries a `git_data_volume_id` fixture" | True (`SECRET_LENGTHS` line 142). New template vars are unmodeled and fall through `DEFAULT_REF_LEN = 80`. Budget is `GIT_DATA_BUDGET = 28_000` / `GIT_DATA_FLOOR = 10_000` vs a current ~21.9 KB render. | **Re-run required, edit optional.** +~96 modeled bytes against ~6 KB headroom. Exact entries added for accuracy (FR10). |
| "Mirror the `local.registry_arch` / `local.inngest_arch` pattern" | Stronger than a pattern: **`cloud-init-inngest.yml` is a line-for-line template.** `:192` `DOPPLER_SHA256="${doppler_sha256}"`, `:193` `..._linux_${doppler_arch}.tar.gz`, fed by `inngest-host.tf:286-287`. | Copy the inngest template shape verbatim, including the `doppler_arch` / `doppler_sha256` var names. |
| "Reuse the per-arch sha256 pair at `inngest-host.tf:66`" | The pair appears **three** times: `inngest-host.tf:66`, `zot-registry.tf:86`, and git-data's own hardcoded arm64 literal at `cloud-init-git-data.yml:128` — all byte-identical, all pinned to Doppler `3.75.3` (confirmed in all three cloud-inits). | Reuse verbatim. The arm64 half is **already proven correct by git-data's own current literal**; the amd64 half is proven by two live hosts. |
| (not in spec) | **`inngest-host.test.sh` §5 is a dual-arch guard precedent**, registered at `infra-validation.yml:700`. Five `git-data-*.test.sh` suites exist; **no `git-data-host.test.sh`**. | **New deliverable:** create + register `git-data-host.test.sh` (FR11, Phase 1 — TDD RED). |
| (not in spec) | **ADR-143's closing paragraph asserts** *"`var.registry_server_type` and `var.git_data_server_type` keep their unorderable defaults."* This PR falsifies half of it. | The addendum must **amend** that sentence, not merely append — otherwise the ADR contradicts itself (FR9). |
| (not in spec) | C4: **no git-data element exists**, and **no `cax11`/ARM/Ampere claim appears in any `.c4` file** (the only `arm64` hit is the inngest→Better Stack Vector edge, `model.c4:433`). | **No C4 edit.** Enumeration cited in §Architecture Decision. |
| TR7 rebase risk | `git diff HEAD...origin/main` on all four target files: **empty**. `origin/main` = `f0df12daf`. | No rebase needed now; re-check immediately before editing `variables.tf`. |

## User-Brand Impact

Carried forward from the brainstorm (unchanged).

- **If this lands broken, the user experiences:** nothing immediately — the host is unborn and
  `GIT_DATA_STORE_ENABLED` is absent from Doppler `prd`, so no user request touches this path today.
  The damage is deferred and lands at the birth: a host that boots on the wrong architecture fails
  its Doppler CLI install, never obtains `GIT_DATA_LUKS_KEY`, and cannot open the LUKS volume — the
  bare-repo store is then absent when ADR-068 Phase-3 finally routes workspace git history to it.
- **If this leaks, the user's data is exposed via:** not a new exposure surface. The LUKS
  passphrase resources are explicitly out of scope (TR2), and the passphrase is never in `user_data`
  — it arrives only as a Doppler-injected env at boot. The relevant risk is **loss, not leak**:
  git-data stores per-workspace bare repos, and ADR-068 §(d) records that git-data is authoritative
  for the most-recent per-user worktree tip (a fresh GitHub clone "can be strictly behind").
- **Brand-survival threshold:** `single-user incident`.

CPO sign-off is carried forward from the brainstorm's cross-domain framing; `user-impact-reviewer`
runs at PR review.

## Implementation Phases

Phase order is **load-bearing**: the contract (variables + locals) must land before its consumer
(the cloud-init template + templatefile map), or Phase 3 references locals that do not yet exist.

### Phase 0 — Preconditions (no edits)

1. `git fetch origin main` and re-confirm zero drift on `variables.tf`, `git-data.tf`,
   `cloud-init-git-data.yml`, `expenses.md` (TR7).
2. Confirm the three Doppler checksum sites still agree and all pin `3.75.3`:
   `grep -n 'doppler_sha256\|DOPPLER_VERSION' apps/web-platform/infra/{zot-registry.tf,inngest-host.tf,cloud-init-*.yml}`
3. **Verify `architecture` exists on the `hcloud_server_type` data source** (provider
   `hetznercloud/hcloud` v1.63.0). If it does **not** resolve, **drop FR6b** and record why — do not
   improvise a substitute. See the FR6b `automation-status` note.
4. Re-probe live orderability before trusting `cpx22` (stock moves on an hours timescale). This is
   informational for the plan; the birth dispatch re-probes for real via `stock-preflight-gate.sh`.

### Phase 1 — RED: the dual-arch guard suite (`cq-write-failing-tests-before`)

Create `apps/web-platform/infra/git-data-host.test.sh`, mirroring `inngest-host.test.sh` §5.
Assertions (all must FAIL before Phase 2):

- `local.git_data_arch` is declared in `git-data.tf` and derived via `startswith(..., "cax")`.
- `local.git_data_doppler_sha256` declares **both** 64-hex checksums.
- `cloud-init-git-data.yml` contains **no** hardcoded `linux_arm64` / `linux_amd64` literal.
- `cloud-init-git-data.yml` contains **no** hardcoded 64-hex `DOPPLER_SHA256` literal.
- The `templatefile` map in `git-data.tf` passes both `doppler_arch` and `doppler_sha256`.
- `var.git_data_server_type` carries a `validation` block.

Register it in `.github/workflows/infra-validation.yml` alongside `inngest-host.test.sh:700`.
**Registration is mandatory** — `run-registered-suites.sh` derives its list from that workflow and
reports unregistered suites as orphans (TR6).

### Phase 2 — GREEN part 1: the contract

`apps/web-platform/infra/variables.tf`:

- `git_data_server_type` default `cax11` → **`cpx22`** (FR1).
- Rewrite the `description` (shape 2 vCPU x86 / 4 GB; arch is DERIVED from this value; `cpx22` is
  stock-forced, not a sizing decision).
- Add the `validation` block rejecting a prefix outside `^(cax|cpx|cx|ccx)` (FR5), mirroring
  `inngest_server_type:260`.

`apps/web-platform/infra/git-data.tf`:

- Extend the existing `locals` block (`:69-77`) with `git_data_arch` and
  `git_data_doppler_sha256` (FR2, FR3), copying the `inngest-host.tf:57-66` comment shape.
- Add `data "hcloud_server_type" "git_data" { name = var.git_data_server_type }` (FR6), mirroring
  `zot-registry.tf:134`.
- Rewrite the void inline comment at `:120` (FR7).

### Phase 3 — GREEN part 2: the consumer (atomic pair)

The cloud-init template and the `templatefile` map **must change in the same commit** —
`templatefile` fails if the template references a var the map does not supply.

`apps/web-platform/infra/cloud-init-git-data.yml` (`:120-130`):

- Header comment: `Doppler CLI (arm64)` → arch-derived wording.
- `DOPPLER_SHA256="${doppler_sha256}"` (replacing the hardcoded literal).
- URL `..._linux_${doppler_arch}.tar.gz` (replacing `linux_arm64`).
- Keep `$${DOPPLER_VERSION}` double-`$` escaped — it is a **shell** variable, not a Terraform one.
  Getting this wrong is the single most likely mechanical error in this PR.

`apps/web-platform/infra/git-data.tf` templatefile map: add `doppler_arch = local.git_data_arch`
and `doppler_sha256 = local.git_data_doppler_sha256`.

Phase 1's suite should now go GREEN.

### Phase 4 — Ledger

`knowledge-base/operations/expenses.md` row 19: `Hetzner CAX11 (git-data)` → `CPX22`, `4.10` →
`~21.05` USD (EUR 19.49 × ~1.08 FX). Status **stays** `approved-not-billing` — the host is still
unborn (FR8). Carry the identical-net-vs-gross caveat the web-2 row uses, and keep the existing
PHANTOM-ROW note (still accurate).

### Phase 5 — ADR-143 addendum

Append a dated addendum recording D1–D10 **and amend** the closing "Not changed by this addendum"
paragraph, which currently asserts `var.git_data_server_type` keeps its unorderable default (FR9).
Leaving it unamended ships a self-contradictory ADR. No new ADR ordinal is allocated (D8, TR8).

### Phase 6 — Verification

1. `cd apps/web-platform/infra && terraform init -input=false && terraform validate`
2. `terraform plan` — assert **no diff** on `hcloud_volume.git_data*`, `random_password.git_data_luks`,
   `doppler_secret.git_data_luks_key` (TR2). The `hcloud_server.git_data` CREATE is expected and
   **not applied** (NG1).
3. `bash apps/web-platform/infra/git-data-host.test.sh` — GREEN.
4. `./node_modules/.bin/vitest run test/...` for `cloud-init-user-data-size.test.ts` (size budget).
5. `bash apps/web-platform/infra/run-registered-suites.sh` — the authoritative infra gate (~25 min),
   confirms zero orphans (TR6).
6. `bash scripts/test-all.sh`.

## Files to Edit

- `apps/web-platform/infra/variables.tf` — FR1, FR5 *(fetch `origin/main` first, TR7)*
- `apps/web-platform/infra/git-data.tf` — FR2, FR3, FR6, FR6b, FR7 + templatefile map
- `apps/web-platform/infra/cloud-init-git-data.yml` — FR4
- `.github/workflows/infra-validation.yml` — register the new suite (FR11)
- `knowledge-base/operations/expenses.md` — FR8
- `knowledge-base/engineering/architecture/decisions/ADR-143-active-active-web-ingress-drain-gated-host-lifecycle.md` — FR9
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` — FR10 (optional accuracy entries)

## Files to Create

- `apps/web-platform/infra/git-data-host.test.sh` — FR11

**Explicitly NOT edited:** `plugins/soleur/test/terraform-target-parity.test.ts` (see Research
Reconciliation), `git-data-luks.tf`, `git-data-cutover.sh`, any volume or LUKS resource (D10, TR2).

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `grep -c 'default *= *"cpx22"' apps/web-platform/infra/variables.tf` ≥ 1 within the
  `git_data_server_type` block.
- **AC2** — `grep -c 'linux_arm64\|linux_amd64' apps/web-platform/infra/cloud-init-git-data.yml` == 0.
- **AC3** — `grep -cE 'DOPPLER_SHA256="[0-9a-f]{64}"' apps/web-platform/infra/cloud-init-git-data.yml` == 0.
- **AC4** — `local.git_data_arch` and `local.git_data_doppler_sha256` exist in `git-data.tf`, and the
  templatefile map passes `doppler_arch` + `doppler_sha256`.
- **AC5** — `terraform validate` passes; `terraform plan` shows **no** change to
  `hcloud_volume.git_data`, `hcloud_volume.git_data_luks`, `random_password.git_data_luks`,
  `doppler_secret.git_data_luks_key`.
- **AC6** — a nonsense type (`cx99`) fails at **plan**, not after a destroy. Verify by temporarily
  setting `TF_VAR_git_data_server_type=cx99` and confirming plan aborts.
- **AC7** — `bash apps/web-platform/infra/git-data-host.test.sh` exits 0, and the suite appears in
  `.github/workflows/infra-validation.yml`.
- **AC8** — `bash apps/web-platform/infra/run-registered-suites.sh` reports **zero orphans**.
- **AC9** — `cloud-init-user-data-size.test.ts` passes: render `< GIT_DATA_BUDGET (28_000)` and
  `> GIT_DATA_FLOOR (10_000)`.
- **AC10** — expenses row 19 reads CPX22 / ~21.05 / `approved-not-billing`, with a `verify_by` marker.
- **AC11** — ADR-143 carries a dated addendum recording D1–D10, **and** its "Not changed by this
  addendum" paragraph no longer claims `git_data_server_type` keeps an unorderable default.
- **AC12** — PR body carries the brainstorm's Premise Corrections table (the falsified account-cap
  and freed-slot claims), so the stale framing is not re-imported downstream.
- **AC13** — every `knowledge-base/` path cited in this plan resolves:
  `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN: {}'`

### Post-merge (operator)

None. The birth is a separate gated `workflow_dispatch` tracked by the downstream chain in the spec
— it is deliberately **not** an acceptance criterion of this PR.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/variables.tf` (default + validation), `git-data.tf` (2 locals, 1 data
source, 2 templatefile args, 1 comment), `cloud-init-git-data.yml` (2 interpolations). Provider
`hetznercloud/hcloud` v1.63.0 (`~> 1.49`). **No new variable, no new secret, no new
`TF_VAR_*`** — so `hr-tf-variable-no-operator-mint-default` does not fire and there is no
merge-blocking Doppler provisioning precondition.

### Apply path

**None in this PR.** git-data resources are `OPERATOR_APPLIED_EXCLUSIONS` (ADR-103) and excluded
from the per-PR `-target=` list, so the merge-triggered auto-apply does not touch them. The change
takes effect at the next `apply_target=git-data-host-replace` dispatch or at first birth. Expected
downtime: zero (the host does not exist).

### Distinctness / drift safeguards

No `dev`/`prd` divergence (single infra root). No `lifecycle.ignore_changes` added — git-data
deliberately omits it (`git-data.tf:185`) to preserve a clean replace-to-reprovision path. The new
`data` source is read-only and creates nothing.

### Vendor-tier reality check

`cpx22` is a standard shared-vCPU type, no tier gate. Account limit is 10 servers with 5 running —
five free slots, so the additive birth has headroom (contra the issue's stale "cap is 5").

## Observability

This PR changes no runtime error path — the affected host does not exist. The declaration below is
the honest current state, not a new instrumentation surface.

```yaml
liveness_signal:
  what: betteruptime_heartbeat.git_data_prd (armed at 230s, apply-web-platform-infra.yml:976)
  cadence: 60s expected / 180s grace
  alert_target: Better Stack
  configured_in: apps/web-platform/infra/git-data.tf + apply-web-platform-infra.yml
error_reporting:
  destination: cloud-init failure is fail-closed at boot — `sha256sum -c -` aborts the Doppler
    install, and git-data-bootstrap.sh fails loud on any unmet invariant
  fail_loud: true
failure_modes:
  - mode: wrong-arch Doppler binary selected (the defect this PR structurally prevents)
    detection: sha256sum -c fails at cloud-init → bootstrap never reaches LUKS open →
      web-host-driven readiness check finds no git/bare-repo and blocks cutover
    alert_route: cutover precondition abort (git-data-cutover.sh preconditions())
  - mode: declared type left the orderable set
    detection: stock-preflight-gate.sh at dispatch; data.hcloud_server_type at plan (FR6)
    alert_route: apply aborts before any destroy
logs:
  where: host journald → Vector → Better Stack (post-birth only)
  retention: Better Stack default
discoverability_test:
  command: cd apps/web-platform/infra && terraform plan  # no ssh
  expected_output: hcloud_server.git_data planned with server_type = "cpx22"
```

**Known gaps, tracked not fixed here:** #6975 (the git-data heartbeat key is unsuffixed, so a
healthy web-1 probe masks a dead web-2 path) and #6548 (`git_data_prd` never unpaused, absent from
live Better Stack). Both gate the **birth**, not this repin. Per §2.9.2 the git-data host is a blind
surface; #6975 is precisely the in-surface discriminating probe that gap calls for.

## Encryption Posture

No store and no cross-component connection is introduced; both volumes are untouched (TR2). Posture
is restated for continuity because the file-pattern trigger fires.

```yaml
at_rest:
  - store: hcloud_volume.git_data_luks
    mechanism: guest-side LUKS2 (cryptsetup, not an hcloud attribute)
    evidence: cloud-init-git-data.yml:159-170; encryption-posture-audit-2026-07-23.md:35 "conforming"
    defends_against: disk seizure / vendor-side media access at rest
    does_not_defend: a live host with the mapper open; anyone holding GIT_DATA_LUKS_KEY
    disclosed_as: encryption-at-rest for user git-data (ADR-068 §3.D, NFR-027)
    live_verification: unmeasured — the host has never existed
  - store: hcloud_volume.git_data (plaintext ext4)
    mechanism: plaintext-exception
    evidence: encryption-posture-audit-2026-07-23.md:37
    defends_against: nothing
    does_not_defend: any at-rest threat
    disclosed_as: cutover source / rollback backstop
    live_verification: n/a — never provisioned
in_transit:
  - connection: web host → git-data bare repos
    tls: SSH (ED25519, private-net only; public ingress deny-all)
    cert_verification: TOFU — tracked by #5914, not changed here
    does_not_defend: a compromised web host with the transport key
    disclosed_as: private-net git transport (ADR-068 §6)
exception:
  justification: >
    The plaintext volume is a cutover artifact that can never hold user data — every git-data write
    path is gated on isGitDataStoreEnabled(), and git-data-cutover.sh preconditions() refuses to run
    unless that flag is OFF, setting it true only as its final step after repoint_luks_mount. This
    was settled as brainstorm D10; born-on-LUKS was considered and rejected.
  tracking_issue: "#6976"
  reevaluate_when: the git-data host is born
  expires_on: 2026-10-31
```

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-143** with a dated addendum (D8 — no new ordinal allocated, TR8). It must record D1–D10
**and** correct the closing paragraph that currently asserts `var.git_data_server_type` keeps its
unorderable default. ADR-143:149 already names #6570 as the owner of this decision, so this is the
handoff that ADR anticipated.

### C4 views

**No C4 change required** — supported by an explicit enumeration against all three
`knowledge-base/engineering/architecture/diagrams/*.c4` files:

- **(a) External human actors:** none added or changed. A server-type repin introduces no actor.
- **(b) External systems / vendors:** none new. Hetzner is already the `hetzner` container's
  `technology`. The Doppler CLI GitHub-release download is pre-existing egress, and is not modeled
  as an edge for *any* host (inngest and registry perform the identical download and carry no such
  element).
- **(c) Containers / data stores touched:** none. `hcloud_volume.git_data*` are untouched (TR2), and
  neither is a C4 element — the only modeled volume is `workspacesVolume`, which is the **web
  host's** `/workspaces`, not git-data's store.
- **(d) Access relationships:** none change.

Additionally verified: **no `cax11`, `Ampere`, or `ARM-native` claim exists in any `.c4` file**, so
this PR falsifies no modeled description. The only `arm64` occurrence is `model.c4:433`, the
inngest→Better Stack Vector edge, which is unrelated. `model.c4:180`'s DR-gap list (web-1 `cx33`,
grok-dogfood `cx33`, registry `cx23`) correctly omits git-data because it names *running* hosts —
and this PR moves git-data's declared type into the orderable set, so that list stays accurate.

## Domain Review

**Domains relevant:** Engineering, Finance, Legal (carried forward from the brainstorm's
`## Domain Assessments`).

**Not spawned.** This session runs under a standing operator instruction against invoking subagents,
so neither the Phase 2.5 domain-leader Tasks nor the Step 4.5 advisor consult nor the plan-review
panel were spawned. The assessments below are the orchestrator's, recorded honestly as such rather
than presented as leader sign-off. **This is the main quality caveat on this plan** — the 3–5 agent
plan-review panel that normally catches phase-ordering and AC-verifiability defects did not run.

### Engineering

**Status:** reviewed (inline). Three files plus a new test suite, with two in-repo precedents copied
verbatim. The only genuinely novel element is FR6's plan-time tripwire. Chief mechanical risk is the
`$${DOPPLER_VERSION}` vs `${doppler_arch}` escaping distinction in the cloud-init.

### Finance

**Status:** reviewed (inline). +€13.50/mo net vs the voided ARM pin (~+$14.60 at ~1.08 FX). Not yet
burn — the row stays `approved-not-billing` until the gated birth. The cheaper `cx23` alternative
was rejected on stock durability, so the increase is a deliberate purchase of orderability.

### Legal

**Status:** reviewed (inline). No new sub-processor; same Hetzner account and DPA. `hel1` preserves
EU residency (CLO T-1). LUKS-at-rest posture unchanged by construction (TR2).

### Product/UX Gate

Not applicable — no path in Files to Edit/Create matches any UI-surface term or glob. Tier: NONE.

## Open Code-Review Overlap

**None.** Queried `gh issue list --label code-review --state open --limit 200` and matched every
planned file path (`infra/variables.tf`, `infra/git-data.tf`, `cloud-init-git-data.yml`,
`expenses.md`) against issue bodies — zero hits.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `$${DOPPLER_VERSION}` escaping broken while adding `${doppler_arch}` — renders a literal `${...}` or fails templatefile | `terraform validate` + `.github/scripts/validate-infra-templates.sh`, which discovers templates structurally from `templatefile()` calls and renders them. AC2/AC3 greps. |
| amd64 checksum wrong → host boots with no LUKS passphrase access | Reused verbatim from two live hosts; git-data's own current arm64 literal is byte-identical to inngest's, proving same-version provenance. `sha256sum -c -` fails closed at boot. |
| `cpx22` leaves the orderable set before the birth | `stock-preflight-gate.sh` re-probes live at dispatch. `cpx*`/`ccx*` were stably orderable in all 3 DCs across both recorded probes. |
| FR6's data source 403s or the API is unreachable → **every** plan of this root fails | `zot-registry.tf:134` already takes this dependency and is green, so the token demonstrably reads server types. Precedent, not a new risk. |
| Reviewer reads this as authorizing the birth | NG1 in the spec, D9 in the brainstorm, and "Post-merge (operator): None" above. |
| Plan-review panel did not run (no subagents) | Stated plainly in §Domain Review. Offer the panel before `/work` if the operator wants it. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or
  `/work`.
- **`$${VAR}` vs `${VAR}` in `cloud-init-git-data.yml` is the highest-risk edit in this PR.** Double-`$`
  is a **shell** variable that Terraform must pass through literally; single-`$` is a Terraform
  interpolation that must have a matching templatefile map key. `DOPPLER_VERSION` stays double;
  `doppler_arch` and `doppler_sha256` are single.
- **FR6b (`lifecycle.precondition` cross-checking `local.git_data_arch` against
  `data.hcloud_server_type.git_data.architecture`) is beyond the brainstorm's D1–D10 and is marked
  `automation-status: UNVERIFIED`.** The `architecture` attribute is expected on hcloud provider
  v1.63.0 but was **not** verified against the installed provider schema at plan time. Phase 0 step 3
  must verify it; if absent, **drop FR6b** rather than improvising. Reviewers may cut it as scope
  creep without affecting D1–D10.
- The new `data "hcloud_server_type" "git_data"` is a **pure tripwire** — nothing references its
  output (unlike `zot-registry.tf`, whose data source feeds `local.registry_memory_cap_mb`).
  Terraform still reads unreferenced data sources at plan time, so the tripwire works, but a future
  "unused data source" cleanup could delete it and silently remove the guard. FR6b, if kept, makes it
  load-bearing and immune to that.
