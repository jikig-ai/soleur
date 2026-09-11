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
| 9 | The flip-guard `BLOCK` marker carries the current `boot_id` | **FALSE.** `inngest-server-flip-guard.sh` logs under `readonly LOG_TAG` = `inngest-server-flip-guard` and its three `BLOCK:` lines carry no `boot_id` field. A `boot_id` join is not derivable from that stream | CORRECTED — see D2 |
| 10 | `registry_fns=__UNREADABLE__` is evidence of darkness | **Partly false.** The emitter sets it unconditionally on the first arm: `if [ "$http_code" != "200" ]; then … registry_fns=__UNREADABLE__`. On the dark arm it is *entailed by* `http_code=000` and carries no independent information | CORRECTED — see D3 |
| 11 | (unbriefed) the probe row cannot say *why* the host is dark | **FALSE.** `cutover_flag` is field 10 of the same row. The flip-guard's refusal cause is readable from the single row the gate already grades | CORRECTED — see D2 |
| 12 | (unbriefed) a Better Stack read from `op=execute` needs a new secret | **FALSE.** `scripts/cutover-inngest.sh` already reads Better Stack via `_flip_query_rows`, and the `op=execute` job already carries `DOPPLER_TOKEN` (prd_terraform, read-only) | HOLDS the design — no workflow secret change |

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
| `boot_id` equality between probe row and flip-guard row | corroboration | Not derivable — the guard emits no `boot_id`. Substituted by the boot-window join in D2. **CUT** |
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
| Corroborate the probe row with the flip-guard `BLOCK` marker "on the CURRENT `boot_id`" | `inngest-server-flip-guard.sh` emits three `BLOCK:` lines under `readonly LOG_TAG="inngest-server-flip-guard"`, none of which carries `boot_id`. The two streams share only `host`, `host_name` and `dt` | **D2.** Two-part substitute. (a) **Row-internal, mandatory:** the probe row's own `cutover_flag` field is read and required to be outside `{armed,flipping,flushed,done}` — the P1-5 refusal cause, on the same row, same boot, no join. (b) **Cross-stream, conditional:** a `BLOCK:` row from `SYSLOG_IDENTIFIER == "inngest-server-flip-guard"` with `dt` at or after `row.dt − uptime_s` (the current boot's start, since `uptime_s` is `cut -d. -f1 /proc/uptime`). (b) ships only if Phase 0's live probe proves such a row exists — see D5 |
| `probe_schema=8` carries the darkness evidence as `http_code=000`, `server_active` not active, `registry_fns=__UNREADABLE__` | True that all three are emitted, but `registry_fns=__UNREADABLE__` is set by the emitter's FIRST arm — `if [ "$http_code" != "200" ]; then … registry_fns=__UNREADABLE__` — so on the dark arm it is entailed by `http_code`, not independent of it | **D3.** `registry_fns=__UNREADABLE__` is kept, but as a **coherence** predicate in the shape of the existing G14 (`redis_keys==0` implies `redis_key_patterns==__NONE__`): a row asserting `http_code` non-200 while reporting a numeric count contradicts its own emitter and is refused as `row_incoherent`. The independent conjuncts are `http_code`, `server_active`, `host_role` and `cutover_flag` |
| The 2.0 remediation text presumes a dark host that is RUNNING but unarmed | Confirmed — 2.0's `::error::` still says *"(2) stop the dark inngest-server so nothing re-syncs functions"*, which the P1-5 guard has made impossible | **D4.** The remediation text is rewritten in the same edit. Leaving prose that instructs stopping a process that cannot start is the same defect one layer up |
| (unstated) the flip-guard `BLOCK` marker is reliably present | Every `logger` call in the guard is `2>/dev/null || true`, and it fires from `ExecStartPre`, so it is emitted only when systemd actually attempts a start. **Absence proves nothing** | **D5.** The corroborator's SATISFIABILITY is measured before it is shipped. Phase 0 runs one read against the live host's current boot; if no `BLOCK:` row is found in that window, conjunct (b) is dropped and the plan ships the row-internal conjunction alone. Shipping an unmeasured conjunct is precisely the #8054 defect recurring one layer over |
| `registry_fns` numeric > 0 must REFUSE | Confirmed and load-bearing, but note `registry_fns` is `n/a` on a **web-host** row, so the host conjunction must run first or the co-located web host grades as dark | **D6.** The `_IHDG_SELECT` host conjunction (`$d.host == $h and $d.host_name == $hn`) runs before any field read, and a separate `host_role == dedicated` predicate is asserted as belt-and-braces (`wrong_role`) |

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
one additional read of rows the host already emits; it must not begin echoing row CONTENT into CI
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
| `tests/scripts/lib/inngest-host-dark-gate.sh` | Add ONE new public entry point, `inngest_execute_registry_gate`, beside `inngest_host_dark_gate`. It reuses `_IHDG_SELECT`, `_ihdg_rows`, `_ihdg_newest_dt`, `_ihdg_row_count`, `_ihdg_tied_newest` and `_ihdg_field` **verbatim** — no second selector. Adds `_ihdg_guard_block_count` (the flip-guard stream reader, field-isolated on `SYSLOG_IDENTIFIER`) and `_ierg_verdict` (rc 0 only on the literal `dark-empty`) |
| `tests/scripts/test-inngest-host-dark-gate.sh` | Extend `bs_line` to take a `SYSLOG_IDENTIFIER` (today it hardcodes `"inngest-server-probe"`), add the must-REFUSE battery below, add `registry_fns` to the B12 consumed-field list, and RAISE both floors — `_PRED_FLOOR=22` and `_FLOOR=124` — to the new measured values |
| `scripts/cutover-inngest.sh` | 2.0 gains the second arm: `_probe_query_rows` + `_guard_block_query_rows` readers mirroring `_flip_query_rows`, a source of the gate lib, the gate call, and a `case` over the verdict token. The existing 200/`registry_empty` logic is byte-for-byte unchanged. The non-empty remediation text is corrected (D4) |
| `apps/web-platform/infra/cutover-inngest-workflow.test.sh` | Add the wiring + dispatch assertions: 2.0 routes through exactly one gate call, every verdict token has an arm, the unrecognised-token arm exits 1, and the reader passes host isolation post-decode rather than via `--grep` |
| `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` | New dated addendum (see `## Architecture Decision`) |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | ONE edge-description edit on `github -> betterstack`: it currently names `op=verify` as the sole SAFETY-CRITICAL cutover read of the Logs warehouse; this plan adds `op=execute` 2.0 as a second, so the sentence is falsified as written (see `## Architecture Decision`) |

