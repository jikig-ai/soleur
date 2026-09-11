---
title: "fix(cutover): op=execute 2.0 must accept a provably-dark dedicated host, not only a reachable-empty one"
date: 2026-09-10
slug: fix-cutover-execute-dark-host-registry-gate
branch: feat-one-shot-8054-execute-dark-host-registry-gate
issue: 8054
closes: [8054]
type: fix
lane: cross-domain
priority: p0
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No `spec.md` exists for
this branch: the one-shot path entered `plan` directly with no preceding brainstorm.

## Overview

`op=execute`'s 2.0 pre-flight in `scripts/cutover-inngest.sh` requires the dedicated inngest host
to answer a registry probe with `registry_empty=true`. The P1-5 arm-atomicity guard in
`apps/web-platform/infra/inngest-server-flip-guard.sh` refuses a prod-URI start on every pre-arm
value of `INNGEST_CUTOVER_FLIP`, so the host is dark whenever `execute` runs and 2.0 can never be
satisfied. The property 2.0 actually needs — the dedicated host is not carrying a function registry
that would double-fire — is satisfied more strongly by a provably-dark host than by a
reachable-empty one. This plan widens 2.0 to accept positively-established darkness while keeping
every existing refusal, and keeps silence firmly on the refusal side.

## Research Insights

### Premise Validation (Phase 0.6)

Every reference the brief cites was probed. Six premises held; six needed correction, and four of
those change the design rather than only the prose.

| # | Premise as briefed | Measured | Disposition |
|---|---|---|---|
| 1 | #8054 is the defect | OPEN, `priority/p0-critical`, title *"cutover op=execute is unrunnable: 2.0 needs a reachable dedicated host, but P1-5 keeps it dark on every pre-arm flag"* | HOLDS |
| 2 | #8017 is a "merged fix" | Issue #8017 is **OPEN**; its fix **PR #8019 merged 2026-09-10T20:10:52Z** (*"probe_schema=8 — G14's by-id comparison was unreachable, so the recut gate could never pass"*) | CORRECTED — cite **PR #8019** for the lineage; #8017 the issue is not closed |
| 3 | #8015 is the `registry_fns` issue | OPEN; the field is present in the emitter under the comment `#8015 probe_schema=8: registry evidence, so G18 stops passing vacuously` | HOLDS |
| 4 | #6178 / #7695 / #6894 open downstream | All three OPEN | HOLDS |
| 5 | 2.0 requires HTTP 200 + `registry_empty=true`, else `exit 1` | Confirmed in `scripts/cutover-inngest.sh` `execute)` arm, comment anchor `---- 2.0 empty-registry pre-flight (P1-6)` | HOLDS |
| 6 | P1-5 refuses every pre-arm flag | Confirmed: `inngest-server-flip-guard.sh` emits `BLOCK: prod Postgres URI with cutover flag='${FLIP_FLAG:-unset}' not in {armed,flipping,flushed,done} — refusing inngest-server start (P1-5)` | HOLDS |
| 7 | `scripts/cutover-inngest.sh` is not a baked carrier | Confirmed: `.github/workflows/cutover-inngest.yml` runs it from `${GITHUB_WORKSPACE}` after `actions/checkout` — no digest pin, no `user_data` | HOLDS |
| 8 | The dark gate's G1-G3 standard includes "`boot_id` matching" | **FALSE.** G3 was rewritten to a **wall-clock** bound. Its own comment: *"THIS PREDICATE WAS A BOOT_ID COMPARISON AND IT WAS DEAD ON ARRIVAL … boot_id is CONSTANT across every row of one boot"*. Only two `boot_id` **presence** checks survive | CORRECTED — see D1 |
| 9 | The flip-guard `BLOCK` marker carries the current `boot_id` | **Message: FALSE — envelope: TRUE.** The three `BLOCK:` lines carry no `boot_id` field, but every journald row Vector ships carries systemd's `_BOOT_ID` envelope field, and it is the same kernel value the probe writes as `boot_id=` (measured 2026-09-11 on all three streams: probe `boot_id=402c0d5b-1cf3-…` ↔ `_BOOT_ID=402c0d5b1cf3…`, hyphens the only difference; 500/500 heartbeat rows and 229/229 `BLOCK:` rows on the current boot). A `boot_id` join IS derivable — from the envelope, with no arithmetic | CORRECTED twice — see D2; plan-review found the envelope field the first research pass missed |
| 10 | `registry_fns=__UNREADABLE__` is evidence of darkness | **Partly false.** The emitter sets it unconditionally on the first arm: `if [ "$http_code" != "200" ]; then … registry_fns=__UNREADABLE__`. On the dark arm it is *entailed by* `http_code=000` and carries no independent information | CORRECTED — see D3 |
| 11 | (unbriefed) the probe row cannot say *why* the host is dark | **FALSE.** `cutover_flag` is field 10 of the same row. The flip-guard's refusal cause is readable from the single row the gate already grades | CORRECTED — see D2 |
| 12 | (unbriefed) a Better Stack read from `op=execute` needs a new secret | **FALSE.** `scripts/cutover-inngest.sh` already reads Better Stack via `_flip_query_rows`, and the `op=execute` job already carries `DOPPLER_TOKEN` (prd_terraform, read-only) | HOLDS the design — no workflow secret change |
| 13 | (surfaced by plan-review) the flip FSM's 30 s timer emits a heartbeat the gate can read | **TRUE, and measured.** `inngest-cutover-flip.sh`'s terminal arms call `emit_state 0 "" "noop-aborted" aborted` (and `noop-rolled-back`, `noop-done`, `noop-unset`) on every tick; the timer is never disabled (P0-1). Live: **500 rows in 24 h** on `SYSLOG_IDENTIFIER=inngest-cutover-flip`, ~1–2/min, every one `flag=aborted reason=noop-aborted` with `_BOOT_ID` on the current boot; Vector has already parsed the JSON, so `.message.flag` is a field, not a string. `scripts/cutover-inngest.sh` already reads this stream (`_flip_query_rows`, `_flip_liveness_count`) | DESIGN CHANGE — this is the freshness source (D2b'), replacing the `BLOCK:` read |

Two corrections to the research fan-out's own output, recorded so they do not propagate:
`scripts/lint-guard-contract.py` **does** exist (13,906 bytes, executable) and
`scripts/lint-orphan-test-suites.sh` **does** exist — a research agent reported both missing.

**Mechanism vs. the ADR corpus.** `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`
already carries a dated-addendum convention and, at `## Addendum — 2026-08-25 (#7674) — code delivery
to this host is replace-only, and "host dark" is not "query finds nothing"`, already decides the
adjacent question. This plan's mechanism is a direct continuation of that addendum, not a reversal
of it, and lands as a further addendum rather than a new ordinal. (Next free ordinals, measured:
**215** on `origin/main`, **216** across all `origin/*` refs — recorded only as the fallback if
review rules an addendum insufficient.)

### Property List (Phase 0.6b)

- **P1.** `op=execute` runs to completion against the dedicated host in its real pre-arm state.
- **P2.** `op=execute` still refuses when the dedicated host is reachable and carrying functions.
- **P3.** `op=execute` refuses whenever it cannot establish the host's state — absence, staleness
  and read failure all refuse.
- **P4.** There is exactly ONE definition of `SOLEUR_INNGEST_SERVER_PROBE` row-selection semantics
  in the repo, so a tightening cannot land on some readers and not others.
- **P5.** Every refusal names a distinguishable reason token, so a green suite cannot certify the
  wrong refusal.

### Cut List (Phase 0.6b)

| Mechanism the brief or the obvious design proposes | Property it would buy | What already buys it — cut |
|---|---|---|
| A second probe-row reader inside `cutover-inngest.sh` | P4 | `_IHDG_SELECT` + `_ihdg_rows` / `_ihdg_newest_dt` / `_ihdg_row_count` / `_ihdg_tied_newest` / `_ihdg_field` in `tests/scripts/lib/inngest-host-dark-gate.sh`. `scripts/lint-shell-trace-credential-refusal.py` classifies `tests/scripts/lib/*-gate.sh` as `PRODUCTION_GATE`, and `scripts/followthroughs/git-data-rung2-evidence-capture.sh` already sources a sibling gate lib from production code. **CUT** |
| A new Better Stack transport / new workflow secret | P1 | `_flip_query_rows` in the same script (`doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh …`), and `DOPPLER_TOKEN` already in the `op=execute` job env. **CUT** |
| `scripts/inngest-dedicated-host-classify.sh` as the reader | P3, P5 | Wrong shape by its own design: `tests/scripts/lib/inngest-host-dark-gate.sh` records that it *"collapses `silent`, `unreadable` and a pre-schema row into one `probe-unavailable` verdict … the WRONG shape here"*. **CUT** |
| Calling `inngest_host_dark_gate` itself from 2.0 | P1-P3 | It grades 20 predicates for an irreversible destroy, four of which (G17-G20) are recut-specific dispatch-time re-reads (`--expected-volume-id`, `--live-attachment-id`, `--followthrough-rc`) with no meaning at 2.0. **CUT the call, KEEP the helpers.** |
| `boot_id` equality via a `dt − uptime_s` boot-window join | freshness / same-boot | The journald envelope `_BOOT_ID` is on every shipped row (premise 9, corrected). Equality on that field replaces the arithmetic join; the join is **CUT**, the equality is kept |
| A second Better Stack read of flip-guard `BLOCK:` rows as the freshness source | freshness | Unsatisfiable after any `stop_server` (an explicit stop does not re-fire `Restart=on-failure`; the 5.4-day stopped-host record proves it), and coupled to ~55k noise rows/day. The FSM heartbeat (premise 13) buys the same property from the component that owns the flag, via the reader the script already has. **CUT — replaced by D2(b′)** |
| `registry_fns=__UNREADABLE__` as an independent darkness conjunct | P3 | Entailed by `http_code != 200` at the emitter. Demoted to a coherence predicate. **CUT as evidence, KEPT as coherence.** |
| A new ADR ordinal | recorded decision | ADR-100's dated-addendum convention. **CUT** |
| A new test-suite file | P5 | `apps/web-platform/infra/cutover-inngest-workflow.test.sh` already extracts pure decision functions with `awk '/^diag_boot_decide\(\) \{$/,/^\}$/'`, sources them, asserts token mappings, and floors dispatch (`diag_boot_decide scenarios actually dispatched (>=7)`). **CUT** |

### Value-Proposition Measurement (Phase 0.6c)

Not applicable — the justification is correctness (a pipeline step that cannot run), not a cost or
performance saving. No unquantified saving is load-bearing anywhere in this plan.

### Measured facts the design rests on

- **The emitter** `apps/web-platform/infra/inngest-bootstrap.sh` renders one line per probe under
  `logger -t "$LOG_TAG" "SOLEUR_INNGEST_SERVER_PROBE http_code=… server_active=… vector_active=…
  redis_active=… uptime_s=… boot_id=… image_ref=… instance_id=… cli_version=… cutover_flag=…
  probe_schema=… host_role=… flush_latched=… redis_keys=… redis_expires=… redis_key_patterns=…
  data_mount_src=… data_bytes=… data_mount_base=… data_mount_devid=… registry_fns=…"` — 21 fields.
- **`uptime_s`** is `cut -d. -f1 /proc/uptime` — HOST uptime, not process uptime — and **`boot_id`**
  is `/proc/sys/kernel/random/boot_id`. Boot start is therefore derivable as row `dt` minus
  `uptime_s`, which is the join key D2 uses.
- **`registry_fns`** is `__UNREADABLE__` when `http_code != 200`, when `jq` is absent, or when the
  GQL body does not yield an array; otherwise the array length. `0` is a measurement (the
  diagnostic-boot signature), never an absence — the distinction #8015 exists to preserve.
- **`http_code=000`** is curl's could-not-connect; **`server_active`** is systemd `is-active` output.
- **The flip-guard** emits exactly three `BLOCK:` lines under tag `inngest-server-flip-guard`, and
  `apps/web-platform/infra/vector.toml` allowlists both `inngest-cutover-flip` and
  `inngest-server-flip-guard`, so the marker does reach Better Stack.
- **The emitter is baked** (OCI image + `user_data` digest literal), so a change to it needs a host
  replace. **This plan changes no emitter field** — `probe_schema=8` already carries everything the
  new arm reads, which is why the constraint "no image bump, no host replace" holds.

### Institutional learnings that bear on this change

| Learning | Bearing |
|---|---|
| `knowledge-base/project/learnings/2026-09-03-the-gate-cleared-the-destroy-and-never-graded-the-create.md` | Source of the G3 rewrite: *"A predicate that cannot distinguish two states is not a predicate, however it reads."* Directly why premise 8 is corrected rather than copied. |
| `knowledge-base/project/learnings/2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect.md` | *"A signal that BOTH the old and the new artifact emit can never be a positive control."* Directly why `registry_fns=__UNREADABLE__` is demoted (premise 10). |
| `knowledge-base/project/learnings/2026-09-02-i-built-a-host-discriminator-out-of-an-absence-and-fixtured-the-absence.md` | A discriminator built from an absence, fixtured to agree with itself. Why the PASS arm must be a positive conjunction and the battery must assert the value that must never appear. |
| `knowledge-base/project/learnings/2026-08-09-my-suites-were-hermetic-so-they-certified-a-gate-reached-through-a-dead-read.md` | *"A hermetic suite cannot see a dead live input."* Why the plan carries a live discoverability probe of the query shape, not only fixture coverage. |
| `knowledge-base/project/learnings/2026-08-01-i-shipped-a-gate-my-own-tests-could-not-see.md` | Bare-token anchors match the comment that documents them. Why every assertion anchors on a dispatch or a token mapping, not a string the file also explains. |
| `knowledge-base/project/learnings/2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` | A bare-substring Better Stack probe is self-contaminating. Why the guard-marker read is field-isolated rather than payload-grepped. |
| `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` | Why the Guard Contract below carries harness rows and a must-PASS non-canonical input, not only RED rows. |

### Conventions in force

- `hr-no-ssh-fallback-in-runbooks` — the new arm is a Better Stack read; no host touch.
- `hr-menu-option-ack-not-prod-write-auth` — `op=execute` performs no prod write; unchanged.
- `hr-observability-as-plan-quality-gate`, `hr-observability-layer-citation` — `## Observability` below.
- `cq-cite-content-anchor-not-line-number`, `cq-assert-anchor-not-bare-token` — every citation in
  this plan is a content anchor; every AC asserts a dispatch or a token, never a bare literal.
- `cq-write-failing-tests-before` — the mutation matrix is written from the design, before the code.
- ADR-150 — the run body lives in `scripts/cutover-inngest.sh`, not in workflow YAML.

### Related issues and PRs

#8054 (this defect) · PR **#8019** merged (the #8017 fix, same class) · #8017 (issue, still open) ·
#8015 (`registry_fns`) · #6178 (the cutover this unblocks) · #7695, #6894 (downstream) ·
#7674, #7462, #7228, #6616, #6258 (cited by the surrounding code).


## Research Reconciliation — Spec vs. Codebase

| Claim in the issue / brief | Codebase reality | Plan response |
|---|---|---|
| The dark gate's G1-G3 standard is "row present, newest, within a max age, `boot_id` matching" | G3 is a **wall-clock** bound; its own comment records the `boot_id` form as *"DEAD ON ARRIVAL … boot_id is CONSTANT across every row of one boot"*. Only two `boot_id` **presence** checks survive | **D1.** The new arm reuses G1-G4 as they are TODAY — count, newest-is-graded, tie-free, wall-clock age, exact `probe_schema=8`, `boot_id` presence. It does NOT reintroduce a `boot_id` equality that the sibling gate already deleted as vacuous |
| Corroborate the probe row with the flip-guard `BLOCK` marker "on the CURRENT `boot_id`" | The `BLOCK:` message has no `boot_id`, but the journald **envelope** `_BOOT_ID` is on every row of every stream (measured). And the flip FSM emits a parsed JSON heartbeat every ~30 s carrying `flag`, `reason`, `guard`, on a timer that is never disabled — 500 rows/24 h live | **D2.** (a) **Row-internal, primary:** the probe row's own `cutover_flag` is read as a POSITIVE allowlist — `∈ {aborted, rolled-back}` continues, `∈ {armed, flipping, flushed, done}` refuses `flag_armed`, anything else (`unknown`, `rollback`, empty) refuses `flag_unreadable`. (b′) **Freshness bridge, required:** the newest `inngest-cutover-flip` heartbeat for this host whose `_BOOT_ID` equals the probe row's `boot_id` (hyphens stripped) must be within `FLIP_LIVENESS_SINCE` (15 m) and carry `.message.flag ∈ {aborted, rolled-back}`. It closes the ≤90-min snapshot gap to ~1 min from the component that owns the flag, survives `stop_server` (the timer runs on every flag), and is read by `_flip_query_rows`, which already exists. The `BLOCK:` read, the `dt − uptime_s` join and `guard_unattested` are gone |
| `probe_schema=8` carries the darkness evidence as `http_code=000`, `server_active` not active, `registry_fns=__UNREADABLE__` | All three are emitted, but `registry_fns=__UNREADABLE__` is set by the emitter's FIRST arm whenever `http_code != 200`, so on the dark arm it is entailed, not independent — and a NUMERIC `registry_fns` on a non-200 row is a state the emitter cannot produce | **D3.** `registry_fns == __UNREADABLE__` is a one-line coherence check (the sibling's G14 shape) refusing `unreadable` on contradiction. There is no `registry_populated` and no `row_incoherent` token: P2 (refuse a reachable host carrying functions) is bought entirely by the untouched HTTP-200 arm. The independent conjuncts are `http_code`, `server_active`, `host_role`, `cutover_flag` |
| The 2.0 remediation text presumes a dark host that is RUNNING but unarmed | Confirmed — 2.0's `::error::` still says *"(2) stop the dark inngest-server so nothing re-syncs functions"*, which the P1-5 guard has made impossible | **D4.** The remediation text is rewritten in the same edit. Leaving prose that instructs stopping a process that cannot start is the same defect one layer up |
| (unstated) the flip-guard `BLOCK` marker is reliably present | It is present ONLY while systemd keeps attempting a start. After `op=rollback` or an FSM-aborted arm the FSM calls `stop_server`; an explicit stop does not re-fire `Restart=on-failure`, so no `BLOCK:` rows are emitted at all — the health workflow measured 5.4 days of exactly that. Today's loop exists only because the host was REPLACED with the flag already `aborted` | **D5.** Plan-review (spec-flow P0, architecture P1, CTO P1, DHH P0, simplicity) converged: a predicate that holds only on a freshly-replaced host and fails on every routine retry is the #8054 defect one layer over. The `BLOCK:` read is deleted; the heartbeat (D2b′) is the freshness source, and it was measured present on THIS boot before being written into the design |
| `registry_fns` numeric > 0 must REFUSE | On the real emitter a NUMERIC `registry_fns` cannot appear on a non-200 row (it is set to `__UNREADABLE__` on that arm), so on the dark arm it is a contradiction, not a population reading. `registry_fns` is `n/a` on a **web-host** row | **D6.** P2 (refuse a reachable host carrying functions) is bought entirely by the untouched HTTP-200 arm. On the dark arm E12 refuses any non-`__UNREADABLE__` value as `unreadable`. The `_IHDG_SELECT` host conjunction runs before any field read and E8 asserts `host_role == dedicated` (`wrong_host`) so the web host never reaches E12 |

