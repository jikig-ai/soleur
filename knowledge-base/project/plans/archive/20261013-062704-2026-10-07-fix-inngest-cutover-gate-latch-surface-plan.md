---
title: "fix(inngest): three sibling repairs to the cutover gate/latch surface — append-only authorized latch clear (#7777), G8 not-serving predicate (#8078), op=resume bootstrap-done gate (#9177)"
date: 2026-10-07
slug: inngest-cutover-gate-latch-surface
branch: feat-one-shot-7777-8078-9177-cutover-gates
issue: [7777, 8078, 9177]
closes: [7777, 8078, 9177]
type: fix
priority: p1
domain: engineering
lane: single-domain
brand_survival_threshold: multi-user incident
requires_cpo_signoff: false
---

# fix(inngest): three sibling repairs to the cutover gate/latch surface

## Overview

Three sibling fixes to the Inngest dedicated-host cutover gate/latch surface, delivered in one
PR because they touch the same five files and share one safety model:

1. **#7777 — append-only authorized latch clear.** `flip-done.latch` records that an authorized
   `FLUSHALL` ran and refuses a second one; nothing can supersede it, which makes the recut
   gate's `redis_keys > 0` refusal circular ("empty the store with a FLUSHALL" vs. "the FSM
   refuses a second FLUSHALL"). The latch becomes an append-only LEDGER: a new `reflush`
   FSM arm — reachable only through a new reviewer-gated `op=reflush` — appends a `cleared_at`
   record carrying its authorization evidence (dispatching actor, run id, UTC timestamp, host
   `boot_id`) and then re-runs the normal flush path. `flush_already_performed` moves from
   "latch exists" to "the newest latch record is a `flushed_at` not superseded by a later
   authorization" — the same monotonicity, one level up.
2. **#8078 — recut gate G8.** G8 requires `server_active == "inactive"`; the live host legitimately
   reports `activating` (P1-5 refuse-loop) or `failed` while serving nothing, so G8 mis-grades a
   dark host `host_serving` and refuses the recut. G8 becomes the sibling E10 predicate verbatim:
   present, non-empty, `!= unknown`, `!= active`. The deliberate-divergence header note is
   rewritten and the sibling-predicate class is audited.
3. **#9177 — `op=resume` bootstrap-done G-row.** `op=resume` writes
   `INNGEST_CUTOVER_FLIP=flushed` — a prod-scheduler start — after G1 (flag is `done`) and G3
   (host audible), but nothing proves the CURRENT host generation finished provisioning. A new
   G4 refuses unless `scripts/followthroughs/inngest-provision-unit-8562.sh` reads
   `verdict=PASS` — i.e. the newest `provision-unit-armed` row's cloud-init `iid=` has a matching
   `bootstrap-done`. `bootstrap-done-DEGRADED`, missing/mismatched iids, in-progress, and
   read-path failures all refuse.

No production mutation, Terraform apply, workflow dispatch, or live cutover is performed or
prescribed. Every change is gate/lib/script logic plus fixture tests.

## Research Insights

### Premise Validation

All three issues are real, measured, and confirmed in the worktree:

- #7777: `flush_already_performed` (`inngest-cutover-flip.sh:536`) is existence-based —
  `[[ -e "$LATCH_FILE" ]] && return 0`. `record_flush_latch` appends
  `flushed_at=%s host=%s dbsize=%s` with `>>`. No clear path exists; the op=arm G3.7 refusal
  message even says "The latch is cleared ONLY by recutting the host's /mnt/data volume", which
  the recut gate then refuses while `redis_keys > 0` — the documented circularity.
- #8078: `tests/scripts/lib/inngest-host-dark-gate.sh:813` —
  `[[ "$server_active" == "inactive" ]] || { _ihdg_verdict "host_serving"; ... }`.
  The sibling `inngest_execute_registry_gate` E10 (~line 1304) already implements the correct
  predicate: `[[ -n "$server_active" && "$server_active" != "unknown" ]]` → `unreadable`;
  `[[ "$server_active" != "active" ]]` → `host_serving`. The "DELIBERATE DIVERGENCE FROM G8"
  header note at ~line 1065 documents the split and names #8078 as its own issue. Live-host
  measurement in the issue: 25 probe rows/24h, all `server_active=activating`.
- #9177: `scripts/cutover-inngest.sh` `resume)` block (~line 3254): G1 requires flag `done`;
  G3 requires host audibility via `_flip_liveness_count`/`resume_liveness_decide`; then it
  writes `flushed` unconditionally. The block's own comments already document "the current
  op=resume path should only be run after provisioning has emitted bootstrap-done" as a
  documented-but-unenforced precondition.
