---
title: "infra: the dedicated inngest host is stopped by a standing rollback flag, and G3.7 cannot see the flush latch"
date: 2026-08-25
slug: fix-inngest-host-not-serving-and-latch-gate-blindness
branch: feat-one-shot-7674-inngest-host-not-serving
issue: 7674
closes: 7674
lane: cross-domain
type: fix
domain: engineering
priority: p1-high
brand_survival_threshold: aggregate pattern
---

## Overview

The dedicated Inngest host (10.0.1.40) boots cleanly, bootstraps to completion, and then stops
serving. Measurement shows this is neither a crash nor a restart loop: `inngest-server.service`
reads `inactive` rather than `failed`, on a single unchanged `boot_id`, for 5.4 days. The cutover
flip FSM's 30-second poll read a standing `INNGEST_CUTOVER_FLIP=rollback`, took its `stop_server`
arm, wrote the terminal `rolled-back`, and has emitted a no-op on every tick since.

**The host is not broken. It is obeying a brake that was never released.** `bind=[]` and
`priv8288=000` are consequences of a deliberate stop, not evidence of a bind failure — which means
#7674's step 4 ("fix what the net-health trace names") is aimed at a defect that does not exist.

Two real defects sit behind that misreading, and this plan targets them:

1. **Nothing reads the signal that names the cause.** The hourly probe has carried
   `server_active=inactive` *and* `cutover_flag=rolled-back` in the same row, every hour, for 5.4
   days. `SOLEUR_INNGEST_SERVER_PROBE` has **zero consumers** outside its own unit tests — no
   workflow, alert, or gate reads it. Meanwhile `scheduled-inngest-health.yml` polls the web host
   and stays green, because the web host *is* healthy. A dead dedicated host is invisible by
   construction.

2. **Gate G3.7 passes without answering its question.** Its Better Stack query returns zero rows at
   7d, 30d, and 365d, so `flush_latch_decide` returns `clear` and the gate reports coverage it does
   not have. It cannot distinguish "no flush has happened" from "I cannot tell".

The plan also designs a gated, never-auto-executed destructive path for recutting `/mnt/data`,
which does not exist today.

## Research Insights

### Premise Validation (Phase 0.6)

Every cited reference was re-checked against live state on 2026-08-25.