## Hypotheses

`hr-ssh-diagnosis-verify-firewall` / the network-outage checklist fired on `unreachable` in the
brief. The L3→L7 order is honoured, and every layer carries an artifact rather than an assertion.
The unusual feature of this incident is that the L7 artifact is **positive** — the service says, in
its own words, that it refused to start — which is what lets the lower layers be closed out.

1. **L3 — firewall allow-list.** *Opted out, with artifact.* The dedicated host's private address
   `10.0.1.40` is reached from the web host over the private net, not from an operator egress IP, so
   `var.admin_ips` drift cannot explain it. The decisive artifact is L7 below: a host whose own
   `ExecStartPre` refused the start has no listener for any packet to reach, from any source. The
   probe's `http_code` is measured on **loopback** (`http://127.0.0.1:8288/health`), which no
   firewall rule can affect — `000` there is a statement about the process, not the network.
2. **L3 — DNS / routing.** *Opted out, with artifact.* `10.0.1.40` is a literal in the webhook
   forwarder, not a resolved name. There is no DNS step in this path.
3. **L7 — TLS / proxy.** *Partially relevant, and it is why the arm order matters.* The 2.0 webhook
   traverses Cloudflare Access (`CF-Access-Client-Id` / `CF-Access-Client-Secret`) to
   `deploy.soleur.ai/hooks`, so a non-200 from that path can mean a web-host, Access or WAF fault
   rather than anything about the dedicated host. **This is a design input, not a hypothesis to
   chase:** the dark arm must not consume the webhook's verdict as evidence about the dedicated
   host, and it does not — it grades probe rows the dedicated host emitted itself.
4. **L7 — application.** *Verified, and decisive.* The measured run 34529824513 shows
   `2.0 registry-probe returned HTTP 500: … errors=["__FETCH_FAILED__"] … is the dedicated
   inngest-server reachable at http://10.0.1.40:8288/v0/gql?`, and the host's own journal carries
   `inngest-server-flip-guard: BLOCK: prod Postgres URI with cutover flag='aborted' not in
   {armed,flipping,flushed,done} — refusing inngest-server start (P1-5)`. The service never
   started. There is no lower-layer hypothesis left to test.

**Conclusion.** The unreachability is intended behaviour of a correct guard, not a fault. Nothing in
this plan touches a network layer; the change is entirely in what 2.0 accepts as evidence.

## User-Brand Impact

**If this lands broken, the user experiences:** every scheduled Inngest function firing twice — a
reminder email delivered twice, a workspace reconciliation applied twice, a scheduled send
duplicated — because 2.0 is the FIRST repo-side gate between the cutover flip and a second scheduler
registering against prod Postgres (the on-host P1-5 guard and `op=arm`'s G1 stand behind it, and the
arm-flip itself sits behind the `inngest-cutover` required-reviewer environment — so this is the
outer layer, not the only one). A widened gate that passes on a host still carrying a registry
removes that outer layer and leans on the inner ones; the duplicate, if it happens, reaches the
user's inbox before any dashboard shows it.