- The evidence path for #9177 already exists and is exactly scoped:
  `scripts/followthroughs/inngest-provision-unit-8562.sh` anchors on the newest
  `provision-unit-armed` row's `iid=` (cloud-init instance-id, once per host life), joins
  `bootstrap-done`/`provision-attempt-start`/`bootstrap-done-DEGRADED`/failure stages on that
  iid, and emits exactly one `verdict=PASS|FAIL|TRANSIENT` stdout line with rc
  0/1/2/3. `bootstrap-done-DEGRADED` is a FAIL, never a PASS; a shared/fallback iid
  (`unknown`, the hostname) is `probe-fault`. It is already wired for the same
  `doppler run -p soleur -c prd_terraform` credential channel `_bs_query_rows` uses.

### Property List (mechanism minimality)

- The clear is a RECORD, not a deletion. The latch file gains a second record type
  (`cleared_at`); nothing is ever removed or overwritten.
- Authorization evidence rides the ONE no-SSH channel that already exists — the
  `INNGEST_CUTOVER_FLIP` Doppler value — as `reflush,run=<gha-run-id>,by=<actor>`. A second
  Doppler key is impossible: `cloud-init-inngest.yml`'s boot-isolation self-check is an
  exact-set match on the config and would FATAL every re-provision (the documented
  `done`-marker rejection applies identically).
- The re-flush predicate is "newest record wins": newest `flushed_at` → latched; newest
  `cleared_at` → a flush is authorized; absent file → legacy state-slot compat arm;
  unreadable/malformed newest line → latched (fail closed).
- `op=reflush` is gated the same way as `op=arm`/`op=resume`: the `inngest-cutover` GitHub
  environment required-reviewer ack plus gate rows that fail closed (terminal flag, latch
  present, host audible, evidence well-formed) before the prod write.
- G8 becomes byte-identical to E10's two predicate lines; the safety argument (G9 non-200 +
  G19 synchronous flag ∉ arm set) is written into the lib header where the old divergence
  note lived.
- #9177's G-row reuses the followthrough probe binary verbatim — no new telemetry transport,
  credential class, or iid-join logic is duplicated.

### Cut List

- **No new Doppler key / flag sidecar** — rejected by the boot-isolation exact-set check.
- **No "clear then arm" two-verb design** — a standalone `clear-latch` flag would park the
  latch in a superseded state that ANY later `armed` (including a stray one) rides. Binding
  the clear to the reflush verb keeps the authorization inseparable from the act it
  authorizes. The predicate still honors `cleared_at` for `armed`/`flipping` resumes so a
  crash mid-reflush resumes correctly.
- **No SSH/manual clear path** — forbidden by hr-no-ssh-fallback-in-runbooks and by the
  deny-all-public host posture.
- **No weakening of `op=arm`'s G3.7** — it still refuses to arm over flush evidence; reflush
  is the deliberate exception verb, not a relaxation.
- **No changes to the flip-guard prod-start allowlist** — `{armed,flipping,flushed,done}` is
  correct: `reflush` never coincides with a server start (the FSM sets `flipping` before any
  host mutation and starts under `flushed`).

### Institutional learnings applied

- `#6178` emitter parity: every new `emit_state` reason literal must be anchored in
  `_flip_transition_dt`'s `--grep` set AND in `inngest-cutover-flip-rollout-7761.sh`'s
  `DRIFT_GREPS`/`KNOWN_REASONS` — the cross-file parity loops in
  `cutover-inngest-workflow.test.sh` redden otherwise.
- `#7761` seam gate: every new fixture-seam env var must be added to the FSM's argv-gated
  unset list AND its prose list — the completeness tripwire derives the set by shape.
- `#7674` polarity lesson: decision helpers must be pure token-mappers extracted for
  behavioural tests (`resume_bootstrap_decide` follows `resume_liveness_decide`); do NOT
  reuse `flush_latch_decide` for reflush — L's polarity inverts again (L>=1 is REQUIRED here,
  the inverse of arm's L==0, and different from resume's "not checked").
- Fail-closed on every read path; every refusal names its remediation and says "Do NOT SSH
  the host."
- Literal `emit_state` reasons only (never `"$reason"`) — the parity extraction takes the
  literal 3rd positional.

## Open Code-Review Overlap

