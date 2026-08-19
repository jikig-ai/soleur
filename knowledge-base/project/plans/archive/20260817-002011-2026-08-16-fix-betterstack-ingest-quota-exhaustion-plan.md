---
title: "Restore Better Stack ingest and make an account-wide refusal alarm instead of reading as silence"
date: 2026-08-16
slug: fix-betterstack-ingest-quota-exhaustion
branch: feat-one-shot-7569-registry-log-channel-dark
issue: 7569
closes: 7569
lane: cross-domain
type: fix
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Restore Better Stack ingest and make an account-wide refusal alarm instead of reading as silence

## Overview

Issue #7569 reports the registry host's container-log channel dark since 2026-08-14 19:06:58Z and
names four candidate causes, all on the registry side. Every one of those four is refuted by
measurement taken this session. The registry host is not implicated at all.

The Better Stack account is over its ingest quota. A POST to the Logs ingest endpoint carrying the
live `BETTERSTACK_LOGS_TOKEN` answers **HTTP 402 `{"error":"Quota exceeded"}`**. Every emitter on
every host, plus the CI-side emitter, stopped writing at the same instant. The registry channel is
simply the consumer that noticed, because it has a follow-through probe watching it.

**This is a repeat of a documented, predicted near-miss.** The 2026-06-10 postmortem
`betterstack-quota-near-miss-postmortem.md` recorded a vendor warning at 80% of a **3 GB/month
free-tier** allowance and stated in terms that at 100% "Better Stack drops new data — which would
have silently blinded the WARN+ log/diagnosis channel". Its 5-Why #5 was "no internal monitor
watches quota". That action item was never closed. Measured now: **3.81 GB/month against a 3 GB
allowance**.

Three things have to change, and they are separable:

1. **A refusal has to alarm.** A producer-silence detector already exists and ran every 30 minutes
   throughout the two dark days without filing anything, because its "can't tell" arm is fail-open
   for exactly the total-outage shape. That is the durable defect and the primary deliverable —
   and the repo already contains the correct four-outcome taxonomy in
   `scripts/betterstack-assert-absence.sh`, so this is a reuse job, not a new mechanism.
