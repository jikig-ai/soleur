---
title: "fix(registry): zot's 60s HTTP deadlines cut large-layer blob uploads and blocked a release"
date: 2026-08-13
slug: fix-zot-mirror-large-layer-upload-timeout
branch: feat-one-shot-7341-zot-restart-loop-blocks-release
issue: 7341
refs: [7341, 7456, 7247, 7516]
closes: null
lane: cross-domain
type: bug
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No
> `knowledge-base/project/specs/feat-one-shot-7341-zot-restart-loop-blocks-release/spec.md` exists;
> this plan is the first artifact on the branch.

## Overview

A `Web Platform Release` failed at the release-blocking `zot mirror` step on 2026-08-13. The cause is
**measured and reproduced off-box**: zot v2.1.20 ships `ReadTimeout` and `WriteTimeout` defaults of
exactly 60 s, and a container-image layer that takes longer than 60 s to upload is killed
mid-`PATCH`. The registry host was not restarting, its store was not full, garbage collection was not
stalled, and the Cloudflare tunnel is exonerated.

This plan raises the deadline at its origin, makes the copy-stage failure diagnose itself, keeps the
deciding evidence alive through the burst, and — because the fix rides a `user_data` change on a
cloud-init-only host — **builds the dispatcher that delivers it**, rather than booking an operator
step as automation.