None. Collision checks run at pipeline start: no open PR or worktree covers #7777/#8078/#9177.
Predecessors #7778 (recut gate), #8054 (execute gate E10), #9159 (provision unit) are merged
and are citations, not conflicts.

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/inngest-cutover-flip.sh` | New `reflush` FSM arm; `record_latch_clear`; `flush_already_performed` becomes newest-record predicate; new `CUTOVER_BOOT_ID` seam (gate list + prose); header/docs updated |
| `apps/web-platform/infra/inngest-cutover-latch.test.sh` | New ledger/clear/reflush cases; assertion floor raised |
| `apps/web-platform/infra/inngest-cutover-flip.test.sh` | `reflush` transition-ordering case; evidence-invalid refusal case |
| `apps/web-platform/infra/cat-inngest-cutover-state.sh` | Surface newest-record type (cleared vs flushed) if needed by the read contract — confirm at implementation; currently prints `tail -n1` which already shows the newest record |
| `scripts/cutover-inngest.sh` | New `reflush)` op arm with G1–G3 + evidence validation + write + confirm; `resume)` gains G4 bootstrap-done gate + `resume_bootstrap_decide`; `_flip_transition_dt` grep set gains the new reasons; op=arm G3.7 latched message names op=reflush |
| `.github/workflows/cutover-inngest.yml` | `reflush` added to op options, `environment:` ternary, `DOPPLER_TOKEN_INNGEST_ARM` ternary |
| `apps/web-platform/infra/cutover-inngest-workflow.test.sh` | Assertions for the new op (ternary parity auto-covers), the reflush block's gates, `resume_bootstrap_decide` behavioural rows, G4 ordering before the write |
| `tests/scripts/lib/inngest-host-dark-gate.sh` | G8 → E10 predicate; header table + monotonicity step + divergence note updated; `_erg_flag_class` learns `reflush` as `armed` class |
| `tests/scripts/test-inngest-host-dark-gate.sh` | `activating`/`failed` must-PASS rows; `unknown` → unreadable; updated + new mutate rows (restore `== inactive` → RED) |
| `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh` | `DRIFT_GREPS` + `KNOWN_REASONS` gain the new emit_state literals |
| `knowledge-base/engineering/architecture/decisions/ADR-100-*.md` | Addendum recording the ledger latch model + the G8 predicate correction |
| `knowledge-base/engineering/operations/runbooks/inngest-server.md` | Document `op=reflush` (the authorized clear) and that `op=resume` enforces bootstrap-done |

## Files to Create

None. (No new scripts; the reflush verb and G4 row live in existing files per the surface's
own conventions.)

## The change

### Workstream A — append-only authorized latch clear (#7777)

**Ledger model.** `flip-done.latch` keeps its name and location. Two record types, one per
line, append-only forever:

```text
flushed_at=<utc-iso> host=<hostname> dbsize=<n>                      # existing record_flush_latch
cleared_at=<utc-iso> run=<gha-run-id> by=<actor> boot_id=<boot>    # new record_latch_clear
```

**Predicate.** `flush_already_performed` becomes:

- latch file absent → fall through to the legacy state-slot `done` compat arm (unchanged);
- latch present → newest non-empty line prefix `flushed_at=` → latched (refuse);
  prefix `cleared_at=` → not latched (authorized); anything else → latched (fail closed on a
  malformed/tampered tail).

**New FSM arm** `reflush|reflush,*` in `run_flip`, before the `armed` arm's latch check is
ever reached:

1. Parse `reflush,run=<digits>,by=<token>` strictly. Missing/malformed evidence →
   `emit_state 1 "" "reflush-evidence-invalid" "aborted"` + `flag_set aborted` + exit 1.
   Evidence is MANDATORY — a bare `reflush` is a refused authorization, never a silent clear.
2. `record_latch_clear "$run" "$by"`: same mount gate + `mkdir -p` + `>>` + fatal-on-failure
   shape as `record_flush_latch` (fails `latch-unrecordable`, terminal `aborted`). Appends
   `cleared_at=$(date -u …) run=$run by=$by boot_id=$(cat /proc/sys/kernel/random/boot_id)` —
   the host stamps its own time and boot id; the dispatch stamps who/run. Idempotent:
   if the newest record is already a `cleared_at` for the same `run`, skip the append
   (crash re-entry must not double-record).
3. Emit `emit_state 0 "" "latch-cleared" "reflush"` — the operator-visible record on Better
   Stack (the file is the authority; the marker is the no-SSH observable).
4. `flag_set flipping; run_preflush_flip` — the shared stop→FLUSHALL→assert→latch→flushed→
   start→done path, which appends the next `flushed_at` and re-engages the latch.

**New seam** `CUTOVER_BOOT_ID` (default `cat /proc/sys/kernel/random/boot_id`) so fixtures
control the stamped boot id — added to the argv gate's unset list (→16 names) and the header
prose list.

**`op=reflush`** in `scripts/cutover-inngest.sh` (mirroring `op=resume`'s shape):

- Require `DOPPLER_TOKEN_INNGEST_ARM` (the dispatch is environment-gated upstream).
- G1: current flag ∈ `{done,aborted,rolled-back}`; in-flight values (`armed|flipping|flushed|
  reflush*`) refuse. (`read_failed` refuses.)
- G2: the latch must EXIST off-host — `_flush_latch_count` ≥ 1. `L=0` → refuse "no recorded
  flush; use op=arm". Unreadable → refuse fail-closed.
- G3: host audibility — `_flip_liveness_count` + `resume_liveness_decide` (audible required;
  a dark host cannot consume the write and parking `reflush` strands the flag in-flight).
- Evidence: `run=$GITHUB_RUN_ID`, `by=${GITHUB_TRIGGERING_ACTOR:-$GITHUB_ACTOR}` — both
  validated non-empty + charset (`run` digits; `by` `[A-Za-z0-9._-]+`); refuse if absent.
- Write `reflush,run=$run,by=$by` via stdin `doppler secrets set` (same shape as resume).
- Confirm via `confirm_flip_state` since-write: `done` → pass; `aborted`/`rolled-back`/
  timeout → loud failure naming the marker to read.

**Cascade updates** (all pinned by existing parity tests):

- `_flip_transition_dt` --grep set += `latch-cleared`, `reflush-evidence-invalid`.
- `inngest-cutover-flip-rollout-7761.sh` `DRIFT_GREPS` += both; `KNOWN_REASONS` += both.
- `.github/workflows/cutover-inngest.yml`: `reflush` in options + both ternaries.
- op=arm G3.7 `latched` message: name `op=reflush` as the authorized re-flush path (replaces
  "cleared ONLY by recutting the volume").
- op=arm G1 refusal message enumeration gains `reflush` in the in-flight set.
- `_erg_flag_class`: `reflush|reflush,*` → `armed` (it authorizes a flush — `flag_armed` is
  the honest verdict; `unreadable` would lie).
- `cat-inngest-cutover-state.sh`: leave `tail -n1` (already shows newest record); confirm no
  consumer parses `latch_record` as flushed-only.

### Workstream B — G8 not-serving predicate (#8078)

In `inngest_host_dark_gate`, replace:

```bash
[[ -n "$server_active" ]]                                 || { _ihdg_verdict "unreadable"; return $?; }
[[ "$server_active" == "inactive" ]]                      || { _ihdg_verdict "host_serving"; return $?; }
```

with E10's two lines verbatim:

```bash
[[ -n "$server_active" && "$server_active" != "unknown" ]] || { _ihdg_verdict "unreadable"; return $?; }
[[ "$server_active" != "active" ]]                        || { _ihdg_verdict "host_serving"; return $?; }
```

Comment/table updates in the same file:

- Header table row G8 → `server_active present, non-empty, != unknown; != active`.
- Monotonicity step 2 (header ~line 45): `server_active=inactive` → `server_active != active`
  with the safety argument: `activating`/`failed` are non-serving; G9 (`http_code != 200`)
  excludes a bound listener; G19 (synchronous flag ∈ {rolled-back,aborted} only) excludes a
  host mid-arm — under the P1-5 refuse loop `activating` cannot reach `active` without the
  flag leaving the pre-arm set, which G19 refuses.
- The `DELIBERATE DIVERGENCE FROM G8` block (~line 1065) → rewritten as RESOLVED: G8 and E10
  now share the predicate; the divergence's reason (P1-5 refuse-loop keeps `activating`) is
  why the wide predicate is CORRECT, not dangerous.
- Sweep the lib for the same staleness class (`== "inactive"`, `!= "active"`, `unknown`
  sentinel handling) and record the result; G8 is the only `== "inactive"` predicate.

### Workstream C — `op=resume` G4 bootstrap-done gate (#9177)

In the `resume)` block, after G3 (audibility) and BEFORE the `flushed` write:

```bash
G4_OUT=""; G4_RC=0
G4_OUT="$(doppler run -p soleur -c prd_terraform -- \
  bash scripts/followthroughs/inngest-provision-unit-8562.sh)" || G4_RC=$?