Phase 5's wiring suite also asserts that the two new readers pass exactly one `--grep` term each —
the property Phase 0.1 measured the combined form violating.

`.github/workflows/cutover-inngest.yml` is deliberately **absent** from this list: the `op=execute`
job already carries `DOPPLER_TOKEN` (prd_terraform, read-only), which is the only credential
`betterstack-query.sh` needs, and `scripts/cutover-inngest.sh` is not a baked carrier.

## Files to Create

None. Every artifact this change needs already exists; adding a file would create the second reader
this plan exists to avoid.

## Open Code-Review Overlap

**None.** Sixty-five open `code-review` issues were fetched and each of the five planned paths was
searched against every issue body with `jq --arg`. Zero matches.

## Implementation Phases

### Phase 0 — Measure before designing anything that depends on a measurement

Phase 0 exists because #8054 IS the cost of skipping it: a predicate was written against a world
nobody re-measured. Nothing in Phase 1 may proceed on an unmeasured premise.

0.1 **Satisfiability of the corroborator (D5) — the fork that decides the design.** TWO reads, from
the worktree, against the live host's current boot — one per stream:

```
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
  --since 24h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 500
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
  --since 24h --grep inngest-server-flip-guard --limit 500
```

**They MUST be separate reads, and this was measured, not reasoned.** An earlier draft of this step
OR-combined both `--grep` terms into one read. Run at plan time (2026-09-11T10:56Z) that single read
returned exactly 500 rows: 271 under `SYSLOG_IDENTIFIER=doppler` (the guard's `doppler run` wrapper
noise) + 229 under `inngest-server-flip-guard` — and **zero** probe rows. The P1-5 refusal is a
`Restart=` loop firing every few seconds, so its two streams fill a 500-row window in roughly an
hour and the hourly probe row is starved out of the limit every time. A combined read therefore
grades `silent` against a host that is emitting perfectly, which is the #7674-class false reading
this whole plan exists to avoid. Host isolation still happens after decoding, never in `--grep`.
From the two results establish:

- the newest probe row for `host=soleur-inngest host_name=soleur-inngest-prd`, and its
  `boot_id`, `uptime_s`, `probe_schema`, `http_code`, `server_active`, `cutover_flag`,
  `host_role`, `registry_fns`;
- whether at least one row with `SYSLOG_IDENTIFIER == "inngest-server-flip-guard"` and a message
  beginning `BLOCK: ` has `dt >= (probe row dt − uptime_s)`.

**Fork.** If such a `BLOCK:` row exists → conjunct D2(b) ships as a required predicate. If it does
NOT → D2(b) is **dropped** and the plan ships the row-internal conjunction alone; record the
measurement and the drop in the plan and in the ADR addendum. Do not ship a predicate whose
satisfiability was never observed.

**Fork RESOLVED at plan time (2026-09-11T10:56Z) — D2(b) SHIPS as required.** Measured against the
live host with the two separate reads above:

| Read | Result |
|---|---|
| Probe stream | rc 0, 49 rows, **25** dedicated-host rows in 24h. Newest (dt `2026-09-11 10:00:55`): `boot_id=402c0d5b-1cf3-495a-92e1-cf137732156f uptime_s=46908 probe_schema=8 http_code=000 server_active=activating cutover_flag=aborted host_role=dedicated registry_fns=__UNREADABLE__ redis_keys=16` |
| Guard stream | **229** `BLOCK: ` rows under `SYSLOG_IDENTIFIER=inngest-server-flip-guard` for `host=soleur-inngest` in a 500-row window; oldest in window `2026-09-11 10:43:45`, newest `2026-09-11 10:56:21` |
| Join | boot start = `10:00:55 − 46908 s` = `2026-09-10 20:59:07`; every `BLOCK:` row in the window is ≥ that. **Satisfied.** |

