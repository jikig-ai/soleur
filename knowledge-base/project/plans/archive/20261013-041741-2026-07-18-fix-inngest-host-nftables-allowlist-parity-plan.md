---
title: "fix(infra): inngest-host nftables allowlist parity — drop stale 10.0.1.11, add var.web_hosts drift guard (#6608), reconcile #6197 as already-delivered"
date: 2026-07-18
type: fix
lane: single-domain
brand_survival_threshold: none
issues: ["#6608", "#6197"]
epic: "#6178 (HELD)"
---

# fix(infra): inngest-host nftables allowlist parity (#6608) + #6197 reconciliation

## Enhancement Summary

**Deepened on:** 2026-07-18
**Sections enhanced:** Research Reconciliation, Apply path, Downtime & Cutover (added), Observability.
**Verification performed (live, this pass):** PR citations #6209/#6631/#6651 confirmed MERGED;
issues #6538 CLOSED, #6178/#6608/#6197 OPEN; the `vinngest-v1.1.23` OCI tag confirmed to carry the
arm64 Vector (`aarch64`) + `BETTERSTACK_LOGS_TOKEN` bootstrap/cloud-init changes (per the
"image-baked is a claim" learning); the `inngest-host-replace` dispatch confirmed at
`apply-web-platform-infra.yml:92/101/1602` (scoped `-replace`, AOF-preserving, menu-ack); the
parity-test precedent read verbatim at `cutover-inngest-workflow.test.sh:184-199`; the co-edit
target confirmed at `inngest-host.test.sh:91` (hardcodes the stale literal, `grep -Fc '10\.0\.1\.11'`
== 1 pre-fix).

