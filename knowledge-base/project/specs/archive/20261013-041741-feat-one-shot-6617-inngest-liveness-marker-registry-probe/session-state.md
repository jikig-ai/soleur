# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-20-feat-inngest-liveness-marker-discriminators-and-registry-probe-op-plan.md
- Status: complete

### Errors
- Plan write blocked once by the IaC-routing PreToolUse hook — an acceptance criterion quoted a
  forbidden literal (a Doppler secret-write command) in order to *prohibit* it. Reworded rather
  than adding the opt-out ack, since the plan introduces no manual provisioning. Recorded as a
  Sharp Edge in the plan.
- v1 of the plan carried four P0 design defects, all caught by the review panel and corrected in
  v2 (see the plan's Review Reconciliation table). No defective plan was committed — v1 was
  rewritten before the first commit.
- deepen-plan Phase 4.55 halted the plan (force-replace of a serving resource with no
  zero-downtime evaluation). Closed by adding the required section; telemetry emitted.

### Decisions
- Re-scoped from "build a marker" to "extend + deliver" after measuring that PR #6702's marker is
  on `main` and inert on the host, with a passing positive control proving the zero-row reading
  was real.
- Replaced `backend_sha8` with `backend_is_prod` sourced from `inngest-server-flip-guard.sh`,
  eliminating a guaranteed false-escalation defect (prod and dark would have hashed identically),
  a missing cross-host comparand, and a `/proc/environ` read contradicting the repo's secrets
  boundary.
- Decoupled the H4 double-scheduler answer from the host replace by adding `op=doublefire-probe`
  alongside the requested `op=registry-probe` — the replace becomes delivery, not diagnosis.
- Split into three ordered PRs so the #6295 credential-leak fix is not gated behind an OCI build,
  and so two contradictory close semantics do not share one PR body.
- `Ref #6617`, not `Closes` — the close-condition is a post-merge replace, with explicit branches
  that refuse to close on a degraded or positive reading.

### Components Invoked
- Skill: soleur:plan, soleur:plan-review, soleur:deepen-plan
- Agents: Explore x2, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer,
  architecture-strategist, spec-flow-analyzer, cto, cpo
- scripts/betterstack-query.sh (hot + archive arms, with positive control)
- gh issue/pr view for premise validation; git log/grep for attribution checks
- .claude/hooks/lib/incidents.sh — emit_incident for the Phase 4.55 gate

## Scope Ruling (operator, 2026-07-20)

> **SUPERSEDED 2026-07-20 — PR C is now CANCELLED, not HELD.** The "separate decision" this block
> awaits has been made: see § "Closing entry (2026-07-20): PR C cancelled" at the end of this file,
> and the authoritative § "Follow-on ruling — 2026-07-20: PR C is CANCELLED" in
> `decision-challenges.md`. Two claims below are no longer live: PR C's **HELD** status (now
> cancelled outright), and the #6348 stranding race (**dissolved** — cancelling PR C means there is
> no undelivered PR C to strand). The block is retained verbatim as the record of the ruling as it
> stood when written.

Operator was presented UC-1 (three-PR split) and UC-2 (priority reorder) and ruled:

**Ship PR A + PR B now. PR C is HELD pending a separate decision.**

- **PR A** (`_pf_scrub` libpq redaction, `Closes #6295`) — in scope.
- **PR B** (standalone `op=registry-probe` + `op=doublefire-probe`, `Ref #6617`) — in scope.
  Carries the H4 answer with **no host replace**.
- **PR C** (marker discriminators + `apply_target=inngest-host` delivery) — **HELD**. Not to be
  implemented, pushed, or merged in this run. The operator will decide after reading PR B's
  actual probe output (Phase B4.2).

Rationale: PR C's delivery path force-replaces the sole production Inngest scheduler days before
the cutover it instruments. PR B answers the double-scheduler question without that risk, so the
replace decision is better made with the probe reading in hand than ahead of it.

Live race noted: PR #6348 is draft and MERGEABLE. If it merges before PR C, PR C would be
stranded merged-but-undelivered. This does not affect A or B.

## B4.2 / B5 — the H4 double-scheduler answer (recorded 2026-07-20)