case "$(resume_bootstrap_decide "$G4_RC" "$G4_OUT")" in
  proceed) ::notice:: ... ;;
  refuse-*) ::error:: + exit 1, one message per class naming the probe's verdict/reason ;;
esac
```

New pure function `resume_bootstrap_decide <rc> <verdict-line>` (column-0 signature +
closing brace for the test's awk extraction):

| rc | verdict line | outcome |
|---|---|---|
| 0 | `verdict=PASS` | `proceed` |
| * | `verdict=FAIL reason=degraded…` | `refuse-degraded` |
| * | `verdict=FAIL …` (other) | `refuse-failed` |
| * | `verdict=TRANSIENT reason=in-progress` | `refuse-in-progress` |
| * | `verdict=TRANSIENT reason=not-delivered` | `refuse-not-delivered` |
| * | `verdict=TRANSIENT reason=probe-fault` | `refuse-unreadable` |
| * | anything else / empty / rc≠0 unmatched | `refuse-unreadable` |

Fail-closed by construction: only `proceed` reaches the write. Each refusal prints the
probe's `verdict=`/`cause=` summary to the run log and remediation (`in-progress` →
re-dispatch later; `degraded` → SQLite-only boot, investigate; `not-delivered`/
`never-started`/`no-bootstrap-done` → the provision unit's own runbook section;
`probe-fault` → the read path failed, not the host).

## Guard Contract

### Guard A — the anti-double-FLUSHALL latch predicate and its authorized-clear path

**Property.** A second `FLUSHALL` runs only when the latch's newest record is an explicit
authorization (`cleared_at` carrying run/actor/boot evidence), and NO code path removes or
overwrites a latch record. Every other newest-record shape — `flushed_at`, malformed, empty —
refuses. The mount-gate and fatal-on-unrecordable semantics are unchanged and apply equally
to the clear append.

**Assembly.** `flush_already_performed` (reads newest record), `record_flush_latch` +
`record_latch_clear` (append-only writes behind `is_real_mount` + `mkdir` + `>>`), the
`reflush` case arm (evidence parse → clear → flipping → shared preflush path), `op=reflush`'s
gate chain (terminal flag + latch-exists + audible + evidence-shape + stdin write +
confirm), plus the two flag-value consumers (`_erg_flag_class`, G19) staying fail-closed.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `flush_already_performed` reads the FIRST line instead of the newest — after clear+reflush the ledger's head is still `flushed_at` | RED — the authorized-reflush fixture refuses |
| 2 | `record_latch_clear` writes with `>` instead of `>>` — the prior `flushed_at` is destroyed | RED — the append-only assertion (original record still present after clear) fails |
| 3 | `reflush` arm accepts a bare `reflush` (skip evidence validation) | RED — the bare/malformed-evidence fixture must refuse, no FLUSHALL |
| 4 | `op=reflush` gate chain drops the L>=1 requirement | RED — the workflow test's "refuse when no recorded flush" row fails |
| 5 | Harness non-vacuity: run a reflush case with the latch path NOT wired into the fixture | RED — the clear-append assertion and the latch-existence stamps in the trace fail, proving the fixture exercises the ledger |

**Harness rows.** must-PASS non-canonical: `armed` on a ledger whose newest is `cleared_at`
proceeds (the slot cannot veto a newer clear); `flushed`-resume backfills `flushed_at` over a
`cleared_at` tail. must-REFUSE: malformed tail, bare `reflush`, `reflush,run=` (missing
fields), `reflush` on unwritable latch dir (fatal), `armed` over a `flushed_at` tail.

### Guard B — recut gate G8 not-serving predicate

**Property.** The recut gate grades `activating` and `failed` as non-serving (like the live
host under the P1-5 refuse loop) while `active` still refuses as `host_serving` and
`unknown`/empty/absent still refuse as `unreadable`.

**Assembly.** Two predicate lines inside `inngest_host_dark_gate` only (E10 already correct);
the header table, monotonicity step, and divergence note carry the safety argument.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `== "inactive"` semantics (`!= "active"` → `== "inactive"`) | RED — the `activating` fixture verdicts `host_serving`, kill |
| 2 | Drop the `!= "unknown"` clause | RED — the `server_active=unknown` fixture must stay `unreadable` |
| 3 | Weaken to `!= "activating"` (wrong constant) | RED — `active`/`failed` fixtures fail |

**Harness rows.** must-PASS: `server_active=activating`, `server_active=failed` (coherent
dark fixtures). must-REFUSE: `active` (host_serving), `unknown`/empty/absent (unreadable).

### Guard C — `op=resume` bootstrap-done G-row

**Property.** `op=resume` writes `flushed` only when the CURRENT host generation's cloud-init
iid provably reached `bootstrap-done`; every other probe outcome — degraded, in-progress,
not-delivered, failed, unreadable, empty — refuses before the write.

**Assembly.** `resume_bootstrap_decide` pure function + the G4 call site ordering (after G3,
before the `doppler secrets set`), plus the followthrough probe's own contract (iid join,
DEGRADED ≠ PASS, probe-fault distinct from not-delivered).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `resume_bootstrap_decide` returns `proceed` on `verdict=FAIL reason=degraded` | RED — the degraded fixture row fails |
| 2 | G4 moves AFTER the `flushed` write (order swap) | RED — the ordering assertion (probe call line < write line in the extracted resume block) fails |
| 3 | Decide treats TRANSIENT as proceed | RED — `in-progress`/`not-delivered` rows fail |

**Harness rows.** Behavioural: PASS+rc0 → proceed; FAIL degraded → refuse; FAIL no-bootstrap →
refuse; TRANSIENT in-progress → refuse; TRANSIENT not-delivered → refuse; TRANSIENT
probe-fault → refuse; empty verdict + rc≠0 → refuse; garbage verdict → refuse. Structural:
the resume block invokes `inngest-provision-unit-8562.sh` through the prd_terraform doppler
wrapper, extracts `verdict=`, and the refusal messages exist.

## Scope Check

### Ask Mapping (verbatim)

| Verbatim ask | Plan item |
|---|---|
| #7777 "An APPEND-ONLY authorized clear, not a latch reset … Clearing must ADD a record, never remove or overwrite one" | Workstream A: `record_latch_clear` appends `cleared_at`; `>` never used; append-only pinned by mutation row 2 + "no branch erases the latch" extension |
| #7777 "Each clear carries its own authorization evidence (who, when, which run, against which boot_id)" | `cleared_at=<utc> run=<run> by=<actor> boot_id=<boot>`; by/run from the dispatch, timestamp + boot_id stamped on-host |
| #7777 "The re-flush guard's predicate changes from 'no latch exists' to 'the newest latch record is superseded by a later authorization'" | `flush_already_performed` newest-record predicate |
| #7777 "It must not become a general reset switch" | Evidence is MANDATORY and validated; bare `reflush` refuses; the write requires the reviewer-gated environment + L>=1 + audibility |
| #8078 "G8 becomes server_active present, non-empty, != unknown, != active — the same predicate as the sibling's E10" | Workstream B, byte-identical predicate lines |
| #8078 "a mutate() row … widen back to == inactive → the activating fixture must go RED" | Guard B mutation row 1 |
| #8078 "a must-PASS non-canonical row with server_active=activating and one with failed" | Guard B harness rows |
| #8078 "a re-read of the gate's header comment on G8, which currently argues for inactive" | Header table + monotonicity step + divergence note rewrite |
| #8078 "Safety argument … G9 and G19 already exclude a host that is about to become active" | Written into the header where the divergence note lived |
| #9177 "Add an op=resume G-row … that refuses unless the new host's cloud-init instance id has emitted bootstrap-done" | Workstream C, G4 via the 8562 followthrough probe (which anchors on the newest armed row's iid) |
| User "fail-closed behavior and auditability must be preserved"; "gate/lib/scripts, fixtures, and tests only"; "no production mutation" | All changes are in the named files; every refusal exits non-zero before any write |

### Plan-Item Provenance

- `op=reflush` + `reflush,run=,by=` flag payload — designed from #7777's "who, when, which
  run" evidence requirement + the codebase's single no-SSH channel (the flag value) + the
  exact-set Doppler constraint that forbids a second key.
- `latch-cleared` / `reflush-evidence-invalid` emit literals — required by the emit_state
  parity contract the moment the FSM gains a new arm.
- `resume_bootstrap_decide` — repo idiom (`resume_liveness_decide`, `flush_latch_decide`,
  `diag_boot_decide`): pure token-mapper extracted for behavioural tests.
- `CUTOVER_BOOT_ID` seam — required for deterministic fixture assertions on the stamped
  boot id; follows the argv-gate seam convention.

### Split Assessment

One PR is correct: the three changes share the latch/flag/telemetry surface and each is
small; splitting would serialize three reviews over one safety model. The PR body carries
`Closes #7777 / #8078 / #9177` each on its own line.

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