Two consequences the design must carry: (i) `server_active` reads `activating` — the `Restart=` loop
never settles to `inactive` — so the dark conjunct is `server_active != active`, never
`server_active == inactive` (mutation #2 and must-PASS row H5 already encode this); (ii) at ~229
`BLOCK:` rows per 500-row window, a `--limit 500` guard read spans roughly the most recent hour,
which is sufficient for "≥ 1 row at or after boot start" but means D2(b) **depends on the refuse
loop still running** — see `## Dependencies & Risks`, R1.

/work re-runs 0.1 as a freshness check (the state can change under a long pipeline), but the fork
is closed: a re-run that finds NO `BLOCK:` row is a **new finding to stop on**, not a licence to
silently drop D2(b).

0.2 **Confirm the live row already satisfies the intended dark conjunction.** Against
`boot_id=402c0d5b`, `probe_schema=8`, `cutover_flag=aborted`, `INNGEST_DIAGNOSTIC_BOOT=0`: the row
must read `http_code=000`, `server_active` not `active`, `host_role=dedicated`,
`registry_fns=__UNREADABLE__`. If any field disagrees, the design premise is wrong and Phase 1 stops.

**Measured at plan time: every field agrees** (the 0.1 probe-stream row above). `server_active` is
`activating`, not `inactive`, which the conjunction admits by design.

0.3 **Confirm the credential path.** `betterstack-query.sh` exits 3 when
`BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` are not injected, and that 3 must never be read as
"nothing found". Confirm the `op=execute` job's `DOPPLER_TOKEN` resolves `prd_terraform` and that
the new reader distinguishes rc 3 from rc 0-with-zero-rows.

0.4 **Baseline the floors.** Record today's values so the raise is derived, not guessed:
`grep -n '_PRED_FLOOR=\|_FLOOR=' tests/scripts/test-inngest-host-dark-gate.sh` and the green
assertion count from `bash tests/scripts/test-inngest-host-dark-gate.sh`.

**Measured at plan time (2026-09-11, tree `0d97ede5c`):** `_PRED_FLOOR=22`, `_FLOOR=124`; the suite
prints `drop-one floor: 23 distinct predicates covered across 23 cases (floor 22)`,
`anti-vacuity floor: 124 assertions ran (floor 124)`, `inngest-host-dark-gate: 124 passed, 0 failed`.
The anti-vacuity floor is EXACT (124 == 124), which is the property Phase 1.4 must preserve: the
raise lands on the new measured count, never on `>=` slack.

0.5 **Baseline the sibling suite.** Record the current pass count of
`bash apps/web-platform/infra/cutover-inngest-workflow.test.sh`.

**Measured at plan time:** `PASS: anti-deletion floor (497 >= 497 assertions dispatched)`,
`=== Results: 497 passed, 0 failed ===`. Phase 5's additions raise that floor too.

### Phase 1 — Write the mutation matrix and the failing battery FIRST

`cq-write-failing-tests-before`. The matrix in `## Guard Contract` is derived from the DESIGN in
this document, not from code that does not yet exist. Land the battery RED before the gate.

1.1 Extend `bs_line` to accept a `SYSLOG_IDENTIFIER` argument, defaulting to
`inngest-server-probe` so every existing call site is unchanged, and add a `guard_line` helper that
builds a flip-guard `BLOCK:` row.

1.2 Add `expect_erg` / `predicate_erg` mirroring the existing `expect` / `predicate` — assert the
**token** and the rc together, with rc 0 expected only for `dark-empty` — plus their wrapper
self-tests (the existing suite self-tests all four of its helpers and rolls the counters back;
neutering one previously left it at "112 passed, 0 failed").

1.3 Write every row of the mutation matrix, plus the harness rows, as failing cases. **Each case
name carries its matrix row id** — `M1`…`M19` for the mutation rows, `H1`…`H6` for the harness
rows — so AC16 can prove the contract and the suite name the same set, and a row added to one
without the other reddens the AC rather than drifting silently.

1.4 Raise `_PRED_FLOOR` and `_FLOOR` to the values Phase 3 measures. The file's own comment records
that the slack is deliberately one, so the raise is exact, never `>=`.

### Phase 2 — `inngest_execute_registry_gate` in the existing gate library

2.1 Add the entry point beside `inngest_host_dark_gate` in
`tests/scripts/lib/inngest-host-dark-gate.sh`. It takes `--rows-file`, `--query-rc`,
`--guard-file`, `--guard-rc`, `--now-epoch`, `--max-row-age`, `--host`, `--host-name`,
`--expected-schema`, and echoes exactly one verdict token.

2.2 Reuse `_IHDG_SELECT`, `_ihdg_rows`, `_ihdg_newest_dt`, `_ihdg_row_count`, `_ihdg_tied_newest`
and `_ihdg_field` **without copying or re-deriving any of them**. The whole point of the placement
is that one tightening of `_IHDG_SELECT` reddens both consumers at once.

2.3 Add `_ihdg_guard_block_count` — decode `.raw`, require
`.SYSLOG_IDENTIFIER == "inngest-server-flip-guard"`, require `$d.host == $h and $d.host_name == $hn`,
require the message to start `BLOCK: `, and require `dt >= boot_start`. Field-isolate on
`SYSLOG_IDENTIFIER`; the tag never appears inside `.message`, so a `test("^inngest-server-flip-guard")`
over the message is a permanent zero-match.

2.4 Add `_ierg_verdict` — echo the token, rc 0 only for the literal `dark-empty`. A positive
allowlist, exactly as `_ihdg_verdict` is: every other token, `unreadable` included, refuses.

2.5 Predicate order is E1 → E14 as listed in the Guard Contract, and the ordering is load-bearing
for the DIAGNOSIS: identity population is measured before the silence check so a wrong-host window
reports `wrong_host` rather than `silent`.

### Phase 3 — Turn the battery green, then re-derive the floors

Run the suite; raise `_PRED_FLOOR` / `_FLOOR` to the measured values from a green run.

### Phase 4 — Wire 2.0

4.1 Add `_probe_query_rows` and `_guard_block_query_rows` beside `_flip_query_rows`, same transport,
same `|| rc=$?` shape, returning the query's rc so the caller owns its failure semantics. **Each
reader issues its own `betterstack-query.sh` invocation with exactly ONE `--grep` term** — the
probe reader greps only `SOLEUR_INNGEST_SERVER_PROBE`, the guard reader only
`inngest-server-flip-guard`. Never OR-combine them: Phase 0.1 measured the combined form returning
500 rows and zero probe rows, because the refuse loop's two streams (`inngest-server-flip-guard`
+ its `doppler` wrapper noise) fill the window. Phase 5 asserts the one-term-per-reader property.

4.2 In the `execute)` arm, leave the HTTP-200 path byte-for-byte unchanged. Replace **only** the
`if [[ "$CODE" != "200" ]]; then … exit 1; fi` branch with: log the HTTP code and cause as a notice,
source the gate library, run the two reads, call `inngest_execute_registry_gate`, and `case` on the
token. `dark-empty` emits a `::notice::` naming the row's `boot_id`, `cutover_flag` and row age
**and stating in plain words that dark is the intended, safe pre-flip posture** (E14's wording —
the annotation text is the founder's entire view of this step, and `http_code=000` beside a green
tick must not read as a fault), then falls through to 2.1. Every other token emits `::error::` with
the remediation the E-table names for that token and `exit 1`. An unrecognised token exits 1
fail-closed, mirroring G3.6's `*)` arm.

**The HTTP-200 arm gains one `::warning::`, nothing else.** Since ADR-100's 2026-08-20 addendum the
dark slot holds the prod DSN as steady state, so a dedicated host that *answers* at `execute` time
means either the P1-5 guard did not hold or `op=arm` already ran — a 200 here is an out-of-sequence
signal. The arm's decision logic stays byte-for-byte (AC7) because a reachable-EMPTY host still
satisfies the gate's property; the warning names the sequencing question. It is emitted **after** the
existing `pre-flight clear` notice, outside the range AC7 diffs, so the arm's decision logic is
provably untouched. Changing that arm's behaviour is tracked as **#8072**, not folded in here.

4.3 Correct the non-empty remediation text (D4): step (2) can no longer instruct stopping a process
the P1-5 guard will not start. Replace with the flag-and-registry path that is actually available.

