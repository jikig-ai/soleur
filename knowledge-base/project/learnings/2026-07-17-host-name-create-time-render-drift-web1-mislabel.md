---
title: "host_name telemetry drift is create-time-render, and the dedicated node's OS hostname ≠ its Hetzner resource name"
date: 2026-07-17
issue: 6616
tags: [observability, telemetry, better-stack, create-time-render, infra, identity-not-cardinality]
---

# host_name create-time-render drift (web-1 mislabel) — #6616

## The bug class: create-time-render drift on a long-lived host

A "per-host label injected at construction time" is **not** a runtime-guaranteed invariant. #6396
made Better Stack `host_name` derive per-host from a Terraform-injected value rendered into the
Vector config at cloud-init time. That fix is correct **for fresh hosts** — but a host that predates
the render and cannot re-run cloud-init keeps whatever it was rendered with.

web-1 booted in the pre-#6344 co-located-Inngest era, so it runs an **inngest-owned `vector.service`**
whose config was `sed`-rendered `host_name=soleur-inngest-prd` (`inngest-bootstrap.sh`). Because
`hcloud_server.web` carries `lifecycle{ignore_changes=[user_data]}`, web-1 never re-ran cloud-init to
pick up #6396's per-host name — and the web-install path's skip-guard refuses to re-render while the
inngest-owned unit exists. So web-1 ships its telemetry stamped `host_name=soleur-inngest-prd` while
its OS hostname (`host`, Vector auto-derived) is `soleur-web-platform` — colliding with the dedicated
Inngest node on the sole per-host discriminator in Better Stack source 2457081.

This is the **same class** the C4 model already documents for the #6425/#6594 tunnel-connector
coin-flip: *a construction-time gate presented as a runtime precondition — it governs only future
fresh hosts.* The remediation is the same: a C4/ADR caveat + a follow-through that enforces the live
invariant, **not** a templating change (the templating is already correct — touching it is a no-op).

The physical fix is a web-1 **immutable recreate** (SSH edits are forbidden per `AP-002`; there is no
`web-1-recreate` dispatch target; recreate is blocked — cx33 unorderable EU-wide, ADR-119 §(e)). So
#6616 ships diagnosis + record-correction + an **armed, read-only follow-through** that auto-closes it
once web-1 is eventually recreated (the GA blue-green host-replaceability work) and the label clears.

## The trap that live data caught: the plan pinned identity from the WRONG resource

The deepened plan pinned the dedicated node's telemetry `host` value as **`soleur-inngest-server-prd`**,
citing `inngest.tf:291`. **The live query refuted this** — `soleur-inngest-server-prd` never appears in
telemetry. The reason is a mis-sourced citation: `inngest.tf:291` is a **Better Stack heartbeat monitor**
(`resource "betteruptime_heartbeat" "inngest_prd" { name = "soleur-inngest-server-prd" }`), NOT a Hetzner
server. The actual Hetzner server is `hcloud_server.inngest` at **`inngest-host.tf:202`**, named
**`soleur-inngest`** — and Hetzner *does* seed the OS hostname from the server `name`, so the dedicated
node's telemetry `host` **equals** its `hcloud_server` name (the same rule `server.tf:225`'s own comment
documents for the web hosts). Had the plan read the `hcloud_server` resource instead of the
similarly-named heartbeat, it would have gotten `soleur-inngest` directly.

The correct value was confirmed independently by **service fingerprint**: a second content-keyed query
showed `host=soleur-inngest` ships the `inngest-heartbeat` service (×3726) plus `doppler`/`sshd`/`systemd`
— unmistakably the dedicated node.

**Lesson (a specific instance of `hr-when-a-plan-specifies-relative-paths-e-g`):** a plan-quoted identity
constant is a *precondition to verify*, not a fact — and verify it against the RIGHT resource. Pin a
host's telemetry identity from the `hcloud_server` resource that provisions it (its `name` = its OS
hostname), never from a similarly-named `betteruptime_heartbeat`/monitor/DNS resource that merely shares
a naming stem; then confirm against an **unforgeable content fingerprint** (the service only that host
runs) and the live telemetry.

## Identity, not cardinality — and why an allowlist was the wrong shape here

The check must key on **identity**, not a bare "≥2 distinct hosts wear the label" cardinality:
- A **single**-emitter mislabel (web-1 sole emitter, dedicated node momentarily silent) reads `1:1`
  yet is still wrong.