### Key findings
1. **#6197 is a stale premise — already fully delivered.** Code (PR #6209) + hardening (#6631) +
   OCI bake `v1.1.23` (#6651) are all merged; the tag carries them. This plan touches zero
   Vector/BetterStack files. Persisted as a headless decision-challenge (`decision-challenges.md`).
2. **This PR is #6608 only** — a `user_data`-ForceNew literal fix + a drift-parity guard. No bundle.
3. **Sibling test co-edit is mandatory** (`inngest-host.test.sh:91` hardcodes the stale value) — the
   parity guard replaces it, so no vacuous double-literal.
4. **Merge is inert; apply folds into the HELD Phase-2 cutover** (`inngest-host.tf` resources are
   excluded from per-PR CI `-target`). `Ref #6608` (ops-remediation), close at Phase-2.

### Gate results
- 4.6 User-Brand Impact: PASS (threshold `none` + scope-out reason for the `apps/*/infra/` path).
- 4.7 Observability: PASS (5 fields, no-ssh discoverability_test).
- 4.8 PAT-shaped-var halt: PASS — the lone regex hit is `var.betterstack_logs_token`, a Better Stack
  logs ingest token (not a GitHub PAT) that pre-exists on main and is *not* introduced here; the
  `hr-github-app-auth-not-pat` intent (GitHub infra-write auth) does not apply.
- 4.9 UI-wireframe halt: N/A (no UI surface).
- 4.55 Downtime & Cutover: fired (hcloud_server replace) → `## Downtime & Cutover` added; defaults to
  zero-downtime (dark host, AOF-preserving, folds into Phase-2). Telemetry emitted.
- 4.5 Network-outage: keyword `firewall`/`nftables` matched → N/A (proactive allowlist edit, not an
  outage diagnosis; no sshd/fail2ban fix proposed). Telemetry emitted.

## Overview

Two pre-cutover hardening items for the dedicated Inngest host (`10.0.1.40`, arm64 `cax11`,
singleton per ADR-100). The cutover (epic **#6178**) is **HELD**; these are its remaining
pre-window items.

- **#6608 (P2) — real code work.** `apps/web-platform/infra/inngest-host.tf:40` hardcodes
  `web_host_private_ips = "10.0.1.10,10.0.1.11"`, rendered into the dedicated host's nftables
  `ip saddr { … }` allowlist for the `:8288`/`:8289` control API (SEC-H2). web-2 (`10.0.1.11`) was
  retired + destroyed 2026-07-17 (#6538) and `var.web_hosts` is now web-1-only (`10.0.1.10`). So
  `.11` is a **stale grant** that would auto-re-grant if Hetzner reallocates `10.0.1.11`. The
  literal has **no edge to `var.web_hosts`**, so the derivation sweep and the two existing
  roster-parity tests (`web-hosts-fanout-parity.test.sh`, `cutover-inngest-workflow.test.sh`) miss
  it. Fix: change the literal to `"10.0.1.10"` and add a parity guard scanning the literal against
  `var.web_hosts` (mirroring `cutover-inngest-workflow.test.sh`'s FIX-H1 scan).

- **#6197 (P3) — NO code work; already delivered.** Premise validation (below) found #6197's arm64
  Vector shipper + `BETTERSTACK_LOGS_TOKEN` provisioning were **fully implemented by PR #6209**
  (merged 2026-07-07), hardened by #6631, and **baked into the OCI image `v1.1.23`** (rebaked by
  #6651, 2026-07-18 — verified the tag carries the change). This plan does **not** touch the Vector
  surface. #6197's only remaining item is the HELD Phase-2 host re-provision (epic #6178).

**Bundle-vs-split decision:** Not a bundle. #6608 contributes the only code (a `user_data`
ForceNew literal + a test); #6197 contributes zero code (its OCI + Doppler delivery is complete).
The two *converge* on one eventual host re-provision — #6608's corrected literal and #6197's
already-merged wiring both land at the next `inngest-host` replace/provision — but they are not
bundled in a code sense. This PR ships #6608's code (inert on merge); its apply, like #6197's,
rides the HELD Phase-2 cutover re-provision.

## Research Reconciliation — Task Framing vs. Codebase Reality

| Framing (task input) | Reality (measured 2026-07-18) | Plan response |
|---|---|---|
| #6197: "inngest bootstrap Vector path is x86_64-hardcoded; add aarch64 URL + arm64 SHA + checksum override" | `inngest-bootstrap.sh:731-737` is **arch-parameterized** (`arm64) vec_triple="aarch64-unknown-linux-musl"`); `vector.tf:22` pins `vector_sha256_arm64`; threaded through `inngest-host.tf:243` + cloud-init `VECTOR_CLI_SHA256`. Landed by **PR #6209** (2026-07-07). | **No change.** Re-implementing = stale-premise trap (#6497 class). |
| #6197: "provision BETTERSTACK_LOGS_TOKEN into soleur-inngest Doppler project (currently only in web-platform)" | `inngest-betterstack-token.tf` already provisions `doppler_secret.inngest_betterstack_logs_token` into `soleur-inngest/prd`; `var.betterstack_logs_token` declared (variables.tf:348); `TF_VAR_betterstack_logs_token` gate in `soleur/prd_terraform` documented "already satisfied" (PR #6209). | **No change.** |
| #6197: "likely needs an OCI image rebake + OCI pin bump" | OCI image **already rebaked to `v1.1.23`** by PR #6651 (2026-07-18). Verified `vinngest-v1.1.23` tag carries arm64 Vector (`aarch64` ×1), `BETTERSTACK_LOGS_TOKEN` (bootstrap ×2, cloud-init allowlist ×6); #6631 is an ancestor of the tag. | **No rebake needed.** |
| #6197: still OPEN → work remaining | PR #6209 was `Ref #6197` (not `Closes`); #6197 stays open **only** as the Phase-2 re-provision tracker (gate on HELD #6178). | Keep #6197 open; record reconciliation. Do **not** close (host not yet re-provisioned). |
| #6608: literal `"10.0.1.10,10.0.1.11"` still stale | **Confirmed** `inngest-host.tf:40` still has both IPs; `var.web_hosts` default = `{web-1 = 10.0.1.10}` only. | **Fix the literal + add parity guard.** |
| (sibling) `inngest-host.test.sh:91` | **Hardcodes the stale value** in an assertion (`web_host_private_ips…"10\.0\.1\.10,10\.0\.1\.11"`). Changing the literal **fails this test**. | Required co-edit — replace the hardcoded grep with the derived parity guard (see Files to Edit). |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing during Phase-1 — the dedicated host is
DARK/inert (zero prod crons). A *wrong* edit (e.g. dropping `.10`/web-1 instead of `.11`) would, at
the Phase-2 cutover, leave web-1 unable to reach the `:8288` control API → `/api/inngest` fanout
fails → crons (email-triage, reminders) stall. This is caught pre-merge by the new parity test
(`literal == var.web_hosts`) and pre-cutover by `inngest-host.test.sh` + the Phase-2 pre-flight.

**If this leaks, the user's data is exposed via:** N/A — the change *removes* an over-broad grant
(a retired host's private IP) from a host-local firewall allowlist. It narrows, never widens, the
`:8288` attack surface. No end-user data surface is touched.

**Brand-survival threshold:** none

threshold: none, reason: a private-network nftables allowlist correction on a DARK/inert arm64
host with no end-user data surface; a wrong edit is caught pre-merge by the new `literal ==
var.web_hosts` parity test and pre-cutover by the arm64 host test suite, and the change only
narrows the control-API grant.

## Files to Edit

1. **`apps/web-platform/infra/inngest-host.tf`** (line 40) — change
   `web_host_private_ips = "10.0.1.10,10.0.1.11"` → `web_host_private_ips = "10.0.1.10"`. Keep the
   surrounding SEC-H2 comment; update it to note the single-host roster + the #6538 web-2
   retirement + `#6608` (and that the value is now guarded by the parity test below).

2. **`apps/web-platform/infra/inngest-host.test.sh`** (lines ~88-96) — the assertion at line 91
   hardcodes `"10\.0\.1\.10,10\.0\.1\.11"`. Replace it with:
   - a grep asserting the literal is the single-host set `"10.0.1.10"` (or, better, that it does not
     contain `.11`), AND
   - **the new parity guard** mirroring `cutover-inngest-workflow.test.sh:184-199`: derive the
     literal's IP set from `inngest-host.tf`, derive the canonical set from `variables.tf`
     `web_hosts` `private_ip` entries (`grep -oE 'private_ip[[:space:]]*=[[:space:]]*"10\.0\.1\.[0-9]+"'
     … | grep -oE '10\.0\.1\.[0-9]+' | sort -u | paste -sd,`), and `assert` the two sorted sets are
     byte-identical. Keep the existing `.20`/`.30` exclusion assertion (lines 95-96) — it is
     complementary (git-data/registry must never be in the allowlist).
   - The test is already registered (`infra-validation.yml:535` → `bash …/inngest-host.test.sh`),
     so **no new registration** is needed. (An `inngest-host.test.sh` line is *not* in
     `scripts/test-all.sh`; the infra suites run via `infra-validation.yml`, not `test-all.sh` —
     do not add a `test-all.sh` entry.)

3. **`apps/web-platform/infra/inngest-host.tf`** SEC-H2 comment (lines ~35-40) — one-line note that
   the literal is now drift-guarded by the parity test (kills the "no edge to var.web_hosts" gap
   the issue calls out).

4. **`knowledge-base/engineering/operations/runbooks/inngest-server.md`** — add a short subsection
   under the existing `inngest-host-replace` material documenting the #6608 remediation apply path
   (see `## Infrastructure (IaC)` → Apply path) and the **no-SSH** post-apply verification of the
   rendered nftables set (via the Vector journald→Better Stack shipper / boot marker — NOT ssh).
   Keep it a runbook note, not a ship-time operator checklist.

## Files to Create

None. (No new test file — the parity guard folds into the already-registered `inngest-host.test.sh`.
No new ADR — see Architecture Decision below.)

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` — no open scope-out names
`inngest-host.tf`, `inngest-host.test.sh`, or `inngest-server.md`.

## Implementation Phases

### Phase 0 — Preconditions (read-only)
- Confirm `inngest-host.tf:40` literal is still `"10.0.1.10,10.0.1.11"` and `var.web_hosts` default
  is web-1-only (`git show origin/main:apps/web-platform/infra/variables.tf`).
- Confirm `inngest-host.test.sh:91` still hardcodes the stale value (the co-edit target).
- (Optional, informs apply-path sequencing) Determine whether `hcloud_server.inngest` is currently
  provisioned and whether `10.0.1.11` has been reallocated to a live host — read-only, via the
  drift-detector output / Hetzner API. If unprovisioned → delivery is fully latent. If provisioned
  dark → delivery rides Phase-2 (default) unless `.11` is reallocated (then immediate dispatch).

### Phase 1 — Fix the literal (RED→GREEN)
- **RED:** update `inngest-host.test.sh` first — add the parity guard + single-host assertion; run
  `bash apps/web-platform/infra/inngest-host.test.sh` and confirm it FAILS against the current
  stale `.10,.11` literal (proves the guard bites).
- **GREEN:** change `inngest-host.tf:40` to `"10.0.1.10"`; update the SEC-H2 comment; re-run the
  test → all pass.

### Phase 2 — Validate + docs
- `terraform -chdir=apps/web-platform/infra fmt -check` and `terraform validate` (no behavior
  change; a literal edit).
- Add the runbook remediation note (Files to Edit #4).
- Re-run the sibling parity tests that DO scan `var.web_hosts` to confirm no regression:
  `bash apps/web-platform/infra/web-hosts-fanout-parity.test.sh` and
  `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh`.

### Phase 3 — Merge is inert; delivery is deferred to Phase-2 cutover
- `inngest-host.tf` resources are **excluded from per-PR CI `-target`** (apply-web-platform-infra.yml
  strips the `inngest-host` dispatch targets; a plan that would create/replace `hcloud_server.inngest`
  HALTs the per-merge apply). So the corrected literal is **not applied at merge**.
- The apply rides the HELD Phase-2 cutover re-provision (see Apply path). No new operator step is
  introduced by this PR.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `inngest-host.tf` `web_host_private_ips` literal == `"10.0.1.10"` — verify:
      `grep -c 'web_host_private_ips[[:space:]]*=[[:space:]]*"10\.0\.1\.10"' apps/web-platform/infra/inngest-host.tf` == 1
      AND `grep -c '10\.0\.1\.11' apps/web-platform/infra/inngest-host.tf` == 0.
- [ ] `inngest-host.test.sh` no longer hardcodes the two-host literal. NOTE: the test stores the
      value as a *regex* (`10\.0\.1\.11` with literal backslashes), so a naive
      `grep -c '10\.0\.1\.10,10\.0\.1\.11'` returns 0 even on the STALE file (vacuous — the
      AC-self-reference-grep trap). Use fixed-string matching:
      `grep -Fc '10\.0\.1\.11' apps/web-platform/infra/inngest-host.test.sh` == 0 (was 1 pre-fix),
      AND the parity assertion below is present.
- [ ] The parity guard is present and derives the canonical set from `variables.tf` `web_hosts`
      `private_ip` (not a hardcoded second literal): `inngest-host.test.sh` contains a `grep -oE`
      over `variables.tf` `private_ip` AND an `assert` that the literal's sorted IP set ==
      the derived canonical set.
- [ ] `bash apps/web-platform/infra/inngest-host.test.sh` exits 0 (all assertions pass, incl. the new
      parity assertion and the retained `.20`/`.30` exclusion).
- [ ] Non-vacuity: temporarily re-adding `,10.0.1.11` to the literal makes the parity assertion FAIL
      (documented in the PR body; revert before merge).
- [ ] `bash apps/web-platform/infra/web-hosts-fanout-parity.test.sh` and
      `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` still pass (no regression).
- [ ] `terraform -chdir=apps/web-platform/infra fmt -check` + `validate` clean.
- [ ] PR body uses `Ref #6608` (ops-remediation class — actual nftables re-render applies
      post-merge at Phase-2), and documents that the apply goes through the
      `apply_target=inngest-host-replace` dispatch / Phase-2 re-provision, NOT a routine apply.
- [ ] PR body records the #6197 reconciliation (already delivered by #6209/#6631/#6651; no code
      here) and does NOT close #6197.

### Post-merge (operator / HELD Phase-2)
- [ ] `Automation: not feasible because` the apply is a prod re-provision of the SOLE Inngest
      scheduler, gated on the HELD epic #6178 maintenance window. `automation-status: the
      inngest-host-replace dispatch itself IS automatable (`gh workflow run
      apply-web-platform-infra.yml -f apply_target=inngest-host-replace`) but must NOT fire outside
      the signed-off Phase-2 window` — folded into the Phase-2 cutover, not a separate step.
- [ ] At Phase-2 re-provision: the rendered nftables `ip saddr` set no longer contains `.11` and the
      `:8288`/`:8289` control API still accepts from web-1 (`10.0.1.10`) — verified **no-SSH** via
      the Vector journald→Better Stack boot marker / `inngest-registry-probe.sh`-class check, then
      `gh issue close 6608`.

## Domain Review

**Domains relevant:** Engineering/Infra only.

### Engineering / Infra
**Status:** reviewed (inline)
**Assessment:** Single-domain Terraform drift-fix on `apps/web-platform/infra/`. No product/UI
surface (no `components/**`, `app/**/page.tsx`). No regulated-data surface (nftables allowlist of a
private IP — no schema/auth/API/`.sql`; GDPR gate does not fire). No new vendor, secret, or runtime
process. The change narrows a security boundary (SEC-H2) and adds a permanent drift guard.

### Product/UX Gate
Not relevant — no UI surface in Files to Edit. NONE.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/inngest-host.tf` — `local.web_host_private_ips` literal (`.10,.11` →
  `.10`). No new resource, variable, provider, or version pin. The value is consumed at
  `inngest-host.tf:253` and rendered into `cloud-init-inngest.yml`'s nftables `ip saddr { … }` via
  `templatefile` → `user_data`.
- `apps/web-platform/infra/inngest-host.test.sh` — parity guard (source-scan test; no infra).
- No `TF_VAR_*` / Doppler / secret changes.

### Apply path
**(b) cloud-init `user_data` ForceNew replace — deferred/latent.** The literal is baked into
`user_data` via `templatefile`; `hcloud_server.inngest` has a **deliberate NO
`lifecycle.ignore_changes=[user_data]`** (inngest-host.tf comment ~L262), so the edit
**force-replaces** the host. The resource is **excluded from per-PR CI `-target`** → **merge is
inert** (no apply at merge; a per-merge plan that would replace the host HALTs). Delivery options:
- **Recommended — fold into the HELD Phase-2 cutover re-provision.** The same
  `apply_target=inngest-host-replace` (or the Phase-2 provision) that delivers #6197's already-merged
  wiring re-renders nftables from the corrected literal. No separate maintenance window, no new
  operator step. `inngest-host-replace` (apply-web-platform-infra.yml:1609-1766) is scoped
  (`-replace=hcloud_server.inngest` + `-target` server/network/volume_attachment), **AOF-volume
  preserving** (`hcloud_volume.inngest_redis` deliberately NOT targeted; pre-apply
  `inngest_host_replace_gate` + post-apply 0-delete backstop), **menu-ack** authorized (no
  environment reviewer; `hr-menu-option-ack-not-prod-write-auth`).
- **Escape hatch — immediate dispatch** only if a read-only check shows `10.0.1.11` reallocated to a
  live host before Phase-2.

**Expected downtime / blast-radius:** zero prod-downtime — the host is DARK/inert (zero prod crons)
during Phase-1. The AOF volume survives the replace. Immutable-redeploy caveat
(`2026-07-07-immutable-redeploy.md`): a fresh host may boot with the private NIC down needing a soft
reboot — a reason to verify inside the Phase-2 window rather than a gratuitous immediate replace.

### Distinctness / drift safeguards
The **new parity test** IS the drift safeguard: `inngest-host.tf`'s literal must equal the
`var.web_hosts` `private_ip` set, closing the "no edge to `var.web_hosts`" gap the issue names. No
`lifecycle.ignore_changes` change. dev is not involved (the host reads `--config prd` only;
`hr-dev-prd-distinct`).

### Vendor-tier reality check
N/A — no new vendor resource.

## Downtime & Cutover

**Trigger:** the literal edit force-replaces `hcloud_server.inngest` (a `-/+` on an `hcloud_server`),
so the downtime gate fires mechanically.

**Offline-inducing operation + surface:** a scoped `-replace` of the dedicated Inngest host (re-runs
cloud-init to re-render nftables). **Surface affected: none that is serving.** During Phase-1 the
dedicated host is **DARK/inert** — it fires zero prod crons (born on a distinct non-prod Postgres,
empty function registry, ADR-100 AC-DARK). The live Inngest control plane during this window is the
**co-located** web-host scheduler, which this replace does not touch.

**Zero-downtime path (default, and the case here by construction):**
- The replace targets an **inert** host → **zero prod-downtime** by construction; no drain needed.
- The durable **Redis AOF volume survives** the replace (`hcloud_volume.inngest_redis` deliberately
  NOT targeted; pre-apply `inngest_host_replace_gate` + post-apply 0-delete backstop enforce it).
- Delivery **folds into the already blue-green Phase-2 cutover** (a fresh host is born into the
  topology, the co-located pusher is quiesced, the Postgres URI is flipped) — no *separate* window.
- Residual: the immutable-redeploy NIC caveat (`2026-07-07-immutable-redeploy.md`) — a fresh host may
  boot with the private NIC down needing a soft reboot; verified inside the Phase-2 window (a reason
  to fold rather than dispatch a gratuitous immediate replace).

**Residual downtime accepted:** none. No maintenance window is introduced by *this PR* (merge is
inert); the eventual apply rides the HELD Phase-2 cutover window that epic #6178 already owns.

## Observability

```yaml
liveness_signal:
  what: dedicated-host heartbeat push (betteruptime_heartbeat.inngest_prd) + scheduled-inngest-health.yml P1 census — UNCHANGED by this PR
  cadence: 60s heartbeat; */15 health census
  alert_target: Better Stack heartbeat monitor + scheduled-inngest-health.yml P1 path
  configured_in: inngest.tf (heartbeat) / .github/workflows/scheduled-inngest-health.yml
error_reporting:
  destination: CI (infra-validation.yml) — the new parity assertion red-lines on any roster drift; post-apply nftables render is observable via the Vector journald→Better Stack shipper (#6197, already delivered) + the baked boot marker
  fail_loud: yes — CI fails pre-merge on drift; a boot-time render failure emits to Better Stack Logs (source 2457081)
failure_modes:
  - mode: wrong edit drops 10.0.1.10 (web-1) instead of 10.0.1.11 → control API rejects web-1 → /api/inngest fanout fails at cutover
    detection: new parity assertion (literal == var.web_hosts) in inngest-host.test.sh
    alert_route: CI red pre-merge (infra-validation.yml)
  - mode: stale 10.0.1.11 re-granted (or a future roster copy drifts) after Hetzner reallocation
    detection: same parity assertion — literal must equal var.web_hosts at all times
    alert_route: CI red pre-merge
  - mode: post-replace host boots with private NIC down (immutable-redeploy)
    detection: Phase-2 pre-flight NIC/registry-empty check + boot marker to Better Stack
    alert_route: Better Stack Logs / deploy-status endpoint (no-SSH)
logs:
  where: host journald → Vector → Better Stack Logs (source 2457081) once delivered at Phase-2; pre-Doppler boot marker via the baked betterstack_logs_token
  retention: Better Stack Logs default retention
discoverability_test:
  command: bash apps/web-platform/infra/inngest-host.test.sh   # NO ssh
  expected_output: all assertions pass, including the new "literal == var.web_hosts private_ip set" parity assertion; grep shows web_host_private_ips == "10.0.1.10" with no 10.0.1.11
```

## Architecture Decision (ADR/C4)

**No new ADR; no C4 change.** This is a drift-fix on an existing surface plus a test — not an
architectural decision. PR #6209 already amended **ADR-100** for the #6197 Vector caveat and added
the inngest→Better Stack C4 log-ship edge; nothing here supersedes or extends an ADR.

**C4 completeness check (all three model files read):**
- `model.c4` — `inngest` container (L189, "Dedicated Hetzner host, private-net 10.0.1.40:8288/:8289")
  and the `api -> inngest` `:8288` edge (L397) are unchanged; **web-2 retirement is already recorded
  in C4** (L385, L387: "web-2 was retired 2026-07-17 (#6538)"). No external human actor, external
  system/vendor, container/data-store, or actor↔surface access-relationship is added or removed —
  the nftables allowlist is a host-local firewall detail *below* the C4 abstraction; removing a
  retired host's IP adds/removes no C4 element.
- `views.c4` — L33 already includes `platform.infra.inngest`; no `include` line changes.
- `spec.c4` — no inngest actor/system entry; nothing to change.
- Conclusion: **no C4 impact**, verified against actors (none new/removed), systems (none), stores
  (none), and access relationships (none — the allowlist *narrows* an existing edge, not re-scopes a
  modeled relationship).

## Network-Outage Hypothesis Check (gate fired on "firewall"/"nftables")

The feature text matches `firewall`/`nftables`, firing plan Phase 1.4. **N/A for the L3→L7 diagnostic
order** — this is a *proactive allowlist correction*, not a diagnosis of an SSH/connectivity failure.
No sshd/fail2ban fix is proposed (`hr-ssh-diagnosis-verify-firewall` is satisfied vacuously). The
change itself edits the firewall allowlist; there is no outage to triage. Noted for the record.

## Sharp Edges

- **`inngest-host.test.sh:91` hardcodes the stale literal.** Changing `inngest-host.tf:40` without
  the co-edit fails CI. The parity guard must *replace* that hardcoded grep with a `var.web_hosts`-
  derived assertion — do not leave two hardcoded copies.
- **Merge is inert; do not "apply" at merge.** `inngest-host.tf` resources are excluded from per-PR
  CI `-target`; the corrected literal delivers only at a deliberate `inngest-host-replace` dispatch
  or the Phase-2 re-provision. Use `Ref #6608`, not `Closes` (ops-remediation class).
- **"#6197 needs implementing" is a stale premise.** Its code (arm64 Vector + BetterStack token) is
  merged (#6209/#6631) and baked into OCI `v1.1.23` (#6651, verified). Do not re-implement any of it
  — that is the #6497 false-premise trap. This plan touches zero Vector/BetterStack files.
- **A `## User-Brand Impact` section that is empty / `TBD` fails deepen-plan Phase 4.6.** It is filled
  (threshold `none` + reason).
- **No-SSH verification.** The host is deny-all-public; post-apply nftables verification must flow
  through the Vector→Better Stack shipper / boot marker / deploy-status, never ssh
  (`hr-no-ssh-fallback-in-runbooks`).
- **Immutable-redeploy NIC caveat.** A fresh host may boot with the private NIC down; verify inside
  the Phase-2 window (soft-reboot path), which is a reason to prefer folding over an immediate
  gratuitous replace.