4.4 Adopt the purity contract verbatim — counts and single extracted fields only, never a whole row,
never a GQL body. The rows the two readers return are captured into variables and written to
tempfiles for `--rows-file` / `--guard-file`; the ONLY values that may reach an `echo "::…"` line
are the six singles `ERG_VERDICT`, `ERG_BOOT_ID`, `ERG_FLAG`, `ERG_ROW_AGE`, `ERG_GUARD_COUNT`,
plus the two reader rcs `PROBE_RC` / `GUARD_RC`. AC9 enumerates the closed set and Phase 5 asserts
it, so a whole-row variable appearing in an annotation is a suite failure, not a review finding.

### Phase 5 — Wiring assertions in the sibling suite

Add to `apps/web-platform/infra/cutover-inngest-workflow.test.sh`: 2.0 routes through exactly one
`inngest_execute_registry_gate` call; every verdict token the gate can emit has a matching `case`
arm; the `*)` arm exits 1; the readers isolate host post-decode and pass no host term to `--grep`;
and the HTTP-200 path is unchanged.

### Phase 6 — ADR addendum, then the full battery

6.1 Write the ADR-100 addendum (see `## Architecture Decision`), including Phase 0.1's measurement
and the D5 fork outcome. Amend the `github -> betterstack` edge description in
`knowledge-base/engineering/architecture/diagrams/model.c4` so `op=execute` 2.0 is named beside
`op=verify` as a safety-critical Logs read, then run the C4 syntax + render suites (AC14).