2. **The volume has to come down.** 64% of all account ingest is one chronic error loop logging an
   already-known-down dependency (#7462) at full stack-trace fidelity, amplified ~14× by a single
   open arm in `vector.toml` that ships every unparseable line past the level gate. Fixing that one
   arm brings steady state to ~1.48 GB/month — **the free tier becomes viable again**.
3. **The current period's consumed allowance has to be addressed.** This is the one step no code
   can perform.

The invariants this change records: **every emitter is bounded per unit time regardless of trigger
frequency**, and **a detector must not read exclusively over the channel it monitors.**

## Research Insights

### Premise Validation (Phase 0.6)

Every reference cited in the issue was probed. All premises hold; none is stale.

| Reference | Probe | State | Effect on plan |
|---|---|---|---|
| #7569 | `gh issue view` | OPEN, `priority/p1-high`, `type/bug`, `domain/engineering` | Valid work target |
| #7440 | `gh issue view` | CLOSED by PR #7444 | Correct provenance for the shipper |
| ADR-184 | file present | `knowledge-base/engineering/architecture/decisions/ADR-184-registry-host-container-log-shipper.md` | Design of record for the channel |
| #7556 | `gh issue view` | OPEN — soak follow-through for #7555 | Genuinely blocked; unblocks when ingest resumes |
| #7555 | `gh issue view` | OPEN — P1 zot 60s HTTP deadline | Genuinely blocked |
| #7071 | `gh pr view` | MERGED — GHCR fallback removal | Registry really is the sole pull path |
| `scripts/betterstack-query.sh` | `ls` | present, executable | Query path exists as described |

One correction to the issue's framing, not a stale premise: the issue treats the 72h positive
control as proof the producer stopped. It proves the *read path* works. It does not distinguish a
stopped producer from a refused write, and that gap is what the diagnosis turned on.

### Measured evidence (self-pulled 2026-08-16, `hr-no-dashboard-eyeball-pull-data-yourself`)

Observability layer: **5 — host/container journald and direct-POST reporters shipped to Better
Stack Logs source 2457081** (`hr-observability-layer-citation`).

**A. The ingest boundary is refusing writes.** This is the root cause and it is a direct
measurement, not an inference:

```
POST https://s2457081.eu-fsn-3.betterstackdata.com/   (live BETTERSTACK_LOGS_TOKEN)
  -> HTTP 402   {"error": "Quota exceeded"}
POST https://in.logs.betterstack.com/                 (same token)
  -> HTTP 402   {"error": "Quota exceeded"}
```

**B. The whole shared source is dark, not the registry channel.** Per-day counts, hot window
`UNION ALL` s3 archive:

| Day | Rows |
|---|---|
| 2026-08-13 | 61,669 (partial — retention edge) |
| 2026-08-14 | 107,567 |
| 2026-08-15 | 0 |
| 2026-08-16 | 0 |

**C. A clean cliff, not a decay.** Hourly on 08-14: flat ~5,500 rows/hour through 18:00, then 612
in the 19:00 hour, then nothing. 612 rows at 91.7 rows/min is ~6.7 minutes, which lands the stop at
~19:06:40 — consistent with the newest surviving row, `2026-08-14 19:07:03.208100`. A ceiling, not
a failing producer.

**D. The destination and all credentials are healthy** — which is precisely why this presented as a
producer fault:

- source 2457081 exists, `ingesting_paused: false`, table `soleur_inngest_vector_prd_3` unchanged
- the source's current ingest token `sha256[0:12] = 81dea0a18e97` equals `BETTERSTACK_LOGS_TOKEN`
  in Doppler `soleur/prd_terraform` — not rotated, not expired
- the writer URL equals the API's reported `ingesting_host`
- the mgmt API and the ClickHouse read path both still answer 200

**E. Retention is 3 days and the evidence is expiring.** `logs_retention: 3`. Oldest surviving row
at time of measurement was `2026-08-13 13:13:45`; the newest is `2026-08-14 19:07:03`. **The last
surviving row ages out at approximately 2026-08-17 19:07Z**, after which every query returns zero
and the positive control that makes this diagnosis legible is gone. That is a real deadline on the
verification steps in this plan, not a rhetorical one.

**F. Where the volume comes from.** 2026-08-14, grouped by producer:

| Producer | Rows/day | Share |
|---|---|---|
| container `soleur-web-platform` (`dba0075ad965`) | 80,320 | 75% |
| host metrics (`namespace: host`) | 17,862 | 17% |
| other/unattributed | 5,150 | 5% |
| `web-git-data-probe` | 2,259 | 2% |
| `web-zot-consumer-probe` | 1,167 | 1% |
| `doppler`, `web-nic-guard`, `webhook`, `inngest-inventory`, `sshd`, `luks-monitor` | < 800 combined | < 1% |

The host-metrics figure (17,862) is consistent with ADR-184's ~19.9k/day estimate. **The registry
container-log channel that #7569 is filed against does not appear at all** — ADR-184's 5,000/day
cap held. The design the issue implicitly blames is exonerated by the data.

**G. Inside the 75%: one chronic error loop.** Message-shape distribution for the
`soleur-web-platform` container on 08-14:

| Message | Rows/day |
|---|---|
| `}` | 9,154 |
| `at async p.wrap (.next/server/app/api/inngest/route.js:815:8249)` | 9,152 |
| `at <unknown> (Error: connect ECONNREFUSED 10.0.1.40:8288) {` | 4,576 |
| `[cause]: Error: connect ECONNREFUSED 10.0.1.40:8288` | 4,576 |
| `code: 'ECONNREFUSED',` / `address: '10.0.1.40',` / `syscall: 'connect',` / `port: 8288` / `errno: -111,` | 4,576 each |
| `[Inngest] error - TypeError: fetch failed` | 4,572 |
| `at async w.handleAction …` / `w.register …` / `j (…673.js)` | 4,572 each |
| `[resolve-origin] Rejected origin: …` (6 distinct origins) | ~6,744 combined |

The `ECONNREFUSED 10.0.1.40:8288` cluster sums to **~68,600 rows/day ≈ 64% of all account
ingest**. One logical event bills as ~14 rows because the Node error is pretty-printed across
physical lines and Vector's journald source ships one row per line.

**H. The loop is chronic, not a spike.** Hourly count of `ECONNREFUSED 10.0.1.40:8288` is flat at
472–595/hour across both surviving days. So the quota exhaustion is cumulative against a steady
overspend, not a sudden burst. **The unreachable Inngest host is already tracked by OPEN issue
#7462** ("restore the dedicated inngest host — replace, diagnostic boot, cutover window").

**I. A producer-silence detector already exists and stayed quiet.** `scripts/zot-restart-loop-alarm.sh`
driven by `.github/workflows/scheduled-zot-restart-loop.yml` at `*/30 * * * *`. Runs through the
outage all report `completed/success`. The live verdict from run 31950267930 (2026-08-16T13:36Z):

```
ZOT_ALARM_VERDICT=TRANSIENT
##[warning]zot restart-loop alarm TRANSIENT (probe fault / zero valid evidence) —
  recent 3h empty AND control-marker query empty/errored (rc=0) —
  Better Stack unreachable / creds unset. No issue filed;
  the errored Sentry check-in surfaces a persistent probe fault.
```

The detector saw the silence every 30 minutes for two days and filed nothing by design.

**J. Two conflations make that arm fail-open.** In `scripts/zot-restart-loop-alarm.sh`, the
zero-rows discriminator reads:

```bash
CONTROL="$("$BQ" --since "$WINDOW" --limit 1 2>/dev/null)"; control_rc=$?
if [[ "$control_rc" -ne 0 || -z "$CONTROL" ]]; then
  VERDICT="TRANSIENT"; DETAIL="recent ${WINDOW} empty AND control-marker query empty/errored (rc=${control_rc}) …"
  emit_and_exit 2
fi
```

- **Conflation 1 — error vs empty.** `control_rc -ne 0 || -z "$CONTROL"` routes both to TRANSIENT.
  The alarm's own detail string prints "empty/errored (rc=0)" — it *had* the discriminating fact
  in `control_rc` and threw it away with the `||`.

  **Correction to the issue body, and to this plan's own first draft.** #7569 states that
  `betterstack-query.sh` "runs `set -uo pipefail` WITHOUT `-e`" and implies it can exit 0 on a
  failed curl. **That is false, and it was measured false this session.** `run_sql` is the last
  command on both mode-2 branches, so curl's status is the script's status, and
  `curl -sS --fail-with-body` propagates:

  | Invocation | Exit |
  |---|---|
  | bad SQL (`SELECT bogus_col …`) | **22** |
  | unreachable host | **6** |
  | valid query, zero rows | **0** |
  | credentials not injected | **3** (documented in the script header) |

  So the transport already distinguishes error from empty. **The defect is purely the `||`
  collapse at the two call sites** — nothing in `betterstack-query.sh` needs fixing. Shipping a
  transport fix here would be a remedy for a mis-derived mechanism, which is the failure this
  repo's own Sharp Edges warn about most often.
- **Conflation 2 — no ingest-side signal at all.** When ingest stops account-wide, the control
  query is empty *because writes are refused*, not because the reader is broken. The arm reads
  that as "Better Stack unreachable / creds unset" and shrugs. **The one condition that produces a
  total outage is exactly the condition this detector is built to stay silent about.**

  The adjacent `PRODUCER_SILENT` arm's own cause text already names "ingest outage" as a thing to
  check — the design anticipated it and then routed the total case away from it.

The identical pattern exists in the private-NIC arm of the same script (`NIC_VERDICT="TRANSIENT"`
on `control_rc -ne 0 || -z "$control"`), so this is two sites, not one.

**K. This exact outcome was predicted, documented, and left unguarded two months ago.**
`knowledge-base/engineering/operations/post-mortems/betterstack-quota-near-miss-postmortem.md`
(2026-06-10) records a vendor email at **80% of a free-tier quota of 3 GB/month logs with 3-day
retention**. Its own framing:

> "At 100%, Better Stack drops new data — which would have silently blinded the WARN+
> log/diagnosis channel (Sentry and uptime monitors were unaffected)."

That is precisely what happened on 2026-08-14. Its 5-Why #5 reads:

> "Why did nobody notice for ~20 days? Better Stack has no usage API and **no internal monitor
> watches quota**; detection depended on the operator reading a vendor email."

That action item was never closed. The remediation then (#5105/#5131) cut *host metrics*, and its
own AC12 verdict **FAILED** at ~57k/day against a ≤25k/day target, with the runtime verdict left
open on **#5110**. Host metrics are now measured at 17,862/day, so that arm did eventually land —
but the ceiling was re-approached from an entirely different direction that no guard was watching.

**This plan must therefore not write a fresh ADR restating an open action item.** It closes the
loop the near-miss opened, and cites it.

**L. The quota arithmetic closes exactly.** Measured on 08-14: 107,567 rows totalling
136,556,248 bytes — **mean 1,269 bytes/row** (the journald metadata envelope dwarfs the message),
**0.127 GB/day**.

| Quantity | Value |
|---|---|
| Free-tier allowance (per the near-miss postmortem) | **3 GB / month** |
| Measured | 0.127 GB/day → **~3.81 GB/month = 127% of allowance** |
| Sustainable ceiling at 1,269 B/row | **~84,600 rows/day** |
| Observed | 107,567 rows/day |
| After removing the ECONNREFUSED cluster (~68,600/day) | ~39,000 rows/day → **~1.48 GB/month ≈ 49% of allowance** |

**The volume cut alone is sufficient to stay on the free tier**, with roughly 2× headroom. A paid
tier is therefore very likely avoidable for steady state — see §Domain Review for the costed
recommendation. What the cut cannot do is un-consume the allowance already spent in the current
billing period.

**M. The amplification flows through one arm in `vector.toml` — but that arm is DELIBERATE, and
an earlier draft of this plan misread it as waste.**
`apps/web-platform/infra/vector.toml:83` — `[transforms.app_container_warn_filter]`:

```
parsed, parse_err = parse_json(.message)
if parse_err != null {
  true                      # <- unparseable lines bypass the level gate
} else if is_object(parsed) {
  ...
  level_int >= 40           # <- the gate structured lines must pass
}
```

Every line that is not parseable JSON bypasses the `level >= 40` gate. Both offenders ride it: each
of the ~14 physical lines of a pretty-printed Node stack trace fails `parse_json`, and so does
every bare `console.warn` — including `resolve-origin.ts:20`, which the module header explains
*must* use `console.warn` because it is edge-runtime and cannot import the pino logger.

**The comment directly above the transform states the arm's purpose:**

> `# Non-JSON lines (container crash / uncaught-exception stack on fd 2) are kept.`

So the arm is **load-bearing**, not an oversight: it is the only off-box evidence that the app
container died mid-request. This plan's first draft — and the engineering advisory that informed
it — both called it "the single hole" after reading the condition and not the rationale five lines
above. **A naive bound would delete container-crash capture**, which is a worse outcome than the
quota exhaustion it fixes.

The fix must therefore **discriminate rather than suppress**: collapse repeated inner stack frames
of the same event, preserve the **first line of every distinct non-JSON event**. That keeps crash
capture whole while removing the ~14× multiplier. Recorded here because "read the condition, miss
the comment" is the exact failure this plan is otherwise about.

Two further facts, both verified: there is **no `throttle` transform anywhere** in `vector.toml`
(`[sinks.betterstack].inputs = ["tag_journald", "tag_metrics"]`), and the file's own comments
already cite "the 2026-06-10 quota-diagnosis learning + #5110 verdict" as the reason Source 2's
PRIORITY filter is kept narrow. The quota was known about and guarded for on one source while
Source 3's parse_err arm stayed wide open.

**N. Blast radius is far wider than the registry channel.** `git grep -ln betterstack-query.sh`
over `.github scripts apps tests` returns **63 files**. Every absence-asserting consumer among
them has been reading a dark warehouse since 08-14 and may have been reporting green. Named
examples to triage first: `.github/workflows/inngest-config-drift.yml`,
`.github/workflows/reusable-release.yml`, `apps/web-platform/infra/infra-config-gate.sh`,
`apps/web-platform/infra/ci-deploy.sh`.

### Property List (Phase 0.6b)

What the ask actually requires, as observable outcomes:

- **P1.** Better Stack ingest accepts writes again, so every channel — registry container logs,
  `SOLEUR_ZOT_DISK`, host metrics, CI markers — is observable.
- **P2.** An account-wide ingest refusal, or any total telemetry stop, raises an operator-visible
  alarm within hours rather than going unnoticed for two days.
- **P3.** Standing ingest volume sits far enough under the account allowance that P1 does not
  regress.
- **P4.** #7556's soak probe can reach a real verdict, unblocking #7555's verification.

### Cut List (Phase 0.6b)

Mechanisms considered and removed before any research or design was spent on them. Each was checked
against the authority named, per `hr-verify-repo-capability-claim-before-assert`.

| Mechanism | Property it would buy | Why cut |
|---|---|---|
| A new "recent row count > 0" watcher workflow | P2 | **Already exists.** `scripts/zot-restart-loop-alarm.sh` computes exactly this every 30 min and has a `PRODUCER_SILENT` verdict + `[ci/zot-telemetry-silent]` issue-filing path (`.github/workflows/scheduled-zot-restart-loop.yml:215-247`). Building a second one would add a mechanism while leaving the first still fail-open. Fix the existing one. |
| A new Sentry cron monitor for telemetry freshness | P2 | Already wired — the same workflow emits a Sentry check-in whose `status` is `error` on TRANSIENT (`scheduled-zot-restart-loop.yml:448`). The gap is not a missing monitor, it is that TRANSIENT was chosen as the verdict. Verify the routing rather than add a monitor. |
| A synthetic canary emitter on the registry host | P2 | ADR-184's Alternatives table already rejected this with a reason that still holds: the 60s liveness beat makes a genuine zot line land every minute by construction, and a shipper-emitted canary would skip the two real failure modes. Also cannot ship at all while ingest is 402. |
| Re-provisioning the registry host | P1 | Refuted by measurement — the host is not implicated. A destructive replace of the sole pull path would cost an authorization and fix nothing. |
| Rotating `BETTERSTACK_LOGS_TOKEN` | P1 | Refuted by measurement — token sha matches the live source token. |
| Re-minting the ClickHouse query connection | P1 | Refuted — the read path answers 200 throughout. |
| A fix to `scripts/betterstack-query.sh`'s exit-code contract | P2 | **Cut — the premise is false.** Measured: bad SQL → 22, bad host → 6, empty → 0, no creds → 3. The transport already discriminates. The `||` collapse at the call sites is the whole defect. |
| A **new** verdict vocabulary (`INGEST_REFUSED` / `PRODUCER_SILENT` / `TRANSIENT`) | P2 | **Cut — already exists.** `scripts/betterstack-assert-absence.sh` implements this exact taxonomy with a 30-line header explaining why: `unknown`(3) = the query did not answer *or* output did not parse as JSONEachRow; `unshipping`(2) = positive control returned 0 rows, channel dark; `present`(1); `clean`(0), the only exit 0 and unreachable without a control read back through the sink. Minting a third vocabulary beside it is the mechanism this gate exists to cut. **Extract its discriminator into `scripts/lib/` and have the zot alarm consume it.** |
| An ingest **write** probe as the *primary* discriminator | P2 | **Demoted, not cut.** Reader-200-over-an-empty-table is already a complete, free, non-consuming signal, and a `SELECT max(dt)` returns the cliff timestamp rather than a boolean. The write probe also (a) expands a read-only alarm's secret set with a **write** credential and (b) **pollutes the signal it measures** — the control query is unfiltered, so the probe's own rows would mask real silence forever. Retained only as *cause annotation* (402→quota, 401→token, 2xx→producer dead), with no veto over the verdict. |

### Institutional learnings applied

| Learning | Application here |
|---|---|
| `knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md` (#6536) | The governing precedent. That plan marked hypotheses CONFIRMED/REFUTED by reasoning while stating its discriminator was unavailable, and burned a host replace on a defect that did not exist. Here **every** candidate is closed by a direct measurement of the thing itself, and the one datum that decided it (the ingest HTTP status) was obtained by probing the boundary rather than arguing about producers. |
| `2026-07-15-zot-mirror-silent-skip-connector-homogeneity-postmortem.md` | "A detector that always alarms is not a detector." The dual here: a detector that resolves the ambiguous case to silence is not a detector either. Same file's "absence was read as health" is the exact shape of the TRANSIENT arm. |
| `registry-disk-heartbeat-false-positive-postmortem.md` | Better Stack heartbeats have no `last_event_at`, so "never pinged" and "stopped pinging" are indistinguishable. Reinforces that the ingest-status probe, not heartbeat state, must be the discriminator. |
| `zot-gate-login-failed-postmortem.md` | The deciding datum was destroyed at the source (stderr discarded). Here every shipper's `curl -fsS` failure breadcrumbs only to host journald, which for the registry host is not shipped — so the 402 was structurally unobservable off-box. Drives the design decision that the guard must live on the CI side of the ingest boundary. |
| `2026-08-03-zot-mirror-blocked-releases-while-the-error-named-a-refuted-cause-postmortem.md` (ADR-166) | An operator-facing message may only name a cause the job measured. The new `INGEST_REFUSED` verdict must report the actual HTTP status it received, never a guessed cause. |

### Conventions carried from AGENTS.md / constitution

- `hr-no-dashboard-eyeball-pull-data-yourself` — every figure above was pulled, not read off a
  dashboard. Where no API exists (vendor usage/billing), the plan asserts the invariant instead.
- `hr-no-ssh-fallback-in-runbooks` — no step in this plan reaches the registry host.
- `hr-observability-layer-citation` — layer 5, cited above.
- `cq-assert-anchor-not-bare-token` — the ingest probe asserts on HTTP status, not on a substring.
- `hr-verify-repo-capability-claim-before-assert` — the "a detector already exists" claim in the
  Cut List was verified by reading the script and its live run output, not assumed.

### Skill description budget

No `plugins/soleur/skills/*/SKILL.md` `description:` edit is candidate in this plan. Check skipped
per Phase 1.8.

## Research Reconciliation — Spec vs. Codebase

The issue body is a careful, well-evidenced filing whose conclusion is nonetheless wrong in scope.
This table is the plan's response to each claim, and it is the basis for the PR-body reframe.

| Issue claim | Measured reality | Plan response |
|---|---|---|
| "The registry container-log channel has been dark" | True, but so is every other channel on source 2457081 | Reframe: account-wide ingest refusal. Keep #7569 as the tracking issue; correct the premise in the PR body |
| Candidate 1 — "the shipper unit on the host stopped (tick failure, `flock` wedge, jq off PATH)" | **Refuted.** A host-local unit fault cannot silence three hosts running two different shipper implementations at the same second | Do not investigate the host |
| Candidate 2 — "the host itself is down or was replaced" | **Refuted.** Same reasoning; also the web-platform and inngest emitters stopped identically | Do not dispatch a host replace |
| Candidate 3 — "the Better Stack source/table was re-provisioned" | **Refuted.** Source 2457081, table `soleur_inngest_vector_prd_3`, `ingesting_paused:false`, writer URL == `ingesting_host` | No re-provisioning work |
| Candidate 4 — "the ingest token expired" | **Refuted.** Doppler token sha == live source token sha (`81dea0a18e97`) | No token rotation |
| "the disk heartbeat's own `soleur-registry-disk-prd` alarm state … [is] queryable" and would discriminate | Partly. The heartbeat's absence signal cannot distinguish producer death from write refusal, and per `registry-disk-heartbeat-false-positive-postmortem.md` Better Stack exposes no `last_event_at` | Use the ingest HTTP status as the discriminator instead |
| "the source's row counts per day are both queryable" | True, and decisive — this is what showed the account-wide cliff | Adopted; the per-day count is folded into the new guard |
| Implicit: ADR-184's shipper is the suspect | It does not appear in the top-10 producers; its 5,000/day cap held | Explicitly exonerate ADR-184 in the ADR and PR body |
| "blocks #7556 … will return `TRANSIENT reason=no-config-line` indefinitely" | Correct, and it generalises — the *restart-loop alarm* fails the same way, resolving a total outage to TRANSIENT | Fix the class, not just the one probe |

## Hypotheses

Phase 1.4 fired on the `SSH` trigger in the feature description. The checklist's L3→L7 ordering is
honoured below: reachability and transport are established before any service-layer hypothesis, and
no sshd/firewall remedy is proposed because the measurement closed the diagnosis above that layer.
Per `hr-ssh-diagnosis-verify-firewall` this ordering is recorded rather than assumed.

| # | Layer | Hypothesis | Discriminator actually run | Verdict |
|---|---|---|---|---|
| H1 | L3/L4 — reachability | Network path to Better Stack is broken | TCP+TLS to both ingest hosts completed; an HTTP response body was returned | **REFUTED** — transport is fine; a 402 is an application-layer refusal |
| H2 | L7 — authn | Ingest token expired or rotated | `sha256` of Doppler `BETTERSTACK_LOGS_TOKEN` == the source's live token | **REFUTED** — identical |
| H3 | L7 — destination | Source/table re-provisioned; writer posts to a dead endpoint | Mgmt API: source 2457081 present, `ingesting_paused:false`, `ingesting_host` == the writer URL | **REFUTED** |
| H4 | L7 — vendor policy | Account is over an ingest quota | Direct POST → `HTTP 402 {"error":"Quota exceeded"}` on both endpoints | **CONFIRMED — measured directly** |
| H5 | host | Registry shipper unit stopped | Cliff is simultaneous across 3 hosts and 2 shipper implementations; registry is not in the top-10 producers | **REFUTED** |
| H6 | host | Registry host down or replaced | Same evidence as H5 | **REFUTED** |
| H7 | reader | The read path or credentials broke | ClickHouse read and mgmt API both answer 200 throughout | **REFUTED** |

No hypothesis in this table is marked from reasoning alone. H4 is the only CONFIRMED entry and it
rests on the HTTP status returned by the boundary itself.

**Open, and deliberately not guessed:** the quota's period and reset date. Better Stack exposes no
usage or billing API — measured 404 on `/api/v1/usage`, `/api/v1/billing`, and
`/api/v1/sources/2457081/usage`. Rather than read a dashboard number
(`hr-no-dashboard-eyeball-pull-data-yourself`), this plan asserts the **invariant** — ingest returns
2xx — and lets the new probe report the transition.

## Network-Outage Deep-Dive

Deepen-plan Phase 4.5 fired on two independent triggers: the prose trigger (`SSH`, `unreachable`,
`ECONNREFUSED` appear in the problem statement) and — more importantly — the **resource-shape
trigger**, because Phase 4's `vector.toml` edit drives an apply on
`terraform_data.journald_persistent`, whose definition contains a `connection { type = "ssh" }`
block. The prose scan alone would not have caught that; the plan body never proposed an SSH step.

Layer-by-layer verification status, L3 → L7, per `hr-ssh-diagnosis-verify-firewall`:

| Layer | Concern | Status | Artifact |
|---|---|---|---|
| **L3 — firewall allow-list** | The apply-time SSH provisioner reaches `web-1:22` only if the CI/operator egress IP ∈ `var.admin_ips` (`firewall.tf`; the CI-deploy SSH rule was removed in #749) | **NOT VERIFIED — must be checked before Phase 4's apply** | `server.tf` comment above `terraform_data.journald_persistent`; remedy `/soleur:admin-ip-refresh`, runbook `admin-ip-drift.md` |
| **L3 — DNS / routing** | `hcloud_server.web["web-1"].ipv4_address` resolves from state, not DNS | Not applicable — no name resolution in the provisioner path | `server.tf` connection block |
| **L4/L7 — TLS to the vendor** | CI → `s2457081.eu-fsn-3.betterstackdata.com` over HTTPS | **VERIFIED** — TCP+TLS completed and an application-layer body was returned this session | The 402 response body itself |
| **L7 — application (vendor)** | Ingest refuses writes | **VERIFIED — HTTP 402 `{"error":"Quota exceeded"}`** | Direct POST, both endpoints |
| **L7 — application (app)** | `ECONNREFUSED 10.0.1.40:8288` — the web app cannot reach the Inngest host | **VERIFIED as a symptom; cause owned by #7462** | ~4,576/day, flat across both surviving days |

**The one open gap is L3.** Before Phase 4's apply runs, confirm the egress IP is in `admin_ips`.
A handshake reset there is drift, and the checklist's ordering forbids proposing an sshd-layer or
service-layer remedy ahead of that check. Note the `ECONNREFUSED` in this incident is **not** a
firewall question — it is a service-down question already tracked by #7462 — so the L3-first rule
applies to the *apply path*, not to the diagnosis, which is closed by measurement.

## User-Brand Impact

**Rewritten after review.** The first draft enumerated by *surface* (registry channel, sub-processor
egress) — which is operator-shaped prose at aggregate-pattern altitude under a
`single-user incident` frontmatter. The threshold was right and the prose did not follow. Below is
the same section written by **user role**, which is what the threshold actually demands.

**If this lands broken, the user experiences** — one user, alone, absorbing a complete incident:

| Role | Artifact they own | What dark ingest does to them |
|---|---|---|
| **A billing-charged customer** | `users.subscription_status`, Stripe `customer_id` | `app/api/webhooks/stripe/route.ts` logs its safety branches at warn/error only — "Unknown Stripe subscription status — defaulting to 'cancelled'", "No user row for Stripe customer — skipping", "failed to update user on customer.subscription.updated". Since 2026-08-14 19:07Z a paying customer silently downgraded to `cancelled` leaves **zero queryable evidence** |
| **An Art. 17 erasure requester** | the deletion record | `server/account-delete.ts` logs a partial erasure's failure at error level into the dark channel. Retention is 3 days, so the proof that their rows were *not* erased is destroyed before anyone can look. This is a statutory-evidence deadline, not just a diagnosis one |
| **A BYOK key owner** | their own vendor spend | `server/byok-lease.ts` / `byok-cap-rpc.ts` log cap-breach and lease failure at warn/error. Uncapped spend on the user's own credential, with no record for either party |
| **An inbound emailer** | their message | `app/api/webhooks/resend-inbound/route.ts` logs six error/warn paths; a dropped email makes "it never arrived" unfalsifiable |
| **Any user of app.soleur.ai** | the running build | `.github/workflows/reusable-release.yml` is an absence-asserting consumer. Over a dark warehouse it can report **PASS and ship** — a fail-open release gate reaching real users |
| **The operator watching a release** | the registry pull path | The fleet's sole image-pull path is unobservable; a crash loop, filling disk, or upload failure produces no evidence |

**If this leaks, the user's data is exposed via** two paths, both created or touched here:

1. **Sub-processor egress.** The volume work touches emitters carrying request-derived content
   (`resolve-origin` logs a caller-supplied `Host`; the Inngest path can carry request context).
   Every change here must reduce or hold constant what is emitted, never widen it. #7529 records
   the Better Stack DPA as **unexecuted** — and a paid tier would extend retention of un-DPA'd
   user-derived content from 3 to 30 days *and* convert the hard 402 into a metered spill that
   ships more. **A paid-tier or retention change is therefore gated on #7529** (AC below).
2. **Public-repo egress — new, and created by this plan.** `jikig-ai/soleur` is `PUBLIC`
   (measured). Any committed dump of warehouse content is permanent, whereas Better Stack expires
   it in 3 days. Non-pino lines traverse only `pii_scrub_string`, the regex backstop — not the
   Art-9 key drop. **No verbatim log line may be committed**; counts, byte totals and hashed
   shapes only.

**Brand-survival threshold:** `single-user incident`

Correct and not to be relaxed: the first three rows each clear the bar with a single victim, no
pattern required. Consistent with ADR-184. Consequences: `requires_cpo_signoff: true`;
`user-impact-reviewer` at review time; plan-review runs the escalated panel.

**Correlated-vendor blast radius.** `cq-silent-fallback-must-mirror-to-sentry` makes Sentry the
designated second home for every silent fallback in the product. The operations advisory reports
Sentry's PAYG cap may bind in the same week (#3958 — at cap, monitors deactivate and check-ins drop
silently). Both layers dead at once, over a 3-day retention window, makes the gap unrecoverable
even after restoration. **Second-order, and the sharpest point in this review:** this plan's own
`## Observability` block detects "the guard itself stops running" via a *Sentry cron monitor* — so
at Sentry cap the new guard can stop running undetected. That is the identical fail-open shape this
plan exists to close, reproduced one level up, and it is why the guard needs a liveness detector
that survives a Sentry cap.

## Architecture Decision (ADR/C4)

Detection fires: this changes a cross-cutting trust/verdict boundary (what a detector is allowed to
resolve to silence) and records a substrate property (a shared telemetry source is a single
billing-domain failure point for every emitter).

### ADR

**ADR-191 — a shared log-ingest quota is a cross-emitter single point of failure.** Amends ADR-172
and ADR-184.

Decision content:

1. **I-1:** *every shipped emitter is bounded per unit time, independent of trigger frequency.*
   **Enforcement corrected at review — Guard 2 is the gate, not the Vector grep.** `model.c4` has
   **six** `-> betterstack` edges and only two traverse `vector.toml`: `zotRegistry` (:593, direct
   curl, ADR-184), `github` (:599, runner curl, ADR-172) and `gitDataStore` (:630, explicitly "NOT
   a Vector agent") bypass it entirely. Worse,
   `.github/workflows/validate-vector-config.yml:18-19` carries
   `paths: ["apps/web-platform/infra/vector.toml"]`, so the grep **does not run at all** unless
   that one file changes — structurally incapable of failing for the direct-POST emitter class.
   Guard 2 discovers producers *from the warehouse*, so it quantifies over all six substrates by
   construction. **Guard 2 is I-1's enforcement; the Vector grep is a supplementary check scoped
   to the Vector leg.** Stated this way so the ADR is not read in six months as "I-1 is gated"
   when five-sixths of it is prose. This generalises ADR-184's per-emitter cap — the one cap that
   **held** through this incident.
2. **I-2 (checklist, not grep):** *a detector must not read exclusively over the channel it
   monitors.* The zot alarm infers Better Stack's health from Better Stack. The fate-independent
   signal already exists and is unused: `[sinks.vector_console]` (`vector.toml:568`) ships
   `internal_metrics` to journald, and Vector's HTTP sink counts responses by status — **the
   shipper knew about every 402 in real time, and that counter went to a sink whose only reader
   was the dead channel.** Routing it to Sentry is the structurally correct detector. Named as
   target state and filed as a follow-up, not built here. Enforcement belongs as a checklist item
   in `observability-coverage-reviewer`.
3. **Source-splitting is explicitly REJECTED.** The 402 is account/plan-level, not source-level;
   splitting source 2457081 per emitter changes nothing about who gets dropped when the plan quota
   hits — every source dies together. Recorded so it is not re-proposed.
4. ADR-184's shipper is explicitly **not** implicated — it does not appear in the top-10 producers.

**Relationship to the 2026-06-10 near-miss.** This ADR does not restate that postmortem's open
action item ("no internal monitor watches quota"); it closes it, and cites it. The PIR for this
outage is a separate artifact — an ADR must not do double duty as an incident record.

Ordinal derivation, and a trap worth recording: a first sweep over **all** local refs reported
ADR-190 as highest, while a purely local `ls` reported ADR-186 — a 4-ordinal disagreement. Both
readings were wrong for the question being asked. Resolving it required scoping the sweep to
`refs/remotes/origin`, which confirms **ADR-190 is genuinely claimed on origin**, so **191 is the
next free**. The intermediate ordinals also appear on two local `refs/backup/*` refs, which are not
pushed branches and must not be mistaken for claims. **ADR-191 is provisional** and MUST be
re-derived against freshly-fetched origin refs immediately before merge — ADR-184 renumbered twice
(179→182→184) inside one review round. On renumber, sweep this plan, `specs/<branch>/tasks.md`, and
every AC naming the ordinal in the same edit.

### C4 views

All three model files were read for this enumeration, per the C4 completeness mandate — not
grepped for the feature's own noun.

Enumeration performed:

- **External human actors:** `founder` (already modeled, already receives pages from both
  `betterstack` and `sentry`). No new actor.
- **External systems / vendors:** `betterstack` (modeled, `model.c4:309`), `sentry` (modeled,
  `model.c4:316`). No new vendor.
- **Containers / data stores:** Logs source 2457081 (modeled inside the `betterstack` description
  and on four edges). No new store.
- **Access relationships:** no new edge. Two **existing** edges carry descriptions this change
  falsifies, and correcting them is the in-scope C4 work:
  - `betterstack` system description (`model.c4:309-311`) describes the shared source as receiving
    from every host and CI emitter but records no **quota ceiling**, so the model currently implies
    an unbounded sink. Add the ceiling and the cross-emitter shared-failure-domain consequence.
  - `github -> betterstack` (`model.c4:599`) states the edge "is no longer read-only" and that the
    POST is "measured, not assumed: 202 on ingest". That sentence is now falsifiable — the same
    POST returns 402 — so the edge must record that a non-2xx ingest status is a first-class
    alarm condition, which is what the new probe reads.

No new element means no `views.c4` `include` line is needed. Because the edits are
description-only, `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` must
still pass and are named in Acceptance Criteria.

### Sequencing

The ADR is authored in this PR describing the target state. Its status is `adopting` until the
soak in §Soak Follow-Through Enrollment reports a first PASS, at which point it flips to
`accepted` — the same shape ADR-184 used.

## Infrastructure (IaC)

This plan introduces no new server, volume, DNS record, TLS cert, firewall rule, or vendor
resource. No new Terraform root, so `hr-every-new-terraform-root-must-include-an` does not fire.

### Terraform changes

**Corrected during deepen-plan — the first draft of this section was wrong.** It claimed "no `.tf`
change, therefore nothing applies". `vector.toml` is a **Terraform-delivered artifact**:

```hcl
# apps/web-platform/infra/server.tf:982-991
resource "terraform_data" "journald_persistent" {
  # Also hashes vector.toml so an edit to the Vector config … re-fires this provisioner and
  # re-delivers + reloads Vector on the running web-1. web-1 installs Vector ONLY at cloud-init
  # boot and never re-runs cloud-init (ignore_changes=[user_data]), so without this fold a
  # vector.toml change is file-only, never live on the host …
  triggers_replace = sha256(join(",", [
    file("${path.module}/journald-soleur.conf"),
    file("${path.module}/vector.toml"),
  ]))
```

So Phase 4's `vector.toml` edit **does** reach the running host — and only because that fold
exists. Without it the change would be file-only, which is the #7539 shape ("vector.toml never
reached web-1") and the ADR-184 §7 "merging this applies nothing" trap.

No new Terraform resource is introduced. `hcloud_server.web` carries
`lifecycle { ignore_changes = [user_data] }`, so the host is **not** replaced and there is no
downtime — the provisioner re-delivers and reloads Vector in place.

### Apply path

**Corrected twice. Merging this PR delivers the volume fix to NO host.**

Two mechanisms exist and they are not interchangeable:

1. `terraform_data.journald_persistent` (`server.tf:982-991`) hashes `vector.toml` and re-delivers
   over an SSH provisioner — the Terraform-side mechanism.
2. **A dedicated gated `workflow_dispatch`**: `apply-web-platform-infra.yml` job `vector_redeliver`
   (`:5540`), fired with `apply_target=vector-redeliver` and the typo-guard
   `confirm=REDELIVER-VECTOR` (`:5598`), documented in
   `knowledge-base/engineering/operations/runbooks/vector-redeliver.md` and listed in the
   `apply_target` enum at `:267`. It was added by #7542/#7543, two commits before this branch.

`vector-redeliver` is the operative path: registry/web infra resources are `-target=`-scoped and
operator-gated, so **a merge applies nothing** — the ADR-184 §7 shape, and the reason #7539 records
"`vector.toml` never reached web-1". Phase 4's edit is committed-but-undelivered until the dispatch
fires. This is exactly the deliverable shape the issue anticipated: ship the code fix plus a gated
`workflow_dispatch`, then dispatch it.

**Scope limit, and it matters for invariant I-1:** `vector-redeliver` targets **web-1 only**. The
throttle therefore bounds only the hosts `vector.toml` actually lands on — a narrower set than the
producer table in §Research Insights F. The registry host runs the ADR-184 bash shipper and CI
direct-POSTs; neither is Vector-shipped, so I-1 must be scoped to "every **Vector-shipped**
emitter" with the non-Vector emitters named as an explicit residual.

Blast radius: a Vector config re-delivery and reload on web-1. No host replace, no serving
interruption — Vector is a log shipper, not a serving surface, so deepen-plan Phase 4.55's downtime
gate does not fire.

**The provisioner connects over SSH, and that is an apply-time dependency this plan must respect.**
`server.tf` declares `connection { type = "ssh", host = hcloud_server.web["web-1"].ipv4_address }`.
Per the comment immediately above it, SSH:22 is allowlisted to `var.admin_ips` only, so the apply
succeeds **iff the CI/operator egress IP is in `admin_ips`**. A `connection reset by peer` at apply
time is **admin-IP drift**, not an sshd fault — remedy is `/soleur:admin-ip-refresh` and the
`admin-ip-drift.md` runbook, per `hr-ssh-diagnosis-verify-firewall`. See §Network-Outage Deep-Dive.

This is an apply-time SSH dependency of the tooling, not an SSH diagnostic path into a host — it
does not conflict with `hr-no-ssh-fallback-in-runbooks`, which forbids reaching the **registry**
host for diagnosis. Nothing in this plan touches the registry host.

### Distinctness / drift safeguards

No state written, no secret added. `BETTERSTACK_LOGS_TOKEN` is read, never mutated. The new CI
probe reads it from the `soleur/prd` root via `secrets.DOPPLER_TOKEN_PRD`, which is the same
credential path `registry-zot-inventory.yml` already uses for its ingest POST — **not** the
registry host's isolated `soleur-registry/prd` copy. Naming the wrong config here would imply a
Doppler grant this needs none of (`model.c4:599` records this exact trap).

### Vendor-tier reality check

The account is demonstrably at a tier whose ingest allowance is below ~132k rows/day, and
`logs_retention: 3` is consistent with a low/free Logs tier. The plan does not encode a tier
assumption; the operations advisory in §Domain Review carries the costed recommendation, and the
restoration criterion is the measured HTTP status, not an assumed allowance.

## Observability

```yaml
liveness_signal:
  what: >
    INGEST_OK — the Better Stack Logs ingest endpoint returns 2xx for an authenticated
    probe POST. Emitted as a workflow output and a Sentry check-in by
    scheduled-zot-restart-loop.yml.
  cadence: every 30 minutes (the workflow's existing '*/30 * * * *' schedule)
  alert_target: >
    GitHub issue '[ci/betterstack-ingest-refused]' labelled action-required, plus the
    existing Sentry cron monitor check-in for scheduled-zot-restart-loop.
  configured_in: >
    .github/workflows/scheduled-zot-restart-loop.yml and
    apps/web-platform/infra/sentry/cron-monitors.tf

error_reporting:
  destination: >
    GitHub issue (action-required label, operator-visible per operator-digest, which
    harvests action-required ISSUES and not PR bodies) + Sentry cron monitor.
  fail_loud: >
    true. The redesigned verdict matrix has no arm that resolves an ingest non-2xx to
    silence. A probe that cannot reach the ingest endpoint at all is itself an alarm,
    not a shrug — see the fail-closed argument in the Guard Contract.

failure_modes:
  - mode: Account-wide ingest refusal (the #7569 incident — HTTP 402 quota exceeded)
    detection: >
      Ingest probe returns non-2xx while the ClickHouse reader answers. In-surface:
      the probe runs on the CI side of the ingest boundary, which is the only side that
      can observe a refusal — a host-side curl breadcrumbs only to unshipped journald.
    alert_route: "[ci/betterstack-ingest-refused] issue + Sentry check-in status=error"
  - mode: A single producer dies while ingest stays healthy
    detection: >
      Ingest probe 2xx, reader answers, zero rows for that producer's marker in the
      window but rows present in the 24h lookback.
    alert_route: "existing PRODUCER_SILENT arm -> [ci/zot-telemetry-silent] issue"
  - mode: The reader (ClickHouse creds/host) breaks while ingest is fine
    detection: >
      Reader returns a distinguishable error (not merely empty) AND the ingest probe
      returns 2xx. This is the only remaining TRANSIENT.
    alert_route: "Sentry check-in status=error; issue filed after N consecutive occurrences"
  - mode: Ingest volume climbs back toward the ceiling
    detection: >
      Daily row count per producer queried from the warehouse; a producer exceeding its
      declared ceiling is reported.
    alert_route: "[ci/betterstack-volume-ceiling] issue"
  - mode: The guard itself stops running or evaluates nothing
    detection: >
      Sentry cron monitor for scheduled-zot-restart-loop misses a check-in; plus the
      guard's own anti-vacuity floor (it must evaluate a non-zero number of producers).
    alert_route: "Sentry missed check-in -> issue"

logs:
  where: >
    Better Stack Logs source 2457081 (eu-fsn-3) for host/container streams; GitHub
    Actions run logs for the guard's own evaluation; Sentry for check-ins.
  retention: >
    3 days for Better Stack logs (measured: logs_retention: 3), 30 days for metrics.
    This is short enough that a 2-day-undetected outage nearly outlives its own evidence
    — recorded as a risk and a costed follow-up rather than changed here.

discoverability_test:
  command: >
    bash scripts/betterstack-ingest-probe.sh --check
  expected_output: >
    INGEST_OK status=202 endpoint=s2457081.eu-fsn-3.betterstackdata.com
  credentials_required: >
    BETTERSTACK_LOGS_TOKEN (ingest, write-only) from Doppler soleur/prd — there is no
    unauthenticated probe that verifies the same property, because ingest acceptance is
    by definition a property of an authenticated write. The token is write-only and
    cannot read log content, so the probe's credential grant is the minimum that
    verifies the invariant.
```

The `discoverability_test.command` first token is `bash`, which is on preflight Check 10's
`PROBE_VERB_ALLOWLIST`. The script is committed in the same PR. It contains no `ssh`.

### Affected-surface observability (Phase 2.9.2)

The registry host is a blind execution surface — cloud-init-only, no SSH, and its journald is the
very channel that failed. This incident is the proof: every shipper's `curl -fsS` failure
breadcrumbs to host journald only, so a 402 was **structurally unobservable off-box forever**. The
channel's own failure mode was invisible through the channel it failed on.

That is why the probe is placed on the **CI side** of the ingest boundary rather than the host
side. Its structured fields discriminate all competing hypotheses in one event:
`ingest_status` (HTTP code), `reader_status` (ok/error/empty), `rows_window`, `rows_lookback`,
`producer`. A single boolean would not separate refusal from producer death from reader fault —
the three-way ambiguity is precisely what made the old arm fail open.

## Soak Follow-Through Enrollment

Restoration is a time-gated criterion — ingest must be observed accepting, and stay accepting, for
long enough that the fix is not a momentary quota reset. Enrolled rather than left to memory.

- **Script:** `scripts/followthroughs/betterstack-ingest-7569.sh`
- **Exit contract:** `0 = PASS` (ingest 2xx AND rows present for every declared producer across the
  soak span AND daily volume below the declared ceiling); `1 = FAIL` (ingest non-2xx at any sample,
  or volume back above ceiling); `2 = TRANSIENT` (cannot establish — reader fault, insufficient
  span).
- **Tracker directive:** `<!-- soleur:followthrough script=scripts/followthroughs/betterstack-ingest-7569.sh earliest=<merge+7d> secrets=DOPPLER_TOKEN_PRD -->` plus the `follow-through` label.
- **Secrets to wire** into `.github/workflows/scheduled-followthrough-sweeper.yml`: none new —
  `DOPPLER_TOKEN_PRD` is already wired for sibling probes. Confirm at implementation rather than
  assume.
- **Enrolled on a dedicated tracker, never on #7569.** The sweeper lists `--state open`, and #7569
  is closed by this PR, so a probe enrolled there is a permanent silent no-op — the exact trap
  ADR-184 documents in its Alternatives table ("Enroll the probe on #7440 — it would have been a
  silent no-op").
- **Soak span:** 7 days, chosen so it strictly exceeds the 3-day retention window; a shorter soak
  could pass on evidence that has not yet had a chance to age out and be re-filled.
- ADR-191 flips `adopting → accepted` on the first PASS.

## Guard Contract

The deliverable includes guards, so each carries Property / Assembly / Mutation matrix. The
matrices below are derived from the **design**, before the guards exist — that ordering is the
point of this gate.

### Guard 1 — the ingest-refusal discriminator

**Property.** No absence evaluation resolves to a non-alarming verdict unless the reader is proven
healthy AND at least one row was read back through the sink in the same run. Reader-error,
channel-dark, and producer-silent are three distinct outcomes and none may be reported as a fourth
thing meaning "carry on".

This is deliberately the property `scripts/betterstack-assert-absence.sh` already states in its own
header (`clean` is the only exit 0, and is unreachable without a positive control read back through
the sink). The guard's job is to make the zot alarm obey the property its sibling already encodes.

**Assembly.** Every code path in `scripts/zot-restart-loop-alarm.sh` that can reach a
non-alarming exit from an emptiness or zero-evidence test.

**The first draft said "two sites, findable with `git grep -n 'control_rc'`". That was a snapshot,
and it was wrong — it finds 2 of 10.** Measured enumeration:

| Line | Arm |
|---|---|
| 149 | NIC transport rc |
| 185 | NIC control empty/errored |
| **213** | **NIC never-emitted AND sibling also silent — literally the total-account-outage shape, resolved TRANSIENT by delegating to "the zot legs below"** |
| 220 | NIC no usable boot_id |
| 367-369 | `betterstack-query.sh` not found/executable |
| 380-381 | zot transport rc |
| 389-390 | zot control empty/errored |
| 400-401 | zot fresh/never-installed host |
| 408-409 | zot no usable boot_id |
| ~433 | all-`-1` zero-evidence seam |

Line 213 must be named explicitly: its detail string delegates the verdict to a sibling arm this
plan is simultaneously rewriting, so the delegation becomes false the moment the zot leg changes
shape.

**The chokepoint is structural, and it is not the `control_rc` token:** every non-alarming exit
reachable from an emptiness test must route through `scripts/lib/betterstack-absence.sh`, and the
guard enumerates candidate sites by *shape* (an `if`/`elif` whose condition contains `-z "$V"`,
`-n "$V"`, `== ""`, or an `rc -ne 0` test in a block that also tests emptiness) rather than by
identifier. Anchoring on a rebindable identifier is the suppression-grep defect this repo has
already paid for once — hence mutation row 8.

**Scope must be resolved asymmetrically, because a blanket rule collides with the script's own
documented doctrine.** `zot-restart-loop-alarm.sh:52-57` states a deliberate FAIL-SAFE trade:
"NEVER FIRE on zero valid evidence… buys ZERO false-positives at the cost of a narrow non-OOM
false-negative", implemented at ~433. A blanket "no non-alarming exit" rule reds that seam and both
no-boot_id arms, and an implementer would resolve the collision by quietly narrowing the guard back
to two sites — making it vacuous. **The defensible line:** zero-evidence about *zot's internal
state* (boot_id, climb samples) may stay TRANSIENT; zero-evidence about *the channel itself*
(control empty, lookback empty, both producers dark) may not. The plan owns this split, with a
reason per arm, rather than leaving it to implementation.

**Anti-vacuity floor is two-level and pinned**, not "not zero": `files_scanned >= MIN_FILES` AND
`sites_found >= MIN_SITES` with both committed as constants (today `MIN_SITES` is the in-scope
subset of the ten above). A `>= 1` floor passes the exact "scoped to one of ten" defect.

**Placement is load-bearing and the first draft got it wrong.** Both absence arms live *inside*
`if [[ -z "$MAIN" ]]` (:384) / `if [[ -z "$trusted" ]]` (:178). When rows are present the script
falls through to the climb evaluation and `emit_and_exit 0` without ever consulting control,
lookback, freshness, or the probe — so T6 is unreachable by construction. **The ingest-status and
`max(dt)` freshness precondition must be hoisted ABOVE the `-z "$MAIN"` test and evaluated on every
path, including GREEN.**

**Mutation matrix** (each MUST drive the guard RED):

| # | Mutation | Expected |
|---|---|---|
| 1 | Reintroduce a bare non-alarming exit on an emptiness test, bypassing the shared classifier | RED — chokepoint assertion fails |
| 2 | Add a **second** absence-testing arm (a third producer) that resolves to a non-alarming verdict without the classifier, after a compliant first arm | RED — proves the check does not stop at the first member |
| 3 | Re-collapse `control_rc -ne 0` and `-z "$CONTROL"` into one branch inside the classifier | RED — behavioural assertion on the verdict, not merely on call shape |
| 4 | Cause the guard's own dispatch to evaluate zero arms (empty assembly) and exit 0 | RED — anti-vacuity floor; a guard reporting "0 checked" must not pass |
| 5 | Make an empty 24h lookback resolve to the "fresh / never-installed host" non-alarming arm | RED — this is the state the outage produces once the cliff ages out; it must fail closed |
| 6 | Let the ingest probe **downgrade** an alarming or dark verdict to a non-alarming one | RED — the fail-open direction; the probe has no veto |
| 6b | Make a measured non-2xx ingest status **unable to escalate** a GREEN reader-derived verdict to an alarm | RED — this is T6, the day-zero case |
| 7 | Remove the control query's exclusion of the probe's own marker, **or** fail to prove the probe body is empty-batch | RED — self-masking; assert the disjunction so neither branch is silently skipped |
| 8 | Rename `control_rc` to `ctl_rc` in one arm | RED — the assembly must not be anchored on a rebindable identifier |
| 9 | Make an emptiness-test block assign a verdict from a string literal instead of the classifier | RED — the decidable form of the chokepoint (see below) |

**Row 6/6b resolve a contradiction three reviewers caught independently.** The first draft's row 6
forbade the probe affecting the verdict at all, while T6 ("ingest 402 while rows are still
present") *requires* the probe to escalate a reader-derived GREEN. As written, T6 was unreachable
and the plan's headline outcome did not land. The veto is **directional**: never downgrade, always
free to escalate.

**"Non-alarming" is defined mechanically as "files no GitHub issue."** Without that, rows 3 and 5
are satisfiable by renaming `TRANSIENT` to `INGEST_UNKNOWN` with zero behaviour change.

**The literal property is not decidable in bash** — "reachable from" is a control-flow-path
property and there is no call graph. The writable conservative form, which is what the guard
actually asserts: *inside an emptiness-test block, a verdict may not be assigned from a string
literal, and no bare non-alarming `exit` may appear.* `VERDICT="TRANSIENT"` violates it;
`VERDICT="$(bs_absence_classify "$rc" "$out")"` complies. Pure syntax, exactly the defect,
unsatisfiable by a stub. Ship it with an honest-limits docstring (an emptiness test inside an
unscanned helper, or a verdict built with `printf -v`, is out of reach).

**Harness rows:**

| # | Edit to the SUITE | Expected |
|---|---|---|
| H1 | Delete the anti-vacuity floor assertion from the suite | RED — the suite must detect its own weakening |
| H2 | must-PASS, non-canonical: a compliant script with the two arms in **reversed order** and an extra compliant third arm | GREEN — the contract permits ordering and arity variation; only chokepoint bypass is forbidden |

### Guard 2 — per-emitter volume ceiling

**Property.** No emitter writes more than its declared **byte** budget per unit time to the shared
source, every emitter has a declared budget, and the sum of declared budgets stays under the
account allowance.

**Denominated in GB/month, never rows/day.** Better Stack bills bytes; a row-count ceiling is a
proxy that drifts the moment row width changes — and a 14-line stack trace is exactly that change.
The existing `scripts/followthroughs/betterstack-quota-verdict-5105.sh` 25k-rows/day gate carries
this defect today and is in scope to re-denominate. Measured conversion for this source:
**1,269 bytes/row**, so any row ceiling must be derived from the byte budget, not asserted
independently of it.

**Assembly.** The declared-budget manifest and the set of emitters discovered from the warehouse by
grouping the previous day's rows **with `sum(length(raw))`**. The structural chokepoint is that the
manifest is diffed against the **discovered** producer set, so a new emitter shipping without a
declared budget is a failure rather than an omission — this is what makes the assembly
self-maintaining rather than a snapshot.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add an emitter to the warehouse-discovered set with no manifest entry | RED — undeclared emitter |
| 2 | Raise one emitter's observed bytes above its declared budget | RED |
| 3 | Empty the manifest entirely so nothing is compared | RED — anti-vacuity: zero declared budgets must not pass |
| 4 | Add a **second** over-budget emitter after a compliant first | RED — quantifies over all, not the first |
| 5 | Hold every emitter's row count constant while tripling mean row size | RED — the byte-denomination assertion; a row-count guard would pass this and it is the exact drift that caused #7569 |
| 5b | Triple the row **count** while holding total bytes constant | **PASS** — the paired inverse. Without it, a guard computing `rows * 1269` (a row guard in a byte costume) passes row 5 and fails nothing |
| 6 | Set the summed declared budgets above the account allowance | RED — the budgets must be feasible, not merely present |
| 7 | **Empty the discovered set (the warehouse is dark) and let the guard PASS** | **RED — must be UNRESOLVED, never PASS** |

**Row 7 closes a fail-open that reproduces this plan's own I-2 inside its own new deliverable**, and
it was caught independently by two reviewers. Guard 2's assembly discovers producers by grouping
warehouse rows. When ingest is refused the warehouse returns zero rows, every producer is trivially
under budget, and Guard 2 reports GREEN throughout the exact incident it exists to prevent — a
detector reading exclusively over the channel it monitors. **Guard 2 must route through the same
`scripts/lib/betterstack-absence.sh` freshness precondition Phase 5 mandates for every other
consumer**; otherwise this plan creates consumer #64 and exempts it from its own sweep. Note this
state is live *today*, not hypothetical.

**Row 5 only discriminates over row-level fixtures.** If the stub returns a canned aggregate
(`{producer, bytes}`), tripling a field the guard already treats as bytes proves nothing about the
denominator. The stub must return row-level data with a row-length knob so `count()` and
`sum(length(raw))` give different answers over one fixture. Add an SUT mutation on the denominator
itself (`sum(length(raw))` → `count() * 1269`) and a calibration assertion reproducing the measured
136,556,248 bytes for 2026-08-14 within a tolerance band — the only test proving the guard's
denominator means what the invoice means.

**Harness rows:**

| # | Edit to the SUITE | Expected |
|---|---|---|
| H1 | Replace the discovered-set query with a hardcoded empty list | RED |
| H2 | must-PASS, non-canonical: a manifest with ceilings set well above current observed volume and one extra declared-but-currently-silent emitter | GREEN — headroom and idle emitters are permitted |

## Domain Review

**Domains relevant:** engineering, operations, finance, legal

Product is **not** relevant: the mechanical UI-surface override was evaluated against the Files to
Create/Edit list below and no path matches `components/**/*.tsx`, `app/**/page.tsx`, or
`app/**/layout.tsx`. `apps/web-platform/lib/auth/resolve-origin.ts` is an edge-runtime helper, not
a UI surface. Tier: **NONE**. No Product/UX gate, no wireframes required
(`wg-ui-feature-requires-pen-wireframe` does not fire).

### Engineering (CTO)

**Status:** reviewed (agent invoked; findings applied to this plan before writing).
**Assessment.** Five findings changed the design and are already folded in above:

1. **The write probe was the wrong primary discriminator.** Reader-200-over-an-empty-table is a
   complete, free, non-consuming signal, and `SELECT max(dt)` returns the cliff timestamp rather
   than a boolean. The probe is demoted to cause-annotation. Two structural objections: it expands
   a read-only alarm's secret set with a **write** credential in a public repo, and it **pollutes
   the signal it measures** unless the control query excludes its own marker.
2. **A mis-derived mechanism was about to be fixed.** The `set -uo pipefail` claim is false;
   measured exit codes prove the transport already discriminates. Cut.
3. **The taxonomy already exists** in `scripts/betterstack-assert-absence.sh`. Reuse, do not mint a
   third vocabulary.
4. **The real chokepoint is `vector.toml:83`'s `parse_err` arm**, which subsumes both volume
   offenders and protects against the next unknown loop. Per-emit-site edits are defense-in-depth.
5. **Blast radius is 63 consumers**, not the one channel — the largest gap in the first draft.

Rejected as scope creep, with reasoning recorded in the ADR: splitting source 2457081 per emitter.
The 402 is account-level, so every source dies together regardless of source count.

### Operations (COO)

**Status:** reviewed (agent invoked). Findings folded in.

**The upgrade is avoidable on capacity — recommend the code fix.** Post-cut ~32k rows/day is ~33%
of the free 3 GB allowance with 3–10× headroom, and `logs_retention: 3` / `metrics_retention: 30`
**is** the free tier exactly, not a chosen setting. Break-even sensitivity: rows would have to
average >3,054 bytes to bust 3 GB post-cut, ~2.4× the measured 1,269 B.

**But the free tier has no overage valve.** The documented 402 fails closed at 100%; paid plans
convert the wall into a metered spill with a self-set cap. The counterfactual is stark: this
outage's overage was ~0.27 GB, which on any paid plan would have billed **$0.027 and never gone
dark**. A paid tier buys a valve and 30-day retention, not capacity.

**Billing is per-BYTE, not per-row.** The in-repo 25k rows/day gate
(`scripts/followthroughs/betterstack-quota-verdict-5105.sh`) is a proxy that drifts the instant row
width changes — which is exactly what a 14-line stack trace does. **Guard 2's ceilings are
re-denominated to GB/month accordingly.**

**A preventive control for this exact class was already deferred.** **#5134 `vendor-quota-watch`**
was deferred on 2026-06-10 specifically to prevent it, with a stated cost of "$0 marginal, ~hours
on the existing `cron-*.ts` substrate". The class recurred and went past 100%. Re-prioritise,
re-denominated in GB/mo. This is the cheapest insurance available and it is already scoped.

**The dead host is the root cause and also costs money.** #7462's Inngest host bills **$22.21/mo**
across three `active` ledger rows while unreachable. Causal chain: **#7462 → 68.6k rows/day flood →
quota exhaustion → #7569 → #7556 blocked.** Sequence remediation that way; a vendor purchase treats
the symptom and leaves the dead asset billing.

**`resolve-origin` is a denial-of-observability vector, not noise.** Any unauthenticated third
party sending a bad `Host` header mints a billable row with no rate limit, and at quota that blinds
63 CI consumers. **This reclassifies the rate cap from tidy-up to a security control** — see the
amended Risks entry.

**Ledger:** `knowledge-base/operations/expenses.md`, line 44 (`Better Stack`, `0.00`,
`free-tier`), line 42 (`Better Stack Responder (DEFERRED)`, `29.00`). Two pre-existing defects to
correct regardless of lever: Responder is booked at the annual rate without saying so ($34
month-to-month), and line 44's thresholds are denominated in rows/day against a byte-billed meter.

`wg-record-recurring-vendor-expense-before-ready` **will fire** — the PR body will contain
"upgrade" whichever lever is chosen. Three valid exits: edit `expenses.md` in the same change;
`Tracks #NNNN` at an open `type/chore` issue carrying the `deferred-automation` sentinel; or a
`gate-override` comment with justification if the change stays free-tier. **Headless aborts on all
three — this needs an interactive ship run.**

### Finance (CFO)

**Status:** assessed via the operations advisory; not separately spawned.
**Assessment:** if a paid tier is chosen, `knowledge-base/finance/cost-model.md` needs a refresh —
$30/mo against Product COGS $238.51 is **+12.58%**, crossing the >10% category-subtotal trigger,
and **both break-even boundaries move** (COGS-scope 5→6 users, all-in 14→15). That is a CFO
decision, not an engineering one, and it is a real reason to prefer the free-tier route.

### Legal (CLO)

**Status:** assessed, not separately spawned.
**Assessment:** open issue **#7529** records the Better Stack vendor DPA as unexecuted. This plan
does not create a new processing activity and does not widen what is sent to the sub-processor — it
strictly **reduces** it. A tier change alters the commercial relationship with a sub-processor
whose DPA is outstanding, which is a pre-existing gap tracked on #7529 and is not resolved here.
Flagged as an interaction, not folded in.

## GDPR / Compliance Gate

Assessed per Phase 2.7 rather than skipped: `apps/web-platform/lib/auth/resolve-origin.ts` sits on
an auth-adjacent surface, which is inside the canonical trigger set.

Finding: the change is a **reduction** in what is logged and therefore transmitted to a
sub-processor. `resolve-origin` currently logs a caller-supplied `Host` header (already truncated
to 100 chars and control-char stripped at the existing call site); rate-limiting it reduces
transmission volume of request-derived data. This is favourable under Art. 5(1)(c) data
minimisation. No new personal data category, no new lawful-basis question, no Art. 30 register
entry required — the processing activity itself is unchanged.

Two items are carried rather than closed:
- **#7529** — Better Stack DPA unexecuted. Pre-existing, separately tracked, interacts with any
  tier change.
- The `pii_scrub_applied` field observed on shipped rows confirms VRL scrubbing is active on the
  Vector path; the CI-side probe posts a synthetic marker with no request-derived content and must
  be asserted PII-free by construction, matching the field allow-list discipline ADR-172 applies to
  `SOLEUR_ZOT_INVENTORY`.

Advisory only; not legal advice.

## Encryption Posture

The plan adds one new cross-component connection: the CI-side ingest probe.

```yaml
in_transit:
  - connection: GitHub Actions runner -> Better Stack Logs ingest (s2457081.eu-fsn-3.betterstackdata.com)
    tls: TLS 1.2+ via HTTPS; curl default verification
    cert_verification: on
    does_not_defend: >
      Does not defend against Better Stack-side compromise or against a malicious
      runner reading the write-only token from the environment. The token is
      write-only and cannot read log content, which bounds the blast radius of the
      second case to spurious ingest, not disclosure.
    disclosed_as: >
      Existing sub-processor transfer to Better Stack (EU/eu-fsn-3), already disclosed
      in the privacy policy and data-protection disclosure; this adds no new
      destination and no new data category.
```

`at_rest`: no new persistent store is introduced. No `exception` block is required — no
plaintext-exception and no `cert_verification: off` row.

## Implementation Phases

Phase order is dependency-directed, not file-grouped, and Phase 0 is time-critical.

### Phase 0 — Snapshot the evidence before it ages out (irreversible if skipped)

The surviving rows age out at approximately **2026-08-17 19:07Z**. Every other phase can be redone
next week; this one cannot.

0.1 **Dump the evidence to a committed file** under `knowledge-base/project/specs/<branch>/`:
    per-day counts, per-producer counts, the message-shape distribution, the hourly cliff, and the
    bytes/row measurement. This becomes the incident's primary record.
0.2 Re-probe the ingest endpoint; record the HTTP status and the time.
0.3 Re-derive the ADR ordinal — see the note in §Architecture Decision about backup refs.

### Phase 1 — Reuse the existing absence taxonomy (no new vocabulary)

1.1 Read `scripts/betterstack-assert-absence.sh` in full. Extract its four-outcome discriminator
    (`unknown` / `unshipping` / `present` / `clean`) into `scripts/lib/` **without changing its
    semantics**, and add the freshness helper: a `SELECT max(dt)` over the union with no `--grep`,
    which returns the cliff timestamp rather than a boolean and costs nothing.
1.2 RED: the Guard 1 mutation matrix.
1.3 GREEN: route **both** absence arms in `scripts/zot-restart-loop-alarm.sh` through the shared
    helper, splitting the `||` collapse at each. Do **not** modify `scripts/betterstack-query.sh` —
    its exit contract is already correct (measured).
1.4 **Fail closed when the lookback is empty.** Today a healthy reader over an entirely empty table
    routes to the "fresh / never-installed host" TRANSIENT arm. Once the cliff ages out, that is
    the state this outage produces — so the alarm would re-darken itself. A healthy reader over an
    empty table is never "can't tell".

### Phase 2 — Ingest probe as cause annotation only (no veto)

2.1 Before building: measure whether an **empty-batch POST** (`[]` and `{}`) returns 402 on a
    quota-exhausted account and 202 otherwise. If it does, the probe is free and non-polluting and
    both objections below vanish. Ten minutes, and it decides the design.
2.2 If a real POST is required, the probe writes a **distinctly-marked** row and the control query
    MUST exclude that marker — otherwise the probe's own rows mask the silence it exists to detect.
    Assert that coupling with a test; it is the subtlest failure mode in this plan.
2.3 The probe annotates cause (402→quota, 401→token, 2xx→producer dead, error→"cause
    undetermined"). It never overrides the reader-derived verdict, so a probe error cannot fail
    open.

### Phase 3 — Alarm wiring

3.1 File `[ci/betterstack-ingest-dark]` with `action-required`, reusing the existing
    `[ci/zot-telemetry-silent]` dedupe-by-title shape rather than a second scheme.
3.2 Extend the Sentry check-in mapping: a dark verdict is a successful *evaluation*.
3.3 **Verify, do not assume, that the Sentry path reaches a person.** It has been emitting errored
    check-ins for two days without effect. `failure_issue_threshold = 1` in
    `apps/web-platform/infra/sentry/cron-monitors.tf` covers a *missed* check-in; an *errored* one
    may not open an issue. If it does not, add an N-consecutive escalation in the alarm itself.

### Phase 4 — Volume reduction at the structural chokepoint

4.0 **L3 precondition (do this first).** Editing `vector.toml` re-fires
    `terraform_data.journald_persistent`, which reaches `web-1:22` over SSH. Confirm the CI/operator
    egress IP is in `var.admin_ips` before the apply. A `connection reset by peer` here is admin-IP
    drift — remedy `/soleur:admin-ip-refresh` — never an sshd or service-layer fault
    (`hr-ssh-diagnosis-verify-firewall`). See §Network-Outage Deep-Dive.

4.1 **Primary fix — `reduce`, NOT `filter` and NOT `throttle`.** Corrected at review; the first
    draft named elements that cannot do the job. The 14× amplification is a **fan-out** problem:
    one logical event billed as ~14 physical rows because a pretty-printed Node error crosses lines
    and journald ships one row per line.
    - A `type = "filter"` (`vector.toml:83`) is a boolean predicate **per event**. It cannot merge
      14 events into 1 and cannot bound per-unit-time. "Bound the arm" is not an operation a filter
      performs.
    - A `throttle` **discards** excess events, so on a 14-line trace it keeps an arbitrary 1–2
      interleaved lines and drops `[cause]:`, `code:`, `syscall:`. That is a *corrupted* trace —
      worse than keeping or dropping the whole event, and it contradicts this plan's own rule
      "collapse to one line plus an aggregate, never remove".
    - **`reduce`** (or multiline merge at the journald source) merges continuation lines into one
      event *before* the filter — preserving the full trace at ~1/14 the byte cost. This is the
      element the plan needs and it is what AC9/AC10 must target.
    Preserve the `parse_err` arm's purpose (§M): it is the documented #4773 decision and the only
    crash-stack path. This **amends** that decision, it does not correct an oversight. Add a
    fixture asserting an uncaught-exception stack (non-JSON, fd 2) still reaches the sink, and the
    inverse must-PASS that a structured `level=50` line still ships. `vector validate` exiting 0
    proves the config parses, never that the gate gates.
4.2 Add `throttle` as a **ceiling behind `reduce`**, not as the fan-out fix. Three constraints:
    - **Two throttles, or journald-leg only.** `[sinks.betterstack].inputs =
      ["tag_journald", "tag_metrics"]`; `tag_metrics` events carry neither container nor
      `SYSLOG_IDENTIFIER`, so a single identifier-keyed throttle collapses all 17,862 metric
      rows/day into one null-key bucket and guts the stream #5105/#5110 already tuned.
    - **Key on identifier AND pino level, with WARN+ separately bucketed or exempt.** A single
      container-wide bucket lets an unauthenticated scanner flood (via `resolve-origin`) starve the
      Stripe/auth ERROR lines for a real user in the same window — escalating an existing
      denial-of-observability into a *targeted* suppressor. Add a mutation row asserting a flood on
      one key cannot starve another.
    - **Drops must be observable.** Vector's throttle discards silently; the only record is
      `component_discarded_events_total` → `[sinks.vector_console]` → journald PRIORITY 6, which
      Source 2's `PRIORITY = ["0","1","2"]` filter drops. That is a *new* I-2 violation inside the
      I-1 fix. Mirror ADR-184's `SOLEUR_ZOT_LOG_DROPPED`: a bounded periodic drop-accounting row
      through the sink, with an AC (`cq-silent-fallback-must-mirror-to-sentry`).
4.3 **Defense-in-depth only** (explicitly not the fix): per-emit-site changes. Note that
    edge-runtime rate limiting in `resolve-origin.ts` would not work as intended anyway — counters
    are per-isolate and ephemeral — and the Inngest emit-site change becomes dead code once
    **#7462** restores the host. Re-size this step after #7462 lands; it may reduce to nothing.
4.4 Declare each emitter's ceiling in the Guard 2 manifest.

### Phase 5 — Blast-radius sweep (the largest gap)

5.1 Classify all 63 `betterstack-query.sh` consumers as **presence-assert** (fail-closed, safe when
    the warehouse is dark) or **absence-assert** (fail-open — silently green for two days).
5.2 Route every absence-assert through the shared freshness precondition so it returns
    **unresolved, not passed**. Start with `.github/workflows/inngest-config-drift.yml` and
    `.github/workflows/reusable-release.yml`.
5.3 If this sweep proves larger than one PR, scope the remainder to a tracked follow-up with the
    classification table committed — but the classification itself lands here.

### Phase 6 — ADR, PIR, C4

6.1 Write the ADR (`status: adopting`) recording both invariants and explicitly **rejecting**
    source-splitting, with the account-level-quota reasoning.
6.2 File a **PIR** for the outage itself via `soleur:incident`, and reopen/cite the near-miss
    postmortem's unclosed 5-Why #5 action item rather than restating it in a new ADR.
6.3 Apply the two `model.c4` description corrections; run the C4 syntax and render tests.
6.4 Enroll the soak follow-through on a dedicated tracker.

### Phase 7 — Restoration

7.1 The volume cut brings steady-state to ~1.48 GB/month against a 3 GB allowance.
7.2 The current period's already-consumed allowance is addressed per the operations advisory. This
    is the one step no in-repo change can perform: it sits behind a payment instrument at the
    vendor, a named human gate.
7.3 Restoration is asserted by a 2xx from the ingest endpoint — never by reading a dashboard
    figure (`hr-no-dashboard-eyeball-pull-data-yourself`). No usage API exists (measured 404 on
    three candidate endpoints), so the invariant is the only honest signal.
7.4 **Free acceptance evidence:** production is currently a perfect live fixture. Assert that the
    new matrix returns a dark verdict against prod *today*, and flips to GREEN after restoration.
    A cleaner proof will not be available again.

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/lib/betterstack-absence.sh` | The four-outcome discriminator **extracted from the existing `scripts/betterstack-assert-absence.sh`**, plus the `max(dt)` freshness helper. Not a new vocabulary |
| `scripts/betterstack-ingest-probe.sh` | Cause annotation only; also the `discoverability_test` command |
| `scripts/followthroughs/betterstack-ingest-7569.sh` | Soak probe for the restoration criterion |
| `knowledge-base/engineering/architecture/decisions/ADR-191-shared-log-ingest-quota-is-a-cross-emitter-spof.md` | ADR (ordinal provisional) |
| `knowledge-base/engineering/operations/post-mortems/2026-08-16-betterstack-ingest-quota-exhaustion-postmortem.md` | PIR via `soleur:incident` |
| `knowledge-base/project/specs/<branch>/evidence-snapshot.md` | Phase 0.1 — the measurements, committed before they age out |
| `tests/scripts/test-betterstack-absence-classifier.sh` | Guard 1 mutation matrix + harness rows |
| `tests/scripts/test-betterstack-ingest-probe.sh` | Probe classification tests |
| `scripts/betterstack-emitter-ceilings.json` | Per-emitter declared volume ceilings (Guard 2 manifest) |

Test paths are provisional: the implementer MUST confirm the runner's discovery globs before
placing them (`package.json` `scripts.test`, and note `bunfig.toml` `pathIgnorePatterns` and
`vitest.config.ts` `include:` for the web-platform package). Do not assume `bun test`.

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/infra/vector.toml` | **The primary volume fix.** Bound the `parse_err != null → true` arm at line 83; add a `throttle` transform ahead of `[sinks.betterstack]` (line 543) |
| `scripts/zot-restart-loop-alarm.sh` | Route **both** absence arms through the shared helper, splitting the `||` collapse at each; fail closed on an empty lookback; anti-vacuity floor |
| `scripts/betterstack-assert-absence.sh` | Consume the extracted `scripts/lib/` helper so there is one implementation, not two |
| `.github/workflows/scheduled-zot-restart-loop.yml` | Run the probe as annotation; file `[ci/betterstack-ingest-dark]`; extend the Sentry status mapping (existing blocks at 215-247, 448) |
| `.github/workflows/inngest-config-drift.yml`, `.github/workflows/reusable-release.yml` | First two absence-assert consumers to route through the freshness precondition (Phase 5) |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Correct the `betterstack` system description and the `github -> betterstack` edge |
| `.github/workflows/scheduled-followthrough-sweeper.yml` | Confirm `DOPPLER_TOKEN_PRD` is wired; add only if genuinely absent |
| `apps/web-platform/lib/auth/resolve-origin.ts` | **Defense-in-depth only** — subsumed by the vector.toml fix. Note edge-runtime counters are per-isolate and ephemeral, so a rate limit here does not behave as intended; prefer no change |
| `apps/web-platform/server/inngest/client.ts` / `app/api/inngest/route.ts` | **Defense-in-depth only** — becomes dead code when #7462 lands. Locate the real emit site by grep before editing; the stack frames point at built output (`.next/server/...`) and the SDK may be the emitter |

`scripts/betterstack-query.sh` is deliberately **absent** from this list — its exit contract was
measured correct. Every path above was verified to exist with `ls`/`git ls-files` at plan time,
except the Inngest emit site, which is flagged as requiring a source grep rather than asserted.

## Open Code-Review Overlap

Checked with `gh issue list --label code-review --state open --limit 200` piped through standalone
`jq --arg` (two-stage, per `2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`) against every path in
Files to Edit.

**None.** No open code-review issue names any file this plan touches.

Adjacent open issues that are **not** code-review overlaps but bear on this work:

- **#5134 — `vendor-quota-watch`, deferred 2026-06-10 to prevent this exact incident class.** Its
  stated cost was "$0 marginal, ~hours on the existing `cron-*.ts` substrate", and its
  re-evaluation criterion has been satisfied the whole time. The class then recurred and went past
  100% to a hard 402. Disposition: **fold in the re-prioritisation** — re-denominated in GB/mo, not
  rows/day. This is the cheapest control available and declining it twice is not defensible.
  `wg-defer-only-after-inline-triage` applies.
- **#7462** — the unreachable Inngest host that is the *source* of the 64% log loop, and $22.21/mo
  of billed idle asset. Causal chain: **#7462 → flood → quota → #7569 → #7556 blocked.** This plan
  does not fix that host; it stops the loop from consuming the observability budget. Disposition:
  **acknowledge and escalate** — cross-reference both ways and note that fixing it removes 64% of
  the flood at negative cost.
- **#3958** — the Sentry PAYG cap behaviour (at cap, all monitors deactivate silently). Directly
  bears on whether this guard has a working backstop. Disposition: **acknowledge**; re-verify the
  cap state during implementation.
- **#7529** — Better Stack DPA unexecuted. Disposition: **acknowledge**, interacts with a tier
  change.
- **#7539** — a red apply on the `[ack-destroy]` guard, noting `vector.toml` never reached web-1.
  Disposition: **acknowledge**; relevant to which hosts ship via Vector but not blocking.
- **#7556 / #7555** — unblocked by restoration, not by code here. Disposition: **acknowledge**,
  comment on restoration.

## Acceptance Criteria

### Pre-merge (PR)

1. The Phase 0 evidence snapshot is committed, and it was captured **before 2026-08-17 19:07Z** or
   carries an explicit note that the window had already closed.
2. `scripts/betterstack-query.sh` is **unmodified** — the PR body records the measured exit codes
   (22 / 6 / 0 / 3) that make a change unnecessary, correcting #7569's premise.
3. All 63 `betterstack-query.sh` consumers are classified presence-assert vs absence-assert, with
   the table committed; every absence-assert either routes through the freshness precondition or
   is listed with a dated follow-up.
4. `scripts/zot-restart-loop-alarm.sh` has no non-alarming exit reachable from an emptiness test
   outside the shared `scripts/lib/betterstack-absence.sh` classifier, asserted mechanically.
5. **Both** absence arms (zot and private-NIC, `git grep -n 'control_rc'`) route through it, and
   `scripts/betterstack-assert-absence.sh` consumes the same extracted helper — one implementation,
   not two.
6. All seven Guard 1 mutation rows drive the suite RED; both harness rows behave as specified
   (H1 RED, H2 GREEN). Evidence pasted in the PR body.
6a. `apps/web-platform/infra/vector.toml` bounds the `parse_err != null` arm; `vector validate`
   exits 0 on the pinned 0.43.1 and the PII parity suite passes 26/26.
6b. A `throttle` transform sits ahead of `[sinks.betterstack]`, and a CI grep asserts the sink
   reads only from throttled transforms (invariant I-1).
6c. The empty-batch POST experiment (Phase 2.1) is run and its result recorded, so the probe design
   is chosen on measurement rather than assumption.
6d. If the ingest probe writes a row, the control query provably excludes the probe's own marker,
   asserted by a test (the self-masking guard).
7. All four Guard 2 mutation rows drive RED; both harness rows behave as specified.
8. The anti-vacuity floor fails when the guard evaluates zero arms.
9. `apps/web-platform/lib/auth/resolve-origin.ts` no longer emits one line per rejected origin, and
   still imports no `@/server/logger` (edge-runtime constraint preserved) — asserted by test.
10. The Inngest connection-failure path emits at most one row per occurrence; a test asserts the
    single-line shape. The signal is **not** removed — a counter or aggregate remains.
11. `scripts/betterstack-emitter-ceilings.json` declares a ceiling for every producer observed in
    the discovery query; an undeclared producer fails the guard.
12. ADR-191 exists with `status: adopting`, and its ordinal is re-derived against freshly-fetched
    `origin/*` refs immediately before merge. If renumbered, `grep -rn 'ADR-191'` over
    `knowledge-base/project/{plans,specs}/` shows zero stale references.
13. `model.c4` carries both description corrections; `apps/web-platform/test/c4-code-syntax.test.ts`
    and `c4-render.test.ts` pass.
14. The soak follow-through script exists and its tracker directive is present on a **dedicated**
    tracker issue, not on #7569.
15. `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0 over the
    full changed set — run the gate's own invocation, not a hand-enumerated path list
    (`cq-assert-anchor-not-bare-token`, and the #7003 input-scope learning).
16. `python3 scripts/lint-guard-contract.py` passes over this plan.
17. Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (never `npm run -w`).
18. If a vendor tier change is chosen, the recurring expense is recorded in the ledger before the
    PR is marked ready (`wg-record-recurring-vendor-expense-before-ready`).
19. The PR body reframes the premise: this is an account-wide ingest refusal, not a registry
    channel fault, and ADR-184's shipper is explicitly exonerated. Uses `Closes #7569`.

### Post-merge

20. The ingest probe reports 2xx.
21. Rows resume for every declared producer, confirmed by a per-producer query.
22. Measured daily volume is below the aggregate declared ceiling.
23. #7556's soak probe returns a verdict other than `TRANSIENT reason=no-config-line`.
24. The soak follow-through reaches PASS; ADR-191 flips `adopting → accepted`.
25. #7569 closed; unblock commented on #7556 and #7555; cross-reference added to #7462.

Note on ordering: #7569 is closed by this PR via `Closes`, and criteria 20-25 complete afterwards.
That is acceptable here because the PR genuinely delivers the guard and the volume cut — the
remaining vendor step is tracked by the soak follow-through on its own dedicated tracker, which is
what keeps the loop closed. Criterion 25's close is the confirmatory one.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The evidence expires mid-implementation** (last row ages out ~2026-08-17 19:07Z) | Phase 0.2 makes this explicit. The tables in this plan are the historical record; do not re-measure zeros and report agreement. This is the single most likely way the implementation misreads its own situation |
| The volume cut alone does not restore ingest because the allowance is already consumed for the period | Expected. The plan separates restoration (vendor) from recurrence-prevention (code) and does not claim code restores ingest |
| Adding `set -e` to `betterstack-query.sh` breaks silent consumers | Phase 1.2 requires a consumer sweep first; the fix is a distinguishable exit, not a blanket `-e` |
| The ingest probe's own row consumption contributes to the quota | 48 rows/day against a ~132k/day baseline. Quantified, negligible, and the probe is the thing that detects the ceiling |
| Silencing the Inngest loop darks a real signal about #7462 | Explicitly forbidden — collapse to one line plus an aggregate, never remove. AC10 asserts the signal survives |
| The new `INGEST_REFUSED` issue floods on a long outage | Reuse the existing dedupe-by-title pattern from the `[ci/zot-telemetry-silent]` block rather than inventing a second scheme |
| The Sentry cron monitor was already erroring for two days and nobody saw it | Do **not** assume the Sentry path works. Verify the monitor's alert routing actually reaches a person before relying on it as the backstop; if it does not, that is a finding, not an assumption |
| **The Sentry backstop may fail in the same week.** The operations advisory reports the Sentry PAYG on-demand period ending **2026-08-16** with $42.22 of $50 drawn; at cap, per #3958, every monitor deactivates at once and check-ins are silently dropped | **Two nominally independent vendors, two independent quota mechanisms, both fail-closed, both silent, both binding inside 48 hours.** Re-verify the Sentry cap state before designating Sentry as the escalation path for this guard. If it is at cap, the guard has no working backstop and the GitHub-issue path is the only live one. This risk alone justifies filing the issue rather than relying on a check-in |
| A tier change re-provisions the source or moves the region | **Hazard, not a nicety.** 63 files read source 2457081, and it is cluster-pinned (eu-fsn-3 → 202; eu-nbg-2 → 401). A relocation is simultaneously mass CI breakage and an Art. 30 residency amendment. Capture source id, `table_name`, and region before and after any plan change |
| The volume cut lands but the row-count ceiling drifts as row width changes | Guard 2 is denominated in bytes, and mutation row 5 asserts exactly this |
| ADR-191 collides | Provisional; re-derive against origin refs immediately before merge and sweep planning artifacts on renumber |

## Alternatives Considered

| Alternative | Verdict | Reason |
|---|---|---|
| Build a new telemetry-freshness watcher | **Rejected** | A detector already exists and already computes freshness. Adding a second leaves the first fail-open. Fix the chokepoint |
| Treat this as a registry-host fault, per the issue's four candidates | **Rejected** | All four refuted by measurement. Acting on them would have cost a destructive replace of the sole pull path — the #6536 failure mode exactly |
| Split the shared Logs source into per-emitter sources | **Deferred** | Would isolate blast radius, but does not address an account-level allowance, which is shared regardless of source count. Referred to the engineering advisory; file as follow-up if endorsed |
| Raise log retention above 3 days now | **Deferred** | Does not restore ingest and would confound the soak signal. Costed as a follow-up |
| Silence the Inngest error entirely | **Rejected** | Darks a live signal about the open #7462. Collapse, do not remove |
| Read the vendor usage figure from the dashboard to find the reset date | **Rejected** | `hr-no-dashboard-eyeball-pull-data-yourself`. No API exists (measured). Assert the invariant — ingest returns 2xx — instead of a proxy number |
| Fix the Inngest host as part of this PR | **Rejected, out of scope** | #7462 owns it and it needs a provisioning event. This plan stops the loop from consuming the observability budget, which is the part that belongs here |

## Test Scenarios

Beyond the mutation matrices, which are the primary gate:

| # | Scenario | Expected |
|---|---|---|
| T1 | Ingest 402, reader answers, zero rows | `INGEST_REFUSED`, issue filed |
| T2 | Ingest 2xx, reader answers, zero rows in window, rows in 24h lookback | `PRODUCER_SILENT`, issue filed |
| T3 | Ingest 2xx, reader answers, rows present | `GREEN` |
| T4 | Ingest 2xx, reader returns a distinguishable error | `TRANSIENT`, no issue, Sentry error check-in |
| T5 | Ingest probe unreachable, reader answers, zero rows | Fail-closed to an alarm — see the CTO advisory on this arm before finalising |
| T6 | Ingest 402 while rows are still present in the window (early in an outage) | Alarm — refusal is not masked by not-yet-expired rows. This is the case that would have caught #7569 on day zero |
| T7 | A producer with no declared ceiling appears | Guard 2 RED |
| T8 | `resolve-origin` receives 1,000 rejected origins in a minute | At most the rate-limited count of rows; counter reflects 1,000 |

T6 is the scenario that matters most: it is the one that converts this class of outage from
two days undetected to one 30-minute cycle.

## BLOCKING — the warehouse is an unauthenticated write surface, and the canonical classifier trusts it

Security review found, and this session verified directly, that **this is not only a billing
problem — it is an integrity problem**, and the plan's central move (promote
`scripts/betterstack-assert-absence.sh` to the shared classifier for all consumers) multiplies the
blast radius of an existing forgery hole. These are blocking: resolve them before implementation
starts, not during.

### F14 (HIGH) — the canonical classifier's only exit-0 is attacker-forgeable

Verified at `scripts/betterstack-assert-absence.sh`:

- `:67` — `CONTROL_MARKER="SOLEUR_PROBE_CANARY"`
- `:209` — `control_rows="$(run_count "raw LIKE '%$(sql_lit "$CONTROL_MARKER")%'")"`
- `:170` — the only structured clause is `JSONExtractString(raw,'host_name') = '${HOST_LIT}'`

`outcome=clean` — **the only exit 0**, and the very property Guard 1 is built to protect ("at least
one row was read back through the sink") — is unlocked by *any* row on that host whose text
contains the marker. The predicate is an unanchored `%…%` substring. `host_name` is Vector-injected
and not attacker-settable, but it pins the **host, not the producer** — and the web container runs
on that host. There is no `source_kind`, no `SYSLOG_IDENTIFIER`, no `CONTAINER_NAME`, no anchor.

**The only thing standing between an unauthenticated HTTP `Host` header and a forged "the channel
is alive" is that ClickHouse `LIKE` is byte-case-sensitive while `resolve-origin.ts:17` calls
`.toLowerCase()`.** That call exists for origin comparison. It is not a log-safety control, it is
not documented as one, and nothing tests it. This plan would make it load-bearing for the repo's
canonical absence classifier across every consumer in the Phase 5 sweep.

**Required before extraction:** pin the control predicate on **producer identity**, not just host.
The strong form already exists in-repo — the envelope anchor at `zot-restart-loop-alarm.sh:176`
and the prefix-anchored decoded form in `zot-inventory-assert-marker.sh`. Add a Guard 1 mutation
row: *a web-container journald row containing the control marker as literal text must NOT satisfy
the positive control.* Either document and test the case-fold dependency at `resolve-origin.ts:17`,
or stop depending on it.

### F15 (HIGH) — an anchor asymmetry that lets an attacker SUPPRESS the alarm

Same file, two legs, verified:

- **NIC leg, `:176`** — `grep -F '"raw":"{\"message\":\"SOLEUR_PRIVATE_NIC '`. Envelope-anchored;
  a Vector-shipped journald row's `raw` starts `{"PRIORITY":"6",…` and structurally cannot match.
  The comment records the live 2026-07-15 incident where three GitHub-webhook rows quoting the
  marker were returned.
- **ZOT leg, `:403`** — straight into `zot_trusted_region` with **no envelope anchor at all**.

A forged `SOLEUR_ZOT_DISK` row therefore parses as genuine telemetry — and the second consequence
is the one that belongs in this plan: it makes `$MAIN` non-empty, which **skips the entire
`if [[ -z "$MAIN" ]]` block containing the `PRODUCER_SILENT` branch**. An unauthenticated third
party can mask genuine registry-telemetry darkness. That is precisely the failure this plan exists
to close, and none of Guard 1's mutation rows cover it.

**Whichever anchor the extracted classifier adopts becomes the repo-wide contract — adopt the NIC
leg's.** Add the alarm-suppression mutation row.

### F16 (MEDIUM) — AC2's wording outruns its measurement

`scripts/betterstack-query.sh:189` escapes single quotes but **not backslashes**; its sibling
`betterstack-assert-absence.sh:136` does both, in the correct order. Latent, not live — every
current `--grep` term is a repo-controlled literal. But AC2 declares the file *unmodified* and
records exit codes "that make a change unnecessary", which reads as a general audit pass the
measurement did not earn. **Either fix the escaping here or narrow AC2 to the exit contract only.**
Also unescaped: `_` is a ClickHouse `LIKE` wildcard, so `--grep SOLEUR_ZOT_DISK` really matches
`SOLEUR?ZOT?DISK` — widening rather than forgery-enabling, but it belongs in the Phase 5 table.

### F18 (MEDIUM) — forgery preferentially wins

`betterstack-query.sh:215-226` orders `dt DESC LIMIT ${LIMIT}` inside the subquery, so **a freshly
injected row is the newest and always survives the limit**. Every consumer using `--limit 1` +
`tail -1` reads the attacker's row preferentially — including `zot-restart-loop-alarm.sh:206`,
`:393` and `inngest-config-drift.yml:63`. Separately, the one consumer that *does* pin a producer
field pins the wrong one: `cert-reissue-markers-6698.sh:52` requires
`"source_kind":"app_container"`, which `vector.toml:487` sets for the web container — making its
producer isolation **anti-protective** against this vector.

### The through-line, and it belongs in the ADR

F14, F15, F17 and F18 all trace to one root: **an unauthenticated party can write attacker-chosen
text into a shared telemetry source that 63+ consumers read with unanchored substring matches.**
The ADR must say so, and must record the invariant: *no marker predicate may be satisfiable by a
row an attacker can influence.* `resolve-origin` is not a noisy emitter — it is an unauthenticated
write path into the evidence store, which is also why its rate cap is a control rather than
housekeeping.

**Two further blocking items from the same review:** the plan's "no secret added" claim is false —
the alarm workflow holds no Doppler token today, so provision `BETTERSTACK_LOGS_TOKEN` directly
rather than granting prd-wide read; and the empty-batch POST experiment should be promoted from a
Phase 2.1 nicety to a **blocking gate**, because a non-writing probe dissolves the self-masking
hazard, the credential expansion, and the probe's share of F14 at once.

## Deepen-Plan Review Findings

Six reviewers ran against this plan (observability-coverage, architecture-strategist,
code-simplicity, test-design, user-impact, security-sentinel). The P0s and the corrections already
folded into the sections above are not repeated here. This table records the remainder with an
explicit disposition so `/work` inherits them rather than rediscovering them.

**Three reviewers independently found the same contradiction** (Guard 1 row 6 vs T6) and **two
independently found the same fail-open** (Guard 2 over a dark warehouse). Convergence of that kind
is the strongest signal in this table.

| # | Finding | Disposition |
|---|---|---|
| R1 | `[ci/betterstack-ingest-refused]` (Observability block) vs `[ci/betterstack-ingest-dark]` (Phase 3, Files to Edit) — **two titles for one alarm in a dedupe-by-title scheme**. Every filing step here dedupes on `in:title "<exact string>"` | **Fix inline at /work.** Pick `[ci/betterstack-ingest-dark]`, use it verbatim in all four places (block, phase, filing step, close step), add to ACs |
| R2 | `discoverability_test` asserts `status=202`, which is measured-**false** today and stays false until a human pays a bill. Preflight Check 10 *executes* it, so it FAILs — or gets weakened to pass. It also lacks a `doppler run` wrapper, and the property the PR delivers is verifiable offline with no credentials | **Replace.** Use `bash tests/scripts/test-betterstack-absence-classifier.sh --case ingest-402-reader-ok`, expecting the alarming verdict. Zero network, zero credentials, passes today, asserts the invariant not the vendor's billing state. Move the live 202 assertion to the soak follow-through, which is already time-gated for it |
| R3 | Observability layer cited as **5**; layer 5 is Sentry `release` context | **Fix.** Layer **3** for the journald→Better Stack producer path; layer **6** for the guard's own operator-visible signal (workflow-run log, `::error::`, filed issue). `failure_modes` 2 and 4 cite no layer at all |
| R4 | `failure_modes` entry 4 (`[ci/betterstack-volume-ceiling]`) has **no owning phase and no file** — it reads as though the route exists | **Rewrite** to say the route is a tracked follow-up on #5134 with no live detection today, or build it. Overstating coverage on the exact axis that caused the incident is the worst place to do it |
| R5 | The ADR claims to **close** the near-miss's 5-Why #5, but no phase builds `vendor-quota-watch` and Guard 2 cannot substitute (it reads the warehouse, dark at exactly quota) | **Reword** to "supersedes #5134's mechanism and leaves it open with a re-scoped body", or build the watch. Claiming a closure the PR does not deliver is the near-miss's own defect repeated |
| R6 | `betterstack-quota-near-miss-postmortem.md` is **not in Files to Edit** — no back-link from the prediction to the recurrence | **Add** a `RECURRED 2026-08-14 → <PIR path>, ADR-191` line. §K's argument depends on that file being reachable *from* the recurrence |
| R7 | **Live AP-021 violation nobody reported.** The shipped alarm string "Better Stack unreachable / creds unset" names two causes the job measured **false** (it had `rc=0`). AP-021 (ADR-166, hook-tier, `scripts/lint-diagnosis-claims.sh`) forbids exactly this, and the gate did not catch it — for two days, every 30 minutes | **Elevate.** Add an AC running `lint-diagnosis-claims.sh` against `scripts/zot-restart-loop-alarm.sh`. If it passes today on that string, **the gate gap is the real deliverable**. Also mint AP-023/AP-024 rows for I-1/I-2 in `principles-register.md`, which the plan currently never touches |
| R8 | Source-splitting rejection is **inference labelled as measurement**: both probes used the *same* source token, which cannot discriminate account-level from source-level | **Soften** to unfalsified inference, or measure with a second source's token. The clause currently reads "Recorded so it is not re-proposed" — permanently foreclosing an option on an unmeasured premise, in a plan that boasts no hypothesis rests on reasoning alone |
| R9 | **Metrics-off-the-Logs-quota alternative never evaluated.** 17,862 rows/day of `host_metrics` bill against the *Logs* quota only because Vector's native metrics sink does not exist. The near-miss's 5-Why #3 says exactly this | **Add to Alternatives Considered** with a verdict, even if deferred. Second-largest producer, pure structural waste, already identified once |
| R10 | I-2's named target state routes to **Sentry**, which this plan's own Risks table says may be at PAYG cap this week | **Reword** target state to "a channel independent of the monitored vendor", naming the GitHub-issue path as the one in force. Build the N-consecutive escalation as a Phase 3 deliverable with an AC — and define **where the counter lives**, since a GHA bash script is stateless between runs (issue-comment count, committed marker, or the Sentry monitor's own consecutive-failure setting). It is currently unimplementable as written |
| R11 | Two C4 edits leave the four highest-volume emitter edges (`model.c4:524, 525, 593, 630`) implying independence | **Add one sentence to each of the six edges** naming `betterstack-emitter-ceilings.json` as the authority plus the shared-failure-domain consequence. Keep the numbers in the manifest only — `vector.toml:126-129` already documents two comments in one file drifting apart on a rows/day figure |
| R12 | **Stub-ladder aliasing.** `zot-restart-loop-alarm.test.sh:38` branches on `$*` substrings and its comment says "ORDER IS LOAD-BEARING". The new `max(dt)` read carries no `--grep`, so it lands in the branch serving the control probe — every freshness fixture would silently read the control fixture | **Give the freshness helper a distinguishable argv** (`--max-dt`) *before* the stub is written |
| R13 | **Two seams for one override**: `ZOT_BQ_OVERRIDE` (`zot-restart-loop-alarm.sh:70`) and `BETTERSTACK_QUERY_SCRIPT` (`betterstack-assert-absence.sh:64`) | **Unify in Phase 1.1**, keeping `ZOT_BQ_OVERRIDE` as a deprecated alias — otherwise the shared classifier has two override paths and a test can stub one while the other reaches the network |
| R14 | No **staleness threshold** is declared for the `max(dt)` freshness helper — AC4 asserts it is enforced mechanically and there is nothing to enforce against | **Declare the number** and derive it from `WINDOW` |
| R15 | **`max(dt)` and byte sums are measured/wall-clock quantities.** No tolerance discipline is specified | **Never assert equality.** Inject `now` via a `BS_NOW_EPOCH` override; bound elapsed values (`-le N`), never pin them |
| R16 | Phase 5's "63 consumers" is a `git grep -l` artifact, inflated ~2.3×: 29 are `scripts/followthroughs/` soak probes whose `*=TRANSIENT(retry)` contract is already correct, and 19 contain no invocation. Real gating surface ~24. Separately, the wider sweep (`betterstackdata.com`, `BETTERSTACK_LOGS_TOKEN`, `uptime.betterstack.com`) finds **52 more files** — the direct-POST emitters that swallowed the 402 | **Re-scope.** Exclude `scripts/followthroughs/` by rule with one sentence of justification; classify the ~24 gating consumers; route the named ones; follow-up for the rest. Rewrite AC3 accordingly |
| R17 | Phase 5's taxonomy is wrong on one half: "presence-assert = fail-closed, safe" — a presence-assert that hard-blocks turns a vendor outage into a **fleet-wide release freeze**, and two named targets are release-path gates. It also misses a third class: **state-mutating consumers** that close issues or mark soaks PASS on empty reads | **Re-axis** on *authorized action* (gates a deploy > closes a standing signal > advisory). Triage state-mutating consumers **first** — a two-day dark window may already have auto-closed live issues and PASSed soaks on empty evidence. That is a retrospective question this plan does not ask |
| R18 | The **3 GB/month allowance is an unverified inherited premise** from a 2-month-old postmortem; every quantitative conclusion rests on it and all three usage APIs 404 | **Record as a named constant with a provenance comment** stating it is unverifiable by API, so one edit re-tunes everything. Consider self-calibrating: an observed 402 *measures* that the effective allowance ≤ cumulative bytes since the last reset |
| R19 | Guard 2 compares a **daily** measurement against a **monthly** budget over a 3-day-retention warehouse; the ×30 extrapolation is nowhere stated | **Denominate in bytes/day**, derived from the monthly allowance with the ÷30.44 shown inline |
| R20 | AC7 says "All **four** Guard 2 mutation rows"; the matrix has **seven** | **Fix the count.** Two rows were unasserted and would have been quietly dropped |
| R21 | ACs that are phase-output audits, not post-conditions: AC1 (self-certifying "or carries a note"), AC3, AC6c ("the experiment is run and recorded"), AC19 ("the PR body reframes"). ACs 20-23 depend on a vendor payment and another workflow's schedule — `cq-ac-must-not-depend-on-concurrent-sessions` | **Rewrite or delete.** Move AC20-23 into the soak follow-through's exit contract, which already states them |
| R22 | `evidence-snapshot.md` duplicates plan tables B/C/F/G/L, and the Risks table already says "the tables in this plan are the historical record" — while the repo is **PUBLIC**, making any verbatim dump a permanent egress | **Cut the separate file.** Keep the plan tables as the record; if any dump is kept, counts/byte-totals/hashed shapes only, never a verbatim log line, with an AC |
| R23 | `scripts/followthroughs/betterstack-quota-verdict-5105.sh` is named in-scope for re-denomination but is **dormant** — hardcoded `ISSUE=5110`, which its own header says is CLOSED/NOT_PLANNED and the sweeper skips. It is also missing from Files to Edit | **Cut the re-denomination** as waste, or revive the probe deliberately. Do not schedule work against a script that never runs |
| R24 | Fail-open default at `zot-restart-loop-alarm.sh:128` — `${NIC_VERDICT:-TRANSIENT}` defaults an *unset* verdict to non-alarming, outside every emptiness test | **Default to an alarming sentinel**, and add a mutation row for "change a `:-` default from alarming to non-alarming" |
| R25 | Phase 3's new `rc=$?` captures risk the AP-022 pattern (a `run:` block dying at the command and silently skipping the `$GITHUB_OUTPUT` write) | **Note in Phase 3**: `set +e` / `|| rc=$?`. Gate the new filing step on `== 'INGEST_DARK'` (equality against a non-empty literal), never `!=` — an unset output satisfies an inequality and files a spurious issue on the alarm's own crash |
| R26 | No **lifecycle spec** for the new issue — filing and dedupe are specified, closing is not | **State the close condition**: ingest 2xx on N consecutive runs, own-title search, never a union search |
| R27 | Missing scenarios: T9 (402 + empty window **and** empty lookback — the state production is in today), T10 (`max(dt)` not advancing — detects the outage with no probe at all), T11 (control returns only the probe's marker), T12 (both arms in one run), T13 (`betterstack-query.sh` exit 3 vs 6 vs 22), T14 (**HTTP 200 with a mid-stream `DB::Exception`** — the real transport gap, guarded today by the parseability check Phase 1.1 extracts, with nothing asserting the protection came with it), T15/T16 (the `reduce` fix itself, plus the inverse must-PASS that a structured `level=50` line still ships) | **Add all.** T5's expected value ("see the CTO advisory") must also become concrete — the right form is a consistency assertion that T5's verdict *equals* T2's for the same reader state |
| R28 | Guard suites need the `fail()`-increments-`PASS` accounting control (precedent: `lint-guard-contract.test.sh` TS-21) and registration via `scripts/lint-orphan-test-suites.sh` | **Add both**; the accounting control is what catches "0 passed, 0 failed, exit 0" |
| R29 | Scope: the plan mixes a CI-side shell/workflow half (testable today against a dark prod) with an infra-apply half gated on `admin_ips` drift and a delivery path that has failed before | **Consider splitting at that seam.** The detector is the stated primary deliverable and should not wait on an apply that can bounce on IP drift |
| R30 | Postmortem directory mixes dated and undated filenames | **Pick one convention** |

Security-sentinel had not reported when this section was written; its findings should be folded in
at `/work` Phase 0 rather than assumed absent.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Filled above.
- **The positive control this diagnosis rests on expires ~2026-08-17 19:07Z.** After that every
  query returns zero and "channel dark", "query broken", and "producers quiet" become
  indistinguishable from the warehouse alone — which is the precise ambiguity the ingest probe
  exists to break. An implementer who re-measures after that time and finds nothing has not
  contradicted this plan.
- **An empty warehouse query is not evidence of absence.** It has three causes. This entire plan
  exists because one detector conflated two of them and a second detector had no way to see the
  third.
- **Do not read the workflow's `completed/success` as the alarm being healthy.** It reported
  success every 30 minutes for two days while the thing it watches was completely dark. Green CI on
  a detector says the detector *ran*, never that its subject is well.
- **The issue body's `set -uo pipefail` claim is false, and this plan's first draft repeated it.**
  Measured: bad SQL → 22, unreachable host → 6, empty result → 0, missing creds → 3. `run_sql` is
  the last command, so curl's status propagates. A remedy was drafted for a mechanism that does
  not exist, and it was caught only because the exit codes were actually run. **An inherited
  premise is not a measurement** — even when it arrives inside an unusually well-evidenced issue.
  The real transport gap is different and narrower: ClickHouse can return HTTP 200 with a
  mid-stream `DB::Exception`, which curl reports as success — and
  `scripts/betterstack-assert-absence.sh` already guards it by validating JSONEachRow
  parseability.
- **A write probe can mask the silence it is built to detect.** The alarm's control query is
  unfiltered, so any row the probe writes satisfies it forever. Adding an ingest probe without
  excluding its own marker converts a two-day outage into a permanent blind spot. This is the
  subtlest failure mode in the plan and it is why the probe is demoted to cause-annotation.
- **Two ordinal sweeps disagreed by four.** All-local-refs said ADR-190; a local `ls` said
  ADR-186; only scoping to `refs/remotes/origin` answered the actual question. Local
  `refs/backup/*` refs carry ADRs that are not claims.
- **The registry host's own failure breadcrumbs are unreachable.** Every shipper writes
  `curl -fsS` failures to host journald, and that journald is shipped by the very channel that
  failed. A host-side guard for this class is structurally impossible; it must live on the CI side
  of the ingest boundary.