Both standalone ops were dispatched against the branch. **One returned a verdict; one
surfaced a pre-existing defect that had to be fixed before it could.**

### `op=registry-probe` — ANSWERED (run 29729509511, success)

```
registry-probe: registry_empty=true function_count=0 ids=[]
```

**No SDK has registered functions against the dedicated host (10.0.1.40).** Its registry is
empty. Corroborates #6488's 2026-07-15 finding that `INNGEST_CUTOVER_FLIP` is unset and
`INNGEST_POSTGRES_URI` still points at the dark soleur-dev backend.

Also confirms **B-AC6**: the run completed with no pending-approval state, i.e. the
`environment:` expression evaluated to `''` for the new op — no reviewer gate was engaged.

### `op=doublefire-probe` — BLOCKED, then fixed (run 29729623865, failure → HTTP 500)

The dispatch returned HTTP 500. The host's own journald named the cause:

```
inngest-doublefire-probe: SOLEUR_INNGEST_PREFLIGHT_START op=verify-doublefire
  host=soleur-web-platform window=2025-07-20T08:57:28Z..open page_ceiling=1000 deadline_s=50
webhook: command output: jq: invalid JSON text passed to --argjson
webhook: error occurred: exit status 2
```

The `page_ceiling=1000 deadline_s=50` in the START marker matches the current repo defaults,
so the host copy was **not** stale — the defect is in the shipped code. `build_request_body`
used `printf '%s'`, which emits zero bytes for an empty CSV, so `jq -R` emitted nothing and
`--argjson fnids ""` aborted.

**This is the DEFAULT path.** `op=verify` step 2.6 passes no `FUNCTION_IDS`, so the cutover's
exactly-once double-fire check could never have produced a verdict. Fixed inline (one line,
`printf '%s\n'`) with a test that calls `build_request_body` directly — every pre-existing
test bypassed it, because the fixture seam returns before that function is reached.

### Outstanding

> **SUPERSEDED 2026-07-20 — see § "Closing entry (2026-07-20): PR C cancelled" at the end of this
> file.** The doublefire reading described below HAS since been taken: run 29748606817 returned
> ZERO runs on the dedicated host, and the registry-alone caveat below is thereby **discharged**.
> The block is retained verbatim as the record of what was outstanding when it was written.

The doublefire reading itself is **not yet taken**. The host runs the deployed copy of
`inngest-doublefire-probe.sh`; the fix reaches it via the post-merge infra-config push. Re-dispatch
`op=doublefire-probe` after this merges and delivery lands, and record the run count there.

**Do not read the registry result alone as "no double-scheduler."** An empty registry means
nothing has registered *now*; it is not proof that nothing executed earlier. The doublefire
probe is the instrument that proves the harm, and it has not yet run successfully.

---

## Closing entry (2026-07-20): PR C cancelled

**Decision: the operator cancelled PR C.** It was previously HELD by the operator ruling recorded
in `decision-challenges.md`; that hold is now superseded by outright cancellation. The
authoritative ruling is the follow-on entry appended to that file. This entry is the session
narrative: what was measured, what was decided, what carries forward.

### What shipped, and in what shape

PR A + PR B **merged together as #6748** (commit `1d4208f44`, 2026-07-20) — one PR, not two.
That PR also carried a third piece: making `op=verify`'s exactly-once check capable of returning a
verdict. #6295 closed with it.

### The four measures

The diagnostic question PR C existed to answer — what state is the dark dedicated Inngest host in —
is now settled on four independent measures, **none of which required the host replace**:

| # | Measure | Reading | Source |
|---|---|---|---|
| 1 | doublefire probe | **ZERO runs** on the dedicated host | run 29748606817, dispatched from `main` (sha `898de92e4`) after #6748 merged |
| 2 | registry probe | `registry_empty=true`, `function_count=0` | run 29729509511 |
| 3 | `backend_is_prod` | **no** (i.e. FALSE) — the dedicated host's `INNGEST_POSTGRES_URI` does not contain the prod project ref | evaluated against the `soleur-inngest/prd` Doppler config **without ever rendering the URI** (AC-NOBODY preserved) |
| 4 | start-blocked | `INNGEST_CUTOVER_FLIP` is **absent** from `soleur-inngest/prd`, so the flip guard refuses any prod-URI start | corroborates #6488 |