6.2 `shellcheck` both edited shell files; run `bash scripts/test-all.sh` for the full battery, not
only the touched shards — `tests/scripts/test-inngest-host-dark-gate.sh` is registered by an
explicit `run_suite` line at `scripts/test-all.sh`'s `#7695 — the two guards on
apply_target=inngest-volume-recut` comment, and nothing auto-discovers `tests/scripts/`.

6.3 Run `python3 scripts/lint-guard-contract.py` against this plan and
`bash scripts/lint-orphan-test-suites.sh`.

## Guard Contract

### Guard 1 — inngest_execute_registry_gate

**Property.** `op=execute` proceeds past 2.0 only when the dedicated inngest host is established,
from evidence the host itself emitted, to be carrying no function registry that could double-fire —
either because it answered and reported an empty registry, or because it is positively dark. Every
other state, including every state in which the host's condition cannot be established, refuses.

**Assembly.** The quantification is over three chokepoints, and naming them structurally rather than
by today's members is the point. (1) **Row selection** — every consumer of a
`SOLEUR_INNGEST_SERVER_PROBE` row flows through `_IHDG_SELECT` and the four helpers that embed it
(`_ihdg_rows`, `_ihdg_newest_dt`, `_ihdg_row_count`, `_ihdg_tied_newest`); a fifth reader added
outside that set is the defect this contract exists to catch, and `_ihdg_field` is the sole field
extractor. (2) **Verdict dispatch** — `_ierg_verdict` is the only place a token becomes an rc, and
2.0's `case` is the only place a token becomes control flow; both must be single chokepoints, and a
second `exit 0`/fall-through path reachable from 2.0 is a breach. (3) **Evidence acquisition** —
`_probe_query_rows` and `_guard_block_query_rows` are the only paths by which rows enter the gate,
and both must return the query's rc rather than swallowing it. The `_ihdg_*` helpers are shared with
`inngest_host_dark_gate`, so a tightening of any of them must redden BOTH suites; a change that
reddens only one means a copy was made.

**Predicates, in evaluation order, and the token each refusal emits.** The order is load-bearing for
the DIAGNOSIS (population before silence, identity before content): every token names one cause,
and `dark-empty` is reachable only by passing all fourteen. Every remediation is a `gh workflow run`
verb or a host-replace dispatch — none is an SSH step (`hr-no-ssh-fallback-in-runbooks`).

| E | Predicate (from the graded probe row unless stated) | Refusal token | Remediation the `::error::` names |
|---|---|---|---|
| E1 | probe `--query-rc` is numeric and `0` | `unreadable` | The Better Stack read path did not answer (precedent: HTTP 503 "source under maintenance"), or `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` are not injected (exit 3). Verify the three in `prd_terraform`; re-dispatch when the read path is healthy. Nothing about the host was measured |
| E2 | `--rows-file` exists and decodes | `unreadable` | as E1 |
| E3 | window holds ≥ 1 row from ANY host; then ≥ 1 row with `host==soleur-inngest && host_name==soleur-inngest-prd` | `silent` (zero rows) / `wrong_host` (rows, none ours) | `silent`: the host emits nothing — cross-check `scheduled-inngest-health.yml`'s latest run; two consecutive probe-unavailable readings there make it a host replace (`apply-web-platform-infra.yml -f apply_target=inngest-host-replace`), the only no-SSH path to a dead Vector/timer. `wrong_host`: an identity mislabel (#6616 class) — stop; do not proceed |
| E4 | the newest row is the graded row and is tie-free (`_ihdg_tied_newest`) | `unreadable` | Two rows at the same newest `dt` disagree — the emitter or the warehouse is inconsistent; wait one probe period and re-dispatch |
| E5 | row age ≤ `--max-row-age` | `stale_row` | The newest row predates the bound — wait for the next hourly probe (≤ 60 min) and re-dispatch; if it stays stale, treat as `silent` |
| E6 | `probe_schema == "8"` (exact) | `stale_schema` | The host runs a pre-schema-8 renderer. The emitter is baked, so this is a host replace on a pin that carries the emitter — confirm first with the dark gate's own tag check (`git show vinngest-<pin>:apps/web-platform/infra/inngest-bootstrap.sh \| grep -c probe_schema=8`); a replace on an unbumped pin re-delivers the same bytes |
| E7 | `boot_id` present and non-empty | `unreadable` | The row is truncated (the #7674 field-order lesson) — treat as E1 |
| E8 | `host_role == dedicated` | `wrong_role` | A web-host row reached the dedicated selector — identity mislabel (#6616 class); stop |
| E9 | `http_code` is numeric and `!= 200` | `host_serving` | The host IS answering pre-arm. This is the second-scheduler precursor: STOP, run `op=doublefire-probe -f cron_period_seconds=1200`, do not proceed to 2.1 |
| E10 | `server_active != active` | `host_serving` | as E9 |
| E11 | `cutover_flag ∉ {armed, flipping, flushed, done}` | `flag_armed` | `INNGEST_CUTOVER_FLIP` is inside the arm allowlist — an arm is in flight or complete and `execute` is out of sequence. Read the flag (`op=inventory`); if `done`, the cutover has already happened |
| E12 | coherence: `http_code != 200` ⇒ `registry_fns == __UNREADABLE__`. A numeric `^[1-9][0-9]*$` is its own token; `0` or any other value on a non-200 row contradicts the emitter | `registry_populated` / `row_incoherent` | `registry_populated`: the P1-6 abort — the host carries functions; STOP. `row_incoherent`: the emitter contradicts itself — treat as `unreadable` and file an issue against `inngest-bootstrap.sh` |
| E13 | guard `--guard-rc` is `0` AND ≥ 1 row with `SYSLOG_IDENTIFIER == inngest-server-flip-guard`, same host pair, message starting `BLOCK: `, `dt ≥ row.dt − uptime_s` | `unreadable` (rc) / `guard_unattested` (no row) | `guard_unattested`: the probe row is dark but the guard has not refused a start inside this boot's window — the refuse loop has quieted (R1). Dispatch `restart-inngest-server.yml`: on a dark host it re-attempts a start, which re-emits `BLOCK:`; re-dispatch `execute` after the next probe |
| E14 | all of E1–E13 hold | **`dark-empty`** (rc 0) | Proceeds to 2.1. The `::notice::` MUST say, in plain words: *"the dedicated host is intentionally refusing to start until `op=arm`; `http_code=000 server_active=activating` is the correct pre-flip posture, not a fault"* — a founder reading a green step beside `000` must not go looking for a fix that must not be applied |

**Mutation matrix**

| # | Mutation (derived from the design, not from the code) | Must drive |
|---|---|---|
| 1 | Delete the `registry_fns` numeric-greater-than-zero refusal | RED — token `registry_populated` no longer emitted |
| 2 | Delete the `server_active != active` conjunct | RED — a serving host with a broken loopback grades `dark-empty` |
| 3 | Delete the `http_code == 000` conjunct | RED |
| 4 | Delete the `cutover_flag ∉ {armed,flipping,flushed,done}` conjunct | RED — token `flag_armed` unreachable |
| 5 | Delete the `host_role == dedicated` conjunct | RED — a web-host row (`registry_fns=n/a`) grades dark |
| 6 | Delete the coherence conjunct (non-200 implies `registry_fns=__UNREADABLE__`) | RED — token `row_incoherent` unreachable |
| 7 | Weaken `probe_schema` from exact `== "8"` to `>=` | RED |
| 8 | Change the zero-row arm from refuse to pass | RED — `silent` becomes `dark-empty` |
| 9 | Change the non-zero `--query-rc` arm from refuse to pass | RED — `unreadable` becomes `dark-empty` |
| 10 | Widen `--max-row-age` so a stale newest row passes | RED — `stale_row` unreachable |
| 11 | Replace `_IHDG_SELECT` in `_ihdg_newest_dt` only, with a copy that drops the host conjunction | RED **in both suites** — a foreign fresh row supplies the recency bound |
| 12 | Make `_ierg_verdict` return rc 0 for any token, not only `dark-empty` | RED — every refusal case's rc assertion flips |
| 13 | Add a SECOND member: after a compliant first probe row, add a second row at the same newest `dt` that disagrees | RED — tie disagreement must refuse, not take file order |
| 14 | **Guard's own dispatch:** make `inngest_execute_registry_gate` return before evaluating any predicate, echoing `dark-empty` | RED — the anti-vacuity floor must fire, not report `0 checked, ok` |
| 15 | Delete the `boot_id` presence check | RED |
| 16 | Delete `_probe_query_rows`'s `|| rc=$?` so a failed query returns rc 0 with empty rows | RED — a dead read must not present as silence-then-refusal-for-the-wrong-reason |
| 17 | Move the guard-marker read so it observes a window that starts BEFORE `row.dt − uptime_s` | RED — a previous boot's `BLOCK:` row must not attest the current one |
| 18 | Replace 2.0's `case` `*)` fail-closed arm with a fall-through | RED — an unrecognised token must never proceed |
| 19 | Collapse `_probe_query_rows` + `_guard_block_query_rows` into ONE `betterstack-query.sh` call carrying both `--grep` terms | RED — Phase 5's one-term-per-reader assertion; measured at plan time to return 500 rows and zero probe rows, i.e. a false `silent` |

**Harness rows.** The matrix above mutates the system under test; these mutate the SUITE, because a
matrix that never touches the harness cannot see a harness that asserts nothing.

| # | Harness mutation or input | Must drive |
|---|---|---|
| H1 | Neuter `expect_erg` so it compares only the token and ignores the rc | RED — at least one case must depend on the rc alone |
| H2 | Neuter `predicate_erg`'s distinct-predicate accounting so every case registers the same `En` | RED — `_PRED_FLOOR` must fire |
| H3 | Delete one `fails=$((fails + 1))` increment | RED — a floor that dispatches through its own counter is not a floor |
| H4 | Lower `_FLOOR` below the measured green count | RED — the floor must be exact, never `>=` slack |
| H5 | **Must-PASS, non-canonical:** a probe row with `server_active=failed` (not `inactive`), a different `boot_id`, an unfamiliar `image_ref`, a row age well inside the bound, and an extra trailing field the gate does not consume | PASS `dark-empty` — the contract permits every one of these, and a suite whose only PASS input is the canonical fixture cannot tell a correct gate from one that rejects everything |
| H6 | **Must-PASS, non-canonical:** the reachable-empty arm — `http_code=200`, `server_active=active`, `registry_fns=0` reached through the WEBHOOK path, with no probe row at all | PASS — the pre-existing arm must remain reachable and must not be routed through the new gate |

## Observability

```yaml
liveness_signal:
  what: >-
    The 2.0 verdict line itself. On the dark arm, a `::notice::` naming the graded row's
    boot_id, cutover_flag, row age and the verdict token `dark-empty`; on every refusal an
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
    Yes, and fail-closed. Every non-`dark-empty` token exits 1. `betterstack-query.sh`
    exit 3 (credentials not injected) is mapped to its OWN token, never to "no rows found" —
    the two have opposite remedies and only one of them is a wait.