**Issue disposition (decided, per the brief's explicit ask).** This does **not** close #7341, whose
closure is mechanised by `scripts/followthroughs/zot-fill-rate-7341.sh` on a *fill-rate slope* — a
different condition from a timeout that consumes no disk. A distinct issue is filed; the PR body
carries `Closes #<new-issue>` and `Ref #7341`. Two measured facts go back to #7341 as a comment: its
`100% full` premise is stale (`pcent=12`), and its `restarting ~4x/min` clause is refuted for the
current host (`zot_restarts=0` across 48 h).

**Not overclaimed:** #7341's unattributed-growth criterion lists *orphaned `.uploads/` staging* as a
candidate. This plan names that string's mechanism — but zot **succeeds** at cleanup on the measured
path (`removing .uploads/ files` is zot cleaning up). Orphans that survive imply a *different*
disconnect path. No growth claim is made.

---

## Research Insights

### Premise Validation (Phase 0.6)

| Cited | Verified state | Verdict |
|---|---|---|
| #7341 | OPEN, `priority/p1-high`, `type/bug`, `follow-through` | Holds — title premise **stale** |
| #7539 | OPEN — separate tracker | Holds; out of scope |
| #7516 | Open PR — the **inngest host's pull path**. No file collision. But it makes that host a **zot-primary boot-time consumer**, so after it merges the replace window blocks its *bootstrap*, not just pulls | Holds; blast radius updated |
| #7513 / #7435 / #7514 | Merged; fill-rate attribution machinery | **Do not rebuild** |
| #7456 | OPEN — item (c)'s "sustained ordinary-row loss" criterion has now **fired** | Holds |
| upstream zot#4235 | **REFUTED on the current host** — gc completed for both repos at 20:01 and 21:01 | Stale |
| ADR-167 (`write-path-stays-dual-push`) | **Status: Proposed**, CPO-gated at this same threshold. Self-describes as a conditional hold: *"within 14 days of zot reaching a verified restart plateau, the zot-first question is re-opened"* | Holds — **and this plan's measurement supplies that precondition** |
| `scripts/zot-mirror-diagnosis.sh` | A **pure credential-verdict classifier**. `grep -cE 'stage|copy_'` → **0** | Holds — and it is **not** on the copy path (see Reconciliation) |

### Property List (Phase 0.6b)

- **P1** — A release that fails at the zot mirror names the cause that was measured.
- **P2** — The evidence deciding the cause survives the burst that accompanies the failure.
- **P3** — A mirror push of the current image is not killed by a deadline.
- **P4** — The next occurrence self-reports without anyone reading a dashboard.

### Cut List (Phase 0.6b)

| Cut | Property | Authority |
|---|---|---|
| A new restart-loop detector | P4 | `scheduled-zot-restart-loop.yml`. Also moot — the loop is refuted. |
| A new zot log channel | P2 | `SOLEUR_ZOT_LOG` (ADR-184), live at ~18 rows/tick. |
| A new fill-rate probe | — | `zot-fill-rate-7341.sh`. Different property. |
| An SSH/exec lever for zot config | P3 | ADR-096 forbids it. |
| **A discovery probe for the 60 s owner** | P3 | **Cut — the measurement was performed during planning (§2a).** What survives is a *regression* gate, not a discovery probe. |
| **Probe C (bridged)** | P3 | **Cut — no venue.** `tunnel.tf` declares the ingress production-only; there is no local Cloudflare Access ingress, so "bridged" would mean pushing ~700 MB into the **production** store. Moot anyway: §2a reproduced the failure with Cloudflare absent. |
| **A 6-field structured probe event** | — | **Cut — no reader, no sink, no time axis.** The deliverable is a table. |
| **A copy-stage arm inside `zot-mirror-diagnosis.sh`** | P1 | **Cut — the library is not on the copy path.** The live defect is one static line in `degraded()`. |
| **A C1-vs-C2 probe on the dark diagnostic** | P1 | **Cut — both candidates lead to the identical diff.** |
| Shrinking the 703 MB layer *as the remedy* | P3 | **Cut** — the **272 MB** layer failed at the same wall. Time wall, not size wall. (Retained as an interim *mitigation* — see Release-Blocked Window.) |
| A new channel-health ratio probe | P4 | `zot-log-channel-7440.sh` is already enrolled on this channel against #7455. |

### Relevant institutional learnings (paths verified in this worktree)

- `knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`
  — the governing learning. Honoured literally: the discriminator was **run**, not reasoned about.
- `knowledge-base/project/learnings/2026-06-30-recurring-missing-data-signal-can-be-a-query-assumption-bug.md`
- `knowledge-base/project/learnings/2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`
- `knowledge-base/project/learnings/workflow-patterns/2026-07-01-recurring-bug-across-merged-fixes-means-misdiagnosis-make-the-silent-failure-loud-first.md`
- `knowledge-base/project/learnings/best-practices/2026-07-08-disk-full-reads-as-not-full-when-you-check-block-device-not-filesystem.md`
- `knowledge-base/project/learnings/2026-07-08-verify-disk-fullness-write-health-on-deny-all-host-without-ssh.md`

---

## Research Reconciliation — Spec vs. Codebase

| Claim | Measured reality | Response |
|---|---|---|
| "zot restarting ~4x/min" | `zot_restarts=0`; `zot_uptime_s` **85843 → 86143** (exactly the 300 s tick) across the window; no restart in 48 h | **Dropped** |
| #7341: "100% full" | `pcent=12` on 59 GB | **Dropped** |
| zot#4235 gc stall | gc completed for both repos, 20:01 and 21:01 | **Refuted** |
| `.uploads/` as a disk consumer | zot's line is `removing .uploads/ files` — deleted **by** the failing request | Reframed as fingerprint |
| "the diagnostic was dark — check the allowlist" | Channel **live**: 36 `SOLEUR_ZOT_DISK` rows in the window reported empty. **No Vector on this host** — ADR-184 ships by direct POST | **Consumer defect, not channel defect** |
| Draft: "three call sites source the diagnosis helper" | **Six** sourcing sites; and only **three** *invoke* `zot_mirror_diagnosis` — `reusable-release.yml` once, `cf-tunnel-registry-bridge/action.yml` **twice**. `registry-zot-inventory.yml` sources it but calls `zot_mirror_verdict`, never `zot_mirror_diagnosis` | **Corrected** |
| Draft: "the diagnosis library is the copy-stage chokepoint" | **It is not on the copy path at all.** `zot_mirror_diagnosis` is called at `reusable-release.yml:1242`, *inside* `if [[ "${BRIDGE_OUTCOME:-}" == "failure" ]]` (opened 1133, closed 1252). The `for TAG_SPEC` loop is at **1273** — after that `fi`, calling `degraded "$COPY_REASON"` with a locally-built string | **Retargeted** — see Phase 1 |
| Draft: "the retry loop cannot succeed" | A release **succeeded** at 21:54:00Z after an `unexpected EOF` on the same surface | **Corrected** (§2b) |
| Draft: "AC — the next release reaches `mirror_status=ok`" | Base rate ~1-in-13; and merging **fires a release against the un-replaced host** | **Excluded** (§2b, Release-Blocked Window) |
| Draft: "widen `is_cap_exempt()`'s signature" | The classifier **cannot see `statusCode`** — `JQ_TICK` emits 3 tab-separated fields and the in-file invariant says *"zmsg is LAST because it is the only one that can legitimately be empty"* | **Redesigned** — see Phase 2 |
| Registry host is 8 GB (tf comment `cpx22`) | `mem_total_mb=3814`, cap 3072 — a **4 GB** host | Latent risk R4, not conflated |
| `variables.tf` — *"pulls fall through to GHCR meanwhile, non-release-blocking"* | **False since #7071.** GHCR's pull leg is dead (AP-016) | One-line correction in scope |

---

## Measured Diagnosis

Every figure was self-pulled via
`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh`, or reproduced locally
against the pinned digest.

### 1. The failing run

Run `31740550632` is on **`attempt: 2`**.

| Attempt | `release / release` | Outcome |
|---|---|---|
| 1 | 20:23:00Z → 20:41:39Z | failure — **this attempt ran the mirror** |
| 2 | 20:47:36Z → 20:48:28Z (52 s) | failure — too short for three 60 s uploads |

`copy_v` is generated per tag by
`for TAG_SPEC in "v${VERSION}:copy_v" "${COMMIT_SHA}:copy_sha" "latest:copy_latest"`.

### 2. The mechanism, in zot's own words

```
time:2026-08-13T20:33:37.751Z  level:error
message: unexpected error, removing .uploads/ files
error:   read tcp 172.17.0.2:5000->10.0.1.10:52888: i/o timeout
caller:  zotregistry.dev/zot/v2/pkg/api/routes.go:2078
func:    zotregistry.dev/zot/v2/pkg/api.(*RouteHandler).PatchBlobUpload
```
```
method:PATCH  path:/v2/jikig-ai/soleur-web-platform/blobs/uploads/dfb1905f-…
statusCode:500  latency:1m0s  bodySize:0
Content-Length:[703724542]   User-Agent:[crane/0.20.2 go-containerregistry/0.20.2]
```

Three concurrent layers — **703 724 542 B**, **272 236 549 B**, and a third — each at `latency:1m0s`.

### 2a. Who owns the 60 seconds — MEASURED off-box, Cloudflare absent

The deployed zot `config.json` has an `"http"` block with **no timeout key**. Running the pinned
digest locally over a docker bridge, with no tunnel and no Cloudflare edge, zot's boot config reports:

```
"HTTP":{"Address":"0.0.0.0","Port":"5000","ReadTimeout":60000000000,"WriteTimeout":60000000000,…}
```

`60000000000` ns = **60.000 s**, both deadlines, as zot v2.1.20's built-in default. Dribbling a
**4 MB** blob over 100 s reproduced production byte-for-byte — same message, same error shape, same
`routes.go:2078`, same `statusCode:500`, same `latency:1m0s`, with no 703 MB and no network fault.

**zot's `http.Server` read deadline owns the 60 seconds.** The runner's `connection reset by peer` is
the downstream echo.

**A SLOW-file problem, not a LARGE-file problem.** 703 724 542 B ÷ 60 s demands **11.73 MB/s
sustained per layer**; three concurrent layers demand ~280 Mbit/s through one tunnel. This also
**refutes shrink-the-layers as the remedy** from evidence in hand: the 272 MB layer failed at the
same wall, putting effective throughput under ~4.5 MB/s.

### 2b. The failure is INTERMITTENT, and there is a second sub-mode

Run `31746790267`'s release job ran 21:44:36Z → **21:54:00Z and SUCCEEDED**. With the 12 consecutive
successes before the failure, the observed rate is roughly **1 in 13**. During that *successful* run:

```
time:2026-08-13T21:53:09.466Z  level:error
message: unexpected error, removing .uploads/ files
error:   unexpected EOF
```

So `PatchBlobUpload` fails in at least two shapes: **`i/o timeout` at `latency:1m0s`** (the deadline)
and **`unexpected EOF`**. Consequences:

- **The retry loop is not futile and must not be removed.** Retries genuinely clear the *EOF*
  sub-mode. They cannot clear a *deterministic deadline*. Once the deadline is raised the existing
  3×/0 s/5 s/15 s loop becomes correct as written. **Leave it.**
- **Success is not proof of a fix.** At ~1-in-13, *"the next release mirrors successfully"* passes
  ~92% of the time unfixed. Such an AC is **excluded**, notwithstanding a review recommendation to
  promote it — the base rate was measured after that review was dispatched.
- **The three 20:33 errors are concurrent layers, not sequential attempts** — 7 s apart, shorter than
  the loop's own backoff, three distinct UUIDs.

### 3. What is refuted

| Framing | Refuting measurement |
|---|---|
| zot restart loop | `zot_restarts=0`; uptime monotonic; none in 48 h |
| 100% full | `pcent=12`, `resize_ok=true` |
| zot#4235 gc stall | gc completed for both repos |
| credential expiry | token verdict `live` |
| OOM | `zot_anon_mb=46` vs cap 3072; `zot_oom_kills=0` |
| **the Cloudflare tunnel** | **reproduced with Cloudflare absent (§2a)** |
| **layer size as the remedy** | **the 272 MB layer failed at the same wall** |

### 4. Two diagnostic defects, on two different arms — stated separately

An earlier draft ran these together. They are **not** the same defect, and the distinction is
load-bearing:

**(a) The copy arm emits no diagnosis at all.** `RESTART_SUMMARY` and `DIAG` are assembled *inside*
the bridge-failure branch. A `copy_v` failure calls `degraded "$COPY_REASON" …` with a locally-built
string and never reaches them. What it *does* inherit is one unconditional line inside `degraded()`
— `Registry-host health (disk AND zot_restarts/exit_code, which is what an origin flap shows up in):
see SOLEUR_ZOT_DISK / Better Stack registry_disk_prd.` — appended to **every** stage's output. That
single line is the entire mechanism by which a copy-stage failure pointed the reader at refuted host
telemetry. **This is the P1 defect and it is what Phase 1 fixes.**

**(b) The bridge arm's `SOLEUR_ZOT_DISK` read reported zero rows where 36 exist.** Candidate causes:
a missing `doppler run` wrapper, and `betterstack-query.sh` running `set -uo pipefail` **without
`-e`** so an internal failure exits 0 with an error payload. **Both lead to the identical diff**, so
no probe is built to choose between them.

> **Honesty note.** This plan did **not** establish which attempt's log carried the no-samples text.
> That text lives only in the bridge branch, so it most plausibly came from attempt 2 — meaning (b)
> is a **real but separate** defect on an arm the measured copy failure never entered. It is kept in
> scope because the fix is three lines and the two arms share a file, **not** because the measurement
> implicates it. AC coverage keeps them separately falsifiable so a green run cannot be read as
> evidence for the other.

**The deciding evidence survived by luck.** In the failure's tick the shipper emitted
`SOLEUR_ZOT_LOG_DROPPED n=124 … cum=5743 reason=rate_cap` against a baseline of `n=8`. Cumulatively
at 21:40Z: **`dropped_cum=5841` vs `shipped_cum=5151`.** The `PatchBlobUpload` rows survived only
because that class is cap-exempt; the paired HTTP-API rows carrying `Content-Length` and
`latency:1m0s` are **ordinary rows**. This is #7456 item (c)'s criterion, **fired on measurement**.

---

## Hypotheses

Triggered by `plan-network-outage-checklist.md` (`connection reset`, `timeout`). L3 → L7 per
`hr-ssh-diagnosis-verify-firewall`. Every layer is closed by an artifact.

1. **L3 — firewall.** *Opt-out with artifact:* zot logged the request, authenticated it, issued an
   upload UUID and served it 60 s. A firewall that dropped this cannot produce a server-side
   `PatchBlobUpload` row. **[verified]**
2. **L3 — DNS / routing.** Same artifact, plus `10.0.1.x` pulls returning `200` every ~15 s
   throughout. **[verified]**
3. **L7 — Cloudflare tunnel.** **REFUTED** — reproduced on a local docker bridge with Cloudflare
   absent (§2a). This retires a standing misattribution and supplies ADR-167's re-open precondition.
4. **L7 — zot's read deadline.** **CONFIRMED** — zot's own boot config reports
   `ReadTimeout: 60000000000` / `WriteTimeout: 60000000000` ns.
5. **L7 — payload size.** Not competing, and refuted as a remedy: the 272 MB layer failed identically.

**Open and explicitly not claimed:** the `unexpected EOF` sub-mode has **no** established owner. This
plan does not fix it and does not assert the deadline change will.

---

## User-Brand Impact

- **If this lands broken, the user experiences:** a deploy path that intermittently refuses to
  deliver — and in the Arm C failure mode below, one that *reports success while delivering nothing*.
  The 2026-08-03 post-mortem records this shape costing ~18 h.
- **If this leaks, the user's workflow is exposed via:** `SOLEUR_ZOT_LOG` carries zot's HTTP logs.
  `Authorization` is `[REDACTED]` at source; client addresses are RFC1918. Phase 2 widens *which*
  rows ship, never *what* they contain.
- **Brand-survival threshold:** `single-user incident`.

---

## Release-Blocked Window — the interim posture, stated explicitly

**There is no interim unblock path, and that is a finding rather than an omission.**
`allow_unmirrored_reason` exists (`reusable-release.yml:42`) and is **not** the answer — the workflow
says so itself: *"An override buys NOTHING when the gate is right: an image that is not in zot cannot
be pulled, so overriding just publishes a still-undeployable release."* The GHCR fallback is dead
(`GHCR_READ_TOKEN` revoked, minter `403 DENIED`), so a release absent from zot cannot deploy at all.

Therefore, between merge and the dispatcher firing, releases remain exposed to the ~1-in-13 rate.
Two things bound that window:

- **The dispatcher (Phase 3) is a deliverable of this PR**, so delivery does not wait on anyone
  remembering to fire it.
- **The one client-side mitigation available with no host replace is layer size.** It is refuted as
  a *remedy* (§2a) but it is real as a *probability reduction*: fewer bytes per PATCH means fewer
  uploads reaching 60 s. It is **not** taken in this PR — blast radius on the Dockerfile is wide and
  the deadline fix supersedes it — and it is recorded here so the option is visible rather than
  rediscovered.

---

## Implementation Phases

### Phase 1 — Make the copy arm diagnose itself (no host replace)

1. **Retarget at `degraded()`, not at the diagnosis library.** Make `degraded()`'s trailing telemetry
   pointer branch on `$reason`: `copy_*` and `verify` get the upload-ceiling pointer
   (`PatchBlobUpload` / `latency` / `Content-Length` in `SOLEUR_ZOT_LOG`); `bridge` and
   `crane_install` keep the host-health pointer. **One `case` in one function, on the path that
   actually fires.** No stage parameter is added to `zot_mirror_diagnosis()` — that would be a
   signature change across three callers to reach a function the copy path never calls.
2. **Repair the bridge arm's read** (defect (b)): require all three `BETTERSTACK_QUERY_*` values,
   matching the script's own guard, and treat an error payload as a failed read. Anchor: the comment
   beginning `# BOOT-SCOPED.`
3. **Consistency sweep** across the three `zot_mirror_diagnosis` **invocation** sites — one in
   `reusable-release.yml`, **two** in `.github/actions/cf-tunnel-registry-bridge/action.yml`. That
   directory is invisible to `.github/workflows/`-scoped greps, which is why
   `scripts/lint-diagnosis-claims.sh` exists.
4. Any new causal sentence carries a `# MEASURED-BY:` marker or references a verdict variable, or
   `lint-diagnosis-claims.sh` fails it. Its `.highwater` baseline must not regress.

### Phase 2 — Raise the deadline and keep the paired evidence (ONE host replace)

Both edits touch `apps/web-platform/infra/cloud-init-registry.yml`, which is `user_data` and
`ForceNew`. **They ship in one merge and one replace** — separating them books two fleet-wide pull
outages to buy nothing.

1. **Set BOTH deadlines** in the `"http"` block (anchor `"compat": ["docker2s2"]`):
   `"readTimeout": "1800s"`, `"writeTimeout": "1800s"`.

   **Setting only `readTimeout` is worse than shipping nothing.** Measured against the pinned digest:

   | Arm | config | zot's PATCH row | client got |
   |---|---|---|---|
   | A | default (today's prod) | `500`, `latency:1m0s` | broken pipe at 65.7 s |
   | B | both raised | `202`, `latency:1m38s` | `HTTP/1.1 202 Accepted` |
   | C | `readTimeout` only | `202`, `latency:1m38s` | **empty — connection closed, no response** |

   Arm C is a split-brain: zot logs a **`202` success** while `writeTimeout` (still 60 s, and in Go
   it ticks from header-read, not response-write) kills the response. **Both, or neither.**

2. **`1800s` is bounded above by `gcDelay`, not chosen freely.** The same file sets
   `"gcDelay": "1h"` — *"the dangling-blob SAFETY window that protects a blob just uploaded but not
   yet manifest-referenced during an in-flight push."* **A read deadline longer than `gcDelay` lets
   gc reclaim the staging of an upload still in flight.** 1800 s is 2× margin under it; any future
   increase moves `gcDelay` first. At 1800 s a 703 MB layer needs ~0.39 MB/s.
   Slowloris is not live: `hcloud_firewall.registry` is deny-all on public ingress and the only path
   is CF Access plus htpasswd.

3. **Free latent fix:** the deadlines are server-wide, so today's `writeTimeout: 60s` imposes the
   same ~11.7 MB/s floor on every *pull* response over the tunnel. This clears that too.

4. **Exempt the PAIRED row — narrowly, and via the tick record, not the classifier's signature.**

   **Narrow to the pairing, not to all 5xx.** Exempting every 5xx is a **priority inversion** that
   defeats the very property it is meant to buy. The exempt lane is a single FIFO 17-slot counter
   (`CAP_EXEMPT_PER_INTERVAL`) with no intra-lane priority: once 17 rows are admitted in a tick,
   everything after is dropped regardless of class. The 60 s liveness GET plus
   `web-zot-consumer-probe.timer` alone put ~10 HTTP-API rows in every tick — so if those start
   5xx-ing, probe traffic consumes most of the lane and **crowds out panic traces**. That is exactly
   the #7444 R12 defect (*"a Go panic is 30-60 journald entries against a 17/tick cap"*) reinstated
   one lane down. The predicate is therefore `statusCode` 5xx **AND** `path` matching
   `/blobs/uploads/` — bounded by push concurrency (3 in the measured incident), not fleet volume.

   **The tick record must carry the fields.** `is_cap_exempt()` cannot see `statusCode`:

   ```
   JQ_TICK='(.MESSAGE // "") as $m | [(.__CURSOR // ""), $m, (($m | fromjson? | .message?) // "")] | @tsv'
   while IFS=$'\t' read -r cur msg zmsg; do
   ```

   Three positional tab-separated fields, and the invariant directly above reads *"zmsg is LAST
   because it is the only one that can legitimately be empty."* `statusCode` and `path` are **also**
   legitimately empty (every gc line, every panic trace, every plaintext row), so they must be
   appended **after** `zmsg` and the `read -r` widened **in the same edit**. If `JQ_TICK` gains
   fields and `read -r` does not, bash folds them into `zmsg` — and because every exempt arm is a
   **prefix** match, `is_cap_exempt` keeps returning 0 and the suite stays green over a corrupted
   record. **That fail-open is Guard 2's primary mutation row.**

   Add a sibling predicate at the single call site rather than changing the classifier's contract:

   ```
   if is_cap_exempt "$zmsg" || is_upload_failure_evidence "$zstatus" "$zpath"; then
   ```

   `is_cap_exempt` still keys on the parsed `message` field only, so the documented
   `User-Agent: executing gc` bypass stays closed, and `statusCode`/`path` are server-emitted.
   **Note:** the in-file comment says *"The four measured evidence classes"* while the body carries
   **eight** arms. Count the body.

5. **`user_data` budget.** Measured now: `stored_bytes:13136, cap:32768, headroom:19632`. Phase 2
   grows this file and `infra-validation.yml` hard-fails on the cap (ADR-185). Re-measure before merge.

### Phase 3 — Build the dispatcher that delivers it

`registry-host-replace` is **`workflow_dispatch`-only**
(`if: github.event_name == 'workflow_dispatch' && inputs.apply_target == 'registry-host-replace'`),
and nothing in the repo fires it — every reference is a command printed for a human. A draft of this
plan booked it under *"Post-merge (automated — no human step)"*, which was simply false and trips
`wg-block-pr-ready-on-undeferred-operator-steps` and `hr-never-label-any-step-as-manual-without`.

**Automation is available and is therefore mandatory here** (`hr-exhaust-all-automated-options-before`):
the target carries no `environment:` reviewer gate and no `confirm=` input, and the dispatcher
pattern already exists twice — `.github/workflows/inngest-watchdog-restart-dispatch.yml` and
`.github/workflows/registry-zot-inventory-dispatch.yml`.

Build a dispatch workflow that, on merge of a `cloud-init-registry.yml` change:

1. **Pre-checks pull-path health before firing.** Firing blind is the #6400 hazard recorded at
   `scheduled-zot-restart-loop.yml` — *"in #6400 the GHCR fallback was ALSO degraded, which is what
   turned a registry outage into a total deploy outage."* Reuse `scripts/registry-pull-path-health.sh`.
2. Fires `apply-web-platform-infra.yml` with `apply_target=registry-host-replace` and a `reason`
   naming the merge commit, sourcing the ack token rather than requiring it to be typed.
3. Fails loudly, and files nothing silently, if the pre-check is red.

### Phase 4 — Record and enrol

ADR per `## Architecture Decision`; follow-through per `## Observability`.

---

## Files to Edit

- `.github/workflows/reusable-release.yml` — `degraded()` reason-branching; the `# BOOT-SCOPED.` read guard.
- `.github/actions/cf-tunnel-registry-bridge/action.yml` — **both** `zot_mirror_diagnosis` sites.
- `scripts/zot-mirror-diagnosis.sh` + `scripts/zot-mirror-diagnosis.test.sh` — only if the shared
  message text changes; **no stage parameter**.
- `apps/web-platform/infra/cloud-init-registry.yml` — `"http"` deadlines; `JQ_TICK` + `read -r`
  widening; `is_upload_failure_evidence` predicate.
- `apps/web-platform/infra/zot-log-shipper.test.sh` — mutation rows.
- `scripts/followthroughs/zot-log-channel-7440.sh` + `tests/scripts/test-zot-log-channel-probe.sh` —
  the **shadow reader** counts the four `message:` literals; after Phase 2 the producer exempts more.
  Update, or state in-file why the reader stays four-class.
- `apps/web-platform/infra/variables.tf` — correct the stale *"pulls fall through to GHCR"* comment.

## Files to Create

- `.github/workflows/registry-host-replace-dispatch.yml` — Phase 3.
- `knowledge-base/engineering/architecture/decisions/ADR-189-zot-http-deadlines-sized-to-largest-layer.md`
  (ordinal **provisional**).
- A committed guard running the pinned zot digest against the **rendered** `config.json`.
- `scripts/followthroughs/zot-upload-ceiling-<tracker>.sh`.

---

## Acceptance Criteria

### Pre-merge (PR)

1. For a `copy_*` or `verify` stage failure, `degraded()` emits the upload-ceiling pointer naming
   `PatchBlobUpload`, `latency` and `Content-Length`; assert on those content anchors.
2. For a `bridge` or `crane_install` failure, `degraded()` still emits the host-health pointer —
   the two arms are separately falsifiable, so neither's pass is evidence for the other.
3. With any one of the three `BETTERSTACK_QUERY_*` values absent, the bridge arm reports a **failed
   read**, never a no-samples measurement.
4. The three `zot_mirror_diagnosis` invocation sites are consistent; the set is derived by
   `grep -rn 'zot_mirror_diagnosis' --include=*.yml --include=*.sh`, not from a hand-written list.
5. `bash scripts/zot-mirror-diagnosis.test.sh` passes with its `MIN_ASSERTIONS=50` floor intact —
   the floor must not be lowered (its own comment: *"Fix the dispatch, do not lower the floor"*).
6. `bash apps/web-platform/infra/zot-log-shipper.test.sh` passes with its `>= 150` floor and
   `CANARY_OK` harness canary intact.
7. The rendered-config guard runs the pinned digest against the **rendered** `config.json` (the bytes
   that reach the host, via `registry-userdata-budget.sh`'s render path) and fails on: `readTimeout`
   without `writeTimeout` (Arm C), either below the largest-layer budget, or either ≥ `gcDelay`.
8. The guard's negative control holds: zot rejects an unknown key under `HTTP`
   (`'HTTP' has invalid keys: zzzboguskey`) — without which "the key was accepted" means nothing.
9. A tick whose `JQ_TICK` field count and `read -r` arity disagree drives the shipper suite RED.
10. A tick of 17 ordinary 5xx rows followed by a panic trace still ships the panic trace.
11. Every mutation row in `## Guard Contract` drives its guard RED; every must-PASS row passes.
12. `bash scripts/lint-diagnosis-claims.sh` passes and its `.highwater` baseline has not regressed.
13. `bash apps/web-platform/infra/registry-userdata-budget.sh --json` reports `stored_bytes` under
    `cap` with headroom above the ADR-185 policy floor.
14. `python3 scripts/lint-guard-contract.py <this plan path>` passes — path-scoped, so a concurrently
    merged plan cannot redden it.
15. `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` passes.
16. The dispatcher workflow exists, is `actionlint`-clean, and its pull-path pre-check is exercised
    by a test with a synthesized red reading.
17. No `<tracker>` or `<new-issue>` placeholder remains: `grep -rn '<new-issue>\|<tracker>'` over the
    diff returns nothing.
18. PR body carries `Closes #<new-issue>` and `Ref #7341`, and does **not** carry `Closes #7341`.

### Post-merge (automated by the Phase 3 dispatcher — no human step)

19. The dispatcher fires `registry-host-replace` and its run concludes successfully.
20. zot's boot `configuration settings` line — already carried to the warehouse by the ADR-184
    shipper — reports `ReadTimeout` and `WriteTimeout` of `1800000000000` ns. Queryable from Better
    Stack with no dashboard and no SSH.
21. Over the soak window, `SOLEUR_ZOT_LOG` shows **zero** `PatchBlobUpload` rows carrying
    `i/o timeout` with `latency:1m0s`. *(Scoped to the deadline sub-mode: `unexpected EOF` is out of
    scope per §2b; and a bare "the next release succeeds" criterion passes ~92% of the time unfixed,
    so it is excluded.)*

**Sequencing note.** `web-platform-release.yml` triggers on `push` to `main` with paths including
`apps/web-platform/**`, so **merging this PR fires a release against the still-un-replaced host**.
That run is expected to remain exposed to the ~1-in-13 rate and is explicitly **not** evidence for or
against this change. AC19-21 are graded only after the dispatcher's replace completes.

---

## Infrastructure (IaC)

### Terraform changes

No new resources, providers, variables or secrets. Phase 2 edits
`apps/web-platform/infra/cloud-init-registry.yml`, the `user_data` for `hcloud_server.registry` in
`apps/web-platform/infra/zot-registry.tf`.

### Apply path

**(c) replace**, delivered by the **new Phase 3 dispatcher** calling `apply-web-platform-infra.yml`
with `apply_target=registry-host-replace`. Verified: `zot-registry.tf` resources are
`OPERATOR_APPLIED_EXCLUSIONS` and are **not** in the per-PR `-target=` allow-list, and the per-PR
path bridges to the existing *web* host so it cannot reprovision the registry at all. The one
registry-named address in the per-PR set — `terraform_data.registry_insecure_config` — is the web
host's docker daemon config. **Merging does not replace the registry.**

**Blast radius.** The registry is the fleet's sole image-pull path, so the replace window is a window
in which no host can pull — and **after #7516 merges it also blocks the Inngest host's bootstrap**.
Exactly one replace is booked: Phase 1 carries no cloud-init change; Phase 2's edits are batched.
The volume is preserved; the stock-availability guard gates it; the Phase 3 pre-check refuses to fire
into an already-degraded pull path (#6400).

### Distinctness / drift safeguards

`hcloud_server.registry` is outside the per-PR `-target=` set. The Better Stack heartbeat's `paused`
`lifecycle.ignore_changes` (ADR-117) is untouched.

### Vendor-tier reality check

No new vendor resource; no tier gate applies.

---

## Observability

```yaml
liveness_signal:
  what: SOLEUR_ZOT_LOG envelope rows from host=soleur-registry, plus the SOLEUR_ZOT_DISK heartbeat
  cadence: 5 min (shipper cron 3-59/5; 5-min heartbeat) — measured live during planning
  alert_target: existing soleur-registry-disk-prd absence heartbeat + scheduled-zot-restart-loop.yml
  configured_in: apps/web-platform/infra/cloud-init-registry.yml, apps/web-platform/infra/zot-registry.tf

error_reporting:
  destination: Better Stack Logs source 2457081 by direct POST (ADR-184 — no Vector on this host)
  fail_loud: yes — the mirror step is release-blocking with no continue-on-error

failure_modes:
  - mode: a layer upload exceeds the HTTP read deadline
    detection: SOLEUR_ZOT_LOG row pairing PatchBlobUpload/i-o-timeout with statusCode 5xx and
      latency, emitted FROM the registry host itself
    alert_route: degraded()'s copy-stage pointer, surfaced in the release ::error:: and mirror_reason
  - mode: the applied deadline silently reverts to the 60s default on a replace
    detection: zot's boot `configuration settings` line, shipped by the ADR-184 channel, carrying
      ReadTimeout/WriteTimeout in nanoseconds
    alert_route: the follow-through probe asserts both values
  - mode: the deciding rows are dropped at the shipper's rate cap
    detection: SOLEUR_ZOT_LOG_DROPPED reason=rate_cap / exempt_cap, plus the
      log_shipper_dropped_cum / log_shipper_shipped_cum pair on every heartbeat
    alert_route: the ratio arm folds into scripts/followthroughs/zot-log-channel-7440.sh, which is
      already enrolled on this channel — not a new probe
  - mode: the diagnostic reads green over a broken query
    detection: the Phase 1 split — "read failed" and "read returned nothing" carry distinct reasons
    alert_route: distinguishable in the release job's own annotation

logs:
  where: Better Stack ClickHouse warehouse via scripts/betterstack-query.sh
  retention: hot window ~40 min via remote(); the archive arm (s3Cluster) covers the soak span — any
    query spanning more than the hot window MUST include the archive arm

discoverability_test:
  command: bash scripts/followthroughs/zot-upload-ceiling-<tracker>.sh
  expected_output: "PASS" with a non-zero observed-sample count, both deadlines reading
    1800000000000 ns, and zero PatchBlobUpload i/o-timeout pairings in the window
  credentials_required: "BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} (read-only ClickHouse
    connection) — the property is the absence of a server-side upload failure on a deny-all private
    host, and no unauthenticated probe can observe that host's logs"
```

**Soak follow-through enrolment (Phase 2.9.1).** AC21 is time-gated, so closure is mechanised.

**The tracker MUST NOT be `<new-issue>`.** `scripts/sweep-followthroughs.sh` enumerates
`gh issue list --label follow-through --state open`, and AC18 closes `<new-issue>` at merge — a probe
hosted there is a permanent silent no-op. This repo has already been burned by exactly this and wrote
the warning into `scripts/followthroughs/zot-log-channel-7440.sh`: *"TRACKER: #7455 (dedicated). NOT
#7440 — that issue is closed by the shipping PR."* Phase 4 therefore files a **dedicated, separate**
tracker carrying
`<!-- soleur:followthrough script=scripts/followthroughs/zot-upload-ceiling-<tracker>.sh earliest=<replace+7d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`
plus the `follow-through` label. Those secrets are already wired into
`.github/workflows/scheduled-followthrough-sweeper.yml` by the sibling zot probes — confirm, do not
re-add.

**Exit contract, numeric and explicit** (exit 0 auto-closes the tracker, so this cannot be vague):
`0` PASS — window ≥ 7 d, ≥ 12 heartbeat samples on the newest `boot_id`, both deadlines reading
`1800000000000`, zero `i/o timeout` pairings. `1` FAIL — a pairing observed, or a deadline reading
the 60 s default (a silent revert). `2` TRANSIENT with a distinct `reason=` — replace not yet fired,
sample floor unmet, or any query/auth failure. `${VAR:?msg}` is banned (lint-enforced). Note the
sweeper comments **before** deciding on the open path, so a probe left TRANSIENT comments daily —
which is why the replace is automated in Phase 3 rather than awaited.

---

## Guard Contract

### Guard 1 — a copy-stage failure is diagnosed from upload evidence

**Property.** Every stage in the `copy_*`/`verify` family emits the upload-ceiling pointer, and every
stage in the `bridge`/`crane_install` family emits the host-health pointer — at the one place that
renders it for all stages.

**Assembly.** The chokepoint is `degraded()`'s trailing telemetry pointer in
`.github/workflows/reusable-release.yml`, quantified over **the reason set the `for TAG_SPEC` loop
generates** plus the non-copy reasons — structurally, not as the reason list reads today. This
retargeting is itself a review finding: a draft named `zot-mirror-diagnosis.sh`'s "stage dispatch" as
the chokepoint, and that file contains **no** stage concept (`grep -cE 'stage|copy_'` → 0) and is not
on the copy path at all.

**Mutation matrix.**

| # | Edit | Must drive |
|---|---|---|
| 1 | Make `degraded()` emit the host-health pointer unconditionally again (today's state) | RED |
| 2 | Add a fourth `TAG_SPEC` tag without extending the reason branching | RED |
| 3 | Drop `Content-Length` from the copy-stage pointer while keeping `latency` | RED |
| 4 | Give `bridge` the upload-ceiling pointer — the inverse error, which a copy-only assertion cannot see | RED |
| 5 | **Second member:** fix `copy_v` but leave `copy_sha` on the old pointer | RED |

**Harness row.**

| # | Input | Must drive |
|---|---|---|
| H1 | **Must-PASS non-canonical:** a pointer carrying all three anchors in a different field order | PASS |

*(No own-dispatch row: `scripts/zot-mirror-diagnosis.test.sh` already carries an anti-vacuity
`MIN_ASSERTIONS=50` floor, asserted by AC5. Duplicating it here would be a third encoding.)*

### Guard 2 — the paired upload-failure row survives the cap, and the tick record cannot silently corrupt

**Property.** A `SOLEUR_ZOT_LOG` row that is the HTTP-API half of an upload-failure pairing is never
dropped at the ordinary cap while its `PatchBlobUpload` half is exempt — **and** admitting it never
starves a crash-class row.

**Assembly.** Two coupled chokepoints in `apps/web-platform/infra/cloud-init-registry.yml`, which
must be enumerated together because the failure mode lives in their disagreement: the tick record
contract (`JQ_TICK`'s field list and the `read -r` arity that consumes it positionally) and the
exempt decision at its single call site. The classifier body carries **eight** arms while its comment
says four, so an enumeration copied from the prose is wrong on arrival.

**Mutation matrix.**

| # | Edit | Must drive |
|---|---|---|
| 1 | Widen `JQ_TICK` to emit the new fields but leave `read -r` at three variables | RED — **the fail-open**: fields fold into `zmsg`, prefix matching still returns 0, suite stays green over a corrupted record |
| 2 | Remove `is_upload_failure_evidence` from the call site | RED |
| 3 | Broaden the predicate from the `/blobs/uploads/` pairing to all 5xx | RED — reinstates the #7444 R12 priority inversion |
| 4 | Make the predicate match only `500`, missing `502`/`503`/`504` | RED |
| 5 | Make `is_cap_exempt` match the whole line instead of the parsed `message` field | RED — re-opens the documented `User-Agent: executing gc` bypass |
| 6 | **Second member:** exempt the first pairing in a tick and drop the second | RED |
| 7 | Admit 17 ordinary 5xx rows ahead of a panic trace and drop the panic trace | RED |

**Harness row.**

| # | Input | Must drive |
|---|---|---|
| H1 | **Must-PASS non-canonical:** a synthesized pairing with a different `path` suffix and `goroutine` than the canonical fixture | PASS |

*(No own-dispatch row: `zot-log-shipper.test.sh` already carries a `>= 150` floor fired from an EXIT
trap plus a `CANARY_OK` harness canary, asserted by AC6.)*

### Guard 3 — the deadline config cannot ship in a split-brain, gc-unsafe, or unparseable shape

**Property.** The **rendered** zot `config.json` — the bytes that actually reach the host — always
carries both deadlines, both at or above the largest-layer budget, both strictly below `gcDelay`, and
is accepted by the pinned zot digest.

**Assembly.** The chokepoint is the rendered `config.json` together with the `gcDelay` value in the
same document, evaluated by the pinned digest. Rendering matters: this is a ForceNew replace of the
sole pull path with no SSH, so a config zot rejects is not a plan-time failure — the destroy
succeeds, the create succeeds, and zot fails to start on an unreachable host. Nothing in the repo
validates this today.

**Mutation matrix.**

| # | Edit | Must drive |
|---|---|---|
| 1 | Set `readTimeout`, omit `writeTimeout` (Arm C split-brain) | RED |
| 2 | Set both ≥ `gcDelay` | RED — gc could reclaim in-flight staging |
| 3 | Lower `gcDelay` below the deadlines without touching them | RED — proves the guard reads the *relation*, not a literal |
| 4 | Set both below the largest-layer budget | RED |
| 5 | Introduce a typo'd key (`readTimeOut`) that the pinned digest rejects | RED — the negative control, without which acceptance means nothing |
| 6 | **Own-dispatch:** point the guard at a render with no `"http"` block | RED — must fail, not vacuously pass |

**Harness row.**

| # | Input | Must drive |
|---|---|---|
| H1 | **Must-PASS non-canonical:** both deadlines at a value other than `1800s` still satisfying every relation | PASS — the guard enforces the invariant, not the literal |

All fixtures are synthesized against shapes measured in this plan (`cq-test-fixtures-synthesized-only`).

---

## Architecture Decision (ADR/C4)

### ADR

**ADR-189 — zot HTTP deadlines are sized to the largest layer, not left at the 60 s default**
(ordinal **provisional**).

A review position argued for deleting this ADR as "a value, not a road-choice", partly because its
shape depended on an unperformed measurement. That premise is now false (§2a), and what the record
captures is not the number:

- **The CF tunnel is exonerated for a class of failure it has been carrying blame for** — a
  correction to the shared model that feeds ADR-167's pending re-open.
- **A cross-subsystem coupling invisible at both call sites:** the HTTP deadline is bounded above by
  `gcDelay`. Raising either without reading the other reintroduces in-flight staging reclamation.
- **The Arm C split-brain:** the two keys move together, and the failure mode of moving one is
  *silent success*.

It cites ADR-166 for the message-honesty half rather than restating it. The number lives in
`cloud-init-registry.yml` next to the setting in the `#7282` house style — stating what was measured,
and carrying *re-measure on every zot bump, never re-word*. Guard 3 is what actually fails when
someone violates the invariant.

**Ordinal hygiene.** `origin/main` tops out at ADR-186; 187 and 188 exist only on unmerged branches,
and **ADR-187 is double-claimed under two different titles on two branches** (as is ADR-167). So
re-verification alone cannot reserve: if either ADR-187 claimant renumbers upward it lands on 188 and
pushes the next onto 189. This plan therefore **pushes an ADR-189 stub early to claim the ordinal**,
and on collision the later-pushed branch renumbers. Any renumber sweeps this plan, `tasks.md`, and
every AC naming it.

**Sequencing with ADR-167.** ADR-167 is CPO-gated at this same threshold, over this same subsystem,
and this plan's restart-plateau measurement fires its re-open trigger. Phase 4 states that
relationship explicitly so the finding is not stranded; it does not decide ADR-167.

### C4 views

The decision changes no element and no relationship — it changes a **property** of an existing edge.
Confirmed against all three model files —
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — read in full rather
than grepped for `zot`, against this enumeration:

- **External human actors:** none added; machine-to-machine.
- **External systems / vendors:** Cloudflare (tunnel/Access) on the write path and Better Stack as
  the `SOLEUR_ZOT_LOG` sink — both already modelled.
- **Containers / data stores:** the zot container and its `/var/lib/zot` volume — already modelled.
- **Access relationships:** unchanged. No actor gains or loses a path. The Phase 3 dispatcher is a
  workflow, not a C4 element.

**No C4 edit is in scope.** If implementation surfaces a missing element against that enumeration it
is added with its `#external` tag, its edges, **and** the `views.c4` `include` line, followed by
`apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.

---

## Open Code-Review Overlap

`gh issue list --label code-review --state open --limit 200` returned **63** open issues; none
contains any path in `## Files to Edit` or `## Files to Create`. **None.**

---

## Domain Review

**Domains relevant:** Engineering.

### Engineering

**Status:** reviewed
**Assessment:** Routed to `cto` with a brief enumerating, for each non-preferred option, the fact that
would disqualify it — including the `#7282` precedent that a zot config key must be measured against
the pinned image, never read off upstream docs. The leader **ran the probe** rather than reasoning
from docs: it closed hypotheses 3 and 4, produced the Arm A/B/C table, found the `gcDelay` upper
bound and the Arm C split-brain, and declined to invent a disqualifying fact for the one option it
could not measure. Its scope guidance (do not close #7341; do not overclaim `.uploads/`) is adopted
verbatim.

**Escalated 5-agent panel** (per the `single-user incident` threshold) returned four verified
blockers now folded in: the diagnosis library is not on the copy path; the consumer enumeration was
wrong; `registry-host-replace` has no automation; and the 5xx exemption was a priority inversion.

**Product/UX Gate:** not applicable. The independent mechanical UI-surface scan over `## Files to
Edit` and `## Files to Create` matches no path under `components/**/*.tsx`, `app/**/page.tsx` or
`app/**/layout.tsx`. Product tier **NONE**.

**Operations / Legal / Finance / Marketing / Sales / Support:** not relevant — internal
infrastructure, no user-facing surface, no regulated data, no new vendor, no recurring expense change.

---

## GDPR / Compliance

Skipped — the canonical regulated-data regex matches no file in scope and none of the four expansion
triggers fire. Phase 2 widens *which* rows ship, not *what* they contain; `Authorization` is already
`[REDACTED]` at source and client addresses are RFC1918.

## Encryption Posture

Skipped — no persistent store and no cross-component connection is introduced. `/var/lib/zot` is
already a LUKS-backed volume; the Better Stack POST path and the Cloudflare tunnel both pre-exist.

---

## Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Arm C split-brain** — `readTimeout` without `writeTimeout` turns a loud 500 into a silent success | Guard 3 row 1 fails CI on exactly this shape |
| R2 | A deadline ≥ `gcDelay` lets gc reclaim in-flight staging | 2× margin; Guard 3 rows 2-3 enforce the *relation*, not a literal |
| R3 | **The replace darkens the fleet's only pull path** (and, post-#7516, the Inngest bootstrap) | Bounded, not merely acknowledged: exactly one replace (Phase 2 batched), the Phase 3 pre-check refuses to fire into an already-degraded pull path (#6400), volume preserved, stock guard gates it |
| R4 | **Latent:** the host is 4 GB / cap 3072 — the size whose boot scan of a 35 GB store caused the #6288 OOM loop. Store is ~7 GB today | Recorded, not folded in. Live only if #7341's fill-rate probe shows the store climbing back |
| R5 | The `unexpected EOF` sub-mode is untouched | Explicitly out of scope and not claimed (§2b); AC21 is scoped to the deadline sub-mode so a pass cannot be misread as covering EOF |
| R6 | **The tick-record fail-open** — `JQ_TICK`/`read -r` disagreement corrupts records while the suite stays green | Guard 2 row 1, the matrix's primary row |
| R7 | **Exempt-lane starvation** crowds out panic traces | Predicate narrowed to the `/blobs/uploads/` pairing (bounded by push concurrency); Guard 2 rows 3 and 7 |
| R8 | Raising server-wide deadlines weakens a slowloris defence | Not live: deny-all public ingress; only path is CF Access plus htpasswd |
| R9 | ADR ordinal collision — 187 is already double-claimed on two branches | Stub pushed early to claim 189; later-pushed branch renumbers; renumber sweeps plan + tasks + ACs |
| R10 | `user_data` ForceNew budget | Measured `headroom:19632`; AC13 re-measures before merge |
| R11 | Merging fires a release against the un-replaced host | Stated in the Sequencing note; that run is explicitly not evidence either way |

---

## Non-Goals

- Closing #7341 or altering `zot-fill-rate-7341.sh`.
- #7539 — out of scope.
- The `unexpected EOF` sub-mode — no established owner; not claimed.
- Rebuilding fill-rate attribution from #7513 / #7435 / #7514.
- Removing or restructuring the 3× mirror retry loop — it becomes correct once the deadline is raised.
- Shrinking image layers — refuted as a *remedy*; recorded as an unused interim mitigation.
- Any write-path topology change — the cause is inside zot, so a direct path hits the identical wall.
  ADR-167 is untouched and gains a retired premise.
- Deciding ADR-167's re-open.
- Changing the registry host's server type (R4 — observation only).

---

## Test Scenarios

Framework is the repo's existing `*.test.sh` convention. `bash <file>` is the correct invocation
(matching `scripts/test-all.sh` and `infra-validation.yml`). The Guard Contract matrices are the test
list for the guards and are not restated.

| # | Scenario | Shape |
|---|---|---|
| T1 | `degraded()` on `copy_v` against a synthesized `PatchBlobUpload` + `statusCode:500 latency:1m0s` pair | emits `PatchBlobUpload`, `latency`, `Content-Length` |
| T2 | `degraded()` on `bridge` | still emits the host-health pointer |
| T3 | Bridge read with one of three `BETTERSTACK_QUERY_*` absent | reports a **failed read**, never a no-samples measurement |
| T4 | Rendered-config guard: Arms A/B/C plus the typo'd-key negative control | reproduces the Phase 2 table; unknown key rejected |
| T5 | Shipper over a synthesized burst: two pairings, 200 ordinary rows, one panic trace | pairings and panic exempt; ordinary capped |
| T6 | `JQ_TICK`/`read -r` arity mismatch | suite RED, not green-over-corrupt |
| T7 | Dispatcher pre-check against a synthesized red pull-path reading | refuses to fire, fails loudly |
| T8 | Follow-through probe: clean window / pairing present / boot line at the 60 s default | PASS(0) / FAIL(1) / FAIL(1) respectively |
| T9 | Follow-through probe before the replace has fired | TRANSIENT(2) with a distinct `reason=` |

---

## Sharp Edges

- **Set both deadlines or neither.** `readTimeout` alone yields a zot-side `202` while the client gets
  nothing — a green server log over a failed push, strictly worse than today's honest 500.
- **The HTTP deadline is coupled to `gcDelay` across subsystems.** `gcDelay` moves first, always.
- **`scripts/zot-mirror-diagnosis.sh` is not on the copy path.** It is a credential-verdict library
  reached only inside the bridge-failure branch. The copy loop calls `degraded "$COPY_REASON"` after
  that branch closes. Do not add a stage parameter to reach a function the copy path never calls.
- **Enumerate the diagnosis consumers structurally.** A `.github/workflows/`-scoped grep returns
  three; two of the three *invocations* live in `.github/actions/`, which is exactly why
  `lint-diagnosis-claims.sh` exists.
- **The follow-through tracker must not be the issue the PR closes.** The sweeper lists `--state
  open`; a probe on a closed issue is a permanent silent no-op.
- **`registry-host-replace` has no automation until this PR builds it.** Do not write "fired by the
  workflow" about a `workflow_dispatch`-only target — `lint-infra-no-human-steps.py` will not catch
  it, because that phrasing carries no actor token. It passes the lint by asserting a falsehood.
- The ADR ordinal is **provisional**; 187 is already double-claimed. Push the stub early.
- Any Better Stack query spanning more than the ~40-minute hot window MUST include the archive arm.