No new infrastructure is provisioned. The `doppler secrets set` calls named below are not
resource provisioning — they are the pre-existing operational write channel this whole
surface already runs on (op=arm/op=resume/op=rollback write `INNGEST_CUTOVER_FLIP` exactly
this way, behind the same reviewer-gated environment and arm token). `op=reflush` adds a new
flag VALUE to that channel, not a new secret name — and a new Doppler KEY is structurally
impossible here because `cloud-init-inngest.yml`'s boot-isolation self-check is an exact-set
match that would FATAL every re-provision. The only workflow-YAML delta is adding `reflush`
to the existing op option/ternary lists. No `.tf` changes, no apply, no dispatch.

## Architecture Decision (ADR/C4)

- **ADR-100 amendment/addendum** (edit, not a new ADR): the durable-state model changes
  from "append-only single-record latch" to "append-only ledger (flush + authorized-clear
  records), newest record wins"; the G8 predicate correction and its G9/G19 safety argument;
  and `op=reflush` as the fourth flag-writing verb. One continuous decision surface.
- ADR-257 is cited (bootstrap-done semantics) but unchanged — #9177 consumes its contract.
- No C4 diagram impact: no new component or channel; the reflush verb rides the existing
  flag/telemetry paths.

## Encryption Posture

No change. No secrets are logged: the flag payload carries a run id and an actor login only
(public metadata); `doppler secrets set` stays stdin-fed; no latch record contains
credentials (hostname, run id, actor, boot id — none sensitive).