failure_modes:
  - mode: The Better Stack read path is down (measured precedent: HTTP 503 "This source is currently under maintenance")
    detection: non-zero `--query-rc` reaching the gate; verdict token `unreadable`
    alert_route: "`::error::` + exit 1 on the op=execute run; the operator re-runs when the read path recovers"
  - mode: The credentials are not injected into the job
    detection: "`betterstack-query.sh` exit 3, mapped to a distinct token, never to `silent`"
    alert_route: "`::error::` naming `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` in prd_terraform"
  - mode: The host has stopped emitting probe rows (timer or Vector down)
    detection: zero qualifying rows with a successful read; verdict token `silent`
    alert_route: "`::error::` + exit 1. Cross-checked by `scheduled-inngest-health.yml`, which reads the same marker on a schedule and classifies via `classify_dedicated_host`"
  - mode: The host is emitting from a pre-`probe_schema=8` renderer
    detection: exact-equality schema check fails; verdict token `stale_schema`
    alert_route: "`::error::` naming the replace-only delivery constraint — the emitter is baked, so this is actionable as a host replace with a bumped pin, not as a retry"
  - mode: The host is reachable and CARRYING functions (the double-fire precursor)
    detection: "`registry_fns` matching `^[1-9][0-9]*$`, or the webhook arm's `registry_empty=false`; tokens `registry_populated` / the existing 2.0 ABORT"
    alert_route: "`::error::` + exit 1 with the P1-6 remediation"
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
| R1 | **D2(b) depends on the P1-5 refuse loop still running.** The corroborating `BLOCK:` row is emitted from `ExecStartPre` only when systemd attempts a start. Today the unit retries every few seconds (229 rows per 500-row window, measured), so the row is always fresh. If a future change adds a `StartLimitBurst` that lets the unit settle to `failed`, `BLOCK:` rows stop, age past the read window, and D2(b) refuses a host that is legitimately dark — a **fail-closed** false refusal that blocks the cutover, never a false pass. | The refusal token names the cause (`guard_unattested`) and its `::error::` names the no-SSH remedy that exists today: `.github/workflows/restart-inngest-server.yml` re-attempts a start, which re-emits a `BLOCK:` row on a dark host. Recorded in the ADR-100 addendum in one sentence — *"any change that quiets the P1-5 refuse loop (start-limit, backoff, clean stop) must re-measure D2(b) or 2.0 refuses again"* — so the next well-meaning noise-reduction PR knows what it is disarming. |
| R2 | **Stream starvation in the Better Stack read.** Measured at plan time: an OR-combined read of both streams returns 500 rows and zero probe rows. | Two reads, one `--grep` term each (Phase 4.1); Phase 5 asserts the property; mutation #19 reddens on regression. |
| R3 | **The read window and the probe cadence.** The probe fires hourly; `--max-row-age` must exceed one probe period plus Vector/warehouse lag or a healthy host grades `stale_row` between probes. The sibling gate's own G3 sets the precedent. | Reuse the dark gate's `--max-row-age` default rather than inventing one; the H5 must-PASS row uses an age "well inside the bound", and one RED row (#10) proves the bound bites. |
| R4 | **A second reader drifts from the first.** The whole class of #8017 and #8054 is two readers of one row disagreeing. | The new entry point shares `_IHDG_SELECT` and every `_ihdg_*` helper by construction; mutation #11 requires a tightening to redden BOTH suites; `## Files to Create` is empty. |
| R5 | **Transport confinement on the `github -> betterstack` edge (#7873 / ADR-202).** Every credentialed curl on that edge must be `--disable`/`--noproxy` confined. | The new readers add NO curl — both call `scripts/betterstack-query.sh`, which owns the transport. `lint-shell-trace-credential-refusal.py` Rule D runs on every touched file. |
| R6 | **The planning pipeline itself hit an API rate limit** (three research/domain agents terminated with HTTP 429 on 2026-09-11; weekly limit, resets 2026-09-16). | The plan body was recovered from disk and completed inline; Phase 0 was measured directly rather than delegated. `## Domain Review` records which leaders actually ran and which did not, so nothing reads as reviewed that was not. |

**Dependencies.** PR #8019 (merged 2026-09-10) — `probe_schema=8` and the `registry_fns` field the
new arm reads are on the live host (measured: `image_ref=…v1.1.35@sha256:c8e27c71…`,
`probe_schema=8`). No other PR must land first.

## Architecture Decision (ADR/C4)

The plan changes what the cutover orchestrator accepts as evidence of a safe pre-flip state, and
adds a second safety-critical CI read of the Logs warehouse. A competent engineer reading only
ADR-100 and the C4 model after this ships would be misled on both counts, so both are deliverables
here — not follow-ups.

### ADR

**Amend ADR-100** (`knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`)
with a dated addendum in its existing convention — heading
`## Addendum — 2026-09-11 (#8054) — "host dark" is a positive reading, and 2.0 accepts it`. No new
ordinal: the 2026-08-25 (#7674) addendum already decided the adjacent question (*"host dark" is
not "query finds nothing"*), and this is its direct continuation. (Fallback if review rules an
addendum insufficient: next free ordinal measured **215** on `origin/main`, **216** across all
`origin/*` refs — provisional until merge per the ordinal-collision gate.)

The addendum records, as decision text: (1) the P1-5 guard and 2.0 were written against different
worlds, and the guard is the one that is right; (2) 2.0's property is *not carrying a double-fire
registry*, satisfied by reachable-empty OR positively-dark, never by silence; (3) the row-internal
conjunction (D2a) is the primary evidence and `cutover_flag` on the probe row is the P1-5 cause
read without a join; (4) the D5 fork outcome — `BLOCK:` corroboration measured satisfiable
2026-09-11T10:56Z and shipped as required — with R1's dependency on the refuse loop stated
plainly and the sentence *"any change that quiets the P1-5 refuse loop (start-limit, backoff, clean stop) must re-measure D2(b) or 2.0 refuses again"*; (5) the stream-starvation measurement and the one-`--grep`-per-reader rule it forces.

### C4 views

All three model files were read (`model.c4` 710 lines, `views.c4` 74, `spec.c4` 54), and the
external actors, systems, containers and relationships this change touches were enumerated:

| Actor / system / container / relationship | Modeled? | Disposition |
|---|---|---|
| Dedicated Inngest host (`inngest` container, `hetzner -> inngest` "dedicated single-host node, private-net 10.0.1.40") | yes | unchanged |
| `inngestRedis`, `inngestPostgres` | yes | unchanged — this plan reads neither |
| Better Stack as the Logs warehouse (`betterstack` system; `inngest -> betterstack` ships journald via Vector) | yes | unchanged |
| GitHub Actions as the cutover orchestrator (`github` system; `github -> tunnel` for the webhook path) | yes | unchanged |
| **`github -> betterstack`** — the CI read of the warehouse | yes, but its description names `op=verify` as the sole *SAFETY-CRITICAL* cutover read | **EDIT** — the sentence beginning `SINCE #6178/ADR-146 this edge also carries a SAFETY-CRITICAL read: cutover-inngest.yml op=verify …` gains `op=execute` 2.0 (the probe-row + flip-guard-row read; a retention miss or query failure refuses 2.0 closed, exactly as it fails `verify` closed). The `--disable`/`--noproxy` obligation already stated on that edge is inherited via `betterstack-query.sh`, so no new transport is introduced |
| Human actors | none new — the reads are CI-initiated, no operator in the loop | unchanged |
| Data stores | none new | unchanged |

No element is added, so `views.c4` needs no `include` change. Validation after the edit:
`cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.
(The `c4-count-parity` gate named in the plan skill was looked for and is not present on this tree
— `git ls-files | grep -i count-parity` returns nothing — so the edge-description edit is the whole
C4 change and the syntax/render suites are the validation.)

### Sequencing

The ADR addendum and the `.c4` edit land in the same PR as the code (Phase 6.1), before the
full-battery run. Nothing here is soak-gated: the decision is true the moment the gate widens.

## Acceptance Criteria

Every criterion is a checkable post-condition on file state or command output, anchored on a
dispatch or a token — never a bare literal the file also documents, never a line number. All
pre-merge criteria run in CI or locally with no credentials except where stated.

### Pre-merge (PR)

- [ ] **AC1 — dark-gate battery green, floors raised exactly.** `bash tests/scripts/test-inngest-host-dark-gate.sh` exits 0; its last line matches `^inngest-host-dark-gate: [0-9]+ passed, 0 failed$` with the passed count **> 124** (the plan-time baseline); the two floor lines print, and the anti-vacuity line's ran-count EQUALS its floor (`grep -oE 'anti-vacuity floor: ([0-9]+) assertions ran \(floor \1\)'` matches — exact, no slack, as the file's own comment requires).
- [ ] **AC2 — wiring suite green, floor raised.** `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` exits 0; last line matches `^=== Results: [0-9]+ passed, 0 failed ===$` with the count **> 497**.
- [ ] **AC3 — one entry point, one selector, one lib.** `grep -cE '^inngest_execute_registry_gate\(\) \{' tests/scripts/lib/inngest-host-dark-gate.sh` → `1`; `grep -cE '^_IHDG_SELECT=' tests/scripts/lib/inngest-host-dark-gate.sh` → `1`; `git diff --name-only origin/main -- tests/scripts/lib/ | wc -l` → `1` (only the dark-gate lib changed under that directory — no sibling reader was created).
- [ ] **AC4 — positive allowlist, every refusal token exercised.** `grep -cE '^_ierg_verdict\(\) \{' tests/scripts/lib/inngest-host-dark-gate.sh` → `1`. For every token `T` in `grep -oE '_ierg_verdict "[a-z_-]+"' tests/scripts/lib/inngest-host-dark-gate.sh | cut -d'"' -f2 | sort -u`, `grep -cF "\"$T\"" tests/scripts/test-inngest-host-dark-gate.sh` ≥ 1 — no token can be emitted that the battery never asserts.
- [ ] **AC5 — 2.0 routes through exactly one gate call.** `awk '/^  execute\)$/{f=1;next} f&&/^  [a-z-]+\)$/{exit} f' scripts/cutover-inngest.sh | grep -c 'inngest_execute_registry_gate'` → `1`.
- [ ] **AC6 — two readers, one `--grep` term each.** `grep -cE '^_probe_query_rows\(\) \{' scripts/cutover-inngest.sh` → `1` and `grep -cE '^_guard_block_query_rows\(\) \{' scripts/cutover-inngest.sh` → `1`. For each: `awk '/^_probe_query_rows\(\) \{$/{f=1;next} f&&/^\}$/{exit} f' scripts/cutover-inngest.sh | grep -o -- '--grep' | wc -l` → `1` (same command with `_guard_block_query_rows` → `1`). Both end in `|| rc=$?` + `return "$rc"` (`… | grep -cE 'return "\$rc"'` → `1` each).
- [ ] **AC7 — the reachable-empty arm is byte-identical to `origin/main`.** `diff <(git show origin/main:scripts/cutover-inngest.sh | awk '/REG_EMPTY=\$\(echo "\$BODY"/{f=1} f{print} f&&/pre-flight clear/{exit}') <(awk '/REG_EMPTY=\$\(echo "\$BODY"/{f=1} f{print} f&&/pre-flight clear/{exit}' scripts/cutover-inngest.sh)` exits 0 with no output.
- [ ] **AC8 — D4 remediation corrected.** `grep -c 'stop the dark inngest-server' scripts/cutover-inngest.sh` → `0`.
- [ ] **AC9 — purity contract in the 2.0 block.** Within the `execute)` arm, every `echo "::` line interpolates only single extracted fields: `awk '/^  execute\)$/{f=1;next} f&&/^  [a-z-]+\)$/{exit} f' scripts/cutover-inngest.sh | grep -E 'echo "::(notice|error|warning)::' | grep -oE '\$\{?[A-Z_]+' | tr -d '${' | sort -u` is a subset of `{CODE, CAUSE, CUTOVER_HOSTS, ERG_VERDICT, ERG_BOOT_ID, ERG_FLAG, ERG_ROW_AGE, ERG_GUARD_COUNT, PROBE_RC, GUARD_RC, REG_COUNT, REG_EMPTY, HOSTS, INNGEST_CONNS, EXPECTED_BURST_COST, READINESS_CEILING, POOL_SIZE, SUPAVISOR_WARM_RESERVE, POOL_BREAKDOWN, POOL_HTTP, POOL_RC, POOL_BODY_SAFE}` — i.e. the pre-existing set plus the six `ERG_*` singles. No `PROBE_ROWS*`, `GUARD_ROWS*` or `BODY` appears in any annotation line.
- [ ] **AC10 — shellcheck clean.** `shellcheck -S warning scripts/cutover-inngest.sh tests/scripts/lib/inngest-host-dark-gate.sh tests/scripts/test-inngest-host-dark-gate.sh apps/web-platform/infra/cutover-inngest-workflow.test.sh` exits 0 (ShellCheck 0.10.0 on this tree).
- [ ] **AC11 — guard-contract lint.** `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-09-10-fix-cutover-execute-dark-host-registry-gate-plan.md` exits 0.
- [ ] **AC12 — orphan-suite lint.** `bash scripts/lint-orphan-test-suites.sh` exits 0 (the dark-gate suite is registered by an explicit `run_suite` line in `scripts/test-all.sh`, and this PR adds no new suite file).
- [ ] **AC13 — ADR-100 addendum present and substantive.** `grep -cE '^## Addendum — 2026-09-1[0-9] \(#8054\)' knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` → `1`; within that addendum (from its heading to the next `^## ` or EOF), `grep -c 'BLOCK:'` ≥ 1 and `grep -c -- '--grep'` ≥ 1 (the D5 outcome and the starvation rule are both recorded).
- [ ] **AC14 — C4 edge amended and the model still renders.** `grep -E '^\s*github -> betterstack' knowledge-base/engineering/architecture/diagrams/model.c4 | grep -c 'op=execute'` → `1`; `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` exits 0.
- [ ] **AC15 — untouched surfaces are untouched.** `git diff --quiet origin/main -- .github/workflows/cutover-inngest.yml apps/web-platform/infra/inngest-bootstrap.sh apps/web-platform/infra/cloud-init-inngest.yml apps/web-platform/infra/inngest-server-flip-guard.sh` exits 0 — no workflow secret change, no emitter change, no guard change, so no image bump and no host replace.
- [ ] **AC16 — mutation matrix rows are each named in the battery.** For each `n` in 1..19 and each of H1..H6, `grep -cE "(^|[^0-9])(M$n|H$n)\b" tests/scripts/test-inngest-host-dark-gate.sh` ≥ 1 — the case names carry the row ids so the matrix in `## Guard Contract` and the suite cannot silently diverge.
- [ ] **AC17 — full battery.** `bash scripts/test-all.sh` prints a marker matching `^=== [0-9]+/[0-9]+ suites passed ===$` and its rc file reads `0`.
- [ ] **AC18 — plan-review artifacts.** This plan's frontmatter carries `requires_cpo_signoff: true` and `brand_survival_threshold: single-user incident`; `## Domain Review` records the CPO sign-off status as measured, and `knowledge-base/project/specs/feat-one-shot-8054-execute-dark-host-registry-gate/tasks.md` exists.

### Post-merge — dispatched by the pipeline (no operator step)

- [ ] **AC19 — the step that could not run, runs.** After merge, `gh workflow run cutover-inngest.yml --ref main -f op=execute -f cron_period_seconds=1200` (1200 is the measured shortest registered cron period — `cron-ghcr-token-minter` at `*/20 * * * *`; the 3600 default would report a phantom double-fire). In the run log: a `::notice::` line matching `2\.0 .*dark-empty` that names `boot_id=` and `cutover_flag=aborted`; a subsequent `2.1` capture line (proof 2.0 fell through); and the run terminates at `2.2 QUIESCE HARD GATE` with the STILL-RUNNING verdict, because the co-located scheduler is serving — the **expected** stop for a pre-flip dispatch. The conclusion is `failure` at 2.2, not at 2.0. `INNGEST_BASE_URL` on `soleur/prd` still reads `http://host.docker.internal:8288` afterwards.


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
   names every token the gate can emit, including the previously unnamed *"probe dark but zero
   `BLOCK:` rows in the boot window"* case (`guard_unattested`), and every remediation is a
   `gh workflow run` verb or a host-replace dispatch.
3. **The `dark-empty` notice states in plain words that dark is the intended, safe state** (E14 and
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
## Test Scenarios

| # | Scenario | Type | Steps | Expected |
|---|---|---|---|---|
| TS1 | Hermetic battery, dark arm | local, no credentials | `bash tests/scripts/test-inngest-host-dark-gate.sh` | AC1's exact output shape; the H5 non-canonical must-PASS row (`server_active=failed`, unfamiliar `image_ref`, extra trailing field) grades `dark-empty`; every RED row in the matrix is a named failing case when its mutation is applied (spot-check M2, M8, M14, M19 by applying the mutation with `sed`, observing RED, reverting) |
| TS2 | Hermetic wiring suite | local, no credentials | `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` | AC2; the one-gate-call, one-`--grep`-per-reader, `*)`-exits-1 and reachable-arm-unchanged assertions each print a PASS line |
| TS3 | Live read against the real host | read-only, `doppler run -p soleur -c prd_terraform` | Run the two Phase 0.1 reads from the worktree; decode; select `host=soleur-inngest host_name=soleur-inngest-prd` post-decode | Newest probe row: `probe_schema=8 http_code=000 server_active!=active cutover_flag=aborted host_role=dedicated registry_fns=__UNREADABLE__`; ≥ 1 `BLOCK: ` row under `SYSLOG_IDENTIFIER=inngest-server-flip-guard` with `dt ≥ row.dt − uptime_s`. Then call `inngest_execute_registry_gate` directly with those two files and the live `--now-epoch` → token `dark-empty`, rc 0 |
| TS4 | Live read, negative control | read-only | Same as TS3 but pass `--host soleur-web-platform --host-name soleur-web-platform-prd` | Token is a refusal (`wrong_host` or `silent`), never `dark-empty` — the co-located web host, whose row carries `registry_fns=n/a` and `host_role=web`, must not grade dark |
| TS5 | Live read, credential failure is not silence | read-only | Run `_probe_query_rows` with `BETTERSTACK_QUERY_PASSWORD` unset in the environment | `betterstack-query.sh` exits 3; the gate receives `--query-rc 3` and emits `unreadable`, never `silent` |
| TS6 | The unblocked dispatch (post-merge, AC19) | live dispatch, pipeline-owned | `gh workflow run cutover-inngest.yml --ref main -f op=execute -f cron_period_seconds=1200`; poll with the Monitor tool | 2.0 `dark-empty` notice → 2.1 capture → stops at the 2.2 quiesce gate with STILL RUNNING. Nothing is quiesced, armed or flushed |