Phase C6.3's escalation branch fires on `backend_is_prod=yes` **OR** a non-empty doublefire result.
**Neither limb is met.**

### The registry-alone caveat is discharged, not bypassed

The § Outstanding block above warns that an empty registry proves nothing has registered *now*, not
that nothing executed earlier. That caveat was written when the doublefire probe had not yet run
successfully. It is now **discharged** by run 29748606817 — the instrument that proves the harm
itself has run and returned empty. Verbatim annotations:

```
doublefire-probe: 0 run(s) in window; bucketing by (functionID, floor(startedAt / 3600s))
doublefire-probe: ZERO runs on the dedicated host — its scheduler has executed nothing in the window.
```

This read was taken from `main` **after** #6748 merged, so it exercised the shipped
`build_request_body` fix rather than the branch copy. That is precisely what made B4.2.b
answerable: its blocker was that the host ran the unfixed deployed copy.

Scope caveat carried forward from the probe's own output: this reads ONLY the dedicated host's run
history. It is not a web-2 double-fire detector, and the operator's web-2 quiesce remains the
control against that failure mode.

### Why CANCEL rather than continue to HOLD

> PR C's discriminators exist to distinguish states of a **dark** host. After the cutover the
> dedicated host becomes the live scheduler and that question is no longer asked. The instrument's
> useful life is therefore **bounded by the pre-cutover window** — and it cannot be delivered
> inside that window at acceptable risk, because its delivery force-replaces the sole production
> Inngest scheduler days before the cutover it was built to instrument.
>
> **An instrument that cannot be delivered while it still matters is cancelled, not parked.**

The reason delivery costs a full host replace is #6780: the dedicated host has no in-place
redelivery channel. That root debt is what makes "park it and deliver later" not actually
recoverable.

### The `sdk_url` note

`sdk_url` was the one discriminator with **no off-host channel**. It is read from the unit's
ExecStart argv (`systemctl show -p ExecStart`), which reads configuration and therefore works while
the host is dark — that is what made it viable as a marker, and also what makes it the field that
dies with the cancellation. It is **not decision-relevant while `backend_is_prod` is false**: a host
not wired to prod Postgres cannot corrupt prod state regardless of which SDK URL it would poll.

### Consequence the operator is accepting

After cancellation the dedicated Inngest host has **no continuous liveness discriminators**. Its
observability posture is on-demand only, via the two standalone ops PR B shipped
(`op=registry-probe`, `op=doublefire-probe`). This is what makes #6780 the live root debt rather
than a filed-and-forgotten follow-up.

### Carry-forward items (already filed — referenced, not re-filed)

- **#6780** — C5.8 root debt: the dedicated host has no in-place redelivery channel.
- **#6781** — C6.7 / T-4: the cron send-path has no idempotency guard.
- **#6608** — was C6.6 ("rides along, closed post-replace"). *(Status corrected 2026-07-22:
  not re-homed in a separate session — no such session materialized. The code fix landed via
  #6664 on 2026-07-18 and is inert by design (`hcloud_server.inngest` is excluded from the
  per-merge `-target`); the corrected nftables allowlist re-renders when the dedicated host is
  re-provisioned. With PR C cancelled there is no pre-cutover replace, so #6608 now waits for the
  actual Phase-2 cutover — it waits longer, not orphaned. Close after that apply confirms the
  rendered `ip saddr` set no longer contains `.11`. It does NOT depend on #6780: that is an
  in-place *script* delivery gap; #6608 is terraform-rendered host config that a replace covers.)*
- **#6348** — the draft `INNGEST_BASE_URL` repoint PR. The original operator ruling recorded a
  standing risk that if it merged before PR C was delivered, PR C would be stranded
  merged-but-undelivered. **Cancelling PR C dissolves that risk.**

### Tracking issue

#6617 remains **OPEN** and its state was not altered by this change. Its existing follow-through
sweeper owns closure.