## User-Brand Impact

- These gates protect an irreversible `FLUSHALL` of user data (prompts, agent output). The
  dominant brand risk is a second unauthorized flush or a resume onto an unprovisioned
  scheduler — both are exactly what the new guards make harder to reach.
- Operator-facing surface changes: `op=reflush` appears in the dispatch menu (reviewer-gated);
  op=resume may now refuse with a bootstrap-done explanation where it previously wrote —
  the refusal names the remediation. op=arm's latch refusal gains the op=reflush pointer,
  resolving the documented circularity.
- Threshold: multi-user incident class is unchanged — the delta strictly reduces the
  reachable set of destructive states.

## Domain Review

### Engineering

- Single-domain (infra/shell). No Product/UX surface; no copy changes beyond operator runlog
  text. Product gate: not applicable.
- The write-boundary sweep is explicit: `>>` appends only at the two record sites; the flag
  write sites are enumerated (arm G5, resume write, rollback write, luks writes, and the new
  reflush write — all stdin-fed).
- Cross-consumer grep for the widened flag value: `_erg_flag_class` (execute gate), G19
  (recut gate), the flip-guard allowlist, `op=arm` G1 — all audited; only `_erg_flag_class`
  and the G1 message need updating, and each update keeps the consumer fail-closed.

## Observability