| Cited premise | Verdict | How checked |
|---|---|---|
| #7674 is the live tracker | **Holds** — OPEN | `gh issue view 7674 --json state` |
| #7462, #7228 are closed | **Holds** — both CLOSED 2026-08-20 | `gh issue view` |
| #6178 (extract inngest to own host) | **Holds** — OPEN | `gh issue view 6178` |
| PR #7647 made `op=arm` idempotent | **Holds** — MERGED | `gh pr view 7647` |
| Handoff: "Doppler 521 = ExecStart secret-fetch failure" | **STALE / WRONG** — corrected in #7674 and independently refuted here: those rows are Inngest's own queue-executor logger, interleaved with healthy traffic | Better Stack |
| Handoff: "Better Stack ingestion stopped 2026-08-14" | **WRONG** — hourly probe rows land through 2026-08-25 11:14Z; the channel is live | `betterstack-query.sh --since 24h` |
| #7674: G3.7 blind because "evidence aged out (0 rows over 365d)" | **Symptom confirmed, cause NOT established** — 0 rows reproduced at 7d/30d/365d, but retention-vs-never-shipped is *undetermined* (Hypotheses H5/H6) | reproduced G3.7's exact query |
| Volume `106261946` predates the flip and was re-attached, not recut | **Holds** — volume created 2026-07-07, host created 2026-08-20 | Hetzner API (carried from #7674) |
| `op=verify-wiped-volume` does not touch `/mnt/data` | **Holds** | `inngest-wiped-volume-verify.sh` — `DATA_DIR="${INNGEST_DATA_DIR:-/var/lib/inngest}"`, zero `/mnt/data` references |
| No volume-recut apply_target exists | **Holds** | `apply-web-platform-infra.yml` options block |

**Mechanism-vs-ADR check (Phase 0.6 step 4) — the ask's mechanism is an explicitly rejected
alternative.** ADR-100's flip-mechanism alternatives list contains, verbatim:

> **A dedicated-host webhook reached via web-host fan-out.** Rejected: a new inbound control plane on
> the deny-all-public singleton enlarges its attack surface (SEC-H2). The Doppler-flag **poll** keeps
> the host inbound-closed.

and Decision 6a states the dedicated host runs **no** `adnanh/webhook` / `hooks.json` / `ci-deploy.sh`.
Scope item 2's literal mechanism ("expose `cat-inngest-cutover-state.sh` behind a webhook id") is
therefore not an unconsidered idea — it is the alternative ADR-100 refused, for a security reason
that still applies. The ADR's *adopted* transport for exactly this need is the one this plan uses:

> **Flip-state is read no-SSH via Better Stack** (P0-2): the oneshot emits its verify-state as a
> `logger -t inngest-cutover-flip` JSON line, carried off-box by the already-shipped on-host
> Vector → Better Stack Logs journald shipper.

### Property List (Phase 0.6b)

- **P1** — The reason `inngest-server` is inactive is known from evidence, and the *next* occurrence
  reports itself without a human joining two queries.
- **P2** — The host serves again, positively readable off-host.
- **P3** — Before any arm, "has a FLUSHALL already happened on this volume?" is answered by a signal
  that distinguishes *no* from *cannot tell*.
- **P4** — A reviewed, never-auto-executed path exists to clear the `/mnt/data` latch.
- **P5** — The remaining restoration work stays tracked by a probe that actually runs.

### Cut List (Phase 0.6b) — three of five proposed mechanisms are cut

| Mechanism proposed by the ask | Property | What already buys it → disposition |
|---|---|---|
| Add a new `SOLEUR_*` marker so the cause self-reports | P1 | **CUT.** `inngest-bootstrap.sh` (probe emit line) already carries `server_active=` **and** `cutover_flag=` in the *same* row, and the flip FSM emits `{flag,reason,exit_code}` on the allowlisted `inngest-cutover-flip` tag. The cause has been fully present in telemetry for 5.4 days. The gap is a **missing consumer**, not a missing marker — so the deliverable is a reader, not an emitter. |
| Expose `cat-inngest-cutover-state.sh` behind a webhook id | P3 | **CUT.** Two independent blockers: (a) ADR-100 explicitly rejected a dedicated-host webhook (SEC-H2); (b) delivery is replace-only, and the enabling edit is in the forbidden file. |
| A new freshness marker for G3.7 to read | P3 | **CUT.** The `inngest-cutover-flip` FSM already emits a host-originated row every ~35 s on an allowlisted tag — **measured live**, not assumed. G3.7 needs to *read* it. |
| A volume-recut apply_target for `/mnt/data` | P4 | **KEEP.** Verified absent; nothing wipes `/mnt/data`. |
| Successor follow-through probe; retire the predecessor | P5 | **KEEP.** Verified: `#7462` and `#7228` both closed while still carrying the directive. |

### The structural constraint that shapes everything: code delivery is replace-only

Every on-host asset — `inngest-server-probe.sh`, `cat-inngest-cutover-state.sh`, `vector.toml`,
`inngest-cutover-flip.sh`, the flip guard — is baked into the OCI bootstrap image and pulled by a
**digest literal pinned inside `apps/web-platform/infra/cloud-init-inngest.yml`** (the `IREF=` line
pinning `soleur-inngest-bootstrap:v1.1.25@sha256:f23a2a0d…`, plus its zot-mirror twin).

That literal lives in `user_data`, which is ForceNew on `hcloud_server.inngest` with no
`ignore_changes`. `deploy-inngest-image.yml` does **not** reach this host — it POSTs to the *web*
host's `deploy.soleur.ai/hooks/deploy`, and `ci-deploy.sh`'s inngest arm says so in two places
("On this (web) host the bootstrap's `soleur` default at :47 remains correct regardless" /
"for the day the DEDICATED host got a ci-deploy path").

**Therefore there is no no-SSH code-delivery path to 10.0.1.40 that does not force-replace the
fleet's sole scheduler.** Any deliverable needing new code *on the host* is replace-coupled and
cannot land in this PR. This is why every deliverable below is repo-side.

### Measured state (self-pulled 2026-08-25, `hr-no-dashboard-eyeball-pull-data-yourself`)

| Fact | Value | Command |
|---|---|---|
| Probe, latest | `http_code=000 server_active=inactive vector_active=active redis_active=active uptime_s=469312 boot_id=cb4e3bb0… cutover_flag=rolled-back` @ 11:14:25Z | `betterstack-query.sh --since 24h --grep SOLEUR_INNGEST_SERVER_PROBE` |
| Boot id | `cb4e3bb0-…` — unchanged since 2026-08-20 | same |
| Flip guard at boot | `DIAGNOSTIC: unit is SQLite-only … treating as non-prod`, then `ALLOW: is_prod=false flag='rollback'`, **twice**, 00:53:28.87 and 00:53:29.55 | `--since 7d --grep 'flip-guard'` |
| Flip FSM, now | `{"exit_code":0,"flag":"rolled-back","reason":"noop-rolled-back",…}` | `--since 24h --grep 'noop-rolled-back'` |
| Flip FSM cadence | **~1.7 rows/min (~2,450 rows/day)**, continuous | `--since 1h --grep noop-rolled-back`, bucketed per minute |
| G3.7's exact query | **0 rows at 7d, 30d, and 365d** | `--grep '"reason":"flip-complete"' --grep '"reason":"refuse-rearm-after-done"'` |
| `INNGEST_CUTOVER_FLIP` / `INNGEST_DIAGNOSTIC_BOOT` | `rolled-back` / `1` | `doppler secrets get … -p soleur-inngest -c prd --plain` |
| `FLUSH_LATCH_SINCE` repo variable | **unset** → G3.7 defaults to `365d` | `gh variable list` |
| `inngest-cutover` / `workspaces-luks-cutover` environments | both exist, `required_reviewers=[deruelle]` (non-empty) | `gh api repos/:owner/:repo/environments/<n>` |
| `inngest-cutover-flip` in Vector's Source-4 allowlist | **present**, and rows confirmed arriving | `vector.toml` allowlist + live query |
| Volume `hcloud_volume.inngest_redis` | `format = "ext4"` — **plaintext, no LUKS** | `inngest-host.tf`; zero `luks` matches in that file |
| `SOLEUR_INNGEST_SERVER_PROBE` consumers | **zero** outside its own unit tests | repo-wide grep excluding `knowledge-base/` |
| test capacity | `CAPACITY_CONTENDED`, 4 sibling runs in other worktrees | `bash scripts/test-all.sh --capacity` |

### Two measurement traps hit while producing the table above — recorded because they generalise

1. **`.message` is sometimes an object, not a string.** For `inngest-cutover-flip`, Vector parses the
   JSON payload into a structured object, so `jq -r '… + (.raw|fromjson|.message)'` throws on
   string+object concatenation. Under `2>/dev/null` that renders as **zero rows**, indistinguishable
   from a dead channel. It briefly produced a confident, wrong conclusion here ("the flip tag is not
   allowlisted") that a second, count-only query refuted. Any query whose result will bound a plan's
   options must be re-run in a shape that cannot silently swallow errors — `grep -c '^{'` on the raw
   stream, not a jq expression with stderr suppressed.
2. **A `--limit`-bound query cannot measure a retention floor.** Sorting `dt` over
   `--since 365d --limit 1000` returned an oldest row of 2026-08-25 09:09 — that is the *limit*
   binding, not the archive floor, because the ~1.7 rows/min flip channel saturates the window.
   Retention is therefore recorded as **UNKNOWN** rather than asserted.

### Applicable institutional learnings

- `2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md` — the
  governing methodology. Applied twice: (a) the retention-vs-never-shipped question is left
  **UNKNOWN** because the discriminator is not currently obtainable, rather than settled by argument;
  (b) the root cause is asserted only because a *positive* discriminator exists (`inactive` not
  `failed`, the guard's `flag='rollback'` at boot, and the FSM's `rollback` arm being the only
  unit-stop caller on the host).
- `2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md` — **the closest prior
  art, and a near-miss for this design.** In that incident the flip emitted
  `logger -t inngest-cutover-flip` while the tag was absent from `vector.toml`'s exact-match Source-4
  allowlist, so the marker never left the box and the no-SSH gate was inert — "rides the shipper" was
  a plan-time claim, not a fact. This plan's liveness witness reads that exact tag, so the claim was
  re-verified rather than inherited: the tag **is** in the allowlist today and rows **are** arriving
  at ~1.7/min. Had that not been re-checked, the witness would have been dead on arrival.
- `2026-05-16-adr-amendment-required-when-reversing-and-destroy-guard-empty-string-bypass.md` —
  destroy guards fail open on parse failure: `[[ "" -gt 0 ]]` is FALSE in bash arithmetic context, so
  an empty count from a broken `jq` lets a destructive plan through. Governs Guard 2 directly, and
  corroborates the existing `flush_latch_decide` contract (anything non-decimal ⇒ fail closed), which
  Phase 1 preserves.
- `2026-07-15-comment-fix-pr-wrote-a-new-false-comment-and-vacuous-ac-classes.md` — an AC that passes
  against the pre-fix tree is vacuous. Discharged by AC 18.
- `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` — discriminate
  on the `SYSLOG_IDENTIFIER`/host field, never a bare payload substring. Load-bearing because the
  probe script is the **shared** renderer for the dedicated host and web-1.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` and
  `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — three guards
  ship here; both are discharged in `## Guard Contract`.
- `2026-07-17-workflow-env-gate-references-unprovisioned-environment-auto-approves.md` — an
  `environment:` naming an unprovisioned environment silently auto-approves. Governs the destructive
  target; resolved by reusing the already-provisioned `inngest-cutover`.

**Rejected as stale or unsupported:** a learnings sweep proposed that the root cause is a cloud-init
silent package drop leaving the unit uninstalled. That is refuted by direct measurement — the unit
started at boot (the guard's ALLOW arm ran twice) and the FSM subsequently stopped it. The same sweep
proposed rewriting the flip FSM's pre/post-side-effect checkpoints; those checkpoints already exist
(`flipping` PRE-flush / `flushed` POST-flush), and a rewrite is out of scope here.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / handoff / ask) | Reality | Plan response |
|---|---|---|
| "The host boots and bootstraps cleanly but `inngest-server` never becomes active" | True but misleading. It *did* become active at boot; the flip FSM stopped it ~30 s later. | Reframe step 4: there is no bind failure to fix. Diagnose, record, and do not chase a phantom. |
| Step 4 exit: `server_active=active` + `http_code=200` on a **DURABLE** ExecStart | **Unreachable without arming.** A durable ExecStart needs `INNGEST_DIAGNOSTIC_BOOT` cleared *at boot* (consumed in `runcmd`, first-boot-only ⇒ replace); a durable ExecStart with the prod DSN and a flag outside `{armed,flipping,flushed,done}` is refused by the flip guard ⇒ `failed`. "Durable AND serving" exists only inside a cutover. | Split the criterion. 4a (this PR, reachable): cause named + detection + gate fixed. 4b (deferred to the step-5 window): durable serving. Stated as a contradiction, not silently redefined. |
| "Expose `cat-inngest-cutover-state.sh` behind a webhook id" | The host runs no webhook; ADR-100 rejected adding one; the script is replace-only to deliver. | Satisfy the **intent** via the ADR's adopted transport. Recorded as a User-Challenge (see Domain Review). |
| "G3.7's Better Stack evidence aged out (0 rows over 365d)" | 0 rows reproduced. Cause undetermined — retention or never-shipped. | Fix the gate so *either* cause yields a refusal, and stop depending on which. |
| "Design a **`inngest-luks-recut`** apply_target" | `hcloud_volume.inngest_redis` is `format = "ext4"` — there is **no LUKS** on this volume. | Name it **`inngest-volume-recut`**. Adopting `-luks-` would assert an encryption property the volume does not have and mislead every later reader and audit. |
| Runbook: G3.6 remediation — "clear `INNGEST_DIAGNOSTIC_BOOT`, let the host re-render its ExecStart, then re-run `op=arm`. No SSH." | **False.** The flag is read in `runcmd`, first boot only. A running host cannot re-render. | Correct the runbook. |
| Runbook: "The latch clears only when the host's `/mnt/data` volume is recut, via the `inngest-host-replace` maintenance window" | **False.** The measured volume (created 2026-07-07) survived the 2026-08-20 replace. A host replace re-attaches; it does not recut. | Correct the runbook; this false remediation is exactly why P4 has no mechanism today. |
| ADR-100 addendum: the July G6 confirm timeout happened "because … the host ships nothing" | True *then*. Not a general law — the host ships ~2,450 rows/day now, and G3.7 still reads zero. | ADR addendum: separate "host dark" from "query finds nothing". |

## Hypotheses

Network-outage gate (Phase 1.4) fired on `ECONNREFUSED`. Per `hr-ssh-diagnosis-verify-firewall`,
L3 is verified **before** any service-layer hypothesis.

### L3 — Firewall allow-list — **VERIFIED NOT CAUSAL**

- `hcloud_firewall.inngest` is a **zero-rule deny-all** and filters only the *public* interface;
  `inngest-host.tf` states intra-network traffic needs no allow rule.
- Host-local nftables is the real control:
  `tcp dport { 8288, 8289 } ip saddr { ${web_host_private_ips} } accept` followed by `drop`.
  web-1 (10.0.1.10) is inside the accept set.
- **Decisive artifact:** web-1 receives `connect ECONNREFUSED 10.0.1.40:8288` (errno -111). An
  nftables `drop` produces a **timeout**, not a refusal. `ECONNREFUSED` is a TCP RST — the packet
  reached the host's network stack and no process was listening. The firewall layer is excluded by
  the symptom's own shape, independently corroborated by `bind=[]`.

### L3 — DNS / routing — **NOT APPLICABLE**

The dispatch target is a literal private address (`10.0.1.40`); no name resolution participates.
`nic=[10.0.1.40,]` confirms the interface holds the expected address.

### L7 — TLS / proxy — **NOT APPLICABLE**

Plaintext HTTP on the private network; no CDN, proxy, or certificate is in the path.

### L7 — Service layer

| # | Hypothesis | Verdict | Discriminator |
|---|---|---|---|
| H1 | The unit crash-loops and systemd gave up | **REFUTED** | Start-limit exhaustion leaves `failed`; the probe reads `inactive`. |
| H2 | A `Condition*`/`Assert*` directive cleanly skipped the start | **REFUTED (structural)** | The unit heredoc in `inngest-bootstrap.sh` contains no `Condition*`/`Assert*` directive at all, so the clean-skip state is unreachable. |
| H3 | The flip guard refused the start | **REFUTED** | An `ExecStartPre` non-zero exit yields `failed`, not `inactive` — and the guard *ALLOWed*, twice, in the measured boot log. |
| **H4** | **The flip FSM's `rollback` arm stopped the unit, then parked at terminal `rolled-back`** | **CONFIRMED** | Four independent facts agree: (a) `rollback)` → `stop_server` → `flag_set rolled-back` is the **only** unit-stop caller on this host; (b) the guard logged `flag='rollback'` at boot while Doppler now reads `rolled-back` — exactly the transition that arm performs; (c) `rolled-back)` is a pure no-op forever, matching 5.4 days of stasis on one `boot_id`; (d) a stop yields `inactive`, which is what is measured. |
| H5 | G3.7 reads zero rows because retention cannot reach 2026-07-23 | **UNKNOWN — deliberately unresolved** | The discriminator (this source's archive floor) is not obtainable while the ~1.7 rows/min flip channel saturates any `--limit`-bound query. A verdict here would repeat the #6536 failure. The fix is designed so **both** branches yield a refusal. |
| H6 | G3.7 reads zero rows because no `flip-complete` row ever shipped | **UNKNOWN** | Same discriminator as H5. |

**Consequence of leaving H5/H6 open:** the gate must not be repaired by widening or narrowing
`FLUSH_LATCH_SINCE` — that tunes a window whose adequacy is unmeasurable. It must instead gain the
ability to say *"I cannot tell"*, and refuse on that.

## Sequencing

Diagnosis does **not** gate the fixes, because the diagnosis is already complete from existing
telemetry.

1. **Phase 1 — G3.7 gains a `silent` outcome + a liveness witness.** Repo-only. Removes the
   fail-open on the only question the gate asks.
2. **Phase 2 — a consumer for the probe.** Repo-only. Closes the detection gap that let this stand
   5.4 days (and, in July, 12 days).
3. **Phase 3 — `inngest-volume-recut` apply_target.** Repo-only, ships gated and inert.
4. **Phase 4 — follow-through: retire the predecessor, enrol a positive successor.**
5. **Phase 5 — corrections to the runbook and ADR-100.**
6. **Phase 6 — the flip FSM's emit rate-limit.** Repo-side change that takes effect on the *next*
   replace; explicitly not applied by this PR.

**Explicitly out of scope, and why:** `op=arm` (forbidden); any host replace (it reboots into the
same `rolled-back` flag, the poller stops the unit again within 30 s, and it destroys the 5.4-day
standing evidence that is the diagnostic subject); any edit to `cloud-init-inngest.yml` (force-replaces
the fleet's sole scheduler).

## Implementation Phases

### Phase 1 — G3.7: distinguish "clear" from "cannot tell"

`scripts/cutover-inngest.sh` currently derives one signal: a count of rows matching
`flip-complete` / `refuse-rearm-after-done`, passed to `flush_latch_decide`, which returns
`clear | latched | unreadable`. Zero rows ⇒ `clear` ⇒ pass.

Add a **second, independent** signal: a count of *any* `inngest-cutover-flip` row inside a short
recent window — the host's own liveness witness, measured to be arriving at ~1.7 rows/min, emitted
by **every** terminal FSM arm (`noop-rolled-back`, `noop-done`, `noop-aborted`), so it survives
whatever state the flag is in.

New decision table, replacing the single-input one:

| `L` (latch rows) | `H` (liveness rows, 15 min) | outcome | gate |
|---|---|---|---|
| ≥ 1 | any | `latched` | refuse — a flush already happened |
| non-decimal | any | `unreadable` | refuse — the **read path** is broken |
| 0 | ≥ 1 | `clear` | proceed — the host is reporting and shows no flush |
| 0 | 0 | **`silent`** | refuse — the host is **not reporting**; absence proves nothing |
| 0 | non-decimal | `silent` | refuse |

`silent` must be a distinct fourth outcome rather than folded into `unreadable`, because the forward
actions differ: `unreadable` points at `BETTERSTACK_QUERY_*` credentials in `prd_terraform`;
`silent` points at the dedicated host having gone dark. Collapsing them prints the wrong remediation
at the worst moment.

Both readers must validate their counts with an explicit numeric predicate (`^[0-9]+$`) rather than
relying on bash arithmetic coercion — an empty string from a broken pipe compares FALSE under
`-gt`, which is the documented destroy-guard bypass class. The existing decider already has this
contract; the new reader must match it.

Constraints this phase must honour, all pinned by existing assertions:
- G3.7 stays **after G3.6** and **before G4's first prod write**.
- Exactly **one** call site each for the two readers and the decider.
- **No `exit 1` inside any case arm**; the single positive-allowlist chokepoint
  `if [[ "$FL_OUTCOME" != "clear" ]]; then exit 1; fi` keeps ownership of the abort.
- The decider keeps its signature and closing brace at column 0 with no column-0 `}` inside the
  body — the test harness extracts it by `awk` range.
- The 15-minute window tolerates **both** cadences: today's ~35 s and the ~5 min the Phase 6
  rate-limit imposes after the next replace. It must not be tightened below the slower of the two.
- `cutover-inngest.sh` forbids naming the off-host read path literally inside the `arm)` body,
  because a sibling assertion greps that body to prove `op=arm` adds no polling hook. The new reader
  is therefore a **function defined outside** the arm, called once from it, exactly as the existing
  latch reader is. An inline query would redden that assertion.

**Honesty requirement.** The gate's comment must state that with H5/H6 unresolved, `clear` is a
**weak** verdict: it means "the host is reporting and no flush evidence is visible in the window",
not "no flush has happened". The on-host monotonic latch remains the authority; this gate can only
ever ADD a refusal.

### Phase 2 — give `SOLEUR_INNGEST_SERVER_PROBE` a consumer

The marker is emitted hourly and read by nothing. Add a scheduled reader that pulls the most recent
probe row for the dedicated host and fails loud when it reports not-serving, carrying the joined
`cutover_flag` in the message so the *cause* is in the alert rather than one query away.

Verdicts the reader must distinguish — `inngest-liveness-classify.sh` is the model, whose
`probe_unavailable` class exists precisely so a missing signal never reads as health:

| Condition | Verdict |
|---|---|
| `server_active=active` and `http_code=200` | healthy |
| `server_active != active` and `cutover_flag` ∈ `{rollback, rolled-back}` | **stopped-by-brake** — names the standing flag; today's state |
| `server_active != active` otherwise | **not-serving** — genuinely unexplained |
| no probe row inside the window | **probe-unavailable** — never "healthy" |

Field isolation is mandatory: the probe script is the **shared** renderer for the dedicated host and
web-1, so the reader must select on the `host`/`host_name` field, never a bare payload substring.
web-1's rows legitimately carry `cutover_flag=unknown` and must not be mistaken for the dedicated
host's.

### Phase 3 — the `inngest-volume-recut` apply_target (destructive, gated, inert by default)

Named for what the volume is: `hcloud_volume.inngest_redis` is `format = "ext4"`, so **`-luks-` does
not belong in the name**. It is the fleet's sole scheduler volume and holds the durable Redis queue
state, so this is the most destructive target in the repo's inngest surface.

Copy the four guard layers from `workspaces-luks-recut`, the only existing target that destroys
sole-copy `/mnt/data` data:

1. **`environment:` required-reviewer gate** — the sole human authorization, blocking the job before
   its first step. **Reuse the already-provisioned `inngest-cutover`** (verified
   `required_reviewers=[deruelle]`, non-empty). Minting a new environment is the trap: an
   `environment:` naming an *unprovisioned* environment silently auto-approves, producing the
   appearance of a gate without the gate.
2. **Typed confirm + numeric id pin** — a literal distinct from every existing one
   (`RECUT-WORKSPACES-LUKS`, `RECUT-REGISTRY-LUKS`, …) so a token typed for another target cannot
   authorize this one, plus an `expected_volume_id` matched `^[0-9]+$`. Both are typo-guards and must
   be labelled as such; the environment approval is the authorization.
3. **Scoped plan + sourced destroy-guard** — a `-replace`/`-target` plan narrowed to the volume and
   its attachment, fed to `tests/scripts/lib/inngest-volume-recut-gate.sh`, with **no `[ack-destroy]`
   bypass**.
4. **Post-apply jq backstop** — assert from the **saved** plan that `hcloud_server.inngest` and every
   unrelated resource show **zero** actions, and that the volume shows delete+create.

Plus a job-level `concurrency` mutex.

**Input-budget fork.** `workflow_dispatch` caps at 10 inputs and 7 are used; the workflow states that
the next per-target input *pair* should split into a dedicated workflow rather than spend two more
slots. A recut needs `expected_volume_id`, which spends slot 8 — inside the cap but one from it.
**Decision: add the target to the existing workflow and reuse the existing `confirm` input**,
spending exactly one new slot, and record that the *next* target needing an input must split.
Rationale: a dedicated workflow duplicates the whole environment + destroy-guard + backstop scaffold
for one target, and the budget note's trigger is a per-target input *pair*, which this is not.

**A new option with no matching job silently no-ops** — the run is green and empty, and nothing lints
for it. Phase 3 therefore ships an assertion binding every enum entry to a job guard.

**Ordering constraint.** The recut destroys the latch, so it must never be reachable before the
question "should the latch be cleared?" is answerable — it depends on Phase 1 landing, and it ships
inert.

### Phase 4 — follow-through

- **Retire the predecessor.** Enrollment is an HTML-comment directive in the **issue body**, so
  retirement is issue-side: `#7462` and `#7228` are both closed while still carrying the directive
  for `inngest-zot-boot-7462.sh`. Its contract (zot boot + `bootstrap-done`) is satisfied. Remove the
  directive from both bodies rather than re-pointing it; the file stays on disk (there is no archive
  directory, and only three probes have ever been deleted).
- **Enrol a successor** at `scripts/followthroughs/inngest-host-not-serving-7674.sh`, asserting the
  step-4 exit criterion **positively** — a probe row with `server_active=active` **and**
  `http_code=200` — never via an absence arm. Contract requirements, all mechanically enforced:
  committed mode `100755` (asserted against the **git index**); `set -uo pipefail` with **no `-e`**
  (an `-e` abort exits 1 = FAIL, which comments daily); the `${VAR:?msg}` form is banned and linted;
  required env named literally because the sweeper runs probes under `env -i`. Exit contract:
  `0` = PASS (closes the issue), `1` = FAIL (reserve — comments daily), `2` = TRANSIENT.
  Because step 4b is deferred to the cutover window, the probe legitimately returns **2** until then;
  `earliest=` must reflect that rather than manufacturing daily noise.
- The directive gate blocks issue creation unless `script=` resolves to an existing **executable**
  file, so the probe must be committed executable **before** the issue body is edited.

### Phase 5 — corrections to the runbook and ADR-100

Three corrections, each of which currently reads as a working remediation and is not:

1. **G3.6 remediation** — clearing `INNGEST_DIAGNOSTIC_BOOT` cannot re-render a running host's
   ExecStart; the flag is consumed in `runcmd`, first boot only.
2. **G3.7 remediation** — `inngest-host-replace` re-attaches the volume; it does not recut it. The
   measured volume predates the current host by six weeks. This false remediation is why P4 has no
   mechanism today, and the correction must point at the Phase 3 target.
3. **A new failure-mode entry** — "the host is inactive because a standing `rollback` flag stopped
   it", with the one-row discriminator (`server_active` + `cutover_flag` in the same probe line) and
   the note that `inactive` ≠ `failed`.

ADR-100 gains an addendum recording (a) that the dedicated host's code delivery is **replace-only**,
a standing architectural constraint rather than an incident detail; and (b) that the July G6 confirm
timeout's "the host ships nothing" attribution does not generalise — the host ships ~2,450 rows/day
today and G3.7 still reads zero, so "host dark" and "query finds nothing" are distinct failures that
had been conflated.

### Phase 6 — rate-limit the flip FSM's terminal no-op emit

`emit_state` calls `logger` unconditionally on **every** arm including the terminal no-ops, with no
rate limit, at a 30 s cadence. Measured: **~1.7 rows/min ≈ 2,450 rows/day**, roughly 10% of the
~25k/day Better Stack budget `vector.toml` repeatedly defends — burning continuously since the
rollback, undetected. `vector.toml` states that any further timer-driven tag is "a fresh quota
decision", and `#6617b` existed to remove exactly this shape from the heartbeat.

Rate-limit the **terminal no-op arms only** to ~5 minutes. Two constraints:
- **Not transition-only.** Transition-only emission would destroy the liveness witness Phase 1
  depends on. The witness needs a heartbeat, just a slower one.
- This is on-host code, so it is **replace-only** and takes effect on the next replace. Phase 1's
  15-minute window is sized to tolerate both cadences precisely so the two can land out of step.

## Files to Edit

| File | Change |
|---|---|
| `scripts/cutover-inngest.sh` | G3.7: add the liveness reader, add the `silent` outcome to `flush_latch_decide`, rewire the single chokepoint, rewrite the gate comment for the weak-`clear` honesty requirement. |
| `apps/web-platform/infra/cutover-inngest-workflow.test.sh` | New decision-table rows, reader-argv assertions, ordering assertions; **raise the anti-deletion floor from 449** to the re-measured value (measure by running the file — never a remembered figure). |
| `.github/workflows/apply-web-platform-infra.yml` | Add the `inngest-volume-recut` enum option, its guarded job, and the `expected_volume_id` input. |
| `apps/web-platform/infra/inngest-cutover-flip.sh` | Rate-limit the terminal no-op emit (Phase 6; replace-coupled). |
| `.github/workflows/infra-validation.yml` | Register the new suite(s). |
| `knowledge-base/engineering/operations/runbooks/inngest-server.md` | The three corrections in Phase 5. |
| `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` | Addendum: replace-only delivery; "host dark" ≠ "query finds nothing". |

## Files to Create

| File | Purpose |
|---|---|
| `tests/scripts/lib/inngest-volume-recut-gate.sh` | Sourced destroy-guard for the recut plan, mirroring `workspaces-luks-recut-gate.sh`. |
| `apps/web-platform/infra/inngest-volume-recut-header.test.sh` | Guard suite: enum↔job binding, reviewer-set non-empty, confirm-literal distinctness, mutation-tested. |
| `scripts/followthroughs/inngest-host-not-serving-7674.sh` | Successor probe, positive assertion, mode `100755`. |
| A scheduled reader workflow for the probe consumer (Phase 2) | Closes the detection gap. |

## Acceptance Criteria

### Pre-merge (PR)

1. `flush_latch_decide` returns `silent` for `(L=0, H=0)` and for `(L=0, H` non-decimal`)`, `clear`
   only for `(L=0, H≥1)`, `latched` for `L≥1`, `unreadable` for non-decimal `L` — asserted as a
   table, with a harness canary proving the comparator is live.
2. Both readers validate their counts with an explicit `^[0-9]+$` predicate; no count reaches a
   comparison via bash arithmetic coercion.
3. Exactly one call site each for the latch reader, the liveness reader, and the decider; zero
   `exit 1` inside any `case` arm of `arm)`.
4. The G3.7 gate line sorts after the G3.6 line and before the first prod write, asserted by
   line-ordering.
5. The `arm)` body contains no literal off-host read path (the existing sibling assertion stays
   green).
6. `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` passes, and again under
   `LC_ALL=C`; the floor is raised to the value produced by **running** the file.
7. `bash apps/web-platform/infra/run-registered-suites.sh` passes (floor 100), with the new suites
   registered and zero unaccounted.
8. `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
   passes.
9. `bash scripts/lint-workflows.sh` completes without a hang (rc 124 is the only failure).
10. `inngest-volume-recut` appears in the enum **and** has a matching job guard — asserted
    mechanically, with a mutation removing the job driving it red.
11. The recut job declares `environment: inngest-cutover`, and an assertion proves that environment's
    reviewer set is non-empty (block-scoped, mutation-tested).
12. The recut confirm literal is distinct from every existing literal in the workflow.
13. The destroy-guard fails closed when its resource count is empty or non-numeric.
14. `scripts/followthroughs/inngest-host-not-serving-7674.sh` is mode `100755` in the git index,
    contains no `${VAR:?}` form, uses `set -uo pipefail` without `-e`, and asserts
    `server_active=active` together with `http_code=200`.
15. `apps/web-platform/infra/cloud-init-inngest.yml` is **unmodified** —
    `git diff --name-only origin/main...HEAD` does not list it.
16. No `op=arm` dispatch occurs on this branch.
17. Every `knowledge-base/` path cited in this plan resolves to a real file.
18. **Every AC above was run against the pre-fix tree and FAILED there.** An AC that passes before
    the change is vacuous and must be rewritten or dropped.

### Post-merge (automated)

19. The probe-consumer reader runs on schedule and reports `stopped-by-brake` for the dedicated host
    while the flag remains `rolled-back` — i.e. it names today's state rather than reporting health.
20. The successor probe is enrolled on #7674 and returns `2` (TRANSIENT) without commenting daily.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing immediately — web-1's co-located scheduler is
firing production crons normally and there is no outage. The exposure is deferred: a G3.7 that still
fails open lets a future arm quiesce the working scheduler and complete a cutover onto a host that
serves nothing, which stops every production cron while reporting success.

**If this leaks, the user's workflow is exposed via:** the recut target destroying the sole scheduler
volume's durable queue state — in-flight `step.sleep` and queued jobs — if it were ever executed
without review. Hence the required-reviewer environment, typed confirm, scoped destroy-guard with no
bypass, and post-apply backstop, and never auto-executing.

**Brand-survival threshold:** `aggregate pattern`. No single user's data is at risk in this PR: the
production scheduler is unaffected, the destructive path ships inert, and every change is repo-side.
The pattern being corrected — a gate reporting coverage it does not have, and a marker nobody reads —
is an aggregate reliability defect rather than a per-user incident.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_INNGEST_SERVER_PROBE, joined with cutover_flag in the same row
  cadence: hourly (inngest-server-probe.timer, OnUnitActiveSec=1h)
  alert_target: the Phase 2 scheduled reader; fails loud on not-serving and on probe-unavailable
  configured_in: apps/web-platform/infra/inngest-bootstrap.sh (emitter, existing); the Phase 2 reader workflow (consumer, new)
error_reporting:
  destination: GitHub Actions annotation (::error::) from the reader, plus the existing Better Stack row
  fail_loud: true — a missing probe row classifies as probe-unavailable, never as healthy
failure_modes:
  - mode: dedicated host stopped by a standing rollback flag
    detection: probe row with server_active != active and cutover_flag in {rollback, rolled-back}
    alert_route: reader verdict stopped-by-brake, naming the flag in the message
  - mode: dedicated host not serving for an unexplained reason
    detection: probe row with server_active != active and any other cutover_flag
    alert_route: reader verdict not-serving
  - mode: dedicated host stops reporting entirely
    detection: no probe row inside the reader's window
    alert_route: reader verdict probe-unavailable — distinct from healthy and from not-serving
  - mode: G3.7 cannot see the flush latch because the host is silent
    detection: L=0 with H=0 over the 15-minute liveness window
    alert_route: gate outcome silent, refusing the arm before any prod write
  - mode: G3.7's read path itself is broken
    detection: non-decimal row count from either reader
    alert_route: gate outcome unreadable, pointing at BETTERSTACK_QUERY_* in prd_terraform
logs:
  where: Better Stack, source soleur-inngest-vector-prd, via the on-host Vector journald shipper
  retention: UNKNOWN for this source — not measurable while the ~1.7 rows/min flip channel saturates any limit-bound query. Treated as a hazard rather than a number: the gate is designed so neither branch of the retention question can produce a false clear.
discoverability_test:
  command: bash scripts/followthroughs/inngest-host-not-serving-7674.sh
  expected_output: exit 2 with a TRANSIENT line naming server_active and cutover_flag while the flag remains rolled-back; exit 0 only once a probe row shows server_active=active with http_code=200
  credentials_required: "BETTERSTACK_QUERY_HOST / _USERNAME / _PASSWORD — the probe asserts a property of the live host's telemetry, and no unauthenticated substitute reads that source"
```

## Infrastructure (IaC)

### Terraform changes

No new resources. The recut target operates on the **existing** `hcloud_volume.inngest_redis` and
`hcloud_volume_attachment.inngest_redis` via a scoped `-replace` / `-target` plan. No new provider,
no new version pin, and no new no-default variable that could break the merge-triggered apply.

### Apply path

**Gated dispatch only, never auto-applied.** The target is `workflow_dispatch`-reachable, held at the
`inngest-cutover` required-reviewer environment before its first step, and additionally guarded by a
typed confirm, a numeric volume-id pin, a sourced destroy-guard over the saved plan, and a post-apply
backstop. Blast radius when executed: the durable Redis queue state on `/mnt/data` is destroyed and
the volume recreated empty; the `/mnt/data` flush latch clears, which is the entire point.
`hcloud_server.inngest` must show **zero** actions — asserted, not assumed.

### Distinctness / drift safeguards

- The `-target` set is scoped to the volume and its attachment; the destroy-guard fails closed if the
  saved plan shows any action on the server or any unrelated resource.
- `-replace` on the volume is transitive on its attachment; the backstop pins that only these two
  move.
- The confirm literal is distinct per target so a token typed for the workspaces or registry recut
  cannot authorize this one.
- The reviewer set is asserted non-empty by a block-scoped, mutation-tested predicate, because an
  unprovisioned environment auto-approves silently and there is no generic lint for this.
- Counts inside the destroy-guard are validated numerically, closing the empty-string bypass.

### Vendor-tier reality check

No new vendor resource and no tier-gated API. Hetzner volume delete+create is within the existing
plan; the Better Stack reads reuse the existing `prd_terraform` query credentials.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-100** rather than minting a new ordinal — every finding modifies decisions that ADR
already owns:

- Record that **code delivery to the dedicated host is replace-only**: every on-host asset is baked
  into the OCI image and pulled by a digest literal inside `cloud-init-inngest.yml` `user_data`,
  which is ForceNew with no `ignore_changes`, and `deploy-inngest-image.yml` reaches the *web* host
  only. A standing constraint that will keep shaping plans, currently implicit.
- Correct the 2026-08-11 addendum's generalisation: "the host ships nothing" explained July, but the
  host now ships ~2,450 rows/day while G3.7 still reads zero, so *host dark* and *query finds
  nothing* are separate failures.
- Record the G3.7 two-signal design and the explicit weakness of a `clear` verdict.
- Add to Decision 6a's alternatives that the webhook-for-latch-readback idea was re-proposed and
  re-rejected — for the original SEC-H2 reason plus the newly recorded replace-only delivery reason.

Because this is an amendment, no ordinal is claimed and the collision class does not apply.

### C4 views

Checked all three model files —
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — for this change's
external actors, external systems, containers, and access relationships:

- **External human actors:** none added. The recut is dispatched under the existing reviewer role
  already modelled for the cutover environment.
- **External systems:** Better Stack (already modelled as the log sink), Hetzner (already modelled),
  GitHub Actions (already modelled). No new vendor edge.
- **Containers / data stores:** `/mnt/data` on the inngest host is the existing Redis store; no new
  store, and no change to which container holds it.
- **Access relationships:** unchanged. The dedicated host remains inbound-closed and Doppler-poll
  driven; this plan explicitly declines to add the inbound webhook edge that would have changed the
  diagram.

**No C4 edit is required**, and the enumeration above is the evidence for that conclusion rather than
an unsupported "None".

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.inngest_redis (/mnt/data) — durable Redis queue state + the flush latch
    mechanism: plaintext-exception
    evidence: apps/web-platform/infra/inngest-host.tf — `format = "ext4"`, zero `luks` references in the file
    defends_against: nothing at the block layer; Hetzner-side physical media handling only
    does_not_defend: an attacker with volume-snapshot or detached-volume access reads queue payloads and the latch record in the clear
    disclosed_as: internal infrastructure state; by design this volume holds scheduler queue state, not end-user records
    live_verification: the volume's `format` attribute in the Terraform plan output for the recut target
in_transit:
  - connection: web-1 -> 10.0.1.40:8288 (event dispatch)
    tls: false
    cert_verification: off
    does_not_defend: an attacker with a foothold inside 10.0.1.0/24 can read or forge dispatches
    disclosed_as: private-network plaintext, bounded by the nftables source allow-list and fail-closed HMAC at /api/inngest
  - connection: on-host Vector -> Better Stack ingest
    tls: true
    cert_verification: on
    does_not_defend: content already scrubbed on-host; a compromised host still chooses what to emit
    disclosed_as: standard vendor log shipping
exception:
  justification: the inngest volume was provisioned ext4 without LUKS, unlike its registry and workspaces siblings. This plan does not change that posture — it only adds a gated path to recut the volume — but the asymmetry is real and is surfaced here rather than left implicit behind a target name that would have falsely implied LUKS.
  tracking_issue: to be filed with this PR — "inngest /mnt/data is plaintext while sibling volumes are LUKS"
  reevaluate_when: the next inngest-host-replace window, when a recut is already being performed and the format could change at no extra outage cost
  expires_on: 2026-11-30
```

## Guard Contract

### Guard 1 — G3.7 two-signal flush-latch gate

**Property.** No arm proceeds unless the dedicated host is currently reporting **and** shows no
evidence of a prior FLUSHALL; absence of evidence from a silent host never reads as permission.

**Assembly.** The chokepoint is the single `FL_OUTCOME` allowlist test in the `arm)` case of
`scripts/cutover-inngest.sh`. Every input flows through exactly two reader functions (latch count,
liveness count) and one pure decider, each with exactly one call site, all defined at column 0
outside the arm. The property quantifies over the decider's full input cross-product, not over the
outcomes that happen to exist today — a fifth outcome added later must still funnel through the same
test.

**Mutation matrix.**

| # | Mutation | Must drive |
|---|---|---|
| 1 | Liveness reader returns `0` while the latch reader returns `0` | RED — outcome `silent`, gate refuses |
| 2 | Delete the liveness reader's call site so only the latch signal is consulted | RED — the two-call-site assertion fails |
| 3 | Change the chokepoint from `!= "clear"` to a blocklist of specific refusals | RED — the positive-allowlist assertion fails |
| 4 | Move the G3.7 gate line after the first prod write | RED — the ordering assertion fails |
| 5 | Add a **second** terminal outcome not routed through the chokepoint | RED — the single-chokepoint assertion fails |
| 6 | Neuter the decider so it always returns `clear` (its own dispatch) | RED — the decision-table canary fails and the evaluation floor is not met |
| 7 | Make a reader return the empty string on a broken pipe | RED — the `^[0-9]+$` predicate yields `unreadable`, never a numeric comparison |

**Harness rows.** (a) Delete one row from the decision-table fixture — the evaluation floor must fail,
proving the harness cannot silently shrink. (b) A must-PASS input that is **not** the canonical:
`L=0, H=7` with a differently-shaped but valid liveness payload must still yield `clear`, proving the
gate is not simply rejecting everything.

### Guard 2 — `inngest-volume-recut` destroy-guard

**Property.** The recut destroys the named volume and its attachment and **nothing else**, and it
cannot run without a human approval that actually exists.

**Assembly.** The saved Terraform plan JSON is the single artifact quantified over — not the plan
text, not console output. Every entry in `resource_changes` is classified; the guard fails closed on
any action outside the permitted delete+create on the volume pair. The authorization assembly is the
job's `environment:` key **plus** the provisioned environment's reviewer list; both are asserted,
because either alone is satisfiable while the other is absent.

**Mutation matrix.**

| # | Mutation | Must drive |
|---|---|---|
| 1 | Plan JSON shows any action on `hcloud_server.inngest` | RED |
| 2 | Empty the environment's reviewer set | RED — the non-empty predicate fails (mutation-tested, block-scoped) |
| 3 | Remove the `environment:` key from the job | RED |
| 4 | Add a **second** unrelated resource with a delete action after a compliant first | RED — proves the guard does not stop at the first resource |
| 5 | Guard exits 0 having classified zero resources (its own dispatch) | RED — the min-cardinality floor fails |
| 6 | Swap the confirm literal for another target's literal | RED |
| 7 | Break the count step so the resource count is the empty string | RED — numeric validation refuses; must not pass via arithmetic coercion |

**Harness rows.** (a) Break the guard's invocation so it is never sourced — the suite must fail rather
than report zero findings. (b) A must-PASS non-canonical plan JSON containing the volume pair plus an
unrelated **no-op** resource must still pass, proving the guard permits no-ops rather than rejecting
everything.

### Guard 3 — enum↔job binding for apply targets

**Property.** Every `apply_target` enum option has exactly one job that runs for it; an option with
no job cannot ship.

**Assembly.** The enum options block and the set of job-level `apply_target ==` guards, both parsed
from `apply-web-platform-infra.yml`. The property quantifies over **all** options, not the newly
added one.

**Mutation matrix.**

| # | Mutation | Must drive |
|---|---|---|
| 1 | Add an enum option with no matching job | RED |
| 2 | Delete the `inngest-volume-recut` job while keeping the option | RED |
| 3 | Add a **second** orphan option after a compliant first | RED — proves the check does not stop at the first mismatch |
| 4 | Parser matches zero options (its own dispatch) | RED — the min-cardinality floor (≥ 15 options) fails |

**Harness rows.** (a) Point the parser at an empty file — the floor must fail rather than report
clean. (b) A must-PASS input where a job guard uses a different but valid expression shape must still
bind, proving the matcher is not over-fitted to one literal spelling.

## Domain Review

**Domains relevant:** Engineering.

### Engineering (CTO)

**Status:** reviewed

**Assessment:** The design call for scope item 2 was routed to the CTO agent as the ask directed,
because it had grown past a mechanical wiring. The review corrected a load-bearing error in this
session's research — an earlier claim that `deploy-inngest-image.yml` delivers code to the dedicated
host, which is false; it reaches the *web* host, and the dedicated host's image is pinned by a digest
literal inside the forbidden `cloud-init-inngest.yml`. That correction converted the proposed
probe-enrichment deliverable from "repo-only, ships now" to "replace-coupled, deferred", and is why
Phases 1–5 are all repo-side.

The review independently reached the same root cause (standing `rollback` flag → `stop_server` →
terminal `rolled-back`) and supplied the `silent`-outcome decision table and the liveness-witness
idea that Phase 1 implements. Two of its inputs were **corrected by measurement** rather than
adopted: its suggestion that a new marker was needed is unnecessary (the tag is already allowlisted
and arriving), and its ~2,880 rows/day quota estimate was re-measured at ~2,450/day — close enough to
confirm the defect is real, and now sourced from a command rather than an estimate.

**Risk ratings carried forward:** Phase 1 low (repo-only, fail-closed direction, no prod write);
Phase 6 medium (must not break the witness Phase 1 depends on — resolved by rate-limiting rather than
going transition-only); Phase 3 high blast-radius but inert as shipped; any `cloud-init` edit high
and therefore excluded.

**User-Challenge (operator direction, not silently applied).** The ask specified a webhook id; this
plan does not build one. The mechanism is blocked by an explicit ADR-100 rejection (SEC-H2) and by
replace-only delivery, and the ask's own escape hatch ("if this grows past a mechanical wiring, route
the design call to the CTO agent") was exercised. The **intent** — an authoritative, no-SSH
flush-latch signal with Better Stack secondary — is delivered via the ADR's adopted transport. This
is recorded to `knowledge-base/project/specs/<branch>/decision-challenges.md` for surfacing rather
than being applied quietly.

### Product/UX Gate

Not applicable — no path in `## Files to Edit` or `## Files to Create` matches a UI surface; this is
infrastructure and workflow tooling with no user-facing render.

## Open Code-Review Overlap

**None.** Checked 2026-08-25 against all 65 open `code-review` issues
(`gh issue list --label code-review --state open --json number,title,body --limit 200`, then a
standalone `jq --arg path … | contains($path)` per planned path). No open scope-out mentions
`scripts/cutover-inngest.sh`, `apps/web-platform/infra/cutover-inngest-workflow.test.sh`,
`.github/workflows/apply-web-platform-infra.yml`, `apps/web-platform/infra/inngest-cutover-flip.sh`,
`.github/workflows/infra-validation.yml`, or
`knowledge-base/engineering/operations/runbooks/inngest-server.md`.

## Test Scenarios

1. `flush_latch_decide` across the full input cross-product, including both non-decimal arms, with a
   live comparator canary.
2. Liveness reader argv fidelity: `-c prd_terraform`, `scripts/betterstack-query.sh`, the window
   literal, and field isolation on the dedicated host — asserted term by term against a stubbed
   `doppler` that records its argv.
3. Gate ordering: G3.6 line < G3.7 line < first prod write line.
4. Single-chokepoint and no-`exit 1`-in-arm assertions.
5. The `arm)` body contains no literal off-host read path.
6. Enum↔job binding across all `apply_target` options, with the orphan-option mutation.
7. Recut destroy-guard against saved plan JSON fixtures: compliant, server-touched,
   second-unrelated-destroy, zero-resource, and empty-count.
8. Environment reviewer-set non-emptiness, block-scoped and mutation-tested.
9. Successor probe: git-index mode, banned-form absence, `set -uo pipefail` without `-e`, and a
   positive assertion on `server_active=active` **and** `http_code=200`.
10. `cloud-init-inngest.yml` untouched, asserted against `origin/main`.

## Risks & Sharp Edges

- **A host replace is not a shortcut.** It reboots into the same `rolled-back` flag, the poller stops
  the unit again within 30 s, and it destroys the 5.4-day standing evidence (`boot_id cb4e3bb0`) that
  is the diagnostic subject. It also force-replaces the fleet's sole scheduler.
- **Do not tune `FLUSH_LATCH_SINCE` as the fix.** With H5/H6 unresolved, widening or narrowing the
  window tunes a parameter whose adequacy is unmeasurable. The `silent` outcome is the fix precisely
  because it is correct under either branch.
- **The probe is the shared renderer for two hosts.** web-1 legitimately reports
  `cutover_flag=unknown` and has no `cat-inngest-cutover-state.sh`. A reader that substring-matches
  instead of field-isolating on the host will read web-1's rows as the dedicated host's.
- **Phase 6 and Phase 1 land out of step by construction.** The rate-limit is replace-coupled; the
  window is sized for both cadences. Tightening it below ~5 minutes would make the gate read `silent`
  on a healthy host after the next replace — inverting the semantics it exists to fix.
- **`-luks-` in the target name would be a lie.** The volume is `ext4`. The naming decision is
  recorded in Research Reconciliation so a later reader does not "restore consistency" with the
  sibling targets by renaming it back.
- **Raise the test floor by running the file**, never by copying a remembered figure — the suite's own
  comment insists on this.
- **A query whose result bounds this plan's options must not be run through a jq expression with
  stderr suppressed.** Two of this session's near-misses came from that shape; both were caught only
  by re-running the query in a count-only form.
- **Do not empty the `## User-Brand Impact` section.** A plan whose section is empty, contains only
  placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6 and preflight Check 6. The
  threshold here is `aggregate pattern`, deliberately: the production scheduler is unaffected and the
  destructive path ships inert, so no single user's data is at risk in this PR.