**If this leaks, the user's workflow is exposed via:** the Better Stack warehouse. The new arm ships
two additional reads of rows the host already emits (the probe stream and the flip FSM heartbeat); it must not begin echoing row CONTENT into CI
logs. The existing readers in this script hold a stated purity contract — *"Count rows, never echo
one: the standing purity contract of every Better Stack reader here"* — and the new reader adopts
it, echoing counts and single extracted field values only, never a whole row and never a GQL body.

**Brand-survival threshold:** single-user incident

`requires_cpo_signoff: true` is set in the frontmatter. CPO sign-off is recorded in `## Domain
Review`; `user-impact-reviewer` is invoked at review time per
`plugins/soleur/skills/review/SKILL.md`'s conditional-agent block.

## Non-Goals

- **`op=arm`'s G3.6, the P1-5 flag allowlist, and the `inngest-registry-probe` host script's own
  refusal are not touched.** All three are correct; the 500 is the probe declining to emit a false
  empty and must stay.
- **The reachable-empty arm keeps its PASS, and this plan does not re-decide whether it should.**
  A dedicated host that ANSWERS at `execute` time is, since ADR-100's 2026-08-20 addendum (prod DSN
  in the dark slot as steady state), an out-of-sequence signal — either P1-5 did not hold or `arm`
  already ran. But a reachable host reporting an EMPTY registry still satisfies the property 2.0
  guards (nothing to double-fire), so the arm stays byte-for-byte and gains only a `::warning::`
  naming the sequencing question (Phase 4.2). Whether that arm should REFUSE is a separate decision
  with its own blast radius; it is filed as **#8072** rather than folded into a gate widening.
- **The sibling recut gate's G8 (`server_active == "inactive"`) is not changed here.** It refuses
  today's live host (`activating`) as `host_serving` — the same class as this plan, one gate over —
  but it guards an irreversible destroy and gets its own issue and its own mutation row, not a
  ride-along edit under a P0 pre-flight fix. Tracked as **#8078**; the divergence from E10 is recorded in the lib header.
- **`op=registry-probe` has the identical defect and is not changed here.** Its `registry-probe)`
  arm hits the same hook and `exit 1`s on non-200, so it is unrunnable pre-arm for the same reason.
  It is a standalone diagnostic, not on the cutover's critical path; tracked as **#8079**.
- **`scheduled-inngest-health.yml`'s auto-restart is not suppressed here** (R7). It is the next
  hazard in the flow this plan unblocks, and it is out of this diff; tracked as **#8077**.
- **`INNGEST_BASE_URL` stays `http://host.docker.internal:8288`.** The co-located scheduler keeps
  serving production. Nothing here repoints traffic.
- **No outage is started and the one authorized `FLUSHALL` is not spent.** This plan changes a
  pre-flight predicate only; it performs no prod write and consumes no one-shot budget.
- **The probe emitter is not changed.** `probe_schema` stays at `8` and no field is added, so no
  image bump and no host replace. This is what keeps
  `hr-prod-host-config-change-immutable-redeploy` out of scope.
- **Encryption posture (Phase 2.11) does not fire.** No `*.tf`, no `supabase/migrations/*.sql`, no
  `cloud-init*.yaml`, no `docker-compose*.yaml` in the file list, and no new store or connection
  class — the Better Stack read path already exists in this same script (`_flip_query_rows`). #6894
  (the plaintext `hcloud_volume.inngest_redis`) remains open and out of scope.

## Files to Edit

| File | Change |
|---|---|
| `tests/scripts/lib/inngest-host-dark-gate.sh` | Extract `_ihdg_graded_row` (G1–G7 / E1–E7, currently ~110 lines inlined in `inngest_host_dark_gate`) and have both gates call it; fold `_ihdg_row_count`'s inline selector copy onto `"$_IHDG_SELECT"`; add `inngest_execute_registry_gate` (E8–E13) reusing `_ihdg_field` / `_ihdg_verdict` **verbatim** — no second verdict function, no second selector; header lists both consumers, copies the E-table, records the G8/E10 divergence |
| `tests/scripts/test-inngest-host-dark-gate.sh` | Extend `bs_line` (tag + `_BOOT_ID` args, defaults preserve every existing call) and add `hb_line`; add the `[ERG E1]`…`[ERG E13]` + `[ERG H5]` cases; route every matrix row through `mutate()` with the address-range scoping rule; `_FLOOR` → `-ne` with the `STALE FLOOR` message; raise `_FLOOR` and `_PRED_FLOOR` (measured−1) to the new measured values; add `cutover_flag`, `uptime_s`, `registry_fns` to both B12 consumed-field loops; the `set -euo pipefail` call-shape case; helper-level fixture tests |
| `scripts/cutover-inngest.sh` | Generalise `_flip_query_rows` → `_bs_query_rows <since> <grep> <limit>` (three existing call sites updated, behaviour unchanged); 2.0 gains the dark arm with the `\|\| ERG_RC=$?` call shape and the guarded `source`; the `case` over 11 tokens; D4 remediation text replaced; the 2.2 STILL RUNNING sentence (4.5); the reachable-arm `::warning::` (4.6). The HTTP-200 decision logic is unchanged (AC7) |
| `apps/web-platform/infra/cutover-inngest-workflow.test.sh` | Wiring assertions: one guarded gate call; every token has a `case` arm; `*)` exits 1; two `_bs_query_rows` call sites with one distinct `--grep` each; guarded `source`; added-annotation purity; **E11 set-equality against the P1-5 `case` derived from `inngest-server-flip-guard.sh`**; H6 (reachable arm reachable, not routed through the gate) |
| `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` | New dated addendum (see `## Architecture Decision`) |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | TWO edge-description edits: `github -> betterstack` (`op=execute` 2.0 beside `op=verify`) and `inngest -> betterstack` (the `inngest-cutover-flip` heartbeat is a safety-critical input to 2.0) |

`.github/workflows/cutover-inngest.yml` is deliberately **absent**: the `op=execute` job already
carries `DOPPLER_TOKEN` (prd_terraform, read-only), which is the only credential
`betterstack-query.sh` needs. `DOPPLER_TOKEN_INNGEST_ARM` stays environment-gated to
arm/rollback/resume — 2.0 does NOT read the flag synchronously from Doppler; the heartbeat is how it
gets freshness without that token. `apps/web-platform/infra/inngest-bootstrap.sh`,
`inngest-server-flip-guard.sh` and `inngest-cutover-flip.sh` are absent because they are baked: no
image bump, no host replace.

## Files to Create

None. Every artifact this change needs already exists; adding a file would create the second reader
this plan exists to avoid.

## Open Code-Review Overlap

**None.** Sixty-five open `code-review` issues were fetched and each of the five planned paths was
searched against every issue body with `jq --arg`. Zero matches.

## Implementation Phases

### Phase 0 — Measure before designing anything that depends on a measurement

Phase 0 exists because #8054 IS the cost of skipping it: a predicate was written against a world
nobody re-measured. Every measurement below was taken at plan time (2026-09-11, tree `0d97ede5c`)
and is re-run by /work as a freshness check; a re-run that disagrees is a finding to stop on, never
a licence to quietly drop a predicate.

0.1 **Two streams, two reads — never one.** From the worktree:

```
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
  --since 24h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 500
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
  --since 15m --grep inngest-cutover-flip --limit 200
```

An OR-combined read of two streams was measured returning 500 rows and **zero** probe rows: the
dedicated host's `doppler run` wrapper noise and the P1-5 refuse loop fill a 500-row window in ~13
minutes and starve the hourly probe row out of the limit. Host isolation happens after decoding,
never in `--grep`.

**Measured (probe stream):** rc 0, 25 dedicated-host rows in 24 h. Newest (dt `2026-09-11 10:00:55`):
`boot_id=402c0d5b-1cf3-495a-92e1-cf137732156f uptime_s=46908 probe_schema=8 http_code=000
server_active=activating cutover_flag=aborted host_role=dedicated registry_fns=__UNREADABLE__
redis_keys=16`; envelope `_BOOT_ID=402c0d5b1cf3495a92e1cf137732156f`. The previous boot
`906c015b…` is also in the window — the real "row from a previous boot" fixture.

**Measured (heartbeat stream):** 500 rows in 24 h (the limit), ~1–2/min, span 06:55→11:23; every
row `SYSLOG_IDENTIFIER=inngest-cutover-flip`, `_BOOT_ID=402c0d5b…`, and Vector has already parsed
the JSON: `.message = {"flag":"aborted","reason":"noop-aborted","guard":"7761","exit_code":0,
"start_ts":…}`. The heartbeat is read with `.message.flag`, not a string parse.