- `latch-cleared` emit_state row on `inngest-cutover-flip` — the operator-visible record of
  every authorized clear (host-stamped; the file remains the authority).
- `reflush-evidence-invalid` — a refused reflush attempt is loud on the same channel.
- Both literals join `_flip_transition_dt`'s grep set, `DRIFT_GREPS`, and `KNOWN_REASONS`,
  so the rollout probe and the anchor deriver see them (parity-enforced).
- op=resume G4 refusals echo the probe's `verdict=`/`cause=` summary to the run log —
  counts + iid only, per the probe's purity contract (no raw rows, no secrets).
- `cat-inngest-cutover-state.sh` already surfaces `tail -n1` of the latch, so the newest
  record (whichever type) is visible on the debug aid unchanged.

## Implementation Phases

TDD throughout: fixtures/mutations first (red), then implementation (green), then the
affected suites.

1. **Workstream B (smallest, unblocks the shared-file churn).** Update G8 + header; add
   `activating`/`failed`/`unknown` fixture rows + new mutate rows; run
   `tests/scripts/test-inngest-host-dark-gate.sh`.
2. **Workstream A (FSM + verb).** Latch test cases (red) → `record_latch_clear`,
   newest-record predicate, `reflush` arm, `CUTOVER_BOOT_ID` seam → flip/latch suites green.
   Then `op=reflush` + workflow edits + reason-set cascades + workflow test rows →
   `cutover-inngest-workflow.test.sh` + `inngest-cutover-flip.test.sh` green.
3. **Workstream C.** `resume_bootstrap_decide` + G4 block + workflow test rows → suite green.
4. **Docs.** ADR-100 addendum; runbook `op=reflush` + enforced bootstrap-done note; flip.sh
   header FSM-state table updated (new arm + ledger model).
5. **Full affected sweep:** the three touched suites + `inngest-server-flip-guard.test.sh`
   (flag-consumer) + `inngest-provision-unit-8562.test.sh` (probe contract unchanged) +
   `shellcheck` on edited scripts.

## Test Scenarios

- Reflush happy path: latch `flushed_at` → `reflush,run=42,by=octocat` → cleared_at appended
  (both records present) → flipping → stop→FLUSHALL→assert → flushed_at appended → done.
- Reflush refusal classes: bare `reflush`; `reflush,run=`; `reflush,by=x`; unwritable latch
  dir (fatal, no flush); op-level L=0 / flag in-flight / host silent / missing env evidence.
- Predicate monotonicity: `armed` over `flushed_at` tail refuses; over `cleared_at` tail
  proceeds; over garbage tail refuses; `flushed` resume backfills over `cleared_at`.