- A **schema-drift false-GREEN**: if Vector's `host` field is renamed/absent, `JSONExtractString`
  returns empty for every row and a naive check goes vacuously GREEN. Guard with a **positive
  schema-liveness marker** — require ≥1 row with the dedicated node's `host` present before any PASS.

But a **pure allowlist** ("PASS iff `soleur-inngest-prd` emitted only by the dedicated node") is *also*
wrong here: the dedicated node's own **generic early-boot rows** (`host=Ubuntu-2404-noble-64-minimal`,
kernel-only, a default Hetzner image hostname that reappears every reboot before the hostname is set)
would be counted as a non-dedicated emitter → **false-FAIL forever**. The faithful predicate is the one
the issue title names: **FAIL iff a known WEB-host identity (`soleur-web-platform`/`soleur-web-2`, from
`server.tf:225`) emits the Inngest label**, with the dedicated-node liveness marker gating PASS. This is
strictly better-scoped and aligns with the deliberate YAGNI descope of a generic multi-host detector.

## #6425 re-derivation: it did NOT depend on host_name

The issue worried that #6425's "false `inngest-down` alarms came from web-2" reading was poisoned by
this mislabel. It is **not**: #6425's attribution was via the Cloudflare connector **colo census**
(`model.c4`; #6425 body), which is `host_name`-independent (web-2 ships 0 lines to source 2457081
anyway). It stands unaffected. The genuinely suspect readings are any that treat a
`host_name=soleur-inngest-prd` row as *the dedicated Inngest host* — because ~75% of those rows in the
24h window are actually web-1.

## Session Errors

- **The correction narrative was itself mis-sourced (caught by review, not by me).** After the live
  query refuted the plan's `soleur-inngest-server-prd`, I documented the *reason* as "Hetzner resource
  name ≠ OS hostname," citing `inngest.tf:291` — and propagated that inverted lesson into the learning,
  `model.c4`, ADR-100, and the script comment before a `code-quality-analyst` review pass caught it.
  `inngest.tf:291` is a `betteruptime_heartbeat` monitor, not a Hetzner server; the real
  `hcloud_server.inngest` (`inngest-host.tf:202`) IS named `soleur-inngest` = the OS hostname, so the
  name→hostname rule *holds*. **Recovery:** rewrote the narrative across all 8 artifacts. **Prevention:**
  when documenting *why* a plan-pinned identity was wrong, resolve the citation to the exact resource
  TYPE (`grep -A2 'resource "hcloud_server"'`) before asserting a general lesson — a refuted value and a
  correct diagnosis of *why* are two separate claims, each needing its own verification (this is why the
  live diagnosis was right — service fingerprint — while the first written explanation was wrong).
- **Replicated IaC literals shipped without a parity guard (caught by review).** The three pinned
  constants (`soleur-inngest-prd`, the web identities) had only comment citations, no coupling. **Recovery:**
  added a mutation-proven parity battery. **Prevention:** the repo convention is explicit — any literal
  copied from IaC/SSOT into a guard needs a parity assertion in the same PR (`cq-cite-content-anchor-not-line-number`).
- **Editing `model.c4` without regenerating `model.likec4.json` (caught by the full-suite exit gate, twice).**
  **Recovery:** `bash scripts/regenerate-c4-model.sh`. **Prevention:** already enforced — `c4-model-freshness.test.sh`
  fails with the exact regen command; the lesson is to run `test-all.sh` (not just touched-file tests) as
  the Phase-2 exit gate, which is what surfaced it.
- **Forwarded from plan phase:** two `Write` "File has not been read yet" errors on existing files after a
  skill context reload; resolved by Read-then-Write (covered by `hr-always-read-a-file-before-editing-it`).

## Artifacts

- Follow-through: `scripts/followthroughs/hostname-mislabel-web1-6616.sh` (+ `.test.sh`, 7 arms) —
  read-only, rides the existing `scheduled-followthrough-sweeper.yml`.
- Record-correction: two `model.c4` edge edits (isolated→shared/collision; overclaim caveat), an
  ADR-100 create-time-render pointer, and this learning.
- Plan: `knowledge-base/project/plans/2026-07-17-fix-host-name-telemetry-mislabel-plan.md`.
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`.
