---
title: "fix(cutover): op=execute 2.0 must accept a provably-dark dedicated host, not only a reachable-empty one"
date: 2026-09-10
slug: fix-cutover-execute-dark-host-registry-gate
branch: feat-one-shot-8054-execute-dark-host-registry-gate
issue: 8054
---

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
duplicated — because 2.0 is the only gate standing between the cutover flip and a second scheduler
registering against prod Postgres. A widened gate that passes on a host still carrying a registry
produces exactly the double-fire the gate exists to prevent, and the duplicate reaches the user's
inbox before any dashboard shows it.

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

0.1 **Satisfiability of the corroborator (D5) — the fork that decides the design.** One read, from
the worktree, against the live host's current boot:

```
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
  --since 24h --grep SOLEUR_INNGEST_SERVER_PROBE --grep inngest-server-flip-guard --limit 500
```

`--grep` is OR-combined, so this single read returns BOTH streams; host isolation happens after
decoding, never in `--grep` (which would widen, not narrow). From the result establish:

- the newest probe row for `host=soleur-inngest host_name=soleur-inngest-prd`, and its
  `boot_id`, `uptime_s`, `probe_schema`, `http_code`, `server_active`, `cutover_flag`,
  `host_role`, `registry_fns`;
- whether at least one row with `SYSLOG_IDENTIFIER == "inngest-server-flip-guard"` and a message
  beginning `BLOCK: ` has `dt >= (probe row dt − uptime_s)`.

**Fork.** If such a `BLOCK:` row exists → conjunct D2(b) ships as a required predicate. If it does
NOT → D2(b) is **dropped** and the plan ships the row-internal conjunction alone; record the
measurement and the drop in the plan and in the ADR addendum. Do not ship a predicate whose
satisfiability was never observed.

0.2 **Confirm the live row already satisfies the intended dark conjunction.** Against
`boot_id=402c0d5b`, `probe_schema=8`, `cutover_flag=aborted`, `INNGEST_DIAGNOSTIC_BOOT=0`: the row
must read `http_code=000`, `server_active` not `active`, `host_role=dedicated`,
`registry_fns=__UNREADABLE__`. If any field disagrees, the design premise is wrong and Phase 1 stops.

0.3 **Confirm the credential path.** `betterstack-query.sh` exits 3 when
`BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` are not injected, and that 3 must never be read as
"nothing found". Confirm the `op=execute` job's `DOPPLER_TOKEN` resolves `prd_terraform` and that
the new reader distinguishes rc 3 from rc 0-with-zero-rows.

0.4 **Baseline the floors.** Record today's values so the raise is derived, not guessed:
`grep -n '_PRED_FLOOR=\|_FLOOR=' tests/scripts/test-inngest-host-dark-gate.sh` (currently
`_PRED_FLOOR=22`, `_FLOOR=124`) and the green assertion count from
`bash tests/scripts/test-inngest-host-dark-gate.sh`.

0.5 **Baseline the sibling suite.** Record the current pass count of
`bash apps/web-platform/infra/cutover-inngest-workflow.test.sh`.

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

1.3 Write every row of the mutation matrix, plus the harness rows, as failing cases.

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
same `|| rc=$?` shape, returning the query's rc so the caller owns its failure semantics.

4.2 In the `execute)` arm, leave the HTTP-200 path byte-for-byte unchanged. Replace **only** the
`if [[ "$CODE" != "200" ]]; then … exit 1; fi` branch with: log the HTTP code and cause as a notice,
source the gate library, run the two reads, call `inngest_execute_registry_gate`, and `case` on the
token. `dark-empty` emits a `::notice::` naming the row's `boot_id`, `cutover_flag` and row age, and
falls through to 2.1. Every other token emits `::error::` with a remediation specific to that token
and `exit 1`. An unrecognised token exits 1 fail-closed, mirroring G3.6's `*)` arm.

4.3 Correct the non-empty remediation text (D4): step (2) can no longer instruct stopping a process
the P1-5 guard will not start. Replace with the flag-and-registry path that is actually available.

4.4 Adopt the purity contract verbatim — counts and single extracted fields only, never a whole row,
never a GQL body.

### Phase 5 — Wiring assertions in the sibling suite

Add to `apps/web-platform/infra/cutover-inngest-workflow.test.sh`: 2.0 routes through exactly one
`inngest_execute_registry_gate` call; every verdict token the gate can emit has a matching `case`
arm; the `*)` arm exits 1; the readers isolate host post-decode and pass no host term to `--grep`;
and the HTTP-200 path is unchanged.

### Phase 6 — ADR addendum, then the full battery

6.1 Write the ADR-100 addendum (see `## Architecture Decision`), including Phase 0.1's measurement
and the D5 fork outcome.

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