- Crash re-entry: `reflush` re-fired with same run → no duplicate clear record.
- G8: `activating`/`failed` pass dark; `active`→host_serving; `unknown`/empty/absent→unreadable;
  mutate-to-`==inactive` kills on the activating fixture.
- Resume G4: PASS→write; degraded/in-progress/not-delivered/never-started/probe-fault/
  no-verdict → refuse before the write.
- Parity: emitter reasons ⊆ grep sets (workflow test auto-derives); env/token ternary op-set
  equality; seam-list completeness tripwire.

## Acceptance Criteria

1. `inngest-cutover-latch.test.sh`, `inngest-cutover-flip.test.sh`,
   `tests/scripts/test-inngest-host-dark-gate.sh`, `cutover-inngest-workflow.test.sh`,
   `inngest-server-flip-guard.test.sh`, and `inngest-provision-unit-8562.test.sh` all pass.
2. A `reflush,run=<id>,by=<actor>` flag drives: validated clear append → flipping → flush →
   new `flushed_at`; the ledger retains EVERY prior record byte-for-byte.
3. `armed` refuses over a `flushed_at` tail and proceeds over a `cleared_at` tail; a
   malformed tail refuses fail-closed.
4. `op=reflush` refuses (before any write) on: non-terminal flag, L=0, silent host,
   unreadable reads, missing/malformed run/actor evidence; it is inside both reviewer-gate
   ternaries.
5. G8 accepts `activating`/`failed`, refuses `active` as `host_serving`, refuses
   `unknown`/empty/absent as `unreadable`; the `== inactive` mutation kills on the
   `activating` fixture.
6. `op=resume` writes `flushed` only on `verdict=PASS`; all FAIL/TRANSIENT/probe-fault
   outcomes refuse before the write with distinct messages.
7. No `TODO`/`TBD` in the diff; every new refusal says what to do next and "Do NOT SSH".

## Sharp Edges and Risks

- **Flag-value shape change** (`reflush,k=v,k=v`): `read_flag` strips whitespace, so the
  payload is comma-delimited without spaces; strict parse + refuse on anything else.
  Consumers audited above — all fail closed, `_erg_flag_class` gains the honest `armed`
  class.
- **Cleared-but-never-flushed window**: a `reflush` crash between clear-append and the
  flush leaves the newest record `cleared_at`, which an `armed` may ride. That is the
  issue-specified predicate semantics — the clear WAS authorized — and the parked flag still
  reads `reflush`/`flipping`, so the in-flight refusals protect it.
- **A pre-#8562 host has no `provision-unit-armed` row** → G4 refuses `not-delivered`. That
  is intentional fail-closed (the runbook requires bootstrap-done for the new iid); the
  refusal message names the cause class explicitly.
- **Duplicate `cleared_at` on crash re-entry** is prevented by the same-run skip; even
  without it, the ledger stays honest (two appends, still append-only).
- **`_flush_latch_count` sees `flip-complete` from the REFLUSH too** — correct: after a
  completed reflush the host is latched again, and op=arm's G3.7 keeps refusing; only
  another authorized `op=reflush` clears.
- The `reflush` flag value reaching the probe's `cutover_flag` field is in-flight by
  construction — the gates that read it refuse, which is the correct posture.

## References

- Issues: #7777 (append-only clear), #8078 (G8 predicate), #9177 (resume G-row);
  predecessors #7228 (monotonic latch, probe-derived done, done-owner marker), #7462/#7674
  (off-host latch read, generation-scoped liveness), #7761 (seam gate + rollout probe),
  #8017/#8054 (same staleness class; E10 sibling), #8562/#9159/ADR-257 (provision unit +
  bootstrap-done).
- `tests/scripts/lib/inngest-host-dark-gate.sh` (G8 ~L807, E10 ~L1304, divergence note ~L1065,
  header table ~L118).
- `apps/web-platform/infra/inngest-cutover-flip.sh` (latch model L459–L649, FSM dispatch
  L666–L728, seam gate L78–L161).
- `scripts/cutover-inngest.sh` (`resume)` ~L3254, `arm)` G1/G3.7 ~L2550, `_flush_latch_count`
  ~L390, `_flip_transition_dt` ~L270, `resume_liveness_decide` ~L1030).
- `scripts/followthroughs/inngest-provision-unit-8562.sh` (verdict contract L19–L49).
- `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh` (DRIFT_GREPS ~L159,
  KNOWN_REASONS ~L182).
- `.github/workflows/cutover-inngest.yml` (options ~L26, environment/token ternaries ~L91/L136).
- ADR-100 (cutover FSM + latch decision), ADR-257 (provision unit).