**Two consequences the design carries:** (i) `server_active` reads `activating` — the refuse loop
never settles to `inactive` — so the dark conjunct is `server_active != active`; (ii) the join
between streams is `_BOOT_ID` equality (hyphens stripped from the probe's `boot_id`), not clock
arithmetic.

0.2 **The live row satisfies the intended conjunction.** Measured: every field agrees (0.1).

0.3 **Baselines.** `tests/scripts/test-inngest-host-dark-gate.sh`: `_PRED_FLOOR=22` (23 covered — the
file keeps one of slack by its own comment), `_FLOOR=124` (124 ran — exact), `124 passed, 0 failed`.
`apps/web-platform/infra/cutover-inngest-workflow.test.sh`: `497 passed, 0 failed`, floor 497.

0.4 **Two premises the first research pass got wrong, now in the record.** `_ihdg_row_count`
carries an inline copy of the selector (it does NOT embed `_IHDG_SELECT`), and the gate body's
`wrong_host_rows` jq is a deliberate inverse — so P4 is false on the current tree until Phase 2
folds the copy. And `betterstack-query.sh` exit 3 = credentials absent, 2 = query/archive failure;
`doppler run` itself exits 1 on a dead token — three rcs, three remedies.

### Phase 1 — Write the failing battery FIRST, keyed on the predicates

`cq-write-failing-tests-before`. The mutation matrix in `## Guard Contract` is derived from the
DESIGN, before the code. Land the battery RED.

1.1 Extend `bs_line` to accept a `SYSLOG_IDENTIFIER` argument (default `inngest-server-probe`, every
existing call site unchanged) and to accept an envelope `_BOOT_ID`; add `hb_line` building a
heartbeat row whose `.message` is a parsed object with `flag`/`reason`.

1.2 **Reuse `expect` and `predicate` unchanged.** The pass token is `dark` — the same literal the
sibling gate emits and `expect` already maps to rc 0 — so no `expect_erg`/`predicate_erg`/
`_ierg_verdict` exists. Case names carry the predicate id **namespaced to the gate**: `[ERG E1]` …
`[ERG E13]`, `[ERG H5]`. The bare `[M1]`…`[M7]`, `H2`, `H3` are already taken by the sibling's own
matrix in this file (measured: 9 of 25 un-namespaced ids would have matched before a single new
case existed).

1.3 **Route every mutation row through the existing `mutate()` harness (section 4 of the suite),
not through case names.** `mutate()` patches a pristine copy with a single-line `sed`, refuses
no-op and multi-line patches, runs the unmutated control, and asserts the verdict flips — it is
the machine that makes a matrix real. Two scoping rules, and they are the shared-helper contract:
per-consumer mutations are **address-range scoped** to their function
(`/^inngest_execute_registry_gate() {$/,/^}$/ s|…|…|`, likewise for `inngest_host_dark_gate`),
because predicate lines textually shared by both entry points would otherwise match twice and red
the sibling's G4/G7/G9 rows with "changed 2 lines"; shared-helper mutations (the `_ihdg_*` rows)
are **unscoped** and each is asserted to redden BOTH consumers — a helper mutation that reddens
only one suite is the copy-detector, made mechanical.

1.4 One case runs a refusing input under `bash -c 'set -euo pipefail; source …; …'` and asserts
token + rc 1 — the lib has never been called under `errexit` and the production caller is.

### Phase 2 — `inngest_execute_registry_gate`, and the shared prelude it makes visible

2.1 **Extract `_ihdg_graded_row`.** G1–G7 of the sibling — query-rc, rows-file, population-then-
silence, newest/tie-free, wall-clock age, exact schema, `boot_id` presence — are ~110 lines inlined
in `inngest_host_dark_gate`'s body, not in any helper. E1–E7 are that exact sequence. Extract it
ONCE as `_ihdg_graded_row` (returns the graded message + row age on stdout, or a refusal token) and
have BOTH gates call it. Behaviour-preserving for the sibling: its battery stays green at 124 and
its G-row mutations still redden. Fold `_ihdg_row_count`'s inline selector copy onto
`"$_IHDG_SELECT"` in the same edit.

2.2 Add `inngest_execute_registry_gate` beside `inngest_host_dark_gate`. Inputs: `--rows-file`,
`--query-rc`, `--hb-file`, `--hb-rc`, `--now-epoch`, `--max-row-age`, `--hb-max-age` (default the
script's `FLIP_LIVENESS_SINCE`, 900 s), `--host`, `--host-name`, `--expected-schema`. Echoes exactly
one token via `_ihdg_verdict` — rc 0 only on the literal `dark`.

2.3 Predicates E1–E13 in the order the Guard Contract lists. E8–E12 are the gate-specific
conjunction; E13 is the heartbeat freshness bridge: decode `--hb-file`, require rc 0 and
bytes-vs-decodes coherence (raw lines ≥ 1 ∧ decoded == 0 → `fsm_unreadable`), select
`SYSLOG_IDENTIFIER == inngest-cutover-flip` ∧ same host pair ∧ `_BOOT_ID == strip_hyphens(boot_id)`,
take the newest, require age ≤ `--hb-max-age` (else `fsm_silent`), require
`.message.flag ∈ {aborted, rolled-back}` (else `flag_armed` / `flag_unreadable` by the same
partition as E11).

2.4 **E11 is a POSITIVE allowlist**, mirroring the sibling's G19 and its own G20 lesson ("THE EMPTY
STRING IS NOT AN ACCEPTING VALUE, and it was"): `cutover_flag ∈ {aborted, rolled-back}` → continue;
`∈ {armed, flipping, flushed, done}` → `flag_armed`; anything else — `unknown` (the emitter's
read-failed sentinel), `rollback` (in flight), empty, absent — → `flag_unreadable`. `server_active`
likewise must be present, non-empty and not `unknown`, else `unreadable`.

2.5 **Lib header:** list both entry points as consumers, name `scripts/cutover-inngest.sh
op=execute (P0 cutover step)` explicitly so the next editor of `_IHDG_SELECT` knows they are editing
the cutover, copy the E-table beside the existing G-table so the `[ERG En]` ids resolve in-tree, and
record the deliberate divergence: G8 is `server_active == "inactive"`, E10 is `!= "active"`. The
sibling's G8 refuses today's live host (`activating`) as `host_serving` — the same class as this
plan — and is tracked in its own issue rather than changed under a destroy gate here.

2.6 Helper-level fixture tests independent of either consumer: `_ihdg_field` absent/dup/newline →
rc 1; `_ihdg_tied_newest` 1 on identical duplicate, 0 on disagreement; `_ihdg_graded_row` on the
previous-boot fixture; and an assertion that no `_ihdg_*` helper body calls `_ihdg_verdict` (policy
cannot leak into a shared helper).

### Phase 3 — Green, then re-derive the floors

Run the suite. `_FLOOR` becomes `-ne` with a distinct `STALE FLOOR — set _FLOOR=<ran>` message
(precedent: `scripts/follow-through-closure-guard.test.sh`), so every future addition is a
one-number bump the failure text dictates; `_PRED_FLOOR` stays measured−1 per the file's own
comment. Record both new values in the PR body.

### Phase 4 — Wire 2.0

4.1 **Readers.** Generalise `_flip_query_rows` to `_bs_query_rows <since> <grep> <limit>` (its three
existing call sites pass `inngest-cutover-flip`; behaviour unchanged) and call it twice from 2.0 —
once with `SOLEUR_INNGEST_SERVER_PROBE`, once with `inngest-cutover-flip`. One `--grep` term per
invocation by construction. Each returns the query's rc (`|| rc=$?`). Rows are captured to
tempfiles for `--rows-file` / `--hb-file`; they are never echoed.

4.2 **Call shape under `set -euo pipefail` — load-bearing.** `scripts/cutover-inngest.sh` runs
errexit, and every refusal returns non-zero. A bare `ERG_VERDICT=$(…)` aborts the script before the
`case`, so no `::error::` and no remediation would ever print — fail-closed but mute. The shape is
`ERG_RC=0; ERG_VERDICT="$(inngest_execute_registry_gate …)" || ERG_RC=$?`, then `case
"$ERG_VERDICT"`. The `source` of the gate lib is guarded the same way:
`source tests/scripts/lib/inngest-host-dark-gate.sh || { echo "::error::2.0: gate library not found
on this ref — dispatch with --ref main"; exit 1; }` (cwd-relative, matching how the script already
invokes `scripts/betterstack-query.sh`; this is the second `scripts/`-side consumer of a
`tests/scripts/lib` gate after `scripts/followthroughs/git-data-rung2-evidence-capture.sh`).

4.3 **The dark arm.** In the `execute)` arm, leave the HTTP-200 decision logic unchanged. Replace
ONLY the `if [[ "$CODE" != "200" ]]; then … exit 1; fi` branch with: a `::notice::` prefixed
*"expected pre-arm (P1-5): webhook probe HTTP $CODE — grading darkness from the host's own rows"*
(the webhook's `CAUSE` is a question phrased as a fault and must not be printed bare beside a green
step), the two reads, the guarded call, and the `case`. `dark` emits the E13 notice and falls
through to 2.1. Every refusal token emits the `::error::` the E-table names and `exit 1`. The `*)`
arm prints the token, both rcs, and *"this is a defect in the gate, not a host state — file an
issue with this run URL; do not proceed"*, then `exit 1`.

4.4 **D4 — the P1-6 remediation text.** Step (2) of the existing non-empty `::error::` reads *"stop
the dark inngest-server so nothing re-syncs functions"* — impossible under P1-5. Replace steps
(2)–(3) with: *"(2) read the flag the gate graded (`ERG_FLAG`); if it is `done`, the cutover already
completed — dispatch `op=verify`; if `armed`/`flipping`, an arm is in flight — read that run, do not
re-dispatch execute; if `flushed`, dispatch `op=resume`. (3) if the flag is pre-arm and the registry
is still non-empty, the dedicated server started outside the guard — dispatch `op=doublefire-probe
-f cron_period_seconds=1200`, then `op=rollback`."* This edited echo is the ONE line inside the
reachable-empty block that changes; AC7 excludes it by content anchor.

4.5 **The 2.2 message, one sentence added.** When 2.2 fails STILL RUNNING, append: *"On the first
`execute` of a cutover this is the designed stop and the run is red by design. `op=quiesce-web`
STOPS production scheduling on both web hosts (it opens the maintenance window); dispatch it only
when you can continue through `op=arm` in the same sitting — `scheduled-inngest-health.yml`
auto-restarts the web scheduler within 15 minutes of seeing it down."* Today the SEAM text that
explains the window prints only after 2.2 passes, so a first-run operator never sees it.

4.6 **The reachable-empty arm gains one `::warning::` after the `pre-flight clear` notice** —
*"a dedicated host that ANSWERS pre-arm is out of sequence (P1-5 should keep it dark); the empty
registry still satisfies 2.0 — see #8072"* — and nothing else.

### Phase 5 — Wiring assertions in the sibling suite

Add to `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, each extracted from source with
the suite's existing `awk '/^fn() {$/,/^}$/'` pattern: 2.0 routes through exactly one guarded
`inngest_execute_registry_gate` call (`|| ERG_RC=$?` shape present; a bare `$(…)` is a failure);
every token the lib can emit has a `case` arm; the `*)` arm exits 1; both `_bs_query_rows` call
sites in 2.0 pass exactly one `--grep` term and distinct terms; no `echo "::…"` line added by this
PR interpolates `PROBE_ROWS*`, `HB_ROWS*` or `BODY`; the `source` line is `||`-guarded; and the
E11 allowlist in the lib is **set-equal to the P1-5 allowlist derived from
`apps/web-platform/infra/inngest-server-flip-guard.sh`'s own `case` arm** (the partition already
drifted once — #6553 added `flushed`; a retyped copy is the recurrence path).

### Phase 6 — ADR addendum, C4, then the full battery

6.1 Write the ADR-100 addendum (see `## Architecture Decision`). Amend TWO edge descriptions in
`knowledge-base/engineering/architecture/diagrams/model.c4`: `github -> betterstack` (`op=execute`
2.0 joins `op=verify` as a safety-critical Logs read) and `inngest -> betterstack` (the
`inngest-cutover-flip` heartbeat is now a safety-critical INPUT to 2.0 — the producer-side editor
reads that edge, not the consumer's). Run the C4 syntax + render suites.

6.2 `shellcheck` every edited shell file; `bash scripts/test-all.sh` for the full battery —
`tests/scripts/test-inngest-host-dark-gate.sh` is registered by an explicit `run_suite` line and
nothing auto-discovers `tests/scripts/`.

6.3 `python3 scripts/lint-guard-contract.py` against this plan; `bash scripts/lint-orphan-test-suites.sh`.

## Guard Contract

### Guard 1 — inngest_execute_registry_gate

**Property.** `op=execute` proceeds past 2.0 only when the dedicated inngest host is established,
from evidence the host itself emitted, to be carrying no function registry that could double-fire —
either because it answered and reported an empty registry, or because it is positively dark AND its
own flip FSM attested, within the last 15 minutes and on the same boot, that the cutover flag is
outside the arm set. Every other state, including every state in which the host's condition cannot
be established, refuses.

**Assembly.** Three chokepoints, named structurally. (1) **Row grading** — every consumer of a
`SOLEUR_INNGEST_SERVER_PROBE` row flows through `_ihdg_graded_row`, which is the ONLY place G1–G7 /
E1–E7 are evaluated, and which itself flows through `_IHDG_SELECT` and `_ihdg_field`; a second copy
of any of that (the state of the tree TODAY, where `_ihdg_row_count` carries an inline selector) is
the defect this contract exists to catch. (2) **Verdict dispatch** — `_ihdg_verdict` is the only
place a token becomes an rc for BOTH gates, and 2.0's `case` is the only place a token becomes
control flow; the production call is `||`-guarded so every token reaches the `case`. (3) **Evidence
acquisition** — `_bs_query_rows` is the only path by which rows enter either read, and it returns
the query's rc. The `_ihdg_*` helpers and `_ihdg_graded_row` are shared with `inngest_host_dark_gate`,
so a tightening of any of them must redden BOTH suites — the `mutate()` scoping rule in Phase 1.3 is
what makes that mechanical rather than aspirational.

**Assumed world, and who owns it.** E9/E10 assume the dedicated host cannot serve pre-arm — owned by
`apps/web-platform/infra/inngest-server-flip-guard.sh` (P1-5). E11/E13 assume the flag partition
`{armed, flipping, flushed, done}` — owned by the same file; Phase 5 derives it from source. E13
assumes the flip timer runs on every flag — owned by `inngest-cutover-flip.timer` (P0-1) and
measured (premise 13). E6 assumes `probe_schema=8` — owned by the baked emitter (PR #8019). A future
change to any of those files is a change to this gate.

**Predicates, in evaluation order, and the token each refusal emits.** Population before silence,
identity before content; `dark` is reachable only by passing all thirteen. Every remediation is a
`gh workflow run` verb, a wait bounded by a named cadence, or "file an issue" — never an SSH step.

| E | Predicate | Refusal token | Remediation the `::error::` names |
|---|---|---|---|
| E1 | probe `--query-rc` numeric and `0` | `unreadable` | Branch on `PROBE_RC` in the message: **3** → `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` not injected — verify in `prd_terraform`; **2** → the Better Stack read path did not answer (precedent: HTTP 503 "source under maintenance") — re-dispatch later; **1** → `doppler run` itself failed — the `DOPPLER_TOKEN` repo secret. Nothing about the host was measured |
| E2 | rows file decodes; raw lines ≥ 1 ∧ decoded == 0 is a decode failure, not silence | `unreadable` | as E1, `PROBE_RC=0` arm: "rows arrived but did not decode — file an issue with this run URL" |
| E3 | ≥ 1 row from ANY host; then ≥ 1 with `host==soleur-inngest ∧ host_name==soleur-inngest-prd` | `silent` / `wrong_host` | `silent`: the host emits no probe rows — read `scheduled-inngest-health.yml`'s latest run; two consecutive probe-unavailable readings there make it a host replace (`apply-web-platform-infra.yml -f apply_target=inngest-host-replace`). `wrong_host`: identity mislabel (#6616 class) — file an issue with this run URL; no host action, the host is not the problem |
| E4 | newest row is the graded row and tie-free | `unreadable` | Two rows at the same newest `dt` disagree — wait one probe period (≤ 60 min), re-dispatch |
| E5 | row age ≤ `--max-row-age` | `stale_row` | Wait for the next hourly probe and re-dispatch; if it stays stale, treat as `silent`. There is no no-SSH way to fire the probe early |
| E6 | `probe_schema == "8"` exact | `stale_schema` | The emitter is baked: host replace on a pin that carries the emitter — confirm first with `git show vinngest-<pin>:apps/web-platform/infra/inngest-bootstrap.sh \| grep -c probe_schema=8` |
| E7 | `boot_id` present, non-empty, matches `^[0-9a-f-]{36}$` | `unreadable` | Truncated row (the #7674 field-order lesson) — as E2 |
| E8 | `host_role == dedicated` | `wrong_host` | as E3 `wrong_host` (same predicate the sibling maps to the same token) |
| E9 | `http_code` numeric; `!= 200` | `unreadable` (non-numeric) / `host_serving` | The host answers on loopback while the webhook returned non-200 — the row and the webhook disagree. Check the WEBHOOK path first (`op=registry-probe`: CF Access / WAF / web-host); if it returns 200 the host IS serving pre-arm → `op=doublefire-probe -f cron_period_seconds=1200`; a double-fire → `op=rollback`; clean → re-dispatch `execute` |
| E10 | `server_active` present, non-empty, `!= unknown`, `!= active` | `unreadable` / `host_serving` | as E9 |
| E11 | `cutover_flag` **∈ {aborted, rolled-back}** (positive allowlist) | `flag_armed` (∈ arm set) / `flag_unreadable` (anything else) | `flag_armed`: print `ERG_FLAG` and branch — `done` → the cutover already completed, dispatch `op=verify`; `armed`/`flipping` → an arm is in flight, read that run, do not re-dispatch; `flushed` → `op=resume`. `flag_unreadable`: the emitter could not read the flag (`unknown`) or it is mid-transition (`rollback`) — wait one probe period, re-dispatch |
| E12 | coherence: `registry_fns == __UNREADABLE__` (entailed by E9 on the real emitter) | `unreadable` | The emitter contradicts itself — file an issue against `inngest-bootstrap.sh` with this run URL |
| E13 | heartbeat: `--hb-rc` is `0`; decode coherence as E2; newest `inngest-cutover-flip` row for this host pair with `_BOOT_ID == strip_hyphens(boot_id)` has age ≤ `--hb-max-age`; `.message.flag ∈ {aborted, rolled-back}` | `fsm_unreadable` (rc / decode) / `fsm_silent` (no fresh same-boot row) / `flag_armed` · `flag_unreadable` (as E11) | `fsm_silent`: the flip timer has not reported on this boot in 15 min — the FSM timer or Vector is down on a host the probe still sees; two consecutive readings → host replace. `fsm_unreadable`: as E1 with `HB_RC`. Flag tokens: as E11 |
| — | all of E1–E13 hold | **`dark`** (rc 0) | Proceeds to 2.1. The `::notice::` names `boot_id`, the graded flag, the probe row's age and the heartbeat's age, and says in plain words: *"the dedicated host is intentionally refusing to start until `op=arm`; a non-200 loopback with the server not active is the correct pre-flip posture, not a fault"* — value-agnostic about the flag literal, since `rolled-back` is equally correct |

**Token set** (11): `dark` · `unreadable` · `silent` · `wrong_host` · `stale_row` · `stale_schema` ·
`host_serving` · `flag_armed` · `flag_unreadable` · `fsm_silent` · `fsm_unreadable`. Eight are the
sibling's own vocabulary; the three new ones each carry a remedy no existing token names.

**Mutation matrix** — every row is a `mutate()` invocation (Phase 1.3), scoped per the rule there.
"Both" means the unscoped helper mutation must redden BOTH suites.

| # | Mutation (derived from the design) | Scope | Must drive |
|---|---|---|---|
| 1 | Delete E9's `!= 200` | gate | RED — a `http_code=200` row grades `dark` |
| 2 | Delete E10's `!= active` | gate | RED — a serving host with a broken loopback grades `dark` |
| 3 | Widen E11 to a NEGATIVE allowlist (`∉ arm set`) | gate | RED — `cutover_flag=unknown` grades `dark` (the G20 class) |
| 4 | Delete E8 | gate | RED — a web-host row (`host_role=web`, `registry_fns=n/a`) grades `dark` |
| 5 | Delete E12 | gate | RED — a numeric `registry_fns` on a non-200 row passes |
| 6 | Weaken E6 from `== "8"` to `>=` | gate | RED |
| 7 | Change E3's zero-row arm from refuse to pass | shared (`_ihdg_graded_row`) | RED in **both** — `silent` becomes a pass |
| 8 | Change E1's non-zero rc arm from refuse to pass | shared | RED in **both** |
| 9 | Drop the host conjunction from `_IHDG_SELECT` | shared | RED in **both** — a foreign fresh row supplies the recency bound |
| 10 | Delete E7 | shared | RED in **both** |
| 11 | Make `_ihdg_verdict` return rc 0 for any token | shared | RED in **both** — every refusal case's rc assertion flips |
| 12 | **Second member:** after a compliant newest row, add a second row at the same newest `dt` that disagrees | shared | RED in **both** — tie disagreement must refuse |
| 13 | **Own dispatch:** make `inngest_execute_registry_gate` echo `dark` before evaluating anything | gate | RED — `_FLOOR` (exact, `-ne`) fires; `0 checked, ok` is not a pass |
| 14 | Change E13's `_BOOT_ID` equality to "any boot" | gate | RED — a previous boot's heartbeat (`906c015b…`, real fixture) attests the current one |
| 15 | Widen `--hb-max-age` so a 2-hour-old heartbeat passes | gate | RED — `fsm_silent` unreachable |
| 16 | Widen E13's flag check to the negative form | gate | RED — heartbeat `flag=unknown` passes |
| 17 | Make `_bs_query_rows` swallow rc (`\|\| rc=$?` removed) | script (wiring suite) | RED — a dead read presents as `silent` with the wrong remedy |
| 18 | Replace 2.0's `case` `*)` arm with a fall-through | script (wiring suite) | RED |
| 19 | Un-guard the production call (`ERG_VERDICT=$(…)` bare) | script (wiring suite) | RED — under `set -e` no verdict is ever emitted |
| 20 | Retype E11's allowlist with one member missing | gate | RED — Phase 5's set-equality against the P1-5 source |

**Harness rows.** These mutate the SUITE, because a matrix that never touches the harness cannot see
a harness that asserts nothing. The suite already self-tests `expect`, `predicate`, `mutate` and
the floor counters (Phase 1.2 reuses them), so the pre-existing harness rows carry over; the two
below are new and gate-specific.

| # | Harness input | Must drive |
|---|---|---|
| H5 | **Must-PASS, non-canonical:** probe row with `server_active=failed` (not `activating`), `cutover_flag=rolled-back` (not `aborted`), an unfamiliar `image_ref`, an extra trailing field the gate never reads, age well inside the bound; heartbeat with `flag=rolled-back reason=noop-rolled-back` on the same `_BOOT_ID` | PASS `dark` — the contract permits every one of these; a suite whose only PASS input is the canonical fixture cannot tell a correct gate from one that rejects everything |
| H6 | **Must-PASS, wiring suite:** the reachable-empty arm — webhook `200`, `registry_empty=true`, no probe read at all | PASS — the pre-existing arm must remain reachable and must not route through the new gate |

## Observability

```yaml
liveness_signal:
  what: >-
    The 2.0 verdict line itself. On the dark arm, a `::notice::` naming the graded row's
    boot_id, the graded flag, the probe-row age, the heartbeat age and the verdict token `dark`; on every refusal an
    `::error::` naming the token. The verdict is emitted on EVERY op=execute run, so the
    absence of a 2.0 verdict line in a run log is itself a signal that the block was skipped.
  cadence: once per `op=execute` dispatch of `.github/workflows/cutover-inngest.yml` (manual)
  alert_target: >-
    The workflow run's own conclusion. A refusal is `exit 1`, which fails the job and
    surfaces through the existing GitHub Actions notification path for that workflow.
  configured_in: >-
    `scripts/cutover-inngest.sh`, `execute)` arm, the 2.0 block; observability layer 5
    (CI workflow annotations), per `hr-observability-layer-citation`.
error_reporting:
  destination: >-
    GitHub Actions `::error::` annotations on the run, plus the upstream evidence trail in
    Better Stack (source 2457081) which holds the rows the verdict was computed from.
  fail_loud: >-
    Yes, and fail-closed. Every non-`dark` token exits 1. `betterstack-query.sh`
    exit 3 (credentials not injected) yields `unreadable` with `PROBE_RC=3` printed and the remedy
    branched on it — never `silent`; the two have opposite remedies and only one of them is a wait.
failure_modes:
  - mode: The Better Stack read path is down (measured precedent: HTTP 503 "This source is currently under maintenance")
    detection: non-zero `--query-rc` reaching the gate; verdict token `unreadable`
    alert_route: "`::error::` + exit 1 on the op=execute run; the operator re-runs when the read path recovers"
  - mode: The credentials are not injected into the job
    detection: "`betterstack-query.sh` exit 3 → `unreadable` with `PROBE_RC=3` in the message, never `silent`"
    alert_route: "`::error::` naming `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` in prd_terraform"
  - mode: The host has stopped emitting probe rows (timer or Vector down)
    detection: zero qualifying rows with a successful read; verdict token `silent`
    alert_route: "`::error::` + exit 1. Cross-checked by `scheduled-inngest-health.yml`, which reads the same marker on a schedule and classifies via `classify_dedicated_host`"
  - mode: The host is emitting from a pre-`probe_schema=8` renderer
    detection: exact-equality schema check fails; verdict token `stale_schema`
    alert_route: "`::error::` naming the replace-only delivery constraint — the emitter is baked, so this is actionable as a host replace with a bumped pin, not as a retry"
  - mode: The host is reachable and CARRYING functions (the double-fire precursor)
    detection: "the webhook arm's `registry_empty=false` (the existing 2.0 ABORT); on the dark arm a numeric `registry_fns` is an emitter contradiction → `unreadable`"
    alert_route: "`::error::` + exit 1 with the P1-6 remediation"
  - mode: The flip FSM heartbeat has stopped or is not shipping (timer disabled, Vector allowlist drift)
    detection: no `inngest-cutover-flip` row with this boot's `_BOOT_ID` inside 15 min; verdict token `fsm_silent`
    alert_route: "`::error::` + exit 1; two consecutive readings make it a host replace"
  - mode: The gate's own dispatch is skipped or short-circuited
    detection: "the suite's anti-vacuity floor (`_FLOOR`) and distinct-predicate floor (`_PRED_FLOOR`) in `tests/scripts/test-inngest-host-dark-gate.sh`"
    alert_route: CI failure on `scripts/test-all.sh`
logs:
  where: >-
    GitHub Actions run logs for `cutover-inngest.yml` (90-day default retention); the
    underlying probe and flip-guard rows in Better Stack source 2457081, hot window plus
    the S3 archive that `betterstack-query.sh` unions in by default.
  retention: "GitHub Actions run logs 90 days; Better Stack hot window ~40 minutes, archive per the source's retention"
discoverability_test:
  command: bash tests/scripts/test-inngest-host-dark-gate.sh
  expected_output: >-
    The final line reads `inngest-host-dark-gate: <N> passed, 0 failed`, preceded by
    `ok   drop-one floor: <D> distinct predicates covered across <C> cases (floor <F>)` and
    `ok   anti-vacuity floor: <A> assertions ran (floor <B>)`. A non-zero failure count, or a
    missing floor line, means the gate's own dispatch is not being exercised.
```

The `discoverability_test` runs locally with no credentials and no network, so no
`credentials_required` declaration is made. It verifies the gate's LOGIC. Input validity — that the
live query shape actually returns rows — is a separate property and is verified by Phase 0.1, which
is a live read run at `/work` time rather than a hermetic fixture, because a hermetic suite cannot
see a dead live input.

**Soak follow-through (2.9.1):** not applicable. No acceptance criterion here is time-gated; the
gate's correctness is established by the battery and by Phase 0's live read, not by a post-deploy
soak window.

## Dependencies & Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **The freshness bridge (E13) depends on the flip FSM timer emitting on every flag.** If the timer is disabled or Vector stops shipping the `inngest-cutover-flip` tag, E13 refuses `fsm_silent` on a legitimately dark host — fail-closed, never fail-open. | The timer is designed never to be disabled (`inngest-cutover-flip.sh` P0-1: "a disabled timer would make no-SSH rollback unreachable") and emits on every terminal flag (P0-2); measured live at ~1–2/min for 24 h. The dependency is recorded in the ADR-100 addendum and on the `inngest -> betterstack` C4 edge, so the producer-side editor sees it. `fsm_silent` names the remedy. |
| R2 | **Stream starvation in a Better Stack read.** Measured: an OR-combined read of two streams returned 500 rows and zero probe rows. | One `--grep` term per `_bs_query_rows` invocation, by construction (Phase 4.1); Phase 5 asserts distinct single terms at both 2.0 call sites. |
| R3 | **The read window vs. the probe cadence.** The probe fires hourly; `--max-row-age` must exceed one period plus ingest lag or a healthy host grades `stale_row` between probes. | Reuse the sibling gate's `--max-row-age` default (5400 s); H5 uses an age well inside it; mutation #15 proves the heartbeat bound bites. There is no no-SSH way to fire the probe early, and E5's text says so. |
| R4 | **A second reader drifts from the first.** #8017 and #8054 are two readers of one row disagreeing. | `_ihdg_graded_row` is extracted so G1–G7 / E1–E7 exist ONCE; `_ihdg_row_count`'s inline copy is folded; mutation rows 7–12 are unscoped and must redden BOTH suites; `## Files to Create` is empty. |
| R5 | **Transport confinement on the `github -> betterstack` edge (#7873 / ADR-202).** | No new curl — both reads go through `scripts/betterstack-query.sh`, which owns the transport; `lint-shell-trace-credential-refusal.py` Rule D runs on every touched file. |
| R6 | **The planning pipeline hit an API rate limit** (three agents 429'd 2026-09-11). | Plan recovered from disk and completed inline; Phase 0 measured directly; `## Domain Review` records which leaders ran. The plan-review panel ran in full afterwards. |
| R7 | **The health watchdog races the cutover window.** `scheduled-inngest-health.yml` runs every 15 min and its "Auto-dispatch inngest restart" step fires `restart-inngest-server.yml` on `inngest_down` with no quiesce suppression — so after `op=quiesce-web` the watchdog RESTARTS the web scheduler, and the second `execute` fails 2.2 STILL RUNNING. Out of this diff, but it is the flow this plan unblocks. | The 2.2 message (Phase 4.5) tells the operator to dispatch `quiesce-web → execute → arm` back-to-back inside 15 min; the suppression is **#8077**. |
| R8 | **The reachable-empty arm is now the weaker arm** — the dark arm enforces the flag (E11/E13) and the reachable arm does not, so gate strength depends on which arm the host lands in. | Recorded in the ADR addendum; the `::warning::` names #8072, where the decision is taken with its own blast radius. |

**Dependencies.** PR #8019 (merged 2026-09-10) — `probe_schema=8` and `registry_fns` are on the live
host (measured). The flip FSM heartbeat and Vector's `inngest-cutover-flip` allowlist entry are on
the live host (measured, premise 13). No other PR must land first.

## Architecture Decision (ADR/C4)

The plan changes what the cutover orchestrator accepts as evidence of a safe pre-flip state, adds a
second safety-critical CI read of the Logs warehouse, and makes the flip FSM's heartbeat a
safety-critical input. A competent engineer reading only ADR-100 and the C4 model after this ships
would be misled on all three, so all three are deliverables here.

### ADR

**Amend ADR-100** with a dated addendum in its existing convention — heading
`## Addendum — 2026-09-11 (#8054) — "host dark" is a positive reading, and 2.0 accepts it`. No new
ordinal: the 2026-08-25 (#7674) addendum decided the adjacent question (*"host dark" is not "query
finds nothing"*), and this is its continuation. (Fallback if review rules an addendum insufficient:
next free ordinal measured **215** on `origin/main`, **216** across all `origin/*` refs —
provisional until merge per the ordinal-collision gate.)

The addendum records, as decision text: (1) the P1-5 guard and 2.0 were written against different
worlds, and the guard is the one that is right; (2) 2.0's property is *not carrying a double-fire
registry*, satisfied by reachable-empty OR positively-dark, never by silence; (3) the probe row's
own `cutover_flag`, read as a POSITIVE allowlist, is the P1-5 cause without a join; (4) the flip
FSM's heartbeat, joined on the journald `_BOOT_ID` envelope, is the freshness bridge — its value is
freshness, not corroboration, and it is why a dark host can be graded from a ≤90-min row; (5) the
`BLOCK:`-stream design was measured, found unsatisfiable after any `stop_server`, and rejected —
recorded so it is not proposed again; (6) the stream-starvation measurement and the
one-`--grep`-per-read rule; (7) the deliberate G8/E10 divergence (`== inactive` vs `!= active`) and
that the sibling refuses today's live host, tracked as #8078; (8) the reachable-arm asymmetry
(R8) deferred to #8072.

### C4 views

All three model files were read (`model.c4` 710 lines, `views.c4` 74, `spec.c4` 54) and the
actors, systems, containers and relationships this change touches were enumerated:

| Actor / system / container / relationship | Modeled? | Disposition |
|---|---|---|
| Dedicated Inngest host (`inngest` container; `hetzner -> inngest` "dedicated single-host node, private-net 10.0.1.40") | yes | unchanged |
| `inngestRedis`, `inngestPostgres` | yes | unchanged — this plan reads neither |
| Better Stack as the Logs warehouse (`betterstack` system) | yes | unchanged |
| GitHub Actions as the cutover orchestrator (`github`; `github -> tunnel` for the webhook path) | yes | unchanged |
| **`github -> betterstack`** — CI reads of the warehouse | yes, but its description names `op=verify` as the sole *SAFETY-CRITICAL* cutover read | **EDIT** — the sentence beginning `SINCE #6178/ADR-146 this edge also carries a SAFETY-CRITICAL read: cutover-inngest.yml op=verify …` gains `op=execute` 2.0 (probe-row + FSM-heartbeat reads; a retention miss or query failure refuses 2.0 closed, as it fails `verify` closed). The `--disable`/`--noproxy` obligation is inherited via `betterstack-query.sh` |
| **`inngest -> betterstack`** — the host ships journald via Vector | yes, described as telemetry shipping | **EDIT** — one clause: the `inngest-cutover-flip` heartbeat on this edge is now a safety-critical INPUT to `op=execute` 2.0 (E13); a producer-side editor reads this edge, not the consumer's |
| Human actors | none new — CI-initiated reads, no operator in the loop | unchanged |
| Data stores | none new | unchanged |

No element is added, so `views.c4` needs no `include` change. Validation after the edits:
`cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.
(The `c4-count-parity` gate the plan skill names is not present on this tree — `git ls-files |
grep -i count-parity` returns nothing — so the syntax/render suites are the validation.)

### Sequencing

The ADR addendum and both `.c4` edits land in the same PR as the code (Phase 6.1), before the
full-battery run. Nothing here is soak-gated.

## Acceptance Criteria

Every criterion is a checkable post-condition on file state or command output, anchored on a
dispatch or a token — never a bare literal the file also documents, never a line number. Comments
are stripped (`grep -v '^\s*#'`) before any count. All pre-merge criteria run in CI or locally with
no credentials except where stated.

### Pre-merge (PR)

- [ ] **AC1 — dark-gate battery green, floors re-derived.** `bash tests/scripts/test-inngest-host-dark-gate.sh` exits 0; its last line matches `^inngest-host-dark-gate: [0-9]+ passed, 0 failed$` with the passed count **> 124**; the anti-vacuity line's ran-count EQUALS its floor (`grep -oE 'anti-vacuity floor: ([0-9]+) assertions ran \(floor \1\)'` matches) and the floor comparison in the file is `-ne` (`grep -cE '_FLOOR \) -ne|-ne "\$_FLOOR"|_FLOOR" -ne' tests/scripts/test-inngest-host-dark-gate.sh` ≥ 1); `_PRED_FLOOR` equals covered−1 per the file's convention.
- [ ] **AC2 — wiring suite green, floor raised.** `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` exits 0; last line matches `^=== Results: [0-9]+ passed, 0 failed ===$` with the count **> 497**.
- [ ] **AC3 — one grading prelude, one selector, two entry points.** In `tests/scripts/lib/inngest-host-dark-gate.sh` (comments stripped): `grep -cE '^_ihdg_graded_row\(\) \{'` → `1`; `grep -cE '^inngest_[a-z_]+\(\) \{'` → `2`; `grep -cE '^_IHDG_SELECT='` → `1`; the literal `test("^SOLEUR_INNGEST_SERVER_PROBE ")` appears exactly **2** times (the selector and the deliberate `wrong_host_rows` inverse — the inline copy in `_ihdg_row_count` is gone); `grep -c '"\$_IHDG_SELECT"'` ≥ 4.
- [ ] **AC4 — one verdict function, every token exercised, none vacuous.** `grep -cE '^_ierg_verdict\(\)' tests/scripts/lib/inngest-host-dark-gate.sh` → `0` (no second verdict function). `T=$(grep -oE '_ihdg_verdict "[a-z_-]+"' tests/scripts/lib/inngest-host-dark-gate.sh | cut -d'"' -f2 | sort -u)`; `echo "$T" | grep -qx dark` and `echo "$T" | wc -l` ≥ 11; for every `t` in `$T`, `grep -cF "\"$t\"" tests/scripts/test-inngest-host-dark-gate.sh` ≥ 1.
- [ ] **AC5 — exactly one guarded gate call in 2.0.** `awk '/^  execute\)$/{f=1;next} f&&/^  [a-z-]+\)$/{exit} f' scripts/cutover-inngest.sh | grep -v '^\s*#' | grep -cE '^\s*ERG_VERDICT="?\$\(inngest_execute_registry_gate ' → `1`, and that same line matches `\|\| ERG_RC=\$\?` (the `set -e`-safe shape).
- [ ] **AC6 — one reader, two call sites, one term each.** `grep -cE '^_bs_query_rows\(\) \{' scripts/cutover-inngest.sh` → `1`; `grep -cE '^_(flip|probe|guard_block)_query_rows\(\) \{' scripts/cutover-inngest.sh` → `0`; within the execute arm (comments stripped) the lines calling `_bs_query_rows` number exactly `2`, one containing `SOLEUR_INNGEST_SERVER_PROBE` and one containing `inngest-cutover-flip`, and neither line contains both.
- [ ] **AC7 — the reachable-empty decision logic is unchanged.** Scoped to the execute arm and excluding the one edited echo: `for src in <(git show origin/main:scripts/cutover-inngest.sh) scripts/cutover-inngest.sh; do awk '/^  execute\)$/{e=1} e&&/REG_EMPTY=\$\(echo "\$BODY"/{f=1} f{print} f&&/pre-flight clear/{exit}' "$src" | grep -v 'Remediation (P1-6)'; done` produces two identical streams (`diff` exits 0). (Measured: the un-scoped anchor first matches in the `registry-probe)` arm at a different line; the arm scope is load-bearing.)
- [ ] **AC8 — D4 replaced, not deleted.** In the execute arm, `grep -c 'stop the dark inngest-server'` → `0` AND `grep -cE 'Remediation \(P1-6\).*ERG_FLAG'` → `1`.
- [ ] **AC9 — purity of the ADDED annotation lines.** `git diff origin/main -- scripts/cutover-inngest.sh | grep '^+' | grep -E 'echo "::(notice|error|warning)::' | grep -cE '\$\{?(PROBE_ROWS|HB_ROWS|BODY)\b'` → `0`.
- [ ] **AC10 — shellcheck clean.** `shellcheck -S warning scripts/cutover-inngest.sh tests/scripts/lib/inngest-host-dark-gate.sh tests/scripts/test-inngest-host-dark-gate.sh apps/web-platform/infra/cutover-inngest-workflow.test.sh` exits 0 (ShellCheck 0.10.0).
- [ ] **AC11 — guard-contract lint.** `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-09-10-fix-cutover-execute-dark-host-registry-gate-plan.md` exits 0.
- [ ] **AC12 — orphan-suite lint.** `bash scripts/lint-orphan-test-suites.sh` exits 0.
- [ ] **AC13 — ADR-100 addendum present.** `grep -cE '^## Addendum — 2026-09-1[0-9] \(#8054\)' knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` → `1`.
- [ ] **AC14 — both C4 edges amended and the model renders.** `grep -E '^\s*github -> betterstack' knowledge-base/engineering/architecture/diagrams/model.c4 | grep -c 'op=execute'` → `1`; `grep -E '^\s*inngest -> betterstack' knowledge-base/engineering/architecture/diagrams/model.c4 | grep -c 'inngest-cutover-flip'` → `1`; `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` exits 0.
- [ ] **AC15 — untouched surfaces are untouched.** `git diff --quiet origin/main -- .github/workflows/cutover-inngest.yml apps/web-platform/infra/inngest-bootstrap.sh apps/web-platform/infra/cloud-init-inngest.yml apps/web-platform/infra/inngest-server-flip-guard.sh apps/web-platform/infra/inngest-cutover-flip.sh` exits 0 — no workflow secret change, no emitter change, no guard or FSM change, so no image bump and no host replace.
- [ ] **AC16 — the E11 allowlist is derived, not retyped.** The wiring suite contains an assertion that extracts the P1-5 `case` allowlist from `apps/web-platform/infra/inngest-server-flip-guard.sh` and the E11/E13 set from the gate lib, and asserts set-equality (it prints a PASS line naming both files); mutation #20 reddens it.
- [ ] **AC17 — full battery.** `bash scripts/test-all.sh` prints a marker matching `^=== [0-9]+/[0-9]+ suites passed ===$` and its rc file reads `0`, on a run this branch owns. A run with no marker and rc `4` was REFUSED because a sibling full-gate run was in flight — that is *no verdict*, not a failure; re-run when no sibling is running.
- [ ] **AC18 — the sibling gate is behaviour-preserved.** Every pre-existing `[G<n>]` case and every pre-existing `mutate()` row in `tests/scripts/test-inngest-host-dark-gate.sh` still passes after the `_ihdg_graded_row` extraction (AC1's `0 failed` covers it), and `git diff origin/main -- tests/scripts/lib/inngest-host-dark-gate.sh | grep -cE '^-.*server_active" == "inactive"'` → `0` (G8 was not changed here; it is tracked separately).

### Post-merge — dispatched by the pipeline (no operator step)

- [ ] **AC19 — the step that could not run, runs.** Precondition, re-measured immediately before dispatch: `doppler secrets get INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd --plain` → `aborted`, and the newest dedicated probe row still reads `http_code=000`. If either has moved, this criterion is re-scoped to the new state, not marked failed. Then `gh workflow run cutover-inngest.yml --ref main -f op=execute` (no `cron_period_seconds` — the execute arm never reads it). In `gh run view <id> --log`: a line matching `expected pre-arm \(P1-5\)`; a `::notice::` matching `2\.0 .*dark` that names `boot_id=` and the graded flag; the line `::notice::2.1 capture: Σcaptured=`; the line `quiesce check \(LB-reachable host\): inngest STILL RUNNING`; and `::error::2.2 QUIESCE HARD GATE FAILED` followed by the sentence beginning *"On the first `execute` of a cutover this is the designed stop"*. **The red X on the run is the pass condition**: the failure is at 2.2, not at 2.0. Afterwards `doppler secrets get INNGEST_BASE_URL -p soleur -c prd --plain` still reads `http://host.docker.internal:8288`, and nothing was quiesced, armed or flushed.

## Domain Review

**Domains relevant:** engineering, product (sign-off only — no UI surface)

The mechanical UI-surface override did not fire: `## Files to Edit` names two shell scripts, two
shell test suites, one ADR and one `.c4` model — no path matches the UI-surface term list, so the
Product/UX Gate tier is **none**. Product participates here only because `## User-Brand Impact`
declares `single-user incident`, which requires a plan-time CPO sign-off (Phase 2.6 step 3).
Legal, finance, marketing, sales, support and operations were assessed against the plan content and
have no implications — this is an infrastructure/tooling gate change that performs no production
write and touches no user data, contract, cost line or channel.

### Engineering

**Status:** reviewed (partial)
**Assessment:** The CTO domain-leader spawn of the original planning run (2026-09-11) was terminated
by an API rate limit (HTTP 429, weekly limit) before returning. Its sub-probe *"Assess current
double-fire exposure"* completed and its findings are carried forward as the engineering
assessment, because they are the facts the design rests on:

- **Topology today:** two web hosts exist in Terraform, but only web-1 runs a co-located Inngest
  scheduler (`web_colocate_inngest` defaults `false`; web-2 was born after that default and carries
  no `inngest-server` unit at all). The dedicated host exists and is dark. **No double-fire is
  happening today**, and the thing preventing it is configuration defaults (web-2 without the unit,
  web-2 at LB weight 0), not the singleton topology ADR-100 intends — exactly the Option-B posture
  ADR-100 rejected. Flipping `web_colocate_inngest=true`, or recreating web-1 while pooling web-2,
  re-arms N-way double-fire immediately.
- **The guard, not the backend, keeps the host dark:** since 2026-07-23 the dark slot holds the
  prod DSN as steady state; darkness comes from `inngest-server-flip-guard.sh`'s P1-5 refusal.
  There is no singleton election on the web side; `host_role` is a telemetry discriminator, not a
  gate; `--sdk-url` is not a double-fire guard (shared Postgres drives scheduling regardless).
- **What the cutover is blocking downstream:** active-active web (web-2 not poolable pre-flip),
  HA/redundancy (#6185), disaster recovery (web-1 is a pet on a `cx33` not orderable in hel1,
  #6460), the soleur-dev co-tenancy retirement follow-through (#6488), the dormant
  config-refresh channel, and ADR-100's `adopting → accepted` soak.
- **Cost of staying blocked:** app-originated `inngest.send()` was measured failing at ~621
  `ECONNREFUSED 10.0.1.40:8288` rows/hour on 2026-08-25 (since repointed to the co-located
  scheduler on 2026-09-07); the twelve days of lost dispatches were accepted as lost by operator
  decision on 2026-08-11.

The CTO leader itself was not re-spawned after the 429: the sub-probe's findings are the substance
of what a leader assessment would carry, and the leader's remaining judgement (loop-quieting cost,
whether to re-noise-budget the guard) is recorded by the CPO below as a CTO/COO decision to take
after the cutover lands. **Partial** is the honest status.

### Product/UX Gate

**Tier:** none
**Decision:** reviewed
**Agents invoked:** cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

**CPO sign-off: approved-with-conditions** (2026-09-11, read-only spawn against this plan and
ADR-100). All four conditions were applied to this plan before `## Acceptance Criteria` was written:

1. **`## Dependencies & Risks` written**, with R1 recording that D2(b) makes the P1-5 refuse loop's
   `BLOCK:` rows a *required* input to a safety gate, and the ADR-100 addendum (Phase 6.1) carrying
   the sentence *"any change that quiets the P1-5 refuse loop (start-limit, backoff, clean stop)
   must re-measure D2(b) or 2.0 refuses again."*
2. **Token-to-remediation table written** — the E1…E14 predicate table in `## Guard Contract`
   names every token the gate can emit and every remediation is a `gh workflow run` verb, a
   bounded wait, or "file an issue". (The `guard_unattested` token this condition first produced was
   later CUT with the `BLOCK:` design — see the Plan Review Panel below.)
3. **The `dark` notice states in plain words that dark is the intended, safe state** (the E-table's pass row and
   Phase 4.2) — a founder reading `http_code=000 server_active=activating` beside a green tick
   must not go looking for a fix that must not be applied.
4. **Why the reachable-empty arm keeps its PASS is recorded** (`## Non-Goals`, Phase 4.2), the arm
   gains a `::warning::` naming the sequencing question, and the decision whether it should refuse
   is filed as **#8072** rather than folded in.

CPO also corrected one overstatement — *"2.0 is the only gate standing between the flip and a
second scheduler"* — which `## User-Brand Impact` now states accurately (2.0 is the outer,
repo-side layer; P1-5, `op=arm` G1 and the reviewer environment stand behind it).

**Worst-case review (CPO):** double-fire is the right worst case for a *widened* gate;
zero-fire is not introduced because nothing repoints `INNGEST_BASE_URL` or quiesces. A 2.0 pass
unlocks 2.1 capture (a snapshot POST, not a prod-data write), the 2.2 quiesce *verification*, and
a printed SEAM — the arm-flip and FLUSHALL stay behind `op=arm`'s own gates and the reviewer
environment, so the irreversible budget is genuinely untouched.

**Strategy (CPO):** none against the direction — widening the gate is strictly right over loosening
the guard, which is now the primary barrier and is baked into the host image. Caveat carried to
R1: the gate now depends on a noisy refuse loop staying noisy (tens of thousands of Better Stack
rows per day with no product value); quieting it is a CTO/COO decision for after the cutover, and
whoever takes it must know D2(b) is downstream.

### Plan Review Panel (2026-09-11)

**Panel:** DHH, Kieran, code-simplicity (eng baseline) + architecture-strategist, spec-flow-analyzer
(threshold escalation) + cto (named panel, devex lens — closing the Engineering gap left by the
rate-limited domain-leader spawn). All six returned. cpo was not re-spawned: its sign-off ran first,
with conditions applied. cmo and ux-design-lead: not relevant (no market/brand copy, no UI surface).

**Where both panels fired on one scope — delete over fix, applied:**
- **D2(b) on the flip-guard `BLOCK:` stream — CUT.** Simplification panel: ceremony that answers
  "why is the host dark" when the property is "does it carry a registry" (DHH P0, simplicity CUT).
  Correctness panel: unsatisfiable after any `stop_server` — an explicit stop does not re-fire
  `Restart=on-failure`, and the health workflow measured 5.4 days of exactly that; the remediation
  named a workflow that restarts the WEB scheduler and, post-quiesce, un-quiesces it (spec-flow P0
  ×2, architecture P1, CTO P1). Today's loop exists only because the host was replaced with the
  flag already `aborted`.

**Where the panels disagreed — resolution and class:**
- **Keep a freshness bridge at all?** DHH and simplicity: no — `cutover_flag` on the probe row
  suffices. Architecture (P1, findings 3/7) and CTO (P1, finding 2): yes — the probe row is ≤90 min
  old, and the flip FSM's heartbeat proves the flag was outside the arm set ~1 min ago, from the
  component that owns it, via the reader the script already has. **Resolved for the bridge
  (D2b′)** because it was MEASURED present (premise 13: 500 rows/24 h, `_BOOT_ID`-joined) before
  being adopted — the same rule that rejected the `BLOCK:` design. The dissent is recorded as
  **Taste** in `decision-challenges.md`.
- **Fix the sibling G8 (`== inactive`) here?** DHH: yes, once, in the shared prelude. Architecture
  (9d): record the divergence and file an issue — it is a destroy gate. **Resolved for the issue**;
  the divergence is in the lib header (Phase 2.5) and the sibling is asserted unchanged (AC18).
- **The reachable-arm `::warning::`?** Simplicity: cut (out of scope by the plan's own Non-Goals).
  CPO condition 4 and architecture 13: keep, name #8072. **Kept** — it is the founder's only view of
  an out-of-sequence host; recorded as **Taste** in `decision-challenges.md`.

**Mechanical findings applied (one right answer each):** E11 and E13 are POSITIVE allowlists
(`unknown`/`rollback`/empty refuse — architecture P0, Kieran 8); the production call is
`|| ERG_RC=$?`-guarded and the `source` is guarded, or `set -e` kills the script before any verdict
(architecture P1, Kieran 13, spec-flow 8); `_ihdg_graded_row` extracted and `_ihdg_row_count`'s
inline selector folded (DHH 2, simplicity a, Kieran 4, architecture 8); `mutate()` with
address-range scoping for per-gate rows and unscoped both-suites rows for helpers (architecture P1
finding 5, DHH 3); `_BOOT_ID` envelope equality replaces the `dt − uptime_s` join (dissolves Kieran
5/12, architecture 4/6/10, spec-flow 13/15); tokens collapsed onto the sibling's vocabulary — pass
token `dark`, `wrong_role`→`wrong_host`, `row_incoherent`/`registry_populated` gone (simplicity b/d,
DHH 4/5, architecture 12); `unreadable` remediations branch on the rc (Kieran 7, spec-flow 5); E11
allowlist derived from the guard's source by a set-equality test (CTO 3); `_FLOOR` `-ne`,
`_PRED_FLOOR` measured−1, Phase 1.4 deleted (CTO 4, Kieran 11); `M<n>` ids dropped — they collided
with the sibling's own `[M1]`–`[M7]` (Kieran 3) — cases keyed `[ERG En]`; AC7 scoped to the execute
arm and excluding the D4 echo (Kieran P0 — the un-scoped anchor first matched in `registry-probe)`
and AC7/AC8 could not both hold); AC9 diff-scoped denylist (Kieran 2); AC4 non-vacuous (Kieran 10);
AC5/AC6 comment-stripped (Kieran 9); AC19 drops the inert `cron_period_seconds` and gains literal
anchors and "the red X is the pass" (spec-flow 10/11); every "stop" token ends in a verb or "file an
issue" (spec-flow 9); E9/E10 check the webhook path before fearing a second scheduler (CTO 8,
spec-flow 7); E11 `flag_armed` branches on the value instead of pointing at `op=inventory`, which
does not read the flag (spec-flow 6); the 2.2 message gains the designed-stop sentence and the
maintenance-window warning (spec-flow P1 3/4); a producer-side C4 clause on `inngest -> betterstack`
(architecture 14); "what world does this predicate assume, and who owns it" added to the Guard
Contract (CTO strategy; templated by #8081).

**Follow-up issues filed from the panel (deferral tracking):** **#8077** watchdog quiesce suppression
(R7, spec-flow 4); **#8078** sibling G8 vs the live `activating` host (architecture 9d, DHH 2);
**#8079** `op=registry-probe` same defect (CTO 7); **#8080** post-cutover hardening — satisfiability
witness on `scheduled-inngest-health.yml` + `RestartSec` quieting with the ~55k rows/day figure on
the ledger (CTO strategy + loop recommendation); **#8081** the plan skill's Guard Contract gains an
"assumed world, and who owns it" field (CTO strategy — three instances in one week).

**Not applied, and why:** DHH 7 (the `## Hypotheses` walk and premise table are ceremony) — the
walk is mandated by the plan skill's network-outage checklist when `unreachable` appears in the
brief, and the premise table is the record of what changed the design; both stay. Architecture 9's
per-entry-point `_PRED_FLOOR` split — the `[ERG En]` keying already names the gate in a coverage
loss; not worth a second counter.

## Test Scenarios

| # | Scenario | Type | Steps | Expected |
|---|---|---|---|---|
| TS1 | Hermetic battery, dark arm | local, no credentials | `bash tests/scripts/test-inngest-host-dark-gate.sh` | AC1's exact output shape; `[ERG H5]` (`server_active=failed`, `cutover_flag=rolled-back`, heartbeat `flag=rolled-back`, unfamiliar `image_ref`, trailing unknown field) grades `dark`; every `mutate()` row in the matrix reddens its scope — rows 7–12 in BOTH suites |
| TS2 | Hermetic wiring suite | local, no credentials | `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` | AC2; the guarded-call, one-term-per-read, `*)`-exits-1, guarded-`source`, E11-set-equality and reachable-arm-unchanged assertions each print a PASS line |
| TS3 | Live read against the real host | read-only, `doppler run -p soleur -c prd_terraform` | Run the two Phase 0.1 reads; write each to a tempfile; call `inngest_execute_registry_gate --rows-file … --hb-file … --now-epoch "$(date +%s)"` with the live `--host`/`--host-name` | Token `dark`, rc 0. Probe row: `probe_schema=8 http_code=000 server_active!=active cutover_flag∈{aborted,rolled-back} host_role=dedicated registry_fns=__UNREADABLE__`; heartbeat: newest same-`_BOOT_ID` row ≤ 15 min old, `.message.flag=aborted` |
| TS4 | Live read, negative control | read-only | Same as TS3 with `--host soleur-web-platform --host-name soleur-web-platform-prd` | A refusal (`wrong_host` or `silent`), never `dark` — the co-located web host (`host_role=web`, `registry_fns=n/a`) must not grade dark |
| TS5 | Live read, previous-boot fixture | read-only | Same as TS3 but with `--hb-file` filtered to rows whose `_BOOT_ID` is the previous boot `906c015b…` (present in the 24 h window) | `fsm_silent` — a heartbeat from another boot must not attest this one (mutation #14 is the code-side twin) |
| TS6 | Credential failure is not silence | read-only | Run `_bs_query_rows` with `BETTERSTACK_QUERY_PASSWORD` unset | `betterstack-query.sh` exits 3; the gate receives `--query-rc 3` → `unreadable`, and the `::error::` names `PROBE_RC=3` and the three `BETTERSTACK_QUERY_*` names |
| TS7 | `set -euo pipefail` call shape | local | `bash -c 'set -euo pipefail; source tests/scripts/lib/inngest-host-dark-gate.sh; ERG_RC=0; V="$(inngest_execute_registry_gate --rows-file /dev/null --query-rc 0 …)" \|\| ERG_RC=$?; echo "$V $ERG_RC"'` | Prints `silent 1` (or `unreadable 1`) and the shell survives to print it — under a bare `$(…)` it would have died first |
| TS8 | The unblocked dispatch (post-merge, AC19) | live dispatch, pipeline-owned | `gh workflow run cutover-inngest.yml --ref main -f op=execute`; poll with the Monitor tool | The AC19 anchors in order; stops at 2.2 with the designed-stop sentence; nothing quiesced, armed or flushed |

