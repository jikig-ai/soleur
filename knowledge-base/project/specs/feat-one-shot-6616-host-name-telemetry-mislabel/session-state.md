# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-17-fix-host-name-telemetry-mislabel-plan.md
- Status: complete

### Errors
None. (Two Write calls initially returned "File has not been read yet" for existing files after the skill context reloaded; resolved by Read-then-Write.)

### Decisions
- Premise reframe: the issue's proposed remedy ("make host_name derive from host identity") already shipped in #6396/PR #6401. Real residual bug is create-time-render drift on long-lived web-1 (booted pre-#6344 co-located-Inngest era; runs inngest-owned vector.service labeled soleur-inngest-prd; ignore_changes=[user_data] + skip-guard block re-render).
- Cannot fix in-session; deferred + enrolled: relabeling web-1 needs an immutable recreate — no web-1-recreate dispatch target exists and recreate is independently blocked (cx33 unorderable, ADR-119). No SSH (AP-002). Plan delivers diagnosis + record-correction + armed closure follow-through.
- Identity, not cardinality: dedicated node has host=soleur-inngest-server-prd / host_name=soleur-inngest-prd by design — re-keyed on identity invariant from inngest.tf with positive schema-liveness guard (#5934).
- Collapsed standing detector into one read-only follow-through (−~1300 LOC): standalone alarm was born-firing / redundant. Dissent recorded in decision-challenges.md.
- Gates: IaC (no new Terraform), Observability (5-field ssh-free), User-Brand Impact, Downtime/Cutover (zero-downtime), Network-Outage (N/A), PAT-halt (clean), ADR/C4 all satisfied.

### Components Invoked
- Skills: soleur:plan (6616), soleur:deepen-plan
- Agents: Explore; review panel — architecture-strategist, observability-coverage-reviewer, spec-flow-analyzer, code-simplicity-reviewer
- Git: 2 commits pushed to feat-one-shot-6616-host-name-telemetry-mislabel

## Work Phase — Phase 0 ground-truth diagnosis (2026-07-17, LIVE)

The `prd_terraform` creds **were** available in-session, so the diagnosis is a **live confirmation**, not a deferral.

**Query** (24h hot+archive, source 2457081), verbatim output:
```
{"host_name":"","host":"","n":40640}
{"host_name":"","host":"soleur-inngest","n":28}
{"host_name":"soleur-inngest-prd","host":"soleur-web-platform","n":14993}
{"host_name":"soleur-inngest-prd","host":"soleur-inngest","n":5096}
{"host_name":"soleur-inngest-prd","host":"Ubuntu-2404-noble-64-minimal","n":16}
```

**Verdict (identity rule): MISLABEL CONFIRMED.** `host_name=soleur-inngest-prd` is emitted by
`host=soleur-web-platform` (web-1, 14993 rows) — a web host wearing the dedicated node's `host_name`.
This is the #6616 collision, live.

### ⚠️ Plan-correction (live data refuted a plan precondition — corrected inline per `hr-when-a-plan-specifies-relative-paths-e-g` class)

The deepened plan pinned the dedicated Inngest node's telemetry `host` value as **`soleur-inngest-server-prd`**,
citing `inngest.tf:291`. **That string never appears in telemetry** — because `inngest.tf:291` is a Better
Stack **heartbeat monitor** (`betteruptime_heartbeat.inngest_prd`), NOT a Hetzner server. The actual Hetzner
server is `hcloud_server.inngest` at **`inngest-host.tf:202`**, named **`soleur-inngest`**, and Hetzner seeds
the OS hostname from the server `name` — so the dedicated node's Vector `host` = `soleur-inngest` = its
`hcloud_server` name. The plan mis-sourced the identity from a similarly-named monitor resource. Confirmed
independently by **service fingerprint** (`host=soleur-inngest` ships `inngest-heartbeat` ×3726 plus
`doppler`/`sshd`/`systemd`; second content-keyed query, not the group-by output).

**Consequences for the follow-through (corrected):**
- A pure allowlist keyed on the dedicated node (`PASS iff soleur-inngest-prd only by <dedicated>`) would have
  **false-FAILed forever** on the inngest node's own generic early-boot rows (`host=Ubuntu-2404-noble-64-minimal`,
  kernel-only, n=16 — a default Hetzner image hostname that reappears every reboot before the hostname is set).
- Corrected predicate keys **FAIL on authoritative WEB-host identities** (the exact bug: "a web host self-labels
  soleur-inngest-prd") pinned from `server.tf:225` (`soleur-web-platform` = web-1, `soleur-web-2` = web-2), with a
  **positive schema-liveness marker** = ≥1 row with `host=soleur-inngest` (dedicated node present) required before
  any PASS. This is strictly better-scoped than the plan's allowlist for this bug and aligns with DC-1's YAGNI
  descope of a generic multi-host detector.

**Pinned constants (authoritative sources):**
- `MISLABEL_HOST_NAME = soleur-inngest-prd` — the stale literal (`inngest-bootstrap.sh` sed)
- `DEDICATED_HOST = soleur-inngest` — dedicated node OS hostname (live service-fingerprint, 2026-07-17)
- `WEB_HOSTS = soleur-web-platform, soleur-web-2` — `server.tf:225` per-host `host_name`/`name` map

AC1 satisfied (query recorded + verdict matches identity rule: confirmed via a non-dedicated web emitter).
